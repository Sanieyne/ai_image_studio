import 'lora.dart';

/// Outgoing generation payload matching POST /generate (Part 4/5).
class GenerationRequest {
  final String prompt;
  final String negativePrompt;
  final String aspectRatio;
  final int steps;
  final double guidanceScale;
  final int seed;
  final List<LoraConfig>? loras;

  final String? imageBase64;
  final double strength;

  const GenerationRequest({
    required this.prompt,
    this.negativePrompt = 'low quality, bad anatomy, worst quality, blurry',
    this.aspectRatio = '9:16',
    this.steps = 30,
    this.guidanceScale = 7.0,
    this.seed = -1,
    this.loras,
    this.imageBase64,
    this.strength = 0.65,
  });

  Map<String, dynamic> toJson() => {
        'prompt': prompt,
        'negative_prompt': negativePrompt,
        'aspect_ratio': aspectRatio,
        'steps': steps,
        'guidance_scale': guidanceScale,
        'seed': seed,
        if (loras != null && loras!.isNotEmpty)
          'loras': loras!.map((l) => l.toJson()).toList(),
        if (imageBase64 != null && imageBase64!.isNotEmpty)
          'image_base64': imageBase64,
        if (imageBase64 != null && imageBase64!.isNotEmpty)
          'strength': strength,
      };
}
