import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:pdf_document/pdf_document.dart';

/// One entry in the app's "Open recent" list: a PDF the user opened
/// before, with the metadata the menu shows. The document's bytes live in
/// the cache store under [id]; [RecentFilesStore.bytesFor] reads them back
/// to reopen it.
@immutable
class RecentFile {
  const RecentFile({
    required this.id,
    required this.title,
    required this.size,
    required this.openedAt,
  });

  /// Stable identifier - the document's content key, which is also the
  /// cache key its bytes are stored under. Reopening the same document
  /// therefore folds into the existing entry instead of duplicating it.
  final String id;

  /// The file's display name, e.g. `report.pdf`.
  final String title;

  /// The document's size in bytes.
  final int size;

  /// When the file was last opened.
  final DateTime openedAt;

  RecentFile _openedNow() =>
      RecentFile(id: id, title: title, size: size, openedAt: DateTime.now());

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'size': size,
        'openedAt': openedAt.millisecondsSinceEpoch,
      };

  static RecentFile? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final title = value['title'];
    final size = value['size'];
    final openedAt = value['openedAt'];
    if (id is! String ||
        title is! String ||
        size is! int ||
        openedAt is! int) {
      return null;
    }
    return RecentFile(
      id: id,
      title: title,
      size: size,
      openedAt: DateTime.fromMillisecondsSinceEpoch(openedAt),
    );
  }
}

/// The example app's "Open recent" list, persisted on the same
/// [PdfCacheStore] the page caches use (a filesystem directory on native,
/// IndexedDB on the web).
///
/// Each opened document's bytes are kept under its content key so a recent
/// file reopens on every platform - including the web, where a picked file
/// has no path to re-read from. A JSON manifest records the order
/// (most-recently opened first) and the metadata the menu shows; the list
/// is trimmed to [maxEntries] and a total [maxBytes] budget, evicting the
/// oldest first (its bytes are deleted with it).
///
/// Mutations are serialized through an internal queue and every store
/// access is best-effort: a backend hiccup degrades to an empty list or a
/// miss, never an exception, so a blocked cache never breaks file opening.
class RecentFilesStore extends ChangeNotifier {
  RecentFilesStore(
    this._store, {
    this.maxEntries = 10,
    this.maxBytes = 128 * 1024 * 1024,
  }) {
    _ready = _run(() async {});
  }

  final PdfCacheStore _store;

  /// How many recent files to remember.
  final int maxEntries;

  /// Ceiling on the total bytes of remembered documents; the newest entry
  /// is always kept even if it alone exceeds the budget.
  final int maxBytes;

  static const _prefix = 'recents';
  static const _manifestKey = '$_prefix/__manifest__';
  static String _dataKey(String id) => '$_prefix/d/$id';

  // Most-recently opened first.
  List<RecentFile> _entries = const [];

  bool _loaded = false;
  Future<void> _queue = Future<void>.value();
  late final Future<void> _ready;

  /// Resolves once the persisted list has loaded (or storage proved
  /// unavailable and the list stays empty).
  Future<void> get ready => _ready;

  /// The recent files, most-recently opened first.
  List<RecentFile> get entries => _entries;

  /// Records [bytes] - a freshly opened PDF named [title] - at the front of
  /// the list, folding a re-open of the same content into one entry and
  /// evicting the oldest past the count or byte budget.
  Future<void> record(String title, Uint8List bytes) => _run(() async {
        final id = pdfContentKey(bytes);
        // Drop any existing entry for the same content; it is re-added at
        // the front below (and its bytes rewritten, in case they were lost).
        _entries = [
          for (final entry in _entries)
            if (entry.id != id) entry,
        ];
        await _safeWrite(_dataKey(id), bytes);
        _entries = [
          RecentFile(
            id: id,
            title: title,
            size: bytes.length,
            openedAt: DateTime.now(),
          ),
          ..._entries,
        ];
        await _evict();
        await _flush();
        notifyListeners();
      });

  /// The stored bytes for the recent file [id], or null when they are no
  /// longer available (an evicted or externally purged entry).
  Future<Uint8List?> bytesFor(String id) =>
      _run(() async => _safeRead(_dataKey(id)));

  /// Moves [id] to the front after it is reopened from the list. A no-op
  /// when it is absent or already newest.
  Future<void> touch(String id) => _run(() async {
        final index = _entries.indexWhere((entry) => entry.id == id);
        if (index <= 0) return;
        final entry = _entries[index];
        _entries = [
          entry._openedNow(),
          for (var i = 0; i < _entries.length; i++)
            if (i != index) _entries[i],
        ];
        await _flush();
        notifyListeners();
      });

  /// Forgets [id] and deletes its stored bytes.
  Future<void> remove(String id) => _run(() async {
        if (!_entries.any((entry) => entry.id == id)) return;
        _entries = [
          for (final entry in _entries)
            if (entry.id != id) entry,
        ];
        await _safeDelete(_dataKey(id));
        await _flush();
        notifyListeners();
      });

  /// Forgets every recent file and deletes their stored bytes.
  Future<void> clear() => _run(() async {
        if (_entries.isEmpty) return;
        for (final entry in _entries) {
          await _safeDelete(_dataKey(entry.id));
        }
        _entries = const [];
        await _safeDelete(_manifestKey);
        notifyListeners();
      });

  // --- internals -----------------------------------------------------

  /// Serializes [action] behind every earlier call, loading the manifest
  /// on the first one. A throw inside never escapes - it degrades to the
  /// empty/miss result - but the queue keeps running for the next caller.
  Future<T> _run<T>(Future<T> Function() action) {
    final result = _queue.then((_) async {
      if (!_loaded) {
        _loaded = true;
        await _load();
      }
      return action();
    });
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<void> _load() async {
    final raw = await _safeRead(_manifestKey);
    if (raw == null) return;
    try {
      final decoded = json.decode(utf8.decode(raw));
      if (decoded is! List) return;
      final loaded = [
        for (final entry in decoded)
          if (RecentFile.fromJson(entry) case final file?) file,
      ];
      if (loaded.isNotEmpty) {
        _entries = loaded;
        notifyListeners();
      }
    } catch (_) {
      // corrupt manifest - start empty
    }
  }

  Future<void> _flush() async {
    final payload =
        utf8.encode(json.encode([for (final entry in _entries) entry.toJson()]));
    await _safeWrite(_manifestKey, Uint8List.fromList(payload));
  }

  Future<void> _evict() async {
    var total = _entries.fold<int>(0, (sum, entry) => sum + entry.size);
    while (_entries.length > maxEntries) {
      total -= await _drop(_entries.last);
    }
    // Keep the newest entry even if it alone busts the budget.
    while (total > maxBytes && _entries.length > 1) {
      total -= await _drop(_entries.last);
    }
  }

  /// Removes [victim] from the list, deletes its bytes, and returns its
  /// size so the caller can keep its running total.
  Future<int> _drop(RecentFile victim) async {
    _entries = _entries.sublist(0, _entries.length - 1);
    await _safeDelete(_dataKey(victim.id));
    return victim.size;
  }

  Future<Uint8List?> _safeRead(String key) async {
    try {
      return await _store.read(key);
    } catch (_) {
      return null;
    }
  }

  Future<void> _safeWrite(String key, Uint8List bytes) async {
    try {
      await _store.write(key, bytes);
    } catch (_) {}
  }

  Future<void> _safeDelete(String key) async {
    try {
      await _store.delete(key);
    } catch (_) {}
  }
}
