import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../lib/services/model_download_service.dart';

// Integration test: downloads real model files through the live backend.
// Runs only when COSMIC_TEST_TOKEN holds a valid access token, e.g.
//   COSMIC_TEST_TOKEN=<token> flutter test test/test_model_download.dart
final String? _testToken = Platform.environment['COSMIC_TEST_TOKEN'];

void main() {
  test('Real-ESRGAN end-to-end download and engine path verification', () async {
    print('=== STARTING REAL-ESRGAN END-TO-END DOWNLOAD TEST ===');

    final service = ModelDownloadService.instance;
    const modelId = 'Real-ESRGAN x4plus';

    print('1. Normalizing model ID: "$modelId" -> "${service.normalizeModelId(modelId)}"');
    print('2. Checking models directory: ${service.getModelsBaseDirectory().path}');

    // Check available disk space
    final availBytes = await service.getAvailableDiskSpace();
    print('3. Available disk space: ${availBytes == null ? 'unknown' : '${(availBytes / 1e9).toStringAsFixed(2)} GB'}');

    print('4. Querying download URLs and initiating download from R2...');
    final sub = service.watchProgress(modelId).listen((prog) {
      if (prog.status == ModelDownloadStatus.downloading) {
        print('   [PROGRESS] ${prog.formattedProgress} | File: ${prog.currentFile}');
      }
    });

    try {
      await service.downloadModel(modelId, authToken: _testToken!);
      print('5. Download completed successfully!');
    } finally {
      await sub.cancel();
    }

    // Verification
    final modelDir = service.getModelDirectory(modelId);
    final targetWeight = File('${modelDir.path}/RealESRGAN_x4plus.pth');
    print('6. Target weight file: ${targetWeight.path}');
    expect(targetWeight.existsSync(), isTrue);
    print('   File size: ${(targetWeight.lengthSync() / (1024 * 1024)).toStringAsFixed(2)} MB (${targetWeight.lengthSync()} bytes)');

    // Check engine expectation paths
    final engineCandidate1 = File('/workspace/models/realesrgan/RealESRGAN_x4plus.pth');
    final engineCandidate2 = File('/root/models/realesrgan/RealESRGAN_x4plus.pth');
    print('7. Engine expectation check:');
    print('   /workspace/models/realesrgan/RealESRGAN_x4plus.pth: ${engineCandidate1.existsSync()}');
    print('   /root/models/realesrgan/RealESRGAN_x4plus.pth: ${engineCandidate2.existsSync()}');

    // Verify service status reflects downloaded
    final finalDownloaded = await service.isModelDownloaded(modelId);
    print('8. Final isModelDownloaded: $finalDownloaded (UI reflects "Downloaded ✓")');
    expect(finalDownloaded, isTrue);

    print('\n[SUCCESS] Track 2 End-to-End Download Test Passed!');
  },
      timeout: const Timeout(Duration(minutes: 5)),
      tags: ['integration'],
      skip: (_testToken == null || _testToken!.isEmpty)
          ? 'Integration test: set COSMIC_TEST_TOKEN to run'
          : false);
}
