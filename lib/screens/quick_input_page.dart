import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/command_group.dart';
import '../providers/settings_provider.dart';

class QuickInputPage extends ConsumerStatefulWidget {
  final void Function(String text) onSend;

  const QuickInputPage({
    super.key,
    required this.onSend,
  });

  @override
  ConsumerState<QuickInputPage> createState() => _QuickInputPageState();
}

class _QuickInputPageState extends ConsumerState<QuickInputPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _lastTabLength = 1;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 1, vsync: this);
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _onDataLoaded(List<CommandGroup> groups) {
    final newLength = 1 + groups.length;
    if (newLength != _lastTabLength) {
      _lastTabLength = newLength;
      final index = _tabController.index;
      // Defer controller rebuild to avoid side effects during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _tabController.dispose();
        _tabController = TabController(
          length: newLength,
          vsync: this,
          initialIndex: index.clamp(0, newLength - 1),
        );
        _tabController.addListener(() => setState(() {}));
      });
    }
  }

  void _addGroup() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Command Group'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Group name',
            hintText: 'e.g. Kubernetes',
          ),
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                final id = 'custom_${DateTime.now().millisecondsSinceEpoch}';
                ref
                    .read(quickInputGroupsProvider.notifier)
                    .addGroup(CommandGroup(
                      id: id,
                      name: name,
                      commands: [],
                    ));
                Navigator.pop(ctx);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _editGroupName(CommandGroup group) {
    final controller = TextEditingController(text: group.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Group'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Group name'),
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                group.name = name;
                ref.read(quickInputGroupsProvider.notifier).updateGroup(group);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _deleteGroup(CommandGroup group) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Group'),
        content: Text('Delete "${group.name}" and all its commands?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              ref
                  .read(quickInputGroupsProvider.notifier)
                  .deleteGroup(group.id);
              Navigator.pop(ctx);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _addCommand(CommandGroup group) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add command to ${group.name}'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Command',
            hintText: 'e.g. kubectl get pods',
          ),
          autofocus: true,
          style: const TextStyle(fontFamily: 'monospace'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final cmd = controller.text.trim();
              if (cmd.isNotEmpty) {
                group.commands.add(cmd);
                ref.read(quickInputGroupsProvider.notifier).updateGroup(group);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _editCommand(CommandGroup group, int index) {
    final controller = TextEditingController(text: group.commands[index]);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Command'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Command'),
          autofocus: true,
          style: const TextStyle(fontFamily: 'monospace'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final cmd = controller.text.trim();
              if (cmd.isNotEmpty) {
                group.commands[index] = cmd;
                ref.read(quickInputGroupsProvider.notifier).updateGroup(group);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _deleteCommand(CommandGroup group, int index) {
    group.commands.removeAt(index);
    ref.read(quickInputGroupsProvider.notifier).updateGroup(group);
  }

  void _sendAndClose(String text) {
    widget.onSend(text);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(quickInputGroupsProvider);

    return groupsAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Quick Input')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (err, _) => Scaffold(
        appBar: AppBar(title: const Text('Quick Input')),
        body: Center(child: Text('Error: $err')),
      ),
      data: (groups) {
        _onDataLoaded(groups);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Quick Input'),
            actions: [
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'New command group',
                onPressed: _addGroup,
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                const Tab(text: 'Clipboard'),
                ...groups.map((g) => Tab(text: g.name)),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildClipboardTab(),
              ...groups.map((g) => _buildGroupTab(g)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildClipboardTab() {
    final history = ref.watch(clipboardHistoryProvider);
    if (history.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.content_paste_off, size: 48, color: Colors.grey[600]),
            const SizedBox(height: 16),
            Text('No clipboard history',
                style: TextStyle(color: Colors.grey[500])),
          ],
        ),
      );
    }
    return ListView.builder(
      itemCount: history.length,
      itemBuilder: (context, index) {
        return ListTile(
          leading: const Icon(Icons.content_paste, size: 20),
          title: Text(
            history[index],
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
          ),
          onTap: () => _sendAndClose(history[index]),
        );
      },
    );
  }

  Widget _buildGroupTab(CommandGroup group) {
    return Column(
      children: [
        // Header with edit/delete buttons
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(
            children: [
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.edit, size: 18),
                tooltip: 'Rename group',
                onPressed: () => _editGroupName(group),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                tooltip: 'Delete group',
                onPressed: () => _deleteGroup(group),
              ),
            ],
          ),
        ),
        // Command list
        Expanded(
          child: group.commands.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('No commands in ${group.name}',
                          style: TextStyle(color: Colors.grey[500])),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () => _addCommand(group),
                        icon: const Icon(Icons.add),
                        label: const Text('Add command'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: group.commands.length,
                  itemBuilder: (context, index) {
                    return ListTile(
                      leading: const Icon(Icons.terminal, size: 20),
                      title: Text(
                        group.commands[index],
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 14),
                      ),
                      trailing: PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, size: 18),
                        onSelected: (action) {
                          switch (action) {
                            case 'copy':
                              Clipboard.setData(ClipboardData(
                                  text: group.commands[index]));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Copied'),
                                    duration: Duration(seconds: 1)),
                              );
                            case 'edit':
                              _editCommand(group, index);
                            case 'delete':
                              _deleteCommand(group, index);
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'copy',
                            child: ListTile(
                              leading: Icon(Icons.copy, size: 18),
                              title: Text('Copy'),
                              dense: true,
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'edit',
                            child: ListTile(
                              leading: Icon(Icons.edit, size: 18),
                              title: Text('Edit'),
                              dense: true,
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: ListTile(
                              leading: Icon(Icons.delete_outline,
                                  size: 18, color: Colors.red),
                              title: Text('Delete',
                                  style: TextStyle(color: Colors.red)),
                              dense: true,
                            ),
                          ),
                        ],
                      ),
                      onTap: () => _sendAndClose(group.commands[index]),
                    );
                  },
                ),
        ),
        // Bottom add button
        Padding(
          padding: const EdgeInsets.all(8),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _addCommand(group),
              icon: const Icon(Icons.add),
              label: const Text('Add Command'),
            ),
          ),
        ),
      ],
    );
  }
}
