import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

// The form-field highlight: a translucent wash + hairline border over
// every visible field widget, the way desktop editors mark fields. On by
// default, display-only, theme-able, and off with the annotations.
void main() {
  Future<void> pumpViewer(
    WidgetTester tester, {
    bool highlightFormFields = true,
    bool showAnnotations = true,
    PdfViewerThemeData? theme,
    PdfViewerController? controller,
  }) async {
    final document = PdfDocument.open(buildAcroFormPdf());
    final viewer = PdfViewer(
      initialFit: PdfViewerFit.width,
      document: document,
      controller: controller,
      highlightFormFields: highlightFormFields,
      showAnnotations: showAnnotations,
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body:
            theme == null ? viewer : PdfViewerTheme(data: theme, child: viewer),
      ),
    ));
    await tester.pump();
  }

  /// The field-highlight painter, found by type name (it's private to
  /// the viewer library).
  dynamic fieldPainter(WidgetTester tester) {
    for (final paint
        in tester.widgetList<CustomPaint>(find.byType(CustomPaint))) {
      final painter = paint.painter;
      if (painter.runtimeType.toString() == '_FormFieldPainter') {
        return painter;
      }
    }
    return null;
  }

  testWidgets('field widgets are washed by default', (tester) async {
    await pumpViewer(tester);
    final painter = fieldPainter(tester);
    expect(painter, isNotNull);
    // all seven widgets on the fixture page (text ×2, checkbox, two
    // radio kids, combo, read-only text)
    expect(painter.fields, hasLength(7));
    expect(painter.fields,
        contains(const PdfRect(72, 700, 300, 724))); // the 'name' field
  });

  testWidgets('highlightFormFields: false removes the wash', (tester) async {
    await pumpViewer(tester, highlightFormFields: false);
    expect(fieldPainter(tester), isNull);
  });

  testWidgets('hiding annotations hides the wash too', (tester) async {
    await pumpViewer(tester, showAnnotations: false);
    expect(fieldPainter(tester), isNull);
  });

  testWidgets('the theme recolors the wash', (tester) async {
    const tint = Color(0x3300A040);
    await pumpViewer(tester,
        theme: const PdfViewerThemeData(formFieldHighlightColor: tint));
    final painter = fieldPainter(tester);
    expect(painter, isNotNull);
    expect(painter.theme.formFieldHighlightColor, tint);
  });

  testWidgets('the highlight border counter-scales while zoomed',
      (tester) async {
    final controller = PdfViewerController();
    addTearDown(controller.dispose);
    await pumpViewer(tester, controller: controller);
    controller.setZoom(2 * 800 / 612);
    await tester.pump();

    final painter = fieldPainter(tester);
    expect(painter, isNotNull);
    expect(painter.chromeScale, closeTo(0.5, 0.01));
  });

  testWidgets('a page without fields paints no wash', (tester) async {
    final document = PdfDocument.open(buildMultiPagePdf(1));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          initialFit: PdfViewerFit.width,
          document: document,
        ),
      ),
    ));
    await tester.pump();
    expect(fieldPainter(tester), isNull);
  });

  testWidgets(
      'flattening clears cached field highlights and undo restores them',
      (tester) async {
    final editing = PdfEditingController(buildAcroFormPdf());
    addTearDown(editing.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          initialFit: PdfViewerFit.width,
          document: editing.document,
          editing: editing,
        ),
      ),
    ));
    await tester.pump();
    expect(fieldPainter(tester), isNotNull);

    expect(editing.flattenDocument(), isTrue);
    await tester.pump();
    expect(fieldPainter(tester), isNull);

    editing.undo();
    await tester.pump();
    expect(fieldPainter(tester), isNotNull);
  });
}
