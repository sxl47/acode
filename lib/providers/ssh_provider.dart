import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/server_config.dart';
import '../services/ssh_service.dart';

class SshConnection {
  final ServerConfig server;
  final SshService service;
  final bool connected;

  SshConnection({
    required this.server,
    required this.service,
    this.connected = false,
  });

  SshConnection copyWith({bool? connected}) {
    return SshConnection(
      server: server,
      service: service,
      connected: connected ?? this.connected,
    );
  }
}

final sshServiceProvider = Provider.family<SshService, String>((ref, serverId) {
  return SshService();
});

final sshConnectionProvider =
    AsyncNotifierProvider.family<SshConnectionNotifier, SshConnection?, String>(
        SshConnectionNotifier.new);

class SshConnectionNotifier extends FamilyAsyncNotifier<SshConnection?, String> {
  @override
  Future<SshConnection?> build(String serverId) async {
    return null;
  }

  Future<SshConnection> connect(ServerConfig server) async {
    // Disconnect existing connection first to avoid leaking SSH sockets
    final existing = state.valueOrNull;
    if (existing != null) {
      await existing.service.disconnect();
    }
    state = const AsyncLoading();
    final service = SshService();
    try {
      await service.connect(server);
      final connection = SshConnection(
        server: server,
        service: service,
        connected: true,
      );
      state = AsyncData(connection);
      return connection;
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  Future<void> disconnect() async {
    final conn = state.valueOrNull;
    if (conn != null) {
      await conn.service.disconnect();
      state = const AsyncData(null);
    }
  }
}
