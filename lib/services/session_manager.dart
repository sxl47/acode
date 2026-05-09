import 'dart:async';
import 'dart:io';
import 'package:uuid/uuid.dart';
import '../models/session.dart';
import '../models/chat_message.dart';
import '../models/server_config.dart';
import '../models/cli_tool.dart';
import 'ssh_service.dart';
import 'tmux_service.dart';
import 'sftp_service.dart';
import 'cli_adapter.dart';
import 'adapters/claude_adapter.dart';
import 'adapters/generic_adapter.dart';

class SessionManager {
  final SshService _ssh;
  late final TmuxService _tmux;
  late final SftpService _sftp;
  final _uuid = const Uuid();

  final Map<String, StreamSubscription> _outputSubscriptions = {};
  final StreamController<ChatMessage> _messageController =
      StreamController<ChatMessage>.broadcast();

  Stream<ChatMessage> get messageStream => _messageController.stream;

  SessionManager(this._ssh) {
    _tmux = TmuxService(_ssh);
    _sftp = SftpService(_ssh);
  }

  CliAdapter getAdapter(String cliToolId, {String? command}) {
    switch (cliToolId) {
      case 'claude':
        return ClaudeAdapter();
      case 'generic':
        return GenericAdapter(command: command ?? '');
      default:
        return GenericAdapter(command: cliToolId);
    }
  }

  Future<Session> createSession({
    required ServerConfig server,
    required CliTool cliTool,
    String? workingDir,
  }) async {
    final sessionId = _uuid.v4();
    final tmuxName = 'acode_${cliTool.id}_$sessionId';
    final adapter = getAdapter(cliTool.id, command: cliTool.command);
    final dir = workingDir ?? server.defaultWorkingDir;

    // Create tmux session with the CLI tool
    final startCmd = adapter.getStartCommand(workingDir: dir);
    await _tmux.createSession(tmuxName, startCmd, workingDir: dir);

    final session = Session(
      id: sessionId,
      serverId: server.id,
      cliToolId: cliTool.id,
      tmuxSessionName: tmuxName,
      title: '${cliTool.name} - ${server.name}',
      status: SessionStatus.active,
      workingDir: dir,
    );

    return session;
  }

  Future<void> attachToSession(Session session) async {
    // Verify tmux session exists
    final exists = await _tmux.sessionExists(session.tmuxSessionName);
    if (!exists) {
      throw StateError(
          'Tmux session ${session.tmuxSessionName} not found on server');
    }
  }

  Future<List<Session>> discoverRemoteSessions(ServerConfig server) async {
    final sessions = await _tmux.listSessions();
    final acodeSessions = sessions
        .where((s) => s.name.startsWith('acode_'))
        .toList();

    return acodeSessions.map((info) {
      final parts = info.name.split('_');
      final cliId = parts.length > 1 ? parts[1] : 'generic';

      return Session(
        id: _uuid.v4(),
        serverId: server.id,
        cliToolId: cliId,
        tmuxSessionName: info.name,
        title: info.name,
        status: SessionStatus.active,
      );
    }).toList();
  }

  Future<void> sendMessage(Session session, String text,
      {List<String>? imagePaths}) async {
    final adapter = getAdapter(session.cliToolId);
    final input = adapter.formatInput(text, imagePaths: imagePaths);
    await _tmux.sendKeys(session.tmuxSessionName, input);
    session.touch();
  }

  Future<String> captureOutput(Session session) async {
    return await _tmux.captureOutput(session.tmuxSessionName);
  }

  Future<String> uploadImage(File file) async {
    final ext = file.path.split('.').last;
    final name = '${_uuid.v4()}.$ext';
    return await _sftp.uploadFile(file, name);
  }

  Future<void> killSession(Session session) async {
    _outputSubscriptions[session.id]?.cancel();
    _outputSubscriptions.remove(session.id);
    await _tmux.killSession(session.tmuxSessionName);
  }

  void dispose() {
    for (final sub in _outputSubscriptions.values) {
      sub.cancel();
    }
    _outputSubscriptions.clear();
    _messageController.close();
  }
}
