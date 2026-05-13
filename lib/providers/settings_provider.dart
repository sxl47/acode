import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/server_config.dart';
import '../models/cli_tool.dart';
import '../models/command_group.dart';

final serversBoxProvider = FutureProvider<Box<ServerConfig>>((ref) async {
  return await Hive.openBox<ServerConfig>('servers');
});

final cliToolsBoxProvider = FutureProvider<Box<CliTool>>((ref) async {
  return await Hive.openBox<CliTool>('cli_tools');
});

final settingsBoxProvider = FutureProvider<Box>((ref) async {
  return await Hive.openBox('settings');
});

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    _loadTheme();
    return ThemeMode.dark;
  }

  Future<void> _loadTheme() async {
    try {
      final box = await ref.read(settingsBoxProvider.future);
      final savedTheme = box.get('themeMode', defaultValue: 'dark');
      state = savedTheme == 'light' ? ThemeMode.light : ThemeMode.dark;
    } catch (_) {
      state = ThemeMode.dark;
    }
  }

  Future<void> toggle() async {
    state = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    await _saveTheme();
  }

  Future<void> setTheme(ThemeMode mode) async {
    state = mode;
    await _saveTheme();
  }

  Future<void> _saveTheme() async {
    try {
      final box = await ref.read(settingsBoxProvider.future);
      await box.put('themeMode', state == ThemeMode.light ? 'light' : 'dark');
    } catch (_) {}
  }
}

final serversProvider =
    AsyncNotifierProvider<ServersNotifier, List<ServerConfig>>(
        ServersNotifier.new);

class ServersNotifier extends AsyncNotifier<List<ServerConfig>> {
  @override
  Future<List<ServerConfig>> build() async {
    final box = await ref.watch(serversBoxProvider.future);
    return box.values.toList();
  }

  Future<void> addServer(ServerConfig config) async {
    final box = await ref.read(serversBoxProvider.future);
    await box.put(config.id, config);
    ref.invalidateSelf();
  }

  Future<void> updateServer(ServerConfig config) async {
    final box = await ref.read(serversBoxProvider.future);
    await box.put(config.id, config);
    ref.invalidateSelf();
  }

  Future<void> deleteServer(String id) async {
    final box = await ref.read(serversBoxProvider.future);
    await box.delete(id);
    ref.invalidateSelf();
  }
}

final cliToolsProvider =
    AsyncNotifierProvider<CliToolsNotifier, List<CliTool>>(CliToolsNotifier.new);

class CliToolsNotifier extends AsyncNotifier<List<CliTool>> {
  @override
  Future<List<CliTool>> build() async {
    final box = await ref.watch(cliToolsBoxProvider.future);
    if (box.isEmpty) {
      for (final tool in CliTool.defaults()) {
        await box.put(tool.id, tool);
      }
    }
    return box.values.toList()
      ..sort((a, b) {
        const defaultOrder = ['generic', 'claude', 'opencode', 'aider'];
        final ia = defaultOrder.indexOf(a.id);
        final ib = defaultOrder.indexOf(b.id);
        if (ia == -1 && ib == -1) return a.name.compareTo(b.name);
        if (ia == -1) return 1;
        if (ib == -1) return -1;
        return ia.compareTo(ib);
      });
  }

  Future<void> addTool(CliTool tool) async {
    final box = await ref.read(cliToolsBoxProvider.future);
    await box.put(tool.id, tool);
    ref.invalidateSelf();
  }

  Future<void> updateTool(CliTool tool) async {
    final box = await ref.read(cliToolsBoxProvider.future);
    await box.put(tool.id, tool);
    ref.invalidateSelf();
  }

  Future<void> deleteTool(String id) async {
    final box = await ref.read(cliToolsBoxProvider.future);
    await box.delete(id);
    ref.invalidateSelf();
  }
}

final quickInputGroupsBoxProvider =
    FutureProvider<Box<CommandGroup>>((ref) async {
  return await Hive.openBox<CommandGroup>('quick_input_groups');
});

final quickInputGroupsProvider = AsyncNotifierProvider<
    QuickInputGroupsNotifier, List<CommandGroup>>(
    QuickInputGroupsNotifier.new);

class QuickInputGroupsNotifier extends AsyncNotifier<List<CommandGroup>> {
  @override
  Future<List<CommandGroup>> build() async {
    final box = await ref.watch(quickInputGroupsBoxProvider.future);
    if (box.isEmpty) {
      for (final group in CommandGroup.defaults()) {
        await box.put(group.id, group);
      }
    }
    return box.values.toList();
  }

  Future<void> addGroup(CommandGroup group) async {
    final box = await ref.read(quickInputGroupsBoxProvider.future);
    await box.put(group.id, group);
    ref.invalidateSelf();
  }

  Future<void> updateGroup(CommandGroup group) async {
    final box = await ref.read(quickInputGroupsBoxProvider.future);
    await box.put(group.id, group);
    ref.invalidateSelf();
  }

  Future<void> deleteGroup(String id) async {
    final box = await ref.read(quickInputGroupsBoxProvider.future);
    await box.delete(id);
    ref.invalidateSelf();
  }
}

final clipboardHistoryProvider =
    NotifierProvider<ClipboardHistoryNotifier, List<String>>(
        ClipboardHistoryNotifier.new);

class ClipboardHistoryNotifier extends Notifier<List<String>> {
  static const _maxEntries = 20;

  @override
  List<String> build() {
    _load();
    return [];
  }

  Future<void> _load() async {
    try {
      final box = await ref.read(settingsBoxProvider.future);
      final stored = box.get('clipboard_history') as List?;
      if (stored != null) {
        state = stored.cast<String>();
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final box = await ref.read(settingsBoxProvider.future);
      await box.put('clipboard_history', state);
    } catch (_) {}
  }

  void add(String text) {
    state = [text, ...state.where((s) => s != text)];
    if (state.length > _maxEntries) {
      state = state.sublist(0, _maxEntries);
    }
    _save();
  }
}
