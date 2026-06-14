import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pdf_ocr_ondevice/pdf_ocr_ondevice.dart';

PdfOcrModel _modelFor(Uri base, {String? detSha}) => PdfOcrModel(
      id: 'test-model',
      displayName: 'Test',
      detection: PdfOcrModelFile(
          name: 'det.onnx',
          url: base.resolve('det.onnx'),
          sha256: detSha,
          sizeBytes: 4),
      recognition: PdfOcrModelFile(
          name: 'rec.onnx', url: base.resolve('rec.onnx'), sizeBytes: 4),
      dictionary: PdfOcrModelFile(
          name: 'dict.txt', url: base.resolve('dict.txt'), sizeBytes: 2),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final base = Uri.parse('https://example.test/');
  late Directory tempRoot;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('pdf_ocr_test');
  });
  tearDown(() {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  PdfOcrModelManager managerWith(http.Client client) => PdfOcrModelManager(
        client: client,
        cacheRoot: () async => tempRoot,
      );

  final bodies = <String, Uint8List>{
    'det.onnx': Uint8List.fromList([1, 2, 3, 4]),
    'rec.onnx': Uint8List.fromList([5, 6, 7, 8]),
    'dict.txt': Uint8List.fromList([97, 10]), // "a\n"
  };

  MockClient serving(Map<String, Uint8List> files) => MockClient((req) async {
        final name = req.url.pathSegments.last;
        final body = files[name];
        if (body == null) return http.Response('not found', 404);
        return http.Response.bytes(body, 200);
      });

  test('isSupported is true on the default test platform (android)', () {
    expect(PdfOcrModelManager.isSupported, isTrue);
  });

  test('download fetches every file and reports progress', () async {
    final manager = managerWith(serving(bodies));
    final model = _modelFor(base);
    expect(await manager.isDownloaded(model), isFalse);

    final progress = <PdfOcrDownloadProgress>[];
    await manager.download(model, onProgress: progress.add);

    expect(await manager.isDownloaded(model), isTrue);
    final files = await manager.localFiles(model);
    expect(files.keys, containsAll(['det.onnx', 'rec.onnx', 'dict.txt']));
    expect(await files['det.onnx']!.readAsBytes(), bodies['det.onnx']);
    // Progress ran and finished at the full byte total.
    expect(progress, isNotEmpty);
    expect(progress.last.receivedBytes, 4 + 4 + 2);
    expect(progress.last.fraction, closeTo(1.0, 1e-9));
    manager.close();
  });

  test('a matching SHA-256 passes verification', () async {
    final sha = sha256.convert(bodies['det.onnx']!).toString();
    final manager = managerWith(serving(bodies));
    await manager.download(_modelFor(base, detSha: sha));
    expect(await manager.isDownloaded(_modelFor(base, detSha: sha)), isTrue);
    manager.close();
  });

  test('a checksum mismatch throws and leaves nothing installed', () async {
    final manager = managerWith(serving(bodies));
    final model = _modelFor(base, detSha: 'deadbeef');
    await expectLater(
      manager.download(model),
      throwsA(isA<PdfOcrModelException>()),
    );
    expect(await manager.isDownloaded(model), isFalse);
    // No leftover .part file.
    final dir = await manager.directory(model);
    final leftovers = dir.existsSync()
        ? dir.listSync().where((e) => e.path.endsWith('.part')).toList()
        : const [];
    expect(leftovers, isEmpty);
    manager.close();
  });

  test('an HTTP error surfaces as PdfOcrModelException', () async {
    final manager = managerWith(serving({})); // every file 404s
    await expectLater(
      manager.download(_modelFor(base)),
      throwsA(isA<PdfOcrModelException>()),
    );
    manager.close();
  });

  test('download skips files already present and delete clears them',
      () async {
    var detHits = 0;
    final client = MockClient((req) async {
      final name = req.url.pathSegments.last;
      if (name == 'det.onnx') detHits++;
      return http.Response.bytes(bodies[name]!, 200);
    });
    final manager = managerWith(client);
    final model = _modelFor(base);
    await manager.download(model);
    await manager.download(model); // second run should re-fetch nothing
    expect(detHits, 1);

    await manager.delete(model);
    expect(await manager.isDownloaded(model), isFalse);
    manager.close();
  });

  test('localFiles throws when the model is not downloaded', () async {
    final manager = managerWith(serving(bodies));
    await expectLater(
      manager.localFiles(_modelFor(base)),
      throwsA(isA<PdfOcrModelException>()),
    );
    manager.close();
  });
}
