import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/session.dart';
import '../models/chat_message.dart';
import '../models/server_config.dart';
import '../models/cli_tool.dart';
import '../services/session_manager.dart';
import 'ssh_provider.dart';

final sessionsBoxProvider = FutureProvider<Box<Session>>((ref) async {
  return await Hive.openBox<Session>('sessions');
});

final chatMessagesBoxProvider = FutureProvider<Box<ChatMessage>>((ref) async {
  return await Hive.openBox<ChatMessage>('chat_messages');
});

// Session list for a specific server
final serverSessionsProvider = AsyncNotifierProvider.family<
    ServerSessionsNotifier, List<Session>, String>(ServerSessionsNotifier.new);

class ServerSessionsNotifier
    extends FamilyAsyncNotifier<List<Session>, String> {
  @override
  Future<List<Session>> build(String serverId) async {
    final box = await ref.watch(sessionsBoxProvider.future);
    return box.values.where((s) => s.serverId == serverId).toList();
  }

  Future<Session> createSession({
    required ServerConfig server,
    required CliTool cliTool,
    String? workingDir,
  }) async {
    final connState = ref.read(sshConnectionProvider(server.id));
    final conn = connState.valueOrNull;
    if (conn == null || !conn.connected) {
      throw StateError('Not connected to server');
    }

    final manager = SessionManager(conn.service);
    final session = await manager.createSession(
      server: server,
      cliTool: cliTool,
      workingDir: workingDir,
    );

    final box = await ref.read(sessionsBoxProvider.future);
    await box.put(session.id, session);
    ref.invalidateSelf();
    return session;
  }

  Future<void> deleteSession(String sessionId) async {
    final box = await ref.read(sessionsBoxProvider.future);
    final session = box.get(sessionId);
    if (session != null) {
      // Try to kill the tmux session on the server
      try {
        final connState = ref.read(sshConnectionProvider(session.serverId));
        final conn = connState.valueOrNull;
        if (conn != null && conn.connected) {
          final manager = SessionManager(conn.service);
          await manager.killSession(session);
        }
      } catch (_) {
        // Ignore errors when killing remote session
      }
      await box.delete(sessionId);
      ref.invalidateSelf();
    }
  }

  Future<void> discoverRemote(ServerConfig server) async {
    final connState = ref.read(sshConnectionProvider(server.id));
    final conn = connState.valueOrNull;
    if (conn == null || !conn.connected) return;

    final manager = SessionManager(conn.service);
    final remoteSessions = await manager.discoverRemoteSessions(server);

    final box = await ref.read(sessionsBoxProvider.future);
    for (final session in remoteSessions) {
      if (!box.containsKey(session.id)) {
        await box.put(session.id, session);
      }
    }
    ref.invalidateSelf();
  }
}

// Active session management
final activeSessionProvider =
    NotifierProvider<ActiveSessionNotifier, Session?>(ActiveSessionNotifier.new);

class ActiveSessionNotifier extends Notifier<Session?> {
  @override
  Session? build() => null;

  void setActive(Session? session) {
    state = session;
  }
}

// Chat messages for a session
final chatMessagesProvider = AsyncNotifierProvider.family<
    ChatMessagesNotifier, List<ChatMessage>, String>(ChatMessagesNotifier.new);

class ChatMessagesNotifier
    extends FamilyAsyncNotifier<List<ChatMessage>, String> {
  @override
  Future<List<ChatMessage>> build(String sessionId) async {
    final box = await ref.watch(chatMessagesBoxProvider.future);
    return box.values
        .where((m) => m.sessionId == sessionId)
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  Future<void> addMessage(ChatMessage message) async {
    final box = await ref.read(chatMessagesBoxProvider.future);
    await box.put(message.id, message);
    ref.invalidateSelf();
  }

  Future<void> updateMessage(String id, {String? content, bool? isStreaming}) async {
    final box = await ref.read(chatMessagesBoxProvider.future);
    final msg = box.get(id);
    if (msg != null) {
      if (content != null) msg.content = content;
      if (isStreaming != null) msg.isStreaming = isStreaming;
      await box.put(id, msg);
      ref.invalidateSelf();
    }
  }

  Future<void> clearSession(String sessionId) async {
    final box = await ref.read(chatMessagesBoxProvider.future);
    final keys = box.values
        .where((m) => m.sessionId == sessionId)
        .map((m) => m.id)
        .toList();
    await box.deleteAll(keys);
    ref.invalidateSelf();
  }
}
