import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/cloud_mode/data/models/saved_generation.dart';
import '../features/cloud_mode/data/services/cloud_api_service.dart';
import '../models/generation_item.dart';
import '../theme/app_theme.dart';
import 'moderation_outcome_dialog.dart';

/// One feed turn (Part 5/5): right-aligned user prompt bubble on top,
/// centered AI output card below with hover action bar, metadata
/// footer, retry support, and a zoomable lightbox.
class GenerationBubble extends StatefulWidget {
  final GenerationItem item;
  final VoidCallback? onRetry;

  const GenerationBubble({super.key, required this.item, this.onRetry});

  @override
  State<GenerationBubble> createState() => _GenerationBubbleState();
}

class _GenerationBubbleState extends State<GenerationBubble> {
  bool _isCardHovered = false;
  bool _isPlayingAudio = false;
  bool _isSaving = false;
  Process? _activeAudioProcess;

  @override
  void dispose() {
    try {
      _activeAudioProcess?.kill();
    } catch (_) {}
    super.dispose();
  }

  Future<bool> _handleSaveToCloud(BuildContext context) async {
    if (!widget.item.isCloud) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Save is only available for Cloud Mode generations. Switch to Cloud Mode to save and share.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return false;
    }

    if (widget.item.isSaved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This creation is already saved in your library ✓'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return true;
    }

    if (_isSaving) return false;
    setState(() => _isSaving = true);

    try {
      final cloudApi = CloudApiService.instance;
      await cloudApi.initAuth();
      if (!cloudApi.isAuthenticated) {
        if (!context.mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please sign in to Cloud Mode to save generations.'),
            backgroundColor: Colors.amber,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return false;
      }

      String? mediaBase64 = widget.item.rawBase64;
      String extension = 'png';
      String mediaType = 'image';

      if (widget.item.isVideo) {
        mediaType = 'video';
        extension = 'mp4';
        final path = widget.item.videoPath ?? widget.item.imagePath;
        if (path != null) {
          final f = File(path);
          if (await f.exists()) {
            final bytes = await f.readAsBytes();
            mediaBase64 = base64Encode(bytes);
          }
        }
      } else if (widget.item.isAudio) {
        mediaType = 'audio';
        extension = 'wav';
        final path = widget.item.audioPath ?? widget.item.imagePath;
        if (path != null) {
          final f = File(path);
          if (await f.exists()) {
            final bytes = await f.readAsBytes();
            mediaBase64 = base64Encode(bytes);
          }
        }
      } else {
        mediaType = 'image';
        extension = 'png';
        if (mediaBase64 == null || mediaBase64.isEmpty) {
          if (widget.item.imageBytes != null) {
            mediaBase64 = base64Encode(widget.item.imageBytes!);
          } else if (widget.item.imagePath != null) {
            final f = File(widget.item.imagePath!);
            if (await f.exists()) {
              final bytes = await f.readAsBytes();
              mediaBase64 = base64Encode(bytes);
            }
          }
        }
      }

      if (mediaBase64 == null || mediaBase64.isEmpty) {
        if (!context.mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot save: Media file data not found on disk.'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return false;
      }

      final res = await cloudApi.saveGeneration(
        mediaBase64: mediaBase64,
        mediaType: mediaType,
        extension: extension,
        prompt: widget.item.prompt,
        negativePrompt: widget.item.negativePrompt,
        modelId: widget.item.modelName,
        settings: {
          'aspectRatio': widget.item.aspectRatio,
          'seed': widget.item.seed,
          'inferenceTimeMs': widget.item.inferenceTimeMs,
          'sampleRate': widget.item.sampleRate,
          'language': widget.item.language,
        },
      );

      if (!context.mounted) return false;

      if (res.isQuotaExceeded) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: isDark ? LuminaColors.darkCard : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.disc_full_rounded, color: Colors.orangeAccent),
                SizedBox(width: 8),
                Text('Storage Full', style: TextStyle(fontSize: 16)),
              ],
            ),
            content: Text(
              res.quotaMessage ?? 'Storage full — free up space or delete old saves',
              style: const TextStyle(fontSize: 13),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Dismiss'),
              ),
            ],
          ),
        );
        return false;
      }

      if (res.success && res.generation != null) {
        setState(() {
          widget.item.isSaved = true;
          widget.item.cloudGenerationId = res.generation!.id;
          if (res.generation!.url.isNotEmpty) {
            widget.item.outputImageUrl = res.generation!.url;
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 18),
                SizedBox(width: 8),
                Text('Saved to your library'),
              ],
            ),
            duration: Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Color(0xFF1E293B),
          ),
        );
        return true;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.message.isNotEmpty ? res.message : 'Failed to save generation.'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return false;
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _handlePublishToGallery(BuildContext context) async {
    if (!widget.item.isCloud) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Publishing to Community Gallery is only available for Cloud Mode generations.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // If already published, open the public URL in browser
    if (widget.item.isPublic && widget.item.cloudGenerationId != null) {
      _openGalleryPostUrl(widget.item.cloudGenerationId!);
      return;
    }

    // Auto-save first if not saved yet
    if (!widget.item.isSaved || widget.item.cloudGenerationId == null) {
      final saved = await _handleSaveToCloud(context);
      if (!saved || widget.item.cloudGenerationId == null) {
        return;
      }
    }

    if (!context.mounted) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final savedGen = SavedGeneration(
      id: widget.item.cloudGenerationId!,
      userId: '',
      prompt: widget.item.prompt,
      negativePrompt: widget.item.negativePrompt,
      modelId: widget.item.modelName,
      mediaType: widget.item.isVideo ? 'video' : widget.item.isAudio ? 'audio' : 'image',
      mediaUrl: widget.item.outputImageUrl ?? '',
      storageKey: '',
      settings: {
        'aspectRatio': widget.item.aspectRatio,
        'seed': widget.item.seed,
      },
      isPublic: widget.item.isPublic,
      moderationStatus: widget.item.moderationStatus ?? 'none',
      createdAt: widget.item.timestamp,
    );

    final updated = await ModerationOutcomeDialog.showPublishFlow(
      context,
      generation: savedGen,
      isDark: isDark,
    );

    if (updated != null && mounted) {
      setState(() {
        widget.item.isPublic = updated.isPublic;
        widget.item.moderationStatus = updated.moderationStatus;
      });
    }
  }

  void _openGalleryPostUrl(String generationId) {
    final url = 'https://cosmic-gen.com/gallery/$generationId';
    try {
      if (Platform.isLinux) {
        Process.start('xdg-open', [url]);
      } else if (Platform.isMacOS) {
        Process.start('open', [url]);
      } else if (Platform.isWindows) {
        Process.start('explorer', [url]);
      }
    } catch (_) {}
  }

  String _time(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  void _copyPrompt(BuildContext context) {
    Clipboard.setData(ClipboardData(text: widget.item.prompt));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Prompt copied'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _copyNegative(BuildContext context) {
    Clipboard.setData(ClipboardData(text: widget.item.negativePrompt));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Negative prompt copied'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _downloadImage(BuildContext context) async {
    if (widget.item.imageBytes == null) return;
    try {
      final downloadsDir =
          Directory('${Platform.environment['HOME']}/Downloads');
      final fileName = 'lumina_${widget.item.id}.png';
      final file = File('${downloadsDir.path}/$fileName');
      await file.writeAsBytes(widget.item.imageBytes!);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved to Downloads: $fileName'),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save file: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _playVideo(BuildContext context, String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Video file not found on disk.'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
      try {
        await Process.start('mpv', ['--loop', '--title=AI Video Preview', path]);
      } catch (_) {
        await Process.start('xdg-open', [path]);
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to play video: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _saveVideo(BuildContext context) async {
    try {
      final path = widget.item.videoPath ?? widget.item.imagePath;
      if (path == null) return;
      final file = File(path);
      if (!await file.exists()) return;
      final downloadsDir =
          Directory('${Platform.environment['HOME']}/Downloads');
      final isMiniMax = widget.item.modelName.contains('MiniMax');
      final fileName = isMiniMax
          ? 'minimax_h3_${widget.item.id}.mp4'
          : 'wan_animate_${widget.item.id}.mp4';
      final target = File('${downloadsDir.path}/$fileName');
      await file.copy(target.path);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved video to Downloads: $fileName 🎬'),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save video: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _togglePlayAudio(BuildContext context, String? path) async {
    if (path == null) return;
    final file = File(path);
    if (!await file.exists()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Audio file not found on disk.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    if (_isPlayingAudio) {
      try {
        _activeAudioProcess?.kill();
      } catch (_) {}
      setState(() {
        _isPlayingAudio = false;
        _activeAudioProcess = null;
      });
      return;
    }

    setState(() => _isPlayingAudio = true);
    try {
      Process proc;
      if (Platform.isLinux) {
        try {
          proc = await Process.start('paplay', [path]);
        } catch (_) {
          try {
            proc = await Process.start('aplay', [path]);
          } catch (_) {
            try {
              proc = await Process.start(
                  'ffplay', ['-nodisp', '-autoexit', path]);
            } catch (_) {
              proc = await Process.start('xdg-open', [path]);
            }
          }
        }
      } else if (Platform.isWindows) {
        proc = await Process.start('powershell',
            ['-c', '(New-Object Media.SoundPlayer "$path").PlaySync()']);
      } else if (Platform.isMacOS) {
        proc = await Process.start('afplay', [path]);
      } else {
        proc = await Process.start('xdg-open', [path]);
      }

      _activeAudioProcess = proc;
      proc.exitCode.then((_) {
        if (mounted) {
          setState(() {
            _isPlayingAudio = false;
            _activeAudioProcess = null;
          });
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isPlayingAudio = false);
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to play audio: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _saveAudio(BuildContext context) async {
    try {
      final path = widget.item.audioPath ?? widget.item.imagePath;
      if (path == null) return;
      final file = File(path);
      if (!await file.exists()) return;
      final downloadsDir =
          Directory('${Platform.environment['HOME']}/Downloads');
      final isBreeze = widget.item.modelName.contains('Breeze');
      final fileName = isBreeze
          ? 'breeze_voice_${widget.item.id}.wav'
          : 'chatterbox_voice_${widget.item.id}.wav';
      final target = File('${downloadsDir.path}/$fileName');
      await file.copy(target.path);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved speech audio to Downloads: $fileName 🎙️'),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save audio: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _openLightbox(BuildContext context) {
    if (widget.item.imageBytes == null) return;
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(
              maxScale: 4.0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(widget.item.imageBytes!),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                icon: const Icon(Icons.close,
                    color: Colors.white, size: 28),
                tooltip: 'Close',
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final item = widget.item;

    return Padding(
      padding:
          const EdgeInsets.symmetric(vertical: 20.0, horizontal: 32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Right-aligned user bubble.
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 580),
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1E232D)
                    : Colors.white,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(4),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.06),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white10
                              : Colors.black
                                  .withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '[${item.aspectRatio}] • [${item.modelName}] • ${_time(item.timestamp)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? Colors.white60
                                : Colors.black54,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (item.isMock)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD32F2F)
                                .withValues(alpha: 0.12),
                            borderRadius:
                                BorderRadius.circular(6),
                            border: Border.all(
                                color: const Color(0xFFD32F2F)
                                    .withValues(alpha: 0.4)),
                          ),
                          child: const Text(
                            '⚡ Offline Mock',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFD32F2F)),
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green
                                .withValues(alpha: 0.12),
                            borderRadius:
                                BorderRadius.circular(6),
                            border: Border.all(
                                color: Colors.green
                                    .withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            item.modelName,
                            style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.green),
                          ),
                        ),

                      const Text('Alex Dan',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                      const CircleAvatar(
                        radius: 12,
                        backgroundColor: Color(0xFFD32F2F),
                        child: Text('AD',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Tooltip(
                    message: 'Click to copy prompt',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => _copyPrompt(context),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 2),
                        child: Text(
                          item.prompt,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.9)
                                : const Color(0xFF14181F),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (item.negativePrompt.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Tooltip(
                      message: 'Click to copy negative prompt',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () => _copyNegative(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: Colors.redAccent
                                  .withValues(alpha: 0.25),
                            ),
                          ),
                          child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.block,
                            size: 11,
                            color: Colors.redAccent,
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              'Neg: ${item.negativePrompt}',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontStyle: FontStyle.italic,
                                color: isDark
                                    ? Colors.redAccent.shade100
                                    : Colors.redAccent.shade700,
                              ),
                            ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (item.referenceImageBytes != null ||
                      item.referenceVideoBytes != null ||
                      item.referenceVideoName != null) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      alignment: WrapAlignment.end,
                      children: [
                        if (item.referenceImageBytes != null)
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.05)
                                  : Colors.black.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: LuminaColors.primaryGlow
                                    .withValues(alpha: 0.35),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.memory(
                                    item.referenceImageBytes!,
                                    width: 34,
                                    height: 34,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  '📷 Character Photo',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: LuminaColors.primaryGlow,
                                  ),
                                ),
                                const SizedBox(width: 4),
                              ],
                            ),
                          ),
                        if (item.referenceVideoBytes != null ||
                            item.referenceVideoName != null)
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.05)
                                  : Colors.black.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: LuminaColors.primaryGlow
                                    .withValues(alpha: 0.35),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: LuminaColors.primaryGlow
                                        .withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Icon(
                                    Icons.videocam_rounded,
                                    color: LuminaColors.primaryGlow,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    '🎬 Motion Video: ${item.referenceVideoName ?? "Attached"}',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: LuminaColors.primaryGlow,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),
          // 2. Centered output display.
          Center(
            child: _buildOutputDisplay(context, isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildOutputDisplay(BuildContext context, bool isDark) {
    final item = widget.item;
    final muted = isDark
        ? LuminaColors.darkMuted
        : LuminaColors.lightMuted;

    if (item.status == GenerationStatus.generating) {
      return Container(
        width: 320,
        height: 440,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF181C24) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: isDark ? Colors.white10 : Colors.black12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Color(0xFFD32F2F),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Rendering via ${item.modelName}...',
              style: TextStyle(fontSize: 13, color: muted),
            ),
          ],
        ),
      );
    }

    if (item.status == GenerationStatus.failed) {
      return Container(
        constraints: const BoxConstraints(maxWidth: 480),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: Colors.redAccent.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(
              item.errorMessage ?? 'Generation failed',
              style: const TextStyle(
                  color: Colors.redAccent, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            if (widget.onRetry != null) ...[
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: widget.onRetry,
                icon: const Icon(Icons.refresh,
                    size: 16, color: Colors.redAccent),
                label: const Text('Retry',
                    style: TextStyle(color: Colors.redAccent)),
              ),
            ],
          ],
        ),
      );
    }

    final isVideo = item.isVideo ||
        item.videoPath != null ||
        (item.imagePath != null && item.imagePath!.endsWith('.mp4'));
    final videoPath = item.videoPath ?? item.imagePath;

    final isAudio = item.isAudio ||
        item.audioPath != null ||
        (item.imagePath != null &&
            (item.imagePath!.endsWith('.wav') ||
                item.imagePath!.endsWith('.mp3')));
    final audioPath = item.audioPath ?? item.imagePath;

    if (isAudio) {
      return _buildAudioPlayerCard(context, item, isDark, audioPath, muted);
    }

    // Completed state (+ network fallback via outputImageUrl).
    ImageProvider<Object>? image;
    if (item.imageBytes != null) {
      image = MemoryImage(item.imageBytes!);
    } else if (item.outputImageUrl != null) {
      image = NetworkImage(item.outputImageUrl!);
    }
    if (image == null && !isVideo) {
      return const SizedBox(
        width: 320,
        height: 240,
        child: Center(
          child: Icon(Icons.broken_image_outlined,
              size: 40, color: Colors.grey),
        ),
      );
    }
    final resolved = image;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        MouseRegion(
          onEnter: (_) => setState(() => _isCardHovered = true),
          onExit: (_) => setState(() => _isCardHovered = false),
          child: Container(
            constraints: const BoxConstraints(
                maxWidth: 440, maxHeight: 560),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.black.withValues(alpha: 0.08),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (isVideo && videoPath != null)
                    GestureDetector(
                      onTap: () => _playVideo(context, videoPath),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          if (resolved != null)
                            Image(
                              image: resolved,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => Container(
                                width: 320,
                                height: 240,
                                color: Colors.black26,
                                child: const Icon(Icons.movie_creation_outlined,
                                    size: 40, color: Colors.grey),
                              ),
                            )
                          else
                            Container(
                              width: 320,
                              height: 240,
                              color: Colors.black54,
                              child: const Icon(Icons.movie_creation_outlined,
                                  size: 40, color: Colors.grey),
                            ),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: LuminaColors.primaryGlow
                                      .withValues(alpha: 0.5),
                                  blurRadius: 18,
                                ),
                              ],
                            ),
                            child: const Icon(Icons.play_arrow_rounded,
                                color: Colors.white, size: 40),
                          ),
                          Positioned(
                            top: 10,
                            left: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.75),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.videocam,
                                      size: 13, color: Colors.white),
                                  SizedBox(width: 4),
                                  Text(
                                    'WAN 2.2 MP4',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    GestureDetector(
                      onTap: () => _openLightbox(context),
                      child: resolved != null
                          ? Image(
                              image: resolved,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) =>
                                  const SizedBox(
                                width: 320,
                                height: 240,
                                child: Center(
                                  child: Icon(
                                      Icons.broken_image_outlined,
                                      size: 40,
                                      color: Colors.grey),
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  if (_isCardHovered)
                    Positioned(
                      bottom: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E232D)
                              .withValues(alpha: 0.9),
                          borderRadius:
                              BorderRadius.circular(30),
                          border: Border.all(
                              color: Colors.white24, width: 0.8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isVideo && videoPath != null) ...[
                              _actionButton(
                                icon: Icons.play_arrow_rounded,
                                tooltip: 'Play Video',
                                onTap: () => _playVideo(context, videoPath),
                              ),
                              const SizedBox(width: 6),
                              _actionButton(
                                icon: Icons.copy_rounded,
                                tooltip: 'Copy Prompt',
                                onTap: () => _copyPrompt(context),
                              ),
                              const SizedBox(width: 6),
                              _actionButton(
                                icon: Icons.download_rounded,
                                tooltip: 'Save Video',
                                onTap: () => _saveVideo(context),
                              ),
                            ] else ...[
                              _actionButton(
                                icon: Icons.fullscreen_rounded,
                                tooltip: 'Full Preview',
                                onTap: () =>
                                    _openLightbox(context),
                              ),
                              const SizedBox(width: 6),
                              _actionButton(
                                icon: Icons.copy_rounded,
                                tooltip: 'Copy Prompt',
                                onTap: () => _copyPrompt(context),
                              ),
                              const SizedBox(width: 6),
                              _actionButton(
                                icon: Icons.download_rounded,
                                tooltip: 'Download',
                                onTap: () =>
                                    _downloadImage(context),
                              ),
                            ],
                            const SizedBox(width: 6),
                            // Save to Cloud Library
                            _actionButton(
                              icon: !item.isCloud
                                  ? Icons.cloud_off_rounded
                                  : item.isSaved
                                      ? Icons.check_circle_rounded
                                      : Icons.bookmark_add_rounded,
                              tooltip: !item.isCloud
                                  ? 'Save & Publish (Cloud Only)'
                                  : item.isSaved
                                      ? 'Saved to Cloud Library ✓'
                                      : 'Save to Cloud Library',
                              onTap: () => _handleSaveToCloud(context),
                            ),
                            const SizedBox(width: 6),
                            // Publish to Gallery
                            _actionButton(
                              icon: !item.isCloud
                                  ? Icons.public_off_rounded
                                  : item.isPublic
                                      ? Icons.open_in_new_rounded
                                      : Icons.public_rounded,
                              tooltip: !item.isCloud
                                  ? 'Publish to Gallery (Cloud Only)'
                                  : item.isPublic
                                      ? 'View in Community Gallery'
                                      : item.moderationStatus == 'pending_review'
                                          ? 'Under Review ⏳'
                                          : 'Publish to Community Gallery',
                              onTap: () => _handlePublishToGallery(context),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        _buildActionRow(context, isDark),
        const SizedBox(height: 6),
        // Metadata footer.
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 6,
          children: [
            if (isVideo)
              _metaTag(
                  muted, Icons.videocam_rounded, 'MP4 Video (Wan 2.2)'),
            if (item.inferenceTimeMs != null &&
                item.inferenceTimeMs! > 0)
              _metaTag(
                  muted,
                  Icons.timer_outlined,
                  '${item.inferenceTimeMs}ms'),
            if (item.seed != null && item.seed! != -1)
              _metaTag(
                  muted, Icons.tag_rounded, 'Seed ${item.seed}'),
            if (item.activeLoras.isNotEmpty)
              _metaTag(
                  muted,
                  Icons.extension_outlined,
                  'LoRAs: ${item.activeLoras.keys.join(", ")}'),
          ],
        ),
      ],
    );
  }

  Widget _buildAudioPlayerCard(
    BuildContext context,
    GenerationItem item,
    bool isDark,
    String? audioPath,
    Color muted,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          constraints: const BoxConstraints(maxWidth: 440),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              colors: isDark
                  ? [
                      const Color(0xFF1F222E).withValues(alpha: 0.95),
                      const Color(0xFF141722).withValues(alpha: 0.95),
                    ]
                  : [
                      Colors.white.withValues(alpha: 0.95),
                      const Color(0xFFF3F5FA).withValues(alpha: 0.95),
                    ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: LuminaColors.primaryGlow.withValues(alpha: 0.35),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.1),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: LuminaColors.primaryGlow.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          item.modelName.contains('Breeze')
                              ? Icons.graphic_eq_rounded
                              : Icons.record_voice_over_rounded,
                          size: 13,
                          color: LuminaColors.primaryGlow,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          item.modelName.contains('Breeze')
                              ? 'BREEZE TTS 2'
                              : 'CHATTERBOX TTS',
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: LuminaColors.primaryGlow,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (item.language != null && item.language!.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        item.language!.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: muted,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              // Spoken script text
              Text(
                '"${item.prompt}"',
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.4,
                  fontStyle: FontStyle.italic,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.92)
                      : Colors.black87,
                ),
              ),
              const SizedBox(height: 16),
              // Play button + visualizer waveform
              Row(
                children: [
                  GestureDetector(
                    onTap: () => _togglePlayAudio(context, audioPath),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: LuminaColors.primaryGradient,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: LuminaColors.primaryGlow
                                .withValues(alpha: 0.45),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        _isPlayingAudio
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.black.withValues(alpha: 0.25)
                            : Colors.white.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isDark ? Colors.white12 : Colors.black12,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: List.generate(24, (idx) {
                          final heights = [
                            8, 14, 22, 10, 18, 28, 16, 24, 12, 20, 26, 14,
                            22, 30, 18, 24, 12, 20, 16, 26, 18, 14, 10, 6,
                          ];
                          final h = heights[idx % heights.length].toDouble();
                          final active = _isPlayingAudio;
                          return AnimatedContainer(
                            duration: Duration(milliseconds: 150 + (idx * 20)),
                            width: 3,
                            height: active ? (h * 0.8 + 4) : (h * 0.55),
                            decoration: BoxDecoration(
                              color: active
                                  ? LuminaColors.primaryGlow
                                  : muted.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
                ],
              ),
              if (item.referenceAudioName != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.mic_none_rounded,
                        size: 13, color: LuminaColors.primaryGlow),
                    const SizedBox(width: 5),
                    Text(
                      'Cloned from: ${item.referenceAudioName}',
                      style: const TextStyle(
                          fontSize: 11, color: LuminaColors.primaryGlow),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              // Action buttons: Play, Copy Prompt, Download WAV, Open External
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _actionButton(
                    icon: _isPlayingAudio
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    tooltip: _isPlayingAudio ? 'Stop Audio' : 'Play Voice',
                    onTap: () => _togglePlayAudio(context, audioPath),
                  ),
                  const SizedBox(width: 6),
                  _actionButton(
                    icon: Icons.copy_rounded,
                    tooltip: 'Copy Spoken Text',
                    onTap: () => _copyPrompt(context),
                  ),
                  const SizedBox(width: 6),
                  _actionButton(
                    icon: Icons.download_rounded,
                    tooltip: 'Save Voice WAV',
                    onTap: () => _saveAudio(context),
                  ),
                  const SizedBox(width: 6),
                  _actionButton(
                    icon: Icons.open_in_new_rounded,
                    tooltip: 'Open with System Player',
                    onTap: () {
                      if (audioPath != null) {
                        Process.start('xdg-open', [audioPath]);
                      }
                    },
                  ),
                  const SizedBox(width: 6),
                  _actionButton(
                    icon: !item.isCloud
                        ? Icons.cloud_off_rounded
                        : item.isSaved
                            ? Icons.check_circle_rounded
                            : Icons.bookmark_add_rounded,
                    tooltip: !item.isCloud
                        ? 'Save & Publish (Cloud Only)'
                        : item.isSaved
                            ? 'Saved to Cloud Library ✓'
                            : 'Save Voice to Library',
                    onTap: () => _handleSaveToCloud(context),
                  ),
                  const SizedBox(width: 6),
                  _actionButton(
                    icon: !item.isCloud
                        ? Icons.public_off_rounded
                        : item.isPublic
                            ? Icons.open_in_new_rounded
                            : Icons.public_rounded,
                    tooltip: !item.isCloud
                        ? 'Publish to Gallery (Cloud Only)'
                        : item.isPublic
                            ? 'View in Community Gallery'
                            : 'Publish to Community Gallery',
                    onTap: () => _handlePublishToGallery(context),
                  ),
                ],
              ),
            ],
          ),
        ),
        _buildActionRow(context, isDark),
        const SizedBox(height: 6),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 6,
          children: [
            _metaTag(muted, Icons.record_voice_over_rounded, 'Voice Audio'),
            if (item.inferenceTimeMs != null && item.inferenceTimeMs! > 0)
              _metaTag(
                  muted, Icons.timer_outlined, '${item.inferenceTimeMs}ms'),
            if (item.seed != null && item.seed! != -1)
              _metaTag(muted, Icons.tag_rounded, 'Seed ${item.seed}'),
            if (item.sampleRate != null && item.sampleRate! > 0)
              _metaTag(
                  muted, Icons.graphic_eq_rounded, '${item.sampleRate}Hz'),
          ],
        ),
      ],
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
      ),
    );
  }

  Widget _metaTag(Color muted, IconData icon, String text) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: muted.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: muted),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 11, color: muted)),
        ],
      ),
    );
  }

  Widget _buildActionRow(BuildContext context, bool isDark) {
    final item = widget.item;
    final isCloud = item.isCloud;
    final isSaved = item.isSaved;
    final isPublic = item.isPublic;
    final modStatus = item.moderationStatus;

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          // 1. SAVE BUTTON
          if (!isCloud)
            Tooltip(
              message: 'Save & Publish is only available for Cloud Mode generations.\nSwitch to Cloud Mode to save creations.',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark ? Colors.white10 : Colors.black12,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.cloud_off_rounded,
                      size: 14,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Save (Cloud Only)',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (isSaved)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.green.withValues(alpha: 0.35),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_rounded, size: 14, color: Colors.greenAccent),
                  SizedBox(width: 5),
                  Text(
                    'Saved ✓',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.greenAccent,
                    ),
                  ),
                ],
              ),
            )
          else
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _isSaving ? null : () => _handleSaveToCloud(context),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark ? LuminaColors.darkCard : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: LuminaColors.primaryEnd.withValues(alpha: 0.5),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: LuminaColors.primaryGlow.withValues(alpha: 0.15),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isSaving)
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: LuminaColors.primaryEnd,
                          ),
                        )
                      else
                        const Icon(
                          Icons.bookmark_add_rounded,
                          size: 14,
                          color: LuminaColors.primaryEnd,
                        ),
                      const SizedBox(width: 6),
                      Text(
                        _isSaving ? 'Saving...' : 'Save to Library',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: LuminaColors.primaryEnd,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // 2. PUBLISH BUTTON
          if (!isCloud)
            Tooltip(
              message: 'Community Gallery publishing is only available for Cloud Mode generations.',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark ? Colors.white10 : Colors.black12,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.public_off_rounded,
                      size: 14,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Publish (Cloud Only)',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (isPublic)
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  if (item.cloudGenerationId != null) {
                    _openGalleryPostUrl(item.cloudGenerationId!);
                  }
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: LuminaColors.primaryGradient,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: LuminaColors.primaryGlow.withValues(alpha: 0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.open_in_new_rounded, size: 13, color: Colors.white),
                      SizedBox(width: 5),
                      Text(
                        'Published 🎉 View on Web',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (modStatus == 'pending_review')
            Tooltip(
              message: 'Your post is under review by moderation and will appear in the gallery once approved.',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.amber.withValues(alpha: 0.4),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.hourglass_top_rounded, size: 14, color: Colors.amber),
                    SizedBox(width: 5),
                    Text(
                      'Under Review ⏳',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.amber,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (modStatus == 'rejected')
            Tooltip(
              message: 'This generation could not be published due to community guidelines.',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.redAccent.withValues(alpha: 0.4),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.block_rounded, size: 14, color: Colors.redAccent),
                    SizedBox(width: 5),
                    Text(
                      'Rejected ❌',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.redAccent,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _handlePublishToGallery(context),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: LuminaColors.primaryGradient,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: LuminaColors.primaryGlow.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.public_rounded, size: 14, color: Colors.white),
                      SizedBox(width: 5),
                      Text(
                        'Publish to Gallery',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
