// Select-tool hit testing for line work: a /PolyLine, an unfilled /Polygon
// and a callout's leader are hit on their strokes, not anywhere inside the
// bounding /Rect, so the empty page inside the box reaches what's behind.

import 'package:flutter/widgets.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main() {
  PdfEditingController controller() {
    final editing = PdfEditingController(buildMultiPagePdf(1));
    addTearDown(editing.dispose);
    return editing;
  }

  test('a polyline is hit on its segments, not its empty bounds', () {
    final editing = controller()
      ..addPolyLine(0, [(100, 100), (200, 200), (300, 100)])
      ..tool = PdfEditTool.select;

    expect(editing.selectableAnnotationAt(0, 150, 150)?.$1, 0);
    expect(editing.selectableAnnotationAt(0, 152, 149)?.$1, 0);
    expect(editing.selectableAnnotationAt(0, 300, 100)?.$1, 0);
    // inside /Rect, far from either segment
    expect(editing.selectableAnnotationAt(0, 200, 110), isNull);
  });

  test('an unfilled polygon is hit on its outline only', () {
    final editing = controller()
      ..addPolygon(0, [(100, 100), (300, 100), (300, 300), (100, 300)])
      ..tool = PdfEditTool.select;

    expect(editing.selectableAnnotationAt(0, 200, 101)?.$1, 0);
    expect(editing.selectableAnnotationAt(0, 300, 200)?.$1, 0);
    expect(editing.selectableAnnotationAt(0, 200, 200), isNull);
  });

  test('a click inside a polyline\'s bounds reaches the shape behind it', () {
    final editing = controller()
      ..addRectangle(0, const PdfRect(180, 105, 220, 125))
      ..addPolyLine(0, [(100, 100), (200, 200), (300, 100)])
      ..tool = PdfEditTool.select;

    expect(editing.selectableAnnotationAt(0, 200, 115)?.$1, 0);
    expect(editing.selectAnnotationAt(0, 200, 115), isTrue);
    expect(editing.selectedAnnotationSlots, [(0, 0)]);
  });

  test('a callout is hit on its box and leader, not the space between', () {
    final editing = controller()
      ..addCallout(0, const PdfRect(300, 300, 400, 340), 'Note', (100, 100))
      ..tool = PdfEditTool.select;
    final callout = editing.document.page(0).annotations.single;
    expect(callout.isCallout, isTrue);
    final box = callout.calloutBox!;
    final leader = callout.calloutLeaders!.single;

    // the box
    expect(
        editing
            .selectableAnnotationAt(
                0, (box.left + box.right) / 2, (box.bottom + box.top) / 2)
            ?.$1,
        0);
    // the arrow tip and the middle of the leader
    expect(editing.selectableAnnotationAt(0, 100, 100)?.$1, 0);
    final (ax, ay) = leader.first;
    final (bx, by) = leader[1];
    expect(
        editing.selectableAnnotationAt(0, (ax + bx) / 2, (ay + by) / 2)?.$1, 0);
    // inside /Rect, well off both
    expect(editing.selectableAnnotationAt(0, 120, 300), isNull);
  });

  test('a polyline arrowhead is part of the stroke', () {
    final plain = controller()
      ..addPolyLine(0, [(100, 100), (200, 100), (300, 100)]);
    final arrow = controller()
      ..preferences.lineEndEnding = PdfLineEnding.closedArrow
      ..addPolyLine(0, [(100, 100), (200, 100), (300, 100)]);

    // beside the tip, past the bare line's reach but on the arrow's barb
    expect(plain.selectableAnnotationAt(0, 296, 108), isNull);
    expect(arrow.selectableAnnotationAt(0, 296, 108)?.$1, 0);
  });

  test('a filled polygon is hit inside as well as on its outline', () {
    final editing = controller()
      ..preferences.shapeFillColor = const Color(0xFF00FF00)
      ..addPolygon(0, [(100, 100), (300, 100), (300, 300), (100, 300)]);

    expect(editing.selectableAnnotationAt(0, 200, 200)?.$1, 0);
    expect(editing.selectableAnnotationAt(0, 200, 101)?.$1, 0);
    expect(editing.selectableAnnotationAt(0, 400, 200), isNull);
  });

  test('a cloudy polygon reaches its scallops but not its middle', () {
    final editing = controller()
      ..addCloudPolygon(0, const PdfRect(100, 100, 300, 300));

    // past the straight edge, where the puffs bulge out
    expect(editing.selectableAnnotationAt(0, 200, 92)?.$1, 0);
    expect(editing.selectableAnnotationAt(0, 200, 200), isNull);
  });

  test('a measurement keeps its /Rect hit so the caption stays clickable', () {
    final editing = controller()
      ..addMeasurement(
          0, PdfMeasurementKind.perimeter, [(100, 100), (200, 200), (300, 100)],
          valueText: '12 m');

    expect(editing.selectableAnnotationAt(0, 200, 110)?.$1, 0);
  });

  test('a cloud callout is hit inside its marked region', () {
    final editing = controller()
      ..addCloudCallout(0, const PdfRect(300, 380, 420, 440),
          const PdfRect(100, 480, 300, 600), 'x');

    expect(editing.selectableAnnotationAt(0, 360, 410)?.$1, 0);
    // inside /Rect, off the note, the leader and the cloud
    expect(editing.selectableAnnotationAt(0, 150, 400), isNull);
  });
}
