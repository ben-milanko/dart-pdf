import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 800×600 viewport, fit-width: 612pt page → view scale
const scale = 800 / 612;

Offset viewPoint(double x, double y) => Offset(x * scale, (792 - y) * scale);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PdfSnapshotClipboard.instance.clear();
  });

  group('applySelectedStyleAsDefault', () {
    test('captures a shape\'s style into the matching tool\'s creation default',
        () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addRectangle(0, const PdfRect(50, 700, 150, 750))
        ..tool = PdfEditTool.select
        ..selectAnnotation(0, 0);
      addTearDown(editing.dispose);

      // restyle the rectangle to distinctive, cleanly round-tripping values
      editing.restyleSelected(
        color: const Color(0xFFFF0000),
        strokeWidth: 7,
        opacity: 0.5,
        fill: (const Color(0xFF0000FF),),
      );

      expect(editing.canApplySelectedStyleAsDefault, isTrue);
      expect(editing.applySelectedStyleAsDefault(), isTrue);

      // arming the rectangle tool restores its saved slot into the live
      // creation defaults - which now match the annotation we captured from
      editing.tool = PdfEditTool.rectangle;
      expect(editing.preferences.color, const Color(0xFFFF0000));
      expect(editing.preferences.strokeWidth, 7);
      expect(editing.preferences.opacity, closeTo(0.5, 1e-6));
      expect(editing.preferences.shapeFillColor, const Color(0xFF0000FF));
    });

    test('does not disturb an unrelated tool\'s default', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addRectangle(0, const PdfRect(50, 700, 150, 750))
        ..tool = PdfEditTool.select
        ..selectAnnotation(0, 0);
      addTearDown(editing.dispose);

      // seed a different color under the ellipse tool
      editing.tool = PdfEditTool.ellipse;
      editing.color = const Color(0xFF00FF00);
      editing
        ..tool = PdfEditTool.select
        ..selectAnnotation(0, 0)
        ..restyleSelected(color: const Color(0xFFFF0000));
      editing.applySelectedStyleAsDefault();

      // the rectangle default took the capture; the ellipse default is intact
      editing.tool = PdfEditTool.ellipse;
      expect(editing.preferences.color, const Color(0xFF00FF00));
      editing.tool = PdfEditTool.rectangle;
      expect(editing.preferences.color, const Color(0xFFFF0000));
    });

    test('captures a free-text box\'s font and size', () {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      editing.preferences
        ..fontSize = 30
        ..fontFamily = PdfStandardFont.times;
      editing.addFreeText(0, const PdfRect(50, 600, 300, 700), 'Hi');

      // move the live defaults away, so a capture must come from the box
      editing.preferences
        ..fontSize = 10
        ..fontFamily = PdfStandardFont.helvetica;

      editing
        ..tool = PdfEditTool.select
        ..selectAnnotation(0, 0);
      expect(editing.canApplySelectedStyleAsDefault, isTrue);
      editing.applySelectedStyleAsDefault();

      editing.tool = PdfEditTool.freeText;
      expect(editing.preferences.fontSize, 30);
      expect(editing.preferences.fontFamily.family, PdfStandardFontFamily.serif);
    });

    test('captures text markup colour and opacity into the markup scope', () {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      editing.preferences
        ..color = const Color(0xFFFF9900)
        ..opacity = 0.4;
      editing.addMarkup(PdfMarkupKind.highlight, {
        0: const [PdfRect(50, 700, 200, 720)],
      });
      // move the live defaults away
      editing.preferences
        ..color = const Color(0xFF000000)
        ..opacity = 1;

      editing
        ..tool = PdfEditTool.select
        ..selectAnnotation(0, 0);
      expect(editing.selectedAnnotation?.subtype, 'Highlight');
      expect(editing.canApplySelectedStyleAsDefault, isTrue);
      editing.applySelectedStyleAsDefault();

      editing.useMarkupStyleScope();
      expect(editing.preferences.color, const Color(0xFFFF9900));
      expect(editing.preferences.opacity, closeTo(0.4, 1e-6));
    });

    test('is unavailable with nothing selected', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..tool = PdfEditTool.select;
      addTearDown(editing.dispose);
      expect(editing.canApplySelectedStyleAsDefault, isFalse);
      expect(editing.applySelectedStyleAsDefault(), isFalse);
    });
  });

  group('context menu', () {
    Future<PdfEditingController> pumpViewer(WidgetTester tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: editing,
            builder: (context, _) => PdfViewer(
              initialFit: PdfViewerFit.width,
              document: editing.document,
              editing: editing,
            ),
          ),
        ),
      ));
      await tester.pump();
      editing.addRectangle(0, const PdfRect(60, 700, 160, 750));
      await tester.pump();
      return editing;
    }

    Future<void> rightClick(WidgetTester tester, Offset at) async {
      await tester.tapAt(at,
          kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
    }

    testWidgets('Set as default style captures the annotation\'s style',
        (tester) async {
      final editing = await pumpViewer(tester);
      editing
        ..tool = PdfEditTool.select
        ..selectAnnotation(0, 0)
        ..restyleSelected(color: const Color(0xFFFF0000), strokeWidth: 9);
      await tester.pump();

      await rightClick(tester, viewPoint(110, 725));
      expect(find.byKey(const ValueKey('pdf-annot-menu-set-default')),
          findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pdf-annot-menu-set-default')));
      await tester.pumpAndSettle();

      editing.tool = PdfEditTool.rectangle;
      expect(editing.preferences.color, const Color(0xFFFF0000));
      expect(editing.preferences.strokeWidth, 9);
    });
  });
}
