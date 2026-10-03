import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'api_client.dart';

enum ModelDownloadStatus {
  notDownloaded,
  checking,
  downloading,
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

class ModelDownloadService {
  ModelDownloadService._();
  static final ModelDownloadService instance = ModelDownloadService._();

  final ApiClient _apiClient = ApiClient();
  final Map<String, StreamController<ModelDownloadProgress>> _controllers = {};
  final Map<String, ModelDownloadProgress> _currentProgress = {};

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
      final entities = dir.listSync(recursive: true);
      final files = entities.whereType<File>().toList();
      if (files.isEmpty) return false;

      // Ensure key weight files are not empty (size > 1MB)
      final hasRealWeights = files.any((f) => f.lengthSync() > 1024 * 1024);
      return hasRealWeights;
    } catch (e) {
      debugPrint('[ModelDownloadService] Error checking local files: $e');
      return false;
    }
  }

  /// Check available disk space in bytes for the models directory
  Future<int> getAvailableDiskSpace() async {
    final base = getModelsBaseDirectory();
    try {
      if (Platform.isLinux || Platform.isMacOS) {
        final res = await Process.run('df', ['-k', base.path]);
        if (res.exitCode == 0) {
          final lines = res.stdout.toString().trim().split('\n');
          if (lines.length >= 2) {
            final parts = lines[1].split(RegExp(r'\s+'));
            if (parts.length >= 4) {
              final availKB = int.tryParse(parts[3]);
              if (availKB != null) {
                return availKB * 1024;
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[ModelDownloadService] Error checking disk space: $e');
    }
    // Fallback: 50GB assumed
    return 50 * 1024 * 1024 * 1024;
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

  /// Downloads a model end-to-end with resume support and progress reporting
  Future<void> downloadModel(String rawModelId, {String? authToken}) async {
    final canonicalId = normalizeModelId(rawModelId);
    _emitProgress(ModelDownloadProgress(
      modelId: canonicalId,
      status: ModelDownloadStatus.checking,
    ));

    try {
      final data = await fetchDownloadUrls(canonicalId, authToken: authToken);
      final List files = data['files'] ?? [];
      final int totalBytes = data['totalBytes'] ?? 0;

      if (files.isEmpty) {
        throw Exception('No files available for model $canonicalId in R2 storage.');
      }

      // Check disk space (buffer 1GB extra)
      final availableBytes = await getAvailableDiskSpace();
      if (availableBytes < (totalBytes + 1024 * 1024 * 1024)) {
        throw InsufficientDiskSpaceException(
          availableBytes: availableBytes,
          requiredBytes: totalBytes,
        );
      }

      final destDir = getModelDirectory(canonicalId);
      if (!destDir.existsSync()) {
        destDir.createSync(recursive: true);
      }

      int aggregateDownloaded = 0;

      // Pre-calculate already downloaded files for aggregate progress
      for (final f in files) {
        final filename = f['filename'] as String;
        final expectedSize = f['size'] as int;
        final localFile = File(p.join(destDir.path, filename));
        if (localFile.existsSync() && localFile.lengthSync() == expectedSize) {
          aggregateDownloaded += expectedSize;
        }
      }

      _emitProgress(ModelDownloadProgress(
        modelId: canonicalId,
        status: ModelDownloadStatus.downloading,
        downloadedBytes: aggregateDownloaded,
        totalBytes: totalBytes,
        percentage: totalBytes > 0 ? aggregateDownloaded / totalBytes : 0.0,
      ));

      final httpClient = http.Client();
      try {
        for (final f in files) {
          final filename = f['filename'] as String;
          final expectedSize = f['size'] as int;
          final downloadUrl = f['downloadUrl'] as String;

          final targetFile = File(p.join(destDir.path, filename));
          targetFile.parent.createSync(recursive: true);

          if (targetFile.existsSync() && targetFile.lengthSync() == expectedSize) {
            // Already complete
            continue;
          }

          final partFile = File('${targetFile.path}.part');
          int startByte = 0;
          if (partFile.existsSync()) {
            startByte = partFile.lengthSync();
            if (startByte > expectedSize) {
              partFile.deleteSync();
              startByte = 0;
            }
          }

          final request = http.Request('GET', Uri.parse(downloadUrl));
          if (startByte > 0) {
            request.headers['Range'] = 'bytes=$startByte-';
          }

          final response = await httpClient.send(request);
          if (response.statusCode != 200 && response.statusCode != 206) {
            throw Exception('HTTP ${response.statusCode} while fetching $filename');
          }

          final sink = partFile.openWrite(mode: startByte > 0 ? FileMode.append : FileMode.write);

          await for (final chunk in response.stream) {
            sink.add(chunk);
            aggregateDownloaded += chunk.length;

            _emitProgress(ModelDownloadProgress(
              modelId: canonicalId,
              status: ModelDownloadStatus.downloading,
              downloadedBytes: aggregateDownloaded,
              totalBytes: totalBytes,
              percentage: totalBytes > 0 ? (aggregateDownloaded / totalBytes).clamp(0.0, 1.0) : 0.0,
              currentFile: filename,
            ));
          }

          await sink.flush();
          await sink.close();

          if (partFile.lengthSync() != expectedSize) {
            throw Exception('Size mismatch for $filename: expected $expectedSize, got ${partFile.lengthSync()}');
          }

          if (targetFile.existsSync()) {
            targetFile.deleteSync();
          }
          partFile.renameSync(targetFile.path);
        }
      } finally {
        httpClient.close();
      }

      // Establish symlinks for engine backward compatibility
      _setupEngineSymlinks(canonicalId, destDir);

      _emitProgress(ModelDownloadProgress(
        modelId: canonicalId,
        status: ModelDownloadStatus.downloaded,
        downloadedBytes: totalBytes,
        totalBytes: totalBytes,
        percentage: 1.0,
      ));
    } catch (e) {
      debugPrint('[ModelDownloadService] Download error: $e');
      _emitProgress(ModelDownloadProgress(
        modelId: canonicalId,
        status: ModelDownloadStatus.failed,
        errorMessage: e.toString(),
      ));
      rethrow;
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
