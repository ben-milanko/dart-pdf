import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pdf_cos/pdf_cos.dart';
import 'package:test/test.dart';

BigInt _hexInt(String s) => BigInt.parse(s.replaceAll(' ', ''), radix: 16);

/// A deterministic PRNG so key generation and serials are reproducible in
/// tests (never use outside tests - this is not a secure source).
class _SeededRandom implements Random {
  _SeededRandom(this._state);
  int _state;

  @override
  int nextInt(int max) {
    // xorshift32, then reduce into [0, max)
    _state ^= (_state << 13) & 0xFFFFFFFF;
    _state ^= _state >> 17;
    _state ^= (_state << 5) & 0xFFFFFFFF;
    return (_state & 0x7FFFFFFF) % max;
  }

  @override
  bool nextBool() => nextInt(2) == 1;
  @override
  double nextDouble() => nextInt(1 << 30) / (1 << 30);
}

void main() {
  group('ECDSA deterministic signing (RFC 6979)', () {
    // RFC 6979 Appendix A.2.5, curve NIST P-256 (prime256v1), SHA-256.
    final key = EcPrivateKey(
      EcCurve.p256,
      _hexInt('C9AFA9D845BA75166B5C215767B1D693'
          '4E50C3DB36E89B127B8A622B120F6721'),
    );

    void checkVector(String message, String rHex, String sHex) {
      final digest = crypto.sha256.convert(ascii.encode(message)).bytes;
      final (r, s) = ecdsaSignRs(key, digest);
      expect(r, _hexInt(rHex), reason: 'r for "$message"');
      expect(s, _hexInt(sHex), reason: 's for "$message"');
    }

    test('matches the RFC 6979 vector for "sample"', () {
      checkVector(
        'sample',
        'EFD48B2AACB6A8FD1140DD9CD45E81D6'
            '9D2C877B56AAF991C34D0EA84EAF3716',
        'F7CB1C942D657C41D436C7A1B6E29F65'
            'F3E900DBB9AFF4064DC4AB2F843ACDA8',
      );
    });

    test('matches the RFC 6979 vector for "test"', () {
      checkVector(
        'test',
        'F1ABB023518351CD71D881567B1EA663'
            'ED3EFCF6C5132B354F28D3B0B7D38367',
        '019F4113742A2B14BD25926B49C64915'
            '5F267E60D3814B4C0CC84250E46F0083',
      );
    });

    test('the DER signature verifies with our own verifier', () {
      final digest = crypto.sha256.convert(ascii.encode('sample')).bytes;
      final signature = ecdsaSign(key, digest);
      expect(ecdsaVerify(key.publicKey, digest, signature), isTrue);
    });

    test('a tampered digest fails to verify', () {
      final signature =
          ecdsaSign(key, crypto.sha256.convert(ascii.encode('sample')).bytes);
      final other = crypto.sha256.convert(ascii.encode('samplE')).bytes;
      expect(ecdsaVerify(key.publicKey, other, signature), isFalse);
    });
  });

  group('EC key generation', () {
    test('a generated key signs and verifies', () {
      final key = EcPrivateKey.generate(EcCurve.p256, random: _SeededRandom(1));
      expect(key.d >= BigInt.one && key.d < EcCurve.p256.n, isTrue);
      final digest = crypto.sha256.convert(ascii.encode('hello')).bytes;
      expect(
          ecdsaVerify(key.publicKey, digest, ecdsaSign(key, digest)), isTrue);
    });

    test('the public point lies on the curve and is 65 SEC1 bytes', () {
      final key = EcPrivateKey.generate(EcCurve.p256, random: _SeededRandom(2));
      final pub = key.publicKey;
      final curve = EcCurve.p256;
      final lhs = (pub.y * pub.y) % curve.p;
      final rhs = (pub.x * pub.x * pub.x + curve.a * pub.x + curve.b) % curve.p;
      expect(lhs, rhs);
      expect(pub.sec1.length, 65);
      expect(pub.sec1.first, 0x04);
    });

    test('the private key round-trips through its SEC1 DER', () {
      final key = EcPrivateKey.generate(EcCurve.p256, random: _SeededRandom(5));
      final restored = EcPrivateKey.fromSec1(key.sec1Der);
      expect(restored.d, key.d);
      expect(restored.curve.oid, key.curve.oid);
      final digest = crypto.sha256.convert(ascii.encode('roundtrip')).bytes;
      expect(ecdsaVerify(restored.publicKey, digest, ecdsaSign(restored, digest)),
          isTrue);
    });

    test('a PKCS#8 key reads its curve from the outer AlgorithmIdentifier',
        () {
      // A non-P256 key whose PKCS#8 inner ECPrivateKey omits its own [0]
      // curve params - the curve must come from the outer AlgorithmIdentifier.
      final key = EcPrivateKey.generate(EcCurve.p384, random: _SeededRandom(3));
      final size = (EcCurve.p384.n.bitLength + 7) >> 3;
      final scalar = Uint8List(size);
      var rest = key.d;
      for (var i = size - 1; i >= 0 && rest > BigInt.zero; i--) {
        scalar[i] = (rest & BigInt.from(0xFF)).toInt();
        rest >>= 8;
      }
      final inner = derSequence([derInteger(BigInt.one), derOctetString(scalar)]);
      final pkcs8 = derSequence([
        derInteger(BigInt.zero),
        derSequence([
          derOid('1.2.840.10045.2.1'), // ecPublicKey
          derOid(EcCurve.p384.oid), // named curve, outer only
        ]),
        derOctetString(inner),
      ]);

      final restored = EcPrivateKey.fromSec1(pkcs8);
      expect(restored.curve.oid, EcCurve.p384.oid);
      expect(restored.d, key.d);
      expect(restored.publicKey.x, key.publicKey.x);
    });
  });

  group('self-signed X.509 builder', () {
    final key = EcPrivateKey.generate(EcCurve.p256, random: _SeededRandom(7));
    final notBefore = DateTime.utc(2026, 1, 1);
    final notAfter = DateTime.utc(2031, 1, 1);

    Uint8List build({String? email, String? org}) => buildSelfSignedCertificate(
          key: key,
          commonName: 'Ada Lovelace',
          organization: org,
          email: email,
          notBefore: notBefore,
          notAfter: notAfter,
          serialNumber: BigInt.from(0x4242),
          random: _SeededRandom(9),
        );

    test('round-trips through our X.509 parser', () {
      final cert = X509Certificate.parse(build(org: 'dart-pdf'));
      expect(cert.subjectCommonName, 'Ada Lovelace');
      expect(cert.subject['2.5.4.10'], 'dart-pdf');
      expect(cert.serial, BigInt.from(0x4242));
      expect(cert.notBefore, notBefore);
      expect(cert.notAfter, notAfter);
      expect(cert.publicKey, isA<EcPublicKey>());
      // subject == issuer for a self-signed certificate
      expect(cert.subjectDer, cert.issuerDer);
    });

    test('is signed by its own key (a valid trust anchor)', () {
      final cert = X509Certificate.parse(build());
      expect(cert.isSignedBy(cert), isTrue);
      final result =
          verifyCertificateChain(leaf: cert, trustAnchors: [cert], at: DateTime.utc(2027));
      expect(result.trusted, isTrue, reason: result.problems.join('; '));
    });

    test('the embedded public key matches the signing key', () {
      final cert = X509Certificate.parse(build());
      final parsed = cert.publicKey as EcPublicKey;
      expect(parsed.x, key.publicKey.x);
      expect(parsed.y, key.publicKey.y);
    });
  });

  group('CMS detached signing with ECDSA', () {
    final key = EcPrivateKey.generate(EcCurve.p256, random: _SeededRandom(11));
    final certDer = buildSelfSignedCertificate(
      key: key,
      commonName: 'Grace Hopper',
      notBefore: DateTime.utc(2026),
      notAfter: DateTime.utc(2036),
      random: _SeededRandom(13),
    );
    final cert = X509Certificate.parse(certDer);
    final content = Uint8List.fromList(utf8.encode('the signed document'));

    test('a plain EC CMS verifies', () {
      final cms = cmsSignDetachedEcdsa(
        contentDigest: crypto.sha256.convert(content).bytes,
        privateKey: key,
        certificates: [certDer],
      );
      final parsed = CmsSignedData.parse(cms);
      expect(parsed.signerInfos.first.hasSigningCertificate, isFalse);
      final v = cmsVerify(parsed, parsed.signerInfos.first, content);
      expect(v.digestMatches, isTrue);
      expect(v.signatureValid, isTrue);
    });

    test('a PAdES EC CMS carries signing-certificate-v2 and verifies', () {
      final cms = cmsSignDetachedEcdsa(
        contentDigest: crypto.sha256.convert(content).bytes,
        privateKey: key,
        certificates: [certDer],
        essCertificate: cert,
        signingTime: DateTime.utc(2026, 6, 1),
      );
      final parsed = CmsSignedData.parse(cms);
      final signer = parsed.signerInfos.first;
      expect(signer.hasSigningCertificate, isTrue);
      final v = cmsVerify(parsed, signer, content);
      expect(v.digestMatches, isTrue);
      expect(v.signatureValid, isTrue);
    });

    test('tampered content fails the digest check', () {
      final cms = cmsSignDetachedEcdsa(
        contentDigest: crypto.sha256.convert(content).bytes,
        privateKey: key,
        certificates: [certDer],
      );
      final parsed = CmsSignedData.parse(cms);
      final v = cmsVerify(parsed, parsed.signerInfos.first,
          Uint8List.fromList(utf8.encode('the tampered document')));
      expect(v.digestMatches, isFalse);
    });
  });
}
