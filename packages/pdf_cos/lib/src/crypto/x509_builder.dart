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
}

/// The ecdsa-with-SHAx AlgorithmIdentifier for [hash] - a bare OID, with no
/// parameters, exactly as RFC 5758 §3.2 specifies for ECDSA.
Uint8List ecdsaSignatureAlgorithm(crypto.Hash hash) =>
    derSequence([derOid(_ecdsaSignatureOid(hash))]);

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
}) {
  return _assembleCertificate(
    signingKey: issuerKey,
    issuerName: _subjectNameOf(issuerCertificate),
    subjectName: _name(commonName, organization),
    subjectPublicKey: subjectPublicKey,
    notBefore: notBefore,
    notAfter: notAfter,
    serial: serialNumber ?? _randomSerial(random ?? Random.secure()),
    hash: hash,
    extensions: _endEntityExtensions(
      subjectPublicKey,
      email: email,
      authorityKey: issuerKey.publicKey,
    ),
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
  final spki = derSequence([
    derSequence([derOid(_CertOid.ecPublicKey), derOid(subjectPublicKey.curve.oid)]),
    derBitString(subjectPublicKey.sec1),
  ]);
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
      derSequence([derOid(oid), derEncode(DerTag.utf8String, utf8.encode(value))]),
    ]);

Uint8List _extension(String oid, {bool critical = false, required Uint8List value}) =>
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
