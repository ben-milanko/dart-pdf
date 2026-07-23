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
}
