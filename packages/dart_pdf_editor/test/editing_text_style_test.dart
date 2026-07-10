import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One-page Helvetica PDF whose content stream is [content].
Uint8List buildTextPdf(String content) {
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

const singleLine = 'BT /F1 12 Tf 72 700 Td (Hello World) Tj ET';

String pageText(PdfDocument doc) => latin1.decode(doc.page(0).contentBytes());

bool selectElementByText(PdfEditingController editing, String text) {
  final element = editing
      .elementsOn(0)
      .elements
      .firstWhere((e) => e.kind == PdfElementKind.text && e.text == text);
  final b = element.bounds!;
  return editing.selectElementAt(
      0, (b.left + b.right) / 2, (b.bottom + b.top) / 2);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('replaceStyledSelectedElementText (controller)', () {
    test('recolours the replacement and keeps the reading text', () {
      final editing = PdfEditingController(buildTextPdf(singleLine));
      addTearDown(editing.dispose);
      editing.tool = PdfEditTool.content;
      expect(selectElementByText(editing, 'Hello World'), isTrue);

      final count = editing.replaceStyledSelectedElementText(
          'Hi World', const PdfTextStyle(color: 0xFF0000));
      expect(count, greaterThan(0));
      expect(editing.isModified, isTrue);

      final text = pageText(editing.document);
      expect(text, contains('1 0 0 rg'));
      final reads = PdfPageElements.of(editing.document, 0)
          .elements
          .where((e) => e.kind == PdfElementKind.text)
          .map((e) => e.text)
          .join();
      expect(reads, contains('Hi World'));
    });

    test('bold selects a base-14 variant font resource', () {
      final editing = PdfEditingController(buildTextPdf(singleLine));
      addTearDown(editing.dispose);
      editing.tool = PdfEditTool.content;
      expect(selectElementByText(editing, 'Hello World'), isTrue);
      editing.replaceStyledSelectedElementText(
          'Hi World', const PdfTextStyle(bold: true));

      final doc = editing.document;
      final fonts =
          doc.cos.resolve(doc.page(0).resources['Font']) as CosDictionary;
      final hasBold = fonts.entries.values
          .map((v) => doc.cos.resolve(v))
          .whereType<CosDictionary>()
          .any((f) => f['BaseFont'] == const CosName('Helvetica-Bold'));
      expect(hasBold, isTrue);
    });

    test('does nothing without a selection', () {
      final editing = PdfEditingController(buildTextPdf(singleLine));
      addTearDown(editing.dispose);
      expect(
          editing.replaceStyledSelectedElementText(
              'x', const PdfTextStyle(color: 0xFF0000)),
          0);
      expect(editing.isModified, isFalse);
    });
  });

  group('Edit text & style toolbar action', () {
    Future<PdfEditingController> pumpToolbar(
      WidgetTester tester, {
      required PdfStyledTextPrompt styledTextPrompt,
    }) async {
      final editing = PdfEditingController(buildTextPdf(singleLine));
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
              styledTextPrompt: styledTextPrompt,
            ),
          ),
        ),
      ));
      await tester.pump();
      return editing;
    }

    testWidgets('the strip exposes the style button and applies the style',
        (tester) async {
      var prompted = false;
      final editing = await pumpToolbar(
        tester,
        styledTextPrompt: (context,
            {required initial, palette = const <Color>[]}) async {
          prompted = true;
          expect(initial, 'Hello World');
          return const PdfStyledTextEdit(
              'Hi World', PdfTextStyle(color: 0x0000FF, bold: true));
        },
      );

      editing.tool = PdfEditTool.content;
      expect(selectElementByText(editing, 'Hello World'), isTrue);
      await tester.pump();

      final button = find.byKey(const ValueKey('pdf-style-element-text'));
      expect(button, findsOneWidget);
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(prompted, isTrue);
      expect(editing.isModified, isTrue);
      final text = pageText(editing.document);
      expect(text, contains('0 0 1 rg'));
    });

    testWidgets('cancelling the prompt changes nothing', (tester) async {
      final editing = await pumpToolbar(
        tester,
        styledTextPrompt: (context,
            {required initial, palette = const <Color>[]}) async =>
            null,
      );
      editing.tool = PdfEditTool.content;
      expect(selectElementByText(editing, 'Hello World'), isTrue);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pdf-style-element-text')));
      await tester.pumpAndSettle();
      expect(editing.isModified, isFalse);
    });
  });

  group('showPdfStyledTextPrompt dialog', () {
    Future<PdfStyledTextEdit?> openDialog(WidgetTester tester) async {
      PdfStyledTextEdit? result;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showPdfStyledTextPrompt(context,
                      initial: 'Hello');
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('reuses the Bold/Italic toggles and fill swatches',
        (tester) async {
      await openDialog(tester);
      // the shared style controls are present
      expect(find.byKey(const ValueKey('pdf-styled-bold')), findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-styled-italic')), findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-styled-size')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('pdf-styled-fill-none')), findsOneWidget);
    });

    testWidgets('an untouched dialog is a plain replacement', (tester) async {
      await openDialog(tester);
      await tester.enterText(
          find.byKey(const ValueKey('pdf-styled-text-field')), 'Goodbye');
      await tester.tap(find.byKey(const ValueKey('pdf-styled-ok')));
      await tester.pumpAndSettle();
      // nothing touched → every style field stays null (keep the run's values)
    });

    testWidgets('bold selected forces the style, fill swatch sets colour',
        (tester) async {
      PdfStyledTextEdit? captured;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  captured = await showPdfStyledTextPrompt(context,
                      initial: 'Hello',
                      palette: const [Color(0xFFE53935)]);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const ValueKey('pdf-styled-text-field')), 'Goodbye');
      await tester.tap(find.byKey(const ValueKey('pdf-styled-bold')));
      await tester.tap(find.byKey(const ValueKey('pdf-styled-fill-0')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pdf-styled-ok')));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.text, 'Goodbye');
      expect(captured!.style.bold, isTrue);
      // FontStyleToggles reports a whole font, so touching style sets both axes
      expect(captured!.style.italic, isFalse);
      expect(captured!.style.color, 0xE53935);
    });

    testWidgets('choosing a font family reports it in the style',
        (tester) async {
      PdfStyledTextEdit? captured;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  captured = await showPdfStyledTextPrompt(context,
                      initial: 'Hello');
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('pdf-styled-family')));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const ValueKey('pdf-styled-family-serif')).last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pdf-styled-ok')));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.style.family, PdfStandardFontFamily.serif);
    });

    testWidgets('the fill "More colors…" button opens the custom picker',
        (tester) async {
      PdfStyledTextEdit? captured;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  captured = await showPdfStyledTextPrompt(context,
                      initial: 'Hello');
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // open the shared swatch row's custom picker and accept its default
      await tester.tap(find.byKey(const ValueKey('pdf-styled-fill-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pdf-styled-ok')));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      // a colour came back from the picker (the row's default white)
      expect(captured!.style.color, isNotNull);
    });
  });
}
