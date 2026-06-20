import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One entry in the "recent documents" list shown on the welcome screen.
@immutable
class RecentFile {
  const RecentFile({required this.title, this.path, required this.openedAt});

  final String title;

  /// The on-disk path, when the document was opened from a real file (desktop).
  /// Null on web/mobile, where re-opening needs a fresh pick (until Phase 2/3
  /// persists reusable origin handles).
  final String? path;

  /// Epoch milliseconds of the most recent open — drives ordering.
  final int openedAt;

  /// Stable identity: the path when present (so the same file dedupes across
  /// renames of the tab title), else the title.
  String get id => path ?? title;

  /// True when this entry can be reopened directly (we hold a usable path).
  bool get isReopenable => path != null && path!.isNotEmpty;

  Map<String, dynamic> toJson() => {
        't': title,
        if (path != null) 'p': path,
        'o': openedAt,
      };

  factory RecentFile.fromJson(Map<String, dynamic> j) => RecentFile(
        title: (j['t'] as String?) ?? 'Untitled',
        path: j['p'] as String?,
        openedAt: (j['o'] as num?)?.toInt() ?? 0,
      );
}

/// A persisted, most-recent-first list of opened documents, capped to a small
/// number. Backed by `shared_preferences`; when storage is unavailable (widget
/// tests) it degrades to an in-memory list so the UI stays deterministic with
/// no mocking, mirroring how [PdfEditingPreferences] handles the same case.
class RecentsStore extends ChangeNotifier {
  static const _key = 'dart_pdf_editor_app.recents';
  static const _cap = 20;

  final List<RecentFile> _items = [];
  bool _loaded = false;

  List<RecentFile> get items => List.unmodifiable(_items);
  bool get isEmpty => _items.isEmpty;

  /// Loads the persisted list. Safe to call more than once; a no-op after the
  /// first successful load.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      _items
        ..clear()
        ..addAll(decoded
            .whereType<Map>()
            .map((m) => RecentFile.fromJson(m.cast<String, dynamic>())));
      _sort();
      notifyListeners();
    } catch (_) {
      // No storage (tests) — keep the in-memory list.
    }
  }

  /// Records (or refreshes) a recently opened document at the front.
  Future<void> add({required String title, String? path}) async {
    final entry = RecentFile(
      title: title,
      path: path,
      openedAt: DateTime.now().millisecondsSinceEpoch,
    );
    _items.removeWhere((e) => e.id == entry.id);
    _items.insert(0, entry);
    if (_items.length > _cap) _items.removeRange(_cap, _items.length);
    notifyListeners();
    await _persist();
  }

  Future<void> remove(String id) async {
    _items.removeWhere((e) => e.id == id);
    notifyListeners();
    await _persist();
  }

  Future<void> clear() async {
    _items.clear();
    notifyListeners();
    await _persist();
  }

  void _sort() => _items.sort((a, b) => b.openedAt.compareTo(a.openedAt));

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _key, jsonEncode(_items.map((e) => e.toJson()).toList()));
    } catch (_) {
      // No storage — nothing to persist.
    }
  }
}
