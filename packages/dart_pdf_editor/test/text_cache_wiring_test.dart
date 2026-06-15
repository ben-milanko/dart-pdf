// The persistent text cache wired into the viewer: a static document's
// search extraction is written through to (and, on a cold reopen, read
// from) the on-disk PdfPageTextCache — but an active edit session never
// serves text from the content-keyed persistent cache.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';

import 'search_navigation_test.dart' show buildLongLinePdf;

void main() {
  Widget host(PdfViewerController controller, PdfDocument document,
      {PdfPageTextCache? textCache,
      String? documentId,
      PdfEditingController? editing}) {
    return MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          document: document,
          controller: controller,
          editing: editing,
          textCache: textCache,
          documentId: documentId,
          initialFit: PdfViewerFit.width,
        ),
      ),
    );
  }

  testWidgets('search writes extracted text through to the persistent cache',
      (tester) async {
    final store = PdfMemoryCacheStore();
    final textCache = PdfPageTextCache(PdfDiskCache(store));
    final bytes = buildLongLinePdf();
    final document = PdfDocument.open(bytes);
    final controller = PdfViewerController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
        host(controller, document, textCache: textCache, documentId: 'doc'));
    await tester.pump();

    await tester.runAsync(() async {
      await controller.search('sentinel');

      // the page's extracted text landed in the store...
      final cached = await textCache.cache.read('doc/0');
      expect(cached, isNotNull);
      final decoded = pdfDecodePageText(cached!);
      expect(decoded, isNotNull);
      expect(decoded!.text, contains('sentinel'));

      // ...and a fresh session serves it without recomputing
      var recomputed = false;
      final reopened = await textCache.get('doc', 0, () async {
        recomputed = true;
        return const PdfPageText(pageIndex: 0, text: '', runs: []);
      });
      expect(recomputed, isFalse);
      expect(reopened.text, contains('sentinel'));
    });
    expect(controller.searchResults, isNotEmpty);
  });

  testWidgets('an edit session never serves text from the persistent cache',
      (tester) async {
    final store = PdfMemoryCacheStore();
    final textCache = PdfPageTextCache(PdfDiskCache(store));
    final bytes = buildLongLinePdf();
    final editing = PdfEditingController(bytes);
    addTearDown(editing.dispose);
    final controller = PdfViewerController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(host(controller, editing.document,
        textCache: textCache, documentId: 'doc', editing: editing));
    await tester.pump();

    await tester.runAsync(() async {
      await controller.search('sentinel');
      // the content-keyed store stays empty — an edit session's text is
      // in-memory only (it would otherwise go stale after a content edit)
      expect(store.debugBytes, 0);
    });
    expect(controller.searchResults, isNotEmpty);
  });
}
