import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_image_studio/models/generation_request.dart';
import 'package:ai_image_studio/models/generation_result.dart';
import 'package:ai_image_studio/widgets/app_sidebar.dart';
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
}
