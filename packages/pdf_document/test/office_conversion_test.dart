// The Office→PDF conversion seam: a pluggable converter contract (no engine
// ships in-tree), format sniffing, and the loud default no-op converter.
import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart';
import 'package:test/test.dart';

void main() {
  group('PdfOfficeFormat.sniff', () {
    test('recognizes formats by extension (case-insensitive)', () {
      expect(PdfOfficeFormat.sniff(filename: 'report.docx'),
          PdfOfficeFormat.docx);
      expect(PdfOfficeFormat.sniff(filename: 'BOOK.XLSX'),
          PdfOfficeFormat.xlsx);
      expect(PdfOfficeFormat.sniff(filename: 'deck.pptx'),
          PdfOfficeFormat.pptx);
      expect(PdfOfficeFormat.sniff(filename: 'notes.odt'), PdfOfficeFormat.odt);
    });

    test('recognizes RTF by its magic bytes', () {
      final rtf = Uint8List.fromList('{\\rtf1 hi}'.codeUnits);
      expect(PdfOfficeFormat.sniff(bytes: rtf), PdfOfficeFormat.rtf);
    });

    test('returns null for the unknown', () {
      expect(PdfOfficeFormat.sniff(filename: 'photo.png'), isNull);
      expect(PdfOfficeFormat.sniff(filename: 'noext'), isNull);
      expect(PdfOfficeFormat.sniff(bytes: Uint8List(0)), isNull);
    });
  });

  group('PdfOfficeDocument', () {
    test('resolves the format from the filename when unset', () {
      final doc = PdfOfficeDocument(
        bytes: Uint8List.fromList([1, 2, 3]),
        filename: 'q3.xlsx',
      );
      expect(doc.format, isNull);
      expect(doc.resolvedFormat, PdfOfficeFormat.xlsx);
    });

    test('keeps an explicit format', () {
      final doc = PdfOfficeDocument(
        bytes: Uint8List.fromList([1]),
        format: PdfOfficeFormat.doc,
      );
      expect(doc.resolvedFormat, PdfOfficeFormat.doc);
    });
  });

  group('UnsupportedPdfOfficeConverter', () {
    test('supports nothing and throws with guidance', () async {
      const converter = UnsupportedPdfOfficeConverter();
      expect(converter.supportedFormats, isEmpty);

      final doc = PdfOfficeDocument(
        bytes: Uint8List.fromList([0]),
        filename: 'a.docx',
      );
      await expectLater(
        converter.convert(doc),
        throwsA(isA<PdfOfficeConversionException>()
            .having((e) => e.format, 'format', PdfOfficeFormat.docx)
            .having((e) => e.toString(), 'message',
                contains('No office-to-PDF converter'))),
      );
    });
  });

  test('a host converter can satisfy the contract', () async {
    final converter = _FakeConverter();
    expect(converter.supportedFormats, contains(PdfOfficeFormat.docx));
    final pdf = await converter.convert(PdfOfficeDocument(
      bytes: Uint8List.fromList([9]),
      format: PdfOfficeFormat.docx,
    ));
    // The fake returns a real (if tiny) PDF byte stream.
    expect(pdf.sublist(0, 5), [0x25, 0x50, 0x44, 0x46, 0x2D]); // %PDF-
  });
}

/// Stand-in for a host-provided converter (e.g. one POSTing to a headless
/// LibreOffice service); here it just hands back a minimal PDF.
class _FakeConverter implements PdfOfficeConverter {
  @override
  Set<PdfOfficeFormat> get supportedFormats =>
      const {PdfOfficeFormat.docx, PdfOfficeFormat.xlsx};

  @override
  Future<Uint8List> convert(PdfOfficeDocument source) async {
    if (!supportedFormats.contains(source.resolvedFormat)) {
      throw PdfOfficeConversionException('unsupported',
          format: source.resolvedFormat);
    }
    return Uint8List.fromList('%PDF-1.7\n%%EOF\n'.codeUnits);
  }
}
