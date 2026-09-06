// Diagnostic harness (set SLUG_DEBUG=1 to run): dumps the slug shader's
// internals - raw uv varying, band selection, per-ray sums, per-curve H
// contributions - through pdf_slug.frag's uDebug modes. This is the tool
// that found both B3 platform bugs (the u16-decode double-rounding loop
// overrun and Impeller's texcoord-grid snapshot evaluation); keep it.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:dart_pdf_editor/strips.dart';

Future<Uint8List> renderMode(double mode, double param) async {
  final font = TrueTypeFont.parse(
      File('../dart_pdf_editor_assets/assets/fonts/DejaVuSans.ttf').readAsBytesSync())!;
  final outline = font.outlineForGlyph(font.gidForUnicode(0x67))!;
  final r = PdfTextRun(
    text: 'g',
    transform: const PdfMatrix(24, 0, 0, -24, 4, 22),
    color: const PdfColor(1, 1, 1),
    width: 0.6,
    glyphs: [PdfGlyphPlacement(offset: 0, outline: outline)],
  );
  StripPdfDevice.slugGlyphs = true;
  StripPdfDevice.debugSlugMode = mode;
  StripPdfDevice.debugSlugParam = param;
  try {
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec);
    final device = StripPdfDevice(canvas,
        pageToDevice: PdfMatrix.identity,
        deviceWidth: 32,
        deviceHeight: 32,
        pixelRatio: 1);
    device.drawText(r);
    await device.finish();
    final pic = rec.endRecording();
    final img = await pic.toImage(32, 32);
    final px = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!
        .buffer
        .asUint8List();
    img.dispose();
    pic.dispose();
    device.dispose();
    return px;
  } finally {
    StripPdfDevice.slugGlyphs = false;
    StripPdfDevice.debugSlugMode = 0;
    StripPdfDevice.debugSlugParam = 0;
  }
}

const probes = [(10, 13), (5, 13), (10, 14), (20, 13), (10, 20)];

void main() {
  if (Platform.environment['SLUG_DEBUG'] != '1') {
    test('slug shader debug dumps', skip: 'set SLUG_DEBUG=1 to run', () {});
    return;
  }
  testWidgets('dump raw uv varying', (tester) async {
    await tester.runAsync(() async {
      final px = await renderMode(4, 0);
      for (final (x, y) in probes) {
        final o = (y * 32 + x) * 4;
        // ignore: avoid_print
        print('DBG4 ($x,$y): u=${px[o] / 255} v=${px[o + 1] * 8 / 255} '
            'fracv=${px[o + 2] / 255}');
      }
    });
  });

  testWidgets('dump shader band selection', (tester) async {
    await tester.runAsync(() async {
      final px = await renderMode(1, 0);
      for (final (x, y) in probes) {
        final o = (y * 32 + x) * 4;
        // ignore: avoid_print
        print('DBG1 ($x,$y): hb=${px[o] * 8 / 255} '
            'count=${px[o + 1] * 16 / 255} emY=${(px[o + 2] / 255 - 0.5) * 4}');
      }
    });
  });

  testWidgets('dump ray sums', (tester) async {
    await tester.runAsync(() async {
      final px = await renderMode(2, 0);
      for (final (x, y) in probes) {
        final o = (y * 32 + x) * 4;
        // ignore: avoid_print
        print('DBG2 ($x,$y): |covH|=${px[o] / 255} |covV|=${px[o + 1] / 255} '
            'covH=${(px[o + 2] / 255 - 0.5) * 4}');
      }
    });
  });

  testWidgets('dump per-curve H contributions', (tester) async {
    await tester.runAsync(() async {
      for (var i = 0; i < 8; i++) {
        final px = await renderMode(3, i.toDouble());
        for (final (x, y) in probes.take(2)) {
          final o = (y * 32 + x) * 4;
          // ignore: avoid_print
          print('DBG3 i=$i ($x,$y): d=${(px[o] / 255 - 0.5) * 4} '
              'e0=${(px[o + 1] / 255 - 0.5) * 4} '
              'e1=${(px[o + 2] / 255 - 0.5) * 4}');
        }
      }
    });
  });
}
