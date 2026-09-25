import 'package:flutter/material.dart';

/// Pricing Policy: 50 credits per 1 USD, 25% markup (1.25x) on raw Vast.ai prices
const double kCreditsPerUsd = 50.0;
const double kVastPriceMarkup = 1.25;

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
      defaultSteps: (json['defaultSteps'] as num?)?.toInt() ?? 30,
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

  /// Hourly compute cost in credits (1 USD = 50 credits, with 25% markup on raw Vast.ai)
  double get creditsPerHour => (pricePerHour * kVastPriceMarkup * kCreditsPerUsd);
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

  /// Monthly storage plan price in credits (1 USD = 50 credits, with 25% markup)
  double get creditsPerMonth => (pricePerMonth * kVastPriceMarkup * kCreditsPerUsd);
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
      modelCount: (json['modelCount'] as num?)?.toInt() ?? 0,
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

/// Real-time live GPU marketplace bundle from Vast.ai
class MarketplaceOffer {
  final String id;
  final String provider;
  final String gpuName;
  final double vramGB;
  final int numGpus;
  final double totalFlops;
  final double pricePerHour;
  final double dphBase;
  final double storageCostPerHour;
  final double bandwidthCostPerGB;
  final double totalHourlyCost;
  final int inetUp;
  final int inetDown;
  final double reliability;
  final double cudaVersion;
  final String driverVersion;
  final String geolocation;
  final int directPortCount;
  final int cpuCores;
  final double ramGB;
  final int diskGB;
  final double dlperf;
  final bool verified;
  final bool rentable;
  final double headroomVramGB;
  final String fit; // 'optimal' | 'tight' | 'minimum'
  final String fitReason;
  final double estimatedDownloadTimeMinutes;
  final double? customCreditsPerHour;
  final double? customTotalCreditsPerHour;
  final double? customStorageCreditsPerHour;
  final double? customBandwidthCreditsPerGB;

  /// Hourly compute cost in credits (1 USD = 50 credits, 25% markup on raw Vast.ai)
  double get creditsPerHour =>
      customCreditsPerHour ?? (pricePerHour * kVastPriceMarkup * kCreditsPerUsd);

  /// Total hourly cost in credits (compute + storage)
  double get totalCreditsPerHour =>
      customTotalCreditsPerHour ?? (totalHourlyCost * kVastPriceMarkup * kCreditsPerUsd);

  /// Storage cost in credits per hour
  double get storageCreditsPerHour =>
      customStorageCreditsPerHour ?? (storageCostPerHour * kVastPriceMarkup * kCreditsPerUsd);

  /// Bandwidth egress cost in credits per GB
  double get bandwidthCreditsPerGB =>
      customBandwidthCreditsPerGB ?? (bandwidthCostPerGB * kVastPriceMarkup * kCreditsPerUsd);

  const MarketplaceOffer({
    required this.id,
    required this.provider,
    required this.gpuName,
    required this.vramGB,
    required this.numGpus,
    required this.totalFlops,
    required this.pricePerHour,
    required this.dphBase,
    required this.storageCostPerHour,
    required this.bandwidthCostPerGB,
    required this.totalHourlyCost,
    required this.inetUp,
    required this.inetDown,
    required this.reliability,
    required this.cudaVersion,
    required this.driverVersion,
    required this.geolocation,
    required this.directPortCount,
    required this.cpuCores,
    required this.ramGB,
    required this.diskGB,
    required this.dlperf,
    required this.verified,
    required this.rentable,
    required this.headroomVramGB,
    required this.fit,
    required this.fitReason,
    required this.estimatedDownloadTimeMinutes,
    this.customCreditsPerHour,
    this.customTotalCreditsPerHour,
    this.customStorageCreditsPerHour,
    this.customBandwidthCreditsPerGB,
  });

  factory MarketplaceOffer.fromJson(Map<String, dynamic> json) {
    return MarketplaceOffer(
      id: json['id']?.toString() ?? '',
      provider: json['provider']?.toString() ?? 'vastai',
      gpuName: json['gpuName']?.toString() ?? 'GPU',
      vramGB: (json['vramGB'] as num?)?.toDouble() ?? 0.0,
      numGpus: (json['numGpus'] as num?)?.toInt() ?? 1,
      totalFlops: (json['totalFlops'] as num?)?.toDouble() ?? 0.0,
      pricePerHour: (json['pricePerHour'] as num?)?.toDouble() ?? 0.0,
      dphBase: (json['dphBase'] as num?)?.toDouble() ?? 0.0,
      storageCostPerHour: (json['storageCostPerHour'] as num?)?.toDouble() ?? 0.0,
      bandwidthCostPerGB: (json['bandwidthCostPerGB'] as num?)?.toDouble() ?? 0.02,
      totalHourlyCost: (json['totalHourlyCost'] as num?)?.toDouble() ?? 0.0,
      inetUp: (json['inetUp'] as num?)?.toInt() ?? 100,
      inetDown: (json['inetDown'] as num?)?.toInt() ?? 250,
      reliability: (json['reliability'] as num?)?.toDouble() ?? 0.98,
      cudaVersion: (json['cudaVersion'] as num?)?.toDouble() ?? 12.4,
      driverVersion: json['driverVersion']?.toString() ?? '550.54.14',
      geolocation: json['geolocation']?.toString() ?? 'Global',
      directPortCount: (json['directPortCount'] as num?)?.toInt() ?? 1,
      cpuCores: (json['cpuCores'] as num?)?.toInt() ?? 8,
      ramGB: (json['ramGB'] as num?)?.toDouble() ?? 32.0,
      diskGB: (json['diskGB'] as num?)?.toInt() ?? 100,
      dlperf: (json['dlperf'] as num?)?.toDouble() ?? 30.0,
      verified: json['verified'] as bool? ?? true,
      rentable: json['rentable'] as bool? ?? true,
      headroomVramGB: (json['headroomVramGB'] as num?)?.toDouble() ?? 0.0,
      fit: json['fit']?.toString() ?? 'optimal',
      fitReason: json['fitReason']?.toString() ?? '',
      estimatedDownloadTimeMinutes: (json['estimatedDownloadTimeMinutes'] as num?)?.toDouble() ?? 2.5,
      customCreditsPerHour: (json['creditsPerHour'] as num?)?.toDouble(),
      customTotalCreditsPerHour: (json['totalCreditsPerHour'] as num?)?.toDouble(),
      customStorageCreditsPerHour: (json['storageCreditsPerHour'] as num?)?.toDouble(),
      customBandwidthCreditsPerGB: (json['bandwidthCreditsPerGB'] as num?)?.toDouble(),
    );
  }
}

/// Ranked recommendations from live marketplace
class MarketplaceRecommendedResult {
  final Map<String, dynamic> requirements;
  final MarketplaceOffer? cheapestOffer;
  final MarketplaceOffer? fastestOffer;
  final MarketplaceOffer? mostReliableOffer;
  final MarketplaceOffer? balancedOffer;
  final List<MarketplaceOffer> allOffers;

  const MarketplaceRecommendedResult({
    required this.requirements,
    this.cheapestOffer,
    this.fastestOffer,
    this.mostReliableOffer,
    this.balancedOffer,
    required this.allOffers,
  });

  factory MarketplaceRecommendedResult.fromJson(Map<String, dynamic> json) {
    final all = (json['allOffers'] as List<dynamic>?)
            ?.map((e) => MarketplaceOffer.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList() ??
        [];

    final cheapest = json['cheapestOffer'] != null
        ? MarketplaceOffer.fromJson(Map<String, dynamic>.from(json['cheapestOffer'] as Map))
        : null;

    final fastest = json['fastestOffer'] != null
        ? MarketplaceOffer.fromJson(Map<String, dynamic>.from(json['fastestOffer'] as Map))
        : null;

    final mostReliable = json['mostReliableOffer'] != null
        ? MarketplaceOffer.fromJson(Map<String, dynamic>.from(json['mostReliableOffer'] as Map))
        : null;

    final balanced = json['balancedOffer'] != null
        ? MarketplaceOffer.fromJson(Map<String, dynamic>.from(json['balancedOffer'] as Map))
        : null;

    return MarketplaceRecommendedResult(
      requirements: Map<String, dynamic>.from(json['requirements'] as Map? ?? {}),
      cheapestOffer: cheapest,
      fastestOffer: fastest,
      mostReliableOffer: mostReliable,
      balancedOffer: balanced,
      allOffers: all,
    );
  }
}

