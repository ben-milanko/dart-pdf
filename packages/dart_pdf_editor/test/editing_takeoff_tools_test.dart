import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // The viewer fits a 612pt-wide page into an 800px viewport.
  const scale = 800 / 612;
  Offset view(double x, double y) => Offset(x * scale, (792 - y) * scale);

  Future<PdfEditingController> pumpEditor(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final editing = PdfEditingController(buildMultiPagePdf(1))
      ..measurementScale = PdfMeasurementScale(
          unitsPerPoint: 20 / 72, unitLabel: 'ft', precision: 1);
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

  // One discrete mouse click at a view point (a poly vertex).
  Future<void> click(WidgetTester tester, Offset at) async {
    final g = await tester.startGesture(at, kind: PointerDeviceKind.mouse);
    await g.up();
    await tester.pump();
  }

  testWidgets('slope tool drags a /Line slope measurement', (tester) async {
    final editing = await pumpEditor(tester);
    editing.tool = PdfEditTool.measureSlope;
    await tester.pump();

    final from = view(100, 600);
    final to = view(200, 700); // 45° rise/run
    final gesture =
        await tester.startGesture(from, kind: PointerDeviceKind.mouse);
    await tester.pump();
    await gesture.moveTo(to);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    final annot = editing.document.page(0).annotations.single;
    expect(annot.subtype, 'Line');
    expect(annot.measurementKind, PdfMeasurementKind.slope);
    expect(annot.measurementResult!.value, closeTo(45, 1e-6));
  });

  testWidgets('angle tool auto-finishes after three clicks', (tester) async {
    final editing = await pumpEditor(tester);
    editing.tool = PdfEditTool.measureAngle;
    await tester.pump();

    // arms along +x and +y from a vertex at (100,600) → 90°.
    await click(tester, view(200, 600));
    await click(tester, view(100, 600));
    await click(tester, view(100, 700));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    final annot = editing.document.page(0).annotations.single;
    expect(annot.subtype, 'PolyLine');
    expect(annot.measurementKind, PdfMeasurementKind.angle);
    expect(annot.measurementResult!.value, closeTo(90, 1e-6));
    // the tool stays armed (it didn't disarm itself), ready for the next.
    expect(editing.tool, PdfEditTool.measureAngle);
  });

  testWidgets('arc tool measures the swept length after three clicks',
      (tester) async {
    final editing = await pumpEditor(tester);
    editing.measurementScale = PdfMeasurementScale(
        unitsPerPoint: 1 / 72, unitLabel: 'ft', precision: 100);
    editing.tool = PdfEditTool.measureArc;
    await tester.pump();

    // a semicircle radius 72pt = 1ft centred at (100,650): length = π ft.
    await click(tester, view(28, 650)); // -72 from the centre
    await click(tester, view(100, 722)); // top of the arc
    await click(tester, view(172, 650)); // +72
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    final annot = editing.document.page(0).annotations.single;
    expect(annot.measurementKind, PdfMeasurementKind.arc);
    expect(annot.measurementResult!.value, closeTo(3.14159, 1e-2));
  });

  testWidgets('volume tool prompts for depth and stamps area × depth',
      (tester) async {
    final editing = await pumpEditor(tester);
    editing.tool = PdfEditTool.measureVolume;
    await tester.pump();

    // a 1in × 1in footprint (72pt square) → 20ft × 20ft = 400 ft².
    await click(tester, view(400, 500));
    await click(tester, view(472, 500));
    await click(tester, view(472, 572));
    await click(tester, view(400, 572));
    // double-tap the last vertex to finish the polygon.
    final p = view(400, 572);
    await tester.tapAt(p);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(p);
    await tester.pumpAndSettle();

    // the depth dialog appears; enter 2 ft.
    expect(find.byKey(const ValueKey('pdf-depth-value')), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('pdf-depth-value')), '2');
    await tester.tap(find.byKey(const ValueKey('pdf-depth-apply')));
    await tester.pumpAndSettle();

    final annot = editing.document.page(0).annotations.single;
    expect(annot.subtype, 'Polygon');
    expect(annot.measurementKind, PdfMeasurementKind.volume);
    expect(annot.takeoff?.depth, 2);
    expect(annot.measurementText, '800 ft³'); // 400 ft² × 2 ft
  });

  testWidgets('the depth dialog returns the entered value', (tester) async {
    double? captured;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              captured = await showPdfDepthDialog(context, unitLabel: 'ft');
            },
            child: const Text('go'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('pdf-depth-value')), '3.5');
    await tester.tap(find.byKey(const ValueKey('pdf-depth-apply')));
    await tester.pumpAndSettle();
    expect(captured, 3.5);
  });
}
