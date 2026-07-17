import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('callout through the controller', () {
    test('addCallout builds a FreeText callout pointing at the target', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..preferences.author = 'Ben'
        ..addCallout(
            0, const PdfRect(300, 600, 460, 660), 'Look here', (120, 500));

      final annot = editing.document.page(0).annotations.single;
      expect(annot.subtype, 'FreeText');
      expect(annot.isCallout, isTrue);
      expect(annot.contents, 'Look here');
      final line = annot.calloutLine!;
      expect(line.first, (120.0, 500.0), reason: 'leader tip is the target');
      expect(annot.rect.left, lessThanOrEqualTo(120));
      expect(annot.rect.bottom, lessThanOrEqualTo(500));
    });

    test('the callout tool exposes the color/font controls', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..tool = PdfEditTool.callout;
      // the callout tool exposes the same box controls as free text
      expect(editing.toolUsesColor, isTrue);
    });

    test('resizing a selected callout resizes the box, not the arrow', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addCallout(0, const PdfRect(300, 600, 460, 660), 'x', (120, 500));
      expect(editing.selectAnnotation(0, 0), isTrue);
      final terminus0 =
          editing.document.page(0).annotations.single.calloutLine!.first;

      editing.resizeSelected(const PdfRect(320, 610, 520, 690));

      final a = editing.document.page(0).annotations.single;
      expect(a.isCallout, isTrue);
      expect(a.calloutLine!.first, terminus0, reason: 'arrow tip stays put');
      expect(a.calloutBox!.left, closeTo(320, 0.5));
      expect(a.calloutBox!.right, closeTo(520, 0.5));
    });

    test('autosize fits the box and leaves the arrow tip alone', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..preferences.fontSize = 14
        ..addCallout(0, const PdfRect(300, 600, 700, 700), 'Hi', (120, 500));
      expect(editing.selectAnnotation(0, 0), isTrue);
      final tip0 =
          editing.document.page(0).annotations.single.calloutLine!.first;

      editing.autosizeSelectedTextBox();

      final a = editing.document.page(0).annotations.single;
      expect(a.isCallout, isTrue);
      expect(a.calloutLine!.first, tip0, reason: 'arrow tip untouched');
      expect(a.calloutBox!.width, lessThan(400), reason: 'box shrank to fit');
    });

    test('reshapeSelectedCalloutTarget moves only the arrow', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addCallout(0, const PdfRect(300, 600, 460, 660), 'x', (120, 500));
      expect(editing.selectAnnotation(0, 0), isTrue);
      final box0 = editing.document.page(0).annotations.single.calloutBox!;

      editing.reshapeSelectedCalloutTarget((560, 630));

      final a = editing.document.page(0).annotations.single;
      expect(a.calloutLine!.first, (560.0, 630.0));
      expect(a.calloutBox!.left, closeTo(box0.left, 0.5));
      expect(a.calloutBox!.top, closeTo(box0.top, 0.5));
      expect(a.calloutBox!.bottom, closeTo(box0.bottom, 0.5));
    });
  });

  group('callout tool in the viewer', () {
    const scale = 800 / 612;
    Offset view(double x, double y) => Offset(x * scale, (792 - y) * scale);

    Future<void> drag(WidgetTester tester, Offset from, Offset to) async {
      final gesture = await tester.startGesture(from);
      await gesture.moveTo(Offset.lerp(from, to, 0.5)!);
      await gesture.moveTo(to);
      await gesture.up();
      await tester.pump();
    }

    Future<void> settle(WidgetTester tester) =>
        tester.pumpAndSettle(const Duration(milliseconds: 300));

    Future<void> tap(WidgetTester tester, Offset position) async {
      await tester.tapAt(position);
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<PdfEditingController> pumpEditor(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
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

    const editorKey = ValueKey('pdf-freetext-editor');

    testWidgets('dragging from the terminus to the box places a callout',
        (tester) async {
      final editing = await pumpEditor(tester);
      editing.tool = PdfEditTool.callout;
      await tester.pump();

      // press at the terminus (what we point at), release where the box goes
      await drag(tester, view(150, 500), view(360, 660));

      // the box editor opens in place, nothing committed yet
      expect(find.byKey(editorKey), findsOneWidget);
      expect(editing.isEditingText, isTrue);
      expect(editing.document.page(0).annotations, isEmpty);

      await tester.enterText(find.byKey(editorKey), 'Callout body');
      await tap(tester, view(450, 400)); // commit outside the box

      expect(find.byKey(editorKey), findsNothing);
      final annot = editing.document.page(0).annotations.single;
      expect(annot.isCallout, isTrue);
      expect(annot.contents, 'Callout body');
      final line = annot.calloutLine!;
      // the leader points back at the terminus we pressed on
      expect(line.first.$1, closeTo(150, 2));
      expect(line.first.$2, closeTo(500, 2));
      await settle(tester);
    });

    testWidgets('an empty callout box commits nothing', (tester) async {
      final editing = await pumpEditor(tester);
      editing.tool = PdfEditTool.callout;
      await tester.pump();

      await drag(tester, view(150, 500), view(360, 660));
      expect(find.byKey(editorKey), findsOneWidget);
      await tap(tester, view(450, 400)); // commit with no text

      expect(editing.document.page(0).annotations, isEmpty);
      await settle(tester);
    });

    testWidgets('dragging the terminus handle re-aims the arrow, box stays',
        (tester) async {
      final editing = await pumpEditor(tester);
      editing.addCallout(0, const PdfRect(300, 600, 460, 660), 'x', (150, 480));
      editing.tool = PdfEditTool.select;
      expect(editing.selectAnnotation(0, 0), isTrue);
      await tester.pump();
      final box0 = editing.document.page(0).annotations.single.calloutBox!;

      // the terminus handle sits at the arrow tip (150, 480); drag it away
      await drag(tester, view(150, 480), view(230, 430));
      await tester.pump();

      final a = editing.document.page(0).annotations.single;
      expect(a.isCallout, isTrue);
      final tip = a.calloutLine!.first;
      expect(tip.$1, closeTo(230, 6), reason: 'arrow tip followed the drag');
      expect(tip.$2, closeTo(430, 6));
      expect(a.calloutBox!.left, closeTo(box0.left, 1), reason: 'box unmoved');
      expect(a.calloutBox!.top, closeTo(box0.top, 1));
      await settle(tester);
    });

    testWidgets('dragging the base handle slides the base, box + tip stay',
        (tester) async {
      final editing = await pumpEditor(tester);
      editing.addCallout(0, const PdfRect(300, 600, 460, 660), 'x', (150, 630));
      editing.tool = PdfEditTool.select;
      expect(editing.selectAnnotation(0, 0), isTrue);
      await tester.pump();
      final a0 = editing.document.page(0).annotations.single;
      final tip0 = a0.calloutLine!.first;
      final base0 = a0.calloutLine!.last; // ~ (300, 630) on the left edge
      final box0 = a0.calloutBox!;

      // the base handle sits at the attach point; drag it inside toward the
      // top edge - it snaps onto the perimeter there
      await drag(tester, view(base0.$1, base0.$2), view(400, 640));
      await tester.pump();

      final a = editing.document.page(0).annotations.single;
      expect(a.calloutLine!.first, tip0, reason: 'arrow tip unchanged');
      final base = a.calloutLine!.last;
      expect((base.$1 - base0.$1).abs() + (base.$2 - base0.$2).abs(),
          greaterThan(5),
          reason: 'the base moved');
      expect(a.calloutBox!.left, closeTo(box0.left, 1), reason: 'box unmoved');
      expect(a.calloutBox!.right, closeTo(box0.right, 1));
      await settle(tester);
    });

    testWidgets('a plain tap makes the tap the terminus and offsets the box',
        (tester) async {
      final editing = await pumpEditor(tester);
      editing.tool = PdfEditTool.callout;
      await tester.pump();

      await tap(tester, view(250, 500)); // no drag: the tap is the terminus
      expect(find.byKey(editorKey), findsOneWidget);

      await tester.enterText(find.byKey(editorKey), 'Tapped callout');
      await tap(tester, view(450, 400)); // commit

      final annot = editing.document.page(0).annotations.single;
      expect(annot.isCallout, isTrue);
      final line = annot.calloutLine!;
      expect(line.first.$1, closeTo(250, 2));
      expect(line.first.$2, closeTo(500, 2));
      await settle(tester);
    });
  });

  test('callout survives a save/reload round-trip', () {
    final editing = PdfEditingController(buildMultiPagePdf(1))
      ..addCallout(0, const PdfRect(300, 600, 460, 660), 'persist', (120, 500));
    final reopened = PdfDocument.open(editing.bytes);
    final annot = reopened.page(0).annotations.single;
    expect(annot.isCallout, isTrue);
    expect(annot.calloutLine!.first, (120.0, 500.0));
    final ap = latin1
        .decode(reopened.cos.decodeStreamData(annot.normalAppearance!));
    expect(ap, contains('Tj'));
  });
}
