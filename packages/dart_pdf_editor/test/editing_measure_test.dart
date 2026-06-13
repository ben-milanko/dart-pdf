import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const readoutKey = ValueKey('pdf-measure-readout');

  group('calibration and the controller scale', () {
    test('calibrateScale derives units per point from a reference segment',
        () {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      expect(editing.hasMeasurementScale, isFalse);

      // a 216 pt (3 in) reference segment that represents 60 ft
      editing.calibrateScale((100, 100), (316, 100), 60, 'ft');

      expect(editing.hasMeasurementScale, isTrue);
      final scale = editing.measurementScale!;
      expect(scale.unitLabel, 'ft');
      expect(scale.unitsPerPoint, closeTo(60 / 216, 1e-9));
      // 1 in = 72 pt → 72 × (60/216) = 20 ft
      expect(scale.ratioLabel, '1 in = 20 ft');
    });

    test('live readouts compute distance, perimeter, and area', () {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      editing.measurementScale =
          PdfMeasurementScale(unitsPerPoint: 20 / 72, unitLabel: 'ft');

      expect(editing.measuredDistance((100, 100), (316, 100)), '60 ft');
      expect(
          editing.measuredPerimeter(
              const [(100, 100), (172, 100), (172, 172)]),
          '40 ft');
      expect(
          editing.measuredArea(const [(0, 0), (72, 0), (72, 72), (0, 72)]),
          '400 ft²');
    });

    test('addMeasurement stamps a /Measure annotation with the active scale',
        () {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      editing.measurementScale =
          PdfMeasurementScale(unitsPerPoint: 20 / 72, unitLabel: 'ft');

      editing.addMeasurement(
          0, PdfMeasurementKind.distance, const [(100, 100), (316, 100)]);

      final annotation = editing.document.page(0).annotations.single;
      expect(annotation.subtype, 'Line');
      expect(annotation.measure, isNotNull);
      expect(annotation.measurementText, '60 ft');
    });

    test('addMeasurement is a no-op without a scale', () {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      editing.addMeasurement(
          0, PdfMeasurementKind.distance, const [(0, 0), (72, 0)]);
      expect(editing.document.page(0).annotations, isEmpty);
      expect(editing.isModified, isFalse);
    });

    test('the measurement scale persists across sessions', () async {
      SharedPreferences.setMockInitialValues({});
      final a = PdfEditingPreferences();
      await a.ready;
      expect(a.measurementScale, isNull);
      a.measurementScale =
          PdfMeasurementScale(unitsPerPoint: 20 / 72, unitLabel: 'ft');
      await pumpEventQueue();

      final b = PdfEditingPreferences();
      await b.ready;
      expect(b.measurementScale, isNotNull);
      expect(b.measurementScale!.unitLabel, 'ft');
      expect(b.measurementScale!.unitsPerPoint, closeTo(20 / 72, 1e-9));
    });
  });

  group('live readout chip in the viewer', () {
    const scale = 800 / 612;
    Offset view(double x, double y) => Offset(x * scale, (792 - y) * scale);

    Future<(PdfEditingController, PdfViewerController)> pumpEditor(
        WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(2))
        ..measurementScale =
            PdfMeasurementScale(unitsPerPoint: 20 / 72, unitLabel: 'ft');
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
      return (editing, viewer);
    }

    testWidgets('mouse: readout rides just off the cursor', (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing.tool = PdfEditTool.measureDistance;
      await tester.pump();

      final from = view(100, 700);
      final to = view(300, 700);
      final gesture =
          await tester.startGesture(from, kind: PointerDeviceKind.mouse);
      await gesture.moveTo(Offset.lerp(from, to, 0.5)!);
      await gesture.moveTo(to);
      await tester.pump();

      expect(find.byKey(readoutKey), findsOneWidget);
      // mouse chip is offset down-right of the cursor (+16, -36)
      final topLeft = tester.getTopLeft(find.byKey(readoutKey));
      expect(topLeft.dx, closeTo(to.dx + 16, 0.5));
      expect(topLeft.dy, closeTo(to.dy - 36, 0.5));

      await gesture.up();
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      // the gesture committed a measurement annotation
      expect(editing.document.page(0).annotations.single.subtype, 'Line');
    });

    testWidgets('touch: readout floats well above the finger', (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing.tool = PdfEditTool.measureDistance;
      await tester.pump();

      final from = view(100, 600);
      final to = view(320, 600);
      final gesture =
          await tester.startGesture(from, kind: PointerDeviceKind.touch);
      await gesture.moveTo(Offset.lerp(from, to, 0.5)!);
      await gesture.moveTo(to);
      await tester.pump();

      expect(find.byKey(readoutKey), findsOneWidget);
      final box = tester.getRect(find.byKey(readoutKey));
      // sits clearly above the contact point and is horizontally centered
      expect(box.top, closeTo(to.dy - 64, 0.5));
      expect(box.center.dx, closeTo(to.dx, 1.0));
      // farther above than the mouse offset (36)
      expect(to.dy - box.bottom, greaterThan(0));

      await gesture.up();
      await tester.pumpAndSettle(const Duration(milliseconds: 400));
    });

    testWidgets('no readout once the tool is disarmed', (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing.tool = PdfEditTool.measureDistance;
      await tester.pump();
      // nothing drawn yet → no readout
      expect(find.byKey(readoutKey), findsNothing);
    });
  });
}
