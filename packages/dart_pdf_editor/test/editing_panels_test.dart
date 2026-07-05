import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    // the mock store is process-global: start every test from defaults
    SharedPreferences.setMockInitialValues({});
    PdfThumbnailSidebar.debugRasterizations = 0;
  });

  group('pageRenderStamp', () {
    test('moves only for the pages an edit touched', () {
      final editing = PdfEditingController(buildMultiPagePdf(3));
      addTearDown(editing.dispose);
      final before = [for (var i = 0; i < 3; i++) editing.pageRenderStamp(i)];

      editing.addRectangle(0, const PdfRect(100, 100, 200, 150));
      expect(editing.pageRenderStamp(0), isNot(before[0]));
      expect(editing.pageRenderStamp(1), before[1]);
      expect(editing.pageRenderStamp(2), before[2]);
    });

    test('annotation edits leave the base page content stamp stable', () {
      final editing = PdfEditingController(buildMultiPagePdf(2));
      addTearDown(editing.dispose);
      final renderBefore = editing.pageRenderStamp(0);
      final contentBefore = editing.pageContentRenderStamp(0);
      final otherContentBefore = editing.pageContentRenderStamp(1);

      editing.placeTextStamp(0, 200, 300, 'APPROVED');

      expect(editing.pageRenderStamp(0), isNot(renderBefore),
          reason: 'thumbnails and annotation overlays still refresh');
      expect(editing.pageContentRenderStamp(0), contentBefore,
          reason: 'deep-zoom page images should not rerender for /Annots');
      expect(editing.pageContentRenderStamp(1), otherContentBefore);
    });

    test('undo and redo bump exactly the reverted revision\'s pages', () {
      final editing = PdfEditingController(buildMultiPagePdf(3))
        ..addRectangle(1, const PdfRect(100, 100, 200, 150));
      addTearDown(editing.dispose);
      final after = [for (var i = 0; i < 3; i++) editing.pageRenderStamp(i)];

      editing.undo();
      expect(editing.pageRenderStamp(0), after[0]);
      expect(editing.pageRenderStamp(1), isNot(after[1]));
      expect(editing.pageRenderStamp(2), after[2]);

      final undone = editing.pageRenderStamp(1);
      editing.redo();
      expect(editing.pageRenderStamp(0), after[0]);
      expect(editing.pageRenderStamp(1), isNot(undone));
      expect(editing.pageRenderStamp(2), after[2]);
    });

    test('structural and unattributed edits bump every page', () {
      final editing = PdfEditingController(buildMultiPagePdf(3));
      addTearDown(editing.dispose);
      final before = [for (var i = 0; i < 3; i++) editing.pageRenderStamp(i)];

      editing.movePage(0, 2);
      final moved = [for (var i = 0; i < 3; i++) editing.pageRenderStamp(i)];
      for (var i = 0; i < 3; i++) {
        expect(moved[i], isNot(before[i]));
      }

      // a host edit through the public apply, with no pages named
      editing.apply((e) => e.rotatePage(0, 90));
      for (var i = 0; i < 3; i++) {
        expect(editing.pageRenderStamp(i), isNot(moved[i]));
      }
    });

    test('pageAt caches within a revision', () {
      final editing = PdfEditingController(buildMultiPagePdf(2));
      addTearDown(editing.dispose);
      expect(identical(editing.pageAt(0), editing.pageAt(0)), isTrue);
      final before = editing.pageAt(0);
      editing.addRectangle(0, const PdfRect(100, 100, 200, 150));
      expect(identical(editing.pageAt(0), before), isFalse);
    });
  });

  group('thumbnail rasters', () {
    Future<void> waitForRasters(WidgetTester tester, int target) async {
      for (var i = 0;
          i < 100 && PdfThumbnailSidebar.debugRasterizations < target;
          i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      expect(PdfThumbnailSidebar.debugRasterizations, target);
    }

    testWidgets('an edit re-renders only the page it touched', (tester) async {
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
      await waitForRasters(tester, 3);

      // an edit on page 0 re-rasterizes that page alone
      editing.addRectangle(0, const PdfRect(100, 100, 200, 150));
      await waitForRasters(tester, 4);
      // give any over-eager renders a chance to land, then re-assert
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
      expect(PdfThumbnailSidebar.debugRasterizations, 4);

      // undoing it re-renders page 0 again — and only page 0
      editing.undo();
      await waitForRasters(tester, 5);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
      expect(PdfThumbnailSidebar.debugRasterizations, 5);
    });

    testWidgets('a new edit session re-renders — stamps restart at zero',
        (tester) async {
      final first = PdfEditingController(buildMultiPagePdf(2));
      final second = PdfEditingController(buildMultiPagePdf(2));
      final viewer = PdfViewerController();
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      addTearDown(viewer.dispose);
      Widget strip(PdfEditingController controller) => MaterialApp(
            home: Scaffold(
              body: Row(children: [
                PdfThumbnailSidebar(
                    controller: controller, viewerController: viewer),
                const Expanded(child: SizedBox()),
              ]),
            ),
          );
      await tester.pumpWidget(strip(first));
      await waitForRasters(tester, 2);

      // same widget, different session: the cached rasters must not be
      // served for the new document (stamp keys collide across sessions)
      await tester.pumpWidget(strip(second));
      await waitForRasters(tester, 4);
    });
  });

  group('viewport indicator contrast', () {
    Future<Color> indicatorColor(WidgetTester tester, ThemeData theme) async {
      final editing = PdfEditingController(buildMultiPagePdf(2));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Row(children: [
            PdfThumbnailSidebar(controller: editing, viewerController: viewer),
            Expanded(
              child: PdfViewer(
                initialFit: PdfViewerFit.width,
                document: editing.document,
                controller: viewer,
                editing: editing,
              ),
            ),
          ]),
        ),
      ));
      await tester.pump();
      final paint = tester
          .widgetList<CustomPaint>(find.byWidgetPredicate((w) =>
              w is CustomPaint &&
              w.painter.runtimeType.toString() == '_ViewportPainter'))
          .first;
      // ignore: avoid_dynamic_calls
      return (paint.painter as dynamic).color as Color;
    }

    double contrast(Color a, Color b) {
      final la = a.computeLuminance();
      final lb = b.computeLuminance();
      final hi = la > lb ? la : lb;
      final lo = la > lb ? lb : la;
      return (hi + 0.05) / (lo + 0.05);
    }

    // the dark-mode AnimatedTheme gotcha: assert the two themes in
    // separate tests, never by re-pumping one tree

    testWidgets('reads on white paper under a dark theme', (tester) async {
      final color = await indicatorColor(tester, ThemeData.dark());
      // a dark theme's primary is light — near-invisible on white paper
      expect(contrast(color, const Color(0xFFFFFFFF)), greaterThan(3));
    });

    testWidgets('stays the primary accent under a light theme', (tester) async {
      final theme = ThemeData.light();
      final color = await indicatorColor(tester, theme);
      expect(color, theme.colorScheme.primary);
    });
  });

  group('resizable sidebars', () {
    testWidgets('the thumbnail grip drags the panel wider and persists',
        (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1));
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

      final before = tester.getSize(find.byType(PdfThumbnailSidebar)).width;
      expect(before, 160);

      final grip = tester
          .getCenter(find.byKey(const ValueKey('pdf-thumbnail-resize-grip')));
      final gesture =
          await tester.startGesture(grip, kind: PointerDeviceKind.mouse);
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      final after = tester.getSize(find.byType(PdfThumbnailSidebar)).width;
      expect(after, greaterThan(before + 40));
      expect(editing.preferences.thumbnailSidebarWidth, after);
    });

    testWidgets('the annotation grip grows leftward, clamps, and persists',
        (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Row(children: [
            const Expanded(child: SizedBox()),
            PdfAnnotationSidebar(controller: editing, viewerController: viewer),
          ]),
        ),
      ));
      await tester.pump();

      expect(tester.getSize(find.byType(PdfAnnotationSidebar)).width, 280);

      // docked right: dragging the grip left makes the panel wider
      final grip = tester
          .getCenter(find.byKey(const ValueKey('pdf-annotation-resize-grip')));
      final gesture =
          await tester.startGesture(grip, kind: PointerDeviceKind.mouse);
      await gesture.moveBy(const Offset(-1000, 0)); // far past the clamp
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(tester.getSize(find.byType(PdfAnnotationSidebar)).width, 480);
      expect(editing.preferences.annotationSidebarWidth, 480);
    });

    testWidgets('a persisted width comes back on the next build',
        (tester) async {
      SharedPreferences.setMockInitialValues(
          {'dart_pdf_editor.editing.thumbnailSidebarWidth': 222.0});
      final editing = PdfEditingController(buildMultiPagePdf(1));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await editing.preferences.ready;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Row(children: [
            PdfThumbnailSidebar(controller: editing, viewerController: viewer),
            const Expanded(child: SizedBox()),
          ]),
        ),
      ));
      await tester.pump();
      expect(tester.getSize(find.byType(PdfThumbnailSidebar)).width, 222);
    });
  });

  group('the strip follows the viewer', () {
    testWidgets('jumping pages scrolls the current tile into view',
        (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(12));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Row(children: [
            PdfThumbnailSidebar(
              controller: editing,
              viewerController: viewer,
              width: 140,
            ),
            Expanded(
              child: PdfViewer(
                initialFit: PdfViewerFit.width,
                document: editing.document,
                controller: viewer,
                editing: editing,
              ),
            ),
          ]),
        ),
      ));
      await tester.pump();

      // page 10's tile starts far below the strip's viewport
      expect(find.text('Page 10').hitTestable(), findsNothing);

      // fire-and-forget: awaiting would deadlock the fake-async pump
      unawaited(viewer.jumpToPage(9));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(viewer.currentPage, 9);
      expect(find.text('Page 10').hitTestable(), findsOneWidget);

      // and back up
      unawaited(viewer.jumpToPage(0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Page 1').hitTestable(), findsOneWidget);
    });
  });

  group('zoom-to flash', () {
    (int, int, int) pixelAt(ByteData pixels, int width, int x, int y) {
      final i = (y * width + x) * 4;
      return (
        pixels.getUint8(i),
        pixels.getUint8(i + 1),
        pixels.getUint8(i + 2),
      );
    }

    /// Whether the captured frame holds the flash's amber anywhere —
    /// the 0.9-alpha stroke stays close to (255, 179, 0) over any paper.
    bool hasAmber(ByteData pixels, int width, int height) {
      for (var y = 0; y < height; y += 2) {
        for (var x = 0; x < width; x += 2) {
          final (r, g, b) = pixelAt(pixels, width, x, y);
          if (r > 230 && g > 150 && g < 220 && b < 90) return true;
        }
      }
      return false;
    }

    Future<ByteData> capture(WidgetTester tester, Key key) async {
      final boundary =
          tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
      final ui.Image image = (await tester.runAsync(() => boundary.toImage()))!;
      final pixels = (await tester.runAsync(() => image.toByteData()))!;
      addTearDown(image.dispose);
      return pixels;
    }

    testWidgets('a sidebar tap pulses the annotation, then it expires',
        (tester) async {
      const boundaryKey = ValueKey('flash-capture');
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addRectangle(0, const PdfRect(250, 350, 400, 450));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Row(children: [
            Expanded(
              child: RepaintBoundary(
                key: boundaryKey,
                child: ListenableBuilder(
                  listenable: editing,
                  builder: (context, _) => PdfViewer(
                    initialFit: PdfViewerFit.width,
                    document: editing.document,
                    controller: viewer,
                    editing: editing,
                  ),
                ),
              ),
            ),
            PdfAnnotationSidebar(controller: editing, viewerController: viewer),
          ]),
        ),
      ));
      await tester.pump();

      await tester.tap(find.text('Square'));
      await tester.pump();
      expect(editing.pendingFlash,
          (page: 0, slot: 0, sequence: editing.pendingFlash!.sequence));
      expect(editing.selectedAnnotationSlot, (0, 0));

      // mid-pulse: the amber ring is on screen
      await tester.pump(const Duration(milliseconds: 120));
      final boundary =
          tester.renderObject<RenderRepaintBoundary>(find.byKey(boundaryKey));
      final size = boundary.size;
      var pixels = await capture(tester, boundaryKey);
      expect(hasAmber(pixels, size.width.round(), size.height.round()), isTrue,
          reason: 'the flash ring should be painted mid-pulse');

      // the animation ends, then the pending flash expires on its timer
      await tester.pump(const Duration(milliseconds: 1200));
      pixels = await capture(tester, boundaryKey);
      expect(hasAmber(pixels, size.width.round(), size.height.round()), isFalse,
          reason: 'the flash should be gone once the pulse ends');
      await tester.pump(const Duration(milliseconds: 600));
      expect(editing.pendingFlash, isNull);
    });

    testWidgets('a second tap on the same tile pulses again', (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addRectangle(0, const PdfRect(250, 350, 400, 450));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Row(children: [
            Expanded(
              child: ListenableBuilder(
                listenable: editing,
                builder: (context, _) => PdfViewer(
                  initialFit: PdfViewerFit.width,
                  document: editing.document,
                  controller: viewer,
                  editing: editing,
                ),
              ),
            ),
            PdfAnnotationSidebar(controller: editing, viewerController: viewer),
          ]),
        ),
      ));
      await tester.pump();

      await tester.tap(find.text('Square'));
      await tester.pump();
      final first = editing.pendingFlash!.sequence;
      await tester.pump(const Duration(seconds: 2)); // pulse + expiry

      expect(editing.pendingFlash, isNull);
      await tester.tap(find.text('Square'));
      await tester.pump();
      expect(editing.pendingFlash!.sequence, isNot(first));
      await tester.pump(const Duration(seconds: 2));
    });

    test('an edit invalidates the pending flash', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addRectangle(0, const PdfRect(250, 350, 400, 450));
      addTearDown(editing.dispose);
      editing.flashAnnotation(0, 0);
      expect(editing.pendingFlash, isNotNull);
      editing.addNote(0, 100, 700, 'note'); // new revision, slots may shift
      expect(editing.pendingFlash, isNull);
    });
  });

  group('scrollbar clearance', () {
    testWidgets('the lists keep clear of the overlay scrollbar zone',
        (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(2))
        ..addNote(0, 100, 700, 'note');
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Row(children: [
            PdfThumbnailSidebar(controller: editing, viewerController: viewer),
            const Expanded(child: SizedBox()),
            PdfAnnotationSidebar(controller: editing, viewerController: viewer),
          ]),
        ),
      ));
      await tester.pump();

      // left-docked strip: 14px bar stepped off the 8px grip, tiles
      // already pad 12 — the list adds the missing 10
      final strip =
          tester.widget<ReorderableListView>(find.byType(ReorderableListView));
      expect(strip.padding, const EdgeInsets.fromLTRB(0, 8, 10, 8));

      // right-docked annotation list: the grip rides the far edge, so
      // just the bar's 14px
      final list = tester.widget<ListView>(find.byType(ListView));
      expect(list.padding, const EdgeInsets.only(right: 14));
      await tester.pump(const Duration(seconds: 2)); // drain tile renders
    });

    testWidgets('a left-docked annotation list also steps off the grip',
        (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addNote(0, 100, 700, 'note');
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Row(children: [
            PdfAnnotationSidebar(
              controller: editing,
              viewerController: viewer,
              side: PdfSidebarSide.left,
            ),
            const Expanded(child: SizedBox()),
          ]),
        ),
      ));
      await tester.pump();

      final list = tester.widget<ListView>(find.byType(ListView));
      expect(list.padding, const EdgeInsets.only(right: 22));
    });
  });
}
