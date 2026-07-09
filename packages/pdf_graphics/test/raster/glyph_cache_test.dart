// Glyph strip cache: replayed (hit) output must be byte-identical to the
// freshly-built (miss) output, quantization stays within tolerance of the
// uncached path, LRU caps hold, and bypasses fall back to direct raster.
import 'dart:typed_data';

import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_graphics/raster.dart';
import 'package:test/test.dart';

import 'reference_raster.dart';

PdfPath glyphA() => PdfPath([
      // A-ish triangle with a curved bowl and a hole
      PdfMoveTo(0.1, 0.0),
      PdfLineTo(0.35, 0.7),
      PdfCubicTo(0.42, 0.85, 0.58, 0.85, 0.65, 0.7),
      PdfLineTo(0.9, 0.0),
      PdfLineTo(0.72, 0.0),
      PdfLineTo(0.5, 0.55),
      PdfLineTo(0.28, 0.0),
      const PdfClosePath(),
    ]);

PdfPath glyphO() => PdfPath([
      PdfMoveTo(0.5, 0.75),
      PdfCubicTo(0.15, 0.75, 0.15, 0.05, 0.5, 0.05),
      PdfCubicTo(0.85, 0.05, 0.85, 0.75, 0.5, 0.75),
      const PdfClosePath(),
      PdfMoveTo(0.5, 0.6),
      PdfCubicTo(0.68, 0.6, 0.68, 0.2, 0.5, 0.2),
      PdfCubicTo(0.32, 0.2, 0.32, 0.6, 0.5, 0.6),
      const PdfClosePath(),
    ]);

/// Draws a small "text page": two glyph shapes at a sweep of positions,
/// sizes, and subpixel phases.
void drawTextPage(StripGenerator gen, {int color = 0xFF202020}) {
  final a = FlattenedOutline.of(_outlineA);
  final o = FlattenedOutline.of(_outlineO);
  var x = 3.17;
  for (var i = 0; i < 12; i++) {
    final size = 12.0 + (i % 3) * 4.5;
    final y = 20.0 + (i % 4) * 19.3 + i * 0.23;
    gen.fillOutline(
        i.isEven ? a : o, PdfMatrix(size, 0, 0, -size, x, y), color);
    x += size * 0.62;
  }
}

final _outlineA = glyphA();
final _outlineO = glyphO();

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
    final cache = GlyphStripCache();
    final gen = (StripGenerator()..glyphCache = cache)..begin(120, 100);
    // pass 1: first sights render directly (cache-on-second-sight gate)
    drawTextPage(gen);
    expect(cache.firstSights, greaterThan(0));
    // pass 2: every draw is a fresh build (miss) or a hit - both replay
    gen.begin(120, 100);
    drawTextPage(gen);
    final first = snapshot(gen.strips);
    expect(cache.misses, greaterThan(0));
    final missCount = cache.misses;

    gen.begin(120, 100);
    drawTextPage(gen);
    final second = snapshot(gen.strips);
    expect(cache.misses, missCount, reason: 'third pass must be all hits');
    expect(cache.hits, greaterThan(0));
    expect(second.$1, first.$1);
    expect(second.$2, first.$2);
    expect(second.$3, first.$3);
    expect(second.$4, first.$4);
    expect(second.$5, first.$5);
  });

  test('quantized cached raster stays close to the uncached path', () {
    final cached = (StripGenerator()..glyphCache = GlyphStripCache())
      ..begin(120, 100);
    drawTextPage(cached);
    final direct = (StripGenerator()..glyphCache = null)..begin(120, 100);
    drawTextPage(direct);
    final a = decodeStripCoverage(cached.strips, 120, 100);
    final b = decodeStripCoverage(direct.strips, 120, 100);
    // quantization moves glyphs <= 1/8 px; mean coverage impact is small
    expect(meanAbsDiff(a, b), lessThanOrEqualTo(1.0));
  });

  test('grid-aligned draws replay identically across generators sharing a '
      'cache', () {
    final cache = GlyphStripCache();
    final g0 = (StripGenerator()..glyphCache = cache)..begin(64, 64);
    final g1 = (StripGenerator()..glyphCache = cache)..begin(64, 64);
    final g2 = (StripGenerator()..glyphCache = cache)..begin(64, 64);
    const m = PdfMatrix(20, 0, 0, -20, 8.25, 40.5); // on the 1/4-px grid
    g0.fillOutline(FlattenedOutline.of(_outlineA), m, 0xFF000000); // 1st sight
    g1.fillOutline(FlattenedOutline.of(_outlineA), m, 0xFF000000); // build
    g2.fillOutline(FlattenedOutline.of(_outlineA), m, 0xFF000000); // hit
    expect(decodeStripCoverage(g2.strips, 64, 64),
        decodeStripCoverage(g1.strips, 64, 64));
    expect(cache.firstSights, 1);
    expect(cache.misses, 1);
    expect(cache.hits, 1);
  });

  test('color override: replay carries the current fill color', () {
    final gen = (StripGenerator()..glyphCache = GlyphStripCache())..begin(64, 64);
    const m = PdfMatrix(20, 0, 0, -20, 4, 40);
    gen.fillOutline(FlattenedOutline.of(_outlineA), m, 0x11223344);
    final n1 = gen.strips.length;
    gen.fillOutline(FlattenedOutline.of(_outlineA), m, 0x55667788);
    for (var i = 0; i < n1; i++) {
      expect(gen.strips.color[i], 0x11223344);
    }
    for (var i = n1; i < gen.strips.length; i++) {
      expect(gen.strips.color[i], 0x55667788);
    }
  });

  test('offscreen glyphs bypass the cache and still render clipped', () {
    final cache = GlyphStripCache();
    final gen = (StripGenerator()..glyphCache = cache)..begin(40, 40);
    // glyph hanging off the left edge
    const m = PdfMatrix(30, 0, 0, -30, -10, 30);
    gen.fillOutline(FlattenedOutline.of(_outlineA), m, 0xFF000000);
    expect(cache.bypasses, 1);
    expect(cache.misses, 0);
    final direct = (StripGenerator()..glyphCache = null)..begin(40, 40);
    direct.fillOutline(FlattenedOutline.of(_outlineA), m, 0xFF000000);
    expect(decodeStripCoverage(gen.strips, 40, 40),
        decodeStripCoverage(direct.strips, 40, 40));
  });

  test('LRU eviction respects maxEntries', () {
    final cache = GlyphStripCache(maxEntries: 3);
    final gen = (StripGenerator()..glyphCache = cache)..begin(400, 40);
    final o = FlattenedOutline.of(_outlineA);
    // 5 distinct subpixel phases -> 5 keys, each drawn twice so the
    // second-sight gate promotes them into the cache
    for (var i = 0; i < 5; i++) {
      final m = PdfMatrix(20, 0, 0, -20, 10 + i * 30 + i * 0.25, 30);
      gen.fillOutline(o, m, 0xFF000000);
      gen.fillOutline(o, m, 0xFF000000);
    }
    expect(cache.entryCount, 3);
    expect(cache.misses, 5);
  });

  test('cache accounting tracks alpha bytes', () {
    final cache = GlyphStripCache();
    final gen = (StripGenerator()..glyphCache = cache)..begin(64, 64);
    gen.fillOutline(FlattenedOutline.of(_outlineA),
        const PdfMatrix(20, 0, 0, -20, 4, 40), 0xFF000000);
    gen.fillOutline(FlattenedOutline.of(_outlineA),
        const PdfMatrix(20, 0, 0, -20, 4, 40), 0xFF000000);
    expect(cache.alphaBytes, greaterThan(0));
    cache.clear();
    expect(cache.alphaBytes, 0);
    expect(cache.entryCount, 0);
  });
}
