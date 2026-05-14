import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/gestures.dart';
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
import 'quick_input_page.dart';

class SessionScreen extends ConsumerStatefulWidget {
  final Session session;
  final ServerConfig server;

  const SessionScreen({super.key, required this.session, required this.server});

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
  bool _shiftActive = false;
  late bool _showKeyBar;
  bool _keyboardVisible = false;
  bool _userToggleKeyboard = false;
  bool _terminalReady = false;
  final _terminalViewKey = GlobalKey<TerminalViewState>();
  final _terminalController = TerminalController();
  Timer? _selectionTimer;
  Timer? _debugTimer;

  // Selection handle state
  bool _selectionActive = false;
  Offset? _startHandleOffset;
  Offset? _endHandleOffset;
  bool _isDraggingStart = false;
  bool _isDraggingEnd = false;

  // Scroll accumulation for touch-based scrolling via tmux mouse events
  double _scrollAccum = 0;

  static const _darkTheme = TerminalTheme(
    cursor: Color(0xFFAEAFAD),
    selection: Color(0xFF2A3E5C),
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
    selection: Color(0xFFC5D9F1),
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
    _terminalController.addListener(_onSelectionChanged);
    _terminal.addListener(_onTerminalChanged);
    _connect();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _selectionTimer?.cancel();
    _debugTimer?.cancel();
    _terminal.removeListener(_onTerminalChanged);
    _terminalController.removeListener(_onSelectionChanged);
    _terminalController.dispose();
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

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!mounted || _userToggleKeyboard) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _userToggleKeyboard) return;
      final bottom = MediaQuery.of(context).viewInsets.bottom;
      final keyboardOpen = bottom > 0;
      if (_keyboardVisible != keyboardOpen) {
        setState(() => _keyboardVisible = keyboardOpen);
      }
    });
  }

  void _setupTerminalService(SshConnection conn) {
    _terminalService?.dispose();
    _terminalService = TerminalService(conn.service);
    _terminalService!.bindTerminal(_terminal);
    _terminalService!.setOnDisconnect(_onSessionDisconnect);
    _terminal.onResize = (width, height, _, _) {
      _terminalService?.resize(width, height);
    };
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
      setState(
        () => _connectionStatus = 'Disconnected. Tap Retry to reconnect.',
      );
    }
  }

  Future<void> _connect() async {
    if (_isConnecting) return;
    _isConnecting = true;

    setState(() => _connectionStatus = 'Connecting to server...');

    try {
      final notifier = ref.read(
        sshConnectionProvider(widget.server.id).notifier,
      );
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

      // Show TerminalView first so layout gives us correct viewport dimensions
      setState(() => _terminalReady = true);

      // Wait for one frame — TerminalView gets built, laid out,
      // autoResize sets _terminal.viewWidth/viewHeight to actual widget size.
      final completer = Completer<void>();
      WidgetsBinding.instance.addPostFrameCallback((_) => completer.complete());
      await completer.future;
      if (!mounted) return;

      // Now _terminal has correct dimensions — open SSH shell with matching PTY size
      try {
        await _terminalService!.attachToSession(
          widget.session.tmuxSessionName,
          startCommand: _getStartCommand(),
          workingDir: widget.session.workingDir,
        );
        if (!mounted) return;
        _wrapTerminalOutput();
        // Exit alternate screen so xterm scrollback + scrollbar work
        _terminal.write('\x1b[?1049l');
      } catch (e) {
        if (e.toString().contains('Transport') ||
            e.toString().contains('closed')) {
          await notifier.disconnect();
          await notifier.connect(widget.server);
          if (!mounted) return;
          conn = ref.read(sshConnectionProvider(widget.server.id)).valueOrNull;
          if (conn == null) throw StateError('Failed to reconnect');
          _setupTerminalService(conn);
          await _terminalService!.attachToSession(
            widget.session.tmuxSessionName,
            startCommand: _getStartCommand(),
            workingDir: widget.session.workingDir,
          );
          if (!mounted) return;
          _wrapTerminalOutput();
          _terminal.write('\x1b[?1049l');
        } else {
          rethrow;
        }
      }

      if (!mounted) return;
      _reconnectAttempts = 0;
      setState(() {
        _connected = true;
        _connectionStatus = 'Connected';
      });

      // Desktop: force-open text input connection so physical keyboard
      // and IME (Chinese/Japanese/Korean) input work. On mobile, the
      // on-screen keyboard is toggled explicitly by the user.
      if (!Platform.isAndroid && !Platform.isIOS) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _terminalViewKey.currentState?.requestKeyboard();
          }
        });
      }

      // Debug: log initial cursor state
      final buf = _terminal.buffer;
      debugPrint(
        '[CURSOR DEBUG] INITIAL: cursorY=${buf.cursorY} '
        'absoluteCursorY=${buf.absoluteCursorY} '
        'scrollBack=${buf.scrollBack} '
        'viewHeight=${buf.viewHeight} '
        'height=${buf.height} '
        'cursorX=${buf.cursorX}',
      );

      // Debug: periodic cursor position logging
      _debugTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        final buf = _terminal.buffer;
        debugPrint(
          '[CURSOR DEBUG] cursorY=${buf.cursorY} '
          'absoluteCursorY=${buf.absoluteCursorY} '
          'scrollBack=${buf.scrollBack} '
          'viewHeight=${buf.viewHeight} '
          'height=${buf.height} '
          'cursorX=${buf.cursorX}',
        );
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

  // --- Ctrl modifier wrapper ---

  void _wrapTerminalOutput() {
    final original = _terminal.onOutput;
    if (original == null) return;
    _terminal.onOutput = (String data) {
      if (_ctrlActive && data.length == 1) {
        final c = data.codeUnitAt(0);
        if (c >= 0x61 && c <= 0x7A) {
          // a-z
          original(String.fromCharCode(c - 96));
          return;
        }
        if (c >= 0x41 && c <= 0x5A) {
          // A-Z
          original(String.fromCharCode(c - 64));
          return;
        }
      }
      original(data);
    };
  }

  int _lastCursorY = -1;

  void _onTerminalChanged() {
    final buf = _terminal.buffer;
    if (buf.cursorY != _lastCursorY) {
      _lastCursorY = buf.cursorY;
      debugPrint(
        '[CURSOR CHANGED] cursorY=${buf.cursorY} '
        'absoluteCursorY=${buf.absoluteCursorY} '
        'scrollBack=${buf.scrollBack} '
        'viewHeight=${buf.viewHeight} '
        'height=${buf.height} '
        'cursorX=${buf.cursorX}',
      );
    }
  }

  // --- Selection / Copy ---

  void _onSelectionChanged() {
    final selection = _terminalController.selection;
    if (selection == null || selection.isCollapsed) {
      if (_selectionActive) {
        setState(() {
          _selectionActive = false;
          _startHandleOffset = null;
          _endHandleOffset = null;
        });
      }
      return;
    }
    _selectionTimer?.cancel();
    _selectionTimer = Timer(const Duration(milliseconds: 1500), () {
      _copySelection();
    });
    if (!_isDraggingStart && !_isDraggingEnd) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateHandlePositions();
      });
    }
  }

  void _copySelection() {
    final selection = _terminalController.selection;
    if (selection == null || selection.isCollapsed) return;
    final text = _terminal.buffer.getText(selection);
    if (text.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: text));
      ref.read(clipboardHistoryProvider.notifier).add(text);
    }
  }

  // --- Selection handles ---

  void _updateHandlePositions() {
    final selection = _terminalController.selection;
    if (selection == null || selection.isCollapsed) return;
    final renderState = _terminalViewKey.currentState;
    if (renderState == null) return;
    final rt = renderState.renderTerminal;
    final cellSize = rt.cellSize;

    final startPixel = rt.getOffset(selection.begin);
    final endPixel = rt.getOffset(selection.end);

    setState(() {
      _startHandleOffset = Offset(startPixel.dx, startPixel.dy);
      _endHandleOffset = Offset(
        endPixel.dx + cellSize.width,
        endPixel.dy + cellSize.height,
      );
      _selectionActive = true;
    });
  }

  void _onStartHandleDrag(DragUpdateDetails details) {
    _isDraggingStart = true;
    final renderState = _terminalViewKey.currentState;
    if (renderState == null) return;
    final rt = renderState.renderTerminal;

    if (_startHandleOffset == null || _endHandleOffset == null) return;
    final newPos = _startHandleOffset! + details.delta;
    // Clamp to render bounds
    final clamped = Offset(
      newPos.dx.clamp(0, rt.cellSize.width * _terminal.viewWidth),
      newPos.dy.clamp(0, rt.cellSize.height * _terminal.buffer.lines.length),
    );
    _startHandleOffset = clamped;
    rt.selectCharacters(clamped, _endHandleOffset!);
  }

  void _onStartHandleDragEnd(_) {
    _isDraggingStart = false;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _updateHandlePositions(),
    );
  }

  void _onEndHandleDrag(DragUpdateDetails details) {
    _isDraggingEnd = true;
    final renderState = _terminalViewKey.currentState;
    if (renderState == null) return;
    final rt = renderState.renderTerminal;

    if (_startHandleOffset == null || _endHandleOffset == null) return;
    final newPos = _endHandleOffset! + details.delta;
    final clamped = Offset(
      newPos.dx.clamp(0, rt.cellSize.width * _terminal.viewWidth),
      newPos.dy.clamp(0, rt.cellSize.height * _terminal.buffer.lines.length),
    );
    _endHandleOffset = clamped;
    rt.selectCharacters(_startHandleOffset!, clamped);
  }

  void _onEndHandleDragEnd(_) {
    _isDraggingEnd = false;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _updateHandlePositions(),
    );
  }

  List<Widget> _buildSelectionHandles() {
    if (!_selectionActive ||
        _startHandleOffset == null ||
        _endHandleOffset == null) {
      return [];
    }

    const handleSize = 20.0;
    final purple = const Color(0xFF7C3AED);

    return [
      // Start handle
      Positioned(
        left: _startHandleOffset!.dx - handleSize / 2,
        top: _startHandleOffset!.dy - handleSize,
        width: handleSize,
        height: handleSize,
        child: GestureDetector(
          onPanUpdate: _onStartHandleDrag,
          onPanEnd: _onStartHandleDragEnd,
          child: CustomPaint(
            painter: _HandlePainter(color: purple, isStart: true),
          ),
        ),
      ),
      // End handle
      Positioned(
        left: _endHandleOffset!.dx - handleSize / 2,
        top: _endHandleOffset!.dy,
        width: handleSize,
        height: handleSize,
        child: GestureDetector(
          onPanUpdate: _onEndHandleDrag,
          onPanEnd: _onEndHandleDragEnd,
          child: CustomPaint(
            painter: _HandlePainter(color: purple, isStart: false),
          ),
        ),
      ),
    ];
  }

  // --- Touch scroll handling ---

  static const double _scrollThreshold = 20.0; // ~1 cell height in pixels

  void _onScrollPointerMove(PointerMoveEvent event) {
    // Negate: finger movement and scroll semantics have opposite sign conventions
    _handleScrollDelta(-event.delta.dy);
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      _handleScrollDelta(event.scrollDelta.dy);
    }
  }

  void _handleScrollDelta(double delta) {
    if (!_connected || _terminalService == null) return;
    _scrollAccum += delta;

    while (_scrollAccum.abs() >= _scrollThreshold) {
      if (_scrollAccum > 0) {
        // Scroll down → send wheel-down SGR sequence to tmux
        _sendScrollSignal('\x1b[<65;1;1M');
      } else {
        // Scroll up → send wheel-up SGR sequence to tmux
        _sendScrollSignal('\x1b[<64;1;1M');
      }
      _scrollAccum -= _scrollAccum > 0 ? _scrollThreshold : -_scrollThreshold;
    }
  }

  void _sendScrollSignal(String seq) {
    // Send directly to SSH session (bypasses xterm's mouse mode entirely)
    _terminalService?.sendInput(seq);
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
      if (_altActive) {
        _ctrlActive = false;
        _shiftActive = false;
      }
    });
  }

  void _toggleCtrl() {
    setState(() {
      _ctrlActive = !_ctrlActive;
      if (_ctrlActive) {
        _altActive = false;
        _shiftActive = false;
      }
    });
  }

  void _toggleShift() {
    setState(() {
      _shiftActive = !_shiftActive;
      if (_shiftActive) {
        _altActive = false;
        _ctrlActive = false;
      }
    });
  }

  void _clearModifiers() {
    if (_altActive || _ctrlActive || _shiftActive) {
      setState(() {
        _altActive = false;
        _ctrlActive = false;
        _shiftActive = false;
      });
    }
  }

  void _sendNumber(int n) {
    _send('$n');
    _clearModifiers();
  }

  void _toggleKeyboard() {
    _userToggleKeyboard = true;
    if (_keyboardVisible) {
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() => _keyboardVisible = false);
    } else {
      setState(() => _keyboardVisible = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _terminalViewKey.currentState?.requestKeyboard();
      });
    }
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) _userToggleKeyboard = false;
    });
  }

  void _openQuickInput() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QuickInputPage(onSend: (text) => _terminal.paste(text)),
      ),
    );
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
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8,
      LogicalKeyboardKey.digit9,
    ];
    for (var i = 0; i < count; i++) {
      map[SingleActivator(digitKeys[i], alt: true)] = () =>
          _switchToSession(sessions[i].id);
    }
    map[SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true)] = () =>
        _switchToAdjacentSession(-1);
    map[SingleActivator(LogicalKeyboardKey.arrowRight, alt: true)] = () =>
        _switchToAdjacentSession(1);
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
                  child: ListTile(
                    leading: Icon(Icons.copy),
                    title: Text('Copy output'),
                    dense: true,
                  ),
                ),
                const PopupMenuItem(
                  value: 'reconnect',
                  child: ListTile(
                    leading: Icon(Icons.refresh),
                    title: Text('Reconnect'),
                    dense: true,
                  ),
                ),
                if (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
                  PopupMenuItem(
                    value: 'keys',
                    child: ListTile(
                      leading: Icon(
                        _showKeyBar ? Icons.keyboard_hide : Icons.keyboard,
                      ),
                      title: Text(_showKeyBar ? 'Hide keys' : 'Show keys'),
                      dense: true,
                    ),
                  ),
                const PopupMenuItem(
                  value: 'kill',
                  child: ListTile(
                    leading: Icon(Icons.stop_circle, color: Colors.red),
                    title: Text(
                      'Kill Session',
                      style: TextStyle(color: Colors.red),
                    ),
                    dense: true,
                  ),
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
    if (!_terminalReady) {
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

    const fontSize = 14.0;

    Widget terminal = Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _scrollAccum = 0,
      onPointerMove: _onScrollPointerMove,
      onPointerSignal: _onPointerSignal,
      child: LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          color: _terminalTheme.background,
          child: TerminalView(
              _terminal,
              key: _terminalViewKey,
              controller: _terminalController,
              theme: _terminalTheme,
              textStyle: TerminalStyle(
                fontSize: fontSize,
                fontFamily: 'monospace',
              ),
              autofocus: true,
              readOnly: (Platform.isAndroid || Platform.isIOS)
                  ? !_keyboardVisible
                  : false,
              deleteDetection: true,
              keyboardType: TextInputType.text,
              keyboardAppearance: Brightness.dark,
              backgroundOpacity: 1.0,
              simulateScroll: false,
              cursorType: TerminalCursorType.underline,
            ),
          );
        },
      ),
    );

    // Overlay a semi-transparent status when not yet connected
    if (!_connected) {
      terminal = Stack(
        children: [
          terminal,
          Positioned.fill(
            child: Container(
              color: const Color(0x88000000),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      _connectionStatus,
                      style: const TextStyle(color: Colors.white),
                    ),
                    if (_connectionStatus.startsWith('Error') ||
                        _reconnectAttempts > _maxReconnectAttempts)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: FilledButton(
                          onPressed: () {
                            _reconnectAttempts = 0;
                            _connect();
                          },
                          child: const Text('Retry'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    // Overlay selection handles on top of terminal
    final handles = _buildSelectionHandles();
    if (_selectionActive && handles.isNotEmpty) {
      terminal = Stack(children: [terminal, ...handles]);
    }

    return terminal;
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
            // Row 1: Esc 1 2 3 4 5 6
            _buildKeyRow([
              _KeyDef('Esc', _sendEsc),
              _KeyDef('1', () => _sendNumber(1)),
              _KeyDef('2', () => _sendNumber(2)),
              _KeyDef('3', () => _sendNumber(3)),
              _KeyDef('4', () => _sendNumber(4)),
              _KeyDef('5', () => _sendNumber(5)),
              _KeyDef('6', () => _sendNumber(6)),
            ]),
            // Row 2: Tab Shift Home ↑ End Paste Bsp
            _buildKeyRow([
              _KeyDef('Tab', _sendTab),
              _KeyDef('Shift', _toggleShift, active: _shiftActive),
              _KeyDef('Home', _sendHome),
              _KeyDef('↑', _sendUp),
              _KeyDef('End', _sendEnd),
              _KeyDef('📋', _openQuickInput),
              _KeyDef('Bsp', _sendBackspace, onRepeat: _sendBackspace),
            ]),
            // Row 3: Ctrl Alt ← ↓ → Keyboard Enter
            _buildKeyRow([
              _KeyDef('Ctrl', _toggleCtrl, active: _ctrlActive),
              _KeyDef('Alt', _toggleAlt, active: _altActive),
              _KeyDef('←', _sendLeft),
              _KeyDef('↓', _sendDown),
              _KeyDef('→', _sendRight),
              _KeyDef('⌨', _toggleKeyboard),
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
        final button = key.onRepeat != null
            ? _RepeatButton(
                label: key.label,
                onTap: key.onTap,
                active: key.active,
              )
            : TextButton(
                onPressed: key.onTap,
                style: TextButton.styleFrom(
                  backgroundColor: key.active ? primary : surfaceVariant,
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
              );
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.all(1),
            child: SizedBox(height: 36, child: button),
          ),
        );
      }).toList(),
    );
  }

  void _copyOutput() {
    final text = _terminal.buffer.getText();
    Clipboard.setData(ClipboardData(text: text));
    ref.read(clipboardHistoryProvider.notifier).add(text);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
  }

  void _switchToSession(String sessionId) {
    if (sessionId == widget.session.id) return;
    // Dismiss keyboard before switching to prevent flicker
    FocusManager.instance.primaryFocus?.unfocus();
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
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
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
                    Icon(
                      Icons.check,
                      size: 16,
                      color: theme.colorScheme.primary,
                    )
                  else
                    const SizedBox(width: 16),
                  const SizedBox(width: 8),
                  Text(
                    '${index + 1}. ',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Expanded(
                    child: Text(
                      s.title,
                      style: TextStyle(
                        fontWeight: isCurrent
                            ? FontWeight.bold
                            : FontWeight.normal,
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
          'This will terminate the CLI tool on the server. Continue?',
        ),
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
  final VoidCallback? onRepeat;

  const _KeyDef(this.label, this.onTap, {this.active = false, this.onRepeat});
}

class _RepeatButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final bool active;

  const _RepeatButton({
    required this.label,
    required this.onTap,
    this.active = false,
  });

  @override
  State<_RepeatButton> createState() => _RepeatButtonState();
}

class _RepeatButtonState extends State<_RepeatButton> {
  Timer? _timer;
  bool _isPressing = false;

  void _onLongPressStart(_) {
    _isPressing = true;
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      widget.onTap();
    });
    Future.delayed(const Duration(seconds: 1), () {
      if (_isPressing && mounted) {
        _timer?.cancel();
        _timer = Timer.periodic(const Duration(milliseconds: 40), (_) {
          widget.onTap();
        });
      }
    });
  }

  void _stopRepeat() {
    _isPressing = false;
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _stopRepeat();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final surfaceVariant = theme.colorScheme.surfaceContainerHighest;
    final onSurface = theme.colorScheme.onSurface;
    return GestureDetector(
      onTap: widget.onTap,
      onLongPressStart: _onLongPressStart,
      onLongPressEnd: (_) => _stopRepeat(),
      onLongPressCancel: _stopRepeat,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: widget.active ? primary : surfaceVariant,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          widget.label,
          style: TextStyle(
            fontSize: 12,
            color: widget.active
                ? theme.colorScheme.onPrimary
                : onSurface.withValues(alpha: 0.8),
          ),
        ),
      ),
    );
  }
}

class _HandlePainter extends CustomPainter {
  final Color color;
  final bool isStart;

  const _HandlePainter({required this.color, required this.isStart});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, isStart ? size.height : 0);
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    // Draw vertical line from center to edge
    if (isStart) {
      canvas.drawLine(center, Offset(size.width / 2, size.height), linePaint);
    } else {
      canvas.drawLine(Offset(size.width / 2, 0), center, linePaint);
    }

    // Draw dot at the handle end
    canvas.drawCircle(center, 5, dotPaint);
    // Draw white border
    dotPaint.color = Colors.white;
    dotPaint.style = PaintingStyle.stroke;
    dotPaint.strokeWidth = 1.5;
    canvas.drawCircle(center, 5, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _HandlePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.isStart != isStart;
}
