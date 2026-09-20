import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/video_template.dart';
import 'silent_video_preview_player.dart';

/// Wide responsive multi-column/row Video Template Gallery for the main content area
class VideoTemplateGallery extends StatefulWidget {
  final ValueChanged<VideoTemplate> onSelectTemplate;
  final ValueChanged<VideoTemplate>? onGenerateDirect;
  final ValueChanged<VideoTemplate>? onStartProjectWithTemplate;
  final VoidCallback? onNewVideoProject;
  final VoidCallback? onBackToGenerations;
  final VoidCallback? onDismiss;
  final int generationsCount;
  final bool isDark;

  const VideoTemplateGallery({
    super.key,
    required this.onSelectTemplate,
    this.onGenerateDirect,
    this.onStartProjectWithTemplate,
    this.onNewVideoProject,
    this.onBackToGenerations,
    this.onDismiss,
    this.generationsCount = 0,
    this.isDark = true,
  });

  @override
  State<VideoTemplateGallery> createState() => _VideoTemplateGalleryState();
}

class _VideoTemplateGalleryState extends State<VideoTemplateGallery> {
  String _selectedCategory = 'All';
  String _searchQuery = '';
  final _searchController = TextEditingController();

  final List<String> _categories = [
    'All',
    'Cinematic Drone',
    'Commercial 360',
    'Anime & VFX',
    'Fashion & Character',
    'Nature & Wildlife',
    'Visual FX / Macro',
    'Action & Vehicle',
    'Tech & Sci-Fi',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<VideoTemplate> get _filteredTemplates {
    return VideoTemplate.curatedTemplates.where((t) {
      final matchesCategory =
          _selectedCategory == 'All' || t.category == _selectedCategory;
      if (!matchesCategory) return false;
      if (_searchQuery.isEmpty) return true;
      final query = _searchQuery.toLowerCase();
      final inTitle = t.title.toLowerCase().contains(query);
      final inPrompt = t.prompt.toLowerCase().contains(query);
      final inCamera = t.cameraMotion.toLowerCase().contains(query);
      final inTags = t.tags.any((tag) => tag.toLowerCase().contains(query));
      return inTitle || inPrompt || inCamera || inTags;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.isDark;
    final bgColor = dark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final cardBg = dark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor =
        dark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final textColor = dark ? Colors.white : const Color(0xFF0F172A);
    final mutedColor =
        dark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Container(
      color: bgColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // TOP HEADER & ACTION BAR
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
                        gradient: const LinearGradient(
                          colors: [Color(0xFF2563EB), Color(0xFF0284C7)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF2563EB)
                                .withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.movie_filter_rounded,
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
                                'Video Templates Studio',
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
                                  color: const Color(0xFF2563EB)
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: const Color(0xFF2563EB)
                                          .withValues(alpha: 0.3)),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check_circle_rounded,
                                        size: 12, color: Color(0xFF38BDF8)),
                                    SizedBox(width: 4),
                                    Text(
                                      'PRODUCTION READY',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF38BDF8),
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
                            'Explore multi-frame cinematic motion prompts with muted silent previews and camera choreography in wide grid format.',
                            style: TextStyle(fontSize: 12, color: mutedColor),
                          ),
                        ],
                      ),
                    ),

                    // Actions
                    Row(
                      children: [
                        if (widget.onDismiss != null) ...[
                          OutlinedButton.icon(
                            onPressed: widget.onDismiss,
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: borderColor),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(9)),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 12),
                            ),
                            icon: const Icon(Icons.edit_note_rounded, size: 16),
                            label: Text(
                              'Blank Canvas',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: textColor),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
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
                            icon: const Icon(Icons.art_track_rounded, size: 16),
                            label: Text(
                              'Creations Feed (${widget.generationsCount})',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: textColor),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],

                        // New Video Project Button
                        Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                            ),
                            borderRadius: BorderRadius.circular(9),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF2563EB)
                                    .withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: FilledButton.icon(
                            onPressed: widget.onNewVideoProject,
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
                              '+ New Video Project',
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
                        onChanged: (v) => setState(() => _searchQuery = v.trim()),
                        style: TextStyle(fontSize: 13, color: textColor),
                        decoration: InputDecoration(
                          hintText:
                              'Search templates by camera motion, style, or keywords...',
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
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: borderColor),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: borderColor),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                const BorderSide(color: Color(0xFF2563EB)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Category Chips Bar
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _categories.map((cat) {
                      final isSelected = _selectedCategory == cat;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(cat),
                          selected: isSelected,
                          onSelected: (_) {
                            setState(() => _selectedCategory = cat);
                          },
                          labelStyle: TextStyle(
                            fontSize: 11,
                            fontWeight:
                                isSelected ? FontWeight.bold : FontWeight.w500,
                            color: isSelected
                                ? Colors.white
                                : (dark ? Colors.white70 : Colors.black87),
                          ),
                          selectedColor: const Color(0xFF2563EB),
                          backgroundColor: dark
                              ? Colors.white.withValues(alpha: 0.05)
                              : Colors.grey.shade200,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(7),
                            side: BorderSide(
                              color: isSelected
                                  ? const Color(0xFF2563EB)
                                  : borderColor,
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          visualDensity: VisualDensity.compact,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),

          // TEMPLATES GRID: ROWS AND COLUMNS USING LAYOUTBUILDER
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final int crossAxisCount;
                if (width >= 1350) {
                  crossAxisCount = 3;
                } else if (width >= 820) {
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
                    mainAxisExtent: 510,
                  ),
                  itemCount: templates.length,
                  itemBuilder: (context, index) {
                    final t = templates[index];
                    return _WideVideoTemplateCard(
                      template: t,
                      isDark: dark,
                      cardBg: cardBg,
                      borderColor: borderColor,
                      textColor: textColor,
                      mutedColor: mutedColor,
                      onUseTemplate: () => widget.onSelectTemplate(t),
                      onGenerateDirect: widget.onGenerateDirect != null
                          ? () => widget.onGenerateDirect!(t)
                          : null,
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

/// A rich multi-column card showing silent video preview with title inside,
/// motion tags, detailed prompt snippet, and action buttons.
class _WideVideoTemplateCard extends StatelessWidget {
  final VideoTemplate template;
  final bool isDark;
  final Color cardBg;
  final Color borderColor;
  final Color textColor;
  final Color mutedColor;
  final VoidCallback onUseTemplate;
  final VoidCallback? onGenerateDirect;
  final VoidCallback? onStartNewProject;

  const _WideVideoTemplateCard({
    required this.template,
    required this.isDark,
    required this.cardBg,
    required this.borderColor,
    required this.textColor,
    required this.mutedColor,
    required this.onUseTemplate,
    this.onGenerateDirect,
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
          // 1. Silent Video Preview Player (with title inside viewport, REC timecode, NO SOUND badge)
          SilentVideoPreviewPlayer(
            template: t,
            aspectRatio: 16 / 9,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(11)),
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
                          color: const Color(0xFF2563EB)
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                              color: const Color(0xFF2563EB)
                                  .withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.bolt_rounded,
                                size: 12, color: Color(0xFF38BDF8)),
                            const SizedBox(width: 3),
                            Text(
                              t.model,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF38BDF8),
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
                                      content: Text('Prompt copied to clipboard!'),
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
                      // "Use Template" / "Load to Prompt"
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onUseTemplate,
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: const Color(0xFF2563EB)
                                  .withValues(alpha: 0.45),
                            ),
                            backgroundColor: const Color(0xFF2563EB)
                                .withValues(alpha: 0.08),
                            padding: const EdgeInsets.symmetric(
                                vertical: 9, horizontal: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          icon: const Icon(Icons.tune_rounded,
                              size: 14, color: Color(0xFF38BDF8)),
                          label: const Text(
                            'Use Template',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF38BDF8),
                            ),
                          ),
                        ),
                      ),
                      if (onGenerateDirect != null) ...[
                        const SizedBox(width: 8),
                        // "Generate"
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF2563EB), Color(0xFF0284C7)],
                              ),
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF2563EB)
                                      .withValues(alpha: 0.3),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: FilledButton.icon(
                              onPressed: onGenerateDirect,
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 9, horizontal: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              icon: const Icon(Icons.bolt_rounded,
                                  size: 15, color: Colors.white),
                              label: const Text(
                                'Generate',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
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
}
