// Deep phase-split probe for the full-render path, to see where the per-page
// time goes:
//   - collect : interpreter pass #1 (image discovery; scan-only after PR #52)
//   - decode  : decodeImages (Flutter image codecs)
//   - paint   : interpreter pass #2 into CanvasPdfDevice (build canvas ops)
//   - toImage : rasterize the recorded picture
//   - readback: toByteData(rawRgba)
//
//   cd packages/dart_pdf_editor
//   PDF_BENCHMARK_DIR=../../test_corpora/ghent PDF_BENCHMARK_SCALE=2 \
//   PDF_BENCHMARK_MAX_PAGES=10 \
//     fvm flutter test test/benchmark_phases_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/image_decoder.dart';

import 'render_smoke_test.dart' show loadSystemFonts;

void main() {
  final dir = Platform.environment['PDF_BENCHMARK_DIR'];
  final scale =
      double.tryParse(Platform.environment['PDF_BENCHMARK_SCALE'] ?? '') ?? 2.0;
  final maxPages =
      int.tryParse(Platform.environment['PDF_BENCHMARK_MAX_PAGES'] ?? '') ?? 10;

  testWidgets('render phase breakdown', (tester) async {
    if (dir == null) {
      markTestSkipped('set PDF_BENCHMARK_DIR');
      return;
    }
    await tester.runAsync(() async {
      await loadSystemFonts();
      final files = Directory(dir)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.pdf'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

      var pages = 0;
      var parseUs = 0, collectUs = 0, decodeUs = 0, paintUs = 0, imgUs = 0;
      var rbUs = 0;
      var imgPages = 0;
      var warmed = false;

      for (final file in files) {
        PdfDocument doc;
        try {
          doc = PdfDocument.open(file.readAsBytesSync());
        } catch (_) {
          continue;
        }
        final limit = maxPages <= 0
            ? doc.pageCount
            : (doc.pageCount < maxPages ? doc.pageCount : maxPages);
        for (var i = 0; i < limit; i++) {
          try {
            final page = doc.page(i);
            final cos = page.document.cos;
            final size = PdfPageRenderer.pageSize(page);
            final box = page.cropBox;

            if (!warmed) {
              final w = await PdfPageRenderer.renderPicture(page);
              final wi = await PdfPageRenderer.rasterize(w, size, scale);
              await wi.toByteData(format: ui.ImageByteFormat.rawRgba);
              wi.dispose();
              w.dispose();
              warmed = true;
            }

            final sw = Stopwatch()..start();
            // parse the page content once and share it across both passes —
            // exactly what renderPicture does.
            final pageOps = ContentStreamParser.parse(page.contentBytes());
            parseUs += sw.elapsedMicroseconds;

            sw
              ..reset()
              ..start();
            // collect pass — scan-only image discovery (matches renderPicture)
            final collector = ImageCollector();
            final collecting = PdfInterpreter(
                cos: cos, device: collector, scanImagesOnly: true)
              ..drawPageOperations(page, pageOps);
            collecting.drawAnnotations(page);
            collectUs += sw.elapsedMicroseconds;

            sw
              ..reset()
              ..start();
            final images = await decodeImages(cos, collector.streams);
            decodeUs += sw.elapsedMicroseconds;
            if (collector.streams.isNotEmpty) imgPages++;

            sw
              ..reset()
              ..start();
            final recorder = ui.PictureRecorder();
            final canvas = Canvas(recorder);
            canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
            canvas.translate(0, box.height);
            canvas.scale(1, -1);
            canvas.translate(-box.left, -box.bottom);
            final painting = PdfInterpreter(
                cos: cos, device: CanvasPdfDevice(canvas, images: images))
              ..drawPageOperations(page, pageOps);
            painting.drawAnnotations(page);
            final pic = recorder.endRecording();
            paintUs += sw.elapsedMicroseconds;

            sw
              ..reset()
              ..start();
            final img = await PdfPageRenderer.rasterize(pic, size, scale);
            imgUs += sw.elapsedMicroseconds;

            sw
              ..reset()
              ..start();
            await img.toByteData(format: ui.ImageByteFormat.rawRgba);
            rbUs += sw.elapsedMicroseconds;

            img.dispose();
            pic.dispose();
            for (final im in images.values) {
              im.dispose();
            }
            pages++;
          } catch (_) {}
        }
      }

      String per(int us) => (us / 1000 / pages).toStringAsFixed(1);
      final total = parseUs + collectUs + decodeUs + paintUs + imgUs + rbUs;
      // ignore: avoid_print
      print('\n=== deep render breakdown ($pages pages, $imgPages with images, '
          'scale $scale) ===');
      // ignore: avoid_print
      print('  parse    (shared, once):   ${per(parseUs)} ms/page');
      // ignore: avoid_print
      print('  collect  (scan walk):      ${per(collectUs)} ms/page');
      // ignore: avoid_print
      print('  decode   (image codecs):   ${per(decodeUs)} ms/page');
      // ignore: avoid_print
      print('  paint    (interp pass 2):  ${per(paintUs)} ms/page');
      // ignore: avoid_print
      print('  toImage  (rasterize):      ${per(imgUs)} ms/page');
      // ignore: avoid_print
      print('  readback (toByteData):     ${per(rbUs)} ms/page');
      // ignore: avoid_print
      print('  TOTAL:                     ${per(total)} ms/page');
    });
  }, timeout: const Timeout(Duration(minutes: 60)));
}
