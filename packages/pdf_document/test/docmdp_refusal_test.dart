// Signing a document whose certification forbids changes (/DocMDP /P 1) is
// refused before any byte is written: the incremental update would break the
// very certification it is appended to, and every viewer would report the
// result as tampered with.
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

final signerKey = RsaPrivateKey.fromPem(testSignerKeyPem);
final signerCert = pemBytes(testSignerCertPem);
final signedAt = DateTime.utc(2026, 6, 15, 10, 0, 0);

PdfTimestampClient testTsa() =>
    (request) async => buildTestTimeStampToken(request, genTime: signedAt);

/// A one-page PDF certified by another producer: the catalog's /Perms
/// /DocMDP points at a signature dictionary carrying a /DocMDP transform.
/// [transformParams] is the raw /TransformParams dictionary body, so a test
/// can write `/P 1`, another level, or omit /P entirely.
Uint8List buildCertifiedPdf(String transformParams) {
  const content = 'BT /F1 24 Tf 72 720 Td (Certified) Tj ET';
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R /AcroForm << /Fields [6 0 R] '
        '/SigFlags 3 >> /Perms << /DocMDP 7 0 R >> >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R '
        '/Resources << /Font << /F1 5 0 R >> >> /Annots [6 0 R] >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    '<< /FT /Sig /T (AuthorSig) /Type /Annot /Subtype /Widget '
        '/Rect [0 0 0 0] /F 4 /P 3 0 R /V 7 0 R >>',
    '<< /Type /Sig /Filter /Adobe.PPKLite /SubFilter /adbe.pkcs7.detached '
        '/ByteRange [0 0 0 0] /Contents <00> '
        '/Reference [<< /Type /SigRef /TransformMethod /DocMDP '
        '/TransformParams << /Type /TransformParams $transformParams >> >>] '
        '>>',
  ];
  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xrefOffset = buffer.length;
  buffer
    ..write('xref\n0 ${objects.length + 1}\n')
    ..write('0000000000 65535 f \n');
  for (final offset in offsets) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer
    ..write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n')
    ..write('startxref\n$xrefOffset\n%%EOF\n');
  return ascii(buffer.toString());
}

PdfEditor editorFor(Uint8List bytes) => PdfEditor(PdfDocument.open(bytes));

Uint8List signWith(PdfEditor editor) => editor.saveSigned(
      privateKey: signerKey,
      certificates: [signerCert],
      signingTime: signedAt,
    );

void main() {
  group('DocMDP /P 1 refuses further signing', () {
    test('saveSigned throws before writing anything', () {
      final editor = editorFor(buildCertifiedPdf('/P 1'));
      final before = editor.document.cos.bytes.length;
      expect(() => signWith(editor), throwsA(isA<CertifiedNoChangesException>()));
      // refused before any byte was appended - the editor is still usable
      expect(editor.document.cos.bytes.length, before);
    });

    test('the message names the reason', () {
      expect(CertifiedNoChangesException().toString(),
          contains('DocMDP /P 1'));
    });

    test('saveSignedEcdsa is refused on the same document', () {
      final identity = PdfSigningIdentity.generate(name: 'Tester');
      final editor = editorFor(buildCertifiedPdf('/P 1'));
      expect(
        () => editor.saveSignedEcdsa(
          privateKey: identity.privateKey,
          certificates: identity.certificates,
          signingTime: signedAt,
        ),
        throwsA(isA<CertifiedNoChangesException>()),
      );
    });

    test('saveSignedExternal is refused on the same document', () {
      final editor = editorFor(buildCertifiedPdf('/P 1'));
      expect(
        editor.saveSignedExternal(
          signer: (_) async => Uint8List(0),
          certificates: [signerCert],
          signingTime: signedAt,
        ),
        throwsA(isA<CertifiedNoChangesException>()),
      );
    });

    test('saveSignedPades is refused on the same document', () {
      final editor = editorFor(buildCertifiedPdf('/P 1'));
      expect(
        editor.saveSignedPades(
          privateKey: signerKey,
          certificates: [signerCert],
          signingTime: signedAt,
        ),
        throwsA(isA<CertifiedNoChangesException>()),
      );
    });

    test('a document timestamp is still allowed - B-LTA depends on it',
        () async {
      final editor = editorFor(buildCertifiedPdf('/P 1'));
      final bytes = await editor.addDocumentTimestamp(testTsa());
      final doc = PdfDocument.open(bytes);
      final stamp = PdfSignature.of(doc)
          .where((s) =>
              (doc.cos.resolve(s.dict['Type']) as CosName?)?.value ==
              'DocTimeStamp')
          .single;
      expect((doc.cos.resolve(stamp.dict['SubFilter']) as CosName).value,
          'ETSI.RFC3161');
    });
  });

  group('permissive certifications still sign', () {
    test('/P 2 (form filling and signing) is allowed', () {
      final bytes = signWith(editorFor(buildCertifiedPdf('/P 2')));
      expect(PdfSignature.of(PdfDocument.open(bytes)), hasLength(2));
    });

    test('/P 3 (plus annotations) is allowed', () {
      final bytes = signWith(editorFor(buildCertifiedPdf('/P 3')));
      expect(PdfSignature.of(PdfDocument.open(bytes)), hasLength(2));
    });

    test('/P absent defaults to 2 and is allowed', () {
      final bytes = signWith(editorFor(buildCertifiedPdf('')));
      expect(PdfSignature.of(PdfDocument.open(bytes)), hasLength(2));
    });

    test('an uncertified document is untouched by the check', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(2)));
      expect(PdfSignature.of(PdfDocument.open(signWith(editor))), hasLength(1));
    });
  });

  group('certification we write ourselves', () {
    test('certifying at /P 1 then re-signing is refused', () async {
      final certified = await PdfEditor(PdfDocument.open(buildMultiPagePdf(2)))
          .saveSignedPades(
        privateKey: signerKey,
        certificates: [signerCert],
        signingTime: signedAt,
        certify: true,
        docMdpPermissions: 1,
      );
      expect(() => signWith(editorFor(certified)),
          throwsA(isA<CertifiedNoChangesException>()));
    });

    test('certifying at /P 2 leaves the document signable', () async {
      final certified = await PdfEditor(PdfDocument.open(buildMultiPagePdf(2)))
          .saveSignedPades(
        privateKey: signerKey,
        certificates: [signerCert],
        signingTime: signedAt,
        certify: true,
        docMdpPermissions: 2,
      );
      final bytes = signWith(editorFor(certified));
      expect(PdfSignature.of(PdfDocument.open(bytes)), hasLength(2));
    });
  });
}
