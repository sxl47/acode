import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';
import '../models/session.dart';
import '../models/server_config.dart';
import '../services/session_manager.dart';
import '../services/terminal_service.dart';
import '../providers/ssh_provider.dart';
import '../providers/session_provider.dart';
import '../providers/settings_provider.dart';

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
  final Terminal _terminal = Terminal(maxLines: 10000);
  TerminalService? _terminalService;
  bool _connected = false;
  String _connectionStatus = 'Connecting...';
  bool _isConnecting = false;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;

  static const _darkTheme = TerminalTheme(
    cursor: Color(0xFFAEAFAD),
    selection: Color(0xFFAEAFAD),
    foreground: Color(0xFFCCCCCC),
    background: Color(0xFF0D1117),
    black: Color(0xFF000000),
    red: Color(0xFFCD3131),
    green: Color(0xFF0DBC79),
    yellow: Color(0xFFE5E510),
    blue: Color(0xFF2472C8),
    magenta: Color(0xFFBC3FBC),
    cyan: Color(0xFF11A8CD),
    white: Color(0xFFE5E5E5),
    brightBlack: Color(0xFF666666),
    brightRed: Color(0xFFF14C4C),
    brightGreen: Color(0xFF23D18B),
    brightYellow: Color(0xFFF5F543),
    brightBlue: Color(0xFF3B8EEA),
    brightMagenta: Color(0xFFD670D6),
    brightCyan: Color(0xFF29B8DB),
    brightWhite: Color(0xFFFFFFFF),
    searchHitBackground: Color(0xFFFFFF2B),
    searchHitBackgroundCurrent: Color(0xFF31FF26),
    searchHitForeground: Color(0xFF000000),
  );

  static const _lightTheme = TerminalTheme(
    cursor: Color(0xFF4D4D4D),
    selection: Color(0xFFBDBDBD),
    foreground: Color(0xFF333333),
    background: Color(0xFFFFFFFF),
    black: Color(0xFF000000),
    red: Color(0xFFCD3131),
    green: Color(0xFF0DBC79),
    yellow: Color(0xFFE5E510),
    blue: Color(0xFF2472C8),
    magenta: Color(0xFFBC3FBC),
    cyan: Color(0xFF11A8CD),
    white: Color(0xFFE5E5E5),
    brightBlack: Color(0xFF666666),
    brightRed: Color(0xFFF14C4C),
    brightGreen: Color(0xFF23D18B),
    brightYellow: Color(0xFFF5F543),
    brightBlue: Color(0xFF3B8EEA),
    brightMagenta: Color(0xFFD670D6),
    brightCyan: Color(0xFF29B8DB),
    brightWhite: Color(0xFFFFFFFF),
    searchHitBackground: Color(0xFFFFFF2B),
    searchHitBackgroundCurrent: Color(0xFF31FF26),
    searchHitForeground: Color(0xFF000000),
  );

  TerminalTheme get _terminalTheme {
    final themeMode = ref.watch(themeModeProvider);
    return themeMode == ThemeMode.dark ? _darkTheme : _lightTheme;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _connect();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _terminalService?.dispose();
    _terminalService = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reconnectIfNeeded();
    }
  }

  void _setupTerminalService(SshConnection conn) {
    _terminalService?.dispose();
    _terminalService = TerminalService(conn.service);
    _terminalService!.bindTerminal(_terminal);
    _terminalService!.setOnDisconnect(_onSessionDisconnect);
  }

  void _onSessionDisconnect() {
    if (!mounted) return;
    _reconnectAttempts++;
    if (_reconnectAttempts <= _maxReconnectAttempts) {
      final delay = Duration(seconds: (_reconnectAttempts * 2).clamp(2, 30));
      Future.delayed(delay, () {
        if (mounted) _connect();
      });
    } else {
      setState(() => _connectionStatus = 'Disconnected. Tap Retry to reconnect.');
    }
  }

  Future<void> _connect() async {
    if (_isConnecting) return;
    _isConnecting = true;

    setState(() => _connectionStatus = 'Connecting to server...');

    try {
      final notifier = ref.read(sshConnectionProvider(widget.server.id).notifier);
      final connState = ref.read(sshConnectionProvider(widget.server.id));
      final existingConn = connState.valueOrNull;

      // Only reconnect if there's no active connection
      if (existingConn == null || !existingConn.connected) {
        if (existingConn != null) {
          await notifier.disconnect();
        }
        await notifier.connect(widget.server);
      }

      var conn = ref.read(sshConnectionProvider(widget.server.id)).valueOrNull;
      if (conn == null) throw StateError('Failed to connect');

      setState(() => _connectionStatus = 'Attaching to session...');

      _setupTerminalService(conn);

      try {
        await _terminalService!.attachToSession(
          widget.session.tmuxSessionName,
          startCommand: _getStartCommand(),
          workingDir: widget.session.workingDir,
        );
      } catch (e) {
        // Transport may have died — force reconnect and retry once
        if (e.toString().contains('Transport') || e.toString().contains('closed')) {
          await notifier.disconnect();
          await notifier.connect(widget.server);
          conn = ref.read(sshConnectionProvider(widget.server.id)).valueOrNull;
          if (conn == null) throw StateError('Failed to reconnect');
          _setupTerminalService(conn);
          await _terminalService!.attachToSession(
            widget.session.tmuxSessionName,
            startCommand: _getStartCommand(),
            workingDir: widget.session.workingDir,
          );
        } else {
          rethrow;
        }
      }

      _reconnectAttempts = 0;
      setState(() {
        _connected = true;
        _connectionStatus = 'Connected';
      });
    } catch (e) {
      setState(() => _connectionStatus = 'Error: $e');
    } finally {
      _isConnecting = false;
    }
  }

  Future<void> _reconnectIfNeeded() async {
    if (_terminalService == null || !_terminalService!.isActive) {
      await _connect();
    }
  }

  String? _getStartCommand() {
    final connState = ref.read(sshConnectionProvider(widget.server.id));
    final conn = connState.valueOrNull;
    if (conn == null) return null;
    final adapter = SessionManager.getAdapter(widget.session.cliToolId);
    return adapter.getStartCommand(workingDir: widget.session.workingDir);
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
            icon: const Icon(Icons.copy),
            tooltip: 'Copy output',
            onPressed: _copyOutput,
          ),
          PopupMenuButton(
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'reconnect',
                child: Text('Reconnect'),
              ),
              const PopupMenuItem(
                value: 'kill',
                child:
                    Text('Kill Session', style: TextStyle(color: Colors.red)),
              ),
            ],
            onSelected: (value) {
              if (value == 'reconnect') _connect();
              if (value == 'kill') _killSession();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Terminal output area - full screen
          Expanded(child: _buildTerminalOutput()),
        ],
      ),
      floatingActionButton: FloatingActionButton.small(
        onPressed: () => _terminal.keyInput(TerminalKey.enter),
        child: const Icon(Icons.keyboard_return),
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
            if (_connectionStatus.startsWith('Error') ||
                _reconnectAttempts > _maxReconnectAttempts)
              FilledButton(
                onPressed: () {
                  _reconnectAttempts = 0;
                  _connect();
                },
                child: const Text('Retry'),
              ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate terminal dimensions based on available space and font size
        const fontSize = 14.0;
        const lineHeight = fontSize * 1.2;
        final cols = (constraints.maxWidth / (fontSize * 0.6)).floor();
        final rows = (constraints.maxHeight / lineHeight).floor();

        // Resize terminal to match available space
        if (cols > 0 && rows > 0 &&
            (cols != _terminal.viewWidth || rows != _terminal.viewHeight)) {
          _terminal.resize(cols, rows);
          _terminalService?.resize(cols, rows);
        }

        return Container(
        color: _terminalTheme.background,
        child: GestureDetector(
          onTap: () => _terminal.viewHeight,
          child: TerminalView(
            _terminal,
            theme: _terminalTheme,
            textStyle: TerminalStyle(
              fontSize: fontSize,
              fontFamily: 'monospace',
            ),
            autofocus: true,
            deleteDetection: true,
            keyboardType: TextInputType.text,
            keyboardAppearance: Brightness.light,
            backgroundOpacity: 1.0,
            simulateScroll: false,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.enter) {
                _terminal.keyInput(TerminalKey.enter);
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
          ),
        ),
      );
      },
    );
  }

  void _copyOutput() {
    final text = _terminal.buffer.getText();
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard')),
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
      await _terminalService?.detach();
      await ref
          .read(serverSessionsProvider(widget.server.id).notifier)
          .deleteSession(widget.session.id);
      if (mounted) Navigator.pop(context);
    }
  }
}
