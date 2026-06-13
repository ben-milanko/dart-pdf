import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/editing/editing_overlay.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The editing overlay's preview painter, read through a dynamic cast
/// (the painter class is private to the library).
dynamic overlayPainter(WidgetTester tester) => tester
    .widget<CustomPaint>(find
        .descendant(
            of: find.byType(EditingPageOverlay),
            matching: find.byType(CustomPaint))
        .first)
    .painter;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // A bare overlay over a 306×396 view of the 612×792 page: 0.5 px/pt.
  Future<PdfEditingController> pumpOverlay(WidgetTester tester,
      {required String shape}) async {
    final editing = PdfEditingController(buildMultiPagePdf(1))
      ..color = const Color(0xFFFF0000)
      ..strokeWidth = 4;
    if (shape == 'Circle') {
      editing.addEllipse(0, const PdfRect(100, 550, 300, 650));
    } else {
      editing.addRectangle(0, const PdfRect(100, 550, 300, 650));
    }
    editing
      ..tool = PdfEditTool.select
      ..selectAnnotation(0, 0);
    addTearDown(editing.dispose);
    final geometry = PdfPageGeometry(
      cropBox: editing.document.page(0).cropBox,
      rotation: 0,
      viewSize: const Size(306, 396),
    );
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox(
          width: 306,
          height: 396,
          child: EditingPageOverlay(
            controller: editing,
            pageIndex: 0,
            geometry: geometry,
            textPrompt: showPdfTextPrompt,
          ),
        ),
      ),
    ));
    await tester.pump();
    return editing;
  }

  testWidgets(
      'a square resize previews at a constant stroke width, not the '
      'stretched ghost', (tester) async {
    await pumpOverlay(tester, shape: 'Square');
    final origin = tester.getTopLeft(find.byType(EditingPageOverlay));
    // selection (100,550)-(300,650) → view (50,71)-(150,121); the
    // bottom-right corner handle sits at the rect corner
    final corner = origin + const Offset(150, 121);

    final gesture =
        await tester.startGesture(corner, kind: PointerDeviceKind.mouse);
    // widen and lengthen the box a long way — a stretched ghost would
    // thicken the line in proportion
    await gesture.moveTo(origin + const Offset(280, 250));
    await tester.pump();

    final painter = overlayPainter(tester);
    // the ghost is suppressed in favour of the constant-width preview
    expect(painter.ghost, isNull);
    final shapeResize = painter.shapeResize;
    expect(shapeResize, isNotNull);
    expect(shapeResize.ellipse, isFalse);
    // 4pt border at 0.5 px/pt = 2 view px, regardless of the drag size
    expect(shapeResize.strokeWidth, closeTo(2.0, 1e-9));
    expect(shapeResize.stroke, isNotNull);

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('a circle resize previews as an ellipse at constant width',
      (tester) async {
    await pumpOverlay(tester, shape: 'Circle');
    final origin = tester.getTopLeft(find.byType(EditingPageOverlay));
    final corner = origin + const Offset(150, 121);

    final gesture =
        await tester.startGesture(corner, kind: PointerDeviceKind.mouse);
    await gesture.moveTo(origin + const Offset(280, 250));
    await tester.pump();

    final shapeResize = overlayPainter(tester).shapeResize;
    expect(shapeResize, isNotNull);
    expect(shapeResize.ellipse, isTrue);
    expect(shapeResize.strokeWidth, closeTo(2.0, 1e-9));

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets(
      'the resize commit regenerates the shape at its original border width',
      (tester) async {
    final editing = await pumpOverlay(tester, shape: 'Square');
    final before = editing.document.page(0).annotations.single.borderWidth;
    final origin = tester.getTopLeft(find.byType(EditingPageOverlay));
    final corner = origin + const Offset(150, 121);

    final gesture =
        await tester.startGesture(corner, kind: PointerDeviceKind.mouse);
    await gesture.moveTo(origin + const Offset(280, 250));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));

    final annotation = editing.document.page(0).annotations.single;
    // the box grew, but the border width is unchanged (constant stroke)
    expect(annotation.rect.width, greaterThan(200));
    expect(annotation.borderWidth, before);
  });
}
