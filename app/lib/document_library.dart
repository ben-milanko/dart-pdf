import 'dart:async';

import 'package:flutter/foundation.dart';

import 'document_tab.dart';
import 'document_tabs.dart';
import 'pdf_cache.dart';
import 'recents.dart';
import 'session_store.dart';

/// The app's private copies of opened PDFs that have no reusable file path
/// (mobile and web picks); see pdf_cache.dart.
abstract interface class PdfSnapshotStore {
  /// Whether this platform keeps snapshots at all.
  bool get available;

  /// Stores [bytes], returning their key, or null when the write failed.
  Future<String?> store(Uint8List bytes);

  /// Deletes every snapshot not in [keep], returning the keys still present,
  /// or null when unknown.
  Future<Set<String>?> prune(Set<String> keep);
}

/// [PdfSnapshotStore] over the platform's pdf_cache backend.
class PlatformPdfSnapshots implements PdfSnapshotStore {
  const PlatformPdfSnapshots();

  @override
  bool get available => canCacheRecentPdfs;

  @override
  Future<String?> store(Uint8List bytes) => cacheOpenedPdf(bytes);

  @override
  Future<Set<String>?> prune(Set<String> keep) => pruneCachedPdfs(keep);
}

/// How a just-opened document reaches Recent files and session restore.
enum RecentRecording {
  /// Record it now: it has a reusable file origin or an existing snapshot,
  /// or the platform keeps no snapshots (the entry is then not reopenable).
  now,

  /// Snapshot its bytes first, then record the snapshot.
  afterSnapshot,
}

/// The one rule for [RecentRecording].
RecentRecording recentRecordingFor({
  required String? originPath,
  required String? cachePath,
  required bool canSnapshot,
}) =>
    originPath != null || cachePath != null || !canSnapshot
        ? RecentRecording.now
        : RecentRecording.afterSnapshot;

/// What session restore reads back for [tabs]: one entry per writable origin
/// (desktop) or private snapshot (mobile file cache, web IndexedDB), in strip
/// order. Tabs with neither - a derived or comparison tab, an error tab, or a
/// web pick whose snapshot failed - can't be read back and are skipped.
List<SessionDocument> sessionDocumentsOf(Iterable<DocumentTab> tabs) {
  final documents = <SessionDocument>[];
  final seen = <String>{};
  for (final tab in tabs) {
    final path = tab.originPath;
    final cachePath = tab.cachePath;
    final key = (path != null && path.isNotEmpty) ? path : cachePath;
    if (key == null || key.isEmpty || !seen.add(key)) continue;
    documents.add(SessionDocument(
        title: tab.title,
        path: path ?? '',
        cachePath: cachePath,
        bookmark: tab.originBookmark));
  }
  return documents;
}

/// The open documents' persistence: the session the next launch restores,
/// the Recent files they are recorded under, and the private snapshots that
/// make a path-less pick reopenable.
///
/// Every change to [tabs] persists the session (after [onTabsChanged], which
/// is where the crash-recovery mirror learns what to watch), so no transition
/// can forget to. Snapshot writes and pruning are serialized, so a prune
/// never deletes a snapshot between its write and its Recent entry.
class DocumentLibrary {
  DocumentLibrary({
    required this.tabs,
    required this.session,
    required this.recents,
    this.snapshots = const PlatformPdfSnapshots(),
    this.persistsSession = true,
    this.onTabsChanged,
  }) {
    tabs.addListener(_onTabsChanged);
  }

  final DocumentTabs tabs;
  final SessionPersistence session;
  final RecentsLog recents;
  final PdfSnapshotStore snapshots;

  /// False for a secondary window: only the application session's owner
  /// writes the restore list.
  final bool persistsSession;

  /// Runs before every persist with the current tabs.
  final void Function(List<DocumentTab> tabs)? onTabsChanged;

  /// Held until the last session has been read back, so a launch can't
  /// overwrite it with the handful of tabs open so far.
  bool sessionLoaded = false;

  Future<void> _cacheWork = Future<void>.value();
  bool _disposed = false;

  void _onTabsChanged() => unawaited(persist());

  /// Saves the restore list for the tabs open now.
  Future<void> persist() async {
    if (_disposed) return;
    onTabsChanged?.call(tabs.tabs);
    if (!persistsSession || !sessionLoaded) return;
    await session.save(sessionDocumentsOf(tabs.tabs));
  }

  /// Records [tab], just opened from [bytes], as a recent - snapshotting the
  /// bytes first when it has no reusable source ([recentRecordingFor]). The
  /// snapshot runs off the open hot path; await the result only to know when
  /// it landed.
  Future<void> recordOpened(DocumentTab tab, Uint8List bytes) {
    switch (_recordingFor(tab)) {
      case RecentRecording.now:
        return recents.add(
            title: tab.title,
            path: tab.originPath,
            cachePath: tab.cachePath,
            bookmark: tab.originBookmark);
      case RecentRecording.afterSnapshot:
        return snapshot(tab, bytes);
    }
  }

  /// Snapshots [tab]'s [bytes] when it has no reusable source yet (a mobile
  /// progressive open, a fresh scan renamed into a document), recording the
  /// recent once the snapshot lands. False, doing nothing, otherwise.
  Future<bool> snapshotIfUnbacked(DocumentTab tab, Uint8List bytes) async {
    if (_recordingFor(tab) != RecentRecording.afterSnapshot) return false;
    await snapshot(tab, bytes);
    return true;
  }

  RecentRecording _recordingFor(DocumentTab tab) => recentRecordingFor(
      originPath: tab.originPath,
      cachePath: tab.cachePath,
      canSnapshot: snapshots.available);

  /// Copies [bytes] into the private store as [tab]'s reopenable source, then
  /// records the recent and re-persists the session. A failed write still
  /// records a (non-reopenable) recent. Nothing happens once [tab] has left
  /// the strip.
  Future<void> snapshot(DocumentTab tab, Uint8List bytes) {
    return _cacheWork = _cacheWork.then((_) async {
      await _snapshotNow(tab, bytes);
      await _pruneNow();
    });
  }

  Future<void> _snapshotNow(DocumentTab tab, Uint8List bytes) async {
    if (_disposed || !tabs.contains(tab)) return;
    final key = await snapshots.store(bytes);
    if (_disposed || !tabs.contains(tab)) return;
    if (key == null) {
      await recents.add(title: tab.title, bookmark: tab.originBookmark);
      return;
    }
    tab.cachePath = key;
    await recents.add(
        title: tab.title, cachePath: key, bookmark: tab.originBookmark);
    unawaited(persist());
  }

  /// Called after every prune (thumbnail retention hangs off it).
  void Function()? onPruned;

  /// Deletes snapshots no Recent entry refers to, after any in-flight
  /// snapshot write.
  Future<void> prune() => _cacheWork = _cacheWork.then((_) => _pruneNow());

  Future<void> _pruneNow() async {
    if (_disposed) return;
    final keep = {
      for (final entry in recents.items)
        if (entry.cachePath != null) entry.cachePath!,
    };
    final available = await snapshots.prune(keep);
    if (_disposed) return;
    if (available != null) {
      await recents.updateCachedAvailability(keep, available);
    }
    onPruned?.call();
  }

  void dispose() {
    _disposed = true;
    tabs.removeListener(_onTabsChanged);
  }
}
