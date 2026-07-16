import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

void main() {
  group('PdfTaggedText (structure + text join)', () {
    late PdfDocument doc;
    setUp(() => doc = PdfDocument.open(buildTaggedPdf()));

    test('returns null for untagged documents', () {
      expect(PdfTaggedText.extract(PdfDocument.open(buildClassicPdf())), isNull);
    });

    test('joins MCID-tagged text onto structure elements', () {
      final logical = PdfTaggedText.extract(doc)!;
      final byType = {
        for (final n in logical.nodesInReadingOrder) n.structureType: n
      };
      expect(byType['Title']!.text, 'Heading One');
      expect(byType['Title']!.standardType, 'H1');
      expect(byType['P']!.text, 'Body paragraph text.');
      // The figure tags a rectangle (no text) - accessibleText falls back to
      // /ActualText then /Alt.
      expect(byType['Figure']!.text, isEmpty);
      expect(byType['Figure']!.accessibleText, 'Figure 1');
    });

    test('full reading-order text walks the whole tree', () {
      final logical = PdfTaggedText.extract(doc)!;
      expect(
        logical.text,
        'Heading One\nBody paragraph text.\nFigure 1',
      );
    });

    test('text runs carry their MCID through extraction', () {
      final page = PdfTextExtractor.extract(doc, 0);
      final tagged = page.runs.where((r) => r.mcid != null).toList();
      expect(tagged, isNotEmpty);
      expect(tagged.map((r) => r.mcid).toSet(), containsAll([0, 1]));
    });
  });
}
