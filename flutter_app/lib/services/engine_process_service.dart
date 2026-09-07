import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Manages the Python sidecar backend via [Process.start].
///
/// Starts `python ../python_engine/app.py` (dev layout) so the Flutter
/// window owns the backend lifetime. Call [dispose] when the window
/// closes to ensure the child process is killed.
class EngineProcessService {
  Process? _process;
  final _logController = StreamController<String>.broadcast();

  Stream<String> get logs => _logController.stream;
  bool get isRunning => _process != null;

  /// Starts the backend. Tries `python`, then `python3`, then `.venv` paths.
  Future<void> start({String host = '127.0.0.1', int port = 8000}) async {
    if (_process != null) return;
    final candidates = <List<String>>[
      ['python', '../python_engine/app.py'],
      ['python3', '../python_engine/app.py'],
      ['..\\..\\.venv\\Scripts\\python.exe', '..\\..\\python_engine\\app.py'],
      ['../../.venv/bin/python', '../../python_engine/app.py'],
    ];
    Exception? lastError;
    for (final c in candidates) {
      try {
        _process = await Process.start(
          c[0],
          [...c.sublist(1), '--host', host, '--port', '$port'],
          runInShell: true,
        );
        _process!.stdout.transform(utf8.decoder).listen(_logController.add);
        _process!.stderr.transform(utf8.decoder).listen(_logController.add);
        unawaited(_process!.exitCode.then((_) => _process = null));
        return;
      } catch (e) {
        lastError = e is Exception ? e : Exception('$e');
      }
    }
    throw lastError ?? Exception('Could not start Python engine process.');
  }

  /// Kills the child process (SIGTERM, then SIGKILL fallback).
  Future<void> stop() async {
    final p = _process;
    _process = null;
    if (p == null) return;
    try {
      p.kill(ProcessSignal.sigterm);
      await p.exitCode.timeout(const Duration(seconds: 5));
    } catch (_) {
      try {
        p.kill(ProcessSignal.sigkill);
      } catch (_) {}
    }
  }

  /// Alias for [stop] + closing the log stream. Call from dispose().
  Future<void> dispose() async {
    await stop();
    await _logController.close();
  }
}
