import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  PdfPageGeometry geometry(PdfEditingController editing) {
    final page = editing.document.page(0);
    return PdfPageGeometry(
      cropBox: page.cropBox,
      rotation: page.rotation,
      viewSize: PdfPageRenderer.pageSize(page),
    );
  }

  const original = Rect.fromLTWH(100, 100, 200, 120);
  const font = PdfStandardFont.courier;
  const size = 18.0;
  final lineWidth = measureStandardText('Wide line', size, font: font) + 6;
  // Courier's AFM ascent/descent, matching its rendered text metrics.
  final lineHeight = 6 + size * (629 + 157) / 1000;

  PdfEditingController create(int rotation) {
    final editing =
        PdfEditingController(buildMultiPagePdf(1, rotation: rotation))
          ..fontFamily = font
          ..preferences.fontSize = size;
    addTearDown(editing.dispose);
    return editing;
  }

  void expectBox(Rect actual, Rect expected) {
    expect(actual.left, closeTo(expected.left, 0.01));
    expect(actual.top, closeTo(expected.top, 0.01));
    expect(actual.width, closeTo(expected.width, 0.01));
    expect(actual.height, closeTo(expected.height, 0.01));
  }

  for (final rotation in [0, 90, 180, 270]) {
    group('autosize on /Rotate $rotation', () {
      test('fits multiline text from its visible top-left, with undo/redo', () {
        final editing = create(rotation);
        final g = geometry(editing);
        editing
          ..addFreeText(0, g.toPageRect(original), 'Wide line\nshort')
          ..selectAnnotation(0, 0);
        final before = editing.selectedAnnotation!.rect;
        final name = editing.selectedAnnotation!.name;

        editing.autosizeSelectedTextBox();

        final expected = Rect.fromLTWH(
            original.left, original.top, lineWidth, lineHeight + size * 1.2);
        expectBox(g.toViewRect(editing.selectedAnnotation!.rect), expected);
        expect(editing.selectedAnnotation!.name, name);
        expect(editing.selectedAnnotation!.contents, 'Wide line\nshort');
        expect(editing.selectedTextStyle, (font: font, size: size));
        final reopened = PdfDocument.open(editing.bytes);
        expectBox(
            g.toViewRect(reopened.page(0).annotations.single.rect), expected);

        editing.undo();
        expectBox(
            g.toViewRect(editing.document.page(0).annotations.single.rect),
            g.toViewRect(before));
        editing.redo();
        expectBox(
            g.toViewRect(editing.document.page(0).annotations.single.rect),
            expected);
      });

      test('keeps a wrapped paragraph at its visible column width', () {
        const paragraph =
            'The quick brown fox jumps over the lazy dog and keeps on running';
        const column = Rect.fromLTWH(100, 100, 120, 400);
        final editing = create(rotation);
        final g = geometry(editing);
        editing
          ..addFreeText(0, g.toPageRect(column), paragraph)
          ..selectAnnotation(0, 0);
        final lines = pdfWrapText(paragraph, column.width - 6,
            (text) => measureStandardText(text, size, font: font));

        editing.autosizeSelectedTextBox();

        expectBox(
            g.toViewRect(editing.selectedAnnotation!.rect),
            Rect.fromLTWH(column.left, column.top, column.width,
                lineHeight + (lines.length - 1) * size * 1.2));
      });

      test('fits a callout box without moving its arrow tip', () {
        final editing = create(rotation);
        final g = geometry(editing);
        final target = g.toPagePoint(const Offset(40, 350));
        editing
          ..addCallout(0, g.toPageRect(original), 'Wide line', target)
          ..selectAnnotation(0, 0);
        final tip = editing.selectedAnnotation!.calloutLine!.first;

        editing.autosizeSelectedTextBox();

        final annotation = editing.selectedAnnotation!;
        expectBox(g.toViewRect(annotation.calloutBox!),
            Rect.fromLTWH(original.left, original.top, lineWidth, lineHeight));
        expect(annotation.calloutLine!.first, tip);
      });

      testWidgets('Alt+Z uses the rotated visible box dimensions',
          (tester) async {
        final editing = create(rotation);
        final g = geometry(editing);
        editing
          ..addFreeText(0, g.toPageRect(original), 'Wide line')
          ..selectAnnotation(0, 0);
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
        await tester.tapAt(const Offset(400, 400),
            kind: PointerDeviceKind.mouse);
        editing.selectAnnotation(0, 0);
        await tester.pump();

        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
        await tester.pump();

        expectBox(g.toViewRect(editing.selectedAnnotation!.rect),
            Rect.fromLTWH(original.left, original.top, lineWidth, lineHeight));
        await tester.pumpAndSettle(const Duration(milliseconds: 100));
      });
    });
  }
}
