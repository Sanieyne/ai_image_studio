import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/cloud_model.dart';
import '../models/saved_generation.dart';
import '../../../../services/api_client.dart';
import '../../../../services/auth_service.dart';
import '../../../../services/database_service.dart';

/// Service interfacing with the AI Image Studio Cloud Backend (Contabo VPS & Vast.ai Provisioner)
class CloudApiService {
  static final CloudApiService instance = CloudApiService._();
  CloudApiService._();
  factory CloudApiService() => instance;

  String baseUrl = kCloudApiBaseUrl;

  ApiClient? _client;
  @visibleForTesting
  ApiClient? testApiClient;

  /// Authenticated HTTP client, rebuilt if [baseUrl] is reassigned.
  ApiClient get _api {
    final testClient = testApiClient;
    if (testClient != null) return testClient;
    final current = _client;
    if (current != null && current.baseUrl == baseUrl) return current;
    return _client = ApiClient(baseUrl: baseUrl);
  }

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

  /// Fetch dynamic server pricing and token conversion policy
  Future<PricingPolicyConfig?> fetchPricingConfig() async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/pricing/config'))
          .timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final data = body['data'] as Map<String, dynamic>;
        return PricingPolicyConfig.fromJson(data);
      }
    } catch (e) {
      debugPrint('[CloudApiService] fetchPricingConfig error: $e');
    }
    return null;
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
  /// Live offers for [modelIds], priced by the server for [storageGB] of storage.
  Future<MarketplaceRecommendedResult?> fetchRecommendedGpuOffers(
    List<String> modelIds, {
    int? storageGB,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/gpu/recommended').replace(
        queryParameters: {
          'modelIds': modelIds.join(','),
          if (storageGB != null) 'storageGB': storageGB.toString(),
        },
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

  /// Estimate live pricing dynamically for arbitrary storage size (credits only)
  Future<LivePricingEstimate?> estimateStoragePricing({
    required String offerId,
    required int storageGB,
    double hours = 1.0,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/gpu/pricing/estimate').replace(
        queryParameters: {
          'offerId': offerId,
          'storageGB': storageGB.toString(),
          'hours': hours.toString(),
        },
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final data = body['data'] as Map<String, dynamic>;
        return LivePricingEstimate.fromJson(data);
      }
    } catch (e) {
      debugPrint('[CloudApiService] estimateStoragePricing error: $e');
    }
    return null;
  }

  /// Retrieve GPU series grouping from backend (RTX 30-Series, RTX 40-Series, Datacenter)
  Future<Map<String, List<String>>?> fetchGpuSeries() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/gpu/series')).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final data = body['data'] as Map<String, dynamic>;
        final Map<String, List<String>> result = {};
        for (final entry in data.entries) {
          result[entry.key] = List<String>.from((entry.value as List<dynamic>).map((e) => e.toString()));
        }
        return result;
      }
    } catch (e) {
      debugPrint('[CloudApiService] fetchGpuSeries error: $e');
    }
    return null;
  }

  String? _lastRentError;
  String? get lastRentError => _lastRentError;

  /// Provision and rent a dedicated GPU instance with selected models
  /// Whether new rentals are open (GET /gpu/rentals/status). Null when unknown.
  Future<RentalsStatus?> fetchRentalsStatus() async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/gpu/rentals/status'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        return RentalsStatus.fromJson(body['data'] as Map<String, dynamic>? ?? const {});
      }
    } catch (e) {
      debugPrint('[CloudApiService] fetchRentalsStatus error: $e');
    }
    return null;
  }

  /// One rented instance with its progress, recent log lines, elapsed time and credits.
  Future<Map<String, dynamic>?> fetchInstance(String instanceId) async {
    try {
      final res = await _api.get('/gpu/instances/$instanceId');
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        return body['data'] as Map<String, dynamic>?;
      }
    } catch (e) {
      debugPrint('[CloudApiService] fetchInstance error: $e');
    }
    return null;
  }

  /// The signed-in user's active instances (provisioning, downloading, ready, running).
  Future<List<Map<String, dynamic>>?> fetchMyInstances() async {
    await initAuth();
    if (!isAuthenticated) return const [];
    try {
      final res = await _api.get('/gpu/instances/me');
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        return (body['data'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (e) {
      debugPrint('[CloudApiService] fetchMyInstances error: $e');
    }
    return null;
  }

  String? _lastStopError;
  String? get lastStopError => _lastStopError;

  /// Stops (destroys) an instance: DELETE /gpu/instances/:id. Returns the stopped
  /// instance (with credits charged / refunded), or null with [lastStopError] set.
  Future<Map<String, dynamic>?> stopInstance(String instanceId) async {
    try {
      final res = await _api.delete('/gpu/instances/$instanceId', timeout: const Duration(seconds: 30));
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200) {
        _lastStopError = null;
        return body['data'] as Map<String, dynamic>?;
      }
      _lastStopError = body['message'] as String? ?? 'Could not stop the GPU (${res.statusCode}).';
    } catch (e) {
      _lastStopError = 'Could not reach the server to stop the GPU. Check your connection and try again.';
      debugPrint('[CloudApiService] stopInstance error: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> rentGpuInstance({
    required String offerId,
    required List<String> selectedModelIds,
    int storageGB = 50,
  }) async {
    await initAuth();
    if (!isAuthenticated) {
      _lastRentError = 'Authentication required. Please log in.';
      return null;
    }
    try {
      final res = await _api.post(
        '/gpu/rent',
        jsonBody: {
          'offerId': offerId,
          'storageGB': storageGB,
          'selectedModelIds': selectedModelIds,
        },
        timeout: const Duration(seconds: 45),
      );
      if (res.statusCode == 201 || res.statusCode == 200) {
        _lastRentError = null;
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        return body['data'] as Map<String, dynamic>?;
      }
      try {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        _lastRentError = body['message'] as String? ?? 'Failed to rent instance (${res.statusCode})';
      } catch (_) {
        _lastRentError = 'Server error (${res.statusCode})';
      }
    } catch (e) {
      _lastRentError = 'Connection error: $e';
      debugPrint('[CloudApiService] rentGpuInstance error: $e');
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
        pricePerMonth: totalWithBuffer <= 30 ? 3.75 : totalWithBuffer <= 50 ? 6.25 : 11.25,
        freeAfterGB: (totalWithBuffer <= 30 ? 30 : 100) - totalWithBuffer,
        fits: true,
        customCreditsPerMonth: totalWithBuffer <= 30 ? 188 : totalWithBuffer <= 50 ? 312 : 562,
        customCreditsPerHour: totalWithBuffer <= 30 ? 0.26 : totalWithBuffer <= 50 ? 0.43 : 0.78,
      ),
      compatibleGPUs: [
        if (maxVram <= 12)
          const GpuTier(id: 'rtx-3060-12gb', name: 'RTX 3060', vramGB: 12, ramGB: 32, pricePerHour: 0.275, tier: 'budget', tags: ['budget', 'sdxl'], fit: 'minimum', customCreditsPerHour: 13.8),
        if (maxVram <= 24)
          const GpuTier(id: 'rtx-3090-24gb', name: 'RTX 3090', vramGB: 24, ramGB: 64, pricePerHour: 0.55, tier: 'balanced', tags: ['popular', 'flux'], fit: 'optimal', customCreditsPerHour: 27.5),
        if (maxVram <= 24)
          const GpuTier(id: 'rtx-4090-24gb', name: 'RTX 4090', vramGB: 24, ramGB: 64, pricePerHour: 0.775, tier: 'performance', tags: ['fast', 'wan'], fit: 'optimal', customCreditsPerHour: 38.8),
        const GpuTier(id: 'a100-40gb', name: 'A100 40GB', vramGB: 40, ramGB: 128, pricePerHour: 1.4375, tier: 'pro', tags: ['wan-14b'], fit: 'optimal', customCreditsPerHour: 71.9),
        const GpuTier(id: 'a100-80gb', name: 'A100 80GB', vramGB: 80, ramGB: 256, pricePerHour: 2.3125, tier: 'enterprise', tags: ['all'], fit: 'optimal', customCreditsPerHour: 115.6),
      ],
      warnings: [
        if (totalWithBuffer > 30) 'Starter 30GB storage is insufficient. Upgrade recommended.',
      ],
      allPlans: const [
        StoragePlan(id: '30gb', name: 'Starter 30GB', sizeGB: 30, pricePerMonth: 3.75, customCreditsPerMonth: 188, customCreditsPerHour: 0.26),
        StoragePlan(id: '50gb', name: 'Creator 50GB', sizeGB: 50, pricePerMonth: 6.25, customCreditsPerMonth: 312, customCreditsPerHour: 0.43),
        StoragePlan(id: '100gb', name: 'Studio 100GB', sizeGB: 100, pricePerMonth: 11.25, customCreditsPerMonth: 562, customCreditsPerHour: 0.78),
        StoragePlan(id: '200gb', name: 'Pro 200GB', sizeGB: 200, pricePerMonth: 20.0, customCreditsPerMonth: 1000, customCreditsPerHour: 1.39),
        StoragePlan(id: '500gb', name: 'Enterprise 500GB', sizeGB: 500, pricePerMonth: 43.75, customCreditsPerMonth: 2188, customCreditsPerHour: 3.04),
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

  // =========================================================================
  // Cloud Auth & Session Management
  // =========================================================================

  String? get authToken => AuthService.instance.accessToken;
  bool get isAuthenticated => AuthService.instance.isAuthenticated;

  /// Initialize auth state from secure storage.
  ///
  /// Also performs a one-time migration of tokens saved by older app
  /// versions in plain SQLite (`cloud_auth_token`) into secure storage,
  /// then wipes the SQLite copy. JWTs must never live in plain SQLite.
  Future<void> initAuth() async {
    await AuthService.instance.init();
    try {
      final legacy =
          await DatabaseService.instance.getSetting('cloud_auth_token');
      if (legacy != null && legacy.isNotEmpty) {
        await AuthService.instance.adoptLegacyAccessToken(legacy);
        await DatabaseService.instance.setSetting('cloud_auth_token', '');
      }
    } catch (_) {}
  }

  /// Legacy token setter, kept for API compatibility.
  ///
  /// Prefer [AuthService.login]/[AuthService.register]; passing null logs out.
  Future<void> setAuthToken(String? token) async {
    if (token == null || token.isEmpty) {
      await AuthService.instance.logout();
    } else {
      await AuthService.instance.adoptLegacyAccessToken(token);
    }
  }

  Map<String, String> get authHeaders => {
    'Content-Type': 'application/json',
    if (authToken != null && authToken!.isNotEmpty)
      'Authorization': 'Bearer $authToken',
  };

  /// Log in with email and password (delegates to [AuthService]).
  Future<bool> login(String email, String password) async {
    try {
      await AuthService.instance.login(email, password);
      return true;
    } catch (e) {
      debugPrint('[CloudApiService] login error: $e');
      return false;
    }
  }

  /// Register new user account (delegates to [AuthService]).
  Future<bool> register(String username, String email, String password) async {
    try {
      await AuthService.instance.register(username, email, password);
      return true;
    } catch (e) {
      debugPrint('[CloudApiService] register error: $e');
      return false;
    }
  }

  /// Retrieve current authenticated user profile.
  ///
  /// Goes through [ApiClient], so an expired access token is silently
  /// refreshed and retried once before giving up.
  Future<CloudUserProfile?> fetchCurrentUser() async {
    await initAuth();
    if (!isAuthenticated) return null;

    try {
      final res = await _api.get('/users/me');
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final data = body['data'] as Map<String, dynamic>?;
        if (data != null) {
          final profile = CloudUserProfile.fromJson(data);
          AuthService.instance.updateCachedUser(profile);
          return profile;
        }
      }
    } catch (e) {
      debugPrint('[CloudApiService] fetchCurrentUser error: $e');
    }
    return null;
  }

  String? _lastProfileUpdateError;
  String? get lastProfileUpdateError => _lastProfileUpdateError;

  /// Update creator public profile
  Future<bool> updateProfile({
    String? displayName,
    String? avatarUrl,
    String? bio,
    bool? isPublicProfile,
  }) async {
    await initAuth();
    if (!isAuthenticated) return false;

    try {
      final payload = <String, dynamic>{};
      if (displayName != null) payload['displayName'] = displayName;
      if (avatarUrl != null) payload['avatarUrl'] = avatarUrl;
      if (bio != null) payload['bio'] = bio;
      if (isPublicProfile != null) payload['isPublicProfile'] = isPublicProfile;

      final res = await _api.patch('/users/me/profile', jsonBody: payload);
      if (res.statusCode == 200) {
        _lastProfileUpdateError = null;
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final data = body['data'] as Map<String, dynamic>?;
        if (data != null) {
          final updated = CloudUserProfile.fromJson(data);
          AuthService.instance.updateCachedUser(updated);
        }
        return true;
      }
      try {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        _lastProfileUpdateError = body['message'] as String? ?? 'Failed to update profile (${res.statusCode})';
      } catch (_) {
        _lastProfileUpdateError = 'Server error (${res.statusCode})';
      }
      return false;
    } catch (e) {
      _lastProfileUpdateError = e.toString();
      debugPrint('[CloudApiService] updateProfile error: $e');
      return false;
    }
  }

  // =========================================================================
  // Cloud Generation & Library Management
  // =========================================================================

  /// Persist a completed cloud generation to user's remote library
  Future<SaveGenerationResponse> saveGeneration({
    required String mediaBase64,
    required String mediaType,
    String extension = 'png',
    required String prompt,
    String negativePrompt = '',
    required String modelId,
    Map<String, dynamic> settings = const {},
  }) async {
    await initAuth();
    if (!isAuthenticated) {
      return const SaveGenerationResponse(
        success: false,
        message: 'Please sign in or configure your cloud account to save generations.',
      );
    }

    try {
      final res = await _api.post(
        '/generations',
        jsonBody: {
          'mediaBase64': mediaBase64,
          'mediaType': mediaType,
          'extension': extension,
          'prompt': prompt,
          'negativePrompt': negativePrompt,
          'modelId': modelId,
          'settings': settings,
        },
        timeout: const Duration(seconds: 25),
      );

      final body = jsonDecode(res.body) as Map<String, dynamic>;

      if (res.statusCode == 201 && body['data'] != null) {
        final gen = SavedGeneration.fromJson(body['data'] as Map<String, dynamic>);
        return SaveGenerationResponse(
          success: true,
          generation: gen,
          message: 'Saved to your library',
        );
      }

      if (res.statusCode == 403) {
        final serverMsg = body['message'] as String? ?? '';
        return SaveGenerationResponse(
          success: false,
          isQuotaExceeded: true,
          quotaMessage: serverMsg.isNotEmpty
              ? serverMsg
              : 'Storage full — free up space or delete old saves',
          message: 'Storage full — free up space or delete old saves',
        );
      }

      return SaveGenerationResponse(
        success: false,
        message: body['message'] as String? ?? 'Failed to save generation to cloud',
      );
    } catch (e) {
      debugPrint('[CloudApiService] saveGeneration error: $e');
      return SaveGenerationResponse(
        success: false,
        message: 'Network error while saving generation: $e',
      );
    }
  }

  /// Retrieve paginated list of user's saved generations from library
  Future<MyGenerationsResponse> fetchMyGenerations({
    int page = 1,
    int limit = 24,
    String? mediaType,
  }) async {
    await initAuth();
    if (!isAuthenticated) {
      return const MyGenerationsResponse(success: false, items: []);
    }

    try {
      final queryParams = <String, String>{
        'page': page.toString(),
        'limit': limit.toString(),
      };
      if (mediaType != null && mediaType.isNotEmpty && mediaType.toLowerCase() != 'all') {
        queryParams['mediaType'] = mediaType.toLowerCase();
      }

      final res = await _api.get('/generations/me', queryParameters: queryParams);

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final data = body['data'] as List<dynamic>? ?? [];
        final pagination = body['pagination'] as Map<String, dynamic>? ?? {};

        final items = data
            .map((item) => SavedGeneration.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList();

        return MyGenerationsResponse(
          success: true,
          items: items,
          page: (pagination['page'] as num?)?.toInt() ?? page,
          limit: (pagination['limit'] as num?)?.toInt() ?? limit,
          total: (pagination['total'] as num?)?.toInt() ?? items.length,
          totalPages: (pagination['totalPages'] as num?)?.toInt() ?? 1,
          hasMore: pagination['hasMore'] as bool? ?? false,
        );
      }
    } catch (e) {
      debugPrint('[CloudApiService] fetchMyGenerations error: $e');
    }
    return const MyGenerationsResponse(success: false, items: []);
  }

  /// Delete a saved generation from cloud library
  Future<bool> deleteGeneration(String generationId) async {
    await initAuth();
    if (!isAuthenticated) return false;

    try {
      final res = await _api.delete('/generations/$generationId');
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('[CloudApiService] deleteGeneration error: $e');
      return false;
    }
  }

  /// Publish a saved generation to the public Community Gallery
  Future<PublishResult> publishGeneration(
    String generationId, {
    String? testModerationVerdict,
  }) async {
    await initAuth();
    if (!isAuthenticated) {
      return const PublishResult(
        verdict: PublishVerdict.error,
        message: 'Authentication required to publish creations.',
      );
    }

    try {
      final headers = <String, String>{};
      if (testModerationVerdict != null && testModerationVerdict.isNotEmpty) {
        headers['x-test-moderation-verdict'] = testModerationVerdict;
      }

      final res = await _api.post(
        '/generations/$generationId/publish',
        headers: headers,
        timeout: const Duration(seconds: 20),
      );

      final body = jsonDecode(res.body) as Map<String, dynamic>;

      if (res.statusCode == 200) {
        final gen = body['data'] != null
            ? SavedGeneration.fromJson(body['data'] as Map<String, dynamic>)
            : null;
        return PublishResult(
          verdict: PublishVerdict.approved,
          message: 'Published to Community Gallery 🎉',
          generation: gen,
        );
      }

      if (res.statusCode == 202) {
        final gen = body['data'] != null
            ? SavedGeneration.fromJson(body['data'] as Map<String, dynamic>)
            : null;
        return PublishResult(
          verdict: PublishVerdict.pendingReview,
          message:
              "Your post is under review and will appear in the gallery once approved. This usually takes a few minutes — we'll notify you.",
          generation: gen,
        );
      }

      if (res.statusCode == 400) {
        final serverMsg = body['message'] as String?;
        return PublishResult(
          verdict: PublishVerdict.rejected,
          message: serverMsg ??
              'This generation cannot be published as it does not meet our community safety standards.',
        );
      }

      return PublishResult(
        verdict: PublishVerdict.error,
        message: body['message'] as String? ?? 'Failed to publish generation (${res.statusCode})',
      );
    } catch (e) {
      debugPrint('[CloudApiService] publishGeneration error: $e');
      return PublishResult(
        verdict: PublishVerdict.error,
        message: 'Connection error during publication check: $e',
      );
    }
  }

  /// Unpublish a generation from Community Gallery
  Future<bool> unpublishGeneration(String generationId) async {
    await initAuth();
    if (!isAuthenticated) return false;

    try {
      final res = await _api.post('/generations/$generationId/unpublish');
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('[CloudApiService] unpublishGeneration error: $e');
      return false;
    }
  }
}
