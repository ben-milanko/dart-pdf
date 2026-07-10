// B3 Slug glyph rendering: shader-vs-Dart-reference exactness, text-page
// slug-vs-strip-vs-canvas parity, batching stats, and the C2 sharpness
// property (a recorded picture's Slug text stays sharp under canvas zoom,
// unlike baked strips).
//
// Run with the default backend AND with --enable-impeller; Impeller runs
// must set SLUG_IMPELLER=1. Impeller evaluates drawVertices runtime
// effects on an integer texcoord-unit grid that ignores the CTM scale
// (a snapshot sampled by the vertex UVs), so there the slug output is a
// record-resolution glyph raster: exactness tolerances widen to resampling
// error and the C2 zoom-sharpness property does not hold (slug only has to
// match the baked-strip control).
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_graphics/raster.dart';
// ignore: implementation_imports
import 'package:pdf_graphics/src/fonts/truetype.dart';
import 'package:dart_pdf_editor/strips.dart';

final bool _impeller = Platform.environment['SLUG_IMPELLER'] == '1';

TrueTypeFont? _font;
TrueTypeFont get font =>
    _font ??= TrueTypeFont.parse(
        File('assets/fonts/DejaVuSans.ttf').readAsBytesSync())!;

PdfPath outlineOf(String char) =>
    font.outlineForGlyph(font.gidForUnicode(char.codeUnitAt(0)))!;

/// A text run of [text] with real DejaVu outlines, em->page transform
/// scale [size] at ([x], [y]) baseline (y-up page space assumed flipped by
/// the caller's transform; these tests use y-down device==page space, so
/// the transform flips em y).
PdfTextRun run(String text, double size, double x, double y,
    {PdfColor color = PdfColor.black}) {
  final glyphs = <PdfGlyphPlacement>[];
  var pen = 0.0;
  for (final code in text.codeUnits) {
    if (code == 0x20) {
      pen += 0.32;
      continue;
    }
    final gid = font.gidForUnicode(code);
    glyphs.add(PdfGlyphPlacement(offset: pen, outline: font.outlineForGlyph(gid)));
    pen += font.advanceForGlyph(gid) ?? 0.6;
  }
  return PdfTextRun(
    text: text,
    transform: PdfMatrix(size, 0, 0, -size, x, y),
    color: color,
    width: pen,
    glyphs: glyphs,
  );
}

Future<Uint8List> pixelsOf(ui.Image image) async =>
    (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
        .buffer
        .asUint8List();

double meanDiff(Uint8List a, Uint8List b) {
  var sum = 0;
  for (var i = 0; i < a.length; i += 4) {
    var d = 0;
    for (var c = 0; c < 3; c++) {
      final dc = (a[i + c] - b[i + c]).abs();
      if (dc > d) d = dc;
    }
    sum += d;
  }
  return sum / (a.length ~/ 4);
}

/// Renders [draw] through a StripPdfDevice (identity page->device) into a
/// [w]x[h] image; [slug] toggles Slug glyph mode for this render.
Future<ui.Image> render(
    void Function(StripPdfDevice d) draw, int w, int h,
    {required bool slug, double zoom = 1}) async {
  final was = StripPdfDevice.slugGlyphs;
  StripPdfDevice.slugGlyphs = slug;
  try {
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec);
    canvas.drawRect(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        ui.Paint()..color = const ui.Color(0xFFFFFFFF));
    final device = StripPdfDevice(canvas,
        pageToDevice: PdfMatrix.identity,
        deviceWidth: w,
        deviceHeight: h,
        pixelRatio: 1);
    draw(device);
    await device.finish();
    final picture = rec.endRecording();
    // optionally replay the recorded picture under a canvas zoom (C2)
    final outRec = ui.PictureRecorder();
    final outCanvas = ui.Canvas(outRec);
    outCanvas.scale(zoom);
    outCanvas.drawPicture(picture);
    final out = outRec.endRecording();
    final image =
        await out.toImage((w * zoom).round(), (h * zoom).round());
    picture.dispose();
    out.dispose();
    device.dispose();
    return image;
  } finally {
    StripPdfDevice.slugGlyphs = was;
  }
}

void main() {
  testWidgets('slug shader matches the Dart glyphCoverageAA reference',
      (tester) async {
    await tester.runAsync(() async {
      const w = 32, h = 32;
      const size = 24.0;
      final outline = outlineOf('g');
      final quads = outlineToQuads(outline);
      final bands = buildBands(quads, bandCount: 8);
      expect(bands.overflow, isFalse);

      final r = PdfTextRun(
        text: 'g',
        transform: const PdfMatrix(size, 0, 0, -size, 4, 22),
        color: PdfColor.black,
        width: 0.6,
        glyphs: [PdfGlyphPlacement(offset: 0, outline: outline)],
      );
      final image = await render((d) => d.drawText(r), w, h, slug: true);
      final got = await pixelsOf(image);
      image.dispose();

      // reference: shader formula in Dart, quantized scale like the slot
      final sq = (size * 16).round() / 16.0;
      const m = PdfMatrix(size, 0, 0, -size, 4, 22);
      final inv = m.inverted()!;
      var sum = 0.0;
      var maxD = 0;
      for (var py = 0; py < h; py++) {
        for (var px = 0; px < w; px++) {
          final ex = inv.transformX(px + 0.5, py + 0.5);
          final ey = inv.transformY(px + 0.5, py + 0.5);
          final cov = glyphCoverageAA(quads, bands, ex, ey, sq, sq);
          final want = (255 * (1 - cov)).round();
          final d = (got[(py * w + px) * 4] - want).abs();
          sum += d;
          if (d > maxD) maxD = d;
        }
      }
      final mean = sum / (w * h);
      // ignore: avoid_print
      print('SLUG-REF: mean ${mean.toStringAsFixed(2)}/255 max $maxD/255');
      for (var py = 0; py < h; py++) {
        for (var px = 0; px < w; px++) {
          final ex = inv.transformX(px + 0.5, py + 0.5);
          final ey = inv.transformY(px + 0.5, py + 0.5);
          final cov = glyphCoverageAA(quads, bands, ex, ey, sq, sq);
          final want = (255 * (1 - cov)).round();
          final d = (got[(py * w + px) * 4] - want).abs();
          if (d > 32) {
            // ignore: avoid_print
            print('  WORST ($px,$py) got=${got[(py * w + px) * 4]} want=$want '
                'em=(${ex.toStringAsFixed(4)},${ey.toStringAsFixed(4)}) '
                'hband=${bands.bandFor(ey)} vband=${bands.vBandFor(ex)}');
          }
        }
      }
      // Skia: fixed-point curve quantization (1/8192 em) + float32 vs
      // float64 land within a few counts; structural mismatch would be
      // tens. Impeller: the snapshot resamples the glyph raster at the
      // subpixel quad offset, so edges shift by up to a pixel's coverage.
      expect(mean, lessThanOrEqualTo(_impeller ? 8.0 : 1.5));
      expect(maxD, lessThanOrEqualTo(_impeller ? 192 : 24));
    });
  });

  testWidgets('text page: slug vs strip vs canvas-style parity',
      (tester) async {
    await tester.runAsync(() async {
      const w = 220, h = 64;
      void page(StripPdfDevice d) {
        d.drawText(run('Sphinx of black', 16, 6, 22));
        d.drawText(run('quartz judge', 11, 6, 40,
            color: const PdfColor(0.8, 0.1, 0.2)));
        d.drawText(run('vow 42', 24, 6, 60));
      }

      final slugImg = await render(page, w, h, slug: true);
      final stripImg = await render(page, w, h, slug: false);
      final slugPx = await pixelsOf(slugImg);
      final stripPx = await pixelsOf(stripImg);
      slugImg.dispose();
      stripImg.dispose();

      final d = meanDiff(slugPx, stripPx);
      // signed bias: negative = slug renders darker (higher coverage)
      var signed = 0;
      for (var i = 0; i < slugPx.length; i += 4) {
        signed += slugPx[i] - stripPx[i];
      }
      // ignore: avoid_print
      print('SLUG-TEXT: slug-vs-strip mean ${d.toStringAsFixed(2)}/255 '
          'signed ${(signed / (slugPx.length / 4)).toStringAsFixed(2)}/255');
      // Slug AA is dual-ray, strips are exact area coverage: text edges
      // differ by design, but the page must agree closely overall.
      expect(d, lessThanOrEqualTo(_impeller ? 8.0 : 4.0));

      // batching: one slug batch, no strip quads for pure text
      StripPdfDevice.resetStats();
      final again = await render(page, w, h, slug: true);
      again.dispose();
      expect(StripPdfDevice.totalSlugQuads, greaterThan(20));
      expect(StripPdfDevice.totalStripQuads, 0);
      expect(StripPdfDevice.totalFlushes, 1);
    });
  });

  testWidgets('minification guard: tiny text keeps the strip path',
      (tester) async {
    await tester.runAsync(() async {
      StripPdfDevice.resetStats();
      final image = await render(
          (d) => d.drawText(run('tiny glyphs below guard', 3, 2, 12)),
          80, 16, slug: true);
      image.dispose();
      expect(StripPdfDevice.totalSlugQuads, 0,
          reason: 'sub-guard text must not take the slug path');
      expect(StripPdfDevice.totalStripQuads, greaterThan(0));
    });
  });

  testWidgets('painter order: vector after slug text forces a window split',
      (tester) async {
    await tester.runAsync(() async {
      const w = 64, h = 32;
      final image = await render((d) {
        d.drawText(run('gg', 24, 4, 26));
        // opaque box painted AFTER the text must cover it
        d.fillPath(
            PdfPath([
              PdfMoveTo(0, 0),
              PdfLineTo(40, 0),
              PdfLineTo(40, 32),
              PdfLineTo(0, 32),
              const PdfClosePath(),
            ]),
            const PdfColor(0, 0.6, 0),
            PdfFillRule.nonzero,
            1);
      }, w, h, slug: true);
      final px = await pixelsOf(image);
      image.dispose();
      // sample inside the box where the glyph would be: pure green
      final o = (16 * w + 12) * 4;
      expect(px[o], lessThanOrEqualTo(2), reason: 'text must be covered');
      expect(px[o + 1], inInclusiveRange(140, 165));
    });
  });

  testWidgets('C2 sharpness: recorded slug text survives 3x canvas zoom',
      (tester) async {
    await tester.runAsync(() async {
      const w = 120, h = 40;
      void page(StripPdfDevice d) {
        d.drawText(run('Rgke 37', 18, 4, 30));
      }

      // sharp truth: freshly rendered at 3x (strip raster at real 3x res)
      final sharp = await render((d) {
        d.drawText(run('Rgke 37', 54, 12, 90));
      }, w * 3, h * 3, slug: false);
      // recorded at 1x, replayed under 3x canvas scale
      final slugZoom = await render(page, w, h, slug: true, zoom: 3);
      final stripZoom = await render(page, w, h, slug: false, zoom: 3);

      final sharpPx = await pixelsOf(sharp);
      final slugPx = await pixelsOf(slugZoom);
      final stripPx = await pixelsOf(stripZoom);
      sharp.dispose();
      slugZoom.dispose();
      stripZoom.dispose();

      final slugErr = meanDiff(slugPx, sharpPx);
      final stripErr = meanDiff(stripPx, sharpPx);
      // ignore: avoid_print
      print('SLUG-ZOOM: slug-picture@3x vs sharp ${slugErr.toStringAsFixed(2)}'
          '/255, strip-picture@3x vs sharp ${stripErr.toStringAsFixed(2)}/255');
      if (_impeller) {
        // Impeller's texcoord-grid snapshot ignores the CTM: slug text is
        // a record-resolution raster there, no sharper than baked strips.
        expect(slugErr, lessThan(stripErr * 1.3),
            reason: 'slug text must stay comparable to strips under zoom');
        return;
      }
      // Skia evaluates the shader per fragment: slug quads re-resolve at
      // the zoomed resolution (geometry stays exact; only the AA ramp
      // keeps its recorded width), while baked strips scale like any
      // raster.
      expect(slugErr, lessThan(stripErr * 0.5),
          reason: 'slug text must be dramatically sharper under zoom');
    });
  });
}
