import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/editing/editing_tool_behavior.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

/// The `PdfEditToolBehavior` interface is the tool-logic test surface: rather
/// than pumping a `PdfViewer` and simulating raw pointer streams, these feed a
/// behaviour a `PdfEditingController` (and, for the commit hooks, page-space
/// geometry) and assert what it reports and emits.
void main() {
  group('registry', () {
    test('every PdfEditTool has exactly one behaviour, keyed by itself', () {
      for (final tool in PdfEditTool.values) {
        final behavior = PdfEditToolBehavior.of(tool);
        expect(behavior.tool, tool, reason: '$tool maps to a mismatched row');
      }
    });

    test('maybeOf is null for no armed tool', () {
      expect(PdfEditToolBehavior.maybeOf(null), isNull);
      expect(PdfEditToolBehavior.maybeOf(PdfEditTool.ink), isNotNull);
    });
  });

  group('classification', () {
    Set<PdfEditTool> toolsWhere(bool Function(PdfEditToolBehavior) test) => {
          for (final tool in PdfEditTool.values)
            if (test(PdfEditToolBehavior.of(tool))) tool,
        };

    test('ink family (was _inkTool)', () {
      expect(toolsWhere((b) => b.isInk),
          {PdfEditTool.ink, PdfEditTool.highlight});
    });

    test('draw tools drive the raw pointer (was _drawTool)', () {
      expect(toolsWhere((b) => b.isDraw),
          {PdfEditTool.ink, PdfEditTool.highlight, PdfEditTool.eraser});
    });

    test('ink buffering (was _buffersInk)', () {
      expect(toolsWhere((b) => b.buffersInk),
          {PdfEditTool.ink, PdfEditTool.highlight});
    });

    test('poly tools (was _polyTool - the cloud is deliberately excluded)', () {
      expect(toolsWhere((b) => b.isPoly), {
        PdfEditTool.polyline,
        PdfEditTool.polygon,
        PdfEditTool.measurePerimeter,
        PdfEditTool.measureArea,
        PdfEditTool.measureAngle,
        PdfEditTool.measureArc,
        PdfEditTool.measureVolume,
      });
    });

    test('line-drag tools (was _lineDragTool)', () {
      expect(toolsWhere((b) => b.isLineDrag), {
        PdfEditTool.line,
        PdfEditTool.arrow,
        PdfEditTool.measureDistance,
        PdfEditTool.measureSlope,
        PdfEditTool.calibrate,
      });
    });

    test('measurement kinds (was _measureKind)', () {
      expect(PdfEditToolBehavior.of(PdfEditTool.measureDistance).measureKind,
          PdfMeasurementKind.distance);
      expect(PdfEditToolBehavior.of(PdfEditTool.measureVolume).measureKind,
          PdfMeasurementKind.volume);
      expect(PdfEditToolBehavior.of(PdfEditTool.rectangle).measureKind, isNull);
      expect(PdfEditToolBehavior.of(PdfEditTool.polygon).measureKind, isNull);
    });

    test('fixed poly arity - only angle and arc auto-finish (was '
        '_fixedPolyCount)', () {
      expect(toolsWhere((b) => b.fixedPolyCount != null),
          {PdfEditTool.measureAngle, PdfEditTool.measureArc});
      expect(PdfEditToolBehavior.of(PdfEditTool.measureAngle).fixedPolyCount, 3);
    });
  });

  group('persisted style scope (was the controller tables)', () {
    test('scope keys - styled tools name a slot, the rest are null', () {
      expect(PdfEditToolBehavior.of(PdfEditTool.ink).styleScopeKey, 'ink');
      expect(PdfEditToolBehavior.of(PdfEditTool.highlight).styleScopeKey,
          'freehandHighlight');
      expect(PdfEditToolBehavior.of(PdfEditTool.rectangle).styleScopeKey,
          'rectangle');
      expect(
          PdfEditToolBehavior.of(PdfEditTool.measureArc).styleScopeKey,
          'measureArc');
      for (final tool in [
        PdfEditTool.select,
        PdfEditTool.content,
        PdfEditTool.form,
        PdfEditTool.redact,
        PdfEditTool.signature,
        PdfEditTool.image,
        PdfEditTool.snapshot,
        PdfEditTool.calibrate,
      ]) {
        expect(PdfEditToolBehavior.of(tool).styleScopeKey, isNull,
            reason: '$tool creates nothing styled');
      }
    });

    test('scope fields drive toolUsesColor', () {
      expect(PdfEditToolBehavior.of(PdfEditTool.rectangle).usesColor, isTrue);
      expect(PdfEditToolBehavior.of(PdfEditTool.eraser).usesColor, isFalse);
      expect(PdfEditToolBehavior.of(PdfEditTool.rectangle).styleScopeFields,
          contains('cornerRadius'));
      expect(PdfEditToolBehavior.of(PdfEditTool.ellipse).styleScopeFields,
          isNot(contains('cornerRadius')));
    });

    test('the freehand highlighter seeds its broad translucent yellow', () {
      expect(PdfEditToolBehavior.of(PdfEditTool.highlight).styleScopeDefaults, {
        'color': 0xFFFFD100,
        'strokeWidth': 12.0,
        'opacity': 0.45,
      });
      expect(PdfEditToolBehavior.of(PdfEditTool.ink).styleScopeDefaults, isEmpty);
    });

    test('the controller reads the behaviour for toolUsesColor', () {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      editing.tool = PdfEditTool.rectangle;
      expect(editing.toolUsesColor, isTrue);
      editing.tool = PdfEditTool.eraser;
      expect(editing.toolUsesColor, isFalse);
    });
  });

  group('tune-popup style fields (was the toolbar mirror)', () {
    test('a rectangle offers a corner-radius slider, not a font', () {
      final fields = PdfEditToolBehavior.of(PdfEditTool.rectangle).styleFields;
      expect(fields.cornerRadius, isTrue);
      expect(fields.shapeFill, isTrue);
      expect(fields.font, isFalse);
    });

    test('only the line and polyline shapes carry endings', () {
      expect(PdfEditToolBehavior.of(PdfEditTool.line).styleFields.lineEndings,
          isTrue);
      expect(
          PdfEditToolBehavior.of(PdfEditTool.polyline).styleFields.lineEndings,
          isTrue);
      expect(PdfEditToolBehavior.of(PdfEditTool.arrow).styleFields.lineEndings,
          isFalse);
      expect(PdfEditToolBehavior.of(PdfEditTool.polygon).styleFields.lineEndings,
          isFalse);
    });

    test('the eraser popup replaces everything with its radius', () {
      final fields = PdfEditToolBehavior.of(PdfEditTool.eraser).styleFields;
      expect(fields.eraser, isTrue);
      expect(fields.stroke, isFalse);
      expect(fields.opacity, isFalse);
    });

    test('select and the edit tools expose no tune popup', () {
      for (final tool in [
        PdfEditTool.select,
        PdfEditTool.content,
        PdfEditTool.form,
        PdfEditTool.redact,
        PdfEditTool.snapshot,
      ]) {
        expect(PdfEditToolBehavior.of(tool).styleFields.isEmpty, isTrue,
            reason: '$tool should carry no tune controls');
      }
    });
  });

  group('measurement scale', () {
    test('the controller forwards measurementScale to its preferences', () {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);

      // Reads through to preferences (unset by default).
      expect(editing.measurementScale, isNull);
      expect(editing.hasMeasurementScale, isFalse);

      final scale = PdfMeasurementScale(unitsPerPoint: 20 / 72, unitLabel: 'ft');
      editing.measurementScale = scale;

      // Writes through, and the getter reflects it.
      expect(editing.measurementScale, same(scale));
      expect(editing.preferences.measurementScale, same(scale));
      expect(editing.hasMeasurementScale, isTrue);
    });
  });

  group('commit hooks emit annotations', () {
    PdfEditingController controller() {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      return editing;
    }

    test('the shape family stamps a Square / Circle / Polygon', () {
      for (final (tool, subtype) in [
        (PdfEditTool.rectangle, 'Square'),
        (PdfEditTool.ellipse, 'Circle'),
        (PdfEditTool.cloudPolygon, 'Polygon'),
      ]) {
        final editing = controller();
        final consumed = PdfEditToolBehavior.of(tool).commitShapeRect(
            editing, 0, PdfRect(100, 100, 300, 260));
        expect(consumed, isTrue, reason: '$tool should consume the drag');
        expect(editing.document.page(0).annotations.single.subtype, subtype);
      }
    });

    test('the line family stamps a /Line, arrowed only for the arrow tool', () {
      final line = controller();
      PdfEditToolBehavior.of(PdfEditTool.line)
          .commitLineDrag(line, 0, (100, 100), (300, 100));
      final lineAnnot = line.document.page(0).annotations.single;
      expect(lineAnnot.subtype, 'Line');
      expect(pdfLineEndings(lineAnnot)?.$2, isNot(PdfLineEnding.closedArrow));

      final arrow = controller();
      PdfEditToolBehavior.of(PdfEditTool.arrow)
          .commitLineDrag(arrow, 0, (100, 100), (300, 100));
      final arrowAnnot = arrow.document.page(0).annotations.single;
      expect(arrowAnnot.subtype, 'Line');
      expect(pdfLineEndings(arrowAnnot)?.$2, PdfLineEnding.closedArrow);
    });

    test('the poly family stamps a /PolyLine or /Polygon', () {
      final poly = controller();
      PdfEditToolBehavior.of(PdfEditTool.polyline)
          .commitPoly(poly, 0, const [(100, 100), (200, 140), (300, 100)]);
      expect(poly.document.page(0).annotations.single.subtype, 'PolyLine');

      final closed = controller();
      PdfEditToolBehavior.of(PdfEditTool.polygon)
          .commitPoly(closed, 0, const [(100, 100), (200, 140), (300, 100)]);
      expect(closed.document.page(0).annotations.single.subtype, 'Polygon');
    });

    test('a line-shaped measurement needs a scale and stamps a /Line', () {
      final editing = controller();
      editing.preferences.measurementScale =
          PdfMeasurementScale(unitsPerPoint: 20 / 72, unitLabel: 'ft');
      final consumed = PdfEditToolBehavior.of(PdfEditTool.measureDistance)
          .commitLineDrag(editing, 0, (100, 100), (316, 100));
      expect(consumed, isTrue);
      final annot = editing.document.page(0).annotations.single;
      expect(annot.subtype, 'Line');
      expect(annot.measurementText, '60 ft');
    });

    test('a poly-shaped measurement stamps a takeoff', () {
      final editing = controller();
      editing.preferences.measurementScale =
          PdfMeasurementScale(unitsPerPoint: 20 / 72, unitLabel: 'ft');
      PdfEditToolBehavior.of(PdfEditTool.measurePerimeter)
          .commitPoly(editing, 0, const [(100, 100), (300, 100), (300, 260)]);
      final annot = editing.document.page(0).annotations.single;
      expect(annot.subtype, 'PolyLine');
      expect(annot.measure, isNotNull);
    });

    test('the volume tool declines the synchronous commit (it needs a depth)',
        () {
      final editing = controller();
      editing.preferences.measurementScale =
          PdfMeasurementScale(unitsPerPoint: 20 / 72, unitLabel: 'ft');
      final consumed = PdfEditToolBehavior.of(PdfEditTool.measureVolume)
          .commitPoly(editing, 0, const [(100, 100), (300, 100), (300, 260)]);
      expect(consumed, isFalse);
      expect(editing.document.page(0).annotations, isEmpty);
    });

    test('metadata-only tools do not commit through the hooks', () {
      final editing = controller();
      final note = PdfEditToolBehavior.of(PdfEditTool.note);
      expect(note.commitShapeRect(editing, 0, PdfRect(0, 0, 10, 10)), isFalse);
      expect(note.commitLineDrag(editing, 0, (0, 0), (1, 1)), isFalse);
      expect(note.commitPoly(editing, 0, const [(0, 0), (1, 1)]), isFalse);
      expect(editing.document.page(0).annotations, isEmpty);
    });
  });
}
