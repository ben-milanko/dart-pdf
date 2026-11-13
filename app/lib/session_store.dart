import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'devtools.dart';
import 'pdf_cache.dart';

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

/// Where the open documents are remembered for the next launch
/// (this is [SessionStore]; tests pass a fake).
abstract interface class SessionPersistence {
  Future<List<SessionDocument>> load();

  Future<void> save(List<SessionDocument> documents);
}

/// [SessionPersistence] that also remembers which window each document was
/// in, so a desktop session with several native windows comes back as
/// several windows (see window_sessions.dart).
abstract interface class WindowSessionPersistence
    implements SessionPersistence {
  /// The open documents of each window, in window order. Never contains an
  /// empty window.
  Future<List<List<SessionDocument>>> loadWindows();

  /// Replaces the persisted session with [windows] (window order, each in
  /// tab order).
  Future<void> saveWindows(List<List<SessionDocument>> windows);
}

/// The documents of every window in [windows] as one list, in window then
/// tab order, each reusable source once - what a single-window launch (or an
/// older build) restores.
List<SessionDocument> flattenSessionWindows(
    Iterable<List<SessionDocument>> windows) {
  final seen = <String>{};
  return [
    for (final window in windows)
      for (final doc in window)
        if (seen.add(doc.readPath ?? '')) doc,
  ];
}

/// Persists the ordered list of file-backed documents currently open so the
/// editor can re-open them the next time it launches ("restore last session").
///
/// Documents are tracked by a reusable read source - the on-disk path on
/// desktop, or the app-private byte snapshot on mobile (private file) and web
/// (IndexedDB), see pdf_cache.dart. A derived tab (comparison, or a pick whose
/// snapshot failed) has neither and is skipped. Backed by `shared_preferences`;
/// when storage is unavailable (widget tests) it degrades to the in-memory
/// list, mirroring how [RecentsStore] and [PdfEditingPreferences] handle the
/// same case.
class SessionStore implements WindowSessionPersistence {
  SessionStore({CachedPdfKeyResolver? resolveCacheKey})
      : _resolveCacheKey = resolveCacheKey ?? resolveCachedPdfKey;

  final CachedPdfKeyResolver _resolveCacheKey;

  /// Every open document, flattened across windows. This is the only key an
  /// older build reads, so a downgrade still restores every document (in one
  /// window), and it is how [loadWindows] notices an older build has since
  /// rewritten the session.
  static const _key = 'dart_pdf_editor_app.session';

  /// The same documents grouped by window: `{"windows": [[doc, ...], ...]}`.
  static const _windowsKey = 'dart_pdf_editor_app.session.windows';

  List<List<SessionDocument>> _windows = const [];

  /// The most recently loaded/saved set of open documents, in tab order
  /// (flattened across windows).
  List<SessionDocument> get documents =>
      List.unmodifiable(flattenSessionWindows(_windows));

  /// Reads the persisted open-document list, flattened across windows.
  /// Returns the (possibly empty) list and also caches it in [documents].
  @override
  Future<List<SessionDocument>> load() async =>
      flattenSessionWindows(await loadWindows());

  @override
  Future<List<List<SessionDocument>>> loadWindows() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final flat = _decodeDocuments(_decode(prefs.getString(_key)));
      if (flat == null) return _windows;
      var windows = [flat];
      final grouped = _decode(prefs.getString(_windowsKey));
      if (grouped is Map && grouped['windows'] is List) {
        final candidate = [
          for (final w in (grouped['windows'] as List))
            if (_decodeDocuments(w) case final docs? when docs.isNotEmpty) docs,
        ];
        // Trust the grouping only while it still describes the flat list: an
        // older build rewrites just the flat key, and its set wins.
        if (_sameDocuments(flattenSessionWindows(candidate), flat)) {
          windows = candidate;
        }
      }
      _windows = [
        for (final window in windows)
          [
            for (final doc in window) await _rebase(doc),
          ],
      ].where((w) => w.isNotEmpty).toList();
    } catch (e) {
      // No storage (tests) - keep whatever is already in memory.
      AppDevTools.instance
          .addLog('session restore failed: $e', level: DevLogLevel.error);
    }
    return _windows;
  }

  static Object? _decode(String? raw) => raw == null ? null : jsonDecode(raw);

  static List<SessionDocument>? _decodeDocuments(Object? decoded) {
    if (decoded is! List) return null;
    return [
      for (final m in decoded.whereType<Map>())
        if (SessionDocument.fromJson(m.cast<String, dynamic>()) case final doc
            when doc.readPath != null)
          doc,
    ];
  }

  static bool _sameDocuments(List<SessionDocument> a, List<SessionDocument> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].path != b[i].path || a[i].cachePath != b[i].cachePath) {
        return false;
      }
    }
    return true;
  }

  /// Points [doc]'s snapshot at the live store, which an app update can move
  /// (see `resolveCachedPdfKey`).
  Future<SessionDocument> _rebase(SessionDocument doc) async {
    final cachePath = doc.cachePath;
    if (cachePath == null) return doc;
    final live = await _resolveCacheKey(cachePath);
    if (live == null || live == cachePath) return doc;
    return SessionDocument(
        title: doc.title,
        path: doc.path,
        cachePath: live,
        bookmark: doc.bookmark);
  }

  /// Replaces the persisted open-document list with [documents] (tab order),
  /// as one window.
  @override
  Future<void> save(List<SessionDocument> documents) =>
      saveWindows([documents]);

  @override
  Future<void> saveWindows(List<List<SessionDocument>> windows) async {
    _windows = List.unmodifiable([
      for (final w in windows)
        if (w.isNotEmpty) List<SessionDocument>.unmodifiable(w),
    ]);
    List<Map<String, dynamic>> encode(List<SessionDocument> docs) =>
        [for (final d in docs) d.toJson()];
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _key, jsonEncode(encode(flattenSessionWindows(_windows))));
      await prefs.setString(
          _windowsKey,
          jsonEncode({
            'windows': [for (final w in _windows) encode(w)],
          }));
    } catch (e) {
      // No storage - nothing to persist.
      AppDevTools.instance
          .addLog('session persist failed: $e', level: DevLogLevel.error);
    }
  }
}
