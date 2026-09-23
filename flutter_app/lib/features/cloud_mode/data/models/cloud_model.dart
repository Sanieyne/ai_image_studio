import 'package:flutter/material.dart';

/// App execution mode: running on local hardware or remote cloud GPU
enum StudioExecutionMode {
  local,
  cloud;

  String get label => this == StudioExecutionMode.local ? 'Local Engine' : 'Cloud GPU';
  IconData get icon => this == StudioExecutionMode.local ? Icons.memory_rounded : Icons.cloud_outlined;
}

/// Catalog AI model representation
class CloudModel {
  final String modelId;
  final String displayName;
  final String mode;
  final String hfRepoId;
  final double sizeGB;
  final double requiredVramGB;
  final int defaultSteps;
  final double defaultGuidance;
  final bool isEnabled;

  const CloudModel({
    required this.modelId,
    required this.displayName,
    required this.mode,
    required this.hfRepoId,
    required this.sizeGB,
    required this.requiredVramGB,
    this.defaultSteps = 30,
    this.defaultGuidance = 5.0,
    this.isEnabled = true,
  });

  factory CloudModel.fromJson(Map<String, dynamic> json) {
    return CloudModel(
      modelId: json['modelId'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      mode: json['mode'] as String? ?? 'image',
      hfRepoId: json['hfRepoId'] as String? ?? '',
      sizeGB: (json['sizeGB'] as num?)?.toDouble() ?? 0.0,
      requiredVramGB: (json['requiredVramGB'] as num?)?.toDouble() ?? 0.0,
      defaultSteps: json['defaultSteps'] as int? ?? 30,
      defaultGuidance: (json['defaultGuidance'] as num?)?.toDouble() ?? 5.0,
      isEnabled: json['isEnabled'] as bool? ?? true,
    );
  }
}

/// Cloud GPU tier specification
class GpuTier {
  final String id;
  final String name;
  final double vramGB;
  final double ramGB;
  final double pricePerHour;
  final String tier;
  final List<String> tags;
  final bool canRun;
  final double headroomVramGB;
  final String fit; // 'optimal' | 'tight' | 'minimum'
  final String? reason;

  const GpuTier({
    required this.id,
    required this.name,
    required this.vramGB,
    required this.ramGB,
    required this.pricePerHour,
    required this.tier,
    required this.tags,
    this.canRun = true,
    this.headroomVramGB = 0,
    this.fit = 'optimal',
    this.reason,
  });

  factory GpuTier.fromJson(Map<String, dynamic> json) {
    return GpuTier(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      vramGB: (json['vramGB'] as num?)?.toDouble() ?? 0.0,
      ramGB: (json['ramGB'] as num?)?.toDouble() ?? 0.0,
      pricePerHour: (json['pricePerHour'] as num?)?.toDouble() ?? 0.0,
      tier: json['tier'] as String? ?? 'balanced',
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      canRun: json['canRun'] as bool? ?? true,
      headroomVramGB: (json['headroomVramGB'] as num?)?.toDouble() ?? 0.0,
      fit: json['fit'] as String? ?? 'optimal',
      reason: json['reason'] as String?,
    );
  }
}

/// Storage volume sizing plan
class StoragePlan {
  final String id;
  final String name;
  final double sizeGB;
  final double pricePerMonth;
  final double freeAfterGB;
  final bool fits;

  const StoragePlan({
    required this.id,
    required this.name,
    required this.sizeGB,
    required this.pricePerMonth,
    this.freeAfterGB = 0,
    this.fits = true,
  });

  factory StoragePlan.fromJson(Map<String, dynamic> json) {
    return StoragePlan(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      sizeGB: (json['sizeGB'] as num?)?.toDouble() ?? 0.0,
      pricePerMonth: (json['pricePerMonth'] as num?)?.toDouble() ?? 0.0,
      freeAfterGB: (json['freeAfterGB'] as num?)?.toDouble() ?? 0.0,
      fits: json['fits'] as bool? ?? true,
    );
  }
}

/// Sizing requirements calculations
class RecommendationRequirements {
  final int modelCount;
  final double totalModelSizeGB;
  final double baseOverheadGB;
  final double bufferGB;
  final double totalWithBufferGB;
  final double maxVramGB;
  final double minVramGB;

  const RecommendationRequirements({
    required this.modelCount,
    required this.totalModelSizeGB,
    required this.baseOverheadGB,
    required this.bufferGB,
    required this.totalWithBufferGB,
    required this.maxVramGB,
    required this.minVramGB,
  });

  factory RecommendationRequirements.fromJson(Map<String, dynamic> json) {
    return RecommendationRequirements(
      modelCount: json['modelCount'] as int? ?? 0,
      totalModelSizeGB: (json['totalModelSizeGB'] as num?)?.toDouble() ?? 0.0,
      baseOverheadGB: (json['baseOverheadGB'] as num?)?.toDouble() ?? 7.0,
      bufferGB: (json['bufferGB'] as num?)?.toDouble() ?? 0.0,
      totalWithBufferGB: (json['totalWithBufferGB'] as num?)?.toDouble() ?? 0.0,
      maxVramGB: (json['maxVramGB'] as num?)?.toDouble() ?? 0.0,
      minVramGB: (json['minVramGB'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Complete recommendation response
class RecommendationResult {
  final List<Map<String, dynamic>> selectedModels;
  final RecommendationRequirements requirements;
  final StoragePlan recommendedStorage;
  final List<GpuTier> compatibleGPUs;
  final List<String> warnings;
  final List<StoragePlan> allPlans;

  const RecommendationResult({
    required this.selectedModels,
    required this.requirements,
    required this.recommendedStorage,
    required this.compatibleGPUs,
    required this.warnings,
    required this.allPlans,
  });

  factory RecommendationResult.fromJson(Map<String, dynamic> json) {
    final selModels = (json['selectedModels'] as List<dynamic>?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ??
        [];

    final req = RecommendationRequirements.fromJson(
        Map<String, dynamic>.from(json['requirements'] as Map? ?? {}));

    final recStorage = StoragePlan.fromJson(
        Map<String, dynamic>.from(json['recommendedStorage'] as Map? ?? {}));

    final gpus = (json['compatibleGPUs'] as List<dynamic>?)
            ?.map((e) => GpuTier.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList() ??
        [];

    final warns = (json['warnings'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    final plans = (json['allPlans'] as List<dynamic>?)
            ?.map((e) => StoragePlan.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList() ??
        [];

    return RecommendationResult(
      selectedModels: selModels,
      requirements: req,
      recommendedStorage: recStorage,
      compatibleGPUs: gpus,
      warnings: warns,
      allPlans: plans,
    );
  }
}
