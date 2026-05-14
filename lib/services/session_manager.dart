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

  static CliAdapter getAdapter(String cliToolId, {String? command}) {
    switch (cliToolId) {
      case 'claude':
        return ClaudeAdapter();
      case 'generic':
        return GenericAdapter(command: command ?? '');
      default:
        return GenericAdapter(command: command ?? cliToolId);
    }
  }

  Future<Session> createSession({
    required ServerConfig server,
    required CliTool cliTool,
    String? workingDir,
    int? sessionIndex,
  }) async {
    final sessionId = _uuid.v4();
    final toolPrefix = cliTool.id.length > 1 ? cliTool.id.substring(0, 1) : cliTool.id;
    final adapter = getAdapter(cliTool.id, command: cliTool.command);
    final dir = workingDir ?? server.defaultWorkingDir;
    final startCmd = adapter.getStartCommand(workingDir: dir);

    // Find an available tmux session name (avoid conflicts with existing sessions)
    int index = sessionIndex ?? 1;
    String tmuxName = 'acode_$toolPrefix$index';
    while (await _tmux.sessionExists(tmuxName)) {
      index++;
      tmuxName = 'acode_$toolPrefix$index';
    }

    // Create tmux session with the CLI tool
    await _tmux.createSession(tmuxName, startCmd, workingDir: dir);

    final suffix = index > 1 ? ' #$index' : '';
    final session = Session(
      id: sessionId,
      serverId: server.id,
      cliToolId: cliTool.id,
      cliToolCommand: cliTool.command,
      tmuxSessionName: tmuxName,
      title: '${cliTool.name} - ${server.name}$suffix',
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

  Future<List<Session>> discoverRemoteSessions(
    ServerConfig server, {
    List<CliTool> knownTools = const [],
  }) async {
    final sessions = await _tmux.listSessions();
    final acodeSessions = sessions
        .where((s) => s.name.startsWith('acode_'))
        .toList();

    // Build prefix→cliToolId map from known tools
    final prefixMap = <String, String>{};
    for (final tool in knownTools) {
      final prefix = tool.id.length > 1 ? tool.id.substring(0, 1) : tool.id;
      // Don't overwrite an existing mapping (first wins)
      prefixMap.putIfAbsent(prefix, () => tool.id);
    }

    // Group by cliToolId to assign sequential numbers
    final toolCount = <String, int>{};

    return acodeSessions.map((info) {
      // Parse name like "acode_c1" -> prefix "c", number "1"
      final namePart = info.name.substring(6); // strip "acode_"
      final prefixChar = namePart.replaceAll(RegExp(r'\d'), '');
      final cliId = prefixMap[prefixChar] ?? prefixChar;

      // Look up name from known tools or fall back to ID
      final known = knownTools.where((t) => t.id == cliId);
      final toolName = known.isNotEmpty
          ? known.first.name
          : CliTool.defaults()
              .firstWhere(
                (t) => t.id == cliId,
                orElse: () => CliTool(id: cliId, name: cliId, command: cliId),
              )
              .name;

      final count = (toolCount[cliId] ?? 0) + 1;
      toolCount[cliId] = count;

      final suffix = count > 1 ? ' #$count' : '';

      return Session(
        id: _uuid.v4(),
        serverId: server.id,
        cliToolId: cliId,
        tmuxSessionName: info.name,
        title: '$toolName - ${server.name}$suffix',
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
