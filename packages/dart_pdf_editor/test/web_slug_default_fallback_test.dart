import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main() {
  testWidgets('browser default keeps embedded-font pages on the raster path',
      (tester) async {
    PdfPageView.debugWebSlugGlyphLayerBackendOverride = true;
    addTearDown(() {
      PdfPageView.debugWebSlugGlyphLayerBackendOverride = null;
    });
    final page = PdfDocument.open(buildEmbeddedFontPdf()).page(0);
    Widget at(double scale) => Center(
          child: SizedBox(
              width: 612, child: PdfPageView(page: page, scale: scale)),
        );
    for (final scale in [1.0, 2.0]) {
      await tester.pumpWidget(at(scale));
      for (var i = 0; i < 200; i++) {
        await tester.pump();
        final error = tester.takeException();
        if (error != null) fail('page rendering failed: $error');
        if (find.byType(RawImage).evaluate().isNotEmpty) break;
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
      }
      expect(find.byType(RawImage), findsWidgets);
      expect(find.byKey(const ValueKey('pdf-page-slug-picture')), findsNothing);
    }
  });
}
