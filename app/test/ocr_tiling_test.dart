// The browser OCR path tiles a page so Florence-2 sees legible sub-regions,
// then maps each tile's boxes back and de-duplicates the overlaps. The tiling
// geometry, Florence-2 result parsing, and merge are pure (no web imports) so
// they run here on the VM; `ocr_web.dart` itself can't be loaded by the VM
// test runner (it imports dart:js_interop).
import 'dart:ui' show Rect;

import 'package:dart_pdf_editor_app/ocr_tiling.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ocrTiles', () {
    test('a small raster is a single full-image tile', () {
      final tiles = ocrTiles(800, 600, tileSize: 1024);
      expect(tiles, [const Rect.fromLTWH(0, 0, 800, 600)]);
    });

    test('a large raster is split into overlapping tiles that cover it all',
        () {
      const w = 2384, h = 1684; // an A3 page rendered at 2x.
      const tileSize = 1024, overlap = 128;
      final tiles = ocrTiles(w, h, tileSize: tileSize, overlap: overlap);

      expect(tiles.length, greaterThan(1));

      // No tile exceeds the model-friendly size, and every tile is inside the
      // image.
      for (final t in tiles) {
        expect(t.width, lessThanOrEqualTo(tileSize.toDouble()));
        expect(t.height, lessThanOrEqualTo(tileSize.toDouble()));
        expect(t.left, greaterThanOrEqualTo(0));
        expect(t.top, greaterThanOrEqualTo(0));
        expect(t.right, lessThanOrEqualTo(w.toDouble()));
        expect(t.bottom, lessThanOrEqualTo(h.toDouble()));
      }

      // The tiles must reach both far edges (nothing past the last tile is
      // dropped).
      expect(tiles.map((t) => t.right).reduce((a, b) => a > b ? a : b), w);
      expect(tiles.map((t) => t.bottom).reduce((a, b) => a > b ? a : b), h);

      // Every pixel center is inside at least one tile (sampled on a grid).
      for (var y = 0; y < h; y += 53) {
        for (var x = 0; x < w; x += 53) {
          final covered = tiles.any((t) =>
              x >= t.left && x < t.right && y >= t.top && y < t.bottom);
          expect(covered, isTrue, reason: 'pixel ($x,$y) is in no tile');
        }
      }
    });

    test('neighbouring interior tiles overlap', () {
      final tiles = ocrTiles(3000, 1000, tileSize: 1000, overlap: 200);
      // First two columns share the same top row, so they should overlap in x.
      final a = tiles[0];
      final b = tiles[1];
      expect(b.left, lessThan(a.right), reason: 'columns should overlap');
    });

    test('a degenerate size yields no tiles', () {
      expect(ocrTiles(0, 100), isEmpty);
      expect(ocrTiles(100, 0), isEmpty);
    });
  });

  group('OcrRawSpan', () {
    test('shifted translates the box by the tile origin, keeping text/conf',
        () {
      const span = OcrRawSpan(
          text: '20m', box: Rect.fromLTRB(10, 20, 30, 40), confidence: 0.8);
      final moved = span.shifted(100, 200);
      expect(moved.text, '20m');
      expect(moved.confidence, 0.8);
      expect(moved.box, const Rect.fromLTRB(110, 220, 130, 240));
    });
  });

  group('parseFlorenceSpans', () {
    test('reads the <OCR_WITH_REGION> labels + quad_boxes shape', () {
      final payload = {
        '<OCR_WITH_REGION>': {
          'labels': ['Hello', 'World'],
          'quad_boxes': [
            [10, 20, 50, 20, 50, 40, 10, 40],
            [60, 22, 110, 22, 110, 42, 60, 42],
          ],
        },
      };
      final spans = parseFlorenceSpans(payload,
          fallbackWidth: 1024, fallbackHeight: 1024);
      expect(spans.map((s) => s.text), ['Hello', 'World']);
      // The quad becomes its axis-aligned bounding box.
      expect(spans.first.box, const Rect.fromLTRB(10, 20, 50, 40));
    });

    test('reads a 4-number bbox shape', () {
      final payload = {
        '<OCR_WITH_REGION>': {
          'labels': ['A'],
          'bboxes': [
            [5, 6, 25, 16]
          ],
        },
      };
      final spans = parseFlorenceSpans(payload,
          fallbackWidth: 100, fallbackHeight: 100);
      expect(spans.single.box, const Rect.fromLTRB(5, 6, 25, 16));
    });

    test('reads the texts/boxes keys on an unwrapped payload', () {
      // No <OCR…> wrapper, and the alternate `texts`/`boxes` key names.
      final payload = {
        'texts': ['Z'],
        'boxes': [
          [1, 2, 3, 4]
        ],
      };
      final spans = parseFlorenceSpans(payload,
          fallbackWidth: 10, fallbackHeight: 10);
      expect(spans.single.text, 'Z');
      expect(spans.single.box, const Rect.fromLTRB(1, 2, 3, 4));
    });

    test('treats a bare string payload as plain text', () {
      final spans = parseFlorenceSpans('hello world',
          fallbackWidth: 50, fallbackHeight: 12);
      expect(spans.single.text, 'hello world');
      expect(spans.single.box, const Rect.fromLTWH(0, 0, 50, 12));
    });

    test('falls back to one tile-sized span for boxless plain text', () {
      final spans = parseFlorenceSpans(
        {'<OCR>': {'text': 'just some text'}},
        fallbackWidth: 320,
        fallbackHeight: 64,
      );
      expect(spans.single.text, 'just some text');
      expect(spans.single.box, const Rect.fromLTWH(0, 0, 320, 64));
    });

    test('drops empty labels and zero-area boxes', () {
      final payload = {
        '<OCR_WITH_REGION>': {
          'labels': ['', 'Keep'],
          'quad_boxes': [
            [0, 0, 0, 0, 0, 0, 0, 0],
            [1, 1, 5, 1, 5, 9, 1, 9],
          ],
        },
      };
      final spans = parseFlorenceSpans(payload,
          fallbackWidth: 10, fallbackHeight: 10);
      expect(spans.map((s) => s.text), ['Keep']);
    });
  });

  group('mergeOcrSpans', () {
    test('collapses the same text from overlapping tiles', () {
      final spans = [
        const OcrRawSpan(text: '20m', box: Rect.fromLTRB(100, 100, 140, 120)),
        // Same word seen again from the neighbouring tile, slightly shifted.
        const OcrRawSpan(text: '20m', box: Rect.fromLTRB(102, 101, 142, 121)),
        const OcrRawSpan(text: '30m', box: Rect.fromLTRB(300, 100, 340, 120)),
      ];
      final merged = mergeOcrSpans(spans);
      expect(merged.length, 2);
      expect(merged.map((s) => s.text).toSet(), {'20m', '30m'});
    });

    test('keeps identical text whose boxes are far apart', () {
      final spans = [
        const OcrRawSpan(text: '20m', box: Rect.fromLTRB(0, 0, 40, 20)),
        const OcrRawSpan(text: '20m', box: Rect.fromLTRB(500, 400, 540, 420)),
      ];
      expect(mergeOcrSpans(spans).length, 2);
    });

    test('a duplicate keeps the higher-confidence span', () {
      final spans = [
        const OcrRawSpan(
            text: 'x', box: Rect.fromLTRB(0, 0, 10, 10), confidence: 0.4),
        const OcrRawSpan(
            text: 'x', box: Rect.fromLTRB(1, 1, 11, 11), confidence: 0.9),
      ];
      final merged = mergeOcrSpans(spans);
      expect(merged.single.confidence, 0.9);
    });
  });
}
