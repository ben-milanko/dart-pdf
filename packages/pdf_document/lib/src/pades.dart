/// PAdES (ETSI EN 319 142) baseline profiles and the pluggable network
/// seams a PAdES signature needs. The library never touches the network
/// itself (no `dart:io` in `lib/`): the caller supplies the TSA and
/// revocation transports, mirroring how OCR engines are injected.
library;

import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';

/// The PAdES baseline levels, in increasing order of long-term assurance.
enum PdfPadesLevel {
  /// B-B: basic — correct signed attributes incl. signing-certificate-v2.
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

/// Obtains an RFC 3161 timestamp token for [timeStampRequest] — the DER
/// `TimeStampReq` built by [buildTimeStampRequest]. Implementations POST the
/// request to their TSA and return the bare `TimeStampToken` (the inner
/// ContentInfo, e.g. via [timeStampTokenFromResponse]). Injected by the
/// caller so the library stays transport-free.
typedef PdfTimestampClient = Future<Uint8List> Function(
    Uint8List timeStampRequest);

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
