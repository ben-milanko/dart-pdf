// _AnnotationAppearanceLayer caches rendered appearances by appearance-stream
// identity (#404), so committing one edit no longer re-renders every
// annotation on the page.
//
// The risk caching introduces is lifetime, not reuse: a picture dropped from
// the cache may still be referenced by the list the painter holds, and
// Canvas.drawPicture ASSERTS on a disposed picture. A first cut disposed on
// eviction and broke ~40 existing tests, because a render awaits its missing
// appearances and a frame can paint during that window.
//
// These pump through the transitions that open that window. A
// disposed-picture paint surfaces as an unhandled framework exception, which
// flutter_test fails on by itself, so the pumps carry the real assertion and
// the expects below just pin the document state.
//
// Re-run against the disposing version, the last TWO fail: restyling replaces
// one appearance stream and deleting drops one, so both evict. The first only
// adds annotations, so nothing is ever evicted and it passes either way - it
// is here to cover the plain repeat-commit path, not the lifetime bug.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<PdfEditingController> pumpViewer(WidgetTester tester) async {
    final editing = PdfEditingController(buildMultiPagePdf(1));
    addTearDown(editing.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: editing,
          builder: (context, _) => PdfViewer(
            initialFit: PdfViewerFit.width,
            document: editing.document,
            editing: editing,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return editing;
  }

  testWidgets('repeated commits on an annotated page keep painting',
      (tester) async {
    final editing = await pumpViewer(tester);
    for (var i = 0; i < 6; i++) {
      editing.addRectangle(
          0, PdfRect(100, 600.0 - i * 20, 250, 640.0 - i * 20));
      await tester.pumpAndSettle();
    }
    expect(editing.document.page(0).annotations, hasLength(6));
  });

  testWidgets('restyling one annotation keeps the other on screen',
      (tester) async {
    final editing = await pumpViewer(tester);
    editing.addRectangle(0, const PdfRect(100, 600, 250, 640));
    editing.addRectangle(0, const PdfRect(300, 600, 450, 640));
    await tester.pumpAndSettle();

    // One appearance stream is replaced; the other is untouched and has to
    // survive out of the cache while the replacement renders.
    expect(editing.selectAnnotation(0, 0), isTrue);
    expect(editing.restyleSelected(color: const Color(0xFF00FF00)), isTrue);
    await tester.pumpAndSettle();
    expect(editing.document.page(0).annotations, hasLength(2));
  });

  testWidgets('deleting then undoing retires and revives pictures safely',
      (tester) async {
    final editing = await pumpViewer(tester);
    editing.addRectangle(0, const PdfRect(100, 600, 250, 640));
    editing.addRectangle(0, const PdfRect(300, 600, 450, 640));
    await tester.pumpAndSettle();

    expect(editing.selectAnnotation(0, 0), isTrue);
    editing.deleteSelected();
    await tester.pumpAndSettle();
    expect(editing.document.page(0).annotations, hasLength(1));

    editing.undo();
    await tester.pumpAndSettle();
    expect(editing.document.page(0).annotations, hasLength(2));
  });

  // Regression (#418 follow-up): the appearance cache is keyed on the
  // appearance stream, but a move rewrites only /Rect and leaves that stream
  // identical - so keying on the stream alone returned the stale picture
  // pinned at the old spot, and the annotation appeared not to move until the
  // layer was rebuilt (a tab switch). The /Rect must be part of the key.
  testWidgets('moving an annotation repaints it at the new /Rect',
      (tester) async {
    await tester.runAsync(() async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(300, 460);
      addTearDown(tester.view.reset);

      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      editing.preferences
        ..shapeFillColor = const Color(0xFFFF0000)
        ..opacity = 1.0;
      editing.color = const Color(0xFFFF0000);

      final boundaryKey = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: editing,
              builder: (context, _) => PdfViewer(
                initialFit: PdfViewerFit.width,
                document: editing.document,
                editing: editing,
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // A solid-red box near the top of the page, then the same box slid far
      // down (same appearance stream, new /Rect).
      const oldRect = PdfRect(120, 620, 260, 700);
      const newRect = PdfRect(120, 120, 260, 200);
      editing.addRectangle(0, oldRect);
      await tester.pumpAndSettle();

      final pageRect = tester.getRect(find.byType(PdfPageView).first);
      final geometry = PdfPageGeometry(
        cropBox: editing.document.page(0).cropBox,
        rotation: 0,
        viewSize: pageRect.size,
      );
      Offset centerOf(PdfRect r) =>
          pageRect.topLeft + geometry.toViewRect(r).center;
      final oldCenter = centerOf(oldRect);
      final newCenter = centerOf(newRect);

      // Count red pixels in an 11×11 window around a boundary-local point.
      Future<int> reds(Offset at) async {
        final boundary =
            tester.renderObject<RenderRepaintBoundary>(find.byKey(boundaryKey));
        final image = await boundary.toImage();
        final width = image.width;
        final height = image.height;
        final data =
            (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        image.dispose();
        var count = 0;
        for (var dy = -5; dy <= 5; dy++) {
          for (var dx = -5; dx <= 5; dx++) {
            final x = (at.dx + dx).round();
            final y = (at.dy + dy).round();
            if (x < 0 || x >= width || y < 0 || y >= height) continue;
            final i = (y * width + x) * 4;
            final r = data.getUint8(i);
            final g = data.getUint8(i + 1);
            final b = data.getUint8(i + 2);
            if (r > 150 && g < 100 && b < 100) count++;
          }
        }
        return count;
      }

      // The box paints where it was added and nowhere it wasn't.
      expect(await reds(oldCenter), greaterThan(20),
          reason: 'the added box should paint at its /Rect');
      expect(await reds(newCenter), 0,
          reason: 'nothing painted at the destination yet');

      // Slide it down by 500pt and let the appearance layer re-render.
      editing
        ..tool = PdfEditTool.select
        ..selectAnnotation(0, 0);
      editing.moveSelected(0, newRect.bottom - oldRect.bottom);
      await tester.pumpAndSettle();
      expect(editing.document.page(0).annotations.single.rect, newRect);

      // The picture must follow the box: red at the new spot, gone from the
      // old one. Before the fix the stale cached picture stayed put and the
      // old spot was still red.
      expect(await reds(newCenter), greaterThan(20),
          reason: 'the moved box must repaint at its new /Rect');
      expect(await reds(oldCenter), 0,
          reason: 'the stale picture must not linger at the old /Rect');
    });
  });
}
