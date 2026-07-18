/// Viewer debug-overlay flags and registries, driven by a host app's
/// developer tools. All default off and cost nothing until flipped; they are
/// [ValueNotifier]s so overlay painters can repaint on toggle without the
/// host rebuilding the page tree.
library;

import 'dart:async';

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
