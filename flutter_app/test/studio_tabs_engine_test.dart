import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_image_studio/services/engine_process_manager.dart';
import 'package:ai_image_studio/widgets/app_sidebar.dart';
import 'package:ai_image_studio/widgets/model_download_button.dart';
import 'package:ai_image_studio/widgets/prompt_input_bar.dart';
import 'package:ai_image_studio/widgets/top_bar.dart';

class _ComposerHost extends StatefulWidget {
  final GlobalKey<PromptInputBarState> barKey;
  const _ComposerHost({super.key, required this.barKey});
  @override
  State<_ComposerHost> createState() => _ComposerHostState();
}

class _ComposerHostState extends State<_ComposerHost> {
  String? tab = 'voice';
  void setTab(String? t) => setState(() => tab = t);
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(width: 760, child: PromptInputBar(key: widget.barKey, studioTab: tab)),
        ),
      );
}

/// The test font is much wider than real fonts, so existing fixed-width rows in
/// the sidebar and top bar report overflows that do not happen in the app.
/// Only those layout warnings are ignored; any other error still fails the test.
void ignoreOverflow() {
  final original = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('A RenderFlex overflowed')) return;
    original?.call(details);
  };
  addTearDown(() => FlutterError.onError = original);
}

void main() {
  group('composer follows the sidebar tab', () {
    testWidgets('created under the Voice tab it shows Voice Studio, not Motion Animate', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      final barKey = GlobalKey<PromptInputBarState>();
      final hostKey = GlobalKey<_ComposerHostState>();
      await tester.pumpWidget(MaterialApp(home: _ComposerHost(key: hostKey, barKey: barKey)));
      await tester.pump();
      expect(barKey.currentState!.mode, 'Voice Studio');

      hostKey.currentState!.setTab('video');
      await tester.pump();
      expect(barKey.currentState!.mode, 'Video Mode');

      hostKey.currentState!.setTab('enhancer');
      await tester.pump();
      expect(barKey.currentState!.mode, 'AI Enhancer');
    });

    testWidgets('a mode that already belongs to the new tab is kept (e.g. a template just applied)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      final barKey = GlobalKey<PromptInputBarState>();
      final hostKey = GlobalKey<_ComposerHostState>();
      await tester.pumpWidget(MaterialApp(home: _ComposerHost(key: hostKey, barKey: barKey)));
      await tester.pump();
      // A video template picks Wan 2.2 Animate before the tab switches to Video.
      barKey.currentState!.setVideoModel('Wan 2.2 Animate 14B');
      hostKey.currentState!.setTab('video');
      await tester.pump();
      expect(barKey.currentState!.modeBelongsToTab('video'), isTrue);
      expect(barKey.currentState!.mode, 'Video Mode');
    });
  });

  group('voice panel', () {
    testWidgets('voice models are cards with download buttons; Breeze is cloud only', (tester) async {
      ignoreOverflow();
      await tester.binding.setSurfaceSize(const Size(420, 2400));
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: AppSidebar(activeTab: SidebarTab.voice))));
      await tester.pump();
      expect(find.byType(DropdownButton<String>), findsNothing, reason: 'no model dropdown any more');
      for (final title in ['Chatterbox TTS', 'Chatterbox Multilingual V3', 'Breeze TTS 2']) {
        expect(find.byKey(ValueKey('voice_model_card_$title')), findsOneWidget);
      }
      final buttons = tester.widgetList<ModelDownloadButton>(find.byType(ModelDownloadButton)).toList();
      expect(buttons.map((b) => b.modelId), ['chatterbox-tts', 'chatterbox-tts'],
          reason: 'both Chatterbox models use the one download that holds both sets of weights');
      expect(find.text('Cloud only'), findsOneWidget);
      expect(find.text('Runs on a cloud GPU; no local download.'), findsOneWidget);
    });
  });

  group('local engine status in the top bar', () {
    Widget bar() => MaterialApp(
          home: Scaffold(
            appBar: TopBar(engineOnline: false, isDark: false, onThemeToggle: () {}),
          ),
        );

    testWidgets('starting and failed are told apart, with the reason', (tester) async {
      ignoreOverflow();
      await tester.binding.setSurfaceSize(const Size(2400, 400));
      final status = EngineProcessManager.instance.status;
      status.value = const EngineStatus(EngineRunPhase.starting);
      await tester.pumpWidget(bar());
      expect(find.text('Engine starting…'), findsOneWidget);

      status.value = const EngineStatus(EngineRunPhase.failed, 'the engine stopped (exit code 3)');
      await tester.pump();
      expect(find.text('Engine failed: the engine stopped (exit code 3)'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('engine_status_menu')));
      await tester.pumpAndSettle();
      expect(find.text('Open engine log'), findsOneWidget);
      expect(find.text('Restart engine'), findsOneWidget);
      status.value = const EngineStatus(EngineRunPhase.idle);
    });
  });
}
