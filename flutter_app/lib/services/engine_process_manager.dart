import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'api_service.dart';
import 'model_download_service.dart';

enum EngineRunPhase { idle, starting, running, failed, external }

/// What the top bar shows about the local engine.
@immutable
class EngineStatus {
  final EngineRunPhase phase;

  /// Plain-words reason when [phase] is failed.
  final String? reason;
  const EngineStatus(this.phase, [this.reason]);

  String get label => switch (phase) {
        EngineRunPhase.starting => 'Engine starting…',
        EngineRunPhase.failed => 'Engine failed: ${reason ?? 'unknown error'}',
        EngineRunPhase.running || EngineRunPhase.external => 'Engine running',
        EngineRunPhase.idle => 'Engine not started',
      };
}

/// Manages the lifecycle of the bundled Python AI Engine sidecar.
///
/// The engine's output goes to `<app support>/logs/engine.log` (the previous
/// run is kept as engine.prev.log). A starting engine is never killed for being
/// slow; [status] says "starting" until it answers, and "failed: <reason>" if
/// the process exits or does not answer within [startupTimeout].
class EngineProcessManager {
  EngineProcessManager._();
  static final EngineProcessManager instance = EngineProcessManager._();

  /// Observable engine state for the UI.
  final ValueNotifier<EngineStatus> status = ValueNotifier(const EngineStatus(EngineRunPhase.idle));

  /// How long a starting engine may take to answer before it is reported as failed
  /// (it keeps running; first start can include loading large libraries).
  Duration startupTimeout = const Duration(minutes: 10);

  Process? _process;
  bool _spawnedByUs = false;
  IOSink? _logSink;
  File? _logFile;
  final List<String> _recentErrors = [];

  bool get isRunning => _process != null || _spawnedByUs;

  /// Where the engine's output is written (null until the first launch).
  File? get logFile => _logFile;

  Future<File> _openLog() async {
    final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'logs'));
    await dir.create(recursive: true);
    final log = File(p.join(dir.path, 'engine.log'));
    if (log.existsSync()) {
      try {
        log.renameSync(p.join(dir.path, 'engine.prev.log'));
      } catch (_) {}
    }
    return log;
  }

  void _logLine(String stream, String line) {
    debugPrint('[Engine $stream] $line');
    _logSink?.writeln('${DateTime.now().toIso8601String()} [$stream] $line');
    if (stream == 'stderr' && line.trim().isNotEmpty) {
      _recentErrors.add(line.trim());
      if (_recentErrors.length > 20) _recentErrors.removeAt(0);
    }
  }

  /// The most telling recent error line from the engine's output.
  String _failureReasonFromOutput(String fallback) {
    for (final line in _recentErrors.reversed) {
      if (RegExp(r'Error|Exception|FAIL|Traceback', caseSensitive: false).hasMatch(line)) {
        return line.length > 200 ? '${line.substring(0, 200)}…' : line;
      }
    }
    return fallback;
  }

  /// Returns true if the engine is reachable or was successfully started.
  Future<bool> ensureEngineRunning() async {
    // 1. Check if an engine is already running (e.g. manual dev server or remote).
    if (await _pingHealth()) {
      debugPrint('[EngineManager] Engine already running and healthy.');
      status.value = const EngineStatus(EngineRunPhase.external);
      return true;
    }
    status.value = const EngineStatus(EngineRunPhase.starting);
    // The engine loads models only from the folder the app downloads into.
    final modelsDir = ModelDownloadService.instance.getModelsBaseDirectory().absolute.path;

    // 2. Locate bundled engine executable relative to the Flutter app executable.
    final engineExe = _findEngineExecutable();
    if (engineExe != null && engineExe.existsSync()) {
      return _launchProcess(
        executable: engineExe.path,
        args: [],
        workingDir: engineExe.parent.path,
        environment: {
          'AI_STUDIO_MODELS_DIR': modelsDir,
          'HF_HUB_OFFLINE': '1',
          'PYTHONUNBUFFERED': '1',
        },
        isDev: false,
      );
    }

    // 3. In development mode (flutter run), locate python_engine source in monorepo
    final devScript = kDebugMode ? _findDevEngineScript() : null;
    if (devScript != null && devScript.existsSync()) {
      var pythonCmd = Platform.isWindows ? 'python' : 'python3';
      final venvCandidates = Platform.isWindows
          ? [
              p.join(devScript.parent.path, '.venv', 'Scripts', 'python.exe'),
              p.join(devScript.parent.parent.path, '.venv', 'Scripts', 'python.exe'),
            ]
          : [
              p.join(devScript.parent.path, '.venv', 'bin', 'python'),
              p.join(devScript.parent.parent.path, '.venv', 'bin', 'python'),
            ];
      for (final venv in venvCandidates) {
        if (File(venv).existsSync()) {
          pythonCmd = venv;
          debugPrint('[EngineManager] Using dedicated virtual environment: $venv');
          break;
        }
      }

      return _launchProcess(
        executable: pythonCmd,
        args: [devScript.path],
        workingDir: devScript.parent.path,
        environment: {
          'AI_STUDIO_MOCK': '1',
          'AI_STUDIO_MODELS_DIR': modelsDir,
          'PYTHONUNBUFFERED': '1',
        },
        isDev: true,
      );
    }

    debugPrint(
      '[EngineManager] No bundled engine or dev python_engine found. Assuming remote or external server.',
    );
    status.value = const EngineStatus(EngineRunPhase.failed, 'the engine is not installed next to the app');
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
      try {
        _logFile = await _openLog();
        _logSink = _logFile!.openWrite(mode: FileMode.write);
        _logSink!.writeln('=== ${DateTime.now().toIso8601String()} launching $executable ${args.join(' ')} ===');
      } catch (e) {
        debugPrint('[EngineManager] Could not open the engine log: $e');
      }
      _recentErrors.clear();

      _process = await Process.start(
        executable,
        args,
        workingDirectory: workingDir,
        environment: environment,
      );
      _spawnedByUs = true;

      _process!.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen((line) => _logLine('stdout', line));
      _process!.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen((line) => _logLine('stderr', line));

      var exited = false;
      _process!.exitCode.then((code) {
        exited = true;
        debugPrint('[EngineManager] Engine process exited with code $code');
        _logSink?.writeln('=== engine exited with code $code ===');
        _process = null;
        _spawnedByUs = false;
        if (status.value.phase != EngineRunPhase.idle) {
          status.value = EngineStatus(
            EngineRunPhase.failed,
            _failureReasonFromOutput('the engine stopped (exit code $code)'),
          );
        }
      });

      // 4. Wait for the engine to answer. A slow start is not a failure: the
      //    process is never killed here.
      final deadline = DateTime.now().add(startupTimeout);
      while (DateTime.now().isBefore(deadline) && !exited) {
        if (await _pingHealth()) {
          debugPrint('[EngineManager] Engine initialized and healthy!');
          status.value = const EngineStatus(EngineRunPhase.running);
          return true;
        }
        await Future.delayed(const Duration(seconds: 1));
      }
      if (!exited) {
        status.value = EngineStatus(
          EngineRunPhase.failed,
          'no answer after ${startupTimeout.inMinutes} minutes (still running; see the engine log)',
        );
      }
      return false;
    } catch (e) {
      debugPrint('[EngineManager] Failed to spawn engine: $e');
      status.value = EngineStatus(EngineRunPhase.failed, 'could not start the engine ($e)');
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
    status.value = const EngineStatus(EngineRunPhase.idle);
  }

  /// Opens the engine log in the system's text viewer.
  Future<bool> openLog() async {
    final log = _logFile;
    if (log == null || !log.existsSync()) return false;
    try {
      if (Platform.isWindows) {
        await Process.start('notepad.exe', [log.path], mode: ProcessStartMode.detached);
      } else if (Platform.isMacOS) {
        await Process.start('open', [log.path], mode: ProcessStartMode.detached);
      } else {
        await Process.start('xdg-open', [log.path], mode: ProcessStartMode.detached);
      }
      return true;
    } catch (e) {
      debugPrint('[EngineManager] Could not open the engine log: $e');
      return false;
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
}
