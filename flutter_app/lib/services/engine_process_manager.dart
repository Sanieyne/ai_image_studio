import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'api_service.dart';

/// Manages the lifecycle of the bundled Python AI Engine sidecar.
class EngineProcessManager {
  EngineProcessManager._();
  static final EngineProcessManager instance = EngineProcessManager._();

  Process? _process;
  bool _spawnedByUs = false;

  bool get isRunning => _process != null || _spawnedByUs;

  /// Returns true if the engine is reachable or was successfully started.
  Future<bool> ensureEngineRunning() async {
    // 1. Check if an engine is already running (e.g. manual dev server or remote).
    if (await _pingHealth()) {
      debugPrint('[EngineManager] Engine already running and healthy.');
      return true;
    }

    // 2. Locate bundled engine executable relative to the Flutter app executable.
    final engineExe = _findEngineExecutable();
    if (engineExe != null && engineExe.existsSync()) {
      return _launchProcess(
        executable: engineExe.path,
        args: [],
        workingDir: engineExe.parent.path,
        isDev: false,
      );
    }

    // 3. In development mode (flutter run), locate python_engine source in monorepo
    final devScript = _findDevEngineScript();
    if (devScript != null && devScript.existsSync()) {
      final pythonCmd = Platform.isWindows ? 'python' : 'python3';
      return _launchProcess(
        executable: pythonCmd,
        args: [devScript.path],
        workingDir: devScript.parent.path,
        environment: {
          'AI_STUDIO_MOCK': '1',
          'PYTHONUNBUFFERED': '1',
        },
        isDev: true,
      );
    }

    debugPrint(
      '[EngineManager] No bundled engine or dev python_engine found. Assuming remote or external server.',
    );
    return false;
  }

  Future<bool> _launchProcess({
    required String executable,
    required List<String> args,
    required String workingDir,
    Map<String, String>? environment,
    required bool isDev,
  }) async {
    try {
      debugPrint('[EngineManager] Launching ${isDev ? 'dev' : 'bundled'} engine: $executable ${args.join(' ')}');
      _process = await Process.start(
        executable,
        args,
        workingDirectory: workingDir,
        environment: environment,
      );
      _spawnedByUs = true;

      // Pipe logs for diagnostics
      _process!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => debugPrint('[Engine stdout] $line'));

      _process!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => debugPrint('[Engine stderr] $line'));

      _process!.exitCode.then((code) {
        debugPrint('[EngineManager] Engine process exited with code $code');
        _process = null;
        _spawnedByUs = false;
      });

      // 4. Poll health endpoint until engine is ready (up to 30 seconds).
      final ready = await _pollHealth(timeout: const Duration(seconds: 30));
      if (ready) {
        debugPrint('[EngineManager] Engine initialized and healthy!');
        return true;
      } else {
        debugPrint('[EngineManager] Engine failed health check within timeout.');
        stopEngine();
        return false;
      }
    } catch (e) {
      debugPrint('[EngineManager] Failed to spawn engine: $e');
      return false;
    }
  }

  /// Gracefully terminates the child engine process.
  void stopEngine() {
    if (_process != null && _spawnedByUs) {
      debugPrint('[EngineManager] Terminating engine process...');
      try {
        _process!.kill(ProcessSignal.sigterm);
      } catch (_) {
        _process!.kill();
      }
      _process = null;
      _spawnedByUs = false;
    }
  }

  File? _findEngineExecutable() {
    try {
      final exePath = Platform.resolvedExecutable;
      final appDir = p.dirname(exePath);

      // On Windows: appDir/engine/engine.exe
      // On Linux:   appDir/engine/engine
      final binaryName = Platform.isWindows ? 'engine.exe' : 'engine';

      // Check standard bundle location
      var candidate = File(p.join(appDir, 'engine', binaryName));
      if (candidate.existsSync()) return candidate;

      // Check adjacent directory
      candidate = File(p.join(appDir, binaryName));
      if (candidate.existsSync()) return candidate;

      return candidate;
    } catch (e) {
      debugPrint('[EngineManager] Error resolving executable path: $e');
      return null;
    }
  }

  File? _findDevEngineScript() {
    try {
      final exePath = Platform.resolvedExecutable;
      var dir = Directory(p.dirname(exePath));

      // Walk up directories from the build bundle output to find the monorepo root
      for (int i = 0; i < 7; i++) {
        final script = File(p.join(dir.path, 'python_engine', 'launcher.py'));
        if (script.existsSync()) return script;

        final candidateInDir = File(p.join(dir.path, 'launcher.py'));
        if (candidateInDir.existsSync()) return candidateInDir;

        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }

      // Check relative to current working directory as well
      final cwdCandidates = [
        File(p.join(Directory.current.path, '..', 'python_engine', 'launcher.py')),
        File(p.join(Directory.current.path, 'python_engine', 'launcher.py')),
        File(p.join(Directory.current.path, 'launcher.py')),
      ];

      for (final candidate in cwdCandidates) {
        if (candidate.existsSync()) return candidate;
      }

      return null;
    } catch (e) {
      debugPrint('[EngineManager] Error searching for dev python engine: $e');
      return null;
    }
  }

  Future<bool> _pingHealth() async {
    try {
      final api = ApiService();
      return await api.checkHealth();
    } catch (_) {
      return false;
    }
  }

  Future<bool> _pollHealth({required Duration timeout}) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await _pingHealth()) return true;
      await Future.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }
}
