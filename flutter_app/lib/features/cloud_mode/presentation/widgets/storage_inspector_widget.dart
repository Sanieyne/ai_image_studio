import 'package:flutter/material.dart';
import '../../../../theme/app_theme.dart';
import '../../data/models/cloud_model.dart';

class StorageInspectorWidget extends StatelessWidget {
  final RecommendationResult? result;
  final bool isDark;
  final Function(String modelId)? onEvictModel;

  const StorageInspectorWidget({
    super.key,
    required this.result,
    required this.isDark,
    this.onEvictModel,
  });

  @override
  Widget build(BuildContext context) {
    final border = isDark ? LuminaColors.darkBorder : LuminaColors.lightBorder;
    final surface = isDark ? LuminaColors.darkSurface : Colors.white;
    final muted = isDark ? LuminaColors.darkMuted : LuminaColors.lightMuted;

    final req = result?.requirements;
    final plan = result?.recommendedStorage;

    final totalGB = req?.totalWithBufferGB ?? 15.97;
    final planGB = plan?.sizeGB ?? 30.0;
    final usedRatio = (totalGB / planGB).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface.withValues(alpha: isDark ? 0.72 : 0.85),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.storage_rounded, size: 20, color: LuminaColors.purple),
              const SizedBox(width: 8),
              const Text(
                'Cloud Storage Volume',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (plan != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: LuminaColors.purple.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: LuminaColors.purple.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    plan.name,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: LuminaColors.purple,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Storage breakdown bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${totalGB.toStringAsFixed(1)} GB Projected',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              Text(
                '${planGB.toInt()} GB Volume Plan',
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: usedRatio,
              minHeight: 12,
              backgroundColor: isDark ? Colors.white12 : Colors.black12,
              valueColor: AlwaysStoppedAnimation<Color>(
                usedRatio > 0.85 ? Colors.redAccent : LuminaColors.purple,
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Footprint Breakdown Chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildBreakdownChip(
                'Model Weights',
                '${(req?.totalModelSizeGB ?? 6.9).toStringAsFixed(1)} GB',
                LuminaColors.infoBlue,
              ),
              _buildBreakdownChip(
                'Engine & venv',
                '${(req?.baseOverheadGB ?? 7.0).toStringAsFixed(0)} GB',
                Colors.amber,
              ),
              _buildBreakdownChip(
                'Output Buffer (30%)',
                '${(req?.bufferGB ?? 2.07).toStringAsFixed(1)} GB',
                LuminaColors.purple,
              ),
              _buildBreakdownChip(
                'Free Space',
                '${(plan?.freeAfterGB ?? 14.03).toStringAsFixed(1)} GB',
                Colors.greenAccent.shade700,
              ),
            ],
          ),

          if (result?.warnings.isNotEmpty ?? false) ...[
            const SizedBox(height: 16),
            ...result!.warnings.map(
              (w) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.amber),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        w,
                        style: const TextStyle(fontSize: 11.5, color: Colors.amber),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),
          const Text(
            'Cached Models in Volume',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          // List of models in current selection with eviction button
          Expanded(
            child: ListView.separated(
              itemCount: result?.selectedModels.length ?? 0,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, idx) {
                final modelMap = result!.selectedModels[idx];
                final modelId = modelMap['modelId']?.toString() ?? '';
                final name = modelMap['displayName']?.toString() ?? modelId;
                final sizeGB = (modelMap['sizeGB'] as num?)?.toDouble() ?? 0.0;

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.folder_open_rounded, size: 16, color: LuminaColors.purple),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${sizeGB.toStringAsFixed(1)} GB',
                        style: TextStyle(fontSize: 11, color: muted),
                      ),
                      if (onEvictModel != null && (result?.selectedModels.length ?? 0) > 1) ...[
                        const SizedBox(width: 6),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Colors.redAccent),
                          tooltip: 'Evict model from volume cache',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => onEvictModel!(modelId),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBreakdownChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
          const SizedBox(width: 4),
          Text(value, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}
