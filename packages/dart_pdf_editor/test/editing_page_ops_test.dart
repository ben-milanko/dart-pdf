import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  group('page selection', () {
    test('selectPage selects one page and sets the anchor', () {
      final editing = PdfEditingController(buildMultiPagePdf(5));
      addTearDown(editing.dispose);
      editing.selectPage(2);
      expect(editing.selectedPages, [2]);
      expect(editing.isPageSelected(2), isTrue);
      expect(editing.hasPageSelection, isTrue);
      expect(editing.selectedPageCount, 1);
    });

    test('selectPageRange extends a contiguous range from the anchor', () {
      final editing = PdfEditingController(buildMultiPagePdf(5));
      addTearDown(editing.dispose);
      editing.selectPage(1);
      editing.selectPageRange(3);
      expect(editing.selectedPages, [1, 2, 3]);
    });

    test('selectPageRange works backwards from the anchor', () {
      final editing = PdfEditingController(buildMultiPagePdf(5));
      addTearDown(editing.dispose);
      editing.selectPage(3);
      editing.selectPageRange(1);
      expect(editing.selectedPages, [1, 2, 3]);
    });

    test('a second shift-range re-extends from the same anchor', () {
      final editing = PdfEditingController(buildMultiPagePdf(6));
      addTearDown(editing.dispose);
      editing.selectPage(2);
      editing.selectPageRange(4);
      expect(editing.selectedPages, [2, 3, 4]);
      // anchor stays at 2 — extend the other way, replacing the range
      editing.selectPageRange(0);
      expect(editing.selectedPages, [0, 1, 2]);
    });

    test('togglePageSelection adds then removes individual pages', () {
      final editing = PdfEditingController(buildMultiPagePdf(5));
      addTearDown(editing.dispose);
      editing.selectPage(0);
      editing.togglePageSelection(2);
      editing.togglePageSelection(4);
      expect(editing.selectedPages, [0, 2, 4]);
      editing.togglePageSelection(2);
      expect(editing.selectedPages, [0, 4]);
    });

    test('selectAllPages then clearPageSelection', () {
      final editing = PdfEditingController(buildMultiPagePdf(3));
      addTearDown(editing.dispose);
      editing.selectAllPages();
      expect(editing.selectedPages, [0, 1, 2]);
      editing.clearPageSelection();
      expect(editing.hasPageSelection, isFalse);
    });

    test('removeSelectedPages deletes the selection in one undo', () {
      final editing = PdfEditingController(buildMultiPagePdf(4));
      addTearDown(editing.dispose);
      editing.selectPage(0);
      editing.selectPageRange(1); // Page 1 and Page 2
      expect(editing.removeSelectedPages(), isTrue);
      expect(labelsOf(editing.document), ['Page 3', 'Page 4']);
      expect(editing.hasPageSelection, isFalse);
      editing.undo();
      expect(labelsOf(editing.document),
          ['Page 1', 'Page 2', 'Page 3', 'Page 4']);
    });

    test('removeSelectedPages refuses to empty the document', () {
      final editing = PdfEditingController(buildMultiPagePdf(3));
      addTearDown(editing.dispose);
      editing.selectAllPages();
      expect(editing.removeSelectedPages(), isFalse);
      expect(editing.document.pageCount, 3);
    });

    test('a structural page edit clears the selection', () {
      final editing = PdfEditingController(buildMultiPagePdf(4));
      addTearDown(editing.dispose);
      editing.selectPage(1);
      editing.selectPageRange(3);
      editing.addBlankPage();
      expect(editing.hasPageSelection, isFalse);
    });

    test('exportSelectedPages builds a standalone PDF in page order', () {
      final editing = PdfEditingController(buildMultiPagePdf(4));
      addTearDown(editing.dispose);
      editing.selectPage(3);
      editing.togglePageSelection(1);
      final bytes = editing.exportSelectedPages();
      expect(bytes, isNotNull);
      expect(labelsOf(PdfDocument.open(bytes!)), ['Page 2', 'Page 4']);
      expect(editing.isModified, isFalse);
    });

    test('exportSelectedPages is null with nothing selected', () {
      final editing = PdfEditingController(buildMultiPagePdf(2));
      addTearDown(editing.dispose);
      expect(editing.exportSelectedPages(), isNull);
    });

    test('rotateSelectedPages turns the selection and keeps it', () {
      final editing = PdfEditingController(buildMultiPagePdf(4));
      addTearDown(editing.dispose);
      editing.selectPage(0);
      editing.togglePageSelection(2);
      expect(editing.rotateSelectedPages(90), isTrue);
      expect(editing.document.page(0).rotation, 90);
      expect(editing.document.page(1).rotation, 0);
      expect(editing.document.page(2).rotation, 90);
      // a visual rotation does not shift indices, so the selection survives
      expect(editing.selectedPages, [0, 2]);
      editing.undo();
      expect(editing.document.page(0).rotation, 0);
    });

    test('rotateSelectedPages counterclockwise normalizes', () {
      final editing = PdfEditingController(buildMultiPagePdf(2));
      addTearDown(editing.dispose);
      editing.selectPage(1);
      expect(editing.rotateSelectedPages(-90), isTrue);
      expect(editing.document.page(1).rotation, 270);
    });

    test('rotateSelectedPages is a no-op with nothing selected', () {
      final editing = PdfEditingController(buildMultiPagePdf(2));
      addTearDown(editing.dispose);
      expect(editing.rotateSelectedPages(), isFalse);
      expect(editing.isModified, isFalse);
    });

    test('rotatePages targets explicit indices', () {
      final editing = PdfEditingController(buildMultiPagePdf(3));
      addTearDown(editing.dispose);
      expect(editing.rotatePages([1], 180), isTrue);
      expect(editing.document.page(1).rotation, 180);
      expect(editing.rotatePages([], 90), isFalse);
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

    testWidgets('shift-click selects a range, then deletes it', (tester) async {
      // a tall surface so every tile builds (the list is lazy)
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final editing = PdfEditingController(buildMultiPagePdf(5));
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

      // a plain tap selects one page (and anchors there)
      await tester.tap(find.text('Page 2'));
      await tester.pump();
      expect(editing.selectedPages, [1]);

      // shift-click extends the range from the anchor
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.tap(find.text('Page 4'));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pump();
      expect(editing.selectedPages, [1, 2, 3]);

      // the selection bar appears; its delete removes the whole selection
      expect(find.byKey(const ValueKey('pdf-thumbnail-delete-selected')),
          findsOneWidget);
      await tester.tap(
          find.byKey(const ValueKey('pdf-thumbnail-delete-selected')));
      await tester.pump();
      expect(labelsOf(editing.document), ['Page 1', 'Page 5']);
      expect(editing.hasPageSelection, isFalse);
      await tester.pump(const Duration(seconds: 2)); // drain tile renders
    });

    testWidgets('ctrl-click toggles pages into the selection', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final editing = PdfEditingController(buildMultiPagePdf(4));
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

      await tester.tap(find.text('Page 1'));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tap(find.text('Page 3'));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(editing.selectedPages, [0, 2]);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('the selection bar rotates, exports, and clears',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final editing = PdfEditingController(buildMultiPagePdf(4));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      Uint8List? exported;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Row(children: [
            PdfThumbnailSidebar(
              controller: editing,
              viewerController: viewer,
              onExportPages: (bytes) => exported = bytes,
            ),
            const Expanded(child: SizedBox()),
          ]),
        ),
      ));
      await tester.pump();

      await tester.tap(find.text('Page 1'));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.tap(find.text('Page 3'));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pump();
      expect(editing.selectedPages, [0, 1, 2]);

      // rotate right, then left: the two cancel back to no rotation
      await tester.tap(
          find.byKey(const ValueKey('pdf-thumbnail-rotate-selected-cw')));
      await tester.pump();
      expect(editing.document.page(0).rotation, 90);
      expect(editing.document.page(1).rotation, 90);
      expect(editing.document.page(2).rotation, 90);
      expect(editing.document.page(3).rotation, 0);
      // the selection survives a visual rotation
      expect(editing.selectedPages, [0, 1, 2]);

      await tester.tap(
          find.byKey(const ValueKey('pdf-thumbnail-rotate-selected-ccw')));
      await tester.pump();
      expect(editing.document.page(0).rotation, 0);
      expect(editing.selectedPages, [0, 1, 2]);

      // export hands the host the selected pages
      await tester
          .tap(find.byKey(const ValueKey('pdf-thumbnail-export-selected')));
      await tester.pump();
      expect(exported, isNotNull);
      expect(labelsOf(PdfDocument.open(exported!)),
          ['Page 1', 'Page 2', 'Page 3']);

      // clear empties the selection (and dismisses the bar)
      await tester
          .tap(find.byKey(const ValueKey('pdf-thumbnail-clear-selection')));
      await tester.pump();
      expect(editing.hasPageSelection, isFalse);
      await tester.pump(const Duration(seconds: 2)); // drain tile renders
    });

    testWidgets('a per-tile rotate button turns one page', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final editing = PdfEditingController(buildMultiPagePdf(3));
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

      await tester.tap(find.byKey(const ValueKey('pdf-thumbnail-rotate-1')));
      await tester.pump();
      expect(editing.document.page(0).rotation, 0);
      expect(editing.document.page(1).rotation, 90);
      await tester.pump(const Duration(seconds: 2));
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
