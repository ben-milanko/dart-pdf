// The annotation properties panel: reads the selection's properties and
// edits them through the controller — plus the controller's contents and
// author setters it relies on.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    // the mock store is process-global: an earlier test's persisted
    // style would otherwise leak in through the async preference load
    SharedPreferences.setMockInitialValues({});
  });

  group('controller contents & author', () {
    test('a markup contents edit is metadata only', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addRectangle(0, const PdfRect(100, 600, 200, 660));
      addTearDown(editing.dispose);
      editing.selectAnnotation(0, 0);
      final appearance = editing.document.cos.decodeStreamData(
          editing.document.page(0).annotations.single.normalAppearance!);

      expect(editing.setSelectedContents('a comment'), isTrue);
      final after = editing.document.page(0).annotations.single;
      expect(after.contents, 'a comment');
      // same appearance bytes — nothing was redrawn
      expect(editing.document.cos.decodeStreamData(after.normalAppearance!),
          appearance);
      // the selection survives the in-place edit
      expect(editing.selectedAnnotation?.contents, 'a comment');

      // unchanged value: no new revision
      final revision = editing.document;
      expect(editing.setSelectedContents('a comment'), isFalse);
      expect(identical(editing.document, revision), isTrue);
    });

    test('free-text contents rewrite the displayed text', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addFreeText(0, const PdfRect(100, 560, 300, 620), 'Hello');
      addTearDown(editing.dispose);
      editing.selectAnnotation(0, 0);

      expect(editing.setSelectedContents('Changed'), isTrue);
      final after = editing.selectedAnnotation!;
      expect(after.subtype, 'FreeText');
      expect(after.contents, 'Changed');
    });

    test('the author applies to the whole selection as one undo', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addRectangle(0, const PdfRect(100, 600, 200, 660))
        ..addEllipse(0, const PdfRect(250, 600, 350, 660));
      addTearDown(editing.dispose);
      editing.selectAllAnnotationsOn(0);

      expect(editing.setSelectedAuthor('Ben'), isTrue);
      final annotations = editing.document.page(0).annotations;
      expect(annotations[0].author, 'Ben');
      expect(annotations[1].author, 'Ben');

      editing.undo();
      expect(editing.document.page(0).annotations[0].author, isNull);

      editing.redo();
      // empty clears, in one revision again
      editing.selectAllAnnotationsOn(0);
      expect(editing.setSelectedAuthor(''), isTrue);
      expect(editing.document.page(0).annotations[0].author, isNull);
      expect(editing.document.page(0).annotations[1].author, isNull);
    });
  });

  group('properties panel', () {
    Future<void> pumpPanel(
        WidgetTester tester, PdfEditingController editing) async {
      // a tall surface so every panel row is built (ListView is lazy)
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Row(children: [
            const Expanded(child: SizedBox()),
            PdfAnnotationPropertiesPanel(controller: editing, width: 300),
          ]),
        ),
      ));
      await tester.pump();
    }

    Future<void> submit(WidgetTester tester, Key key, String text) async {
      await tester.enterText(find.byKey(key), text);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
    }

    testWidgets('shows a hint without a selection, details with one',
        (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addRectangle(0, const PdfRect(100, 600, 220, 660));
      addTearDown(editing.dispose);
      await pumpPanel(tester, editing);
      expect(find.text('Select an annotation to see its properties'),
          findsOneWidget);

      editing.selectAnnotation(0, 0);
      await tester.pump();
      expect(find.text('Square'), findsOneWidget);
      expect(find.text('Page 1'), findsOneWidget);
      // page-space geometry: x=100, y=600, 120×60
      expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('pdf-prop-x')))
              .controller!
              .text,
          '100');
      expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('pdf-prop-y')))
              .controller!
              .text,
          '600');
      expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('pdf-prop-w')))
              .controller!
              .text,
          '120');
      expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('pdf-prop-h')))
              .controller!
              .text,
          '60');
    });

    testWidgets('contents and author commit on submit', (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addRectangle(0, const PdfRect(100, 600, 220, 660));
      addTearDown(editing.dispose);
      await pumpPanel(tester, editing);
      editing.selectAnnotation(0, 0);
      await tester.pump();

      await submit(tester, const ValueKey('pdf-prop-contents'), 'A note');
      expect(editing.selectedAnnotation?.contents, 'A note');

      await submit(tester, const ValueKey('pdf-prop-author'), 'Ben');
      expect(editing.selectedAnnotation?.author, 'Ben');
    });

    testWidgets('showAuthor: false hides the author row', (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addRectangle(0, const PdfRect(100, 600, 220, 660));
      addTearDown(editing.dispose);
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Row(children: [
            const Expanded(child: SizedBox()),
            PdfAnnotationPropertiesPanel(
                controller: editing, width: 300, showAuthor: false),
          ]),
        ),
      ));
      await tester.pump();

      editing.selectAnnotation(0, 0);
      await tester.pump();
      // contents stays, author is gone
      expect(find.byKey(const ValueKey('pdf-prop-contents')), findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-prop-author')), findsNothing);
    });

    testWidgets('X moves and W resizes, anchored bottom-left', (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addRectangle(0, const PdfRect(100, 600, 220, 660));
      addTearDown(editing.dispose);
      await pumpPanel(tester, editing);
      editing.selectAnnotation(0, 0);
      await tester.pump();

      await submit(tester, const ValueKey('pdf-prop-x'), '150');
      var rect = editing.selectedAnnotation!.rect;
      expect(rect.left, closeTo(150, 1e-6));
      expect(rect.bottom, closeTo(600, 1e-6)); // a move, not a resize
      expect(rect.width, closeTo(120, 1e-6));

      await submit(tester, const ValueKey('pdf-prop-w'), '200');
      rect = editing.selectedAnnotation!.rect;
      expect(rect.left, closeTo(150, 1e-6)); // anchored
      expect(rect.bottom, closeTo(600, 1e-6));
      expect(rect.width, closeTo(200, 1e-6));
      expect(rect.height, closeTo(60, 1e-6));

      // junk input changes nothing and the field snaps back
      await submit(tester, const ValueKey('pdf-prop-x'), 'abc');
      expect(editing.selectedAnnotation!.rect.left, closeTo(150, 1e-6));
      expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('pdf-prop-x')))
              .controller!
              .text,
          '150');
    });

    testWidgets('the sliders restyle the selection in place', (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addRectangle(0, const PdfRect(100, 600, 220, 660));
      addTearDown(editing.dispose);
      await pumpPanel(tester, editing);
      editing.selectAnnotation(0, 0);
      await tester.pump();

      await tester.drag(
          find.byKey(const ValueKey('pdf-prop-stroke')), const Offset(60, 0));
      await tester.pump();
      final width = editing.selectedAnnotation!.borderWidth!;
      expect(width, greaterThan(2));

      await tester.drag(
          find.byKey(const ValueKey('pdf-prop-opacity')), const Offset(-60, 0));
      await tester.pump();
      final opacity = editing.selectedAnnotation!.appearanceOpacity;
      expect(opacity, lessThan(1));
      expect(opacity, greaterThan(0));
      // the selection (and the stroke restyle) survived both edits
      expect(editing.selectedAnnotation!.borderWidth, width);
    });

    testWidgets('the fill clear button removes a shape fill', (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      editing.apply((e) => e.addSquare(0, const PdfRect(100, 600, 220, 660),
          strokeWidth: 2, fillColor: 0x43A047));
      await pumpPanel(tester, editing);
      editing.selectAnnotation(0, 0);
      await tester.pump();
      expect(editing.selectedAnnotation!.interiorColor, 0x43A047);

      await tester.tap(find.byTooltip('No fill'));
      await tester.pump();
      expect(editing.selectedAnnotation!.interiorColor, isNull);
    });

    testWidgets('free text gets font and size controls', (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addFreeText(0, const PdfRect(100, 500, 300, 620), 'Hello');
      addTearDown(editing.dispose);
      await pumpPanel(tester, editing);
      editing.selectAnnotation(0, 0);
      await tester.pump();

      expect(editing.selectedTextStyle?.font, PdfStandardFont.helvetica);
      await tester.tap(find.byKey(const ValueKey('pdf-prop-font')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Serif').last);
      await tester.pumpAndSettle();
      expect(editing.selectedTextStyle?.font, PdfStandardFont.times);
      expect(editing.selectedAnnotation?.contents, 'Hello'); // text kept

      // the Bold / Italic toggles pick the variant, keeping the family
      await tester.tap(find.byKey(const ValueKey('pdf-prop-font-bold')));
      await tester.pump();
      expect(editing.selectedTextStyle?.font, PdfStandardFont.timesBold);
      await tester.tap(find.byKey(const ValueKey('pdf-prop-font-italic')));
      await tester.pump();
      expect(editing.selectedTextStyle?.font, PdfStandardFont.timesBoldItalic);
    });

    testWidgets('free text gets an outline (border) control', (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addFreeText(0, const PdfRect(100, 500, 300, 620), 'Hello');
      addTearDown(editing.dispose);
      await pumpPanel(tester, editing);
      editing.selectAnnotation(0, 0);
      await tester.pump();

      // no border yet
      expect(editing.selectedAnnotation?.freeTextStyle?.borderColor, isNull);
      // the outline row is present for free text
      expect(
          find.byKey(const ValueKey('pdf-prop-text-border')), findsOneWidget);

      // setting a border directly through the controller (the swatch opens a
      // modal picker) shows it round-trips, and clearing removes it
      editing.restyleSelectedText(border: (0xFF0000,), borderWidth: 2);
      await tester.pump();
      expect(editing.selectedAnnotation?.freeTextStyle?.borderColor, 0xFF0000);

      editing.restyleSelectedText(border: (null,));
      await tester.pump();
      expect(editing.selectedAnnotation?.freeTextStyle?.borderColor, isNull);
    });

    testWidgets('a multi-selection styles everything at once', (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addRectangle(0, const PdfRect(100, 600, 220, 660))
        ..addEllipse(0, const PdfRect(250, 600, 350, 660));
      addTearDown(editing.dispose);
      await pumpPanel(tester, editing);
      editing.selectAllAnnotationsOn(0);
      await tester.pump();

      expect(find.text('2 annotations'), findsOneWidget);
      // no geometry fields in multi mode
      expect(find.byKey(const ValueKey('pdf-prop-x')), findsNothing);

      await tester.drag(
          find.byKey(const ValueKey('pdf-prop-opacity')), const Offset(-60, 0));
      await tester.pump();
      final annotations = editing.document.page(0).annotations;
      expect(annotations[0].appearanceOpacity, lessThan(1));
      expect(annotations[1].appearanceOpacity, lessThan(1));
      expect(annotations[0].appearanceOpacity,
          closeTo(annotations[1].appearanceOpacity, 1e-6));
    });

    testWidgets('the dragged width persists as a preference', (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      await pumpPanel(tester, editing);

      final grip = find.byKey(const ValueKey('pdf-properties-resize-grip'));
      expect(grip, findsOneWidget);
      final before =
          tester.getSize(find.byType(PdfAnnotationPropertiesPanel)).width;
      final gesture = await tester.startGesture(tester.getCenter(grip),
          kind: PointerDeviceKind.mouse);
      await gesture.moveBy(const Offset(-60, 0));
      await gesture.up();
      await tester.pump();

      final after =
          tester.getSize(find.byType(PdfAnnotationPropertiesPanel)).width;
      expect(after, greaterThan(before));
      expect(editing.preferences.propertiesPanelWidth, after);
    });
  });
}
