import 'dart:async';
import 'package:flutter/material.dart';

import '../models/camera_frame_result.dart';
import '../services/api_service.dart';

/// Standalone webcam capture and real-time face framing dialog.
///
/// Features:
/// - 1.5s live polling from python_engine InsightFace endpoint.
/// - Dynamic visual framing feedback pill (good framing vs too far / too close / off center / no face).
/// - Real-time face bounding box overlay.
/// - Capture button enabled only upon confident, well-framed face detection.
/// - Confirmed snapshot saved locally to temporary staging directory.
/// - Automatic hardware release on dialog dismissal or inactivity.
class CameraCaptureDialog extends StatefulWidget {
  final ApiService? apiService;

  const CameraCaptureDialog({
    super.key,
    this.apiService,
  });

  /// Convenience helper to display the modal dialog.
  static Future<CameraCaptureResult?> show(
    BuildContext context, {
    ApiService? apiService,
  }) {
    return showDialog<CameraCaptureResult>(
      context: context,
      barrierDismissible: true,
      builder: (context) => CameraCaptureDialog(apiService: apiService),
    );
  }

  @override
  State<CameraCaptureDialog> createState() => _CameraCaptureDialogState();
}

class _CameraCaptureDialogState extends State<CameraCaptureDialog> {
  late final ApiService _apiService;
  Timer? _pollTimer;

  bool _isLoading = true;
  bool _isCapturing = false;
  CameraFrameResult? _latestFrame;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _apiService = widget.apiService ?? ApiService();
    _fetchFrame();
    // Poll every 1.5 seconds matching backend analysis cadence
    _pollTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (!_isCapturing && mounted) {
        _fetchFrame();
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    // Guarantee camera hardware is freed immediately upon dismissal
    _apiService.releaseCamera();
    super.dispose();
  }

  Future<void> _fetchFrame() async {
    final result = await _apiService.getCameraFrame();
    if (!mounted) return;

    setState(() {
      _isLoading = false;
      if (result.success) {
        _latestFrame = result;
        _errorMessage = null;
      } else {
        _errorMessage = result.feedbackText.isNotEmpty
            ? result.feedbackText
            : (result.error ?? 'Unable to connect to camera feed');
      }
    });
  }

  Future<void> _handleCapture() async {
    if (_latestFrame == null || !_latestFrame!.canCapture || _isCapturing) return;

    setState(() {
      _isCapturing = true;
    });

    try {
      final captureResult = await _apiService.captureCameraFrame();
      if (!mounted) return;

      if (captureResult.success) {
        setState(() {
          _capturedResult = captureResult;
          _isCapturing = false;
        });

        // Briefly show confirmation before popping result
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Face captured and saved to ${captureResult.fileName}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 2),
          ),
        );

        Navigator.of(context).pop(captureResult);
      } else {
        setState(() {
          _errorMessage = captureResult.feedbackText.isNotEmpty
              ? captureResult.feedbackText
              : 'Capture failed';
          _isCapturing = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Capture failed: $e';
        _isCapturing = false;
      });
    }
  }

  Color _getStatusColor(String code, bool canCapture) {
    if (canCapture || code == 'good') {
      return const Color(0xFF10B981); // Emerald Green
    }
    switch (code) {
      case 'off_center':
      case 'too_far':
      case 'too_close':
      case 'low_confidence':
        return const Color(0xFFF59E0B); // Amber / Yellow
      case 'no_face':
        return const Color(0xFF94A3B8); // Slate / Muted
      default:
        return const Color(0xFFEF4444); // Red / Error
    }
  }

  IconData _getStatusIcon(String code, bool canCapture) {
    if (canCapture || code == 'good') {
      return Icons.check_circle_rounded;
    }
    switch (code) {
      case 'off_center':
        return Icons.pan_tool_alt_rounded;
      case 'too_far':
        return Icons.zoom_in_rounded;
      case 'too_close':
        return Icons.zoom_out_rounded;
      case 'no_face':
        return Icons.face_retouching_off_rounded;
      default:
        return Icons.info_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final frame = _latestFrame;
    final canCapture = frame != null && frame.canCapture && !_isCapturing;
    final statusColor = _getStatusColor(frame?.feedbackCode ?? '', frame?.canCapture ?? false);
    final statusIcon = _getStatusIcon(frame?.feedbackCode ?? '', frame?.canCapture ?? false);

    return Dialog(
      backgroundColor: const Color(0xFF18191E),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF2A2D35), width: 1),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- Header ---
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF23262F),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.camera_alt_outlined, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Webcam Capture',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'Live InsightFace AntelopeV2 framing detection',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0xFF2A2D35), height: 1),

            // --- Camera Feed Area ---
            Padding(
              padding: const EdgeInsets.all(16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Container(
                    color: const Color(0xFF0F1014),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Raw Image Display
                        if (frame?.imageBytes != null)
                          Image.memory(
                            frame!.imageBytes!,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                          )
                        else if (_isLoading)
                          const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 32,
                                  height: 32,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                    color: Color(0xFF6366F1),
                                  ),
                                ),
                                SizedBox(height: 12),
                                Text(
                                  'Initializing camera & face model...',
                                  style: TextStyle(color: Colors.white70, fontSize: 13),
                                ),
                              ],
                            ),
                          )
                        else
                          Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.videocam_off_outlined, color: Colors.white38, size: 48),
                                const SizedBox(height: 8),
                                Text(
                                  _errorMessage ?? 'No camera feed available',
                                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 12),
                                ElevatedButton.icon(
                                  onPressed: _fetchFrame,
                                  icon: const Icon(Icons.refresh, size: 16),
                                  label: const Text('Retry'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF2A2D35),
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // Face Bounding Box Overlay
                        if (frame?.faceMetrics != null && frame?.width != null && frame?.height != null)
                          CustomPaint(
                            painter: _FaceBboxPainter(
                              bbox: frame!.faceMetrics!.bbox,
                              frameWidth: frame.width!,
                              frameHeight: frame.height!,
                              statusColor: statusColor,
                              canCapture: frame.canCapture,
                            ),
                          ),

                        // Status & Framing Feedback Pill Overlay
                        if (frame != null)
                          Positioned(
                            bottom: 16,
                            left: 16,
                            right: 16,
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF111317).withValues(alpha: 0.9),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color: statusColor.withValues(alpha: 0.8),
                                    width: 1.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: statusColor.withValues(alpha: 0.25),
                                      blurRadius: 12,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(statusIcon, color: statusColor, size: 18),
                                    const SizedBox(width: 8),
                                    Text(
                                      frame.feedbackText,
                                      style: TextStyle(
                                        color: statusColor,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                        // Capturing Spinner Overlay
                        if (_isCapturing)
                          Container(
                            color: Colors.black.withValues(alpha: 0.6),
                            child: const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(
                                    strokeWidth: 3,
                                    color: Color(0xFF10B981),
                                  ),
                                  SizedBox(height: 12),
                                  Text(
                                    'Saving high-quality snapshot...',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
            ),

            // --- Footer Actions ---
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Row(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: frame != null && frame.success ? const Color(0xFF10B981) : Colors.amber,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Engine Active',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(foregroundColor: Colors.white70),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: canCapture ? _handleCapture : null,
                    icon: _isCapturing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.camera, size: 18),
                    label: Text(_isCapturing ? 'Capturing...' : 'Capture Photo'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      disabledBackgroundColor: const Color(0xFF2A2D35),
                      foregroundColor: Colors.white,
                      disabledForegroundColor: Colors.white38,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom painter for the live face bounding box and corner brackets.
class _FaceBboxPainter extends CustomPainter {
  final List<int> bbox;
  final int frameWidth;
  final int frameHeight;
  final Color statusColor;
  final bool canCapture;

  const _FaceBboxPainter({
    required this.bbox,
    required this.frameWidth,
    required this.frameHeight,
    required this.statusColor,
    required this.canCapture,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (bbox.length < 4 || frameWidth <= 0 || frameHeight <= 0) return;

    // Scale from frame coordinates to widget canvas size
    final scaleX = size.width / frameWidth;
    final scaleY = size.height / frameHeight;

    final left = bbox[0] * scaleX;
    final top = bbox[1] * scaleY;
    final right = bbox[2] * scaleX;
    final bottom = bbox[3] * scaleY;
    final rect = Rect.fromLTRB(left, top, right, bottom);

    // Subtle box border
    final boxPaint = Paint()
      ..color = statusColor.withValues(alpha: canCapture ? 0.8 : 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8)), boxPaint);

    // Corner guides
    final cornerPaint = Paint()
      ..color = statusColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    final cornerLen = (right - left) * 0.15;

    // Top-left
    canvas.drawLine(Offset(left, top + cornerLen), Offset(left, top), cornerPaint);
    canvas.drawLine(Offset(left, top), Offset(left + cornerLen, top), cornerPaint);

    // Top-right
    canvas.drawLine(Offset(right - cornerLen, top), Offset(right, top), cornerPaint);
    canvas.drawLine(Offset(right, top), Offset(right, top + cornerLen), cornerPaint);

    // Bottom-left
    canvas.drawLine(Offset(left, bottom - cornerLen), Offset(left, bottom), cornerPaint);
    canvas.drawLine(Offset(left, bottom), Offset(left + cornerLen, bottom), cornerPaint);

    // Bottom-right
    canvas.drawLine(Offset(right - cornerLen, bottom), Offset(right, bottom), cornerPaint);
    canvas.drawLine(Offset(right, bottom), Offset(right, bottom - cornerLen), cornerPaint);
  }

  @override
  bool shouldRepaint(covariant _FaceBboxPainter oldDelegate) {
    return oldDelegate.bbox != bbox ||
        oldDelegate.statusColor != statusColor ||
        oldDelegate.canCapture != canCapture;
  }
}
