import 'package:flutter/material.dart';
import '../../../../theme/app_theme.dart';
import '../../data/models/cloud_model.dart';
import '../../data/services/cloud_api_service.dart';

class GpuRecommendationCard extends StatefulWidget {
  final RecommendationResult? result;
  final MarketplaceRecommendedResult? marketplaceResult;
  final MarketplaceOffer? selectedOffer;
  final ValueChanged<MarketplaceOffer?>? onSelectOffer;
  final bool isDark;
  final Function(MarketplaceOffer? offer) onLaunchInstance;
  final String? initialTab;
  final String? initialSearchQuery;
  final bool hasModelSelection;

  /// When set, renting is off (e.g. rentals paused); the reason is shown on the button.
  final String? rentDisabledReason;

  const GpuRecommendationCard({
    super.key,
    required this.result,
    this.marketplaceResult,
    this.selectedOffer,
    this.onSelectOffer,
    required this.isDark,
    required this.onLaunchInstance,
    this.initialTab,
    this.initialSearchQuery,
    this.rentDisabledReason,
    this.hasModelSelection = false,
  });

  @override
  State<GpuRecommendationCard> createState() => _GpuRecommendationCardState();
}

class _GpuRecommendationCardState extends State<GpuRecommendationCard> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final _cloudApi = CloudApiService.instance;

  String _browsingTab = 'recommended'; // 'recommended' | 'series' | 'search'
  String _selectedRankMode = 'balanced'; // 'balanced' | 'cheapest' | 'fastest' | 'reliable'

  Map<String, List<String>> _gpuSeriesMap = {};
  String _selectedSeries = 'All';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    if (widget.initialTab != null) {
      _browsingTab = widget.initialTab!;
    }
    if (widget.initialSearchQuery != null && widget.initialSearchQuery!.isNotEmpty) {
      _searchQuery = widget.initialSearchQuery!;
      _searchController.text = widget.initialSearchQuery!;
    }
    _loadSeries();
  }

  Future<void> _loadSeries() async {
    final series = await _cloudApi.fetchGpuSeries();
    if (!mounted) return;
    if (series != null && series.isNotEmpty) {
      setState(() {
        _gpuSeriesMap = series;
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final border = widget.isDark ? LuminaColors.darkBorder : LuminaColors.lightBorder;
    final surface = widget.isDark ? LuminaColors.darkSurface : Colors.white;
    final muted = widget.isDark ? LuminaColors.darkMuted : LuminaColors.lightMuted;

    final mr = widget.marketplaceResult;

    // Filter displayed offers based on current tab
    List<MarketplaceOffer> displayedOffers = mr?.allOffers ?? [];
    if (_browsingTab == 'series') {
      if (_selectedSeries != 'All') {
        final allowedModels = _gpuSeriesMap[_selectedSeries] ?? [];
        displayedOffers = displayedOffers.where((offer) {
          if (allowedModels.isNotEmpty) {
            return allowedModels.any((m) => offer.gpuName.toLowerCase().contains(m.toLowerCase()));
          }
          if (_selectedSeries == 'RTX 30-Series') return offer.gpuName.contains('30');
          if (_selectedSeries == 'RTX 40-Series') return offer.gpuName.contains('40');
          if (_selectedSeries == 'RTX 50-Series') return offer.gpuName.contains('50');
          if (_selectedSeries == 'Datacenter') return offer.gpuName.contains('A100') || offer.gpuName.contains('H100') || offer.gpuName.contains('Tesla') || offer.gpuName.contains('Ada');
          return true;
        }).toList();
      }
    } else if (_browsingTab == 'search') {
      final query = _searchQuery.trim().toLowerCase();
      if (query.isNotEmpty) {
        displayedOffers = displayedOffers.where((offer) {
          return offer.gpuName.toLowerCase().contains(query);
        }).toList();
      }
    }

    final MarketplaceOffer? userSelectedOffer = widget.selectedOffer;

    // Display-only recommendation: computed only when a model is selected,
    // and only on the Recommended tab. Never written into the selection.
    MarketplaceOffer? recommendedOffer;
    if (widget.hasModelSelection && _browsingTab == 'recommended' && mr != null && mr.allOffers.isNotEmpty) {
      switch (_selectedRankMode) {
        case 'cheapest':
          recommendedOffer = mr.cheapestOffer;
          break;
        case 'fastest':
          recommendedOffer = mr.fastestOffer;
          break;
        case 'reliable':
          recommendedOffer = mr.mostReliableOffer;
          break;
        case 'balanced':
        default:
          recommendedOffer = mr.balancedOffer;
          break;
      }
    }

    // Hero card shows the user's pick if any, otherwise the highlighted recommendation.
    final MarketplaceOffer? activeOffer = userSelectedOffer ?? recommendedOffer;
    final bool heroIsRecommendationOnly = userSelectedOffer == null && recommendedOffer != null;
    final bool canLaunch = widget.rentDisabledReason == null &&
        widget.hasModelSelection &&
        userSelectedOffer != null &&
        userSelectedOffer.priceAvailable;

    final primaryFallbackGpu = widget.result?.compatibleGPUs.firstOrNull;
    final maxVram = widget.result?.requirements.maxVramGB ?? 12.0;

    final displayName = activeOffer?.gpuName ?? primaryFallbackGpu?.name ?? 'RTX 3090';
    // Server prices for the selected storage size; null = price unavailable.
    final double? computeCreditsPerHour = activeOffer?.computeCreditsPerHour;
    final double? storageCreditsPerHour = activeOffer?.storageCreditsPerHour;
    final double? totalCreditsPerHour = activeOffer?.totalCreditsPerHour;
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
          const SizedBox(height: 10),

          // Three GPU Browsing Tabs: Recommended | By Series | Search
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: (widget.isDark ? Colors.black : Colors.white).withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: border),
            ),
            child: Row(
              children: [
                _buildTopNavTab('recommended', Icons.auto_awesome_rounded, 'Recommended'),
                _buildTopNavTab('series', Icons.layers_rounded, 'By Series'),
                _buildTopNavTab('search', Icons.search_rounded, 'Search'),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Sub-navigation filter bar
          if (_browsingTab == 'recommended' && mr != null && mr.allOffers.isNotEmpty && widget.hasModelSelection) ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
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
            ),
            const SizedBox(height: 10),
          ] else if (_browsingTab == 'series') ...[
            _buildSeriesFilterRow(border, muted, mr),
            const SizedBox(height: 10),
          ] else if (_browsingTab == 'search') ...[
            _buildSearchField(border, muted),
            const SizedBox(height: 10),
          ],

          // Scrollable Content Area: Hero Card + Telemetry + Available GPU Offers
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
                    if (activeOffer == null)
                      _buildSelectionPrompt(border: border, muted: muted)
                    else ...[
                      if (heroIsRecommendationOnly)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              const Icon(Icons.auto_awesome_rounded, size: 14, color: LuminaColors.amber),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Top recommendation for your models — tap it to select',
                                  style: TextStyle(fontSize: 11.5, color: muted, fontWeight: FontWeight.w600),
                                ),
                              ),
                              TextButton.icon(
                                key: const ValueKey('select_recommended_btn'),
                                onPressed: () => widget.onSelectOffer?.call(recommendedOffer),
                                icon: const Icon(Icons.check_rounded, size: 14),
                                label: const Text('Select this GPU', style: TextStyle(fontSize: 11.5)),
                              ),
                            ],
                          ),
                        ),
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
                            color: heroIsRecommendationOnly
                                ? LuminaColors.amber.withValues(alpha: 0.6)
                                : LuminaColors.infoBlue.withValues(alpha: 0.5),
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        displayName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: -0.2,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
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
                                ),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    formatCreditsRate(totalCreditsPerHour, 'credits/hr'),
                                    key: const ValueKey('gpu_card_total_rate'),
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: LuminaColors.amber,
                                    ),
                                  ),
                                  if (totalCreditsPerHour != null)
                                    Text(
                                      'GPU ${formatCreditsRate(computeCreditsPerHour, '')}+ '
                                      '${activeOffer.storageGB ?? '?'} GB storage ${formatCreditsRate(storageCreditsPerHour, '')}'.trim(),
                                      style: TextStyle(fontSize: 10.5, color: muted),
                                    ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            activeOffer.fitReason.isNotEmpty ? activeOffer.fitReason : 'Best balance of VRAM headroom, network bandwidth, and cost.',
                            style: TextStyle(fontSize: 12, color: muted),
                          ),
                          const SizedBox(height: 12),

                          // VRAM Usage Progress Bar
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('VRAM Required: ${maxVram.toStringAsFixed(0)} GB',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              Flexible(
                                child: Text(
                                  '${vramTotal.toStringAsFixed(0)} GB (+${headroom.toStringAsFixed(0)} GB)',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12, color: LuminaColors.infoBlue, fontWeight: FontWeight.w600),
                                ),
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
                                          value: _bandwidthText(activeOffer),
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
                      ),
                    ),
                  ],

                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Text(
                          _browsingTab == 'recommended'
                              ? 'Live Available GPU Instances (${displayedOffers.length})'
                              : (_browsingTab == 'series'
                                  ? 'GPUs in $_selectedSeries (${displayedOffers.length})'
                                  : 'Search Results (${displayedOffers.length})'),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        if (userSelectedOffer != null)
                          InkWell(
                            onTap: () => widget.onSelectOffer?.call(null),
                            child: const Text(
                              'Clear selection',
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
                    if (displayedOffers.isNotEmpty)
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: displayedOffers.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, idx) {
                          final offer = displayedOffers[idx];
                          final isSelected = offer.id == userSelectedOffer?.id;
                          final isRecommended = !isSelected && offer.id == recommendedOffer?.id;

                          return InkWell(
                            onTap: () => widget.onSelectOffer?.call(offer),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected
                                      ? LuminaColors.infoBlue
                                      : (isRecommended ? LuminaColors.amber.withValues(alpha: 0.7) : border),
                                  width: (isSelected || isRecommended) ? 1.5 : 1.0,
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
                                      if (isRecommended) ...[
                                        const SizedBox(width: 6),
                                        _buildMiniTag('★ Recommended', LuminaColors.amber),
                                      ],
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
                                        formatCreditsRate(offer.totalCreditsPerHour, 'cr/hr'),
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
                                      _buildMiniTag(_bandwidthText(offer), Colors.cyanAccent.shade700),
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
                        },
                      )
                    else if (mr != null)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
                        alignment: Alignment.center,
                        child: Column(
                          children: [
                            Icon(Icons.search_off_rounded, size: 36, color: muted),
                            const SizedBox(height: 8),
                            Text(
                              _browsingTab == 'search'
                                  ? 'No GPUs matching "$_searchQuery"'
                                  : 'No available GPUs in $_selectedSeries',
                              style: TextStyle(fontSize: 12.5, color: muted, fontWeight: FontWeight.w600),
                            ),
                            if (_browsingTab == 'search') ...[
                              const SizedBox(height: 6),
                              TextButton(
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                                child: const Text('Clear search filter', style: TextStyle(fontSize: 12)),
                              ),
                            ],
                          ],
                        ),
                      )
                    else if (widget.result?.compatibleGPUs.isNotEmpty ?? false)
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: widget.result!.compatibleGPUs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, idx) {
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
                                Text(gpu.creditsPerHour == null ? kPriceUnavailable : '~${formatCreditsRate(gpu.creditsPerHour, 'cr/hr', decimals: 1)} typical',
                                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 10),
          // Launch Instance Button
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              key: const ValueKey('gpu_card_launch_btn'),
              onPressed: canLaunch ? () => widget.onLaunchInstance(userSelectedOffer) : null,
              icon: Icon(canLaunch ? Icons.rocket_launch_rounded : Icons.lock_outline_rounded, size: 18),
              label: Text(
                widget.rentDisabledReason != null
                    ? widget.rentDisabledReason!
                    : !widget.hasModelSelection
                    ? 'Select a model to continue'
                    : (userSelectedOffer == null
                        ? 'Select a GPU offer to continue'
                        : (userSelectedOffer.priceAvailable
                            ? 'Rent & Launch $displayName (${formatCreditsRate(userSelectedOffer.totalCreditsPerHour, 'credits/hr')})'
                            : 'Rent unavailable: $kPriceUnavailable')),
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: LuminaColors.primaryEnd,
                foregroundColor: Colors.white,
                disabledBackgroundColor: (widget.isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
                disabledForegroundColor: muted,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: canLaunch ? 4 : 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionPrompt({required Color border, required Color muted}) {
    final noModels = !widget.hasModelSelection;
    return Container(
      key: const ValueKey('gpu_selection_prompt'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
        color: (widget.isDark ? Colors.white : Colors.black).withValues(alpha: 0.03),
      ),
      child: Column(
        children: [
          Icon(noModels ? Icons.layers_outlined : Icons.touch_app_rounded, size: 32, color: LuminaColors.infoBlue),
          const SizedBox(height: 8),
          Text(
            noModels ? 'No Models Selected' : 'No GPU Selected',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            noModels
                ? 'Select a model to see personalized recommendations'
                : 'Tap a GPU below to select it',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: muted),
          ),
        ],
      ),
    );
  }

  Widget _buildRankTab(String modeKey, String label, bool enabled) {
    final active = _selectedRankMode == modeKey;
    final muted = widget.isDark ? LuminaColors.darkMuted : LuminaColors.lightMuted;

    return InkWell(
      // Display-only: changes which offer is highlighted. Never selects an offer.
      onTap: enabled ? () => setState(() => _selectedRankMode = modeKey) : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
    );
  }

  Widget _buildTopNavTab(String tabKey, IconData icon, String label) {
    final active = _browsingTab == tabKey;
    final muted = widget.isDark ? LuminaColors.darkMuted : LuminaColors.lightMuted;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          setState(() {
            _browsingTab = tabKey;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: active
                ? LuminaColors.infoBlue.withValues(alpha: widget.isDark ? 0.25 : 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: active
                ? Border.all(color: LuminaColors.infoBlue.withValues(alpha: 0.6))
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: active ? LuminaColors.infoBlue : muted,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: active ? FontWeight.bold : FontWeight.w500,
                    color: active ? LuminaColors.infoBlue : muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSeriesFilterRow(Color border, Color muted, MarketplaceRecommendedResult? mr) {
    final seriesKeys = ['All', ...(_gpuSeriesMap.isNotEmpty ? _gpuSeriesMap.keys : ['RTX 30-Series', 'RTX 40-Series', 'RTX 50-Series', 'Datacenter'])];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: seriesKeys.map((key) {
          final isSelected = _selectedSeries == key;
          int count = 0;
          if (mr != null) {
            if (key == 'All') {
              count = mr.allOffers.length;
            } else {
              final models = _gpuSeriesMap[key] ?? [];
              count = mr.allOffers.where((o) {
                if (models.isNotEmpty) return models.any((m) => o.gpuName.toLowerCase().contains(m.toLowerCase()));
                if (key == 'RTX 30-Series') return o.gpuName.contains('30');
                if (key == 'RTX 40-Series') return o.gpuName.contains('40');
                if (key == 'RTX 50-Series') return o.gpuName.contains('50');
                if (key == 'Datacenter') return o.gpuName.contains('A100') || o.gpuName.contains('H100') || o.gpuName.contains('Tesla') || o.gpuName.contains('Ada');
                return false;
              }).length;
            }
          }

          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _selectedSeries = key),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isSelected
                      ? LuminaColors.infoBlue.withValues(alpha: widget.isDark ? 0.25 : 0.15)
                      : (widget.isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02)),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected ? LuminaColors.infoBlue : border,
                    width: isSelected ? 1.5 : 1.0,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      key,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected ? LuminaColors.infoBlue : muted,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: isSelected ? LuminaColors.infoBlue.withValues(alpha: 0.3) : (widget.isDark ? Colors.white10 : Colors.black12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? LuminaColors.infoBlue : muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSearchField(Color border, Color muted) {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: (widget.isDark ? Colors.black : Colors.white).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(fontSize: 12.5),
        decoration: InputDecoration(
          hintText: 'Search GPU models (e.g. 4090, 3090, A100)...',
          hintStyle: TextStyle(fontSize: 12, color: muted),
          prefixIcon: const Icon(Icons.search_rounded, size: 16),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 14),
                  padding: EdgeInsets.zero,
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          isDense: true,
        ),
        onChanged: (val) {
          setState(() => _searchQuery = val);
        },
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
        Flexible(
          child: Text(
            '$label: $value',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  /// "↓ 0.2441 · ↑ 0.2441 cr/GB (by usage)" from the server's per-GB prices.
  String _bandwidthText(MarketplaceOffer offer) {
    String v(double? x) => x == null ? '?' : x.toStringAsFixed(4);
    if (offer.bandwidthDownCreditsPerGB == null && offer.bandwidthUpCreditsPerGB == null) {
      return 'Bandwidth: $kPriceUnavailable';
    }
    return '↓ ${v(offer.bandwidthDownCreditsPerGB)} · ↑ ${v(offer.bandwidthUpCreditsPerGB)} cr/GB (by usage)';
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
