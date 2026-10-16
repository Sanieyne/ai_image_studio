import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/project_item.dart';
import '../models/video_template.dart';
import '../models/image_template.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'model_download_button.dart';
import 'settings_dialog.dart';
import 'silent_video_preview_player.dart';

/// Navigation modes for the unified sidebar.
enum SidebarTab {
  history,
  voice,
  video,
  image,
  enhancer,
  cloud,
  library,
}

/// Voice preset with preview metadata
class VoicePreset {
  final String id;
  final String name;
  final String gender;
  final String accent;
  final String tags;
  final String previewDescription;
  final IconData icon;

  const VoicePreset({
    required this.id,
    required this.name,
    required this.gender,
    required this.accent,
    required this.tags,
    required this.previewDescription,
    required this.icon,
  });
}

/// Modern multi-mode Studio Sidebar:
/// - Top Tab Bar: History (Chat Projects), Voice Studio, Video Mode, Image Mode
/// - Dedicated interactive mode panels (Voice Studio with Model Selector, Voice Options, 
///   20-30s Audio Previews, Tone/Speed/Exaggeration Sliders, and Instant Voice Cloning Upload)
/// - Collapsible to 72px rail with active tab badge icons.
class AppSidebar extends StatefulWidget {
  final bool collapsed;
  final List<ProjectItem> projects;
  final String? activeProjectId;
  final VoidCallback? onNewProject;
  final VoidCallback? onNewVoiceProject;
  final VoidCallback? onNewVideoProject;
  final VoidCallback? onNewImageProject;
  final VoidCallback? onNewEnhanceProject;
  final VoidCallback? onOpenVideoGallery;
  final VoidCallback? onOpenImageGallery;
  final ValueChanged<SidebarTab>? onTabChanged;
  final ValueChanged<String>? onSelectProject;
  final void Function(String id, String title)? onRenameTitle;
  final ValueChanged<ProjectItem>? onTogglePin;
  final ValueChanged<ProjectItem>? onDeleteProject;
  final VoidCallback? onExpand;
  final ApiService? apiService;
  final ValueChanged<VideoTemplate>? onSelectVideoTemplate;
  final ValueChanged<String>? onSelectVideoModel;
  final ValueChanged<ImageTemplate>? onSelectImageTemplate;
  final ValueChanged<String>? onSelectImageModel;
  final ValueChanged<String>? onSelectEnhancerModel;
  final VoidCallback? onOpenCloudMode;
  final VoidCallback? onOpenDeepFaceCamera;
  final SidebarTab? activeTab;

  const AppSidebar({
    super.key,
    this.collapsed = false,
    this.projects = const [],
    this.activeProjectId,
    this.onNewProject,
    this.onNewVoiceProject,
    this.onNewVideoProject,
    this.onNewImageProject,
    this.onNewEnhanceProject,
    this.onOpenVideoGallery,
    this.onOpenImageGallery,
    this.onTabChanged,
    this.onSelectProject,
    this.onRenameTitle,
    this.onTogglePin,
    this.onDeleteProject,
    this.onExpand,
    this.apiService,
    this.onSelectVideoTemplate,
    this.onSelectVideoModel,
    this.onSelectImageTemplate,
    this.onSelectImageModel,
    this.onSelectEnhancerModel,
    this.onOpenCloudMode,
    this.onOpenDeepFaceCamera,
    this.activeTab,
  });

  @override
  State<AppSidebar> createState() => _AppSidebarState();
}

enum ProjectAction { share, rename, pin, archive, delete, moveToProject }

class _AppSidebarState extends State<AppSidebar> with SingleTickerProviderStateMixin {
  SidebarTab _currentTab = SidebarTab.history;

  @override
  void initState() {
    super.initState();
    if (widget.activeTab != null) {
      _currentTab = widget.activeTab!;
    }
    AuthService.instance.getCurrentUser();
  }

  @override
  void didUpdateWidget(covariant AppSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activeTab != null && widget.activeTab != _currentTab) {
      setState(() => _currentTab = widget.activeTab!);
    }
  }

  final _search = TextEditingController();
  String _filter = '';

  // ─── Video Mode State ─────────────────────────────────────
  String _selectedVideoModel = 'Wan 2.1 T2V 1.3B';
  String? _selectedVideoTemplateId;
  String _videoTemplateCategory = 'All';

  // ─── Image Mode State ─────────────────────────────────────
  String _selectedImageModel = 'FLUX.1 Kontext [dev]';
  String? _selectedImageTemplateId;
  String _imageTemplateCategory = 'All';

  // ─── Enhancer Mode State ──────────────────────────────────
  String _selectedEnhancerModel = 'Real-ESRGAN x4plus';
  int _enhancerScale = 4;
  bool _enhancerFaceRestore = true;

  // ─── Voice Mode State ─────────────────────────────────────
  String _selectedVoiceModel = 'Chatterbox TTS';
  String _selectedVoicePresetId = 'aurora';
  double _exaggeration = 0.5;
  double _cfgWeight = 0.7;
  double _speechSpeed = 1.0;

  // Audio Preview Simulation State (20-30s player)
  String? _playingVoiceId;
  int _previewPlaybackSeconds = 0;
  Timer? _previewTimer;

  // Voice Cloning Upload State
  Uint8List? _cloneAudioBytes;
  String? _cloneAudioName;
  final _cloneSpeakerNameController = TextEditingController();

  static const List<VoicePreset> _voicePresets = [
    VoicePreset(
      id: 'aurora',
      name: 'Aurora Sterling',
      gender: 'Female',
      accent: 'American (Neutral)',
      tags: 'Warm · Narrative · Professional',
      previewDescription: '"Step into the future of creative AI with crystal-clear voice clarity."',
      icon: Icons.record_voice_over_rounded,
    ),
    VoicePreset(
      id: 'marcus',
      name: 'Marcus Vance',
      gender: 'Male',
      accent: 'British (RP)',
      tags: 'Deep · Documentary · Authoritative',
      previewDescription: '"Across the cosmos, every story begins with a single spark of imagination."',
      icon: Icons.mic_external_on_rounded,
    ),
    VoicePreset(
      id: 'elena',
      name: 'Elena Rostova',
      gender: 'Female',
      accent: 'European / Melodic',
      tags: 'Smooth · Conversational · Dynamic',
      previewDescription: '"Experience seamless translations with natural cadence and tone."',
      icon: Icons.graphic_eq_rounded,
    ),
    VoicePreset(
      id: 'zephyr',
      name: 'Zephyr Studio',
      gender: 'Non-Binary',
      accent: 'Modern Cinema',
      tags: 'Energetic · Commercial · Expressive',
      previewDescription: '"Turn your ideas into broadcast-grade voice productions in seconds."',
      icon: Icons.multitrack_audio_rounded,
    ),
  ];

  /// Voice models. `downloadId` is the R2 / engine folder ('' = no local
  /// download): both Chatterbox models use the same chatterbox-tts download,
  /// which holds the English and the multilingual weights. Breeze needs a
  /// runtime that is not on PyPI, so it runs only on cloud GPUs.
  static const List<Map<String, String>> _voiceModels = [
    {
      'title': 'Chatterbox TTS',
      'desc': 'Resemble AI Voice · 500M · Ultra Low Latency',
      'icon': 'voice',
      'downloadId': 'chatterbox-tts',
      'tag': 'English',
    },
    {
      'title': 'Chatterbox Multilingual V3',
      'desc': 'Resemble AI · 23+ Languages · High Expressiveness',
      'icon': 'language',
      'downloadId': 'chatterbox-tts',
      'tag': '23 languages',
    },
    {
      'title': 'Breeze TTS 2',
      'desc': 'BreezeBlue Voice Design · 3.4B · Cinematic Tone',
      'icon': 'sound',
      'downloadId': '',
      'tag': 'Cloud only',
    },
  ];

  static const List<Map<String, String>> _videoModels = [
    {
      'id': 'Wan 2.1 T2V 1.3B',
      'name': 'Wan 2.1 T2V 1.3B',
      'tag': 'Fast 1.3B DiT',
      'desc': 'Text-to-Video with natural cinematic camera motion at 480p/720p',
      'resolution': '480p / 720p',
      'speed': 'Fast (~15s)',
    },
    {
      'id': 'Wan 2.1 I2V 14B',
      'name': 'Wan 2.1 I2V 14B',
      'tag': 'Flagship 14B DiT',
      'desc': 'High-fidelity Image-to-Video diffusion bringing static artwork to life',
      'resolution': '720p HD',
      'speed': 'Quality (~45s)',
    },
    {
      'id': 'Wan 2.2 Animate 14B',
      'name': 'Wan 2.2 Animate 14B',
      'tag': 'Pose-Driven',
      'desc': 'Pose-driven character dance & animation from reference video + image',
      'resolution': '720p HD',
      'speed': 'Smooth (24fps)',
    },
    {
      'id': 'MiniMax-H3 Video+Audio',
      'name': 'MiniMax-H3 Video+Audio',
      'tag': 'Omni 33B',
      'desc': 'Joint multimodal diffusion generating synchronized soundscapes & video',
      'resolution': '720p + Audio',
      'speed': 'Full Production',
    },
    {
      'id': 'Lightricks LTX-Video',
      'name': 'Lightricks LTX-Video',
      'tag': 'Real-Time 0.9.1',
      'desc': 'Low-latency video diffusion with extreme camera trajectory precision',
      'resolution': '720p 30fps',
      'speed': 'Real-Time',
    },
  ];

  static const List<Map<String, String>> _imageModels = [
    {
      'id': 'Qwen-Image 2.1',
      'name': 'Qwen-Image 2.1',
      'tag': 'New 7B DiT',
      'desc': 'Unified 7B single-stream DiT for generation & editing with native 2K and transparent RGBA',
      'resolution': 'Up to 2048px',
      'speed': 'Fast (~8s)',
    },
    {
      'id': 'FLUX.1 Kontext [dev]',
      'name': 'FLUX.1 Kontext [dev]',
      'tag': 'Flagship 12B',
      'desc': 'State-of-the-art flow transformer with contextual conditioning & precise typography',
      'resolution': 'Up to 2048px',
      'speed': 'Quality (~20s)',
    },
    {
      'id': 'Z-Image Turbo',
      'name': 'Z-Image Turbo',
      'tag': '8-Step RF',
      'desc': 'Ultra-fast distilled Rectified Flow delivering photorealism in sub-second inference',
      'resolution': '1024x1024',
      'speed': 'Fast (~4s)',
    },
    {
      'id': 'SDXL Base 1.0',
      'name': 'SDXL Base 1.0',
      'tag': 'SDXL Base',
      'desc': 'Classic high-dynamic-range open diffusion base model with wide LoRA compatibility',
      'resolution': '1024x1024',
      'speed': 'Standard (~12s)',
    },
    {
      'id': 'FASHN VTON 1.5',
      'name': 'FASHN VTON 1.5',
      'tag': 'Virtual Try-On',
      'desc': 'Virtual try-on replacing outfits & garments while maintaining exact pose & identity',
      'resolution': 'High-Res VTON',
      'speed': 'Specialized (~18s)',
    },
  ];

  static const List<Map<String, String>> _enhancerModels = [
    {
      'id': 'Real-ESRGAN x4plus',
      'name': 'Real-ESRGAN x4plus',
      'tag': 'Official 4×',
      'desc': 'Practical blind super-resolution with high-order degradation for photos & AI art',
      'resolution': '4× Super-Res (up to 4K)',
      'speed': 'Fast (~3s)',
    },
    {
      'id': 'Real-ESRGAN Anime 6B',
      'name': 'Real-ESRGAN Anime 6B',
      'tag': 'Anime 6B',
      'desc': 'Compact 6-block model designed for anime illustrations & crisp clean 2D lineart',
      'resolution': '4× Super-Res',
      'speed': 'Ultra-Fast (~1.5s)',
    },
  ];

  @override
  void dispose() {
    _search.dispose();
    _previewTimer?.cancel();
    _cloneSpeakerNameController.dispose();
    super.dispose();
  }

  List<ProjectItem> get _pinned =>
      widget.projects.where((p) => p.isPinned).toList();
  List<ProjectItem> get _recent =>
      widget.projects.where((p) => !p.isPinned).toList();

  List<ProjectItem> _visible(List<ProjectItem> src) => _filter.isEmpty
      ? src
      : src
          .where((p) => p.title.toLowerCase().contains(_filter))
          .toList();

  void _onProjectAction(ProjectAction action, ProjectItem p) {
    switch (action) {
      case ProjectAction.rename:
        break;
      case ProjectAction.pin:
        widget.onTogglePin?.call(p);
        break;
      case ProjectAction.delete:
        widget.onDeleteProject?.call(p);
        break;
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_actionLabel(action)} is coming soon.'),
          ),
        );
    }
  }

  String _actionLabel(ProjectAction action) {
    switch (action) {
      case ProjectAction.share:
        return 'Share';
      case ProjectAction.rename:
        return 'Rename';
      case ProjectAction.pin:
        return 'Pin';
      case ProjectAction.archive:
        return 'Archive';
      case ProjectAction.delete:
        return 'Delete';
      case ProjectAction.moveToProject:
        return 'Move to project';
    }
  }

  void _togglePreviewPlayback(String voiceId) {
    if (_playingVoiceId == voiceId) {
      _stopPreview();
    } else {
      _startPreview(voiceId);
    }
  }

  void _startPreview(String voiceId) {
    _previewTimer?.cancel();
    setState(() {
      _playingVoiceId = voiceId;
      _previewPlaybackSeconds = 0;
    });

    _previewTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_previewPlaybackSeconds >= 24) {
        _stopPreview();
      } else {
        setState(() => _previewPlaybackSeconds++);
      }
    });
  }

  void _stopPreview() {
    _previewTimer?.cancel();
    if (mounted) {
      setState(() {
        _playingVoiceId = null;
        _previewPlaybackSeconds = 0;
      });
    }
  }

  Future<void> _pickAudioForCloning() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['wav', 'mp3', 'ogg', 'flac', 'm4a'],
      );
      if (result.isNotEmpty) {
        final file = result.first;
        final bytes = await file.readAsBytes();
        setState(() {
          _cloneAudioBytes = bytes;
          _cloneAudioName = file.name;
          if (_cloneSpeakerNameController.text.trim().isEmpty) {
            _cloneSpeakerNameController.text =
                file.name.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');
          }
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Audio loaded for cloning: ${file.name} (${(bytes.lengthInBytes / 1024).toStringAsFixed(1)} KB)'),
              backgroundColor: const Color(0xFF2E7D32),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load audio: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = LuminaTheme.isDark(context);
    final border = dark ? LuminaColors.darkBorder : LuminaColors.lightBorder;
    final muted = dark ? LuminaColors.darkMuted : LuminaColors.lightMuted;
    final card = dark ? LuminaColors.darkSurface : Colors.white;
    final collapsed = widget.collapsed;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOutCubic,
      width: collapsed ? 72 : 318,
      clipBehavior: Clip.hardEdge,
      margin: const EdgeInsets.fromLTRB(14, 8, 0, 14),
      decoration: BoxDecoration(
        color: card.withValues(alpha: dark ? 0.76 : 0.70),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.35 : 0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: collapsed
          ? _buildRail(dark, muted, card)
          : _buildFullPanel(dark, border, muted, card),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Collapsed 72px Rail
  // ─────────────────────────────────────────────────────────────
  Widget _buildRail(bool dark, Color muted, Color card) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      child: Column(
        children: [
          // New Project / Action button
          Tooltip(
            message: 'New Chat / Project',
            child: Material(
              color: Colors.transparent,
              child: Ink(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: LuminaColors.primaryGradient,
                  boxShadow: [
                    BoxShadow(
                      color: LuminaColors.primaryGlow.withValues(alpha: 0.45),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: InkWell(
                  onTap: () {
                    widget.onExpand?.call();
                    widget.onNewProject?.call();
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: const Center(
                    child: Icon(Icons.add, color: Colors.white, size: 20),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Collapsed Tab Switcher Icons
          _buildRailTabIcon(
            tab: SidebarTab.history,
            icon: Icons.chat_bubble_outline_rounded,
            tooltip: 'History / Chats',
            dark: dark,
          ),
          const SizedBox(height: 8),
          _buildRailTabIcon(
            tab: SidebarTab.voice,
            icon: Icons.record_voice_over_rounded,
            tooltip: 'Voice Studio & Cloning',
            dark: dark,
          ),
          const SizedBox(height: 8),
          _buildRailTabIcon(
            tab: SidebarTab.video,
            icon: Icons.videocam_outlined,
            tooltip: 'Video Mode (Wan & MiniMax)',
            dark: dark,
          ),
          const SizedBox(height: 8),
          _buildRailTabIcon(
            tab: SidebarTab.image,
            icon: Icons.image_outlined,
            tooltip: 'Image Studio (Qwen / FLUX / DiT)',
            dark: dark,
          ),
          const SizedBox(height: 8),
          _buildRailTabIcon(
            tab: SidebarTab.enhancer,
            icon: Icons.auto_fix_high_rounded,
            tooltip: 'AI Enhancer (Real-ESRGAN)',
            dark: dark,
          ),
          const SizedBox(height: 8),
          _buildRailTabIcon(
            tab: SidebarTab.cloud,
            icon: Icons.cloud_outlined,
            tooltip: 'Cloud GPU Mode (Vast.ai)',
            dark: dark,
          ),
          const SizedBox(height: 8),
          _buildRailTabIcon(
            tab: SidebarTab.library,
            icon: Icons.collections_bookmark_rounded,
            tooltip: 'My Library (Cloud Saves & Posts)',
            dark: dark,
          ),

          const SizedBox(height: 14),
          Divider(color: dark ? Colors.white12 : Colors.black12, height: 1),
          const SizedBox(height: 10),

          // Scrollable project thumbnails when in history tab
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final p in widget.projects)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: IconButton(
                        onPressed: () {
                          widget.onSelectProject?.call(p.id);
                          widget.onExpand?.call();
                        },
                        icon: Icon(
                          p.isPinned
                              ? Icons.folder_special_rounded
                              : Icons.chat_bubble_outline_rounded,
                          size: 18,
                          color: p.id == widget.activeProjectId
                              ? const Color(0xFFD32F2F)
                              : muted,
                        ),
                        tooltip: p.title,
                        style: IconButton.styleFrom(
                          backgroundColor: p.id == widget.activeProjectId
                              ? LuminaColors.primaryGlow.withValues(alpha: 0.16)
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 10),
          ListenableBuilder(
            listenable: AuthService.instance,
            builder: (context, _) {
              final user = AuthService.instance.currentUser;
              final name = user?.displayName?.isNotEmpty == true
                  ? user!.displayName!
                  : (user?.username ?? 'Guest');
              final credits = user?.credits ?? 0;
              return Tooltip(
                message: '$name — $credits Credits',
                child: InkWell(
                  onTap: widget.onExpand,
                  borderRadius: BorderRadius.circular(16),
                  child: _avatar(card, 32),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRailTabIcon({
    required SidebarTab tab,
    required IconData icon,
    required String tooltip,
    required bool dark,
  }) {
    final isSelected = _currentTab == tab;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            setState(() => _currentTab = tab);
            widget.onTabChanged?.call(tab);
            if (tab == SidebarTab.cloud) {
              widget.onOpenCloudMode?.call();
            } else {
              widget.onExpand?.call();
            }
          },
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isSelected
                  ? (dark ? const Color(0xFFD32F2F).withValues(alpha: 0.22) : const Color(0xFFD32F2F).withValues(alpha: 0.14))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: isSelected
                  ? Border.all(color: const Color(0xFFD32F2F).withValues(alpha: 0.5), width: 1.2)
                  : null,
            ),
            child: Icon(
              icon,
              size: 20,
              color: isSelected
                  ? const Color(0xFFD32F2F)
                  : (dark ? Colors.white70 : Colors.black54),
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Full 318px Sidebar Panel
  // ─────────────────────────────────────────────────────────────
  Widget _buildFullPanel(bool dark, Color border, Color muted, Color card) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ─── Top Tabs Bar ────────────────────────────────────
          _buildTopTabsBar(dark, border),
          const SizedBox(height: 12),

          // ─── Mode Content View ───────────────────────────────
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _buildSelectedTabContent(dark, border, muted, card),
            ),
          ),

          const SizedBox(height: 10),
          _buildProfile(context, dark),
        ],
      ),
    );
  }

  // ── Top Tabs Segmented Switcher ──────────────────────────────
  /// The seven studio tabs as a two-row grid (4 + 3) of equal-width tiles with
  /// icon and label. A grid, not icon-only tabs with an expanding pill: in the
  /// 318 px sidebar, six icon tabs leave about 70 px for the selected pill, too
  /// little for labels such as "Enhance"; here every label is always readable,
  /// nothing scrolls or clips, and tiles keep a fixed size (no layout jump).
  static const List<(SidebarTab, String, IconData)> _tabs = [
    (SidebarTab.history, 'History', Icons.forum_rounded),
    (SidebarTab.voice, 'Voice', Icons.mic_rounded),
    (SidebarTab.video, 'Video', Icons.videocam_rounded),
    (SidebarTab.image, 'Image', Icons.photo_rounded),
    (SidebarTab.enhancer, 'Enhance', Icons.auto_fix_high_rounded),
    (SidebarTab.cloud, 'Cloud', Icons.cloud_outlined),
    (SidebarTab.library, 'Library', Icons.collections_bookmark_rounded),
  ];

  Widget _buildTopTabsBar(bool dark, Color border) {
    const gap = 6.0;
    return Container(
      key: const ValueKey('sidebar_tabs'),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: dark ? Colors.black.withValues(alpha: 0.35) : Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tileWidth = (constraints.maxWidth - 3 * gap) / 4;
          Widget row(Iterable<(SidebarTab, String, IconData)> tabs) => Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final (i, t) in tabs.indexed) ...[
                    if (i > 0) const SizedBox(width: gap),
                    SizedBox(width: tileWidth, child: _buildTabButton(tab: t.$1, label: t.$2, icon: t.$3, dark: dark)),
                  ],
                ],
              );
          return Column(
            children: [
              row(_tabs.take(4)),
              const SizedBox(height: gap),
              row(_tabs.skip(4)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTabButton({
    required SidebarTab tab,
    required String label,
    required IconData icon,
    required bool dark,
  }) {
    return _SidebarTabTile(
      key: ValueKey('sidebar_tab_${tab.name}'),
      label: label,
      icon: icon,
      dark: dark,
      selected: _currentTab == tab,
      onTap: () {
        setState(() => _currentTab = tab);
        widget.onTabChanged?.call(tab);
        if (tab == SidebarTab.cloud) {
          widget.onOpenCloudMode?.call();
        }
      },
    );
  }

  // ── Content Switcher based on Tab ────────────────────────────
  Widget _buildSelectedTabContent(bool dark, Color border, Color muted, Color card) {
    switch (_currentTab) {
      case SidebarTab.voice:
        return _buildVoiceModePanel(dark, border, muted);
      case SidebarTab.video:
        return _buildVideoModePanel(dark, border, muted);
      case SidebarTab.image:
        return _buildImageModePanel(dark, border, muted);
      case SidebarTab.enhancer:
        return _buildEnhancerModePanel(dark, border, muted);
      case SidebarTab.cloud:
      case SidebarTab.library:
      case SidebarTab.history:
        return _buildHistoryPanel(dark, border, muted, card);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // TAB 1: HISTORY (Chat History & Projects)
  // ─────────────────────────────────────────────────────────────
  Widget _buildHistoryPanel(bool dark, Color border, Color muted, Color card) {
    final pinned = _visible(_pinned);
    final recent = _visible(_recent);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // New Project Button
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(LuminaColors.cardRadius),
            gradient: LuminaColors.primaryGradient,
            boxShadow: [
              BoxShadow(
                color: LuminaColors.primaryGlow.withValues(alpha: 0.40),
                blurRadius: 14,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: FilledButton.icon(
            onPressed: widget.onNewProject,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(LuminaColors.cardRadius),
              ),
              padding: const EdgeInsets.symmetric(vertical: 11),
            ),
            icon: const Icon(Icons.add, size: 18, color: Colors.white),
            label: const Text(
              'New Creation Chat',
              style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white, fontSize: 13),
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Search Bar
        TextField(
          controller: _search,
          onChanged: (v) => setState(() => _filter = v.trim().toLowerCase()),
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Search Chats & Generations',
            hintStyle: TextStyle(fontSize: 12.5, color: muted),
            prefixIcon: Icon(Icons.search, size: 16, color: muted),
            filled: true,
            fillColor: dark ? Colors.white.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.7),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(LuminaColors.pillRadius),
              borderSide: BorderSide(color: border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(LuminaColors.pillRadius),
              borderSide: BorderSide(color: border),
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
          ),
        ),
        const SizedBox(height: 10),

        // Scrollable Project Items
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (pinned.isNotEmpty) ...[
                  _SectionHeader('Pinned Chats', muted),
                  ...pinned.map((p) => SidebarProjectTile(
                        icon: Icons.folder_special_outlined,
                        title: p.title,
                        isPinned: p.isPinned,
                        isSelected: p.id == widget.activeProjectId,
                        onTap: () => widget.onSelectProject?.call(p.id),
                        onRename: (newTitle) => widget.onRenameTitle?.call(p.id, newTitle),
                        onActionSelected: (a) => _onProjectAction(a, p),
                      )),
                  const SizedBox(height: 10),
                ],
                _SectionHeader('Recent Chats', muted),
                if (recent.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Text(
                      'No recent chats yet',
                      style: TextStyle(
                        fontSize: 12,
                        color: muted.withValues(alpha: 0.6),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  )
                else
                  ...recent.map((p) => SidebarProjectTile(
                        icon: Icons.chat_bubble_outline_rounded,
                        title: p.title,
                        isPinned: p.isPinned,
                        isSelected: p.id == widget.activeProjectId,
                        onTap: () => widget.onSelectProject?.call(p.id),
                        onRename: (newTitle) => widget.onRenameTitle?.call(p.id, newTitle),
                        onActionSelected: (a) => _onProjectAction(a, p),
                      )),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // TAB 2: VOICE STUDIO & CLONING PANEL
  // ─────────────────────────────────────────────────────────────
  Widget _buildVoiceModePanel(bool dark, Color border, Color muted) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(right: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Section Title
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFD32F2F).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.record_voice_over_rounded, size: 16, color: Color(0xFFD32F2F)),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Voice Studio',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF34A853).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'ACTIVE',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF34A853)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // New Voice Project / Fresh Session Button
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: const LinearGradient(
                colors: [Color(0xFFD32F2F), Color(0xFFB71C1C)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFD32F2F).withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: FilledButton.icon(
              onPressed: widget.onNewVoiceProject ?? widget.onNewProject,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              icon: const Icon(Icons.add_rounded, size: 18, color: Colors.white),
              label: const Text(
                'New Voice Project',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  fontSize: 12.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 1. Voice Engine / Model Selector
          _SectionHeader('1. Voice Model', muted),
          ..._voiceModels.map((m) => _buildVoiceModelCard(
                model: m,
                isSelected: _selectedVoiceModel == m['title'],
                dark: dark,
                border: border,
                muted: muted,
              )),
          const SizedBox(height: 6),

          // 2. Voice Options & 20-30s Audio Previews
          _SectionHeader('2. Voice Personas & Preview', muted),
          Text(
            'Tap play to preview 20-30s studio audio clips:',
            style: TextStyle(fontSize: 11, color: muted),
          ),
          const SizedBox(height: 6),

          ..._voicePresets.map((preset) => _buildVoicePresetCard(preset, dark, border, muted)),
          const SizedBox(height: 14),

          // 3. Audio Adjustments (Pitch, Speed, Exaggeration, CFG)
          _SectionHeader('3. Audio Adjustments', muted),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: dark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Exaggeration Slider
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Emotion & Exaggeration', style: TextStyle(fontSize: 11.5, color: muted)),
                    Text('${(_exaggeration * 100).toInt()}%',
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  ),
                  child: Slider(
                    value: _exaggeration,
                    min: 0.0,
                    max: 1.0,
                    activeColor: const Color(0xFFD32F2F),
                    onChanged: (v) => setState(() => _exaggeration = v),
                  ),
                ),

                // Speed Slider
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Pacing & Speed', style: TextStyle(fontSize: 11.5, color: muted)),
                    Text('${_speechSpeed.toStringAsFixed(1)}x',
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  ),
                  child: Slider(
                    value: _speechSpeed,
                    min: 0.5,
                    max: 2.0,
                    divisions: 15,
                    activeColor: const Color(0xFFD32F2F),
                    onChanged: (v) => setState(() => _speechSpeed = v),
                  ),
                ),

                // CFG Guidance Weight
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Prompt Adherence (CFG)', style: TextStyle(fontSize: 11.5, color: muted)),
                    Text('${(_cfgWeight * 100).toInt()}%',
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  ),
                  child: Slider(
                    value: _cfgWeight,
                    min: 0.1,
                    max: 1.0,
                    activeColor: const Color(0xFFD32F2F),
                    onChanged: (v) => setState(() => _cfgWeight = v),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 4. Voice Cloning Upload Section
          _SectionHeader('4. Instant Voice Cloning', muted),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF1E2530) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _cloneAudioBytes != null ? const Color(0xFF2E7D32) : border,
                width: _cloneAudioBytes != null ? 1.5 : 1.0,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.cloud_upload_outlined,
                      size: 20,
                      color: _cloneAudioBytes != null ? const Color(0xFF2E7D32) : const Color(0xFFD32F2F),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Clone Any Speaker Voice',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Upload a 5-30 second clear audio clip (WAV/MP3). Zero-shot clone will mimic timbre, pitch, and accent.',
                  style: TextStyle(fontSize: 11, color: muted, height: 1.3),
                ),
                const SizedBox(height: 10),

                // Upload Button or File Preview
                if (_cloneAudioBytes == null)
                  OutlinedButton.icon(
                    onPressed: _pickAudioForCloning,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      side: BorderSide(color: border),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.file_upload_outlined, size: 16),
                    label: const Text('Select Audio File (.wav, .mp3)', style: TextStyle(fontSize: 12)),
                  )
                else ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E7D32).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF2E7D32).withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.audiotrack, size: 18, color: Color(0xFF2E7D32)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _cloneAudioName ?? 'Reference Audio',
                                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '${(_cloneAudioBytes!.lengthInBytes / 1024).toStringAsFixed(1)} KB · Ready for inference',
                                style: const TextStyle(fontSize: 10, color: Color(0xFF2E7D32)),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => setState(() {
                            _cloneAudioBytes = null;
                            _cloneAudioName = null;
                          }),
                          icon: const Icon(Icons.close, size: 16),
                          tooltip: 'Remove uploaded sample',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Speaker Custom Name
                  TextField(
                    controller: _cloneSpeakerNameController,
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      labelText: 'Custom Voice Label',
                      labelStyle: TextStyle(fontSize: 11, color: muted),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ── Voice Persona Card with 20-30s Audio Player ──────────────
  Widget _buildVoicePresetCard(VoicePreset preset, bool dark, Color border, Color muted) {
    final isSelected = _selectedVoicePresetId == preset.id;
    final isPlaying = _playingVoiceId == preset.id;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected
            ? (dark ? const Color(0xFF262D38) : Colors.white)
            : (dark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02)),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected ? const Color(0xFFD32F2F).withValues(alpha: 0.5) : border,
          width: isSelected ? 1.4 : 1.0,
        ),
      ),
      child: InkWell(
        onTap: () => setState(() => _selectedVoicePresetId = preset.id),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected
                          ? const Color(0xFFD32F2F).withValues(alpha: 0.15)
                          : (dark ? Colors.white10 : Colors.black12),
                    ),
                    child: Icon(
                      preset.icon,
                      size: 17,
                      color: isSelected ? const Color(0xFFD32F2F) : (dark ? Colors.white70 : Colors.black54),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                preset.name,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '(${preset.gender})',
                              style: TextStyle(fontSize: 10, color: muted),
                            ),
                          ],
                        ),
                        Text(
                          preset.tags,
                          style: TextStyle(fontSize: 10, color: muted),
                        ),
                      ],
                    ),
                  ),
                  // Radio Indicator
                  Icon(
                    isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    size: 16,
                    color: isSelected ? const Color(0xFFD32F2F) : muted,
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // Audio preview mini player bar (20-30s simulation)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: dark ? Colors.black.withValues(alpha: 0.25) : Colors.black.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    InkWell(
                      onTap: () => _togglePreviewPlayback(preset.id),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isPlaying ? const Color(0xFFD32F2F) : (dark ? Colors.white24 : Colors.black12),
                        ),
                        child: Icon(
                          isPlaying ? Icons.pause : Icons.play_arrow_rounded,
                          size: 15,
                          color: isPlaying ? Colors.white : (dark ? Colors.white : Colors.black87),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Text(
                                  isPlaying ? 'Playing Sample (${_previewPlaybackSeconds}s / 24s)' : '24s Audio Sample',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    color: isPlaying ? const Color(0xFFD32F2F) : muted,
                                    fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ),
                              Text(
                                '${isPlaying ? "0:${_previewPlaybackSeconds.toString().padLeft(2, '0')}" : "0:00"} / 0:24',
                                style: TextStyle(fontSize: 9, color: muted),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          LinearProgressIndicator(
                            value: isPlaying ? (_previewPlaybackSeconds / 24.0) : 0.0,
                            minHeight: 3,
                            backgroundColor: dark ? Colors.white12 : Colors.black12,
                            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFD32F2F)),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // TAB 3: VIDEO MODE PANEL (Wan 2.1 / Wan 2.2 / MiniMax)
  // ─────────────────────────────────────────────────────────────
  // ─────────────────────────────────────────────────────────────
  // TAB 3: VIDEO MODE PANEL (Wan 2.1 / Wan 2.2 / MiniMax / LTX)
  // ─────────────────────────────────────────────────────────────
  Widget _buildVideoModePanel(bool dark, Color border, Color muted) {
    final filteredTemplates = _videoTemplateCategory == 'All'
        ? VideoTemplate.curatedTemplates
        : VideoTemplate.curatedTemplates
            .where((t) => t.category == _videoTemplateCategory)
            .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.only(right: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: LuminaColors.primaryStart.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.videocam_rounded, size: 17, color: LuminaColors.primaryEnd),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Video Studio & Motion',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Multi-frame cinematic AI video & DiT motion',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // New Video Project / Fresh Session Button
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: LuminaColors.primaryGradient,
              boxShadow: [
                BoxShadow(
                  color: LuminaColors.primaryGlow.withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: FilledButton.icon(
              onPressed: widget.onNewVideoProject ?? widget.onNewProject,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              icon: const Icon(Icons.add_rounded, size: 18, color: Colors.white),
              label: const Text(
                'New Video Project',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  fontSize: 12.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // SECTION 1: VIDEO MODELS SELECTION WITH BLUE TICK ICON
          _SectionHeader('Video Models', muted),
          const SizedBox(height: 2),
          Text(
            'Select an AI video model to activate for generation:',
            style: TextStyle(fontSize: 11, color: muted),
          ),
          const SizedBox(height: 8),
          for (final model in _videoModels)
            _buildVideoModelCard(
              model: model,
              isSelected: _selectedVideoModel == model['id'],
              dark: dark,
              border: border,
              muted: muted,
            ),

          const SizedBox(height: 18),

          // SECTION 2: AMAZING VIDEO TEMPLATES (Silent preview with title)
          _SectionHeader('Cinematic Video Templates', muted),
          const SizedBox(height: 2),
          Text(
            'Silent preview with title inside. Tap any template to populate prompt container with all settings.',
            style: TextStyle(fontSize: 11, color: muted),
          ),
          const SizedBox(height: 10),

          // Category Filter Bar
          _buildVideoTemplateCategoryFilter(dark, border, muted),
          const SizedBox(height: 10),

          // Templates List
          for (final template in filteredTemplates) ...[
            _VideoTemplateCard(
              template: template,
              isSelected: _selectedVideoTemplateId == template.id,
              dark: dark,
              border: border,
              muted: muted,
              onSelect: () {
                setState(() {
                  _selectedVideoTemplateId = template.id;
                  _selectedVideoModel = template.model;
                });
                widget.onSelectVideoModel?.call(template.model);
                widget.onSelectVideoTemplate?.call(template);
              },
            ),
            const SizedBox(height: 12),
          ],

          const SizedBox(height: 10),

          // SECTION 3: VIDEO GUIDELINES
          _SectionHeader('Video Prompting Pro Tips', muted),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: dark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTipRow('Camera Movement:', 'Use terms like "FPV drone dive", "360 orbit", "slow push-in", or "lateral tracking".', muted),
                const SizedBox(height: 6),
                _buildTipRow('Aspect Ratios:', 'Use 16:9 for landscape cinema, or 9:16 for TikTok/Reels fashion videos.', muted),
                const SizedBox(height: 6),
                _buildTipRow('Driving Motion:', 'When using Wan 2.2 Animate, attach a 2s-15s reference motion video.', muted),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  /// A voice model card, like the Image and Video panels: select it, and
  /// download its weights for the local engine (or see that it is cloud-only).
  Widget _buildVoiceModelCard({
    required Map<String, String> model,
    required bool isSelected,
    required bool dark,
    required Color border,
    required Color muted,
  }) {
    final title = model['title']!;
    final downloadId = model['downloadId'] ?? '';
    final cloudOnly = downloadId.isEmpty;
    return Padding(
      key: ValueKey('voice_model_card_$title'),
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => setState(() => _selectedVoiceModel = title),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: isSelected
                ? (dark ? LuminaColors.primaryStart.withValues(alpha: 0.14) : LuminaColors.primaryStart.withValues(alpha: 0.08))
                : (dark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02)),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? LuminaColors.primaryStart : border,
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                    size: 20,
                    color: isSelected ? LuminaColors.primaryStart : (dark ? Colors.white24 : Colors.black26),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                        color: isSelected ? LuminaColors.primaryEnd : null,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: cloudOnly
                          ? Colors.cyanAccent.withValues(alpha: 0.12)
                          : (dark ? Colors.white.withValues(alpha: 0.07) : Colors.black.withValues(alpha: 0.05)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      model['tag'] ?? '',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: cloudOnly ? Colors.cyan.shade700 : muted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(model['desc']!, style: TextStyle(fontSize: 11, color: muted, height: 1.3)),
                    const SizedBox(height: 6),
                    if (cloudOnly)
                      Text(
                        'Runs on a cloud GPU; no local download.',
                        style: TextStyle(fontSize: 10.5, color: muted, fontStyle: FontStyle.italic),
                      )
                    else
                      ModelDownloadButton(
                        modelId: downloadId,
                        displayName: downloadId == 'chatterbox-tts' ? 'Chatterbox (English + Multilingual)' : title,
                        isSelected: isSelected,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoModelCard({
    required Map<String, String> model,
    required bool isSelected,
    required bool dark,
    required Color border,
    required Color muted,
  }) {
    final modelId = model['id']!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () {
          setState(() => _selectedVideoModel = modelId);
          widget.onSelectVideoModel?.call(modelId);
        },
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: isSelected
                ? (dark ? LuminaColors.primaryStart.withValues(alpha: 0.14) : LuminaColors.primaryStart.withValues(alpha: 0.08))
                : (dark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02)),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? LuminaColors.primaryStart : border,
              width: isSelected ? 1.5 : 1.0,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: LuminaColors.primaryGlow.withValues(alpha: 0.20),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Tick Icon with circular red gradient badge when selected!
                  if (isSelected) ...[
                    Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(
                        gradient: LuminaColors.primaryGradient,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x66D32F2F),
                            blurRadius: 6,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ] else ...[
                    Icon(
                      Icons.radio_button_unchecked_rounded,
                      size: 20,
                      color: dark ? Colors.white24 : Colors.black26,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      model['name']!,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                        color: isSelected ? LuminaColors.primaryEnd : null,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? LuminaColors.primaryStart.withValues(alpha: 0.20)
                          : (dark ? Colors.white.withValues(alpha: 0.07) : Colors.black.withValues(alpha: 0.05)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      model['tag']!,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? LuminaColors.primaryEnd : muted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ModelDownloadButton(
                    modelId: model['id']!,
                    displayName: model['name']!,
                    isSelected: isSelected,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      model['desc']!,
                      style: TextStyle(fontSize: 11, color: muted, height: 1.3),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Icon(Icons.hd_outlined, size: 12, color: muted.withValues(alpha: 0.8)),
                        const SizedBox(width: 4),
                        Text(
                          model['resolution']!,
                          style: TextStyle(fontSize: 10, color: muted.withValues(alpha: 0.9), fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(width: 12),
                        Icon(Icons.speed_rounded, size: 12, color: muted.withValues(alpha: 0.8)),
                        const SizedBox(width: 4),
                        Text(
                          model['speed']!,
                          style: TextStyle(fontSize: 10, color: muted.withValues(alpha: 0.9), fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoTemplateCategoryFilter(bool dark, Color border, Color muted) {
    const categories = [
      'All',
      'Cinematic Drone',
      'Commercial 360',
      'Anime & Action',
      'Fashion & Character',
      'Nature & Wildlife',
      'Visual FX / Macro',
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final cat in categories)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(cat),
                selected: _videoTemplateCategory == cat,
                onSelected: (selected) {
                  if (selected) {
                    setState(() => _videoTemplateCategory = cat);
                  }
                },
                labelStyle: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: _videoTemplateCategory == cat
                      ? Colors.white
                      : (dark ? Colors.white70 : Colors.black87),
                ),
                selectedColor: LuminaColors.primaryStart,
                backgroundColor: dark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                  side: BorderSide(
                    color: _videoTemplateCategory == cat ? LuminaColors.primaryStart : border,
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTipRow(String title, String text, Color muted) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('• ', style: TextStyle(fontSize: 11, color: muted, fontWeight: FontWeight.bold)),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: TextStyle(fontSize: 11, color: muted, height: 1.35),
              children: [
                TextSpan(text: '$title ', style: const TextStyle(fontWeight: FontWeight.bold)),
                TextSpan(text: text),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // TAB 4: IMAGE MODE PANEL (FLUX / Z-Image / SDXL / FASHN)
  // ─────────────────────────────────────────────────────────────
  Widget _buildImageModePanel(bool dark, Color border, Color muted) {
    final filteredTemplates = _imageTemplateCategory == 'All'
        ? ImageTemplate.curatedTemplates
        : ImageTemplate.curatedTemplates
            .where((t) => t.category == _imageTemplateCategory)
            .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.only(right: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: LuminaColors.primaryStart.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.photo_library_rounded, size: 17, color: LuminaColors.primaryEnd),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Image Studio & Art',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'State-of-the-art text-to-image & neural editing',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // New Image Project / Fresh Session Button
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: LuminaColors.primaryGradient,
              boxShadow: [
                BoxShadow(
                  color: LuminaColors.primaryGlow.withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: FilledButton.icon(
              onPressed: widget.onNewImageProject ?? widget.onNewProject,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              icon: const Icon(Icons.add_photo_alternate_rounded, size: 18, color: Colors.white),
              label: const Text(
                'New Image Project',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  fontSize: 12.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // DEEPFACE WEBCAM CAPTURE ACTION
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: LinearGradient(
                colors: dark
                    ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                    : [const Color(0xFFF1F5F9), const Color(0xFFE2E8F0)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                color: LuminaColors.primaryStart.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: LuminaColors.primaryStart.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.face_retouching_natural,
                    color: LuminaColors.primaryEnd,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'DeepFace Live Cam',
                        style: TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'Live video call clone (Deep-Live-Cam)',
                        style: TextStyle(fontSize: 10.5, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonal(
                  onPressed: widget.onOpenDeepFaceCamera,
                  style: FilledButton.tonalStyleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor:
                        LuminaColors.primaryStart.withValues(alpha: 0.25),
                  ),
                  child: const Text(
                    'Capture',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: LuminaColors.primaryEnd,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // SECTION 1: IMAGE MODELS SELECTION WITH RED GRADIENT TICK ICON
          _SectionHeader('Image Models', muted),
          const SizedBox(height: 2),
          Text(
            'Select an AI image model to activate for generation:',
            style: TextStyle(fontSize: 11, color: muted),
          ),
          const SizedBox(height: 8),
          for (final model in _imageModels)
            _buildImageModelCard(
              model: model,
              isSelected: _selectedImageModel == model['id'],
              dark: dark,
              border: border,
              muted: muted,
            ),

          const SizedBox(height: 18),

          // SECTION 2: CURATED IMAGE TEMPLATES
          _SectionHeader('Curated Image Templates', muted),
          const SizedBox(height: 2),
          Text(
            'Tap any template to populate prompt container with all required settings.',
            style: TextStyle(fontSize: 11, color: muted),
          ),
          const SizedBox(height: 10),

          // Category Filter Bar
          _buildImageTemplateCategoryFilter(dark, border, muted),
          const SizedBox(height: 10),

          // Templates List
          for (final template in filteredTemplates) ...[
            _ImageTemplateCard(
              template: template,
              isSelected: _selectedImageTemplateId == template.id,
              dark: dark,
              border: border,
              muted: muted,
              onSelect: () {
                setState(() {
                  _selectedImageTemplateId = template.id;
                  _selectedImageModel = template.model;
                });
                widget.onSelectImageModel?.call(template.model);
                widget.onSelectImageTemplate?.call(template);
              },
            ),
            const SizedBox(height: 12),
          ],

          const SizedBox(height: 10),

          // SECTION 3: IMAGE GUIDELINES
          _SectionHeader('Image Prompting Pro Tips', muted),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: dark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTipRow('Aspect Ratios:', 'Use 1:1 for square avatars/social, 16:9 for cinematic landscapes, or 9:16 for posters/stories.', muted),
                const SizedBox(height: 6),
                _buildTipRow('Virtual Try-On:', 'When using FASHN VTON 1.5, provide reference images for both the person and clothing.', muted),
                const SizedBox(height: 6),
                _buildTipRow('Lighting Detail:', 'Specify lighting terms like "volumetric rim lighting, Octane Render 8k, soft diffusion" for peak realism.', muted),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildImageModelCard({
    required Map<String, String> model,
    required bool isSelected,
    required bool dark,
    required Color border,
    required Color muted,
  }) {
    final modelId = model['id']!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () {
          setState(() => _selectedImageModel = modelId);
          widget.onSelectImageModel?.call(modelId);
        },
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: isSelected
                ? (dark ? LuminaColors.primaryStart.withValues(alpha: 0.14) : LuminaColors.primaryStart.withValues(alpha: 0.08))
                : (dark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02)),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? LuminaColors.primaryStart : border,
              width: isSelected ? 1.5 : 1.0,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: LuminaColors.primaryGlow.withValues(alpha: 0.20),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (isSelected) ...[
                    Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(
                        gradient: LuminaColors.primaryGradient,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x66D32F2F),
                            blurRadius: 6,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ] else ...[
                    Icon(
                      Icons.radio_button_unchecked_rounded,
                      size: 20,
                      color: dark ? Colors.white24 : Colors.black26,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      model['name']!,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                        color: isSelected ? LuminaColors.primaryEnd : null,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? LuminaColors.primaryStart.withValues(alpha: 0.20)
                          : (dark ? Colors.white.withValues(alpha: 0.07) : Colors.black.withValues(alpha: 0.05)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      model['tag']!,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? LuminaColors.primaryEnd : muted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ModelDownloadButton(
                    modelId: model['id']!,
                    displayName: model['name']!,
                    isSelected: isSelected,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      model['desc']!,
                      style: TextStyle(fontSize: 11, color: muted, height: 1.3),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Icon(Icons.photo_size_select_actual_outlined, size: 12, color: muted.withValues(alpha: 0.8)),
                        const SizedBox(width: 4),
                        Text(
                          model['resolution']!,
                          style: TextStyle(fontSize: 10, color: muted.withValues(alpha: 0.9), fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(width: 12),
                        Icon(Icons.speed_rounded, size: 12, color: muted.withValues(alpha: 0.8)),
                        const SizedBox(width: 4),
                        Text(
                          model['speed']!,
                          style: TextStyle(fontSize: 10, color: muted.withValues(alpha: 0.9), fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageTemplateCategoryFilter(bool dark, Color border, Color muted) {
    const categories = [
      'All',
      'Portrait & Character',
      'Product & Commercial',
      'Anime & Fantasy',
      'Fashion & Try-On',
      'Architecture',
      'Nature & Macro',
      'Sci-Fi & 3D',
      'Cinematic Still',
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final cat in categories)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(cat),
                selected: _imageTemplateCategory == cat,
                onSelected: (selected) {
                  if (selected) {
                    setState(() => _imageTemplateCategory = cat);
                  }
                },
                labelStyle: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: _imageTemplateCategory == cat
                      ? Colors.white
                      : (dark ? Colors.white70 : Colors.black87),
                ),
                selectedColor: LuminaColors.primaryStart,
                backgroundColor: dark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                  side: BorderSide(
                    color: _imageTemplateCategory == cat ? LuminaColors.primaryStart : border,
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // TAB 5: AI ENHANCER PANEL (Real-ESRGAN x4plus & Anime 6B)
  // ─────────────────────────────────────────────────────────────
  Widget _buildEnhancerModePanel(bool dark, Color border, Color muted) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(right: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: LuminaColors.primaryStart.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.auto_fix_high_rounded, size: 17, color: LuminaColors.primaryEnd),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI Image Enhancer',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Real-ESRGAN 4× Super-Resolution & Clarity',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // New Enhance Project Button
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: LuminaColors.primaryGradient,
              boxShadow: [
                BoxShadow(
                  color: LuminaColors.primaryGlow.withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: FilledButton.icon(
              onPressed: widget.onNewEnhanceProject ?? widget.onNewProject,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              icon: const Icon(Icons.add_photo_alternate_rounded, size: 18, color: Colors.white),
              label: const Text(
                'New Enhancement',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  fontSize: 12.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Section Title: Models
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'ENHANCER ENGINE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: muted,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: LuminaColors.primaryStart.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'RRDBNet 4×',
                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: LuminaColors.primaryEnd),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Model Cards
          ..._enhancerModels.map((m) {
            final isSelected = _selectedEnhancerModel == m['id'];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: () {
                  setState(() => _selectedEnhancerModel = m['id']!);
                  widget.onSelectEnhancerModel?.call(m['id']!);
                },
                borderRadius: BorderRadius.circular(10),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? (dark ? const Color(0xFF281F26) : const Color(0xFFFFF0F3))
                        : (dark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03)),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? LuminaColors.primaryStart : border,
                      width: isSelected ? 1.5 : 1.0,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                            size: 16,
                            color: isSelected ? LuminaColors.primaryStart : muted,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              m['name']!,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                                color: isSelected ? (dark ? Colors.white : LuminaColors.primaryStart) : null,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isSelected ? LuminaColors.primaryStart : (dark ? Colors.white10 : Colors.black12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              m['tag']!,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: isSelected ? Colors.white : muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        m['desc']!,
                        style: TextStyle(fontSize: 11, color: muted, height: 1.3),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.photo_size_select_large_rounded, size: 12, color: muted),
                          const SizedBox(width: 4),
                          Text(m['resolution']!, style: TextStyle(fontSize: 10.5, color: muted)),
                          const Spacer(),
                          const Icon(Icons.bolt_rounded, size: 12, color: LuminaColors.primaryEnd),
                          const SizedBox(width: 2),
                          Text(m['speed']!, style: TextStyle(fontSize: 10.5, color: muted)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),

          const SizedBox(height: 10),

          // Scale Selector
          Text(
            'UPSCALE SCALE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: muted,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildScaleChip(
                  scale: 4,
                  label: '4× Ultra 4K',
                  subtitle: 'Highest clarity & super-res',
                  dark: dark,
                  border: border,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildScaleChip(
                  scale: 2,
                  label: '2× Fast HD',
                  subtitle: 'Quick crisp sharpening',
                  dark: dark,
                  border: border,
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Face Restoration Toggle
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: dark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: border),
            ),
            child: Row(
              children: [
                const Icon(Icons.face_retouching_natural_rounded, size: 20, color: LuminaColors.primaryEnd),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Face Restoration (GFPGAN)',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        'Sharpen eyes, skin & facial contours',
                        style: TextStyle(fontSize: 10.5, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _enhancerFaceRestore,
                  onChanged: (val) => setState(() => _enhancerFaceRestore = val),
                  activeThumbColor: LuminaColors.primaryStart,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Pro Tips Info Card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF1E2430) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.tips_and_updates_rounded, size: 15, color: Colors.amber),
                    const SizedBox(width: 6),
                    Text(
                      'HOW AI ENHANCER WORKS',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: dark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '• Real-ESRGAN operates purely in high-fidelity pixel space without needing a text prompt.\n• Upload low-res, compressed, or blurry photos to upscale 4× into crystal-clear detail.\n• Great for vintage photos, AI art upscaling, and anime wallpapers.',
                  style: TextStyle(fontSize: 10.5, color: muted, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildScaleChip({
    required int scale,
    required String label,
    required String subtitle,
    required bool dark,
    required Color border,
  }) {
    final isSelected = _enhancerScale == scale;
    return InkWell(
      onTap: () => setState(() => _enhancerScale = scale),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? (dark ? const Color(0xFF281F26) : const Color(0xFFFFF0F3))
              : (dark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? LuminaColors.primaryStart : border,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: isSelected ? LuminaColors.primaryStart : null,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 9.5, color: isSelected ? LuminaColors.primaryStart.withValues(alpha: 0.8) : Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // ─────────────────────────────────────────────────────────────
  // Profile Card (Bottom of Sidebar)
  // ─────────────────────────────────────────────────────────────
  Widget _buildProfile(BuildContext context, bool isDark) {
    return ListenableBuilder(
      listenable: AuthService.instance,
      builder: (context, _) {
        final user = AuthService.instance.currentUser;
        final displayName = user?.displayName?.isNotEmpty == true
            ? user!.displayName!
            : (user?.username ?? 'Guest User');
        final email = user?.email ?? 'Not signed in';
        final credits = user?.credits ?? 0;
        final initials = (user?.displayName ?? user?.username ?? 'CG')
            .trim()
            .split(' ')
            .where((s) => s.isNotEmpty)
            .map((s) => s[0])
            .take(2)
            .join('')
            .toUpperCase();

        final avatarWidget = Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: const Color(0xFFD32F2F),
              backgroundImage: (user?.avatarUrl != null && user!.avatarUrl!.isNotEmpty)
                  ? NetworkImage(user.avatarUrl!)
                  : null,
              child: (user?.avatarUrl == null || user!.avatarUrl!.isEmpty)
                  ? Text(
                      initials.isEmpty ? 'CG' : initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  : null,
            ),
            Positioned(
              bottom: -1,
              right: -1,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: user != null ? const Color(0xFF34A853) : Colors.grey,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDark ? const Color(0xFF14181F) : const Color(0xFFF3F1EC),
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ],
        );

        return PopupMenuButton<String>(
          tooltip: '',
          padding: EdgeInsets.zero,
          offset: const Offset(0, -190),
          elevation: 12,
          color: isDark ? const Color(0xFF1E232D) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06),
            ),
          ),
          onSelected: (value) async {
            if (value == 'account') {
              _openSettingsDialog(context, initialTab: 0);
            } else if (value == 'models') {
              _openSettingsDialog(context, initialTab: 1);
            } else if (value == 'preferences') {
              _openSettingsDialog(context, initialTab: 2);
            } else if (value == 'logout') {
              await AuthService.instance.signOut();
            }
          },
          itemBuilder: (ctx) => [
            _buildProfileMenuItem(
              value: 'account',
              icon: Icons.person_outline_rounded,
              title: 'Account Settings',
              isDark: isDark,
            ),
            _buildProfileMenuItem(
              value: 'models',
              icon: Icons.tune_rounded,
              title: 'Models & Paths',
              isDark: isDark,
            ),
            _buildProfileMenuItem(
              value: 'preferences',
              icon: Icons.settings_outlined,
              title: 'Preferences',
              isDark: isDark,
            ),
            const PopupMenuDivider(height: 10),
            _buildProfileMenuItem(
              value: 'logout',
              icon: Icons.logout_rounded,
              title: 'Sign Out',
              isDark: isDark,
              isDestructive: true,
            ),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1A1F29) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.05),
              ),
            ),
            child: Row(
              children: [
                avatarWidget,
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              displayName,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 12.5,
                                color: isDark ? Colors.white : const Color(0xFF14181F),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5B942).withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                color: const Color(0xFFF5B942).withValues(alpha: 0.35),
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.stars_rounded, color: Color(0xFFF5B942), size: 10),
                                const SizedBox(width: 2.5),
                                Text(
                                  '$credits cr',
                                  style: const TextStyle(
                                    color: Color(0xFFF5B942),
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        email,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: isDark ? Colors.white54 : Colors.black45,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.more_vert,
                  size: 16,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  PopupMenuItem<String> _buildProfileMenuItem({
    required String value,
    required IconData icon,
    required String title,
    required bool isDark,
    bool isDestructive = false,
  }) {
    final textColor = isDestructive
        ? const Color(0xFFFF5252)
        : (isDark ? Colors.white : const Color(0xFF14181F));
    final iconColor = isDestructive
        ? const Color(0xFFFF5252)
        : (isDark ? Colors.white60 : Colors.black54);

    return PopupMenuItem<String>(
      value: value,
      height: 38,
      child: Row(
        children: [
          Icon(icon, size: 17, color: iconColor),
          const SizedBox(width: 10),
          Text(title, style: TextStyle(fontSize: 13, color: textColor)),
        ],
      ),
    );
  }

  void _openSettingsDialog(BuildContext context, {int initialTab = 0}) {
    showDialog(
      context: context,
      builder: (ctx) => SettingsDialog(initialTab: initialTab),
    );
  }

  Widget _avatar(Color card, double size) {
    final user = AuthService.instance.currentUser;
    final initials = (user?.displayName ?? user?.username ?? 'CG')
        .trim()
        .split(' ')
        .where((s) => s.isNotEmpty)
        .map((s) => s[0])
        .take(2)
        .join('')
        .toUpperCase();

    return Stack(
      children: [
        Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LuminaColors.primaryGradient,
          ),
          child: Center(
            child: (user?.avatarUrl != null && user!.avatarUrl!.isNotEmpty)
                ? ClipOval(
                    child: Image.network(
                      user.avatarUrl!,
                      width: size,
                      height: size,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Text(
                        initials.isEmpty ? 'CG' : initials,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: size * 0.35,
                        ),
                      ),
                    ),
                  )
                : Text(
                    initials.isEmpty ? 'CG' : initials,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: size * 0.35,
                    ),
                  ),
          ),
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: size * 0.28,
            height: size * 0.28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: user != null ? const Color(0xFF34D17B) : Colors.grey,
              border: Border.all(color: card, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  final Color muted;
  const _SectionHeader(this.text, this.muted);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 4),
      child: Text(text.toUpperCase(),
          style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: muted)),
    );
  }
}

class SidebarProjectTile extends StatefulWidget {
  final IconData icon;
  final String title;
  final bool isPinned;
  final bool isSelected;
  final VoidCallback? onTap;
  final ValueChanged<String>? onRename;
  final Function(ProjectAction action)? onActionSelected;

  const SidebarProjectTile({
    super.key,
    required this.icon,
    required this.title,
    this.isPinned = false,
    this.isSelected = false,
    this.onTap,
    this.onRename,
    this.onActionSelected,
  });

  @override
  State<SidebarProjectTile> createState() => _SidebarProjectTileState();
}

class _SidebarProjectTileState extends State<SidebarProjectTile> {
  bool _isHovered = false;
  bool _isMenuOpen = false;
  bool _isEditing = false;
  bool _isSubmitting = false;

  late TextEditingController _editController;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _editController = TextEditingController(text: widget.title);
    _focusNode = FocusNode(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _cancelEditing();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    );
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant SidebarProjectTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isEditing && oldWidget.title != widget.title) {
      _editController.text = widget.title;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _editController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!_focusNode.hasFocus && _isEditing) {
      if (!_isSubmitting) {
        _cancelEditing();
      }
    }
  }

  void _startEditing() {
    _isSubmitting = false;
    setState(() {
      _isEditing = true;
      _isMenuOpen = false;
      _editController.text = widget.title;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      _editController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _editController.text.length,
      );
    });
  }

  void _commitRename() {
    if (!_isEditing) return;
    _isSubmitting = true;

    final trimmed = _editController.text.trim();
    if (trimmed.isNotEmpty && trimmed != widget.title) {
      widget.onRename?.call(trimmed);
    } else {
      _editController.text = widget.title;
    }

    setState(() {
      _isEditing = false;
      _isSubmitting = false;
    });
  }

  void _cancelEditing() {
    setState(() {
      _editController.text = widget.title;
      _isEditing = false;
      _isSubmitting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Container(
        height: 38,
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: _isEditing
              ? (isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.04))
              : widget.isSelected
                  ? (isDark
                      ? LuminaColors.primaryGlow.withValues(alpha: 0.16)
                      : const Color(0xFFD32F2F).withValues(alpha: 0.10))
                  : (_isHovered || _isMenuOpen)
                      ? (isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.05))
                      : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: _isEditing
              ? Border.all(
                  color: const Color(0xFFD32F2F).withValues(alpha: 0.5),
                  width: 1,
                )
              : widget.isSelected
                  ? Border.all(
                      color: const Color(0xFFD32F2F).withValues(alpha: 0.35),
                      width: 1,
                    )
                  : null,
        ),
        child: _isEditing
            ? _buildInlineEditingRow(isDark)
            : _buildDisplayRow(isDark),
      ),
    );
  }

  Widget _buildInlineEditingRow(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 10, right: 6),
      child: Row(
        children: [
          Icon(widget.icon, size: 18, color: const Color(0xFFD32F2F)),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _editController,
              focusNode: _focusNode,
              onSubmitted: (_) => _commitRename(),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : const Color(0xFF14181F),
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
          Listener(
            onPointerDown: (_) => _isSubmitting = true,
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: _commitRename,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFFD32F2F).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(
                  Icons.check,
                  size: 16,
                  color: Color(0xFFD32F2F),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: _cancelEditing,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(
                Icons.close,
                size: 16,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDisplayRow(bool isDark) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: widget.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            if (widget.isSelected)
              Container(
                width: 3,
                height: 14,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFD32F2F),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            Icon(
              widget.icon,
              size: 18,
              color: widget.isSelected
                  ? const Color(0xFFD32F2F)
                  : (isDark ? Colors.white70 : Colors.black54),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      widget.isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: widget.isSelected
                      ? (isDark ? Colors.white : const Color(0xFFD32F2F))
                      : (isDark ? Colors.white : const Color(0xFF14181F)),
                ),
              ),
            ),
            if (widget.isPinned && !_isHovered && !_isMenuOpen)
              const Icon(Icons.star, size: 14, color: Color(0xFFF5B942)),
            if (_isHovered || _isMenuOpen)
              PopupMenuButton<ProjectAction>(
                tooltip: '',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 190),
                elevation: 10,
                offset: const Offset(20, 0),
                color: const Color(0xFF21252D),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                onOpened: () => setState(() => _isMenuOpen = true),
                onCanceled: () => setState(() => _isMenuOpen = false),
                onSelected: (action) {
                  setState(() => _isMenuOpen = false);
                  if (action == ProjectAction.rename) {
                    _startEditing();
                  } else {
                    widget.onActionSelected?.call(action);
                  }
                },
                itemBuilder: (context) => [
                  _buildMenuItem(
                    ProjectAction.share,
                    Icons.ios_share_rounded,
                    'Share',
                  ),
                  _buildMenuItem(
                    ProjectAction.rename,
                    Icons.edit_outlined,
                    'Rename',
                  ),
                  _buildMenuItem(
                    ProjectAction.pin,
                    widget.isPinned
                        ? Icons.star_border
                        : Icons.push_pin_outlined,
                    widget.isPinned ? 'Unpin chat' : 'Pin chat',
                  ),
                  _buildMenuItem(
                    ProjectAction.archive,
                    Icons.archive_outlined,
                    'Archive',
                  ),
                  _buildMenuItem(
                    ProjectAction.delete,
                    Icons.delete_outline,
                    'Delete',
                    isDestructive: true,
                  ),
                  _buildMenuItem(
                    ProjectAction.moveToProject,
                    Icons.folder_outlined,
                    'Move to project',
                  ),
                ],
                child: const SizedBox(
                  width: 28,
                  height: 28,
                  child: Center(
                    child: Icon(Icons.more_horiz,
                        size: 18, color: Colors.white70),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<ProjectAction> _buildMenuItem(
    ProjectAction value,
    IconData icon,
    String title, {
    bool isDestructive = false,
  }) {
    final color = isDestructive ? const Color(0xFFFF5252) : Colors.white;
    return PopupMenuItem<ProjectAction>(
      value: value,
      height: 38,
      child: Row(
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 12),
          Text(title, style: TextStyle(fontSize: 13, color: color)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// VIDEO TEMPLATE CARDS & SILENT PREVIEW PLAYER
// ─────────────────────────────────────────────────────────────

class _VideoTemplateCard extends StatelessWidget {
  final VideoTemplate template;
  final bool isSelected;
  final bool dark;
  final Color border;
  final Color muted;
  final VoidCallback onSelect;

  const _VideoTemplateCard({
    required this.template,
    required this.isSelected,
    required this.dark,
    required this.border,
    required this.muted,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onSelect,
      borderRadius: BorderRadius.circular(11),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isSelected
              ? (dark
                  ? LuminaColors.primaryStart.withValues(alpha: 0.16)
                  : LuminaColors.primaryStart.withValues(alpha: 0.08))
              : (dark
                  ? Colors.white.withValues(alpha: 0.03)
                  : Colors.black.withValues(alpha: 0.02)),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: isSelected ? LuminaColors.primaryStart : border,
            width: isSelected ? 1.5 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: LuminaColors.primaryGlow.withValues(alpha: 0.22),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Video Display Viewport Without Sound with Title in it!
            SilentVideoPreviewPlayer(
              template: template,
              isSelected: isSelected,
            ),

            // Template Details & Apply Action
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    template.description,
                    style: TextStyle(fontSize: 11, color: muted, height: 1.3),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),

                  // Tags
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final tag in template.tags)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: dark
                                ? Colors.white.withValues(alpha: 0.06)
                                : Colors.black.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            tag,
                            style: TextStyle(
                              fontSize: 9.5,
                              color: muted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Parameter Summary
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: dark
                          ? Colors.white.withValues(alpha: 0.03)
                          : Colors.black.withValues(alpha: 0.02),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: dark
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.black.withValues(alpha: 0.06),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${template.aspectRatio} • ${template.steps} steps',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: muted),
                        ),
                        Text(
                          'CFG ${template.cfgScale} • ${template.fps} fps',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Apply to Prompt Container Action Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: onSelect,
                      icon: const Icon(Icons.auto_awesome_rounded,
                          size: 13, color: Colors.white),
                      label: Text(
                        isSelected
                            ? 'Selected (Ready to Generate)'
                            : 'Load Template into Prompt',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isSelected
                            ? LuminaColors.primaryStart
                            : const Color(0xFF1E293B),
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(7)),
                        elevation: 0,
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

class _ImageTemplateCard extends StatelessWidget {
  final ImageTemplate template;
  final bool isSelected;
  final bool dark;
  final Color border;
  final Color muted;
  final VoidCallback onSelect;

  const _ImageTemplateCard({
    required this.template,
    required this.isSelected,
    required this.dark,
    required this.border,
    required this.muted,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onSelect,
      borderRadius: BorderRadius.circular(11),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isSelected
              ? (dark
                  ? LuminaColors.primaryStart.withValues(alpha: 0.16)
                  : LuminaColors.primaryStart.withValues(alpha: 0.08))
              : (dark
                  ? Colors.white.withValues(alpha: 0.03)
                  : Colors.black.withValues(alpha: 0.02)),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: isSelected ? LuminaColors.primaryStart : border,
            width: isSelected ? 1.5 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: LuminaColors.primaryGlow.withValues(alpha: 0.22),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Visual Header with Gradient, Icon, and Model Badge
            Container(
              height: 100,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                gradient: LinearGradient(
                  colors: template.gradientColors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.25),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          template.icon,
                          size: 32,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        template.category,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        template.model,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 8,
                    left: 8,
                    right: 8,
                    child: Text(
                      template.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(blurRadius: 4, color: Colors.black54),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Template Details & Apply Action
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    template.description,
                    style: TextStyle(fontSize: 11, color: muted, height: 1.3),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),

                  // Attachment Requirement Indicator
                  if (template.requiresAttachment) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.attachment_rounded, size: 12, color: Colors.amber),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              template.attachmentBadgeLabel,
                              style: const TextStyle(
                                fontSize: 9.5,
                                color: Colors.amber,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Tags
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final tag in template.tags)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: dark
                                ? Colors.white.withValues(alpha: 0.06)
                                : Colors.black.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            tag,
                            style: TextStyle(
                              fontSize: 9.5,
                              color: muted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Parameter Summary
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: dark
                          ? Colors.white.withValues(alpha: 0.03)
                          : Colors.black.withValues(alpha: 0.02),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: dark
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.black.withValues(alpha: 0.06),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${template.aspectRatio} • ${template.steps} steps',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: muted),
                        ),
                        Text(
                          'CFG ${template.cfgScale} • ${template.strength} str',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Apply to Prompt Container Action Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: onSelect,
                      icon: const Icon(Icons.auto_awesome_rounded,
                          size: 13, color: Colors.white),
                      label: Text(
                        isSelected
                            ? 'Selected (Ready to Generate)'
                            : 'Load Template into Prompt',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isSelected
                            ? LuminaColors.primaryStart
                            : const Color(0xFF1E293B),
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(7)),
                        elevation: 0,
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

/// One studio tab: pointer cursor, hover tint and lift, tooltip, keyboard focus
/// ring and pressed state; selected = brand red tint, red icon and border.
/// Fixed height, so switching tabs never moves the layout.
class _SidebarTabTile extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final bool dark;
  final VoidCallback onTap;

  const _SidebarTabTile({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.dark,
    required this.onTap,
  });

  @override
  State<_SidebarTabTile> createState() => _SidebarTabTileState();
}

class _SidebarTabTileState extends State<_SidebarTabTile> {
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  static const _duration = Duration(milliseconds: 200);
  static const _red = LuminaColors.primaryStart;

  @override
  Widget build(BuildContext context) {
    final dark = widget.dark;
    final selected = widget.selected;
    final background = selected
        ? _red.withValues(alpha: dark ? 0.20 : 0.10)
        : _hovered
            ? (dark ? Colors.white.withValues(alpha: 0.07) : Colors.black.withValues(alpha: 0.05))
            : Colors.transparent;
    final borderColor = _focused
        ? _red
        : selected
            ? _red.withValues(alpha: 0.55)
            : Colors.transparent;
    final iconColor = selected ? _red : (dark ? Colors.white60 : Colors.black54);
    final textColor =
        selected ? (dark ? Colors.white : const Color(0xFF14181F)) : (dark ? Colors.white70 : Colors.black87);

    return Tooltip(
      message: widget.label,
      waitDuration: const Duration(milliseconds: 500),
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
            widget.onTap();
            return null;
          }),
        },
        child: Semantics(
          button: true,
          selected: selected,
          label: widget.label,
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => setState(() => _pressed = true),
              onTapCancel: () => setState(() => _pressed = false),
              onTapUp: (_) => setState(() => _pressed = false),
              onTap: widget.onTap,
              child: AnimatedScale(
                scale: _pressed ? 0.96 : 1.0,
                duration: const Duration(milliseconds: 100),
                child: AnimatedSlide(
                  offset: _hovered && !selected ? const Offset(0, -0.03) : Offset.zero,
                  duration: _duration,
                  curve: Curves.easeOutCubic,
                  child: AnimatedContainer(
                    duration: _duration,
                    curve: Curves.easeOutCubic,
                    height: 46,
                    decoration: BoxDecoration(
                      color: background,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: borderColor, width: _focused ? 1.6 : 1.0),
                      boxShadow: selected || _hovered
                          ? [
                              BoxShadow(
                                color: (selected ? _red : Colors.black)
                                    .withValues(alpha: selected ? 0.18 : (dark ? 0.25 : 0.06)),
                                blurRadius: selected ? 10 : 6,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedSwitcher(
                          duration: _duration,
                          child: Icon(widget.icon, key: ValueKey(selected), size: 17, color: iconColor),
                        ),
                        const SizedBox(height: 3),
                        AnimatedDefaultTextStyle(
                          duration: _duration,
                          // Merge, so the label keeps the theme's font family.
                          style: DefaultTextStyle.of(context).style.merge(
                                TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                                  color: textColor,
                                ),
                              ),
                          child: Text(widget.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
