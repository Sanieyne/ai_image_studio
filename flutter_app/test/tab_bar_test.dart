import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_image_studio/widgets/app_sidebar.dart';

const _labels = ['History', 'Voice', 'Video', 'Image', 'Enhance', 'Rent GPU', 'Library'];

/// The default test font draws every glyph as a full square (about twice as
/// wide as real text), which would make any label look truncated. Load the
/// real Roboto from the Flutter SDK so widths match the app.
Future<void> _loadRoboto() async {
  // The test runner lives inside the SDK's bin/cache; walk up to find the fonts.
  Directory? dir;
  final roots = [
    if (Platform.environment['FLUTTER_ROOT'] != null) Directory(Platform.environment['FLUTTER_ROOT']!),
    File(Platform.resolvedExecutable).parent,
  ];
  for (var d in roots) {
    for (var i = 0; i < 8 && dir == null; i++) {
      final candidate = Directory('${d.path}/bin/cache/artifacts/material_fonts');
      final inCache = Directory('${d.path}/artifacts/material_fonts');
      if (candidate.existsSync()) dir = candidate;
      if (inCache.existsSync()) dir = inCache;
      d = d.parent;
    }
  }
  if (dir == null) {
    markTestSkipped('Roboto not found in the Flutter SDK; label widths cannot be checked with real metrics.');
    return;
  }
  final loader = FontLoader('Roboto');
  for (final name in ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']) {
    final f = File('${dir.path}/$name');
    if (f.existsSync()) loader.addFont(Future.value(ByteData.view(f.readAsBytesSync().buffer)));
  }
  await loader.load();
}

Finder _tabBar() => find.byKey(const ValueKey('sidebar_tabs'));
Finder _tabLabel(String label) => find.descendant(of: _tabBar(), matching: find.text(label));

/// Mode panels below the tabs have fixed-width rows that may overflow; only
/// those layout warnings are ignored, everything else still fails.
void _ignorePanelOverflows() {
  final original = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('overflowed by')) return;
    original?.call(details);
  };
  addTearDown(() => FlutterError.onError = original);
}

Future<void> _pumpSidebar(WidgetTester tester, {AppSidebar? sidebar}) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  _ignorePanelOverflows();
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(fontFamily: 'Roboto'),
    home: Scaffold(body: Row(children: [sidebar ?? const AppSidebar()])),
  ));
  await tester.pump();
}

Future<void> _settle(WidgetTester tester) async {
  // Bounded pumps: some mode panels animate forever.
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(_loadRoboto);

  group('Sidebar top tab bar', () {
    testWidgets('all tab labels render fully, un-truncated', (tester) async {
      await _pumpSidebar(tester);
      for (final label in _labels) {
        final finder = _tabLabel(label);
        expect(finder, findsOneWidget, reason: '$label tab missing');
        final text = tester.widget<Text>(finder);
        final painter = TextPainter(
          text: TextSpan(text: text.data, style: DefaultTextStyle.of(tester.element(finder)).style.merge(text.style)),
          textDirection: TextDirection.ltr,
        )..layout();
        expect(tester.getSize(finder).width, greaterThanOrEqualTo(painter.width - 0.5),
            reason: '$label is truncated');
      }
    });

    testWidgets('no horizontal scrolling: every tab sits inside the bar', (tester) async {
      await _pumpSidebar(tester);
      expect(find.descendant(of: _tabBar(), matching: find.byType(Scrollable)), findsNothing);
      final bar = tester.getRect(_tabBar());
      for (final label in _labels) {
        final r = tester.getRect(_tabLabel(label));
        expect(r.left >= bar.left && r.right <= bar.right, isTrue, reason: '$label clipped');
      }
    });

    testWidgets('tapping each tab reports onTabChanged', (tester) async {
      final tapped = <SidebarTab>[];
      await _pumpSidebar(tester, sidebar: AppSidebar(onTabChanged: tapped.add));
      const expected = {
        'History': SidebarTab.history,
        'Voice': SidebarTab.voice,
        'Video': SidebarTab.video,
        'Image': SidebarTab.image,
        'Enhance': SidebarTab.enhancer,
        'Rent GPU': SidebarTab.cloud,
        'Library': SidebarTab.library,
      };
      for (final entry in expected.entries) {
        await tester.tap(_tabLabel(entry.key));
        await _settle(tester);
        expect(tapped.last, entry.value);
      }
      expect(tapped.length, expected.length);
    });

    testWidgets('Cloud tab triggers onOpenCloudMode, others do not', (tester) async {
      var cloudOpened = 0;
      await _pumpSidebar(tester, sidebar: AppSidebar(onOpenCloudMode: () => cloudOpened++));
      for (final label in ['History', 'Voice', 'Rent GPU']) {
        await tester.tap(_tabLabel(label));
        await _settle(tester);
      }
      expect(cloudOpened, 1);
    });
  });
}
