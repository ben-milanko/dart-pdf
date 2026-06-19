import 'dart:io';
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The TrueType fixture lives in pdf_document's test tree.
final _fontBytes =
    File('../pdf_document/test/fonts/DejaVuSans.ttf').readAsBytesSync();

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  String daOf(PdfEditingController c, PdfAnnotation a) =>
      (c.document.cos.resolve(a.dict['DA']) as CosString).text;

  bool isType0(PdfEditingController c, PdfAnnotation a) {
    final res = c.document.cos
        .resolve(a.normalAppearance!.dictionary['Resources']) as CosDictionary;
    final fonts = c.document.cos.resolve(res['Font']) as CosDictionary;
    final f = c.document.cos.resolve(fonts.entries.values.first);
    return f is CosDictionary &&
        (c.document.cos.resolve(f['Subtype']) as CosName?)?.value == 'Type0';
  }

  group('controller font selection', () {
    test('setCustomFont parses a font and embeds it in new free text', () {
      final c = PdfEditingController(buildMultiPagePdf(1));
      expect(c.setCustomFont(_fontBytes), isTrue);
      expect(c.activeFont, isNotNull);
      expect(c.activeFontLabel, contains('DejaVu'));

      c.addFreeText(0, const PdfRect(72, 600, 300, 660), 'Hello');
      final a = c.document.page(0).annotations.last;
      expect(daOf(c, a), contains('/F0'));
      expect(isType0(c, a), isTrue);
    });

    test('setCustomFont rejects non-font bytes', () {
      final c = PdfEditingController(buildMultiPagePdf(1));
      expect(c.setCustomFont(Uint8List(8)), isFalse);
      expect(c.activeFont, isNull);
    });

    test('selecting a standard family clears the active embedded font', () {
      final c = PdfEditingController(buildMultiPagePdf(1))
        ..setCustomFont(_fontBytes);
      expect(c.activeFont, isNotNull);
      c.fontFamily = PdfStandardFont.times;
      expect(c.activeFont, isNull);

      c.addFreeText(0, const PdfRect(72, 600, 300, 660), 'Times');
      final a = c.document.page(0).annotations.last;
      expect(daOf(c, a), contains('/TiRo'));
    });

    test('editing an embedded-font box keeps its font, not Helvetica', () {
      final c = PdfEditingController(buildMultiPagePdf(1))
        ..setCustomFont(_fontBytes);
      c.addFreeText(0, const PdfRect(72, 600, 300, 660), 'first');
      c.selectAnnotation(0, c.document.page(0).annotations.length - 1);
      c.setSelectedText('edited text');

      final a = c.document.page(0).annotations.last;
      expect(a.contents, 'edited text');
      // Still the embedded font — not reverted to /Helv.
      expect(daOf(c, a), contains('/F0'));
      expect(isType0(c, a), isTrue);
    });

    test('restyleSelectedFont switches a selected box to an embedded font',
        () {
      final c = PdfEditingController(buildMultiPagePdf(1));
      c.addFreeText(0, const PdfRect(72, 600, 300, 660), 'plain');
      final a0 = c.document.page(0).annotations.last;
      expect(daOf(c, a0), contains('/Helv'));

      c.selectAnnotation(0, c.document.page(0).annotations.length - 1);
      c.restyleSelectedFont(PdfEmbeddedFont.parse(_fontBytes));
      final a1 = c.document.page(0).annotations.last;
      expect(isType0(c, a1), isTrue);
    });

    test('placeFreeText respects the active embedded font', () {
      final c = PdfEditingController(buildMultiPagePdf(1))
        ..setCustomFont(_fontBytes);

      expect(c.placeFreeText(0, 180, 620, 'pasted'), isTrue);

      final a = c.document.page(0).annotations.last;
      expect(daOf(c, a), contains('/F0'));
      expect(isType0(c, a), isTrue);
    });
  });

  group('font menu UI', () {
    Future<void> pumpButton(WidgetTester tester, PdfEditingController c,
        {PdfFontPicker? picker}) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: ListenableBuilder(
              listenable: c,
              builder: (_, __) =>
                  PdfFontMenuButton(controller: c, fontPicker: picker),
            ),
          ),
        ),
      ));
    }

    testWidgets('shows the active font and opens a menu of choices',
        (tester) async {
      final c = PdfEditingController(buildMultiPagePdf(1));
      await pumpButton(tester, c);
      expect(find.byKey(const ValueKey('pdf-font-menu')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pdf-font-menu')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pdf-font-std-serif')), findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-font-bundled-0')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pdf-font-std-serif')));
      await tester.pumpAndSettle();
      expect(c.fontFamily.family, PdfStandardFontFamily.serif);
    });

    testWidgets('the Load font… entry runs the picker and sets the font',
        (tester) async {
      final c = PdfEditingController(buildMultiPagePdf(1));
      await pumpButton(tester, c, picker: (_) async => _fontBytes);

      await tester.tap(find.byKey(const ValueKey('pdf-font-menu')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pdf-font-load')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pdf-font-load')));
      await tester.pumpAndSettle();
      expect(c.activeFont, isNotNull);
      expect(c.activeFontLabel, contains('DejaVu'));
    });

    testWidgets('selecting a bundled font loads and embeds it',
        (tester) async {
      final c = PdfEditingController(buildMultiPagePdf(1));
      await pumpButton(tester, c);
      await tester.tap(find.byKey(const ValueKey('pdf-font-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pdf-font-bundled-1')));
      await tester.pumpAndSettle();
      // DejaVu Serif is the second bundled entry.
      expect(c.activeFont, isNotNull);
      expect(c.activeFontLabel, contains('DejaVu'));
    });

    testWidgets('without a picker, Load font… is absent', (tester) async {
      final c = PdfEditingController(buildMultiPagePdf(1));
      await pumpButton(tester, c);
      await tester.tap(find.byKey(const ValueKey('pdf-font-menu')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pdf-font-load')), findsNothing);
    });
  });
}
