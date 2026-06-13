import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The "Page N" label a page draws, or '' for a blank page.
String labelOf(PdfDocument doc, int index) {
  final content = String.fromCharCodes(doc.page(index).contentBytes());
  return RegExp(r'\((Page \d+)\)').firstMatch(content)?.group(1) ?? '';
}

List<String> labelsOf(PdfDocument doc) =>
    [for (var i = 0; i < doc.pageCount; i++) labelOf(doc, i)];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('addBlankPage', () {
    test('appends a blank page and bumps the count', () {
      final editing = PdfEditingController(buildMultiPagePdf(2));
      addTearDown(editing.dispose);
      editing.addBlankPage();
      expect(editing.document.pageCount, 3);
      expect(labelOf(editing.document, 2), '');
    });

    test('a blank page with no size given matches its neighbour', () {
      // buildVariedHeightPdf cycles heights 792, 396, 1008 (all 612 wide)
      final editing = PdfEditingController(buildVariedHeightPdf(3));
      addTearDown(editing.dispose);
      // insert after page index 1 (height 396) — the new page copies it
      editing.addBlankPage(at: 2);
      expect(editing.document.pageCount, 4);
      expect(editing.document.page(2).mediaBox, const PdfRect(0, 0, 612, 396));
    });

    test('an explicit size wins over the neighbour default', () {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      editing.addBlankPage(width: 200, height: 300);
      expect(editing.document.page(1).mediaBox, const PdfRect(0, 0, 200, 300));
    });

    test('undo restores the page count', () {
      final editing = PdfEditingController(buildMultiPagePdf(2));
      addTearDown(editing.dispose);
      editing.addBlankPage();
      expect(editing.document.pageCount, 3);
      editing.undo();
      expect(editing.document.pageCount, 2);
    });
  });

  group('insertPagesFrom', () {
    test('insertPagesFromBytes merges another document at a position', () {
      final editing = PdfEditingController(buildMultiPagePdf(2));
      addTearDown(editing.dispose);
      editing.insertPagesFromBytes(buildMultiPagePdf(3), at: 1);
      expect(editing.document.pageCount, 5);
      expect(labelsOf(editing.document),
          ['Page 1', 'Page 1', 'Page 2', 'Page 3', 'Page 2']);
    });

    test('insertPagesFrom can pick a subset', () {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      final source = PdfDocument.open(buildMultiPagePdf(3));
      editing.insertPagesFrom(source, indices: [2]);
      expect(labelsOf(editing.document), ['Page 1', 'Page 3']);
    });
  });

  group('export', () {
    test('exportPages builds a standalone PDF and leaves this one alone', () {
      final editing = PdfEditingController(buildMultiPagePdf(3));
      addTearDown(editing.dispose);
      final out = PdfDocument.open(editing.exportPages([2, 0]));
      expect(labelsOf(out), ['Page 3', 'Page 1']);
      // the source document is unchanged
      expect(editing.document.pageCount, 3);
      expect(editing.isModified, isFalse);
    });

    test('exportPageRange exports a contiguous span', () {
      final editing = PdfEditingController(buildMultiPagePdf(4));
      addTearDown(editing.dispose);
      final out = PdfDocument.open(editing.exportPageRange(1, 2));
      expect(labelsOf(out), ['Page 2', 'Page 3']);
    });
  });

  group('page range dialog', () {
    testWidgets('returns the chosen 0-based inclusive range', (tester) async {
      ({int start, int end})? result;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showPdfPageRangeDialog(context, pageCount: 10);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('pdf-page-range-from')), '3');
      await tester.enterText(
          find.byKey(const ValueKey('pdf-page-range-to')), '7');
      await tester.tap(find.byKey(const ValueKey('pdf-page-range-confirm')));
      await tester.pumpAndSettle();
      expect(result, (start: 2, end: 6));
    });

    testWidgets('a reversed range is rejected and stays open', (tester) async {
      ({int start, int end})? result;
      var returned = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showPdfPageRangeDialog(context, pageCount: 5);
                returned = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('pdf-page-range-from')), '4');
      await tester.enterText(
          find.byKey(const ValueKey('pdf-page-range-to')), '2');
      await tester.tap(find.byKey(const ValueKey('pdf-page-range-confirm')));
      await tester.pumpAndSettle();
      // still open, nothing returned
      expect(returned, isFalse);
      expect(result, isNull);
      expect(find.byKey(const ValueKey('pdf-page-range-dialog')), findsOneWidget);
    });
  });

  group('thumbnail strip', () {
    testWidgets('the Add page footer appends a blank page', (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(2));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Row(children: [
            PdfThumbnailSidebar(controller: editing, viewerController: viewer),
            const Expanded(child: SizedBox()),
          ]),
        ),
      ));
      await tester.pump();

      expect(editing.document.pageCount, 2);
      await tester.tap(find.byKey(const ValueKey('pdf-thumbnail-add-page')));
      await tester.pump();
      expect(editing.document.pageCount, 3);
      await tester.pump(const Duration(seconds: 2)); // drain tile renders
    });

    testWidgets('a read-only strip has no Add page footer', (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(2));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Row(children: [
            PdfThumbnailSidebar(
              controller: editing,
              viewerController: viewer,
              allowPageEditing: false,
            ),
            const Expanded(child: SizedBox()),
          ]),
        ),
      ));
      await tester.pump();
      expect(
          find.byKey(const ValueKey('pdf-thumbnail-add-page')), findsNothing);
      await tester.pump(const Duration(seconds: 2));
    });
  });
}
