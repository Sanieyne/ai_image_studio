import 'package:flutter_test/flutter_test.dart';

import 'package:ai_image_studio/features/cloud_mode/data/models/saved_generation.dart';

void main() {
  test('SavedGeneration constructor accepts the publish-flow named args', () {
    // Mirrors the SavedGeneration(...) construction in
    // generation_bubble.dart's publish flow. Uses the model's `url`
    // parameter (there is no `mediaUrl`); a rename on either side breaks
    // compilation of this test.
    final gen = SavedGeneration(
      id: 'gen-1',
      userId: '',
      prompt: 'a test prompt',
      negativePrompt: '',
      modelId: 'sdxl-base-1.0',
      mediaType: 'image',
      url: 'https://cdn.example.com/out.png',
      storageKey: '',
      settings: const {'aspectRatio': '1:1'},
      isPublic: false,
      moderationStatus: 'none',
      createdAt: DateTime(2026, 1, 1),
    );

    expect(gen.url, 'https://cdn.example.com/out.png');
    expect(gen.publicUrl, 'https://cdn.example.com/out.png');
  });

  test('SavedGeneration.fromJson reads the backend url field', () {
    final gen = SavedGeneration.fromJson({
      '_id': 'gen-2',
      'userId': 'user-1',
      'mediaType': 'image',
      'storageKey': 'users/u/gen-2.png',
      'prompt': 'p',
      'modelId': 'm',
      'url': 'https://cdn.example.com/gen-2.png',
      'createdAt': '2026-01-01T00:00:00.000Z',
    });

    expect(gen.url, 'https://cdn.example.com/gen-2.png');
  });

  test('publicUrl falls back to storageKey when url is null', () {
    final gen = SavedGeneration(
      id: 'gen-3',
      userId: 'user-1',
      mediaType: 'image',
      storageKey: 'users/u/gen-3.png',
      prompt: 'p',
      modelId: 'm',
      createdAt: DateTime(2026, 1, 1),
    );

    expect(gen.url, isNull);
    expect(gen.publicUrl, 'https://cosmic-gen.com/media/users/u/gen-3.png');
  });
}
