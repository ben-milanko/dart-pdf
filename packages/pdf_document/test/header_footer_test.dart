import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

PdfDocument reopened(PdfEditor editor) => PdfDocument.open(editor.save());

/// The text strings shown by a page's content stream, in order.
List<String> shownStrings(PdfDocument doc, int index) {
  final content = String.fromCharCodes(doc.page(index).contentBytes());
  return [
    for (final m in RegExp(r'\(((?:[^()\\]|\\.)*)\)\s*Tj').allMatches(content))
      m.group(1)!
  ];
}

void main() {
  group('headers and footers', () {
    test('stamps page-number tokens across every page', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(3)))
        ..stampHeaderFooter(
            footer: const PdfHeaderFooter(center: 'Page {page} of {pages}'));
      final out = reopened(editor);
      expect(shownStrings(out, 0), contains('Page 1 of 3'));
      expect(shownStrings(out, 1), contains('Page 2 of 3'));
      expect(shownStrings(out, 2), contains('Page 3 of 3'));
    });

    test('left/center/right slots all render', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)))
        ..stampHeaderFooter(
            header: const PdfHeaderFooter(
                left: 'Left', center: 'Center', right: 'Right'));
      final shown = shownStrings(reopened(editor), 0);
      expect(shown, containsAll(['Left', 'Center', 'Right']));
    });

    test('the {date} token expands', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)))
        ..stampHeaderFooter(
            footer: const PdfHeaderFooter(left: 'Printed {date}'),
            date: DateTime.utc(2026, 6, 22));
      expect(shownStrings(reopened(editor), 0), contains('Printed 2026-06-22'));
    });

    test('the {label} token honours page labels', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(3)))
        ..setPageLabel(0, style: PdfPageLabelStyle.romanLower)
        ..stampHeaderFooter(footer: const PdfHeaderFooter(center: '{label}'));
      final out = reopened(editor);
      expect(shownStrings(out, 0), contains('i'));
      expect(shownStrings(out, 1), contains('ii'));
    });

    test('a page range limits stamping', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(4)))
        ..stampHeaderFooter(
            footer: const PdfHeaderFooter(center: 'F{page}'),
            fromPage: 1,
            toPage: 2);
      final out = reopened(editor);
      expect(shownStrings(out, 0), isNot(contains('F1')));
      expect(shownStrings(out, 1), contains('F2'));
      expect(shownStrings(out, 2), contains('F3'));
      expect(shownStrings(out, 3), isNot(contains('F4')));
    });

    test('the original page content survives alongside the stamp', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)))
        ..stampHeaderFooter(
            footer: const PdfHeaderFooter(center: 'Footer'));
      final shown = shownStrings(reopened(editor), 0);
      expect(shown, containsAll(['Page 1', 'Footer']));
    });

    test('saves are incremental: original bytes survive verbatim', () {
      final original = buildMultiPagePdf(2);
      final editor = PdfEditor(PdfDocument.open(original))
        ..stampHeaderFooter(
            header: const PdfHeaderFooter(left: 'Hdr'));
      final saved = editor.save();
      expect(saved.sublist(0, original.length), original);
    });
  });
}
