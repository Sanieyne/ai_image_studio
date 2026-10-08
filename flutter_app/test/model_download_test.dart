import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:ai_image_studio/services/model_download_service.dart';

/// A local file server that misbehaves on purpose. Each `fail*` counter is
/// consumed by the next matching request.
class FlakyServer {
  final Map<String, Uint8List> files;
  late final HttpServer _server;
  final List<String> log = [];

  int dropMidFile = 0; // send half the remaining bytes, then cut the connection
  int ignoreRange = 0; // answer 200 with the whole file despite a Range header
  int expireOnce = 0; // answer 403 (expired signature)
  int stall = 0; // send some bytes, then nothing
  int corrupt = 0; // flip a byte in the body
  Completer<void>? gate; // hold the response until completed (for pause tests)

  FlakyServer(this.files);

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  String url(String name, {int version = 1}) => 'http://127.0.0.1:${_server.port}/$name?v=$version';

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest req) async {
    final name = req.uri.pathSegments.last;
    final body = files[name]!;
    final range = req.headers.value('range');
    log.add('${req.uri.query} ${range ?? 'full'}');
    final res = req.response;
    if (gate != null) await gate!.future;

    if (expireOnce > 0 && req.uri.queryParameters['v'] == '1') {
      expireOnce -= 1;
      res.statusCode = 403;
      res.write('<Error><Code>AccessDenied</Code><Message>Request has expired</Message></Error>');
      await res.close();
      return;
    }

    var start = 0;
    if (range != null && ignoreRange == 0) {
      start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
      res.statusCode = 206;
      res.headers.set('content-range', 'bytes $start-${body.length - 1}/${body.length}');
    } else {
      if (range != null) ignoreRange -= 1;
      res.statusCode = 200;
    }
    var payload = Uint8List.fromList(body.sublist(start));
    if (corrupt > 0) {
      corrupt -= 1;
      payload[payload.length ~/ 2] ^= 0xFF;
    }
    res.contentLength = payload.length;

    if (dropMidFile > 0) {
      dropMidFile -= 1;
      // Fewer bytes than Content-Length, then close: the client sees the connection end early.
      res.add(payload.sublist(0, payload.length ~/ 2));
      await res.flush();
      try {
        await res.close();
      } catch (_) {}
      return;
    }
    if (stall > 0) {
      stall -= 1;
      res.add(payload.sublist(0, payload.length ~/ 4));
      await res.flush();
      await Future.delayed(const Duration(seconds: 3)); // longer than the test's stallTimeout
      try {
        await res.close();
      } catch (_) {}
      return;
    }
    res.add(payload);
    await res.close();
  }
}

Uint8List bytes(int n, int seed) => Uint8List.fromList(List.generate(n, (i) => (i * 31 + seed) % 251));

void main() {
  late Directory tmp;
  late FlakyServer server;
  final weights = bytes(3 * 1024 * 1024 + 123, 7); // > 1 MB, so it counts as real weights
  final config = bytes(2048, 3);

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('models_test');
    server = FlakyServer({'model.safetensors': weights, 'config.json': config});
    await server.start();
  });
  tearDown(() async {
    await server.close();
    await tmp.delete(recursive: true);
  });

  ModelDownloadService service({
    int urlVersion = 1,
    bool withHashes = false,
    Duration stallTimeout = const Duration(seconds: 30),
    List<Map<String, dynamic>>? files,
  }) {
    var version = urlVersion;
    return ModelDownloadService.forTest(
      baseDir: tmp,
      stallTimeout: stallTimeout,
      freeSpace: () async => 100 * 1024 * 1024 * 1024,
      fetchUrls: (id) async {
        final current = version;
        version += 1; // every refresh hands out a new (valid) link
        return {
          'totalBytes': weights.length + config.length,
          'files': files ??
              [
                {
                  'filename': 'model.safetensors',
                  'size': weights.length,
                  'downloadUrl': server.url('model.safetensors', version: current),
                  if (withHashes) 'sha256': crypto.sha256.convert(weights).toString(),
                },
                {
                  'filename': 'config.json',
                  'size': config.length,
                  'downloadUrl': server.url('config.json', version: current),
                  if (withHashes) 'sha256': crypto.sha256.convert(config).toString(),
                },
              ],
        };
      },
    );
  }

  File modelFile(String name) => File(p.join(tmp.path, 'sdxl-base-1.0', name));

  test('dropped connection, ignored Range and an expired link: the file finishes intact without starting over',
      () async {
    final svc = service();
    server.dropMidFile = 2; // two cuts mid-file
    server.ignoreRange = 1; // one 200 instead of 206
    server.expireOnce = 1; // first link refused as expired
    final seen = <ModelDownloadStatus>[];
    final sub = svc.watchProgress('sdxl-base-1.0').listen((e) => seen.add(e.status));

    await svc.downloadModel('sdxl-base-1.0');
    await Future<void>.delayed(Duration.zero); // deliver the last progress events
    await sub.cancel();

    expect(await modelFile('model.safetensors').readAsBytes(), weights);
    expect(await modelFile('config.json').readAsBytes(), config);
    expect(File('${modelFile('model.safetensors').path}.part').existsSync(), isFalse);
    expect(seen, contains(ModelDownloadStatus.waitingForNetwork));
    expect(seen.last, ModelDownloadStatus.downloaded);
    // Resumed with Range after the cuts; a fresh link (v=2) replaced the expired one.
    expect(server.log.where((l) => l.contains('bytes=')).length, greaterThanOrEqualTo(2));
    expect(server.log.any((l) => l.startsWith('v=2')), isTrue);
    expect(await svc.isModelDownloaded('sdxl-base-1.0'), isTrue);
    expect(await svc.pendingDownloads(), isEmpty);
  });

  test('resumes from an existing .part file and counts it in the progress', () async {
    final part = File('${modelFile('model.safetensors').path}.part');
    part.parent.createSync(recursive: true);
    part.writeAsBytesSync(weights.sublist(0, 1024 * 1024));
    final svc = service();
    ModelDownloadProgress? first;
    final sub = svc.watchProgress('sdxl-base-1.0').listen((e) {
      if (e.status == ModelDownloadStatus.downloading) first ??= e;
    });

    await svc.downloadModel('sdxl-base-1.0');
    await sub.cancel();

    expect(first!.downloadedBytes, 1024 * 1024, reason: 'partial bytes on disk count from the start');
    expect(server.log.first, contains('bytes=${1024 * 1024}-'));
    expect(await modelFile('model.safetensors').readAsBytes(), weights);
  });

  test('a stalled connection is dropped and resumed', () async {
    final svc = service(stallTimeout: const Duration(milliseconds: 500));
    server.stall = 1;
    await svc.downloadModel('sdxl-base-1.0');
    expect(await modelFile('model.safetensors').readAsBytes(), weights);
    expect(server.log.length, greaterThanOrEqualTo(3));
  });

  test('SHA-256 is verified; a corrupted copy is downloaded again', () async {
    final svc = service(withHashes: true);
    server.corrupt = 1;
    await svc.downloadModel('sdxl-base-1.0');
    expect(await modelFile('model.safetensors').readAsBytes(), weights);
    expect(server.log.where((l) => l.contains('full')).length, greaterThanOrEqualTo(3),
        reason: 'the corrupted file was fetched again from the start');
  });

  test('pause keeps the partial file and resume continues; the download is remembered meanwhile', () async {
    final svc = service();
    server.gate = Completer<void>();
    final paused = Completer<void>();
    final sub = svc.watchProgress('sdxl-base-1.0').listen((e) {
      if (e.status == ModelDownloadStatus.paused && !paused.isCompleted) paused.complete();
    });

    final running = svc.downloadModel('sdxl-base-1.0');
    await Future.delayed(const Duration(milliseconds: 200));
    expect(svc.isActive('sdxl-base-1.0'), isTrue);
    expect(await svc.pendingDownloads(), ['sdxl-base-1.0']);
    svc.pause('sdxl-base-1.0');
    server.gate!.complete();
    await running;
    await paused.future;
    expect(svc.isActive('sdxl-base-1.0'), isFalse);
    expect(await svc.pendingDownloads(), ['sdxl-base-1.0'], reason: 'remembered for after a restart');
    expect(await svc.isModelDownloaded('sdxl-base-1.0'), isFalse);

    server.gate = null;
    await svc.downloadModel('sdxl-base-1.0');
    await sub.cancel();
    expect(await modelFile('model.safetensors').readAsBytes(), weights);
    expect(await svc.pendingDownloads(), isEmpty);
  });

  test('cancel deletes the partial files and forgets the download', () async {
    final part = File('${modelFile('model.safetensors').path}.part');
    part.parent.createSync(recursive: true);
    part.writeAsBytesSync(weights.sublist(0, 4096));
    File(p.join(tmp.path, '.pending_downloads.json')).writeAsStringSync('["sdxl-base-1.0"]');
    final svc = service();
    await svc.cancel('sdxl-base-1.0');
    expect(part.existsSync(), isFalse);
    expect(await svc.pendingDownloads(), isEmpty);
  });

  test('file names that would escape the model folder are refused', () async {
    final svc = service(files: [
      {'filename': '../../evil.dll', 'size': 10, 'downloadUrl': server.url('config.json')},
    ]);
    await expectLater(svc.downloadModel('sdxl-base-1.0'), throwsA(anything));
    expect(File(p.join(tmp.parent.path, 'evil.dll')).existsSync(), isFalse);
    expect(
      () => ModelDownloadService.safeTarget(Directory(tmp.path), p.join(tmp.path, 'x')),
      throwsA(anything),
      reason: 'absolute paths are refused',
    );
    expect(ModelDownloadService.safeTarget(Directory(tmp.path), 'text_encoder/model.bin').path,
        p.join(tmp.absolute.path, 'text_encoder', 'model.bin'));
  });

  test('not enough free disk space stops before downloading', () async {
    final svc = ModelDownloadService.forTest(
      baseDir: tmp,
      freeSpace: () async => 1024,
      fetchUrls: (_) async => {
        'totalBytes': weights.length,
        'files': [
          {'filename': 'model.safetensors', 'size': weights.length, 'downloadUrl': server.url('model.safetensors')},
        ],
      },
    );
    await expectLater(svc.downloadModel('sdxl-base-1.0'), throwsA(isA<InsufficientDiskSpaceException>()));
    expect(server.log, isEmpty);
  });
}
