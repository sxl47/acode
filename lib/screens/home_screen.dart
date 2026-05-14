import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../providers/settings_provider.dart';
import '../providers/session_provider.dart';
import '../providers/ssh_provider.dart';
import '../models/server_config.dart';
import '../models/session.dart';
import '../models/cli_tool.dart';
import 'connect_screen.dart';
import 'session_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    // Auto-discover sessions on first load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _discoverAllSessions();
    });
  }

  Future<void> _discoverAllSessions() async {
    final servers = await ref.read(serversProvider.future);
    for (final server in servers) {
      await _discoverServerSessions(server);
    }
  }

  Future<void> _discoverServerSessions(ServerConfig server) async {
    try {
      final connState = ref.read(sshConnectionProvider(server.id));
      if (connState.valueOrNull == null ||
          !connState.valueOrNull!.connected) {
        await ref
            .read(sshConnectionProvider(server.id).notifier)
            .connect(server);
      }
      await ref
          .read(serverSessionsProvider(server.id).notifier)
          .discoverRemote(server);
    } catch (_) {
      // Ignore discovery errors on startup
    }
  }

  @override
  Widget build(BuildContext context) {
    final serversAsync = ref.watch(serversProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ACode'),
        actions: [
          IconButton(
            icon: const Icon(Icons.brightness_6),
            tooltip: 'Toggle theme',
            onPressed: () {
              ref.read(themeModeProvider.notifier).toggle();
            },
          ),
          IconButton(
            icon: _scanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            tooltip: 'Discover remote sessions',
            onPressed: _scanning
                ? null
                : () async {
                    setState(() => _scanning = true);
                    await _discoverAllSessions();
                    if (mounted) setState(() => _scanning = false);
                  },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: serversAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (servers) {
          if (servers.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.dns_outlined, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No servers configured',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add a server to get started',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[500],
                        ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () => _addServer(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Server'),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _discoverAllSessions,
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: servers.length,
              itemBuilder: (context, index) {
                final server = servers[index];
                return _ServerCard(
                  server: server,
                  onDiscover: () => _discoverServerSessions(server),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addServer(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _addServer(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ConnectScreen()),
    );
  }
}

class _ServerCard extends ConsumerStatefulWidget {
  final ServerConfig server;
  final VoidCallback? onDiscover;

  const _ServerCard({required this.server, this.onDiscover});

  @override
  ConsumerState<_ServerCard> createState() => _ServerCardState();
}

class _ServerCardState extends ConsumerState<_ServerCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final sessionsAsync = ref.watch(serverSessionsProvider(widget.server.id));
    final connState = ref.watch(sshConnectionProvider(widget.server.id));
    final isConnected = connState.valueOrNull?.connected ?? false;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _expanded = !_expanded),
        onLongPress: () => _showServerDetail(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.dns,
                    color: isConnected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.server.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: isConnected ? Colors.green : Colors.grey,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isConnected ? 'Connected' : 'Disconnected',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: isConnected
                                        ? Colors.green[600]
                                        : Colors.grey[600],
                                  ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.play_circle_outline),
                    tooltip: 'New session',
                    onPressed: () => _showServerDetail(context),
                  ),
                  IconButton(
                    icon: Icon(_expanded
                        ? Icons.expand_less
                        : Icons.expand_more),
                    onPressed: () =>
                        setState(() => _expanded = !_expanded),
                  ),
                ],
              ),
              if (_expanded) ...[
                const Divider(height: 24),
                sessionsAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(8),
                    child: LinearProgressIndicator(),
                  ),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text('Error: $e',
                        style: TextStyle(color: Colors.red[400])),
                  ),
                  data: (sessions) {
                    if (sessions.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          'No active sessions. Tap play to start one.',
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                      );
                    }
                    return Column(
                      children: sessions
                          .map((s) => _SessionTile(
                                session: s,
                                server: widget.server,
                              ))
                          .toList(),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showServerDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _ServerDetailSheet(server: widget.server),
    );
  }
}

class _SessionTile extends ConsumerWidget {
  final Session session;
  final ServerConfig server;

  const _SessionTile({required this.session, required this.server});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusColor = switch (session.status) {
      SessionStatus.active => Colors.green,
      SessionStatus.connecting => Colors.orange,
      SessionStatus.disconnected => Colors.grey,
      SessionStatus.error => Colors.red,
    };

    return Dismissible(
      key: Key(session.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete Session'),
            content: Text('Delete "${session.title}"?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) {
        ref
            .read(serverSessionsProvider(server.id).notifier)
            .deleteSession(session.id);
      },
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: statusColor.withValues(alpha: 0.2),
          child: Icon(Icons.terminal, size: 16, color: statusColor),
        ),
        title: Text(session.title, style: const TextStyle(fontSize: 14)),
        subtitle: Text(
          _formatTime(session.lastActiveAt),
          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
        ),
        trailing: const Icon(Icons.chevron_right, size: 20),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SessionScreen(session: session, server: server),
            ),
          );
        },
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _ServerDetailSheet extends ConsumerStatefulWidget {
  final ServerConfig server;

  const _ServerDetailSheet({required this.server});

  @override
  ConsumerState<_ServerDetailSheet> createState() => _ServerDetailSheetState();
}

class _ServerDetailSheetState extends ConsumerState<_ServerDetailSheet> {
  bool _connecting = false;
  late final TextEditingController _workDirCtrl;

  @override
  void initState() {
    super.initState();
    _workDirCtrl = TextEditingController(text: widget.server.defaultWorkingDir);
  }

  @override
  void dispose() {
    _workDirCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cliToolsAsync = ref.watch(cliToolsProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollController) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: ListView(
            controller: scrollController,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.server.name,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${widget.server.username}@${widget.server.host}:${widget.server.port}',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              ConnectScreen(server: widget.server),
                        ),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_outlined),
                    tooltip: 'Copy server',
                    onPressed: () async {
                      final src = widget.server;
                      final copy = ServerConfig(
                        id: const Uuid().v4(),
                        name: '${src.name} (copy)',
                        host: src.host,
                        port: src.port,
                        username: src.username,
                        password: src.password,
                        privateKeyPath: src.privateKeyPath,
                        privateKeyContent: src.privateKeyContent,
                        passphrase: src.passphrase,
                        defaultWorkingDir: src.defaultWorkingDir,
                      );
                      await ref.read(serversProvider.notifier).addServer(copy);
                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Copied: ${copy.name}')),
                        );
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'Start New Session',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _workDirCtrl,
                decoration: InputDecoration(
                  labelText: 'Working Directory',
                  hintText: '~/projects/myapp',
                  prefixIcon: const Icon(Icons.folder_open, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  isDense: true,
                ),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
              ),
              const SizedBox(height: 12),
              cliToolsAsync.when(
                loading: () => const CircularProgressIndicator(),
                error: (e, _) => Text('Error: $e'),
                data: (tools) => Column(
                  children: tools.map((tool) {
                    return Card(
                      child: ListTile(
                        leading: Icon(_getToolIcon(tool.icon)),
                        title: Text(tool.name),
                        subtitle: Text(tool.description),
                        trailing: _connecting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.play_arrow),
                        onTap: _connecting
                            ? null
                            : () => _createSession(context, tool),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Text(
                    'Active Sessions',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Scan Remote'),
                    onPressed: () async {
                      await ref
                          .read(
                              serverSessionsProvider(widget.server.id).notifier)
                          .discoverRemote(widget.server);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildActiveSessions(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActiveSessions() {
    final sessionsAsync =
        ref.watch(serverSessionsProvider(widget.server.id));
    return sessionsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Text('Error: $e'),
      data: (sessions) {
        if (sessions.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Icon(Icons.inbox_outlined, size: 48, color: Colors.grey[400]),
                const SizedBox(height: 8),
                Text(
                  'No active sessions',
                  style: TextStyle(color: Colors.grey[500]),
                ),
                const SizedBox(height: 4),
                Text(
                  'Start one from the tools above',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
          );
        }
        return Column(
          children: sessions.map((s) {
            return Card(
              child: ListTile(
                leading: Icon(
                  s.status == SessionStatus.active
                      ? Icons.play_circle
                      : Icons.pause_circle,
                  color: s.status == SessionStatus.active
                      ? Colors.green
                      : Colors.grey,
                ),
                title: Text(s.title),
                subtitle: Text(
                  '${s.cliToolId} - ${_formatTime(s.lastActiveAt)}',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _deleteSession(s),
                ),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SessionScreen(
                        session: s,
                        server: widget.server,
                      ),
                    ),
                  );
                },
              ),
            );
          }).toList(),
        );
      },
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Future<void> _createSession(BuildContext context, CliTool tool) async {
    setState(() => _connecting = true);
    try {
      final connState =
          ref.read(sshConnectionProvider(widget.server.id));
      if (connState.valueOrNull == null ||
          !connState.valueOrNull!.connected) {
        await ref
            .read(sshConnectionProvider(widget.server.id).notifier)
            .connect(widget.server);
      }

      final workDir = _workDirCtrl.text.trim().isNotEmpty
          ? _workDirCtrl.text.trim()
          : null;

      final session = await ref
          .read(serverSessionsProvider(widget.server.id).notifier)
          .createSession(
            server: widget.server,
            cliTool: tool,
            workingDir: workDir,
          );

      if (context.mounted) {
        Navigator.pop(context);
        if (context.mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  SessionScreen(session: session, server: widget.server),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed: $e')),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _deleteSession(Session session) async {
    await ref
        .read(serverSessionsProvider(widget.server.id).notifier)
        .deleteSession(session.id);
  }

  IconData _getToolIcon(String icon) {
    switch (icon) {
      case 'smart_toy':
        return Icons.smart_toy;
      case 'code':
        return Icons.code;
      case 'pair_programming':
        return Icons.people;
      case 'terminal':
      default:
        return Icons.terminal;
    }
  }
}
