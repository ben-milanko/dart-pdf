import 'dart:async';
import 'dart:developer' show Timeline;
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';

import '../perf_log.dart';
import '../raster_cache.dart';

/// A shared, viewport-aware cache of rasterized page thumbnails — and the
/// render queues that fill it.
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
/// ## Two queues: foreground tiles, background warm
///
/// On-screen tiles register through [request]: a serialized queue (one page
/// interpreted at a time, so a burst of fresh tiles never walks a dozen
/// content streams at once) *ordered* by viewport proximity rather than
/// first-come — the task nearest [focus] is served next, so the pages on
/// screen sharpen before off-screen neighbours even when a hundred tiles
/// requested at once (the page grid builds every cell eagerly). Panels push
/// [focus] as they scroll, re-prioritizing the queue toward whatever just
/// came into view.
///
/// The whole-document background warm ([setWarm]) is a *separate*, paced loop
/// — never the same serialized slot as the on-screen tiles. It renders one
/// off-screen page at a time, nearest [focus] first, but only while no tile
/// is queued or rendering, and yields a frame between pages. Crucially it
/// must not block a tile the user is looking at: a tile that arrives mid-warm
/// preempts the warm render at the worker (the warm pass renders at a lower
/// worker priority and declines the UI-thread fallback), so warming a heavy
/// document never adds latency to the visible page. See the panels'
/// `_warmRender`.
class PdfThumbnailCache {
  PdfThumbnailCache({this.capacity = 256});

  /// Maximum number of cached rasters (LRU eviction past it).
  final int capacity;

  /// Optional persistent backing for thumbnails, bound to the open document
  /// (see [PdfRasterCache]). The thumbnail surfaces set this each build; when
  /// present, unedited pages render straight from disk on a later open and
  /// freshly-rendered ones write through. Null leaves the cache session-only.
  PdfRasterCache? disk;

  // LinkedHashMap insertion order doubles as LRU order: a claim re-inserts,
  // eviction drops the first key.
  final Map<String, ui.Image> _images = {};
  bool _disposed = false;

  final List<_ThumbTask> _pending = [];
  bool _draining = false;
  int _focus = 0;

  /// The page index nearest the viewport. Foreground tasks (and the warm
  /// loop) closest to it are served first; pushing a new focus (a panel
  /// scrolled) re-orders the work toward what just came into view.
  set focus(int index) {
    if (_focus == index || _disposed) return;
    _focus = index;
    _scheduleDrain();
    _kickWarm(); // a moved viewport may re-aim the warm pass too
  }

  int get focus => _focus;

  /// Whether any on-screen tile is queued or rendering — the warm loop holds
  /// off while this is true so the visible pages always win the worker.
  bool get _foregroundBusy => _draining || _pending.isNotEmpty;

  /// Registers (or refreshes) [token]'s request to render on-screen tile
  /// [pageIndex]. [run] is invoked when the task's turn comes — the queue
  /// grants the pending task nearest [focus], one at a time. Calling again
  /// for the same [token] (a re-layout, a resize, a viewport move) just
  /// updates it.
  void request(Object token, int pageIndex, Future<void> Function() run) {
    if (_disposed) return;
    for (final task in _pending) {
      if (identical(task.token, token)) {
        task
          ..pageIndex = pageIndex
          ..run = run;
        _scheduleDrain();
        return;
      }
    }
    _pending.add(_ThumbTask(token, pageIndex, run));
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
        Timeline.instantSync('thumbnail grant', arguments: {
          'page': next.pageIndex,
          'focus': _focus,
          'pending': _pending.length,
        });
        PdfPerfLog.log('thumbnail grant page=${next.pageIndex} '
            'focus=$_focus pending=${_pending.length}');
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
      // a tile that just finished may have been the last thing holding the
      // warm pass back
      _kickWarm();
    }
  }

  // The on-screen tile nearest [focus] is served first.
  int _rank(_ThumbTask task) => (task.pageIndex - _focus).abs();

  // --- background whole-document warm -------------------------------------

  int _warmCount = 0;
  String? _warmSignature;
  Object? _warmOwner;
  Future<void> Function(int page)? _warmRenderer;
  final Set<int> _warmAttempted = {};
  bool _warming = false;

  /// Arms (or refreshes) the background warm of every page into the cache for
  /// [owner], rendering through [renderPage]. Cheap to call from every build:
  /// it only resets the pass when [signature] or [pageCount] changed (the
  /// render resolution, paper color, or page count moved), so a plain rebuild
  /// doesn't re-warm pages already done. [renderPage] should skip a page
  /// whose raster is already cached, render at a *lower* worker priority than
  /// on-screen tiles, and decline the UI-thread fallback so a visible tile
  /// always preempts it.
  void setWarm(Object owner, int pageCount, String signature,
      Future<void> Function(int page) renderPage) {
    if (_disposed) return;
    _warmOwner = owner;
    _warmRenderer = renderPage;
    if (signature == _warmSignature && pageCount == _warmCount) {
      _kickWarm(); // same pass; just make sure the loop is running
      return;
    }
    _warmSignature = signature;
    _warmCount = pageCount;
    _warmAttempted.clear();
    PdfPerfLog.log('thumbnail warm armed pages=$pageCount key=$signature');
    _kickWarm();
  }

  /// Stops [owner]'s background warm (its panel was disposed, or the session
  /// swapped). A no-op if another owner has since taken over.
  void clearWarm(Object owner) {
    if (!identical(_warmOwner, owner)) return;
    _warmOwner = null;
    _warmRenderer = null;
    _warmSignature = null;
    _warmCount = 0;
    _warmAttempted.clear();
  }

  void _kickWarm() {
    if (_warming || _disposed || _warmRenderer == null) return;
    _warming = true;
    scheduleMicrotask(_warmLoop);
  }

  Future<void> _warmLoop() async {
    try {
      while (!_disposed && _warmRenderer != null) {
        // never compete with the page the user is looking at — step aside and
        // let the foreground drain re-kick us when it's done (its `finally`
        // calls _kickWarm), rather than busy-waiting on frames
        if (_foregroundBusy) {
          PdfPerfLog.log('thumbnail warm yields — foreground busy '
              '(pending=${_pending.length} draining=$_draining)');
          return;
        }
        final page = _nextWarmPage();
        if (page == null) return; // every page attempted this pass
        _warmAttempted.add(page);
        final renderer = _warmRenderer;
        if (renderer == null) return;
        Timeline.instantSync('thumbnail warm', arguments: {'page': page});
        PdfPerfLog.log('thumbnail warm page=$page focus=$_focus '
            '(${_warmAttempted.length}/$_warmCount)');
        try {
          await renderer(page);
        } catch (_) {
          // a page that fails to warm simply isn't cached; the pass goes on
        }
        // breathe between heavy pages so input and animations run, and a tile
        // that arrived meanwhile is picked up before the next warm page
        await SchedulerBinding.instance.endOfFrame;
      }
    } finally {
      _warming = false;
    }
  }

  /// The not-yet-attempted warm page nearest [focus] — warming radiates out
  /// from wherever the viewport is.
  int? _nextWarmPage() {
    int? best;
    var bestDistance = 1 << 30;
    for (var i = 0; i < _warmCount; i++) {
      if (_warmAttempted.contains(i)) continue;
      final distance = (i - _focus).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        best = i;
      }
    }
    return best;
  }

  // --- raster store -------------------------------------------------------

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
    _warmRenderer = null;
    clear();
  }
}

class _ThumbTask {
  _ThumbTask(this.token, this.pageIndex, this.run);
  final Object token;
  int pageIndex;
  Future<void> Function() run;
}
