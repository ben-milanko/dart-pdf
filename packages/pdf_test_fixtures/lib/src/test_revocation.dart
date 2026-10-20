/// A throwaway three-tier PKI (root -> intermediate -> signer) with an
/// in-process OCSP responder and CRL issuer, for exercising revocation
/// checking without a network. Every artifact is minted on the fly with the
/// pure-Dart EC signer, so tests can dial in any status, freshness window,
/// nonce or responder arrangement. Test-only - never use outside this repo.
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pdf_cos/pdf_cos.dart';

/// The OCSP URL the test signer and intermediate certificates advertise.
const testOcspUrl = 'http://ocsp.test.invalid/';

/// The CRL distribution point of the test signer (issued by the
/// intermediate).
const testSignerCrlUrl = 'http://crl.test.invalid/intermediate.crl';

/// The CRL distribution point of the test intermediate (issued by the root).
const testIntermediateCrlUrl = 'http://crl.test.invalid/root.crl';

/// A root CA, an intermediate CA, a document signer, and a delegated OCSP
/// responder authorized by the intermediate - all P-256.
class TestRevocationPki {
  TestRevocationPki._({
    required this.rootKey,
    required this.root,
    required this.intermediateKey,
    required this.intermediate,
    required this.signerKey,
    required this.signer,
    required this.responderKey,
    required this.responder,
    required this.rogueResponder,
  });

  /// Mints a fresh hierarchy valid from [notBefore] for ten years. Pass a
  /// seeded [random] for reproducible keys.
  factory TestRevocationPki.generate({DateTime? notBefore, Random? random}) {
    final rng = random ?? Random.secure();
    final start = (notBefore ?? DateTime.utc(2026)).toUtc();
    final end = start.add(const Duration(days: 3650));
    final rootKey = EcPrivateKey.generate(EcCurve.p256, random: rng);
    final root = buildCaCertificate(
      key: rootKey,
      commonName: 'Revocation Test Root',
      organization: 'dart-pdf',
      notBefore: start,
      notAfter: end,
      random: rng,
    );
    final intermediateKey = EcPrivateKey.generate(EcCurve.p256, random: rng);
    final intermediate = issueCertificate(
      issuerKey: rootKey,
      issuerCertificate: root,
      subjectPublicKey: intermediateKey.publicKey,
      commonName: 'Revocation Test Intermediate',
      organization: 'dart-pdf',
      notBefore: start,
      notAfter: end,
      isCa: true,
      ocspResponderUrl: testOcspUrl,
      crlDistributionUrls: const [testIntermediateCrlUrl],
      random: rng,
    );
    final signerKey = EcPrivateKey.generate(EcCurve.p256, random: rng);
    final signer = issueCertificate(
      issuerKey: intermediateKey,
      issuerCertificate: intermediate,
      subjectPublicKey: signerKey.publicKey,
      commonName: 'Revocation Test Signer',
      organization: 'dart-pdf',
      notBefore: start,
      notAfter: end,
      ocspResponderUrl: testOcspUrl,
      crlDistributionUrls: const [testSignerCrlUrl],
      serialNumber: BigInt.from(0x5151),
      random: rng,
    );
    final responderKey = EcPrivateKey.generate(EcCurve.p256, random: rng);
    final responder = issueCertificate(
      issuerKey: intermediateKey,
      issuerCertificate: intermediate,
      subjectPublicKey: responderKey.publicKey,
      commonName: 'Revocation Test OCSP Responder',
      notBefore: start,
      notAfter: end,
      extendedKeyUsages: const [OcspOid.ocspSigning],
      ocspNoCheck: true,
      random: rng,
    );
    // Same key as the real responder, issued by the intermediate, but
    // WITHOUT the OCSPSigning purpose - an unauthorized delegate.
    final rogueResponder = issueCertificate(
      issuerKey: intermediateKey,
      issuerCertificate: intermediate,
      subjectPublicKey: responderKey.publicKey,
      commonName: 'Revocation Test OCSP Responder',
      notBefore: start,
      notAfter: end,
      random: rng,
    );
    return TestRevocationPki._(
      rootKey: rootKey,
      root: root,
      intermediateKey: intermediateKey,
      intermediate: intermediate,
      signerKey: signerKey,
      signer: signer,
      responderKey: responderKey,
      responder: responder,
      rogueResponder: rogueResponder,
    );
  }

  final EcPrivateKey rootKey;

  /// The self-signed root (DER) - the trust anchor.
  final Uint8List root;

  final EcPrivateKey intermediateKey;

  /// The intermediate CA (DER), issued by [root].
  final Uint8List intermediate;

  final EcPrivateKey signerKey;

  /// The document signer (DER, serial 0x5151), issued by [intermediate],
  /// advertising [testOcspUrl] and [testSignerCrlUrl].
  final Uint8List signer;

  final EcPrivateKey responderKey;

  /// A delegated OCSP responder authorized by [intermediate]
  /// (id-kp-OCSPSigning + ocsp-nocheck).
  final Uint8List responder;

  /// A certificate for [responderKey] issued by [intermediate] but without
  /// the OCSPSigning purpose - responses it signs must be refused.
  final Uint8List rogueResponder;

  /// The signing chain, leaf first: signer, intermediate, root.
  List<Uint8List> get chain => [signer, intermediate, root];
}

/// Builds a DER `OCSPResponse` reporting [status] for [certificate], issued
/// by [issuer]. By default the issuer CA signs it directly with [signerKey];
/// pass [responderCertificate] to sign as a delegated responder (the
/// certificate is embedded and named by the ResponderID). [nonce] is echoed
/// verbatim as the nonce extension's extnValue payload (see
/// `ocspNonceValue`).
Uint8List buildTestOcspResponse({
  required Uint8List certificate,
  required Uint8List issuer,
  required EcPrivateKey signerKey,
  Uint8List? responderCertificate,
  OcspCertStatus status = OcspCertStatus.good,
  required DateTime thisUpdate,
  DateTime? nextUpdate,
  DateTime? producedAt,
  DateTime? revocationTime,
  int? revocationReason,
  Uint8List? nonce,
  bool responderByKey = false,
}) {
  final cert = X509Certificate.parse(certificate);
  final ca = X509Certificate.parse(issuer);
  final signerCert = X509Certificate.parse(responderCertificate ?? issuer);
  final certId = derSequence([
    derSequence([derOid(DigestOid.sha1), derNull()]),
    derOctetString(crypto.sha1.convert(cert.issuerDer).bytes),
    derOctetString(crypto.sha1.convert(ca.subjectPublicKeyBytes).bytes),
    derInteger(cert.serial),
  ]);
  final certStatus = switch (status) {
    OcspCertStatus.good => derContextPrimitive(0, const []),
    OcspCertStatus.unknown => derContextPrimitive(2, const []),
    OcspCertStatus.revoked => derContext(1, [
        ...derGeneralizedTime(revocationTime ?? thisUpdate),
        if (revocationReason != null)
          ...derContext(0, derEnumerated(revocationReason)),
      ]),
  };
  final single = derSequence([
    certId,
    certStatus,
    derGeneralizedTime(thisUpdate),
    if (nextUpdate != null) derContext(0, derGeneralizedTime(nextUpdate)),
  ]);
  final responderId = responderByKey
      ? derContext(
          2,
          derOctetString(
              crypto.sha1.convert(signerCert.subjectPublicKeyBytes).bytes))
      : derContext(1, signerCert.subjectDer);
  final tbs = derSequence([
    responderId,
    derGeneralizedTime(producedAt ?? thisUpdate),
    derSequence([single]),
    if (nonce != null)
      derContext(
          1,
          derSequence([
            derSequence([derOid(OcspOid.nonce), derOctetString(nonce)]),
          ])),
  ]);
  final signature = ecdsaSign(signerKey, crypto.sha256.convert(tbs).bytes);
  final basic = derSequence([
    tbs,
    ecdsaSignatureAlgorithm(crypto.sha256),
    derBitString(signature),
    if (responderCertificate != null)
      derContext(0, derSequence([responderCertificate])),
  ]);
  return derSequence([
    derEnumerated(0), // successful
    derContext(
        0,
        derSequence([
          derOid(OcspOid.basic),
          derOctetString(basic),
        ])),
  ]);
}

/// Builds a DER CRL issued (and signed) by [issuer] with [issuerKey],
/// listing each serial in [revoked] with its revocation date.
Uint8List buildTestCrl({
  required Uint8List issuer,
  required EcPrivateKey issuerKey,
  Map<BigInt, DateTime> revoked = const {},
  required DateTime thisUpdate,
  DateTime? nextUpdate,
}) {
  final ca = X509Certificate.parse(issuer);
  final algorithm = ecdsaSignatureAlgorithm(crypto.sha256);
  final tbs = derSequence([
    derInteger(BigInt.one), // v2
    algorithm,
    ca.subjectDer,
    derUtcTime(thisUpdate),
    if (nextUpdate != null) derUtcTime(nextUpdate),
    if (revoked.isNotEmpty)
      derSequence([
        for (final entry in revoked.entries)
          derSequence([derInteger(entry.key), derUtcTime(entry.value)]),
      ]),
  ]);
  final signature = ecdsaSign(issuerKey, crypto.sha256.convert(tbs).bytes);
  return derSequence([tbs, algorithm, derBitString(signature)]);
}
