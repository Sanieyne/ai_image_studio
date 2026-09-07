import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/generation_item.dart';
import '../theme/app_theme.dart';

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

  String _time(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  void _copyPrompt(BuildContext context) {
    Clipboard.setData(ClipboardData(text: widget.item.prompt));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Prompt copied to clipboard'),
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
                          child: const Text(
                            '⚡ Live RTX 3090',
                            style: TextStyle(
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
                  Text(
                    item.prompt,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.9)
                          : const Color(0xFF14181F),
                    ),
                  ),
                  if (item.negativePrompt.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Colors.redAccent.withValues(alpha: 0.25),
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
                  ],
                  if (item.referenceImageBytes != null) ...[
                    const SizedBox(height: 8),
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
                              width: 38,
                              height: 38,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            '📷 Reference Image Attached',
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

    // Completed state (+ network fallback via outputImageUrl).
    ImageProvider<Object>? image;
    if (item.imageBytes != null) {
      image = MemoryImage(item.imageBytes!);
    } else if (item.outputImageUrl != null) {
      image = NetworkImage(item.outputImageUrl!);
    }
    if (image == null) {
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
                  GestureDetector(
                    onTap: () => _openLightbox(context),
                    child: Image(
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
                    ),
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
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Metadata footer.
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 6,
          children: [
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
}
