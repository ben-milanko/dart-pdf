import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One file-backed document that was open in the previous session, captured so
/// the editor can re-open it on the next launch.
@immutable
class SessionDocument {
  const SessionDocument({
    required this.title,
    required this.path,
    this.bookmark,
  });

  /// The tab title (usually the file name) - shown while the file is read back.
  final String title;

  /// The reusable on-disk origin. Only documents with a path are tracked, so
  /// every restored document can be read directly without a fresh pick.
  final String path;

  /// macOS security-scoped bookmark for [path], when available.
  final String? bookmark;

  Map<String, dynamic> toJson() => {
        't': title,
        'p': path,
        if (bookmark != null) 'b': bookmark,
      };

  factory SessionDocument.fromJson(Map<String, dynamic> j) => SessionDocument(
        title: (j['t'] as String?) ?? 'Untitled',
        path: (j['p'] as String?) ?? '',
        bookmark: j['b'] as String?,
      );
}

/// Persists the ordered list of file-backed documents currently open so the
/// editor can re-open them the next time it launches ("restore last session").
///
/// Only documents with a reusable on-disk path are tracked - web and mobile
/// picks have no path to read back from, so the session there is always empty
/// and restore is a no-op. Backed by `shared_preferences`; when storage is
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
          .where((d) => d.path.isNotEmpty)
          .toList();
    } catch (_) {
      // No storage (tests) - keep whatever is already in memory.
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
    } catch (_) {
      // No storage - nothing to persist.
    }
  }
}
