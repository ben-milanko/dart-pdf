// The interactive image-crop UI: the on-page crop rectangle
// (PdfImageCropOverlay) and its wiring into the viewer and controller.
import 'dart:convert';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/editing/editing_image_crop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _png = base64.decode('iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0k'
    'AAAAGUlEQVR4nGP4z8DwHwgbWBgZ/jNyicr7AgA3BAUOTnqjAAAAAABJRU5ErkJggg==');

String appearance(PdfDocument doc, PdfAnnotation annot) =>
    latin1.decode(doc.cos.decodeStreamData(annot.normalAppearance!));

void main() {
  group('PdfImageCropOverlay widget', () {
    testWidgets('dragging the top-right handle shrinks the crop', (tester) async {
      const bounds = Rect.fromLTWH(0, 0, 200, 200);
      Rect? changed;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Stack(children: [
            PdfImageCropOverlay(
              bounds: bounds,
              initialCrop: bounds,
              chromeScale: 1,
              accentColor: const Color(0xFF1E88E5),
              onChanged: (r) => changed = r,
              onCommit: () {},
              onCancel: () {},
            ),
          ]),
        ),
      ));

      // top-right handle sits at (200, 0); drag it in by (-60, +60)
      await tester.dragFrom(const Offset(200, 0), const Offset(-60, 60));
      await tester.pump();

      expect(changed, isNotNull);
      expect(changed!.right, closeTo(140, 0.5));
      expect(changed!.top, closeTo(60, 0.5));
      // the left/bottom edges are untouched by a top-right drag
      expect(changed!.left, closeTo(0, 0.5));
      expect(changed!.bottom, closeTo(200, 0.5));
    });

    testWidgets('dragging the interior moves the crop, clamped to bounds',
        (tester) async {
      const bounds = Rect.fromLTWH(0, 0, 200, 200);
      // start from a smaller centered crop so there is room to move
      const start = Rect.fromLTWH(50, 50, 100, 100);
      Rect? changed;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Stack(children: [
            PdfImageCropOverlay(
              bounds: bounds,
              initialCrop: start,
              chromeScale: 1,
              accentColor: const Color(0xFF1E88E5),
              onChanged: (r) => changed = r,
              onCommit: () {},
              onCancel: () {},
            ),
          ]),
        ),
      ));

      // grab the interior (center) and drag up-left far enough to clamp
      await tester.dragFrom(const Offset(100, 100), const Offset(-200, -200));
      await tester.pump();
      expect(changed, isNotNull);
      // clamped into the bounds, size preserved
      expect(changed!.left, closeTo(0, 0.5));
      expect(changed!.top, closeTo(0, 0.5));
      expect(changed!.width, closeTo(100, 0.5));
      expect(changed!.height, closeTo(100, 0.5));
    });

    testWidgets('the confirm and cancel chips fire their callbacks',
        (tester) async {
      var committed = false, cancelled = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Stack(children: [
            PdfImageCropOverlay(
              bounds: const Rect.fromLTWH(20, 20, 200, 200),
              initialCrop: const Rect.fromLTWH(20, 20, 200, 200),
              chromeScale: 1,
              accentColor: const Color(0xFF1E88E5),
              onChanged: (_) {},
              onCommit: () => committed = true,
              onCancel: () => cancelled = true,
            ),
          ]),
        ),
      ));

      await tester.tap(find.byKey(const ValueKey('pdf-crop-confirm')));
      expect(committed, isTrue);
      await tester.tap(find.byKey(const ValueKey('pdf-crop-cancel')));
      expect(cancelled, isTrue);
    });
  });

  group('crop overlay in the viewer', () {
    Future<PdfEditingController> pumpWithImage(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      // a fully-visible image near the top of the page
      expect(editing.addImageInRect(
          0, const PdfRect(150, 520, 350, 700), _png), isTrue);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: editing,
            builder: (context, _) => PdfViewer(
              initialFit: PdfViewerFit.width,
              document: editing.document,
              controller: viewer,
              editing: editing,
            ),
          ),
        ),
      ));
      await tester.pump();
      return editing;
    }

    testWidgets('beginImageCrop shows the overlay; confirm hides it',
        (tester) async {
      final editing = await pumpWithImage(tester);
      expect(editing.canCropSelected, isTrue);
      expect(find.byKey(const ValueKey('pdf-image-crop-overlay')), findsNothing);

      editing.beginImageCrop();
      await tester.pump();
      expect(editing.isCroppingImage, isTrue);
      expect(
          find.byKey(const ValueKey('pdf-image-crop-overlay')), findsOneWidget);

      // the on-page confirm chip commits and tears the overlay down
      await tester.tap(find.byKey(const ValueKey('pdf-crop-confirm')));
      // let the double-tap window and ink ripple timers drain
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expect(editing.isCroppingImage, isFalse);
      expect(find.byKey(const ValueKey('pdf-image-crop-overlay')), findsNothing);
    });

    testWidgets('dragging a handle then confirming crops the image',
        (tester) async {
      final editing = await pumpWithImage(tester);
      final rect = editing.selectedAnnotation!.rect; // [160,520,340,700]
      editing.beginImageCrop();
      await tester.pump();

      // the page is laid out at 800px wide (page 612pt) → scale ≈ 1.307; the
      // top-left handle sits at the image's top-left view corner
      const s = 800 / 612;
      final topLeft = Offset(rect.left * s, (792 - rect.top) * s);
      final g = await tester.startGesture(topLeft);
      await tester.pump();
      await g.moveBy(const Offset(40, 40));
      await tester.pump();
      await g.up();
      await tester.pump();

      // the draft shrank from the top-left (page space: left grew, top fell)
      expect(editing.imageCropDraft!.left, greaterThan(rect.left + 5));
      expect(editing.imageCropDraft!.top, lessThan(rect.top - 5));

      await tester.tap(find.byKey(const ValueKey('pdf-crop-confirm')));
      await tester.pumpAndSettle(const Duration(milliseconds: 400));

      final stamp = editing.selectedAnnotation!;
      expect(editing.isCroppingImage, isFalse);
      expect(stamp.imageStampCrop, isNotNull);
      // the box shrank to the dragged region
      expect(stamp.rect.left, greaterThan(rect.left + 5));
      expect(stamp.rect.top, lessThan(rect.top - 5));
      expect(appearance(editing.document, stamp), contains('/Img0 Do'));
    });

    testWidgets('cancel via the overlay chip discards the crop', (tester) async {
      final editing = await pumpWithImage(tester);
      final rect = editing.selectedAnnotation!.rect;
      editing.beginImageCrop();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pdf-crop-cancel')));
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expect(editing.isCroppingImage, isFalse);
      expect(editing.selectedAnnotation!.imageStampCrop, isNull);
      expect(editing.selectedAnnotation!.rect, rect);
    });
  });

  group('crop in the toolbar', () {
    Future<PdfEditingController> pumpToolbar(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      expect(editing.addImageInRect(
          0, const PdfRect(150, 520, 350, 700), _png), isTrue);
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

    testWidgets('the Crop button arms cropping and swaps in the crop strip',
        (tester) async {
      final editing = await pumpToolbar(tester);
      await tester.pump();
      // the placed image is selected, so the Crop button shows
      expect(find.byKey(const ValueKey('pdf-crop-image')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pdf-crop-image')));
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expect(editing.isCroppingImage, isTrue);
      // the strip now shows the crop Done/Cancel actions
      expect(find.byKey(const ValueKey('pdf-crop-apply-toolbar')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-crop-cancel-toolbar')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-crop-image')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('pdf-crop-cancel-toolbar')));
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
      expect(editing.isCroppingImage, isFalse);
      expect(find.byKey(const ValueKey('pdf-crop-image')), findsOneWidget);
    });
  });
}
