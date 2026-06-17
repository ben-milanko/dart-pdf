import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

/// One 200×300 page with /Rotate [rotation] and a black 20×20 square
/// at (100, 150)..(120, 170) in page space.
Uint8List _buildRotatedPdf(int rotation) {
  const content = '0 g 100 150 20 20 re f';
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 300] '
        '/Rotate $rotation /Contents 4 0 R >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
  ];
  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xrefOffset = buffer.length;
  buffer
    ..write('xref\n0 ${objects.length + 1}\n')
    ..write('0000000000 65535 f \n');
  for (final offset in offsets) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer
    ..write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n')
    ..write('startxref\n$xrefOffset\n%%EOF\n');
  return ascii(buffer.toString());
}

void main() {
  group('PdfViewerController.rotateView', () {
    test('starts at 0', () {
      final controller = PdfViewerController();
      expect(controller.viewRotation, 0);
    });

    test('accumulates clockwise rotations', () {
      final controller = PdfViewerController();
      controller.rotateView(90);
      expect(controller.viewRotation, 90);
      controller.rotateView(90);
      expect(controller.viewRotation, 180);
      controller.rotateView(90);
      expect(controller.viewRotation, 270);
      controller.rotateView(90);
      expect(controller.viewRotation, 0);
    });

    test('normalizes negative values', () {
      final controller = PdfViewerController();
      controller.rotateView(-90);
      expect(controller.viewRotation, 270);
      controller.rotateView(-90);
      expect(controller.viewRotation, 180);
    });

    test('full turn is a no-op', () {
      final controller = PdfViewerController();
      var notified = false;
      controller.addListener(() => notified = true);
      controller.rotateView(360);
      expect(controller.viewRotation, 0);
      expect(notified, isFalse);
    });

    test('notifies listeners', () {
      final controller = PdfViewerController();
      var count = 0;
      controller.addListener(() => count++);
      controller.rotateView(90);
      expect(count, 1);
    });
  });

  group('PdfPageRenderer.pageSize with rotation override', () {
    testWidgets('rotation override swaps dimensions', (tester) async {
      await tester.runAsync(() async {
        final doc = PdfDocument.open(_buildRotatedPdf(0));
        final page = doc.page(0);
        // /Rotate 0: 200×300
        final normal = PdfPageRenderer.pageSize(page);
        expect(normal.width, 200);
        expect(normal.height, 300);
        // override 90: 300×200
        final rotated = PdfPageRenderer.pageSize(page, rotation: 90);
        expect(rotated.width, 300);
        expect(rotated.height, 200);
        // override 180: same as 0
        final flipped = PdfPageRenderer.pageSize(page, rotation: 180);
        expect(flipped.width, 200);
        expect(flipped.height, 300);
        // override 270: swapped like 90
        final rot270 = PdfPageRenderer.pageSize(page, rotation: 270);
        expect(rot270.width, 300);
        expect(rot270.height, 200);
      });
    });

    testWidgets('composes with document /Rotate', (tester) async {
      await tester.runAsync(() async {
        // Page has /Rotate 90 → native size is 300×200
        final doc = PdfDocument.open(_buildRotatedPdf(90));
        final page = doc.page(0);
        final native = PdfPageRenderer.pageSize(page);
        expect(native.width, 300);
        expect(native.height, 200);
        // Override rotation=180 on a /Rotate 90 page → effective 180
        final overridden = PdfPageRenderer.pageSize(page, rotation: 180);
        expect(overridden.width, 200);
        expect(overridden.height, 300);
      });
    });
  });

  group('renderer with rotation override produces correct pixels', () {
    for (final viewRot in [90, 180, 270]) {
      testWidgets(
          '/Rotate 0 + rotation:$viewRot matches /Rotate $viewRot native',
          (tester) async {
        await tester.runAsync(() async {
          // Render a page with /Rotate 0, overriding to viewRot
          final doc0 = PdfDocument.open(_buildRotatedPdf(0));
          final page0 = doc0.page(0);
          final img0 = await PdfPageRenderer.renderImage(page0,
              rotation: viewRot);

          // Render a page with /Rotate=viewRot natively
          final docR = PdfDocument.open(_buildRotatedPdf(viewRot));
          final pageR = docR.page(0);
          final imgR = await PdfPageRenderer.renderImage(pageR);

          expect(img0.width, imgR.width);
          expect(img0.height, imgR.height);

          final data0 =
              (await img0.toByteData(format: ImageByteFormat.rawRgba))!
                  .buffer
                  .asUint8List();
          final dataR =
              (await imgR.toByteData(format: ImageByteFormat.rawRgba))!
                  .buffer
                  .asUint8List();

          // pixel-identical
          expect(data0.length, dataR.length);
          var diffPixels = 0;
          for (var i = 0; i < data0.length; i += 4) {
            if ((data0[i] - dataR[i]).abs() > 1 ||
                (data0[i + 1] - dataR[i + 1]).abs() > 1 ||
                (data0[i + 2] - dataR[i + 2]).abs() > 1) {
              diffPixels++;
            }
          }
          expect(diffPixels, 0,
              reason: 'rotation:$viewRot on /Rotate 0 should match '
                  '/Rotate $viewRot native render');
        });
      });
    }
  });

  group('PdfPageGeometry with view rotation', () {
    test('effective rotation round-trips coordinates', () {
      // Simulate a /Rotate 0 page viewed at 90° view rotation
      // → effective rotation = 90, view size swaps
      const geometry = PdfPageGeometry(
        cropBox: PdfRect(0, 0, 200, 300),
        rotation: 90,
        viewSize: Size(300, 200),
      );
      final (x, y) = geometry.toPagePoint(geometry.toViewOffset(110, 160));
      expect(x, moreOrLessEquals(110));
      expect(y, moreOrLessEquals(160));
    });

    for (final effective in [0, 90, 180, 270]) {
      testWidgets(
          'toViewOffset hits the rendered mark at effective rotation $effective',
          (tester) async {
        await tester.runAsync(() async {
          // Always /Rotate 0, override with effective rotation
          final doc = PdfDocument.open(_buildRotatedPdf(0));
          final page = doc.page(0);
          final image = await PdfPageRenderer.renderImage(page,
              rotation: effective);
          final size =
              Size(image.width.toDouble(), image.height.toDouble());
          final geometry = PdfPageGeometry(
            cropBox: page.cropBox,
            rotation: effective,
            viewSize: size,
          );
          final data =
              (await image.toByteData(format: ImageByteFormat.rawRgba))!
                  .buffer
                  .asUint8List();
          int pixelAt(Offset view) {
            final x = view.dx.round().clamp(0, image.width - 1);
            final y = view.dy.round().clamp(0, image.height - 1);
            return data[(y * image.width + x) * 4];
          }

          // center of the square (110, 160) must be dark
          expect(pixelAt(geometry.toViewOffset(110, 160)), lessThan(50),
              reason: 'mark center at effective=$effective');
          // far from the square must be white
          expect(pixelAt(geometry.toViewOffset(50, 50)), greaterThan(200),
              reason: 'empty area at effective=$effective');
        });
      });
    }
  });

  group('viewer integration', () {
    Future<PdfViewerController> pumpViewer(WidgetTester tester,
        {Uint8List? bytes}) async {
      final controller = PdfViewerController();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PdfViewer(
            initialFit: PdfViewerFit.width,
            document: PdfDocument.open(bytes ?? buildMultiPagePdf(3)),
            controller: controller,
            pagePreviews: false,
          ),
        ),
      ));
      await tester.pump();
      return controller;
    }

    testWidgets('rotateView changes the page layout aspect',
        (tester) async {
      final controller = await pumpViewer(tester);
      // 612×792 page at fit-width in 800×600: tall page
      final sizeBefore = tester.getSize(find.byType(PdfPageView).first);
      expect(sizeBefore.width, greaterThan(sizeBefore.height * 0.5),
          reason: 'portrait page should be taller than wide');

      controller.rotateView(90);
      await tester.pump();

      // After 90° view rotation the page should be landscape
      final sizeAfter = tester.getSize(find.byType(PdfPageView).first);
      expect(sizeAfter.width, greaterThan(sizeAfter.height),
          reason: 'page should be wider after 90° view rotation');
    });

    testWidgets('rotateView 360° returns to original layout',
        (tester) async {
      final controller = await pumpViewer(tester);
      final sizeBefore = tester.getSize(find.byType(PdfPageView).first);

      controller.rotateView(90);
      await tester.pump();
      controller.rotateView(90);
      await tester.pump();
      controller.rotateView(90);
      await tester.pump();
      controller.rotateView(90);
      await tester.pump();

      final sizeAfter = tester.getSize(find.byType(PdfPageView).first);
      expect(sizeAfter.width, closeTo(sizeBefore.width, 1));
      expect(sizeAfter.height, closeTo(sizeBefore.height, 1));
    });

    testWidgets('rotateView with an already-rotated document composes',
        (tester) async {
      // /Rotate 90 doc → native landscape. View rotate 90 → portrait again
      final controller =
          await pumpViewer(tester, bytes: _buildRotatedPdf(90));
      final sizeBefore = tester.getSize(find.byType(PdfPageView).first);
      // /Rotate 90 on 200×300 → 300×200 landscape
      expect(sizeBefore.width, greaterThan(sizeBefore.height));

      controller.rotateView(90);
      await tester.pump();

      // effective = 180 → 200×300 portrait
      final sizeAfter = tester.getSize(find.byType(PdfPageView).first);
      expect(sizeAfter.height, greaterThan(sizeAfter.width));
    });
  });
}
