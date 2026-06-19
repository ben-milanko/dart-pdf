import 'package:flutter/gestures.dart' show kLongPressTimeout;
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

  // a roomy surface so every grid cell lays out and is hit-testable (the
  // grid builds every child eagerly, but they still need to fit to tap)
  void wideScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<({PdfEditingController editing, PdfViewerController viewer})> pumpGrid(
    WidgetTester tester, {
    int pages = 4,
    bool allowPageEditing = true,
    void Function(Uint8List bytes)? onExportPages,
    void Function(int pageIndex)? onOpenPage,
    PdfEditingController? controller,
  }) async {
    final editing =
        controller ?? PdfEditingController(buildMultiPagePdf(pages));
    final viewer = PdfViewerController();
    if (controller == null) addTearDown(editing.dispose);
    addTearDown(viewer.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfThumbnailView(
          controller: editing,
          viewerController: viewer,
          allowPageEditing: allowPageEditing,
          onExportPages: onExportPages,
          onOpenPage: onOpenPage,
        ),
      ),
    ));
    await tester.pump();
    return (editing: editing, viewer: viewer);
  }

  // thumbnails rasterize on a serialized async queue; let it settle so no
  // work outlives the test
  Future<void> drain(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 2));

  group('PdfThumbnailView', () {
    testWidgets('lays out one cell per page', (tester) async {
      wideScreen(tester);
      await pumpGrid(tester, pages: 5);
      for (var i = 0; i < 5; i++) {
        expect(
            find.byKey(ValueKey('pdf-thumbnail-grid-cell-$i')), findsOneWidget);
      }
      await drain(tester);
    });

    testWidgets('the Add page footer appends a blank page', (tester) async {
      wideScreen(tester);
      final refs = await pumpGrid(tester, pages: 2);
      expect(refs.editing.document.pageCount, 2);
      await tester
          .tap(find.byKey(const ValueKey('pdf-thumbnail-view-add-page')));
      await tester.pump();
      expect(refs.editing.document.pageCount, 3);
      expect(labelOf(refs.editing.document, 2), '');
      await drain(tester);
    });

    testWidgets('a plain tap opens the page: selects, jumps, and notifies',
        (tester) async {
      wideScreen(tester);
      int? opened;
      final refs = await pumpGrid(
        tester,
        pages: 4,
        onOpenPage: (i) => opened = i,
      );
      await tester.tap(find.text('Page 3'));
      await tester.pump();
      expect(refs.editing.selectedPages, [2]);
      expect(opened, 2);
      await drain(tester);
    });

    testWidgets('the size slider changes the tile-width preference',
        (tester) async {
      wideScreen(tester);
      final refs = await pumpGrid(tester, pages: 3);
      final prefs = refs.editing.preferences;
      expect(prefs.thumbnailViewTileWidth, isNull);

      // drag the slider toward "larger"
      await tester.drag(find.byKey(const ValueKey('pdf-thumbnail-view-size')),
          const Offset(40, 0));
      await tester.pump();

      final width = prefs.thumbnailViewTileWidth;
      expect(width, isNotNull);
      expect(width, greaterThan(96));
      expect(width, lessThanOrEqualTo(360));
      await drain(tester);
    });

    testWidgets('the tile width follows the preference', (tester) async {
      wideScreen(tester);
      final refs = await pumpGrid(tester, pages: 3);
      refs.editing.preferences.thumbnailViewTileWidth = 300;
      await tester.pump();
      final size = tester
          .getSize(find.byKey(const ValueKey('pdf-thumbnail-grid-cell-0')));
      expect(size.width, moreOrLessEquals(300, epsilon: 0.5));
      await drain(tester);
    });

    testWidgets('shift-click builds a selection the bar deletes',
        (tester) async {
      wideScreen(tester);
      final refs = await pumpGrid(tester, pages: 5);

      await tester.tap(find.text('Page 2'));
      await tester.pump();
      expect(refs.editing.selectedPages, [1]);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.tap(find.text('Page 4'));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pump();
      expect(refs.editing.selectedPages, [1, 2, 3]);

      expect(find.byKey(const ValueKey('pdf-thumbnail-delete-selected')),
          findsOneWidget);
      await tester
          .tap(find.byKey(const ValueKey('pdf-thumbnail-delete-selected')));
      await tester.pump();
      expect(labelsOf(refs.editing.document), ['Page 1', 'Page 5']);
      expect(refs.editing.hasPageSelection, isFalse);
      await drain(tester);
    });

    testWidgets('a per-tile rotate button turns one page', (tester) async {
      wideScreen(tester);
      final refs = await pumpGrid(tester, pages: 3);
      await tester.tap(find.byKey(const ValueKey('pdf-thumbnail-rotate-1')));
      await tester.pump();
      expect(refs.editing.document.page(0).rotation, 0);
      expect(refs.editing.document.page(1).rotation, 90);
      await drain(tester);
    });

    testWidgets('a long-press drag reorders pages', (tester) async {
      wideScreen(tester);
      final refs = await pumpGrid(tester, pages: 4);
      expect(labelsOf(refs.editing.document),
          ['Page 1', 'Page 2', 'Page 3', 'Page 4']);

      // touch is the default test pointer, so the cell waits for a long
      // press before dragging — pick up page 1, drop it on page 3's cell
      final from = tester
          .getCenter(find.byKey(const ValueKey('pdf-thumbnail-grid-cell-0')));
      final to = tester
          .getCenter(find.byKey(const ValueKey('pdf-thumbnail-grid-cell-2')));
      final gesture = await tester.startGesture(from);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      await gesture.moveTo(to);
      await tester.pump();
      await gesture.up();
      await tester.pump();

      // movePage(0, 2): page 1 lands at index 2
      expect(labelsOf(refs.editing.document),
          ['Page 2', 'Page 3', 'Page 1', 'Page 4']);
      await drain(tester);
    });

    testWidgets('the selection bar exports the selection', (tester) async {
      wideScreen(tester);
      Uint8List? exported;
      final refs = await pumpGrid(
        tester,
        pages: 4,
        onExportPages: (bytes) => exported = bytes,
      );
      await tester.tap(find.text('Page 1'));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.tap(find.text('Page 2'));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pump();
      expect(refs.editing.selectedPages, [0, 1]);

      await tester
          .tap(find.byKey(const ValueKey('pdf-thumbnail-export-selected')));
      await tester.pump();
      expect(exported, isNotNull);
      expect(labelsOf(PdfDocument.open(exported!)), ['Page 1', 'Page 2']);
      await drain(tester);
    });

    testWidgets('a read-only grid drops the editing controls', (tester) async {
      wideScreen(tester);
      await pumpGrid(tester, pages: 3, allowPageEditing: false);
      // no footer, no per-tile rotate/delete, and no draggable cells
      expect(find.byKey(const ValueKey('pdf-thumbnail-view-add-page')),
          findsNothing);
      expect(
          find.byKey(const ValueKey('pdf-thumbnail-rotate-0')), findsNothing);
      expect(find.byType(LongPressDraggable<int>), findsNothing);
      expect(find.byType(Draggable<int>), findsNothing);
      await drain(tester);
    });
  });
}
