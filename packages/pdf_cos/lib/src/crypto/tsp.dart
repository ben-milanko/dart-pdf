/// RFC 3161 Time-Stamp Protocol: building the TimeStampReq blob to POST to
/// a TSA, and parsing/verifying the TimeStampToken (a CMS SignedData over a
/// TSTInfo) that comes back. The HTTP transport is the caller's — this layer
/// is bytes-in, bytes-out, so it stays `dart:io`-free and runs on the web.
library;

import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import 'asn1.dart';
import 'cms.dart';

abstract final class TspOid {
  /// id-ct-TSTInfo — the eContentType of a timestamp token.
  static const tstInfo = '1.2.840.113549.1.9.16.1.4';
}

/// Builds the DER `TimeStampReq` (RFC 3161 §2.4.1) that asks a TSA to stamp
/// [messageImprint] — the digest, computed with [hash], of the bytes to be
/// timestamped (for a signature timestamp this is the hash of the signer's
/// signature value; for a document timestamp it is the hash of the signed
/// byte ranges).
///
/// [requestCertificate] asks the TSA to embed its signing certificate in the
/// token (needed so the token verifies offline — required for LTV). A
/// [nonce], when supplied, is echoed in the response and lets the caller
/// detect replay.
Uint8List buildTimeStampRequest({
  required List<int> messageImprint,
  crypto.Hash hash = crypto.sha256,
  BigInt? nonce,
  bool requestCertificate = true,
  String? reqPolicy,
}) {
  final digestOid = digestOidForHash(hash);
  if (digestOid == null) {
    throw ArgumentError('unsupported timestamp digest algorithm');
  }
  final imprint = derSequence([
    derSequence([derOid(digestOid), derNull()]),
    derOctetString(messageImprint),
  ]);
  return derSequence([
    derInteger(BigInt.one), // version v1
    imprint,
    if (reqPolicy != null) derOid(reqPolicy),
    if (nonce != null) derInteger(nonce),
    // certReq DEFAULT FALSE — only emitted when true
    if (requestCertificate) derBoolean(true),
  ]);
}

/// PKIStatus values that matter to a caller (RFC 3161 §2.4.2).
enum TspStatus {
  granted(0),
  grantedWithMods(1),
  rejection(2),
  waiting(3),
  revocationWarning(4),
  revocationNotification(5),
  unknown(-1);

  const TspStatus(this.value);
  final int value;

  static TspStatus fromValue(int v) =>
      values.firstWhere((s) => s.value == v, orElse: () => TspStatus.unknown);

  bool get isSuccess =>
      this == TspStatus.granted || this == TspStatus.grantedWithMods;
}

/// Extracts the bare TimeStampToken (the inner CMS ContentInfo) from a TSA's
/// `TimeStampResp`. Throws when the TSA rejected the request. The returned
/// bytes are exactly what is embedded in a PDF (the DocTimeStamp /Contents,
/// or the signature-time-stamp attribute value).
Uint8List timeStampTokenFromResponse(Uint8List responseDer) {
  final resp = DerObject.parse(responseDer).children;
  // PKIStatusInfo ::= SEQUENCE { status INTEGER, statusString OPTIONAL, ... }
  final status = TspStatus.fromValue(resp[0].children[0].asInteger.toInt());
  if (!status.isSuccess) {
    throw FormatException('TSA rejected the request (status ${status.name})');
  }
  if (resp.length < 2) {
    throw const FormatException('TSA response carries no token');
  }
  return resp[1].encoded;
}

/// The MessageImprint of a TSTInfo — the digest the token attests to.
class TstMessageImprint {
  TstMessageImprint(this.hashAlgorithmOid, this.hashedMessage);
  final String hashAlgorithmOid;
  final Uint8List hashedMessage;
}

/// A parsed RFC 3161 timestamp token: the CMS wrapper plus the decoded
/// TSTInfo it signs.
class TimeStampToken {
  TimeStampToken._(this.cms, this.signer, this.messageImprint, this.genTime,
      this.serialNumber, this.policy, this.nonce);

  /// Parses a TimeStampToken (a CMS SignedData whose eContent is a TSTInfo).
  factory TimeStampToken.parse(Uint8List der) {
    final cms = CmsSignedData.parse(der);
    if (cms.signerInfos.isEmpty) {
      throw const FormatException('timestamp token has no signer');
    }
    final tstInfoDer = cms.eContent;
    if (tstInfoDer == null) {
      throw const FormatException('timestamp token has no TSTInfo');
    }
    final info = DerObject.parse(tstInfoDer).children;
    // TSTInfo ::= SEQUENCE { version, policy, messageImprint, serialNumber,
    //   genTime, accuracy OPTIONAL, ordering DEFAULT FALSE, nonce OPTIONAL,
    //   tsa [0] OPTIONAL, extensions [1] OPTIONAL }
    var i = 1; // version
    final policy = info[i++].asOid;
    final imprint = info[i++].children;
    final messageImprint = TstMessageImprint(
      imprint[0].children[0].asOid,
      imprint[1].content,
    );
    final serialNumber = info[i++].asInteger;
    final genTime = info[i++].asTime;
    BigInt? nonce;
    for (; i < info.length; i++) {
      if (info[i].tag == DerTag.integer) {
        nonce = info[i].asInteger;
        break;
      }
    }
    return TimeStampToken._(cms, cms.signerInfos.first, messageImprint,
        genTime, serialNumber, policy, nonce);
  }

  final CmsSignedData cms;
  final CmsSignerInfo signer;
  final TstMessageImprint messageImprint;

  /// The time the TSA attests it saw the imprint (the trusted clock).
  final DateTime genTime;
  final BigInt serialNumber;
  final String policy;
  final BigInt? nonce;

  /// The TSA's signing certificate, when the token embedded it.
  X509Certificate? get signerCertificate => cms.certificateFor(signer);
}

/// The outcome of verifying a timestamp token against the data it stamps.
class TimeStampVerification {
  TimeStampVerification({
    required this.imprintMatches,
    required this.signatureValid,
    required this.genTime,
    this.problem,
  });

  /// The token's MessageImprint equals the digest of the timestamped data.
  final bool imprintMatches;

  /// The TSA's CMS signature over the TSTInfo verifies.
  final bool signatureValid;

  /// The trusted time the token asserts.
  final DateTime? genTime;

  final String? problem;

  bool get valid => imprintMatches && signatureValid;
}

/// Verifies [token] against [stampedData] — the exact bytes whose digest the
/// token should attest to (the signature value for a signature timestamp,
/// the signed byte ranges for a document timestamp). Confirms the embedded
/// MessageImprint matches and the TSA's CMS signature is cryptographically
/// valid against its embedded certificate. Trust in the TSA certificate is
/// the caller's to establish (via a trust store) and is out of scope here.
TimeStampVerification verifyTimeStampToken(
    TimeStampToken token, List<int> stampedData) {
  final hash = hashForDigestOid(token.messageImprint.hashAlgorithmOid);
  if (hash == null) {
    return TimeStampVerification(
      imprintMatches: false,
      signatureValid: false,
      genTime: token.genTime,
      problem: 'unsupported imprint digest '
          '${token.messageImprint.hashAlgorithmOid}',
    );
  }
  final digest = hash.convert(stampedData).bytes;
  final imprintMatches = _bytesEqual(digest, token.messageImprint.hashedMessage);

  // The token's CMS signs the TSTInfo (the eContent), via signed attributes.
  final verification = cmsVerify(token.cms, token.signer, token.cms.eContent!);
  return TimeStampVerification(
    imprintMatches: imprintMatches,
    signatureValid: verification.signatureValid && verification.digestMatches,
    genTime: token.genTime,
    problem: verification.problem,
  );
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
