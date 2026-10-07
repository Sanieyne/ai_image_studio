import 'dart:async';

import 'package:flutter/material.dart';
import '../../../../services/auth_service.dart';
import '../../../../theme/app_theme.dart';
import '../../../../widgets/app_toast.dart';
import '../../data/models/cloud_model.dart';
import '../../data/services/cloud_api_service.dart';
import '../widgets/active_instances_panel.dart';
import '../widgets/gpu_recommendation_card.dart';
import '../widgets/model_selector_widget.dart';
import '../widgets/storage_inspector_widget.dart';
import 'instance_provisioning_screen.dart';

class CloudManagementScreen extends StatefulWidget {
  final bool isDark;
  final Set<String>? initialSelectedModelIds;
  final int? initialStorageGB;
  final String? initialGpuTab;
  final String? initialSearchQuery;
  final VoidCallback? onReturnToStudio;

  const CloudManagementScreen({
    super.key,
    required this.isDark,
    this.initialSelectedModelIds,
    this.initialStorageGB,
    this.initialGpuTab,
    this.initialSearchQuery,
    this.onReturnToStudio,
  });

  @override
  State<CloudManagementScreen> createState() => _CloudManagementScreenState();
}

class _CloudManagementScreenState extends State<CloudManagementScreen> {
  final _cloudApi = CloudApiService.instance;

  bool _syncing = false;
  bool _backendOnline = false;
  late List<CloudModel> _models;
  Set<String> _selectedModelIds = {};
  RecommendationResult? _recommendation;
  MarketplaceRecommendedResult? _marketplaceResult;
  MarketplaceOffer? _selectedOffer;
  int _selectedStorageGB = 50;
  RentalsStatus? _rentals;
  List<Map<String, dynamic>> _activeInstances = const [];
  final Set<String> _stoppingIds = {};

  /// Why renting is off right now, or null. Unknown status does not block:
  /// the server refuses a paused rental anyway.
  String? get _rentDisabledReason {
    final r = _rentals;
    if (r == null || r.rentalsEnabled) return null;
    return r.message ?? 'Cloud GPU rentals are paused.';
  }

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
    if (_selectedModelIds.isNotEmpty) {
      _recommendation = _cloudApi.calculateOfflineFallback(_selectedModelIds.toList());
    }
    _loadCloudData();
  }

  Future<void> _loadCloudData() async {
    setState(() => _syncing = true);
    try {
      _refreshRentalsAndInstances();
      final results = await Future.wait([
        _cloudApi.checkHealth(),
        _cloudApi.fetchModels(),
        _cloudApi.calculateRecommendations(_selectedModelIds.toList()),
        _cloudApi.fetchRecommendedGpuOffers(_selectedModelIds.toList(), storageGB: _selectedStorageGB),
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
          _applyMarket(market);
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
      _recommendation = newSelection.isNotEmpty
          ? _cloudApi.calculateOfflineFallback(newSelection.toList())
          : null;
      _syncing = true;
    });

    try {
      final results = await Future.wait([
        _cloudApi.calculateRecommendations(newSelection.toList()),
        _cloudApi.fetchRecommendedGpuOffers(newSelection.toList(), storageGB: _selectedStorageGB),
      ]);

      if (!mounted) return;
      final rec = results[0] as RecommendationResult?;
      final market = results[1] as MarketplaceRecommendedResult?;

      setState(() {
        if (rec != null) _recommendation = rec;
        if (market != null) {
          _applyMarket(market);
        }
        _syncing = false;
      });
    } catch (_) {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _refreshRentalsAndInstances() async {
    final results = await Future.wait([
      _cloudApi.fetchRentalsStatus(),
      _cloudApi.fetchMyInstances(),
    ]);
    if (!mounted) return;
    setState(() {
      _rentals = results[0] as RentalsStatus?;
      final instances = results[1] as List<Map<String, dynamic>>?;
      if (instances != null) _activeInstances = instances;
    });
  }

  /// Stops an instance after the panel's confirmation.
  Future<void> _stopActiveInstance(Map<String, dynamic> instance) async {
    final id = (instance['_id'] ?? instance['id'] ?? '').toString();
    if (id.isEmpty) return;
    final gpu = instance['gpuType']?.toString() ?? 'GPU';
    setState(() => _stoppingIds.add(id));
    final result = await _cloudApi.stopInstance(id);
    if (!mounted) return;
    setState(() => _stoppingIds.remove(id));
    if (result == null) {
      AppToast.showInfo(context, title: 'Could not stop the GPU',
          message: _cloudApi.lastStopError ?? 'Try again in a moment.');
    } else {
      AuthService.instance.refreshProfile();
      AppToast.showSuccess(context, title: 'GPU stopped', message: '$gpu was stopped.');
    }
    await _refreshRentalsAndInstances();
  }

  void _openInstance(Map<String, dynamic> instance) {
    final id = (instance['_id'] ?? instance['id'] ?? '').toString();
    if (id.isEmpty) return;
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (ctx) => InstanceProvisioningScreen(
            instanceId: id,
            gpuName: instance['gpuType']?.toString() ?? 'Cloud GPU',
            selectedModelIds: (instance['modelsRequested'] as List?)?.map((e) => e.toString()).toList() ?? const [],
            isDark: widget.isDark,
          ),
        ))
        .then((_) => _refreshRentalsAndInstances());
  }

  /// Stores new offers and keeps the selected offer, now priced for the new size.
  void _applyMarket(MarketplaceRecommendedResult market) {
    _marketplaceResult = market;
    final selectedId = _selectedOffer?.id;
    if (selectedId != null) {
      for (final o in market.allOffers) {
        if (o.id == selectedId) {
          _selectedOffer = o;
          break;
        }
      }
    }
  }

  Timer? _storageRepriceTimer;

  /// Offers are priced by the server for one storage size; refetch when it changes.
  void _onStorageChanged(int gb) {
    setState(() => _selectedStorageGB = gb);
    _storageRepriceTimer?.cancel();
    _storageRepriceTimer = Timer(const Duration(milliseconds: 400), () async {
      final market = await _cloudApi.fetchRecommendedGpuOffers(
        _selectedModelIds.toList(),
        storageGB: gb,
      );
      if (!mounted || market == null || gb != _selectedStorageGB) return;
      setState(() => _applyMarket(market));
    });
  }

  @override
  void dispose() {
    _storageRepriceTimer?.cancel();
    super.dispose();
  }

  Future<void> _handleLaunchInstance([MarketplaceOffer? offer, int? storageGB]) async {
    final effectiveOffer = offer ?? _selectedOffer;
    if (effectiveOffer == null || _selectedModelIds.isEmpty) {
      if (_selectedModelIds.isEmpty) {
        AppToast.showInfo(
          context,
          title: 'Select Model',
          message: 'Please select at least one AI model before renting.',
        );
      } else {
        AppToast.showInfo(
          context,
          title: 'Select GPU Offer',
          message: 'Please click to select a GPU offer first.',
        );
      }
      return;
    }

    final paused = _rentDisabledReason;
    if (paused != null) {
      AppToast.showInfo(context, title: 'Rentals paused', message: paused);
      return;
    }
    final effectiveStorageGB = storageGB ?? _selectedStorageGB;
    final gpuName = effectiveOffer.gpuName;
    // The rate shown here is the server's price for this offer and storage size,
    // the same figure the offer card, the side panel and billing use.
    final estimate = await _cloudApi.estimateStoragePricing(
      offerId: effectiveOffer.id,
      storageGB: effectiveStorageGB,
    );
    if (!mounted) return;
    final creditsPerHour = estimate?.totalCreditsPerHour;
    if (creditsPerHour == null) {
      AppToast.showInfo(
        context,
        title: 'Price unavailable',
        message: 'Could not get a price for this GPU right now. Try again or choose another offer.',
      );
      return;
    }

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
            Text('Hourly Rate: ${formatCreditsRate(creditsPerHour, 'credits / hr')} (GPU + $effectiveStorageGB GB storage)'),
            if (estimate?.bandwidthDownCreditsPerGB != null || estimate?.bandwidthUpCreditsPerGB != null) ...[
              const SizedBox(height: 4),
              Text(
                'Bandwidth, billed by usage: ↓ ${formatCreditsRate(estimate?.bandwidthDownCreditsPerGB, 'cr/GB', decimals: 4)}'
                ' · ↑ ${formatCreditsRate(estimate?.bandwidthUpCreditsPerGB, 'cr/GB', decimals: 4)}',
                style: const TextStyle(fontSize: 12),
              ),
            ],
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
              final targetOfferId = effectiveOffer.id.toString();

              AppToast.showInfo(
                context,
                title: 'Requesting GPU',
                message: 'Requesting GPU instance ($gpuName)...',
              );

              final result = await _cloudApi.rentGpuInstance(
                offerId: targetOfferId,
                selectedModelIds: _selectedModelIds.toList(),
                storageGB: effectiveStorageGB,
              );

              if (!mounted) return;
              if (result != null) {
                AuthService.instance.refreshProfile();
                AppToast.showSuccess(
                  context,
                  title: 'Instance Provisioned',
                  message: '🚀 Instance provisioned successfully! Connecting to stream...',
                );

                final instanceId = (result['_id'] ?? result['id'] ?? '').toString();
                if (instanceId.isNotEmpty) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (ctx) => InstanceProvisioningScreen(
                        instanceId: instanceId,
                        gpuName: gpuName,
                        selectedModelIds: _selectedModelIds.toList(),
                        isDark: widget.isDark,
                        onReturnToStudio: widget.onReturnToStudio,
                      ),
                    ),
                  );
                }
              } else {
                final errorMsg = _cloudApi.lastRentError ??
                    'Failed to rent instance. Check your balance or authentication.';
                
                // If offer was taken / unavailable, deselect it and auto-refresh live inventory
                if (errorMsg.contains('just rented') || errorMsg.contains('not available') || errorMsg.contains('no_such_ask')) {
                  setState(() => _selectedOffer = null);
                  _loadCloudData();
                  AppToast.showError(
                    context,
                    title: 'GPU Unavailable',
                    message: 'This GPU was just rented by someone else. Refreshing live offers for you...',
                  );
                } else {
                  AppToast.showError(
                    context,
                    title: 'GPU Launch Failed',
                    message: errorMsg,
                  );
                }
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
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Cosmic-Gen Cloud GPU Orchestrator',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Dynamic VRAM recommendation, multi-model storage footprinting & high-throughput cloud instances.',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: muted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
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

              if (_rentDisabledReason != null)
                Container(
                  key: const ValueKey('rentals_paused_banner'),
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: LuminaColors.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: LuminaColors.amber.withValues(alpha: 0.35)),
                  ),
                  child: Text(
                    '${_rentDisabledReason!} You can still browse GPUs and prices.',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ),
              if (_activeInstances.isNotEmpty)
                ActiveInstancesPanel(
                  instances: _activeInstances,
                  stoppingIds: _stoppingIds,
                  isDark: widget.isDark,
                  onStop: _stopActiveInstance,
                  onOpen: _openInstance,
                ),

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
                              hasModelSelection: _selectedModelIds.isNotEmpty,
                              onSelectOffer: (offer) => setState(() => _selectedOffer = offer),
                              isDark: widget.isDark,
                              onLaunchInstance: _handleLaunchInstance,
                              rentDisabledReason: _rentDisabledReason,
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
                                    onStorageChanged: _onStorageChanged,
                                    isDark: widget.isDark,
                                    onEvictModel: (modelId) {
                                      final next = Set<String>.from(_selectedModelIds)..remove(modelId);
                                      _onSelectionChanged(next);
                                    },
                                    onLaunchInstance: (offer, gb) => _handleLaunchInstance(offer, gb),
                                    rentDisabledReason: _rentDisabledReason,
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
                                    hasModelSelection: _selectedModelIds.isNotEmpty,
                                    onSelectOffer: (offer) => setState(() => _selectedOffer = offer),
                                    isDark: widget.isDark,
                                    onLaunchInstance: _handleLaunchInstance,
                                    rentDisabledReason: _rentDisabledReason,
                                    initialTab: widget.initialGpuTab,
                                    initialSearchQuery: widget.initialSearchQuery,
                                  ),
                                  _selectedModelIds.isNotEmpty
                                      ? StorageInspectorWidget(
                                          result: _recommendation,
                                          selectedOffer: _selectedOffer,
                                          initialStorageGB: _selectedStorageGB,
                                          onStorageChanged: _onStorageChanged,
                                          isDark: widget.isDark,
                                          onEvictModel: (modelId) {
                                            final next = Set<String>.from(_selectedModelIds)..remove(modelId);
                                            _onSelectionChanged(next);
                                          },
                                          onLaunchInstance: (offer, gb) => _handleLaunchInstance(offer, gb),
                                          rentDisabledReason: _rentDisabledReason,
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
                  Flexible(
                    child: Text(
                      'Choose models from the left catalog',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: muted),
                    ),
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
