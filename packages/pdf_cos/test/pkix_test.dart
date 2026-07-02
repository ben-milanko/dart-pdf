// Known-answer tests for the LTV/PAdES crypto primitives, validated against
// OpenSSL-produced reference artifacts (see tool/gen_pkix_fixtures.sh).
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pdf_cos/pdf_cos.dart';
import 'package:test/test.dart';

import 'pkix_fixtures.g.dart';

Uint8List der(String b64) => base64.decode(b64);

final caCert = X509Certificate.parse(der(caCertB64));
final leafCert = X509Certificate.parse(der(leafCertB64));
final revokedCert = X509Certificate.parse(der(revokedCertB64));
final tsaCert = X509Certificate.parse(der(tsaCertB64));

final leafSerial = BigInt.parse('1111', radix: 16);
final revokedSerial = BigInt.parse('2222', radix: 16);
final tsaSerial = BigInt.parse('3333', radix: 16);

void main() {
  group('certificate fixtures', () {
    test('serials and chaining match the OpenSSL setup', () {
      expect(leafCert.serial, leafSerial);
      expect(revokedCert.serial, revokedSerial);
      expect(tsaCert.serial, tsaSerial);
      expect(leafCert.isSignedBy(caCert), isTrue);
      expect(revokedCert.isSignedBy(caCert), isTrue);
      expect(tsaCert.isSignedBy(caCert), isTrue);
    });
  });

  group('CRL (RFC 5280)', () {
    final crl = CertificateRevocationList.parse(der(crlB64));

    test('signature verifies against the issuing CA', () {
      expect(crl.signatureValid(caCert), isTrue);
      // wrong issuer key must fail
      expect(crl.signatureValid(leafCert), isFalse);
    });

    test('lists the revoked serial and not the good one', () {
      expect(crl.forSerial(revokedSerial), isNotNull);
      expect(crl.forSerial(leafSerial), isNull);
    });

    test('carries the validity window', () {
      expect(crl.thisUpdate.isBefore(crl.nextUpdate!), isTrue);
    });
  });

  group('OCSP (RFC 6960)', () {
    final good = OcspResponse.parse(der(ocspGoodB64));
    final revoked = OcspResponse.parse(der(ocspRevokedB64));

    test('good response reports the leaf as good and verifies', () {
      expect(good.responseStatus, OcspResponseStatus.successful);
      final single = good.forSerial(leafSerial);
      expect(single, isNotNull);
      expect(single!.status, OcspCertStatus.good);
      expect(good.signatureValid(caCert), isTrue);
    });

    test('revoked response reports the revoked serial as revoked', () {
      final single = revoked.forSerial(revokedSerial);
      expect(single, isNotNull);
      expect(single!.status, OcspCertStatus.revoked);
      expect(single.revocationTime, isNotNull);
      expect(revoked.signatureValid(caCert), isTrue);
    });

    test('our OCSP request CertID matches OpenSSL for the same cert', () {
      final ours = buildOcspRequest(cert: leafCert, issuer: caCert);
      // CertID lives at OCSPRequest -> tbsRequest -> requestList -> Request
      final ourCertId = DerObject.parse(ours)
          .children[0] // tbsRequest
          .children[0] // requestList
          .children[0] // Request
          .children[0]; // reqCert (CertID)
      final theirs = DerObject.parse(der(ocspReqGoodB64));
      final theirCertId = theirs
          .children[0]
          .children[0]
          .children[0]
          .children[0];
      expect(ourCertId.encoded, theirCertId.encoded);
    });
  });

  group('RFC 3161 timestamp', () {
    final token = TimeStampToken.parse(der(tsTokenB64));
    final payload = Uint8List.fromList(utf8.encode(tsPayload));

    test('parses the TSTInfo fields', () {
      expect(token.signerCertificate, isNotNull);
      expect(token.signerCertificate!.serial, tsaSerial);
      expect(token.genTime.year, greaterThanOrEqualTo(2026));
      expect(token.messageImprint.hashedMessage,
          crypto.sha256.convert(payload).bytes);
    });

    test('verifies against the stamped payload', () {
      final result = verifyTimeStampToken(token, payload);
      expect(result.imprintMatches, isTrue);
      expect(result.signatureValid, isTrue);
      expect(result.valid, isTrue);
    });

    test('rejects a payload it did not stamp', () {
      final result = verifyTimeStampToken(
          token, Uint8List.fromList(utf8.encode('tampered')));
      expect(result.imprintMatches, isFalse);
      expect(result.valid, isFalse);
      // the TSA signature itself is still cryptographically sound
      expect(result.signatureValid, isTrue);
    });

    test('our TimeStampReq imprint matches OpenSSL for the same payload', () {
      final ours = buildTimeStampRequest(
          messageImprint: crypto.sha256.convert(payload).bytes);
      // messageImprint is field [1] of the TimeStampReq SEQUENCE
      final ourImprint = DerObject.parse(ours).children[1];
      final theirs = DerObject.parse(der(tsqB64)).children[1];
      expect(ourImprint.encoded, theirs.encoded);
    });
  });

  group('CMS PAdES baseline (signing-certificate-v2)', () {
    final key = RsaPrivateKey.fromDer(der(leafKeyB64));
    final content = Uint8List.fromList(utf8.encode('the signed document'));

    test('a plain CMS has no signing-certificate attribute', () {
      final cms = cmsSignDetached(
        contentDigest: crypto.sha256.convert(content).bytes,
        privateKey: key,
        certificates: [der(leafCertB64)],
      );
      final parsed = CmsSignedData.parse(cms);
      expect(parsed.signerInfos.first.hasSigningCertificate, isFalse);
      final v = cmsVerify(parsed, parsed.signerInfos.first, content);
      expect(v.digestMatches, isTrue);
      expect(v.signatureValid, isTrue);
    });

    test('a PAdES CMS carries signing-certificate-v2 and still verifies', () {
      final cms = cmsSignDetached(
        contentDigest: crypto.sha256.convert(content).bytes,
        privateKey: key,
        certificates: [der(leafCertB64)],
        essCertificate: leafCert,
      );
      final parsed = CmsSignedData.parse(cms);
      expect(parsed.signerInfos.first.hasSigningCertificate, isTrue);
      final v = cmsVerify(parsed, parsed.signerInfos.first, content);
      expect(v.digestMatches, isTrue);
      expect(v.signatureValid, isTrue);
    });
  });
}
