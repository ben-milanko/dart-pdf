import 'dart:async';
import 'dart:ui' as ui;

/// A shared, viewport-aware cache of rasterized page thumbnails — and the
/// render queue that fills it.
///
/// One of these is owned by each [PdfEditingController] (see
/// [PdfEditingController.thumbnailCache]) so every thumbnail surface of a
/// session — the docked strip, the full-area page grid — draws from the
/// *same* rasters. A page rendered for the strip is reused by the grid (and
/// vice versa), and a tile scrolled out of view and back is served from the
/// cache instead of re-rendering.
///
/// Entries hand out [ui.Image.clone]s, so an eviction never pulls pixels
/// out from under a tile still painting them, and are evicted
/// least-recently-used past [capacity].
///
/// ## The scheduler
///
/// Renders are serialized — one page interpreted at a time, so a burst of
/// fresh tiles never walks a dozen content streams at once — but *ordered*
/// by viewport proximity rather than first-come. Each pending task carries
/// the page it renders; the queue always serves the task nearest [focus]
/// next, so the pages on screen sharpen before off-screen neighbours even
/// when a hundred tiles requested at once (the page grid builds every cell
/// eagerly). Panels push [focus] as they scroll, so scrolling re-prioritizes
/// the queue toward whatever just came into view.
///
/// Tasks marked [warm] (the background fill of every page, see the panels'
/// idle prerender) rank below *every* viewport tile, so warming the whole
/// document never delays a page the user is looking at.
class PdfThumbnailCache {
  PdfThumbnailCache({this.capacity = 256});

  /// Maximum number of cached rasters (LRU eviction past it).
  final int capacity;

  // LinkedHashMap insertion order doubles as LRU order: a claim re-inserts,
  // eviction drops the first key.
  final Map<String, ui.Image> _images = {};
  bool _disposed = false;

  final List<_ThumbTask> _pending = [];
  bool _draining = false;
  int _focus = 0;

  /// The page index nearest the viewport. Pending tasks closest to it are
  /// served first; pushing a new focus (a panel scrolled) re-orders the
  /// queue toward what just came into view.
  set focus(int index) {
    if (_focus == index || _disposed) return;
    _focus = index;
    _scheduleDrain();
  }

  int get focus => _focus;

  /// Registers (or refreshes) [token]'s request to render [pageIndex].
  /// [run] is invoked when the task's turn comes — the queue grants the
  /// pending task nearest [focus], one at a time. Calling again for the same
  /// [token] (a re-layout, a resize, a viewport move) just updates it.
  ///
  /// [warm] flags a background-fill task: it ranks below every non-warm
  /// (on-screen) task regardless of page distance, so warming the document
  /// yields to anything actually visible.
  void request(Object token, int pageIndex, Future<void> Function() run,
      {bool warm = false}) {
    if (_disposed) return;
    for (final task in _pending) {
      if (identical(task.token, token)) {
        task
          ..pageIndex = pageIndex
          ..run = run
          ..warm = warm;
        _scheduleDrain();
        return;
      }
    }
    _pending.add(_ThumbTask(token, pageIndex, run, warm));
    _scheduleDrain();
  }

  /// Withdraws [token]'s pending request — its tile was disposed (scrolled
  /// out of the lazy strip), superseded, or no longer needs rendering. A
  /// cheap no-op when nothing matches or the task already started.
  void cancel(Object token) =>
      _pending.removeWhere((task) => identical(task.token, token));

  void _scheduleDrain() {
    if (_draining || _disposed || _pending.isEmpty) return;
    _draining = true;
    // off the current build/layout stack (requests fire from build) so the
    // first grant lands after this frame rather than blocking it
    scheduleMicrotask(_drain);
  }

  Future<void> _drain() async {
    try {
      while (!_disposed && _pending.isNotEmpty) {
        var pick = 0;
        var best = _rank(_pending.first);
        for (var i = 1; i < _pending.length; i++) {
          final rank = _rank(_pending[i]);
          if (rank < best) {
            best = rank;
            pick = i;
          }
        }
        final next = _pending.removeAt(pick);
        try {
          // one synchronous-ish interpret at a time; the awaits inside let
          // the engine breathe between pages
          await next.run();
        } catch (_) {
          // a page that throws mid-render must not strand the queue — it
          // simply keeps its placeholder and the next page proceeds
        }
      }
    } finally {
      _draining = false;
    }
  }

  // Lower ranks are served first: every viewport tile (warm == false) beats
  // every warm task, and within a class the page nearest [focus] wins.
  int _rank(_ThumbTask task) =>
      (task.warm ? 1 << 30 : 0) + (task.pageIndex - _focus).abs();

  /// Whether a raster for [key] is already cached.
  bool contains(String key) => _images.containsKey(key);

  /// The raster for [key] as a clone the caller owns (and must dispose), or
  /// null on a miss. Counts as a use for LRU.
  ui.Image? claim(String key) {
    final image = _images.remove(key);
    if (image == null) return null;
    _images[key] = image; // back to most-recently-used
    return image.clone();
  }

  /// Stores [image] under [key], taking ownership. Evicts the
  /// least-recently-used entries past [capacity].
  void put(String key, ui.Image image) {
    if (_disposed) {
      image.dispose(); // landed after the session went away
      return;
    }
    _images.remove(key)?.dispose();
    _images[key] = image;
    while (_images.length > capacity) {
      _images.remove(_images.keys.first)!.dispose();
    }
  }

  /// Drops every cached raster (a page-color change invalidates them all).
  /// Pending tasks are left to re-populate it.
  void clear() {
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
  }

  void dispose() {
    _disposed = true;
    _pending.clear();
    clear();
  }
}

class _ThumbTask {
  _ThumbTask(this.token, this.pageIndex, this.run, this.warm);
  final Object token;
  int pageIndex;
  Future<void> Function() run;
  bool warm;
}
