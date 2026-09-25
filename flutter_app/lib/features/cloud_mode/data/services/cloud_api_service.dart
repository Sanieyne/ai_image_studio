import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/cloud_model.dart';

/// Service interfacing with the AI Image Studio Cloud Backend (Contabo VPS & Vast.ai Provisioner)
class CloudApiService {
  static final CloudApiService instance = CloudApiService._();
  CloudApiService._();
  factory CloudApiService() => instance;

  String baseUrl = 'https://nass-works.com/ai-api/api/v1';

  /// Check connectivity to remote Cloud Orchestrator backend
  Future<bool> checkHealth() async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 4));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Retrieve catalog models with optional filtering by mode or query
  Future<List<CloudModel>> fetchModels({String? mode, String? search}) async {
    try {
      final queryParams = <String, String>{};
      if (mode != null && mode.isNotEmpty && mode.toLowerCase() != 'all') {
        queryParams['mode'] = mode.toLowerCase();
      }
      if (search != null && search.isNotEmpty) {
        queryParams['search'] = search;
      }

      final uri = Uri.parse('$baseUrl/models').replace(
        queryParameters: queryParams.isEmpty ? null : queryParams,
      );

      final res = await http.get(uri).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final list = data['data'] as List<dynamic>? ?? [];
        return list
            .map((item) => CloudModel.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList();
      }
    } catch (e) {
      // Fallback: return default models if network unreachable
    }
    return _fallbackModels;
  }

  /// Query the backend recommendation engine for selected models
  Future<RecommendationResult?> calculateRecommendations(List<String> modelIds) async {
    if (modelIds.isEmpty) return null;
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/models/recommend'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'modelIds': modelIds}),
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final data = body['data'] as Map<String, dynamic>;
        return RecommendationResult.fromJson(data);
      }
    } catch (e) {
      // Return local fallback calculation if offline
    }
    return _calculateOfflineFallback(modelIds);
  }

  /// Query live Vast.ai marketplace GPU offers for current model selection
  Future<List<MarketplaceOffer>> fetchGpuOffers({
    List<String>? selectedModelIds,
    double? minVramGB,
    double? maxPrice,
    int limit = 20,
    String orderBy = 'price',
  }) async {
    try {
      final queryParams = <String, String>{
        'limit': limit.toString(),
        'orderBy': orderBy,
      };
      if (selectedModelIds != null && selectedModelIds.isNotEmpty) {
        queryParams['selectedModelIds'] = selectedModelIds.join(',');
      }
      if (minVramGB != null && minVramGB > 0) {
        queryParams['minVramGB'] = minVramGB.toString();
      }
      if (maxPrice != null && maxPrice > 0) {
        queryParams['maxPrice'] = maxPrice.toString();
      }

      final uri = Uri.parse('$baseUrl/gpu/offers').replace(queryParameters: queryParams);
      final res = await http.get(uri).timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final data = body['data'] as Map<String, dynamic>;
        final offersList = data['offers'] as List<dynamic>? ?? [];
        return offersList
            .map((item) => MarketplaceOffer.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList();
      }
    } catch (e) {
      debugPrint('[CloudApiService] fetchGpuOffers error: $e');
    }
    return [];
  }

  /// Query ranked GPU recommendations (cheapest, fastest, most reliable, balanced)
  Future<MarketplaceRecommendedResult?> fetchRecommendedGpuOffers(List<String> modelIds) async {
    try {
      final uri = Uri.parse('$baseUrl/gpu/recommended').replace(
        queryParameters: {'modelIds': modelIds.join(',')},
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final data = body['data'] as Map<String, dynamic>;
        return MarketplaceRecommendedResult.fromJson(data);
      }
    } catch (e) {
      debugPrint('[CloudApiService] fetchRecommendedGpuOffers error: $e');
    }
    return null;
  }

  /// Expose fallback models for instant zero-latency UI initialization
  List<CloudModel> get fallbackModels => _fallbackModels;

  /// Local fallback calculation when backend is momentarily offline or in airplane mode
  RecommendationResult calculateOfflineFallback(List<String> modelIds) => _calculateOfflineFallback(modelIds);

  /// Local fallback calculation when backend is momentarily offline or in airplane mode
  RecommendationResult _calculateOfflineFallback(List<String> modelIds) {
    final selected = _fallbackModels.where((m) => modelIds.contains(m.modelId)).toList();
    final totalSize = selected.fold<double>(0, (sum, m) => sum + m.sizeGB);
    final maxVram = selected.isEmpty ? 12.0 : selected.map((m) => m.requiredVramGB).reduce((a, b) => a > b ? a : b);
    final minVram = selected.isEmpty ? 12.0 : selected.map((m) => m.requiredVramGB).reduce((a, b) => a < b ? a : b);
    final buffer = totalSize * 0.3;
    final totalWithBuffer = totalSize + 7.0 + buffer;

    return RecommendationResult(
      selectedModels: selected.map((m) => {
        'modelId': m.modelId,
        'displayName': m.displayName,
        'mode': m.mode,
        'sizeGB': m.sizeGB,
        'requiredVramGB': m.requiredVramGB,
      }).toList(),
      requirements: RecommendationRequirements(
        modelCount: selected.length,
        totalModelSizeGB: totalSize,
        baseOverheadGB: 7.0,
        bufferGB: buffer,
        totalWithBufferGB: totalWithBuffer,
        maxVramGB: maxVram,
        minVramGB: minVram,
      ),
      recommendedStorage: StoragePlan(
        id: totalWithBuffer <= 30 ? '30gb' : totalWithBuffer <= 50 ? '50gb' : '100gb',
        name: totalWithBuffer <= 30 ? 'Starter 30GB' : totalWithBuffer <= 50 ? 'Creator 50GB' : 'Studio 100GB',
        sizeGB: totalWithBuffer <= 30 ? 30 : totalWithBuffer <= 50 ? 50 : 100,
        pricePerMonth: totalWithBuffer <= 30 ? 3 : totalWithBuffer <= 50 ? 5 : 9,
        freeAfterGB: (totalWithBuffer <= 30 ? 30 : 100) - totalWithBuffer,
        fits: true,
      ),
      compatibleGPUs: [
        if (maxVram <= 12)
          const GpuTier(id: 'rtx-3060-12gb', name: 'RTX 3060', vramGB: 12, ramGB: 32, pricePerHour: 0.22, tier: 'budget', tags: ['budget', 'sdxl'], fit: 'minimum'),
        if (maxVram <= 24)
          const GpuTier(id: 'rtx-3090-24gb', name: 'RTX 3090', vramGB: 24, ramGB: 64, pricePerHour: 0.44, tier: 'balanced', tags: ['popular', 'flux'], fit: 'optimal'),
        if (maxVram <= 24)
          const GpuTier(id: 'rtx-4090-24gb', name: 'RTX 4090', vramGB: 24, ramGB: 64, pricePerHour: 0.62, tier: 'performance', tags: ['fast', 'wan'], fit: 'optimal'),
        const GpuTier(id: 'a100-40gb', name: 'A100 40GB', vramGB: 40, ramGB: 128, pricePerHour: 1.15, tier: 'pro', tags: ['wan-14b'], fit: 'optimal'),
        const GpuTier(id: 'a100-80gb', name: 'A100 80GB', vramGB: 80, ramGB: 256, pricePerHour: 1.85, tier: 'enterprise', tags: ['all'], fit: 'optimal'),
      ],
      warnings: [
        if (totalWithBuffer > 30) 'Starter 30GB storage is insufficient. Upgrade recommended.',
      ],
      allPlans: const [
        StoragePlan(id: '30gb', name: 'Starter 30GB', sizeGB: 30, pricePerMonth: 3),
        StoragePlan(id: '50gb', name: 'Creator 50GB', sizeGB: 50, pricePerMonth: 5),
        StoragePlan(id: '100gb', name: 'Studio 100GB', sizeGB: 100, pricePerMonth: 9),
        StoragePlan(id: '200gb', name: 'Pro 200GB', sizeGB: 200, pricePerMonth: 16),
        StoragePlan(id: '500gb', name: 'Enterprise 500GB', sizeGB: 500, pricePerMonth: 35),
      ],
    );
  }

  static const List<CloudModel> _fallbackModels = [
    CloudModel(
      modelId: 'sdxl-base-1.0',
      displayName: 'SDXL Base 1.0',
      mode: 'image',
      hfRepoId: 'stabilityai/stable-diffusion-xl-base-1.0',
      sizeGB: 6.9,
      requiredVramGB: 12,
    ),
    CloudModel(
      modelId: 'flux-kontext-dev',
      displayName: 'FLUX.1 Kontext [dev]',
      mode: 'image',
      hfRepoId: 'black-forest-labs/FLUX.1-Kontext-dev',
      sizeGB: 24.0,
      requiredVramGB: 24,
    ),
    CloudModel(
      modelId: 'qwen-image-2.1',
      displayName: 'Qwen-Image 2.1',
      mode: 'image',
      hfRepoId: 'Qwen/Qwen-Image-2.1',
      sizeGB: 15.0,
      requiredVramGB: 16,
    ),
    CloudModel(
      modelId: 'z-image-turbo',
      displayName: 'Z-Image Turbo',
      mode: 'image',
      hfRepoId: 'Tongyi-MAI/Z-Image-Turbo',
      sizeGB: 6.2,
      requiredVramGB: 12,
    ),
    CloudModel(
      modelId: 'wan-2.1-t2v-1.3b',
      displayName: 'Wan 2.1 T2V 1.3B',
      mode: 'video',
      hfRepoId: 'Wan-AI/Wan2.1-T2V-1.3B-Diffusers',
      sizeGB: 3.5,
      requiredVramGB: 12,
    ),
    CloudModel(
      modelId: 'wan-2.1-i2v-14b',
      displayName: 'Wan 2.1 I2V 14B',
      mode: 'video',
      hfRepoId: 'Wan-AI/Wan2.1-I2V-14B-480P-Diffusers',
      sizeGB: 28.0,
      requiredVramGB: 24,
    ),
    CloudModel(
      modelId: 'wan-2.2-animate-14b',
      displayName: 'Wan 2.2 Animate 14B',
      mode: 'motion',
      hfRepoId: 'Wan-AI/Wan2.2-Animate-14B',
      sizeGB: 28.0,
      requiredVramGB: 24,
    ),
    CloudModel(
      modelId: 'minimax-h3',
      displayName: 'MiniMax-H3 Video+Audio',
      mode: 'motion',
      hfRepoId: 'MiniMaxAI/MiniMax-H3',
      sizeGB: 33.0,
      requiredVramGB: 32,
    ),
    CloudModel(
      modelId: 'chatterbox-tts',
      displayName: 'Chatterbox TTS',
      mode: 'voice',
      hfRepoId: 'ResembleAI/chatterbox',
      sizeGB: 1.2,
      requiredVramGB: 4,
    ),
    CloudModel(
      modelId: 'fashn-vton-1.5',
      displayName: 'FASHN VTON 1.5',
      mode: 'vton',
      hfRepoId: 'fashn-ai/fashn-vton-1.5',
      sizeGB: 2.1,
      requiredVramGB: 8,
    ),
    CloudModel(
      modelId: 'realesrgan-x4plus',
      displayName: 'Real-ESRGAN x4plus',
      mode: 'enhancer',
      hfRepoId: 'amd/realesrgan-x4plus',
      sizeGB: 0.15,
      requiredVramGB: 4,
    ),
  ];
}
