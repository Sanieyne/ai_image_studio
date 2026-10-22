import 'package:flutter/material.dart';

/// Prices are computed by the server only (pricingService.priceOffer). The app
/// displays them and shows [kPriceUnavailable] when one is missing; it never
/// derives a price itself.
const String kPriceUnavailable = 'price unavailable';

/// "4.62 credits/hr", or "price unavailable" when the server sent no price.
/// "~2.7 min", "<1 min", or "—" when unknown; the card and the panel both use it.
String formatDownloadMinutes(double? minutes) {
  if (minutes == null) return '—';
  if (minutes < 1) return '<1 min';
  return '~${minutes.toStringAsFixed(1)} min';
}

String formatCreditsRate(double? credits, String unit, {int decimals = 2}) =>
    credits == null ? kPriceUnavailable : '${credits.toStringAsFixed(decimals)} $unit';

/// App execution mode: running on local hardware or remote cloud GPU
enum StudioExecutionMode {
  local,
  cloud;

  String get label => this == StudioExecutionMode.local ? 'Local Engine' : 'Rent GPU';
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
  final double? customCreditsPerHour;

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
    this.customCreditsPerHour,
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
      customCreditsPerHour: (json['creditsPerHour'] as num?)?.toDouble(),
    );
  }

  /// Server-provided typical hourly compute cost in credits; null when the server sent none.
  double? get creditsPerHour => customCreditsPerHour;
}

/// Storage volume sizing plan
class StoragePlan {
  final String id;
  final String name;
  final double sizeGB;
  final double pricePerMonth;
  final double freeAfterGB;
  final bool fits;
  final double? customCreditsPerMonth;
  final double? customCreditsPerHour;

  const StoragePlan({
    required this.id,
    required this.name,
    required this.sizeGB,
    required this.pricePerMonth,
    this.freeAfterGB = 0,
    this.fits = true,
    this.customCreditsPerMonth,
    this.customCreditsPerHour,
  });

  factory StoragePlan.fromJson(Map<String, dynamic> json) {
    return StoragePlan(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      sizeGB: (json['sizeGB'] as num?)?.toDouble() ?? 0.0,
      pricePerMonth: (json['pricePerMonth'] as num?)?.toDouble() ?? 0.0,
      freeAfterGB: (json['freeAfterGB'] as num?)?.toDouble() ?? 0.0,
      fits: json['fits'] as bool? ?? true,
      customCreditsPerMonth: (json['creditsPerMonth'] as num?)?.toDouble(),
      customCreditsPerHour: (json['creditsPerHour'] as num?)?.toDouble(),
    );
  }

  /// Server-provided monthly storage plan price in credits; null when the server sent none.
  double? get creditsPerMonth => customCreditsPerMonth;

  /// Server-provided hourly storage cost in credits; null when the server sent none.
  double? get creditsPerHour => customCreditsPerHour;
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

/// Real-time live GPU marketplace bundle from Vast.ai.
///
/// Prices are credits from the server, for [storageGB] of storage; null when the
/// server could not price the offer. Bandwidth is billed by usage, separately.
class MarketplaceOffer {
  final String id;
  final String provider;
  final String gpuName;
  final double vramGB;
  final int numGpus;
  final double totalFlops;
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
  /// Minutes to download the selected models at this host's speed; null when
  /// no model is selected. Show it with [formatDownloadMinutes].
  final double? estimatedDownloadTimeMinutes;

  /// Storage size (GB) the prices below are for.
  final int? storageGB;
  final double? computeCreditsPerHour;
  final double? storageCreditsPerGBMonth;
  final double? storageCreditsPerHour;

  /// Compute + storage for [storageGB]: what the Rent button, the confirmation
  /// dialog and billing use.
  final double? totalCreditsPerHour;
  final double? bandwidthDownCreditsPerGB;
  final double? bandwidthUpCreditsPerGB;

  bool get priceAvailable => totalCreditsPerHour != null;

  const MarketplaceOffer({
    required this.id,
    required this.provider,
    required this.gpuName,
    required this.vramGB,
    required this.numGpus,
    required this.totalFlops,
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
    this.storageGB,
    this.computeCreditsPerHour,
    this.storageCreditsPerGBMonth,
    this.storageCreditsPerHour,
    this.totalCreditsPerHour,
    this.bandwidthDownCreditsPerGB,
    this.bandwidthUpCreditsPerGB,
  });

  factory MarketplaceOffer.fromJson(Map<String, dynamic> json) {
    double? n(String key) => (json[key] as num?)?.toDouble();
    final priced = json['priceAvailable'] != false;
    return MarketplaceOffer(
      id: json['id']?.toString() ?? '',
      provider: json['provider']?.toString() ?? 'vastai',
      gpuName: json['gpuName']?.toString() ?? 'GPU',
      vramGB: (json['vramGB'] as num?)?.toDouble() ?? 0.0,
      numGpus: (json['numGpus'] as num?)?.toInt() ?? 1,
      totalFlops: (json['totalFlops'] as num?)?.toDouble() ?? 0.0,
      inetUp: (json['inetUp'] as num?)?.toInt() ?? 0,
      inetDown: (json['inetDown'] as num?)?.toInt() ?? 0,
      reliability: (json['reliability'] as num?)?.toDouble() ?? 0.0,
      cudaVersion: (json['cudaVersion'] as num?)?.toDouble() ?? 0.0,
      driverVersion: json['driverVersion']?.toString() ?? '',
      geolocation: json['geolocation']?.toString() ?? '',
      directPortCount: (json['directPortCount'] as num?)?.toInt() ?? 0,
      cpuCores: (json['cpuCores'] as num?)?.toInt() ?? 0,
      ramGB: (json['ramGB'] as num?)?.toDouble() ?? 0.0,
      diskGB: (json['diskGB'] as num?)?.toInt() ?? 0,
      dlperf: (json['dlperf'] as num?)?.toDouble() ?? 0.0,
      verified: json['verified'] as bool? ?? false,
      rentable: json['rentable'] as bool? ?? true,
      headroomVramGB: (json['headroomVramGB'] as num?)?.toDouble() ?? 0.0,
      fit: json['fit']?.toString() ?? 'optimal',
      fitReason: json['fitReason']?.toString() ?? '',
      estimatedDownloadTimeMinutes: (json['estimatedDownloadTimeMinutes'] as num?)?.toDouble(),
      storageGB: (json['storageGB'] as num?)?.toInt(),
      // Older servers send creditsPerHour / bandwidthCreditsPerGB only.
      computeCreditsPerHour: priced ? (n('computeCreditsPerHour') ?? n('creditsPerHour')) : null,
      storageCreditsPerGBMonth: priced ? n('storageCreditsPerGBMonth') : null,
      storageCreditsPerHour: priced ? n('storageCreditsPerHour') : null,
      totalCreditsPerHour: priced ? n('totalCreditsPerHour') : null,
      bandwidthDownCreditsPerGB: n('bandwidthDownCreditsPerGB') ?? n('bandwidthCreditsPerGB'),
      bandwidthUpCreditsPerGB: n('bandwidthUpCreditsPerGB'),
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

/// Server Pricing & Token Value Policy
class PricingPolicyConfig {
  final double tokenValue;
  final double creditsPerUsd;
  final double markupPercentage;
  final double markupMultiplier;
  final double minLaunchCredits;
  final String? notes;

  const PricingPolicyConfig({
    this.tokenValue = 50.0,
    this.creditsPerUsd = 50.0,
    this.markupPercentage = 25.0,
    this.markupMultiplier = 1.25,
    this.minLaunchCredits = 10.0,
    this.notes,
  });

  factory PricingPolicyConfig.fromJson(Map<String, dynamic> json) {
    final token = (json['tokenValue'] as num?)?.toDouble() ?? (json['creditsPerUsd'] as num?)?.toDouble() ?? 50.0;
    final markup = (json['markupPercentage'] as num?)?.toDouble() ?? 25.0;
    return PricingPolicyConfig(
      tokenValue: token,
      creditsPerUsd: token,
      markupPercentage: markup,
      markupMultiplier: (json['markupMultiplier'] as num?)?.toDouble() ?? (1.0 + markup / 100.0),
      minLaunchCredits: (json['minLaunchCredits'] as num?)?.toDouble() ?? 10.0,
      notes: json['notes'] as String?,
    );
  }
}

/// Price of one offer for one storage size, from GET /gpu/pricing/estimate.
/// [totalCreditsPerHour] is the same figure the offer card shows for that size.
class LivePricingEstimate {
  final String offerId;
  final String gpuName;
  final int storageGB;
  final bool priceAvailable;
  final double? computeCreditsPerHour;
  final double? storageCreditsPerGBMonth;
  final double? storageCreditsPerHour;
  final double? totalCreditsPerHour;
  final double? bandwidthDownCreditsPerGB;
  final double? bandwidthUpCreditsPerGB;

  const LivePricingEstimate({
    required this.offerId,
    required this.gpuName,
    required this.storageGB,
    required this.priceAvailable,
    this.computeCreditsPerHour,
    this.storageCreditsPerGBMonth,
    this.storageCreditsPerHour,
    this.totalCreditsPerHour,
    this.bandwidthDownCreditsPerGB,
    this.bandwidthUpCreditsPerGB,
  });

  factory LivePricingEstimate.fromJson(Map<String, dynamic> json) {
    double? n(String key) => (json[key] as num?)?.toDouble();
    final total = n('totalCreditsPerHour');
    return LivePricingEstimate(
      offerId: json['offerId']?.toString() ?? '',
      gpuName: json['gpuName']?.toString() ?? '',
      storageGB: (json['storageGB'] as num?)?.toInt() ?? 0,
      priceAvailable: json['priceAvailable'] != false && total != null,
      computeCreditsPerHour: n('computeCreditsPerHour'),
      storageCreditsPerGBMonth: n('storageCreditsPerGBMonth'),
      storageCreditsPerHour: n('storageCreditsPerHour'),
      totalCreditsPerHour: total,
      bandwidthDownCreditsPerGB: n('bandwidthDownCreditsPerGB'),
      bandwidthUpCreditsPerGB: n('bandwidthUpCreditsPerGB'),
    );
  }
}

/// Whether new GPU rentals are open, from GET /gpu/rentals/status.
class RentalsStatus {
  final bool rentalsEnabled;
  final String? message;

  const RentalsStatus({required this.rentalsEnabled, this.message});

  factory RentalsStatus.fromJson(Map<String, dynamic> json) => RentalsStatus(
        rentalsEnabled: json['rentalsEnabled'] == true,
        message: json['message'] as String?,
      );
}
