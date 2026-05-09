import 'dart:async';
import 'dart:convert';
import 'package:dartssh2/dartssh2.dart';
import '../models/server_config.dart';

class SshService {
  SSHClient? _client;
  SftpClient? _sftp;
  SSHSession? _shellSession;
  StreamController<String>? _outputController;

  SSHClient? get client => _client;
  bool get isConnected => _client != null;

  Stream<String>? get outputStream => _outputController?.stream;

  Future<void> connect(ServerConfig config) async {
    _outputController = StreamController<String>.broadcast();

    if (config.useKeyAuth) {
      final keyPairs = SSHKeyPair.fromPem(
        config.privateKeyContent!,
        config.passphrase,
      );
      _client = SSHClient(
        await SSHSocket.connect(config.host, config.port),
        username: config.username,
        identities: keyPairs,
      );
    } else {
      _client = SSHClient(
        await SSHSocket.connect(config.host, config.port),
        username: config.username,
        onPasswordRequest: () => config.password,
      );
    }
  }

  Future<SftpClient> getSftp() async {
    if (_sftp != null) return _sftp!;
    if (_client == null) throw StateError('Not connected');
    _sftp = await _client!.sftp();
    return _sftp!;
  }

  Future<SSHSession> openShell() async {
    if (_client == null) throw StateError('Not connected');
    _shellSession = await _client!.shell();

    _shellSession!.stdout
        .cast<List<int>>()
        .transform(utf8.decoder)
        .listen((data) {
      _outputController?.add(data);
    });

    _shellSession!.stderr
        .cast<List<int>>()
        .transform(utf8.decoder)
        .listen((data) {
      _outputController?.add(data);
    });

    return _shellSession!;
  }

  Future<String> exec(String command) async {
    if (_client == null) throw StateError('Not connected');
    final result = await _client!.run(command);
    return utf8.decode(result);
  }

  Future<void> writeToShell(String data) async {
    if (_shellSession == null) throw StateError('Shell not open');
    _shellSession!.write(utf8.encode(data));
  }

  Future<void> disconnect() async {
    _outputController?.close();
    _outputController = null;
    _shellSession?.close();
    _shellSession = null;
    _sftp = null;
    _client?.close();
    _client = null;
  }
}
