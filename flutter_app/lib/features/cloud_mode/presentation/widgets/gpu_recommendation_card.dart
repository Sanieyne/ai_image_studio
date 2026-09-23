import 'package:flutter/material.dart';
import '../../../../theme/app_theme.dart';
import '../../data/models/cloud_model.dart';

class GpuRecommendationCard extends StatelessWidget {
  final RecommendationResult? result;
  final bool isDark;
  final VoidCallback onLaunchInstance;

  const GpuRecommendationCard({
    super.key,
    required this.result,
    required this.isDark,
    required this.onLaunchInstance,
  });

  @override
  Widget build(BuildContext context) {
    final border = isDark ? LuminaColors.darkBorder : LuminaColors.lightBorder;
    final surface = isDark ? LuminaColors.darkSurface : Colors.white;
    final muted = isDark ? LuminaColors.darkMuted : LuminaColors.lightMuted;

    final primaryGpu = result?.compatibleGPUs.firstOrNull;
    final maxVram = result?.requirements.maxVramGB ?? 12.0;

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
              const Icon(Icons.speed_rounded, size: 20, color: LuminaColors.amber),
              const SizedBox(width: 8),
              const Text(
                'Recommended Hardware',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (primaryGpu != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _fitColor(primaryGpu.fit).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _fitColor(primaryGpu.fit)),
                  ),
                  child: Text(
                    primaryGpu.fit.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _fitColor(primaryGpu.fit),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Primary Recommendation Hero Box
          if (primaryGpu != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  colors: [
                    LuminaColors.infoBlue.withValues(alpha: isDark ? 0.2 : 0.1),
                    LuminaColors.primaryEnd.withValues(alpha: isDark ? 0.15 : 0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: LuminaColors.infoBlue.withValues(alpha: 0.5),
                  width: 1.5,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        primaryGpu.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                      ),
                      Text(
                        '\$${primaryGpu.pricePerHour.toStringAsFixed(2)} / hr',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: LuminaColors.amber,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    primaryGpu.reason ?? 'Best balance of VRAM headroom and cost efficiency.',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                  const SizedBox(height: 14),

                  // VRAM Usage Progress Meter
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('VRAM Required: ${maxVram.toStringAsFixed(0)} GB',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      Text(
                        '${primaryGpu.vramGB.toStringAsFixed(0)} GB Total (+${primaryGpu.headroomVramGB.toStringAsFixed(0)} GB Headroom)',
                        style: const TextStyle(fontSize: 12, color: LuminaColors.infoBlue, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: (maxVram / primaryGpu.vramGB).clamp(0.0, 1.0),
                      minHeight: 8,
                      backgroundColor: isDark ? Colors.white12 : Colors.black12,
                      valueColor: AlwaysStoppedAnimation<Color>(_fitColor(primaryGpu.fit)),
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.red.withValues(alpha: 0.1),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
              ),
              child: const Text('No single GPU tier satisfies selected models. Consider multi-GPU or reducing selection.'),
            ),

          const SizedBox(height: 16),
          const Text(
            'All Compatible GPU Options',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          // Compatible GPU Tiers List
          Expanded(
            child: ListView.separated(
              itemCount: result?.compatibleGPUs.length ?? 0,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, idx) {
                final gpu = result!.compatibleGPUs[idx];
                final isBest = idx == 0;

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: isBest ? LuminaColors.infoBlue.withValues(alpha: 0.4) : border),
                    color: isBest
                        ? LuminaColors.infoBlue.withValues(alpha: isDark ? 0.08 : 0.03)
                        : Colors.transparent,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isBest ? Icons.star_rounded : Icons.check_circle_outline_rounded,
                        size: 16,
                        color: isBest ? LuminaColors.amber : LuminaColors.infoBlue,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        gpu.name,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '(${gpu.vramGB.toInt()}GB VRAM / ${gpu.ramGB.toInt()}GB RAM)',
                        style: TextStyle(fontSize: 11, color: muted),
                      ),
                      const Spacer(),
                      Text(
                        '\$${gpu.pricePerHour.toStringAsFixed(2)}/hr',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 12),
          // Launch Instance Button
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: onLaunchInstance,
              icon: const Icon(Icons.rocket_launch_rounded, size: 18),
              label: Text(
                'Rent & Launch ${primaryGpu?.name ?? 'GPU'} (~${((primaryGpu?.pricePerHour ?? 0.44) * 200).toInt()} credits/hr)',
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: LuminaColors.primaryEnd,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _fitColor(String fit) {
    switch (fit.toLowerCase()) {
      case 'optimal':
        return Colors.greenAccent.shade700;
      case 'tight':
        return Colors.amber;
      case 'minimum':
      default:
        return Colors.orangeAccent;
    }
  }
}
