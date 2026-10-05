import 'dart:async';
import 'package:flutter/material.dart';

import '../../../../theme/app_theme.dart';
import '../../data/services/instance_status_client.dart';

enum ProvisioningState {
  provisioning,
  downloadingModel,
  ready,
  failed,
}

/// Full-screen branded provisioning status screen for newly rented Cloud GPUs.
/// Displays Cosmic-Gen AI styling, real-time WebSocket state streaming,
/// stepper progress, and auto-navigates into the studio upon readiness.
class InstanceProvisioningScreen extends StatefulWidget {
  final String instanceId;
  final String gpuName;
  final List<String> selectedModelIds;
  final bool isDark;
  final VoidCallback? onReturnToStudio;

  const InstanceProvisioningScreen({
    super.key,
    required this.instanceId,
    this.gpuName = 'Cloud GPU',
    this.selectedModelIds = const [],
    required this.isDark,
    this.onReturnToStudio,
  });

  @override
  State<InstanceProvisioningScreen> createState() =>
      _InstanceProvisioningScreenState();
}

class _InstanceProvisioningScreenState
    extends State<InstanceProvisioningScreen>
    with SingleTickerProviderStateMixin {
  final _statusClient = InstanceStatusClient.instance;

  ProvisioningState _state = ProvisioningState.provisioning;
  String? _errorMessage;
  String? _deviceInfo;
  bool _isConnecting = true;
  Timer? _navigationTimer;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _connectToStatusStream();
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    _pulseController.dispose();
    _statusClient.disconnect();
    super.dispose();
  }

  Future<void> _connectToStatusStream() async {
    if (!mounted) return;
    setState(() {
      _isConnecting = true;
      _errorMessage = null;
    });

    await _statusClient.connect(
      instanceId: widget.instanceId,
      onStatusUpdate: _handleStatusUpdate,
      onError: _handleClientError,
    );

    if (mounted) {
      setState(() => _isConnecting = false);
    }
  }

  void _handleStatusUpdate(Map<String, dynamic> payload) {
    if (!mounted) return;
    final rawStatus = (payload['status'] ?? '').toString().toUpperCase();
    final details = payload['details'] as Map<String, dynamic>?;

    setState(() {
      _isConnecting = false;
      if (details != null && details['deviceName'] != null) {
        _deviceInfo = details['deviceName'].toString();
      }

      switch (rawStatus) {
        case 'DOWNLOADING_MODEL':
          _state = ProvisioningState.downloadingModel;
          break;
        case 'READY':
        case 'RUNNING':
          _state = ProvisioningState.ready;
          _scheduleAutoNavigation();
          break;
        case 'FAILED':
        case 'ERROR':
        case 'STOPPED':
          _state = ProvisioningState.failed;
          _errorMessage = details?['reason']?.toString() ??
              'Provisioning failed or timed out.';
          break;
        case 'PROVISIONING':
        default:
          _state = ProvisioningState.provisioning;
          break;
      }
    });
  }

  void _handleClientError(String error) {
    if (!mounted) return;
    setState(() {
      _isConnecting = false;
      _errorMessage = error;
    });
  }

  void _scheduleAutoNavigation() {
    _navigationTimer?.cancel();
    _navigationTimer = Timer(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      // Close the provisioning screen
      Navigator.of(context).pop(true);
      // Navigate to generation studio
      widget.onReturnToStudio?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.isDark ? LuminaColors.darkBg : LuminaColors.lightBg;
    final surface =
        widget.isDark ? LuminaColors.darkSurface : LuminaColors.lightSurface;
    final card = widget.isDark ? LuminaColors.darkCard : LuminaColors.lightCard;
    final border =
        widget.isDark ? LuminaColors.darkBorder : LuminaColors.lightBorder;
    final text = widget.isDark ? LuminaColors.darkText : LuminaColors.lightText;
    final muted =
        widget.isDark ? LuminaColors.darkMuted : LuminaColors.lightMuted;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Stack(
          children: [
            // Top back button
            Positioned(
              top: 16,
              left: 16,
              child: IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: text),
                tooltip: 'Back to Marketplace',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),

            // Top-right brand badge
            Positioned(
              top: 20,
              right: 24,
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFFEF4444),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'COSMIC-GEN AI CLOUD',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: muted,
                    ),
                  ),
                ],
              ),
            ),

            // Main center card
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 540),
                  child: Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: card,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: border),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(widget.isDark ? 0.35 : 0.08),
                          blurRadius: 30,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Animated Hero Icon with Glow
                        _buildHeroGraphic(),

                        const SizedBox(height: 28),

                        // Title
                        Text(
                          _getTitleText(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: text,
                            letterSpacing: -0.3,
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Description / subtitle
                        Text(
                          _getSubtitleText(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: muted,
                            height: 1.45,
                          ),
                        ),

                        if (_deviceInfo != null && _state == ProvisioningState.ready) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0x1A10B981),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: const Color(0x3310B981)),
                            ),
                            child: Text(
                              _deviceInfo!,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF10B981),
                              ),
                            ),
                          ),
                        ],

                        const SizedBox(height: 32),

                        // Stepper timeline
                        _buildProgressStepper(border, muted, text),

                        const SizedBox(height: 28),

                        // Action button or info box based on state
                        _buildBottomActions(muted, text),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroGraphic() {
    Color primaryColor;
    IconData iconData;

    switch (_state) {
      case ProvisioningState.provisioning:
        primaryColor = LuminaColors.cyan;
        iconData = Icons.memory_rounded;
        break;
      case ProvisioningState.downloadingModel:
        primaryColor = LuminaColors.amber;
        iconData = Icons.cloud_download_rounded;
        break;
      case ProvisioningState.ready:
        primaryColor = const Color(0xFF10B981);
        iconData = Icons.check_circle_rounded;
        break;
      case ProvisioningState.failed:
        primaryColor = const Color(0xFFEF4444);
        iconData = Icons.error_outline_rounded;
        break;
    }

    return ScaleTransition(
      scale: (_state == ProvisioningState.provisioning ||
              _state == ProvisioningState.downloadingModel)
          ? _pulseAnimation
          : const AlwaysStoppedAnimation(1.0),
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: primaryColor.withOpacity(0.12),
          border: Border.all(color: primaryColor.withOpacity(0.4), width: 2),
          boxShadow: [
            BoxShadow(
              color: primaryColor.withOpacity(0.25),
              blurRadius: 24,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (_state == ProvisioningState.provisioning ||
                _state == ProvisioningState.downloadingModel)
              SizedBox(
                width: 90,
                height: 90,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                ),
              ),
            Icon(
              iconData,
              size: 44,
              color: primaryColor,
            ),
          ],
        ),
      ),
    );
  }

  String _getTitleText() {
    switch (_state) {
      case ProvisioningState.provisioning:
        return 'Spinning up ${widget.gpuName}';
      case ProvisioningState.downloadingModel:
        return 'Instance Ready!';
      case ProvisioningState.ready:
        return 'Cosmic-Gen GPU Ready!';
      case ProvisioningState.failed:
        return 'Launch Failed';
    }
  }

  String _getSubtitleText() {
    switch (_state) {
      case ProvisioningState.provisioning:
        return 'Spinning up your GPU — ready in 2–5 minutes. R2 stream channels are configuring.';
      case ProvisioningState.downloadingModel:
        final modelCount = widget.selectedModelIds.length;
        final modelLabel = modelCount > 1 ? '$modelCount models' : 'your model';
        return 'Instance ready! Downloading $modelLabel now — almost there.';
      case ProvisioningState.ready:
        return 'Inference engine is online and calibrated. Redirecting to your Creative Studio...';
      case ProvisioningState.failed:
        return _errorMessage ??
            'We encountered an issue allocating the selected GPU contract. You have not been billed.';
    }
  }

  Widget _buildProgressStepper(Color border, Color muted, Color text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: widget.isDark ? const Color(0x12FFFFFF) : const Color(0x06000000),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Column(
        children: [
          _buildStepRow(
            stepNumber: 1,
            title: 'Allocate & Boot GPU',
            isActive: _state == ProvisioningState.provisioning,
            isDone: _state == ProvisioningState.downloadingModel ||
                _state == ProvisioningState.ready,
            isFailed: _state == ProvisioningState.failed,
            text: text,
            muted: muted,
          ),
          const SizedBox(height: 12),
          _buildStepRow(
            stepNumber: 2,
            title: 'Stream Model Weights',
            isActive: _state == ProvisioningState.downloadingModel,
            isDone: _state == ProvisioningState.ready,
            isFailed: _state == ProvisioningState.failed &&
                _state != ProvisioningState.provisioning,
            text: text,
            muted: muted,
          ),
          const SizedBox(height: 12),
          _buildStepRow(
            stepNumber: 3,
            title: 'Calibrate Inference Engine',
            isActive: _state == ProvisioningState.ready,
            isDone: _state == ProvisioningState.ready,
            isFailed: false,
            text: text,
            muted: muted,
          ),
        ],
      ),
    );
  }

  Widget _buildStepRow({
    required int stepNumber,
    required String title,
    required bool isActive,
    required bool isDone,
    required bool isFailed,
    required Color text,
    required Color muted,
  }) {
    Widget indicator;
    if (isDone) {
      indicator = const Icon(Icons.check_circle_rounded,
          size: 18, color: Color(0xFF10B981));
    } else if (isActive) {
      indicator = const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation(LuminaColors.cyan),
        ),
      );
    } else if (isFailed) {
      indicator = const Icon(Icons.cancel_rounded,
          size: 18, color: Color(0xFFEF4444));
    } else {
      indicator = Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: muted.withOpacity(0.5), width: 1.5),
        ),
      );
    }

    return Row(
      children: [
        SizedBox(width: 22, height: 22, child: Center(child: indicator)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isActive || isDone ? FontWeight.w600 : FontWeight.w400,
              color: isActive || isDone ? text : muted,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomActions(Color muted, Color text) {
    if (_state == ProvisioningState.failed || _errorMessage != null) {
      return Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: text,
                  side: BorderSide(
                      color: widget.isDark
                          ? LuminaColors.darkBorder
                          : LuminaColors.lightBorder),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry Connection'),
                onPressed: _connectToStatusStream,
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: LuminaColors.primaryEnd,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.storefront_rounded, size: 18),
                label: const Text('Back to Marketplace'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ],
      );
    }

    if (_state == ProvisioningState.ready) {
      return ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF10B981),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        icon: const Icon(Icons.arrow_forward_rounded, size: 18),
        label: const Text('Open Creative Studio Now',
            style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: () {
          _navigationTimer?.cancel();
          Navigator.of(context).pop(true);
          widget.onReturnToStudio?.call();
        },
      );
    }

    // Default provisioning / downloading state
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: muted,
          ),
          icon: const Icon(Icons.visibility_off_outlined, size: 16),
          label: const Text('Run in background & browse studio',
              style: TextStyle(fontSize: 12)),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
