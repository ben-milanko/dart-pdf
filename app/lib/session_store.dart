import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'devtools.dart';

/// One file-backed document that was open in the previous session, captured so
/// the editor can re-open it on the next launch.
@immutable
class SessionDocument {
  const SessionDocument({
    required this.title,
    required this.path,
    this.cachePath,
    this.bookmark,
  });

  /// The tab title (usually the file name) - shown while the file is read back.
  final String title;

  /// The reusable on-disk origin (desktop), or empty for a mobile pick tracked
  /// only by its [cachePath] snapshot.
  final String path;

  /// The app-private snapshot of a mobile pick's bytes (see pdf_cache.dart),
  /// so the last session restores there too even without a durable [path].
  final String? cachePath;

  /// macOS security-scoped bookmark for [path], when available.
  final String? bookmark;

  /// Where to read the document back from - the real origin when present,
  /// otherwise the private snapshot. Null when neither is usable.
  String? get readPath {
    if (path.isNotEmpty) return path;
    if (cachePath != null && cachePath!.isNotEmpty) return cachePath;
    return null;
  }

  Map<String, dynamic> toJson() => {
        't': title,
        'p': path,
        if (cachePath != null) 'c': cachePath,
        if (bookmark != null) 'b': bookmark,
      };

  factory SessionDocument.fromJson(Map<String, dynamic> j) => SessionDocument(
        title: (j['t'] as String?) ?? 'Untitled',
        path: (j['p'] as String?) ?? '',
        cachePath: j['c'] as String?,
        bookmark: j['b'] as String?,
      );
}

/// Persists the ordered list of file-backed documents currently open so the
/// editor can re-open them the next time it launches ("restore last session").
///
/// Documents are tracked by a reusable read source - the on-disk path on
/// desktop, or the app-private byte snapshot on mobile (see pdf_cache.dart).
/// Web picks have neither, so the session there is always empty and restore is
/// a no-op. Backed by `shared_preferences`; when storage is
/// unavailable (widget tests) it degrades to the in-memory list, mirroring how
/// [RecentsStore] and [PdfEditingPreferences] handle the same case.
class SessionStore {
  static const _key = 'dart_pdf_editor_app.session';

  List<SessionDocument> _documents = const [];

  /// The most recently loaded/saved set of open documents, in tab order.
  List<SessionDocument> get documents => List.unmodifiable(_documents);

  /// Reads the persisted open-document list. Returns the (possibly empty) list
  /// and also caches it in [documents].
  Future<List<SessionDocument>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return _documents;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return _documents;
      _documents = decoded
          .whereType<Map>()
          .map((m) => SessionDocument.fromJson(m.cast<String, dynamic>()))
          .where((d) => d.readPath != null)
          .toList();
    } catch (e) {
      // No storage (tests) - keep whatever is already in memory.
      AppDevTools.instance
          .addLog('session restore failed: $e', level: DevLogLevel.error);
    }
    return _documents;
  }

  /// Replaces the persisted open-document list with [documents] (tab order).
  Future<void> save(List<SessionDocument> documents) async {
    _documents = List.unmodifiable(documents);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _key, jsonEncode(_documents.map((d) => d.toJson()).toList()));
    } catch (e) {
      // No storage - nothing to persist.
      AppDevTools.instance
          .addLog('session persist failed: $e', level: DevLogLevel.error);
    }
  }
}
