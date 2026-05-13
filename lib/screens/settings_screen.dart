import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/cli_tool.dart';
import '../providers/settings_provider.dart';
import 'about_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          _buildSection(
            context,
            title: 'CLI Tools',
            icon: Icons.terminal,
            child: _CliToolsList(),
          ),
          _buildSection(
            context,
            title: 'About',
            icon: Icons.info_outline,
            child: ListTile(
              title: const Text('ACode'),
              subtitle: const Text('Version 1.0.0'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AboutScreen()),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Row(
            children: [
              Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
        ),
        child,
      ],
    );
  }
}

class _CliToolsList extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toolsAsync = ref.watch(cliToolsProvider);

    return toolsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (tools) {
        return Column(
          children: [
            ...tools.map((tool) => _CliToolTile(tool: tool)),
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('Add Custom CLI Tool'),
              onTap: () => _showAddToolDialog(context, ref),
            ),
          ],
        );
      },
    );
  }

  void _showAddToolDialog(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController();
    final cmdCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add CLI Tool'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Display Name',
                hintText: 'My Tool',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: cmdCtrl,
              decoration: const InputDecoration(
                labelText: 'Command',
                hintText: 'my-tool',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (nameCtrl.text.isNotEmpty && cmdCtrl.text.isNotEmpty) {
                final tool = CliTool(
                  id: const Uuid().v4(),
                  name: nameCtrl.text.trim(),
                  command: cmdCtrl.text.trim(),
                  description: descCtrl.text.trim(),
                );
                ref.read(cliToolsProvider.notifier).addTool(tool);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

class _CliToolTile extends ConsumerWidget {
  final CliTool tool;

  const _CliToolTile({required this.tool});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: Icon(_getIcon(tool.icon)),
      title: Text(tool.name),
      subtitle: Text('${tool.command}${tool.description.isNotEmpty ? ' - ${tool.description}' : ''}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (tool.supportsImages)
            Chip(
              label: const Text('Images', style: TextStyle(fontSize: 11)),
              padding: EdgeInsets.zero,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: () => _showEditDialog(context, ref, tool),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
            onPressed: () => _confirmDelete(context, ref, tool),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(BuildContext context, WidgetRef ref, CliTool tool) {
    final nameCtrl = TextEditingController(text: tool.name);
    final cmdCtrl = TextEditingController(text: tool.command);
    final descCtrl = TextEditingController(text: tool.description);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit CLI Tool'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Display Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: cmdCtrl,
              decoration: const InputDecoration(labelText: 'Command'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              tool.name = nameCtrl.text.trim();
              tool.command = cmdCtrl.text.trim();
              tool.description = descCtrl.text.trim();
              ref.read(cliToolsProvider.notifier).updateTool(tool);
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, CliTool tool) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Tool'),
        content: Text('Delete "${tool.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              ref.read(cliToolsProvider.notifier).deleteTool(tool.id);
              Navigator.pop(ctx);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  IconData _getIcon(String icon) {
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
