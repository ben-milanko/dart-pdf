import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Metadata for one document whose unsaved edits are mirrored to durable
/// storage, so a crash (or a killed browser tab) can't lose them.
///
/// The bytes themselves live beside this record in an [UnsavedChangesStore];
/// this is everything needed to put the recovered document back in a tab that
/// behaves exactly like the one that was lost - same title, same save
/// destination, same dirty state.
@immutable
class UnsavedRecord {
  const UnsavedRecord({
    required this.id,
    required this.title,
    required this.length,
    this.originPath = '',
    this.originBookmark,
    this.cachePath,
    this.savedLength = -1,
    this.updatedAt = 0,
  });

  /// Opaque per-document key, stable for the life of the tab. Never contains
  /// `/` or a path separator - it is used verbatim as a filename (native) and
  /// as a key prefix (web).
  final String id;

  /// The tab title (usually the file name) at the time of the last mirror.
  final String title;

  /// Byte length of the mirrored revision that is **known complete** in the
  /// store.
  ///
  /// Load-bearing for crash safety: the store appends bytes first and commits
  /// this record second, so a crash in the middle of an append leaves this
  /// pointing at the previous, whole revision. Recovery reads exactly this many
  /// bytes and so never sees a torn tail.
  final int length;

  /// The document's writable on-disk origin, or empty when it has none (a
  /// brand-new document, a mobile/web pick). Save writes back here.
  final String originPath;

  /// macOS security-scoped bookmark for [originPath], when available.
  final String? originBookmark;

  /// The app-private byte snapshot backing a mobile/web pick (pdf_cache.dart),
  /// carried so a recovered tab keeps its Recent entry reopenable.
  final String? cachePath;

  /// Byte length of the last revision written to the document's real
  /// destination, or -1 for a document that has never been saved anywhere.
  ///
  /// This is `DocumentTab.savedLength` verbatim, so a recovered tab comes back
  /// dirty in exactly the way the lost one was.
  final int savedLength;

  /// Wall-clock ms of the last mirror, for diagnostics and for ordering the
  /// recovered tabs the way they were last touched.
  final int updatedAt;

  /// True when [other] describes the same document state as this record, so a
  /// mirror pass with nothing new to say can skip the write entirely.
  bool sameAs(UnsavedRecord other) =>
      id == other.id &&
      title == other.title &&
      length == other.length &&
      originPath == other.originPath &&
      originBookmark == other.originBookmark &&
      cachePath == other.cachePath &&
      savedLength == other.savedLength;

  Map<String, dynamic> toJson() => {
        'i': id,
        't': title,
        'n': length,
        if (originPath.isNotEmpty) 'p': originPath,
        if (originBookmark != null) 'b': originBookmark,
        if (cachePath != null) 'c': cachePath,
        's': savedLength,
        'u': updatedAt,
      };

  static UnsavedRecord? fromJson(Map<String, dynamic> j) {
    final id = j['i'] as String?;
    final length = (j['n'] as num?)?.toInt();
    if (id == null || id.isEmpty || length == null || length <= 0) return null;
    return UnsavedRecord(
      id: id,
      title: (j['t'] as String?) ?? 'Untitled',
      length: length,
      originPath: (j['p'] as String?) ?? '',
      originBookmark: j['b'] as String?,
      cachePath: j['c'] as String?,
      savedLength: (j['s'] as num?)?.toInt() ?? -1,
      updatedAt: (j['u'] as num?)?.toInt() ?? 0,
    );
  }

  String encode() => jsonEncode(toJson());

  /// Decodes a record written by [encode], or null when the text is not a
  /// record we can use (truncated by a crash, written by a future version).
  static UnsavedRecord? decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return fromJson(decoded.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }
}

/// A document recovered from the store: its metadata plus the bytes of the
/// revision that was in flight when the app went away.
@immutable
class RecoveredDocument {
  const RecoveredDocument({required this.record, required this.bytes});

  final UnsavedRecord record;
  final Uint8List bytes;
}

/// Durable mirror of the documents that currently have unsaved edits.
///
/// One implementation per platform ([openUnsavedChangesStore] in
/// unsaved_changes_store.dart picks it): a private directory of files on
/// native, an IndexedDB database on the web, nothing at all where neither is
/// available.
///
/// Two properties every implementation must hold, because recovery is only
/// worth having if it is trustworthy:
///
/// * **Appends, not rewrites.** Editor revisions are byte prefixes of one
///   growing buffer (see `PdfEditingController`), so a mirror pass writes only
///   the tail past what it already stored. Mirroring an edit to a 200 MB
///   document must cost the size of the edit, not the size of the document.
/// * **Torn writes are survivable.** The bytes are committed first and
///   [UnsavedRecord.length] second, so a crash mid-append is indistinguishable
///   from never having started it: recovery reads the previous whole revision.
///
/// Every method degrades quietly: a store that can't be opened (private-mode
/// quotas, a read-only home directory) makes recovery unavailable but must
/// never break editing.
abstract class UnsavedChangesStore {
  /// The records still in the store - after a clean run this is empty, since
  /// saving or closing a document drops its record. Anything here survived a
  /// crash.
  ///
  /// Records whose bytes are missing or short of [UnsavedRecord.length] are
  /// skipped: half a document is not a recovery.
  Future<List<UnsavedRecord>> list();

  /// Reads back exactly [UnsavedRecord.length] bytes for [record], or null when
  /// they are gone.
  Future<Uint8List?> read(UnsavedRecord record);

  /// Mirrors [bytes] (the full current revision) for [record], writing only
  /// what is new since the last pass and committing [record] afterwards.
  Future<void> write(UnsavedRecord record, Uint8List bytes);

  /// Drops the document [id] and its bytes - it was saved, closed, or
  /// discarded, so there is nothing left to recover.
  Future<void> delete(String id);

  /// Drops every document except [keep]; used after a recovery pass to clear
  /// records nothing adopted.
  Future<void> pruneExcept(Set<String> keep);
}

/// Chunk arithmetic for a store that mirrors bytes in fixed-size pieces.
///
/// The web backend needs it because IndexedDB replaces values whole: a
/// single-value document would rewrite the entire PDF on every keystroke, so
/// the bytes are split and only the pieces past what is already stored get
/// written. That makes this the off-by-one-prone heart of the web store - and
/// IndexedDB cannot run under `flutter test`, so the arithmetic lives here,
/// platform-free and covered, rather than inside the JS interop.
@immutable
class UnsavedChunking {
  const UnsavedChunking(this.chunkBytes);

  final int chunkBytes;

  /// How many chunks a document of [length] bytes occupies.
  int chunkCount(int length) => (length + chunkBytes - 1) ~/ chunkBytes;

  /// The first chunk a mirror pass has to write, given [flushed] bytes already
  /// stored.
  ///
  /// The chunk holding the last stored byte is partial, so it has to be
  /// rewritten; every chunk before it is full and final. An exact multiple
  /// means the previous chunk was filled, so the new bytes start a fresh one.
  int firstDirtyChunk(int flushed) =>
      flushed <= 0 ? 0 : flushed ~/ chunkBytes;

  int chunkStart(int index) => index * chunkBytes;

  /// End of chunk [index] within a document of [length] bytes (the last chunk
  /// is short).
  int chunkEnd(int index, int length) {
    final end = chunkStart(index) + chunkBytes;
    return end < length ? end : length;
  }
}

/// An [UnsavedChangesStore] with no durable backing, for tests and for the
/// in-memory half of a platform that has no store of its own.
class InMemoryUnsavedChangesStore implements UnsavedChangesStore {
  final Map<String, UnsavedRecord> _records = {};
  final Map<String, Uint8List> _bytes = {};

  /// Total bytes written across every [write] - lets a test assert that
  /// mirroring an edit costs the edit, not the document.
  int bytesWritten = 0;

  @override
  Future<List<UnsavedRecord>> list() async => _records.values.toList()
    ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));

  @override
  Future<Uint8List?> read(UnsavedRecord record) async {
    final bytes = _bytes[record.id];
    if (bytes == null || bytes.length < record.length) return null;
    return Uint8List.sublistView(bytes, 0, record.length);
  }

  @override
  Future<void> write(UnsavedRecord record, Uint8List bytes) async {
    final previous = _bytes[record.id];
    final shared = previous == null
        ? 0
        : (previous.length < bytes.length ? previous.length : bytes.length);
    bytesWritten += bytes.length - shared;
    _bytes[record.id] = Uint8List.fromList(bytes);
    _records[record.id] = record;
  }

  @override
  Future<void> delete(String id) async {
    _records.remove(id);
    _bytes.remove(id);
  }

  @override
  Future<void> pruneExcept(Set<String> keep) async {
    for (final id in _records.keys.toList()) {
      if (!keep.contains(id)) await delete(id);
    }
  }
}
