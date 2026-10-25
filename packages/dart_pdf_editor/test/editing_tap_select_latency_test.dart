import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

// A finger tap that selects must land on the lift, not after the viewer's
// double-tap-to-zoom recognizer gives the gesture up (kDoubleTapTimeout).

// 800×600 viewport, fit-width: 612pt page → view scale
const scale = 800 / 612;

Offset viewPoint(double x, double y) => Offset(x * scale, (792 - y) * scale);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<PdfEditingController> pumpViewer(WidgetTester tester,
      {Uint8List? bytes}) async {
    final editing = PdfEditingController(bytes ?? buildMultiPagePdf(1));
    addTearDown(editing.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(initialFit: PdfViewerFit.width, editing: editing),
      ),
    ));
    await tester.pump();
    return editing;
  }

  Future<void> touchTap(WidgetTester tester, Offset at) async {
    final gesture =
        await tester.startGesture(at, kind: PointerDeviceKind.touch);
    await tester.pump(const Duration(milliseconds: 40));
    await gesture.up();
    await tester.pump();
  }

  testWidgets('a touch tap selects an annotation on the lift', (tester) async {
    final editing = await pumpViewer(tester);
    editing
      ..addRectangle(0, const PdfRect(300, 400, 400, 450))
      ..addRectangle(0, const PdfRect(100, 500, 200, 550))
      ..tool = PdfEditTool.select;
    await tester.pump();

    await touchTap(tester, viewPoint(350, 425));
    expect(editing.selectedAnnotationSlots, [(0, 0)]);
    // the arena's own tap arriving later must not re-run the tap
    await tester.pump(kDoubleTapTimeout);
    expect(editing.selectedAnnotationSlots, [(0, 0)]);

    await tester.pump(const Duration(milliseconds: 100));
    await touchTap(tester, viewPoint(150, 525));
    expect(editing.selectedAnnotationSlots, [(0, 1)]);
    await tester.pump(kDoubleTapTimeout);

    // a tap on empty page clears it, just as promptly
    await tester.pump(const Duration(milliseconds: 100));
    await touchTap(tester, viewPoint(550, 380));
    expect(editing.selectedAnnotationSlots, isEmpty);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('re-tapping a selected free text still opens its editor once',
      (tester) async {
    final editing = await pumpViewer(tester);
    editing
      ..addFreeText(0, const PdfRect(300, 400, 420, 430), 'Hello')
      ..tool = PdfEditTool.select;
    await tester.pump();
    final rect = editing.document.page(0).annotations.single.rect;
    final at =
        viewPoint(rect.left + rect.width / 2, rect.bottom + rect.height / 2);

    await touchTap(tester, at);
    expect(editing.selectedAnnotationSlots, [(0, 0)]);
    // the delayed arena tap of that same press must not read as the
    // "tap the selected free text" second tap
    await tester.pump(kDoubleTapTimeout);
    expect(editing.isEditingText, isFalse);

    await tester.pump(const Duration(milliseconds: 100));
    await touchTap(tester, at);
    await tester.pump(kDoubleTapTimeout);
    expect(editing.isEditingText, isTrue);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a touch drag is not a tap', (tester) async {
    final editing = await pumpViewer(tester);
    editing
      ..addRectangle(0, const PdfRect(300, 400, 400, 450))
      ..tool = PdfEditTool.select;
    await tester.pump();
    final gesture = await tester.startGesture(viewPoint(550, 380),
        kind: PointerDeviceKind.touch);
    await gesture.moveBy(const Offset(0, -60));
    await gesture.moveTo(viewPoint(350, 425));
    await gesture.up();
    await tester.pump();
    expect(editing.selectedAnnotationSlots, isEmpty);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets(
      'the form tool selects a field on the click, not after its '
      'fill double-tap gives up', (tester) async {
    // buildAcroFormPdf's 'name' text field is [72 700 300 724]
    final editing = await pumpViewer(tester, bytes: buildAcroFormPdf());
    editing.tool = PdfEditTool.form;
    await tester.pump();

    final gesture = await tester.startGesture(viewPoint(186, 712),
        kind: PointerDeviceKind.mouse);
    await gesture.up();
    await tester.pump();
    expect(editing.selectedAnnotation?.subtype, 'Widget');
    await tester.pump(kDoubleTapTimeout);
    expect(editing.selectedAnnotation?.subtype, 'Widget');
    expect(find.byKey(const ValueKey('pdf-form-text-editor')), findsNothing);
    await tester.pump(const Duration(seconds: 1));
  });
}
