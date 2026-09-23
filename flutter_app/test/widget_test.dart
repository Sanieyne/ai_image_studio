import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_image_studio/models/generation_item.dart';
import 'package:ai_image_studio/models/generation_request.dart';
import 'package:ai_image_studio/models/generation_result.dart';
import 'package:ai_image_studio/services/api_service.dart';
import 'package:ai_image_studio/widgets/app_sidebar.dart';
import 'package:ai_image_studio/widgets/prompt_input_bar.dart';
import 'package:ai_image_studio/widgets/settings_dialog.dart';

void main() {
  test('GenerationResult failure constructor smoke test', () {
    final result = GenerationResult.failure('Network timeout');
    expect(result.success, isFalse);
    expect(result.error, 'Network timeout');
  });

  test('GenerationRequest serialization smoke test', () {
    const req = GenerationRequest(prompt: 'A futuristic city');
    final json = req.toJson();
    expect(json['prompt'], 'A futuristic city');
  });

  testWidgets('SidebarProjectTile inline editing flow: rename commit',
      (tester) async {
    String? renamed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SidebarProjectTile(
            icon: Icons.movie_creation_outlined,
            title: 'Initial Title',
            onRename: (val) => renamed = val,
          ),
        ),
      ),
    );

    expect(find.text('Initial Title'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    // Hover to reveal more_horiz button
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byType(SidebarProjectTile)));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.more_horiz), findsOneWidget);
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();

    // Tap 'Rename'
    expect(find.text('Rename'), findsOneWidget);
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    // Verify NO AlertDialog was shown
    expect(find.byType(AlertDialog), findsNothing);

    // Verify inline TextField and checkmark button appear
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);

    // Enter new text and tap checkmark
    await tester.enterText(find.byType(TextField), 'New Project Name');
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();

    // Verify callback was called with new title and editing finished
    expect(renamed, 'New Project Name');
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('SidebarProjectTile cancel editing on Escape',
      (tester) async {
    String? renamed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SidebarProjectTile(
            icon: Icons.movie_creation_outlined,
            title: 'Initial Title',
            onRename: (val) => renamed = val,
          ),
        ),
      ),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byType(SidebarProjectTile)));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Discarded Title');
    await tester.pumpAndSettle();

    // Send Escape key
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // Verify rename was NOT called and TextField closed
    expect(renamed, isNull);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Initial Title'), findsOneWidget);
  });

  testWidgets('SidebarProjectTile submit rename on Enter key',
      (tester) async {
    String? renamed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SidebarProjectTile(
            icon: Icons.movie_creation_outlined,
            title: 'Initial Title',
            onRename: (val) => renamed = val,
          ),
        ),
      ),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byType(SidebarProjectTile)));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Submitted via Enter');
    await tester.pumpAndSettle();

    // Submit on Enter
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(renamed, 'Submitted via Enter');
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('SidebarProjectTile cancel editing on focus loss without submission',
      (tester) async {
    String? renamed;
    final otherFocusNode = FocusNode();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SidebarProjectTile(
                icon: Icons.movie_creation_outlined,
                title: 'Initial Title',
                onRename: (val) => renamed = val,
              ),
              TextField(
                focusNode: otherFocusNode,
                key: const Key('outside_field'),
              ),
            ],
          ),
        ),
      ),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byType(SidebarProjectTile)));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNWidgets(2));
    await tester.enterText(find.byType(TextField).first, 'Unsubmitted Text');
    await tester.pumpAndSettle();

    // Tap outside to lose focus
    await tester.tap(find.byKey(const Key('outside_field')));
    await tester.pumpAndSettle();

    expect(renamed, isNull);
    expect(find.text('Initial Title'), findsOneWidget);
  });

  testWidgets('AppSidebar avatar popup menu opens and contains items',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppSidebar(),
        ),
      ),
    );

    // Profile card has 'Alex Dan'
    expect(find.text('Alex Dan'), findsOneWidget);

    // Tap profile card to open popup menu
    await tester.tap(find.text('Alex Dan'));
    await tester.pumpAndSettle();

    // Verify popup menu items
    expect(find.text('Account Settings'), findsOneWidget);
    expect(find.text('Models & Paths'), findsOneWidget);
    expect(find.text('Preferences'), findsOneWidget);
    expect(find.text('Sign Out'), findsOneWidget);

    // Tap 'Account Settings' -> opens SettingsDialog
    await tester.tap(find.text('Account Settings'));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsDialog), findsOneWidget);
    expect(find.text('Account Overview'), findsOneWidget);
    expect(find.text('2,450 Credits'), findsOneWidget);
  });

  testWidgets('SettingsDialog tab navigation and reset functionality',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SettingsDialog(initialTab: 1),
        ),
      ),
    );

    expect(find.text('Models & Local Paths'), findsOneWidget);
    expect(find.text('Base SDXL Checkpoint / Repo ID'), findsOneWidget);
    expect(find.text('Save & Apply Paths'), findsOneWidget);

    // Modify text in model field and reset
    await tester.enterText(find.byType(TextField).first, 'custom/model-id');
    await tester.pumpAndSettle();
    expect(find.text('custom/model-id'), findsOneWidget);

    // Tap 'Reset'
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(
        find.text('stabilityai/stable-diffusion-xl-base-1.0'), findsOneWidget);

    // Switch to 'Inference Defaults' tab
    await tester.tap(find.text('Inference Defaults'));
    await tester.pumpAndSettle();
    expect(find.text('Default Negative Prompt'), findsOneWidget);

    // Switch to 'Account' tab
    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();
    expect(find.text('Account Overview'), findsOneWidget);
    expect(find.text('128 Images'), findsOneWidget);
  });

  test('GenerationResult audio factory constructor test', () {
    final dummyWav = Uint8List.fromList([82, 73, 70, 70, 0, 0, 0, 0]);
    final result = GenerationResult.audio(
      dummyWav,
      audioPath: '/tmp/test.wav',
      sampleRate: 24000,
      inferenceTimeMs: 1250,
    );

    expect(result.success, isTrue);
    expect(result.isAudio, isTrue);
    expect(result.audioBytes, equals(dummyWav));
    expect(result.audioPath, '/tmp/test.wav');
    expect(result.sampleRate, 24000);
    expect(result.inferenceTimeMs, 1250);
  });

  test('GenerationItem audio attributes serialization and clone test', () {
    final item = GenerationItem(
      id: 'item-123',
      projectId: 'proj-1',
      prompt: 'Hello Chatterbox voice',
      aspectRatio: '1:1',
      modelName: 'Chatterbox TTS',
      timestamp: DateTime(2026, 1, 1),
      isAudio: true,
      audioPath: '/data/audio/item-123.wav',
      language: 'fr',
      referenceAudioName: 'ref.wav',
    );

    expect(item.isAudio, isTrue);
    expect(item.audioPath, '/data/audio/item-123.wav');
    expect(item.language, 'fr');
    expect(item.referenceAudioName, 'ref.wav');

    item.audioPath = '/data/audio/updated.wav';
    item.language = 'es';
    expect(item.audioPath, '/data/audio/updated.wav');
    expect(item.language, 'es');
    expect(item.isAudio, isTrue);
  });

  test('ApiService generateVoice in offline mock mode produces valid WAV bytes', () async {
    ApiService.forceMockMode = true;
    final api = ApiService();
    final result = await api.generateVoice(
      prompt: 'Testing mock voice synthesis',
      language: 'en',
      exaggeration: 0.6,
      cfgWeight: 0.5,
    );

    expect(result.success, isTrue);
    expect(result.isAudio, isTrue);
    expect(result.audioBytes, isNotNull);
    expect(result.audioBytes!.length, greaterThan(44)); // WAV header is 44 bytes
    expect(result.sampleRate, 24000);
    // Check RIFF header magic bytes: 'R' 'I' 'F' 'F'
    expect(result.audioBytes![0], 0x52);
    expect(result.audioBytes![1], 0x49);
    expect(result.audioBytes![2], 0x46);
    expect(result.audioBytes![3], 0x46);
  });

  test('AvailableModelInfo fromJson parses fields accurately', () {
    final info = AvailableModelInfo.fromJson({
      'id': 'Qwen/Qwen-Image-2.1',
      'label': 'Qwen-Image 2.1',
      'family': 'qwen',
      'mode': 'image',
      'is_active': true,
      'is_downloaded': true,
      'default_steps': 40,
      'default_guidance': 1.0,
      'gated': false,
      'note': 'Unified 7B DiT',
    });

    expect(info.id, 'Qwen/Qwen-Image-2.1');
    expect(info.label, 'Qwen-Image 2.1');
    expect(info.family, 'qwen');
    expect(info.mode, 'image');
    expect(info.isActive, isTrue);
    expect(info.isDownloaded, isTrue);
    expect(info.defaultSteps, 40);
    expect(info.defaultGuidance, 1.0);
  });

  testWidgets('PromptInputBar programmatic mode switch updates model to mode models',
      (tester) async {
    final key = GlobalKey<PromptInputBarState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PromptInputBar(key: key),
        ),
      ),
    );

    // Initial state is 'Motion Animate' with 'Wan 2.2 Animate 14B'
    expect(find.text('Motion Animate'), findsOneWidget);
    expect(find.text('Wan 2.2 Animate 14B'), findsOneWidget);

    // Programmatically switch mode to 'Image Mode'
    key.currentState!.setMode('Image Mode');
    await tester.pumpAndSettle();

    // Now mode is 'Image Mode' and model switched to 'Qwen-Image 2.1'
    expect(find.text('Image Mode'), findsOneWidget);
    expect(find.text('Qwen-Image 2.1'), findsOneWidget);

    // Programmatically switch mode to 'Voice Studio'
    key.currentState!.setMode('Voice Studio');
    await tester.pumpAndSettle();

    expect(find.text('Voice Studio'), findsOneWidget);
    expect(find.text('Chatterbox TTS'), findsOneWidget);
  });
}
