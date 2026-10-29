/// PAdES (ETSI EN 319 142) baseline profiles and the pluggable network
/// seams a PAdES signature needs. The library never touches the network
/// itself (no `dart:io` in `lib/`): the caller supplies the TSA and
/// revocation transports, mirroring how OCR engines are injected.
library;

import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';

/// The PAdES baseline levels, in increasing order of long-term assurance.
enum PdfPadesLevel {
  /// B-B: basic - correct signed attributes incl. signing-certificate-v2.
  bB,

  /// B-T: B-B plus a trusted signature timestamp.
  bT,

  /// B-LT: B-T plus all certificate, OCSP and CRL validation material
  /// embedded in a /DSS, so the signature verifies offline forever.
  bLT,

  /// B-LTA: B-LT plus a document timestamp (DocTimeStamp), which can be
  /// renewed to extend trust past the timestamp's own certificate expiry.
  bLTA;

  bool operator >=(PdfPadesLevel other) => index >= other.index;
}

/// Obtains an RFC 3161 timestamp token for [timeStampRequest] - the DER
/// `TimeStampReq` built by [buildTimeStampRequest]. Implementations POST the
/// request to their TSA and return the bare `TimeStampToken` (the inner
/// ContentInfo, e.g. via [timeStampTokenFromResponse]). Injected by the
/// caller so the library stays transport-free.
typedef PdfTimestampClient = Future<Uint8List> Function(
    Uint8List timeStampRequest);

/// Free, public RFC 3161 timestamp authorities suitable as the default a
/// signature is timestamped against. A trusted timestamp gives even a
/// self-signed signature CA-anchored signing time - the timestamp chain
/// often validates in Acrobat even when the signer certificate does not.
///
/// These are transport endpoints only; the library performs no I/O. A host
/// wires one into a [PdfTimestampClient] that POSTs the DER `TimeStampReq`
/// with `Content-Type: application/timestamp-query` and returns the token
/// via [timeStampTokenFromResponse]. [digicert] is a sensible default; the
/// others are alternates to fall back to.
abstract final class PdfDefaultTimestampAuthority {
  /// DigiCert's public TSA - the recommended default (no account needed).
  static const digicert = 'http://timestamp.digicert.com';

  /// Sectigo's public TSA.
  static const sectigo = 'http://timestamp.sectigo.com';

  /// Apple's public TSA.
  static const apple = 'http://timestamp.apple.com/ts01';

  /// freeTSA.org, a community-run TSA.
  static const freeTsa = 'https://freetsa.org/tsr';

  /// All of the above, [digicert] first, for a fall-back list.
  static const all = [digicert, sectigo, apple, freeTsa];
}

/// Revocation and certificate material gathered for a signature's chain,
/// ready to embed in a /DSS for LTV. All blobs are DER: OCSP responses are
/// `OCSPResponse` structures, CRLs are `CertificateList`s, and
/// [certificates] are extra X.509 certificates (intermediates, responder
/// certs) the verifier may need offline.
class PdfRevocationMaterial {
  const PdfRevocationMaterial({
    this.ocspResponses = const [],
    this.crls = const [],
    this.certificates = const [],
  });

  final List<Uint8List> ocspResponses;
  final List<Uint8List> crls;
  final List<Uint8List> certificates;

  bool get isEmpty =>
      ocspResponses.isEmpty && crls.isEmpty && certificates.isEmpty;

  PdfRevocationMaterial operator +(PdfRevocationMaterial other) =>
      PdfRevocationMaterial(
        ocspResponses: [...ocspResponses, ...other.ocspResponses],
        crls: [...crls, ...other.crls],
        certificates: [...certificates, ...other.certificates],
      );
}

/// Fetches revocation material for the certificate [chain] (leaf first) so
/// the editor can embed it in a /DSS. A typical implementation builds an
/// OCSP request per certificate with [buildOcspRequest] (POSTing to the
/// cert's [X509Certificate.ocspResponderUrl]) and/or downloads the CRL from
/// [X509Certificate.crlDistributionUrls], returning whatever it could
/// gather. Injected by the caller; the library performs no I/O.
typedef PdfRevocationClient = Future<PdfRevocationMaterial> Function(
    List<X509Certificate> chain);

/// A signer whose private key lives somewhere this library cannot reach: a
/// remote signing service (see `cscRemoteSigner`), a hardware token, or a
/// platform keystore. Hand one to [PdfPadesSigning.saveSignedPadesRemote].
///
/// The editor lays out the signature revision, builds the CAdES signed
/// attributes, and asks [signDigest] to sign their SHA-256 digest. The value
/// that comes back is checked against [certificates]`.first` under
/// [signatureAlgorithm] before anything is written, so a signer that used the
/// wrong key or algorithm fails loudly instead of producing a broken PDF.
abstract interface class PdfRemoteSigner {
  /// The signer's DER certificate chain, leaf first. Known before signing,
  /// because the signature revision reserves room for it.
  List<Uint8List> get certificates;

  /// The DER AlgorithmIdentifier the SignerInfo names for the value
  /// [signDigest] returns: [rsaPkcs1SignatureAlgorithm],
  /// [rsaPssSignatureAlgorithm] or [ecdsaSignatureAlgorithm].
  Uint8List get signatureAlgorithm;

  /// Signs [digest] (SHA-256 of the DER signed attributes) and returns the
  /// signature value: the RSA octets, or a DER `SEQUENCE { r, s }` for ECDSA.
  /// It may take as long as the signer needs, for example while a person
  /// approves the request on their phone.
  Future<Uint8List> signDigest(Uint8List digest);
}

/// A [PdfRemoteSigner] returned a value that does not verify against its own
/// certificate. Thrown before any byte of the signed revision is returned.
class PdfRemoteSigningException implements Exception {
  const PdfRemoteSigningException(this.message);

  final String message;

  @override
  String toString() => 'PdfRemoteSigningException: $message';
}
