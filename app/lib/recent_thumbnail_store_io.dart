import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

Future<Directory> _thumbnailDir() async {
  final base = await getApplicationSupportDirectory();
  final dir = Directory('${base.path}/recent_thumbnails');
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}

Future<Uint8List?> readStoredRecentThumbnail(String key) async {
  try {
    final file = File('${(await _thumbnailDir()).path}/$key.thumb');
    if (!await file.exists()) return null;
    return await file.readAsBytes();
  } catch (_) {
    return null;
  }
}

Future<void> writeStoredRecentThumbnail(String key, Uint8List bytes) async {
  try {
    final file = File('${(await _thumbnailDir()).path}/$key.thumb');
    await file.writeAsBytes(bytes, flush: true);
  } catch (_) {
    // A read-only/unavailable support directory only disables persistence;
    // the in-memory cache still serves the rendered thumbnail this session.
  }
}

Future<void> pruneStoredRecentThumbnails(Set<String> keep) async {
  try {
    final dir = await _thumbnailDir();
    await for (final entry in dir.list()) {
      if (entry is! File || !entry.path.endsWith('.thumb')) continue;
      final name = entry.uri.pathSegments.last;
      final key = name.substring(0, name.length - '.thumb'.length);
      if (keep.contains(key)) continue;
      try {
        await entry.delete();
      } catch (_) {
        // Best-effort cleanup: a locked or racing cache file can survive.
      }
    }
  } catch (_) {
    // No writable store - nothing to prune.
  }
}
