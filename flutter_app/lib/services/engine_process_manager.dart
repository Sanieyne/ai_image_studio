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
    if (engineExe == null || !engineExe.existsSync()) {
      debugPrint(
        '[EngineManager] No bundled engine found at: ${engineExe?.path}. Assuming remote or external server.',
      );
      return false;
    }

    // 3. Launch engine as a child process.
    try {
      debugPrint('[EngineManager] Launching engine: ${engineExe.path}');
      _process = await Process.start(
        engineExe.path,
        [],
        workingDirectory: engineExe.parent.path,
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
