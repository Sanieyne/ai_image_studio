import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'lora_manager.dart';

typedef PromptGenerateCallback = void Function(
  String prompt,
  String negativePrompt,
  String ratio,
  String model,
  String? imageBase64,
  double strength,
  Uint8List? referenceBytes,
  int steps,
  double cfgScale,
);

/// Floating frosted prompt bar: dropdown selector pills on top, pill
/// text field with upload/camera actions and a Generate button below.
class PromptInputBar extends StatefulWidget {
  final PromptGenerateCallback? onGenerate;
  final ApiService? apiService;

  const PromptInputBar({super.key, this.onGenerate, this.apiService});

  /// Display label -> HF repo id. Single source of truth for home_screen too.
  static const modelIds = {
    'RealVisXL V4.0': 'SG161222/RealVisXL_V4.0',
    'Juggernaut XL v9': 'RunDiffusion/Juggernaut-XL-v9',
    'DreamShaper XL': 'Lykon/dreamshaper-xl-1-0',
    'SDXL Base 1.0': 'stabilityai/stable-diffusion-xl-base-1.0',
    'FLUX.1-schnell': 'black-forest-labs/FLUX.1-schnell',
    'FLUX.1-dev': 'black-forest-labs/FLUX.1-dev',
  };

  @override
  State<PromptInputBar> createState() => _PromptInputBarState();
}

class _MenuOption {
  final String value;
  final String hint;
  final IconData icon;
  const _MenuOption(this.value, this.hint, this.icon);
}

class _PromptInputBarState extends State<PromptInputBar> {
  final _controller = TextEditingController();
  final _negController = TextEditingController();
  bool _showNegativePrompt = false;

  Uint8List? _referenceBytes;
  String? _referenceName;
  String? _referenceBase64;
  double _strength = 0.65;
  bool _showTune = false;
  int _steps = 30;
  double _cfg = 7.0;

  static const _ratios = [
    _MenuOption('16:9', 'Landscape', Icons.crop_landscape),
    _MenuOption('9:16', 'Portrait', Icons.crop_portrait),
    _MenuOption('1:1', 'Square', Icons.crop_square),
    _MenuOption('4:5', 'Social', Icons.crop_5_4),
  ];
  static const _models = [
    _MenuOption('RealVisXL V4.0', 'Photoreal', Icons.bolt_rounded),
    _MenuOption('Juggernaut XL v9', 'Detailed', Icons.auto_awesome),
    _MenuOption('DreamShaper XL', 'Creative', Icons.brush_outlined),
    _MenuOption('SDXL Base 1.0', 'Neutral base', Icons.science_outlined),
    _MenuOption('FLUX.1-schnell', 'Fast 4-step', Icons.flash_on),
    _MenuOption('FLUX.1-dev', 'Quality', Icons.hd),
    _MenuOption('Offline Mock Mode', 'Test Only', Icons.laptop_chromebook),
  ];

  static const _modes = [
    _MenuOption('Image Mode', 'Single frame', Icons.image_outlined),
    _MenuOption('Video Mode', 'Multi frame', Icons.videocam_outlined),
    _MenuOption('Motion Animate', 'Animate stills', Icons.animation),
  ];

  String _ratio = '9:16';
  String _model = 'RealVisXL V4.0';
  String _mode = 'Image Mode';

  @override
  void dispose() {
    _controller.dispose();
    _negController.dispose();
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

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final neg = _negController.text.trim();
    widget.onGenerate?.call(
      text,
      neg,
      _ratio,
      _model,
      _referenceBase64,
      _strength,
      _referenceBytes,
      _steps,
      _cfg,
    );
    setState(() {
      _controller.clear();
      _negController.clear();
      _showNegativePrompt = false;
      _referenceBytes = null;
      _referenceName = null;
      _referenceBase64 = null;
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
            child: Column(
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
                      // 5 options: spawn above the pill.
                      menuOffset: const Offset(0, -370),
                      onSelected: (v) => setState(() {
                        _model = v;
                        // Family defaults so FLUX isn't run with SDXL numbers.
                        if (v == 'FLUX.1-schnell') {
                          _steps = 4;
                          _cfg = 0.0;
                        } else if (v == 'FLUX.1-dev') {
                          _steps = 28;
                          _cfg = 3.5;
                        } else {
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
                      // 3 options: spawn above the pill.
                      menuOffset: const Offset(0, -150),
                      onSelected: (v) =>
                          setState(() => _mode = v),
                    ),
                    _buildNegativePromptToggle(dark, border, muted),
                    _buildTuneToggle(dark, border, muted),
                    _buildLoraPill(dark, border, muted),
                  ],
                ),
                // Optional expandable tune sliders (steps / CFG).
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
                          if (_model == 'FLUX.1-schnell')
                            const Padding(
                              padding: EdgeInsets.only(bottom: 4),
                              child: Text(
                                'Schnell is distilled: CFG is ignored, 4 steps is enough.',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontStyle: FontStyle.italic),
                              ),
                            ),
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
                _buildReferenceImagePreview(dark, border, muted),
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
                          hintText:
                              'Describe your image or video prompt, style, lighting, camera angle...',
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
                          ? 'Change reference photo'
                          : 'Attach reference photo (Img2Img)',
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
                        child: const Text('Generate ⚡',
                            style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.white)),
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
                'Tune ($_steps / ${_cfg.toStringAsFixed(1)})',
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
                          'Denoising: ${(_strength * 100).toInt()}%',
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
