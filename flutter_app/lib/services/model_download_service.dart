import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'api_client.dart';

enum ModelDownloadStatus {
  notDownloaded,
  checking,
  downloading,

  /// The connection dropped; retrying automatically. The .part file is kept.
  waitingForNetwork,

  /// Paused by the user; resume continues from the .part file.
  paused,
  verifying,
  downloaded,
  failed,
}

class ModelDownloadProgress {
  final String modelId;
  final ModelDownloadStatus status;
  final int downloadedBytes;
  final int totalBytes;
  final double percentage; // 0.0 to 1.0
  final String? currentFile;
  final String? errorMessage;

  const ModelDownloadProgress({
    required this.modelId,
    required this.status,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.percentage = 0.0,
    this.currentFile,
    this.errorMessage,
  });

  String get formattedProgress {
    final downMB = (downloadedBytes / (1024 * 1024)).toStringAsFixed(1);
    final totalMB = (totalBytes / (1024 * 1024)).toStringAsFixed(1);
    final pct = (percentage * 100).toStringAsFixed(1);
    return '$downMB MB / $totalMB MB ($pct%)';
  }
}

class InsufficientDiskSpaceException implements Exception {
  final int availableBytes;
  final int requiredBytes;

  InsufficientDiskSpaceException({
    required this.availableBytes,
    required this.requiredBytes,
  });

  @override
  String toString() {
    final availGB = (availableBytes / 1e9).toStringAsFixed(1);
    final reqGB = (requiredBytes / 1e9).toStringAsFixed(1);
    return 'Insufficient disk space: $availGB GB available, but $reqGB GB required.';
  }
}

/// A download that stopped because the user paused or cancelled it.
class _Interrupted implements Exception {
  final bool cancelled;
  const _Interrupted(this.cancelled);
}

/// A failure that retrying with the same URL will not fix.
class _Fatal implements Exception {
  final String message;
  const _Fatal(this.message);
  @override
  String toString() => message;
}

class _UrlExpired implements Exception {
  const _UrlExpired();
}

class _Job {
  bool pauseRequested = false;
  bool cancelRequested = false;
  http.Client? client;
  void abort() {
    client?.close();
    client = null;
  }
}

/// Downloads model weights from signed R2 URLs into the models folder.
///
/// Robust to bad networks: every file resumes from its `.part` file (Range
/// requests, appended only on a 206 answer), dropped connections and stalls
/// (no bytes for [stallTimeout]) are retried with backoff while the status says
/// "waiting for network", and expired links are replaced by fresh ones. Pause,
/// resume and cancel are supported, and unfinished downloads are remembered in
/// `<models>/.pending_downloads.json` so they can be resumed after a restart.
class ModelDownloadService {
  ModelDownloadService._()
      : _baseDirOverride = null,
        _fetchUrlsOverride = null,
        _clientFactory = http.Client.new,
        _freeSpaceOverride = null,
        stallTimeout = const Duration(seconds: 60),
        retryDelays = _defaultRetryDelays,
        maxNetworkRetries = 60;

  /// For tests: a temporary models folder, fake URL source and HTTP client,
  /// and short timings.
  @visibleForTesting
  ModelDownloadService.forTest({
    required Directory baseDir,
    required Future<Map<String, dynamic>> Function(String modelId) fetchUrls,
    http.Client Function()? clientFactory,
    Future<int?> Function()? freeSpace,
    this.stallTimeout = const Duration(seconds: 60),
    this.retryDelays = const [Duration(milliseconds: 10)],
    this.maxNetworkRetries = 20,
  })  : _baseDirOverride = baseDir,
        _fetchUrlsOverride = fetchUrls,
        _clientFactory = clientFactory ?? http.Client.new,
        _freeSpaceOverride = freeSpace;

  static final ModelDownloadService instance = ModelDownloadService._();

  static const _defaultRetryDelays = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 15),
    Duration(seconds: 30),
  ];

  final Directory? _baseDirOverride;
  final Future<Map<String, dynamic>> Function(String modelId)? _fetchUrlsOverride;
  final http.Client Function() _clientFactory;
  final Future<int?> Function()? _freeSpaceOverride;

  /// Reconnect when no bytes arrive for this long.
  final Duration stallTimeout;

  /// Backoff between retries after a network failure (the last value repeats).
  final List<Duration> retryDelays;

  /// Give up (keeping the .part files) after this many failures in a row.
  final int maxNetworkRetries;

  final ApiClient _apiClient = ApiClient();
  final Map<String, StreamController<ModelDownloadProgress>> _controllers = {};
  final Map<String, ModelDownloadProgress> _currentProgress = {};
  final Map<String, _Job> _jobs = {};

  /// Canonical mapping from various UI display names / aliases to catalog IDs
  static final Map<String, String> _idMapping = {
    'real-esrgan x4plus': 'realesrgan-x4plus',
    'realesrgan x4plus': 'realesrgan-x4plus',
    'realesrgan-x4plus': 'realesrgan-x4plus',
    'amd/realesrgan-x4plus': 'realesrgan-x4plus',
    'real-esrgan anime 6b': 'realesrgan-anime-6b',
    'fashn vton 1.5': 'fashn-vton-1.5',
    'fashn-vton-1.5': 'fashn-vton-1.5',
    'fashn-ai/fashn-vton-1.5': 'fashn-vton-1.5',
    'breeze tts 2': 'breeze-tts-2',
    'breeze-tts-2': 'breeze-tts-2',
    'breezeblue/breeze-tts-2': 'breeze-tts-2',
    'chatterbox tts': 'chatterbox-tts',
    'chatterbox multilingual v3': 'chatterbox-tts',
    'chatterbox multilingual': 'chatterbox-tts',
    'chatterbox-tts': 'chatterbox-tts',
    'resembleai/chatterbox': 'chatterbox-tts',
    'sdxl base 1.0': 'sdxl-base-1.0',
    'sdxl-base-1.0': 'sdxl-base-1.0',
    'stabilityai/stable-diffusion-xl-base-1.0': 'sdxl-base-1.0',
    'flux.1 kontext [dev]': 'flux-kontext-dev',
    'flux-kontext-dev': 'flux-kontext-dev',
    'black-forest-labs/flux.1-kontext-dev': 'flux-kontext-dev',
    'z-image turbo': 'z-image-turbo',
    'z-image-turbo': 'z-image-turbo',
    'tongyi-mai/z-image-turbo': 'z-image-turbo',
    'qwen-image 2.1': 'qwen-image-2.1',
    'qwen-image-2.1': 'qwen-image-2.1',
    'qwen/qwen-image-2.1': 'qwen-image-2.1',
    'wan 2.1 t2v 1.3b': 'wan-2.1-t2v-1.3b',
    'wan-2.1-t2v-1.3b': 'wan-2.1-t2v-1.3b',
    'wan 2.1 i2v 14b': 'wan-2.1-i2v-14b',
    'wan-2.1-i2v-14b': 'wan-2.1-i2v-14b',
    'wan 2.2 animate 14b': 'wan-2.2-animate-14b',
    'wan-2.2-animate-14b': 'wan-2.2-animate-14b',
    'minimax-h3 video+audio': 'minimax-h3',
    'minimax-h3': 'minimax-h3',
  };

  /// Normalizes a model identifier to its canonical catalog ID
  String normalizeModelId(String rawId) {
    final clean = rawId.trim().toLowerCase();
    return _idMapping[clean] ?? rawId.trim();
  }

  /// Base directory for models:
  /// Priorities:
  /// 1. /workspace/models (standard GPU/container workspace)
  /// 2. ~/models
  /// 3. ./models
  Directory getModelsBaseDirectory() {
    final override = _baseDirOverride;
    if (override != null) return override;
    final env = Platform.environment['AI_STUDIO_MODELS_DIR'];
    if (env != null && env.trim().isNotEmpty) {
      final dir = Directory(env.trim());
      try {
        dir.createSync(recursive: true);
      } catch (_) {}
      return dir;
    }
    final workspaceDir = Directory('/workspace/models');
    if (workspaceDir.existsSync()) return workspaceDir;

    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home != null && home.isNotEmpty) {
      final homeModels = Directory(p.join(home, 'models'));
      if (!homeModels.existsSync()) {
        try {
          homeModels.createSync(recursive: true);
        } catch (_) {}
      }
      if (homeModels.existsSync()) return homeModels;
    }

    final localDir = Directory('models');
    if (!localDir.existsSync()) {
      try {
        localDir.createSync(recursive: true);
      } catch (_) {}
    }
    return localDir;
  }

  /// Returns the specific directory where a model should reside
  Directory getModelDirectory(String rawModelId) {
    final canonicalId = normalizeModelId(rawModelId);
    final base = getModelsBaseDirectory();
    return Directory(p.join(base.path, canonicalId));
  }

  /// Checks if a model's weights already exist locally
  Future<bool> isModelDownloaded(String rawModelId) async {
    final canonicalId = normalizeModelId(rawModelId);
    final dir = getModelDirectory(canonicalId);
    if (!dir.existsSync()) {
      // Check common fallback locations
      if (canonicalId == 'realesrgan-x4plus') {
        final alt1 = File('/workspace/models/realesrgan/RealESRGAN_x4plus.pth');
        final alt2 = File('/root/models/realesrgan/RealESRGAN_x4plus.pth');
        final alt3 = File(p.join(Platform.environment['HOME'] ?? '', '.cache/realesrgan/RealESRGAN_x4plus.pth'));
        if (alt1.existsSync() || alt2.existsSync() || alt3.existsSync()) return true;
      }
      return false;
    }

    try {
      // An unfinished download (paused, failed, or the app was closed) is not downloaded.
      if ((await pendingDownloads()).contains(canonicalId)) return false;
      final entities = dir.listSync(recursive: true);
      final files = entities.whereType<File>().where((f) => !f.path.endsWith('.part')).toList();
      if (files.isEmpty) return false;

      // Ensure key weight files are not empty (size > 1MB)
      final hasRealWeights = files.any((f) => f.lengthSync() > 1024 * 1024);
      return hasRealWeights;
    } catch (e) {
      debugPrint('[ModelDownloadService] Error checking local files: $e');
      return false;
    }
  }

  /// Free space (bytes) on the drive holding the models folder, or null when
  /// it cannot be determined. Never guessed.
  Future<int?> getAvailableDiskSpace() async {
    final override = _freeSpaceOverride;
    if (override != null) return override();
    final base = getModelsBaseDirectory();
    try {
      if (Platform.isWindows) {
        // DriveInfo works without admin rights; the path's root is e.g. "C:\".
        final root = p.rootPrefix(base.absolute.path);
        final res = await Process.run('powershell', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          "[System.IO.DriveInfo]::new('$root').AvailableFreeSpace",
        ]);
        if (res.exitCode == 0) return int.tryParse(res.stdout.toString().trim());
      } else {
        final res = await Process.run('df', ['-k', base.path]);
        if (res.exitCode == 0) {
          final lines = res.stdout.toString().trim().split('\n');
          if (lines.length >= 2) {
            final parts = lines.last.split(RegExp(r'\s+'));
            if (parts.length >= 4) {
              final availKB = int.tryParse(parts[3]);
              if (availKB != null) return availKB * 1024;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[ModelDownloadService] Error checking disk space: $e');
    }
    return null;
  }

  /// Stream of download progress for a given model
  Stream<ModelDownloadProgress> watchProgress(String rawModelId) {
    final canonicalId = normalizeModelId(rawModelId);
    if (!_controllers.containsKey(canonicalId)) {
      _controllers[canonicalId] = StreamController<ModelDownloadProgress>.broadcast();
    }
    return _controllers[canonicalId]!.stream;
  }

  ModelDownloadProgress? getCurrentProgress(String rawModelId) {
    final canonicalId = normalizeModelId(rawModelId);
    return _currentProgress[canonicalId];
  }

  void _emitProgress(ModelDownloadProgress progress) {
    _currentProgress[progress.modelId] = progress;
    _controllers[progress.modelId]?.add(progress);
  }

  /// Fetches signed download URLs from the backend
  Future<Map<String, dynamic>> fetchDownloadUrls(String rawModelId, {String? authToken}) async {
    final canonicalId = normalizeModelId(rawModelId);
    try {
      final headers = authToken != null ? {'Authorization': 'Bearer $authToken'} : null;
      final res = await _apiClient.get(
        'models/$canonicalId/download-urls',
        auth: authToken == null,
        headers: headers,
      );
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        if (json['success'] == true && json['data'] != null) {
          return Map<String, dynamic>.from(json['data']);
        }
      }
      throw Exception('Server returned ${res.statusCode}: ${res.body}');
    } catch (e) {
      // Local dev fallback if cosmic-gen.com is not accessible
      try {
        final localUri = Uri.parse('http://localhost:5000/api/v1/models/$canonicalId/download-urls');
        final localReq = await http.get(
          localUri,
          headers: authToken != null ? {'Authorization': 'Bearer $authToken'} : null,
        );
        if (localReq.statusCode == 200) {
          final json = jsonDecode(localReq.body);
          if (json['success'] == true && json['data'] != null) {
            return Map<String, dynamic>.from(json['data']);
          }
        }
      } catch (_) {}
      debugPrint('[ModelDownloadService] Failed to fetch download URLs: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _fetchUrls(String canonicalId, String? authToken) {
    final override = _fetchUrlsOverride;
    if (override != null) return override(canonicalId);
    return fetchDownloadUrls(canonicalId, authToken: authToken);
  }

  /// Whether a download of [rawModelId] is running (or waiting for network).
  bool isActive(String rawModelId) => _jobs.containsKey(normalizeModelId(rawModelId));

  /// Pause a running download; the .part files stay and [downloadModel] resumes them.
  void pause(String rawModelId) {
    final job = _jobs[normalizeModelId(rawModelId)];
    if (job == null) return;
    job.pauseRequested = true;
    job.abort();
  }

  /// Cancel a download and delete its partial files.
  Future<void> cancel(String rawModelId) async {
    final id = normalizeModelId(rawModelId);
    final job = _jobs[id];
    if (job != null) {
      job.cancelRequested = true;
      job.abort();
    } else {
      await _discardPartial(id);
      _emitProgress(ModelDownloadProgress(modelId: id, status: ModelDownloadStatus.notDownloaded));
    }
  }

  Future<void> _discardPartial(String canonicalId) async {
    final dir = getModelDirectory(canonicalId);
    if (dir.existsSync()) {
      for (final f in dir.listSync(recursive: true).whereType<File>()) {
        if (f.path.endsWith('.part')) {
          try {
            f.deleteSync();
          } catch (_) {}
        }
      }
    }
    await _setPending(canonicalId, false);
  }

  File get _pendingFile => File(p.join(getModelsBaseDirectory().path, '.pending_downloads.json'));

  /// Models whose download started but did not finish (paused, failed or the
  /// app closed). Offer to resume these at startup.
  Future<List<String>> pendingDownloads() async {
    try {
      if (!_pendingFile.existsSync()) return const [];
      final list = jsonDecode(await _pendingFile.readAsString());
      return (list as List).map((e) => e.toString()).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _setPending(String canonicalId, bool pending) async {
    try {
      final set = (await pendingDownloads()).toSet();
      final changed = pending ? set.add(canonicalId) : set.remove(canonicalId);
      if (!changed) return;
      _pendingFile.parent.createSync(recursive: true);
      await _pendingFile.writeAsString(jsonEncode(set.toList()));
    } catch (e) {
      debugPrint('[ModelDownloadService] Could not update pending downloads: $e');
    }
  }

  /// A file entry's path inside the model folder; refuses absolute paths and `..`.
  static File safeTarget(Directory destDir, String filename) {
    final normalized = p.normalize(filename.replaceAll('\\', '/'));
    final target = p.normalize(p.join(destDir.absolute.path, normalized));
    if (p.isAbsolute(normalized) || !p.isWithin(destDir.absolute.path, target)) {
      throw _Fatal('Refusing to write "$filename" outside the model folder.');
    }
    return File(target);
  }

  /// Downloads a model end-to-end. Resumes partial files; survives dropped
  /// connections, stalls and expired links (see the class comment).
  Future<void> downloadModel(String rawModelId, {String? authToken}) async {
    final canonicalId = normalizeModelId(rawModelId);
    if (_jobs.containsKey(canonicalId)) return; // already running
    final job = _Job();
    _jobs[canonicalId] = job;
    _emitProgress(ModelDownloadProgress(modelId: canonicalId, status: ModelDownloadStatus.checking));

    var aggregate = 0;
    var totalBytes = 0;
    try {
      var data = await _fetchUrls(canonicalId, authToken);
      final files = List<Map<String, dynamic>>.from(
          (data['files'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
      totalBytes = (data['totalBytes'] as num?)?.toInt() ??
          files.fold<int>(0, (sum, f) => sum + ((f['size'] as num?)?.toInt() ?? 0));
      if (files.isEmpty) {
        throw _Fatal('No files available for model $canonicalId.');
      }

      final destDir = getModelDirectory(canonicalId);
      destDir.createSync(recursive: true);
      final targets = {for (final f in files) f['filename'] as String: safeTarget(destDir, f['filename'] as String)};

      // Bytes already on disk, complete files and partial ones alike.
      var remaining = 0;
      for (final f in files) {
        final size = (f['size'] as num).toInt();
        final target = targets[f['filename']]!;
        final part = File('${target.path}.part');
        if (target.existsSync() && target.lengthSync() == size) {
          aggregate += size;
        } else {
          final have = part.existsSync() ? math.min(part.lengthSync(), size) : 0;
          aggregate += have;
          remaining += size - have;
        }
      }

      final free = await getAvailableDiskSpace();
      if (free != null && free < remaining + 512 * 1024 * 1024) {
        throw InsufficientDiskSpaceException(availableBytes: free, requiredBytes: remaining);
      }

      await _setPending(canonicalId, true);
      void emit(ModelDownloadStatus status, {String? file, String? message}) => _emitProgress(ModelDownloadProgress(
            modelId: canonicalId,
            status: status,
            downloadedBytes: aggregate,
            totalBytes: totalBytes,
            percentage: totalBytes > 0 ? (aggregate / totalBytes).clamp(0.0, 1.0) : 0.0,
            currentFile: file,
            errorMessage: message,
          ));
      emit(ModelDownloadStatus.downloading);

      for (var i = 0; i < files.length; i++) {
        final f = files[i];
        final filename = f['filename'] as String;
        final size = (f['size'] as num).toInt();
        final target = targets[filename]!;
        if (target.existsSync() && target.lengthSync() == size) continue;

        var url = f['downloadUrl'] as String;
        var failures = 0;
        var refreshes = 0;
        var hashMismatches = 0;
        while (true) {
          if (job.cancelRequested) throw const _Interrupted(true);
          if (job.pauseRequested) throw const _Interrupted(false);
          try {
            await _fetchFile(
              job: job,
              url: url,
              target: target,
              expectedSize: size,
              onBytes: (n) {
                aggregate += n;
                if (n != 0) {
                  failures = 0;
                  refreshes = 0;
                }
                emit(ModelDownloadStatus.downloading, file: filename);
              },
            );
            final expectedSha = (f['sha256'] as String?)?.toLowerCase();
            final part = File('${target.path}.part');
            if (expectedSha != null && expectedSha.isNotEmpty) {
              emit(ModelDownloadStatus.verifying, file: filename);
              final actual = (await crypto.sha256.bind(part.openRead()).first).toString();
              if (actual != expectedSha) {
                // Corrupt: start this file again, once; then give up.
                aggregate -= part.lengthSync();
                part.deleteSync();
                hashMismatches += 1;
                if (hashMismatches > 1) throw _Fatal('Checksum mismatch for $filename (downloaded twice).');
                continue;
              }
            }
            if (target.existsSync()) target.deleteSync();
            part.renameSync(target.path);
            break;
          } on _UrlExpired {
            refreshes += 1;
            if (refreshes > 3) throw _Fatal('Download link for $filename keeps being refused.');
            data = await _fetchUrls(canonicalId, authToken);
            final fresh = (data['files'] as List? ?? const [])
                .map((e) => Map<String, dynamic>.from(e as Map))
                .where((e) => e['filename'] == filename)
                .toList();
            if (fresh.isEmpty) throw _Fatal('$filename is no longer offered for download.');
            url = fresh.first['downloadUrl'] as String;
          } on _Interrupted {
            rethrow;
          } on _Fatal {
            rethrow;
          } on InsufficientDiskSpaceException {
            rethrow;
          } catch (e) {
            if (job.cancelRequested || job.pauseRequested) continue; // loop top throws _Interrupted
            failures += 1;
            if (failures > maxNetworkRetries) {
              throw _Fatal('Network unavailable ($e). Partial files are kept; resume to continue.');
            }
            final delay = retryDelays[math.min(failures - 1, retryDelays.length - 1)];
            emit(ModelDownloadStatus.waitingForNetwork,
                file: filename, message: 'Waiting for network… retrying in ${delay.inSeconds > 0 ? '${delay.inSeconds} s' : 'a moment'}');
            await Future.delayed(delay);
            // The .part length is the truth for where to continue.
            aggregate = _bytesOnDisk(files, targets);
          }
        }
      }

      _setupEngineSymlinks(canonicalId, destDir);
      await _setPending(canonicalId, false);
      _emitProgress(ModelDownloadProgress(
        modelId: canonicalId,
        status: ModelDownloadStatus.downloaded,
        downloadedBytes: totalBytes,
        totalBytes: totalBytes,
        percentage: 1.0,
      ));
    } on _Interrupted catch (i) {
      if (i.cancelled) {
        await _discardPartial(canonicalId);
        _emitProgress(ModelDownloadProgress(modelId: canonicalId, status: ModelDownloadStatus.notDownloaded));
      } else {
        _emitProgress(ModelDownloadProgress(
          modelId: canonicalId,
          status: ModelDownloadStatus.paused,
          downloadedBytes: aggregate,
          totalBytes: totalBytes,
          percentage: totalBytes > 0 ? (aggregate / totalBytes).clamp(0.0, 1.0) : 0.0,
        ));
      }
    } catch (e) {
      debugPrint('[ModelDownloadService] Download error: $e');
      _emitProgress(ModelDownloadProgress(
        modelId: canonicalId,
        status: ModelDownloadStatus.failed,
        downloadedBytes: aggregate,
        totalBytes: totalBytes,
        percentage: totalBytes > 0 ? (aggregate / totalBytes).clamp(0.0, 1.0) : 0.0,
        errorMessage: e.toString(),
      ));
      rethrow;
    } finally {
      job.abort();
      _jobs.remove(canonicalId);
    }
  }

  int _bytesOnDisk(List<Map<String, dynamic>> files, Map<String, File> targets) {
    var total = 0;
    for (final f in files) {
      final size = (f['size'] as num).toInt();
      final target = targets[f['filename']]!;
      final part = File('${target.path}.part');
      if (target.existsSync() && target.lengthSync() == size) {
        total += size;
      } else if (part.existsSync()) {
        total += math.min(part.lengthSync(), size);
      }
    }
    return total;
  }

  /// One attempt at one file: continue the .part file from where it ends.
  /// Reports bytes through [onBytes] (negative when a .part file is reset).
  Future<void> _fetchFile({
    required _Job job,
    required String url,
    required File target,
    required int expectedSize,
    required void Function(int bytes) onBytes,
  }) async {
    target.parent.createSync(recursive: true);
    final part = File('${target.path}.part');
    var start = part.existsSync() ? part.lengthSync() : 0;
    if (start > expectedSize) {
      onBytes(-start);
      part.deleteSync();
      start = 0;
    }
    if (start == expectedSize) return;

    final client = _clientFactory();
    job.client = client;
    try {
      final request = http.Request('GET', Uri.parse(url));
      if (start > 0) request.headers['Range'] = 'bytes=$start-';
      final response = await client.send(request).timeout(const Duration(seconds: 30));
      final code = response.statusCode;

      if (code == 401 || code == 403 || code == 410) {
        await response.stream.drain<void>().catchError((_) {});
        throw const _UrlExpired();
      }
      if (code == 400) {
        final body = await response.stream.bytesToString().catchError((_) => '');
        if (RegExp('expired|AccessDenied|SignatureDoesNotMatch', caseSensitive: false).hasMatch(body)) {
          throw const _UrlExpired();
        }
        throw _Fatal('HTTP 400 while downloading ${p.basename(target.path)}');
      }
      if (code == 416) {
        // Nothing left to send for this range; let the size check decide.
        await response.stream.drain<void>().catchError((_) {});
        if (part.existsSync() && part.lengthSync() == expectedSize) return;
        onBytes(-start);
        part.deleteSync();
        throw const HttpException('Range not satisfiable; restarting the file');
      }
      if (code != 200 && code != 206) {
        await response.stream.drain<void>().catchError((_) {});
        if (code >= 500) throw HttpException('Server error $code');
        throw _Fatal('HTTP $code while downloading ${p.basename(target.path)}');
      }

      var append = false;
      if (code == 206) {
        final range = response.headers['content-range'] ?? '';
        final m = RegExp(r'bytes (\d+)-').firstMatch(range);
        append = m != null && int.parse(m.group(1)!) == start;
        if (!append) {
          await response.stream.drain<void>().catchError((_) {});
          onBytes(-start);
          if (part.existsSync()) part.deleteSync();
          throw const HttpException('Unexpected Content-Range; restarting the file');
        }
      } else if (start > 0) {
        // 200: the server ignored Range and is sending the whole file.
        onBytes(-start);
      }

      final sink = part.openWrite(mode: append ? FileMode.append : FileMode.write);
      try {
        await for (final chunk in response.stream.timeout(stallTimeout)) {
          sink.add(chunk);
          onBytes(chunk.length);
        }
      } finally {
        await sink.flush();
        await sink.close();
      }
      final have = part.lengthSync();
      if (have < expectedSize) throw HttpException('Connection ended early ($have of $expectedSize bytes)');
      if (have > expectedSize) {
        onBytes(-have);
        part.deleteSync();
        throw const HttpException('File larger than expected; restarting it');
      }
    } finally {
      client.close();
      if (identical(job.client, client)) job.client = null;
    }
  }

  /// Sets up backward-compatible symlinks / copies for local python pipelines
  void _setupEngineSymlinks(String canonicalId, Directory destDir) {
    try {
      if (canonicalId == 'realesrgan-x4plus') {
        final pth = File(p.join(destDir.path, 'RealESRGAN_x4plus.pth'));
        if (pth.existsSync()) {
          final targets = [
            '/workspace/models/realesrgan/RealESRGAN_x4plus.pth',
            '/root/models/realesrgan/RealESRGAN_x4plus.pth',
            p.join(Platform.environment['HOME'] ?? '', '.cache/realesrgan/RealESRGAN_x4plus.pth'),
          ];
          for (final t in targets) {
            final f = File(t);
            f.parent.createSync(recursive: true);
            if (!f.existsSync()) {
              try {
                Link(t).createSync(pth.path);
              } catch (_) {
                try {
                  pth.copySync(t);
                } catch (_) {}
              }
            }
          }
        }
      } else if (canonicalId == 'breeze-tts-2') {
        final targets = [
          '/workspace/models/breeze-tts-2',
          '/root/models/breeze-tts-2',
        ];
        for (final t in targets) {
          try {
            final link = Link(t);
            if (!link.existsSync() && !Directory(t).existsSync()) {
              link.createSync(destDir.path);
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('[ModelDownloadService] Symlink setup notice: $e');
    }
  }

  /// Deletes local files for a model
  Future<void> deleteModel(String rawModelId) async {
    final canonicalId = normalizeModelId(rawModelId);
    final dir = getModelDirectory(canonicalId);
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
    _emitProgress(ModelDownloadProgress(
      modelId: canonicalId,
      status: ModelDownloadStatus.notDownloaded,
    ));
  }
}
