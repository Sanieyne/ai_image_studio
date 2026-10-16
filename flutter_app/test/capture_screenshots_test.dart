import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_image_studio/theme/app_theme.dart';
import 'package:ai_image_studio/features/cloud_mode/presentation/screens/instance_provisioning_screen.dart';

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
    print('[+] Real fonts & MaterialIcons loaded successfully');
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
    await loadRealFonts();
  });

  testWidgets('Capture Local Mode Model Download Progress', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 850));
    final repaintKey = GlobalKey();

    final darkTheme = LuminaTheme.dark.copyWith(
      textTheme: LuminaTheme.dark.textTheme.apply(fontFamily: 'Roboto'),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: darkTheme,
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: const Color(0xFF090A0F),
          body: Center(
            child: RepaintBoundary(
              key: repaintKey,
              child: Container(
                width: 620,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF13151F),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF232738)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.6),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Model header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: LuminaColors.primaryStart.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: LuminaColors.primaryStart.withOpacity(0.3)),
                          ),
                          child: const Icon(Icons.auto_awesome_rounded, color: LuminaColors.primaryEnd, size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Text(
                                    'SDXL Base 1.0 + InstantID',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Roboto'),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: LuminaColors.primaryStart.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'FACE-LOCK',
                                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: LuminaColors.primaryEnd, fontFamily: 'Roboto'),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              const Text(
                                'Native 1024x1024 diffusion model with zero-shot identity preservation',
                                style: TextStyle(fontSize: 12, color: Colors.white60, fontFamily: 'Roboto'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Pre-flight dialog / storage info pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.sd_storage_rounded, size: 15, color: Colors.white60),
                              SizedBox(width: 6),
                              Text('Model Size: 4.62 GB', style: TextStyle(fontSize: 12, color: Colors.white70, fontFamily: 'Roboto')),
                            ],
                          ),
                          Row(
                            children: [
                              Icon(Icons.check_circle_rounded, size: 15, color: Colors.greenAccent),
                              SizedBox(width: 6),
                              Text('Available Disk: 48.2 GB', style: TextStyle(fontSize: 12, color: Colors.greenAccent, fontWeight: FontWeight.w600, fontFamily: 'Roboto')),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // The Live Downloading Progress Widget (active in-place)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Expanded(
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation(LuminaColors.primaryEnd),
                                    ),
                                  ),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Downloading: 2.82 GB / 4.62 GB (61.0%) • 43.5 MB/s',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: LuminaColors.primaryEnd,
                                        fontFamily: 'Roboto',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Icon(Icons.pause_rounded, size: 15, color: Colors.white70),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Icon(Icons.close_rounded, size: 15, color: Colors.white70),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: const LinearProgressIndicator(
                            value: 0.61,
                            minHeight: 6,
                            backgroundColor: Colors.white12,
                            valueColor: AlwaysStoppedAnimation(LuminaColors.primaryStart),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Est. time remaining: 41s', style: TextStyle(fontSize: 11, color: Colors.white38, fontFamily: 'Roboto')),
                            Text('Source: Cloudflare R2 (cosmic-gen)', style: TextStyle(fontSize: 11, color: Colors.white38, fontFamily: 'Roboto')),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await saveScreenshot(repaintKey, '/root/instantid_test_outputs/web/screenshots/local_model_download_progress.png');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Capture Cloud Mode Instance Provisioning & Streaming Progress', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 950));
    final repaintKey = GlobalKey();

    final testModels = [
      const ModelProvisioningItem(
        modelId: 'sdxl-base-1.0',
        status: 'downloading',
        progressPercent: 68.4,
      ),
      const ModelProvisioningItem(
        modelId: 'instantid',
        status: 'ready',
        progressPercent: 100.0,
        loadedInVram: true,
      ),
      const ModelProvisioningItem(
        modelId: 'realesrgan-x4plus',
        status: 'ready',
        progressPercent: 100.0,
        loadedInVram: false,
      ),
      const ModelProvisioningItem(
        modelId: 'wan-2.1-t2v-1.3b',
        status: 'queued',
        progressPercent: 0.0,
      ),
    ];

    final darkTheme = LuminaTheme.dark.copyWith(
      textTheme: LuminaTheme.dark.textTheme.apply(fontFamily: 'Roboto'),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: darkTheme,
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(
          key: repaintKey,
          child: InstanceProvisioningScreen(
            instanceId: 'vast-54640755',
            gpuName: 'NVIDIA RTX 3090 (24GB VRAM)',
            selectedModelIds: const ['sdxl-base-1.0', 'instantid', 'realesrgan-x4plus', 'wan-2.1-t2v-1.3b'],
            isDark: true,
            disableAutoConnect: true,
            initialPreviewState: ProvisioningState.downloadingModel,
            initialModels: testModels,
            initialDeviceInfo: '151.237.25.16:29110 (Bulgaria, BG)',
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await saveScreenshot(repaintKey, '/root/instantid_test_outputs/web/screenshots/cloud_provisioning_streaming_progress.png');
    await tester.pumpWidget(const SizedBox());
  });
}
