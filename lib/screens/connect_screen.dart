import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/server_config.dart';
import '../providers/settings_provider.dart';
import '../providers/ssh_provider.dart';

class ConnectScreen extends ConsumerStatefulWidget {
  final ServerConfig? server;

  const ConnectScreen({super.key, this.server});

  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _hostCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _userCtrl;
  late final TextEditingController _passCtrl;
  late final TextEditingController _keyCtrl;
  late final TextEditingController _dirCtrl;

  bool _useKeyAuth = false;
  bool _testing = false;
  bool _showPassword = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    final s = widget.server;
    _nameCtrl = TextEditingController(text: s?.name ?? '');
    _hostCtrl = TextEditingController(text: s?.host ?? '');
    _portCtrl = TextEditingController(text: s?.port.toString() ?? '22');
    _userCtrl = TextEditingController(text: s?.username ?? '');
    _passCtrl = TextEditingController(text: s?.password ?? '');
    _keyCtrl = TextEditingController(text: s?.privateKeyContent ?? '');
    _dirCtrl = TextEditingController(text: s?.defaultWorkingDir ?? '~');
    _useKeyAuth = s?.useKeyAuth ?? false;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _keyCtrl.dispose();
    _dirCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.server != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Server' : 'Add Server'),
        actions: [
          if (isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: _deleteServer,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Server Name',
                hintText: 'My Server',
                prefixIcon: Icon(Icons.label_outline),
                border: OutlineInputBorder(),
              ),
              validator: (v) => v == null || v.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _hostCtrl,
              decoration: const InputDecoration(
                labelText: 'Host',
                hintText: '192.168.1.100 or example.com',
                prefixIcon: Icon(Icons.dns_outlined),
                border: OutlineInputBorder(),
              ),
              validator: (v) => v == null || v.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _portCtrl,
              decoration: const InputDecoration(
                labelText: 'Port',
                hintText: '22',
                prefixIcon: Icon(Icons.numbers),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              validator: (v) {
                if (v == null || v.isEmpty) return 'Required';
                final port = int.tryParse(v);
                if (port == null || port < 1 || port > 65535) {
                  return 'Invalid port';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _userCtrl,
              decoration: const InputDecoration(
                labelText: 'Username',
                hintText: 'root',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
              validator: (v) => v == null || v.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Use SSH Key Authentication'),
              value: _useKeyAuth,
              onChanged: (v) => setState(() => _useKeyAuth = v),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: Colors.grey[300]!),
              ),
            ),
            const SizedBox(height: 16),
            if (!_useKeyAuth)
              TextFormField(
                controller: _passCtrl,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showPassword ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                  ),
                ),
                obscureText: !_showPassword,
              )
            else
              TextFormField(
                controller: _keyCtrl,
                decoration: const InputDecoration(
                  labelText: 'Private Key (PEM)',
                  hintText: 'Paste your SSH private key here',
                  prefixIcon: Icon(Icons.key),
                  border: OutlineInputBorder(),
                ),
                maxLines: 5,
              ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _dirCtrl,
              decoration: const InputDecoration(
                labelText: 'Default Working Directory',
                hintText: '~',
                prefixIcon: Icon(Icons.folder_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            if (_testResult != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _testResult!.startsWith('Success')
                      ? Colors.green[50]
                      : Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _testResult!.startsWith('Success')
                        ? Colors.green[300]!
                        : Colors.red[300]!,
                  ),
                ),
                child: Text(
                  _testResult!,
                  style: TextStyle(
                    color: _testResult!.startsWith('Success')
                        ? Colors.green[800]
                        : Colors.red[800],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _testing ? null : _testConnection,
                    child: _testing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Test Connection'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: FilledButton(
                    onPressed: _save,
                    child: Text(isEditing ? 'Update' : 'Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  ServerConfig _buildConfig() {
    return ServerConfig(
      id: widget.server?.id ?? const Uuid().v4(),
      name: _nameCtrl.text.trim(),
      host: _hostCtrl.text.trim(),
      port: int.parse(_portCtrl.text.trim()),
      username: _userCtrl.text.trim(),
      password: _useKeyAuth ? null : _passCtrl.text,
      privateKeyContent: _useKeyAuth ? _keyCtrl.text : null,
      defaultWorkingDir: _dirCtrl.text.trim().isEmpty
          ? '~'
          : _dirCtrl.text.trim(),
    );
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _testing = true;
      _testResult = null;
    });

    final config = _buildConfig();
    final ssh = ref.read(sshServiceProvider('test'));

    try {
      await ssh.connect(config);
      final result = await ssh.exec('echo "connected" && uname -a');
      await ssh.disconnect();
      setState(() {
        _testResult = 'Success: $result';
      });
    } catch (e) {
      setState(() {
        _testResult = 'Failed: $e';
      });
    } finally {
      setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final config = _buildConfig();
    final notifier = ref.read(serversProvider.notifier);

    if (widget.server != null) {
      await notifier.updateServer(config);
    } else {
      await notifier.addServer(config);
    }

    if (mounted) Navigator.pop(context);
  }

  Future<void> _deleteServer() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Server'),
        content: Text('Delete "${widget.server!.name}"?'),
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

    if (confirmed == true) {
      await ref.read(serversProvider.notifier).deleteServer(widget.server!.id);
      if (mounted) Navigator.pop(context);
    }
  }
}
