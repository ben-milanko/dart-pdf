/// Opt-in trust anchors for signature validation: the EU trusted lists
/// (LOTL + Member State lists, fetched and signature-verified through a
/// host transport) and a loader for an Adobe Approved Trust List file the
/// host supplies.
///
/// The core library ships no roots. This library ships the *mechanism* -
/// XML-signature verification of the lists, the pinned LOTL signers, and
/// the parsers - so a host can build a [PdfTrustStore] from the official
/// sources at run time or from a snapshot it refreshed with
/// `tool/trust_lists/refresh_trust_lists.dart`. Pure Dart, no I/O.
library;

import 'dart:typed_data';

import 'src/signature.dart';
import 'src/trust_lists/aatl.dart';
import 'src/trust_lists/eu_trusted_list.dart';

export 'src/trust_lists/aatl.dart';
export 'src/trust_lists/eu_trusted_list.dart';
export 'src/trust_lists/xml_dsig.dart'
    show XmlSignatureVerification, verifyEnvelopedXmlSignature;
export 'src/trust_lists/xml_lite.dart'
    show
        XmlC14nMethod,
        XmlLiteDocument,
        XmlLiteElement,
        canonicalizeDocument,
        canonicalizeElement;

/// Builders for trust stores from the supported public lists.
abstract final class PdfTrustLists {
  /// A store anchored at the EU qualified CA services of a snapshot PEM (as
  /// written by [PdfEuTrustListSnapshot.toPem] or the refresh tool).
  ///
  /// Throws a [FormatException] when the snapshot is expired at [now] (one
  /// of the lists it was built from is past its NextUpdate) - an expired
  /// list may still hold withdrawn anchors. Refresh it instead.
  static PdfTrustStore eutl(String snapshotPem, {DateTime? now}) {
    final snapshot = PdfEuTrustListSnapshot.fromPem(snapshotPem);
    final at = (now ?? DateTime.now()).toUtc();
    if (!snapshot.isCurrentAt(at)) {
      throw FormatException('the EU trusted list snapshot expired '
          '(${snapshot.expires?.toIso8601String() ?? 'no expiry recorded'})');
    }
    return snapshot.toTrustStore();
  }

  /// A store anchored at the trusted roots of an AATL
  /// `.acrobatsecuritysettings` file the host obtained (signature checked
  /// against Adobe Root CA G2 - see [parseAatlSecuritySettings]).
  static PdfTrustStore aatl(Uint8List securitySettings) =>
      parseAatlSecuritySettings(securitySettings).toTrustStore();

  /// Downloads Adobe's AATL through [fetch] and returns its roots - see
  /// [fetchAatl].
  static Future<PdfTrustStore> fetchAatlStore({
    required Future<Uint8List> Function(Uri url) fetch,
    DateTime? now,
  }) async =>
      (await fetchAatl(fetch: fetch, now: now)).toTrustStore();

  /// One store holding every anchor of [stores].
  static PdfTrustStore combine(Iterable<PdfTrustStore> stores) {
    final combined = PdfTrustStore();
    for (final store in stores) {
      for (final anchor in store.anchors) {
        combined.addCertificate(anchor, source: store.sourceOf(anchor));
      }
    }
    return combined;
  }
}
