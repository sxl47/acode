import 'dart:io' show Platform;
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

  bool _altActive = false;
  bool _ctrlActive = false;
  late bool _showKeyBar;

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
    _showKeyBar = Platform.isAndroid || Platform.isIOS;
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
    final adapter = SessionManager.getAdapter(
      widget.session.cliToolId,
      command: widget.session.cliToolCommand,
    );
    return adapter.getStartCommand(workingDir: widget.session.workingDir);
  }

  // --- Key sending helpers ---

  void _send(String data) {
    _terminalService?.sendInput(data);
  }

  void _sendEsc() {
    _send('\x1b');
    _clearModifiers();
  }

  void _sendTab() {
    _send('\x09');
    _clearModifiers();
  }

  void _sendBackspace() {
    _send('\x7f');
    _clearModifiers();
  }

  void _sendEnter() {
    _send('\r');
    _clearModifiers();
  }

  void _sendUp() {
    _send('\x1b[A');
    _clearModifiers();
  }

  void _sendDown() {
    _send('\x1b[B');
    _clearModifiers();
  }

  void _sendRight() {
    _send('\x1b[C');
    _clearModifiers();
  }

  void _sendLeft() {
    _send('\x1b[D');
    _clearModifiers();
  }

  void _sendHome() {
    _send('\x1b[H');
    _clearModifiers();
  }

  void _sendEnd() {
    _send('\x1b[F');
    _clearModifiers();
  }

  void _toggleAlt() {
    setState(() {
      _altActive = !_altActive;
      if (_altActive) _ctrlActive = false;
    });
  }

  void _toggleCtrl() {
    setState(() {
      _ctrlActive = !_ctrlActive;
      if (_ctrlActive) _altActive = false;
    });
  }

  void _clearModifiers() {
    if (_altActive || _ctrlActive) {
      setState(() {
        _altActive = false;
        _ctrlActive = false;
      });
    }
  }

  Future<void> _pasteClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      _terminal.paste(data!.text!);
    }
  }

  // --- Gesture handlers ---

  Offset? _swipeStart;

  void _onPanStart(DragStartDetails details) {
    _swipeStart = details.localPosition;
  }

  void _onPanEnd(DragEndDetails details) {
    if (_swipeStart == null) return;
    final velocity = details.velocity.pixelsPerSecond;
    final dx = velocity.dx.abs();
    final dy = velocity.dy.abs();

    // Determine if it's a vertical or horizontal swipe
    if (dy > dx) {
      // Vertical swipe: scroll
      if (velocity.dy < -200) {
        // Swipe up: scroll up (Page Up or mouse wheel up)
        _send('\x1b[5~'); // Page Up
      } else if (velocity.dy > 200) {
        // Swipe down: scroll down (Page Down or mouse wheel down)
        _send('\x1b[6~'); // Page Down
      }
    } else {
      // Horizontal swipe: move cursor
      if (velocity.dx < -200) {
        // Swipe left: cursor left
        _sendLeft();
      } else if (velocity.dx > 200) {
        // Swipe right: cursor right
        _sendRight();
      }
    }
    _swipeStart = null;
  }

  void _switchToAdjacentSession(int delta) {
    final sessionsAsync = ref.read(serverSessionsProvider(widget.server.id));
    final sessions = sessionsAsync.valueOrNull;
    if (sessions == null || sessions.length <= 1) return;
    final currentIndex = sessions.indexWhere((s) => s.id == widget.session.id);
    if (currentIndex < 0) return;
    final nextIndex = (currentIndex + delta).clamp(0, sessions.length - 1);
    if (nextIndex == currentIndex) return;
    _switchToSession(sessions[nextIndex].id);
  }

  Map<ShortcutActivator, VoidCallback> _buildSessionShortcuts() {
    final sessionsAsync = ref.read(serverSessionsProvider(widget.server.id));
    final sessions = sessionsAsync.valueOrNull;
    if (sessions == null || sessions.length <= 1) return {};
    final count = sessions.length.clamp(0, 9);
    final map = <ShortcutActivator, VoidCallback>{};
    final digitKeys = [
      LogicalKeyboardKey.digit1, LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3, LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5, LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7, LogicalKeyboardKey.digit8,
      LogicalKeyboardKey.digit9,
    ];
    for (var i = 0; i < count; i++) {
      map[SingleActivator(digitKeys[i], alt: true)] =
          () => _switchToSession(sessions[i].id);
    }
    map[SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true)] =
        () => _switchToAdjacentSession(-1);
    map[SingleActivator(LogicalKeyboardKey.arrowRight, alt: true)] =
        () => _switchToAdjacentSession(1);
    return map;
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: _buildSessionShortcuts(),
      child: Scaffold(
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
          _buildSessionTabs(),
          PopupMenuButton(
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'copy',
                child: ListTile(leading: Icon(Icons.copy), title: Text('Copy output'), dense: true),
              ),
              const PopupMenuItem(
                value: 'reconnect',
                child: ListTile(leading: Icon(Icons.refresh), title: Text('Reconnect'), dense: true),
              ),
              if (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
                PopupMenuItem(
                  value: 'keys',
                  child: ListTile(
                    leading: Icon(_showKeyBar ? Icons.keyboard_hide : Icons.keyboard),
                    title: Text(_showKeyBar ? 'Hide keys' : 'Show keys'),
                    dense: true,
                  ),
                ),
              const PopupMenuItem(
                value: 'kill',
                child: ListTile(leading: Icon(Icons.stop_circle, color: Colors.red), title: Text('Kill Session', style: TextStyle(color: Colors.red)), dense: true),
              ),
            ],
            onSelected: (value) {
              if (value == 'copy') _copyOutput();
              if (value == 'reconnect') _connect();
              if (value == 'keys') setState(() => _showKeyBar = !_showKeyBar);
              if (value == 'kill') _killSession();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildTerminalOutput()),
          if (_connected && _showKeyBar) _buildKeyBar(),
        ],
      ),
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
        const fontSize = 14.0;
        const lineHeight = fontSize * 1.2;
        final cols = (constraints.maxWidth / (fontSize * 0.6)).floor();
        final rows = (constraints.maxHeight / lineHeight).floor();

        if (cols > 0 && rows > 0 &&
            (cols != _terminal.viewWidth || rows != _terminal.viewHeight)) {
          _terminal.resize(cols, rows);
          _terminalService?.resize(cols, rows);
        }

        return GestureDetector(
          onPanStart: _onPanStart,
          onPanEnd: _onPanEnd,
          child: Container(
            color: _terminalTheme.background,
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
              keyboardAppearance: Brightness.dark,
              backgroundOpacity: 1.0,
              simulateScroll: false,
              cursorType: TerminalCursorType.underline,
            ),
          ),
        );
      },
    );
  }

  Widget _buildKeyBar() {
    final theme = Theme.of(context);
    final surface = theme.colorScheme.surface;
    return Container(
      color: surface,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Row 1: Esc Alt Home Up End Clipboard Backspace
            _buildKeyRow([
              _KeyDef('Esc', _sendEsc),
              _KeyDef(
                'Alt',
                _toggleAlt,
                active: _altActive,
              ),
              _KeyDef('Home', _sendHome),
              _KeyDef('↑', _sendUp),
              _KeyDef('End', _sendEnd),
              _KeyDef('📋', _pasteClipboard),
              _KeyDef('Bsp', _sendBackspace),
            ]),
            // Row 2: Tab Ctrl Left Down Right Voice Enter
            _buildKeyRow([
              _KeyDef('Tab', _sendTab),
              _KeyDef(
                'Ctrl',
                _toggleCtrl,
                active: _ctrlActive,
              ),
              _KeyDef('←', _sendLeft),
              _KeyDef('↓', _sendDown),
              _KeyDef('→', _sendRight),
              _KeyDef('🎤', _voiceInput),
              _KeyDef('Enter', _sendEnter),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyRow(List<_KeyDef> keys) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final surfaceVariant = theme.colorScheme.surfaceContainerHighest;
    final onSurface = theme.colorScheme.onSurface;
    return Row(
      children: keys.map((key) {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.all(1),
            child: SizedBox(
              height: 36,
              child: TextButton(
                onPressed: key.onTap,
                style: TextButton.styleFrom(
                  backgroundColor: key.active
                      ? primary
                      : surfaceVariant,
                  foregroundColor: key.active
                      ? theme.colorScheme.onPrimary
                      : onSurface.withValues(alpha: 0.8),
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  textStyle: const TextStyle(fontSize: 12),
                ),
                child: Text(key.label),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Future<void> _voiceInput() async {
    // TODO: implement speech-to-text
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Voice input not yet implemented')),
    );
  }

  void _copyOutput() {
    final text = _terminal.buffer.getText();
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard')),
    );
  }

  void _switchToSession(String sessionId) {
    if (sessionId == widget.session.id) return;
    final sessionsAsync = ref.read(serverSessionsProvider(widget.server.id));
    final sessions = sessionsAsync.valueOrNull;
    if (sessions == null) return;
    final target = sessions.firstWhere((s) => s.id == sessionId);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => SessionScreen(session: target, server: widget.server),
      ),
    );
  }

  Widget _buildSessionTabs() {
    final sessionsAsync = ref.watch(serverSessionsProvider(widget.server.id));
    return sessionsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (sessions) {
        if (sessions.length <= 1) return const SizedBox.shrink();
        // Few sessions: show inline tabs
        if (sessions.length <= 5) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: sessions.asMap().entries.map((entry) {
              final index = entry.key;
              final s = entry.value;
              final isCurrent = s.id == widget.session.id;
              final theme = Theme.of(context);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Tooltip(
                  message: '${s.title} (Alt+${index + 1})',
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: TextButton(
                      onPressed: () => _switchToSession(s.id),
                      style: TextButton.styleFrom(
                        backgroundColor: isCurrent
                            ? theme.colorScheme.primary
                            : theme.colorScheme.surfaceContainerHighest,
                        foregroundColor: isCurrent
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurface,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      child: Text('${index + 1}'),
                    ),
                  ),
                ),
              );
            }).toList(),
          );
        }
        // Many sessions: use popup menu
        final theme = Theme.of(context);
        return PopupMenuButton<String>(
          icon: const Icon(Icons.swap_horiz),
          tooltip: 'Switch session',
          itemBuilder: (ctx) => sessions.asMap().entries.map((entry) {
            final index = entry.key;
            final s = entry.value;
            final isCurrent = s.id == widget.session.id;
            return PopupMenuItem(
              value: s.id,
              child: Row(
                children: [
                  if (isCurrent)
                    Icon(Icons.check, size: 16, color: theme.colorScheme.primary)
                  else
                    const SizedBox(width: 16),
                  const SizedBox(width: 8),
                  Text('${index + 1}. ', style: const TextStyle(fontWeight: FontWeight.bold)),
                  Expanded(
                    child: Text(
                      s.title,
                      style: TextStyle(
                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                        color: isCurrent ? theme.colorScheme.primary : null,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onSelected: _switchToSession,
        );
      },
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

class _KeyDef {
  final String label;
  final VoidCallback onTap;
  final bool active;

  const _KeyDef(this.label, this.onTap, {this.active = false});
}
