import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/editing/thumbnail_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // let the serialized async render queue flush its microtasks
  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 50));

  group('PdfThumbnailCache scheduler', () {
    test('serves the pending task nearest the focus first', () async {
      final cache = PdfThumbnailCache();
      addTearDown(cache.dispose);
      final order = <int>[];
      cache.focus = 5;
      for (final page in [0, 5, 2]) {
        cache.request(Object(), page, () async => order.add(page));
      }
      await settle();
      // distance from focus 5: page 5 (0) < page 2 (3) < page 0 (5)
      expect(order, [5, 2, 0]);
    });

    test('a cancelled request never runs', () async {
      final cache = PdfThumbnailCache();
      addTearDown(cache.dispose);
      final order = <int>[];
      final token = Object();
      cache.request(token, 0, () async => order.add(0));
      cache.request(Object(), 1, () async => order.add(1));
      // cancel before the microtask drain gets to it
      cache.cancel(token);
      await settle();
      expect(order, [1]);
    });

    test('re-requesting the same token refreshes rather than duplicating',
        () async {
      final cache = PdfThumbnailCache();
      addTearDown(cache.dispose);
      var runs = 0;
      final token = Object();
      cache.request(token, 0, () async => runs++);
      cache.request(token, 9, () async => runs++); // same token, new page
      await settle();
      expect(runs, 1);
    });
  });

  group('background thumbnail warm', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      PdfThumbnailSidebar.debugRasterizations = 0;
    });

    testWidgets('the strip warms off-screen pages into the shared cache',
        (tester) async {
      // a tall document in a short viewport: the lazy strip builds only the
      // first few tiles, so the rest can rasterize only via the warm pass
      final editing = PdfEditingController(buildMultiPagePdf(12));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 240,
            child: Row(children: [
              PdfThumbnailSidebar(
                  controller: editing, viewerController: viewer),
              const Expanded(child: SizedBox()),
            ]),
          ),
        ),
      ));

      // far fewer than 12 tiles fit in 240px, so without the warm pass the
      // raster count would plateau well below the page count
      expect(
        tester
            .widgetList(find.byKey(const ValueKey('pdf-thumbnail-tile-chip-11')))
            .isEmpty,
        isTrue,
        reason: 'page 12 should be off-screen / unbuilt',
      );

      // drive the serialized async render queue (rasterization needs runAsync)
      for (var i = 0;
          i < 300 && PdfThumbnailSidebar.debugRasterizations < 12;
          i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      // every page rendered exactly once, even the off-screen ones
      expect(PdfThumbnailSidebar.debugRasterizations, 12);
    });

    testWidgets('a second surface over the same session reuses the cache',
        (tester) async {
      // the cache lives on the controller, so a second strip at the same tile
      // resolution draws from the rasters the first already rendered — no
      // page is interpreted twice
      final editing = PdfEditingController(buildMultiPagePdf(3));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);

      Future<void> drainTo(int target) async {
        for (var i = 0;
            i < 300 && PdfThumbnailSidebar.debugRasterizations < target;
            i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)));
          await tester.pump();
        }
      }

      PdfThumbnailSidebar strip() =>
          PdfThumbnailSidebar(controller: editing, viewerController: viewer);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Row(children: [strip(), const Expanded(child: SizedBox())]),
        ),
      ));
      await drainTo(3);
      expect(PdfThumbnailSidebar.debugRasterizations, 3);

      // a fresh, identically-configured strip over the same session: its
      // tiles claim from the shared cache instead of re-rendering
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Row(children: [
            strip(),
            strip(),
            const Expanded(child: SizedBox()),
          ]),
        ),
      ));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
      expect(PdfThumbnailSidebar.debugRasterizations, 3);
    });
  });
}
