// Per-glyph substituted-text composition (#454): composing a run from cached
// single-character layouts must (a) place glyphs exactly where whole-run
// shaping does for text with no cross-character kerning (the flutter_test font
// is such a font), (b) fall back to whole-run shaping for anything outside the
// composable set, and (c) reuse per-character layouts so unique runs stop
// re-shaping.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

Future<Uint8List> _rasterRun(String text, {required bool perGlyph}) async {
  CanvasPdfDevice.clearTextLayoutCache();
  CanvasPdfDevice.perGlyphSubstitutedText = perGlyph;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)
    ..drawColor(const Color(0xFFFFFFFF), BlendMode.src);
  CanvasPdfDevice(canvas).drawText(
    PdfTextRun(
      text: text,
      transform: const PdfMatrix(20, 0, 0, 20, 20, 80),
      color: const PdfColor(0, 0, 0),
      width: text.length * 0.5,
      fontName: 'Helvetica',
      fontSize: 20,
    ),
  );
  final image = await recorder.endRecording().toImage(900, 160);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return Uint8List.fromList(data!.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}

int _diffPixels(Uint8List a, Uint8List b) {
  var n = 0;
  for (var i = 0; i < a.length; i += 4) {
    if (a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2]) n++;
  }
  return n;
}

void main() {
  tearDown(() {
    CanvasPdfDevice.perGlyphSubstitutedText = false;
    CanvasPdfDevice.clearTextLayoutCache();
  });

  testWidgets('a composable run composes identically to whole-run shaping',
      (tester) async {
    await tester.runAsync(() async {
      // A gate-composable run (isolated letters, tabular digits). The
      // flutter_test font has no kerning, so per-character placement must match
      // whole-run placement to the pixel - a placement bug would show here.
      const label = 'N1234.567 E7654.321 A3 B7';
      final whole = await _rasterRun(label, perGlyph: false);
      final composed = await _rasterRun(label, perGlyph: true);
      expect(_diffPixels(whole, composed), 0,
          reason: 'composed glyphs must land exactly where whole-run does');
    });
  });

  testWidgets('a non-composable run falls back to whole-run shaping',
      (tester) async {
    await tester.runAsync(() async {
      // Lowercase (ligature-prone) is outside the composable set, so the flag
      // must not change its rendering at all.
      const prose = 'affine ligature office';
      final off = await _rasterRun(prose, perGlyph: false);
      final on = await _rasterRun(prose, perGlyph: true);
      expect(_diffPixels(off, on), 0,
          reason: 'non-composable text must be untouched by the flag');
    });
  });

  testWidgets('unique composable runs reuse per-character layouts',
      (tester) async {
    await tester.runAsync(() async {
      CanvasPdfDevice.clearTextLayoutCache();
      CanvasPdfDevice.perGlyphSubstitutedText = true;
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final device = CanvasPdfDevice(canvas);
      // Many runs that are unique as whole strings but share one alphabet.
      for (var i = 0; i < 200; i++) {
        device.drawText(
          PdfTextRun(
            text: 'N${1000000 + i} E${9000000 - i}',
            transform: const PdfMatrix(6, 0, 0, 6, 20, 80),
            color: const PdfColor(0, 0, 0),
            width: 3,
            fontName: 'Helvetica',
            fontSize: 6,
          ),
        );
      }
      recorder.endRecording().dispose();
      // Composed runs never touch the run cache, and the glyph cache holds only
      // the ~14 distinct characters (digits, space, N, E) - not 200 runs.
      expect(CanvasPdfDevice.debugTextLayoutCacheLength, 0,
          reason: 'composed runs bypass the run cache');
      expect(CanvasPdfDevice.debugGlyphLayoutCacheLength, lessThan(20),
          reason: '200 unique runs collapse to an alphabet of glyphs');
      expect(CanvasPdfDevice.debugGlyphLayoutCacheLength, greaterThan(0));
    });
  });

  testWidgets('exact placement reuses cached glyph paragraphs across labels',
      (tester) async {
    await tester.runAsync(() async {
      CanvasPdfDevice.clearTextLayoutCache();
      CanvasPdfDevice.debugResetTextShape();
      final recorder = ui.PictureRecorder();
      final device = CanvasPdfDevice(ui.Canvas(recorder));
      for (var i = 0; i < 100; i++) {
        final text = 'AB${(i ~/ 10) % 10}${i % 10}';
        device.drawText(PdfTextRun(
          text: text,
          charOffsets: const [0, 0.05, 0.1, 0.75, 0.8],
          transform: const PdfMatrix(6, 0, 0, 6, 20, 80),
          color: const PdfColor(0, 0, 0),
          width: 0.8,
          fontName: 'Helvetica',
          fontSize: 6,
        ));
      }
      recorder.endRecording().dispose();

      expect(CanvasPdfDevice.debugTextLayoutCacheLength, 100);
      expect(CanvasPdfDevice.debugGlyphLayoutCacheLength, lessThan(20));
      expect(CanvasPdfDevice.debugTextPainterBuilds, lessThan(20),
          reason: '100 unique labels must shape the alphabet, not 400 fresh '
              'character paragraphs');
    });
  });

  testWidgets('exact placement composes unique multi-character labels',
      (tester) async {
    await tester.runAsync(() async {
      // Offsets the fixed-pitch test font agrees with, so every word is one
      // piece of several characters - the unique CAD label that used to shape
      // a fresh paragraph per word. The test font kerns nothing, so the pieces
      // are laid out from the glyph cache instead.
      CanvasPdfDevice.clearTextLayoutCache();
      CanvasPdfDevice.debugResetTextShape();
      final recorder = ui.PictureRecorder();
      final device = CanvasPdfDevice(ui.Canvas(recorder));
      for (var i = 0; i < 100; i++) {
        final text = 'N${100000 + 7 * i}.5 E${900000 - 3 * i}.25';
        device.drawText(PdfTextRun(
          text: text,
          charOffsets: [for (var j = 0; j <= text.length; j++) j.toDouble()],
          transform: const PdfMatrix(6, 0, 0, 6, 20, 80),
          color: const PdfColor(0, 0, 0),
          width: text.length.toDouble(),
          fontName: 'Helvetica',
          fontSize: 6,
        ));
      }
      recorder.endRecording().dispose();

      expect(CanvasPdfDevice.debugTextLayoutCacheLength, 100);
      expect(CanvasPdfDevice.debugTextPainterBuilds, lessThan(30),
          reason: '200 unique word pieces must come from the alphabet, plus '
              "the face's one-off kerning check");
    });
  });

  testWidgets('a run with more characters than the glyph cache still paints',
      (tester) async {
    await tester.runAsync(() async {
      // 4,200 distinct ideographs overflow the 4,096-entry glyph cache inside
      // one run: the first ones resolved are evicted - and disposed - before
      // the run gets to retain them. Pen steps alternating 1 and 2 em against
      // a fixed-pitch face cut every character into a piece of its own, so
      // each is retained from the glyph cache.
      CanvasPdfDevice.clearTextLayoutCache();
      final text = String.fromCharCodes([
        for (var cu = 0x4E00; cu < 0x4E00 + 4200; cu++) cu,
      ]);
      final offsets = <double>[0];
      for (var j = 0; j < text.length; j++) {
        offsets.add(offsets.last + (j.isEven ? 1 : 2));
      }
      final recorder = ui.PictureRecorder();
      CanvasPdfDevice(ui.Canvas(recorder)).drawText(PdfTextRun(
        text: text,
        charOffsets: offsets,
        transform: const PdfMatrix(1, 0, 0, 1, 0, 80),
        color: const PdfColor(0, 0, 0),
        width: offsets.last,
        fontName: 'Helvetica',
        fontSize: 1,
      ));
      final picture = recorder.endRecording();
      final image = await picture.toImage(64, 64);
      image.dispose();
      picture.dispose();
      expect(CanvasPdfDevice.debugTextLayoutCacheLength, 1);
    });
  });
}
