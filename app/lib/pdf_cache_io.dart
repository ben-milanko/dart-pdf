import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'pdf_cache_key.dart';

/// Whether opened PDFs should be snapshotted for later reopening on this
/// platform. Only mobile needs it: desktop keeps the picked file's real path,
/// and the web stub can't write a private file at all. Gating to Android/iOS
/// keeps desktop behavior byte-for-byte unchanged.
bool get canCacheRecentPdfs =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

Future<Directory> _cacheDir() async {
  final base = await getApplicationSupportDirectory();
  final dir = Directory('${base.path}/recent_pdfs');
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}

/// Copies [bytes] into the app's private store and returns the absolute path,
/// or null when caching isn't supported (desktop/web) or the write fails.
///
/// The filename is a content hash, so reopening or re-picking the same document
/// reuses one file instead of piling up copies - and the same bytes always map
/// to the same Recent identity.
Future<String?> cacheOpenedPdf(Uint8List bytes) async {
  if (!canCacheRecentPdfs) return null;
  try {
    final dir = await _cacheDir();
    final digest = pdfContentKey(bytes);
    final file = File('${dir.path}/$digest.pdf');
    if (!await file.exists()) {
      await file.writeAsBytes(bytes, flush: true);
    }
    return file.path;
  } catch (_) {
    return null;
  }
}

/// Native reopens a snapshot straight from its filesystem [cacheKey] (a real
/// path) via `readPdfAtPath`, so there's nothing to read back through the store
/// here. Only the web store, whose keys aren't filesystem paths, needs this.
Future<Uint8List?> readCachedPdf(String cacheKey) async => null;

/// Deletes cached copies no longer referenced by [keep] (the cache paths still
/// held by Recent entries), so the store can't grow without bound as entries
/// roll off the capped list.
Future<void> pruneCachedPdfs(Set<String> keep) async {
  if (!canCacheRecentPdfs) return;
  try {
    final dir = await _cacheDir();
    if (!await dir.exists()) return;
    await for (final entry in dir.list()) {
      if (entry is File && !keep.contains(entry.path)) {
        try {
          await entry.delete();
        } catch (_) {
          // Best-effort cleanup - a locked/racing file just survives.
        }
      }
    }
  } catch (_) {
    // No writable store - nothing to prune.
  }
}
