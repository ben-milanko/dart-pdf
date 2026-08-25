// Probe: walk the assembled slug atlas in Dart exactly like the shader
// and compare against glyphCoverageAA - splits atlas-assembly bugs from
// shader-semantics bugs.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_graphics/raster.dart';

void main() {
  test('atlas walk matches glyphCoverageAA', () {
    final font = TrueTypeFont.parse(
        File('../dart_pdf_editor_assets/assets/fonts/DejaVuSans.ttf').readAsBytesSync())!;
    final outline = font.outlineForGlyph(font.gidForUnicode(0x67))!; // g
    final quads = outlineToQuads(outline);
    final bands = buildBands(quads, bandCount: 8);
    final data = SlugGlyphData.of(outline);
    expect(data.overflow, isFalse);

    final builder = SlugBatchBuilder();
    const size = 24.0;
    const emToPage = PdfMatrix(size, 0, 0, -size, 4, 22);
    builder.addGlyph(outline, data, emToPage, size, size, 0xFF000000);
    final batch = builder.build()!;
    final px = batch.atlasPixels;
    final u16 = ByteData.sublistView(px);
    (double, double) pair(int t) => (
          u16.getUint16(t * 4, Endian.little).toDouble(),
          u16.getUint16(t * 4 + 2, Endian.little).toDouble(),
        );
    (double, double) em(int t) {
      final (a, b) = pair(t);
      return ((a - 32768) / 8192, (b - 32768) / 8192);
    }

    double walk(double emX, double emY) {
      final (baseLo, baseHi) = pair(0);
      final base = (baseLo + baseHi * 65536).toInt();
      final (minY, bandH) = em(1);
      final (minX, bandW) = em(2);
      final (sx16, sy16) = pair(3);
      final sx = sx16 / 16, sy = sy16 / 16;
      final (bandCountD, _) = pair(base);
      final bandCount = bandCountD.toInt();

      double ray(bool vertical) {
        final level = vertical ? emX : emY;
        final bandIdx = vertical
            ? ((emX - minX) / bandW).floor().clamp(0, bandCount - 1)
            : ((emY - minY) / bandH).floor().clamp(0, bandCount - 1);
        final tableTexel = base + 1 + (vertical ? bandCount : 0) + bandIdx;
        final (offD, countD) = pair(tableTexel);
        var cov = 0.0;
        for (var i = 0; i < countD.toInt(); i++) {
          final (refD, _) = pair(base + offD.toInt() + i);
          final t0 = base + refD.toInt();
          final (x0, y0) = em(t0);
          final (cx, cy) = em(t0 + 1);
          final (x1, y1) = em(t0 + 2);
          final e0 = (vertical ? x0 : y0) - level;
          final ec = (vertical ? cx : cy) - level;
          final e1 = (vertical ? x1 : y1) - level;
          final q0 = vertical ? y0 : x0;
          final qc = vertical ? cy : cx;
          final q1 = vertical ? y1 : x1;
          final origin = vertical ? emY : emX;
          final scale = vertical ? sy : sx;
          final s0 = e0 > 0, s1 = e1 > 0;
          final a = e0 - 2 * ec + e1;
          final b = 2 * (ec - e0);
          double at(double t) {
            final mt = 1 - t;
            return mt * mt * q0 + 2 * mt * t * qc + t * t * q1;
          }

          double weight(double t) =>
              ((at(t) - origin) * scale + 0.5).clamp(0.0, 1.0);
          final r = sqRoot(b * b - 4 * a * e0);
          final q = -0.5 * (b + (b >= 0 ? r : -r));
          final tA = a.abs() > 1e-12 ? q / a : 2.0;
          final tB = q.abs() > 1e-12 ? e0 / q : 2.0;
          if (s0 != s1) {
            final t = (tB >= 0 && tB <= 1) ? tB : tA;
            final w = weight(t.clamp(0.0, 1.0));
            final up = vertical ? !s1 : s1;
            cov += up ? w : -w;
          } else if (b * b - 4 * a * e0 > 0 &&
              tA > 0 &&
              tA < 1 &&
              tB > 0 &&
              tB < 1) {
            final wMin = weight(math.min(tA, tB));
            final wMax = weight(math.max(tA, tB));
            var sum = s0 ? (wMax - wMin) : (wMin - wMax);
            if (vertical) sum = -sum;
            cov += sum;
          }
        }
        return cov;
      }

      final h = ray(false).abs().clamp(0.0, 1.0);
      final v = ray(true).abs().clamp(0.0, 1.0);
      return (h + v) / 2;
    }

    const m = emToPage;
    final inv = m.inverted()!;
    var worst = 0.0;
    var sum = 0.0;
    for (var py = 0; py < 32; py++) {
      for (var pxi = 0; pxi < 32; pxi++) {
        final ex = inv.transformX(pxi + 0.5, py + 0.5);
        final ey = inv.transformY(pxi + 0.5, py + 0.5);
        final want = glyphCoverageAA(quads, bands, ex, ey, size, size);
        final got = walk(ex, ey);
        final d = (got - want).abs() * 255;
        sum += d;
        if (d > worst) {
          worst = d;
          if (d > 16) {
            // ignore: avoid_print
            print('ATLAS-WALK worst ($pxi,$py) got=${got.toStringAsFixed(3)} '
                'want=${want.toStringAsFixed(3)} em=($ex,$ey)');
          }
        }
      }
    }
    // ignore: avoid_print
    print('ATLAS-WALK: mean ${(sum / 1024).toStringAsFixed(2)} '
        'max ${worst.toStringAsFixed(1)}');
    expect(worst, lessThanOrEqualTo(16));
  });
}

double sqRoot(double v) => v <= 0 ? 0 : math.sqrt(v);
