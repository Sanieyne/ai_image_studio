import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/generation_request.dart';
import '../models/generation_result.dart';
import '../models/lora.dart';
/// Information about an available model returned by GET /models/available
class AvailableModelInfo {
  final String id;
  final String label;
  final String family;
  final String mode; // 'image', 'video', 'voice', 'tryon', 'enhancer'
  final bool isActive;
  final bool isDownloaded;
  final int defaultSteps;
  final double defaultGuidance;
  final bool gated;
  final String note;

  const AvailableModelInfo({
    required this.id,
    required this.label,
    required this.family,
    required this.mode,
    this.isActive = false,
    this.isDownloaded = false,
    this.defaultSteps = 30,
    this.defaultGuidance = 7.0,
    this.gated = false,
    this.note = '',
  });

  factory AvailableModelInfo.fromJson(Map<String, dynamic> json) {
    return AvailableModelInfo(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      family: json['family'] as String? ?? '',
      mode: json['mode'] as String? ?? 'image',
      isActive: json['is_active'] as bool? ?? false,
      isDownloaded: json['is_downloaded'] as bool? ?? false,
      defaultSteps: (json['default_steps'] as num?)?.toInt() ?? 30,
      defaultGuidance: (json['default_guidance'] as num?)?.toDouble() ?? 7.0,
      gated: json['gated'] as bool? ?? false,
      note: json['note'] as String? ?? '',
    );
  }
}

/// HTTP client for the Python engine (Part 4/5): generation + LoRA
/// management + health, with offline mock fallback.
class ApiService {

  static const String baseUrl = 'http://127.0.0.1:8000';
  static const Duration requestTimeout = Duration(minutes: 5);

  /// Set to true during UI testing without a backend.
  static bool forceMockMode = false;

  /// Embedded 1x1 PNG used when even the placeholder CDN is unreachable.
  static final Uint8List _offlinePlaceholder = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  );

  final http.Client _client;

  ApiService({http.Client? client}) : _client = client ?? http.Client();

  String? activeDevice;
  String? activeDeviceName;

  /// GET /health -> true when the engine answers 200.
  Future<bool> checkHealth({int retries = 1}) async {
    for (int attempt = 0; attempt <= retries; attempt++) {
      try {
        final response = await _client
            .get(
              Uri.parse('$baseUrl/health'),
              headers: const {'Connection': 'close'},
            )
            .timeout(const Duration(seconds: 5));
        if (response.statusCode == 200) {
          try {
            final data = jsonDecode(response.body) as Map<String, dynamic>;
            activeDevice = data['device'] as String?;
            activeDeviceName = data['device_name'] as String?;
          } catch (_) {}
          return true;
        }
      } catch (_) {
        if (attempt == retries) {
          return false;
        }
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }
    return false;
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

  /// POST /animate -> Wan 2.2 Animate 14B Character Motion Animation
  Future<GenerationResult> animateCharacter({
    required String imageBase64,
    String? templateVideoBase64,
    String? prompt,
    int numFrames = 17,
    int steps = 4,
    double sampleGuideScale = 1.0,
    int seed = -1,
    int width = 480,
    int height = 640,
    int fps = 24,
  }) async {
    try {
      final cleanImageB64 = imageBase64.contains(',')
          ? imageBase64.split(',').last
          : imageBase64;
      final cleanVideoB64 = (templateVideoBase64 != null &&
              templateVideoBase64.contains(','))
          ? templateVideoBase64.split(',').last
          : templateVideoBase64;

      final body = {
        'image_base64': cleanImageB64,
        if (cleanVideoB64 != null && cleanVideoB64.isNotEmpty)
          'template_video_base64': cleanVideoB64,
        if (prompt != null && prompt.isNotEmpty) 'prompt': prompt,
        'num_frames': numFrames,
        'steps': steps,
        'sample_guide_scale': sampleGuideScale,
        'seed': seed,
        'width': width,
        'height': height,
        'fps': fps,
      };

      final response = await _client
          .post(
            Uri.parse('$baseUrl/animate'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(minutes: 6));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data =
            jsonDecode(response.body) as Map<String, dynamic>;
        final String rawB64 = data['video_base64'] as String? ?? '';
        final String cleanB64 =
            rawB64.contains(',') ? rawB64.split(',').last : rawB64;
        final Uint8List videoBytes = base64Decode(cleanB64);
        return GenerationResult(
          success: true,
          imageBytes: Uint8List(0),
          rawBase64: cleanB64,
          seed: (data['seed'] as num?)?.toInt() ?? seed,
          inferenceTimeMs: 0,
          width: width,
          height: height,
          aspectRatio: '9:16',
          activeLoras: const {},
          isVideo: true,
          videoBytes: videoBytes,
        );
      }
      String detail = 'Server returned code ${response.statusCode}';
      try {
        final Map<String, dynamic> errorBody =
            jsonDecode(response.body) as Map<String, dynamic>;
        detail = errorBody['detail']?.toString() ?? detail;
      } catch (_) {}
      return GenerationResult.failure(detail);
    } catch (e) {
      return GenerationResult.failure('Animation request failed: $e');
    }
  }

  /// POST /wan2_1 -> Wan 2.1 Foundation Video Suite (T2V 1.3B, T2V 14B, I2V 14B)
  Future<GenerationResult> generateWan2_1({
    required String prompt,
    String? negativePrompt,
    String? imageBase64,
    String? endImageBase64,
    String task = 't2v-1.3B',
    int numFrames = 81,
    int steps = 30,
    double guidanceScale = 5.0,
    double flowShift = 3.0,
    int seed = -1,
    int width = 832,
    int height = 480,
    int fps = 16,
    String aspectRatio = '16:9',
  }) async {
    try {
      final cleanImageB64 = (imageBase64 != null && imageBase64.contains(','))
          ? imageBase64.split(',').last
          : imageBase64;
      final cleanEndImageB64 =
          (endImageBase64 != null && endImageBase64.contains(','))
              ? endImageBase64.split(',').last
              : endImageBase64;

      final body = {
        'prompt': prompt,
        if (negativePrompt != null && negativePrompt.isNotEmpty)
          'negative_prompt': negativePrompt,
        if (cleanImageB64 != null && cleanImageB64.isNotEmpty)
          'image_base64': cleanImageB64,
        if (cleanEndImageB64 != null && cleanEndImageB64.isNotEmpty)
          'end_image_base64': cleanEndImageB64,
        'task': task,
        'width': width,
        'height': height,
        'num_frames': numFrames,
        'fps': fps,
        'steps': steps,
        'guidance_scale': guidanceScale,
        'flow_shift': flowShift,
        'seed': seed,
      };

      final response = await _client
          .post(
            Uri.parse('$baseUrl/wan2_1'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(minutes: 6));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data =
            jsonDecode(response.body) as Map<String, dynamic>;
        final String rawB64 = data['video_base64'] as String? ?? '';
        final String cleanB64 =
            rawB64.contains(',') ? rawB64.split(',').last : rawB64;
        final Uint8List videoBytes = base64Decode(cleanB64);
        return GenerationResult(
          success: true,
          imageBytes: Uint8List(0),
          rawBase64: cleanB64,
          seed: (data['seed'] as num?)?.toInt() ?? seed,
          inferenceTimeMs: 0,
          width: width,
          height: height,
          aspectRatio: aspectRatio,
          activeLoras: const {},
          isVideo: true,
          videoBytes: videoBytes,
        );
      }
      String detail = 'Server returned code ${response.statusCode}';
      try {
        final Map<String, dynamic> errorBody =
            jsonDecode(response.body) as Map<String, dynamic>;
        detail = errorBody['detail']?.toString() ?? detail;
      } catch (_) {}
      return GenerationResult.failure('Wan 2.1 failed: $detail');
    } catch (e) {
      return GenerationResult.failure('Wan 2.1 request error: $e');
    }
  }

  /// POST /minimax -> MiniMax-H3 Omni-modal Video+Audio generation
  Future<GenerationResult> generateMiniMaxVideo({
    required String prompt,
    String? imageBase64,
    int durationSeconds = 5,
    int fps = 24,
    int steps = 30,
    String aspectRatio = '16:9',
    int? seed,
  }) async {
    try {
      final cleanImageB64 = (imageBase64 != null && imageBase64.contains(','))
          ? imageBase64.split(',').last
          : imageBase64;

      final body = {
        'prompt': prompt,
        'image_base64': cleanImageB64,
        'duration_seconds': durationSeconds,
        'fps': fps,
        'steps': steps,
        'aspect_ratio': aspectRatio,
        'seed': seed ?? -1,
      };

      final response = await _client
          .post(
            Uri.parse('$baseUrl/minimax'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(minutes: 6));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data =
            jsonDecode(response.body) as Map<String, dynamic>;
        final String rawB64 = data['video_base64'] as String? ?? '';
        final String cleanB64 =
            rawB64.contains(',') ? rawB64.split(',').last : rawB64;
        final Uint8List videoBytes = base64Decode(cleanB64);
        return GenerationResult(
          success: true,
          imageBytes: Uint8List(0),
          rawBase64: cleanB64,
          seed: (data['seed'] as num?)?.toInt() ?? seed ?? 0,
          inferenceTimeMs: 0,
          width: 768,
          height: 432,
          aspectRatio: aspectRatio,
          activeLoras: const {},
          isVideo: true,
          videoBytes: videoBytes,
        );
      }
      String detail = 'Server returned code ${response.statusCode}';
      try {
        final Map<String, dynamic> errorBody =
            jsonDecode(response.body) as Map<String, dynamic>;
        detail = errorBody['detail']?.toString() ?? detail;
      } catch (_) {}
      return GenerationResult.failure(detail);
    } catch (e) {
      return GenerationResult.failure('MiniMax-H3 video generation failed: $e');
    }
  }

  /// POST /voice -> Chatterbox TTS or Breeze-TTS-2 voice generation / cloning
  Future<GenerationResult> generateVoice({
    required String prompt,
    String language = 'en',
    String? modelName,
    String? audioPromptBase64,
    String? instruction,
    String? refText,
    double exaggeration = 0.5,
    double cfgWeight = 0.5,
    int? seed,
  }) async {
    if (forceMockMode) {
      return _mockVoiceFallback(prompt, language: language, seed: seed);
    }
    try {
      final cleanAudioB64 = (audioPromptBase64 != null &&
              audioPromptBase64.contains(','))
          ? audioPromptBase64.split(',').last
          : audioPromptBase64;

      final body = {
        'prompt': prompt,
        'language': language,
        if (modelName != null && modelName.isNotEmpty) 'model_name': modelName,
        if (cleanAudioB64 != null && cleanAudioB64.isNotEmpty)
          'audio_prompt_base64': cleanAudioB64,
        if (instruction != null && instruction.isNotEmpty)
          'instruction': instruction,
        if (refText != null && refText.isNotEmpty)
          'ref_text': refText,
        'exaggeration': exaggeration,
        'cfg_weight': cfgWeight,
        'seed': seed ?? -1,
      };

      final response = await _client
          .post(
            Uri.parse('$baseUrl/voice'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(minutes: 3));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data =
            jsonDecode(response.body) as Map<String, dynamic>;
        final String rawB64 = data['audio_base64'] as String? ?? '';
        final String cleanB64 =
            rawB64.contains(',') ? rawB64.split(',').last : rawB64;
        final Uint8List audioBytes = base64Decode(cleanB64);
        final int sr = (data['sample_rate'] as num?)?.toInt() ?? 24000;
        final int elapsed = (data['inference_time_ms'] as num?)?.toInt() ?? 0;
        final int seedUsed = (data['seed'] as num?)?.toInt() ?? (seed ?? -1);

        return GenerationResult(
          success: true,
          imageBytes: Uint8List(0),
          rawBase64: cleanB64,
          seed: seedUsed,
          inferenceTimeMs: elapsed,
          width: 0,
          height: 0,
          aspectRatio: '1:1',
          activeLoras: const {},
          isAudio: true,
          audioBytes: audioBytes,
          sampleRate: sr,
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
          '[ApiService] Backend unreachable. Falling back to mock voice.');
      return _mockVoiceFallback(prompt, language: language, seed: seed);
    } catch (e) {
      return GenerationResult.failure('Voice generation failed: $e');
    }
  }

  /// POST /tryon -> FASHN VTON v1.5 Virtual Try-On
  Future<GenerationResult> generateTryOn({
    required String personImageBase64,
    required String garmentImageBase64,
    String category = 'tops',
    String garmentPhotoType = 'model',
    int steps = 30,
    double guidanceScale = 1.5,
    int? seed,
    bool segmentationFree = true,
  }) async {
    try {
      final cleanPersonB64 = personImageBase64.contains(',')
          ? personImageBase64.split(',').last
          : personImageBase64;
      final cleanGarmentB64 = garmentImageBase64.contains(',')
          ? garmentImageBase64.split(',').last
          : garmentImageBase64;

      final body = {
        'person_image_base64': cleanPersonB64,
        'garment_image_base64': cleanGarmentB64,
        'category': category,
        'garment_photo_type': garmentPhotoType,
        'steps': steps,
        'guidance_scale': guidanceScale,
        'seed': seed ?? -1,
        'segmentation_free': segmentationFree,
      };

      final response = await _client
          .post(
            Uri.parse('$baseUrl/tryon'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(minutes: 5));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data =
            jsonDecode(response.body) as Map<String, dynamic>;
        final String rawB64 = data['image_base64'] as String? ?? '';
        final String cleanB64 =
            rawB64.contains(',') ? rawB64.split(',').last : rawB64;
        final Uint8List imageBytes = base64Decode(cleanB64);
        final int elapsed = (data['inference_time_ms'] as num?)?.toInt() ?? 0;
        final int seedUsed = (data['seed'] as num?)?.toInt() ?? (seed ?? -1);

        return GenerationResult(
          success: true,
          imageBytes: imageBytes,
          rawBase64: cleanB64,
          seed: seedUsed,
          inferenceTimeMs: elapsed,
          width: 576,
          height: 864,
          aspectRatio: '2:3',
          activeLoras: const {},
        );
      }
      String detail = 'Server returned code ${response.statusCode}';
      try {
        final Map<String, dynamic> errorBody =
            jsonDecode(response.body) as Map<String, dynamic>;
        detail = errorBody['detail']?.toString() ?? detail;
      } catch (_) {}
      return GenerationResult.failure(detail);
    } catch (e) {
      return GenerationResult.failure('Virtual try-on failed: $e');
    }
  }

  /// POST /enhance -> Real-ESRGAN x4plus AI Image Enhancement & Super-Resolution
  Future<GenerationResult> enhanceImage({
    required String imageBase64,
    String modelName = 'amd/realesrgan-x4plus',
    int scale = 4,
    bool faceEnhance = false,
    double denoiseStrength = 0.5,
  }) async {
    try {
      final cleanImageB64 = imageBase64.contains(',')
          ? imageBase64.split(',').last
          : imageBase64;

      final body = {
        'image_base64': cleanImageB64,
        'model_name': modelName,
        'scale': scale,
        'face_enhance': faceEnhance,
        'denoise_strength': denoiseStrength,
      };

      final response = await _client
          .post(
            Uri.parse('$baseUrl/enhance'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(minutes: 3));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data =
            jsonDecode(response.body) as Map<String, dynamic>;
        final String rawB64 = data['image_base64'] as String? ?? '';
        final String cleanResultB64 =
            rawB64.contains(',') ? rawB64.split(',').last : rawB64;
        final Uint8List imageBytes = base64Decode(cleanResultB64);
        final int elapsed = (data['inference_time_ms'] as num?)?.toInt() ?? 0;
        final int width = (data['width'] as num?)?.toInt() ?? 1024;
        final int height = (data['height'] as num?)?.toInt() ?? 1024;

        return GenerationResult(
          success: true,
          imageBytes: imageBytes,
          rawBase64: cleanResultB64,
          seed: -1,
          inferenceTimeMs: elapsed,
          width: width,
          height: height,
          aspectRatio: '$width:$height',
          activeLoras: const {},
        );
      }
      String detail = 'Server returned code ${response.statusCode}';
      try {
        final Map<String, dynamic> errorBody =
            jsonDecode(response.body) as Map<String, dynamic>;
        detail = errorBody['detail']?.toString() ?? detail;
      } catch (_) {}
      return GenerationResult.failure(detail);
    } catch (e) {
      return GenerationResult.failure('Image enhancement failed: $e');
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

  /// GET /models/available -> list of models with live download & active status
  Future<List<AvailableModelInfo>> getAvailableModels() async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/models/available'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final list = data['models'] as List<dynamic>? ?? [];
        return list
            .map((item) =>
                AvailableModelInfo.fromJson(item as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('[ApiService] Failed to fetch available models: $e');
    }
    return [];
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

  Future<GenerationResult> _mockVoiceFallback(
    String prompt, {
    String language = 'en',
    int? seed,
  }) async {
    await Future.delayed(const Duration(milliseconds: 1200));
    final seedUsed = seed ?? (DateTime.now().millisecondsSinceEpoch % 100000);
    final wavBytes = _createMockWavBytes();
    return GenerationResult(
      success: true,
      imageBytes: Uint8List(0),
      rawBase64: base64Encode(wavBytes),
      seed: seedUsed,
      inferenceTimeMs: 1200,
      width: 0,
      height: 0,
      aspectRatio: '1:1',
      activeLoras: const {},
      isAudio: true,
      audioBytes: wavBytes,
      sampleRate: 24000,
      isMock: true,
    );
  }

  static Uint8List _createMockWavBytes() {
    const sampleRate = 24000;
    const numSamples = 24000;
    final byteData = ByteData(44 + numSamples * 2);
    byteData.setUint8(0, 0x52); // 'R'
    byteData.setUint8(1, 0x49); // 'I'
    byteData.setUint8(2, 0x46); // 'F'
    byteData.setUint8(3, 0x46); // 'F'
    byteData.setUint32(4, 36 + numSamples * 2, Endian.little);
    byteData.setUint8(8, 0x57);  // 'W'
    byteData.setUint8(9, 0x41);  // 'A'
    byteData.setUint8(10, 0x56); // 'V'
    byteData.setUint8(11, 0x45); // 'E'
    byteData.setUint8(12, 0x66); // 'f'
    byteData.setUint8(13, 0x6D); // 'm'
    byteData.setUint8(14, 0x74); // 't'
    byteData.setUint8(15, 0x20); // ' '
    byteData.setUint32(16, 16, Endian.little);
    byteData.setUint16(20, 1, Endian.little);
    byteData.setUint16(22, 1, Endian.little);
    byteData.setUint32(24, sampleRate, Endian.little);
    byteData.setUint32(28, sampleRate * 2, Endian.little);
    byteData.setUint16(32, 2, Endian.little);
    byteData.setUint16(34, 16, Endian.little);
    byteData.setUint8(36, 0x64); // 'd'
    byteData.setUint8(37, 0x61); // 'a'
    byteData.setUint8(38, 0x74); // 't'
    byteData.setUint8(39, 0x61); // 'a'
    byteData.setUint32(40, numSamples * 2, Endian.little);
    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      final val = (0.3 * math.sin(2 * math.pi * 440.0 * t) * 32767).toInt();
      byteData.setInt16(44 + i * 2, val, Endian.little);
    }
    return byteData.buffer.asUint8List();
  }

  void dispose() => _client.close();
}
