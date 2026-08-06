import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Covers the geometry half of "drop a PDF at a position in the thumbnails":
/// the panels answer a global drop point with the slot the pages would land
/// in, and mark that slot while the drag hovers. The host's side of the
/// bargain (reading the bytes and calling `insertPagesFromBytes(at:)`) is
/// the app's - see app/test/drop_insert_test.dart.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  void wideScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  // thumbnails rasterize on a serialized async queue; let it settle so no
  // work outlives the test
  Future<void> drain(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 2));

  Future<PdfThumbnailDropController> pumpStrip(
    WidgetTester tester, {
    int pages = 4,
    bool allowPageEditing = true,
  }) async {
    final editing = PdfEditingController(buildMultiPagePdf(pages));
    final viewer = PdfViewerController();
    final drop = PdfThumbnailDropController();
    addTearDown(editing.dispose);
    addTearDown(viewer.dispose);
    addTearDown(drop.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Row(children: [
          PdfThumbnailSidebar(
            controller: editing,
            viewerController: viewer,
            allowPageEditing: allowPageEditing,
            fileDropController: drop,
          ),
          const Expanded(child: SizedBox.expand()),
        ]),
      ),
    ));
    await tester.pump();
    return drop;
  }

  Future<PdfThumbnailDropController> pumpGrid(
    WidgetTester tester, {
    int pages = 4,
  }) async {
    final editing = PdfEditingController(buildMultiPagePdf(pages));
    final viewer = PdfViewerController();
    final drop = PdfThumbnailDropController();
    addTearDown(editing.dispose);
    addTearDown(viewer.dispose);
    addTearDown(drop.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfThumbnailView(
          controller: editing,
          viewerController: viewer,
          fileDropController: drop,
        ),
      ),
    ));
    await tester.pump();
    return drop;
  }

  /// A point inside tile [index] of the strip, [fraction] of the way down it.
  Offset inTile(WidgetTester tester, Finder tile, double fraction) {
    final rect = tester.getRect(tile);
    return Offset(rect.center.dx, rect.top + rect.height * fraction);
  }

  Finder stripTile(int index) => find.byKey(ValueKey(index));
  Finder gridCell(int index) =>
      find.byKey(ValueKey('pdf-thumbnail-grid-cell-$index'));

  group('PdfThumbnailSidebar file drops', () {
    testWidgets('the top half of a tile drops before it, the bottom after',
        (tester) async {
      wideScreen(tester);
      final drop = await pumpStrip(tester, pages: 4);

      expect(drop.indexAt(inTile(tester, stripTile(1), 0.25)), 1);
      expect(drop.indexAt(inTile(tester, stripTile(1), 0.75)), 2);
      await drain(tester);
    });

    testWidgets('a point off the strip is not a drop target', (tester) async {
      wideScreen(tester);
      final drop = await pumpStrip(tester, pages: 4);

      // the viewer area beside the strip
      expect(drop.indexAt(const Offset(800, 400)), isNull);
      await drain(tester);
    });

    testWidgets('a read-only strip declines external drops', (tester) async {
      wideScreen(tester);
      final drop = await pumpStrip(tester, pages: 4, allowPageEditing: false);

      expect(drop.indexAt(inTile(tester, stripTile(1), 0.25)), isNull);
      await drain(tester);
    });

    testWidgets('a hovering drag marks the slot, and ending it clears',
        (tester) async {
      wideScreen(tester);
      final drop = await pumpStrip(tester, pages: 4);

      expect(drop.dragOver(inTile(tester, stripTile(1), 0.25)), 1);
      await tester.pump();
      expect(find.byKey(const ValueKey('pdf-thumbnail-drop-indicator-1-top')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-thumbnail-drop-outline')),
          findsOneWidget);

      // moving into the lower half of the same tile moves the marker down
      expect(drop.dragOver(inTile(tester, stripTile(1), 0.75)), 2);
      await tester.pump();
      expect(find.byKey(const ValueKey('pdf-thumbnail-drop-indicator-1-top')),
          findsNothing);
      expect(find.byKey(const ValueKey('pdf-thumbnail-drop-indicator-2-top')),
          findsOneWidget);

      drop.endDrag();
      await tester.pump();
      expect(find.byKey(const ValueKey('pdf-thumbnail-drop-indicator-2-top')),
          findsNothing);
      expect(find.byKey(const ValueKey('pdf-thumbnail-drop-outline')),
          findsNothing);
      await drain(tester);
    });

    testWidgets('a drop past the last tile marks its bottom edge',
        (tester) async {
      wideScreen(tester);
      final drop = await pumpStrip(tester, pages: 2);

      expect(drop.dragOver(inTile(tester, stripTile(1), 0.95)), 2);
      await tester.pump();
      expect(
          find.byKey(const ValueKey('pdf-thumbnail-drop-indicator-1-bottom')),
          findsOneWidget);
      await drain(tester);
    });

    testWidgets('a drag over the viewer clears a previous mark',
        (tester) async {
      wideScreen(tester);
      final drop = await pumpStrip(tester, pages: 4);

      drop.dragOver(inTile(tester, stripTile(0), 0.25));
      await tester.pump();
      expect(find.byKey(const ValueKey('pdf-thumbnail-drop-indicator-0-top')),
          findsOneWidget);

      expect(drop.dragOver(const Offset(800, 400)), isNull);
      await tester.pump();
      expect(find.byKey(const ValueKey('pdf-thumbnail-drop-indicator-0-top')),
          findsNothing);
      await drain(tester);
    });
  });

  group('PdfThumbnailView file drops', () {
    testWidgets('the left half of a cell drops before it, the right after',
        (tester) async {
      wideScreen(tester);
      final drop = await pumpGrid(tester, pages: 4);
      final rect = tester.getRect(gridCell(1));

      expect(drop.indexAt(Offset(rect.left + rect.width * 0.2, rect.center.dy)),
          1);
      expect(drop.indexAt(Offset(rect.left + rect.width * 0.8, rect.center.dy)),
          2);
      await drain(tester);
    });

    testWidgets('a hovering drag marks the cell edge', (tester) async {
      wideScreen(tester);
      final drop = await pumpGrid(tester, pages: 4);
      final rect = tester.getRect(gridCell(2));

      drop.dragOver(Offset(rect.left + rect.width * 0.2, rect.center.dy));
      await tester.pump();
      expect(find.byKey(const ValueKey('pdf-thumbnail-drop-indicator-2-left')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-thumbnail-view-drop-outline')),
          findsOneWidget);
      await drain(tester);
    });
  });

  group('PdfThumbnailDropController', () {
    test('a detached panel stops answering and clears its mark', () {
      final drop = PdfThumbnailDropController();
      addTearDown(drop.dispose);
      int? resolver(Offset position) => position.dx > 100 ? 3 : null;
      drop.attachPanel(resolver);

      expect(drop.dragOver(const Offset(200, 0)), 3);
      expect(drop.isOverPanel, isTrue);
      expect(drop.indicatorIndexFor(resolver), 3);

      drop.detachPanel(resolver);
      expect(drop.isOverPanel, isFalse);
      expect(drop.indexAt(const Offset(200, 0)), isNull);
    });

    test('the most recently attached panel answers first', () {
      final drop = PdfThumbnailDropController();
      addTearDown(drop.dispose);
      int? strip(Offset position) => 1;
      int? grid(Offset position) => 7;
      drop
        ..attachPanel(strip)
        ..attachPanel(grid);

      expect(drop.indexAt(Offset.zero), 7);
      drop.detachPanel(grid);
      expect(drop.indexAt(Offset.zero), 1);
    });

    test('notifies only when the marked slot changes', () {
      final drop = PdfThumbnailDropController();
      addTearDown(drop.dispose);
      var notifications = 0;
      drop
        ..addListener(() => notifications++)
        ..attachPanel((position) => position.dx.round());

      drop.dragOver(const Offset(4, 0));
      drop.dragOver(const Offset(4, 9)); // same slot: no repaint
      expect(notifications, 1);
      drop.dragOver(const Offset(5, 0));
      expect(notifications, 2);
      drop.endDrag();
      expect(notifications, 3);
      drop.endDrag(); // already clear
      expect(notifications, 3);
    });
  });
}
