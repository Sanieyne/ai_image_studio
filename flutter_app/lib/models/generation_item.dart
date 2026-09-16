import 'dart:typed_data';

import 'lora.dart';

enum GenerationStatus { generating, completed, failed }

/// One conversation turn: user prompt + AI output state (Part 5/5).
class GenerationItem {
  final String id;
  final String projectId;
  final String prompt;
  final String negativePrompt;
  final String aspectRatio;
  final String modelName;
  final DateTime timestamp;
  GenerationStatus status;
  Uint8List? imageBytes;
  String? rawBase64;
  int? seed;
  int? inferenceTimeMs;
  Map<String, LoraInfo> activeLoras;
  String? outputImageUrl;
  String? imagePath;
  String? errorMessage;
  bool isMock;
  Uint8List? referenceImageBytes;
  bool isVideo;
  String? videoPath;
  Uint8List? referenceVideoBytes;
  String? referenceVideoName;
  bool isAudio;
  String? audioPath;
  Uint8List? referenceAudioBytes;
  String? referenceAudioName;
  int? sampleRate;
  String? language;

  GenerationItem({
    required this.id,
    required this.projectId,
    required this.prompt,
    this.negativePrompt = '',
    required this.aspectRatio,
    required this.modelName,
    required this.timestamp,
    this.status = GenerationStatus.generating,
    this.imageBytes,
    this.rawBase64,
    this.seed,
    this.inferenceTimeMs,
    this.activeLoras = const {},
    this.outputImageUrl,
    this.imagePath,
    this.errorMessage,
    this.isMock = false,
    this.referenceImageBytes,
    this.isVideo = false,
    this.videoPath,
    this.referenceVideoBytes,
    this.referenceVideoName,
    this.isAudio = false,
    this.audioPath,
    this.referenceAudioBytes,
    this.referenceAudioName,
    this.sampleRate,
    this.language,
  });
}
