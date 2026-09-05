// Editing past the page edge. An annotation's geometry is not confined to
// the crop box, and the editor paints the part that hangs off the paper -
// so a press out there has to reach the page's editing layer instead of
// falling through to the scroll view. The reach is deliberately narrow: it
// takes only presses on the selection itself, leaving the rest of the
// canvas to scrolling. See PdfEditingReach.
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/editing/editing_reach.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('reaching past the page edge', () {
    // The default page fit leaves the 612x792 page narrower than the 800x600
    // test surface, so there is a real margin either side to press in - the
    // grey canvas the reader sees beside the paper.
    Future<PdfEditingController> pumpEditor(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: editing,
            builder: (context, _) => PdfViewer(editing: editing),
          ),
        ),
      ));
      await tester.pump();
      return editing;
    }

    /// The page's on-screen rect. Read off the reach, which wraps the box
    /// sized to the page and - unlike the editing overlay - is mounted even
    /// in reading mode.
    Rect pageRect(WidgetTester tester) =>
        tester.getRect(find.byType(PdfEditingReach));

    /// Global position of a page-space point, on or off the page.
    Offset globalOf(
        WidgetTester tester, PdfEditingController editing, double x, double y) {
      final rect = pageRect(tester);
      final geometry = PdfPageGeometry(
        cropBox: editing.document.page(0).cropBox,
        rotation: 0,
        viewSize: rect.size,
      );
      return rect.topLeft + geometry.toViewOffset(x, y);
    }

    /// Drags in two steps: a recognizer that accepts on a single large move
    /// never delivers a pan update for it.
    Future<void> drag(WidgetTester tester, Offset from, Offset to) async {
      final gesture = await tester.startGesture(from);
      await gesture.moveTo(Offset.lerp(from, to, 0.5)!);
      await gesture.moveTo(to);
      await gesture.up();
      await tester.pump();
    }

    /// Flushes the viewer's debounced settle timers (200/250ms).
    Future<void> settle(WidgetTester tester) =>
        tester.pumpAndSettle(const Duration(milliseconds: 300));

    /// Does this margin position reach the page? The predicate the reach's
    /// hit test consults, read straight off the render object.
    bool grabsAt(WidgetTester tester, Offset global) {
      final render = tester
          .renderObject<PdfRenderEditingReach>(find.byType(PdfEditingReach));
      return render.grabs(render.globalToLocal(global));
    }

    testWidgets('a selected annotation moves when grabbed by its off-page half',
        (tester) async {
      final editing = await pumpEditor(tester);
      // a rectangle running 88pt past the right edge of the 612pt page
      editing.addRectangle(0, const PdfRect(500, 400, 700, 500));
      expect(editing.selectAnnotation(0, 0), isTrue);
      await tester.pump();

      final rect = pageRect(tester);
      final from = globalOf(tester, editing, 660, 450);
      expect(from.dx, greaterThan(rect.right),
          reason: 'the grab point must be off the page to test anything');
      expect(from.dx, lessThan(800), reason: 'and still inside the viewport');

      final before = editing.document.page(0).annotations.single.rect;
      await drag(tester, from, from - const Offset(60, 0));

      // Moved by the *whole* drag. The reach routes the hit test through the
      // page at its nearest inside point, and this is what proves that clamp
      // is routing only: had the overlay read the clamped point instead of
      // the real one, the delta would come out short.
      final after = editing.document.page(0).annotations.single.rect;
      final scale = rect.width / editing.document.page(0).cropBox.width;
      expect(after.left, closeTo(before.left - 60 / scale, 1));
      expect(after.bottom, closeTo(before.bottom, 1));
      expect(editing.document.page(0).annotations, hasLength(1));
      expect(editing.selectedAnnotationSlots, [(0, 0)]);
      await settle(tester);
    });

    testWidgets('the chrome ring off the page is grabbable too',
        (tester) async {
      final editing = await pumpEditor(tester);
      editing.addRectangle(0, const PdfRect(500, 400, 700, 500));
      expect(editing.selectAnnotation(0, 0), isTrue);
      await tester.pump();

      // just past the annotation's off-page corner: where its resize handle
      // is drawn, so the press must still land on the page
      expect(grabsAt(tester, globalOf(tester, editing, 703, 503)), isTrue);
      // well clear of it, still in the same margin: not ours
      expect(grabsAt(tester, globalOf(tester, editing, 780, 700)), isFalse);
      await settle(tester);
    });

    testWidgets('the canvas stays the scroll gesture\'s, tool armed or not',
        (tester) async {
      final editing = await pumpEditor(tester);
      final margin = globalOf(tester, editing, 700, 400);

      // reading mode: nothing selected, nothing to reach for
      expect(grabsAt(tester, margin), isFalse);

      // an armed tool does NOT claim the margin. A phone at PdfViewerFit.page
      // leaves canvas down both sides of a portrait page for a thumb to land
      // on, and taking that away would cost scrolling more than it buys.
      editing.tool = PdfEditTool.ink;
      await tester.pump();
      expect(grabsAt(tester, margin), isFalse);

      // a selection elsewhere on the page doesn't make the whole margin ours
      editing.tool = null;
      editing.addRectangle(0, const PdfRect(100, 100, 200, 200));
      expect(editing.selectAnnotation(0, 0), isTrue);
      await tester.pump();
      expect(grabsAt(tester, margin), isFalse);
      await settle(tester);
    });

    testWidgets('a press in the margin with no selection reaches nothing',
        (tester) async {
      final editing = await pumpEditor(tester);
      editing.tool = PdfEditTool.rectangle;
      await tester.pump();

      final rect = pageRect(tester);
      final from = globalOf(tester, editing, -60, 500);
      expect(from.dx, lessThan(rect.left));

      await drag(tester, from, globalOf(tester, editing, -20, 400));

      // the drag never reached the page, so no annotation was drawn
      expect(editing.document.page(0).annotations, isEmpty);
      await settle(tester);
    });
  });
}
