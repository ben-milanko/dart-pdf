/// Sigstore/Fulcio **keyless** signing - Tier 3 of the automated signing
/// identities (#322).
///
/// Fulcio (the OpenSSF/Sigstore certificate authority) issues a short-lived
/// (~10 minute) X.509 certificate bound to an OIDC-verified identity - an
/// email address the user proves control of by signing in with Google,
/// GitHub, or Microsoft. Nobody has to bring their own PKI, and unlike a
/// self-signed identity the email in the certificate is independently
/// verifiable.
///
/// The flow this file assembles:
///
///  1. mint an ephemeral P-256 key ([EcPrivateKey.generate]),
///  2. read the identity (email) out of the caller's OIDC token and sign it
///     with the ephemeral key - the *proof of possession* Fulcio requires,
///  3. POST the public key + proof + token to Fulcio and receive a certificate
///     chain,
///  4. wrap the ephemeral key and that chain in a [PdfSigningIdentity].
///
/// Because the certificate expires in minutes you must sign immediately and
/// pair it with a trusted timestamp - PAdES **B-T** via
/// [PdfPadesSigning.saveSelfSignedPades], which stamps the signing time from a
/// TSA so the signature stays verifiable long after the certificate lapses.
///
/// True to this library's rule, nothing here touches the network: the OAuth
/// flow and the HTTPS POST are the host's job. The host obtains an OIDC token
/// (an OAuth 2.0 PKCE flow against a Sigstore-accepted issuer) and supplies a
/// [PdfFulcioTransport]; the library builds the request, parses the response,
/// and does all the crypto.
///
/// The Sigstore roots are **not** publicly trusted by Acrobat, so - like every
/// free option (see [PdfSigningIdentity]) - a keyless signature still reads as
/// "signed, validity unknown" there. To validate it inside this library's own
/// viewer, seed a [PdfTrustStore] with the Sigstore root (fetched by the host
/// from the Sigstore TUF trust root; the library ships no built-in roots).
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pdf_cos/pdf_cos.dart';

import 'signing_identity.dart';

/// Public Fulcio `signingCert` endpoints. Transport-only constants - the
/// library performs no I/O; a host POSTs to one of these from its
/// [PdfFulcioTransport].
abstract final class PdfFulcioAuthority {
  /// The production Sigstore Fulcio v2 REST endpoint.
  static const sigstore = 'https://fulcio.sigstore.dev/api/v2/signingCert';

  /// The Sigstore staging Fulcio endpoint, for testing against non-production
  /// certificates.
  static const sigstoreStaging =
      'https://fulcio.sigstage.dev/api/v2/signingCert';
}

/// POSTs the Fulcio v2 `signingCert` request [requestBody] (a UTF-8 JSON body,
/// `Content-Type: application/json`) to a Fulcio endpoint and returns the raw
/// JSON response body. Injected by the caller so the library stays
/// transport-free, mirroring [PdfTimestampClient].
typedef PdfFulcioTransport = Future<Uint8List> Function(Uint8List requestBody);

/// Mints a **keyless** [PdfSigningIdentity] from Fulcio.
///
/// Generates an ephemeral P-256 key, derives the identity subject from
/// [oidcToken] (a raw OIDC ID token / JWT the host obtained via OAuth), builds
/// the proof-of-possession, POSTs the `signingCert` request through
/// [transport], and wraps the returned certificate chain and the ephemeral key
/// in an identity.
///
/// The resulting certificate is valid for only a few minutes: sign right away
/// and pass [PdfPadesLevel.bT] with a timestamp client (see the library-level
/// documentation of this file). Throws a [FormatException] if [oidcToken] has
/// no usable identity claim or the response carries no certificate.
Future<PdfSigningIdentity> fulcioSigningIdentity({
  required String oidcToken,
  required PdfFulcioTransport transport,
  Random? random,
}) async {
  final subject = oidcTokenSubject(oidcToken);
  final key = EcPrivateKey.generate(EcCurve.p256, random: random);
  final proof = fulcioProofOfPossession(key, subject);
  final request = buildFulcioSigningRequest(
    oidcToken: oidcToken,
    publicKey: key.publicKey,
    proofOfPossession: proof,
  );
  final response = await transport(request);
  final chain = parseFulcioCertificateChain(response);
  return PdfSigningIdentity(
    privateKey: key,
    certificates: chain,
    name: subject,
  );
}

/// The identity Fulcio will certify, read from the OIDC token [jwt]: the
/// `email` claim when present (the usual case for Google/Microsoft sign-in),
/// otherwise the `sub` claim (machine identities such as CI tokens). This is
/// the exact string the proof-of-possession signs and that Fulcio places in
/// the certificate's subjectAltName.
///
/// The token is only decoded, never verified here - Fulcio verifies it against
/// its configured issuers. Throws a [FormatException] if the token is not a
/// JWT with a `email` or `sub` claim.
String oidcTokenSubject(String jwt) {
  final parts = jwt.split('.');
  if (parts.length < 2) {
    throw const FormatException('OIDC token is not a JWT');
  }
  final Object? payload;
  try {
    payload = json.decode(utf8.decode(_base64UrlDecode(parts[1])));
  } on Object {
    throw const FormatException('OIDC token payload is not valid JSON');
  }
  if (payload is Map) {
    final email = payload['email'];
    if (email is String && email.isNotEmpty) return email;
    final sub = payload['sub'];
    if (sub is String && sub.isNotEmpty) return sub;
  }
  throw const FormatException('OIDC token has no email or sub claim');
}

/// The Fulcio proof of possession: an ECDSA (over SHA-256) signature by [key]
/// of [subject], DER-encoded `SEQUENCE { r, s }`. Fulcio verifies this against
/// the submitted public key to confirm the requester controls the private key,
/// binding the OIDC identity to it.
Uint8List fulcioProofOfPossession(EcPrivateKey key, String subject) =>
    ecdsaSign(key, crypto.sha256.convert(utf8.encode(subject)).bytes);

/// Builds the Fulcio v2 `CreateSigningCertificateRequest` JSON body: the OIDC
/// token as the credential, the [publicKey] as a PKIX PEM (`PUBLIC KEY`
/// block), and [proofOfPossession] base64-encoded. Returns UTF-8 bytes ready
/// to POST.
Uint8List buildFulcioSigningRequest({
  required String oidcToken,
  required EcPublicKey publicKey,
  required Uint8List proofOfPossession,
}) {
  final body = <String, Object?>{
    'credentials': {'oidcIdentityToken': oidcToken},
    'publicKeyRequest': {
      'publicKey': {
        'algorithm': 'ECDSA',
        'content': pemEncode('PUBLIC KEY', ecSubjectPublicKeyInfo(publicKey)),
      },
      'proofOfPossession': base64.encode(proofOfPossession),
    },
  };
  return Uint8List.fromList(utf8.encode(json.encode(body)));
}

/// Extracts the DER certificate chain (leaf first) from a Fulcio v2
/// `SigningCertificate` JSON [responseBody]. Handles both the embedded- and
/// detached-SCT response shapes. Throws a [FormatException] if no certificate
/// is present.
List<Uint8List> parseFulcioCertificateChain(Uint8List responseBody) {
  final Object? decoded;
  try {
    decoded = json.decode(utf8.decode(responseBody));
  } on Object {
    throw const FormatException('Fulcio response is not valid JSON');
  }
  if (decoded is! Map) {
    throw const FormatException('Fulcio response is not a JSON object');
  }
  final signed = decoded['signedCertificateEmbeddedSct'] ??
      decoded['signedCertificateDetachedSct'];
  final chain = signed is Map ? signed['chain'] : null;
  final certificates = chain is Map ? chain['certificates'] : null;
  if (certificates is! List || certificates.isEmpty) {
    throw const FormatException('Fulcio response carried no certificate chain');
  }
  return [
    for (final pem in certificates)
      if (pem is String) pemBytes(pem),
  ];
}

/// URL-safe base64 decode, tolerating the missing padding a JWT segment omits.
Uint8List _base64UrlDecode(String segment) {
  final padded = segment.padRight((segment.length + 3) & ~3, '=');
  return Uint8List.fromList(base64Url.decode(padded));
}
