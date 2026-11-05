import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'document_tab.dart';

/// Schedules work after the next frame: how [DocumentTabs] disposes a tab it
/// dropped only once the frame that unmounts its widgets has been drawn.
typedef AfterFrame = void Function(VoidCallback callback);

void _postFrame(VoidCallback callback) =>
    SchedulerBinding.instance.addPostFrameCallback((_) => callback());

/// The open document tabs in strip order, which one is active, and how many
/// at the head of the strip startup restore put there.
///
/// Every tab-set change is one operation here, and every one notifies: the
/// screen listens once to rebuild and persist the session (which also tells
/// the crash-recovery mirror what to watch), so no mutation can forget to. A
/// tab that leaves the set is disposed after the frame that unmounts it.
class DocumentTabs extends ChangeNotifier {
  DocumentTabs({AfterFrame? afterFrame})
      : _afterFrame = afterFrame ?? _postFrame;

  final AfterFrame _afterFrame;
  final List<DocumentTab> _tabs = [];
  int _activeIndex = 0;
  int _restoredCount = 0;

  /// The tabs in strip order.
  List<DocumentTab> get tabs => List.unmodifiable(_tabs);

  int get length => _tabs.length;
  bool get isEmpty => _tabs.isEmpty;
  bool get isNotEmpty => _tabs.isNotEmpty;
  DocumentTab operator [](int index) => _tabs[index];
  int indexOf(DocumentTab tab) => _tabs.indexOf(tab);
  bool contains(DocumentTab tab) => _tabs.contains(tab);

  /// Index of the tab on screen; meaningless while [isEmpty].
  int get activeIndex => _activeIndex;

  /// The tab on screen, or null when none is open.
  DocumentTab? get active =>
      _tabs.isEmpty ? null : _tabs[_activeIndex.clamp(0, _tabs.length - 1)];

  /// How many tabs at the head of the strip were put there by startup
  /// restore (recovered unsaved work, then the last session's documents).
  ///
  /// Restore races the OS file-open that launched the app: on macOS the file
  /// arrives on the warm `openFile` stream whenever the runner finishes
  /// building its payload, which can land before, during, or after the store
  /// read. Restored tabs therefore slot in at this index rather than at the
  /// end, so the document the user actually double-clicked stays last in the
  /// strip - and keeps focus.
  int get restoredCount => _restoredCount;

  /// Adds [tab] to the strip and makes it active.
  ///
  /// A tab added by startup restore ([restored]) is the exception on both
  /// counts: it joins the restored block at the head of the strip instead of
  /// the end, and it takes focus only while nothing else is open. A document
  /// the user asked for - the file the OS launched us with - keeps its place
  /// at the end and stays the one on screen, whichever order the two
  /// asynchronous sources happen to resolve in.
  void add(DocumentTab tab, {bool restored = false}) {
    if (!restored) {
      _tabs.add(tab);
      _activeIndex = _tabs.length - 1;
    } else {
      final at = _restoredCount.clamp(0, _tabs.length);
      // Anything at or past the restored block was opened explicitly this
      // launch; if one of those is active it stays active, just shifted along.
      final userTabActive = _tabs.isNotEmpty && _activeIndex >= at;
      _tabs.insert(at, tab);
      _restoredCount = at + 1;
      _activeIndex = userTabActive ? _activeIndex + 1 : at;
    }
    notifyListeners();
  }

  /// Inserts [tab] at [index] (clamped) and makes it active - a tab handed
  /// over from another window, dropped where the pointer let go.
  void insert(int index, DocumentTab tab) {
    final at = index.clamp(0, _tabs.length);
    _tabs.insert(at, tab);
    if (at < _restoredCount) _restoredCount++;
    _activeIndex = at;
    notifyListeners();
  }

  /// Swaps [current] for [replacement] in place - a lifecycle step such as
  /// placeholder -> document, preview -> document | error, or deferred ->
  /// document - leaving the selection alone, and disposes [current] after
  /// the frame that unmounts it. False, disposing [replacement] instead, when
  /// [current] was closed meanwhile.
  bool replace(DocumentTab current, DocumentTab replacement) {
    final index = _tabs.indexOf(current);
    if (index == -1) {
      replacement.dispose();
      return false;
    }
    _tabs[index] = replacement;
    notifyListeners();
    _afterFrame(current.dispose);
    return true;
  }

  /// Puts the tab at [index] on screen.
  void activate(int index) {
    if (index < 0 || index >= _tabs.length || index == _activeIndex) return;
    _activeIndex = index;
    notifyListeners();
  }

  /// Puts [tab] on screen; when it is a restored placeholder the user never
  /// opened, it first moves to the end, where it would have landed had the
  /// user's open beaten restore to it. Re-slotting a placeholder is
  /// invisible; a document already on its feet keeps the place the user put
  /// it in.
  void focusOpened(DocumentTab tab) {
    final index = _tabs.indexOf(tab);
    if (index == -1) return;
    final move = index < _restoredCount &&
        (tab.isDeferredPath || tab.isDeferred || tab.isLoading);
    if (move) {
      _restoredCount--;
      _tabs.add(_tabs.removeAt(index));
    }
    _activeIndex = move ? _tabs.length - 1 : index;
    notifyListeners();
  }

  /// Moves the tab at [oldIndex] to [newIndex] (already adjusted for the
  /// removed item, the `onReorderItem` convention), keeping the active
  /// document active wherever it lands.
  void reorder(int oldIndex, int newIndex) {
    final active = this.active;
    final moved = _tabs.removeAt(oldIndex);
    _tabs.insert(newIndex, moved);
    if (active != null) _activeIndex = _tabs.indexOf(active);
    notifyListeners();
  }

  /// Removes [targets] and disposes them after the frame that unmounts them.
  /// The previously active document stays active wherever it lands; if it
  /// was removed, the selection falls to a surviving neighbour.
  void remove(Iterable<DocumentTab> targets) {
    final active = this.active;
    final removed = <DocumentTab>[];
    for (final tab in targets) {
      final index = _tabs.indexOf(tab);
      if (index == -1) continue;
      // Keep the restored-block count honest: a session document whose file
      // has vanished drops its placeholder mid-restore.
      if (index < _restoredCount) _restoredCount--;
      _tabs.removeAt(index);
      removed.add(tab);
    }
    if (removed.isEmpty) return;
    final keep = active == null ? -1 : _tabs.indexOf(active);
    if (keep >= 0) {
      _activeIndex = keep;
    } else {
      if (_activeIndex >= _tabs.length) _activeIndex = _tabs.length - 1;
      if (_activeIndex < 0) _activeIndex = 0;
    }
    notifyListeners();
    _afterFrame(() {
      for (final tab in removed) {
        tab.dispose();
      }
    });
  }

  /// Disposes every tab now (the screen is going away).
  @override
  void dispose() {
    for (final tab in _tabs) {
      tab.dispose();
    }
    _tabs.clear();
    super.dispose();
  }
}
