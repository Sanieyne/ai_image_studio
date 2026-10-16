import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';

import '../features/cloud_mode/data/models/cloud_model.dart';
import '../features/cloud_mode/data/services/cloud_api_service.dart';
import '../services/model_download_service.dart';
import '../theme/app_theme.dart';
import '../widgets/model_download_button.dart';

/// Downloads management screen:
/// 1. "Downloading now" — live progress stream, pause/cancel, percentages.
/// 2. "Downloaded" — models with isModelDownloaded == true, size on disk, delete option.
/// 3. "Available to download" — all other catalog models with inline download buttons.
/// 4. Total local storage used visible at the top.
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  final ModelDownloadService _downloadService = ModelDownloadService.instance;
  final CloudApiService _cloudApi = CloudApiService.instance;

  StreamSubscription<ModelDownloadProgress>? _globalSub;

  late List<CloudModel> _catalog = _cloudApi.fallbackModels;
  final Set<String> _downloadedModelIds = {};
  final Map<String, int> _diskSizes = {}; // canonicalId -> bytes on disk
  final Map<String, ModelDownloadProgress> _activeProgress = {}; // canonicalId -> progress
  final Set<String> _pendingResumes = {};

  bool _isLoading = false;
  int? _availableDiskBytes;
  Timer? _ipcTimer;

  @override
  void initState() {
    super.initState();
    _catalog = _cloudApi.fallbackModels;
    _subscribeToDownloads();
    _initCatalogAndStatus();

    _ipcTimer = Timer.periodic(const Duration(milliseconds: 250), (_) async {
      try {
        final f = File('/tmp/trigger_download.txt');
        if (f.existsSync()) {
          final cmd = f.readAsStringSync().trim();
          try {
            f.deleteSync();
          } catch (_) {}
          if (cmd == 'start') {
            await _downloadService.downloadModel('realesrgan-x4plus');
          } else if (cmd == 'delete') {
            await _downloadService.deleteModel('realesrgan-x4plus');
            if (mounted) {
              setState(() {
                _downloadedModelIds.remove('realesrgan-x4plus');
                _diskSizes.remove('realesrgan-x4plus');
              });
            }
          }
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _ipcTimer?.cancel();
    _globalSub?.cancel();
    super.dispose();
  }

  void _subscribeToDownloads() {
    _globalSub = _downloadService.globalProgressStream.listen((progress) {
      if (!mounted) return;
      final cid = _downloadService.normalizeModelId(progress.modelId);
      setState(() {
        switch (progress.status) {
          case ModelDownloadStatus.checking:
          case ModelDownloadStatus.downloading:
          case ModelDownloadStatus.waitingForNetwork:
          case ModelDownloadStatus.verifying:
            _activeProgress[cid] = progress;
            _downloadedModelIds.remove(cid);
            break;
          case ModelDownloadStatus.paused:
          case ModelDownloadStatus.failed:
            _activeProgress[cid] = progress;
            _pendingResumes.add(cid);
            break;
          case ModelDownloadStatus.downloaded:
            _activeProgress.remove(cid);
            _downloadedModelIds.add(cid);
            _pendingResumes.remove(cid);
            _refreshModelSize(cid);
            break;
          case ModelDownloadStatus.notDownloaded:
            _activeProgress.remove(cid);
            _downloadedModelIds.remove(cid);
            _diskSizes.remove(cid);
            _pendingResumes.remove(cid);
            break;
        }
      });
    });
  }

  Future<void> _refreshModelSize(String canonicalId) async {
    final size = await _downloadService.getDownloadedModelSizeBytes(canonicalId);
    if (mounted) {
      setState(() {
        _diskSizes[canonicalId] = size;
      });
    }
  }

  Future<void> _initCatalogAndStatus() async {
    final available = await _downloadService.getAvailableDiskSpace();
    final pending = await _downloadService.pendingDownloads();

    final downloaded = <String>{};
    final sizes = <String, int>{};
    final active = <String, ModelDownloadProgress>{};

    for (final model in _catalog) {
      final cid = _downloadService.normalizeModelId(model.modelId);
      final isDownloaded = await _downloadService.isModelDownloaded(cid);
      if (isDownloaded) {
        downloaded.add(cid);
        sizes[cid] = await _downloadService.getDownloadedModelSizeBytes(cid);
      }

      final curr = _downloadService.getCurrentProgress(cid);
      if (curr != null && _isProgressActive(curr.status)) {
        active[cid] = curr;
      }
    }

    if (mounted) {
      setState(() {
        _availableDiskBytes = available;
        _downloadedModelIds.clear();
        _downloadedModelIds.addAll(downloaded);
        _diskSizes.clear();
        _diskSizes.addAll(sizes);
        _activeProgress.clear();
        _activeProgress.addAll(active);
        _pendingResumes.clear();
        _pendingResumes.addAll(pending);
        _isLoading = false;
      });
    }
  }

  bool _isProgressActive(ModelDownloadStatus status) {
    return status == ModelDownloadStatus.checking ||
        status == ModelDownloadStatus.downloading ||
        status == ModelDownloadStatus.waitingForNetwork ||
        status == ModelDownloadStatus.verifying ||
        status == ModelDownloadStatus.paused;
  }

  int get _totalDiskSizeBytes {
    var sum = 0;
    for (final cid in _downloadedModelIds) {
      sum += _diskSizes[cid] ?? 0;
    }
    return sum;
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final dark = LuminaTheme.isDark(context);
    final bg = dark ? LuminaColors.darkBg : LuminaColors.lightBg;
    final surface = dark ? LuminaColors.darkSurface : LuminaColors.lightSurface;
    final border = dark ? LuminaColors.darkBorder : LuminaColors.lightBorder;
    final muted = dark ? LuminaColors.darkMuted : LuminaColors.lightMuted;

    // Split models into:
    // 1. Active downloads
    final activeModels = _catalog.where((m) {
      final cid = _downloadService.normalizeModelId(m.modelId);
      return _activeProgress.containsKey(cid) &&
          _isProgressActive(_activeProgress[cid]!.status);
    }).toList();

    // 2. Downloaded models
    final downloadedModels = _catalog.where((m) {
      final cid = _downloadService.normalizeModelId(m.modelId);
      return _downloadedModelIds.contains(cid) && !_activeProgress.containsKey(cid);
    }).toList();

    // 3. Available models
    final availableModels = _catalog.where((m) {
      final cid = _downloadService.normalizeModelId(m.modelId);
      final isDownloading = _activeProgress.containsKey(cid) &&
          _isProgressActive(_activeProgress[cid]!.status);
      final isDownloaded = _downloadedModelIds.contains(cid);
      return !isDownloading && !isDownloaded;
    }).toList();

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Model Downloads',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        actions: [
          _buildStorageHeaderPill(dark, border, muted),
          const SizedBox(width: 14),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: border),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _initCatalogAndStatus,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                children: [
                  // SECTION 1: DOWNLOADING NOW (only if non-empty)
                  if (activeModels.isNotEmpty) ...[
                    _buildSectionHeader(
                      context,
                      title: 'Downloading now',
                      count: activeModels.length,
                      icon: Icons.downloading_rounded,
                      iconColor: LuminaColors.cyan,
                    ),
                    const SizedBox(height: 12),
                    ...activeModels.map((m) => _buildDownloadingCard(m, dark, border, muted)),
                    const SizedBox(height: 28),
                  ],

                  // SECTION 2: DOWNLOADED
                  _buildSectionHeader(
                    context,
                    title: 'Downloaded',
                    count: downloadedModels.length,
                    icon: Icons.check_circle_rounded,
                    iconColor: Colors.greenAccent,
                  ),
                  const SizedBox(height: 12),
                  if (downloadedModels.isEmpty)
                    _buildEmptyState(
                      'No models downloaded yet',
                      'Models you download will be stored locally for offline inference.',
                      dark,
                      border,
                      muted,
                    )
                  else
                    ...downloadedModels.map((m) => _buildDownloadedCard(m, dark, border, muted)),
                  const SizedBox(height: 28),

                  // SECTION 3: AVAILABLE TO DOWNLOAD
                  _buildSectionHeader(
                    context,
                    title: 'Available to download',
                    count: availableModels.length,
                    icon: Icons.cloud_download_outlined,
                    iconColor: LuminaColors.violet,
                  ),
                  const SizedBox(height: 12),
                  if (availableModels.isEmpty)
                    _buildEmptyState(
                      'All models are downloaded',
                      'Your local storage contains all models from the catalog.',
                      dark,
                      border,
                      muted,
                    )
                  else
                    ...availableModels.map((m) => _buildAvailableCard(m, dark, border, muted)),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _buildStorageHeaderPill(bool dark, Color border, Color muted) {
    final totalUsedStr = _formatBytes(_totalDiskSizeBytes);
    final availStr = _availableDiskBytes != null ? _formatBytes(_availableDiskBytes!) : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: (dark ? Colors.white : Colors.black).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(LuminaColors.pillRadius),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.storage_rounded, size: 16, color: LuminaColors.cyan),
          const SizedBox(width: 8),
          Text(
            'Total Local Storage: $totalUsedStr',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          if (availStr != null) ...[
            Text(
              '  •  $availStr Free',
              style: TextStyle(fontSize: 11, color: muted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required String title,
    required int count,
    required IconData icon,
    required Color iconColor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: iconColor),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: iconColor,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDownloadingCard(CloudModel model, bool dark, Color border, Color muted) {
    final cid = _downloadService.normalizeModelId(model.modelId);
    final prog = _activeProgress[cid];
    final pct = prog != null ? prog.percentage : 0.0;
    final statusText = _statusToLabel(prog?.status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: (dark ? LuminaColors.darkCard : LuminaColors.lightCard),
        borderRadius: BorderRadius.circular(LuminaColors.cardRadius),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.2 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          model.displayName,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        _buildBadge(model.mode.toUpperCase(), LuminaColors.cyan),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      statusText,
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ],
                ),
              ),
              Text(
                '${(pct * 100).toStringAsFixed(1)}%',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: LuminaColors.cyan,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct > 0 ? pct : null,
              minHeight: 6,
              backgroundColor: (dark ? Colors.white : Colors.black).withValues(alpha: 0.08),
              valueColor: const AlwaysStoppedAnimation<Color>(LuminaColors.cyan),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                prog?.formattedProgress ?? '',
                style: TextStyle(fontSize: 11, color: muted),
              ),
              Row(
                children: [
                  if (prog?.status == ModelDownloadStatus.downloading)
                    TextButton.icon(
                      onPressed: () => _downloadService.pause(model.modelId),
                      icon: const Icon(Icons.pause, size: 14),
                      label: const Text('Pause', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    )
                  else if (prog?.status == ModelDownloadStatus.paused)
                    TextButton.icon(
                      onPressed: () => _downloadService.downloadModel(model.modelId),
                      icon: const Icon(Icons.play_arrow, size: 14),
                      label: const Text('Resume', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  const SizedBox(width: 6),
                  TextButton.icon(
                    onPressed: () => _downloadService.cancel(model.modelId),
                    icon: const Icon(Icons.close, size: 14, color: Colors.redAccent),
                    label: const Text('Cancel', style: TextStyle(fontSize: 12, color: Colors.redAccent)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadedCard(CloudModel model, bool dark, Color border, Color muted) {
    final cid = _downloadService.normalizeModelId(model.modelId);
    final sizeOnDisk = _diskSizes[cid] ?? 0;
    final formattedSize = _formatBytes(sizeOnDisk);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: (dark ? LuminaColors.darkCard : LuminaColors.lightCard),
        borderRadius: BorderRadius.circular(LuminaColors.cardRadius),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.greenAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.check_circle_outline_rounded, color: Colors.greenAccent, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      model.displayName,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    _buildBadge(model.mode.toUpperCase(), LuminaColors.purple),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      'Size on disk: $formattedSize',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(width: 8),
                    Text('•  Catalog: ${model.sizeGB.toStringAsFixed(1)} GB',
                        style: TextStyle(fontSize: 11, color: muted)),
                  ],
                ),
              ],
            ),
          ),
          // Delete option reusing ModelDownloadButton.confirmAndDelete
          OutlinedButton.icon(
            onPressed: () async {
              final deleted = await ModelDownloadButton.confirmAndDelete(
                context,
                model.modelId,
                model.displayName,
              );
              if (deleted && mounted) {
                setState(() {
                  _downloadedModelIds.remove(cid);
                  _diskSizes.remove(cid);
                });
              }
            },
            icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Colors.redAccent),
            label: const Text('Delete', style: TextStyle(fontSize: 12, color: Colors.redAccent)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.4)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvailableCard(CloudModel model, bool dark, Color border, Color muted) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: (dark ? LuminaColors.darkCard : LuminaColors.lightCard),
        borderRadius: BorderRadius.circular(LuminaColors.cardRadius),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: LuminaColors.violet.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.cloud_download_outlined, color: LuminaColors.violet, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      model.displayName,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    _buildBadge(model.mode.toUpperCase(), LuminaColors.violet),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      'Download Size: ~${model.sizeGB.toStringAsFixed(1)} GB',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '•  VRAM: ${model.requiredVramGB} GB',
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Reuse existing ModelDownloadButton inline
          ModelDownloadButton(
            modelId: model.modelId,
            displayName: model.displayName,
            isInitiallyDownloaded: false,
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  Widget _buildEmptyState(String title, String subtitle, bool dark, Color border, Color muted) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: (dark ? Colors.white : Colors.black).withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(LuminaColors.cardRadius),
        border: Border.all(color: border),
      ),
      child: Center(
        child: Column(
          children: [
            Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(fontSize: 12, color: muted), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  String _statusToLabel(ModelDownloadStatus? status) {
    switch (status) {
      case ModelDownloadStatus.checking:
        return 'Checking server & disk space...';
      case ModelDownloadStatus.downloading:
        return 'Downloading weights...';
      case ModelDownloadStatus.waitingForNetwork:
        return 'Reconnecting to network...';
      case ModelDownloadStatus.paused:
        return 'Download paused';
      case ModelDownloadStatus.verifying:
        return 'Verifying SHA-256 integrity...';
      case ModelDownloadStatus.downloaded:
        return 'Download complete';
      case ModelDownloadStatus.failed:
        return 'Download failed';
      default:
        return '';
    }
  }
}
