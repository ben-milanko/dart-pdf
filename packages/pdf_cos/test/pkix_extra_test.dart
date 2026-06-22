// Edge- and error-path coverage for the LTV/PAdES primitives: the DER
// encoders, request builders, response/status parsing, and the
// encapsulated-CMS signing path that the OpenSSL KATs don't exercise.
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pdf_cos/pdf_cos.dart';
import 'package:test/test.dart';

import 'pkix_fixtures.g.dart';

Uint8List d(String b64) => base64.decode(b64);

void main() {
  group('DER encoders', () {
    test('GeneralizedTime is canonical (UTC, seconds, Z)', () {
      final der = derGeneralizedTime(DateTime.utc(2026, 1, 2, 3, 4, 5));
      final parsed = DerObject.parse(der);
      expect(parsed.tag, DerTag.generalizedTime);
      expect(String.fromCharCodes(parsed.content), '20260102030405Z');
      expect(parsed.asTime, DateTime.utc(2026, 1, 2, 3, 4, 5));
    });

    test('boolean encodes TRUE as 0xFF and FALSE as 0x00', () {
      expect(DerObject.parse(derBoolean(true)).content, [0xFF]);
      expect(DerObject.parse(derBoolean(false)).content, [0x00]);
    });

    test('enumerated shares the integer content form', () {
      expect(DerObject.parse(derEnumerated(0)).content, [0]);
      expect(DerObject.parse(derEnumerated(5)).asInteger.toInt(), 5);
      // a high bit gets a leading zero to stay positive
      expect(DerObject.parse(derEnumerated(200)).content, [0, 200]);
    });

    test('bit string prepends the zero unused-bits octet', () {
      final parsed = DerObject.parse(derBitString([0xAB, 0xCD]));
      expect(parsed.tag, DerTag.bitString);
      expect(parsed.content, [0, 0xAB, 0xCD]);
      expect(parsed.asBitString, [0xAB, 0xCD]);
    });

    test('context-primitive wraps raw octets under an [n] tag', () {
      final parsed = DerObject.parse(derContextPrimitive(6, 'hi'.codeUnits));
      expect(parsed.tag, DerTag.contextPrimitive(6));
      expect(String.fromCharCodes(parsed.content), 'hi');
    });
  });

  group('digest OID helpers', () {
    test('round-trip for every supported hash', () {
      expect(digestOidForHash(crypto.sha256), DigestOid.sha256);
      expect(digestOidForHash(crypto.sha384), DigestOid.sha384);
      expect(digestOidForHash(crypto.sha512), DigestOid.sha512);
      expect(hashForDigestOid(DigestOid.sha1), crypto.sha1);
      expect(hashForDigestOid(DigestOid.sha512), crypto.sha512);
    });

    test('unknown OID maps to null', () {
      expect(hashForDigestOid('1.2.3.4.5'), isNull);
    });
  });

  group('X.509 extensions', () {
    test('the leaf exposes its AIA OCSP URL and CRL distribution point', () {
      final leaf = X509Certificate.parse(d(leafCertB64));
      expect(leaf.ocspResponderUrl, 'http://ocsp.example/');
      expect(leaf.crlDistributionUrls, contains('http://crl.example/ca.crl'));
    });

    test('a certificate without those extensions reports none', () {
      // the CA has no AIA / CRL-DP in this fixture set
      final ca = X509Certificate.parse(d(caCertB64));
      expect(ca.ocspResponderUrl, isNull);
      expect(ca.crlDistributionUrls, isEmpty);
    });
  });

  group('ESS signing-certificate-v2', () {
    Uint8List essCertId(Uint8List attr) => DerObject.parse(attr)
        .children[1] // SET
        .children[0] // SigningCertificateV2
        .children[0] // certs SEQUENCE
        .children[0] // ESSCertIDv2
        .encoded;

    test('sha256 omits the AlgorithmIdentifier (the ASN.1 DEFAULT)', () {
      final cert = X509Certificate.parse(d(leafCertB64));
      final id = DerObject.parse(
          essCertId(essSigningCertificateV2Attribute(cert)));
      // first field is the certHash OCTET STRING (32 bytes), not an alg id
      expect(id.children[0].tag, DerTag.octetString);
      expect(id.children[0].content, hasLength(32));
    });

    test('a non-default hash emits the AlgorithmIdentifier and 48-byte hash',
        () {
      final cert = X509Certificate.parse(d(leafCertB64));
      final id = DerObject.parse(essCertId(
          essSigningCertificateV2Attribute(cert, hash: crypto.sha384)));
      expect(id.children[0].tag, DerTag.sequence); // AlgorithmIdentifier
      expect(id.children[1].content, hasLength(48)); // sha384 digest
    });
  });

  group('RFC 3161 request and response framing', () {
    test('TimeStampReq carries nonce, policy, and certReq when asked', () {
      final req = buildTimeStampRequest(
        messageImprint: crypto.sha256.convert([1, 2, 3]).bytes,
        nonce: BigInt.from(0xCAFE),
        reqPolicy: '1.2.3.4',
        requestCertificate: true,
      );
      final fields = DerObject.parse(req).children;
      expect(fields.first.asInteger, BigInt.one); // version
      // policy OID, nonce INTEGER and certReq BOOLEAN are all present
      expect(fields.any((f) => f.tag == DerTag.oid), isTrue);
      expect(
          fields.any((f) => f.tag == DerTag.integer && f.asInteger ==
              BigInt.from(0xCAFE)),
          isTrue);
      expect(fields.any((f) => f.tag == 0x01), isTrue); // BOOLEAN
    });

    test('certReq=false omits the boolean (DEFAULT FALSE)', () {
      final req = buildTimeStampRequest(
        messageImprint: crypto.sha256.convert([1]).bytes,
        requestCertificate: false,
      );
      expect(DerObject.parse(req).children.any((f) => f.tag == 0x01), isFalse);
    });

    test('a granted TimeStampResp yields the embedded token', () {
      final token = d(tsTokenB64);
      final resp = derSequence([
        derSequence([derEnumerated(0)]), // PKIStatusInfo { granted }
        token,
      ]);
      expect(timeStampTokenFromResponse(resp), token);
    });

    test('a rejected TimeStampResp throws', () {
      final resp = derSequence([
        derSequence([derEnumerated(2)]), // rejection
      ]);
      expect(() => timeStampTokenFromResponse(resp), throwsFormatException);
    });

    test('TspStatus maps known and unknown codes', () {
      expect(TspStatus.fromValue(0), TspStatus.granted);
      expect(TspStatus.fromValue(0).isSuccess, isTrue);
      expect(TspStatus.fromValue(1).isSuccess, isTrue);
      expect(TspStatus.fromValue(2).isSuccess, isFalse);
      expect(TspStatus.fromValue(99), TspStatus.unknown);
    });
  });

  group('OCSP framing', () {
    test('an unsuccessful response parses its status and carries no entries',
        () {
      final resp = derSequence([derEnumerated(1)]); // malformedRequest
      final parsed = OcspResponse.parse(resp);
      expect(parsed.responseStatus, OcspResponseStatus.malformedRequest);
      expect(parsed.responses, isEmpty);
      expect(parsed.forSerial(BigInt.one), isNull);
    });

    test('status codes map, unknown falls through', () {
      expect(OcspResponseStatus.fromValue(0), OcspResponseStatus.successful);
      expect(OcspResponseStatus.fromValue(6), OcspResponseStatus.unauthorized);
      expect(OcspResponseStatus.fromValue(42), OcspResponseStatus.unknown);
    });

    test('a request with a nonce carries the requestExtensions [2] field', () {
      final leaf = X509Certificate.parse(d(leafCertB64));
      final ca = X509Certificate.parse(d(caCertB64));
      final req =
          buildOcspRequest(cert: leaf, issuer: ca, nonce: BigInt.from(7));
      final tbs = DerObject.parse(req).children[0];
      expect(tbs.children.any((f) => f.tag == DerTag.context(2)), isTrue);
    });
  });

  group('encapsulated CMS signing (the test-TSA path)', () {
    test('cmsSignEncapsulated produces a token verifyTimeStampToken accepts',
        () {
      final key = RsaPrivateKey.fromDer(d(leafKeyB64));
      final stamped = Uint8List.fromList(utf8.encode('stamp me'));
      final imprint = crypto.sha256.convert(stamped).bytes;

      // a minimal TSTInfo over the imprint
      final tstInfo = derSequence([
        derInteger(BigInt.one),
        derOid('1.2.3.4.1'),
        derSequence([
          derSequence([derOid(DigestOid.sha256), derNull()]),
          derOctetString(imprint),
        ]),
        derInteger(BigInt.from(42)),
        derGeneralizedTime(DateTime.utc(2026, 6, 15, 9, 30)),
      ]);
      final token = cmsSignEncapsulated(
        eContent: tstInfo,
        eContentType: TspOid.tstInfo,
        privateKey: key,
        certificates: [d(leafCertB64)],
      );

      final parsed = TimeStampToken.parse(token);
      expect(parsed.serialNumber, BigInt.from(42));
      expect(parsed.genTime, DateTime.utc(2026, 6, 15, 9, 30));
      final result = verifyTimeStampToken(parsed, stamped);
      expect(result.valid, isTrue);
      expect(verifyTimeStampToken(parsed, Uint8List(3)).imprintMatches,
          isFalse);
    });

    test('the signature-time-stamp attribute wraps the token under its OID',
        () {
      final attr =
          DerObject.parse(cmsSignatureTimeStampAttribute(d(tsTokenB64)));
      expect(attr.children[0].asOid, '1.2.840.113549.1.9.16.2.14');
      expect(attr.children[1].tag, DerTag.set);
    });
  });

  group('CRL edge paths', () {
    final crl = CertificateRevocationList.parse(d(crlB64));

    test('a serial that is not listed returns null', () {
      expect(crl.forSerial(BigInt.from(0xABCD)), isNull);
    });

    test('verifying against a key that cannot sign CRLs fails', () {
      // the leaf is RSA but is not the CRL issuer; the signature won't verify
      expect(crl.signatureValid(X509Certificate.parse(d(leafCertB64))), isFalse);
    });
  });
}
