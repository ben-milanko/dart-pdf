// PpOcrPipeline is the shared (VM + web) PP-OCR path; proven here with a fake
// network backend so detection boxes, recognition decoding, cleanup and
// progress are covered without a model.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_ocr_ondevice/pp_ocr.dart';

/// Detection marks [blobs]; recognition "reads" each line as `A ●` (index 1,
/// blank, index 3) so cleanup has a drawing symbol to drop - or, for the
/// batching test, as the letter whose index is the line's batch position.
class _FakeInference implements PpOcrInference {
  _FakeInference({this.blobs = const [(4, 8, 28, 16)]});

  final List<(int, int, int, int)> blobs;
  int loads = 0;
  bool disposed = false;
  final recognitionWidths = <int>[];
  final batchSizes = <int>[];

  @override
  Future<String> load() async {
    loads++;
    return 'A\nB\n●\n';
  }

  @override
  Future<OcrTensor> detect(Float32List input, int width, int height) async {
    expect(input.length, 3 * width * height);
    final map = Float32List(width * height);
    for (final (x0, y0, x1, y1) in blobs) {
      for (var y = y0; y < y1; y++) {
        for (var x = x0; x < x1; x++) {
          map[y * width + x] = 0.9;
        }
      }
    }
    return (data: map, shape: [1, 1, height, width]);
  }

  @override
  Future<OcrTensor> recognize(
      Float32List input, int batch, int height, int width) async {
    expect(input.length, batch * 3 * height * width);
    recognitionWidths.add(width);
    batchSizes.add(batch);
    const vocab = 5; // blank, A, B, ●, space
    const steps = [1, 0, 3];
    final scores = Float32List(batch * steps.length * vocab);
    for (var b = 0; b < batch; b++) {
      for (var t = 0; t < steps.length; t++) {
        scores[(b * steps.length + t) * vocab + steps[t]] = 1;
      }
    }
    return (data: scores, shape: [batch, steps.length, vocab]);
  }

  @override
  Future<void> dispose() async => disposed = true;
}

OcrImage _white(int w, int h) => OcrImage(
    rgba: Uint8List(w * h * 4)..fillRange(0, w * h * 4, 255),
    width: w,
    height: h);

void main() {
  test('detects, recognizes, cleans and reports progress', () async {
    final inference = _FakeInference();
    final pipeline = PpOcrPipeline(inference);
    final progress = <double>[];
    pipeline.onProgress = progress.add;
    await pipeline.load();
    await pipeline.load(); // idempotent
    expect(inference.loads, 1);

    final lines = await pipeline.recognize(_white(64, 32));
    expect(lines, hasLength(1));
    expect(lines.single.text, 'A'); // '●' cleaned away
    final r = lines.single.pixelBounds;
    expect(r.left, lessThan(4));
    expect(r.right, greaterThan(28));
    expect(inference.recognitionWidths.single, 320); // padded to the minimum
    expect(progress, [0.1, 1.0]);
    expect(inference.batchSizes, [1]);

    await pipeline.dispose();
    expect(inference.disposed, isTrue);
  });

  test('lines are recognized in batches but returned in reading order',
      () async {
    // Seven lines down a tall page, one of them very wide: two batches (6 + 1),
    // the wide line alone in the last (aspect-sorted) batch.
    final blobs = [
      for (var i = 0; i < 6; i++) (4, 8 + i * 20, 20, 14 + i * 20),
      (4, 130, 120, 136),
    ];
    final inference = _FakeInference(blobs: blobs);
    final pipeline = PpOcrPipeline(inference);
    await pipeline.load();
    final lines = await pipeline.recognize(_white(128, 160));
    expect(lines, hasLength(7));
    for (var i = 1; i < lines.length; i++) {
      expect(
          lines[i].pixelBounds.top, greaterThan(lines[i - 1].pixelBounds.top));
    }
    expect(inference.batchSizes, [6, 1]);
    expect(inference.recognitionWidths.first, 320);
    expect(inference.recognitionWidths.last, greaterThan(320));
  });

  test('recognize before load is an error', () async {
    expect(() => PpOcrPipeline(_FakeInference()).recognize(_white(32, 32)),
        throwsStateError);
  });

  test('a failed load can be retried', () async {
    var attempts = 0;
    final pipeline = PpOcrPipeline(_FlakyLoad(() => ++attempts == 1));
    await expectLater(pipeline.load(), throwsStateError);
    await pipeline.load();
    expect(attempts, 2);
  });
}

class _FlakyLoad extends _FakeInference {
  _FlakyLoad(this.fail);
  final bool Function() fail;

  @override
  Future<String> load() async {
    if (fail()) throw StateError('network down');
    return super.load();
  }
}
