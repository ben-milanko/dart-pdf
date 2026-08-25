// Slug foundations: cubic->quad error bound, band construction, texel
// encode/decode roundtrip, and band-evaluator winding/coverage vs the
// strip fine raster - all exercised on real glyph outlines from a corpus
// font (DejaVu Sans via the TrueType engine). The Dart evaluator is the
// reference implementation for the eventual GLSL.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_graphics/raster.dart';
import 'package:test/test.dart';

import 'reference_raster.dart';

TrueTypeFont? _loadDejaVu() {
  for (final path in [
    '../dart_pdf_editor_assets/assets/fonts/DejaVuSans.ttf',
    '../../packages/dart_pdf_editor_assets/assets/fonts/DejaVuSans.ttf',
  ]) {
    final f = File(path);
    if (f.existsSync()) return TrueTypeFont.parse(f.readAsBytesSync());
  }
  return null;
}

void main() {
  final font = _loadDejaVu();
  if (font == null) {
    test('curve quads', skip: 'DejaVuSans.ttf not found', () {});
    return;
  }

  PdfPath outlineOf(String char) {
    final gid = font.gidForUnicode(char.codeUnitAt(0));
    expect(gid, isNot(0), reason: 'glyph for "$char"');
    final outline = font.outlineForGlyph(gid);
    expect(outline, isNotNull, reason: 'outline for "$char"');
    return outline!;
  }

  group('outlineToQuads', () {
    test('quads stay within the em-space tolerance of the cubics', () {
      const tol = 1e-3;
      for (final char in ['a', 'g', 'B', 'S', 'e']) {
        final outline = outlineOf(char);
        // walk the original segments; for each cubic, compare dense cubic
        // samples against the emitted quad chain covering it
        final quads = outlineToQuads(outline, tolerance: tol);
        // dense polyline of the whole quad set
        final poly = <double>[];
        for (final q in quads) {
          for (var i = 0; i <= 16; i++) {
            final t = i / 16;
            final mt = 1 - t;
            poly.add(mt * mt * q.x0 + 2 * mt * t * q.cx + t * t * q.x1);
            poly.add(mt * mt * q.y0 + 2 * mt * t * q.cy + t * t * q.y1);
          }
        }
        double distToPoly(double x, double y) {
          var best = double.infinity;
          for (var i = 0; i + 3 < poly.length; i += 2) {
            final ax = poly[i], ay = poly[i + 1];
            final bx = poly[i + 2], by = poly[i + 3];
            final vx = bx - ax, vy = by - ay;
            final len2 = vx * vx + vy * vy;
            var t = len2 == 0 ? 0.0 : ((x - ax) * vx + (y - ay) * vy) / len2;
            t = t.clamp(0.0, 1.0);
            final dx = x - (ax + vx * t), dy = y - (ay + vy * t);
            best = math.min(best, dx * dx + dy * dy);
          }
          return math.sqrt(best);
        }

        var penX = 0.0, penY = 0.0;
        for (final s in outline.segments) {
          switch (s) {
            case PdfMoveTo(:final x, :final y) || PdfLineTo(:final x, :final y):
              penX = x;
              penY = y;
            case PdfCubicTo():
              for (var i = 0; i <= 24; i++) {
                final t = i / 24;
                final mt = 1 - t;
                final bx = mt * mt * mt * penX +
                    3 * mt * mt * t * s.x1 +
                    3 * mt * t * t * s.x2 +
                    t * t * t * s.x3;
                final by = mt * mt * mt * penY +
                    3 * mt * mt * t * s.y1 +
                    3 * mt * t * t * s.y2 +
                    t * t * t * s.y3;
                // allow polyline sampling slack on top of the quad bound
                expect(distToPoly(bx, by), lessThanOrEqualTo(tol * 1.5),
                    reason: '"$char" cubic sample t=$t');
              }
              penX = s.x3;
              penY = s.y3;
            case PdfClosePath():
              break;
          }
        }
      }
    });

    test('every subpath closes (winding depends on closed loops)', () {
      for (final char in ['a', 'g', 'B', 'o']) {
        final quads = outlineToQuads(outlineOf(char));
        // net edge vector sum of a closed loop set is zero-ish; stronger:
        // each endpoint appears as a start point exactly as often
        final starts = <String, int>{};
        for (final q in quads) {
          starts.update('${q.x0},${q.y0}', (v) => v + 1, ifAbsent: () => 1);
          starts.update('${q.x1},${q.y1}', (v) => v - 1, ifAbsent: () => -1);
        }
        starts.removeWhere((_, v) => v == 0);
        expect(starts, isEmpty, reason: '"$char" has unbalanced endpoints');
      }
    });
  });

  group('buildBands', () {
    test('bands cover each curve\'s y-range, sorted by descending max x',
        () {
      final quads = outlineToQuads(outlineOf('g'));
      final bands = buildBands(quads, bandCount: 8);
      expect(bands.bandCount, 8);
      for (var b = 0; b < bands.bandCount; b++) {
        final y0 = bands.minY + b * bands.bandHeight;
        final y1 = y0 + bands.bandHeight;
        final inBand = bands.bands[b];
        // sorted by descending max x
        for (var i = 1; i < inBand.length; i++) {
          expect(quads[inBand[i - 1]].maxX,
              greaterThanOrEqualTo(quads[inBand[i]].maxX));
        }
        // every curve overlapping the band is listed
        for (var i = 0; i < quads.length; i++) {
          final overlaps = quads[i].maxY > y0 && quads[i].minY < y1;
          if (overlaps) {
            expect(inBand, contains(i),
                reason: 'band $b must list curve $i');
          }
        }
      }
    });

    test('overflow flags a band exceeding the cap', () {
      // 17 horizontal-ish curves stacked into the same y range
      final curves = [
        for (var i = 0; i < 17; i++)
          QuadCurve(0, i * 0.001, 0.5, i * 0.001, 1, i * 0.001 + 0.0005),
      ];
      final bands = buildBands(curves, bandCount: 1, maxCurvesPerBand: 16);
      expect(bands.overflow, isTrue);
      // real glyphs at 8 bands stay under the default cap
      for (final char in ['a', 'g', 'B', 'o', 'S']) {
        final b = buildBands(outlineToQuads(outlineOf(char)), bandCount: 8);
        expect(b.overflow, isFalse, reason: '"$char" overflows 16/band');
      }
    });
  });

  group('band evaluator', () {
    test('winding coverage matches the strip fine raster on real glyphs',
        () {
      for (final char in ['a', 'g', 'B', 'o']) {
        final outline = outlineOf(char);
        final quads = outlineToQuads(outline);
        final bands = buildBands(quads, bandCount: 8);
        expect(bands.overflow, isFalse);

        // rasterize via strips at a 24-px em into a small viewport
        const size = 24.0;
        const w = 32, h = 32;
        const m = PdfMatrix(size, 0, 0, -size, 4, 26); // em -> device, y-flip
        final gen = StripGenerator()
          ..glyphCache = null
          ..begin(w, h);
        gen.fillOutline(FlattenedOutline.of(outline), m, 0xFF000000);
        final stripCov = decodeStripCoverage(gen.strips, w, h);

        // band-evaluator coverage: supersample winding in em space
        final inv = m.inverted()!;
        final bandCov = Uint8List(w * h);
        const ss = 8;
        for (var py = 0; py < h; py++) {
          for (var px = 0; px < w; px++) {
            var inside = 0;
            for (var sy = 0; sy < ss; sy++) {
              for (var sx = 0; sx < ss; sx++) {
                final dx = px + (sx + 0.5) / ss, dy = py + (sy + 0.5) / ss;
                final ex = inv.transformX(dx, dy);
                final ey = inv.transformY(dx, dy);
                if (glyphWindingAt(quads, bands, ex, ey) != 0) inside++;
              }
            }
            bandCov[py * w + px] = (inside * 255 + ss * ss ~/ 2) ~/ (ss * ss);
          }
        }
        expect(meanAbsDiff(bandCov, stripCov), lessThanOrEqualTo(2.5),
            reason: '"$char" band evaluation vs strip raster');
      }
    });
  });

  group('AA evaluator', () {
    test('dual-ray AA coverage tracks supersampled area coverage', () {
      for (final char in ['a', 'g', 'B', 'o']) {
        final quads = outlineToQuads(outlineOf(char));
        final bands = buildBands(quads, bandCount: 8);
        const size = 24.0;
        const w = 32, h = 32;
        const m = PdfMatrix(size, 0, 0, -size, 4, 26);
        final inv = m.inverted()!;
        var sum = 0.0;
        var maxD = 0.0;
        for (var py = 0; py < h; py++) {
          for (var px = 0; px < w; px++) {
            // ground truth: supersampled binary winding (area coverage)
            var inside = 0;
            const ss = 8;
            for (var sy = 0; sy < ss; sy++) {
              for (var sx = 0; sx < ss; sx++) {
                final ex = inv.transformX(px + (sx + 0.5) / ss, py + (sy + 0.5) / ss);
                final ey = inv.transformY(px + (sx + 0.5) / ss, py + (sy + 0.5) / ss);
                if (glyphWindingAt(quads, bands, ex, ey) != 0) inside++;
              }
            }
            final want = inside / (ss * ss);
            final ex = inv.transformX(px + 0.5, py + 0.5);
            final ey = inv.transformY(px + 0.5, py + 0.5);
            final got = glyphCoverageAA(quads, bands, ex, ey, size, size);
            final d = (got - want).abs();
            sum += d;
            if (d > maxD) maxD = d;
          }
        }
        final mean = 255 * sum / (w * h);
        // ignore: avoid_print
        print('AA-REF: "$char" mean ${mean.toStringAsFixed(2)}/255 '
            'max ${(255 * maxD).toStringAsFixed(0)}/255');
        // The dual-ray approximation is not exact area coverage (corners,
        // thin features), but must track it closely on body text.
        expect(mean, lessThanOrEqualTo(4.0),
            reason: '"\$char" AA coverage drifts from area coverage');
      }
    });
  });

  group('texel encoding', () {
    test('fixed point roundtrips within 1/8192 em', () {
      for (final v in [-3.999, -1.0, -0.123456, 0.0, 0.5, 1.25, 3.999]) {
        expect((fixedToEm(emToFixed(v)) - v).abs(), lessThan(1 / 8192));
      }
    });

    test('encode/decode roundtrip preserves curves, bands, and winding', () {
      final outline = outlineOf('g');
      final quads = outlineToQuads(outline);
      final bands = buildBands(quads, bandCount: 8);
      final tex = encodeGlyphTexels(quads, bands);
      expect(tex.overflow, isFalse);
      expect(tex.pixels.length, tex.width * tex.height * 4);

      // decode side (mirrors the shader's reads)
      final data = ByteData.sublistView(tex.pixels);
      (int, int) texel(int i) => (
            data.getUint16(i * 4, Endian.little),
            data.getUint16(i * 4 + 2, Endian.little),
          );
      final (bandCount, curveCount) = texel(0);
      expect(bandCount, 8);
      expect(curveCount, quads.length);

      final decoded = <QuadCurve>[];
      final curveBase = 1 +
          2 * bandCount +
          bands.bands.fold<int>(0, (a, b) => a + b.length) +
          bands.vBands.fold<int>(0, (a, b) => a + b.length);
      for (var b = 0; b < bandCount; b++) {
        final (offset, count) = texel(1 + b);
        final refs = <int>[];
        for (var i = 0; i < count; i++) {
          final (curveTexel, _) = texel(offset + i);
          expect((curveTexel - curveBase) % 3, 0);
          refs.add((curveTexel - curveBase) ~/ 3);
        }
        expect(refs, bands.bands[b].toList(),
            reason: 'horizontal band $b reference list');
        final (vOffset, vCount) = texel(1 + bandCount + b);
        final vRefs = <int>[];
        for (var i = 0; i < vCount; i++) {
          final (curveTexel, _) = texel(vOffset + i);
          vRefs.add((curveTexel - curveBase) ~/ 3);
        }
        expect(vRefs, bands.vBands[b].toList(),
            reason: 'vertical band $b reference list');
      }
      for (var i = 0; i < curveCount; i++) {
        final (x0, y0) = texel(curveBase + 3 * i);
        final (cx, cy) = texel(curveBase + 3 * i + 1);
        final (x1, y1) = texel(curveBase + 3 * i + 2);
        decoded.add(QuadCurve(fixedToEm(x0), fixedToEm(y0), fixedToEm(cx),
            fixedToEm(cy), fixedToEm(x1), fixedToEm(y1)));
        expect((decoded[i].x0 - quads[i].x0).abs(), lessThan(1 / 8192));
        expect((decoded[i].cy - quads[i].cy).abs(), lessThan(1 / 8192));
      }

      // winding from decoded curves matches the original at sample points
      final decodedBandsObj = buildBands(decoded, bandCount: 8);
      final rand = math.Random(7);
      for (var i = 0; i < 200; i++) {
        final x = bands.minX + rand.nextDouble() * (bands.maxX - bands.minX);
        final y = bands.minY + rand.nextDouble() * (bands.maxY - bands.minY);
        expect(glyphWindingAt(decoded, decodedBandsObj, x, y) != 0,
            glyphWindingAt(quads, bands, x, y) != 0,
            reason: 'inside/outside at ($x,$y)');
      }
    });

    test('oversized curve streams throw (caller falls back to strips)', () {
      final curves = [
        for (var i = 0; i < 22000; i++)
          QuadCurve(0, i * 1e-5, 0.5, i * 1e-5, 1, i * 1e-5 + 1e-5),
      ];
      final bands = buildBands(curves, bandCount: 1, maxCurvesPerBand: 1 << 20);
      expect(() => encodeGlyphTexels(curves, bands), throwsArgumentError);
    });
  });
}
