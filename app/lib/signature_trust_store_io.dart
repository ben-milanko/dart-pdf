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

/// The EU trusted list anchors.
///
/// - The cached snapshot is used while it is younger than
///   [euTrustListMaxAge] *and* still current - none of the lists it was
///   built from is past its NextUpdate (`PdfEuTrustListSnapshot.isCurrentAt`).
/// - Otherwise a fresh snapshot is fetched, verified and cached. The library
///   refuses an expired LOTL outright and skips an expired national list.
/// - When that refresh fails, an older cached snapshot is used only if it is
///   still current; an expired one is never brought back (returns null, so
///   signatures read as "not from a trusted authority" rather than trusting
///   anchors that may have been withdrawn).
///
/// Parsing, downloading and XML signature verification all run in a
/// background isolate. [cacheFile] and [fetchSnapshotPem] are test seams.
Future<PdfTrustStore?> loadEuTrustStore({
  DateTime? now,
  Future<File> Function()? cacheFile,
  Future<String> Function()? fetchSnapshotPem,
}) async {
  final file = await (cacheFile ?? _cacheFile)();
  final clock = (now ?? DateTime.now()).toUtc();
  PdfEuTrustListSnapshot? cached;
  try {
    if (await file.exists()) {
      final pem = await file.readAsString();
      cached = await Isolate.run(() => PdfEuTrustListSnapshot.fromPem(pem));
    }
  } on Object catch (error) {
    debugPrint('EU trusted list cache unreadable: $error');
    cached = null;
  }
  final usable =
      cached != null && cached.entries.isNotEmpty && cached.isCurrentAt(clock);
  if (usable && clock.difference(cached.fetchedAt) < euTrustListMaxAge) {
    return Isolate.run(cached.toTrustStore);
  }
  try {
    final pem = await (fetchSnapshotPem ?? _fetchSnapshotPem)();
    final fresh = await Isolate.run(() => PdfEuTrustListSnapshot.fromPem(pem));
    if (!fresh.isCurrentAt(clock) || fresh.entries.isEmpty) {
      throw StateError('the fetched EU trusted list snapshot is not current');
    }
    await file.parent.create(recursive: true);
    await file.writeAsString(pem, flush: true);
    return await Isolate.run(fresh.toTrustStore);
  } catch (error) {
    debugPrint('EU trusted list refresh failed: $error');
    if (!usable) {
      if (cached != null) {
        debugPrint('EU trusted list cache expired '
            '(${cached.expires?.toIso8601String()}); not using it');
      }
      return null;
    }
    return Isolate.run(cached.toTrustStore);
  }
}

Future<String> _fetchSnapshotPem() => Isolate.run(() async {
      final snapshot = await fetchEuTrustedLists(fetch: _get);
      return snapshot.toPem();
    });

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
