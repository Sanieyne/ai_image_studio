import 'dart:async';
import 'package:flutter/material.dart';
import '../services/model_download_service.dart';
import '../theme/app_theme.dart';

class ModelDownloadButton extends StatefulWidget {
  final String modelId;
  final String displayName;
  final VoidCallback? onUse;
  final bool isSelected;

  const ModelDownloadButton({
    super.key,
    required this.modelId,
    required this.displayName,
    this.onUse,
    this.isSelected = false,
  });

  @override
  State<ModelDownloadButton> createState() => _ModelDownloadButtonState();
}

class _ModelDownloadButtonState extends State<ModelDownloadButton> {
  bool _isDownloaded = false;
  bool _isLoading = true;
  bool _hasUnfinished = false;
  StreamSubscription<ModelDownloadProgress>? _sub;
  ModelDownloadProgress? _progress;

  @override
  void initState() {
    super.initState();
    _checkStatus();
    _sub = ModelDownloadService.instance.watchProgress(widget.modelId).listen((prog) {
      if (mounted) {
        setState(() {
          _progress = prog;
          if (prog.status == ModelDownloadStatus.downloaded) {
            _isDownloaded = true;
            _hasUnfinished = false;
          } else if (prog.status == ModelDownloadStatus.notDownloaded) {
            _isDownloaded = false;
            _hasUnfinished = false;
          } else if (prog.status == ModelDownloadStatus.paused || prog.status == ModelDownloadStatus.failed) {
            _hasUnfinished = true;
          }
        });
      }
    });
  }

  @override
  void didUpdateWidget(covariant ModelDownloadButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.modelId != widget.modelId) {
      _checkStatus();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _checkStatus() async {
    setState(() => _isLoading = true);
    final service = ModelDownloadService.instance;
    final downloaded = await service.isModelDownloaded(widget.modelId);
    final pending = (await service.pendingDownloads()).contains(service.normalizeModelId(widget.modelId));
    if (mounted) {
      setState(() {
        _isDownloaded = downloaded;
        _hasUnfinished = pending && !service.isActive(widget.modelId);
        _isLoading = false;
      });
    }
  }

  void _start(BuildContext context) {
    setState(() => _hasUnfinished = false);
    ModelDownloadService.instance.downloadModel(widget.modelId).catchError((err) {
      if (context.mounted) {
        setState(() => _hasUnfinished = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download stopped: $err'), backgroundColor: Colors.redAccent),
        );
      }
    });
  }

  Future<void> _promptDownload(BuildContext context) async {
    final service = ModelDownloadService.instance;
    final availableBytes = await service.getAvailableDiskSpace();

    // Fetch metadata
    int totalBytes = 0;
    try {
      final info = await service.fetchDownloadUrls(widget.modelId);
      totalBytes = info['totalBytes'] ?? 0;
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to query model storage: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (!context.mounted) return;

    // Unknown free space does not block the download; it is shown as unknown.
    final availGB = availableBytes == null ? 'unknown' : '${(availableBytes / 1e9).toStringAsFixed(1)} GB';
    final reqGB = (totalBytes / 1e9).toStringAsFixed(2);
    final hasEnough = availableBytes == null || availableBytes >= (totalBytes + 512 * 1024 * 1024);

    showDialog(
      context: context,
      builder: (ctx) {
        final dark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: dark ? const Color(0xFF1E1E24) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.cloud_download_rounded, color: LuminaColors.primaryStart, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Download ${widget.displayName}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Weights will be downloaded from Cloudflare R2 into your local engine models directory.',
                style: TextStyle(fontSize: 12, color: dark ? Colors.white70 : Colors.black87),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: dark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: hasEnough ? Colors.white12 : Colors.redAccent.withValues(alpha: 0.4),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Required Size:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                        Text('$reqGB GB', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Available Disk:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                        Text(
                          availGB,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: hasEnough ? Colors.greenAccent : Colors.redAccent,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!hasEnough) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Insufficient disk space to stage this model safely. Please free disk space.',
                          style: TextStyle(fontSize: 11, color: Colors.redAccent, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: hasEnough
                  ? () {
                      Navigator.of(ctx).pop();
                      _start(context);
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: LuminaColors.primaryStart,
                foregroundColor: Colors.white,
              ),
              child: const Text('Start Download'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Model Weights?'),
        content: Text('This will delete all local weight files for ${widget.displayName} to free up disk space.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ModelDownloadService.instance.deleteModel(widget.modelId);
      await _checkStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    final status = _progress?.status;
    final isDownloading = status == ModelDownloadStatus.downloading ||
        status == ModelDownloadStatus.waitingForNetwork ||
        status == ModelDownloadStatus.verifying ||
        status == ModelDownloadStatus.checking;

    if (isDownloading) {
      final pct = _progress?.percentage ?? 0.0;
      final label = switch (status) {
        ModelDownloadStatus.waitingForNetwork => _progress?.errorMessage ?? 'Waiting for network…',
        ModelDownloadStatus.verifying => 'Verifying ${_progress?.currentFile ?? ''}…',
        ModelDownloadStatus.checking => 'Preparing…',
        _ => _progress?.formattedProgress ?? 'Downloading...',
      };
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  label,
                  key: const ValueKey('model_download_label'),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: status == ModelDownloadStatus.waitingForNetwork ? LuminaColors.amber : LuminaColors.primaryEnd,
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: const ValueKey('model_download_pause'),
                    icon: const Icon(Icons.pause_rounded, size: 14),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Pause',
                    onPressed: () => ModelDownloadService.instance.pause(widget.modelId),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    key: const ValueKey('model_download_cancel'),
                    icon: const Icon(Icons.close_rounded, size: 14),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Cancel and delete partial files',
                    onPressed: () => ModelDownloadService.instance.cancel(widget.modelId),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 4,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation(LuminaColors.primaryStart),
            ),
          ),
        ],
      );
    }

    if (_isDownloaded) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.4)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_outline_rounded, size: 12, color: Colors.greenAccent),
                SizedBox(width: 4),
                Text(
                  'Downloaded ✓',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.greenAccent),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, size: 14, color: Colors.white38),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'Delete local weights to free space',
            onPressed: () => _confirmDelete(context),
          ),
        ],
      );
    }

    // Paused, failed, or interrupted by an app restart: resume from the partial files.
    if (_hasUnfinished) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          OutlinedButton.icon(
            key: const ValueKey('model_download_resume'),
            onPressed: () => _start(context),
            icon: const Icon(Icons.play_arrow_rounded, size: 12),
            label: Text(
              _progress != null && _progress!.totalBytes > 0
                  ? 'Resume (${(_progress!.percentage * 100).toStringAsFixed(0)}%)'
                  : 'Resume download',
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: LuminaColors.primaryStart,
              side: BorderSide(color: LuminaColors.primaryStart.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 14),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'Discard the partial download',
            onPressed: () => ModelDownloadService.instance.cancel(widget.modelId),
          ),
        ],
      );
    }

    // Not yet downloaded
    return OutlinedButton.icon(
      onPressed: () => _promptDownload(context),
      icon: const Icon(Icons.arrow_downward_rounded, size: 11),
      label: const Text('Download', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
      style: OutlinedButton.styleFrom(
        foregroundColor: LuminaColors.primaryStart,
        side: BorderSide(color: LuminaColors.primaryStart.withValues(alpha: 0.5)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
