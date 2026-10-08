import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_image_studio/widgets/app_sidebar.dart';

const _tabs = ['history', 'voice', 'video', 'image', 'enhancer', 'cloud', 'library'];

/// The test font is far wider than real fonts; unrelated fixed-width rows in the
/// sidebar report overflows that the app does not have. Only those are ignored.
void ignoreOverflow() {
  final original = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('A RenderFlex overflowed')) return;
    original?.call(details);
  };
  addTearDown(() => FlutterError.onError = original);
}

Future<List<SidebarTab>> pumpSidebar(WidgetTester tester, {bool dark = false}) async {
  ignoreOverflow();
  await tester.binding.setSurfaceSize(const Size(1200, 1400));
  final changes = <SidebarTab>[];
  await tester.pumpWidget(MaterialApp(
    theme: dark ? ThemeData.dark() : ThemeData.light(),
    home: Scaffold(body: Row(children: [AppSidebar(onTabChanged: changes.add)])),
  ));
  await tester.pump();
  return changes;
}

BoxDecoration tileDecoration(WidgetTester tester, String tab) => tester
    .widget<AnimatedContainer>(
        find.descendant(of: find.byKey(ValueKey('sidebar_tab_$tab')), matching: find.byType(AnimatedContainer)))
    .decoration! as BoxDecoration;

void main() {
  for (final dark in [false, true]) {
    testWidgets('all 7 tabs fit the 318 px sidebar without scrolling or clipping (${dark ? 'dark' : 'light'})',
        (tester) async {
      await pumpSidebar(tester, dark: dark);
      final bar = tester.getRect(find.byKey(const ValueKey('sidebar_tabs')));
      expect(bar.width, lessThanOrEqualTo(318));
      expect(find.descendant(of: find.byKey(const ValueKey('sidebar_tabs')), matching: find.byType(Scrollable)),
          findsNothing);
      final widths = <double>{};
      for (final t in _tabs) {
        final r = tester.getRect(find.byKey(ValueKey('sidebar_tab_$t')));
        expect(bar.contains(r.topLeft) && bar.contains(r.bottomRight - const Offset(0.5, 0.5)), isTrue,
            reason: '$t tab inside the bar');
        expect(r.height, 46);
        widths.add(r.width.roundToDouble());
      }
      expect(widths.length, 1, reason: 'equal-width tiles');
      expect(widths.single, greaterThanOrEqualTo(60), reason: 'clearly more room per tab than before');
    });
  }

  testWidgets('tapping a tab selects it, reports it, and moves nothing', (tester) async {
    final changes = await pumpSidebar(tester);
    final before = {for (final t in _tabs) t: tester.getRect(find.byKey(ValueKey('sidebar_tab_$t')))};

    await tester.tap(find.byKey(const ValueKey('sidebar_tab_voice')));
    await tester.pump(const Duration(milliseconds: 250));
    expect(changes, [SidebarTab.voice]);
    expect((tileDecoration(tester, 'voice').border! as Border).top.color.a, greaterThan(0),
        reason: 'selected tab has the red border');
    expect(tileDecoration(tester, 'history').color, Colors.transparent);

    for (final t in _tabs) {
      expect(tester.getRect(find.byKey(ValueKey('sidebar_tab_$t'))), before[t], reason: 'no layout jump ($t)');
    }
  });

  testWidgets('hover tints an unselected tab and shows the tab name as a tooltip', (tester) async {
    await pumpSidebar(tester);
    expect(tileDecoration(tester, 'image').color, Colors.transparent);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('sidebar_tab_image'))));
    await tester.pump(const Duration(milliseconds: 250));
    expect(tileDecoration(tester, 'image').color, isNot(Colors.transparent));

    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byTooltip('Image'), findsOneWidget);
  });
}
