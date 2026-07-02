import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main() {
  group('PdfEditingController alignment', () {
    /// Three differently-sized, scattered shapes on page 0.
    ///   slot 0: left 100, bottom 600, 80x40   -> right 180, top 640
    ///   slot 1: left 250, bottom 650, 60x30   -> right 310, top 680
    ///   slot 2: left 400, bottom 500, 40x80   -> right 440, top 580
    PdfEditingController threeShapes() =>
        PdfEditingController(buildMultiPagePdf(2))
          ..addRectangle(0, const PdfRect(100, 600, 180, 640))
          ..addEllipse(0, const PdfRect(250, 650, 310, 680))
          ..addRectangle(0, const PdfRect(400, 500, 440, 580));

    const all = PdfRect(90, 490, 450, 690);

    test('canAlign needs two; canDistribute needs three', () {
      final editing = threeShapes();
      addTearDown(editing.dispose);
      expect(editing.canAlignSelected, isFalse);
      expect(editing.canDistributeSelected, isFalse);

      editing.selectAnnotationAt(0, 140, 620);
      expect(editing.canAlignSelected, isFalse,
          reason: 'one selected is not enough');

      editing.selectAnnotationAt(0, 280, 665, toggle: true);
      expect(editing.canAlignSelected, isTrue);
      expect(editing.canDistributeSelected, isFalse,
          reason: 'two is too few to distribute');

      editing.selectAnnotationAt(0, 420, 540, toggle: true);
      expect(editing.canDistributeSelected, isTrue);
    });

    test('align left puts every selected left edge on the minimum', () {
      final editing = threeShapes();
      addTearDown(editing.dispose);
      editing.selectAnnotationsIn(0, all);
      final revisions = editing.bytes.length;

      editing.alignSelected(PdfAlignment.left);
      final annotations = editing.document.page(0).annotations;
      for (final a in annotations) {
        expect(a.rect.left, closeTo(100, 0.5));
      }
      // sizes are preserved
      expect(annotations[0].rect.width, closeTo(80, 0.5));
      expect(annotations[2].rect.height, closeTo(80, 0.5));
      // the move was saved (one incremental revision appended) and the
      // selection survives
      expect(editing.bytes.length, greaterThan(revisions));
      expect(editing.selectedAnnotationSlots, [(0, 0), (0, 1), (0, 2)]);

      // one undo restores them all
      editing.undo();
      expect(editing.document.page(0).annotations[1].rect.left,
          closeTo(250, 0.5));
    });

    test('align top lines the highest edges up', () {
      final editing = threeShapes();
      addTearDown(editing.dispose);
      editing.selectAnnotationsIn(0, all);
      editing.alignSelected(PdfAlignment.top);
      for (final a in editing.document.page(0).annotations) {
        expect(a.rect.top, closeTo(680, 0.5));
      }
    });

    test('horizontal centre aligns the midpoints', () {
      final editing = threeShapes();
      addTearDown(editing.dispose);
      editing.selectAnnotationsIn(0, all);
      editing.alignSelected(PdfAlignment.horizontalCenter);
      // group spans left 100 .. right 440 -> centre 270
      for (final a in editing.document.page(0).annotations) {
        expect((a.rect.left + a.rect.right) / 2, closeTo(270, 0.5));
      }
    });

    test('distribute horizontally equalises the gaps, holding the ends', () {
      final editing = threeShapes();
      addTearDown(editing.dispose);
      editing.selectAnnotationsIn(0, all);
      editing.alignSelected(PdfAlignment.distributeHorizontal);
      final annotations = editing.document.page(0).annotations
        ..sort((a, b) => a.rect.left.compareTo(b.rect.left));
      // ends stay put
      expect(annotations.first.rect.left, closeTo(100, 0.5));
      expect(annotations.last.rect.right, closeTo(440, 0.5));
      // gaps between consecutive boxes match
      final gap1 = annotations[1].rect.left - annotations[0].rect.right;
      final gap2 = annotations[2].rect.left - annotations[1].rect.right;
      expect(gap1, closeTo(gap2, 0.5));
    });

    test('aligning an already-aligned selection adds no revision', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addRectangle(0, const PdfRect(100, 600, 180, 640))
        ..addRectangle(0, const PdfRect(100, 500, 160, 540));
      addTearDown(editing.dispose);
      editing.selectAnnotationsIn(0, const PdfRect(90, 490, 190, 650));
      final revisions = editing.bytes.length;
      editing.alignSelected(PdfAlignment.left); // already share left 100
      expect(editing.bytes.length, revisions, reason: 'nothing moved');
    });

    test('alignment only touches the primary page', () {
      final editing = PdfEditingController(buildMultiPagePdf(2))
        ..addRectangle(0, const PdfRect(100, 600, 180, 640))
        ..addRectangle(0, const PdfRect(250, 600, 330, 640))
        ..addRectangle(1, const PdfRect(400, 600, 440, 640));
      addTearDown(editing.dispose);
      // select two on page 0 and one on page 1; page 0 is primary (last
      // selected via toggle decides, so select page 1's first then page 0)
      editing.selectAnnotation(1, 0);
      editing.selectAnnotationAt(0, 140, 620, toggle: true);
      editing.selectAnnotationAt(0, 290, 620, toggle: true);
      // primary page is 0
      expect(editing.selectedPage, 0);
      final page1Before = editing.document.page(1).annotations.single.rect;

      editing.alignSelected(PdfAlignment.left);
      for (final a in editing.document.page(0).annotations) {
        expect(a.rect.left, closeTo(100, 0.5));
      }
      // the page-1 annotation is untouched
      expect(editing.document.page(1).annotations.single.rect, page1Before);
    });
  });

  group('alignment toolbar', () {
    Future<PdfEditingController> pumpToolbar(WidgetTester tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addRectangle(0, const PdfRect(100, 600, 180, 640))
        ..addEllipse(0, const PdfRect(250, 650, 310, 680))
        ..addRectangle(0, const PdfRect(400, 500, 440, 580));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: ListenableBuilder(
            listenable: editing,
            builder: (context, _) => PdfEditingToolbar(
                controller: editing, viewerController: viewer),
          ),
        ),
      ));
      return editing;
    }

    testWidgets('align buttons appear only with a multi-selection',
        (tester) async {
      final editing = await pumpToolbar(tester);
      editing.selectAnnotation(0, 0);
      await tester.pump();
      expect(find.byKey(const ValueKey('pdf-align-left')), findsNothing,
          reason: 'a single selection has no alignment');

      editing.selectAnnotationsIn(0, const PdfRect(90, 490, 450, 690));
      await tester.pump();
      expect(find.byKey(const ValueKey('pdf-align-left')), findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-align-distributeHorizontal')),
          findsOneWidget);
    });

    testWidgets('tapping align-right lines up the right edges', (tester) async {
      final editing = await pumpToolbar(tester);
      editing.selectAnnotationsIn(0, const PdfRect(90, 490, 450, 690));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('pdf-align-right')));
      await tester.pump();
      for (final a in editing.document.page(0).annotations) {
        expect(a.rect.right, closeTo(440, 0.5));
      }
    });

    testWidgets('the distribute buttons disable below three selected',
        (tester) async {
      final editing = await pumpToolbar(tester);
      editing.selectAnnotationsIn(0, const PdfRect(90, 590, 320, 690)); // two
      await tester.pump();

      final button = tester.widget<IconButton>(
          find.byKey(const ValueKey('pdf-align-distributeHorizontal')));
      expect(button.onPressed, isNull, reason: 'disabled with two selected');
      // edge alignment is still live
      final left = tester.widget<IconButton>(
          find.byKey(const ValueKey('pdf-align-left')));
      expect(left.onPressed, isNotNull);
    });
  });
}
