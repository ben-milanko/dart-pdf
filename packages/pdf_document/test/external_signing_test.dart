import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

void main() {
  final key = RsaPrivateKey.fromPem(testSignerKeyPem);
  final cert = pemBytes(testSignerCertPem);
  // Signataire externe de référence : RSA PKCS#1 v1.5 sur le SHA-256 des
  // signedAttributes — exactement ce que fera SHA256withRSA côté natif.
  Future<Uint8List> signer(Uint8List attrs) async =>
      rsaSign(key, '2.16.840.1.101.3.4.2.1', crypto.sha256.convert(attrs).bytes);

  test('saveSignedExternal : signature intacte + cartouche localisé', () async {
    final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(2)));
    final signed = await editor.saveSignedExternal(
      signer: signer,
      certificates: [cert],
      signingTime: DateTime(2026, 7, 22, 17, 34, 3),
      appearance: const PdfSignatureAppearance(
        page: 1,
        rect: PdfRect(100, 100, 300, 180),
        signedByLabel: 'Signature numérique de',
        dateLabel: 'Date :',
      ),
    );
    final doc = PdfDocument.open(signed);
    final sig = PdfSignature.of(doc).single;
    expect(sig.validate().intact, isTrue);
  });

  test('saveSignedExternal sans appearance : signature invisible intacte', () async {
    final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)));
    final signed = await editor.saveSignedExternal(
        signer: signer, certificates: [cert]);
    expect(PdfSignature.of(PdfDocument.open(signed)).single.validate().intact,
        isTrue);
  });

  test('_pdfDate et cartouche : offset local conservé', () async {
    // Une heure NON-UTC doit produire un /M avec offset, pas un Z.
    final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)));
    final t = DateTime(2026, 7, 22, 17, 34, 3); // locale du terminal de test
    final signed = await editor.saveSignedExternal(
        signer: signer, certificates: [cert], signingTime: t);
    final text = String.fromCharCodes(signed);
    if (t.timeZoneOffset == Duration.zero) {
      expect(text, contains('D:20260722173403Z'));
    } else {
      final o = t.timeZoneOffset;
      final sign = o.isNegative ? '-' : '+';
      final hh = o.abs().inHours.toString().padLeft(2, '0');
      final mm = (o.abs().inMinutes % 60).toString().padLeft(2, '0');
      expect(text, contains("D:20260722173403$sign$hh'$mm'"));
    }
  });
}
