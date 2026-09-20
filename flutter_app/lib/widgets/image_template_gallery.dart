import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/image_template.dart';
import '../theme/app_theme.dart';

/// Wide responsive multi-column/row Image Template Gallery for the main content area
class ImageTemplateGallery extends StatefulWidget {
  final ValueChanged<ImageTemplate> onSelectTemplate;
  final ValueChanged<ImageTemplate>? onStartProjectWithTemplate;
  final VoidCallback? onNewImageProject;
  final VoidCallback? onBackToGenerations;
  final VoidCallback? onDismiss;
  final int generationsCount;
  final bool isDark;

  const ImageTemplateGallery({
    super.key,
    required this.onSelectTemplate,
    this.onStartProjectWithTemplate,
    this.onNewImageProject,
    this.onBackToGenerations,
    this.onDismiss,
    this.generationsCount = 0,
    this.isDark = true,
  });

  @override
  State<ImageTemplateGallery> createState() => _ImageTemplateGalleryState();
}

class _ImageTemplateGalleryState extends State<ImageTemplateGallery> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedCategory = 'All';

  static const List<String> _categories = [
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

  List<ImageTemplate> get _filteredTemplates {
    return ImageTemplate.curatedTemplates.where((t) {
      if (_selectedCategory != 'All' && t.category != _selectedCategory) {
        return false;
      }
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      final titleMatch = t.title.toLowerCase().contains(q);
      final promptMatch = t.prompt.toLowerCase().contains(q);
      final descMatch = t.description.toLowerCase().contains(q);
      final tagMatch = t.tags.any((tag) => tag.toLowerCase().contains(q));
      final modelMatch = t.model.toLowerCase().contains(q);
      return titleMatch || promptMatch || descMatch || tagMatch || modelMatch;
    }).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.isDark;
    final bg = dark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final cardBg = dark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor =
        dark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade200;
    final textColor = dark ? Colors.white : const Color(0xFF0F172A);
    final mutedColor = dark ? Colors.white60 : Colors.black54;

    return Container(
      color: bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── HERO HEADER BAR ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
            decoration: BoxDecoration(
              color: cardBg,
              border: Border(bottom: BorderSide(color: borderColor)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Icon Badge
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: LuminaColors.primaryGradient,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: LuminaColors.primaryGlow
                                .withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.auto_awesome_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),

                    // Titles
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Image Templates Studio',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: LuminaColors.primaryStart
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: LuminaColors.primaryStart
                                          .withValues(alpha: 0.35)),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check_circle_rounded,
                                        size: 12,
                                        color: LuminaColors.primaryEnd),
                                    SizedBox(width: 4),
                                    Text(
                                      'PRODUCTION READY',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.bold,
                                        color: LuminaColors.primaryEnd,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Explore curated high-fidelity prompts across FLUX.1, Z-Image Turbo, SDXL, and Virtual Try-On.',
                            style: TextStyle(fontSize: 12, color: mutedColor),
                          ),
                        ],
                      ),
                    ),

                    // Action Controls
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.generationsCount > 0 &&
                            widget.onBackToGenerations != null) ...[
                          OutlinedButton.icon(
                            onPressed: widget.onBackToGenerations,
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: borderColor),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(9)),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                            ),
                            icon: Icon(Icons.history_rounded,
                                size: 16, color: textColor),
                            label: Text(
                              'Back to Creations (${widget.generationsCount})',
                              style: TextStyle(
                                fontSize: 12,
                                color: textColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        // New Image Project Button
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(9),
                            gradient: LuminaColors.primaryGradient,
                            boxShadow: [
                              BoxShadow(
                                color: LuminaColors.primaryGlow
                                    .withValues(alpha: 0.30),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: FilledButton.icon(
                            onPressed: widget.onNewImageProject,
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(9)),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                            ),
                            icon: const Icon(Icons.add_rounded,
                                size: 18, color: Colors.white),
                            label: const Text(
                              '+ New Image Project',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // SEARCH BAR & CATEGORY FILTER ROW
                Row(
                  children: [
                    // Search Field
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _searchController,
                        onChanged: (v) =>
                            setState(() => _searchQuery = v.trim()),
                        style: TextStyle(fontSize: 13, color: textColor),
                        decoration: InputDecoration(
                          hintText:
                              'Search templates by style, subject, lighting, or keywords...',
                          hintStyle:
                              TextStyle(fontSize: 12.5, color: mutedColor),
                          prefixIcon: Icon(Icons.search_rounded,
                              size: 18, color: mutedColor),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.close_rounded,
                                      size: 16),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: dark
                              ? Colors.black.withValues(alpha: 0.25)
                              : Colors.grey.shade100,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(9),
                            borderSide: BorderSide(color: borderColor),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(9),
                            borderSide: BorderSide(color: borderColor),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(9),
                            borderSide: const BorderSide(
                                color: LuminaColors.primaryStart, width: 1.5),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),

                    // Category Filter Pills
                    Expanded(
                      flex: 4,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _categories.map((cat) {
                            final isSel = _selectedCategory == cat;
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                label: Text(cat),
                                selected: isSel,
                                onSelected: (sel) {
                                  if (sel) {
                                    setState(() => _selectedCategory = cat);
                                  }
                                },
                                labelStyle: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isSel
                                      ? Colors.white
                                      : (dark ? Colors.white70 : Colors.black87),
                                ),
                                selectedColor: LuminaColors.primaryStart,
                                backgroundColor: dark
                                    ? Colors.black.withValues(alpha: 0.25)
                                    : Colors.grey.shade100,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: BorderSide(
                                    color: isSel
                                        ? LuminaColors.primaryStart
                                        : borderColor,
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── GRID OF TEMPLATES ─────────────────────────────────────────
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                int crossAxisCount = 3;
                if (width > 1400) {
                  crossAxisCount = 4;
                } else if (width > 1050) {
                  crossAxisCount = 3;
                } else if (width > 680) {
                  crossAxisCount = 2;
                } else {
                  crossAxisCount = 1;
                }

                final templates = _filteredTemplates;
                if (templates.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_off_rounded,
                            size: 48, color: mutedColor.withValues(alpha: 0.5)),
                        const SizedBox(height: 12),
                        Text(
                          'No templates match "$_searchQuery"',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: textColor),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Try clearing search or selecting "All" categories',
                          style: TextStyle(fontSize: 12, color: mutedColor),
                        ),
                      ],
                    ),
                  );
                }

                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 140),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 18,
                    mainAxisSpacing: 18,
                    mainAxisExtent: 530,
                  ),
                  itemCount: templates.length,
                  itemBuilder: (context, index) {
                    final t = templates[index];
                    return _WideImageTemplateCard(
                      template: t,
                      isDark: dark,
                      cardBg: cardBg,
                      borderColor: borderColor,
                      textColor: textColor,
                      mutedColor: mutedColor,
                      onUseTemplate: () => widget.onSelectTemplate(t),
                      onStartNewProject: widget.onStartProjectWithTemplate != null
                          ? () => widget.onStartProjectWithTemplate!(t)
                          : null,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// A rich multi-column card showing visual artwork preview banner,
/// model specs, detailed prompt snippet, and action buttons.
class _WideImageTemplateCard extends StatelessWidget {
  final ImageTemplate template;
  final bool isDark;
  final Color cardBg;
  final Color borderColor;
  final Color textColor;
  final Color mutedColor;
  final VoidCallback onUseTemplate;
  final VoidCallback? onStartNewProject;

  const _WideImageTemplateCard({
    required this.template,
    required this.isDark,
    required this.cardBg,
    required this.borderColor,
    required this.textColor,
    required this.mutedColor,
    required this.onUseTemplate,
    this.onStartNewProject,
  });

  @override
  Widget build(BuildContext context) {
    final t = template;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Image Visual Artwork Banner with title overlay
          GestureDetector(
            onTap: onUseTemplate,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: _buildArtworkHeader(context),
            ),
          ),

          // 2. Card Body
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Meta Specs Row (Model, Ratio, Steps, CFG)
                  Row(
                    children: [
                      // Model Chip
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: LuminaColors.primaryStart
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                              color: LuminaColors.primaryStart
                                  .withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.bolt_rounded,
                                size: 12, color: LuminaColors.primaryEnd),
                            const SizedBox(width: 3),
                            Text(
                              t.model,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: LuminaColors.primaryEnd,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),

                      // Ratio Chip
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          t.aspectRatio,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                      ),
                      const Spacer(),

                      // Steps & CFG
                      Text(
                        '${t.steps} steps • CFG ${t.cfgScale}',
                        style: TextStyle(
                          fontSize: 10,
                          color: mutedColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Description
                  Text(
                    t.description,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: mutedColor,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),

                  // Attachment Requirement Indicator
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4.5),
                    decoration: BoxDecoration(
                      color: t.requiresImageAttachment
                          ? const Color(0xFFF59E0B).withValues(alpha: 0.12)
                          : const Color(0xFF10B981).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: t.requiresImageAttachment
                            ? const Color(0xFFF59E0B).withValues(alpha: 0.35)
                            : const Color(0xFF10B981).withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          t.requiresImageAttachment
                              ? Icons.checkroom_outlined
                              : Icons.check_circle_outline_rounded,
                          size: 13,
                          color: t.requiresImageAttachment
                              ? const Color(0xFFF59E0B)
                              : const Color(0xFF10B981),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            t.attachmentBadgeLabel,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: t.requiresImageAttachment
                                  ? const Color(0xFFF59E0B)
                                  : const Color(0xFF10B981),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Prompt Preview Box
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.black.withValues(alpha: 0.3)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.grey.shade300,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.edit_note_rounded,
                                  size: 13, color: mutedColor),
                              const SizedBox(width: 4),
                              Text(
                                'PROMPT PREVIEW',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: mutedColor,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const Spacer(),
                              InkWell(
                                onTap: () {
                                  Clipboard.setData(
                                      ClipboardData(text: t.prompt));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content:
                                          Text('Prompt copied to clipboard!'),
                                      duration: Duration(seconds: 1),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 1),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.copy_rounded,
                                          size: 11, color: mutedColor),
                                      const SizedBox(width: 3),
                                      Text(
                                        'Copy',
                                        style: TextStyle(
                                            fontSize: 9.5, color: mutedColor),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Expanded(
                            child: Text(
                              t.prompt,
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.85)
                                    : const Color(0xFF334155),
                                height: 1.35,
                              ),
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Style Tags Row
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: t.tags.take(3).map((tag) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.04)
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.grey.shade300,
                          ),
                        ),
                        child: Text(
                          '#$tag',
                          style: TextStyle(
                            fontSize: 9,
                            color: mutedColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),

                  // Action Buttons Row
                  Row(
                    children: [
                      // "Use Template" Primary Button
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LuminaColors.primaryGradient,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: LuminaColors.primaryGlow
                                    .withValues(alpha: 0.35),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: FilledButton.icon(
                            onPressed: onUseTemplate,
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(
                                  vertical: 10, horizontal: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            icon: const Icon(Icons.tune_rounded,
                                size: 15, color: Colors.white),
                            label: const Text(
                              'Use Template',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (onStartNewProject != null) ...[
                        const SizedBox(width: 6),
                        Tooltip(
                          message: 'Start fresh project with this template',
                          child: OutlinedButton(
                            onPressed: onStartNewProject,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 9),
                              side: BorderSide(color: borderColor),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: Icon(Icons.create_new_folder_outlined,
                                size: 15, color: textColor),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArtworkHeader(BuildContext context) {
    final t = template;
    final colors = t.gradientColors.isNotEmpty
        ? t.gradientColors
        : [const Color(0xFF1E293B), const Color(0xFF0F172A)];

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
        child: Stack(
          children: [
            // Background Artwork Gradient
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: colors,
                  ),
                ),
              ),
            ),

            // Subtle Grid & Lighting Highlights
            Positioned.fill(
              child: CustomPaint(
                painter: _ArtworkGridPainter(),
              ),
            ),

            // Vignette Gradient
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Color(0x88000000),
                      Color(0xCC000000),
                    ],
                    stops: [0.3, 0.7, 1.0],
                  ),
                ),
              ),
            ),

            // Top Badges
            Positioned(
              top: 10,
              left: 10,
              right: 10,
              child: Row(
                children: [
                  // Category Tag
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Text(
                      t.category.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Quality Badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: LuminaColors.primaryStart.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.photo_filter_rounded,
                            size: 11, color: Colors.white),
                        SizedBox(width: 4),
                        Text(
                          '8K PHOTO',
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

            // Center Floating Icon
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.40),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  size: 24,
                  color: Colors.white,
                ),
              ),
            ),

            // Bottom Title & Model inside Viewport
            Positioned(
              left: 12,
              right: 12,
              bottom: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    t.title,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          color: Colors.black87,
                          blurRadius: 6,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        t.model,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: Colors.white70,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        '•',
                        style: TextStyle(fontSize: 10, color: Colors.white38),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${t.aspectRatio} Ratio',
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: Colors.white70,
                          fontWeight: FontWeight.w500,
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
    );
  }
}

class _ArtworkGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 0.5;

    const step = 24.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
