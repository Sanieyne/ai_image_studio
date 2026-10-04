import 'package:flutter/material.dart';
import '../../../../theme/app_theme.dart';
import '../../data/models/cloud_model.dart';
import '../../data/services/cloud_api_service.dart';
import '../widgets/gpu_recommendation_card.dart';
import '../widgets/model_selector_widget.dart';
import '../widgets/storage_inspector_widget.dart';

class CloudManagementScreen extends StatefulWidget {
  final bool isDark;
  final Set<String>? initialSelectedModelIds;
  final int? initialStorageGB;
  final String? initialGpuTab;
  final String? initialSearchQuery;

  const CloudManagementScreen({
    super.key,
    required this.isDark,
    this.initialSelectedModelIds,
    this.initialStorageGB,
    this.initialGpuTab,
    this.initialSearchQuery,
  });

  @override
  State<CloudManagementScreen> createState() => _CloudManagementScreenState();
}

class _CloudManagementScreenState extends State<CloudManagementScreen> {
  final _cloudApi = CloudApiService.instance;

  bool _syncing = false;
  bool _backendOnline = false;
  late List<CloudModel> _models;
  Set<String> _selectedModelIds = {'sdxl-base-1.0'};
  RecommendationResult? _recommendation;
  MarketplaceRecommendedResult? _marketplaceResult;
  MarketplaceOffer? _selectedOffer;
  int _selectedStorageGB = 50;

  @override
  void initState() {
    super.initState();
    if (widget.initialSelectedModelIds != null) {
      _selectedModelIds = Set<String>.from(widget.initialSelectedModelIds!);
    }
    if (widget.initialStorageGB != null) {
      _selectedStorageGB = widget.initialStorageGB!;
    }
    _models = _cloudApi.fallbackModels;
    _recommendation = _cloudApi.calculateOfflineFallback(_selectedModelIds.toList());
    _loadCloudData();
  }

  Future<void> _loadCloudData() async {
    setState(() => _syncing = true);
    try {
      final results = await Future.wait([
        _cloudApi.checkHealth(),
        _cloudApi.fetchModels(),
        _cloudApi.calculateRecommendations(_selectedModelIds.toList()),
        _cloudApi.fetchRecommendedGpuOffers(_selectedModelIds.toList()),
      ]);

      if (!mounted) return;
      final online = results[0] as bool;
      final models = results[1] as List<CloudModel>;
      final rec = results[2] as RecommendationResult?;
      final market = results[3] as MarketplaceRecommendedResult?;

      setState(() {
        _backendOnline = online;
        if (models.isNotEmpty) _models = models;
        if (rec != null) _recommendation = rec;
        if (market != null) {
          _marketplaceResult = market;
          _selectedOffer ??= market.balancedOffer ?? market.allOffers.firstOrNull;
        }
        _syncing = false;
      });
    } catch (_) {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _onSelectionChanged(Set<String> newSelection) async {
    setState(() {
      _selectedModelIds = newSelection;
      _recommendation = _cloudApi.calculateOfflineFallback(newSelection.toList());
      _syncing = true;
    });

    try {
      final results = await Future.wait([
        _cloudApi.calculateRecommendations(newSelection.toList()),
        _cloudApi.fetchRecommendedGpuOffers(newSelection.toList()),
      ]);

      if (!mounted) return;
      final rec = results[0] as RecommendationResult?;
      final market = results[1] as MarketplaceRecommendedResult?;

      setState(() {
        if (rec != null) _recommendation = rec;
        if (market != null) {
          _marketplaceResult = market;
          _selectedOffer = market.balancedOffer ?? market.allOffers.firstOrNull;
        }
        _syncing = false;
      });
    } catch (_) {
      if (mounted) setState(() => _syncing = false);
    }
  }

  void _handleLaunchInstance([MarketplaceOffer? offer, int? storageGB]) {
    final effectiveStorageGB = storageGB ?? _selectedStorageGB;
    final primaryGpu = _recommendation?.compatibleGPUs.firstOrNull;
    final gpuName = offer?.gpuName ?? primaryGpu?.name ?? 'Cloud GPU';
    final creditsPerHour = offer?.totalCreditsPerHour ?? primaryGpu?.creditsPerHour ?? (0.44 * kVastPriceMarkup * kCreditsPerUsd);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: widget.isDark ? LuminaColors.darkSurface : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.rocket_launch_rounded, color: LuminaColors.primaryEnd),
            const SizedBox(width: 10),
            Text('Provision $gpuName'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Selected AI Models (${_selectedModelIds.length}):'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _selectedModelIds.map((id) {
                final model = _models.firstWhere((m) => m.modelId == id, orElse: () => CloudModel(modelId: id, displayName: id, mode: 'image', hfRepoId: '', sizeGB: 0, requiredVramGB: 0));
                return Chip(
                  label: Text(model.displayName, style: const TextStyle(fontSize: 11)),
                  backgroundColor: LuminaColors.infoBlue.withValues(alpha: 0.15),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            Text('Hourly Rate: ${creditsPerHour.toStringAsFixed(1)} credits / hr'),
            const SizedBox(height: 4),
            Text('Allocated Storage: $effectiveStorageGB GB Volume'),
            const SizedBox(height: 14),
            const Text(
              'The Cloud Orchestrator will allocate dedicated GPU instances, stream the model weights into your isolated volume, and connect your studio in seconds.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: LuminaColors.primaryEnd,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
            label: const Text('Confirm & Launch'),
            onPressed: () async {
              Navigator.of(ctx).pop();
              final targetOfferId = offer?.id.toString() ?? _selectedOffer?.id.toString();
              if (targetOfferId == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please select a GPU offer first.')),
                );
                return;
              }

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: LuminaColors.infoBlue,
                  content: Text('⚡ Requesting GPU instance ($gpuName)...'),
                  duration: const Duration(seconds: 4),
                ),
              );

              final result = await _cloudApi.rentGpuInstance(
                offerId: targetOfferId,
                selectedModelIds: _selectedModelIds.toList(),
                storageGB: effectiveStorageGB,
              );

              if (!mounted) return;
              if (result != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: LuminaColors.primaryEnd,
                    content: Text('🚀 Instance provisioned successfully! Bootstrapping engine with ${_selectedModelIds.length} models...'),
                    duration: const Duration(seconds: 6),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    backgroundColor: Colors.redAccent,
                    content: Text('Failed to rent instance. Check your balance or authentication.'),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final border = widget.isDark ? LuminaColors.darkBorder : LuminaColors.lightBorder;
    final surface = widget.isDark ? LuminaColors.darkSurface : Colors.white;
    final muted = widget.isDark ? LuminaColors.darkMuted : LuminaColors.lightMuted;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 850;

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Banner
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: (widget.isDark ? LuminaColors.darkSurface : Colors.white)
                      .withValues(alpha: widget.isDark ? 0.72 : 0.85),
                  border: Border.all(color: border),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: LuminaColors.primaryGradient,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.cloud_sync_rounded, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Lumina Cloud GPU Orchestrator',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Dynamic VRAM recommendation, multi-model storage footprinting & high-throughput cloud instances.',
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                      ],
                    ),
                    const Spacer(),
                    // Backend status pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: (_backendOnline ? Colors.green : Colors.amber).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: (_backendOnline ? Colors.green : Colors.amber).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.circle,
                            size: 8,
                            color: _backendOnline ? Colors.green : Colors.amber,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _backendOnline ? 'Cloud Cluster: Connected (EU-Central)' : 'Cloud Cluster: Connecting...',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _backendOnline ? Colors.green : Colors.amber,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      tooltip: 'Refresh Catalog & Recommendations',
                      onPressed: _loadCloudData,
                    ),
                  ],
                ),
              ),
              if (_syncing) ...[
                const SizedBox(height: 6),
                const ClipRRect(
                  borderRadius: BorderRadius.all(Radius.circular(2)),
                  child: LinearProgressIndicator(minHeight: 2.5),
                ),
                const SizedBox(height: 8),
              ] else ...[
                const SizedBox(height: 14),
              ],

              // Responsive Columns
              Expanded(
                child: isWide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Column 1: Model Selector (Flex 3)
                          Expanded(
                            flex: 3,
                            child: ModelSelectorWidget(
                              models: _models,
                              selectedModelIds: _selectedModelIds,
                              onSelectionChanged: _onSelectionChanged,
                              isDark: widget.isDark,
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Column 2: GPU Recommendation (Flex 4)
                          Expanded(
                            flex: 4,
                            child: GpuRecommendationCard(
                              result: _recommendation,
                              marketplaceResult: _marketplaceResult,
                              selectedOffer: _selectedOffer,
                              onSelectOffer: (offer) => setState(() => _selectedOffer = offer),
                              isDark: widget.isDark,
                              onLaunchInstance: _handleLaunchInstance,
                              initialTab: widget.initialGpuTab,
                              initialSearchQuery: widget.initialSearchQuery,
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Column 3: Storage & Telemetry Inspector (Flex 4) - Shown when models selected
                          Expanded(
                            flex: 4,
                            child: _selectedModelIds.isNotEmpty
                                ? StorageInspectorWidget(
                                    result: _recommendation,
                                    selectedOffer: _selectedOffer,
                                    initialStorageGB: _selectedStorageGB,
                                    onStorageChanged: (gb) => setState(() => _selectedStorageGB = gb),
                                    isDark: widget.isDark,
                                    onEvictModel: (modelId) {
                                      final next = Set<String>.from(_selectedModelIds)..remove(modelId);
                                      _onSelectionChanged(next);
                                    },
                                    onLaunchInstance: (offer, gb) => _handleLaunchInstance(offer, gb),
                                  )
                                : _buildTelemetryPlaceholder(border: border, surface: surface, muted: muted),
                          ),
                        ],
                      )
                    : DefaultTabController(
                        length: 3,
                        child: Column(
                          children: [
                            Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(
                                color: surface.withValues(alpha: widget.isDark ? 0.72 : 0.85),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: border),
                              ),
                              child: TabBar(
                                labelColor: LuminaColors.primaryEnd,
                                unselectedLabelColor: muted,
                                indicatorColor: LuminaColors.primaryEnd,
                                indicatorSize: TabBarIndicatorSize.tab,
                                tabs: const [
                                  Tab(icon: Icon(Icons.layers_rounded, size: 18), text: 'AI Models'),
                                  Tab(icon: Icon(Icons.memory_rounded, size: 18), text: 'GPU Marketplace'),
                                  Tab(icon: Icon(Icons.analytics_rounded, size: 18), text: 'Specs & Telemetry'),
                                ],
                              ),
                            ),
                            Expanded(
                              child: TabBarView(
                                children: [
                                  ModelSelectorWidget(
                                    models: _models,
                                    selectedModelIds: _selectedModelIds,
                                    onSelectionChanged: _onSelectionChanged,
                                    isDark: widget.isDark,
                                  ),
                                  GpuRecommendationCard(
                                    result: _recommendation,
                                    marketplaceResult: _marketplaceResult,
                                    selectedOffer: _selectedOffer,
                                    onSelectOffer: (offer) => setState(() => _selectedOffer = offer),
                                    isDark: widget.isDark,
                                    onLaunchInstance: _handleLaunchInstance,
                                    initialTab: widget.initialGpuTab,
                                    initialSearchQuery: widget.initialSearchQuery,
                                  ),
                                  _selectedModelIds.isNotEmpty
                                      ? StorageInspectorWidget(
                                          result: _recommendation,
                                          selectedOffer: _selectedOffer,
                                          initialStorageGB: _selectedStorageGB,
                                          onStorageChanged: (gb) => setState(() => _selectedStorageGB = gb),
                                          isDark: widget.isDark,
                                          onEvictModel: (modelId) {
                                            final next = Set<String>.from(_selectedModelIds)..remove(modelId);
                                            _onSelectionChanged(next);
                                          },
                                          onLaunchInstance: (offer, gb) => _handleLaunchInstance(offer, gb),
                                        )
                                      : _buildTelemetryPlaceholder(border: border, surface: surface, muted: muted),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTelemetryPlaceholder({
    required Color border,
    required Color surface,
    required Color muted,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: surface.withValues(alpha: widget.isDark ? 0.72 : 0.85),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: LuminaColors.infoBlue.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.analytics_outlined,
                size: 44,
                color: LuminaColors.infoBlue,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No Models Selected',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Select a model to see compatibility and streaming estimates',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: muted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: widget.isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.touch_app_rounded, size: 14, color: muted),
                  const SizedBox(width: 6),
                  Text(
                    'Choose models from the left catalog',
                    style: TextStyle(fontSize: 11.5, color: muted),
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
