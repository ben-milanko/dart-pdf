import 'dart:async';

import 'package:flutter/foundation.dart';

import 'session_store.dart';

/// The process-wide session of a multi-window desktop app: which documents
/// are open in which native window, so the next launch reopens every window
/// with its own tabs.
///
/// Each window holds one [WindowSessionSlot] (its [SessionPersistence]), in
/// the order the windows opened. A slot writes the whole session through
/// [store] whenever its window's tabs change.
///
/// What a window's closing means for the session follows the browser rule:
///
/// - closing one window while others stay open forgets it ([WindowSessionSlot.close]);
/// - closing the last window, or quitting the app, keeps everything that is
///   open, so the next launch resumes it. A window torn down by the app's own
///   exit only [WindowSessionSlot.detach]es and stays in the session.
class WindowSessions {
  WindowSessions(this.store);

  final WindowSessionPersistence store;

  final List<WindowSessionSlot> _slots = [];
  bool _loaded = false;

  /// Whether the previous session has been read back. Until then nothing is
  /// written, so a window opened early can't clobber the stored session.
  bool get loaded => _loaded;

  /// The windows the session is made of, in order (closed ones excluded).
  @visibleForTesting
  List<WindowSessionSlot> get slots => List.unmodifiable(_slots);

  /// Reads the last session back, one entry per window.
  Future<List<List<SessionDocument>>> load() => store.loadWindows();

  /// Adds a window to the session, after the windows already in it.
  /// [documents] seeds a window that is being restored, so the session keeps
  /// describing it while it reopens them.
  WindowSessionSlot open({List<SessionDocument> documents = const []}) {
    final slot = WindowSessionSlot._(this, documents);
    _slots.add(slot);
    return slot;
  }

  /// Starts persisting: the previous session has been read back (or skipped),
  /// and every window that will be restored has its slot.
  void markLoaded() {
    if (_loaded) return;
    _loaded = true;
    unawaited(_persist());
  }

  Future<void> _persist() async {
    if (!_loaded) return;
    await store.saveWindows([
      for (final slot in _slots)
        if (slot.documents.isNotEmpty) slot.documents,
    ]);
  }

  void _close(WindowSessionSlot slot) {
    // The last window open keeps its place: closing it ends the app, and the
    // next launch should come back to it.
    final others = _slots.any((s) => !identical(s, slot) && !s._detached);
    if (!others) return;
    if (_slots.remove(slot)) unawaited(_persist());
  }

  void _discard(WindowSessionSlot slot) {
    if (_slots.remove(slot)) unawaited(_persist());
  }
}

/// One native window's place in a [WindowSessions].
class WindowSessionSlot implements SessionPersistence {
  WindowSessionSlot._(this._owner, List<SessionDocument> documents)
      : _documents = List.unmodifiable(documents);

  final WindowSessions _owner;
  List<SessionDocument> _documents;
  bool _detached = false;

  /// The window's file-backed documents, in tab order.
  List<SessionDocument> get documents => _documents;

  /// Whether the window is gone without having been closed by the user.
  bool get detached => _detached;

  /// The documents this window was seeded with (a restored window).
  @override
  Future<List<SessionDocument>> load() async => _documents;

  /// Records the window's open documents and writes the whole session.
  @override
  Future<void> save(List<SessionDocument> documents) async {
    if (_detached || !_owner._slots.contains(this)) return;
    _documents = List.unmodifiable(documents);
    await _owner._persist();
  }

  /// The user closed this window. It leaves the session unless it is the
  /// last window open, which the next launch should resume.
  void close() => _owner._close(this);

  /// The window is going away without the user closing it (the app is
  /// exiting, or the platform destroyed it). Its documents stay in the
  /// session; later writes from it are ignored.
  void detach() => _detached = true;

  /// Forgets a slot whose window never opened (a restore that failed), so
  /// its documents can be reopened elsewhere.
  void discard() {
    _detached = true;
    _owner._discard(this);
  }
}
