import 'package:flutter/material.dart';
import '../../../../theme/app_theme.dart';
import '../../data/models/cloud_model.dart';

class GpuRecommendationCard extends StatefulWidget {
  final RecommendationResult? result;
  final MarketplaceRecommendedResult? marketplaceResult;
  final bool isDark;
  final Function(MarketplaceOffer? offer) onLaunchInstance;

  const GpuRecommendationCard({
    super.key,
    required this.result,
    this.marketplaceResult,
    required this.isDark,
    required this.onLaunchInstance,
  });

  @override
  State<GpuRecommendationCard> createState() => _GpuRecommendationCardState();
}

class _GpuRecommendationCardState extends State<GpuRecommendationCard> {
  String _selectedRankMode = 'balanced'; // 'balanced' | 'cheapest' | 'fastest' | 'reliable'
  MarketplaceOffer? _selectedOfferOverride;

  @override
  Widget build(BuildContext context) {
    final border = widget.isDark ? LuminaColors.darkBorder : LuminaColors.lightBorder;
    final surface = widget.isDark ? LuminaColors.darkSurface : Colors.white;
    final muted = widget.isDark ? LuminaColors.darkMuted : LuminaColors.lightMuted;

    final mr = widget.marketplaceResult;
    MarketplaceOffer? activeOffer;

    if (_selectedOfferOverride != null) {
      activeOffer = _selectedOfferOverride;
    } else if (mr != null) {
      switch (_selectedRankMode) {
        case 'cheapest':
          activeOffer = mr.cheapestOffer ?? mr.allOffers.firstOrNull;
          break;
        case 'fastest':
          activeOffer = mr.fastestOffer ?? mr.allOffers.firstOrNull;
          break;
        case 'reliable':
          activeOffer = mr.mostReliableOffer ?? mr.allOffers.firstOrNull;
          break;
        case 'balanced':
        default:
          activeOffer = mr.balancedOffer ?? mr.allOffers.firstOrNull;
          break;
      }
    }

    final primaryFallbackGpu = widget.result?.compatibleGPUs.firstOrNull;
    final maxVram = widget.result?.requirements.maxVramGB ?? 12.0;

    final displayName = activeOffer?.gpuName ?? primaryFallbackGpu?.name ?? 'RTX 3090';
    final price = activeOffer?.pricePerHour ?? primaryFallbackGpu?.pricePerHour ?? 0.44;
    final totalHourly = activeOffer?.totalHourlyCost ?? price;
    final vramTotal = activeOffer?.vramGB ?? primaryFallbackGpu?.vramGB ?? 24.0;
    final headroom = activeOffer?.headroomVramGB ?? primaryFallbackGpu?.headroomVramGB ?? 0.0;
    final fit = activeOffer?.fit ?? primaryFallbackGpu?.fit ?? 'optimal';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface.withValues(alpha: widget.isDark ? 0.72 : 0.85),
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
                'Live GPU Marketplace',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _fitColor(fit).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _fitColor(fit)),
                ),
                child: Text(
                  fit.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: _fitColor(fit),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Marketplace ranking selection pills
          if (mr != null && mr.allOffers.isNotEmpty) ...[
            Row(
              children: [
                _buildRankTab('balanced', '⚖ Balanced', mr.balancedOffer != null),
                const SizedBox(width: 6),
                _buildRankTab('cheapest', '💰 Lowest Cost', mr.cheapestOffer != null),
                const SizedBox(width: 6),
                _buildRankTab('fastest', '⚡ Fastest', mr.fastestOffer != null),
                const SizedBox(width: 6),
                _buildRankTab('reliable', '🛡 99%+ Uptime', mr.mostReliableOffer != null),
              ],
            ),
            const SizedBox(height: 12),
          ],

          // Primary Recommendation Hero Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                colors: [
                  LuminaColors.infoBlue.withValues(alpha: widget.isDark ? 0.2 : 0.1),
                  LuminaColors.primaryEnd.withValues(alpha: widget.isDark ? 0.15 : 0.05),
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
                    Row(
                      children: [
                        Text(
                          displayName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                        if (activeOffer != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.greenAccent.shade700.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${activeOffer.inetDown} Mbps ↓',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.greenAccent.shade700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '\$${price.toStringAsFixed(2)} / hr',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: LuminaColors.amber,
                          ),
                        ),
                        Text(
                          '(\$${totalHourly.toStringAsFixed(3)} w/ storage)',
                          style: TextStyle(fontSize: 10.5, color: muted),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  activeOffer?.fitReason ?? 'Best balance of VRAM headroom, network bandwidth, and cost.',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
                const SizedBox(height: 12),

                // VRAM Usage Progress Bar
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('VRAM Required: ${maxVram.toStringAsFixed(0)} GB',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    Text(
                      '${vramTotal.toStringAsFixed(0)} GB Total (+${headroom.toStringAsFixed(0)} GB Headroom)',
                      style: const TextStyle(fontSize: 12, color: LuminaColors.infoBlue, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: (maxVram / vramTotal).clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: widget.isDark ? Colors.white12 : Colors.black12,
                    valueColor: AlwaysStoppedAnimation<Color>(_fitColor(fit)),
                  ),
                ),

                if (activeOffer != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: (widget.isDark ? Colors.black : Colors.white).withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: border.withValues(alpha: 0.5)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _buildTelemetryBadge(
                                icon: Icons.speed_rounded,
                                label: 'Network',
                                value: '↓ ${activeOffer.inetDown}M / ↑ ${activeOffer.inetUp}M',
                                color: Colors.greenAccent.shade700,
                              ),
                            ),
                            Expanded(
                              child: _buildTelemetryBadge(
                                icon: Icons.data_usage_rounded,
                                label: 'Bandwidth',
                                value: '\$${activeOffer.bandwidthCostPerGB.toStringAsFixed(2)}/GB',
                                color: LuminaColors.infoBlue,
                              ),
                            ),
                            Expanded(
                              child: _buildTelemetryBadge(
                                icon: Icons.timer_outlined,
                                label: 'Download',
                                value: '~${activeOffer.estimatedDownloadTimeMinutes}m',
                                color: Colors.orangeAccent,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _buildTelemetryBadge(
                                icon: Icons.location_on_outlined,
                                label: 'Location',
                                value: activeOffer.geolocation.isNotEmpty ? activeOffer.geolocation : 'Global',
                                color: Colors.purpleAccent.shade100,
                              ),
                            ),
                            Expanded(
                              child: _buildTelemetryBadge(
                                icon: Icons.verified_user_outlined,
                                label: 'Uptime',
                                value: '${(activeOffer.reliability * 100).toStringAsFixed(1)}%',
                                color: Colors.tealAccent.shade400,
                              ),
                            ),
                            Expanded(
                              child: _buildTelemetryBadge(
                                icon: Icons.bolt_rounded,
                                label: 'AI Compute',
                                value: '${activeOffer.dlperf.toStringAsFixed(1)} dlperf',
                                color: LuminaColors.amber,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: _buildTelemetryBadge(
                                icon: Icons.memory_rounded,
                                label: 'System',
                                value: '${activeOffer.cpuCores} vCPU · ${activeOffer.ramGB.toInt()}GB RAM · ${activeOffer.diskGB}GB Disk',
                                color: muted,
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: _buildTelemetryBadge(
                                icon: Icons.developer_board_rounded,
                                label: 'NVIDIA',
                                value: 'CUDA ${activeOffer.cudaVersion} (v${activeOffer.driverVersion})',
                                color: muted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                'Live Available GPU Instances (${mr?.allOffers.length ?? widget.result?.compatibleGPUs.length ?? 0})',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (_selectedOfferOverride != null)
                InkWell(
                  onTap: () => setState(() => _selectedOfferOverride = null),
                  child: const Text(
                    'Reset to Recommended',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: LuminaColors.infoBlue,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Compatible Offers List
          Expanded(
            child: ListView.separated(
              itemCount: mr?.allOffers.length ?? widget.result?.compatibleGPUs.length ?? 0,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, idx) {
                if (mr != null && mr.allOffers.isNotEmpty) {
                  final offer = mr.allOffers[idx];
                  final isSelected = offer.id == activeOffer?.id;

                  return InkWell(
                    onTap: () {
                      setState(() {
                        _selectedOfferOverride = offer;
                      });
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? LuminaColors.infoBlue
                              : border,
                          width: isSelected ? 1.5 : 1.0,
                        ),
                        color: isSelected
                            ? LuminaColors.infoBlue.withValues(alpha: widget.isDark ? 0.15 : 0.08)
                            : (widget.isDark ? Colors.white.withValues(alpha: 0.02) : Colors.black.withValues(alpha: 0.02)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                                size: 16,
                                color: isSelected ? LuminaColors.infoBlue : muted,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                offer.gpuName,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: LuminaColors.infoBlue.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${offer.vramGB.toInt()}GB VRAM',
                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: LuminaColors.infoBlue),
                                ),
                              ),
                              if (offer.geolocation.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    '📍 ${offer.geolocation}',
                                    style: TextStyle(fontSize: 11, color: muted),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                              const Spacer(),
                              Text(
                                '\$${offer.pricePerHour.toStringAsFixed(2)}/hr',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: LuminaColors.amber),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              _buildMiniTag('↓ ${offer.inetDown}M / ↑ ${offer.inetUp}M', Colors.greenAccent.shade700),
                              _buildMiniTag('\$${offer.bandwidthCostPerGB.toStringAsFixed(2)}/GB egress', Colors.cyanAccent.shade700),
                              _buildMiniTag('⚡ ${offer.dlperf.toStringAsFixed(1)} dlperf', LuminaColors.amber),
                              _buildMiniTag('🛡 ${(offer.reliability * 100).toInt()}% SLA', Colors.tealAccent.shade400),
                              _buildMiniTag('${offer.cpuCores} vCPU · ${offer.ramGB.toInt()}GB RAM', muted),
                              _buildMiniTag('⏱ ~${offer.estimatedDownloadTimeMinutes}m dl', Colors.orangeAccent),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }

                // Fallback rendering
                final gpu = widget.result!.compatibleGPUs[idx];
                final isBest = idx == 0;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: isBest ? LuminaColors.infoBlue.withValues(alpha: 0.4) : border),
                  ),
                  child: Row(
                    children: [
                      Text(gpu.name, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                      const Spacer(),
                      Text('\$${gpu.pricePerHour.toStringAsFixed(2)}/hr',
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
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
              onPressed: () => widget.onLaunchInstance(activeOffer),
              icon: const Icon(Icons.rocket_launch_rounded, size: 18),
              label: Text(
                'Rent & Launch $displayName (~${(totalHourly * 200).toInt()} credits/hr)',
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

  Widget _buildRankTab(String modeKey, String label, bool enabled) {
    final active = _selectedRankMode == modeKey && _selectedOfferOverride == null;
    final muted = widget.isDark ? LuminaColors.darkMuted : LuminaColors.lightMuted;

    return Expanded(
      child: InkWell(
        onTap: enabled
            ? () => setState(() {
                  _selectedRankMode = modeKey;
                  _selectedOfferOverride = null;
                })
            : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: active
                ? LuminaColors.infoBlue.withValues(alpha: 0.2)
                : (widget.isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03)),
            border: Border.all(
              color: active ? LuminaColors.infoBlue : Colors.transparent,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: active ? FontWeight.bold : FontWeight.w500,
                color: active ? LuminaColors.infoBlue : (enabled ? muted : Colors.grey.withValues(alpha: 0.4)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTelemetryBadge({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
            color: widget.isDark ? Colors.white60 : Colors.black54,
          ),
        ),
        Flexible(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildMiniTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.8),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: color),
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
