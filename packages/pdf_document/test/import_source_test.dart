// The Office/foreign-format ingestion seam (PdfImportSource): an abstract,
// host-provided converter to PDF bytes. A fake converter here proves the
// seam opens whatever bytes it hands back as a PdfDocument.
import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

class _FakeConverter implements PdfImportSource {
  @override
  Future<Uint8List> convertToPdf(Uint8List bytes,
          {String? mimeType, String? fileName}) async =>
      buildClassicPdf();
}

void main() {
  test('importDocument opens the produced PDF', () async {
    final doc = await _FakeConverter()
        .importDocument(Uint8List(0), fileName: 'report.docx');
    expect(doc.pageCount, 1);
  });
}
