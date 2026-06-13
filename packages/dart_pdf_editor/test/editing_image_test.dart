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
      expect(
          editing.addImageInRect(0, const PdfRect(100, 100, 300, 150), _png),
          isTrue);
      final rect = editing.document.page(0).annotations.single.rect;
      expect(rect.width, closeTo(50, 1e-9));
      expect(rect.height, closeTo(50, 1e-9));
      expect((rect.left + rect.right) / 2, closeTo(200, 1e-9));
      expect((rect.bottom + rect.top) / 2, closeTo(125, 1e-9));
    });

    test('junk bytes are rejected without a revision', () {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);

      expect(editing.placeImage(0, 100, 100, Uint8List.fromList([1, 2, 3])),
          isFalse);
      expect(editing.addImageInRect(0, const PdfRect(0, 0, 100, 100),
          Uint8List.fromList([1, 2, 3])), isFalse);
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
      await tester.pump();
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
}
