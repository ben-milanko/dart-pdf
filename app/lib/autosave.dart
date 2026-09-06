import 'dart:async';

import 'package:flutter/foundation.dart';

import 'devtools.dart';
import 'document_tab.dart';
import 'unsaved_changes.dart';

/// How long editing has to go quiet before unsaved changes are mirrored to the
/// store. Long enough that a burst of strokes or keystrokes lands as one write,
/// short enough that a crash costs less than a second of work.
const Duration _kAutosaveDebounce = Duration(milliseconds: 400);

/// Ceiling on how long a *continuous* edit stream can defer its mirror. Without
/// it, dragging an annotation for a minute would reset the debounce on every
/// frame and never write anything - exactly the case where a crash hurts most.
const Duration _kAutosaveMaxDefer = Duration(seconds: 5);

/// Mirrors every dirty document to durable storage so a crash, an OOM kill, or
/// a closed browser tab can't take unsaved work with it.
///
/// The editor's revisions make this cheap: each one is a byte prefix of a
/// single growing buffer, so mirroring an edit means appending the tail past
/// what the store already has. A hundred annotations on a 200 MB file cost the
/// annotations, not a hundred copies of the file.
///
/// The controller tracks a tab from the moment its first edit lands until it is
/// saved, closed, or undone back to the last-saved state - the record exists
/// exactly while there is unsaved work. So anything found in the store at
/// launch is, by construction, work a previous run lost, and [recover] hands it
/// back.
class AutosaveController {
  AutosaveController({
    UnsavedChangesStore? store,
    this.debounce = _kAutosaveDebounce,
    this.maxDefer = _kAutosaveMaxDefer,
  }) : _store = store;

  final UnsavedChangesStore? _store;
  final Duration debounce;
  final Duration maxDefer;

  final Map<DocumentTab, _TabMirror> _mirrors = {};
  int _ids = 0;

  /// Whether this platform has anywhere to mirror to. False leaves every method
  /// a no-op and the editor exactly as it was before recovery existed.
  bool get enabled => _store != null;

  /// The document ids currently mirrored (or awaiting their first write).
  @visibleForTesting
  Set<String> get trackedIds => {for (final m in _mirrors.values) m.id};

  // --- recovery ------------------------------------------------------------

  /// Everything left in the store from a previous run - documents that had
  /// unsaved edits when the app went away.
  ///
  /// A clean run leaves nothing behind, so an empty list is the normal case.
  Future<List<RecoveredDocument>> recover() async {
    final store = _store;
    if (store == null) return const [];
    final recovered = <RecoveredDocument>[];
    try {
      for (final record in await store.list()) {
        final bytes = await store.read(record);
        // A record whose bytes went missing is not a recovery, just noise.
        if (bytes == null || bytes.isEmpty) continue;
        recovered.add(RecoveredDocument(record: record, bytes: bytes));
      }
    } catch (e) {
      AppDevTools.instance.addLog('unsaved-changes recovery failed: $e',
          level: DevLogLevel.error);
    }
    if (recovered.isNotEmpty) {
      AppDevTools.instance.addLog(
          'recovered ${recovered.length} document(s) with unsaved changes');
    }
    return recovered;
  }

  /// Drops every record nothing adopted, so a document that could not be put
  /// back (unreadable bytes, a tab the user declined) doesn't come back forever.
  Future<void> pruneAfterRecovery() async {
    final store = _store;
    if (store == null) return;
    try {
      await store.pruneExcept(trackedIds);
    } catch (_) {
      // Best-effort cleanup.
    }
  }

  // --- tracking ------------------------------------------------------------

  /// Starts mirroring [tab]. Cheap and idempotent: nothing is written until the
  /// document actually has unsaved edits, so tracking every open tab costs a
  /// listener and no disk.
  void track(DocumentTab tab, {UnsavedRecord? recovered}) {
    final session = tab.session;
    if (_store == null || session == null || _mirrors.containsKey(tab)) return;
    final mirror = _TabMirror(
      id: recovered?.id ?? _newId(),
      // A recovered tab's bytes are already in the store, byte for byte - only
      // the *next* edit needs writing.
      written: recovered,
    );
    _mirrors[tab] = mirror;
    mirror.listener = () => _onChanged(tab);
    session.addListener(mirror.listener!);
    // A recovered tab arrives dirty and already mirrored; anything else that is
    // dirty on arrival (a brand-new document) needs its first write.
    if (recovered == null && tab.isDirty) _schedule(tab);
  }

  /// Stops mirroring [tab] and drops its record - the document was closed, so
  /// whatever it held is either saved or deliberately discarded.
  Future<void> untrack(DocumentTab tab) async {
    final mirror = _mirrors.remove(tab);
    if (mirror == null) return;
    _detach(tab, mirror);
    if (mirror.written != null) await _delete(mirror.id);
  }

  /// Stops mirroring every tab that is no longer in [tabs], and starts
  /// mirroring every editable one that isn't yet. The single hook the editor
  /// calls whenever its tab set changes.
  void syncTracking(Iterable<DocumentTab> tabs) {
    if (_store == null) return;
    final live = tabs.toSet();
    for (final tab in _mirrors.keys.toList()) {
      if (!live.contains(tab)) unawaited(untrack(tab));
    }
    for (final tab in live) {
      if (tab.session != null) track(tab);
    }
  }

  /// Notes that [tab] was written to its real destination: the mirror has
  /// nothing left to protect, so the record goes away.
  ///
  /// Saving does not notify the edit session (the bytes didn't change), so the
  /// editor has to say so explicitly.
  Future<void> noteSaved(DocumentTab tab) async {
    final mirror = _mirrors[tab];
    if (mirror == null) return;
    mirror.cancelTimers();
    if (mirror.written == null) return;
    mirror.written = null;
    await _delete(mirror.id);
  }

  /// Renaming changes recovery metadata without notifying the PDF controller.
  void noteMetadataChanged(DocumentTab tab) => _onChanged(tab);

  /// Writes every pending mirror now, without waiting out the debounce. Called
  /// when the app is backgrounded - on mobile and the web that may be the last
  /// moment we get.
  Future<void> flushPending() async {
    for (final tab in _mirrors.keys.toList()) {
      final mirror = _mirrors[tab];
      if (mirror == null) continue;
      mirror.cancelTimers();
      await _write(tab);
    }
  }

  /// Drops every record - the user chose to discard their unsaved changes, so
  /// there is nothing to offer back next launch.
  Future<void> discardAll() async {
    for (final tab in _mirrors.keys.toList()) {
      final mirror = _mirrors[tab];
      if (mirror == null) continue;
      mirror.cancelTimers();
      if (mirror.written == null) continue;
      mirror.written = null;
      await _delete(mirror.id);
    }
  }

  /// Detaches from every tab without touching the store, so the records survive
  /// for the next launch. This is the shutdown path: an editor going away with
  /// dirty tabs is either a crash or an exit the user has already been asked
  /// about, and both want the work kept.
  void dispose() {
    for (final entry in _mirrors.entries) {
      _detach(entry.key, entry.value);
    }
    _mirrors.clear();
  }

  // --- internals -----------------------------------------------------------

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${_ids++}';

  void _detach(DocumentTab tab, _TabMirror mirror) {
    mirror.cancelTimers();
    final listener = mirror.listener;
    if (listener != null) tab.session?.removeListener(listener);
    mirror.listener = null;
  }

  void _onChanged(DocumentTab tab) {
    final mirror = _mirrors[tab];
    if (mirror == null) return;
    if (!tab.isDirty) {
      // Undo walked back to the last-saved state: there is nothing unsaved
      // left, so the record should not outlive it.
      unawaited(noteSaved(tab));
      return;
    }
    if (_isMirrored(tab, mirror)) return;
    _schedule(tab);
  }

  /// True when the store already holds exactly what [tab] would write - the
  /// same bytes and the same metadata - so there is nothing to do.
  bool _isMirrored(DocumentTab tab, _TabMirror mirror) {
    final written = mirror.written;
    final record = _recordFor(tab, mirror);
    return record == null || (written != null && written.sameAs(record));
  }

  UnsavedRecord? _recordFor(DocumentTab tab, _TabMirror mirror) {
    final session = tab.session;
    if (session == null) return null;
    return UnsavedRecord(
      id: mirror.id,
      title: tab.title,
      length: session.bytes.length,
      originPath: tab.originPath ?? '',
      originBookmark: tab.originBookmark,
      cachePath: tab.cachePath,
      savedLength: tab.savedLength,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  void _schedule(DocumentTab tab) {
    final mirror = _mirrors[tab];
    if (mirror == null) return;
    // The debounce restarts on every change, so a burst of strokes or
    // keystrokes lands as a single write.
    mirror.debounce?.cancel();
    mirror.debounce = Timer(debounce, () => _fire(tab));
    // The ceiling does not restart. It starts with the first change of a run
    // and survives every reset, so an unbroken edit stream - dragging an
    // annotation for a minute - still reaches the store instead of deferring
    // forever. That is exactly the stretch where a crash hurts most.
    mirror.ceiling ??= Timer(maxDefer, () => _fire(tab));
  }

  void _fire(DocumentTab tab) {
    final mirror = _mirrors[tab];
    if (mirror == null) return;
    mirror.cancelTimers();
    unawaited(_write(tab));
  }

  Future<void> _write(DocumentTab tab) async {
    final store = _store;
    final mirror = _mirrors[tab];
    if (store == null || mirror == null) return;
    if (mirror.writing) {
      // A write is in flight over an older revision - let it finish and run
      // once more rather than interleave two appends to the same record.
      mirror.pending = true;
      return;
    }
    if (!tab.isDirty || _isMirrored(tab, mirror)) return;
    final record = _recordFor(tab, mirror)!;
    final bytes = tab.session!.bytes;
    mirror.writing = true;
    try {
      await store.write(record, bytes);
      mirror.written = record;
    } catch (e) {
      AppDevTools.instance.addLog('unsaved-changes mirror failed: $e',
          level: DevLogLevel.error);
    } finally {
      mirror.writing = false;
    }
    if (mirror.pending) {
      mirror.pending = false;
      // Only if the tab is still tracked and still has something newer to say.
      if (_mirrors[tab] == mirror) _onChanged(tab);
    }
  }

  Future<void> _delete(String id) async {
    try {
      await _store?.delete(id);
    } catch (e) {
      AppDevTools.instance.addLog('unsaved-changes cleanup failed: $e',
          level: DevLogLevel.error);
    }
  }
}

/// Per-tab mirroring state: which record is on disk, and what is in flight.
class _TabMirror {
  _TabMirror({required this.id, this.written});

  final String id;

  /// The record last committed to the store, or null when nothing is there.
  UnsavedRecord? written;

  VoidCallback? listener;

  /// Restarted by every change, so a burst coalesces into one write.
  Timer? debounce;

  /// Started by the first change of a run and never restarted, so a continuous
  /// edit stream still gets written every [AutosaveController.maxDefer].
  Timer? ceiling;

  void cancelTimers() {
    debounce?.cancel();
    debounce = null;
    ceiling?.cancel();
    ceiling = null;
  }

  bool writing = false;
  bool pending = false;
}
