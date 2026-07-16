// End-to-end PAdES tests: produce B-B…B-LTA signatures with an in-process
// TSA and real OpenSSL revocation material, then validate them offline.
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

final signerKey = RsaPrivateKey.fromPem(testSignerKeyPem);
final signerCert = pemBytes(testSignerCertPem);
final signedAt = DateTime.utc(2026, 6, 15, 10, 0, 0);

/// A TSA that mints real RFC 3161 tokens in-process.
PdfTimestampClient testTsa({DateTime? at}) =>
    (request) async => buildTestTimeStampToken(request, genTime: at ?? signedAt);

PdfEditor freshEditor() => PdfEditor(PdfDocument.open(buildMultiPagePdf(2)));

void main() {
  group('PAdES B-B', () {
    test('produces an ETSI.CAdES.detached signature with the ESS attribute',
        () async {
      final bytes = await freshEditor().saveSignedPades(
        privateKey: signerKey,
        certificates: [signerCert],
        signingTime: signedAt,
        reason: 'Approval',
      );
      final signature = PdfSignature.of(PdfDocument.open(bytes)).single;
      expect(signature.subFilter, 'ETSI.CAdES.detached');

      final result = signature.validate();
      expect(result.intact, isTrue);
      expect(result.problems, isEmpty);
      expect(result.padesLevel, PdfPadesLevel.bB);
      expect(result.timestamp, isNull);
      expect(result.isLtvEnabled, isFalse);
    });
  });

  group('visible signature box', () {
    test('renders a box while staying a valid B-LTA signature', () async {
      final bytes = await freshEditor().saveSignedPades(
        privateKey: signerKey,
        certificates: [signerCert],
        level: PdfPadesLevel.bLTA,
        timestampClient: testTsa(),
        signingTime: signedAt,
        reason: 'Approval',
        appearance: const PdfSignatureAppearance(
          rect: PdfRect(72, 640, 340, 720),
        ),
      );
      final doc = PdfDocument.open(bytes);
      final signature = PdfSignature.of(doc)
          .firstWhere((s) => !s.isDocumentTimeStamp);
      final result = signature.validate();
      expect(result.intact, isTrue);
      expect(result.padesLevel, PdfPadesLevel.bLTA);

      final widget = signature.field.widgets.first;
      final ap = doc.cos.resolve(widget['AP']) as CosDictionary;
      final form = doc.cos.resolve(ap['N']) as CosStream;
      final content = String.fromCharCodes(doc.cos.decodeStreamData(form));
      final shown = RegExp(r'\(([^)]*)\) Tj')
          .allMatches(content)
          .map((m) => m.group(1))
          .join(' ');
      expect(shown, contains('Digitally signed by Dart PDF Test Signer'));
      expect(shown, contains('Reason: Approval'));
    });
  });

  group('PAdES B-T', () {
    test('embeds a verifiable signature timestamp', () async {
      final bytes = await freshEditor().saveSignedPades(
        privateKey: signerKey,
        certificates: [signerCert],
        level: PdfPadesLevel.bT,
        timestampClient: testTsa(),
        signingTime: signedAt,
      );
      final result = PdfSignature.of(PdfDocument.open(bytes)).single.validate();
      expect(result.intact, isTrue);
      expect(result.padesLevel, PdfPadesLevel.bT);
      expect(result.timestamp, isNotNull);
      expect(result.timestamp!.valid, isTrue);
      expect(result.timestamp!.time, signedAt);
    });

    test('a B-T signature without a TSA client is rejected', () async {
      expect(
        () => freshEditor().saveSignedPades(
          privateKey: signerKey,
          certificates: [signerCert],
          level: PdfPadesLevel.bT,
        ),
        throwsArgumentError,
      );
    });
  });

  group('PAdES B-LT (long-term, with real revocation material)', () {
    // Sign with the OpenSSL leaf so the embedded OCSP actually covers it.
    final leafKey = RsaPrivateKey.fromDer(pkixLeafKey);

    Future<Uint8List> signBLT() => freshEditor().saveSignedPades(
          privateKey: leafKey,
          certificates: [pkixLeafCert, pkixCaCert],
          level: PdfPadesLevel.bLT,
          timestampClient: testTsa(),
          signingTime: signedAt,
          revocationClient: (chain) async => PdfRevocationMaterial(
            ocspResponses: [pkixOcspGood],
            crls: [pkixCrl],
            certificates: [pkixCaCert],
          ),
        );

    test('writes a /DSS and reports the signature as LTV-enabled', () async {
      final doc = PdfDocument.open(await signBLT());
      final dss = PdfDss.of(doc);
      expect(dss, isNotNull);
      expect(dss!.ocspResponses, isNotEmpty);
      expect(dss.certificates, isNotEmpty);

      final result = PdfSignature.of(doc).single.validate();
      expect(result.intact, isTrue);
      expect(result.padesLevel, PdfPadesLevel.bLT);
      expect(result.isLtvEnabled, isTrue);
    });

    test('consumes the embedded OCSP to confirm the signer is not revoked',
        () async {
      final result = PdfSignature.of(PdfDocument.open(await signBLT()))
          .single
          .validate();
      expect(result.embeddedRevocation, PdfRevocationStatus.good);
    });
  });

  group('PAdES B-LTA (archive timestamp)', () {
    final leafKey = RsaPrivateKey.fromDer(pkixLeafKey);

    test('adds a document timestamp over the /DSS', () async {
      final bytes = await freshEditor().saveSignedPades(
        privateKey: leafKey,
        certificates: [pkixLeafCert, pkixCaCert],
        level: PdfPadesLevel.bLTA,
        timestampClient: testTsa(),
        signingTime: signedAt,
        revocationClient: (chain) async => PdfRevocationMaterial(
          ocspResponses: [pkixOcspGood],
          certificates: [pkixCaCert],
        ),
      );
      final doc = PdfDocument.open(bytes);
      final signatures = PdfSignature.of(doc);

      final docTs = signatures.where((s) => s.isDocumentTimeStamp).toList();
      expect(docTs, hasLength(1));
      final tsResult = docTs.single.validate();
      expect(tsResult.signatureValid, isTrue);
      expect(tsResult.timestamp!.valid, isTrue);

      final approval =
          signatures.firstWhere((s) => !s.isDocumentTimeStamp).validate();
      expect(approval.intact, isTrue);
      expect(approval.padesLevel, PdfPadesLevel.bLTA);
    });
  });

  group('standalone document timestamp', () {
    test('addDocumentTimestamp stamps an already signed file', () async {
      final signed = await freshEditor().saveSignedPades(
        privateKey: signerKey,
        certificates: [signerCert],
        signingTime: signedAt,
      );
      final stamped = await PdfEditor(PdfDocument.open(signed))
          .addDocumentTimestamp(testTsa());
      final docTs = PdfSignature.of(PdfDocument.open(stamped))
          .where((s) => s.isDocumentTimeStamp)
          .toList();
      expect(docTs, hasLength(1));
      final result = docTs.single.validate();
      expect(result.signatureValid, isTrue);
      expect(result.timestamp!.valid, isTrue);
      // the original approval signature survives the added revision
      final approval = PdfSignature.of(PdfDocument.open(stamped))
          .firstWhere((s) => !s.isDocumentTimeStamp);
      expect(approval.validate().signatureValid, isTrue);
    });
  });

  group('Certify / DocMDP author signature', () {
    test('sets /Perms /DocMDP and a DocMDP transform at the given level',
        () async {
      final bytes = await freshEditor().saveSignedPades(
        privateKey: signerKey,
        certificates: [signerCert],
        signingTime: signedAt,
        certify: true,
        docMdpPermissions: 2,
      );
      final doc = PdfDocument.open(bytes);
      final signature = PdfSignature.of(doc).single;

      final perms = doc.cos.resolve(doc.catalog['Perms']);
      expect(perms, isA<CosDictionary>());
      final docMdp = doc.cos.resolve((perms as CosDictionary)['DocMDP']);
      expect(docMdp, isA<CosDictionary>());
      // /Perms /DocMDP points at the signature dictionary itself
      expect(identical(docMdp, signature.dict), isTrue);

      final reference = doc.cos.resolve(signature.dict['Reference']);
      expect(reference, isA<CosArray>());
      final sigRef = doc.cos.resolve((reference as CosArray).items.first)
          as CosDictionary;
      expect((doc.cos.resolve(sigRef['TransformMethod']) as CosName).value,
          'DocMDP');
      final params =
          doc.cos.resolve(sigRef['TransformParams']) as CosDictionary;
      expect((doc.cos.resolve(params['P']) as CosInteger).value, 2);

      expect(signature.validate().intact, isTrue);
    });
  });
}
