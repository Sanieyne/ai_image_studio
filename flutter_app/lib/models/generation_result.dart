import 'dart:convert';
import 'dart:typed_data';

import 'lora.dart';

/// Parsed POST /generate response (Part 4/5).
class GenerationResult {
  final bool success;
  final Uint8List imageBytes;
  final String rawBase64;
  final int seed;
  final int inferenceTimeMs;
  final int width;
  final int height;
  final String aspectRatio;
  final Map<String, LoraInfo> activeLoras;
  final String? error;
  final bool isMock;
  final bool isVideo;
  final Uint8List? videoBytes;
  final String? videoPath;
  final bool isAudio;
  final Uint8List? audioBytes;
  final String? audioPath;
  final int? sampleRate;

  const GenerationResult({
    required this.success,
    required this.imageBytes,
    required this.rawBase64,
    required this.seed,
    required this.inferenceTimeMs,
    required this.width,
    required this.height,
    required this.aspectRatio,
    required this.activeLoras,
    this.error,
    this.isMock = false,
    this.isVideo = false,
    this.videoBytes,
    this.videoPath,
    this.isAudio = false,
    this.audioBytes,
    this.audioPath,
    this.sampleRate,
  });

  factory GenerationResult.failure(String message) => GenerationResult(
        success: false,
        imageBytes: Uint8List(0),
        rawBase64: '',
        seed: -1,
        inferenceTimeMs: 0,
        width: 0,
        height: 0,
        aspectRatio: '9:16',
        activeLoras: const {},
        error: message,
      );

  factory GenerationResult.audio(
    Uint8List audioBytes, {
    String? audioPath,
    int sampleRate = 24000,
    int inferenceTimeMs = 0,
    bool isMock = false,
  }) =>
      GenerationResult(
        success: true,
        imageBytes: Uint8List(0),
        rawBase64: '',
        seed: 0,
        inferenceTimeMs: inferenceTimeMs,
        width: 0,
        height: 0,
        aspectRatio: '1:1',
        activeLoras: const {},
        isAudio: true,
        audioBytes: audioBytes,
        audioPath: audioPath,
        sampleRate: sampleRate,
        isMock: isMock,
      );
}

/// Legacy decoder kept for raw base64 payloads (pre-Part-3 backends).
Uint8List decodeBase64Image(String raw) {
  var clean = raw;
  if (clean.startsWith('data:')) {
    final comma = clean.indexOf(',');
    if (comma != -1) clean = clean.substring(comma + 1);
  }
  return base64Decode(clean);
}
