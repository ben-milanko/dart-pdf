// #396 part 2: the render worker extracts a page's text off the UI isolate.
// A real isolate worker's extractText must return the same text and run count a
// local PdfTextExtractor.extract produces, so search/hover behave identically
// whether extraction ran in the worker or on the main isolate.
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main() {
  testWidgets('the isolate worker extracts page text, matching a local extract',
      (tester) async {
    await tester.runAsync(() async {
      final bytes = buildMultiPagePdf(3);
      final worker = PdfRenderWorker.startUncached(bytes);
      addTearDown(worker.dispose);

      final doc = PdfDocument.open(bytes);
      final local = PdfTextExtractor.extract(doc, 1);
      expect(local.text, isNotEmpty);

      final viaWorker =
          await worker.extractText(1).timeout(const Duration(seconds: 30));
      expect(viaWorker, isNotNull,
          reason: 'an active worker must fulfill the extraction');
      expect(viaWorker!.pageIndex, local.pageIndex);
      expect(viaWorker.text, local.text);
      expect(viaWorker.runs.length, local.runs.length);
      // Geometry survived the wire: a search finds the same hits in the same
      // place whether extracted locally or in the worker.
      final matchesLocal = local.findAll('Page');
      final matchesWorker = viaWorker.findAll('Page');
      expect(matchesWorker.length, matchesLocal.length);
    });
  });

  testWidgets('a declined extraction (bad index) returns null', (tester) async {
    await tester.runAsync(() async {
      final worker = PdfRenderWorker.startUncached(buildMultiPagePdf(2));
      addTearDown(worker.dispose);
      expect(
        await worker.extractText(99).timeout(const Duration(seconds: 30)),
        isNull,
      );
    });
  });
}
