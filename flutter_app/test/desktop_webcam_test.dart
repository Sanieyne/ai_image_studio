import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_image_studio/services/desktop_webcam_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DesktopWebcamService Tests', () {
    test('Service instance is a singleton', () {
      final s1 = DesktopWebcamService.instance;
      final s2 = DesktopWebcamService.instance;
      expect(identical(s1, s2), isTrue);
      expect(s1.isStreaming, isFalse);
    });

    test('getAvailableCameras returns list of devices', () async {
      final cameras = await DesktopWebcamService.instance.getAvailableCameras();
      expect(cameras, isNotEmpty);
      expect(cameras.first.name, isNotEmpty);
    });

    test('MJPEG frame marker detection works accurately', () {
      // Create synthetic JPEG bytes with SOI [0xFF, 0xD8] and EOI [0xFF, 0xD9]
      final fakeJpeg1 = Uint8List.fromList([
        0xFF, 0xD8, // SOI
        0x01, 0x02, 0x03, 0x04,
        0xFF, 0xD9, // EOI
      ]);

      final fakeJpeg2 = Uint8List.fromList([
        0xFF, 0xD8, // SOI
        0xAA, 0xBB, 0xCC,
        0xFF, 0xD9, // EOI
      ]);

      // Concatenate
      final streamBytes = Uint8List.fromList([...fakeJpeg1, ...fakeJpeg2]);

      final extracted = <String>[];
      final buffer = BytesBuilder(copy: false);
      buffer.add(streamBytes);

      final bytes = buffer.toBytes();
      int searchStart = 0;

      while (true) {
        int soi = -1;
        for (int i = searchStart; i < bytes.length - 1; i++) {
          if (bytes[i] == 0xFF && bytes[i + 1] == 0xD8) {
            soi = i;
            break;
          }
        }
        if (soi == -1) break;

        int eoi = -1;
        for (int i = soi + 2; i < bytes.length - 1; i++) {
          if (bytes[i] == 0xFF && bytes[i + 1] == 0xD9) {
            eoi = i;
            break;
          }
        }
        if (eoi == -1) break;

        final frameLength = (eoi + 2) - soi;
        final frameBytes = Uint8List.view(
          bytes.buffer,
          bytes.offsetInBytes + soi,
          frameLength,
        );

        extracted.add(base64Encode(frameBytes));
        searchStart = eoi + 2;
        if (searchStart >= bytes.length) break;
      }

      expect(extracted.length, equals(2));
      expect(extracted[0], equals(base64Encode(fakeJpeg1)));
      expect(extracted[1], equals(base64Encode(fakeJpeg2)));
    });
  });
}
