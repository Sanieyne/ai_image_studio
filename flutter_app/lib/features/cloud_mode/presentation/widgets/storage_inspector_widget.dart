import 'package:flutter/material.dart';
import '../../../../theme/app_theme.dart';
import '../../data/models/cloud_model.dart';

class StorageInspectorWidget extends StatefulWidget {
  final RecommendationResult? result;
  final MarketplaceOffer? selectedOffer;
  final bool isDark;
  final Function(String modelId)? onEvictModel;
  final Function(MarketplaceOffer? offer)? onLaunchInstance;

  const StorageInspectorWidget({
    super.key,
    required this.result,
    this.selectedOffer,
    required this.isDark,
    this.onEvictModel,
    this.onLaunchInstance,
  });

  @override
  State<StorageInspectorWidget> createState() => _StorageInspectorWidgetState();
}

class _StorageInspectorWidgetState extends State<StorageInspectorWidget> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final border = widget.isDark ? LuminaColors.darkBorder : LuminaColors.lightBorder;
    final surface = widget.isDark ? LuminaColors.darkSurface : Colors.white;
    final muted = widget.isDark ? LuminaColors.darkMuted : LuminaColors.lightMuted;

    final req = widget.result?.requirements;
    final plan = widget.result?.recommendedStorage;
    final offer = widget.selectedOffer;
    final primaryFallbackGpu = widget.result?.compatibleGPUs.firstOrNull;

    final displayName = offer?.gpuName ?? primaryFallbackGpu?.name ?? 'RTX 4090';
    final fit = offer?.fit ?? primaryFallbackGpu?.fit ?? 'optimal';
    final price = offer?.pricePerHour ?? primaryFallbackGpu?.pricePerHour ?? 0.58;
    final totalHourly = offer?.totalHourlyCost ?? price;
    final creditsPerHour = offer?.creditsPerHour ?? primaryFallbackGpu?.creditsPerHour ?? (price * kVastPriceMarkup * kCreditsPerUsd);
    final totalCreditsPerHour = offer?.totalCreditsPerHour ?? (totalHourly * kVastPriceMarkup * kCreditsPerUsd);
    final storageCreditsPerHour = offer?.storageCreditsPerHour ?? ((offer?.storageCostPerHour ?? 0.004) * kVastPriceMarkup * kCreditsPerUsd);
    final bandwidthCreditsPerGB = offer?.bandwidthCreditsPerGB ?? ((offer?.bandwidthCostPerGB ?? 0.02) * kVastPriceMarkup * kCreditsPerUsd);
    final maxVram = req?.maxVramGB ?? 12.0;
    final totalVram = offer?.vramGB ?? primaryFallbackGpu?.vramGB ?? 24.0;
    final headroom = offer?.headroomVramGB ?? primaryFallbackGpu?.headroomVramGB ?? 12.0;

    final totalGB = req?.totalWithBufferGB ?? 15.97;
    final planGB = plan?.sizeGB ?? 30.0;
    final usedRatio = (totalGB / planGB).clamp(0.0, 1.0);

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
          // Header: Title & Fit Badge
          Row(
            children: [
              const Icon(Icons.analytics_rounded, size: 20, color: LuminaColors.infoBlue),
              const SizedBox(width: 8),
              const Text(
                'GPU Specs & Telemetry',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: _fitColor(fit).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _fitColor(fit)),
                ),
                child: Text(
                  fit.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: _fitColor(fit),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Scrollable content with scrollbar
          Expanded(
            child: Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              radius: const Radius.circular(8),
              child: SingleChildScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(right: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Section 1: GPU Identity & Compute Card
                    _buildSectionCard(
                      border: border,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      displayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      offer != null
                                          ? '${offer.provider.toUpperCase()} Host · #${offer.id}'
                                          : 'Vast.ai Verified Node',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 11, color: muted),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.greenAccent.shade700.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${creditsPerHour.toStringAsFixed(1)} cr/hr',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.greenAccent.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // VRAM Sizing Bar
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'VRAM: ${maxVram.toStringAsFixed(0)}GB Req.',
                                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                              ),
                              Flexible(
                                child: Text(
                                  '${totalVram.toStringAsFixed(0)}GB (+${headroom.toStringAsFixed(0)}GB)',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11.5, color: LuminaColors.infoBlue, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: (maxVram / totalVram).clamp(0.0, 1.0),
                              minHeight: 8,
                              backgroundColor: widget.isDark ? Colors.white12 : Colors.black12,
                              valueColor: AlwaysStoppedAnimation<Color>(_fitColor(fit)),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Hardware Specifications Grid
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _buildMetricChip(Icons.bolt_rounded, 'AI Score', '${offer?.dlperf.toStringAsFixed(1) ?? '122.8'} dlperf', LuminaColors.amber),
                              _buildMetricChip(Icons.memory_rounded, 'Host Rig', '${offer?.cpuCores ?? 32} vCPU · ${offer?.ramGB.toInt() ?? 129}GB RAM', Colors.cyanAccent.shade700),
                              _buildMetricChip(Icons.storage_rounded, 'Local NVMe', '${offer?.diskGB ?? 362} GB SSD', LuminaColors.purple),
                              _buildMetricChip(Icons.developer_board_rounded, 'NVIDIA Stack', 'CUDA ${offer?.cudaVersion ?? 13.2} (v${offer?.driverVersion ?? '595.84'})', muted),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Section 2: Internet Speed & Weights Streaming
                    _buildSectionHeader(Icons.speed_rounded, 'Internet Speed & Weights Streaming', LuminaColors.amber),
                    const SizedBox(height: 8),
                    _buildSectionCard(
                      border: border,
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.greenAccent.shade700.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.greenAccent.shade700.withValues(alpha: 0.3)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('DOWNLOAD SPEED', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.greenAccent.shade700)),
                                      const SizedBox(height: 2),
                                      Text('↓ ${offer?.inetDown ?? 1468} Mbps', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: LuminaColors.infoBlue.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: LuminaColors.infoBlue.withValues(alpha: 0.3)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('UPLOAD SPEED', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: LuminaColors.infoBlue)),
                                      const SizedBox(height: 2),
                                      Text('↑ ${offer?.inetUp ?? 781} Mbps', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _buildInfoTile(
                                  icon: Icons.timer_outlined,
                                  title: 'Model Weights Stream',
                                  value: '~${offer?.estimatedDownloadTimeMinutes ?? 0.6} min',
                                  color: Colors.orangeAccent,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildInfoTile(
                                  icon: Icons.data_usage_rounded,
                                  title: 'Bandwidth Egress',
                                  value: '${bandwidthCreditsPerGB.toStringAsFixed(2)} cr/GB',
                                  color: LuminaColors.infoBlue,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Section 3: Geolocation & Host Infrastructure
                    _buildSectionHeader(Icons.public_rounded, 'Location & Host Infrastructure', LuminaColors.infoBlue),
                    const SizedBox(height: 8),
                    _buildSectionCard(
                      border: border,
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _buildInfoTile(
                                  icon: Icons.location_on_rounded,
                                  title: 'Data Center Location',
                                  value: offer?.geolocation.isNotEmpty == true ? offer!.geolocation : 'Romania, RO',
                                  color: Colors.purpleAccent.shade100,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildInfoTile(
                                  icon: Icons.verified_user_rounded,
                                  title: 'Host Reliability SLA',
                                  value: '${((offer?.reliability ?? 0.997) * 100).toStringAsFixed(1)}% Uptime',
                                  color: Colors.tealAccent.shade400,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _buildInfoTile(
                                  icon: Icons.cable_rounded,
                                  title: 'Direct Open Ports',
                                  value: '${offer?.directPortCount ?? 124} Ports Open',
                                  color: muted,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildInfoTile(
                                  icon: Icons.check_circle_rounded,
                                  title: 'Hardware Status',
                                  value: 'Verified & Rentable',
                                  color: Colors.greenAccent.shade700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Section 4: Cloud Storage Volume Sizing
                    _buildSectionHeader(Icons.cloud_upload_rounded, 'Cloud Storage Volume Sizing', LuminaColors.purple),
                    const SizedBox(height: 8),
                    _buildSectionCard(
                      border: border,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${totalGB.toStringAsFixed(1)} GB Footprint',
                                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                              ),
                              Flexible(
                                child: Text(
                                  '${planGB.toInt()} GB Plan (${plan?.name ?? 'Starter'})',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11.5, color: LuminaColors.purple, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: usedRatio,
                              minHeight: 8,
                              backgroundColor: widget.isDark ? Colors.white12 : Colors.black12,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                usedRatio > 0.85 ? Colors.redAccent : LuminaColors.purple,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _buildFootprintChip('Model Weights: ${(req?.totalModelSizeGB ?? 6.9).toStringAsFixed(1)} GB', LuminaColors.infoBlue),
                              _buildFootprintChip('Engine & venv: ${(req?.baseOverheadGB ?? 7.0).toStringAsFixed(0)} GB', Colors.amber),
                              _buildFootprintChip('Output Buffer: ${(req?.bufferGB ?? 2.1).toStringAsFixed(1)} GB', LuminaColors.purple),
                              _buildFootprintChip('Free Space: ${(plan?.freeAfterGB ?? 14.0).toStringAsFixed(1)} GB', Colors.greenAccent.shade700),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Section 5: Cached Models in Volume
                    _buildSectionHeader(Icons.folder_copy_rounded, 'Selected AI Models (${widget.result?.selectedModels.length ?? 1})', Colors.grey),
                    const SizedBox(height: 8),
                    _buildSectionCard(
                      border: border,
                      child: Column(
                        children: (widget.result?.selectedModels ?? [
                          {'displayName': 'SDXL Base 1.0', 'sizeGB': 6.9, 'modelId': 'sdxl-base-1.0'}
                        ]).map((modelMap) {
                          final modelId = modelMap['modelId']?.toString() ?? '';
                          final name = modelMap['displayName']?.toString() ?? modelId;
                          final sizeGB = (modelMap['sizeGB'] as num?)?.toDouble() ?? 0.0;

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                const Icon(Icons.check_circle_outline_rounded, size: 16, color: LuminaColors.primaryEnd),
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
                                if (widget.onEvictModel != null && (widget.result?.selectedModels.length ?? 0) > 1) ...[
                                  const SizedBox(width: 6),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Colors.redAccent),
                                    tooltip: 'Evict model from volume cache',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () => widget.onEvictModel!(modelId),
                                  ),
                                ],
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Section 6: Cost Summary
                    _buildSectionCard(
                      border: border,
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('GPU Hourly Compute:', style: TextStyle(fontSize: 12, color: muted)),
                              Text('${creditsPerHour.toStringAsFixed(1)} cr/hr', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Storage Volume Lease:', style: TextStyle(fontSize: 12, color: muted)),
                              Text('+${storageCreditsPerHour.toStringAsFixed(2)} cr/hr', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            ],
                          ),
                          const Divider(height: 14),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Total Hourly Cost:', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                              Flexible(
                                child: Text(
                                  '${totalCreditsPerHour.toStringAsFixed(1)} credits/hr',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: LuminaColors.amber),
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
            ),
          ),

          const SizedBox(height: 12),
          // Pinned Bottom Action: Rent & Launch Instance
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: () => widget.onLaunchInstance?.call(offer),
              icon: const Icon(Icons.rocket_launch_rounded, size: 18),
              label: Text(
                'Rent & Launch $displayName (${totalCreditsPerHour.toStringAsFixed(1)} credits/hr)',
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

  Widget _buildSectionHeader(IconData icon, String title, Color color) {
    return Row(
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildSectionCard({required Widget child, required Color border}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (widget.isDark ? Colors.black : Colors.white).withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border.withValues(alpha: 0.6)),
      ),
      child: child,
    );
  }

  Widget _buildMetricChip(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text('$label: ', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500)),
          Text(value, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: (widget.isDark ? Colors.white : Colors.black).withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 10, color: widget.isDark ? Colors.white54 : Colors.black54),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFootprintChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
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
