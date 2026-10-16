import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/generation_item.dart';
import '../models/generation_request.dart';
import '../models/generation_result.dart';
import '../models/project_item.dart';
import '../models/video_template.dart';
import '../models/image_template.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/generation_bubble.dart';
import '../widgets/prompt_input_bar.dart';
import '../widgets/top_bar.dart';
import '../widgets/video_template_gallery.dart';
import '../widgets/image_template_gallery.dart';
import '../widgets/camera_capture_dialog.dart';
import '../widgets/deep_live_cam_dialog.dart';
import '../features/cloud_mode/data/models/cloud_model.dart';
import '../features/cloud_mode/data/services/cloud_api_service.dart';
import '../features/cloud_mode/presentation/screens/cloud_management_screen.dart';
import 'my_library_screen.dart';

/// Lumina studio: DB-backed projects + generation feed.
class HomeScreen extends StatefulWidget {
  final bool isDark;
  final VoidCallback onThemeToggle;

  const HomeScreen(
      {super.key, required this.isDark, required this.onThemeToggle});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _db = DatabaseService.instance;
  final _api = ApiService();
  final _cloudApi = CloudApiService.instance;
  final _promptBarKey = GlobalKey<PromptInputBarState>();

  StudioExecutionMode _executionMode = StudioExecutionMode.local;
  Timer? _healthTimer;
  bool _engineOnline = false;
  bool _cloudOnline = false;
  int _consecutiveHealthFailures = 0;
  bool _isSidebarCollapsed = false;
  bool _loading = true;
  bool _dismissedTemplateGallery = false;
  /// The composer's tab name for [_currentSidebarTab] (null: keep its mode).
  String? get _studioTabName => switch (_currentSidebarTab) {
        SidebarTab.image => 'image',
        SidebarTab.video => 'video',
        SidebarTab.voice => 'voice',
        SidebarTab.enhancer => 'enhancer',
        _ => null,
      };

  SidebarTab _currentSidebarTab = SidebarTab.history;

  bool get _shouldShowVideoTemplates {
    // Only the selected video sidebar tab should show the video grid views template!
    if (_currentSidebarTab != SidebarTab.video) return false;
    if (_messages.isNotEmpty) return false;
    return !_dismissedTemplateGallery;
  }

  bool get _shouldShowImageTemplates {
    // Only the selected image sidebar tab should show the image grid views template!
    if (_currentSidebarTab != SidebarTab.image) return false;
    if (_messages.isNotEmpty) return false;
    return !_dismissedTemplateGallery;
  }

  List<ProjectItem> _projects = [];
  ProjectItem? _activeProject;
  List<GenerationItem> _messages = [];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _checkHealth();
    _healthTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _checkHealth(),
    );
    _loadInitialData();
  }

  Future<void> _checkHealth() async {
    final ok = await _api.checkHealth();
    final cloudOk = await _cloudApi.checkHealth();

    if (!mounted) return;
    if (cloudOk != _cloudOnline) {
      setState(() => _cloudOnline = cloudOk);
    }

    if (ok) {
      _consecutiveHealthFailures = 0;
      if (!_engineOnline) {
        setState(() => _engineOnline = true);
        unawaited(_api.getAvailableModels().then((_) {
          if (mounted) setState(() {});
        }));
      }
    } else {
      _consecutiveHealthFailures++;
      // Require 2 consecutive failures before declaring the engine offline.
      // This eliminates UI flickering due to transient network/tunnel packet drops.
      if (_consecutiveHealthFailures >= 2 && _engineOnline) {
        setState(() => _engineOnline = false);
      }
    }
  }

  String _deriveTitle(String prompt) {
    var text = prompt.trim().replaceAll(RegExp(r'\s+'), ' ');
    final prefixes = [
      'cinematic wide shot of an ',
      'cinematic wide shot of a ',
      'cinematic shot of ',
      'raw candid portrait of an ',
      'raw candid portrait of a ',
      'raw photo of an ',
      'raw photo of a ',
      'raw photo of ',
      'photo of an ',
      'photo of a ',
      'a photo of ',
      'an image of ',
      'picture of ',
    ];
    for (final p in prefixes) {
      if (text.toLowerCase().startsWith(p)) {
        text = text.substring(p.length).trim();
        break;
      }
    }
    if (text.length > 30) {
      final cut = text.substring(0, 30);
      final space = cut.lastIndexOf(' ');
      text = space > 15 ? '${cut.substring(0, space)}...' : '$cut...';
    }
    if (text.isEmpty) return 'Untitled Creation';
    return text[0].toUpperCase() + text.substring(1);
  }

  Future<void> _setExecutionMode(StudioExecutionMode mode) async {
    if (_executionMode == mode) return;
    setState(() => _executionMode = mode);
    try {
      await _db.setSetting('studio_execution_mode', mode.name);
    } catch (_) {}
  }

  // ── projects ──────────────────────────────────────────────
  Future<void> _loadInitialData() async {
    try {
      final savedMode = await _db.getSetting('studio_execution_mode');
      if (savedMode == StudioExecutionMode.cloud.name) {
        if (mounted) setState(() => _executionMode = StudioExecutionMode.cloud);
      } else if (savedMode == StudioExecutionMode.local.name) {
        if (mounted) setState(() => _executionMode = StudioExecutionMode.local);
      }
    } catch (_) {}

    var projects = await _db.getAllProjects();
    if (projects.isEmpty) {
      final seed = ProjectItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: 'Cyberpunk Film 4K',
        isPinned: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await _db.insertProject(seed);
      projects = [seed];
    }
    if (!mounted) return;
    setState(() {
      _projects = projects;
      _activeProject = projects.first;
    });
    await _loadGenerations();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _refreshProjects({String? selectId}) async {
    final projects = await _db.getAllProjects();
    if (!mounted) return;
    setState(() {
      _projects = projects;
      if (selectId != null) {
        _activeProject = projects.firstWhere(
          (p) => p.id == selectId,
          orElse: () => projects.first,
        );
      } else if (_activeProject != null) {
        final stillThere =
            projects.where((p) => p.id == _activeProject!.id);
        _activeProject =
            stillThere.isNotEmpty ? stillThere.first : null;
      }
    });
  }

  Future<void> _handleCreateNewProject() async {
    final proj = ProjectItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: 'New Creation ${_projects.length + 1}',
      isPinned: false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await _db.insertProject(proj);
    await _refreshProjects(selectId: proj.id);
    await _loadGenerations();
    _promptBarKey.currentState?.clearInputs();
    _promptBarKey.currentState?.setMode('Text to Image');
    if (mounted) {
      setState(() {
        _currentSidebarTab = SidebarTab.image;
        _dismissedTemplateGallery = false;
      });
    }
  }

  Future<void> _handleCreateNewVoiceProject() async {
    final proj = ProjectItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: 'Voice Project ${_projects.length + 1}',
      isPinned: false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await _db.insertProject(proj);
    await _refreshProjects(selectId: proj.id);
    await _loadGenerations();
    _promptBarKey.currentState?.clearInputs();
    _promptBarKey.currentState?.setVoiceModel('Chatterbox TTS');
    if (mounted) {
      setState(() {
        _currentSidebarTab = SidebarTab.voice;
        _dismissedTemplateGallery = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.record_voice_over_rounded,
                  color: Color(0xFFEF4444), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Started fresh Voice Project: "${proj.title}"',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF1E293B),
        ),
      );
    }
  }

  Future<void> _handleCreateNewVideoProject() async {
    final proj = ProjectItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: 'Video Project ${_projects.length + 1}',
      isPinned: false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await _db.insertProject(proj);
    await _refreshProjects(selectId: proj.id);
    await _loadGenerations();
    _promptBarKey.currentState?.clearInputs();
    _promptBarKey.currentState?.setVideoModel('Wan 2.1 T2V 1.3B');
    if (mounted) {
      setState(() {
        _currentSidebarTab = SidebarTab.video;
        _dismissedTemplateGallery = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.videocam_rounded,
                  color: LuminaColors.primaryEnd, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Started fresh Video Project: "${proj.title}"',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF1E293B),
        ),
      );
    }
  }

  Future<void> _handleStartProjectWithTemplate(VideoTemplate template) async {
    final proj = ProjectItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: template.title,
      isPinned: false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await _db.insertProject(proj);
    await _refreshProjects(selectId: proj.id);
    await _loadGenerations();
    _promptBarKey.currentState?.applyVideoTemplate(template);
    if (mounted) {
      setState(() {
        _currentSidebarTab = SidebarTab.video;
        _dismissedTemplateGallery = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.movie_filter_rounded,
                  color: LuminaColors.primaryEnd, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  template.requiresAttachment
                      ? 'Created "${proj.title}". ${template.attachmentGuidance}'
                      : 'Created "${proj.title}" (CFG: ${template.cfgScale}, Steps: ${template.steps}, Strength: ${template.strength}). Ready to generate!',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF1E293B),
        ),
      );
    }
  }

  Future<void> _handleCreateNewImageProject() async {
    final proj = ProjectItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: 'Image Project ${_projects.length + 1}',
      isPinned: false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await _db.insertProject(proj);
    await _refreshProjects(selectId: proj.id);
    await _loadGenerations();
    _promptBarKey.currentState?.clearInputs();
    _promptBarKey.currentState?.setImageModel('FLUX.1 Kontext [dev]');
    if (mounted) {
      setState(() {
        _currentSidebarTab = SidebarTab.image;
        _dismissedTemplateGallery = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.photo_rounded,
                  color: LuminaColors.primaryEnd, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Started fresh Image Project: "${proj.title}"',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF1E293B),
        ),
      );
    }
  }

  Future<void> _handleCreateNewEnhanceProject() async {
    final proj = ProjectItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: 'Enhancement ${_projects.length + 1}',
      isPinned: false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await _db.insertProject(proj);
    await _refreshProjects(selectId: proj.id);
    await _loadGenerations();
    _promptBarKey.currentState?.clearInputs();
    _promptBarKey.currentState?.setEnhancerModel('Real-ESRGAN x4plus');
    if (mounted) {
      setState(() {
        _currentSidebarTab = SidebarTab.enhancer;
        _dismissedTemplateGallery = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.auto_fix_high_rounded,
                  color: LuminaColors.primaryEnd, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Started fresh Enhancement: "${proj.title}". Drop an image to upscale!',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF1E293B),
        ),
      );
    }
  }

  Future<void> _handleStartImageProjectWithTemplate(ImageTemplate template) async {
    final proj = ProjectItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: template.title,
      isPinned: false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await _db.insertProject(proj);
    await _refreshProjects(selectId: proj.id);
    await _loadGenerations();
    _promptBarKey.currentState?.applyImageTemplate(template);
    if (mounted) {
      setState(() {
        _currentSidebarTab = SidebarTab.image;
        _dismissedTemplateGallery = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.auto_awesome_rounded,
                  color: LuminaColors.primaryEnd, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  template.requiresAttachment
                      ? 'Created "${proj.title}". ${template.attachmentGuidance}'
                      : 'Created "${proj.title}" (CFG: ${template.cfgScale}, Steps: ${template.steps}, Strength: ${template.strength}). Ready to generate!',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF1E293B),
        ),
      );
    }
  }

  Future<void> _handleSelectProject(String id) async {
    await _refreshProjects(selectId: id);
    await _loadGenerations();
    if (mounted) {
      setState(() {
        _dismissedTemplateGallery = false;
      });
    }
  }

  Future<void> _handleRename(String id, String title) async {
    await _db.updateProjectTitle(id, title);
    await _refreshProjects();
  }

  Future<void> _handleTogglePin(ProjectItem p) async {
    await _db.toggleProjectPinned(p.id, !p.isPinned);
    await _refreshProjects();
  }

  Future<void> _handleDelete(ProjectItem p) async {
    await _db.deleteProject(p.id);
    var projects = await _db.getAllProjects();
    if (projects.isEmpty) {
      final fallback = ProjectItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: 'Untitled Project 1',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await _db.insertProject(fallback);
      projects = [fallback];
    }
    if (!mounted) return;
    final wasActive = _activeProject?.id == p.id;
    setState(() {
      _projects = projects;
      if (wasActive) _activeProject = projects.first;
    });
    if (wasActive) await _loadGenerations();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted "${p.title}".')),
      );
    }
  }

  Future<void> _handleOpenDeepFaceCamera() async {
    await DeepLiveCamDialog.show(context, apiService: _api);
  }

  // ── generations feed ──────────────────────────────────────
  Future<void> _loadGenerations() async {
    if (_activeProject == null) return;
    final items =
        await _db.getGenerationsForProject(_activeProject!.id);
    if (!mounted) return;
    setState(() => _messages = items);
    _scrollToBottom();
  }

  Future<void> _handlePromptSubmit(
      String prompt,
      String negativePrompt,
      String ratio,
      String model,
      String? imageBase64,
      double strength,
      Uint8List? referenceBytes,
      int steps,
      double cfgScale, {
      String? videoBase64,
      Uint8List? referenceVideoBytes,
      String? referenceVideoName,
      String? audioBase64,
      Uint8List? referenceAudioBytes,
      String? referenceAudioName,
      String? language,
      double? exaggeration,
      String? instruction,
      String? refText,
      String? garmentBase64,
      Uint8List? garmentBytes,
      String? garmentName,
      String? tryonCategory,
      String? garmentPhotoType,
      String? endImageBase64,
      Uint8List? endImageBytes,
      String? endImageName,
      int? upscaleScale,
      bool? faceEnhance,
  }) async {
    if (_activeProject == null) {
      final newProj = ProjectItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: _deriveTitle(prompt),
        isPinned: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await _db.insertProject(newProj);
      _activeProject = newProj;
    } else {
      final isPlaceholder = _activeProject!.title.startsWith('New Creation') ||
          _activeProject!.title.startsWith('Untitled');
      if (isPlaceholder || _messages.isEmpty) {
        final newTitle = _deriveTitle(prompt);
        _activeProject!.title = newTitle;
        await _db.updateProjectTitle(_activeProject!.id, newTitle);
      } else {
        await _db.touchProject(_activeProject!.id);
      }
    }
    await _refreshProjects(selectId: _activeProject!.id);

    final currentProjId = _activeProject!.id;
    final genId = DateTime.now().millisecondsSinceEpoch.toString();
    final trimmedNeg = negativePrompt.trim();
    final effectiveNeg = trimmedNeg.isNotEmpty
        ? trimmedNeg
        : 'low quality, bad anatomy, worst quality, blurry';

    final isWan21T2V = model == 'Wan 2.1 T2V 1.3B';
    final isWan21I2V = model == 'Wan 2.1 I2V 14B';
    final isWan21FLF2V = model == 'Wan 2.1 FLF2V 14B';
    final isWan21Model = isWan21T2V || isWan21I2V || isWan21FLF2V;
    final isWanAnimateModel = model == 'Wan 2.2 Animate 14B';
    final isWanModel = isWanAnimateModel || isWan21Model;
    final isMiniMaxModel = model.contains('MiniMax');
    final isVoiceModel = model.contains('Chatterbox') || model.contains('Breeze');
    final isTryOnModel = model.contains('FASHN') || model.contains('Try-On');
    final isEnhancerModel = model.contains('Real-ESRGAN') || model.contains('Enhance');
    final item = GenerationItem(
      id: genId,
      projectId: currentProjId,
      prompt: prompt,
      negativePrompt: trimmedNeg,
      aspectRatio: ratio,
      modelName: model,
      timestamp: DateTime.now(),
      referenceImageBytes: referenceBytes,
      referenceVideoBytes: referenceVideoBytes,
      referenceVideoName: referenceVideoName,
      referenceAudioBytes: referenceAudioBytes,
      referenceAudioName: referenceAudioName,
      isVideo: isWanModel || isMiniMaxModel,
      isAudio: isVoiceModel,
      language: language,
      isCloud: _executionMode == StudioExecutionMode.cloud,
    );
    setState(() {
      _messages.add(item);
      _dismissedTemplateGallery = false;
    });
    await _db.insertGeneration(item);
    _scrollToBottom();

    GenerationResult result;
    if (isEnhancerModel) {
      if (imageBase64 == null || imageBase64.isEmpty) {
        result = GenerationResult.failure(
            'Enhancer requires an image to upscale. Please attach or drop an image.');
      } else {
        result = await _api.enhanceImage(
          imageBase64: imageBase64,
          scale: upscaleScale ?? 4,
          faceEnhance: faceEnhance ?? true,
          modelName: model,
        );
      }
    } else if (isTryOnModel) {
      if ((imageBase64 == null || imageBase64.isEmpty) ||
          (garmentBase64 == null || garmentBase64.isEmpty)) {
        result = GenerationResult.failure(
            'Virtual Try-On requires both a Person photo and a Garment photo. Please attach both using the buttons in the bar.');
      } else {
        result = await _api.generateTryOn(
          personImageBase64: imageBase64,
          garmentImageBase64: garmentBase64,
          category: tryonCategory ?? 'tops',
          garmentPhotoType: garmentPhotoType ?? 'model',
          steps: steps,
          guidanceScale: cfgScale,
        );
      }
    } else if (isVoiceModel) {
      result = await _api.generateVoice(
        prompt: prompt,
        language: language ?? 'en',
        modelName: model,
        audioPromptBase64: audioBase64,
        instruction: instruction,
        refText: refText,
        exaggeration: exaggeration ?? 0.5,
        cfgWeight: cfgScale,
      );
    } else if (isMiniMaxModel) {
      result = await _api.generateMiniMaxVideo(
        prompt: prompt,
        imageBase64: imageBase64,
        durationSeconds: 5,
        fps: 24,
        steps: steps,
        aspectRatio: ratio,
      );
    } else if (isWan21Model) {
      String task = 't2v-1.3B';
      if (isWan21I2V) task = 'i2v-14B';
      if (isWan21FLF2V) task = 'flf2v-14B';

      result = await _api.generateWan2_1(
        prompt: prompt,
        negativePrompt: trimmedNeg,
        imageBase64: imageBase64,
        endImageBase64: endImageBase64,
        task: task,
        steps: steps,
        guidanceScale: cfgScale,
        aspectRatio: ratio,
      );
    } else if (isWanAnimateModel) {
      if ((imageBase64 == null || imageBase64.isEmpty) &&
          (videoBase64 == null || videoBase64.isEmpty)) {
        result = GenerationResult.failure(
            'Wan 2.2 Animate requires a character image, a motion video, or both. Click the photo or video icon to attach one.');
      } else {
        result = await _api.animateCharacter(
          imageBase64: imageBase64 ?? '',
          templateVideoBase64: videoBase64,
          prompt: prompt,
          steps: steps,
        );
      }
    } else {
      // Switch the backend to the picked checkpoint (label -> HF id).
      const modelIds = PromptInputBar.modelIds;
      final wasForceMock = ApiService.forceMockMode;
      ApiService.forceMockMode = (model == 'Offline Mock Mode');
      final modelId = modelIds[model];
      if (modelId != null && !ApiService.forceMockMode) {
        await _api.switchModel(modelId);
      }

      result = await _api.generateImage(
        GenerationRequest(
          prompt: prompt,
          negativePrompt: effectiveNeg,
          aspectRatio: ratio,
          steps: steps,
          guidanceScale: cfgScale,
          imageBase64: imageBase64,
          strength: strength,
        ),
      );
      ApiService.forceMockMode = wasForceMock;
    }

    if (!mounted) return;
    if (result.success) {
      final bytesToSave = result.isAudio
          ? result.audioBytes
          : (result.isVideo ? result.videoBytes : result.imageBytes);
      await _db.updateGenerationResult(
        id: genId,
        status: GenerationStatus.completed,
        bytes: bytesToSave,
        seed: result.seed,
        durationMs: result.inferenceTimeMs,
        loras: result.activeLoras,
        isVideo: result.isVideo,
        isAudio: result.isAudio,
      );
    } else {
      await _db.updateGenerationResult(
        id: genId,
        status: GenerationStatus.failed,
        bytes: null,
        seed: null,
        durationMs: null,
        loras: const {},
        error: result.error,
      );
    }
    await _db.touchProject(currentProjId);
    if (_activeProject?.id == currentProjId) {
      await _loadGenerations();
      // Reload drops the transient mock flag; restore it for this turn.
      if (result.success && result.isMock && mounted) {
        final idx = _messages.indexWhere((m) => m.id == genId);
        if (idx != -1) setState(() => _messages[idx].isMock = true);
      }
    }
    await _refreshProjects(selectId: _activeProject?.id);
    AuthService.instance.refreshProfile();
  }

  Future<void> _retryItem(GenerationItem item) async {
    setState(() {
      item.status = GenerationStatus.generating;
      item.errorMessage = null;
    });
    _scrollToBottom();
    final result = await _api.generateImage(
      GenerationRequest(
        prompt: item.prompt,
        negativePrompt: item.negativePrompt.isNotEmpty
            ? item.negativePrompt
            : 'low quality, bad anatomy, worst quality, blurry',
        aspectRatio: item.aspectRatio,
        imageBase64: item.referenceImageBytes != null
            ? base64Encode(item.referenceImageBytes!)
            : null,
      ),
    );
    if (!mounted) return;
    if (result.success) {
      await _db.updateGenerationResult(
        id: item.id,
        status: GenerationStatus.completed,
        bytes: result.imageBytes,
        seed: result.seed,
        durationMs: result.inferenceTimeMs,
        loras: result.activeLoras,
      );
    } else {
      await _db.updateGenerationResult(
        id: item.id,
        status: GenerationStatus.failed,
        bytes: null,
        seed: null,
        durationMs: null,
        loras: const {},
        error: result.error,
      );
    }
    await _loadGenerations();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _healthTimer?.cancel();
    _scrollController.dispose();
    _api.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: ListenableBuilder(
          listenable: AuthService.instance,
          builder: (context, _) => TopBar(
            credits: AuthService.instance.currentUser?.credits ?? 0,
            engineOnline: _engineOnline,
            cloudOnline: _cloudOnline,
            executionMode: _executionMode,
            onExecutionModeChanged: _setExecutionMode,
            deviceName: _api.activeDeviceName,
            isDark: widget.isDark,
            workspaceLabel: _activeProject?.title ?? 'Creative Studio',
            onThemeToggle: widget.onThemeToggle,
            sidebarCollapsed: _isSidebarCollapsed,
            onMenuToggle: () => setState(
                () => _isSidebarCollapsed = !_isSidebarCollapsed),
            onOpenDeepFaceCamera: _handleOpenDeepFaceCamera,
            onBuyCredits: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Checkout is disabled in this build.')),
              );
            },
          ),
        ),
      ),
      body: _executionMode == StudioExecutionMode.cloud
          ? CloudManagementScreen(
              isDark: widget.isDark,
              onReturnToStudio: () => _setExecutionMode(StudioExecutionMode.local),
            )
          : Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSidebar(
            collapsed: _isSidebarCollapsed,
            projects: _projects,
            activeProjectId: _activeProject?.id,
            activeTab: _currentSidebarTab,
            onOpenDeepFaceCamera: _handleOpenDeepFaceCamera,
            onOpenCloudMode: () => _setExecutionMode(StudioExecutionMode.cloud),
            onTabChanged: (tab) {
              if (tab == SidebarTab.cloud) {
                _setExecutionMode(StudioExecutionMode.cloud);
                return;
              }
              // The composer follows the tab through PromptInputBar.studioTab,
              // also when it is not on screen at this moment.
              setState(() {
                _currentSidebarTab = tab;
                _dismissedTemplateGallery = false;
              });
            },
            onNewProject: _handleCreateNewProject,
            onNewVoiceProject: _handleCreateNewVoiceProject,
            onNewVideoProject: _handleCreateNewVideoProject,
            onNewImageProject: _handleCreateNewImageProject,
            onNewEnhanceProject: _handleCreateNewEnhanceProject,
            onOpenVideoGallery: () {
              setState(() {
                _currentSidebarTab = SidebarTab.video;
                _dismissedTemplateGallery = false;
              });
            },
            onOpenImageGallery: () {
              setState(() {
                _currentSidebarTab = SidebarTab.image;
                _dismissedTemplateGallery = false;
              });
            },
            onSelectProject: (id) {
              _handleSelectProject(id);
            },
            onRenameTitle: _handleRename,
            onTogglePin: _handleTogglePin,
            onDeleteProject: _handleDelete,
            onSelectVideoModel: (model) {
              _promptBarKey.currentState?.setVideoModel(model);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(Icons.check_circle_rounded,
                          color: LuminaColors.primaryEnd, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Active Video Model: $model',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  duration: const Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: const Color(0xFF1E293B),
                ),
              );
            },
            onSelectImageModel: (model) {
              _promptBarKey.currentState?.setImageModel(model);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(Icons.check_circle_rounded,
                          color: LuminaColors.primaryEnd, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Active Image Model: $model',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  duration: const Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: const Color(0xFF1E293B),
                ),
              );
            },
            onSelectEnhancerModel: (model) {
              _promptBarKey.currentState?.setEnhancerModel(model);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(Icons.auto_fix_high_rounded,
                          color: LuminaColors.primaryEnd, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Active Enhancer Model: $model',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  duration: const Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: const Color(0xFF1E293B),
                ),
              );
            },
            onSelectVideoTemplate: (VideoTemplate template) {
              _promptBarKey.currentState?.applyVideoTemplate(template);
              setState(() {
                _dismissedTemplateGallery = true;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(Icons.auto_awesome_rounded,
                          color: LuminaColors.primaryEnd, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          template.requiresAttachment
                              ? 'Loaded "${template.title}". ${template.attachmentGuidance}'
                              : 'Loaded "${template.title}" (CFG: ${template.cfgScale}, Steps: ${template.steps}, Strength: ${template.strength}). Ready to generate!',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  duration: const Duration(seconds: 4),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: const Color(0xFF0F172A),
                ),
              );
            },
            onSelectImageTemplate: (ImageTemplate template) {
              _promptBarKey.currentState?.applyImageTemplate(template);
              setState(() {
                _dismissedTemplateGallery = true;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(Icons.auto_awesome_rounded,
                          color: LuminaColors.primaryEnd, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          template.requiresAttachment
                              ? 'Loaded "${template.title}". ${template.attachmentGuidance}'
                              : 'Loaded "${template.title}" (CFG: ${template.cfgScale}, Steps: ${template.steps}, Strength: ${template.strength}). Ready to generate!',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  duration: const Duration(seconds: 4),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: const Color(0xFF0F172A),
                ),
              );
            },
            onExpand: () {
              if (_isSidebarCollapsed) {
                setState(() => _isSidebarCollapsed = false);
              }
            },
          ),
          Expanded(
            child: Stack(
              children: [
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else if (_currentSidebarTab == SidebarTab.library)
                  Positioned.fill(
                    child: MyLibraryScreen(
                      isDark: widget.isDark,
                      onClose: () => setState(() => _currentSidebarTab = SidebarTab.history),
                    ),
                  )
                else if (_shouldShowVideoTemplates)
                  Positioned.fill(
                    child: VideoTemplateGallery(
                      isDark: widget.isDark,
                      generationsCount: _messages.length,
                      onDismiss: () =>
                          setState(() => _dismissedTemplateGallery = true),
                      onBackToGenerations: () => setState(() {
                        _dismissedTemplateGallery = true;
                      }),
                      onNewVideoProject: _handleCreateNewVideoProject,
                      onSelectTemplate: (template) {
                        _promptBarKey.currentState
                            ?.applyVideoTemplate(template);
                        setState(() {
                          _dismissedTemplateGallery = true;
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Row(
                              children: [
                                const Icon(Icons.auto_awesome_rounded,
                                    color: LuminaColors.primaryEnd, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    template.requiresAttachment
                                        ? 'Loaded "${template.title}". ${template.attachmentGuidance}'
                                        : 'Loaded "${template.title}" (CFG: ${template.cfgScale}, Steps: ${template.steps}, Strength: ${template.strength}). Ready to generate!',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                            duration: const Duration(seconds: 4),
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: const Color(0xFF0F172A),
                          ),
                        );
                      },
                      onStartProjectWithTemplate:
                          _handleStartProjectWithTemplate,
                    ),
                  )
                else if (_shouldShowImageTemplates)
                  Positioned.fill(
                    child: ImageTemplateGallery(
                      isDark: widget.isDark,
                      generationsCount: _messages.length,
                      onDismiss: () =>
                          setState(() => _dismissedTemplateGallery = true),
                      onBackToGenerations: () => setState(() {
                        _dismissedTemplateGallery = true;
                      }),
                      onNewImageProject: _handleCreateNewImageProject,
                      onSelectTemplate: (template) {
                        _promptBarKey.currentState
                            ?.applyImageTemplate(template);
                        setState(() {
                          _dismissedTemplateGallery = true;
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Row(
                              children: [
                                const Icon(Icons.auto_awesome_rounded,
                                    color: LuminaColors.primaryEnd, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    template.requiresAttachment
                                        ? 'Loaded "${template.title}". ${template.attachmentGuidance}'
                                        : 'Loaded "${template.title}" (CFG: ${template.cfgScale}, Steps: ${template.steps}, Strength: ${template.strength}). Ready to generate!',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                            duration: const Duration(seconds: 4),
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: const Color(0xFF0F172A),
                          ),
                        );
                      },
                      onStartProjectWithTemplate:
                          _handleStartImageProjectWithTemplate,
                    ),
                  )
                else if (_messages.isEmpty)
                  if (_currentSidebarTab == SidebarTab.enhancer)
                    Center(
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 520),
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: (widget.isDark ? LuminaColors.darkCard : Colors.white).withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: widget.isDark ? LuminaColors.darkBorder : LuminaColors.lightBorder,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: widget.isDark ? 0.3 : 0.08),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                gradient: LuminaColors.primaryGradient,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: LuminaColors.primaryGlow.withValues(alpha: 0.35),
                                    blurRadius: 16,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.auto_fix_high_rounded,
                                size: 36,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 18),
                            const Text(
                              'AI Image Enhancer & Upscaler',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Upload any low-resolution photo, digital art, or anime illustration to upscale 4× into high-definition clarity with Real-ESRGAN.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: widget.isDark ? Colors.white60 : Colors.black54,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.center,
                              children: [
                                _buildEnhancerHeroBadge('4× Super-Resolution', Icons.hd_rounded),
                                _buildEnhancerHeroBadge('Blind Artifact Removal', Icons.auto_awesome_rounded),
                                _buildEnhancerHeroBadge('GFPGAN Face Restoration', Icons.face_retouching_natural_rounded),
                              ],
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              '👇 Drop or attach an image in the control bar below to begin',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: LuminaColors.primaryEnd,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.draw_outlined,
                            size: 48,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.25),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _activeProject == null
                                ? 'Create a project to begin'
                                : 'Your creations will appear here',
                            style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    )
                else
                  ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.only(top: 24, bottom: 140),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final item = _messages[index];
                      return GenerationBubble(
                        key: ValueKey(item.id),
                        item: item,
                        onRetry: () => _retryItem(item),
                      );
                    },
                  ),
                if (_currentSidebarTab != SidebarTab.library)
                  Align(
                    alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: ConstrainedBox(
                      constraints:
                          const BoxConstraints(maxWidth: 760),
                      child: PromptInputBar(
                        key: _promptBarKey,
                        apiService: _api,
                        onGenerate: _handlePromptSubmit,
                        studioTab: _studioTabName,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnhancerHeroBadge(String text, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: widget.isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.isDark ? Colors.white12 : Colors.black12,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: LuminaColors.primaryEnd),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
