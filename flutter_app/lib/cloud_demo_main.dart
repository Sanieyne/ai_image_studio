import 'dart:io';
import 'package:flutter/material.dart';
import 'features/cloud_mode/presentation/screens/cloud_management_screen.dart';
import 'theme/app_theme.dart';

void main() {
  final initialScene = Platform.environment['DEMO_SCENE'] ?? 'recommended';
  runApp(CloudDemoApp(initialScene: initialScene));
}

class CloudDemoApp extends StatefulWidget {
  final String initialScene;
  const CloudDemoApp({super.key, this.initialScene = 'recommended'});

  @override
  State<CloudDemoApp> createState() => _CloudDemoAppState();
}

class _CloudDemoAppState extends State<CloudDemoApp> {
  late String _currentScene;

  @override
  void initState() {
    super.initState();
    _currentScene = widget.initialScene;
  }

  @override
  Widget build(BuildContext context) {
    Set<String> selectedModels;
    int storageGB;
    String gpuTab;

    switch (_currentScene) {
      case 'zero_selection':
        selectedModels = <String>{};
        storageGB = 50;
        gpuTab = 'recommended';
        break;
      case 'slider':
        selectedModels = {'sdxl-base-1.0'};
        storageGB = 100;
        gpuTab = 'recommended';
        break;
      case 'series':
        selectedModels = {'sdxl-base-1.0'};
        storageGB = 50;
        gpuTab = 'series';
        break;
      case 'search':
        selectedModels = {'sdxl-base-1.0'};
        storageGB = 50;
        gpuTab = 'search';
        break;
      case 'telemetry_hidden':
        selectedModels = <String>{};
        storageGB = 50;
        gpuTab = 'recommended';
        break;
      case 'telemetry_shown':
      case 'recommended':
      default:
        selectedModels = {'sdxl-base-1.0'};
        storageGB = 50;
        gpuTab = 'recommended';
        break;
    }

    return MaterialApp(
      title: 'Lumina Cloud GPU Orchestrator Demo',
      debugShowCheckedModeBanner: false,
      theme: LuminaTheme.dark,
      home: Scaffold(
        backgroundColor: const Color(0xFF0F1117),
        body: Column(
          children: [
            // Interactive Scene Switcher Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: const BoxDecoration(
                color: Color(0xFF161922),
                border: Border(bottom: BorderSide(color: Color(0xFF262A36))),
              ),
              child: Row(
                children: [
                  const Icon(Icons.tune_rounded, color: LuminaColors.infoBlue, size: 18),
                  const SizedBox(width: 8),
                  const Text(
                    'DEMO SCENARIO:',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      color: Color(0xFF9EACB9),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _buildSceneBtn('zero_selection', '0. Clean Load (0 Selected)'),
                  const SizedBox(width: 6),
                  _buildSceneBtn('slider', '1. Storage Slider (100 GB)'),
                  const SizedBox(width: 6),
                  _buildSceneBtn('recommended', '2a. Recommended Tab'),
                  const SizedBox(width: 6),
                  _buildSceneBtn('series', '2b. By Series Tab'),
                  const SizedBox(width: 6),
                  _buildSceneBtn('search', '2c. Search Tab'),
                  const SizedBox(width: 6),
                  _buildSceneBtn('telemetry_shown', '3a. Telemetry Shown'),
                  const SizedBox(width: 6),
                  _buildSceneBtn('telemetry_hidden', '3b. Telemetry Hidden'),
                ],
              ),
            ),
            // Cloud Management Screen
            Expanded(
              child: KeyedSubtree(
                key: ValueKey('$_currentScene-$storageGB-${selectedModels.length}-$gpuTab'),
                child: CloudManagementScreen(
                  isDark: true,
                  initialSelectedModelIds: selectedModels,
                  initialStorageGB: storageGB,
                  initialGpuTab: gpuTab,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSceneBtn(String sceneKey, String label) {
    final active = _currentScene == sceneKey;
    return InkWell(
      onTap: () => setState(() => _currentScene = sceneKey),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? LuminaColors.primaryEnd : const Color(0xFF1E2330),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active ? LuminaColors.primaryEnd : const Color(0xFF333A4D),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: active ? FontWeight.bold : FontWeight.w500,
            color: active ? Colors.white : const Color(0xFFC5D1DE),
          ),
        ),
      ),
    );
  }
}
