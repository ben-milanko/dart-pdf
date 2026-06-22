import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart'
    show testCaCertPem, testChainSignerCertPem, testSignerCertPem;
import 'package:test/test.dart';

Uint8List hex(String s) => Uint8List.fromList([
      for (var i = 0; i < s.length; i += 2)
        int.parse(s.substring(i, i + 2), radix: 16),
    ]);

void main() {
  group('DER', () {
    test('integers round-trip including the sign-padding byte', () {
      for (final value in [0, 1, 127, 128, 255, 256, 65537, 1 << 40]) {
        final encoded = derInteger(BigInt.from(value));
        expect(DerObject.parse(encoded).asInteger, BigInt.from(value),
            reason: '$value');
      }
    });

    test('OIDs round-trip through multi-byte arcs', () {
      for (final oid in [
        '1.2.840.113549.1.7.2',
        '2.16.840.1.101.3.4.2.1',
        '1.3.14.3.2.26',
        '2.5.4.3',
      ]) {
        expect(DerObject.parse(derOid(oid)).asOid, oid);
      }
    });

    test('long-form lengths parse', () {
      final blob = derOctetString(List.filled(300, 0xAB));
      final parsed = DerObject.parse(blob);
      expect(parsed.content.length, 300);
      expect(parsed.content.first, 0xAB);
    });

    test('UTCTime applies the RFC 5280 century split and zone offsets', () {
      DerObject time(String text) =>
          DerObject(DerTag.utcTime, Uint8List.fromList(text.codeUnits),
              Uint8List(0));
      expect(time('260610120000Z').asTime, DateTime.utc(2026, 6, 10, 12));
      expect(time('990101000000Z').asTime, DateTime.utc(1999, 1, 1));
      expect(time('260610120000+1000').asTime,
          DateTime.utc(2026, 6, 10, 2));
    });

    test('SET OF sorts element encodings', () {
      final set = derSetOf([
        derOctetString([2, 2]),
        derOctetString([1]),
        derOctetString([2, 1]),
      ]);
      final children = DerObject.parse(set).children;
      expect(children[0].content, [1]);
      expect(children[1].content, [2, 1]);
      expect(children[2].content, [2, 2]);
    });
  });

  group('RSA', () {
    final key = RsaPrivateKey.fromPem(_testKeyPem);

    test('sign/verify round-trip', () {
      final digest = crypto.sha256.convert('payload'.codeUnits).bytes;
      final signature = rsaSign(key, DigestOid.sha256, digest);
      expect(rsaVerify(key.publicKey, DigestOid.sha256, digest, signature),
          isTrue);
    });

    test('a wrong digest fails', () {
      final digest = crypto.sha256.convert('payload'.codeUnits).bytes;
      final other = crypto.sha256.convert('payIoad'.codeUnits).bytes;
      final signature = rsaSign(key, DigestOid.sha256, digest);
      expect(rsaVerify(key.publicKey, DigestOid.sha256, other, signature),
          isFalse);
    });

    test('a corrupted signature fails', () {
      final digest = crypto.sha256.convert('payload'.codeUnits).bytes;
      final signature = rsaSign(key, DigestOid.sha256, digest);
      signature[10] ^= 1;
      expect(rsaVerify(key.publicKey, DigestOid.sha256, digest, signature),
          isFalse);
    });
  });

  group('RSASSA-PSS', () {
    final key = RsaPrivateKey.fromPem(_testKeyPem).publicKey;
    final digest = crypto.sha256
        .convert('dart-pdf rsa-pss test message'.codeUnits)
        .bytes;
    // openssl dgst -sha256 -sigopt rsa_padding_mode:pss with the test key
    final saltlen32 = hex(
        '947efe60e7e20e12114a40430fb9af047816df63acbd1d1612133b579458016b'
        '242dc8cf7bb02baaffb4fbc8e2f230637a518619d1891a051f418f6624614f16'
        'eede4a750afd6f440639aa726c77380bb5a069e68a45a268e477ac4612be08f0'
        '6de69d5ffdd8e98064e8e5d23093cff4b8ebf7d2344b45a54d1be6bb2d4f4bda');
    final saltlen0 = hex(
        'aa257a313a19e4ed227f57008d1710f7aa6232b27443cf45e1b373ce348538fb'
        'a1549fc911473099d8811d43d5caad3e353585acbbdc1355a7bef0748469887c'
        '04178099ef59d489245b5a317a97fd39e93011e43150af4d5ee196cf25cae9ac'
        'd0823f19a123564c42aaab13cbe47a0ed363ac2023ee2b8905eee1678d225eb3');

    test('verifies an openssl signature, recovering the salt length', () {
      expect(rsaVerifyPss(key, crypto.sha256, digest, saltlen32), isTrue);
      expect(rsaVerifyPss(key, crypto.sha256, digest, saltlen0), isTrue);
    });

    test('enforces an explicit salt length when given', () {
      expect(
          rsaVerifyPss(key, crypto.sha256, digest, saltlen32, saltLength: 32),
          isTrue);
      expect(
          rsaVerifyPss(key, crypto.sha256, digest, saltlen0, saltLength: 0),
          isTrue);
      // the wrong declared length is rejected even though the math holds
      expect(
          rsaVerifyPss(key, crypto.sha256, digest, saltlen32, saltLength: 0),
          isFalse);
    });

    test('rejects a wrong digest', () {
      final other =
          crypto.sha256.convert('dart-pdf rsa-pss test messagE'.codeUnits).bytes;
      expect(rsaVerifyPss(key, crypto.sha256, other, saltlen32), isFalse);
    });

    test('rejects a corrupted signature', () {
      final bad = Uint8List.fromList(saltlen32)..[10] ^= 1;
      expect(rsaVerifyPss(key, crypto.sha256, digest, bad), isFalse);
    });
  });

  group('ECDSA', () {
    // vector produced with openssl: prime256v1 key, SHA-256 over
    // 'dart-pdf ecdsa test message'
    final point = hex(
        '0474b3716c54da98198598597f2277100c820378f9b508258d40c7ef14eeb23a'
        '17ee503509bde66c5197460a1ed5053dbae06cba330a7caf4b6fa2a4a65998be'
        'c1');
    final signature = hex(
        '3046022100b4c0cc2dd62b158db0799c3a45f4ad24e2e2c4ca51fcdf2fc2ccd6'
        '79214782f9022100efb780dff41b1ea52da3abdf33c6055426a10ae3d393e4d1'
        '3e6b69773eab4d3b');

    test('verifies an openssl-produced P-256 signature', () {
      final key = EcPublicKey.fromPoint(EcCurve.p256, point);
      final digest = crypto.sha256
          .convert('dart-pdf ecdsa test message'.codeUnits)
          .bytes;
      expect(ecdsaVerify(key, digest, signature), isTrue);
    });

    test('rejects a corrupted digest', () {
      final key = EcPublicKey.fromPoint(EcCurve.p256, point);
      final digest = crypto.sha256
          .convert('dart-pdf ecdsa test messagE'.codeUnits)
          .bytes;
      expect(ecdsaVerify(key, digest, signature), isFalse);
    });
  });

  group('certificate chain verification', () {
    final ca = X509Certificate.parse(pemBytes(testCaCertPem));
    final leaf = X509Certificate.parse(pemBytes(testChainSignerCertPem));
    final selfSigned = X509Certificate.parse(pemBytes(testSignerCertPem));

    test('a CA-signed leaf chains to its anchor', () {
      final result = verifyCertificateChain(
          leaf: leaf, intermediates: [leaf, ca], trustAnchors: [ca]);
      expect(result.trusted, isTrue);
      expect(result.problems, isEmpty);
      expect(result.chain, hasLength(2));
      expect(result.chain.last.subjectCommonName, 'Dart PDF Test CA');
    });

    test('the issuer can come from the trust store alone', () {
      final result = verifyCertificateChain(
          leaf: leaf, intermediates: const [], trustAnchors: [ca]);
      expect(result.trusted, isTrue);
    });

    test('an empty trust store is untrusted with a reason', () {
      final result = verifyCertificateChain(
          leaf: leaf, intermediates: [ca], trustAnchors: const []);
      expect(result.trusted, isFalse);
      expect(result.problems.single, contains('Dart PDF Test CA'));
    });

    test('a self-signed certificate is trusted only as an anchor', () {
      final anchored = verifyCertificateChain(
          leaf: selfSigned, trustAnchors: [selfSigned]);
      expect(anchored.trusted, isTrue);
      final unanchored = verifyCertificateChain(
          leaf: selfSigned,
          intermediates: [selfSigned],
          trustAnchors: [ca]);
      expect(unanchored.trusted, isFalse);
      expect(unanchored.problems.single,
          contains('self-signed certificate'));
    });

    test('the wrong anchor cannot vouch for the leaf', () {
      // the self-signed test cert did not issue the leaf
      final result = verifyCertificateChain(
          leaf: leaf, trustAnchors: [selfSigned]);
      expect(result.trusted, isFalse);
    });

    test('validity windows are enforced at the supplied time', () {
      final tooLate = verifyCertificateChain(
          leaf: leaf, trustAnchors: [ca], at: DateTime.utc(2099, 1, 1));
      expect(tooLate.trusted, isFalse);
      expect(tooLate.problems, isNotEmpty);
      expect(tooLate.problems.first, contains('not valid at'));
      final inWindow = verifyCertificateChain(
          leaf: leaf, trustAnchors: [ca], at: DateTime.utc(2027, 1, 1));
      expect(inWindow.trusted, isTrue);
    });

    test('certificate signatures verify structurally', () {
      expect(leaf.isSignedBy(ca), isTrue);
      expect(leaf.isSignedBy(selfSigned), isFalse);
      expect(ca.isSignedBy(ca), isTrue); // self-signed root
    });
  });
}

/// A throwaway 1024-bit key for fast unit tests (test-only material).
const _testKeyPem = '''
-----BEGIN RSA PRIVATE KEY-----
MIICXAIBAAKBgQDH8QUQ4tO5Pxwm/aYhem1WLTlPemNnMGCFuSIdtZbXQzCMAR6f
XQzvi5fI3+xcVT/FsfsgJ85PltHrnaygOfbopb0DBJxzipPw7sqi5Aj+fxt86oou
pUWtasX3q0RMIwpW/rg0KVxM9FHWfR7lEwlh5qEuNigJAP6R6+gtTgXPUQIDAQAB
AoGBAKptiKrvHhgecmnN9ik9SSuW2u4jXc3cj7oMp8b5PX15+Uytu6ON1nPt4lDI
hpnh1L04S94J8DMpVQBo43ekURBVtJgU10UyKfMU/68yX++RTIj32cKPYG2ELm8x
VVqhhrG4kX5r3sx4hzXc3SCUE8xGV4s4tR4PE9ycmfa6R4GRAkEA780E0rGF+iyN
+332VOIkKY7MEQK/OeMaqBEjveevN3YvcPRRl5aNpFR2QV2oFmzjmja9WiHs7uNh
or5Urc6fbQJBANVysgU2YYfGKd6INMvUc+NgkWSJFnJn3LU0xNLpsI/daCibZJPG
KH8M4ug0RjJqEtNnIS4R5Ic6y+fQ/xiSrPUCQG4wBMFTtT5pbqxbCu+iIf++j+JZ
IslUo5EKnyPJ6+dONSpv+XXwRhF2hggvIud7DXJ1KLjb0eVLMjf3wS1EPlkCQBt9
AeAZ+MV7h7jY4bO+UI5fyVmhLfrd1VagzRg8cDiW0usn1/QP+PcjubUdxkyHzJTd
GzDLrRqdP9VC3RdVDGECQFUB8LSAUJWdsoBo5eINofTwRAnbUIKp81X5Pwza2USF
+5xq8zloUddInXMCk28Ea5qqKwQ7wyGX2tk+Hy2G9YI=
-----END RSA PRIVATE KEY-----
''';
