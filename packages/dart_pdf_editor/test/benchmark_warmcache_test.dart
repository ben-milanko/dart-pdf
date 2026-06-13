// Measures the cross-render decoded-image cache (PdfImageCache): each page is
// rendered cold (cache cleared) then warm (cache hot) back-to-back, so the
// warm time reflects what a zoom/scroll-back/thumbnail/re-render pays once the
// page's images are already decoded.
//
//   cd packages/dart_pdf_editor
//   PDF_BENCHMARK_DIR=../../corpus PDF_BENCHMARK_SCALE=2 PDF_BENCHMARK_MAX_PAGES=5 \
//     fvm flutter test test/benchmark_warmcache_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';

import 'render_smoke_test.dart' show loadSystemFonts;

void main() {
  final dir = Platform.environment['PDF_BENCHMARK_DIR'];
  final scale =
      double.tryParse(Platform.environment['PDF_BENCHMARK_SCALE'] ?? '') ?? 2.0;
  final maxPages =
      int.tryParse(Platform.environment['PDF_BENCHMARK_MAX_PAGES'] ?? '') ?? 5;

  testWidgets('cold vs warm render', (tester) async {
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

      Future<int> renderUs(PdfPage page) async {
        final sw = Stopwatch()..start();
        final pic = await PdfPageRenderer.renderPicture(page);
        final img = await PdfPageRenderer.rasterize(
            pic, PdfPageRenderer.pageSize(page), scale);
        await img.toByteData(format: ui.ImageByteFormat.rawRgba);
        final us = sw.elapsedMicroseconds;
        img.dispose();
        pic.dispose();
        return us;
      }

      var pages = 0, imgPages = 0, coldUs = 0, warmUs = 0;
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
            if (!warmed) {
              await renderUs(page);
              warmed = true;
            }
            // cold: clear the shared cache so this render decodes afresh
            PdfImageCache.instance.clear();
            final cold = await renderUs(page);
            // warm: cache now holds this page's images
            final warm = await renderUs(page);
            coldUs += cold;
            warmUs += warm;
            pages++;
            if (PdfImageCache.instance.debugLength > 0) imgPages++;
          } catch (_) {}
        }
      }

      String per(int us) => (us / 1000 / pages).toStringAsFixed(1);
      // ignore: avoid_print
      print('\n=== cold vs warm render ($pages pages, $imgPages with cached '
          'images, scale $scale) ===');
      // ignore: avoid_print
      print('  cold (cache cleared):  ${per(coldUs)} ms/page');
      // ignore: avoid_print
      print('  warm (cache hot):      ${per(warmUs)} ms/page');
      // ignore: avoid_print
      print('  saved:                 ${per(coldUs - warmUs)} ms/page '
          '(${((coldUs - warmUs) / coldUs * 100).toStringAsFixed(0)}%)');
    });
  }, timeout: const Timeout(Duration(minutes: 60)));
}
