import 'package:flutter/material.dart';
import '../../../../theme/app_theme.dart';
import '../../data/models/cloud_model.dart';
import '../../data/services/cloud_api_service.dart';
import '../widgets/gpu_recommendation_card.dart';
import '../widgets/model_selector_widget.dart';
import '../widgets/storage_inspector_widget.dart';

class CloudManagementScreen extends StatefulWidget {
  final bool isDark;

  const CloudManagementScreen({super.key, required this.isDark});

  @override
  State<CloudManagementScreen> createState() => _CloudManagementScreenState();
}

class _CloudManagementScreenState extends State<CloudManagementScreen> {
  final _cloudApi = CloudApiService.instance;

  bool _loading = true;
  bool _backendOnline = false;
  List<CloudModel> _models = [];
  Set<String> _selectedModelIds = {'sdxl-base-1.0'};
  RecommendationResult? _recommendation;

  @override
  void initState() {
    super.initState();
    _loadCloudData();
  }

  Future<void> _loadCloudData() async {
    setState(() => _loading = true);
    final online = await _cloudApi.checkHealth();
    final models = await _cloudApi.fetchModels();
    final rec = await _cloudApi.calculateRecommendations(_selectedModelIds.toList());

    if (!mounted) return;
    setState(() {
      _backendOnline = online;
      _models = models;
      _recommendation = rec;
      _loading = false;
    });
  }

  Future<void> _onSelectionChanged(Set<String> newSelection) async {
    setState(() => _selectedModelIds = newSelection);
    final rec = await _cloudApi.calculateRecommendations(newSelection.toList());
    if (!mounted) return;
    setState(() => _recommendation = rec);
  }

  void _handleLaunchInstance() {
    final primaryGpu = _recommendation?.compatibleGPUs.firstOrNull;
    final gpuName = primaryGpu?.name ?? 'Cloud GPU';
    final price = primaryGpu?.pricePerHour ?? 0.44;

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
            Text('Hourly Rate: \$${price.toStringAsFixed(2)} / hr (~${(price * 200).toInt()} credits/hr)'),
            const SizedBox(height: 4),
            Text('Recommended Volume: ${_recommendation?.recommendedStorage.name ?? 'Starter 30GB'}'),
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
            onPressed: () {
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: LuminaColors.primaryEnd,
                  content: Text('⚡ Instance provision request sent for $gpuName with ${_selectedModelIds.length} models!'),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final border = widget.isDark ? LuminaColors.darkBorder : LuminaColors.lightBorder;
    final muted = widget.isDark ? LuminaColors.darkMuted : LuminaColors.lightMuted;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1050;

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
                            _backendOnline ? 'Cloud Cluster: Connected (EU-Central)' : 'Cloud Cluster: Offline',
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
              const SizedBox(height: 14),

              // Responsive Columns
              Expanded(
                child: isWide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Column 1: Model Selector (Flex 4)
                          Expanded(
                            flex: 4,
                            child: ModelSelectorWidget(
                              models: _models,
                              selectedModelIds: _selectedModelIds,
                              onSelectionChanged: _onSelectionChanged,
                              isDark: widget.isDark,
                            ),
                          ),
                          const SizedBox(width: 14),
                          // Column 2: GPU Recommendation (Flex 4)
                          Expanded(
                            flex: 4,
                            child: GpuRecommendationCard(
                              result: _recommendation,
                              isDark: widget.isDark,
                              onLaunchInstance: _handleLaunchInstance,
                            ),
                          ),
                          const SizedBox(width: 14),
                          // Column 3: Storage Volume Inspector (Flex 3)
                          Expanded(
                            flex: 3,
                            child: StorageInspectorWidget(
                              result: _recommendation,
                              isDark: widget.isDark,
                              onEvictModel: (modelId) {
                                final next = Set<String>.from(_selectedModelIds)..remove(modelId);
                                _onSelectionChanged(next);
                              },
                            ),
                          ),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: 1,
                            child: ModelSelectorWidget(
                              models: _models,
                              selectedModelIds: _selectedModelIds,
                              onSelectionChanged: _onSelectionChanged,
                              isDark: widget.isDark,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 1,
                            child: GpuRecommendationCard(
                              result: _recommendation,
                              isDark: widget.isDark,
                              onLaunchInstance: _handleLaunchInstance,
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
