import 'dart:convert';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

void main() {
  PdfDocument edited(void Function(PdfEditor) edit) {
    final editor = PdfEditor(PdfDocument.open(buildClassicPdf()));
    edit(editor);
    return PdfDocument.open(editor.save());
  }

  String appearance(PdfDocument doc, PdfAnnotation annot) =>
      latin1.decode(doc.cos.decodeStreamData(annot.normalAppearance!));

  group('pdfParseMeasurementValue', () {
    test('reads a leading number and the unit after it', () {
      expect(pdfParseMeasurementValue('12.5 ft'), (12.5, 'ft'));
      expect(pdfParseMeasurementValue(' 3m '), (3.0, 'm'));
      expect(pdfParseMeasurementValue('1,250.5 mm'), (1250.5, 'mm'));
      expect(pdfParseMeasurementValue('1,5 m'), (1.5, 'm'));
      expect(pdfParseMeasurementValue('42'), (42.0, ''));
    });

    test('reads feet-and-inches as decimal feet', () {
      expect(pdfParseMeasurementValue('12\'-6"'), (12.5, 'ft'));
      expect(pdfParseMeasurementValue('3\' 3"'), (3.25, 'ft'));
    });

    test('text with no number keeps the whole text as its unit', () {
      expect(pdfParseMeasurementValue('TYP.'), (null, 'TYP.'));
    });
  });

  group('written measurement values', () {
    test('a distance with a written value needs no scale', () {
      final doc = edited((e) {
        e.addMeasurement(
            0, PdfMeasurementKind.distance, const [(100, 100), (300, 100)],
            valueText: '12\'-6"');
      });
      final annot = doc.page(0).annotations.single;
      expect(annot.subtype, 'Line');
      expect(annot.measure, isNull);
      expect(annot.measurementKind, PdfMeasurementKind.distance);
      expect(annot.takeoff?.valueText, '12\'-6"');
      expect(annot.contents, '12\'-6"');
      expect(annot.measurementText, '12\'-6"');
      final result = annot.measurementResult!;
      expect(result.isCustom, isTrue);
      expect(result.value, 12.5);
      expect(result.unit, 'ft');
      expect(appearance(doc, annot), contains('12\'-6"'));
    });

    test('a written value overrides the computed one under a scale', () {
      final doc = edited((e) {
        e.setMeasurementScale(1 / 72, 'ft', 20, precision: 1);
        // 72pt = 1 in = 20 ft, but the drawing says 21
        e.addMeasurement(
            0, PdfMeasurementKind.distance, const [(0, 0), (72, 0)],
            valueText: '21');
      });
      final annot = doc.page(0).annotations.single;
      expect(annot.measure, isNotNull);
      expect(annot.measurementText, '21');
      // a bare number takes the scale's unit
      expect(annot.measurementResult!.unit, 'ft');
      expect(annot.measurementResult!.value, 21);
      expect(appearance(doc, annot), isNot(contains('20 ft')));
    });

    test('an area takeoff with a written value totals by its number', () {
      final doc = edited((e) {
        for (final v in ['10 m²', '15.5 m²']) {
          e.addMeasurement(
              0, PdfMeasurementKind.area, const [(0, 0), (50, 0), (50, 50)],
              valueText: v);
        }
      });
      final group = PdfTakeoffSummary.of(doc).groups.single;
      expect(group.kind, PdfMeasurementKind.area);
      expect(group.unit, 'm²');
      expect(group.count, 2);
      expect(group.total, closeTo(25.5, 1e-9));
    });

    test('a blank written value is no value', () {
      expect(
        () => edited((e) => e.addMeasurement(
            0, PdfMeasurementKind.distance, const [(0, 0), (72, 0)],
            valueText: '  ')),
        throwsStateError,
      );
    });

    test('reshaping keeps the written value', () {
      final editor = PdfEditor(PdfDocument.open(buildClassicPdf()));
      editor.addMeasurement(
          0, PdfMeasurementKind.distance, const [(100, 100), (300, 100)],
          valueText: '5 m');
      final annot = editor.document.page(0).annotations.single;
      editor.reshapeLineAnnotation(0, annot, const [(100, 100), (400, 200)]);
      final doc = PdfDocument.open(editor.save());
      final out = doc.page(0).annotations.single;
      expect(out.measurementText, '5 m');
      expect(appearance(doc, out), contains('5 m'));
    });
  });

  group('setMeasurementValue', () {
    test('writes, rewrites and clears the value of a scaled measurement', () {
      final editor = PdfEditor(PdfDocument.open(buildClassicPdf()));
      editor.setMeasurementScale(1 / 72, 'ft', 20, precision: 1);
      editor.addMeasurement(
          0, PdfMeasurementKind.distance, const [(0, 0), (72, 0)]);
      PdfAnnotation annot() => editor.document.page(0).annotations.single;
      expect(annot().takeoff, isNull);
      expect(annot().measurementText, '20 ft');

      expect(editor.setMeasurementValue(0, annot(), '20\'-3"'), isTrue);
      expect(annot().measurementText, '20\'-3"');
      expect(annot().contents, '20\'-3"');
      expect(editor.setMeasurementValue(0, annot(), '20\'-3"'), isFalse);

      // clearing returns to the computed value and drops the /Takeoff a
      // classic distance doesn't need
      expect(editor.setMeasurementValue(0, annot(), ''), isTrue);
      expect(annot().takeoff, isNull);
      expect(annot().contents, '20 ft');

      final doc = PdfDocument.open(editor.save());
      final out = doc.page(0).annotations.single;
      expect(out.measurementText, '20 ft');
      expect(appearance(doc, out), contains('20 ft'));
    });

    test('keeps the takeoff record of a non-classic kind', () {
      final editor = PdfEditor(PdfDocument.open(buildClassicPdf()));
      editor.setMeasurementScale(1 / 72, 'ft', 20, precision: 1);
      editor.addMeasurement(0, PdfMeasurementKind.volume,
          const [(0, 0), (72, 0), (72, 72), (0, 72)],
          depth: 2, label: 'Slab');
      PdfAnnotation annot() => editor.document.page(0).annotations.single;
      expect(editor.setMeasurementValue(0, annot(), '750 ft³'), isTrue);
      expect(annot().takeoff?.depth, 2);
      expect(annot().takeoff?.label, 'Slab');
      expect(annot().measurementResult!.value, 750);
      expect(editor.setMeasurementValue(0, annot(), null), isTrue);
      expect(annot().takeoff?.kind, PdfMeasurementKind.volume);
      expect(annot().measurementText, '800 ft³');
    });

    test('refuses to clear a value with no scale behind it', () {
      final editor = PdfEditor(PdfDocument.open(buildClassicPdf()));
      editor.addMeasurement(
          0, PdfMeasurementKind.distance, const [(0, 0), (72, 0)],
          valueText: '3 m');
      final annot = editor.document.page(0).annotations.single;
      expect(editor.setMeasurementValue(0, annot, null), isFalse);
      expect(annot.measurementText, '3 m');
    });

    test('refuses a non-measurement and a count marker', () {
      final editor = PdfEditor(PdfDocument.open(buildClassicPdf()));
      editor.addLine(0, (0, 0), (72, 0));
      editor.addMeasurement(0, PdfMeasurementKind.count, const [(10, 10)]);
      final annots = editor.document.page(0).annotations;
      expect(editor.setMeasurementValue(0, annots[0], '3 m'), isFalse);
      expect(editor.setMeasurementValue(0, annots[1], '3'), isFalse);
    });
  });
}
