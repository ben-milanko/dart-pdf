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
            derOctetString(derOctetString(_bytesOf(nonce))),
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
  });

  final BigInt serialNumber;
  final OcspCertStatus status;
  final DateTime thisUpdate;
  final DateTime? nextUpdate;
  final DateTime? revocationTime;
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
    this._responderKeyHash,
  );

  /// Parses an `OCSPResponse` (the top-level structure returned over HTTP).
  factory OcspResponse.parse(Uint8List der) {
    final top = DerObject.parse(der).children;
    final status = OcspResponseStatus.fromValue(top[0].asInteger.toInt());
    if (status != OcspResponseStatus.successful || top.length < 2) {
      return OcspResponse._(der, status, null, const [], const [], null, null,
          null, null, null);
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
    );
  }

  static OcspSingleResponse _parseSingle(DerObject single) {
    final f = single.children;
    final serial = f[0].children[3].asInteger;
    final certStatus = f[1];
    OcspCertStatus status;
    DateTime? revocationTime;
    if (certStatus.tag == DerTag.contextPrimitive(0) ||
        certStatus.tag == DerTag.context(0)) {
      status = OcspCertStatus.good;
    } else if (certStatus.tag == DerTag.context(1) ||
        certStatus.tag == DerTag.contextPrimitive(1)) {
      status = OcspCertStatus.revoked;
      try {
        revocationTime = certStatus.children.first.asTime;
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

  /// The status this response reports for [serial], or null when the
  /// response does not cover that certificate.
  OcspSingleResponse? forSerial(BigInt serial) {
    for (final r in responses) {
      if (r.serialNumber == serial) return r;
    }
    return null;
  }

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
      if (matches(c)) return c;
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
