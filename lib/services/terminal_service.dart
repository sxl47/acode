import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import 'ssh_service.dart';

class TerminalService {
  final SshService _ssh;
  SSHSession? _session;
  final StreamController<String> _outputController =
      StreamController<String>.broadcast();
  final List<String> _outputBuffer = [];
  static const int _maxBufferLines = 2000;

  Stream<String> get output => _outputController.stream;
  List<String> get outputBuffer => List.unmodifiable(_outputBuffer);
  bool get isActive => _session != null;

  TerminalService(this._ssh);

  Future<void> attachToSession(String tmuxSessionName) async {
    if (_session != null) {
      await detach();
    }

    _session = await _ssh.openShell();

    // Send tmux attach command
    final cmd = 'tmux attach -t "$tmuxSessionName" 2>/dev/null || echo "Session not found"\n';
    _session!.write(utf8.encode(cmd));

    // Listen to stdout
    _session!.stdout.cast<List<int>>().transform(utf8.decoder).listen(
      (data) {
        _addToBuffer(data);
        _outputController.add(data);
      },
      onDone: () {
        _outputController.add('\n[Session ended]\n');
      },
    );

    // Listen to stderr
    _session!.stderr.cast<List<int>>().transform(utf8.decoder).listen(
      (data) {
        _addToBuffer(data);
        _outputController.add(data);
      },
    );
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
    // Send Ctrl+key (e.g., 'c' for Ctrl+C)
    final code = key.toLowerCase().codeUnitAt(0) - 96; // 'a' = 1, 'c' = 3, etc.
    _session!.write(Uint8List.fromList([code]));
  }

  Future<void> detach() async {
    _session?.close();
    _session = null;
  }

  void _addToBuffer(String data) {
    final lines = data.split('\n');
    _outputBuffer.addAll(lines);
    while (_outputBuffer.length > _maxBufferLines) {
      _outputBuffer.removeAt(0);
    }
  }

  void dispose() {
    _session?.close();
    _outputController.close();
  }
}
