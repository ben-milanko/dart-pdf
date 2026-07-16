// Shape (stroke/fill) strip cache: replayed (hit) output must be
// byte-identical to the freshly-built (miss) output, content keying works
// across distinct PdfPath instances (no shared identity), quantization
// stays within tolerance of the uncached path, caps hold, and bypasses
// fall back to direct raster.
import 'dart:typed_data';

import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_graphics/raster.dart';
import 'package:test/test.dart';

import 'reference_raster.dart';

final int black = premulRgba8(PdfColor.black, 1);

/// A CAD-ish arrowhead symbol at (x, y) - a fresh PdfPath every call, the
/// way interpreters hand shapes to the device (no object identity).
PdfPath arrow(double x, double y) => PdfPath([
      PdfMoveTo(x, y),
      PdfLineTo(x + 9, y + 3),
      PdfLineTo(x + 9, y - 3),
      const PdfClosePath(),
    ]);

/// A small circle-ish symbol of two cubics at (x, y).
PdfPath knob(double x, double y) => PdfPath([
      PdfMoveTo(x, y + 4),
      PdfCubicTo(x - 5.4, y + 4, x - 5.4, y - 4, x, y - 4),
      PdfCubicTo(x + 5.4, y - 4, x + 5.4, y + 4, x, y + 4),
      const PdfClosePath(),
    ]);

/// A hatch stroke segment starting at (x, y).
PdfPath tick(double x, double y) => PdfPath([
      PdfMoveTo(x, y),
      PdfLineTo(x + 11, y + 5),
    ]);

const PdfStroke thinStroke = PdfStroke(width: 1.2);

/// Draws a symbol-heavy "CAD page": the same three shapes repeated at a
/// sweep of positions and subpixel phases, plus strokes with parameters.
void drawSymbolPage(StripGenerator gen, {int color = 0xFF303030}) {
  for (var i = 0; i < 10; i++) {
    final x = 8.0 + i * 13.0 + (i % 4) * 0.25;
    gen.fillPath(arrow(x, 20 + (i % 3) * 22.5), PdfMatrix.identity,
        PdfFillRule.nonzero, color);
    gen.fillPath(knob(x, 45 + (i % 2) * 17.25), PdfMatrix.identity,
        PdfFillRule.evenOdd, color);
    gen.strokePath(
        tick(x, 78 + (i % 3) * 6.0), PdfMatrix.identity, thinStroke, color);
  }
}

(Uint32List, Uint32List, Uint32List, Uint32List, Uint32List) snapshot(
        StripBuffer b) =>
    (
      Uint32List.fromList(Uint32List.sublistView(b.xy, 0, b.length)),
      Uint32List.fromList(Uint32List.sublistView(b.widthFlags, 0, b.length)),
      Uint32List.fromList(Uint32List.sublistView(b.alphaOffset, 0, b.length)),
      Uint32List.fromList(Uint32List.sublistView(b.color, 0, b.length)),
      Uint32List.fromList(b.alphaTexels),
    );

void main() {
  test('replayed (hit) output is byte-identical to freshly built (miss)', () {
    final cache = ShapeStripCache();
    final gen = (StripGenerator()..shapeCache = cache)..begin(150, 110);
    // pass 1: first sights render directly (cache-on-second-sight gate)
    drawSymbolPage(gen);
    expect(cache.firstSights, greaterThan(0));
    // pass 2: every draw is a fresh build (miss) or a hit - both replay
    gen.begin(150, 110);
    drawSymbolPage(gen);
    final first = snapshot(gen.strips);
    expect(cache.misses, greaterThan(0));
    final missCount = cache.misses;

    gen.begin(150, 110);
    drawSymbolPage(gen);
    final second = snapshot(gen.strips);
    expect(cache.misses, missCount, reason: 'third pass must be all hits');
    expect(cache.hits, greaterThan(0));
    expect(second.$1, first.$1);
    expect(second.$2, first.$2);
    expect(second.$3, first.$3);
    expect(second.$4, first.$4);
    expect(second.$5, first.$5);
  });

  test('content keying: distinct PdfPath instances share one entry', () {
    final cache = ShapeStripCache();
    final gen = (StripGenerator()..shapeCache = cache)..begin(80, 40);
    // same shape content at integer translations: one key
    gen.fillPath(arrow(10, 20), PdfMatrix.identity, PdfFillRule.nonzero,
        black); // first sight
    gen.fillPath(arrow(30, 24), PdfMatrix.identity, PdfFillRule.nonzero,
        black); // build
    gen.fillPath(arrow(51, 12), PdfMatrix.identity, PdfFillRule.nonzero,
        black); // hit
    expect(cache.firstSights, 1);
    expect(cache.misses, 1);
    expect(cache.hits, 1);
    expect(cache.entryCount, 1);
  });

  test('quantized cached raster stays close to the uncached path', () {
    final cached = (StripGenerator()..shapeCache = ShapeStripCache())
      ..begin(150, 110);
    drawSymbolPage(cached);
    final direct = (StripGenerator()..shapeCache = null)..begin(150, 110);
    drawSymbolPage(direct);
    final a = decodeStripCoverage(cached.strips, 150, 110);
    final b = decodeStripCoverage(direct.strips, 150, 110);
    // quantization moves shapes <= 1/8 px; mean coverage impact is small
    expect(meanAbsDiff(a, b), lessThanOrEqualTo(1.0));
  });

  test('grid-aligned draws replay identically across generators sharing a '
      'cache', () {
    final cache = ShapeStripCache();
    final g0 = (StripGenerator()..shapeCache = cache)..begin(64, 64);
    final g1 = (StripGenerator()..shapeCache = cache)..begin(64, 64);
    final g2 = (StripGenerator()..shapeCache = cache)..begin(64, 64);
    // anchor on the 1/4-px grid
    g0.fillPath(knob(20.25, 30), PdfMatrix.identity, PdfFillRule.nonzero,
        black); // 1st sight
    g1.fillPath(knob(20.25, 30), PdfMatrix.identity, PdfFillRule.nonzero,
        black); // build
    g2.fillPath(knob(20.25, 30), PdfMatrix.identity, PdfFillRule.nonzero,
        black); // hit
    expect(decodeStripCoverage(g2.strips, 64, 64),
        decodeStripCoverage(g1.strips, 64, 64));
    expect(decodeStripCoverage(g0.strips, 64, 64),
        decodeStripCoverage(g1.strips, 64, 64),
        reason: 'first sight rasters from the same quantized content');
    expect(cache.firstSights, 1);
    expect(cache.misses, 1);
    expect(cache.hits, 1);
  });

  test('stroke parameters join the key', () {
    final cache = ShapeStripCache();
    final gen = (StripGenerator()..shapeCache = cache)..begin(64, 64);
    const wide = PdfStroke(width: 3);
    const dashed = PdfStroke(width: 3, dashArray: [4, 2]);
    for (var pass = 0; pass < 2; pass++) {
      gen.strokePath(tick(10, 20), PdfMatrix.identity, thinStroke, black);
      gen.strokePath(tick(10, 20), PdfMatrix.identity, wide, black);
      gen.strokePath(tick(10, 20), PdfMatrix.identity, dashed, black);
    }
    // three distinct keys, each seen twice -> three entries
    expect(cache.entryCount, 3);
    expect(cache.firstSights, 3);
    expect(cache.misses, 3);
  });

  test('color override: replay carries the current color', () {
    final gen = (StripGenerator()..shapeCache = ShapeStripCache())
      ..begin(64, 64);
    gen.fillPath(
        arrow(10, 20), PdfMatrix.identity, PdfFillRule.nonzero, 0x11223344);
    final n1 = gen.strips.length;
    gen.fillPath(
        arrow(10, 20), PdfMatrix.identity, PdfFillRule.nonzero, 0x55667788);
    for (var i = 0; i < n1; i++) {
      expect(gen.strips.color[i], 0x11223344);
    }
    for (var i = n1; i < gen.strips.length; i++) {
      expect(gen.strips.color[i], 0x55667788);
    }
  });

  test('offscreen shapes bypass the cache and still render clipped', () {
    final cache = ShapeStripCache();
    final gen = (StripGenerator()..shapeCache = cache)..begin(40, 40);
    final path = arrow(-4, 20); // hangs off the left edge
    gen.fillPath(path, PdfMatrix.identity, PdfFillRule.nonzero, black);
    expect(cache.bypasses, 1);
    expect(cache.misses, 0);
    final direct = (StripGenerator()..shapeCache = null)..begin(40, 40);
    direct.fillPath(path, PdfMatrix.identity, PdfFillRule.nonzero, black);
    expect(decodeStripCoverage(gen.strips, 40, 40),
        decodeStripCoverage(direct.strips, 40, 40));
  });

  test('oversized paths skip the cache entirely', () {
    final cache = ShapeStripCache();
    final gen = (StripGenerator()..shapeCache = cache)..begin(64, 64);
    // more segments than maxSegments: never walked/hashed
    final segs = <PdfPathSegment>[PdfMoveTo(2, 2)];
    for (var i = 0; i < ShapeStripCache.maxSegments + 8; i++) {
      segs.add(PdfLineTo(2.0 + (i % 50), 3.0 + i * 0.7));
    }
    gen.fillPath(PdfPath(segs), PdfMatrix.identity, PdfFillRule.nonzero,
        black);
    expect(cache.bypasses, 0);
    expect(cache.firstSights, 0);
    expect(cache.entryCount, 0);
  });

  test('generational rotation bounds live entries at maxEntries', () {
    final cache = ShapeStripCache(maxEntries: 4);
    final gen = (StripGenerator()..shapeCache = cache)..begin(400, 40);
    // 8 distinct shapes (arrow length varies) -> 8 keys, each drawn twice
    // so the second-sight gate promotes them into the cache
    PdfPath shape(int i) => PdfPath([
          PdfMoveTo(10.0 + i * 30, 20),
          PdfLineTo(19.0 + i * 30 + i, 23),
          PdfLineTo(19.0 + i * 30 + i, 17),
          const PdfClosePath(),
        ]);
    for (var i = 0; i < 8; i++) {
      gen.fillPath(shape(i), PdfMatrix.identity, PdfFillRule.nonzero, black);
      gen.fillPath(shape(i), PdfMatrix.identity, PdfFillRule.nonzero, black);
    }
    expect(cache.misses, 8);
    expect(cache.entryCount, lessThanOrEqualTo(4));
    expect(cache.entryCount, greaterThan(0));
    // a key still present replays without a rebuild
    final missCount = cache.misses;
    gen.fillPath(shape(7), PdfMatrix.identity, PdfFillRule.nonzero, black);
    expect(cache.misses, missCount, reason: 'newest key must still be live');
    expect(cache.hits, greaterThan(0));
  });

  test('cache accounting tracks alpha bytes', () {
    final cache = ShapeStripCache();
    final gen = (StripGenerator()..shapeCache = cache)..begin(64, 64);
    gen.fillPath(knob(20, 30), PdfMatrix.identity, PdfFillRule.nonzero,
        black);
    gen.fillPath(knob(20, 30), PdfMatrix.identity, PdfFillRule.nonzero,
        black);
    expect(cache.dataBytes, greaterThan(0));
    cache.clear();
    expect(cache.dataBytes, 0);
    expect(cache.entryCount, 0);
  });

  test('dashed cached stroke matches the direct dashed raster on the grid',
      () {
    const stroke = PdfStroke(width: 2, dashArray: [5, 3], cap: 1);
    final cache = ShapeStripCache();
    final cached = (StripGenerator()..shapeCache = cache)..begin(64, 32);
    // grid-aligned so quantization is exact
    final path = PdfPath([PdfMoveTo(6, 16), PdfLineTo(58, 16)]);
    cached.strokePath(path, PdfMatrix.identity, stroke, black); // 1st sight
    cached.begin(64, 32);
    cached.strokePath(path, PdfMatrix.identity, stroke, black); // build
    final direct = (StripGenerator()..shapeCache = null)..begin(64, 32);
    direct.strokePath(path, PdfMatrix.identity, stroke, black);
    expect(decodeStripCoverage(cached.strips, 64, 32),
        decodeStripCoverage(direct.strips, 64, 32));
  });
}
