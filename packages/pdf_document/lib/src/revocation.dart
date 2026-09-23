/// Certificate revocation checking for signature validation: verifying OCSP
/// responses and CRLs against the certificate they speak for, from either
/// the document's embedded /DSS or material fetched live through an injected
/// [PdfRevocationClient]. The library performs no I/O itself;
/// [pdfOnlineRevocationClient] turns a host-supplied HTTP function into a
/// client.
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';

import 'pades.dart';
import 'signature.dart';

/// Where a revocation verdict came from.
enum PdfRevocationSource {
  /// The document's /DSS (offline LTV material embedded at signing time or
  /// added later).
  embedded,

  /// OCSP/CRL fetched at validation time through a [PdfRevocationClient].
  live,
}

/// Which mechanism produced a revocation verdict.
enum PdfRevocationMechanism { ocsp, crl }

/// Clock skew tolerated when judging OCSP/CRL freshness.
const pdfRevocationClockSkew = Duration(minutes: 5);

/// How old a live OCSP response or CRL without a nextUpdate may be before it
/// no longer counts as current.
const pdfRevocationMaxAge = Duration(days: 7);

/// The revocation verdict for one certificate of a signer's chain.
class PdfCertificateRevocation {
  const PdfCertificateRevocation({
    required this.certificate,
    required this.status,
    this.issuer,
    this.source,
    this.mechanism,
    this.revocationTime,
    this.revocationReason,
    this.thisUpdate,
    this.nextUpdate,
    this.affectsSignature = false,
    this.problems = const [],
  });

  /// The certificate the verdict is about.
  final X509Certificate certificate;

  /// The CA that issued [certificate] - the key OCSP/CRL material is checked
  /// against. Null when it could not be found.
  final X509Certificate? issuer;

  /// [PdfRevocationStatus.good]/[PdfRevocationStatus.revoked] when verified
  /// material decided it; [PdfRevocationStatus.unknown] when material existed
  /// (or a lookup was attempted) but was inconclusive, unverifiable or stale;
  /// [PdfRevocationStatus.none] when nothing covered the certificate.
  final PdfRevocationStatus status;

  /// Where the deciding material came from (null for none/unknown).
  final PdfRevocationSource? source;

  /// OCSP or CRL (null for none/unknown).
  final PdfRevocationMechanism? mechanism;

  /// When the certificate was revoked, for a revoked verdict.
  final DateTime? revocationTime;

  /// The CRLReason code, when an OCSP response gave one.
  final int? revocationReason;

  /// The validity window of the deciding response / CRL.
  final DateTime? thisUpdate;
  final DateTime? nextUpdate;

  /// True when this certificate is revoked in a way that invalidates the
  /// signature under the documented policy (see [PdfSignature.validateOnline]):
  /// the revocation is not proven to postdate a trusted signature timestamp.
  final bool affectsSignature;

  /// Why material was rejected or the lookup failed.
  final List<String> problems;

  PdfCertificateRevocation _withAffects(bool affects) =>
      PdfCertificateRevocation(
        certificate: certificate,
        issuer: issuer,
        status: status,
        source: source,
        mechanism: mechanism,
        revocationTime: revocationTime,
        revocationReason: revocationReason,
        thisUpdate: thisUpdate,
        nextUpdate: nextUpdate,
        affectsSignature: affects,
        problems: problems,
      );
}

/// Checks [certificate] (issued by [issuer]) against [ocspResponses] and
/// [crls], tagging a verdict with [source].
///
/// OCSP is consulted first, then CRLs. An OCSP response counts only if it
/// was successful, its CertID matches the certificate *and* issuer (serial,
/// issuer name hash, issuer key hash), and its signature verifies against
/// the issuer or an authorized delegated responder (issued by the issuer,
/// id-kp-OCSPSigning, valid when the response was produced). A CRL counts
/// only if its issuer name is the issuer's subject and its signature
/// verifies against the issuer's key.
///
/// With [freshAt], material must also be current at that instant: thisUpdate
/// not in the future and nextUpdate not passed (or, without a nextUpdate,
/// thisUpdate within [maxAge]) - the rule for live checks. Embedded material
/// is historical evidence and is judged without it.
PdfCertificateRevocation checkCertificateRevocation({
  required X509Certificate certificate,
  required X509Certificate? issuer,
  List<OcspResponse> ocspResponses = const [],
  List<CertificateRevocationList> crls = const [],
  required PdfRevocationSource source,
  DateTime? freshAt,
  Duration maxAge = pdfRevocationMaxAge,
}) {
  final problems = <String>[];
  String name(X509Certificate c) => c.subjectCommonName ?? 'serial ${c.serial}';
  if (issuer == null) {
    return PdfCertificateRevocation(
      certificate: certificate,
      status: ocspResponses.isEmpty && crls.isEmpty
          ? PdfRevocationStatus.none
          : PdfRevocationStatus.unknown,
      problems: [
        'issuer of "${name(certificate)}" is unavailable, so its '
            'revocation material cannot be verified'
      ],
    );
  }

  bool current(DateTime thisUpdate, DateTime? nextUpdate, String what) {
    final at = freshAt;
    if (at == null) return true;
    if (thisUpdate.isAfter(at.add(pdfRevocationClockSkew))) {
      problems.add('$what for "${name(certificate)}" is dated in the future');
      return false;
    }
    if (nextUpdate != null) {
      if (nextUpdate.isBefore(at.subtract(pdfRevocationClockSkew))) {
        problems.add('$what for "${name(certificate)}" is stale '
            '(next update ${nextUpdate.toIso8601String()})');
        return false;
      }
    } else if (at.difference(thisUpdate) > maxAge) {
      problems.add('$what for "${name(certificate)}" is older than '
          '${maxAge.inDays} days and names no next update');
      return false;
    }
    return true;
  }

  var sawMaterial = false;
  for (final response in ocspResponses) {
    if (response.responseStatus != OcspResponseStatus.successful) continue;
    final single = response.forCertificate(certificate, issuer);
    if (single == null) continue;
    sawMaterial = true;
    final responder = response.responderFor(issuer);
    if (responder == null) {
      problems.add('OCSP response for "${name(certificate)}" is signed by a '
          'responder the issuer did not authorize');
      continue;
    }
    if (!response.signatureValid(issuer)) {
      problems.add('OCSP response signature for "${name(certificate)}" does '
          'not verify');
      continue;
    }
    final producedAt = response.producedAt ?? single.thisUpdate;
    if (!identical(responder, issuer) && !responder.isValidAt(producedAt)) {
      problems.add('OCSP responder certificate for "${name(certificate)}" '
          'was not valid when the response was produced');
      continue;
    }
    if (!current(single.thisUpdate, single.nextUpdate, 'OCSP response')) {
      continue;
    }
    if (single.status == OcspCertStatus.unknown) {
      problems.add('OCSP responder does not know "${name(certificate)}"');
      continue;
    }
    final revoked = single.status == OcspCertStatus.revoked;
    return PdfCertificateRevocation(
      certificate: certificate,
      issuer: issuer,
      status: revoked ? PdfRevocationStatus.revoked : PdfRevocationStatus.good,
      source: source,
      mechanism: PdfRevocationMechanism.ocsp,
      revocationTime: revoked ? single.revocationTime : null,
      revocationReason: revoked ? single.revocationReason : null,
      thisUpdate: single.thisUpdate,
      nextUpdate: single.nextUpdate,
      problems: problems,
    );
  }

  for (final crl in crls) {
    if (!_sameBytes(crl.issuerDer, issuer.subjectDer)) continue;
    sawMaterial = true;
    if (!crl.signatureValid(issuer)) {
      problems.add('CRL signature for "${name(certificate)}" does not verify '
          'against its issuer');
      continue;
    }
    if (!current(crl.thisUpdate, crl.nextUpdate, 'CRL')) continue;
    final entry = crl.forSerial(certificate.serial);
    return PdfCertificateRevocation(
      certificate: certificate,
      issuer: issuer,
      status: entry != null
          ? PdfRevocationStatus.revoked
          : PdfRevocationStatus.good,
      source: source,
      mechanism: PdfRevocationMechanism.crl,
      revocationTime: entry?.revocationDate,
      thisUpdate: crl.thisUpdate,
      nextUpdate: crl.nextUpdate,
      problems: problems,
    );
  }

  return PdfCertificateRevocation(
    certificate: certificate,
    issuer: issuer,
    status: sawMaterial || problems.isNotEmpty
        ? PdfRevocationStatus.unknown
        : PdfRevocationStatus.none,
    problems: problems,
  );
}

/// Combines the embedded and live verdicts for one certificate: a revocation
/// from either source wins (live first), then a live "good", then an
/// embedded "good"; otherwise the more informative of the two, with both
/// sources' problems.
PdfCertificateRevocation combineRevocation(
    PdfCertificateRevocation embedded, PdfCertificateRevocation? live) {
  if (live == null) return embedded;
  if (live.status == PdfRevocationStatus.revoked) return live;
  if (embedded.status == PdfRevocationStatus.revoked) return embedded;
  if (live.status == PdfRevocationStatus.good) return live;
  if (embedded.status == PdfRevocationStatus.good) return embedded;
  final status = live.status == PdfRevocationStatus.unknown ||
          embedded.status == PdfRevocationStatus.unknown
      ? PdfRevocationStatus.unknown
      : PdfRevocationStatus.none;
  return PdfCertificateRevocation(
    certificate: live.certificate,
    issuer: live.issuer ?? embedded.issuer,
    status: status,
    problems: [...embedded.problems, ...live.problems],
  );
}

/// Applies the revocation policy to [verdicts] given the signature's
/// [trustedTime] (a verified signature timestamp; null when the signing time
/// is only claimed): a revoked certificate invalidates the signature unless
/// the timestamp proves the signature existed before the revocation time.
List<PdfCertificateRevocation> applyRevocationPolicy(
    List<PdfCertificateRevocation> verdicts, DateTime? trustedTime) {
  return [
    for (final v in verdicts)
      v._withAffects(v.status == PdfRevocationStatus.revoked &&
          !(trustedTime != null &&
              v.revocationTime != null &&
              trustedTime.isBefore(v.revocationTime!))),
  ];
}

bool _sameBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// One HTTP exchange a [pdfOnlineRevocationClient] needs: an OCSP POST
/// ([body] set, `application/ocsp-request`) or a CRL GET ([body] null).
class PdfRevocationRequest {
  const PdfRevocationRequest(this.url, {this.body, this.contentType});

  final Uri url;
  final Uint8List? body;
  final String? contentType;

  bool get isPost => body != null;
}

/// Performs [request] and returns the response body; throws on transport
/// errors or a non-2xx status. Supplied by the host (e.g. `package:http`).
typedef PdfRevocationFetch = Future<Uint8List> Function(
    PdfRevocationRequest request);

/// A [PdfRevocationClient] that queries each certificate's OCSP responder
/// (Authority Information Access) and falls back to its CRL distribution
/// points, through the host's [fetch]. The library itself still makes no
/// network calls.
///
/// For every certificate in the chain that has an issuer after it (the
/// last, self-signed root is skipped): an OCSP request with a fresh random
/// nonce is POSTed; a response that echoes a *different* nonce is dropped as
/// a replay. Responders that return a cached response without any nonce
/// are accepted - most public CAs do this - and are judged on freshness
/// (thisUpdate/nextUpdate) by the validator instead. When OCSP is missing,
/// fails, or does not say good/revoked, the first CRL that downloads is
/// used. Failures are swallowed per certificate: the validator reports the
/// certificate as "revocation unknown" rather than failing the whole check.
PdfRevocationClient pdfOnlineRevocationClient({
  required PdfRevocationFetch fetch,
  bool useNonce = true,
  Random? random,
}) {
  final rng = random ?? Random.secure();
  return (chain) async {
    final ocsps = <Uint8List>[];
    final crls = <Uint8List>[];
    for (var i = 0; i + 1 < chain.length; i++) {
      final cert = chain[i];
      final issuer = chain[i + 1];
      var decided = false;
      final ocspUrl = cert.ocspResponderUrl;
      if (ocspUrl != null && _httpUrl(ocspUrl) != null) {
        try {
          final nonce = useNonce ? _randomNonce(rng) : null;
          final body = await fetch(PdfRevocationRequest(
            _httpUrl(ocspUrl)!,
            body: buildOcspRequest(cert: cert, issuer: issuer, nonce: nonce),
            contentType: 'application/ocsp-request',
          ));
          final response = OcspResponse.parse(body);
          final replayed = nonce != null &&
              response.nonce != null &&
              !response.echoesNonce(nonce);
          if (!replayed &&
              response.responseStatus == OcspResponseStatus.successful) {
            ocsps.add(body);
            final single = response.forCertificate(cert, issuer);
            decided = single != null && single.status != OcspCertStatus.unknown;
          }
        } on Object {
          // fall through to the CRL
        }
      }
      if (decided) continue;
      for (final url in cert.crlDistributionUrls) {
        final uri = _httpUrl(url);
        if (uri == null) continue;
        try {
          final body = await fetch(PdfRevocationRequest(uri));
          CertificateRevocationList.parse(body); // reject junk early
          crls.add(body);
          break;
        } on Object {
          // try the next distribution point
        }
      }
    }
    return PdfRevocationMaterial(ocspResponses: ocsps, crls: crls);
  };
}

BigInt _randomNonce(Random rng) {
  var value = BigInt.zero;
  for (var b = 0; b < 16; b++) {
    value = (value << 8) | BigInt.from(rng.nextInt(256));
  }
  return value | BigInt.one; // never zero
}

Uri? _httpUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
    return null;
  }
  return uri;
}
