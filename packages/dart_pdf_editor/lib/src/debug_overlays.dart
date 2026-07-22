/// Viewer debug-overlay flags and registries, driven by a host app's
/// developer tools. All default off and cost nothing until flipped; they are
/// [ValueNotifier]s so overlay painters can repaint on toggle without the
/// host rebuilding the page tree.
library;

import 'dart:async';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';

/// Paints diagnostic borders on the deep-zoom detail surfaces: every tile
/// placement in a [PdfTileLayer] (green for exact-bucket tiles, orange for
/// upscaled coarser fallbacks) and the legacy single detail patch (purple).
/// Shows what sharpens the visible slice, and from which source.
final ValueNotifier<bool> pdfDebugPaintDetailBounds = ValueNotifier(false);

/// Outlines, in the thumbnail strip/grid, the pages that currently hold a
/// live page-view state ([PdfLivePageRegistry]) - the lazy-list "render
/// window" whose retained scenes and rasters dominate per-page memory.
final ValueNotifier<bool> pdfDebugShowRenderWindow = ValueNotifier(false);

/// Sink for the viewer's touch/gesture diagnostics. Null (the default) means
/// the viewer emits nothing and pays only a single null-check at each gesture
/// decision point. A host's developer tools sets it to capture which pan/zoom
/// path a touch actually took - the signal for "panning does nothing while
/// zoomed" reports that never reproduce off-device. Set back to null to stop.
///
/// Only discrete gesture *decisions* flow through here (a recognizer claims a
/// drag, the enable gate's verdict on pointer-down, an interaction start/end),
/// never per-move updates, so the log stays readable. Raw per-pointer streams
/// are the host's job (a passive `Listener`).
void Function(String message)? pdfDebugGestureLog;

/// Emits [message] through [pdfDebugGestureLog] when a host has installed one.
/// [details] is appended lazily so its (possibly non-trivial) string only
/// builds when logging is live.
void pdfLogGesture(String message, [String Function()? details]) {
  final sink = pdfDebugGestureLog;
  if (sink == null) return;
  sink(details == null ? message : '$message ${details()}');
}

/// Debug registry of the page indices with a live page-view state (created
/// in `initState`, removed on `dispose`). Only the active document's viewer
/// builds page views, so indices are unambiguous. Feeds
/// [pdfDebugShowRenderWindow]; maintained always (a set add/remove per page
/// lifecycle is noise) so the overlay is truthful the moment it is enabled.
class PdfLivePageRegistry extends ChangeNotifier {
  PdfLivePageRegistry._();

  static final PdfLivePageRegistry instance = PdfLivePageRegistry._();

  final Set<int> _pages = <int>{};

  /// Whether [pageIndex] currently has a live page-view state.
  bool contains(int pageIndex) => _pages.contains(pageIndex);

  /// Number of live page-view states.
  int get length => _pages.length;

  /// The live page indices (unmodifiable snapshot).
  Set<int> get pages => Set.unmodifiable(_pages);

  void add(int pageIndex) {
    if (_pages.add(pageIndex)) _scheduleNotify();
  }

  void remove(int pageIndex) {
    if (_pages.remove(pageIndex)) _scheduleNotify();
  }

  void move(int from, int to) {
    if (from == to) return;
    _pages.remove(from);
    _pages.add(to);
    _scheduleNotify();
  }

  bool _notifyScheduled = false;

  /// Mutations arrive from page-view `initState`/`dispose`, which run
  /// mid-build (a lazy list inflates children inside a layout callback), where
  /// a synchronous [notifyListeners] is a build-phase violation for any
  /// listening overlay. Defer to a microtask (coalescing a burst of page
  /// lifecycles into one tick), which runs after the frame's synchronous work.
  void _scheduleNotify() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      notifyListeners();
    });
  }
}

/// Debug registry of each page's current legacy detail-patch bounds, as
/// fractions (0..1) of the page. Page views report on build (only while
/// [pdfDebugPaintDetailBounds] is on); the thumbnail overlay draws them so
/// the strip shows where each page's patch sits. Same microtask coalescing
/// as [PdfLivePageRegistry] - reports arrive mid-build.
class PdfDebugDetailRegions extends ChangeNotifier {
  PdfDebugDetailRegions._();

  static final PdfDebugDetailRegions instance = PdfDebugDetailRegions._();

  final Map<int, Rect> _patchFraction = {};

  /// The page's current detail-patch bounds (page fractions), or null.
  Rect? patchFractionOf(int pageIndex) => _patchFraction[pageIndex];

  /// Records (or clears, with null) a page's patch bounds.
  void report(int pageIndex, Rect? fraction) {
    if (_patchFraction[pageIndex] == fraction) return;
    if (fraction == null) {
      _patchFraction.remove(pageIndex);
    } else {
      _patchFraction[pageIndex] = fraction;
    }
    _scheduleNotify();
  }

  bool _notifyScheduled = false;

  void _scheduleNotify() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      notifyListeners();
    });
  }
}
