import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const _dependencies = [
    ('Flutter SDK', 'flutter'),
    ('dartssh2', 'SSH client'),
    ('flutter_riverpod', 'State management'),
    ('hive / hive_flutter', 'Local persistence'),
    ('xterm', 'Terminal emulator'),
    ('image_picker', 'Image selection'),
    ('google_fonts', 'Custom fonts'),
    ('uuid', 'Unique IDs'),
    ('path_provider', 'File paths'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final onSurface = theme.colorScheme.onSurface;

    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        children: [
          // Header
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  primary.withValues(alpha: 0.15),
                  primary.withValues(alpha: 0.05),
                ],
              ),
            ),
            padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
            child: Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(Icons.terminal, size: 40, color: primary),
                ),
                const SizedBox(height: 16),
                Text(
                  'ACode',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Version 1.0.0+1',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Remote CLI coding sessions over SSH.\nManage servers, run AI coding tools, '
                  'all from your phone or desktop.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Open Source
          _buildSection(
            context,
            title: 'Open Source',
            children: [
              _InfoTile(
                icon: Icons.code,
                label: 'GitHub',
                value: 'github.com/sxl47/acode',
                onTap: () {
                  Clipboard.setData(
                      const ClipboardData(text: 'https://github.com/sxl47/acode'));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Link copied to clipboard'),
                        duration: Duration(seconds: 2)),
                  );
                },
              ),
              _InfoTile(
                icon: Icons.description,
                label: 'License',
                value: 'MIT',
                onTap: () {
                  Clipboard.setData(const ClipboardData(text: 'MIT'));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('License copied to clipboard'),
                        duration: Duration(seconds: 2)),
                  );
                },
              ),
            ],
          ),

          // Contact
          _buildSection(
            context,
            title: 'Contact',
            children: [
              _InfoTile(
                icon: Icons.email,
                label: 'Email',
                value: 'sxl47@126.com',
                onTap: () {
                  Clipboard.setData(
                      const ClipboardData(text: 'sxl47@126.com'));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Email copied to clipboard'),
                        duration: Duration(seconds: 2)),
                  );
                },
              ),
            ],
          ),

          // Dependencies
          _buildSection(
            context,
            title: 'Dependencies',
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _dependencies.map<Widget>((dep) {
                    return Chip(
                      avatar: Icon(Icons.widgets_outlined,
                          size: 16, color: primary),
                      label: Text(dep.$1,
                          style: const TextStyle(fontSize: 12)),
                      side: BorderSide(
                          color: primary.withValues(alpha: 0.3)),
                      backgroundColor:
                          primary.withValues(alpha: 0.08),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),

          const SizedBox(height: 32),
          Center(
            child: Text(
              'Built with Flutter & Dart',
              style: theme.textTheme.bodySmall?.copyWith(
                color: onSurface.withValues(alpha: 0.4),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        ...children,
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, color: theme.colorScheme.primary, size: 22),
      title: Text(label, style: const TextStyle(fontSize: 13)),
      subtitle: Text(
        value,
        style: TextStyle(
          fontSize: 15,
          color: theme.colorScheme.onSurface,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: const Icon(Icons.copy, size: 18),
      onTap: onTap,
    );
  }
}
