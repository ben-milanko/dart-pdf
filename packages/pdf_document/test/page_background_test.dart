import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

String content(PdfDocument doc, int index) =>
    String.fromCharCodes(doc.page(index).contentBytes());

final _fill = RegExp(r'rg [-\d. ]+ re f');

void main() {
  group('fillPageBackground', () {
    test('paints the colour behind the existing content on every page', () {
      final source = PdfDocument.open(buildMultiPagePdf(2));
      final before = content(source, 1);
      final editor = PdfEditor(source)..fillPageBackground(0xFFEECC);
      final out = PdfDocument.open(editor.save());
      for (var i = 0; i < 2; i++) {
        final text = content(out, i);
        expect(text, startsWith(PdfPageBackgroundEditing.backgroundMarker));
        expect(text, contains('/Artifact <</Type /Background>> BDC'));
        expect(text, contains('q 1 0.933 0.8 rg 0 0 612 792 re f Q'));
      }
      // the original drawing follows the fill, untouched
      expect(content(out, 1), endsWith(before));
    });

    test('re-baking replaces the earlier fill instead of stacking', () {
      final first = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)))
        ..fillPageBackground(0x112233);
      final second = PdfEditor(PdfDocument.open(first.save()))
        ..fillPageBackground(0xFFFFFF);
      final text = content(PdfDocument.open(second.save()), 0);
      expect(_fill.allMatches(text), hasLength(1));
      expect(text, contains('q 1 1 1 rg'));
    });

    test('respects a page range', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(3)))
        ..fillPageBackground(0x000000, fromPage: 1, toPage: 1);
      final out = PdfDocument.open(editor.save());
      expect(_fill.hasMatch(content(out, 0)), isFalse);
      expect(_fill.hasMatch(content(out, 1)), isTrue);
      expect(_fill.hasMatch(content(out, 2)), isFalse);
    });

    test('a later stamp still draws on top of the fill', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)))
        ..stampPage(0, (s) => s.text('Over', x: 10, y: 10))
        ..fillPageBackground(0x336699);
      final text = content(PdfDocument.open(editor.save()), 0);
      expect(text.indexOf('re f'), lessThan(text.indexOf('(Over)')));
    });
  });
}
