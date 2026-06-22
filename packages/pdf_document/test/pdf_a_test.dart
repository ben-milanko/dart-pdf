import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

void main() {
  group('validatePdfA', () {
    test('a plain PDF fails on the core archival requirements', () {
      final report = validatePdfA(PdfDocument.open(buildClassicPdf()));
      expect(report.isCompliant, isFalse);
      final rules = report.errors.map((e) => e.rule).toSet();
      expect(rules, contains('A2:6.1.3')); // no /ID
      expect(rules, contains('A2:6.2.2')); // no OutputIntent
      expect(rules, contains('A2:6.7.2')); // no XMP
      expect(rules, contains('A2:6.3.4')); // Helvetica not embedded
    });

    test('a converted embedded-font PDF passes PDF/A-2b', () {
      final doc = PdfDocument.open(buildEmbeddedFontPdf());
      final editor = PdfEditor(doc)
        ..convertToPdfA(
          iccProfile: adobeRgb1998Icc(),
          iccComponents: 3,
          part: 2,
          level: 'B',
          title: 'Embedded Font Sample',
          outputConditionIdentifier: 'Adobe RGB (1998)',
        );
      final out = PdfDocument.open(editor.save());
      final report = validatePdfA(out, part: 2, level: 'B');
      expect(report.isCompliant, isTrue, reason: report.summary());
    });

    test('conversion adds OutputIntent, XMP, ID, and version', () {
      final doc = PdfDocument.open(buildEmbeddedFontPdf());
      final editor = PdfEditor(doc)
        ..convertToPdfA(iccProfile: adobeRgb1998Icc(), title: 'T');
      final out = PdfDocument.open(editor.save());

      expect(out.cos.resolve(out.catalog['OutputIntents']), isA<CosArray>());
      expect(out.cos.resolve(out.catalog['Metadata']), isA<CosStream>());
      expect(out.cos.resolve(out.cos.trailer['ID']), isA<CosArray>());
      final v = out.cos.resolve(out.catalog['Version']);
      expect((v as CosName).value, '1.7');
    });

    test('conversion does not invent font embedding', () {
      // Converting a base-14 (non-embedded Helvetica) PDF satisfies the
      // structural rules but the font check still fails — proving we do not
      // claim more than we deliver.
      final doc = PdfDocument.open(buildClassicPdf());
      final editor = PdfEditor(doc)
        ..convertToPdfA(iccProfile: adobeRgb1998Icc(), title: 'T');
      final report = validatePdfA(PdfDocument.open(editor.save()));
      final rules = report.errors.map((e) => e.rule).toSet();
      expect(rules, isNot(contains('A2:6.2.2'))); // OutputIntent now present
      expect(rules, isNot(contains('A2:6.7.2'))); // XMP now present
      expect(rules, contains('A2:6.3.4')); // font still not embedded
    });

    test('refuses to convert an encrypted document', () {
      final doc = PdfDocument.open(buildEncryptedPdf());
      final editor = PdfEditor(doc);
      expect(
          () => editor.convertToPdfA(iccProfile: adobeRgb1998Icc()),
          throwsStateError);
    });

    test('A-3 allows what A-2 needs; profile label reflects the part', () {
      final doc = PdfDocument.open(buildEmbeddedFontPdf());
      final editor = PdfEditor(doc)
        ..convertToPdfA(
            iccProfile: adobeRgb1998Icc(), part: 3, title: 'T3');
      final report =
          validatePdfA(PdfDocument.open(editor.save()), part: 3);
      expect(report.profile, 'PDF/A-3b');
      expect(report.isCompliant, isTrue, reason: report.summary());
    });

    test('XMP part/level mismatch is reported', () {
      // Convert to part 2 but validate as part 1: the identifier mismatches.
      final doc = PdfDocument.open(buildEmbeddedFontPdf());
      final editor = PdfEditor(doc)
        ..convertToPdfA(iccProfile: adobeRgb1998Icc(), part: 2, title: 'T');
      final report =
          validatePdfA(PdfDocument.open(editor.save()), part: 1);
      expect(report.errors.map((e) => e.rule), contains('A1:6.7.3'));
    });
  });
}
