import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../models/session.dart';
import '../models/server_config.dart';
import '../models/chat_message.dart';
import '../services/session_manager.dart';
import '../services/terminal_service.dart';
import '../providers/ssh_provider.dart';
import '../providers/session_provider.dart';

class SessionScreen extends ConsumerStatefulWidget {
  final Session session;
  final ServerConfig server;

  const SessionScreen({
    super.key,
    required this.session,
    required this.server,
  });

  @override
  ConsumerState<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends ConsumerState<SessionScreen>
    with WidgetsBindingObserver {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _uuid = const Uuid();
  final List<XFile> _pendingImages = [];
  final List<String> _terminalLines = [];
  TerminalService? _terminal;
  StreamSubscription? _outputSub;
  bool _sending = false;
  bool _connected = false;
  String _connectionStatus = 'Connecting...';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _connect();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _outputSub?.cancel();
    _terminal?.dispose();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reconnectIfNeeded();
    }
  }

  Future<void> _connect() async {
    setState(() => _connectionStatus = 'Connecting to server...');

    try {
      // Get or create SSH connection
      var connState = ref.read(sshConnectionProvider(widget.server.id));
      if (connState.valueOrNull == null ||
          !connState.valueOrNull!.connected) {
        await ref
            .read(sshConnectionProvider(widget.server.id).notifier)
            .connect(widget.server);
      }

      connState = ref.read(sshConnectionProvider(widget.server.id));
      final conn = connState.valueOrNull;
      if (conn == null) throw StateError('Failed to connect');

      setState(() => _connectionStatus = 'Attaching to session...');

      // Create terminal service and attach to tmux session
      _terminal = TerminalService(conn.service);
      _outputSub = _terminal!.output.listen((data) {
        if (mounted) {
          setState(() {
            // Parse terminal output into lines, handling ANSI codes
            final cleaned = _cleanAnsi(data);
            final newLines = cleaned.split('\n');
            _terminalLines.addAll(newLines);
            // Keep buffer manageable
            while (_terminalLines.length > 3000) {
              _terminalLines.removeAt(0);
            }
          });
          _scrollToBottom();
        }
      });

      await _terminal!.attachToSession(widget.session.tmuxSessionName);

      setState(() {
        _connected = true;
        _connectionStatus = 'Connected';
      });
    } catch (e) {
      setState(() => _connectionStatus = 'Error: $e');
    }
  }

  Future<void> _reconnectIfNeeded() async {
    if (_terminal == null || !_terminal!.isActive) {
      await _connect();
    }
  }

  String _cleanAnsi(String input) {
    // Remove ANSI escape sequences
    return input
        .replaceAll(RegExp(r'\x1B\[[0-9;]*[a-zA-Z]'), '')
        .replaceAll(RegExp(r'\x1B\][^\x07]*\x07'), '')
        .replaceAll(RegExp(r'\x1B[()][AB012]'), '')
        .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.session.title, style: const TextStyle(fontSize: 16)),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _connected ? Colors.green : Colors.orange,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _connectionStatus,
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.videocam_outlined),
            tooltip: 'Terminal view',
            onPressed: _showTerminalView,
          ),
          PopupMenuButton(
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'reconnect',
                child: Text('Reconnect'),
              ),
              const PopupMenuItem(
                value: 'clear',
                child: Text('Clear Output'),
              ),
              const PopupMenuItem(
                value: 'kill',
                child:
                    Text('Kill Session', style: TextStyle(color: Colors.red)),
              ),
            ],
            onSelected: (value) {
              if (value == 'reconnect') _connect();
              if (value == 'clear') _clearOutput();
              if (value == 'kill') _killSession();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Terminal output area
          Expanded(child: _buildTerminalOutput()),
          // Image preview strip
          if (_pendingImages.isNotEmpty) _buildImageStrip(),
          // Input area
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildTerminalOutput() {
    if (!_connected) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(_connectionStatus),
            const SizedBox(height: 16),
            if (_connectionStatus.startsWith('Error'))
              FilledButton(
                onPressed: _connect,
                child: const Text('Retry'),
              ),
          ],
        ),
      );
    }

    return Container(
      color: const Color(0xFF0D1117),
      child: _terminalLines.isEmpty
          ? const Center(
              child: Text(
                'Waiting for output...',
                style: TextStyle(color: Colors.grey),
              ),
            )
          : ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.all(8),
              itemCount: _terminalLines.length,
              itemBuilder: (ctx, index) {
                final line = _terminalLines[index];
                return SelectableText(
                  line,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: Color(0xFFE6EDF3),
                    height: 1.3,
                  ),
                );
              },
            ),
    );
  }

  Widget _buildImageStrip() {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _pendingImages.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, index) {
          return Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(_pendingImages[index].path),
                  width: 64,
                  height: 64,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                top: 0,
                right: 0,
                child: GestureDetector(
                  onTap: () => setState(() => _pendingImages.removeAt(index)),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(2),
                    child:
                        const Icon(Icons.close, size: 14, color: Colors.white),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              icon: const Icon(Icons.image_outlined),
              onPressed: _connected ? _pickImage : null,
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_command_key),
              tooltip: 'Send Ctrl+C',
              onPressed: _connected ? () => _sendCtrl('c') : null,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: TextField(
                controller: _inputCtrl,
                decoration: InputDecoration(
                  hintText: _connected ? 'Type a message...' : 'Connecting...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                maxLines: 4,
                minLines: 1,
                enabled: _connected,
                textInputAction: TextInputAction.newline,
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              icon: _sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send),
              onPressed: (_sending || !_connected) ? null : _send,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final images = await picker.pickMultiImage();
    if (images.isNotEmpty) {
      setState(() => _pendingImages.addAll(images));
    }
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty && _pendingImages.isEmpty) return;

    setState(() => _sending = true);

    try {
      final connState =
          ref.read(sshConnectionProvider(widget.server.id));
      final conn = connState.valueOrNull;
      if (conn == null || !conn.connected) {
        throw StateError('Not connected to server');
      }

      final manager = SessionManager(conn.service);

      // Upload images if any
      List<String>? remotePaths;
      if (_pendingImages.isNotEmpty) {
        remotePaths = [];
        for (final img in _pendingImages) {
          final path = await manager.uploadImage(File(img.path));
          remotePaths.add(path);
        }
      }

      // Save user message to local history
      final userMsg = ChatMessage(
        id: _uuid.v4(),
        sessionId: widget.session.id,
        role: MessageRole.user,
        content: text,
        imagePaths: remotePaths,
      );
      await ref
          .read(chatMessagesProvider(widget.session.id).notifier)
          .addMessage(userMsg);

      // Send to CLI via tmux
      await manager.sendMessage(widget.session, text,
          imagePaths: remotePaths);

      _inputCtrl.clear();
      setState(() {
        _pendingImages.clear();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendCtrl(String key) async {
    try {
      await _terminal?.sendCtrl(key);
    } catch (_) {}
  }

  void _clearOutput() {
    setState(() => _terminalLines.clear());
  }

  void _showTerminalView() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollCtrl) {
          return Container(
            color: const Color(0xFF0D1117),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Text(
                        'Terminal Output',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.copy, color: Colors.grey),
                        onPressed: () {
                          Clipboard.setData(
                              ClipboardData(text: _terminalLines.join('\n')));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Copied to clipboard')),
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.grey),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _terminalLines.length,
                    itemBuilder: (ctx, index) {
                      return SelectableText(
                        _terminalLines[index],
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: Color(0xFFE6EDF3),
                          height: 1.3,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _killSession() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kill Session'),
        content: const Text(
            'This will terminate the CLI tool on the server. Continue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Kill'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _terminal?.detach();
      await ref
          .read(serverSessionsProvider(widget.server.id).notifier)
          .deleteSession(widget.session.id);
      if (mounted) Navigator.pop(context);
    }
  }
}
