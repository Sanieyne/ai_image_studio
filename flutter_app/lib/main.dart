import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'screens/home_screen.dart';
import 'services/database_service.dart';
import 'services/engine_process_manager.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Desktop Linux / macOS / Windows SQLite binding.
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Initialize DB tables before the UI boots.
  await DatabaseService.instance.init();

  // Launch local AI Engine sidecar in the background if bundled.
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    unawaited(EngineProcessManager.instance.ensureEngineRunning());
  }

  runApp(const AiImageStudioApp());
}

class AiImageStudioApp extends StatefulWidget {
  const AiImageStudioApp({super.key});

  @override
  State<AiImageStudioApp> createState() => _AiImageStudioAppState();
}

class _AiImageStudioAppState extends State<AiImageStudioApp> {
  ThemeMode _mode = ThemeMode.dark;

  void _toggleTheme() {
    setState(() {
      _mode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lumina AI — Creative Studio',
      debugShowCheckedModeBanner: false,
      theme: LuminaTheme.light,
      darkTheme: LuminaTheme.dark,
      themeMode: _mode,
      home: HomeScreen(
        isDark: _mode == ThemeMode.dark,
        onThemeToggle: _toggleTheme,
      ),
    );
  }
}
