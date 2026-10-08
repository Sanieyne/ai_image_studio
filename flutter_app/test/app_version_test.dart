import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_image_studio/app_version.dart';
import 'package:ai_image_studio/widgets/settings_dialog.dart';

void main() {
  test('the version shown in the app matches pubspec.yaml', () {
    final line = File('pubspec.yaml').readAsLinesSync().firstWhere((l) => l.startsWith('version:'));
    expect(line.trim(), 'version: $kAppVersion+$kAppBuildNumber');
  });

  testWidgets('Settings shows the real version', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SettingsDialog(initialTab: 2))));
    expect(tester.widget<Text>(find.byKey(const ValueKey('settings_app_version'))).data,
        'Cosmic-Gen Studio v$kAppVersion (build $kAppBuildNumber)');
  });
}
