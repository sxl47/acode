import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/server_config.dart';
import '../models/cli_tool.dart';

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
    return box.values.toList();
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
