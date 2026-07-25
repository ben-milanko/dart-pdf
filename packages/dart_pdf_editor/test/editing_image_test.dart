// Inserting a raster image (PdfEditTool.image): the controller places it
// as a stamp annotation, and the viewer's image tool runs the host picker
// on tap / drag-out.
import 'dart:convert';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 2x2 RGBA-8 PNG (square; aspect 1).
final _png = base64.decode('iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0k'
    'AAAAGUlEQVR4nGP4z8DwHwgbWBgZ/jNyicr7AgA3BAUOTnqjAAAAAABJRU5ErkJggg==');

String appearance(PdfDocument doc, PdfAnnotation annot) =>
    latin1.decode(doc.cos.decodeStreamData(annot.normalAppearance!));

void main() {
  group('PdfEditingController image insertion', () {
    test('placeImage drops a square image at the tap, aspect preserved', () {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);

      expect(editing.placeImage(0, 300, 400, _png), isTrue);
      final stamp = editing.document.page(0).annotations.single;
      expect(stamp.subtype, 'Stamp');
      // a 2x2 image: the placed box is square and centered on the tap
      expect(stamp.rect.width, closeTo(stamp.rect.height, 1e-9));
      expect((stamp.rect.left + stamp.rect.right) / 2, closeTo(300, 1e-9));
      expect((stamp.rect.bottom + stamp.rect.top) / 2, closeTo(400, 1e-9));
      expect(appearance(editing.document, stamp), contains('/Img0 Do'));
    });

    test('placeImage clamps the box to keep it on the page', () {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);

      // a tap near the corner: the box stays inside the 612x792 crop box
      expect(editing.placeImage(0, 10, 10, _png), isTrue);
      final rect = editing.document.page(0).annotations.single.rect;
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.bottom, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(612));
      expect(rect.top, lessThanOrEqualTo(792));
    });

    test('addImageInRect fits the image within the dragged box', () {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);

      // a 200x50 box; the square image fits to 50x50, centered
      expect(editing.addImageInRect(0, const PdfRect(100, 100, 300, 150), _png),
          isTrue);
      final rect = editing.document.page(0).annotations.single.rect;
      expect(rect.width, closeTo(50, 1e-9));
      expect(rect.height, closeTo(50, 1e-9));
      expect((rect.left + rect.right) / 2, closeTo(200, 1e-9));
      expect((rect.bottom + rect.top) / 2, closeTo(125, 1e-9));
    });

    test('placeImageAsync prepares the image off-thread and inserts', () async {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);

      expect(await editing.placeImageAsync(0, 300, 400, _png), isTrue);
      final stamp = editing.document.page(0).annotations.single;
      expect(stamp.subtype, 'Stamp');
      expect(appearance(editing.document, stamp), contains('/Img0 Do'));
    });

    test('junk bytes are rejected without a revision', () {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);

      expect(editing.placeImage(0, 100, 100, Uint8List.fromList([1, 2, 3])),
          isFalse);
      expect(
          editing.addImageInRect(
              0, const PdfRect(0, 0, 100, 100), Uint8List.fromList([1, 2, 3])),
          isFalse);
      expect(editing.isModified, isFalse);
    });
  });

  group('image tool in the viewer', () {
    const scale = 800 / 612;
    Offset view(double x, double y) => Offset(x * scale, (792 - y) * scale);

    Future<void> tap(WidgetTester tester, Offset position) async {
      await tester.tapAt(position);
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<void> waitForImageInsert(
        WidgetTester tester, PdfEditingController editing) async {
      await tester.runAsync(() async {
        for (var i = 0; i < 50; i++) {
          if (editing.document.page(0).annotations.isNotEmpty) return;
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pump();
    }

    Future<PdfEditingController> pumpEditor(WidgetTester tester,
        {PdfImagePicker? imagePicker}) async {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: editing,
            builder: (context, _) => PdfViewer(
              initialFit: PdfViewerFit.width,
              document: editing.document,
              controller: viewer,
              editing: editing,
              imagePicker: imagePicker,
            ),
          ),
        ),
      ));
      await tester.pump();
      return editing;
    }

    testWidgets('tapping with the image tool runs the picker and inserts',
        (tester) async {
      var calls = 0;
      final editing = await pumpEditor(tester, imagePicker: (context) {
        calls++;
        return Future.value(_png);
      });
      editing.tool = PdfEditTool.image;
      await tester.pump();

      await tap(tester, view(300, 400));
      await waitForImageInsert(tester, editing);
      expect(calls, 1);
      final stamp = editing.document.page(0).annotations.single;
      expect(stamp.subtype, 'Stamp');
      expect(appearance(editing.document, stamp), contains('/Img0 Do'));
    });

    testWidgets('a cancelled pick inserts nothing', (tester) async {
      final editing = await pumpEditor(tester,
          imagePicker: (context) => Future.value(null));
      editing.tool = PdfEditTool.image;
      await tester.pump();

      await tap(tester, view(300, 400));
      await tester.pump();
      expect(editing.document.page(0).annotations, isEmpty);
      expect(editing.isModified, isFalse);
    });

    testWidgets('with no picker the image tool does nothing', (tester) async {
      final editing = await pumpEditor(tester);
      editing.tool = PdfEditTool.image;
      await tester.pump();

      await tap(tester, view(300, 400));
      await tester.pump();
      expect(editing.document.page(0).annotations, isEmpty);
    });
  });

  group('image tool visibility in the toolbar', () {
    // Anything whose tooltip starts with the image tool's - it carries a
    // trailing " (I)" shortcut hint we don't want to hard-code.
    final imageTool = find.byWidgetPredicate((w) =>
        w is IconButton &&
        (w.tooltip?.startsWith('Image - tap to place') ?? false));

    Future<PdfEditingController> pumpToolbar(WidgetTester tester,
        {PdfImagePicker? imagePicker}) async {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PdfEditingToolbar(
            controller: editing,
            viewerController: viewer,
            imagePicker: imagePicker,
          ),
        ),
      ));
      // Arm a tool that's always in the Insert group to raise its strip.
      editing.tool = PdfEditTool.freeText;
      await tester.pump();
      return editing;
    }

    testWidgets('is hidden from the Insert group when no picker is wired',
        (tester) async {
      await pumpToolbar(tester);
      expect(imageTool, findsNothing);
    });

    testWidgets('appears once an imagePicker is supplied', (tester) async {
      await pumpToolbar(tester, imagePicker: (context) => Future.value(_png));
      expect(imageTool, findsOneWidget);
    });
  });

  group('PdfEditingController image cropping', () {
    PdfEditingController placedImage() {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
      // a 200x200 box centered on (300, 400): [200, 300, 400, 500]
      expect(editing.addImageInRect(
          0, const PdfRect(200, 300, 400, 500), _png), isTrue);
      return editing;
    }

    test('canCropSelected is true only for a selected image stamp', () {
      final editing = placedImage();
      addTearDown(editing.dispose);
      expect(editing.selectedAnnotation?.isImageStamp, isTrue);
      expect(editing.canCropSelected, isTrue);

      // a note is not croppable
      final other = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(other.dispose);
      other.addNote(0, 100, 100, 'hi');
      expect(other.canCropSelected, isFalse);
    });

    test('cropSelectedImage shrinks the box and records the crop', () {
      final editing = placedImage();
      addTearDown(editing.dispose);
      final rect = editing.selectedAnnotation!.rect;
      // crop to the top-right quarter of the box
      final cx = (rect.left + rect.right) / 2;
      final cy = (rect.bottom + rect.top) / 2;
      editing.cropSelectedImage(PdfRect(cx, cy, rect.right, rect.top));

      final stamp = editing.document.page(0).annotations.single;
      // the box shrank to the visible quarter
      expect(stamp.rect.left, closeTo(cx, 1e-6));
      expect(stamp.rect.bottom, closeTo(cy, 1e-6));
      expect(stamp.rect.right, closeTo(rect.right, 1e-6));
      expect(stamp.rect.top, closeTo(rect.top, 1e-6));
      // the crop is the top-right quarter of the source
      final crop = stamp.imageStampCrop!;
      expect(crop.left, closeTo(0.5, 1e-6));
      expect(crop.bottom, closeTo(0.5, 1e-6));
      expect(crop.right, closeTo(1.0, 1e-6));
      expect(crop.top, closeTo(1.0, 1e-6));
    });

    test('cropping composes against the source across two crops', () {
      final editing = placedImage();
      addTearDown(editing.dispose);
      final rect = editing.selectedAnnotation!.rect;
      // first crop: left half
      editing.cropSelectedImage(PdfRect(
          rect.left, rect.bottom, (rect.left + rect.right) / 2, rect.top));
      var crop = editing.selectedAnnotation!.imageStampCrop!;
      expect(crop.right, closeTo(0.5, 1e-6));
      // second crop: left half of what remains → left quarter of the source
      final r2 = editing.selectedAnnotation!.rect;
      editing.cropSelectedImage(PdfRect(
          r2.left, r2.bottom, (r2.left + r2.right) / 2, r2.top));
      crop = editing.selectedAnnotation!.imageStampCrop!;
      expect(crop.right, closeTo(0.25, 1e-6));
    });

    test('resetSelectedImageCrop restores the whole picture and box', () {
      final editing = placedImage();
      addTearDown(editing.dispose);
      final original = editing.selectedAnnotation!.rect;
      editing.cropSelectedImage(PdfRect(original.left, original.bottom,
          (original.left + original.right) / 2, original.top));
      expect(editing.selectedAnnotation!.imageStampCrop, isNotNull);

      editing.resetSelectedImageCrop();
      final stamp = editing.selectedAnnotation!;
      expect(stamp.imageStampCrop, isNull);
      // the box grew back to the original full extent
      expect(stamp.rect.left, closeTo(original.left, 1e-4));
      expect(stamp.rect.right, closeTo(original.right, 1e-4));
      expect(stamp.rect.bottom, closeTo(original.bottom, 1e-4));
      expect(stamp.rect.top, closeTo(original.top, 1e-4));
    });

    test('crop-mode lifecycle: begin, update, commit', () {
      final editing = placedImage();
      addTearDown(editing.dispose);
      final rect = editing.selectedAnnotation!.rect;
      expect(editing.isCroppingImage, isFalse);

      editing.beginImageCrop();
      expect(editing.isCroppingImage, isTrue);
      expect(editing.imageCropDraft, rect);

      // dragging a smaller draft, clamped to the box
      final draft = PdfRect(
          rect.left + 10, rect.bottom + 10, rect.right - 10, rect.top - 10);
      editing.updateImageCropDraft(draft);
      expect(editing.imageCropDraft, draft);
      // an out-of-bounds draft is clamped to the box
      editing.updateImageCropDraft(PdfRect(
          rect.left - 100, rect.bottom + 10, rect.right - 10, rect.top - 10));
      expect(editing.imageCropDraft!.left, closeTo(rect.left, 1e-6));

      editing.commitImageCrop();
      expect(editing.isCroppingImage, isFalse);
      expect(editing.selectedAnnotation!.imageStampCrop, isNotNull);
    });

    test('crop-mode cancel discards the pending crop', () {
      final editing = placedImage();
      addTearDown(editing.dispose);
      final rect = editing.selectedAnnotation!.rect;
      editing.beginImageCrop();
      editing.updateImageCropDraft(PdfRect(
          rect.left + 10, rect.bottom + 10, rect.right - 10, rect.top - 10));
      editing.cancelImageCrop();
      expect(editing.isCroppingImage, isFalse);
      expect(editing.selectedAnnotation!.imageStampCrop, isNull);
      expect(editing.selectedAnnotation!.rect, rect);
    });

    test('changing tool cancels an in-flight crop', () {
      final editing = placedImage();
      addTearDown(editing.dispose);
      editing.beginImageCrop();
      expect(editing.isCroppingImage, isTrue);
      editing.tool = PdfEditTool.ink;
      expect(editing.isCroppingImage, isFalse);
    });
  });
}
