import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

void main() {
  // 1 in = 20 ft at 72 pt/in → 20/72 ft per point.
  PdfMeasure ftScale({int precision = 1}) =>
      PdfMeasure.scale(unitsPerPoint: 20 / 72, unitLabel: 'ft', precision: precision);

  PdfDocument edited(void Function(PdfEditor) edit) {
    final editor = PdfEditor(PdfDocument.open(buildClassicPdf()));
    edit(editor);
    return PdfDocument.open(editor.save());
  }

  group('takeoff geometry', () {
    test('polyline length sums the segments', () {
      expect(pdfPolylineLength(const [(0, 0), (3, 4), (3, 4 + 5)]),
          closeTo(5 + 5, 1e-9));
    });

    test('net polygon area subtracts holes and clamps at zero', () {
      final outer = [(0.0, 0.0), (10.0, 0.0), (10.0, 10.0), (0.0, 10.0)];
      final hole = [(2.0, 2.0), (4.0, 2.0), (4.0, 4.0), (2.0, 4.0)];
      expect(pdfNetPolygonArea(outer, [hole]), closeTo(100 - 4, 1e-9));
      // a hole bigger than the boundary clamps to 0, not negative.
      final big = [(-1.0, -1.0), (11.0, -1.0), (11.0, 11.0), (-1.0, 11.0)];
      expect(pdfNetPolygonArea(outer, [big]), 0);
    });

    test('angle between arms is computed at the vertex', () {
      // vertex at origin, arms along +x and +y → 90°.
      expect(pdfAngleDegrees((0, 0), (1, 0), (0, 1)), closeTo(90, 1e-9));
      // a straight line through the vertex → 180°.
      expect(pdfAngleDegrees((0, 0), (-1, 0), (1, 0)), closeTo(180, 1e-9));
    });

    test('slope is the inclination above horizontal', () {
      expect(pdfSlopeDegrees((0, 0), (1, 0)), closeTo(0, 1e-9));
      expect(pdfSlopeDegrees((0, 0), (1, 1)), closeTo(45, 1e-9));
      expect(pdfSlopeDegrees((0, 0), (0, 1)), closeTo(90, 1e-9));
    });

    test('arc metrics of a half circle', () {
      // a semicircle of radius 1: (-1,0) → (0,1) → (1,0).
      final m = pdfArcMetrics((-1, 0), (0, 1), (1, 0))!;
      expect(m.radius, closeTo(1, 1e-9));
      expect(m.sweep, closeTo(180, 1e-6));
      expect(m.length, closeTo(3.14159265, 1e-5));
    });

    test('arc metrics return null for collinear points', () {
      expect(pdfArcMetrics((0, 0), (1, 0), (2, 0)), isNull);
    });
  });

  group('PdfMeasure formatting', () {
    test('formatVolume multiplies area by depth', () {
      final m = ftScale();
      // a 1in×1in square = 72pt×72pt → 20ft×20ft = 400 ft²; depth 2 ft → 800.
      final area = pdfShoelaceArea(const [(0, 0), (72, 0), (72, 72), (0, 72)]);
      expect(m.formatVolume(area, 2), '800 ft³');
    });

    test('formatAngle defaults to degrees', () {
      final m = ftScale();
      expect(m.formatAngle(90), '90 °');
    });

    test('volume formats round-trip through /Measure (custom /V key)', () {
      final m = ftScale();
      final doc = PdfDocument.open(buildClassicPdf());
      final parsed = PdfMeasure.fromDict(doc, m.toCosDictionary())!;
      expect(parsed.volume, isNotNull);
      expect(parsed.volume!.first.unit, 'ft³');
      expect(parsed.angle!.first.unit, '°');
    });
  });

  group('addMeasurement takeoff kinds', () {
    test('count marker carries /Takeoff and reports a value of 1', () {
      final doc = edited((e) {
        e.addMeasurement(0, PdfMeasurementKind.count, const [(100, 100)],
            label: 'Doors');
      });
      final annot = doc.page(0).annotations.single;
      expect(annot.measurementKind, PdfMeasurementKind.count);
      expect(annot.takeoff?.label, 'Doors');
      final result = annot.measurementResult!;
      expect(result.value, 1);
      expect(result.count, 1);
    });

    test('volume = area × depth, stored and recomputed on reopen', () {
      final doc = edited((e) {
        e.setMeasurementScale(1 / 72, 'ft', 20, precision: 1);
        e.addMeasurement(0, PdfMeasurementKind.volume,
            const [(0, 0), (72, 0), (72, 72), (0, 72)],
            depth: 2);
      });
      final annot = doc.page(0).annotations.single;
      expect(annot.subtype, 'Polygon');
      expect(annot.measurementKind, PdfMeasurementKind.volume);
      expect(annot.takeoff?.depth, 2);
      // 400 ft² × 2 ft = 800 ft³.
      expect(annot.measurementText, '800 ft³');
      expect(annot.measurementResult!.value, closeTo(800, 0.1));
    });

    test('angle measurement reports the interior angle', () {
      final doc = edited((e) {
        e.setMeasurementScale(1 / 72, 'ft', 20, precision: 1);
        e.addMeasurement(0, PdfMeasurementKind.angle,
            const [(100, 100), (0, 100), (0, 200)]);
      });
      final annot = doc.page(0).annotations.single;
      expect(annot.subtype, 'PolyLine');
      expect(annot.measurementResult!.value, closeTo(90, 1e-6));
      expect(annot.measurementText, '90 °');
    });

    test('slope measurement reports inclination', () {
      final doc = edited((e) {
        e.setMeasurementScale(1 / 72, 'ft', 20, precision: 1);
        e.addMeasurement(
            0, PdfMeasurementKind.slope, const [(0, 0), (100, 100)]);
      });
      final annot = doc.page(0).annotations.single;
      expect(annot.subtype, 'Line');
      expect(annot.measurementResult!.value, closeTo(45, 1e-6));
    });

    test('arc measurement reports the swept length', () {
      final doc = edited((e) {
        e.setMeasurementScale(1 / 72, 'ft', 1, precision: 100);
        // semicircle radius 72pt = 1in = 1ft; length = π ft ≈ 3.14.
        e.addMeasurement(0, PdfMeasurementKind.arc,
            const [(-72, 0), (0, 72), (72, 0)]);
      });
      final annot = doc.page(0).annotations.single;
      expect(annot.measurementKind, PdfMeasurementKind.arc);
      expect(annot.measurementResult!.value, closeTo(3.14159, 1e-3));
    });

    test('area cutout reports net area and round-trips holes', () {
      final doc = edited((e) {
        e.setMeasurementScale(1 / 72, 'ft', 20, precision: 1);
        e.addMeasurement(0, PdfMeasurementKind.areaCutout,
            const [(0, 0), (72, 0), (72, 72), (0, 72)],
            holes: const [
              [(18, 18), (54, 18), (54, 54), (18, 54)],
            ]);
      });
      final annot = doc.page(0).annotations.single;
      expect(annot.measurementKind, PdfMeasurementKind.areaCutout);
      expect(annot.takeoff?.holes.length, 1);
      // outer 400 ft²; hole is half-inch square = 36pt×36pt → 10ft×10ft = 100.
      expect(annot.measurementText, '300 ft²');
    });

    test('count needs no scale', () {
      final editor = PdfEditor(PdfDocument.open(buildClassicPdf()));
      expect(
          () => editor.addMeasurement(
              0, PdfMeasurementKind.count, const [(0, 0)]),
          returnsNormally);
    });
  });

  group('PdfTakeoffSummary running totals', () {
    test('buckets by label and sums per kind', () {
      final doc = edited((e) {
        e.setMeasurementScale(1 / 72, 'ft', 20, precision: 1);
        // two areas labelled Slab, one labelled Roof.
        e.addMeasurement(0, PdfMeasurementKind.area,
            const [(0, 0), (72, 0), (72, 72), (0, 72)],
            label: 'Slab'); // 400 ft²
        e.addMeasurement(0, PdfMeasurementKind.area,
            const [(0, 0), (36, 0), (36, 36), (0, 36)],
            label: 'Slab'); // 100 ft²
        e.addMeasurement(0, PdfMeasurementKind.area,
            const [(0, 0), (72, 0), (72, 36), (0, 36)],
            label: 'Roof'); // 200 ft²
        // three door counts.
        for (var i = 0; i < 3; i++) {
          e.addMeasurement(0, PdfMeasurementKind.count, [(10.0 * i, 10)],
              label: 'Doors');
        }
      });
      final summary = PdfTakeoffSummary.of(doc);
      final slab =
          summary.groups.firstWhere((g) => g.label == 'Slab');
      expect(slab.count, 2);
      expect(slab.total, closeTo(500, 0.1));
      final roof = summary.groups.firstWhere((g) => g.label == 'Roof');
      expect(roof.total, closeTo(200, 0.1));
      final doors = summary.groups.firstWhere((g) => g.label == 'Doors');
      expect(doors.kind, PdfMeasurementKind.count);
      expect(doors.count, 3);
      expect(doors.formattedTotal(), '3');

      expect(summary.totalArea, closeTo(700, 0.2));
      expect(summary.totalCount, 3);
    });

    test('formattedTotal renders area through the measure unit', () {
      final doc = edited((e) {
        e.setMeasurementScale(1 / 72, 'ft', 20, precision: 1);
        e.addMeasurement(0, PdfMeasurementKind.area,
            const [(0, 0), (72, 0), (72, 72), (0, 72)],
            label: 'Slab');
      });
      final summary = PdfTakeoffSummary.of(doc);
      final slab = summary.groups.single;
      expect(slab.formattedTotal(doc.page(0).annotations.single.measure),
          '400 ft²');
    });
  });

  group('document-borne scale (/VP viewport)', () {
    test('setPageMeasurementScale persists and reopens', () {
      final m = ftScale();
      final editor = PdfEditor(PdfDocument.open(buildClassicPdf()));
      editor.setPageMeasurementScale(0, m);
      final doc = PdfDocument.open(editor.save());
      final reopened = doc.page(0).measure;
      expect(reopened, isNotNull);
      expect(reopened!.scaleFactor, closeTo(20 / 72, 1e-3));
      expect(reopened.formatDistance(216), '60 ft');
    });

    test('a second call replaces the measurement viewport, not appends', () {
      final editor = PdfEditor(PdfDocument.open(buildClassicPdf()));
      editor.setPageMeasurementScale(0, ftScale());
      editor.setPageMeasurementScale(
          0, PdfMeasure.scale(unitsPerPoint: 1 / 72, unitLabel: 'in'));
      final doc = PdfDocument.open(editor.save());
      expect(doc.page(0).measure!.distance.first.unit, 'in');
    });
  });
}
