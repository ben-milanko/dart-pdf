// Emits a sample signed PDF with a visible signature box so the Acrobat/
// Bluebeam-style appearance can be inspected in a real viewer.
import 'dart:io';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main() {
  final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)));
  final signed = editor.saveSigned(
    privateKey: RsaPrivateKey.fromPem(testSignerKeyPem),
    certificates: [pemBytes(testSignerCertPem)],
    reason: 'I approve this document',
    location: 'Melbourne, AU',
    signingTime: DateTime.utc(2026, 7, 16, 9, 30, 0),
    appearance: const PdfSignatureAppearance(
      rect: PdfRect(72, 640, 372, 720),
      backgroundColor: 0xF3F7FB,
    ),
  );
  File('signature_box_sample.pdf').writeAsBytesSync(signed);
  stdout.writeln('wrote signature_box_sample.pdf (${signed.length} bytes)');
}
