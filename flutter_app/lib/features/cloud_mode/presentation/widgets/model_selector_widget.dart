import 'package:flutter/material.dart';
import '../../../../theme/app_theme.dart';
import '../../data/models/cloud_model.dart';

class ModelSelectorWidget extends StatefulWidget {
  final List<CloudModel> models;
  final Set<String> selectedModelIds;
  final ValueChanged<Set<String>> onSelectionChanged;
  final bool isDark;

  const ModelSelectorWidget({
    super.key,
    required this.models,
    required this.selectedModelIds,
    required this.onSelectionChanged,
    required this.isDark,
  });

  @override
  State<ModelSelectorWidget> createState() => _ModelSelectorWidgetState();
}

class _ModelSelectorWidgetState extends State<ModelSelectorWidget> {
  String _activeFilter = 'all';
  String _searchQuery = '';

  static const List<String> _filters = [
    'all',
    'image',
    'video',
    'motion',
    'voice',
    'vton',
    'enhancer',
  ];

  @override
  Widget build(BuildContext context) {
    final border = widget.isDark ? LuminaColors.darkBorder : LuminaColors.lightBorder;
    final surface = widget.isDark ? LuminaColors.darkSurface : Colors.white;
    final muted = widget.isDark ? LuminaColors.darkMuted : LuminaColors.lightMuted;

    final filtered = widget.models.where((m) {
      if (_activeFilter != 'all' && m.mode.toLowerCase() != _activeFilter) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        return m.displayName.toLowerCase().contains(query) ||
            m.modelId.toLowerCase().contains(query);
      }
      return true;
    }).toList();

    return Container(
      decoration: BoxDecoration(
        color: surface.withValues(alpha: widget.isDark ? 0.72 : 0.85),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with search & counters
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.hub_rounded, size: 20, color: LuminaColors.infoBlue),
                    const SizedBox(width: 8),
                    const Text(
                      'AI Model Catalog',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: LuminaColors.primaryEnd.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: LuminaColors.primaryEnd.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        '${widget.selectedModelIds.length} Selected',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: LuminaColors.primaryEnd,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Search bar
                TextField(
                  onChanged: (val) => setState(() => _searchQuery = val),
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Search models (FLUX, Qwen, Wan, SDXL)...',
                    hintStyle: TextStyle(fontSize: 13, color: muted),
                    prefixIcon: Icon(Icons.search, size: 18, color: muted),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    filled: true,
                    fillColor: (widget.isDark ? Colors.black : Colors.white).withValues(alpha: 0.25),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: border),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Filter pills
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _filters.map((filter) {
                      final active = _activeFilter == filter;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: InkWell(
                          onTap: () => setState(() => _activeFilter = filter),
                          borderRadius: BorderRadius.circular(10),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: active
                                  ? LuminaColors.primaryEnd
                                  : (widget.isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              filter.toUpperCase(),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: active ? FontWeight.bold : FontWeight.w500,
                                color: active ? Colors.white : muted,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: border),
          // Models list
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text('No models match your search.', style: TextStyle(color: muted)),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final model = filtered[index];
                      final isSelected = widget.selectedModelIds.contains(model.modelId);

                      return InkWell(
                        onTap: () {
                          final next = Set<String>.from(widget.selectedModelIds);
                          if (isSelected) {
                            if (next.length > 1) {
                              next.remove(model.modelId);
                              widget.onSelectionChanged(next);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('At least one model must remain selected.')),
                              );
                            }
                          } else {
                            next.add(model.modelId);
                            widget.onSelectionChanged(next);
                          }
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? LuminaColors.infoBlue : border,
                              width: isSelected ? 1.5 : 1.0,
                            ),
                            color: isSelected
                                ? LuminaColors.infoBlue.withValues(alpha: widget.isDark ? 0.12 : 0.06)
                                : Colors.transparent,
                          ),
                          child: Row(
                            children: [
                              Checkbox(
                                value: isSelected,
                                activeColor: LuminaColors.infoBlue,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                onChanged: (val) {
                                  final next = Set<String>.from(widget.selectedModelIds);
                                  if (val == true) {
                                    next.add(model.modelId);
                                  } else {
                                    if (next.length > 1) {
                                      next.remove(model.modelId);
                                    }
                                  }
                                  widget.onSelectionChanged(next);
                                },
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          model.displayName,
                                          style: const TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        _buildModeBadge(model.mode),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      model.hfRepoId,
                                      style: TextStyle(fontSize: 11, color: muted),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: model.requiredVramGB >= 24
                                          ? LuminaColors.purple.withValues(alpha: 0.15)
                                          : LuminaColors.infoBlue.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '${model.requiredVramGB.toInt()} GB VRAM',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: model.requiredVramGB >= 24
                                            ? LuminaColors.purple
                                            : LuminaColors.infoBlue,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${model.sizeGB} GB Disk',
                                    style: TextStyle(fontSize: 11, color: muted),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeBadge(String mode) {
    Color color = Colors.grey;
    switch (mode.toLowerCase()) {
      case 'image':
        color = Colors.cyan;
        break;
      case 'video':
        color = Colors.indigoAccent;
        break;
      case 'motion':
        color = Colors.purpleAccent;
        break;
      case 'voice':
        color = Colors.orangeAccent;
        break;
      case 'vton':
        color = Colors.pinkAccent;
        break;
      case 'enhancer':
        color = Colors.green;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        mode.toUpperCase(),
        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}
