import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'idb_web.dart';
import 'unsaved_changes.dart';

/// Web crash-recovery mirror, backed by IndexedDB.
///
/// The browser can take the tab away at any moment - a reload, a crash, an OOM
/// kill on mobile Safari - and unlike the desktop there is no "are you sure"
/// we can rely on. So the same guarantee has to hold with no filesystem: bytes
/// go into one object store in fixed-size chunks, metadata into another, and
/// only whole chunks past what we already stored are written.
///
/// Chunking is what makes an append an append here. IndexedDB values are
/// replaced whole, so a single-value document would rewrite the entire PDF on
/// every keystroke; splitting it means an edit rewrites the tail chunk and
/// nothing else.
UnsavedChangesStore? openUnsavedChangesStore() => _IdbUnsavedChangesStore();

const String _dbName = 'dart_pdf_editor_app.unsaved_changes';
const String _metaStore = 'meta';
const String _chunkStore = 'chunks';

/// Chunk size for mirrored bytes. Big enough that a large document is a
/// manageable number of records, small enough that the rewrite an edit forces
/// (its tail chunk) stays cheap. The arithmetic itself lives in
/// [UnsavedChunking], where it can be tested off the browser.
const _chunks = UnsavedChunking(1 << 20);

class _IdbUnsavedChangesStore implements UnsavedChangesStore {
  /// Bytes already stored per document id, so a mirror pass writes only the
  /// chunks past this. Seeded by [list] so an adopted record keeps appending.
  final Map<String, int> _flushed = {};

  @override
  Future<List<UnsavedRecord>> list() async {
    try {
      final store = await _store(_metaStore, 'readonly');
      final raw = await idbRequest<List<String>>(store.getAll(), (result) {
        if (result == null) return const [];
        return [
          for (final value in (result as JSArray<JSAny?>).toDart)
            if (value != null) (value as JSString).toDart,
        ];
      });
      final records = <UnsavedRecord>[];
      for (final text in raw) {
        final record = UnsavedRecord.decode(text);
        if (record == null) continue;
        _flushed[record.id] = record.length;
        records.add(record);
      }
      records.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
      return records;
    } catch (_) {
      // Blocked or unavailable IndexedDB (private-mode quotas, disabled
      // storage): nothing to recover, and editing is unaffected.
      return const [];
    }
  }

  @override
  Future<Uint8List?> read(UnsavedRecord record) async {
    try {
      final store = await _store(_chunkStore, 'readonly');
      final chunks = await idbRequest<List<Uint8List>>(
        store.getAll(_range(record.id)),
        (result) {
          if (result == null) return const [];
          return [
            for (final value in (result as JSArray<JSAny?>).toDart)
              if (value != null) (value as JSUint8Array).toDart,
          ];
        },
      );
      // getAll walks the key range in key order, and chunk keys are
      // zero-padded, so the pieces arrive in the order they were written.
      var total = 0;
      for (final chunk in chunks) {
        total += chunk.length;
      }
      if (total < record.length) return null;
      final bytes = Uint8List(record.length);
      var offset = 0;
      for (final chunk in chunks) {
        if (offset >= record.length) break;
        final take = chunk.length > record.length - offset
            ? record.length - offset
            : chunk.length;
        bytes.setRange(offset, offset + take, chunk);
        offset += take;
      }
      return bytes;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(UnsavedRecord record, Uint8List bytes) async {
    try {
      final firstDirty = _chunks.firstDirtyChunk(_flushed[record.id] ?? 0);
      final total = _chunks.chunkCount(bytes.length);

      final chunks = await _store(_chunkStore, 'readwrite');
      // Issue every request against this transaction before awaiting any of
      // them - awaiting first would let it auto-commit out from under the rest.
      final pending = <Future<void>>[];
      for (var index = firstDirty; index < total; index++) {
        final piece = Uint8List.sublistView(bytes, _chunks.chunkStart(index),
            _chunks.chunkEnd(index, bytes.length));
        pending.add(idbRequest<void>(
          chunks.put(piece.toJS, _chunkKey(record.id, index).toJS),
          (_) {},
        ));
      }
      // Undo can walk the revision back past a chunk boundary; drop anything
      // beyond the new end so a later read can't splice stale bytes on.
      pending.add(idbRequest<void>(
        chunks.delete(web.IDBKeyRange.bound(
            _chunkKey(record.id, total).toJS, _rangeEnd(record.id).toJS)),
        (_) {},
      ));
      await Future.wait(pending);
      _flushed[record.id] = bytes.length;

      // Commit second, in its own transaction so it cannot land before the
      // bytes it describes: until this write, recovery still reads the previous
      // whole revision.
      final meta = await _store(_metaStore, 'readwrite');
      await idbRequest<void>(
          meta.put(record.encode().toJS, record.id.toJS), (_) {});
    } catch (_) {
      // Quota exceeded, storage disabled: editing carries on, this document
      // just isn't recoverable.
    }
  }

  @override
  Future<void> delete(String id) async {
    _flushed.remove(id);
    try {
      // Metadata first: without it the chunks are already unreachable, so a
      // crash between the two can't resurrect a saved document.
      final meta = await _store(_metaStore, 'readwrite');
      await idbRequest<void>(meta.delete(id.toJS), (_) {});
      final chunks = await _store(_chunkStore, 'readwrite');
      await idbRequest<void>(chunks.delete(_range(id)), (_) {});
    } catch (_) {
      // Best-effort cleanup.
    }
  }

  @override
  Future<void> pruneExcept(Set<String> keep) async {
    try {
      final store = await _store(_metaStore, 'readonly');
      final ids = await idbRequest<List<String>>(store.getAllKeys(), (result) {
        if (result == null) return const [];
        return [
          for (final key in (result as JSArray<JSAny?>).toDart)
            (key! as JSString).toDart,
        ];
      });
      for (final id in ids) {
        if (!keep.contains(id)) await delete(id);
      }
    } catch (_) {
      // Best-effort cleanup.
    }
  }

  Future<web.IDBDatabase>? _db;

  Future<web.IDBObjectStore> _store(String name, String mode) async {
    final db = await (_db ??= openIdb(_dbName, const [_metaStore, _chunkStore]));
    return db.transaction(name.toJS, mode).objectStore(name);
  }

  /// `<id>/<index>`, zero-padded so lexicographic key order is chunk order.
  String _chunkKey(String id, int index) =>
      '$id/${index.toString().padLeft(8, '0')}';

  /// One past the last possible chunk key for [id]; `￿` sorts above every
  /// digit, so the bound covers the whole document and nothing else.
  String _rangeEnd(String id) => '$id/￿';

  web.IDBKeyRange _range(String id) =>
      web.IDBKeyRange.bound('$id/'.toJS, _rangeEnd(id).toJS);
}
