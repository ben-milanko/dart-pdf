import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

/// One-page Helvetica PDF whose content stream is [content].
Uint8List buildParagraphPdf(String content) {
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R '
        '/Resources << /Font << /F1 5 0 R >> >> >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xrefOffset = buffer.length;
  buffer
    ..write('xref\n0 ${objects.length + 1}\n')
    ..write('0000000000 65535 f \n');
  for (final offset in offsets) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer
    ..write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n')
    ..write('startxref\n$xrefOffset\n%%EOF\n');
  return ascii(buffer.toString());
}

/// A two-line body paragraph (group A) followed, after a gap, by a footer
/// line reached relatively so it cascades.
const paragraphContent = 'BT /F1 12 Tf 14 TL 72 700 Td '
    '(Alpha beta gamma delta) Tj '
    'T* (epsilon zeta eta theta) Tj '
    '0 -28 Td (Footer line here) Tj ET';

/// Selects the page-content text element whose [PdfContentElement.text]
/// equals [text] by hit-testing its bounds centre.
bool selectElementByText(PdfEditingController editing, String text) {
  final element = editing
      .elementsOn(0)
      .elements
      .firstWhere((e) => e.kind == PdfElementKind.text && e.text == text);
  final b = element.bounds!;
  return editing.selectElementAt(
      0, (b.left + b.right) / 2, (b.bottom + b.top) / 2);
}

List<({String text, double bottom})> textRuns(PdfDocument doc) => [
      for (final e in PdfPageElements.of(doc, 0).elements)
        if (e.kind == PdfElementKind.text && e.bounds != null)
          (text: e.text!, bottom: e.bounds!.bottom),
    ];

void main() {
  group('reflowSelectedElementText (controller)', () {
    test('grows the paragraph and cascades the following line', () {
      final editing = PdfEditingController(buildParagraphPdf(paragraphContent));
      addTearDown(editing.dispose);

      final footerBefore = textRuns(editing.document)
          .firstWhere((r) => r.text == 'Footer line here')
          .bottom;

      expect(selectElementByText(editing, 'Alpha beta gamma delta'), isTrue);
      final reflowed = editing.reflowSelectedElementText(
          'Alpha beta gamma delta plus a good many more words to wrap onto '
          'another line entirely');
      expect(reflowed, isTrue);
      expect(editing.isModified, isTrue);

      final after = textRuns(editing.document);
      // the body grew past its original two lines …
      final body = after.where((r) => !r.text.startsWith('Footer')).toList();
      expect(body.length, greaterThan(2));
      // … the footer is unchanged in text and dropped to make room …
      final footerAfter =
          after.firstWhere((r) => r.text == 'Footer line here').bottom;
      expect(footerAfter, lessThan(footerBefore));
      // … and the edited paragraph reads back correctly.
      final joined =
          body.map((r) => r.text).join(' ').replaceAll(RegExp(r'\s+'), ' ');
      expect(
          joined,
          'Alpha beta gamma delta plus a good many more words to wrap onto '
          'another line entirely epsilon zeta eta theta');
    });

    test('returns false and changes nothing when there is no selection', () {
      final editing = PdfEditingController(buildParagraphPdf(paragraphContent));
      addTearDown(editing.dispose);
      expect(editing.reflowSelectedElementText('whatever'), isFalse);
      expect(editing.isModified, isFalse);
    });

    test('returns false (no-op) for an unreflowable shape', () {
      // a single rotated line is not a reflowable paragraph
      final editing = PdfEditingController(buildParagraphPdf(
          'BT /F1 12 Tf 0.7 0.7 -0.7 0.7 72 700 Tm (rotated heading) Tj ET'));
      addTearDown(editing.dispose);
      expect(selectElementByText(editing, 'rotated heading'), isTrue);
      expect(editing.reflowSelectedElementText('rotated heading longer now'),
          isFalse);
      expect(editing.isModified, isFalse);
    });
  });

  group('Reflow paragraph toolbar action', () {
    Future<PdfEditingController> pumpToolbar(
      WidgetTester tester, {
      required PdfTextPrompt textPrompt,
    }) async {
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
              textPrompt: textPrompt,
            ),
          ),
        ),
      ));
      await tester.pump();
      return editing;
    }

    testWidgets('the strip exposes Reflow paragraph for a selected text element',
        (tester) async {
      var prompted = false;
      final editing = await pumpToolbar(
        tester,
        textPrompt: (context, {required title, initial = '', multiline = false}) async {
          prompted = true;
          // a paragraph prompt opens multiline, pre-filled with the line
          expect(title, 'Reflow paragraph');
          expect(multiline, isTrue);
          expect(initial, 'Alpha beta gamma delta');
          return '$initial plus several more words that force another wrapped line';
        },
      );

      editing.tool = PdfEditTool.content;
      expect(selectElementByText(editing, 'Alpha beta gamma delta'), isTrue);
      await tester.pump();

      final button = find.byKey(const ValueKey('pdf-reflow-element-text'));
      expect(button, findsOneWidget);

      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(prompted, isTrue);
      expect(editing.isModified, isTrue);
      final lines = PdfPageElements.of(editing.document, 0)
          .elements
          .where((e) => e.kind == PdfElementKind.text && !e.text!.startsWith('Footer'))
          .length;
      expect(lines, greaterThan(2), reason: 'the paragraph re-wrapped longer');
    });

    testWidgets('an unreflowable selection shows a fallback hint', (tester) async {
      final editing = await pumpToolbar(
        tester,
        textPrompt: (context, {required title, initial = '', multiline = false}) async =>
            'Footer line here grown so long it would need a second wrapped line',
      );
      editing.tool = PdfEditTool.content;
      // the trailing footer is a one-line block with nothing after it to
      // cascade into, so growing it by a line can't reflow safely → bails
      expect(selectElementByText(editing, 'Footer line here'), isTrue);
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('pdf-reflow-element-text')));
      await tester.pumpAndSettle();

      expect(editing.isModified, isFalse, reason: 'a bailed reflow changes nothing');
      expect(find.textContaining("Couldn't reflow"), findsOneWidget);
    });
  });
}
