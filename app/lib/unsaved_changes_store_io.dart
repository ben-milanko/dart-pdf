import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'unsaved_changes.dart';

/// Native crash-recovery mirror: one `<id>.pdf` of bytes plus one `<id>.json`
/// of metadata per document, under the app's private support directory.
UnsavedChangesStore? openUnsavedChangesStore() => _FileUnsavedChangesStore();

class _FileUnsavedChangesStore implements UnsavedChangesStore {
  /// Bytes already on disk per document id, so a mirror pass writes only the
  /// tail past this. Seeded by [list] for records that survived a crash, so an
  /// adopted document keeps appending instead of rewriting itself once.
  final Map<String, int> _flushed = {};

  Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/unsaved_changes');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  File _data(Directory dir, String id) => File('${dir.path}/$id.pdf');
  File _meta(Directory dir, String id) => File('${dir.path}/$id.json');

  @override
  Future<List<UnsavedRecord>> list() async {
    try {
      final dir = await _dir();
      if (!await dir.exists()) return const [];
      final records = <UnsavedRecord>[];
      await for (final entry in dir.list()) {
        if (entry is! File || !entry.path.endsWith('.json')) continue;
        final record = UnsavedRecord.decode(await entry.readAsString());
        if (record == null) continue;
        // A record is only worth offering if its bytes are all there. They can
        // be longer (a crash between the append and the commit left a tail we
        // deliberately ignore), never shorter.
        final data = _data(dir, record.id);
        if (!await data.exists()) continue;
        if (await data.length() < record.length) continue;
        _flushed[record.id] = record.length;
        records.add(record);
      }
      records.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
      return records;
    } catch (_) {
      // No readable store (no support directory, no platform channel under
      // flutter_test): nothing to recover.
      return const [];
    }
  }

  @override
  Future<Uint8List?> read(UnsavedRecord record) async {
    try {
      final data = _data(await _dir(), record.id);
      final bytes = await data.readAsBytes();
      if (bytes.length < record.length) return null;
      // Trailing bytes past the committed length are a half-written revision -
      // drop them and hand back the last whole one.
      return Uint8List.sublistView(bytes, 0, record.length);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(UnsavedRecord record, Uint8List bytes) async {
    try {
      final dir = await _dir();
      final data = _data(dir, record.id);
      final flushed = _flushed[record.id];
      // Only append what the file doesn't already have, and only when the file
      // really is the prefix we think it is - an unexpected length means we
      // lost track of it, so fall back to a full rewrite.
      final appendable = flushed != null &&
          flushed <= bytes.length &&
          await data.exists() &&
          await data.length() == flushed;
      if (appendable) {
        if (flushed < bytes.length) {
          final handle = await data.open(mode: FileMode.append);
          try {
            await handle.writeFrom(bytes, flushed, bytes.length);
            await handle.flush();
          } finally {
            await handle.close();
          }
        }
      } else if (flushed != null && flushed > bytes.length) {
        // Undo walked the revision back: the buffer past here is stale, so cut
        // it off rather than leave bytes we would never read.
        final handle = await data.open(mode: FileMode.append);
        try {
          await handle.truncate(bytes.length);
          await handle.flush();
        } finally {
          await handle.close();
        }
      } else {
        await data.writeAsBytes(bytes, flush: true);
      }
      _flushed[record.id] = bytes.length;
      // Commit second: until this lands, recovery still reads the previous
      // revision, so a crash anywhere above costs the last edit and nothing
      // more. Via a temp file so the commit itself can't be seen half-written.
      final meta = _meta(dir, record.id);
      final temp = File('${meta.path}.tmp');
      await temp.writeAsString(record.encode(), flush: true);
      try {
        await temp.rename(meta.path);
      } catch (_) {
        await meta.writeAsString(record.encode(), flush: true);
        if (await temp.exists()) await temp.delete();
      }
    } catch (_) {
      // A store we can't write to (full disk, sandbox denial) must not break
      // editing; the document simply isn't recoverable.
    }
  }

  @override
  Future<void> delete(String id) async {
    _flushed.remove(id);
    try {
      final dir = await _dir();
      // Metadata first: without it the bytes are already unrecoverable, so a
      // crash between the two deletes can't resurrect a saved document.
      for (final file in [_meta(dir, id), _data(dir, id)]) {
        if (await file.exists()) await file.delete();
      }
    } catch (_) {
      // Best-effort cleanup.
    }
  }

  @override
  Future<void> pruneExcept(Set<String> keep) async {
    try {
      final dir = await _dir();
      if (!await dir.exists()) return;
      final ids = <String>{};
      await for (final entry in dir.list()) {
        if (entry is! File) continue;
        final name = entry.uri.pathSegments.last;
        // A `.tmp` is a commit interrupted by a crash - the record it would
        // have become never existed, so just sweep it.
        if (name.endsWith('.tmp')) {
          try {
            await entry.delete();
          } catch (_) {
            // Best-effort cleanup.
          }
          continue;
        }
        final dot = name.lastIndexOf('.');
        if (dot <= 0) continue;
        ids.add(name.substring(0, dot));
      }
      for (final id in ids) {
        if (!keep.contains(id)) await delete(id);
      }
    } catch (_) {
      // Best-effort cleanup.
    }
  }
}
