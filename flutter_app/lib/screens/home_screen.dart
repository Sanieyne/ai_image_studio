import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/generation_item.dart';
import '../models/generation_request.dart';
import '../models/project_item.dart';
import '../services/api_service.dart';
import '../services/database_service.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/generation_bubble.dart';
import '../widgets/prompt_input_bar.dart';
import '../widgets/top_bar.dart';

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

  Timer? _healthTimer;
  bool _engineOnline = false;
  bool _isSidebarCollapsed = false;
  bool _loading = true;

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
    if (mounted && ok != _engineOnline) {
      setState(() => _engineOnline = ok);
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

  // ── projects ──────────────────────────────────────────────
  Future<void> _loadInitialData() async {
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
  }

  Future<void> _handleSelectProject(String id) async {
    await _refreshProjects(selectId: id);
    await _loadGenerations();
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
      double cfgScale) async {
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

    final item = GenerationItem(
      id: genId,
      projectId: currentProjId,
      prompt: prompt,
      negativePrompt: trimmedNeg,
      aspectRatio: ratio,
      modelName: model,
      timestamp: DateTime.now(),
      referenceImageBytes: referenceBytes,
    );
    setState(() => _messages.add(item));
    await _db.insertGeneration(item);
    _scrollToBottom();

    // Switch the backend to the picked checkpoint (label -> HF id).
    // Must match _models in prompt_input_bar.dart.
    const modelIds = PromptInputBar.modelIds;
    final wasForceMock = ApiService.forceMockMode;
    ApiService.forceMockMode = (model == 'Offline Mock Mode');
    final modelId = modelIds[model];
    if (modelId != null && !ApiService.forceMockMode) {
      await _api.switchModel(modelId);
    }

    final result = await _api.generateImage(
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
    if (!mounted) return;
    if (result.success) {
      await _db.updateGenerationResult(
        id: genId,
        status: GenerationStatus.completed,
        bytes: result.imageBytes,
        seed: result.seed,
        durationMs: result.inferenceTimeMs,
        loras: result.activeLoras,
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
      appBar: TopBar(
        engineOnline: _engineOnline,
        isDark: widget.isDark,
        workspaceLabel: _activeProject?.title ?? 'Creative Studio',
        onThemeToggle: widget.onThemeToggle,
        sidebarCollapsed: _isSidebarCollapsed,
        onMenuToggle: () => setState(
            () => _isSidebarCollapsed = !_isSidebarCollapsed),
        onBuyCredits: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Checkout is disabled in this build.')),
          );
        },
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSidebar(
            collapsed: _isSidebarCollapsed,
            projects: _projects,
            activeProjectId: _activeProject?.id,
            onNewProject: _handleCreateNewProject,
            onSelectProject: _handleSelectProject,
            onRenameTitle: _handleRename,
            onTogglePin: _handleTogglePin,
            onDeleteProject: _handleDelete,
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
                  const Center(
                      child: CircularProgressIndicator())
                else if (_messages.isEmpty)
                  Center(
                    child: Text(
                      _activeProject == null
                          ? 'Create a project to begin'
                          : 'Your creations will appear here',
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.4),
                      ),
                    ),
                  )
                else
                  ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.only(
                        top: 24, bottom: 140),
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
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: ConstrainedBox(
                      constraints:
                          const BoxConstraints(maxWidth: 760),
                      child: PromptInputBar(
                        apiService: _api,
                        onGenerate: (prompt, negativePrompt, ratio, model,
                                imageBase64, strength, referenceBytes,
                                steps, cfgScale) =>
                            _handlePromptSubmit(
                                prompt,
                                negativePrompt,
                                ratio,
                                model,
                                imageBase64,
                                strength,
                                referenceBytes,
                                steps,
                                cfgScale),
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
}
