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
}

/// The trust anchors read from an AATL file.
class PdfAatlSnapshot {
  PdfAatlSnapshot(this.anchors, {this.signedAt, this.signer});

  /// DER certificates Acrobat would use as trusted roots.
  final List<Uint8List> anchors;

  /// When the file was signed, and by whom.
  final DateTime? signedAt;
  final String? signer;

  PdfTrustStore toTrustStore() => PdfTrustStore.trusting(anchors);

  /// A PEM bundle of [anchors] - what `PdfTrustStore.addPem` reads.
  String toPem() => [
        '# Adobe Approved Trust List anchors'
            '${signedAt != null ? ' (signed ${signedAt!.toIso8601String()})' : ''}\n',
        for (final der in anchors) pemEncode('CERTIFICATE', der),
      ].join();
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
PdfAatlSnapshot parseAatlSecuritySettings(Uint8List file,
    {bool verifySignature = true,
    String rootFingerprint = PdfAatl.adobeRootFingerprint}) {
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
