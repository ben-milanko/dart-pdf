// The paint-pass text caches must (a) memoize substituted-font layouts so
// repeated (text, font, colour) runs reuse one laid-out painter, and (b) never
// change a pixel — a warm (cache-hot) render is byte-identical to a cold one,
// for both substituted text and embedded-font glyph outlines.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';

Future<Uint8List> _raster(PdfPage page) async {
  final image = await PdfPageRenderer.renderImage(page, pixelRatio: 2);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return Uint8List.fromList(data!.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}

void main() {
  testWidgets('substituted-text layouts cache and repeated runs reuse them',
      (tester) async {
    await tester.runAsync(() async {
      CanvasPdfDevice.clearTextLayoutCache();
      final page = PdfDocument.open(buildClassicPdf()).page(0);

      await _raster(page);
      final afterFirst = CanvasPdfDevice.debugTextLayoutCacheLength;
      expect(afterFirst, greaterThan(0),
          reason: 'standard-font runs should be cached');

      // Re-rendering the same page hits the cache for every run — no new
      // entries appear.
      await _raster(page);
      expect(CanvasPdfDevice.debugTextLayoutCacheLength, afterFirst,
          reason: 'a re-render is all cache hits, no new layouts');
    });
  });

  testWidgets('clearTextLayoutCache empties the cache', (tester) async {
    await tester.runAsync(() async {
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      await _raster(page);
      expect(CanvasPdfDevice.debugTextLayoutCacheLength, greaterThan(0));
      CanvasPdfDevice.clearTextLayoutCache();
      expect(CanvasPdfDevice.debugTextLayoutCacheLength, 0);
    });
  });

  testWidgets('a warm render is byte-identical (substituted text)',
      (tester) async {
    await tester.runAsync(() async {
      CanvasPdfDevice.clearTextLayoutCache();
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final cold = await _raster(page); // populates the layout cache
      final warm = await _raster(page); // serves it from cache
      expect(warm, equals(cold));
    });
  });

  testWidgets('a warm render is byte-identical (embedded glyph outlines)',
      (tester) async {
    await tester.runAsync(() async {
      // Real TrueType outlines exercise the glyph-path cache (keyed by outline
      // identity); the second render reuses the cached em-space ui.Paths.
      final page = PdfDocument.open(buildEmbeddedFontPdf()).page(0);
      final cold = await _raster(page);
      final warm = await _raster(page);
      expect(warm, equals(cold));
    });
  });
}
