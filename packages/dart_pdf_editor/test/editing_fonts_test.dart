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

/// The bundled font catalogue now ships in `dart_pdf_editor_assets`, so this
/// package's tests can't reach it through the asset bundle. Register the same
/// six faces backed by the moved asset files (read synchronously, so the loader
/// future completes on the microtask queue `pumpAndSettle` drains - no real
/// I/O the fake clock wouldn't wait for). Mirrors what
/// `registerBundledEditorAssets()` does at runtime.
const _assetFontDir = '../dart_pdf_editor_assets/assets/fonts';
List<PdfBundledFont> _registerBundledFontCatalogue() {
  PdfBundledFont face(String label, String file) => PdfBundledFont(
        label,
        'test:$file',
        loadBytes: () async => File('$_assetFontDir/$file').readAsBytesSync(),
      );
  return [
    face('DejaVu Sans', 'DejaVuSans.ttf'),
    face('DejaVu Serif', 'DejaVuSerif.ttf'),
    face('DejaVu Sans Mono', 'DejaVuSansMono.ttf'),
    face('Fira Sans', 'FiraSans-Regular.ttf'),
    face('Spectral', 'Spectral-Regular.ttf'),
    face('Lobster', 'Lobster-Regular.ttf'),
  ];
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // The bundled catalogue is opt-in (empty by default); populate it so the
    // font-menu and fallback tests exercise the registered path.
    pdfBundledFonts = _registerBundledFontCatalogue();
  });
  // The font registries are module-global (a host fills them once at startup);
  // reset them so a test that populates them can't leak into others.
  tearDown(() {
    pdfPlatformFonts = const [];
    pdfBundledFonts = const [];
  });

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

  group('bundled fallback fonts', () {
    testWidgets('loadFallbackFonts resolves the DejaVu trio from assets',
        (tester) async {
      // a missing/renamed asset would silently disable composite-text
      // fallback, so assert the bundled faces load and parse.
      late List<PdfEmbeddedFont> fonts;
      await tester.runAsync(() async => fonts = await loadFallbackFonts());
      expect(fonts.map((f) => f.familyName).join(' '),
          allOf(contains('Sans'), contains('Serif'), contains('Mono')));
      // each carries real glyphs (a Latin letter resolves)
      for (final f in fonts) {
        expect(f.glyphForRune('A'.codeUnitAt(0)), greaterThan(0));
      }
    });
  });

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
      // Still the embedded font - not reverted to /Helv.
      expect(daOf(c, a), contains('/F0'));
      expect(isType0(c, a), isTrue);
    });

    test('restyleSelectedFont switches a selected box to an embedded font', () {
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

    testWidgets('font choices can be searched', (tester) async {
      final c = PdfEditingController(buildMultiPagePdf(1));
      await pumpButton(tester, c);

      await tester.tap(find.byKey(const ValueKey('pdf-font-menu')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pdf-font-search')), findsOneWidget);

      await tester.enterText(
          find.byKey(const ValueKey('pdf-font-search')), 'spect');
      await tester.pump();
      expect(find.text('Spectral'), findsOneWidget);
      expect(find.text('DejaVu Sans'), findsNothing);
    });

    testWidgets('the Load font… entry runs the picker and sets the font',
        (tester) async {
      final c = PdfEditingController(buildMultiPagePdf(1));
      await pumpButton(tester, c, picker: (_) async => _fontBytes);

      await tester.tap(find.byKey(const ValueKey('pdf-font-menu')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('pdf-font-search')), 'load');
      await tester.pump();
      expect(find.byKey(const ValueKey('pdf-font-load')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pdf-font-load')));
      await tester.pumpAndSettle();
      expect(c.activeFont, isNotNull);
      expect(c.activeFontLabel, contains('DejaVu'));
    });

    testWidgets('selecting a bundled font loads and embeds it', (tester) async {
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

    testWidgets('platform fonts from the registry appear and embed on pick',
        (tester) async {
      // The host populates pdfPlatformFonts at startup; the menu picks it up
      // by default (no per-widget plumbing). Selecting one loads its bytes
      // lazily and embeds the outlines.
      pdfPlatformFonts = [
        PdfPlatformFont(
          label: 'Test Platform Sans',
          loadBytes: () async => _fontBytes,
        ),
      ];
      final c = PdfEditingController(buildMultiPagePdf(1));
      await pumpButton(tester, c);
      await tester.tap(find.byKey(const ValueKey('pdf-font-menu')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('pdf-font-search')), 'test platform');
      await tester.pump();
      expect(find.text('Test Platform Sans'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pdf-font-platform-0')));
      await tester.pumpAndSettle();
      expect(c.activeFont, isNotNull);
      expect(c.activeFontLabel, contains('DejaVu'));

      c.addFreeText(0, const PdfRect(72, 600, 300, 660), 'Hi');
      final a = c.document.page(0).annotations.last;
      expect(daOf(c, a), contains('/F0'));
      expect(isType0(c, a), isTrue);
    });

    testWidgets('an unreadable platform font leaves the font unchanged',
        (tester) async {
      pdfPlatformFonts = [
        PdfPlatformFont(label: 'Broken', loadBytes: () async => null),
      ];
      final c = PdfEditingController(buildMultiPagePdf(1));
      await pumpButton(tester, c);
      await tester.tap(find.byKey(const ValueKey('pdf-font-menu')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('pdf-font-search')), 'broken');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pdf-font-platform-0')));
      await tester.pumpAndSettle();
      expect(c.activeFont, isNull);
    });

    testWidgets('the search field is focused when the menu opens',
        (tester) async {
      final c = PdfEditingController(buildMultiPagePdf(1));
      await pumpButton(tester, c);
      await tester.tap(find.byKey(const ValueKey('pdf-font-menu')));
      await tester.pumpAndSettle();
      final editable = tester.widget<EditableText>(find.descendant(
        of: find.byKey(const ValueKey('pdf-font-search')),
        matching: find.byType(EditableText),
      ));
      expect(editable.focusNode.hasFocus, isTrue);
    });

    testWidgets('fonts embedded in the document are offered and embed on pick',
        (tester) async {
      // Author some free text in an embedded font so the document carries it,
      // then reopen: the font now appears under "In this document".
      final c = PdfEditingController(buildMultiPagePdf(1))
        ..setCustomFont(_fontBytes);
      c.addFreeText(0, const PdfRect(72, 600, 300, 660), 'Embedded');
      // Back to a standard family - the embedded face is only in the document.
      c.fontFamily = PdfStandardFont.helvetica;
      expect(c.activeFont, isNull);
      expect(c.documentFonts, isNotEmpty);

      await pumpButton(tester, c);
      await tester.tap(find.byKey(const ValueKey('pdf-font-menu')));
      await tester.pumpAndSettle();
      // It sits under its own "In this document" section header.
      expect(find.text('IN THIS DOCUMENT'), findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-font-document-0')), findsOneWidget);
      // DejaVu is a full font (covers the basic alphabet), so it is not
      // flagged "limited".
      expect(
          find.descendant(
            of: find.byKey(const ValueKey('pdf-font-document-0')),
            matching: find.text('Limited characters'),
          ),
          findsNothing);

      await tester.tap(find.byKey(const ValueKey('pdf-font-document-0')));
      await tester.pumpAndSettle();
      expect(c.activeFont, isNotNull);
      expect(c.activeFontLabel, contains('DejaVu'));
    });

    testWidgets('a document font row previews in its own registered face',
        (tester) async {
      final c = PdfEditingController(buildMultiPagePdf(1))
        ..setCustomFont(_fontBytes);
      c.addFreeText(0, const PdfRect(72, 600, 300, 660), 'Embedded');
      c.fontFamily = PdfStandardFont.helvetica;

      await pumpButton(tester, c);
      await tester.tap(find.byKey(const ValueKey('pdf-font-menu')));
      await tester.pumpAndSettle();
      final title = tester.widget<Text>(find.descendant(
        of: find.byKey(const ValueKey('pdf-font-document-0')),
        matching: find.byType(Text),
      ));
      // The row renders in the font's own registered preview family.
      expect(title.style?.fontFamily, startsWith('pdf-doc-font::'));
    });

    testWidgets('a picked font shows up under "Recently used" next time',
        (tester) async {
      final c = PdfEditingController(buildMultiPagePdf(1));
      await c.preferences.ready;
      await pumpButton(tester, c);

      // No recents yet on first open.
      await tester.tap(find.byKey(const ValueKey('pdf-font-menu')));
      await tester.pumpAndSettle();
      expect(find.text('RECENTLY USED'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('pdf-font-std-serif')));
      await tester.pumpAndSettle();
      expect(c.preferences.recentFonts, contains('std:serif'));

      // Reopen: Serif now heads the list in the recents group.
      await tester.tap(find.byKey(const ValueKey('pdf-font-menu')));
      await tester.pumpAndSettle();
      expect(find.text('RECENTLY USED'), findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-font-recent-0')), findsOneWidget);
      // Picking the recent entry applies the same choice.
      await tester.tap(find.byKey(const ValueKey('pdf-font-recent-0')));
      await tester.pumpAndSettle();
      expect(c.fontFamily.family, PdfStandardFontFamily.serif);
    });
  });
}
