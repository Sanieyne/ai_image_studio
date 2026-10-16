import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/live_cam_models.dart';
import '../services/api_service.dart';

/// Deep-Live-Cam Real-Time Face Swapping Dialog.
/// Allows live webcam cloning for web video calls (Zoom, Discord, Meet, OBS).
class DeepLiveCamDialog extends StatefulWidget {
  final ApiService? apiService;

  const DeepLiveCamDialog({
    super.key,
    this.apiService,
  });

  static Future<void> show(BuildContext context, {ApiService? apiService}) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => DeepLiveCamDialog(apiService: apiService),
    );
  }

  @override
  State<DeepLiveCamDialog> createState() => _DeepLiveCamDialogState();
}

class _DeepLiveCamDialogState extends State<DeepLiveCamDialog> {
  late final ApiService _apiService;
  Timer? _frameTimer;

  bool _isLive = false;
  bool _isStarting = false;
  bool _enhanceFace = false;
  bool _mirrorCamera = true;
  String _activeTargetName = 'Elon Musk';
  double _fps = 0.0;
  String? _frameBase64;
  String? _statusMessage;
  List<LiveCamPreset> _presets = [];
  bool _copiedUrl = false;

  @override
  void initState() {
    super.initState();
    _apiService = widget.apiService ?? ApiService();
    _loadPresetsAndStatus();
  }

  @override
  void dispose() {
    _frameTimer?.cancel();
    _apiService.stopLiveCam();
    super.dispose();
  }

  Future<void> _loadPresetsAndStatus() async {
    final presets = await _apiService.getLiveCamPresets();
    final status = await _apiService.getLiveCamStatus();
    if (mounted) {
      setState(() {
        _presets = presets;
        _isLive = status.active;
        if (status.sourceName != null && status.sourceName!.isNotEmpty) {
          _activeTargetName = status.sourceName!;
        }
      });
      if (_isLive) {
        _startFramePolling();
      }
    }
  }

  void _startFramePolling() {
    _frameTimer?.cancel();
    // Poll at ~20 fps for responsive live UI feedback
    _frameTimer = Timer.periodic(const Duration(milliseconds: 50), (_) async {
      if (!_isLive || !mounted) return;
      final res = await _apiService.getLiveCamFrame();
      if (mounted) {
        setState(() {
          _fps = res.fps;
          if (res.sourceName.isNotEmpty) {
            _activeTargetName = res.sourceName;
          }
          if (res.frameBase64 != null) {
            _frameBase64 = res.frameBase64;
          }
        });
      }
    });
  }

  Future<void> _toggleLive() async {
    if (_isStarting) return;

    if (_isLive) {
      setState(() => _isStarting = true);
      final res = await _apiService.stopLiveCam();
      _frameTimer?.cancel();
      if (mounted) {
        setState(() {
          _isLive = false;
          _isStarting = false;
          _fps = 0.0;
          _statusMessage = res.message;
        });
      }
    } else {
      setState(() {
        _isStarting = true;
        _statusMessage = 'Initializing live AI models...';
      });
      final res = await _apiService.startLiveCam(
        enhance: _enhanceFace,
        mirror: _mirrorCamera,
      );
      if (mounted) {
        setState(() {
          _isStarting = false;
          _isLive = res.success;
          _statusMessage = res.message;
          if (res.sourceName != null) {
            _activeTargetName = res.sourceName!;
          }
        });
        if (_isLive) {
          _startFramePolling();
        }
      }
    }
  }

  Future<void> _selectPreset(LiveCamPreset preset) async {
    setState(() => _activeTargetName = preset.name);
    final res = await _apiService.setLiveCamSource(presetName: preset.name);
    if (mounted) {
      setState(() {
        _statusMessage = res.message;
      });
    }
  }

  void _copyStreamUrl() {
    final url = _apiService.getLiveCamStreamUrl();
    Clipboard.setData(ClipboardData(text: url));
    setState(() => _copiedUrl = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copiedUrl = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final streamUrl = _apiService.getLiveCamStreamUrl();

    return Dialog(
      backgroundColor: const Color(0xFF13171F),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF232A3B), width: 1.5),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960, maxHeight: 720),
        child: Column(
          children: [
            // Header Bar
            _buildHeader(theme),
            const Divider(color: Color(0xFF232A3B), height: 1),

            // Main Body: Video Feed (Left) & Controls/Presets (Right)
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Left: Live Video Preview
                  Expanded(
                    flex: 6,
                    child: _buildVideoFeed(),
                  ),
                  const VerticalDivider(color: Color(0xFF232A3B), width: 1),

                  // Right: Target Selection & Stream Controls
                  Expanded(
                    flex: 4,
                    child: _buildControlPanel(theme, streamUrl),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFF0F1219),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF7C3AED).withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.face_retouching_natural_rounded, color: Color(0xFFA78BFA), size: 20),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Live Video Call DeepFace',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  letterSpacing: 0.3,
                ),
              ),
              Text(
                'Deep-Live-Cam Engine • Real-time Face Replacement',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.55),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const Spacer(),
          // Live status badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _isLive ? const Color(0xFF10B981).withOpacity(0.15) : Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _isLive ? const Color(0xFF10B981).withOpacity(0.4) : Colors.white.withOpacity(0.1),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _isLive ? const Color(0xFF10B981) : Colors.grey,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _isLive ? 'LIVE STREAMING' : 'STANDBY',
                  style: TextStyle(
                    color: _isLive ? const Color(0xFF34D399) : Colors.grey,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.grey, size: 20),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  Widget _buildVideoFeed() {
    return Container(
      color: Colors.black,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Frame display
          if (_frameBase64 != null)
            Image.memory(
              base64Decode(_frameBase64!.split(',').last),
              fit: BoxFit.contain,
              width: double.infinity,
              height: double.infinity,
              gaplessPlayback: true,
            )
          else
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.videocam_outlined,
                  size: 56,
                  color: Colors.white.withOpacity(0.2),
                ),
                const SizedBox(height: 14),
                Text(
                  _isLive ? 'Acquiring video frames...' : 'Camera Standby',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _isLive ? 'InsightFace + INSwapper active' : 'Click "Start Live Cam" below to begin',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.35),
                    fontSize: 12,
                  ),
                ),
              ],
            ),

          // Floating Overlay: Active Target Pill & FPS
          Positioned(
            top: 14,
            left: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.person_pin_circle_rounded, color: Color(0xFFA78BFA), size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'Target: $_activeTargetName',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (_isLive)
            Positioned(
              top: 14,
              right: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: Text(
                  '${_fps.toStringAsFixed(1)} FPS',
                  style: const TextStyle(
                    color: Color(0xFF34D399),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildControlPanel(ThemeData theme, String streamUrl) {
    return Container(
      color: const Color(0xFF13171F),
      padding: const EdgeInsets.all(18),
      child: ListView(
        children: [
          // 1. Target Face Preset Selector
          const Text(
            'SELECT CLONE TARGET',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),
          _buildPresetSelector(),

          const SizedBox(height: 20),
          const Divider(color: Color(0xFF232A3B), height: 1),
          const SizedBox(height: 18),

          // 2. Main Live Stream Toggle Button
          ElevatedButton.icon(
            onPressed: _isStarting ? null : _toggleLive,
            icon: _isStarting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Icon(_isLive ? Icons.stop_rounded : Icons.play_arrow_rounded),
            label: Text(
              _isStarting
                  ? 'Connecting...'
                  : _isLive
                      ? 'Stop Live Cam'
                      : 'Start Live Cam',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _isLive ? const Color(0xFFEF4444) : const Color(0xFF10B981),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
          ),

          if (_statusMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              _statusMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 11,
              ),
            ),
          ],

          const SizedBox(height: 20),
          const Divider(color: Color(0xFF232A3B), height: 1),
          const SizedBox(height: 18),

          // 3. Settings Toggles
          const Text(
            'VIDEO STREAM SETTINGS',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          _buildSettingRow(
            title: 'Mirror Camera',
            subtitle: 'Flip preview horizontally',
            value: _mirrorCamera,
            onChanged: (val) => setState(() => _mirrorCamera = val),
          ),
          const SizedBox(height: 10),
          _buildSettingRow(
            title: 'GFPGAN Face Enhancer',
            subtitle: 'Ultra-crisp face resolution boost',
            value: _enhanceFace,
            onChanged: (val) => setState(() => _enhanceFace = val),
          ),

          const SizedBox(height: 16),
          const Divider(color: Color(0xFF232A3B), height: 1),
          const SizedBox(height: 16),

          // 4. Web Video Call Integration (Zoom / Meet / Discord / OBS)
          const Text(
            'CONNECT TO ZOOM & DISCORD',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F1219),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF232A3B)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.stream_rounded, color: Color(0xFFA78BFA), size: 16),
                    const SizedBox(width: 8),
                    const Text('Live Stream URL', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    InkWell(
                      onTap: _copyStreamUrl,
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        child: Text(
                          _copiedUrl ? 'COPIED!' : 'COPY',
                          style: TextStyle(
                            color: _copiedUrl ? const Color(0xFF34D399) : const Color(0xFFA78BFA),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SelectableText(
                  streamUrl,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.55),
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '💡 Paste into OBS (Browser Source) -> Click "Start Virtual Camera" -> Select "OBS Virtual Camera" in Zoom, Discord, or Google Meet.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.4),
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetSelector() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _presets.map((preset) {
        final isSelected = _activeTargetName.toLowerCase() == preset.name.toLowerCase();
        return InkWell(
          onTap: () => _selectPreset(preset),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF7C3AED).withOpacity(0.2) : const Color(0xFF1E2330),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? const Color(0xFFA78BFA) : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.account_circle_rounded,
                  color: isSelected ? const Color(0xFFA78BFA) : Colors.grey,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  preset.name,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSettingRow({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.45),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          activeColor: const Color(0xFFA78BFA),
          activeTrackColor: const Color(0xFF7C3AED).withOpacity(0.5),
          inactiveThumbColor: Colors.grey.shade400,
          inactiveTrackColor: const Color(0xFF1E2330),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
