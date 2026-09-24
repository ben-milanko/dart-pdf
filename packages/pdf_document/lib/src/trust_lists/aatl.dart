/// Loader for an Adobe Approved Trust List (AATL) security-settings file
/// the host supplies. dart-pdf does not ship or download the AATL itself -
/// its redistribution terms are Adobe's (see doc/signing-identities.md) -
/// but a deployment that has obtained the file can turn it into a
/// [PdfTrustStore] here.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pdf_cos/pdf_cos.dart';

import '../attachment.dart';
import '../document.dart';
import '../signature.dart';
import 'xml_lite.dart';

/// Where Adobe publishes the AATL for Acrobat, and the root its signature
/// chains to.
abstract final class PdfAatl {
  /// The `.acrobatsecuritysettings` file Acrobat downloads (a signed PDF
  /// with a `SecuritySettings.xml` attachment).
  static final url =
      Uri.parse('https://trustlist.adobe.com/tl12.acrobatsecuritysettings');

  /// SHA-256 fingerprint of Adobe Root CA G2, which the file's signature
  /// must chain to.
  static const adobeRootFingerprint =
      '458e0e219698b18d2d4093d6336a12547953a54c05dd967c3a5a268b772d1b22';

  /// The [PdfTrustStore.sourceOf] name of anchors from this list.
  static const sourceName = 'Adobe Approved Trust List';

  /// How old (from Adobe's signing time) a downloaded file may be before
  /// [fetchAatl] refuses it. The file carries no expiry of its own; Adobe
  /// re-signs and republishes it whenever membership changes, several times
  /// a year. A year bounds how long a root Adobe has since dropped could
  /// stay trusted, while never tripping over a normal publishing gap.
  static const maxAge = Duration(days: 365);
}

/// Downloads the AATL from [PdfAatl.url] through the host's [fetch] (the
/// library performs no I/O), verifies that its signature chains to Adobe
/// Root CA G2 and that it was signed within [maxAge] of [now], and returns
/// its trusted roots. Throws [FormatException] when verification fails.
///
/// This fetches Adobe's own published file on the user's device; nothing
/// about the documents being validated is sent. dart-pdf never bundles or
/// redistributes the list.
Future<PdfAatlSnapshot> fetchAatl({
  required Future<Uint8List> Function(Uri url) fetch,
  DateTime? now,
  Duration maxAge = PdfAatl.maxAge,
  String rootFingerprint = PdfAatl.adobeRootFingerprint,
}) async {
  final at = (now ?? DateTime.now()).toUtc();
  final snapshot = parseAatlSecuritySettings(await fetch(PdfAatl.url),
      maxAge: maxAge, now: at, rootFingerprint: rootFingerprint);
  return PdfAatlSnapshot(snapshot.anchors,
      signedAt: snapshot.signedAt, signer: snapshot.signer, fetchedAt: at);
}

/// The trust anchors read from an AATL file.
class PdfAatlSnapshot {
  PdfAatlSnapshot(this.anchors, {this.signedAt, this.signer, this.fetchedAt});

  /// DER certificates Acrobat would use as trusted roots.
  final List<Uint8List> anchors;

  /// When the file was signed, and by whom.
  final DateTime? signedAt;
  final String? signer;

  /// When it was downloaded (set by [fetchAatl]).
  final DateTime? fetchedAt;

  /// Whether the file was signed no more than [maxAge] before [now]. A
  /// snapshot with no signing time is never current.
  bool isCurrentAt(DateTime now, {Duration maxAge = PdfAatl.maxAge}) {
    final signed = signedAt;
    return signed != null && now.difference(signed) <= maxAge;
  }

  PdfTrustStore toTrustStore() {
    final store = PdfTrustStore();
    for (final der in anchors) {
      store.addDer(der, source: PdfAatl.sourceName);
    }
    return store;
  }

  /// A PEM bundle of [anchors] with provenance headers - what
  /// [PdfAatlSnapshot.fromPem] and `PdfTrustStore.addPem` read.
  String toPem() {
    final out = StringBuffer('# Adobe Approved Trust List anchors\n');
    if (signedAt != null) {
      out.writeln('# signed: ${signedAt!.toUtc().toIso8601String()}');
    }
    if (signer != null) out.writeln('# signer: $signer');
    if (fetchedAt != null) {
      out.writeln('# fetched-at: ${fetchedAt!.toUtc().toIso8601String()}');
    }
    for (final der in anchors) {
      out.write(pemEncode('CERTIFICATE', der));
    }
    return out.toString();
  }

  /// Reads a [toPem] bundle back.
  factory PdfAatlSnapshot.fromPem(String pem) {
    String? header(String key) =>
        RegExp('^# $key: (.+)\$', multiLine: true).firstMatch(pem)?.group(1);
    DateTime? time(String key) {
      final value = header(key);
      return value == null ? null : DateTime.tryParse(value.trim());
    }

    return PdfAatlSnapshot(
      [
        for (final m in RegExp(
                r'-----BEGIN CERTIFICATE-----[^-]+-----END CERTIFICATE-----')
            .allMatches(pem))
          pemBytes(m.group(0)!),
      ],
      signedAt: time('signed'),
      signer: header('signer')?.trim(),
      fetchedAt: time('fetched-at'),
    );
  }
}

/// Reads the trusted roots out of an AATL `.acrobatsecuritysettings` file.
///
/// Unless [verifySignature] is false, the file's PDF signature must be
/// intact, cover the whole file, and chain to Adobe Root CA G2
/// ([PdfAatl.adobeRootFingerprint]); otherwise a [FormatException] is
/// thrown. Identities are kept when the file adds them (ImportAction 1 or
/// 2, not 3 = remove) *and* marks them as trusted roots (`<Root>1</Root>`).
///
/// [rootFingerprint] overrides the pinned root (tests, or a future Adobe
/// root).
///
/// Unlike an ETSI trusted list, the AATL file carries no NextUpdate or
/// expiry field - only the date Adobe signed it. Pass [maxAge] to refuse a
/// file signed longer ago than that before [now] (Acrobat itself refreshes
/// it periodically); by default the age is not judged.
PdfAatlSnapshot parseAatlSecuritySettings(Uint8List file,
    {bool verifySignature = true,
    String rootFingerprint = PdfAatl.adobeRootFingerprint,
    Duration? maxAge,
    DateTime? now}) {
  final document = PdfDocument.open(file);
  DateTime? signedAt;
  String? signer;
  if (verifySignature) {
    final signatures = PdfSignature.of(document);
    if (signatures.isEmpty) {
      throw const FormatException('the AATL file is not signed');
    }
    final signature = signatures.last;
    final unanchored = signature.validate();
    final root = unanchored.certificates.where(
        (c) => crypto.sha256.convert(c.der).toString() == rootFingerprint);
    if (root.isEmpty) {
      throw const FormatException(
          'the AATL file is not signed under Adobe Root CA G2');
    }
    final result = signature.validate(
        trustStore: PdfTrustStore()..addCertificate(root.first));
    if (!result.intact ||
        !result.coversWholeDocument ||
        result.chainTrusted != true) {
      throw FormatException('the AATL file signature does not verify: '
          '${[...result.problems, ...result.chainProblems].join('; ')}');
    }
    signedAt = result.signedAt ?? signature.signingTime;
    signer = result.signerCertificate?.subjectCommonName;
    if (maxAge != null) {
      final at = (now ?? DateTime.now()).toUtc();
      if (signedAt == null || at.difference(signedAt) > maxAge) {
        throw FormatException('the AATL file is older than $maxAge '
            '(signed ${signedAt?.toIso8601String() ?? 'at an unknown time'})');
      }
    }
  }
  Uint8List? xml;
  for (final attachment in PdfAttachments.of(document).all) {
    if (attachment.name.toLowerCase().endsWith('securitysettings.xml')) {
      xml = attachment.bytes();
    }
  }
  if (xml == null) {
    throw const FormatException('no SecuritySettings.xml in the AATL file');
  }
  final settings = XmlLiteDocument.parse(xml);
  final anchors = <Uint8List>[];
  for (final identity in settings.root.descendantsNamed('Identity')) {
    final action = identity.child('ImportAction')?.text.trim();
    final isRoot = identity.child('Trust')?.child('Root')?.text.trim() == '1';
    final cert = identity.child('Certificate')?.text;
    if ((action != '1' && action != '2') || !isRoot || cert == null) continue;
    try {
      final der = base64.decode(cert.replaceAll(RegExp(r'\s'), ''));
      X509Certificate.parse(der);
      anchors.add(der);
    } on Object {
      // skip an unparsable identity
    }
  }
  return PdfAatlSnapshot(anchors, signedAt: signedAt, signer: signer);
}
