import 'dart:math' as math;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final rotation in [0, 90, 180, 270]) {
    testWidgets('rendered block moves vertically on a $rotation° page',
        (tester) async {
      await tester.runAsync(() async {
        final firstInkRows = <int>[];
        for (final align in PdfTextVerticalAlign.values) {
          final source = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)))
            ..rotatePages([0], rotation);
          final editing = PdfEditingController(source.save());
          editing.preferences.fontSize = 20;
          editing.setSelectedTextVerticalAlign(align);
          editing.addFreeText(0, const PdfRect(100, 500, 300, 650), 'One\nTwo');
          final page = PdfDocument.open(editing.bytes).page(0);
          final image = await PdfPageRenderer.renderImage(page);
          final pixels = (await image.toByteData())!;
          final geometry = PdfPageGeometry(
            cropBox: page.cropBox,
            rotation: rotation,
            viewSize: Size(image.width.toDouble(), image.height.toDouble()),
          );
          final box = geometry.toViewRect(page.annotations.single.rect);
          var firstInk = -1;
          for (var y = box.top.ceil(); y < box.bottom.floor(); y++) {
            for (var x = box.left.ceil(); x < box.right.floor(); x++) {
              final index = (y * image.width + x) * 4;
              if (pixels.getUint8(index + 1) < 150) {
                firstInk = y;
                break;
              }
            }
            if (firstInk >= 0) break;
          }
          expect(firstInk, greaterThanOrEqualTo(0));
          firstInkRows.add(firstInk);
          image.dispose();
          editing.dispose();
        }
        expect(firstInkRows[1] - firstInkRows[0], greaterThan(40));
        expect(firstInkRows[2] - firstInkRows[1], greaterThan(40));
      });
    });

    test('vertical alignment survives edits on a $rotation° page', () {
      final source = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)))
        ..rotatePages([0], rotation);
      final editing = PdfEditingController(source.save());
      addTearDown(editing.dispose);
      editing.setSelectedTextVerticalAlign(PdfTextVerticalAlign.bottom);
      editing.addFreeText(
          0, const PdfRect(100, 500, 300, 650), 'First\nSecond');
      editing.selectAnnotation(0, 0);
      final name = editing.selectedAnnotation!.name;
      editing.restyleSelectedText(align: PdfTextAlign.right, size: 18);
      editing.setSelectedText('Edited\nSecond');
      editing.resizeSelected(const PdfRect(100, 450, 350, 650));
      expect(editing.selectedTextVerticalAlign, PdfTextVerticalAlign.bottom);
      expect(editing.selectedTextAlign, PdfTextAlign.right);
      expect(editing.selectedAnnotation!.name, name);
      editing.rotateSelected(30);
      editing.restyleSelectedText(verticalAlign: PdfTextVerticalAlign.center);
      expect(editing.selectedTextVerticalAlign, PdfTextVerticalAlign.center);
      expect(editing.selectedAnnotation!.appearanceRotation,
          closeTo(math.pi / 6, 1e-6));
      editing.undo();
      expect(
          editing.document
              .page(0)
              .annotations
              .single
              .freeTextStyle!
              .verticalAlignment,
          PdfTextVerticalAlign.bottom);
      editing.redo();
      final reopened =
          PdfDocument.open(editing.bytes).page(0).annotations.single;
      expect(reopened.freeTextStyle!.verticalAlignment,
          PdfTextVerticalAlign.center);
      expect(reopened.freeTextStyle!.alignment, PdfTextAlign.right);
      expect(reopened.name, name);
    });
  }

  test('rich text and a mixed selection retain vertical alignment', () {
    final editing = PdfEditingController(buildMultiPagePdf(1));
    addTearDown(editing.dispose);
    editing.addFreeTextRich(0, const PdfRect(100, 500, 300, 650), [
      const PdfFreeTextRun('One', fontSize: 12),
      const PdfFreeTextRun('Two', fontSize: 20, color: 0xFF0000),
    ]);
    editing.addRectangle(0, const PdfRect(350, 500, 400, 550));
    editing.selectAllAnnotationsOn(0);
    editing.restyleSelectedText(verticalAlign: PdfTextVerticalAlign.bottom);
    expect(
        editing.document
            .page(0)
            .annotations
            .where((a) => a.subtype == 'Square'),
        hasLength(1));
    editing.selectAnnotation(0, 1);
    expect(editing.selectedRichRuns!.map((r) => r.fontSize), [12, 20]);
    editing.setSelectedRichText([
      const PdfFreeTextRun('Changed', fontSize: 24),
    ]);
    expect(editing.selectedTextVerticalAlign, PdfTextVerticalAlign.bottom);
  });

  test('the new-box preference is saved and restored', () async {
    final preferences = PdfEditingPreferences();
    await preferences.ready;
    preferences.textVerticalAlign = PdfTextVerticalAlign.center;
    await Future<void>.delayed(Duration.zero);
    final restored = PdfEditingPreferences();
    await restored.ready;
    expect(restored.textVerticalAlign, PdfTextVerticalAlign.center);
    preferences.dispose();
    restored.dispose();
  });

  testWidgets('properties controls change vertical placement', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final editing = PdfEditingController(buildMultiPagePdf(1))
      ..addFreeText(0, const PdfRect(100, 500, 300, 650), 'Text')
      ..selectAnnotation(0, 0);
    addTearDown(editing.dispose);
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: Scaffold(
            body: Align(
          alignment: Alignment.centerRight,
          child: PdfAnnotationPropertiesPanel(controller: editing, width: 300),
        ))));
    await tester.pump();
    await tester
        .tap(find.byKey(const ValueKey('pdf-prop-text-vertical-align-center')));
    await tester.pump();
    expect(editing.selectedTextVerticalAlign, PdfTextVerticalAlign.center);
    await tester
        .tap(find.byKey(const ValueKey('pdf-prop-text-vertical-align-bottom')));
    await tester.pump();
    expect(editing.selectedTextVerticalAlign, PdfTextVerticalAlign.bottom);
  });

  for (final align in PdfTextVerticalAlign.values) {
    testWidgets('inline editor opens with ${align.name} vertical placement',
        (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      editing.setSelectedTextVerticalAlign(align);
      editing.addFreeText(0, const PdfRect(100, 500, 300, 650), 'Text');
      editing.selectAnnotation(0, 0);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ListenableBuilder(
        listenable: editing,
        builder: (context, _) => PdfViewer(
          initialFit: PdfViewerFit.width,
          document: editing.document,
          editing: editing,
          controller: viewer,
        ),
      ))));
      await tester.pump();
      expect(editing.requestEditSelectedTextInline(), isTrue);
      await tester.pump();
      final field = tester
          .widget<TextField>(find.byKey(const ValueKey('pdf-freetext-editor')));
      expect(
          field.textAlignVertical,
          switch (align) {
            PdfTextVerticalAlign.top => TextAlignVertical.top,
            PdfTextVerticalAlign.center => TextAlignVertical.center,
            PdfTextVerticalAlign.bottom => TextAlignVertical.bottom,
          });
    });
  }
}
