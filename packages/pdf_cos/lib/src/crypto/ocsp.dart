/// RFC 6960 OCSP, the parts a PDF LTV flow needs: building an OCSPRequest
/// for a certificate, and parsing/validating the OCSPResponse that comes
/// back so it can be embedded in a /DSS and consumed offline later. The
/// HTTP transport is the caller's.
library;

import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import 'asn1.dart';
import 'cms.dart';
import 'ecdsa.dart';
import 'rsa.dart';

abstract final class OcspOid {
  static const basic = '1.3.6.1.5.5.7.48.1.1'; // id-pkix-ocsp-basic
  static const nonce = '1.3.6.1.5.5.7.48.1.2'; // id-pkix-ocsp-nonce
  /// id-kp-OCSPSigning extended key usage for a delegated responder.
  static const ocspSigning = '1.3.6.1.5.5.7.3.9';
}

/// Builds the DER `OCSPRequest` (RFC 6960 §4.1.1) asking whether [cert],
/// issued by [issuer], is revoked. The CertID is keyed by the issuer name
/// hash, issuer key hash, and the certificate serial. [hash] is the CertID
/// digest (SHA-1 is still what most responders key on). An optional [nonce]
/// is echoed by the responder.
Uint8List buildOcspRequest({
  required X509Certificate cert,
  required X509Certificate issuer,
  crypto.Hash hash = crypto.sha1,
  BigInt? nonce,
}) {
  final certId = _certId(cert, issuer, hash);
  final request = derSequence([certId]); // Request ::= SEQUENCE { reqCert }
  final tbsRequest = derSequence([
    derSequence([request]), // requestList SEQUENCE OF Request
    if (nonce != null)
      // requestExtensions [2] EXPLICIT Extensions
      derContext(2, [
        ...derSequence([
          derSequence([
            derOid(OcspOid.nonce),
            derOctetString(ocspNonceValue(nonce)),
          ]),
        ]),
      ]),
  ]);
  return derSequence([tbsRequest]);
}

Uint8List _certId(
    X509Certificate cert, X509Certificate issuer, crypto.Hash hash) {
  final digestOid = digestOidForHash(hash);
  if (digestOid == null) {
    throw ArgumentError('unsupported OCSP CertID digest');
  }
  return derSequence([
    derSequence([derOid(digestOid), derNull()]),
    derOctetString(hash.convert(cert.issuerDer).bytes),
    derOctetString(hash.convert(issuer.subjectPublicKeyBytes).bytes),
    derInteger(cert.serial),
  ]);
}

/// The nonce extension's extnValue payload for [nonce]: an OCTET STRING of
/// the nonce bytes (RFC 8954 §2.1), which a responder echoes verbatim.
Uint8List ocspNonceValue(BigInt nonce) => derOctetString(_bytesOf(nonce));

Uint8List _bytesOf(BigInt value) {
  final bytes = <int>[];
  var rest = value;
  while (rest > BigInt.zero) {
    bytes.insert(0, (rest & BigInt.from(0xFF)).toInt());
    rest >>= 8;
  }
  if (bytes.isEmpty) bytes.add(0);
  if (bytes[0] >= 0x80) bytes.insert(0, 0);
  return Uint8List.fromList(bytes);
}

enum OcspResponseStatus {
  successful(0),
  malformedRequest(1),
  internalError(2),
  tryLater(3),
  sigRequired(5),
  unauthorized(6),
  unknown(-1);

  const OcspResponseStatus(this.value);
  final int value;
  static OcspResponseStatus fromValue(int v) =>
      values.firstWhere((s) => s.value == v,
          orElse: () => OcspResponseStatus.unknown);
}

enum OcspCertStatus { good, revoked, unknown }

/// One SingleResponse inside a BasicOCSPResponse.
class OcspSingleResponse {
  OcspSingleResponse({
    required this.serialNumber,
    required this.status,
    required this.thisUpdate,
    this.nextUpdate,
    this.revocationTime,
    this.revocationReason,
    this.hashAlgorithmOid,
    this.issuerNameHash,
    this.issuerKeyHash,
  });

  final BigInt serialNumber;
  final OcspCertStatus status;
  final DateTime thisUpdate;
  final DateTime? nextUpdate;
  final DateTime? revocationTime;

  /// The CRLReason code of a revoked entry (RFC 5280 §5.3.1), when given.
  final int? revocationReason;

  /// The CertID digest algorithm OID and the issuer name/key hashes it
  /// carries - the rest of the certificate identity besides the serial.
  final String? hashAlgorithmOid;
  final Uint8List? issuerNameHash;
  final Uint8List? issuerKeyHash;

  /// Whether this entry's CertID names [cert] as issued by [issuer]: the
  /// serial, the hash of the issuer's Name, and the hash of the issuer's
  /// public key must all match (RFC 6960 §4.1.1). A serial alone is not an
  /// identity - two CAs can issue the same serial.
  bool matches(X509Certificate cert, X509Certificate issuer) {
    if (serialNumber != cert.serial) return false;
    final oid = hashAlgorithmOid;
    final nameHash = issuerNameHash;
    final keyHash = issuerKeyHash;
    if (oid == null || nameHash == null || keyHash == null) return false;
    final hash = hashForDigestOid(oid);
    if (hash == null) return false;
    return _sameBytes(
            Uint8List.fromList(hash.convert(cert.issuerDer).bytes), nameHash) &&
        _sameBytes(
            Uint8List.fromList(
                hash.convert(issuer.subjectPublicKeyBytes).bytes),
            keyHash);
  }
}

/// A parsed OCSP response. [der] keeps the original bytes for embedding the
/// response verbatim in a /DSS /OCSPs array.
class OcspResponse {
  OcspResponse._(
    this.der,
    this.responseStatus,
    this.producedAt,
    this.responses,
    this.certificates,
    this._tbsResponseData,
    this._signatureAlgorithmOid,
    this._signature,
    this._responderByName,
    this._responderKeyHash, {
    this.nonce,
  });

  /// Parses an `OCSPResponse` (the top-level structure returned over HTTP).
  factory OcspResponse.parse(Uint8List der) {
    final top = DerObject.parse(der).children;
    final status = OcspResponseStatus.fromValue(top[0].asInteger.toInt());
    if (status != OcspResponseStatus.successful || top.length < 2) {
      return OcspResponse._(
          der, status, null, const [], const [], null, null, null, null, null);
    }
    // responseBytes [0] EXPLICIT ResponseBytes ::= SEQUENCE { type, response }
    final responseBytes = top[1].children.first.children;
    final basic = DerObject.parse(responseBytes[1].content).children;
    final tbs = basic[0];
    final signatureAlgorithmOid = basic[1].children[0].asOid;
    final signature = basic[2].asBitString;
    final certificates = <X509Certificate>[];
    if (basic.length > 3 && basic[3].tag == DerTag.context(0)) {
      for (final certDer in basic[3].children.first.children) {
        try {
          certificates.add(X509Certificate.parse(certDer.encoded));
        } on Object {
          // skip unparsable entries
        }
      }
    }

    // ResponseData ::= SEQUENCE { version [0] OPTIONAL, responderID,
    //   producedAt GeneralizedTime, responses SEQUENCE OF SingleResponse,
    //   responseExtensions [1] OPTIONAL }
    final rd = tbs.children;
    var i = 0;
    if (rd[i].tag == DerTag.context(0)) i++; // version
    final responderId = rd[i++];
    Uint8List? responderByName;
    Uint8List? responderKeyHash;
    if (responderId.tag == DerTag.context(1)) {
      responderByName = responderId.children.first.encoded;
    } else if (responderId.tag == DerTag.context(2)) {
      responderKeyHash = responderId.children.first.content;
    }
    final producedAt = rd[i++].asTime;
    final singleResponses = <OcspSingleResponse>[
      for (final single in rd[i].children) _parseSingle(single),
    ];
    i++;
    // responseExtensions [1] EXPLICIT Extensions - the nonce echo lives here
    Uint8List? nonce;
    if (i < rd.length && rd[i].tag == DerTag.context(1)) {
      for (final ext in rd[i].children.first.children) {
        if (ext.children.first.asOid == OcspOid.nonce) {
          nonce = ext.children.last.content;
        }
      }
    }

    return OcspResponse._(
      der,
      status,
      producedAt,
      singleResponses,
      certificates,
      tbs.encoded,
      signatureAlgorithmOid,
      signature,
      responderByName,
      responderKeyHash,
      nonce: nonce,
    );
  }

  static OcspSingleResponse _parseSingle(DerObject single) {
    final f = single.children;
    final certId = f[0].children;
    final serial = certId[3].asInteger;
    final certStatus = f[1];
    OcspCertStatus status;
    DateTime? revocationTime;
    int? revocationReason;
    if (certStatus.tag == DerTag.contextPrimitive(0) ||
        certStatus.tag == DerTag.context(0)) {
      status = OcspCertStatus.good;
    } else if (certStatus.tag == DerTag.context(1) ||
        certStatus.tag == DerTag.contextPrimitive(1)) {
      status = OcspCertStatus.revoked;
      try {
        final info = certStatus.children;
        revocationTime = info.first.asTime;
        // revocationReason [0] EXPLICIT CRLReason (ENUMERATED)
        if (info.length > 1 && info[1].tag == DerTag.context(0)) {
          final reason = info[1].children.first.content;
          if (reason.isNotEmpty) revocationReason = reason.last;
        }
      } on Object {
        // revocationTime is the first field; leave null if unreadable
      }
    } else {
      status = OcspCertStatus.unknown;
    }
    final thisUpdate = f[2].asTime;
    DateTime? nextUpdate;
    for (var j = 3; j < f.length; j++) {
      if (f[j].tag == DerTag.context(0)) {
        nextUpdate = f[j].children.first.asTime;
      }
    }
    return OcspSingleResponse(
      serialNumber: serial,
      status: status,
      thisUpdate: thisUpdate,
      nextUpdate: nextUpdate,
      revocationTime: revocationTime,
      revocationReason: revocationReason,
      hashAlgorithmOid: certId[0].children.first.asOid,
      issuerNameHash: certId[1].content,
      issuerKeyHash: certId[2].content,
    );
  }

  final Uint8List der;
  final OcspResponseStatus responseStatus;
  final DateTime? producedAt;
  final List<OcspSingleResponse> responses;

  /// Certificates the response carried (the responder cert, for delegated
  /// responders) - candidates for verifying the response signature.
  final List<X509Certificate> certificates;

  final Uint8List? _tbsResponseData;
  final String? _signatureAlgorithmOid;
  final Uint8List? _signature;
  final Uint8List? _responderByName;
  final Uint8List? _responderKeyHash;

  /// The extnValue payload of the response's nonce extension, when the
  /// responder echoed one - compare with [echoesNonce].
  final Uint8List? nonce;

  /// Whether the response echoes [requestNonce] (the value passed to
  /// [buildOcspRequest]). Accepts both the RFC 8954 encoding (an OCTET STRING
  /// inside extnValue) and responders that put the raw bytes there.
  bool echoesNonce(BigInt requestNonce) {
    final echoed = nonce;
    if (echoed == null) return false;
    final wrapped = ocspNonceValue(requestNonce);
    return _sameBytes(echoed, wrapped) ||
        _sameBytes(echoed, DerObject.parse(wrapped).content);
  }

  /// The status this response reports for [serial], or null when the
  /// response does not cover that certificate. Prefer [forCertificate],
  /// which also checks the issuer hashes of the CertID.
  OcspSingleResponse? forSerial(BigInt serial) {
    for (final r in responses) {
      if (r.serialNumber == serial) return r;
    }
    return null;
  }

  /// The entry whose CertID identifies [cert] issued by [issuer] (serial,
  /// issuer name hash and issuer key hash), or null.
  OcspSingleResponse? forCertificate(
      X509Certificate cert, X509Certificate issuer) {
    for (final r in responses) {
      if (r.matches(cert, issuer)) return r;
    }
    return null;
  }

  /// The certificate that signed this response on behalf of [issuer]: the
  /// issuing CA itself, or an authorized delegated responder - a certificate
  /// carried in the response, named by the ResponderID, issued *and signed*
  /// by [issuer], and carrying the id-kp-OCSPSigning extended key usage
  /// (RFC 6960 §4.2.2.2). Null when no acceptable responder is found; a
  /// certificate that merely matches the ResponderID but is not authorized
  /// by [issuer] is refused.
  X509Certificate? responderFor(X509Certificate issuer) =>
      _findResponder(issuer);

  /// Verifies the responder's signature over the ResponseData. [issuer] is
  /// the certificate that issued the certificate being checked; the
  /// responder is either [issuer] itself (responses signed directly by the
  /// CA) or a delegated responder certificate carried in [certificates] and
  /// issued by [issuer]. Returns false when the signing key can't be found
  /// or the algorithm is unsupported.
  bool signatureValid(X509Certificate issuer) {
    final tbs = _tbsResponseData;
    final sig = _signature;
    final algOid = _signatureAlgorithmOid;
    if (tbs == null || sig == null || algOid == null) return false;
    final hash = hashForDigestOid(algOid);
    if (hash == null) return false;
    final digest = hash.convert(tbs).bytes;

    final responder = _findResponder(issuer);
    if (responder == null) return false;
    switch (responder.publicKey) {
      case final RsaPublicKey key:
        final digestOid = digestOidForHash(hash);
        if (digestOid == null) return false;
        return rsaVerify(key, digestOid, digest, sig);
      case final EcPublicKey key:
        return ecdsaVerify(key, digest, sig);
      default:
        return false;
    }
  }

  X509Certificate? _findResponder(X509Certificate issuer) {
    bool matches(X509Certificate c) {
      final byName = _responderByName;
      if (byName != null) {
        return _sameBytes(c.subjectDer, byName);
      }
      final keyHash = _responderKeyHash;
      if (keyHash != null) {
        final h = crypto.sha1.convert(c.subjectPublicKeyBytes).bytes;
        return _sameBytes(Uint8List.fromList(h), keyHash);
      }
      return false;
    }

    if (matches(issuer)) return issuer;
    for (final c in certificates) {
      if (!matches(c)) continue;
      // A delegated responder must be authorized by the CA it answers for.
      if (_sameBytes(c.issuerDer, issuer.subjectDer) &&
          c.extendedKeyUsages.contains(OcspOid.ocspSigning) &&
          c.isSignedBy(issuer)) {
        return c;
      }
    }
    // some responders omit a usable ResponderID match; fall back to the CA
    return _responderByName == null && _responderKeyHash == null
        ? issuer
        : null;
  }
}

bool _sameBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
