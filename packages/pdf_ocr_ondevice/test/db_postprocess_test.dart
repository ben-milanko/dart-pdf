import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_ocr_ondevice/pdf_ocr_ondevice.dart';

/// A `w` x `h` probability map that is 1.0 inside each of [blobs] and 0
/// elsewhere.
Float32List _map(int w, int h, List<(int, int, int, int)> blobs) {
  final m = Float32List(w * h);
  for (final (x0, y0, x1, y1) in blobs) {
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        m[y * w + x] = 1.0;
      }
    }
  }
  return m;
}

void main() {
  test('two separated blobs become two boxes in reading order', () {
    // 40x40 map; one blob top-left, one below it.
    final map = _map(40, 40, [(2, 2, 14, 8), (2, 20, 20, 30)]);
    final boxes = extractDetectionBoxes(map, 40, 40,
        threshold: 0.3, boxScoreThreshold: 0.5, unclipRatio: 1.0);
    expect(boxes, hasLength(2));
    // Sorted top-to-bottom.
    expect(boxes[0].rect.top, lessThan(boxes[1].rect.top));
    // First blob spans x[2,14) y[2,8) -> centre (8, 5), unclip 1.0 keeps it.
    expect(boxes[0].rect.left, closeTo(2, 0.5));
    expect(boxes[0].rect.right, closeTo(14, 0.5));
    expect(boxes[0].rect.top, closeTo(2, 0.5));
    expect(boxes[0].rect.bottom, closeTo(8, 0.5));
    expect(boxes[0].score, closeTo(1.0, 1e-6));
  });

  test('unclip grows the box about its centre', () {
    final map = _map(40, 40, [(10, 10, 20, 16)]); // 10x6 at centre (15, 13)
    final boxes =
        extractDetectionBoxes(map, 40, 40, unclipRatio: 2.0);
    expect(boxes, hasLength(1));
    final r = boxes.single.rect;
    // width 10 -> 20 about cx 15 => [5, 25]; height 6 -> 12 about cy 13 => [7, 19]
    expect(r.left, closeTo(5, 0.5));
    expect(r.right, closeTo(25, 0.5));
    expect(r.top, closeTo(7, 0.5));
    expect(r.bottom, closeTo(19, 0.5));
  });

  test('scale maps resized-space boxes back to original pixels', () {
    final map = _map(20, 20, [(2, 2, 8, 6)]);
    final boxes = extractDetectionBoxes(map, 20, 20,
        unclipRatio: 1.0, scaleX: 3.0, scaleY: 2.0);
    final r = boxes.single.rect;
    expect(r.left, closeTo(2 * 3.0, 0.5));
    expect(r.right, closeTo(8 * 3.0, 0.5));
    expect(r.top, closeTo(2 * 2.0, 0.5));
    expect(r.bottom, closeTo(6 * 2.0, 0.5));
  });

  test('tiny blobs and low-probability regions are dropped', () {
    final map = _map(40, 40, [(0, 0, 2, 2)]); // 2x2 < minSize 3
    expect(extractDetectionBoxes(map, 40, 40), isEmpty);
  });
}
