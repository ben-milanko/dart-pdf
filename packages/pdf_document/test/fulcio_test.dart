import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

/// A deterministic PRNG so key generation and serials are reproducible.
/// Never use outside tests - this is not a secure source.
class _SeededRandom implements Random {
  _SeededRandom(this._state);
  int _state;
  int _next() {
    _state = (_state * 1103515245 + 12345) & 0x7fffffff;
    return _state;
  }

  @override
  int nextInt(int max) => _next() % max;
  @override
  double nextDouble() => _next() / 0x7fffffff;
  @override
  bool nextBool() => _next().isEven;
}

/// Builds an unsigned JWT (`header.payload.` with an empty signature) carrying
/// [claims] - enough for the library to read the identity from; Fulcio, not
/// this library, is what verifies the real signature.
String _jwt(Map<String, Object?> claims) {
  String seg(Object o) =>
      base64Url.encode(utf8.encode(json.encode(o))).replaceAll('=', '');
  return '${seg({'alg': 'RS256'})}.${seg(claims)}.';
}

void main() {
  group('OIDC token subject', () {
    test('prefers the email claim', () {
      final token = _jwt({'email': 'dev@example.com', 'sub': 'abc'});
      expect(oidcTokenSubject(token), 'dev@example.com');
    });

    test('falls back to sub when there is no email', () {
      final token = _jwt({'sub': 'https://github.com/login/oauth|42'});
      expect(oidcTokenSubject(token), 'https://github.com/login/oauth|42');
    });

    test('rejects a non-JWT', () {
      expect(() => oidcTokenSubject('not-a-token'), throwsFormatException);
    });

    test('rejects a token with neither email nor sub', () {
      expect(() => oidcTokenSubject(_jwt({'aud': 'sigstore'})),
          throwsFormatException);
    });
  });

  group('proof of possession', () {
    final key = EcPrivateKey.generate(EcCurve.p256, random: _SeededRandom(3));

    test('verifies against the public key over SHA-256 of the subject', () {
      const subject = 'dev@example.com';
      final proof = fulcioProofOfPossession(key, subject);
      final digest = crypto.sha256.convert(utf8.encode(subject)).bytes;
      expect(ecdsaVerify(key.publicKey, digest, proof), isTrue);
      // a proof over a different subject does not verify
      final other = crypto.sha256.convert(utf8.encode('evil@example.com')).bytes;
      expect(ecdsaVerify(key.publicKey, other, proof), isFalse);
    });
  });

  group('signingCert request encoding', () {
    final key = EcPrivateKey.generate(EcCurve.p256, random: _SeededRandom(5));

    test('carries the token, a PKIX public key and the base64 proof', () {
      final token = _jwt({'email': 'dev@example.com'});
      final proof = fulcioProofOfPossession(key, 'dev@example.com');
      final body = json.decode(utf8.decode(buildFulcioSigningRequest(
        oidcToken: token,
        publicKey: key.publicKey,
        proofOfPossession: proof,
      ))) as Map<String, Object?>;

      expect((body['credentials'] as Map)['oidcIdentityToken'], token);
      final pkr = body['publicKeyRequest'] as Map;
      expect((pkr['publicKey'] as Map)['algorithm'], 'ECDSA');
      final pem = (pkr['publicKey'] as Map)['content'] as String;
      expect(pem, contains('BEGIN PUBLIC KEY'));
      // the PEM decodes to the SPKI of the ephemeral key
      expect(pemBytes(pem), ecSubjectPublicKeyInfo(key.publicKey));
      expect(base64.decode(pkr['proofOfPossession'] as String), proof);
    });
  });

  group('certificate chain parsing', () {
    Uint8List response(String key) => Uint8List.fromList(utf8.encode(json.encode({
          key: {
            'chain': {
              'certificates': [
                pemEncode('CERTIFICATE', Uint8List.fromList([1, 2, 3])),
                pemEncode('CERTIFICATE', Uint8List.fromList([4, 5, 6])),
              ],
            },
          },
        })));

    test('reads the embedded-SCT shape, leaf first', () {
      final chain =
          parseFulcioCertificateChain(response('signedCertificateEmbeddedSct'));
      expect(chain, hasLength(2));
      expect(chain.first, [1, 2, 3]);
      expect(chain.last, [4, 5, 6]);
    });

    test('reads the detached-SCT shape too', () {
      final chain =
          parseFulcioCertificateChain(response('signedCertificateDetachedSct'));
      expect(chain.first, [1, 2, 3]);
    });

    test('rejects a response with no chain', () {
      final empty = Uint8List.fromList(utf8.encode(json.encode({'x': 1})));
      expect(() => parseFulcioCertificateChain(empty), throwsFormatException);
    });
  });

  group('keyless signing end to end (in-process Fulcio)', () {
    final signedAt = DateTime.utc(2026, 6, 10, 12);
    final ca = TestFulcioCa.generate(
      notBefore: DateTime.utc(2026),
      random: _SeededRandom(101),
    );

    Future<PdfSigningIdentity> mintIdentity() => fulcioSigningIdentity(
          oidcToken: _jwt({'email': 'dev@example.com'}),
          transport: (request) async => buildTestFulcioResponse(
            request,
            ca: ca,
            notBefore: signedAt,
            random: _SeededRandom(202),
          ),
          random: _SeededRandom(303),
        );

    test('mints an identity whose chain includes the Fulcio CA', () async {
      final identity = await mintIdentity();
      expect(identity.name, 'dev@example.com');
      expect(identity.certificates, hasLength(2));
      final leaf = X509Certificate.parse(identity.certificate);
      expect(leaf.subjectCommonName, 'dev@example.com');
      expect(leaf.publicKey, isA<EcPublicKey>());
    });

    test('a timestamped keyless signature validates and is trusted', () async {
      final identity = await mintIdentity();
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
      expect(signature.signerName, 'dev@example.com');

      // intact and, against the Sigstore CA as a trust anchor, trusted
      final trustStore = PdfTrustStore.trusting([ca.certificate]);
      final result = signature.validate(trustStore: trustStore);
      expect(result.intact, isTrue, reason: result.problems.join('; '));
      expect(result.signatureValid, isTrue);
      expect(result.timestamp, isNotNull);
      expect(result.chainTrusted, isTrue,
          reason: result.chainProblems.join('; '));
    });

    test('a tampered proof is rejected by the CA', () async {
      // Drive the transport with a request whose proof is for a wrong subject.
      final key = EcPrivateKey.generate(EcCurve.p256, random: _SeededRandom(7));
      final badRequest = buildFulcioSigningRequest(
        oidcToken: _jwt({'email': 'dev@example.com'}),
        publicKey: key.publicKey,
        proofOfPossession: fulcioProofOfPossession(key, 'someone-else'),
      );
      expect(
        () => buildTestFulcioResponse(badRequest, ca: ca),
        throwsA(isA<StateError>()),
      );
    });
  });
}
