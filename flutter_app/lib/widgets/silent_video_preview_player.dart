import 'package:flutter/material.dart';
import '../models/video_template.dart';

/// Simulated looping silent video player with camera HUD, timecode, muted audio badge, and title overlay
class SilentVideoPreviewPlayer extends StatefulWidget {
  final VideoTemplate template;
  final bool isSelected;
  final double aspectRatio;
  final BorderRadius? borderRadius;

  const SilentVideoPreviewPlayer({
    super.key,
    required this.template,
    this.isSelected = false,
    this.aspectRatio = 16 / 9,
    this.borderRadius,
  });

  @override
  State<SilentVideoPreviewPlayer> createState() =>
      _SilentVideoPreviewPlayerState();
}

class _SilentVideoPreviewPlayerState extends State<SilentVideoPreviewPlayer>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.template;
    return ClipRRect(
      borderRadius: widget.borderRadius ??
          const BorderRadius.vertical(top: Radius.circular(10)),
      child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: AnimatedBuilder(
          animation: _animController,
          builder: (context, child) {
            final progress = _animController.value;
            final currentSecond = (1 + (progress * 3.99).floor()).clamp(1, 4);

            return Stack(
              fit: StackFit.expand,
              children: [
                // Animated dynamic motion gradient background
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment(-1.0 + (progress * 1.5), -1.0),
                      end: Alignment(1.0 - (progress * 1.0), 1.0),
                      colors: t.gradientColors,
                    ),
                  ),
                ),

                // Subtle motion shimmer / scanline wave overlay
                Positioned.fill(
                  child: CustomPaint(
                    painter: VideoScanlinePainter(progress),
                  ),
                ),

                // Center camera viewfinder watermark
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.35),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2)),
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      size: 26,
                      color: Colors.white70,
                    ),
                  ),
                ),

                // TOP BAR OVERLAY: REC dot, timecode, and MUTED NO SOUND badge
                Positioned(
                  top: 8,
                  left: 8,
                  right: 8,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // REC Indicator
                      Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: (progress * 2).floor() % 2 == 0
                                  ? const Color(0xFFEF4444)
                                  : const Color(0x66EF4444),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'REC 00:0$currentSecond',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 0.5,
                              shadows: [
                                Shadow(
                                    color: Colors.black,
                                    blurRadius: 4,
                                    offset: Offset(0, 1)),
                              ],
                            ),
                          ),
                        ],
                      ),

                      // SILENT / NO SOUND BADGE
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.volume_off_rounded,
                                size: 11, color: Colors.white),
                            SizedBox(width: 4),
                            Text(
                              'NO SOUND',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // BOTTOM OVERLAY: TITLE IN IT + Camera Motion Tag + Looping Progress
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(10, 20, 10, 6),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Color(0x99000000),
                          Color(0xEE000000),
                        ],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Title inside video display!
                        Text(
                          t.title,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: -0.2,
                            shadows: [
                              Shadow(
                                  color: Colors.black,
                                  blurRadius: 6,
                                  offset: Offset(0, 1)),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            const Icon(Icons.videocam_outlined,
                                size: 11, color: Color(0xFF38BDF8)),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                t.cameraMotion,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Color(0xFFE2E8F0),
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                t.duration,
                                style: const TextStyle(
                                    fontSize: 9,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // Looping animated playback progress bar
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 2,
                            backgroundColor: Colors.white24,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                                Color(0xFF38BDF8)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class VideoScanlinePainter extends CustomPainter {
  final double progress;
  VideoScanlinePainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1.0;
    // Horizontal cinematic scanlines
    for (double y = 0; y < size.height; y += 8) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(VideoScanlinePainter oldDelegate) =>
      oldDelegate.progress != progress;
}
