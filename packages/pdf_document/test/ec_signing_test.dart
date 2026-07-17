import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

void main() {
  group('one-tap self-signed EC identity', () {
    final signedAt = DateTime.utc(2026, 6, 10, 12);
    final identity = PdfSigningIdentity.generate(
      name: 'Ada Lovelace',
      email: 'ada@example.com',
      organization: 'dart-pdf',
      notBefore: DateTime.utc(2026),
      validity: const Duration(days: 3650),
    );

    test('generate mints an EC key and a self-signed leaf certificate', () {
      expect(identity.privateKey.curve.oid, EcCurve.p256.oid);
      final cert = X509Certificate.parse(identity.certificate);
      expect(cert.subjectCommonName, 'Ada Lovelace');
      expect(cert.publicKey, isA<EcPublicKey>());
      expect(cert.isSignedBy(cert), isTrue); // valid trust anchor
    });

    test('saveSelfSigned produces a signature that validates as intact', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(2)));
      final signed = editor.saveSelfSigned(
        identity: identity,
        reason: 'Approval',
        location: 'Melbourne',
        signingTime: signedAt,
      );

      final doc = PdfDocument.open(signed);
      final signature = PdfSignature.of(doc).single;
      expect(signature.signerName, 'Ada Lovelace');
      expect(signature.subFilter, 'adbe.pkcs7.detached');
      expect(signature.signingTime, signedAt);

      final result = signature.validate();
      expect(result.problems, isEmpty);
      expect(result.intact, isTrue);
      expect(result.digestMatches, isTrue);
      expect(result.signatureValid, isTrue);
      expect(result.coversWholeDocument, isTrue);
      expect(result.signerCertificate?.subjectCommonName, 'Ada Lovelace');
    });

    test('the identity certificate validates in our own trust store', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)));
      final signed = editor.saveSelfSigned(
        identity: identity,
        signingTime: signedAt,
      );
      final doc = PdfDocument.open(signed);
      final trustStore = PdfTrustStore()..addDer(identity.certificate);
      final result = PdfSignature.of(doc).single.validate(trustStore: trustStore);
      expect(result.signatureValid, isTrue);
      expect(result.chainTrusted, isTrue,
          reason: result.chainProblems.join('; '));
    });

    test('signing keeps the original bytes (incremental update)', () {
      final original = buildMultiPagePdf(2);
      final editor = PdfEditor(PdfDocument.open(original));
      final signed =
          editor.saveSelfSigned(identity: identity, signingTime: signedAt);
      expect(signed.sublist(0, original.length), original);
    });

    test('saveSignedEcdsa without a signerName falls back to the cert CN', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)));
      final signed = editor.saveSignedEcdsa(
        privateKey: identity.privateKey,
        certificates: identity.certificates,
        signingTime: signedAt,
      );
      final doc = PdfDocument.open(signed);
      expect(PdfSignature.of(doc).single.signerName, 'Ada Lovelace');
    });

    test('an identity round-trips through PEM', () {
      final pem = identity.toPem();
      expect(pem, contains('BEGIN EC PRIVATE KEY'));
      expect(pem, contains('BEGIN CERTIFICATE'));
      final restored = PdfSigningIdentity.fromPem(pem);
      expect(restored.name, 'Ada Lovelace');
      expect(restored.privateKey.d, identity.privateKey.d);
      expect(restored.certificate, identity.certificate);

      // the restored identity still produces a valid signature
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)));
      final signed =
          editor.saveSelfSigned(identity: restored, signingTime: signedAt);
      expect(PdfSignature.of(PdfDocument.open(signed)).single.validate().intact,
          isTrue);
    });

    test('an empty certificate list is rejected', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)));
      expect(
        () => editor.saveSignedEcdsa(
            privateKey: identity.privateKey, certificates: const []),
        throwsArgumentError,
      );
    });
  });

  group('EC PAdES B-T with a self-signed identity', () {
    final signedAt = DateTime.utc(2026, 6, 10, 12);
    final identity = PdfSigningIdentity.generate(
      name: 'Grace Hopper',
      notBefore: DateTime.utc(2026),
      validity: const Duration(days: 3650),
    );

    test('a timestamped self-signed signature validates as intact', () async {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)));
      final signed = await editor.saveSelfSignedPades(
        identity: identity,
        level: PdfPadesLevel.bT,
        timestampClient: (request) async =>
            buildTestTimeStampToken(request, genTime: signedAt),
        signingTime: signedAt,
      );
      final doc = PdfDocument.open(signed);
      final signature = PdfSignature.of(doc).single;
      expect(signature.subFilter, 'ETSI.CAdES.detached');
      final result = signature.validate();
      expect(result.intact, isTrue, reason: result.problems.join('; '));
      expect(result.signatureValid, isTrue);
      expect(result.timestamp, isNotNull);
    });
  });
}
