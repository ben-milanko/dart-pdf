/// A self-contained, in-process Fulcio certificate authority for tests: it
/// answers a Fulcio v2 `signingCert` request (the JSON body built by
/// `buildFulcioSigningRequest`) with a real, verifiable certificate chain
/// signed by a throwaway EC CA. Test-only - never use outside this repo.
///
/// It exercises the keyless flow end-to-end without a network: it verifies the
/// requester's proof-of-possession, issues a short-lived leaf certificate with
/// the OIDC identity in a subjectAltName, and returns the same JSON shape real
/// Fulcio does. Its [TestFulcioCa.certificate] is the trust anchor a verifier
/// seeds a `PdfTrustStore` with.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pdf_cos/pdf_cos.dart';

/// A throwaway EC certificate authority standing in for Fulcio's issuing CA.
class TestFulcioCa {
  TestFulcioCa(this.key, this.certificate);

  /// Generates a fresh P-256 CA. Pass a seeded [random] for reproducibility.
  factory TestFulcioCa.generate({
    String commonName = 'sigstore-test',
    DateTime? notBefore,
    Duration validity = const Duration(days: 3650),
    Random? random,
  }) {
    final rng = random ?? Random.secure();
    final key = EcPrivateKey.generate(EcCurve.p256, random: rng);
    final start = (notBefore ?? DateTime.utc(2026)).toUtc();
    final cert = buildCaCertificate(
      key: key,
      commonName: commonName,
      notBefore: start,
      notAfter: start.add(validity),
      random: rng,
    );
    return TestFulcioCa(key, cert);
  }

  /// The CA signing key.
  final EcPrivateKey key;

  /// The CA certificate DER - use it as a `PdfTrustStore` anchor.
  final Uint8List certificate;
}

/// Answers the Fulcio `signingCert` request [requestBody] with a certificate
/// chain, mirroring the real service closely enough to drive the keyless
/// signing flow offline.
///
/// It parses the PKIX public key and the base64 proof-of-possession from the
/// request, verifies the proof against the SHA-256 of the OIDC token's identity
/// (`email`, else `sub`) - so a wrong or missing proof fails exactly as Fulcio
/// would - and issues a short-lived leaf certificate carrying that identity in
/// a subjectAltName, signed by [ca]. Returns the UTF-8 JSON body of a
/// `signedCertificateEmbeddedSct` response whose chain is `[leaf, caCert]`.
Uint8List buildTestFulcioResponse(
  Uint8List requestBody, {
  required TestFulcioCa ca,
  DateTime? notBefore,
  Duration validity = const Duration(minutes: 10),
  Random? random,
}) {
  final request = json.decode(utf8.decode(requestBody)) as Map<String, Object?>;
  final token =
      (request['credentials'] as Map)['oidcIdentityToken'] as String;
  final subject = _tokenSubject(token);

  final publicKeyRequest = request['publicKeyRequest'] as Map;
  final pubPem = (publicKeyRequest['publicKey'] as Map)['content'] as String;
  final proof =
      base64.decode(publicKeyRequest['proofOfPossession'] as String);

  final publicKey = _publicKeyFromSpki(pemBytes(pubPem));
  final ok = ecdsaVerify(
    publicKey,
    crypto.sha256.convert(utf8.encode(subject)).bytes,
    Uint8List.fromList(proof),
  );
  if (!ok) {
    throw StateError('Fulcio proof-of-possession failed to verify');
  }

  final start = (notBefore ?? DateTime.utc(2026, 6, 10, 12)).toUtc();
  final leaf = issueCertificate(
    issuerKey: ca.key,
    issuerCertificate: ca.certificate,
    subjectPublicKey: publicKey,
    commonName: subject,
    email: subject.contains('@') ? subject : null,
    notBefore: start.subtract(const Duration(minutes: 5)),
    notAfter: start.add(validity),
    random: random ?? Random.secure(),
  );

  final response = {
    'signedCertificateEmbeddedSct': {
      'chain': {
        'certificates': [
          pemEncode('CERTIFICATE', leaf),
          pemEncode('CERTIFICATE', ca.certificate),
        ],
      },
    },
  };
  return Uint8List.fromList(utf8.encode(json.encode(response)));
}

/// The email (else sub) claim of an unverified JWT - the identity the test CA
/// certifies.
String _tokenSubject(String jwt) {
  final payload = json.decode(utf8.decode(_base64Url(jwt.split('.')[1])));
  final email = payload['email'];
  if (email is String && email.isNotEmpty) return email;
  return payload['sub'] as String;
}

/// Parses an EC [EcPublicKey] out of a DER SubjectPublicKeyInfo.
EcPublicKey _publicKeyFromSpki(Uint8List spki) {
  final seq = DerObject.parse(spki).children;
  final algorithm = seq[0].children;
  final curve = EcCurve.byOid(algorithm[1].asOid) ?? EcCurve.p256;
  return EcPublicKey.fromPoint(curve, seq[1].asBitString);
}

Uint8List _base64Url(String segment) {
  final padded = segment.padRight((segment.length + 3) & ~3, '=');
  return Uint8List.fromList(base64Url.decode(padded));
}
