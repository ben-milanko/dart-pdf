// Scratch debug harness for the strip device (not part of the suite):
// renders STRIP_DEBUG_PDF page STRIP_DEBUG_PAGE through both devices and
// writes canvas/strips/diff PNGs to STRIP_DEBUG_OUT. Skips unless set.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/strips.dart';

import 'render_smoke_test.dart' show loadSystemFonts;

void main() {
  final pdf = Platform.environment['STRIP_DEBUG_PDF'];
  final page = int.tryParse(Platform.environment['STRIP_DEBUG_PAGE'] ?? '0')!;
  final out = Platform.environment['STRIP_DEBUG_OUT'] ?? '/tmp';
  final ratio =
      double.tryParse(Platform.environment['STRIP_DEBUG_RATIO'] ?? '2')!;

  testWidgets('strip debug dump', (tester) async {
    if (pdf == null) {
      markTestSkipped('set STRIP_DEBUG_PDF');
      return;
    }
    await tester.runAsync(() async {
      await loadSystemFonts();
      final doc = PdfDocument.open(File(pdf).readAsBytesSync());
      PdfPageRenderer.deviceMode = PdfRenderDeviceMode.canvas;
      final a =
          await PdfPageRenderer.renderImage(doc.page(page), pixelRatio: ratio);
      PdfPageRenderer.deviceMode = PdfRenderDeviceMode.strips;
      StripPdfDevice.debugDelegateAll =
          Platform.environment['STRIP_DEBUG_DELEGATE_ALL'] == '1';
      StripPdfDevice.debugDelegateFills =
          Platform.environment['STRIP_DEBUG_DELEGATE_FILLS'] == '1';
      StripPdfDevice.debugDelegateStrokes =
          Platform.environment['STRIP_DEBUG_DELEGATE_STROKES'] == '1';
      StripPdfDevice.debugDelegateText =
          Platform.environment['STRIP_DEBUG_DELEGATE_TEXT'] == '1';
      final b =
          await PdfPageRenderer.renderImage(doc.page(page), pixelRatio: ratio);
      PdfPageRenderer.deviceMode = PdfRenderDeviceMode.canvas;

      Future<void> save(ui.Image img, String name) async {
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
      }

      await save(a, 'canvas');
      await save(b, 'strips');

      final pa = (await a.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!
          .buffer
          .asUint8List();
      final pb = (await b.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!
          .buffer
          .asUint8List();
      final w = a.width, h = a.height;
      final diff = Uint8List(w * h * 4);
      var count = 0;
      for (var i = 0; i < w * h; i++) {
        var d = 0;
        for (var c = 0; c < 4; c++) {
          final dc = (pa[i * 4 + c] - pb[i * 4 + c]).abs();
          if (dc > d) d = dc;
        }
        diff[i * 4] = d > 8 ? 255 : 0;
        diff[i * 4 + 1] = d > 2 ? 128 : (pa[i * 4 + 1] ~/ 3 + 170);
        diff[i * 4 + 3] = 255;
        if (d > 8) count++;
      }
      // ignore: avoid_print
      print('DEBUG: ${w}x$h, ${(100 * count / (w * h)).toStringAsFixed(3)}% '
          'differ >8');
      final done = Completer<void>();
      ui.decodeImageFromPixels(diff, w, h, ui.PixelFormat.rgba8888,
          (img) async {
        await save(img, 'diff');
        done.complete();
      });
      await done.future;
    });
  }, timeout: const Timeout(Duration(minutes: 5)));
}
