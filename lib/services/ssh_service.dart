import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dartssh2/dartssh2.dart';
import '../models/server_config.dart';

class SshService {
  SSHClient? _client;
  SftpClient? _sftp;
  SSHSession? _shellSession;

  static const _connectTimeout = Duration(seconds: 15);

  SSHClient? get client => _client;
  bool get isConnected => _client != null;

  Future<void> connect(ServerConfig config) async {
    try {
      final socket = await _resolveAndConnect(config);

      if (config.useKeyAuth) {
        final keyPairs = SSHKeyPair.fromPem(
          config.privateKeyContent!,
          config.passphrase,
        );
        _client = SSHClient(
          socket,
          username: config.username,
          identities: keyPairs,
        );
      } else {
        _client = SSHClient(
          socket,
          username: config.username,
          onPasswordRequest: () => config.password,
        );
      }
    } on SocketException catch (e) {
      final msg = _friendlySocketError(e, config.host);
      throw SocketException(msg);
    } on TimeoutException {
      throw TimeoutException(
        'Connection to ${config.host}:${config.port} timed out after ${_connectTimeout.inSeconds}s',
      );
    }
  }

  /// Manually resolve hostname (prefer IPv4) then connect via SSHSocket.
  /// This works around Android DNS resolution issues where SSHSocket.connect
  /// fails to resolve hostnames directly.
  Future<SSHSocket> _resolveAndConnect(ServerConfig config) async {
    final host = config.host;

    // If already an IP address, connect directly
    if (InternetAddress.tryParse(host) != null) {
      return SSHSocket.connect(host, config.port, timeout: _connectTimeout);
    }

    // Resolve DNS manually, prefer IPv4
    final addresses = await InternetAddress.lookup(host)
        .timeout(_connectTimeout);

    if (addresses.isEmpty) {
      throw SocketException('Failed host lookup: "$host"');
    }

    // Prefer IPv4 for LAN servers
    final ipv4 = addresses.where((a) => a.type == InternetAddressType.IPv4);
    final target = ipv4.isNotEmpty ? ipv4.first : addresses.first;

    return SSHSocket.connect(
      target.address,
      config.port,
      timeout: _connectTimeout,
    );
  }

  String _friendlySocketError(SocketException e, String host) {
    final msg = e.message.toLowerCase();
    if (msg.contains('failed host lookup') || msg.contains('no address associated')) {
      return 'Cannot resolve host "$host". Please check the server address or your network connection.';
    }
    if (msg.contains('connection refused')) {
      return 'Connection refused by $host. The server may be down or the port is incorrect.';
    }
    if (msg.contains('network unreachable') || msg.contains('no route to host')) {
      return 'Network unreachable. Please check your internet connection.';
    }
    if (msg.contains('connection timed out') || msg.contains('timed out')) {
      return 'Connection to $host timed out. The server may be unreachable.';
    }
    return e.message;
  }

  Future<SftpClient> getSftp() async {
    if (_sftp != null) return _sftp!;
    if (_client == null) throw StateError('Not connected');
    _sftp = await _client!.sftp();
    return _sftp!;
  }

  Future<SSHSession> openShell({int? width, int? height}) async {
    if (_client == null) throw StateError('Not connected');
    // Close previous shell session if any
    if (_shellSession != null) {
      _shellSession!.close();
      _shellSession = null;
    }
    final pty = (width != null && height != null)
        ? SSHPtyConfig(width: width, height: height)
        : const SSHPtyConfig();
    _shellSession = await _client!.shell(pty: pty);
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
    _shellSession?.close();
    _shellSession = null;
    _sftp?.close();
    _sftp = null;
    _client?.close();
    _client = null;
  }
}
