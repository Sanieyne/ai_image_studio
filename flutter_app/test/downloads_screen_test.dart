import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:ai_image_studio/theme/app_theme.dart';
import 'package:ai_image_studio/screens/downloads_screen.dart';
import 'package:ai_image_studio/widgets/top_bar.dart';
import 'package:ai_image_studio/widgets/model_download_button.dart';
import 'package:ai_image_studio/services/model_download_service.dart';

Future<void> loadRealFonts() async {
  try {
    final fontLoader = FontLoader('Roboto');
    final regFile = File('/usr/share/fonts/truetype/roboto/unhinted/RobotoTTF/Roboto-Regular.ttf');
    final boldFile = File('/usr/share/fonts/truetype/roboto/unhinted/RobotoTTF/Roboto-Bold.ttf');
    final medFile = File('/usr/share/fonts/truetype/roboto/unhinted/RobotoTTF/Roboto-Medium.ttf');

    if (regFile.existsSync()) {
      fontLoader.addFont(regFile.readAsBytes().then((b) => b.buffer.asByteData()));
    }
    if (boldFile.existsSync()) {
      fontLoader.addFont(boldFile.readAsBytes().then((b) => b.buffer.asByteData()));
    }
    if (medFile.existsSync()) {
      fontLoader.addFont(medFile.readAsBytes().then((b) => b.buffer.asByteData()));
    }
    await fontLoader.load();

    final iconLoader = FontLoader('MaterialIcons');
    final iconFile = File('/opt/flutter/engine/src/flutter/tools/font_subset/fixtures/MaterialIcons-Regular.ttf');
    if (iconFile.existsSync()) {
      iconLoader.addFont(iconFile.readAsBytes().then((b) => b.buffer.asByteData()));
      await iconLoader.load();
    }
    print('[+] Real fonts and MaterialIcons loaded successfully');
  } catch (e) {
    print('[!] Error loading fonts: $e');
  }
}

Future<void> saveScreenshot(GlobalKey key, String path) async {
  final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 2.0);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  final pngBytes = byteData!.buffer.asUint8List();
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(pngBytes);
  print('Saved screenshot: $path (${pngBytes.length} bytes)');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    HttpOverrides.global = null;
    await loadRealFonts();

    // Acquire auth token for test
    try {
      final tokenRes = await http.post(
        Uri.parse('http://localhost:5000/api/v1/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': 'testdownload@example.com', 'password': 'Password123!'}),
      );
      if (tokenRes.statusCode == 200) {
        final json = jsonDecode(tokenRes.body);
        ModelDownloadService.instance.defaultAuthToken = json['data']['accessToken'];
        print('[+] Test Auth Token acquired: ${ModelDownloadService.instance.defaultAuthToken?.substring(0, 15)}...');
      }
    } catch (e) {
      print('[!] Error obtaining token: $e');
    }
  });

  testWidgets('DownloadsScreen and TopBar: 3 states verification and screenshot capture',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1300, 920));

    final repaintKey = GlobalKey();
    final darkTheme = LuminaTheme.dark.copyWith(
      textTheme: LuminaTheme.dark.textTheme.apply(fontFamily: 'Roboto'),
    );

    final service = ModelDownloadService.instance;
    await service.deleteModel('realesrgan-x4plus');

    Widget buildTestApp() {
      return MaterialApp(
        theme: darkTheme,
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: LuminaColors.darkBg,
          body: RepaintBoundary(
            key: repaintKey,
            child: Column(
              children: [
                TopBar(
                  engineOnline: true,
                  cloudOnline: false,
                  credits: 2450,
                  isDark: true,
                  onThemeToggle: () {},
                  workspaceLabel: 'Neural Inference Hub',
                  onOpenDownloads: () {},
                ),
                const Expanded(
                  child: DownloadsScreen(),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // -------------------------------------------------------------
    // INITIAL LOAD
    // -------------------------------------------------------------
    print('\n>>> INITIAL APP PUMP');
    await tester.pumpWidget(buildTestApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Run full download lifecycle within real async context so network stream never stalls
    await tester.runAsync(() async {
      // -------------------------------------------------------------
      // STATE 1: ACTIVE DOWNLOADING
      // -------------------------------------------------------------
      print('\n>>> TESTING STATE 1: ACTIVE DOWNLOADING');
      print('Starting Real-ESRGAN download...');
      final downloadFuture = service.downloadModel('realesrgan-x4plus');

      // Wait until download reaches downloading status in real time
      for (var i = 0; i < 60; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        final status = service.getCurrentProgress('realesrgan-x4plus')?.status;
        print('RealAsync Loop $i: status=$status, active=${service.hasActiveDownloads}');
        if (status == ModelDownloadStatus.downloading) {
          break;
        }
      }

      // Pump widget to let TopBar and DownloadsScreen react to the live stream
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Verify State 1 UI
      expect(find.text('Downloading now'), findsOneWidget);
      expect(find.text('Real-ESRGAN x4plus'), findsWidgets);
      expect(find.text('Pause'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      // Capture State 1 Screenshot
      final shot1Path = '/root/.gemini/antigravity-cli/brain/af25ee55-4eed-4ab7-8bda-96ab5772a742/state_1_downloading_now.png';
      await saveScreenshot(repaintKey, shot1Path);
      await File(shot1Path).copy('/var/www/instantid/screenshots/state_1_downloading_now.png');

      // -------------------------------------------------------------
      // STATE 2: DOWNLOADED
      // -------------------------------------------------------------
      print('\n>>> TESTING STATE 2: DOWNLOADED STATE');
      // Wait for the download future to complete in real time
      await downloadFuture;
      for (var i = 0; i < 60; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (await service.isModelDownloaded('realesrgan-x4plus')) {
          break;
        }
      }

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Verify State 2 UI
      expect(find.text('Downloaded'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      expect(find.text('Downloading now'), findsNothing);

      // Capture State 2 Screenshot
      final shot2Path = '/root/.gemini/antigravity-cli/brain/af25ee55-4eed-4ab7-8bda-96ab5772a742/state_2_downloaded.png';
      await saveScreenshot(repaintKey, shot2Path);
      await File(shot2Path).copy('/var/www/instantid/screenshots/state_2_downloaded.png');

      // -------------------------------------------------------------
      // STATE 3: AVAILABLE TO DOWNLOAD (AFTER DELETION)
      // -------------------------------------------------------------
      print('\n>>> TESTING STATE 3: AVAILABLE TO DOWNLOAD AFTER DELETION');
      final deleteButton = find.widgetWithText(OutlinedButton, 'Delete');
      expect(deleteButton, findsOneWidget);
      await tester.tap(deleteButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Confirm dialog
      expect(find.text('Delete Model Weights?'), findsOneWidget);
      final confirmDeleteButton = find.widgetWithText(ElevatedButton, 'Delete');
      expect(confirmDeleteButton, findsOneWidget);
      await tester.tap(confirmDeleteButton);
      await Future.delayed(const Duration(milliseconds: 400));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Verify State 3 UI
      expect(find.text('No models downloaded yet'), findsOneWidget);
      expect(find.text('Available to download'), findsOneWidget);

      // Capture State 3 Screenshot
      final shot3Path = '/root/.gemini/antigravity-cli/brain/af25ee55-4eed-4ab7-8bda-96ab5772a742/state_3_available_after_delete.png';
      await saveScreenshot(repaintKey, shot3Path);
      await File(shot3Path).copy('/var/www/instantid/screenshots/state_3_available_after_delete.png');

      print('\n[SUCCESS] All 3 States Verified & Captured Successfully!');
    });
  });
}
