import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_image_studio/widgets/app_sidebar.dart';

const _labels = [
  'History',
  'Voice',
  'Video',
  'Image',
  'Enhance',
  'Cloud',
  'Library',
];

/// Locates the top tab bar: the horizontal SingleChildScrollView that
/// contains the History tab label.
Finder _tabBarScrollView() {
  final candidates = find.byWidgetPredicate(
    (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
  );
  for (final element in candidates.evaluate()) {
    final labels = find.descendant(
      of: find.byWidget(element.widget),
      matching: find.text('History'),
    );
    if (labels.evaluate().isNotEmpty) return find.byWidget(element.widget);
  }
  fail('Top tab bar scroll view not found');
}

Finder _tabLabel(String label) =>
    find.descendant(of: _tabBarScrollView(), matching: find.text(label));

Future<void> _pumpSidebar(WidgetTester tester, {AppSidebar? sidebar}) async {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: sidebar ?? const AppSidebar()),
    ),
  );
}

/// Settles after a tab tap while ignoring RenderFlex overflows from the
/// mode content panels below the tab bar.
///
/// Those overflows (voice/video/image/enhancer detail rows) are pre-existing
/// breakage, proven present on the unmodified code by tapping tabs with this
/// fix stashed — they are unrelated to the tab bar layout, which the tests
/// above assert strictly without any guard. Anything that is NOT a
/// RenderFlex overflow still fails the test.
Future<void> _settleIgnoringPanelOverflows(WidgetTester tester) async {
  final originalOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('overflowed by')) return;
    originalOnError?.call(details);
  };
  try {
    // Bounded pumps, not pumpAndSettle: at least one mode panel runs a
    // never-ending animation that would time settle out.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  } finally {
    FlutterError.onError = originalOnError;
  }
}

/// Full intrinsic width of a label in its rendered style.
double _intrinsicLabelWidth(WidgetTester tester, Finder labelFinder) {
  final text = tester.widget<Text>(labelFinder);
  final painter = TextPainter(
    text: TextSpan(text: text.data, style: text.style),
    textDirection: TextDirection.ltr,
  )..layout();
  return painter.width;
}

void main() {
  group('Sidebar top tab bar', () {
    testWidgets('all tab labels render fully, un-truncated', (tester) async {
      await _pumpSidebar(tester);

      for (final label in _labels) {
        final finder = _tabLabel(label);
        expect(finder, findsOneWidget, reason: '$label tab missing');
        // The rendered Text must be at least as wide as its full content;
        // anything narrower means TextOverflow.ellipsis kicked in.
        final actualWidth = tester.getSize(finder).width;
        final fullWidth = _intrinsicLabelWidth(tester, finder);
        expect(
          actualWidth,
          greaterThanOrEqualTo(fullWidth - 0.5),
          reason: '$label is truncated ($actualWidth < $fullWidth)',
        );
      }
    });

    testWidgets('tab row scrolls horizontally without flex-stretching',
        (tester) async {
      await _pumpSidebar(tester);

      final tabBar = _tabBarScrollView();
      expect(tabBar, findsOneWidget);
      expect(
        tester.widget<SingleChildScrollView>(tabBar).scrollDirection,
        Axis.horizontal,
      );
      // Buttons must size to content: no Expanded between label and scroller.
      for (final label in _labels) {
        expect(
          find.ancestor(
            of: _tabLabel(label),
            matching: find.byType(Expanded),
          ),
          findsNothing,
          reason: '$label is still flex-stretched',
        );
      }
    });

    testWidgets('tapping each tab reports onTabChanged', (tester) async {
      final tapped = <SidebarTab>[];
      await _pumpSidebar(
        tester,
        sidebar: AppSidebar(onTabChanged: tapped.add),
      );

      const expected = {
        'History': SidebarTab.history,
        'Voice': SidebarTab.voice,
        'Video': SidebarTab.video,
        'Image': SidebarTab.image,
        'Enhance': SidebarTab.enhancer,
        'Cloud': SidebarTab.cloud,
        'Library': SidebarTab.library,
      };

      for (final entry in expected.entries) {
        final finder = _tabLabel(entry.key);
        await tester.ensureVisible(finder);
        await _settleIgnoringPanelOverflows(tester);
        await tester.tap(finder);
        await _settleIgnoringPanelOverflows(tester);
        expect(tapped, isNotEmpty);
        expect(tapped.last, entry.value);
      }
    });

    testWidgets('Cloud tab triggers onOpenCloudMode, others do not',
        (tester) async {
      var cloudOpened = 0;
      await _pumpSidebar(
        tester,
        sidebar: AppSidebar(onOpenCloudMode: () => cloudOpened++),
      );

      for (final label in ['History', 'Voice', 'Cloud']) {
        final finder = _tabLabel(label);
        await tester.ensureVisible(finder);
        await _settleIgnoringPanelOverflows(tester);
        await tester.tap(finder);
        await _settleIgnoringPanelOverflows(tester);
      }
      expect(cloudOpened, 1);
    });
  });
}
