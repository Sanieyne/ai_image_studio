import 'dart:async';
import 'package:flutter/material.dart';

import '../../../../theme/app_theme.dart';
import '../../../../services/api_service.dart';
import '../../../../services/database_service.dart';
import '../../data/services/cloud_api_service.dart';
import '../../data/services/instance_status_client.dart';

enum ProvisioningState {
  provisioning,
  downloadingModel,
  ready,
  failed,
}

/// Represents individual model status within the provisioning stream
class ModelProvisioningItem {
  final String modelId;
  final String status; // queued | downloading | loading | ready | failed
  final double progressPercent;
  final String? error;
  final bool loadedInVram;

  const ModelProvisioningItem({
    required this.modelId,
    required this.status,
    this.progressPercent = 0.0,
    this.error,
    this.loadedInVram = false,
  });

  factory ModelProvisioningItem.fromMap(Map<String, dynamic> map) {
    return ModelProvisioningItem(
      modelId: (map['modelId'] ?? '').toString(),
      status: (map['status'] ?? 'queued').toString().toLowerCase(),
      progressPercent: (map['progressPercent'] as num?)?.toDouble() ?? 0.0,
      error: map['error']?.toString(),
      loadedInVram: map['loadedInVram'] == true,
    );
  }

  String get displayName {
    switch (modelId.toLowerCase()) {
      case 'realesrgan-x4plus':
      case 'amd/realesrgan-x4plus':
        return 'Real-ESRGAN 4x+';
      case 'fashn-vton-1.5':
      case 'fashn-ai/fashn-vton-1.5':
        return 'FASHN VTON 1.5';
      case 'breeze-tts-2':
      case 'breezeblue/breeze-tts-2':
        return 'Breeze TTS 2';
      case 'chatterbox-tts':
      case 'resembleai/chatterbox':
        return 'Chatterbox TTS';
      case 'sdxl-base-1.0':
      case 'stabilityai/stable-diffusion-xl-base-1.0':
        return 'SDXL Base 1.0';
      case 'flux-kontext-dev':
      case 'black-forest-labs/flux.1-kontext-dev':
        return 'FLUX.1 Kontext [dev]';
      case 'z-image-turbo':
      case 'tongyi-mai/z-image-turbo':
        return 'Z-Image Turbo';
      case 'qwen-image-2.1':
      case 'qwen/qwen-image-2.1':
        return 'Qwen-Image 2.1';
      case 'wan-2.1-t2v-1.3b':
      case 'wan-ai/wan2.1-t2v-1.3b-diffusers':
        return 'Wan 2.1 T2V 1.3B';
      case 'wan-2.1-i2v-14b':
      case 'wan-ai/wan2.1-i2v-14b-480p-diffusers':
        return 'Wan 2.1 I2V 14B';
      case 'wan-2.2-animate-14b':
      case 'wan-ai/wan2.2-animate-14b':
        return 'Wan 2.2 Animate 14B';
      case 'minimax-h3':
      case 'minimaxai/minimax-h3':
        return 'MiniMax-H3 Video+Audio';
      default:
        return modelId
            .replaceAll('-', ' ')
            .replaceAll('_', ' ')
            .split(' ')
            .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
            .join(' ');
    }
  }

  String get categoryBadge {
    final lower = modelId.toLowerCase();
    if (lower.contains('esrgan') || lower.contains('enhance')) return 'Upscaler';
    if (lower.contains('vton') || lower.contains('tryon')) return 'Virtual Try-On';
    if (lower.contains('tts') || lower.contains('voice') || lower.contains('chatterbox')) return 'Voice AI';
    if (lower.contains('wan') || lower.contains('minimax') || lower.contains('video')) return 'Video Gen';
    return 'Image Gen';
  }
}

/// Full-screen branded provisioning status screen for newly rented Cloud GPUs.
/// Displays Cosmic-Gen AI styling, real-time WebSocket state streaming,
/// per-model live progress tracking, early studio access, and auto-navigation.
class InstanceProvisioningScreen extends StatefulWidget {
  final String instanceId;
  final String gpuName;
  final List<String> selectedModelIds;
  final bool isDark;
  final VoidCallback? onReturnToStudio;
  final ProvisioningState? initialPreviewState;
  final List<ModelProvisioningItem>? initialModels;
  final String? initialDeviceInfo;
  final bool disableAutoConnect;

  /// GET /gpu/instances/:id, used while the live socket is not connected.
  /// Defaults to CloudApiService.fetchInstance; tests pass a fake.
  final Future<Map<String, dynamic>?> Function(String instanceId)? fetchInstance;

  /// DELETE /gpu/instances/:id. Defaults to CloudApiService.stopInstance.
  final Future<Map<String, dynamic>?> Function(String instanceId)? stopInstance;

  /// How often the instance is polled while the socket is down.
  final Duration pollInterval;

  const InstanceProvisioningScreen({
    super.key,
    required this.instanceId,
    this.gpuName = 'Cloud GPU',
    this.selectedModelIds = const [],
    required this.isDark,
    this.onReturnToStudio,
    this.initialPreviewState,
    this.initialModels,
    this.initialDeviceInfo,
    this.disableAutoConnect = false,
    this.fetchInstance,
    this.stopInstance,
    this.pollInterval = const Duration(seconds: 5),
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
  List<ModelProvisioningItem> _models = [];
  String? _errorMessage;
  String? _deviceInfo;
  Timer? _navigationTimer;

  // Live progress from the backend (socket or polling).
  String? _stepMessage;
  int _elapsedSeconds = 0;
  double _creditsCharged = 0;
  double _creditsRefunded = 0;
  bool _socketConnected = false;
  String? _connectionNote;
  Timer? _pollTimer;
  Timer? _ticker;
  bool _stopping = false;
  bool _stoppedByUser = false;

  bool get _isTerminal => _state == ProvisioningState.failed;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    if (widget.initialPreviewState != null) {
      _state = widget.initialPreviewState!;
    }
    if (widget.initialDeviceInfo != null) {
      _deviceInfo = widget.initialDeviceInfo;
    }

    // Seed initial models list
    if (widget.initialModels != null) {
      _models = widget.initialModels!;
    } else if (widget.selectedModelIds.isNotEmpty) {
      _models = widget.selectedModelIds
          .map((id) => ModelProvisioningItem(
                modelId: id,
                status: 'queued',
                progressPercent: 0.0,
              ))
          .toList();
    }

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    if (!widget.disableAutoConnect) {
      _connectToStatusStream();
    }
    // Until the socket is open (and whenever it drops), poll the instance.
    if (!_isTerminal && widget.initialPreviewState == null) {
      _ensurePolling();
    }
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _isTerminal || _state == ProvisioningState.ready) return;
      setState(() => _elapsedSeconds += 1);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _ticker?.cancel();
    _navigationTimer?.cancel();
    _pulseController.dispose();
    _statusClient.disconnect();
    super.dispose();
  }

  Future<void> _connectToStatusStream() async {
    if (!mounted) return;
    setState(() {
      _errorMessage = null;
    });

    await _statusClient.connect(
      instanceId: widget.instanceId,
      onStatusUpdate: _handleStatusUpdate,
      onError: _handleClientError,
      onConnectionChanged: _handleConnectionChanged,
    );
  }

  void _handleConnectionChanged(bool connected) {
    if (!mounted) return;
    setState(() {
      _socketConnected = connected;
      if (connected) _connectionNote = null;
    });
    if (connected) {
      _pollTimer?.cancel();
      _pollTimer = null;
    } else {
      _ensurePolling();
    }
  }

  void _ensurePolling() {
    if (_pollTimer != null || _isTerminal || _state == ProvisioningState.ready) return;
    _pollOnce();
    _pollTimer = Timer.periodic(widget.pollInterval, (_) => _pollOnce());
  }

  Future<void> _pollOnce() async {
    if (!mounted || _socketConnected || _isTerminal) return;
    final fetch = widget.fetchInstance ?? CloudApiService.instance.fetchInstance;
    final data = await fetch(widget.instanceId);
    if (!mounted) return;
    if (data == null) {
      setState(() => _connectionNote = "Can't reach the server right now. Trying again every few seconds.");
      return;
    }
    if (_connectionNote != null && !_connectionNote!.startsWith('Live updates')) {
      setState(() => _connectionNote = 'Live updates are unavailable, so this page checks every few seconds.');
    }
    _applyInstance(data);
  }

  /// Applies GET /gpu/instances/:id as if it were a status message.
  void _applyInstance(Map<String, dynamic> data) {
    const toWs = {
      'provisioning': 'PROVISIONING',
      'downloading_model': 'DOWNLOADING_MODEL',
      'ready': 'READY',
      'running': 'RUNNING',
      'failed': 'FAILED',
      'stopped': 'STOPPED',
    };
    final status = toWs[(data['status'] ?? '').toString().toLowerCase()] ?? 'PROVISIONING';
    final progress = data['progress'] is Map ? Map<String, dynamic>.from(data['progress'] as Map) : null;
    final billing = data['billing'] is Map ? Map<String, dynamic>.from(data['billing'] as Map) : const {};
    final logs = data['provisioningLogs'] is List ? data['provisioningLogs'] as List : const [];
    String? lastLog;
    if (logs.isNotEmpty && logs.last is Map) lastLog = (logs.last as Map)['message']?.toString();
    _handleStatusUpdate({
      'status': status,
      'details': {
        if (data['pythonEngineUrl'] != null) 'pythonEngineUrl': data['pythonEngineUrl'],
        if (progress != null) 'progress': progress,
        'elapsedSeconds': data['elapsedSeconds'],
        'billing': billing,
        if (status == 'FAILED' || status == 'STOPPED') 'message': progress?['failureReason'] ?? lastLog,
      },
    });
  }

  Future<void> _confirmStop() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stop this GPU?'),
        content: Text(
          _state == ProvisioningState.ready
              ? 'The GPU will be shut down and destroyed. Time used so far stays charged.'
              : 'The GPU will be shut down and destroyed. It is not ready yet, so everything charged for it is refunded.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Keep running')),
          ElevatedButton(
            key: const ValueKey('confirm_stop_instance'),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), foregroundColor: Colors.white),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Stop GPU'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _stopping = true);
    final stop = widget.stopInstance ?? CloudApiService.instance.stopInstance;
    final result = await stop(widget.instanceId);
    if (!mounted) return;
    setState(() {
      _stopping = false;
      if (result == null) {
        _connectionNote = CloudApiService.instance.lastStopError ??
            'Could not stop the GPU. Check your connection and try again.';
        return;
      }
      _stoppedByUser = true;
      _state = ProvisioningState.failed;
      _errorMessage = 'You stopped this GPU.';
      _creditsCharged = (result['creditsCharged'] as num?)?.toDouble() ?? _creditsCharged;
      _creditsRefunded = (result['creditsRefunded'] as num?)?.toDouble() ?? _creditsRefunded;
      _navigationTimer?.cancel();
    });
    _pollTimer?.cancel();
    _pollTimer = null;
    _statusClient.disconnect();
  }

  void _handleStatusUpdate(Map<String, dynamic> payload) {
    if (!mounted) return;
    final rawStatus = (payload['status'] ?? '').toString().toUpperCase();
    final details = payload['details'] as Map<String, dynamic>?;

    setState(() {
      if (details != null && details['deviceName'] != null) {
        _deviceInfo = details['deviceName'].toString();
      }

      // Progress relayed by the backend: current step, elapsed time, credits.
      final progress = details?['progress'];
      if (progress is Map) {
        final msg = progress['message']?.toString();
        if (msg != null && msg.isNotEmpty) _stepMessage = msg;
        if (details?['models'] is! List && progress['models'] is List) {
          final fromProgress = (progress['models'] as List)
              .whereType<Map>()
              .map((m) => ModelProvisioningItem.fromMap(Map<String, dynamic>.from(m)))
              .toList();
          if (fromProgress.isNotEmpty) _models = fromProgress;
        }
      }
      final elapsed = details?['elapsedSeconds'];
      if (elapsed is num) _elapsedSeconds = elapsed.toInt();
      final billing = details?['billing'];
      final charged = details?['creditsCharged'] ?? (billing is Map ? billing['creditsCharged'] : null);
      final refunded = details?['creditsRefunded'] ?? (billing is Map ? billing['creditsRefunded'] : null);
      if (charged is num) _creditsCharged = charged.toDouble();
      if (refunded is num) _creditsRefunded = refunded.toDouble();

      // Update per-model list from incoming telemetry payload
      if (details != null && details['models'] is List) {
        final rawList = details['models'] as List;
        final updated = <ModelProvisioningItem>[];
        for (final item in rawList) {
          if (item is Map<String, dynamic>) {
            updated.add(ModelProvisioningItem.fromMap(item));
          }
        }
        if (updated.isNotEmpty) {
          _models = updated;
        }
      }

      final engineUrl = details?['pythonEngineUrl']?.toString();
      if (engineUrl != null && engineUrl.isNotEmpty) {
        ApiService.cloudBaseUrl = engineUrl;
        ApiService.baseUrl = engineUrl;
        DatabaseService.instance.setSetting('studio_cloud_engine_url', engineUrl);
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
          _errorMessage = details?['message']?.toString() ??
              _errorMessage ??
              'The GPU stopped before it was ready.';
          _pollTimer?.cancel();
          _pollTimer = null;
          break;
        case 'PROVISIONING':
        default:
          _state = ProvisioningState.provisioning;
          break;
      }
    });
  }

  /// Socket problems are not rental failures: say so plainly and keep polling.
  void _handleClientError(String error) {
    if (!mounted) return;
    setState(() {
      _connectionNote = 'Live updates are unavailable, so this page checks every few seconds.';
    });
    _ensurePolling();
  }

  void _scheduleAutoNavigation() {
    _navigationTimer?.cancel();
    _navigationTimer = Timer(const Duration(milliseconds: 2200), () {
      if (!mounted) return;
      Navigator.of(context).pop(true);
      widget.onReturnToStudio?.call();
    });
  }

  void _jumpInEarly(ModelProvisioningItem model) {
    _navigationTimer?.cancel();
    Navigator.of(context).pop(model.modelId);
    widget.onReturnToStudio?.call();
  }

  ModelProvisioningItem? get _earlyReadyModel {
    for (final m in _models) {
      if (m.status == 'ready') return m;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.isDark ? LuminaColors.darkBg : LuminaColors.lightBg;
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
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
                    decoration: BoxDecoration(
                      color: card,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: border),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: widget.isDark ? 0.35 : 0.08),
                          blurRadius: 30,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Animated Hero Icon
                        _buildHeroGraphic(),

                        const SizedBox(height: 18),

                        // Title
                        Text(
                          _getTitleText(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.bold,
                            color: text,
                            letterSpacing: -0.3,
                          ),
                        ),

                        const SizedBox(height: 8),

                        // Subtitle
                        Text(
                          _getSubtitleText(),
                          key: const ValueKey('provisioning_subtitle'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: muted,
                            height: 1.4,
                          ),
                        ),

                        _buildLiveStatus(muted, text),

                        if (_deviceInfo != null && _state == ProvisioningState.ready) ...[
                          const SizedBox(height: 10),
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

                        const SizedBox(height: 18),

                        // Stepper timeline
                        _buildProgressStepper(border, muted, text),

                        // Early Access Call-To-Action (if any model is ready before all finish)
                        if (_state == ProvisioningState.downloadingModel &&
                            _earlyReadyModel != null) ...[
                          const SizedBox(height: 18),
                          _buildEarlyAccessBanner(_earlyReadyModel!, text, muted),
                        ],

                        // Live Per-Model Progress List
                        if (_models.isNotEmpty) ...[
                          const SizedBox(height: 18),
                          _buildPerModelList(border, muted, text),
                        ],

                        const SizedBox(height: 20),

                        // Bottom Actions
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
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: primaryColor.withValues(alpha: 0.12),
          border: Border.all(color: primaryColor.withValues(alpha: 0.4), width: 2),
          boxShadow: [
            BoxShadow(
              color: primaryColor.withValues(alpha: 0.25),
              blurRadius: 20,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (_state == ProvisioningState.provisioning ||
                _state == ProvisioningState.downloadingModel)
              SizedBox(
                width: 72,
                height: 72,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                ),
              ),
            Icon(
              iconData,
              size: 36,
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
        return 'Streaming Model Weights';
      case ProvisioningState.ready:
        return 'Cosmic-Gen GPU Ready!';
      case ProvisioningState.failed:
        return _stoppedByUser ? 'GPU Stopped' : 'Launch Failed';
    }
  }

  /// What was charged and refunded, as the backend reports it.
  String _billingSummary() {
    String c(double v) => v.toStringAsFixed(2);
    if (_creditsCharged <= 0 && _creditsRefunded <= 0) return 'Nothing was charged.';
    if (_creditsRefunded > 0 && (_creditsRefunded - _creditsCharged).abs() < 0.005) {
      return '${c(_creditsCharged)} credits were charged and refunded in full.';
    }
    if (_creditsRefunded > 0) {
      return 'Charged ${c(_creditsCharged)} credits, refunded ${c(_creditsRefunded)}.';
    }
    return 'Charged ${c(_creditsCharged)} credits.';
  }

  static String _formatElapsed(int seconds) {
    final m = seconds ~/ 60;
    final s = (seconds % 60).toString().padLeft(2, '0');
    return m >= 60 ? '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m' : '$m:$s';
  }

  /// Current step, elapsed time, credits so far, and connection problems in plain words.
  Widget _buildLiveStatus(Color muted, Color text) {
    return Column(
      children: [
        if (!_isTerminal && _stepMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            _stepMessage!,
            key: const ValueKey('provisioning_step_message'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: text),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          'Elapsed ${_formatElapsed(_elapsedSeconds)} · Charged so far ${_creditsCharged.toStringAsFixed(2)} credits',
          key: const ValueKey('provisioning_elapsed_credits'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: muted),
        ),
        if (_connectionNote != null) ...[
          const SizedBox(height: 8),
          Text(
            _connectionNote!,
            key: const ValueKey('provisioning_connection_note'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: LuminaColors.amber),
          ),
        ],
      ],
    );
  }

  String _getSubtitleText() {
    switch (_state) {
      case ProvisioningState.provisioning:
        return 'Allocating dedicated GPU hardware and configuring high-speed stream channels.';
      case ProvisioningState.downloadingModel:
        final readyCount = _models.where((m) => m.status == 'ready').length;
        if (readyCount > 0) {
          return '$readyCount of ${_models.length} models ready. You can jump in early or wait for all models.';
        }
        return 'Downloading and caching model weights into inference pipelines.';
      case ProvisioningState.ready:
        return 'All models downloaded and ready! Redirecting to your Creative Studio...';
      case ProvisioningState.failed:
        return '${_errorMessage ?? 'The GPU stopped.'} ${_billingSummary()}';
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
          border: Border.all(color: muted.withValues(alpha: 0.5), width: 1.5),
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

  /// Early-Access Call To Action Banner shown as soon as any single model is ready
  Widget _buildEarlyAccessBanner(
      ModelProvisioningItem model, Color text, Color muted) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF10B981).withValues(alpha: 0.16),
            LuminaColors.cyan.withValues(alpha: 0.10),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'READY EARLY',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Jump In Now',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF10B981),
                ),
              ),
              const Spacer(),
              if (!model.loadedInVram)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: LuminaColors.amber.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: LuminaColors.amber.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.flash_auto_rounded, size: 12, color: LuminaColors.amber),
                      SizedBox(width: 4),
                      Text(
                        'On-demand warm-up',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: LuminaColors.amber,
                        ),
                      ),
                    ],
                  ),
                )
              else
                const Row(
                  children: [
                    Icon(Icons.bolt_rounded, size: 14, color: Color(0xFF10B981)),
                    SizedBox(width: 4),
                    Text(
                      'Resident in VRAM',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF10B981),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${model.displayName} is ready to generate!',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            model.loadedInVram
                ? 'Weights are loaded in VRAM. Start generating now while remaining models finish downloading below.'
                : 'Weights are cached on NVMe disk. The first prompt will load into VRAM (~2–3s) while others finish in background.',
            style: TextStyle(
              fontSize: 12,
              color: muted,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 2,
              ),
              icon: const Icon(Icons.flash_on_rounded, size: 18),
              label: Text(
                'Start generating with ${model.displayName} →',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              onPressed: () => _jumpInEarly(model),
            ),
          ),
        ],
      ),
    );
  }

  /// Live Per-Model Progress List Box
  Widget _buildPerModelList(Color border, Color muted, Color text) {
    return Container(
      decoration: BoxDecoration(
        color: widget.isDark ? const Color(0x10FFFFFF) : const Color(0x06000000),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                const Icon(Icons.layers_rounded, size: 16, color: LuminaColors.cyan),
                const SizedBox(width: 8),
                Text(
                  'MODEL DOWNLOAD PIPELINE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    color: text,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_models.where((m) => m.status == 'ready').length} of ${_models.length} ready',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: muted,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: _models.length,
            separatorBuilder: (_, __) => Divider(
              height: 1,
              indent: 16,
              endIndent: 16,
              color: border.withValues(alpha: 0.5),
            ),
            itemBuilder: (context, index) {
              return _buildModelRow(_models[index], text, muted, border);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildModelRow(
      ModelProvisioningItem model, Color text, Color muted, Color border) {
    Widget statusBadge;
    Widget trailingInfo;

    switch (model.status) {
      case 'ready':
        statusBadge = Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0x1A10B981),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0x3310B981)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_rounded, size: 13, color: Color(0xFF10B981)),
              SizedBox(width: 4),
              Text(
                'Ready',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF10B981),
                ),
              ),
            ],
          ),
        );
        trailingInfo = Text(
          model.loadedInVram ? 'VRAM Resident' : 'Cached on NVMe',
          style: TextStyle(
            fontSize: 11,
            color: model.loadedInVram ? const Color(0xFF10B981) : muted,
            fontWeight: FontWeight.w500,
          ),
        );
        break;

      case 'loading':
        statusBadge = Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: LuminaColors.cyan.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: LuminaColors.cyan.withValues(alpha: 0.3)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  valueColor: AlwaysStoppedAnimation(LuminaColors.cyan),
                ),
              ),
              SizedBox(width: 5),
              Text(
                'Loading...',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: LuminaColors.cyan,
                ),
              ),
            ],
          ),
        );
        trailingInfo = Text(
          'Warming pipeline',
          style: TextStyle(fontSize: 11, color: muted),
        );
        break;

      case 'downloading':
        statusBadge = Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: LuminaColors.amber.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: LuminaColors.amber.withValues(alpha: 0.3)),
          ),
          child: Text(
            '${model.progressPercent.toStringAsFixed(1)}%',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: LuminaColors.amber,
            ),
          ),
        );
        trailingInfo = Text(
          'Streaming weights...',
          style: TextStyle(fontSize: 11, color: muted),
        );
        break;

      case 'failed':
        statusBadge = Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0x1AEF4444),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0x33EF4444)),
          ),
          child: const Text(
            'Failed',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Color(0xFFEF4444),
            ),
          ),
        );
        trailingInfo = Text(
          model.error ?? 'Download error',
          style: const TextStyle(fontSize: 11, color: Color(0xFFEF4444)),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
        break;

      case 'queued':
      default:
        statusBadge = Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: widget.isDark ? const Color(0x1AFFFFFF) : const Color(0x0C000000),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            'Queued',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: muted,
            ),
          ),
        );
        trailingInfo = Text(
          'Waiting in queue',
          style: TextStyle(fontSize: 11, color: muted),
        );
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Category tag pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: LuminaColors.violet.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  model.categoryBadge,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: LuminaColors.violet,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  model.displayName,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: text,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              statusBadge,
            ],
          ),
          const SizedBox(height: 6),
          // Progress bar when downloading
          if (model.status == 'downloading') ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (model.progressPercent / 100.0).clamp(0.0, 1.0),
                minHeight: 4,
                backgroundColor: widget.isDark
                    ? const Color(0x22FFFFFF)
                    : const Color(0x15000000),
                valueColor: const AlwaysStoppedAnimation(LuminaColors.amber),
              ),
            ),
            const SizedBox(height: 4),
          ],
          Row(
            children: [
              Text(
                model.modelId,
                style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: muted.withValues(alpha: 0.7),
                ),
              ),
              const Spacer(),
              trailingInfo,
            ],
          ),
          if (model.status == 'ready' && !model.loadedInVram) ...[
            const SizedBox(height: 4),
            const Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 11, color: LuminaColors.amber),
                SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Stored on disk · first inference warms up into VRAM (~2–3s)',
                    style: TextStyle(
                      fontSize: 10,
                      color: LuminaColors.amber,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomActions(Color muted, Color text) {
    final stopButton = OutlinedButton.icon(
      key: const ValueKey('stop_instance_btn'),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFFEF4444),
        side: const BorderSide(color: Color(0x66EF4444)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      icon: _stopping
          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.stop_circle_outlined, size: 18),
      label: Text(_stopping ? 'Stopping…' : 'Stop instance'),
      onPressed: _stopping ? null : _confirmStop,
    );

    if (_state == ProvisioningState.failed) {
      return Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
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
      return Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          stopButton,
          ElevatedButton.icon(
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
          ),
        ],
      );
    }

    // Default provisioning / downloading state
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: [
        stopButton,
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
