// Refreshes signature trust anchors from their official sources into PEM
// snapshots a host can ship or cache (they are never committed to this
// repository - see doc/signing-identities.md for why and for the cadence).
//
//   dart run tool/refresh_trust_lists.dart --eutl eutl.pem
//   dart run tool/refresh_trust_lists.dart --aatl aatl.pem
//
// --eutl  downloads the EU List of Trusted Lists, verifies its XML signature
//         against the pinned LOTL signers (PdfEuLotl.signerFingerprints),
//         then downloads and verifies every Member State list against the
//         certificates the LOTL names for it, and writes the active
//         qualified CA services. A list that fails is reported and skipped.
// --aatl  downloads Adobe's AATL security-settings file, verifies its PDF
//         signature chains to Adobe Root CA G2, and writes its trusted
//         roots. Only for deployments whose own terms with Adobe allow it.
//
// Optional: --lotl-signer <sha256-hex> (repeatable) replaces the pinned LOTL
// signers, for when the Commission rotates them before this file is updated.
// Exits non-zero when a requested list could not be verified at all.
import 'dart:io';
import 'dart:typed_data';

import 'package:pdf_document/trust_lists.dart';

Future<Uint8List> _get(Uri url) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 30)
    // some national list hosts reset connections from the default Dart UA
    ..userAgent = 'dart-pdf-trust-list-refresh';
  try {
    final request = await client.getUrl(url);
    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}', uri: url);
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response) {
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  } finally {
    client.close();
  }
}

Future<void> main(List<String> args) async {
  String? eutlOut;
  String? aatlOut;
  final signers = <String>{};
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--eutl':
        eutlOut = args[++i];
      case '--aatl':
        aatlOut = args[++i];
      case '--lotl-signer':
        signers.add(args[++i].toLowerCase());
      default:
        stderr.writeln('unknown argument ${args[i]}');
        exit(64);
    }
  }
  if (eutlOut == null && aatlOut == null) {
    stderr.writeln('usage: refresh_trust_lists.dart [--eutl out.pem] '
        '[--aatl out.pem] [--lotl-signer sha256]...');
    exit(64);
  }
  var failed = false;

  if (eutlOut != null) {
    try {
      final snapshot = await fetchEuTrustedLists(
        fetch: _get,
        pinnedSigners: signers.isEmpty ? PdfEuLotl.signerFingerprints : signers,
      );
      File(eutlOut).writeAsStringSync(snapshot.toPem());
      final territories = {for (final e in snapshot.entries) e.territory};
      stdout.writeln('EUTL: LOTL #${snapshot.lotlSequenceNumber}, '
          '${snapshot.entries.length} qualified CA certificates from '
          '${territories.length} lists, valid until '
          '${snapshot.expires?.toIso8601String()} -> $eutlOut');
      snapshot.problems.forEach((territory, problem) {
        stdout.writeln('  skipped $territory: $problem');
      });
    } on Object catch (e) {
      stderr.writeln('EUTL: $e');
      failed = true;
    }
  }

  if (aatlOut != null) {
    try {
      final snapshot = parseAatlSecuritySettings(await _get(PdfAatl.url));
      File(aatlOut).writeAsStringSync(snapshot.toPem());
      stdout.writeln('AATL: ${snapshot.anchors.length} trusted roots, signed '
          '${snapshot.signedAt?.toIso8601String()} by ${snapshot.signer} '
          '-> $aatlOut');
    } on Object catch (e) {
      stderr.writeln('AATL: $e');
      failed = true;
    }
  }
  if (failed) exit(1);
}
