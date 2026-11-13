import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'editing_reflow_test.dart'
    show buildParagraphPdf, paragraphContent, selectElementByText;

List<String> pageTexts(PdfDocument doc) => [
      for (final e in PdfPageElements.of(doc, 0).elements)
        if (e.kind == PdfElementKind.text) e.text!,
    ];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('convertSelectedElementTextToFreeText', () {
    test('moves the run out of the content stream into a FreeText box', () {
      final editing = PdfEditingController(buildParagraphPdf(
          'BT /F1 18 Tf 0 0 1 rg 72 700 Td (Hello there) Tj ET '
          'BT /F1 12 Tf 72 600 Td (Stays put) Tj ET'));
      addTearDown(editing.dispose);
      final original = editing
          .elementsOn(0)
          .elements
          .firstWhere((e) => e.text == 'Hello there')
          .bounds!;

      expect(selectElementByText(editing, 'Hello there'), isTrue);
      expect(editing.convertSelectedElementTextToFreeText(), isTrue);

      final doc = editing.document;
      expect(pageTexts(doc), ['Stays put']);
      final annots = doc.page(0).annotations;
      expect(annots, hasLength(1));
      final annot = annots.single;
      expect(annot.subtype, 'FreeText');
      expect(annot.contents, 'Hello there');
      final style = annot.freeTextStyle!;
      expect(style.fontSize, 18);
      expect(style.color, 0x0000FF);
      expect(style.fillColor, isNull);
      // the box covers where the run drew
      expect(annot.rect.left, lessThanOrEqualTo(original.left));
      expect(annot.rect.right, greaterThanOrEqualTo(original.right));
      expect(annot.rect.bottom, lessThanOrEqualTo(original.bottom));
      expect(annot.rect.top, greaterThanOrEqualTo(original.top));

      // the new annotation is selected for immediate moving/restyling
      expect(editing.selectedElement, isNull);
      expect(editing.tool, PdfEditTool.select);
      expect(editing.selectedAnnotationSlot, (0, 0));

      // one undo step restores the page content
      editing.undo();
      expect(pageTexts(editing.document), ['Hello there', 'Stays put']);
      expect(editing.document.page(0).annotations, isEmpty);
    });

    test('scales the size through the text matrix and keeps colour scope', () {
      final editing = PdfEditingController(buildParagraphPdf(
          'q 1 0 0 rg Q BT /F1 1 Tf 24 0 0 24 72 700 Tm (Big) Tj ET'));
      addTearDown(editing.dispose);
      expect(selectElementByText(editing, 'Big'), isTrue);
      expect(editing.convertSelectedElementTextToFreeText(), isTrue);
      final style = editing.document.page(0).annotations.single.freeTextStyle!;
      expect(style.fontSize, 24);
      expect(style.color, 0x000000); // the red was popped by Q
    });

    test('returns false and changes nothing without a text selection', () {
      final editing = PdfEditingController(
          buildParagraphPdf('BT /F1 12 Tf 72 700 Td (Text) Tj ET'));
      addTearDown(editing.dispose);
      expect(editing.convertSelectedElementTextToFreeText(), isFalse);
      expect(editing.isModified, isFalse);
    });
  });

  testWidgets('the element strip converts the selected text to a text box',
      (tester) async {
    final editing = PdfEditingController(buildParagraphPdf(paragraphContent));
    final viewer = PdfViewerController();
    addTearDown(editing.dispose);
    addTearDown(viewer.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: const SizedBox.expand(),
        bottomNavigationBar: ListenableBuilder(
          listenable: editing,
          builder: (context, _) => PdfEditingToolbar(
            controller: editing,
            viewerController: viewer,
          ),
        ),
      ),
    ));
    editing.tool = PdfEditTool.content;
    expect(selectElementByText(editing, 'Footer line here'), isTrue);
    await tester.pump();

    final button =
        find.byKey(const ValueKey('pdf-convert-element-text-to-free-text'));
    expect(button, findsOneWidget);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(pageTexts(editing.document), isNot(contains('Footer line here')));
    expect(editing.document.page(0).annotations.single.contents,
        'Footer line here');
  });
}
