import 'dart:convert';
import 'dart:io';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

void main() {
  group('PdfNumberFormat', () {
    test('decimal format applies the conversion factor and unit label', () {
      // 1 in = 20 ft, drawn at 72 pt/in: a 3 in (216 pt) segment is 60 ft.
      const ft = PdfNumberFormat(unit: 'ft', conversion: 20 / 72, precision: 1);
      expect(ft.format(216), '60 ft');
    });

    test('strips trailing zeros but keeps significant decimals', () {
      const m = PdfNumberFormat(unit: 'm', precision: 100);
      expect(m.format(60), '60 m');
      expect(m.format(60.5), '60.5 m');
      expect(m.format(60.25), '60.25 m');
      // nearest hundredth
      expect(m.format(60.255), '60.26 m');
    });

    test('thousands separator groups the integer part', () {
      const m = PdfNumberFormat(unit: 'mm', precision: 1);
      expect(m.format(1234567), '1,234,567 mm');
    });

    test('prefix-position label and custom separators', () {
      const m = PdfNumberFormat(
        unit: '\$',
        precision: 100,
        labelPosition: 'P',
        decimalSeparator: ',',
        thousandsSeparator: '.',
      );
      expect(m.format(1234.5), '\$ 1.234,5');
    });

    test('fraction format reduces to lowest terms', () {
      const inch = PdfNumberFormat(unit: 'in', fractionFormat: 'F', precision: 16);
      expect(inch.format(2.5), '2 1/2 in');
      expect(inch.format(2.0625), '2 1/16 in');
      expect(inch.format(0.75), '3/4 in');
    });

    test('truncate format rounds toward zero', () {
      const m = PdfNumberFormat(unit: 'm', fractionFormat: 'T', precision: 1);
      expect(m.format(60.9), '60 m');
    });

    test('round-trips through a COS dictionary', () {
      const original = PdfNumberFormat(
        unit: 'ft',
        conversion: 0.5,
        precision: 10,
        fractionFormat: 'D',
        labelPosition: 'S',
        prefix: '~',
        suffix: '.',
      );
      final dict = original.toCosDictionary();
      final doc = PdfDocument.open(buildClassicPdf());
      final parsed = PdfNumberFormat.fromDict(doc, dict)!;
      expect(parsed.unit, 'ft');
      expect(parsed.conversion, closeTo(0.5, 1e-9));
      expect(parsed.precision, 10);
      expect(parsed.prefix, '~');
      expect(parsed.suffix, '.');
      expect(parsed.format(4), original.format(4));
    });
  });

  group('PdfMeasure', () {
    test('scale factor converts a distance through /X then /D', () {
      final m = PdfMeasure.scale(unitsPerPoint: 20 / 72, unitLabel: 'ft');
      expect(m.scaleFactor, closeTo(20 / 72, 1e-9));
      // a 3 in (216 pt) segment
      expect(m.formatDistance(216), '60 ft');
    });

    test('area scales by the factor squared (shoelace)', () {
      final m = PdfMeasure.scale(unitsPerPoint: 20 / 72, unitLabel: 'ft');
      // a 1 in × 1 in square = 72 pt × 72 pt → 20 ft × 20 ft = 400 ft²
      final area = pdfShoelaceArea(
          const [(0, 0), (72, 0), (72, 72), (0, 72)]);
      expect(area, closeTo(5184, 1e-6));
      expect(m.formatArea(area), '400 ft²');
    });

    test('shoelace ignores winding direction', () {
      final cw = pdfShoelaceArea(const [(0, 0), (0, 10), (10, 10), (10, 0)]);
      final ccw = pdfShoelaceArea(const [(0, 0), (10, 0), (10, 10), (0, 10)]);
      expect(cw, closeTo(100, 1e-9));
      expect(ccw, closeTo(100, 1e-9));
    });

    test('round-trips through a /Measure dictionary', () {
      final m = PdfMeasure.scale(
          unitsPerPoint: 20 / 72, unitLabel: 'ft', ratioLabel: '1 in = 20 ft');
      final doc = PdfDocument.open(buildClassicPdf());
      final parsed = PdfMeasure.fromDict(doc, m.toCosDictionary())!;
      expect(parsed.ratio, '1 in = 20 ft');
      expect(parsed.subtype, 'RL');
      expect(parsed.scaleFactor, closeTo(20 / 72, 1e-9));
      expect(parsed.formatDistance(216), '60 ft');
      expect(parsed.area.first.unit, 'ft²');
    });
  });

  group('addMeasurement', () {
    String appearanceText(PdfDocument doc, PdfAnnotation annot) {
      final stream = annot.normalAppearance!;
      return latin1.decode(doc.cos.decodeStreamData(stream));
    }

    PdfDocument measured(void Function(PdfEditor) edit) {
      final editor = PdfEditor(PdfDocument.open(buildClassicPdf()));
      edit(editor);
      return PdfDocument.open(editor.save());
    }

    test('distance line carries /Measure, /Contents and a caption', () {
      final doc = measured((e) {
        e.setMeasurementScale(1 / 72, 'ft', 20);
        e.addMeasurement(
            0, PdfMeasurementKind.distance, const [(100, 100), (316, 100)]);
      });
      final annot = doc.page(0).annotations.single;
      expect(annot.subtype, 'Line');
      expect(annot.measure, isNotNull);
      // 316 - 100 = 216 pt = 3 in = 60 ft
      expect(annot.measurementText, '60 ft');
      expect(annot.contents, '60 ft');
      expect((doc.cos.resolve(annot.dict['IT']) as CosName).value,
          'LineDimension');
      // the caption text is drawn in the appearance stream
      expect(appearanceText(doc, annot), contains('(60 ft)'));
    });

    test('perimeter polyline sums the segment lengths', () {
      final doc = measured((e) {
        e.setMeasurementScale(1 / 72, 'ft', 20);
        e.addMeasurement(0, PdfMeasurementKind.perimeter,
            const [(100, 100), (172, 100), (172, 172)]);
      });
      final annot = doc.page(0).annotations.single;
      expect(annot.subtype, 'PolyLine');
      // 72 + 72 = 144 pt = 2 in = 40 ft
      expect(annot.measurementText, '40 ft');
    });

    test('area polygon uses the shoelace area', () {
      final doc = measured((e) {
        e.setMeasurementScale(1 / 72, 'ft', 20);
        e.addMeasurement(0, PdfMeasurementKind.area,
            const [(0, 0), (72, 0), (72, 72), (0, 72)]);
      });
      final annot = doc.page(0).annotations.single;
      expect(annot.subtype, 'Polygon');
      expect(annot.measurementText, '400 ft²');
    });

    test('per-annotation measure overrides the document default', () {
      final doc = measured((e) {
        e.setMeasurementScale(1 / 72, 'ft', 20);
        e.addMeasurement(
          0,
          PdfMeasurementKind.distance,
          const [(0, 0), (72, 0)],
          measure: PdfMeasure.scale(unitsPerPoint: 1 / 72, unitLabel: 'in'),
        );
      });
      final annot = doc.page(0).annotations.single;
      // 72 pt = 1 in under the override, not feet
      expect(annot.measurementText, '1 in');
    });

    test('throws without any scale', () {
      final editor = PdfEditor(PdfDocument.open(buildClassicPdf()));
      expect(
          () => editor.addMeasurement(
              0, PdfMeasurementKind.distance, const [(0, 0), (10, 0)]),
          throwsStateError);
    });
  });

  // An optional integration check against a real CAD drawing (the corpus
  // is git-ignored). Provide PDF_PATH plus a known scale and segment:
  //
  //   PDF_PATH=../../corpus/site-plan.pdf \
  //   PDF_MEASURE_PER_POINT=0.27778 PDF_MEASURE_UNIT=ft \
  //   PDF_MEASURE_SEG="100,100,316,100" PDF_MEASURE_EXPECT="60 ft" \
  //   fvm dart test test/measure_test.dart
  final corpusPath = Platform.environment['PDF_PATH'];
  group('corpus measurement', () {
    test('measures a known dimension on a real drawing', () {
      final page = int.tryParse(Platform.environment['PDF_PAGE'] ?? '0') ?? 0;
      final perPoint =
          double.parse(Platform.environment['PDF_MEASURE_PER_POINT']!);
      final unit = Platform.environment['PDF_MEASURE_UNIT'] ?? 'unit';
      final seg = Platform.environment['PDF_MEASURE_SEG']!
          .split(',')
          .map(double.parse)
          .toList();
      final editor = PdfEditor(PdfDocument.open(File(corpusPath!).readAsBytesSync()));
      editor.setMeasurementScale(perPoint, unit, 1);
      editor.addMeasurement(page, PdfMeasurementKind.distance,
          [(seg[0], seg[1]), (seg[2], seg[3])]);
      final doc = PdfDocument.open(editor.save());
      final text = doc.page(page).annotations.last.measurementText;
      // ignore: avoid_print
      print('measured: $text');
      final expected = Platform.environment['PDF_MEASURE_EXPECT'];
      if (expected != null) expect(text, expected);
    }, skip: corpusPath == null ? 'set PDF_PATH to run' : false);
  });
}
