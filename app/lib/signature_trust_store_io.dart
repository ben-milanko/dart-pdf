import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_document/trust_lists.dart';

/// How long a fetched EU trusted list snapshot is used before it is
/// refreshed. Member States reissue their lists when a service changes, not
/// on a schedule, so a week keeps new and withdrawn CAs current without
/// re-downloading ~25 MB of lists on every launch.
const euTrustListMaxAge = Duration(days: 7);

/// Live trust needs the network; `flutter test` runs must never reach it.
bool get networkTrustAvailable =>
    !Platform.environment.containsKey('FLUTTER_TEST');

Future<File> _cacheFile() async {
  final base = await getApplicationSupportDirectory();
  return File('${base.path}/signature_trust/eutl.pem');
}

/// The EU trusted list anchors: the cached snapshot while it is younger than
/// [euTrustListMaxAge], otherwise a fresh fetch (verified and cached), and
/// the stale cache when a refresh fails. Parsing, downloading and XML
/// signature verification all run in a background isolate.
Future<PdfTrustStore?> loadEuTrustStore({
  DateTime? now,
  Future<File> Function()? cacheFile,
}) async {
  final file = await (cacheFile ?? _cacheFile)();
  final clock = (now ?? DateTime.now()).toUtc();
  String? cached;
  try {
    if (await file.exists()) cached = await file.readAsString();
  } on FileSystemException {
    cached = null;
  }
  if (cached != null) {
    final pem = cached;
    final snapshot =
        await Isolate.run(() => PdfEuTrustListSnapshot.fromPem(pem));
    if (clock.difference(snapshot.fetchedAt) < euTrustListMaxAge &&
        snapshot.entries.isNotEmpty) {
      return Isolate.run(snapshot.toTrustStore);
    }
  }
  try {
    final pem = await Isolate.run(() async {
      final snapshot = await fetchEuTrustedLists(fetch: _get);
      return snapshot.toPem();
    });
    await file.parent.create(recursive: true);
    await file.writeAsString(pem, flush: true);
    return await Isolate.run(
        () => PdfEuTrustListSnapshot.fromPem(pem).toTrustStore());
  } catch (error) {
    debugPrint('EU trusted list refresh failed: $error');
    if (cached == null) return null;
    final pem = cached;
    return Isolate.run(
        () => PdfEuTrustListSnapshot.fromPem(pem).toTrustStore());
  }
}

Future<Uint8List> _get(Uri url) async {
  final response = await http.get(url, headers: const {
    // some national list hosts reset connections from the default Dart agent
    'User-Agent': 'DartPDF',
  }).timeout(const Duration(seconds: 60));
  if (response.statusCode != 200) {
    throw http.ClientException('HTTP ${response.statusCode}', url);
  }
  return response.bodyBytes;
}
