// Ctrl/Cmd+wheel zooms around the pointer: the document point under the
// cursor must stay under the cursor.
//
// The subtle half is the fit-width seam. Below it zoom lives in the page
// layout (pages relay out smaller and re-centre); above it in the viewer's
// transform. A wheel notch that crosses the seam moves the content under the
// pointer twice - once by the relayout, once by the transform - so the focal
// point has to be carried across the change, not applied to a scene that has
// already moved. Page spacing does not scale with the layout zoom either, so
// the relayout's scroll compensation has to count the gaps rather than scale
// the whole offset.
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main() {
  Future<PdfViewerController> pumpViewer(WidgetTester tester,
      {PdfViewerFit fit = PdfViewerFit.width}) async {
    final controller = PdfViewerController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          initialFit: fit,
          document: PdfDocument.open(buildMultiPagePdf(6)),
          controller: controller,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return controller;
  }

  /// The page rendered under [at], as (its page object, its screen rect).
  (Object, Rect) pageUnder(WidgetTester tester, Offset at) {
    for (final element in find.byType(PdfPageView).evaluate()) {
      final rect = tester.getRect(find.byElementPredicate((e) => e == element));
      if (rect.contains(at)) {
        return ((element.widget as PdfPageView).page, rect);
      }
    }
    fail('no page under $at');
  }

  Rect rectOf(WidgetTester tester, Object page) => tester.getRect(find
      .byWidgetPredicate((w) => w is PdfPageView && identical(w.page, page)));

  Future<void> ctrlWheel(WidgetTester tester, Offset at, double dy) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    final pointer = TestPointer(301, PointerDeviceKind.mouse);
    pointer.hover(at);
    await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  /// Where the document point that sat at [at] inside [before] has landed.
  Offset moved(Rect before, Rect after, Offset at) => Offset(
        after.left + (at.dx - before.left) / before.width * after.width,
        after.top + (at.dy - before.top) / before.height * after.height,
      );

  // The web reports ctrl+wheel as a PointerScaleEvent, not a scroll: the
  // viewer leaves those to InteractiveViewer (which zooms around the pointer)
  // and folds the result into the page layout when the gesture settles. The
  // fold used to be anchored on the viewport centre, so on web the document
  // slid out from under the pointer however well the wheel path behaved.
  Future<void> scaleSignal(WidgetTester tester, Offset at, double scale) async {
    await tester.sendEventToBinding(PointerScaleEvent(
      position: at,
      kind: PointerDeviceKind.mouse,
      scale: scale,
    ));
    await tester.pump();
    await tester.pumpAndSettle();
  }

  group('web ctrl+wheel (a scale signal) holds the point under the cursor', () {
    testWidgets('crossing up into the transform', (tester) async {
      await pumpViewer(tester, fit: PdfViewerFit.page);
      const at = Offset(300, 200);
      final (page, before) = pageUnder(tester, at);
      await scaleSignal(tester, at, 1.6);
      expect(moved(before, rectOf(tester, page), at).dy, closeTo(at.dy, 1));
    });

    testWidgets('staying below fit-width', (tester) async {
      await pumpViewer(tester, fit: PdfViewerFit.page);
      const at = Offset(300, 200);
      final (page, before) = pageUnder(tester, at);
      await scaleSignal(tester, at, 1.15);
      expect(moved(before, rectOf(tester, page), at).dy, closeTo(at.dy, 1));
    });

    testWidgets('deep in the document', (tester) async {
      final controller = await pumpViewer(tester, fit: PdfViewerFit.page);
      unawaited(controller.jumpToPage(4));
      await tester.pumpAndSettle();
      const at = Offset(400, 450);
      final (page, before) = pageUnder(tester, at);
      await scaleSignal(tester, at, 1.4);
      expect(moved(before, rectOf(tester, page), at).dy, closeTo(at.dy, 1));
    });

    testWidgets('already above fit-width, both axes', (tester) async {
      final controller = await pumpViewer(tester);
      await scaleSignal(tester, const Offset(400, 300), 2.0);
      expect(controller.zoom, greaterThan(1.01));
      const at = Offset(300, 200);
      final (page, before) = pageUnder(tester, at);
      await scaleSignal(tester, at, 1.5);
      expect(moved(before, rectOf(tester, page), at),
          within(distance: 1, from: at));
    });
  });

  group('ctrl+wheel zoom holds the point under the cursor', () {
    testWidgets('zooming in at fit-width', (tester) async {
      final controller = await pumpViewer(tester);
      const at = Offset(250, 180);
      final (page, before) = pageUnder(tester, at);
      await ctrlWheel(tester, at, -120);
      expect(controller.zoom, greaterThan(1.01));
      expect(moved(before, rectOf(tester, page), at),
          within(distance: 1, from: at));
    });

    testWidgets('four notches in a row', (tester) async {
      await pumpViewer(tester);
      const at = Offset(600, 420);
      final (page, before) = pageUnder(tester, at);
      for (var i = 0; i < 4; i++) {
        await ctrlWheel(tester, at, -120);
      }
      expect(moved(before, rectOf(tester, page), at),
          within(distance: 1, from: at));
    });

    testWidgets('zooming back out', (tester) async {
      await pumpViewer(tester);
      const at = Offset(250, 180);
      await ctrlWheel(tester, at, -240);
      final (page, before) = pageUnder(tester, at);
      await ctrlWheel(tester, at, 120);
      expect(moved(before, rectOf(tester, page), at),
          within(distance: 1, from: at));
    });

    // Below fit-width the pages lay out smaller and centred, so a notch here
    // crosses the seam: the relayout moves the content under the pointer
    // before the transform ever sees it.
    testWidgets('crossing the fit-width seam, scroll axis', (tester) async {
      await pumpViewer(tester, fit: PdfViewerFit.page);
      const at = Offset(250, 180);
      final (page, before) = pageUnder(tester, at);
      await ctrlWheel(tester, at, -120);
      expect(moved(before, rectOf(tester, page), at).dy, closeTo(at.dy, 1));
    });

    // ...and deep in the document, where the un-scaled page gaps used to
    // drift the compensating scroll jump by a gap per page.
    testWidgets('crossing the seam deep in the document', (tester) async {
      final controller = await pumpViewer(tester, fit: PdfViewerFit.page);
      unawaited(controller.jumpToPage(4));
      await tester.pumpAndSettle();
      const at = Offset(400, 300);
      final (page, before) = pageUnder(tester, at);
      await ctrlWheel(tester, at, -120);
      expect(moved(before, rectOf(tester, page), at).dy, closeTo(at.dy, 1));
    });

    // Zooming out below the seam is the mirror image: the transform is
    // dropped, so the scroll jump has to pin the content to where the
    // pointer is on screen, not to the list point it maps to while zoomed.
    testWidgets('crossing the seam downwards, scroll axis', (tester) async {
      final controller = await pumpViewer(tester, fit: PdfViewerFit.page);
      unawaited(controller.jumpToPage(3));
      await tester.pumpAndSettle();
      // zoom in past the seam around a point away from the viewport centre,
      // so the zoom window carries a translation the scroll jump must undo
      await ctrlWheel(tester, const Offset(200, 150), -200);
      expect(controller.zoom, greaterThan(1.01));
      const at = Offset(600, 450);
      final (page, before) = pageUnder(tester, at);
      await ctrlWheel(tester, at, 200);
      expect(controller.zoom, lessThan(1));
      expect(moved(before, rectOf(tester, page), at).dy, closeTo(at.dy, 1));
    });
  });
}

Matcher within({required double distance, required Offset from}) =>
    predicate<Offset>(
        (o) => (o - from).distance <= distance, 'within $distance of $from');
