import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import 'package:xterm/xterm.dart';
import 'ssh_service.dart';

/// Escapes a string for safe use inside single-quoted shell strings.
/// Replaces each ' with '\'' (end quote, escaped quote, start quote).
/// Also strips null bytes and replaces newlines to prevent command injection.
String shellEscape(String s) {
  s = s.replaceAll('\x00', '').replaceAll('\n', ' ').replaceAll('\r', '');
  return s.replaceAll("'", r"'\''");
}

class TerminalService {
  final SshService _ssh;
  SSHSession? _session;
  Terminal? _terminal;
  StreamSubscription? _stdoutSub;
  StreamSubscription? _stderrSub;
  void Function()? _onDisconnect;
  bool _isConnecting = false;
  bool _explicitDetach = false;

  Terminal? get terminal => _terminal;
  bool get isActive => _session != null;

  TerminalService(this._ssh);

  void setOnDisconnect(void Function() callback) {
    _onDisconnect = callback;
  }

  void bindTerminal(Terminal terminal) {
    _terminal = terminal;
  }

  Future<void> attachToSession(String tmuxSessionName, {String? startCommand, String? workingDir}) async {
    if (_isConnecting) return;
    _isConnecting = true;
    try {
      if (_session != null) {
        await detach();
      }

      final escapedName = shellEscape(tmuxSessionName);
      final dir = shellEscape(workingDir ?? '~');

      // Check if tmux session exists using exec (no terminal echo pollution)
      bool sessionExists = false;
      try {
        final result = await _ssh.exec("tmux has-session -t '$escapedName' 2>&1; echo \$?");
        sessionExists = result.trimRight().endsWith('0');
      } catch (_) {
        sessionExists = false;
      }

      _explicitDetach = false;
      _session = await _ssh.openShell(
        width: _terminal?.viewWidth,
        height: _terminal?.viewHeight,
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw TimeoutException('SSH shell open timed out'),
      );

      // Feed SSH stdout/stderr to the terminal via streaming UTF-8 decoder.
      // The StreamTransformer handles multi-byte characters split across chunks.
      _stdoutSub = _session!.stdout
          .cast<List<int>>()
          .transform(utf8.decoder)
          .listen(
            (data) => _terminal?.write(data),
            onDone: _handleDisconnect,
            onError: (_) => _handleDisconnect(),
          );

      _stderrSub = _session!.stderr
          .cast<List<int>>()
          .transform(utf8.decoder)
          .listen(
            (data) => _terminal?.write(data),
            onDone: _handleDisconnect,
            onError: (_) => _handleDisconnect(),
          );

      // Route terminal keyboard output to SSH stdin
      _terminal?.onOutput = (data) {
        _session?.write(utf8.encode(data));
      };

      // Send tmux attach (or create+attach) command
      if (!sessionExists && startCommand != null && startCommand.isNotEmpty) {
        final escapedCmd = shellEscape(startCommand);
        final cmd =
            "tmux new-session -d -s '$escapedName' -c '$dir' '$escapedCmd' 2>/dev/null; "
            "tmux attach -t '$escapedName'\n";
        _session!.write(utf8.encode(cmd));
      } else {
        final cmd = "tmux attach -t '$escapedName'\n";
        _session!.write(utf8.encode(cmd));
      }
    } finally {
      _isConnecting = false;
    }
  }

  void _handleDisconnect() {
    if (_explicitDetach) return;
    _session = null;
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
    if (_terminal != null) {
      _terminal!.onOutput = (_) {};
    }
    _onDisconnect?.call();
  }

  Future<void> sendInput(String input) async {
    if (_session == null) throw StateError('Terminal not attached');
    _session!.write(utf8.encode(input));
  }

  Future<void> sendLine(String line) async {
    await sendInput('$line\n');
  }

  Future<void> sendCtrl(String key) async {
    if (_session == null) throw StateError('Terminal not attached');
    final code = key.toLowerCase().codeUnitAt(0) - 96;
    _session!.write(Uint8List.fromList([code]));
  }

  void resize(int width, int height) {
    _session?.resizeTerminal(width, height);
  }

  Future<void> detach() async {
    _explicitDetach = true;
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
    _session?.close();
    _session = null;
    if (_terminal != null) {
      _terminal!.onOutput = (_) {};
    }
  }

  void dispose() {
    _explicitDetach = true;
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
    _session?.close();
    _session = null;
    _terminal?.onOutput = (_) {};
    _onDisconnect = null;
  }
}
