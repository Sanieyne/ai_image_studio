import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/image_template.dart';
import '../models/video_template.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'lora_manager.dart';

typedef PromptGenerateCallback = FutureOr<void> Function(
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
});

/// Floating frosted prompt bar: dropdown selector pills on top, pill
/// text field with upload/camera actions and a Generate button below.
class PromptInputBar extends StatefulWidget {
  final PromptGenerateCallback? onGenerate;
  final ApiService? apiService;

  const PromptInputBar({super.key, this.onGenerate, this.apiService});

  /// Display label -> HF repo id. Single source of truth for home_screen too.
  static const modelIds = {
    'Chatterbox TTS': 'ResembleAI/chatterbox',
    'Chatterbox Multilingual V3': 'ResembleAI/chatterbox-multilingual',
    'Breeze TTS 2': 'BreezeBlue/Breeze-TTS-2',
    'MiniMax-H3 Video+Audio': 'MiniMaxAI/MiniMax-H3',
    'Wan 2.1 T2V 1.3B': 'Wan-AI/Wan2.1-T2V-1.3B-Diffusers',
    'Wan 2.1 I2V 14B': 'Wan-AI/Wan2.1-I2V-14B-480P-Diffusers',
    'Wan 2.1 FLF2V 14B': 'Wan-AI/Wan2.1-FLF2V-14B-720P-Diffusers',
    'Wan 2.2 Animate 14B': 'Wan-AI/Wan2.2-Animate-14B',
    'Qwen-Image 2.1': 'Qwen/Qwen-Image-2.1',
    'FLUX.1 Kontext [dev]': 'black-forest-labs/FLUX.1-Kontext-dev',
    'SDXL Base 1.0': 'stabilityai/stable-diffusion-xl-base-1.0',
    'Z-Image Turbo': 'Tongyi-MAI/Z-Image-Turbo',
    'FASHN VTON 1.5': 'fashn-ai/fashn-vton-1.5',
    'Real-ESRGAN x4plus': 'amd/realesrgan-x4plus',
    'Real-ESRGAN Anime 6B': 'amd/realesrgan-anime-6b',
  };

  @override
  State<PromptInputBar> createState() => PromptInputBarState();
}

class _MenuOption {
  final String value;
  final String hint;
  final IconData icon;
  const _MenuOption(this.value, this.hint, this.icon);
}

class PromptInputBarState extends State<PromptInputBar> {
  final _controller = TextEditingController();
  final _negController = TextEditingController();
  final _instructionController = TextEditingController();
  final _refTextController = TextEditingController();
  bool _showNegativePrompt = false;
  String? _videoTemplateNotice;

  /// Programmatically populate the prompt bar with a full VideoTemplate
  void applyVideoTemplate(VideoTemplate template) {
    setState(() {
      _controller.text = template.prompt;
      if (template.negativePrompt.isNotEmpty) {
        _negController.text = template.negativePrompt;
        _showNegativePrompt = true;
      }
      _model = template.model;
      _mode = 'Video Mode';
      _ratio = template.aspectRatio;
      _steps = template.steps;
      _cfg = template.cfgScale;
      _strength = template.strength;
      _showTune = true;
      if (template.requiresAttachment) {
        _videoTemplateNotice = template.attachmentGuidance;
      } else {
        _videoTemplateNotice = null;
      }
    });
  }

  /// Programmatically populate the prompt bar with a full ImageTemplate
  void applyImageTemplate(ImageTemplate template) {
    setState(() {
      _controller.text = template.prompt;
      if (template.negativePrompt.isNotEmpty) {
        _negController.text = template.negativePrompt;
        _showNegativePrompt = true;
      }
      _model = template.model;
      _mode = template.isTryOnModel ? 'Virtual Try-On' : 'Text to Image';
      _ratio = template.aspectRatio;
      _steps = template.steps;
      _cfg = template.cfgScale;
      _strength = template.strength;
      _showTune = true;
      if (template.requiresImageAttachment) {
        _videoTemplateNotice = template.attachmentGuidance;
      } else {
        _videoTemplateNotice = null;
      }
    });
  }

  /// Programmatically set the image model
  void setImageModel(String modelName) {
    setState(() {
      _model = modelName;
      _mode = modelName.contains('FASHN') ? 'Virtual Try-On' : 'Text to Image';
    });
  }

  /// Programmatically set the video model
  void setVideoModel(String modelName) {
    setState(() {
      _model = modelName;
      _mode = 'Video Mode';
    });
  }

  /// Programmatically set the voice model
  void setVoiceModel(String modelName) {
    setState(() {
      _model = modelName;
      _mode = 'Voice Mode';
    });
  }

  /// Programmatically set the enhancer model
  void setEnhancerModel(String modelName) {
    setState(() {
      _model = modelName;
      _mode = 'AI Enhancer';
    });
  }

  /// Programmatically set the generation mode
  void setMode(String mode) {
    setState(() {
      _mode = mode;
    });
  }

  /// Clear all inputs for a fresh conversation session
  void clearInputs() {
    setState(() {
      _controller.clear();
      _negController.clear();
      _instructionController.clear();
      _refTextController.clear();
      _showNegativePrompt = false;
      _referenceBytes = null;
      _referenceName = null;
      _referenceBase64 = null;
      _endImageBytes = null;
      _endImageName = null;
      _endImageBase64 = null;
      _garmentBytes = null;
      _garmentName = null;
      _videoTemplateNotice = null;
    });
  }

  bool get _isVoiceModel =>
      _model.contains('Chatterbox') || _model.contains('Breeze');
  bool get _isMiniMaxModel => _model.contains('MiniMax');
  bool get _isWan21T2V => _model == 'Wan 2.1 T2V 1.3B';
  bool get _isWan21I2V => _model == 'Wan 2.1 I2V 14B';
  bool get _isWan21FLF2V => _model == 'Wan 2.1 FLF2V 14B';
  bool get _isWan21Model => _isWan21T2V || _isWan21I2V || _isWan21FLF2V;
  bool get _isVideoModel =>
      _model == 'Wan 2.2 Animate 14B' || _isWan21Model || _isMiniMaxModel;
  bool get _isTryOnModel => _model.contains('FASHN');
  bool get _isTryOnMode => _mode == 'Virtual Try-On' || _isTryOnModel;
  bool get _isEnhancerModel =>
      _model.contains('Real-ESRGAN') || _mode == 'AI Enhancer' || _mode == 'Enhancer';
  bool get _isEnhancerMode => _isEnhancerModel;
  int _enhancerScale = 4;
  bool _enhancerFaceRestore = true;

  Uint8List? _referenceBytes;
  String? _referenceName;
  String? _referenceBase64;
  Uint8List? _endImageBytes;
  String? _endImageName;
  String? _endImageBase64;
  Uint8List? _garmentBytes;
  String? _garmentName;
  String? _garmentBase64;
  String _tryonCategory = 'tops';
  String _garmentPhotoType = 'model';
  Uint8List? _referenceVideoBytes;
  String? _referenceVideoName;
  String? _referenceVideoBase64;
  Uint8List? _videoThumbnailBytes;
  Uint8List? _referenceAudioBytes;
  String? _referenceAudioName;
  String? _referenceAudioBase64;
  double _strength = 0.65;
  bool _showTune = false;
  int _steps = 16;
  double _cfg = 3.5;
  double _exaggeration = 0.5;
  String _language = 'en';

  static const _ratios = [
    _MenuOption('16:9', 'Landscape', Icons.crop_landscape),
    _MenuOption('9:16', 'Portrait', Icons.crop_portrait),
    _MenuOption('1:1', 'Square', Icons.crop_square),
    _MenuOption('4:5', 'Social', Icons.crop_5_4),
  ];
  static const _tryonCategories = [
    _MenuOption('tops', 'Tops (Shirts/Jackets)', Icons.checkroom),
    _MenuOption('bottoms', 'Bottoms (Pants/Skirts)', Icons.accessibility_new),
    _MenuOption('one-pieces', 'One-Pieces (Dresses/Suits)', Icons.dry_cleaning),
  ];
  static const _garmentPhotoTypes = [
    _MenuOption('model', 'Worn by Model', Icons.person_outline),
    _MenuOption('flat-lay', 'Flat-Lay Product Shot', Icons.layers_outlined),
  ];
  static const _models = [
    _MenuOption('Chatterbox TTS', 'Resemble AI Voice (500M)', Icons.record_voice_over_rounded),
    _MenuOption('Chatterbox Multilingual V3', '23+ Languages TTS', Icons.language_rounded),
    _MenuOption('Breeze TTS 2', 'BreezeBlue Voice Design (3.4B)', Icons.graphic_eq_rounded),
    _MenuOption('MiniMax-H3 Video+Audio', 'Omni Video+Audio (33B)', Icons.movie_filter_rounded),
    _MenuOption('Wan 2.1 T2V 1.3B', 'Fast Text-to-Video (1.3B)', Icons.videocam_rounded),
    _MenuOption('Wan 2.1 I2V 14B', 'Image-to-Video (14B)', Icons.movie_creation_rounded),
    _MenuOption('Wan 2.1 FLF2V 14B', 'First & Last Frame (14B)', Icons.auto_awesome_motion_rounded),
    _MenuOption('Wan 2.2 Animate 14B', 'Character Animation (14B)', Icons.animation),
    _MenuOption('Qwen-Image 2.1', 'Unified 7B DiT · Native 2K', Icons.auto_awesome),
    _MenuOption('FLUX.1 Kontext [dev]', 'Img2Img / Edit (12B)', Icons.auto_fix_high),
    _MenuOption('FASHN VTON 1.5', 'Virtual Try-On (972M)', Icons.checkroom_rounded),
    _MenuOption('Z-Image Turbo', 'Fast 6B DiT · 8 steps', Icons.bolt_rounded),
    _MenuOption('SDXL Base 1.0', 'Base Model', Icons.science_outlined),
    _MenuOption('Real-ESRGAN x4plus', '4× Photo & Art Super-Res', Icons.auto_fix_high_rounded),
    _MenuOption('Real-ESRGAN Anime 6B', '4× Anime & 2D Art', Icons.brush_rounded),
    _MenuOption('Offline Mock Mode', 'Test Only', Icons.laptop_chromebook),
  ];

  static const _modes = [
    _MenuOption('Image Mode', 'Single frame', Icons.image_outlined),
    _MenuOption('Virtual Try-On', 'Outfit & Garment Swap', Icons.checkroom_rounded),
    _MenuOption('Motion Animate', 'Video & Motion (Wan / MiniMax)', Icons.animation),
    _MenuOption('Video Mode', 'Multi frame', Icons.videocam_outlined),
    _MenuOption('Voice Studio', 'TTS & Voice Cloning', Icons.record_voice_over_rounded),
    _MenuOption('AI Enhancer', 'Super-Resolution 4×', Icons.auto_fix_high_rounded),
  ];

  static const _languages = [
    _MenuOption('en', 'English', Icons.language),
    _MenuOption('es', 'Spanish (Español)', Icons.language),
    _MenuOption('fr', 'French (Français)', Icons.language),
    _MenuOption('de', 'German (Deutsch)', Icons.language),
    _MenuOption('zh', 'Chinese (中文)', Icons.language),
    _MenuOption('ja', 'Japanese (日本語)', Icons.language),
    _MenuOption('ko', 'Korean (한국어)', Icons.language),
    _MenuOption('it', 'Italian (Italiano)', Icons.language),
    _MenuOption('pt', 'Portuguese (Português)', Icons.language),
    _MenuOption('hi', 'Hindi (हिन्दी)', Icons.language),
    _MenuOption('ar', 'Arabic (العربية)', Icons.language),
    _MenuOption('ru', 'Russian (Русский)', Icons.language),
    _MenuOption('nl', 'Dutch (Nederlands)', Icons.language),
    _MenuOption('tr', 'Turkish (Türkçe)', Icons.language),
    _MenuOption('sv', 'Swedish (Svenska)', Icons.language),
    _MenuOption('pl', 'Polish (Polski)', Icons.language),
  ];

  String _ratio = '9:16';
  String _model = 'Wan 2.2 Animate 14B';
  String _mode = 'Motion Animate';

  @override
  void dispose() {
    _controller.dispose();
    _negController.dispose();
    _instructionController.dispose();
    _refTextController.dispose();
    super.dispose();
  }

  Future<void> _pickReferenceImage() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
      );
      if (files.isNotEmpty) {
        final file = files.first;
        final bytes = await file.readAsBytes();
        setState(() {
          _referenceBytes = bytes;
          _referenceName = file.name;
          _referenceBase64 = base64Encode(bytes);
          if (_model == 'Wan 2.1 I2V 14B') {
            _videoTemplateNotice = null;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load reference image: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _pickEndImage() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
      );
      if (files.isNotEmpty) {
        final file = files.first;
        final bytes = await file.readAsBytes();
        setState(() {
          _endImageBytes = bytes;
          _endImageName = file.name;
          _endImageBase64 = base64Encode(bytes);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load end frame image: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _pickGarmentImage() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
      );
      if (files.isNotEmpty) {
        final file = files.first;
        final bytes = await file.readAsBytes();
        setState(() {
          _garmentBytes = bytes;
          _garmentName = file.name;
          _garmentBase64 = base64Encode(bytes);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load garment image: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _pickTemplateVideo() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp4', 'mov', 'webm'],
      );
      if (files.isNotEmpty) {
        final file = files.first;
        final bytes = await file.readAsBytes();
        Uint8List? thumbBytes;
        try {
          final tempDir = Directory.systemTemp;
          final tmpVideo = File(
              '${tempDir.path}/tmp_vid_${DateTime.now().millisecondsSinceEpoch}.mp4');
          await tmpVideo.writeAsBytes(bytes);
          final tmpThumb = File(
              '${tempDir.path}/tmp_thumb_${DateTime.now().millisecondsSinceEpoch}.jpg');
          await Process.run('ffmpeg', [
            '-y',
            '-ss',
            '00:00:00',
            '-i',
            tmpVideo.path,
            '-vframes',
            '1',
            tmpThumb.path,
          ]);
          if (await tmpThumb.exists()) {
            thumbBytes = await tmpThumb.readAsBytes();
            await tmpThumb.delete();
          }
          if (await tmpVideo.exists()) await tmpVideo.delete();
        } catch (_) {}

        setState(() {
          _referenceVideoBytes = bytes;
          _referenceVideoName = file.name;
          _referenceVideoBase64 = base64Encode(bytes);
          _videoThumbnailBytes = thumbBytes;
          _model = 'Wan 2.2 Animate 14B';
          _mode = 'Motion Animate';
          _steps = 4;
          _cfg = 1.0;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load template video: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _pickReferenceAudio() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['wav', 'mp3', 'm4a', 'ogg', 'flac'],
      );
      if (files.isNotEmpty) {
        final file = files.first;
        final bytes = await file.readAsBytes();
        setState(() {
          _referenceAudioBytes = bytes;
          _referenceAudioName = file.name;
          _referenceAudioBase64 = base64Encode(bytes);
          if (_mode != 'Voice Studio') {
            _mode = 'Voice Studio';
            _model = 'Chatterbox TTS';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load reference voice clip: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _submitEnhancer() {
    if (_referenceBytes == null || _referenceBase64 == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please upload or attach an image to upscale.'),
          backgroundColor: Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _pickReferenceImage();
      return;
    }

    widget.onGenerate?.call(
      'AI Upscale $_enhancerScale× ($_model)',
      '',
      '1:1',
      _model,
      _referenceBase64,
      1.0,
      _referenceBytes,
      20,
      0.0,
      upscaleScale: _enhancerScale,
      faceEnhance: _enhancerFaceRestore,
    );
  }

  void _submit() {
    if (_isEnhancerMode) {
      _submitEnhancer();
      return;
    }

    if (_isTryOnMode) {
      if (_referenceBytes == null && _garmentBytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Virtual Try-On requires both a Person photo (Slot 1) and a Garment photo (Slot 2).'),
            backgroundColor: Colors.orangeAccent,
          ),
        );
        _pickReferenceImage();
        return;
      }
      if (_referenceBytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please attach a Person photo (Slot 1) to dress.'),
            backgroundColor: Colors.orangeAccent,
          ),
        );
        _pickReferenceImage();
        return;
      }
      if (_garmentBytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please attach a Garment photo (Slot 2) for the outfit.'),
            backgroundColor: Colors.orangeAccent,
          ),
        );
        _pickGarmentImage();
        return;
      }
    }

    if (_isWan21I2V && _referenceBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Wan 2.1 I2V (Image-to-Video) requires an input image to animate. Please attach one using the photo icon.'),
          backgroundColor: Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _pickReferenceImage();
      return;
    }

    if (_isWan21FLF2V) {
      if (_referenceBytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Wan 2.1 FLF2V requires a starting frame image. Please attach one.'),
            backgroundColor: Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
        _pickReferenceImage();
        return;
      }
      if (_endImageBytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Wan 2.1 FLF2V requires an ending frame image. Please attach one.'),
            backgroundColor: Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
        _pickEndImage();
        return;
      }
    }

    if (_model == 'Wan 2.2 Animate 14B' &&
        _referenceBytes == null &&
        _referenceVideoBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Wan 2.2 Animate requires a character image or driving motion video. Please attach one.'),
          backgroundColor: Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _pickReferenceImage();
      return;
    }

    final text = _controller.text.trim();
    if (text.isEmpty &&
        _referenceBytes == null &&
        _garmentBytes == null &&
        _referenceVideoBytes == null &&
        _referenceAudioBytes == null) {
      return;
    }
    final promptText = text.isEmpty
        ? (_isTryOnMode
            ? 'Virtual try-on outfit swap ($_tryonCategory)'
            : (_referenceVideoBytes != null && _referenceBytes != null
                ? 'Animate character using driving motion video'
                : (_referenceVideoBytes != null
                    ? 'Animate video motion'
                    : (_referenceAudioBytes != null
                        ? 'Voice generation sample'
                        : 'Animate character with dynamic motion'))))
        : text;
    final neg = _negController.text.trim();

    // If user provided video only (no separate image), use the video's first frame as character image
    final effectiveImageBase64 = _referenceBase64 ??
        (_videoThumbnailBytes != null
            ? base64Encode(_videoThumbnailBytes!)
            : null);
    final effectiveImageBytes = _referenceBytes ?? _videoThumbnailBytes;

    final inst = _instructionController.text.trim();
    final refT = _refTextController.text.trim();

    widget.onGenerate?.call(
      promptText,
      neg,
      _ratio,
      _model,
      effectiveImageBase64,
      _strength,
      effectiveImageBytes,
      _steps,
      _cfg,
      videoBase64: _referenceVideoBase64,
      referenceVideoBytes: _referenceVideoBytes,
      referenceVideoName: _referenceVideoName,
      audioBase64: _referenceAudioBase64,
      referenceAudioBytes: _referenceAudioBytes,
      referenceAudioName: _referenceAudioName,
      language: _language,
      exaggeration: _exaggeration,
      instruction: inst.isNotEmpty ? inst : null,
      refText: refT.isNotEmpty ? refT : null,
      garmentBase64: _garmentBase64,
      garmentBytes: _garmentBytes,
      garmentName: _garmentName,
      tryonCategory: _tryonCategory,
      garmentPhotoType: _garmentPhotoType,
      endImageBase64: _endImageBase64,
      endImageBytes: _endImageBytes,
      endImageName: _endImageName,
    );
    setState(() {
      _controller.clear();
      _negController.clear();
      _instructionController.clear();
      _refTextController.clear();
      _showNegativePrompt = false;
      _referenceBytes = null;
      _referenceName = null;
      _referenceBase64 = null;
      _endImageBytes = null;
      _endImageName = null;
      _endImageBase64 = null;
      _garmentBytes = null;
      _garmentName = null;
      _garmentBase64 = null;
      _referenceVideoBytes = null;
      _referenceVideoName = null;
      _referenceVideoBase64 = null;
      _videoThumbnailBytes = null;
      _referenceAudioBytes = null;
      _referenceAudioName = null;
      _referenceAudioBase64 = null;
      _strength = 0.65;
    });
  }

  void _comingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature is coming soon in this build.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = LuminaTheme.isDark(context);
    final border = dark ? LuminaColors.darkBorder : LuminaColors.lightBorder;
    final muted = dark ? LuminaColors.darkMuted : LuminaColors.lightMuted;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.45 : 0.12),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: (dark ? LuminaColors.darkSurface : Colors.white)
                  .withValues(alpha: dark ? 0.72 : 0.7),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: border),
            ),
            child: _isEnhancerMode
                ? _buildEnhancerPromptContainer(dark, border, muted)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                // Top row: dropdown selector pills.
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _SelectorMenu(
                      options: _ratios,
                      value: _ratio,
                      muted: muted,
                      border: border,
                      // 4 options: spawn above the pill.
                      menuOffset: const Offset(0, -195),
                      onSelected: (v) =>
                          setState(() => _ratio = v),
                    ),
                    _SelectorMenu(
                      options: _models,
                      value: _model,
                      muted: muted,
                      border: border,
                      menuOffset: const Offset(0, -220),
                      onSelected: (v) => setState(() {
                        _model = v;
                        if (v == 'FASHN VTON 1.5') {
                          _mode = 'Virtual Try-On';
                          _steps = 30;
                          _cfg = 1.5;
                        } else if (v == 'Wan 2.1 T2V 1.3B') {
                          _mode = 'Video Mode';
                          _steps = 30;
                          _cfg = 5.0;
                        } else if (v == 'Wan 2.1 I2V 14B') {
                          _mode = 'Video Mode';
                          _steps = 30;
                          _cfg = 5.0;
                        } else if (v == 'Wan 2.1 FLF2V 14B') {
                          _mode = 'Video Mode';
                          _steps = 30;
                          _cfg = 5.0;
                        } else if (v == 'Wan 2.2 Animate 14B') {
                          _mode = 'Motion Animate';
                          _steps = 4;
                          _cfg = 1.0;
                        } else if (v == 'MiniMax-H3 Video+Audio') {
                          _mode = 'Motion Animate';
                          _steps = 30;
                          _cfg = 6.0;
                        } else if (v == 'Chatterbox TTS' ||
                            v == 'Chatterbox Multilingual V3' ||
                            v == 'Breeze TTS 2') {
                          _mode = 'Voice Studio';
                          _cfg = (v == 'Breeze TTS 2') ? 4.0 : 0.5;
                          _exaggeration = 0.5;
                        } else if (v == 'Qwen-Image 2.1') {
                          _mode = 'Image Mode';
                          _steps = 40;
                          _cfg = 1.0;
                        } else if (v == 'FLUX.1 Kontext [dev]') {
                          _mode = 'Image Mode';
                          _steps = 16;
                          _cfg = 3.5;
                        } else if (v == 'Z-Image Turbo') {
                          _mode = 'Image Mode';
                          _steps = 9;
                          _cfg = 0.0;
                        } else {
                          _mode = 'Image Mode';
                          _steps = 30;
                          _cfg = 7.0;
                        }
                      }),
                    ),
                    _SelectorMenu(
                      options: _modes,
                      value: _mode,
                      muted: muted,
                      border: border,
                      menuOffset: const Offset(0, -180),
                      onSelected: (v) => setState(() {
                        _mode = v;
                        if (v == 'Virtual Try-On') {
                          _model = 'FASHN VTON 1.5';
                          _steps = 30;
                          _cfg = 1.5;
                        } else if (v == 'Voice Studio') {
                          if (!_isVoiceModel) {
                            _model = 'Breeze TTS 2';
                          }
                          _cfg = _model.contains('Breeze') ? 4.0 : 0.5;
                          _exaggeration = 0.5;
                        } else if (v == 'Motion Animate' || v == 'Video Mode') {
                          if (!_isVideoModel) {
                            _model = 'MiniMax-H3 Video+Audio';
                          }
                          _steps = _isMiniMaxModel ? 30 : 4;
                          _cfg = _isMiniMaxModel ? 6.0 : 1.0;
                        } else if (_isVideoModel || _isVoiceModel || _isTryOnModel) {
                          _model = 'FLUX.1 Kontext [dev]';
                          _steps = 16;
                          _cfg = 3.5;
                        }
                      }),
                    ),
                    if (_isTryOnMode) ...[
                      _SelectorMenu(
                        options: _tryonCategories,
                        value: _tryonCategory,
                        muted: muted,
                        border: border,
                        menuOffset: const Offset(0, -150),
                        onSelected: (v) => setState(() => _tryonCategory = v),
                      ),
                      _SelectorMenu(
                        options: _garmentPhotoTypes,
                        value: _garmentPhotoType,
                        muted: muted,
                        border: border,
                        menuOffset: const Offset(0, -110),
                        onSelected: (v) =>
                            setState(() => _garmentPhotoType = v),
                      ),
                    ],
                    if (_mode == 'Voice Studio' || _isVoiceModel)
                      _SelectorMenu(
                        options: _languages,
                        value: _language,
                        muted: muted,
                        border: border,
                        menuOffset: const Offset(0, -260),
                        onSelected: (v) => setState(() => _language = v),
                      ),
                    _buildNegativePromptToggle(dark, border, muted),
                    _buildTuneToggle(dark, border, muted),
                    _buildLoraPill(dark, border, muted),
                  ],
                ),
                // Optional expandable tune sliders (steps / CFG or Exaggeration / CFG).
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 200),
                  crossFadeState: _showTune
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  firstChild: const SizedBox.shrink(),
                  secondChild: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: dark
                            ? Colors.white.withValues(alpha: 0.04)
                            : Colors.black.withValues(alpha: 0.03),
                        borderRadius:
                            BorderRadius.circular(LuminaColors.pillRadius),
                        border: Border.all(color: border),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      child: Column(
                        children: [
                          if (_mode == 'Voice Studio' || _isVoiceModel) ...[
                            if (_model.contains('Breeze')) ...[
                              Padding(
                                padding: const EdgeInsets.only(top: 4, bottom: 6),
                                child: TextField(
                                  controller: _instructionController,
                                  style: const TextStyle(fontSize: 12.5),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    labelText: 'Voice Design / Tone Direction (Optional)',
                                    hintText: 'e.g. A warm, thoughtful young woman with clear delivery',
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    prefixIcon: const Icon(Icons.record_voice_over, size: 16),
                                  ),
                                ),
                              ),
                              if (_referenceAudioBytes != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: TextField(
                                    controller: _refTextController,
                                    style: const TextStyle(fontSize: 12.5),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      labelText: 'Reference Audio Transcript (Optional)',
                                      hintText: 'Exact text spoken in the reference audio',
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                      prefixIcon: const Icon(Icons.subtitles_rounded, size: 16),
                                    ),
                                  ),
                                ),
                            ],
                            Row(
                              children: [
                                const Text('Exaggeration'),
                                Expanded(
                                  child: Slider(
                                    min: 0.0,
                                    max: 1.5,
                                    divisions: 30,
                                    value: _exaggeration,
                                    label: _exaggeration.toStringAsFixed(2),
                                    onChanged: (v) =>
                                        setState(() => _exaggeration = v),
                                  ),
                                ),
                                SizedBox(
                                  width: 36,
                                  child: Text(
                                    _exaggeration.toStringAsFixed(2),
                                    textAlign: TextAlign.end,
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Text(_model.contains('Breeze') ? 'Guidance Scale' : 'CFG Guidance'),
                                Expanded(
                                  child: Slider(
                                    min: 0.0,
                                    max: _model.contains('Breeze') ? 8.0 : 1.5,
                                    divisions: _model.contains('Breeze') ? 32 : 30,
                                    value: _cfg.clamp(0.0, _model.contains('Breeze') ? 8.0 : 1.5),
                                    label: _cfg.toStringAsFixed(2),
                                    onChanged: (v) =>
                                        setState(() => _cfg = v),
                                  ),
                                ),
                                SizedBox(
                                  width: 36,
                                  child: Text(
                                    _cfg.toStringAsFixed(2),
                                    textAlign: TextAlign.end,
                                  ),
                                ),
                              ],
                            ),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                _model.contains('Breeze')
                                    ? 'Breeze TTS 2 (3.4B): Use CFG ~4.0 for Voice Design/Direction; supports vocal events ((laugh), (sigh), [笑]) and zero-shot voice cloning.'
                                    : 'Chatterbox TTS: Higher exaggeration increases emotional expressiveness; lower CFG (~0.3) provides deliberate pacing.',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ] else ...[
                            Row(
                              children: [
                                const Text('Steps'),
                                Expanded(
                                  child: Slider(
                                    min: 1,
                                    max: 60,
                                    divisions: 59,
                                    value: _steps.toDouble(),
                                    label: '$_steps',
                                    onChanged: (v) => setState(
                                        () => _steps = v.round()),
                                  ),
                                ),
                                SizedBox(
                                    width: 36,
                                    child: Text('$_steps',
                                        textAlign: TextAlign.end)),
                              ],
                            ),
                            Row(
                              children: [
                                const Text('CFG'),
                                Expanded(
                                  child: Slider(
                                    min: 0.0,
                                    max: 15.0,
                                    divisions: 150,
                                    value: _cfg,
                                    label: _cfg.toStringAsFixed(1),
                                    onChanged: (v) =>
                                        setState(() => _cfg = v),
                                  ),
                                ),
                                SizedBox(
                                    width: 36,
                                    child: Text(_cfg.toStringAsFixed(1),
                                        textAlign: TextAlign.end)),
                              ],
                            ),
                            if (_model == 'Qwen-Image 2.1')
                              const Padding(
                                padding: EdgeInsets.only(bottom: 4),
                                child: Text(
                                  'Qwen-Image 2.1 (7B): Unified generation & editing DiT with 2K resolution & transparent RGBA.',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontStyle: FontStyle.italic),
                                ),
                              ),
                            if (_model == 'FLUX.1 Kontext [dev]')
                              const Padding(
                                padding: EdgeInsets.only(bottom: 4),
                                child: Text(
                                  'FLUX.1 Kontext (12B): Optimized for instruction-guided image-to-image editing.',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontStyle: FontStyle.italic),
                                ),
                              ),
                            if (_model == 'Z-Image Turbo')
                              const Padding(
                                padding: EdgeInsets.only(bottom: 4),
                                child: Text(
                                  'Z-Image Turbo (6B): 8-step distilled model. Keep CFG at 0 — guidance is baked in.',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontStyle: FontStyle.italic),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                // Optional Expandable Negative Prompt Field
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 200),
                  crossFadeState: _showNegativePrompt
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  firstChild: const SizedBox.shrink(),
                  secondChild: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: dark
                            ? Colors.white.withValues(alpha: 0.04)
                            : Colors.black.withValues(alpha: 0.03),
                        borderRadius:
                            BorderRadius.circular(LuminaColors.pillRadius),
                        border: Border.all(
                          color: Colors.redAccent.withValues(alpha: 0.28),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 2),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.block_outlined,
                            size: 15,
                            color: Colors.redAccent,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _negController,
                              onChanged: (_) => setState(() {}),
                              style: const TextStyle(fontSize: 12.5),
                              decoration: InputDecoration(
                                hintText:
                                    'Avoid: e.g. blurry, low quality, bad anatomy, deformed hands, duplicate, watermark',
                                hintStyle: TextStyle(
                                  fontSize: 12,
                                  color: muted.withValues(alpha: 0.65),
                                ),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding:
                                    const EdgeInsets.symmetric(vertical: 8),
                              ),
                            ),
                          ),
                          if (_negController.text.isNotEmpty) ...[
                            IconButton(
                              icon: const Icon(Icons.close, size: 14),
                              color: muted,
                              tooltip: 'Clear negative prompt',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () =>
                                  setState(() => _negController.clear()),
                            ),
                            const SizedBox(width: 4),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                if (_isTryOnMode)
                  _buildTryOnSlots(dark, border, muted)
                else ...[
                  if (_videoTemplateNotice != null)
                    _buildTemplateAttachmentNotice(dark, border),
                  _buildReferenceImagePreview(dark, border, muted),
                  _buildGarmentImagePreview(dark, border, muted),
                  _buildReferenceVideoPreview(dark, border, muted),
                  _buildReferenceAudioPreview(dark, border, muted),
                ],
                const SizedBox(height: 10),
                // Bottom row: input + actions.
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        onSubmitted: (_) => _submit(),
                        style: const TextStyle(fontSize: 13.5),
                        decoration: InputDecoration(
                          hintText: _isTryOnMode
                              ? 'Virtual Try-On (FASHN VTON 1.5): Attach person photo + garment photo...'
                              : (_isMiniMaxModel
                                  ? 'Describe video scene, action, and sounds (e.g. Neon cyberpunk street in rain, sirens & synth audio)...'
                                  : (_mode == 'Voice Studio' || _isVoiceModel
                                      ? (_model.contains('Breeze')
                                          ? 'Type what you want Breeze TTS 2 to speak (supports (laugh), (sigh), [笑]...)'
                                          : 'Type what you want Chatterbox to speak...')
                                      : 'Describe your character, prompt, motion style, or lighting...')),
                          hintStyle:
                              TextStyle(fontSize: 12.5, color: muted),
                          filled: true,
                          fillColor: dark
                              ? Colors.white
                                  .withValues(alpha: 0.06)
                              : Colors.white
                                  .withValues(alpha: 0.75),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                                LuminaColors.pillRadius),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding:
                              const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (_isTryOnMode)
                      IconButton(
                        onPressed: _pickGarmentImage,
                        icon: Icon(
                          _garmentBytes != null
                              ? Icons.checkroom
                              : Icons.checkroom_outlined,
                          size: 20,
                          color: _garmentBytes != null
                              ? LuminaColors.violet
                              : muted,
                        ),
                        tooltip: _garmentBytes != null
                            ? 'Change garment / clothing photo'
                            : 'Attach garment photo (FASHN VTON 1.5)',
                      ),
                    IconButton(
                      onPressed: _pickReferenceAudio,
                      icon: Icon(
                        _referenceAudioBytes != null
                            ? Icons.mic_rounded
                            : Icons.mic_none_outlined,
                        size: 20,
                        color: _referenceAudioBytes != null
                            ? LuminaColors.primaryGlow
                            : muted,
                      ),
                      tooltip: _referenceAudioBytes != null
                          ? 'Change voice clone clip'
                          : 'Attach voice reference clip (${_model.contains('Breeze') ? 'Breeze Voice Cloning' : 'Chatterbox Cloning'})',
                    ),
                    IconButton(
                      onPressed: _pickReferenceImage,
                      icon: Icon(
                        _referenceBytes != null
                            ? Icons.photo_library
                            : Icons.add_photo_alternate_outlined,
                        size: 20,
                        color: _referenceBytes != null
                            ? LuminaColors.primaryGlow
                            : muted,
                      ),
                      tooltip: _referenceBytes != null
                          ? (_isTryOnMode ? 'Change person photo' : 'Change character photo')
                          : (_isTryOnMode ? 'Attach person photo to dress' : 'Attach first frame photo (${_isMiniMaxModel ? 'MiniMax-H3' : (_isWan21Model ? 'Wan 2.1 I2V' : 'Wan 2.2 / Img2Img')})'),
                    ),
                    if (_isWan21FLF2V)
                      IconButton(
                        onPressed: _pickEndImage,
                        icon: Icon(
                          _endImageBytes != null
                              ? Icons.image_rounded
                              : Icons.flip_to_back_rounded,
                          size: 20,
                          color: _endImageBytes != null
                              ? LuminaColors.violet
                              : muted,
                        ),
                        tooltip: _endImageBytes != null
                            ? 'Change end frame photo'
                            : 'Attach end frame photo (Wan 2.1 FLF2V Morph)',
                      ),
                    IconButton(
                      onPressed: _pickTemplateVideo,
                      icon: Icon(
                        _referenceVideoBytes != null
                            ? Icons.video_file
                            : Icons.video_call_outlined,
                        size: 20,
                        color: _referenceVideoBytes != null
                            ? LuminaColors.primaryGlow
                            : muted,
                      ),
                      tooltip: _referenceVideoBytes != null
                          ? 'Change motion template video'
                          : 'Attach driving video (Wan 2.2 Motion)',
                    ),
                    IconButton(
                      onPressed: () =>
                          _comingSoon('Camera reference'),
                      icon: const Icon(Icons.camera_alt_outlined,
                          size: 20),
                      color: muted,
                      tooltip: 'Camera reference',
                    ),
                    const SizedBox(width: 4),
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(
                            LuminaColors.pillRadius),
                        gradient: LuminaColors.primaryGradient,
                        boxShadow: [
                          BoxShadow(
                            color: LuminaColors.primaryGlow
                                .withValues(alpha: 0.45),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: TextButton(
                        onPressed: _submit,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                          shape: const StadiumBorder(),
                        ),
                        child: Text(
                          _isVoiceModel
                              ? 'Speak 🎙️'
                              : (_isVideoModel
                                  ? 'Animate 🎬'
                                  : (_isTryOnMode
                                      ? 'Try On 👗'
                                      : 'Generate ⚡')),
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEnhancerPromptContainer(bool dark, Color border, Color muted) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top Control Row: Mode badge, Model picker, Scale selector, Face restore
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // Mode Indicator Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                gradient: LuminaColors.primaryGradient,
                borderRadius: BorderRadius.circular(LuminaColors.pillRadius),
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
                  Icon(Icons.auto_fix_high_rounded, size: 14, color: Colors.white),
                  SizedBox(width: 6),
                  Text(
                    'AI Enhancer',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),

            // Enhancer Model Selector
            _SelectorMenu(
              options: const [
                _MenuOption('Real-ESRGAN x4plus', '4× Photo & Art (Official)', Icons.auto_fix_high_rounded),
                _MenuOption('Real-ESRGAN Anime 6B', '4× Anime & 2D Art', Icons.brush_rounded),
              ],
              value: _model.contains('Anime') ? 'Real-ESRGAN Anime 6B' : 'Real-ESRGAN x4plus',
              muted: muted,
              border: border,
              menuOffset: const Offset(0, -110),
              onSelected: (v) => setState(() => _model = v),
            ),

            // Scale Toggle Chips
            Container(
              decoration: BoxDecoration(
                color: dark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(LuminaColors.pillRadius),
                border: Border.all(color: border),
              ),
              padding: const EdgeInsets.all(2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildMiniScaleChip(4, '4× Ultra 4K', dark),
                  _buildMiniScaleChip(2, '2× HD', dark),
                ],
              ),
            ),

            // GFPGAN Face Restoration Toggle
            InkWell(
              onTap: () => setState(() => _enhancerFaceRestore = !_enhancerFaceRestore),
              borderRadius: BorderRadius.circular(LuminaColors.pillRadius),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _enhancerFaceRestore
                      ? LuminaColors.primaryStart.withValues(alpha: 0.15)
                      : (dark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.04)),
                  borderRadius: BorderRadius.circular(LuminaColors.pillRadius),
                  border: Border.all(
                    color: _enhancerFaceRestore ? LuminaColors.primaryStart : border,
                    width: _enhancerFaceRestore ? 1.2 : 1.0,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _enhancerFaceRestore ? Icons.face_retouching_natural_rounded : Icons.face_rounded,
                      size: 14,
                      color: _enhancerFaceRestore ? LuminaColors.primaryEnd : muted,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _enhancerFaceRestore ? 'Face Restore: ON' : 'Face Restore: OFF',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: _enhancerFaceRestore ? FontWeight.bold : FontWeight.w500,
                        color: _enhancerFaceRestore ? LuminaColors.primaryEnd : muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Switch Back To Image Generator
            Tooltip(
              message: 'Switch back to Text-to-Image Generation',
              child: InkWell(
                onTap: () => setState(() {
                  _mode = 'Image Mode';
                  _model = 'FLUX.1 Kontext [dev]';
                }),
                borderRadius: BorderRadius.circular(LuminaColors.pillRadius),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: dark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(LuminaColors.pillRadius),
                    border: Border.all(color: border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.close_rounded, size: 13, color: muted),
                      const SizedBox(width: 4),
                      Text('Exit Enhancer', style: TextStyle(fontSize: 11, color: muted)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // Dedicated Friendly Image Dropzone & Preview Box
        if (_referenceBytes == null)
          InkWell(
            onTap: _pickReferenceImage,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              height: 115,
              decoration: BoxDecoration(
                color: dark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: LuminaColors.primaryStart.withValues(alpha: 0.35),
                  width: 1.5,
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: LuminaColors.primaryStart.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.add_photo_alternate_rounded,
                        size: 24,
                        color: LuminaColors.primaryEnd,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Click to select or upload an image to enhance',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Supports JPG, PNG, WEBP · Super-resolution up to 4K · No prompt needed',
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF1E2430) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: LuminaColors.primaryStart.withValues(alpha: 0.4), width: 1.2),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    _referenceBytes!,
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              _referenceName ?? 'Source Image',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: LuminaColors.primaryStart.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${(_referenceBytes!.lengthInBytes / 1024).toStringAsFixed(1)} KB',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: LuminaColors.primaryEnd,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Target Output: $_enhancerScale× Super-Resolution (${_model.contains('Anime') ? 'Anime 6B' : 'Official x4plus'})${_enhancerFaceRestore ? ' + GFPGAN Face Restore' : ''}',
                        style: TextStyle(fontSize: 11.5, color: muted),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: _pickReferenceImage,
                            icon: const Icon(Icons.refresh_rounded, size: 14),
                            label: const Text('Change Image', style: TextStyle(fontSize: 11)),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                          const SizedBox(width: 12),
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _referenceBytes = null;
                                _referenceBase64 = null;
                                _referenceName = null;
                              });
                            },
                            icon: const Icon(Icons.delete_outline_rounded, size: 14, color: Colors.redAccent),
                            label: const Text('Remove', style: TextStyle(fontSize: 11, color: Colors.redAccent)),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 12),

        // Action Row: Hint & Red Gradient Enhance Button
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  const Icon(Icons.bolt_rounded, size: 16, color: LuminaColors.primaryEnd),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      'Blind degradation removal · Operates directly on pixel tensors',
                      style: TextStyle(fontSize: 11, color: muted, fontStyle: FontStyle.italic),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LuminaColors.primaryGradient,
                boxShadow: [
                  BoxShadow(
                    color: LuminaColors.primaryGlow.withValues(alpha: 0.40),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: FilledButton.icon(
                onPressed: _submitEnhancer,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                ),
                icon: const Icon(Icons.auto_fix_high_rounded, size: 18, color: Colors.white),
                label: Text(
                  'Enhance & Upscale $_enhancerScale×',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMiniScaleChip(int scale, String label, bool dark) {
    final isSelected = _enhancerScale == scale;
    return InkWell(
      onTap: () => setState(() => _enhancerScale = scale),
      borderRadius: BorderRadius.circular(LuminaColors.pillRadius),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? LuminaColors.primaryStart
              : Colors.transparent,
          borderRadius: BorderRadius.circular(LuminaColors.pillRadius),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected
                ? Colors.white
                : (dark ? Colors.white70 : Colors.black87),
          ),
        ),
      ),
    );
  }

  Widget _buildNegativePromptToggle(bool dark, Color border, Color muted) {
    final hasText = _negController.text.trim().isNotEmpty;
    final isActive = _showNegativePrompt || hasText;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _showNegativePrompt = !_showNegativePrompt),
        borderRadius: BorderRadius.circular(LuminaColors.pillRadius),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: isActive
                ? (dark
                    ? Colors.redAccent.withValues(alpha: 0.15)
                    : Colors.redAccent.withValues(alpha: 0.08))
                : (dark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.white.withValues(alpha: 0.8)),
            borderRadius: BorderRadius.circular(LuminaColors.pillRadius),
            border: Border.all(
              color: isActive
                  ? Colors.redAccent.withValues(alpha: 0.5)
                  : border,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isActive
                    ? Icons.remove_circle
                    : Icons.remove_circle_outline,
                size: 14,
                color: isActive ? Colors.redAccent : muted,
              ),
              const SizedBox(width: 6),
              Text(
                hasText ? 'Negative Prompt (Active)' : 'Negative Prompt',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                  color: isActive
                      ? (dark ? Colors.white : Colors.redAccent.shade700)
                      : (dark ? Colors.white70 : Colors.black87),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                _showNegativePrompt
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                size: 14,
                color: isActive ? Colors.redAccent : muted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoraPill(bool dark, Color border, Color muted) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => LoraManagerDialog.show(
            context, widget.apiService ?? ApiService()),
        borderRadius: BorderRadius.circular(LuminaColors.pillRadius),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: dark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.white.withValues(alpha: 0.8),
            borderRadius:
                BorderRadius.circular(LuminaColors.pillRadius),
            border: Border.all(color: border, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.style_outlined, size: 14, color: muted),
              const SizedBox(width: 6),
              Text(
                'LoRA',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: dark ? Colors.white70 : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTuneToggle(bool dark, Color border, Color muted) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _showTune = !_showTune),
        borderRadius: BorderRadius.circular(LuminaColors.pillRadius),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: _showTune
                ? LuminaColors.primaryGlow.withValues(alpha: 0.15)
                : (dark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.white.withValues(alpha: 0.8)),
            borderRadius:
                BorderRadius.circular(LuminaColors.pillRadius),
            border: Border.all(
              color: _showTune
                  ? LuminaColors.primaryGlow.withValues(alpha: 0.5)
                  : border,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.tune_outlined,
                size: 14,
                color:
                    _showTune ? LuminaColors.primaryGlow : muted,
              ),
              const SizedBox(width: 6),
              Text(
                _mode == 'Voice Studio' || _isVoiceModel
                    ? (_model.contains('Breeze')
                        ? 'Tune (Guidance ${_cfg.toStringAsFixed(1)})'
                        : 'Tune (${_exaggeration.toStringAsFixed(1)} / ${_cfg.toStringAsFixed(1)})')
                    : 'Tune ($_steps / ${_cfg.toStringAsFixed(1)})',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight:
                      _showTune ? FontWeight.w600 : FontWeight.w500,
                  color: dark ? Colors.white70 : Colors.black87,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                _showTune
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                size: 14,
                color:
                    _showTune ? LuminaColors.primaryGlow : muted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTemplateAttachmentNotice(bool dark, Color border) {
    if (_videoTemplateNotice == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: LuminaColors.primaryStart.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: LuminaColors.primaryEnd.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded,
                size: 16, color: LuminaColors.primaryEnd),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _videoTemplateNotice!,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: dark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
            ),
            InkWell(
              onTap: () => setState(() => _videoTemplateNotice = null),
              child: const Padding(
                padding: EdgeInsets.all(3),
                child: Icon(Icons.close, size: 14, color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReferenceImagePreview(bool dark, Color border, Color muted) {
    if (_referenceBytes == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        decoration: BoxDecoration(
          color: dark
              ? LuminaColors.primaryGlow.withValues(alpha: 0.08)
              : LuminaColors.primaryGlow.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: LuminaColors.primaryGlow.withValues(alpha: 0.35),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                _referenceBytes!,
                width: 44,
                height: 44,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.image_search_rounded,
                        size: 15,
                        color: LuminaColors.primaryGlow,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          _referenceName ?? 'Reference Image',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: LuminaColors.primaryGlow.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Strength: ${(_strength * 100).toInt()}%',
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: LuminaColors.primaryGlow,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        'Keep Subject',
                        style: TextStyle(
                          fontSize: 10,
                          color: muted,
                        ),
                      ),
                      Expanded(
                        child: SizedBox(
                          height: 18,
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 2,
                              thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 5),
                              overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 9),
                              activeTrackColor: LuminaColors.primaryGlow,
                              inactiveTrackColor: dark
                                  ? Colors.white.withValues(alpha: 0.15)
                                  : Colors.black.withValues(alpha: 0.1),
                              thumbColor: LuminaColors.primaryGlow,
                            ),
                            child: Slider(
                              value: _strength,
                              min: 0.20,
                              max: 0.90,
                              divisions: 14,
                              onChanged: (v) => setState(() => _strength = v),
                            ),
                          ),
                        ),
                      ),
                      Text(
                        'New Scene',
                        style: TextStyle(
                          fontSize: 10,
                          color: muted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              color: muted,
              tooltip: 'Remove reference image',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => setState(() {
                _referenceBytes = null;
                _referenceName = null;
                _referenceBase64 = null;
                _strength = 0.65;
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTryOnSlots(bool dark, Color border, Color muted) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        decoration: BoxDecoration(
          color: dark
              ? LuminaColors.violet.withValues(alpha: 0.08)
              : LuminaColors.violet.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: LuminaColors.violet.withValues(alpha: 0.35),
          ),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, size: 14, color: LuminaColors.violet),
                const SizedBox(width: 6),
                const Text(
                  'Virtual Try-On Setup',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: LuminaColors.violet,
                  ),
                ),
                const Spacer(),
                Text(
                  'Both photos required',
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                // Slot 1: Person Photo
                Expanded(
                  child: InkWell(
                    onTap: _pickReferenceImage,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _referenceBytes != null
                            ? LuminaColors.primaryGlow.withValues(alpha: 0.12)
                            : (dark
                                ? Colors.white.withValues(alpha: 0.04)
                                : Colors.black.withValues(alpha: 0.03)),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _referenceBytes != null
                              ? LuminaColors.primaryGlow.withValues(alpha: 0.5)
                              : border,
                        ),
                      ),
                      child: Row(
                        children: [
                          if (_referenceBytes != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.memory(
                                _referenceBytes!,
                                width: 36,
                                height: 36,
                                fit: BoxFit.cover,
                              ),
                            )
                          else
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: LuminaColors.primaryGlow.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(
                                Icons.person_add_alt_1_rounded,
                                size: 18,
                                color: LuminaColors.primaryGlow,
                              ),
                            ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      '1. Person Photo',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: _referenceBytes != null
                                            ? LuminaColors.primaryGlow
                                            : null,
                                      ),
                                    ),
                                    if (_referenceBytes != null) ...[
                                      const SizedBox(width: 4),
                                      const Icon(Icons.check_circle_rounded,
                                          size: 13, color: Colors.greenAccent),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _referenceName ?? 'Attach human photo',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_referenceBytes != null)
                            IconButton(
                              icon: const Icon(Icons.close, size: 14),
                              color: muted,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Remove person photo',
                              onPressed: () => setState(() {
                                _referenceBytes = null;
                                _referenceName = null;
                                _referenceBase64 = null;
                              }),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Slot 2: Garment Photo
                Expanded(
                  child: InkWell(
                    onTap: _pickGarmentImage,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _garmentBytes != null
                            ? LuminaColors.violet.withValues(alpha: 0.12)
                            : (dark
                                ? Colors.white.withValues(alpha: 0.04)
                                : Colors.black.withValues(alpha: 0.03)),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _garmentBytes != null
                              ? LuminaColors.violet.withValues(alpha: 0.5)
                              : border,
                        ),
                      ),
                      child: Row(
                        children: [
                          if (_garmentBytes != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.memory(
                                _garmentBytes!,
                                width: 36,
                                height: 36,
                                fit: BoxFit.cover,
                              ),
                            )
                          else
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: LuminaColors.violet.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(
                                Icons.checkroom_rounded,
                                size: 18,
                                color: LuminaColors.violet,
                              ),
                            ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      '2. Garment Photo',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: _garmentBytes != null
                                            ? LuminaColors.violet
                                            : null,
                                      ),
                                    ),
                                    if (_garmentBytes != null) ...[
                                      const SizedBox(width: 4),
                                      const Icon(Icons.check_circle_rounded,
                                          size: 13, color: Colors.greenAccent),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _garmentName ?? 'Attach Shadda/clothing',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_garmentBytes != null)
                            IconButton(
                              icon: const Icon(Icons.close, size: 14),
                              color: muted,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Remove garment photo',
                              onPressed: () => setState(() {
                                _garmentBytes = null;
                                _garmentName = null;
                                _garmentBase64 = null;
                              }),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGarmentImagePreview(bool dark, Color border, Color muted) {
    if (_garmentBytes == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        decoration: BoxDecoration(
          color: dark
              ? LuminaColors.violet.withValues(alpha: 0.08)
              : LuminaColors.violet.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: LuminaColors.violet.withValues(alpha: 0.4),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                _garmentBytes!,
                width: 44,
                height: 44,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.checkroom_rounded,
                        size: 15,
                        color: LuminaColors.violet,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          _garmentName ?? 'Garment / Clothing',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: LuminaColors.violet.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _tryonCategory.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: LuminaColors.violet,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'FASHN VTON 1.5 • ${_garmentPhotoType == 'model' ? 'Model photo' : 'Flat-lay product'} • Maskless Try-On',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              color: muted,
              tooltip: 'Remove garment',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => setState(() {
                _garmentBytes = null;
                _garmentName = null;
                _garmentBase64 = null;
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReferenceVideoPreview(bool dark, Color border, Color muted) {
    if (_referenceVideoBytes == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        decoration: BoxDecoration(
          color: dark
              ? LuminaColors.primaryGlow.withValues(alpha: 0.08)
              : LuminaColors.primaryGlow.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: LuminaColors.primaryGlow.withValues(alpha: 0.35),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _videoThumbnailBytes != null
                  ? Stack(
                      alignment: Alignment.center,
                      children: [
                        Image.memory(
                          _videoThumbnailBytes!,
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                        ),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ],
                    )
                  : Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: LuminaColors.primaryGlow.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.videocam_rounded,
                        color: LuminaColors.primaryGlow,
                        size: 24,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.animation_rounded,
                        size: 15,
                        color: LuminaColors.primaryGlow,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          _referenceVideoName ?? 'Driving Video Template',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: LuminaColors.primaryGlow.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _referenceBytes != null
                              ? 'Motion Template'
                              : 'Video Input (Motion + Subject)',
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: LuminaColors.primaryGlow,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _referenceBytes != null
                        ? 'Motion will be retargeted onto your character image'
                        : 'Using video as motion guide & subject. (Attach a photo to swap character!)',
                    style: TextStyle(
                      fontSize: 11,
                      color: muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              color: muted,
              tooltip: 'Remove template video',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => setState(() {
                _referenceVideoBytes = null;
                _referenceVideoName = null;
                _referenceVideoBase64 = null;
                _videoThumbnailBytes = null;
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReferenceAudioPreview(bool dark, Color border, Color muted) {
    if (_referenceAudioBytes == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        decoration: BoxDecoration(
          color: dark
              ? LuminaColors.primaryGlow.withValues(alpha: 0.08)
              : LuminaColors.primaryGlow.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: LuminaColors.primaryGlow.withValues(alpha: 0.35),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: LuminaColors.primaryGlow.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.record_voice_over_rounded,
                color: LuminaColors.primaryGlow,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.mic_rounded,
                        size: 14,
                        color: LuminaColors.primaryGlow,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          _referenceAudioName ?? 'Voice Reference Clip',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color:
                              LuminaColors.primaryGlow.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Zero-Shot Voice Cloning',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: LuminaColors.primaryGlow,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Chatterbox will clone this speaker\'s voice characteristics and tone.',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: muted,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 18),
              color: muted,
              tooltip: 'Remove voice clip',
              onPressed: () => setState(() {
                _referenceAudioBytes = null;
                _referenceAudioName = null;
                _referenceAudioBase64 = null;
              }),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pill button opening a styled dropdown menu. Label and icon follow
/// the current selection.
class _SelectorMenu extends StatelessWidget {
  final List<_MenuOption> options;
  final String value;
  final Color muted;
  final Color border;
  final Offset menuOffset;
  final ValueChanged<String> onSelected;

  const _SelectorMenu({
    required this.options,
    required this.value,
    required this.muted,
    required this.border,
    this.menuOffset = Offset.zero,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final dark = LuminaTheme.isDark(context);
    final current = options.firstWhere((o) => o.value == value,
        orElse: () => options.first);

    return PopupMenuButton<String>(
      initialValue: value,
      onSelected: onSelected,
      offset: menuOffset,
      tooltip: 'Choose option',
      color: dark ? LuminaColors.darkCard : LuminaColors.lightCard,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: border),
      ),
      itemBuilder: (context) => [
        for (final o in options)
          PopupMenuItem<String>(
            value: o.value,
            child: Row(
              children: [
                Icon(o.icon, size: 16, color: muted),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(o.value,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                      Text(o.hint,
                          style: TextStyle(
                              fontSize: 11, color: muted)),
                    ],
                  ),
                ),
                if (o.value == value)
                  const Icon(Icons.check,
                      size: 16, color: LuminaColors.primaryGlow),
              ],
            ),
          ),
      ],
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          borderRadius:
              BorderRadius.circular(LuminaColors.pillRadius),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(current.icon, size: 14, color: muted),
            const SizedBox(width: 6),
            Text(current.value,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(width: 4),
            Icon(Icons.expand_more, size: 14, color: muted),
          ],
        ),
      ),
    );
  }
}
