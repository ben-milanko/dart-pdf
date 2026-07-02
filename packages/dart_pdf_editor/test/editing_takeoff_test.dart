import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  PdfEditingController scaled() {
    final c = PdfEditingController(buildMultiPagePdf(1));
    c.measurementScale =
        PdfMeasurementScale(unitsPerPoint: 20 / 72, unitLabel: 'ft', precision: 1);
    return c;
  }

  group('takeoff measurement kinds via the controller', () {
    test('volume stamps area × depth', () {
      final editing = scaled();
      addTearDown(editing.dispose);
      editing.addMeasurement(0, PdfMeasurementKind.volume,
          const [(0, 0), (72, 0), (72, 72), (0, 72)],
          depth: 2);
      final annot = editing.document.page(0).annotations.single;
      expect(annot.measurementKind, PdfMeasurementKind.volume);
      expect(annot.measurementText, '800 ft³');
    });

    test('count marker needs no scale and tallies', () {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      expect(editing.hasMeasurementScale, isFalse);
      editing.addCountMark(0, (10, 10), label: 'Doors');
      editing.addCountMark(0, (20, 20), label: 'Doors');
      final summary = editing.takeoffSummary;
      final doors = summary.groups.firstWhere((g) => g.label == 'Doors');
      expect(doors.kind, PdfMeasurementKind.count);
      expect(doors.count, 2);
      expect(summary.totalCount, 2);
    });

    test('live readouts cover the new kinds', () {
      final editing = scaled();
      addTearDown(editing.dispose);
      expect(editing.measuredAngle(const [(100, 100), (0, 100), (0, 200)]),
          '90 °');
      expect(editing.measuredSlope((0, 0), (100, 100)), '45 °');
      expect(
          editing.measuredVolume(
              const [(0, 0), (72, 0), (72, 72), (0, 72)], 2),
          '800 ft³');
      expect(
          editing.measuredNetArea(
              const [(0, 0), (72, 0), (72, 72), (0, 72)],
              const [
                [(18, 18), (54, 18), (54, 54), (18, 54)],
              ]),
          '300 ft²');
    });
  });

  group('running totals', () {
    test('groups by label and sums', () {
      final editing = scaled();
      addTearDown(editing.dispose);
      editing.addMeasurement(0, PdfMeasurementKind.area,
          const [(0, 0), (72, 0), (72, 72), (0, 72)],
          label: 'Slab');
      editing.addMeasurement(0, PdfMeasurementKind.area,
          const [(0, 0), (36, 0), (36, 36), (0, 36)],
          label: 'Slab');
      final summary = editing.takeoffSummary;
      final slab = summary.groups.firstWhere((g) => g.label == 'Slab');
      expect(slab.count, 2);
      expect(slab.total, closeTo(500, 0.5));
    });

    test('the existing Bluebeam count tool feeds the running total', () {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      editing.tool = PdfEditTool.count;
      editing.placeCheckMark(0, 30, 30);
      editing.placeCheckMark(0, 40, 40);
      expect(editing.takeoffSummary.totalCount, 2);
    });
  });

  group('document-borne scale', () {
    test('persistScaleToDocument round-trips through a reopen', () {
      final editing = scaled();
      addTearDown(editing.dispose);
      editing.persistScaleToDocument();
      final bytes = editing.bytes;

      // a fresh session with no preference adopts the document's scale.
      final reopened = PdfEditingController(bytes);
      addTearDown(reopened.dispose);
      expect(reopened.hasMeasurementScale, isFalse);
      expect(reopened.adoptDocumentScale(), isTrue);
      expect(reopened.measurementScale!.unitLabel, 'ft');
      expect(reopened.measuredDistance((100, 100), (316, 100)), '60 ft');
    });
  });

  group('PdfTakeoffPanel', () {
    testWidgets('lists groups and totals', (tester) async {
      final editing = scaled();
      addTearDown(editing.dispose);
      editing.addMeasurement(0, PdfMeasurementKind.area,
          const [(0, 0), (72, 0), (72, 72), (0, 72)],
          label: 'Slab');
      editing.addCountMark(0, (10, 10), label: 'Doors');

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PdfTakeoffPanel(controller: editing),
          ),
        ),
      ));
      await tester.pump();

      expect(find.text('Slab'), findsOneWidget);
      expect(find.text('Doors'), findsOneWidget);
      expect(find.text('400 ft²'), findsOneWidget);
    });
  });
}
