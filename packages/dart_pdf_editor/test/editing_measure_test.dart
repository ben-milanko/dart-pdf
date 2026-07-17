import 'dart:convert';

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
      final scale = editing.preferences.measurementScale!;
      expect(scale.unitLabel, 'ft');
      expect(scale.unitsPerPoint, closeTo(60 / 216, 1e-9));
      // 1 in = 72 pt → 72 × (60/216) = 20 ft
      expect(scale.ratioLabel, '1 in = 20 ft');
    });

    test('the controller measurementScale forwarder round-trips preferences',
        () {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      expect(editing.measurementScale, isNull);

      final scale = PdfMeasurementScale(unitsPerPoint: 20 / 72, unitLabel: 'ft');
      editing.measurementScale = scale;
      // The getter reads through to preferences; the setter wrote it there.
      expect(editing.measurementScale, same(scale));
      expect(editing.preferences.measurementScale, same(scale));
    });

    test('live readouts compute distance, perimeter, and area', () {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      editing.preferences.measurementScale =
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
      editing.preferences.measurementScale =
          PdfMeasurementScale(unitsPerPoint: 20 / 72, unitLabel: 'ft');

      editing.addMeasurement(
          0, PdfMeasurementKind.distance, const [(100, 100), (316, 100)]);

      final annotation = editing.document.page(0).annotations.single;
      expect(annotation.subtype, 'Line');
      expect(annotation.measure, isNotNull);
      expect(annotation.measurementText, '60 ft');
    });

    test('new measurements adopt the active caption font and line endings',
        () {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      editing.preferences.measurementScale =
          PdfMeasurementScale(unitsPerPoint: 20 / 72, unitLabel: 'ft');
      editing.fontFamily = PdfStandardFont.times;
      editing.preferences.fontSize = 14;
      editing.preferences.lineStartEnding = PdfLineEnding.openArrow;
      editing.preferences.lineEndEnding = PdfLineEnding.closedArrow;

      editing.addMeasurement(
          0, PdfMeasurementKind.distance, const [(100, 100), (316, 100)]);

      final annot = editing.document.page(0).annotations.single;
      // caption font/size recorded for re-styling, endings on /LE
      expect(annot.defaultAppearance, contains('/TiRo 14 Tf'));
      expect(pdfLineEndings(annot),
          (PdfLineEnding.openArrow, PdfLineEnding.closedArrow));
      expect(annot.measurementText, '60 ft');
    });

    test('changing a selected measurement keeps its caption visible', () {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      editing.preferences.measurementScale =
          PdfMeasurementScale(unitsPerPoint: 20 / 72, unitLabel: 'ft');
      editing.addMeasurement(
          0, PdfMeasurementKind.distance, const [(100, 100), (316, 100)]);
      editing.selectAnnotation(0, 0);

      editing.restyleSelected(strokeWidth: 6);

      // the reported bug: a width change must not drop the label
      final annot = editing.document.page(0).annotations.single;
      final stream = annot.normalAppearance!;
      final text =
          latin1.decode(editing.document.cos.decodeStreamData(stream));
      expect(text, contains('(60 ft)'));
      expect(annot.borderWidth, 6);
    });

    test('the panel can restyle a selected measurement caption font', () {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      editing.preferences.measurementScale =
          PdfMeasurementScale(unitsPerPoint: 20 / 72, unitLabel: 'ft');
      editing.addMeasurement(
          0, PdfMeasurementKind.distance, const [(100, 100), (316, 100)]);
      editing.selectAnnotation(0, 0);

      // the font controls are now offered for a selected measurement
      expect(editing.canRestyleMeasurementCaption, isTrue);
      expect(editing.selectedMeasurementCaptionStyle?.font,
          PdfStandardFont.helvetica);

      editing.setSelectedMeasurementCaption(
          font: PdfStandardFont.times, size: 18);

      final annot = editing.document.page(0).annotations.single;
      expect(annot.defaultAppearance, contains('/TiRo 18 Tf'));
      expect(editing.selectedMeasurementCaptionStyle?.size, 18);
      final text =
          latin1.decode(editing.document.cos.decodeStreamData(
              annot.normalAppearance!));
      expect(text, contains('/TiRo 18 Tf')); // redrawn in the new face
      expect(text, contains('(60 ft)')); // label kept
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

    test('ratioLabel quotes the configurable on-page reference unit', () {
      // 1 cm on the page (72/2.54 pt) = 5 m in the world.
      final scale = PdfMeasurementScale(
        unitsPerPoint: 5 / (72 / 2.54),
        unitLabel: 'm',
        pageUnitLabel: 'cm',
      );
      expect(scale.ratioLabel, '1 cm = 5 m');
    });

    test('an inch page unit stays the default and label', () {
      final scale =
          PdfMeasurementScale(unitsPerPoint: 20 / 72, unitLabel: 'ft');
      expect(scale.pageUnitLabel, 'in');
      expect(scale.ratioLabel, '1 in = 20 ft');
    });

    test('the page unit round-trips through encode/decode', () {
      final scale = PdfMeasurementScale(
        unitsPerPoint: 5 / (72 / 2.54),
        unitLabel: 'm',
        pageUnitLabel: 'cm',
      );
      final restored = PdfMeasurementScale.decode(scale.encode());
      expect(restored, scale);
      expect(restored!.pageUnitLabel, 'cm');
      // a legacy payload without the page unit decodes as inches.
      final legacy = PdfMeasurementScale.decode('{"u":${20 / 72},"l":"ft"}');
      expect(legacy!.pageUnitLabel, 'in');
    });
  });

  group('locale-based default unit', () {
    test('pdfDefaultMeasurementUnit picks imperial vs metric by country', () {
      expect(pdfDefaultMeasurementUnit(const Locale('en', 'US')), 'ft');
      expect(pdfDefaultMeasurementUnit(const Locale('en', 'LR')), 'ft');
      expect(pdfDefaultMeasurementUnit(const Locale('my', 'MM')), 'ft');
      expect(pdfDefaultMeasurementUnit(const Locale('en', 'GB')), 'm');
      expect(pdfDefaultMeasurementUnit(const Locale('fr', 'FR')), 'm');
      expect(pdfDefaultMeasurementUnit(const Locale('de', 'DE')), 'm');
    });

    Future<String> shownUnit(WidgetTester tester, Locale device) async {
      // The dialog follows the DEVICE locale, not the app's UI locale, so
      // drive platformDispatcher rather than MaterialApp.locale.
      tester.platformDispatcher.localeTestValue = device;
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);
      // A blank tree first, so a second call gets a fresh State (else the
      // dialog reuses the prior element and keeps its already-set unit).
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: PdfScaleDialog())));
      await tester.pumpAndSettle();
      final dropdown = tester.widget<DropdownButton<String>>(
          find.byKey(const ValueKey('pdf-scale-unit')));
      return dropdown.value!;
    }

    testWidgets('the scale dialog follows the device region', (tester) async {
      // An English-only app (the demo) used to clamp Localizations to en_US
      // and always show feet; the device region is what should decide.
      expect(await shownUnit(tester, const Locale('en', 'US')), 'ft');
      expect(await shownUnit(tester, const Locale('en', 'AU')), 'm');
      expect(await shownUnit(tester, const Locale('fr', 'FR')), 'm');
    });

    testWidgets('an existing scale wins over the device default',
        (tester) async {
      tester.platformDispatcher.localeTestValue = const Locale('en', 'US');
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: PdfScaleDialog(
            initial: PdfMeasurementScale(unitsPerPoint: 1, unitLabel: 'cm'),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final dropdown = tester.widget<DropdownButton<String>>(
          find.byKey(const ValueKey('pdf-scale-unit')));
      expect(dropdown.value, 'cm');
    });

    Future<String> shownPageUnit(WidgetTester tester, Locale device) async {
      tester.platformDispatcher.localeTestValue = device;
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: PdfScaleDialog())));
      await tester.pumpAndSettle();
      final dropdown = tester.widget<DropdownButton<String>>(
          find.byKey(const ValueKey('pdf-scale-page-unit')));
      return dropdown.value!;
    }

    testWidgets('the page-unit (left side) follows the device region',
        (tester) async {
      expect(await shownPageUnit(tester, const Locale('en', 'US')), 'in');
      expect(await shownPageUnit(tester, const Locale('en', 'AU')), 'cm');
      expect(await shownPageUnit(tester, const Locale('fr', 'FR')), 'cm');
    });

    testWidgets('a metric page unit produces the right per-point scale',
        (tester) async {
      tester.platformDispatcher.localeTestValue = const Locale('fr', 'FR');
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);
      PdfMeasurementScale? result;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async =>
                  result = await showPdfScaleDialog(context),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Defaults to "1 cm = N m" in a metric region.
      final pageUnit = tester.widget<DropdownButton<String>>(
          find.byKey(const ValueKey('pdf-scale-page-unit')));
      expect(pageUnit.value, 'cm');
      await tester.enterText(
          find.byKey(const ValueKey('pdf-scale-value')), '5');
      await tester.tap(find.byKey(const ValueKey('pdf-scale-apply')));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.pageUnitLabel, 'cm');
      expect(result!.unitLabel, 'm');
      // 1 cm = 72/2.54 pt, so 5 m over that span.
      expect(result!.unitsPerPoint, closeTo(5 / (72 / 2.54), 1e-9));
      expect(result!.ratioLabel, '1 cm = 5 m');
    });
  });

  group('calibrate by drawing a reference segment', () {
    testWidgets('the scale dialog hides Calibrate without a callback',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(body: PdfScaleDialog())));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pdf-scale-calibrate')), findsNothing);
    });

    testWidgets('Calibrate dismisses the dialog and fires the callback',
        (tester) async {
      var called = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showPdfScaleDialog(context,
                  onCalibrate: () => called++),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pdf-scale-calibrate')));
      await tester.pumpAndSettle();
      expect(called, 1);
      // the scale dialog is gone (no typed-ratio field left on screen)
      expect(find.byKey(const ValueKey('pdf-scale-value')), findsNothing);
    });

    testWidgets('drawing a segment then entering its length sets the scale',
        (tester) async {
      tester.platformDispatcher.localeTestValue = const Locale('en', 'US');
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);
      const scale = 800 / 612;
      Offset view(double x, double y) => Offset(x * scale, (792 - y) * scale);

      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(2));
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

      editing.tool = PdfEditTool.calibrate;
      await tester.pump();
      expect(editing.hasMeasurementScale, isFalse);

      // a 200 page-point segment (page x 100→300 at y 700)
      final from = view(100, 700);
      final to = view(300, 700);
      final gesture =
          await tester.startGesture(from, kind: PointerDeviceKind.mouse);
      await gesture.moveTo(Offset.lerp(from, to, 0.5)!);
      await gesture.moveTo(to);
      await gesture.up();
      await tester.pumpAndSettle();

      // the calibration-length dialog asks how long the drawn line is
      expect(find.byKey(const ValueKey('pdf-calibrate-value')), findsOneWidget);
      final unit = tester.widget<DropdownButton<String>>(
          find.byKey(const ValueKey('pdf-calibrate-unit')));
      expect(unit.value, 'ft'); // US device region
      await tester.enterText(
          find.byKey(const ValueKey('pdf-calibrate-value')), '50');
      await tester.tap(find.byKey(const ValueKey('pdf-calibrate-apply')));
      await tester.pumpAndSettle();

      expect(editing.hasMeasurementScale, isTrue);
      final result = editing.preferences.measurementScale!;
      expect(result.unitLabel, 'ft');
      // 50 ft over 200 page points
      expect(result.unitsPerPoint, closeTo(50 / 200, 1e-6));
      // nothing was stamped on the page, and the tool stepped back
      expect(editing.document.page(0).annotations, isEmpty);
      expect(editing.tool, PdfEditTool.select);
    });

    testWidgets('cancelling the length dialog leaves the scale unset',
        (tester) async {
      const scale = 800 / 612;
      Offset view(double x, double y) => Offset(x * scale, (792 - y) * scale);
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(2));
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
      editing.tool = PdfEditTool.calibrate;
      await tester.pump();

      final from = view(100, 700);
      final to = view(300, 700);
      final gesture =
          await tester.startGesture(from, kind: PointerDeviceKind.mouse);
      await gesture.moveTo(to);
      await gesture.up();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(editing.hasMeasurementScale, isFalse);
    });
  });

  group('live readout chip in the viewer', () {
    const scale = 800 / 612;
    Offset view(double x, double y) => Offset(x * scale, (792 - y) * scale);

    Future<(PdfEditingController, PdfViewerController)> pumpEditor(
        WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(2))
        ..preferences.measurementScale =
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
