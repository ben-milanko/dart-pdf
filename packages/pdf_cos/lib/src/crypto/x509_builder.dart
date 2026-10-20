/// Builds self-signed X.509 v3 certificates from an [EcPrivateKey], the
/// certificate half of the one-tap signing identity (RFC 5280). Assembled
/// with the same DER toolkit the CMS/PKIX code uses and signed with the
/// deterministic ECDSA signer, so it round-trips through
/// [X509Certificate.parse] and validates as its own trust anchor.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import 'asn1.dart';
import 'ecdsa.dart';

abstract final class _CertOid {
  static const commonName = '2.5.4.3';
  static const organizationName = '2.5.4.10';
  static const ecPublicKey = '1.2.840.10045.2.1';
  static const ecdsaWithSha256 = '1.2.840.10045.4.3.2';
  static const ecdsaWithSha384 = '1.2.840.10045.4.3.3';
  static const ecdsaWithSha512 = '1.2.840.10045.4.3.4';
  static const extBasicConstraints = '2.5.29.19';
  static const extKeyUsage = '2.5.29.15';
  static const extSubjectKeyId = '2.5.29.14';
  static const extAuthorityKeyId = '2.5.29.35';
  static const extSubjectAltName = '2.5.29.17';
  static const extExtendedKeyUsage = '2.5.29.37';
  static const extCrlDistributionPoints = '2.5.29.31';
  static const extAuthorityInfoAccess = '1.3.6.1.5.5.7.1.1';
  static const adOcsp = '1.3.6.1.5.5.7.48.1';
  static const ocspNoCheck = '1.3.6.1.5.5.7.48.1.5';
}

/// The ecdsa-with-SHAx AlgorithmIdentifier for [hash] - a bare OID, with no
/// parameters, exactly as RFC 5758 §3.2 specifies for ECDSA.
Uint8List ecdsaSignatureAlgorithm(crypto.Hash hash) =>
    derSequence([derOid(_ecdsaSignatureOid(hash))]);

/// The DER `SubjectPublicKeyInfo` for an EC public key: an AlgorithmIdentifier
/// of id-ecPublicKey + the named-curve OID, then the uncompressed SEC1 point in
/// a BIT STRING. This is the structure an X.509 certificate carries and the
/// body a PKIX `PUBLIC KEY` PEM block wraps - e.g. the public key a Fulcio
/// `signingCert` request sends.
Uint8List ecSubjectPublicKeyInfo(EcPublicKey key) => derSequence([
      derSequence([derOid(_CertOid.ecPublicKey), derOid(key.curve.oid)]),
      derBitString(key.sec1),
    ]);

String _ecdsaSignatureOid(crypto.Hash hash) {
  if (hash == crypto.sha256) return _CertOid.ecdsaWithSha256;
  if (hash == crypto.sha384) return _CertOid.ecdsaWithSha384;
  if (hash == crypto.sha512) return _CertOid.ecdsaWithSha512;
  throw ArgumentError('unsupported ECDSA hash');
}

/// Builds a self-signed X.509 v3 certificate for [key], returning its DER.
///
/// The subject and issuer are the same Name (CN=[commonName], with an
/// optional O=[organization]); [email], when given, goes in a
/// subjectAltName rfc822Name rather than the deprecated emailAddress RDN.
/// The certificate carries basicConstraints (CA:FALSE), a keyUsage of
/// digitalSignature + contentCommitment (the pair a document signer needs),
/// and a subjectKeyIdentifier. [notBefore]/[notAfter] set the validity
/// window; [serialNumber] defaults to a random positive 128-bit value.
Uint8List buildSelfSignedCertificate({
  required EcPrivateKey key,
  required String commonName,
  String? organization,
  String? email,
  required DateTime notBefore,
  required DateTime notAfter,
  BigInt? serialNumber,
  Random? random,
  crypto.Hash hash = crypto.sha256,
}) {
  final publicKey = key.publicKey;
  final name = _name(commonName, organization);
  return _assembleCertificate(
    signingKey: key,
    issuerName: name,
    subjectName: name, // self-signed: subject == issuer
    subjectPublicKey: publicKey,
    notBefore: notBefore,
    notAfter: notAfter,
    serial: serialNumber ?? _randomSerial(random ?? Random.secure()),
    hash: hash,
    extensions: _endEntityExtensions(publicKey, email: email),
  );
}

/// Builds a self-signed X.509 v3 **CA** certificate for [key] - the root of
/// an "org CA" a deployment issues member signing certs from (see
/// [issueCertificate]). Carries basicConstraints cA=TRUE (with an optional
/// [pathLength]) and a keyUsage of keyCertSign + cRLSign. Share its DER as a
/// trust anchor; member certificates then chain to it and validate.
Uint8List buildCaCertificate({
  required EcPrivateKey key,
  required String commonName,
  String? organization,
  required DateTime notBefore,
  required DateTime notAfter,
  int? pathLength,
  BigInt? serialNumber,
  Random? random,
  crypto.Hash hash = crypto.sha256,
}) {
  final publicKey = key.publicKey;
  final name = _name(commonName, organization);
  return _assembleCertificate(
    signingKey: key,
    issuerName: name,
    subjectName: name,
    subjectPublicKey: publicKey,
    notBefore: notBefore,
    notAfter: notAfter,
    serial: serialNumber ?? _randomSerial(random ?? Random.secure()),
    hash: hash,
    extensions: [
      // basicConstraints cA=TRUE, optional pathLenConstraint.
      _extension(_CertOid.extBasicConstraints,
          critical: true,
          value: derSequence([
            derBoolean(true),
            if (pathLength != null) derInteger(BigInt.from(pathLength)),
          ])),
      // keyUsage: keyCertSign (bit 5) + cRLSign (bit 6) -> 0x06, 1 unused bit.
      _extension(_CertOid.extKeyUsage,
          critical: true, value: derEncode(DerTag.bitString, const [1, 0x06])),
      _extension(_CertOid.extSubjectKeyId,
          value: derOctetString(crypto.sha1.convert(publicKey.sec1).bytes)),
    ],
  );
}

/// Issues an end-entity signing certificate for [subjectPublicKey], signed by
/// [issuerKey] and chaining to [issuerCertificate] (a CA built with
/// [buildCaCertificate]). The issuer Name is copied from the CA certificate's
/// subject, and an authorityKeyIdentifier links the two. Pair the returned
/// leaf with the CA certificate as the chain of a signing identity.
///
/// Optional extensions: [ocspResponderUrl] (an Authority Information Access
/// OCSP entry), [crlDistributionUrls] (CRL Distribution Points),
/// [extendedKeyUsages] (purpose OIDs, e.g. id-kp-OCSPSigning for a delegated
/// responder), [ocspNoCheck] (id-pkix-ocsp-nocheck), and [isCa] to issue a
/// subordinate CA (keyCertSign + cRLSign, cA=TRUE) instead of an end entity.
Uint8List issueCertificate({
  required EcPrivateKey issuerKey,
  required Uint8List issuerCertificate,
  required EcPublicKey subjectPublicKey,
  required String commonName,
  String? organization,
  String? email,
  required DateTime notBefore,
  required DateTime notAfter,
  BigInt? serialNumber,
  Random? random,
  crypto.Hash hash = crypto.sha256,
  String? ocspResponderUrl,
  List<String> crlDistributionUrls = const [],
  List<String> extendedKeyUsages = const [],
  bool ocspNoCheck = false,
  bool isCa = false,
}) {
  final extensions = isCa
      ? [
          _extension(_CertOid.extBasicConstraints,
              critical: true, value: derSequence([derBoolean(true)])),
          _extension(_CertOid.extKeyUsage,
              critical: true,
              value: derEncode(DerTag.bitString, const [1, 0x06])),
          _extension(_CertOid.extSubjectKeyId,
              value: derOctetString(
                  crypto.sha1.convert(subjectPublicKey.sec1).bytes)),
          _extension(_CertOid.extAuthorityKeyId,
              value: derSequence([
                derContextPrimitive(
                    0, crypto.sha1.convert(issuerKey.publicKey.sec1).bytes),
              ])),
        ]
      : _endEntityExtensions(
          subjectPublicKey,
          email: email,
          authorityKey: issuerKey.publicKey,
        );
  return _assembleCertificate(
    signingKey: issuerKey,
    issuerName: _subjectNameOf(issuerCertificate),
    subjectName: _name(commonName, organization),
    subjectPublicKey: subjectPublicKey,
    notBefore: notBefore,
    notAfter: notAfter,
    serial: serialNumber ?? _randomSerial(random ?? Random.secure()),
    hash: hash,
    extensions: [
      ...extensions,
      if (extendedKeyUsages.isNotEmpty)
        _extension(_CertOid.extExtendedKeyUsage,
            value: derSequence(
                [for (final oid in extendedKeyUsages) derOid(oid)])),
      if (ocspNoCheck) _extension(_CertOid.ocspNoCheck, value: derNull()),
      if (ocspResponderUrl != null)
        _extension(_CertOid.extAuthorityInfoAccess,
            value: derSequence([
              derSequence([
                derOid(_CertOid.adOcsp),
                derContextPrimitive(6, ascii.encode(ocspResponderUrl)),
              ]),
            ])),
      if (crlDistributionUrls.isNotEmpty)
        _extension(_CertOid.extCrlDistributionPoints,
            value: derSequence([
              for (final url in crlDistributionUrls)
                // DistributionPoint { distributionPoint [0] { fullName [0]
                //   GeneralNames { uniformResourceIdentifier [6] } } }
                derSequence([
                  derContext(0,
                      derContext(0, derContextPrimitive(6, ascii.encode(url)))),
                ]),
            ])),
    ],
  );
}

/// The end-entity extension set: basicConstraints CA:FALSE, a document
/// signer's keyUsage (digitalSignature + contentCommitment), a
/// subjectKeyIdentifier, an optional authorityKeyIdentifier (when issued by a
/// CA), and an optional subjectAltName rfc822Name.
List<Uint8List> _endEntityExtensions(
  EcPublicKey subjectPublicKey, {
  String? email,
  EcPublicKey? authorityKey,
}) =>
    [
      // basicConstraints: cA defaults to FALSE, so an empty SEQUENCE suffices.
      _extension(_CertOid.extBasicConstraints,
          critical: true, value: derSequence(const [])),
      // keyUsage: digitalSignature (bit 0) + contentCommitment (bit 1).
      _extension(_CertOid.extKeyUsage,
          critical: true, value: derEncode(DerTag.bitString, const [6, 0xC0])),
      _extension(_CertOid.extSubjectKeyId,
          value:
              derOctetString(crypto.sha1.convert(subjectPublicKey.sec1).bytes)),
      if (authorityKey != null)
        _extension(_CertOid.extAuthorityKeyId,
            value: derSequence([
              // AuthorityKeyIdentifier keyIdentifier [0] IMPLICIT OCTET STRING
              derContextPrimitive(
                  0, crypto.sha1.convert(authorityKey.sec1).bytes),
            ])),
      if (email != null && email.isNotEmpty)
        _extension(_CertOid.extSubjectAltName,
            value: derSequence([derContextPrimitive(1, ascii.encode(email))])),
    ];

/// Assembles and signs a certificate. [extensions] are the already-encoded
/// Extension SEQUENCEs to place in the v3 extensions [3] field.
Uint8List _assembleCertificate({
  required EcPrivateKey signingKey,
  required Uint8List issuerName,
  required Uint8List subjectName,
  required EcPublicKey subjectPublicKey,
  required DateTime notBefore,
  required DateTime notAfter,
  required BigInt serial,
  required List<Uint8List> extensions,
  required crypto.Hash hash,
}) {
  final signatureAlgorithm = ecdsaSignatureAlgorithm(hash);
  final spki = ecSubjectPublicKeyInfo(subjectPublicKey);
  final tbs = derSequence([
    derContext(0, derInteger(BigInt.two)), // version v3
    derInteger(serial),
    signatureAlgorithm,
    issuerName,
    derSequence([_time(notBefore), _time(notAfter)]),
    subjectName,
    spki,
    derContext(3, derSequence(extensions)),
  ]);
  final signature = ecdsaSign(signingKey, hash.convert(tbs).bytes, hash: hash);
  return derSequence([tbs, signatureAlgorithm, derBitString(signature)]);
}

/// The DER of a certificate's subject Name - the issuer field a certificate
/// this CA issues must carry. Mirrors X509Certificate.parse's TBS indexing.
Uint8List _subjectNameOf(Uint8List certificateDer) {
  final tbs = DerObject.parse(certificateDer).children[0].children;
  // TBSCertificate: [0]version?, serial, sigAlg, issuer, validity, subject...
  final base = tbs[0].tag == DerTag.context(0) ? 1 : 0;
  return tbs[base + 4].encoded;
}

/// A Name of `CN=[commonName]` and, when supplied, `O=[organization]`.
Uint8List _name(String commonName, String? organization) => derSequence([
      _rdn(_CertOid.commonName, commonName),
      if (organization != null && organization.isNotEmpty)
        _rdn(_CertOid.organizationName, organization),
    ]);

Uint8List _rdn(String oid, String value) => derSet([
      derSequence(
          [derOid(oid), derEncode(DerTag.utf8String, utf8.encode(value))]),
    ]);

Uint8List _extension(String oid,
        {bool critical = false, required Uint8List value}) =>
    derSequence([
      derOid(oid),
      if (critical) derBoolean(true),
      derOctetString(value),
    ]);

/// UTCTime before 2050, GeneralizedTime from 2050 on, per RFC 5280 §4.1.2.5.
Uint8List _time(DateTime time) =>
    time.toUtc().year < 2050 ? derUtcTime(time) : derGeneralizedTime(time);

BigInt _randomSerial(Random random) {
  var value = BigInt.zero;
  for (var i = 0; i < 16; i++) {
    value = (value << 8) | BigInt.from(random.nextInt(256));
  }
  // Keep it positive (derInteger pads the sign bit) and non-zero.
  return (value >> 1) | BigInt.one;
}
