import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // The viewer fits a 612pt-wide page into an 800px viewport.
  const scale = 800 / 612;
  Offset view(double x, double y) => Offset(x * scale, (792 - y) * scale);

  Future<PdfEditingController> pumpEditor(WidgetTester tester,
      {PdfMeasurementScale? measurementScale}) async {
    SharedPreferences.setMockInitialValues({});
    final editing = PdfEditingController(buildMultiPagePdf(1))
      ..preferences.measurementScale = measurementScale;
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
          ),
        ),
      ),
    ));
    await tester.pump();
    return editing;
  }

  Future<void> drag(WidgetTester tester, Offset from, Offset to) async {
    final gesture =
        await tester.startGesture(from, kind: PointerDeviceKind.mouse);
    await tester.pump();
    await gesture.moveTo(to);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
  }

  final field = find.byKey(const ValueKey('pdf-text-prompt-field'));

  testWidgets('drags a dimension and stamps the typed value, no scale needed',
      (tester) async {
    final editing = await pumpEditor(tester);
    editing.tool = PdfEditTool.measureCustom;
    await tester.pump();
    // a dimension reads with an arrowhead at each end
    expect(editing.preferences.lineStartEnding, PdfLineEnding.closedArrow);
    expect(editing.preferences.lineEndEnding, PdfLineEnding.closedArrow);

    await drag(tester, view(100, 650), view(300, 650));
    expect(field, findsOneWidget);
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    await tester.enterText(field, '12\'-6"');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final annot = editing.document.page(0).annotations.single;
    expect(annot.subtype, 'Line');
    expect(annot.measurementKind, PdfMeasurementKind.distance);
    expect(annot.measurementText, '12\'-6"');
    expect(annot.measurementResult!.isCustom, isTrue);
    expect(annot.measurementResult!.value, 12.5);
    // the tool stays armed for the next dimension
    expect(editing.tool, PdfEditTool.measureCustom);
  });

  testWidgets('the prompt starts at the scaled length; cancel stamps nothing',
      (tester) async {
    final editing = await pumpEditor(tester,
        measurementScale: PdfMeasurementScale(
            unitsPerPoint: 20 / 72, unitLabel: 'ft', precision: 1));
    editing.tool = PdfEditTool.measureCustom;
    await tester.pump();

    // 72pt = 1in = 20ft
    await drag(tester, view(100, 650), view(172, 650));
    expect(tester.widget<TextField>(field).controller!.text, '20 ft');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(editing.document.page(0).annotations, isEmpty);

    await drag(tester, view(100, 650), view(172, 650));
    await tester.enterText(field, '21 ft');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    final annot = editing.document.page(0).annotations.single;
    expect(annot.measure, isNotNull);
    expect(annot.measurementText, '21 ft');
  });

  test('a selected measurement takes a written value and gives it back', () {
    SharedPreferences.setMockInitialValues({});
    final editing = PdfEditingController(buildMultiPagePdf(1))
      ..preferences.measurementScale = PdfMeasurementScale(
          unitsPerPoint: 20 / 72, unitLabel: 'ft', precision: 1);
    addTearDown(editing.dispose);
    editing.addMeasurement(
        0, PdfMeasurementKind.distance, const [(100, 100), (172, 100)]);
    editing.selectAnnotation(0, 0);
    expect(editing.canEditSelectedMeasurementValue, isTrue);
    expect(editing.selectedMeasurementValue, '20 ft');
    expect(editing.selectedMeasurementValueIsCustom, isFalse);

    final before = editing.revisionId;
    editing.setSelectedMeasurementValue('19\'-11"');
    expect(editing.revisionId, isNot(before));
    expect(editing.selectedMeasurementValue, '19\'-11"');
    expect(editing.selectedMeasurementValueIsCustom, isTrue);
    expect(editing.document.page(0).annotations.single.measurementText,
        '19\'-11"');

    // unchanged → no revision
    final same = editing.revisionId;
    editing.setSelectedMeasurementValue('19\'-11"');
    expect(editing.revisionId, same);

    // blank → back to the computed value, and undo restores the written one
    editing.setSelectedMeasurementValue('');
    expect(
        editing.document.page(0).annotations.single.measurementText, '20 ft');
    editing.undo();
    expect(editing.document.page(0).annotations.single.measurementText,
        '19\'-11"');
  });

  test('a count marker has no value to write', () {
    SharedPreferences.setMockInitialValues({});
    final editing = PdfEditingController(buildMultiPagePdf(1));
    addTearDown(editing.dispose);
    editing.addCountMark(0, (100, 100));
    editing.selectAnnotation(0, 0);
    expect(editing.canEditSelectedMeasurementValue, isFalse);
    expect(editing.selectedMeasurementValue, isNull);
  });
}
