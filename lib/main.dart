import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'app.dart';
import 'models/adapters.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();
  Hive.registerAdapter(ServerConfigAdapter());
  Hive.registerAdapter(CliToolAdapter());
  Hive.registerAdapter(SessionStatusAdapter());
  Hive.registerAdapter(SessionAdapter());
  Hive.registerAdapter(MessageRoleAdapter());
  Hive.registerAdapter(ChatMessageAdapter());

  runApp(const ProviderScope(child: ACodeApp()));
}
