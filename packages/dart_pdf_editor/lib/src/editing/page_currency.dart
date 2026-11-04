/// Pending visual results of committed revisions, per page: what the editing
/// overlay keeps painting after an edit commits until the page's own raster
/// and annotation layer catch up.
///
/// "Keep painting a committed edit until the page shows it, then retire it"
/// used to be written separately for ink, the overlay's afterimage and the
/// viewer's overlay mount, each with its own retirement rule. This module
/// owns that rule:
///
/// * producers [hold] a result on a page, tagged with the revision that
///   produced it (or pending, before the commit lands - [stamp] tags it);
/// * the editing controller reports every document move ([documentAt]) and
///   which pages it changed;
/// * the viewer reports when a page is current ([pageCurrent]) or behind
///   ([pageStale]);
/// * a held result retires once its page is current at a revision that
///   shows it, or once the document moves past it - unless it is part of a
///   [run] the move extends (back-to-back ink commits).
///
/// [needsOverlay] is then the one answer to "does page N still need an
/// editing overlay mounted?".
class PdfPageCurrency {
  int _revision = 0;

  /// The revision that last changed each page's rendering, and the last
  /// all-pages change.
  final Map<int, int> _changedAt = {};
  int _allChangedAt = 0;

  /// The revision each page's on-screen raster and annotation layer show,
  /// while they are current; absent while the page is behind.
  final Map<int, int> _currentAt = {};

  final List<_Held> _held = [];

  /// Pages whose overlay stays mounted until they are current again
  /// ([keepOverlayUntilCurrent]).
  final Set<int> _mountHeld = {};

  /// The document revision currently open.
  int get revision => _revision;

  /// The revision that last changed [page]'s rendering.
  int changedAt(int page) {
    final own = _changedAt[page] ?? 0;
    return own > _allChangedAt ? own : _allChangedAt;
  }

  /// Whether [page] is reported current and already shows every change up
  /// to the open revision.
  bool isCurrent(int page) {
    final at = _currentAt[page];
    return at != null && at >= changedAt(page);
  }

  // --- controller -------------------------------------------------------

  /// The document moved to [revision]. [changedPages] are the pages whose
  /// rendering it changed (null for all of them). Held results from other
  /// revisions retire, except a [run] the move [extendsRun].
  void documentAt(int revision,
      {Iterable<int>? changedPages = const [], bool extendsRun = false}) {
    final previous = _revision;
    _revision = revision;
    if (changedPages == null) {
      _allChangedAt = revision;
    } else {
      for (final page in changedPages) {
        _changedAt[page] = revision;
      }
    }
    final newestRun = _held
        .where((h) => h.run && h.revision != null)
        .fold<int?>(
            null,
            (newest, h) =>
                newest == null || h.revision! > newest ? h.revision : newest);
    final keepRun = extendsRun && newestRun == previous;
    _retireWhere((h) =>
        h.revision != null && h.revision != revision && !(h.run && keepRun));
  }

  // --- viewer -----------------------------------------------------------

  /// [page]'s raster and annotation layer now show the document as of
  /// [revision] (the revision its page arrived at). Retires what they show.
  void pageCurrent(int page, int revision) {
    _currentAt[page] = revision;
    if (revision >= changedAt(page)) _mountHeld.remove(page);
    retireThrough(page, revision);
  }

  /// Retires [page]'s results (in [slot] only, when given) that a page
  /// showing [revision] already draws itself.
  void retireThrough(int page, int revision, {Object? slot}) =>
      _retireWhere((h) =>
          h.page == page &&
          (slot == null || h.slot == slot) &&
          h.needs != null &&
          h.needs! <= revision);

  /// [page] is behind: its raster or annotation layer is re-rendering.
  void pageStale(int page) => _currentAt.remove(page);

  /// Keeps [page]'s overlay mounted until the page is current again, even
  /// once nothing else needs it: it may still be standing in for an edit the
  /// annotation layer has not drawn yet.
  void keepOverlayUntilCurrent(int page) {
    if (!isCurrent(page)) _mountHeld.add(page);
  }

  /// Whether [page] still needs an editing overlay mounted for held results.
  bool needsOverlay(int page) =>
      _mountHeld.contains(page) || _held.any((h) => h.page == page);

  // --- producers --------------------------------------------------------

  /// Holds [value] in [page]'s [slot] until it retires, replacing what the
  /// slot held (a [run] slot accumulates instead). [revision] is the one
  /// that produced it; omit it for a preview painted ahead of its commit
  /// and [stamp] it once the commit lands. [onRetire] runs when it goes.
  ///
  /// Nothing is held when the page is already current for [revision] - the
  /// page shows the result itself.
  void hold(int page, Object slot, Object value,
      {int? revision, bool run = false, void Function()? onRetire}) {
    if (!run) release(page, slot);
    final held = _Held(page, slot, value, run: run, onRetire: onRetire);
    _held.add(held);
    if (revision != null) stamp(page, slot, revision, value: value);
  }

  /// Tags [page]'s pending [slot] result (the one [value] names, for a run
  /// slot) with the [revision] that committed it.
  void stamp(int page, Object slot, int revision, {Object? value}) {
    for (final held in _held) {
      if (held.page != page || held.slot != slot || held.revision != null) {
        continue;
      }
      if (value != null && !identical(held.value, value)) continue;
      held
        ..revision = revision
        ..needs = changedAt(page);
      if ((_currentAt[page] ?? -1) >= held.needs!) _retire(held);
      return;
    }
  }

  /// Retires whatever [page]'s [slot] holds.
  void release(int page, Object slot) =>
      _retireWhere((h) => h.page == page && h.slot == slot);

  /// What [page]'s [slot] holds, or null.
  T? heldOn<T extends Object>(int page, Object slot) {
    for (final held in _held) {
      if (held.page == page && held.slot == slot && held.value is T) {
        return held.value as T;
      }
    }
    return null;
  }

  /// Everything [page]'s [slot] holds, oldest first.
  List<T> allHeldOn<T extends Object>(int page, Object slot) => [
        for (final held in _held)
          if (held.page == page && held.slot == slot && held.value is T)
            held.value as T,
      ];

  /// Retires everything (the session is going away).
  void clear() {
    _mountHeld.clear();
    _retireWhere((_) => true);
  }

  void _retireWhere(bool Function(_Held held) test) {
    final gone = _held.where(test).toList();
    for (final held in gone) {
      _retire(held);
    }
  }

  void _retire(_Held held) {
    if (!_held.remove(held)) return;
    held.onRetire?.call();
  }
}

class _Held {
  _Held(this.page, this.slot, this.value, {required this.run, this.onRetire});

  final int page;
  final Object slot;
  final Object value;
  final bool run;
  final void Function()? onRetire;

  /// The revision that produced it; null while pending.
  int? revision;

  /// The page change the page must show before this retires.
  int? needs;
}
