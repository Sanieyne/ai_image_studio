import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/generation_request.dart';
import '../models/generation_result.dart';
import '../models/lora.dart';

/// HTTP client for the Python engine (Part 4/5): generation + LoRA
/// management + health, with offline mock fallback.
class ApiService {
  static const String baseUrl = 'http://127.0.0.1:8000';
  static const Duration requestTimeout = Duration(seconds: 90);

  /// Set to true during UI testing without a backend.
  static bool forceMockMode = false;

  /// Embedded 1x1 PNG used when even the placeholder CDN is unreachable.
  static final Uint8List _offlinePlaceholder = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  );

  final http.Client _client;

  ApiService({http.Client? client}) : _client = client ?? http.Client();

  /// GET /health -> true when the engine answers 200.
  Future<bool> checkHealth() async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// POST /generate -> decoded image bytes + metadata.
  Future<GenerationResult> generateImage(GenerationRequest request) async {
    if (forceMockMode) return _mockFallback(request);
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/generate'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(request.toJson()),
          )
          .timeout(requestTimeout);

      if (response.statusCode == 200) {
        final Map<String, dynamic> data =
            jsonDecode(response.body) as Map<String, dynamic>;
        final String rawB64 = data['image_base64'] as String? ?? '';
        final String cleanB64 =
            rawB64.contains(',') ? rawB64.split(',').last : rawB64;
        final Uint8List bytes = base64Decode(cleanB64);
        final Map<String, dynamic> lorasRaw =
            data['active_loras'] as Map<String, dynamic>? ?? {};
        final loras = lorasRaw.map(
          (k, v) => MapEntry(k, LoraInfo.fromJson(v as Map<String, dynamic>)),
        );
        return GenerationResult(
          success: true,
          imageBytes: bytes,
          rawBase64: cleanB64,
          seed: (data['seed'] as num?)?.toInt() ?? request.seed,
          inferenceTimeMs:
              (data['inference_time_ms'] as num?)?.toInt() ?? 0,
          width: (data['width'] as num?)?.toInt() ?? 768,
          height: (data['height'] as num?)?.toInt() ?? 1344,
          aspectRatio:
              data['aspect_ratio'] as String? ?? request.aspectRatio,
          activeLoras: loras,
        );
      }
      String detail = 'Server returned code ${response.statusCode}';
      try {
        final Map<String, dynamic> errorBody =
            jsonDecode(response.body) as Map<String, dynamic>;
        detail = errorBody['detail']?.toString() ?? detail;
      } catch (_) {}
      return GenerationResult.failure(detail);
    } on SocketException catch (_) {
      debugPrint(
          '[ApiService] Backend unreachable. Falling back to mock generator.');
      return _mockFallback(request);
    } on TimeoutException {
      return GenerationResult.failure(
          'Generation timed out after 90 seconds.');
    } catch (e) {
      return GenerationResult.failure('Request error: $e');
    }
  }

  /// GET /loras -> active adapters ({} when offline).
  Future<Map<String, LoraInfo>> getActiveLoras() async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/loras'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final Map<String, dynamic> data =
            jsonDecode(response.body) as Map<String, dynamic>;
        final raw =
            data['active_loras'] as Map<String, dynamic>? ?? {};
        return raw.map(
          (k, v) => MapEntry(k, LoraInfo.fromJson(v as Map<String, dynamic>)),
        );
      }
    } catch (e) {
      debugPrint('[ApiService] Failed to fetch active LoRAs: $e');
    }
    return {};
  }

  /// POST /loras/load -> true on 200.
  Future<bool> loadLora(LoraConfig config) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/loras/load'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(config.toJson()),
          )
          .timeout(const Duration(seconds: 30));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[ApiService] Failed to load LoRA: $e');
      return false;
    }
  }

  /// POST /loras/unload -> true on 200.
  Future<bool> unloadLoras() async {
    try {
      final response = await _client
          .post(Uri.parse('$baseUrl/loras/unload'))
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[ApiService] Failed to unload LoRAs: $e');
      return false;
    }
  }

  /// POST /loras/scale -> true on 200.
  Future<bool> setLoraScale(String adapterName, double weight) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/loras/scale'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(
                {'adapter_name': adapterName, 'weight': weight}),
          )
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[ApiService] Failed to scale LoRA: $e');
      return false;
    }
  }

  /// POST /models/switch -> true when engine loads it.
  Future<bool> switchModel(String modelId) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/models/switch'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'model_id': modelId}),
          )
          .timeout(const Duration(seconds: 120));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[ApiService] Failed to switch model: $e');
      return false;
    }
  }

  /// GET /models/current -> model_id or null when offline.
  Future<String?> getCurrentModel() async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/models/current'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['model_id'] as String?;
      }
    } catch (e) {
      debugPrint('[ApiService] Failed to fetch current model: $e');
    }
    return null;
  }

  /// Offline stand-in: delay + prompt-seeded picsum image at bucket size.
  Future<GenerationResult> _mockFallback(GenerationRequest req) async {
    await Future.delayed(const Duration(milliseconds: 1800));
    final dims = _dimsForRatio(req.aspectRatio);
    final seed = req.seed == -1
        ? DateTime.now().millisecondsSinceEpoch % 100000
        : req.seed;
    final url =
        'https://picsum.photos/seed/$seed/${dims[0]}/${dims[1]}';
    Uint8List bytes;
    try {
      final res = await _client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 15));
      bytes = res.statusCode == 200 ? res.bodyBytes : _offlinePlaceholder;
    } catch (_) {
      bytes = _offlinePlaceholder;
    }
    return GenerationResult(
      success: true,
      imageBytes: bytes,
      rawBase64: '',
      seed: seed,
      inferenceTimeMs: 1800,
      width: dims[0],
      height: dims[1],
      aspectRatio: req.aspectRatio,
      activeLoras: const {},
      isMock: true,
    );
  }

  List<int> _dimsForRatio(String ratio) {
    switch (ratio) {
      case '16:9':
        return [1344, 768];
      case '9:16':
        return [768, 1344];
      case '4:5':
        return [896, 1152];
      case '1:1':
        return [1024, 1024];
      default:
        return [768, 1344];
    }
  }

  void dispose() => _client.close();
}
