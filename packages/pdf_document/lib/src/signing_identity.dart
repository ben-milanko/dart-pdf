/// A signing identity: the private key, its certificate chain, and the
/// display name a signature carries. The [PdfSigningIdentity.generate]
/// factory is the "one-tap" path - it mints a fresh P-256 key and a
/// self-signed certificate offline, so a user who cannot bring their own
/// PKI can still sign.
///
/// Like Acrobat's built-in self-signed digital ID (and every other free
/// option), a self-signed identity reads as "signed, validity unknown" in
/// validators that only trust AATL/EUTL roots - the green check requires a
/// paid, publicly trusted CA. Pair it with a trusted timestamp
/// ([saveSignedPades] B-T with a default TSA) for CA-anchored signing time,
/// and add the certificate to a [PdfTrustStore] to have it validate cleanly
/// inside this library's own viewer.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';

class PdfSigningIdentity {
  const PdfSigningIdentity({
    required this.privateKey,
    required this.certificates,
    this.name,
  });

  /// Creates a self-signed P-256 identity offline: a random EC key and a
  /// certificate for CN=[name] (with optional [email] in a subjectAltName
  /// and [organization] in the DN). The certificate is backdated a few
  /// minutes to tolerate clock skew and is valid for [validity]
  /// (five years by default). Pure Dart - no network, no `dart:io`.
  factory PdfSigningIdentity.generate({
    required String name,
    String? email,
    String? organization,
    DateTime? notBefore,
    Duration validity = const Duration(days: 365 * 5),
    Random? random,
  }) {
    final rng = random ?? Random.secure();
    final key = EcPrivateKey.generate(EcCurve.p256, random: rng);
    final start = (notBefore ?? DateTime.now()).toUtc();
    final certificate = buildSelfSignedCertificate(
      key: key,
      commonName: name,
      email: email,
      organization: organization,
      notBefore: start.subtract(const Duration(minutes: 5)),
      notAfter: start.add(validity),
      random: rng,
    );
    return PdfSigningIdentity(
      privateKey: key,
      certificates: [certificate],
      name: name,
    );
  }

  /// Creates a self-signed **CA** identity offline - the root of an "org CA".
  /// Generate it once, share [certificate] as a trust anchor across the
  /// deployment, and mint member identities with [issue]; their signatures
  /// then chain to this CA and validate for real (not just "validity
  /// unknown"). [validity] defaults to ten years.
  factory PdfSigningIdentity.generateCa({
    required String name,
    String? organization,
    DateTime? notBefore,
    Duration validity = const Duration(days: 365 * 10),
    int? pathLength,
    Random? random,
  }) {
    final rng = random ?? Random.secure();
    final key = EcPrivateKey.generate(EcCurve.p256, random: rng);
    final start = (notBefore ?? DateTime.now()).toUtc();
    final certificate = buildCaCertificate(
      key: key,
      commonName: name,
      organization: organization,
      notBefore: start.subtract(const Duration(minutes: 5)),
      notAfter: start.add(validity),
      pathLength: pathLength,
      random: rng,
    );
    return PdfSigningIdentity(
      privateKey: key,
      certificates: [certificate],
      name: name,
    );
  }

  /// Issues a member signing identity from this CA identity (which must have
  /// been made with [PdfSigningIdentity.generateCa]). The member gets a fresh
  /// EC key and a certificate signed by this CA; its chain is
  /// `[memberCert, caCert]`, so it validates against a [PdfTrustStore] holding
  /// this CA's [certificate]. [validity] defaults to two years.
  PdfSigningIdentity issue({
    required String name,
    String? email,
    String? organization,
    DateTime? notBefore,
    Duration validity = const Duration(days: 365 * 2),
    Random? random,
  }) {
    final rng = random ?? Random.secure();
    final memberKey = EcPrivateKey.generate(EcCurve.p256, random: rng);
    final start = (notBefore ?? DateTime.now()).toUtc();
    final memberCert = issueCertificate(
      issuerKey: privateKey,
      issuerCertificate: certificate,
      subjectPublicKey: memberKey.publicKey,
      commonName: name,
      email: email,
      organization: organization,
      notBefore: start.subtract(const Duration(minutes: 5)),
      notAfter: start.add(validity),
      random: rng,
    );
    return PdfSigningIdentity(
      privateKey: memberKey,
      certificates: [memberCert, ...certificates],
      name: name,
    );
  }

  /// The EC signing key.
  final EcPrivateKey privateKey;

  /// The DER certificate chain, leaf (signer) first.
  final List<Uint8List> certificates;

  /// The signer's display name; falls back to the leaf certificate's CN
  /// when null.
  final String? name;

  /// The leaf (signer) certificate's DER - useful as a trust anchor for a
  /// [PdfTrustStore] so this identity validates in the library's viewer.
  Uint8List get certificate => certificates.first;

  /// Reloads an identity persisted with [toPem] - the `EC PRIVATE KEY`
  /// block plus one or more `CERTIFICATE` blocks (leaf first). This is how
  /// a host restores an identity from a keychain/keystore across sessions.
  factory PdfSigningIdentity.fromPem(String pem, {String? name}) {
    final keyBlock = RegExp(
            r'-----BEGIN (?:EC )?PRIVATE KEY-----[^-]+-----END (?:EC )?PRIVATE KEY-----')
        .firstMatch(pem);
    if (keyBlock == null) {
      throw ArgumentError('no PRIVATE KEY block in PEM input');
    }
    final certs = [
      for (final block in RegExp(
              r'-----BEGIN CERTIFICATE-----[^-]+-----END CERTIFICATE-----')
          .allMatches(pem))
        pemBytes(block.group(0)!),
    ];
    if (certs.isEmpty) {
      throw ArgumentError('no CERTIFICATE block in PEM input');
    }
    return PdfSigningIdentity(
      privateKey: EcPrivateKey.fromSec1(pemBytes(keyBlock.group(0)!)),
      certificates: certs,
      name: name ?? X509Certificate.parse(certs.first).subjectCommonName,
    );
  }

  /// Serializes the identity to PEM: an `EC PRIVATE KEY` block followed by
  /// the certificate chain as `CERTIFICATE` blocks. Store this in a secure
  /// keychain/keystore; [PdfSigningIdentity.fromPem] restores it.
  ///
  /// Handle the output as secret key material - it contains the private
  /// key with no passphrase protection.
  String toPem() {
    final buffer = StringBuffer()
      ..write(_pemBlock('EC PRIVATE KEY', privateKey.sec1Der));
    for (final cert in certificates) {
      buffer.write(_pemBlock('CERTIFICATE', cert));
    }
    return buffer.toString();
  }

  static String _pemBlock(String label, Uint8List der) {
    final body = base64.encode(der);
    final lines = [
      for (var i = 0; i < body.length; i += 64)
        body.substring(i, i + 64 > body.length ? body.length : i + 64),
    ];
    return '-----BEGIN $label-----\n${lines.join('\n')}\n-----END $label-----\n';
  }
}
