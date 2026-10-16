import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'screens/downloads_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'services/auth_service.dart';
import 'services/database_service.dart';
import 'services/engine_process_manager.dart';
import 'theme/app_theme.dart';
import 'widgets/top_bar.dart';

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
      title: 'Cosmic-Gen AI — Creative Studio',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        dragDevices: {
          PointerDeviceKind.mouse,
          PointerDeviceKind.touch,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.stylus,
        },
      ),
      theme: LuminaTheme.light,
      darkTheme: LuminaTheme.dark,
      themeMode: _mode,
      home: Platform.environment['DIRECT_SCREEN'] == 'downloads'
          ? Scaffold(
              backgroundColor: LuminaColors.darkBg,
              body: Column(
                children: [
                  TopBar(
                    engineOnline: true,
                    cloudOnline: false,
                    credits: 2450,
                    isDark: _mode == ThemeMode.dark,
                    onThemeToggle: _toggleTheme,
                    workspaceLabel: 'Neural Inference Hub',
                  ),
                  const Expanded(child: DownloadsScreen()),
                ],
              ),
            )
          : AuthGate(
              isDark: _mode == ThemeMode.dark,
              onThemeToggle: _toggleTheme,
            ),
    );
  }
}

/// App-wide login gate: nothing (including local/offline generation) is
/// reachable without a session, per product direction.
///
/// Flow: splash → silent session restore (refresh + profile load) →
/// [HomeScreen] on success, login/register on failure. Observes
/// [AuthService] so logout (explicit or via failed refresh) returns here
/// without any navigation plumbing. [HomeScreen] is never built before
/// the session check resolves, so it can't flash on a cold start.
class AuthGate extends StatefulWidget {
  final bool isDark;
  final VoidCallback onThemeToggle;

  const AuthGate({
    super.key,
    required this.isDark,
    required this.onThemeToggle,
  });

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _showRegister = false;

  @override
  void initState() {
    super.initState();
    unawaited(AuthService.instance.restoreSession());
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AuthService.instance,
      builder: (context, _) {
        switch (AuthService.instance.status) {
          case AuthStatus.unknown:
            return const _AuthSplash();
          case AuthStatus.authenticated:
            return HomeScreen(
              isDark: widget.isDark,
              onThemeToggle: widget.onThemeToggle,
            );
          case AuthStatus.unauthenticated:
            if (_showRegister) {
              return RegisterScreen(
                onShowLogin: () => setState(() => _showRegister = false),
              );
            }
            return LoginScreen(
              onShowRegister: () => setState(() => _showRegister = true),
            );
        }
      },
    );
  }
}

/// Brief branded loading state while the stored session is validated.
class _AuthSplash extends StatelessWidget {
  const _AuthSplash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: LuminaColors.darkBg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 46,
              height: 46,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LuminaColors.primaryGradient,
                  borderRadius: BorderRadius.all(Radius.circular(14)),
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
            SizedBox(height: 18),
            Text(
              'Cosmic-Gen AI',
              style: TextStyle(
                color: LuminaColors.darkText,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 16),
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                valueColor: AlwaysStoppedAnimation<Color>(
                  LuminaColors.primaryEnd,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
