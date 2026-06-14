import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:pdf_document/pdf_document.dart';

import 'perf_log.dart';
import 'render_worker.dart';
import 'renderer.dart';

/// Low-resolution page previews shown while a page's full render is
/// pending — most visibly during fast scrolling, when [PdfPageView]
/// holds the (UI-thread) first interpretation of pages flying past and
/// would otherwise show blank paper.
///
/// The cache lives above the page widgets (the viewer owns one per
/// document), so previews survive page states being disposed as they
/// scroll out of the build window: a page seen once keeps its preview
/// for the rest of the session. Pages never seen are filled in by the
/// viewer's background prerender, nearest the viewport first.
///
/// Entries are small (longest side [longestSide] px, ~125 KB each at the
/// default 200) and capped at [capacity], oldest-touched evicted first.
/// [imageFor] hands out [ui.Image.clone]s, so eviction can never pull
/// pixels out from under a painting widget.
class PdfPagePreviewCache extends ChangeNotifier {
  PdfPagePreviewCache({this.longestSide = 200, this.capacity = 300});

  /// Pixel size of a preview's longest side. Stretched to page size on
  /// screen the result is soft but recognizable — enough to navigate by.
  final double longestSide;

  /// Maximum number of cached previews (LRU eviction past it).
  final int capacity;

  // LinkedHashMap insertion order doubles as the LRU order: lookups
  // re-insert, eviction takes the first key.
  final _entries = <int, _PreviewEntry>{};
  bool _disposed = false;

  /// The preview for page [index], as a clone the caller owns (and must
  /// dispose), or null when none is cached. Counts as a use for LRU.
  ui.Image? imageFor(int index) {
    final entry = _entries.remove(index);
    if (entry == null) return null;
    _entries[index] = entry;
    return entry.image.clone();
  }

  /// Whether any preview (fresh or stale) exists for page [index].
  bool has(int index) => _entries.containsKey(index);

  /// Whether the cached preview for [index] was rendered from exactly
  /// this [page] object — the staleness test both fill paths use to
  /// skip redundant work.
  bool isFresh(int index, PdfPage page) =>
      identical(_entries[index]?.page, page);

  double _ratioFor(Size size) {
    final longest = math.max(size.width, size.height);
    if (longest <= 0) return 1;
    return math.min(1, longestSide / longest);
  }

  /// Interprets [page] and stores its preview — the background-prerender
  /// path for pages that have never rendered on screen. When [worker] is
  /// supplied the interpreter walk is offloaded to a background isolate and
  /// only the (cheap) replay + downscale run here; otherwise the walk is
  /// synchronous UI-thread work, so callers pace and gate these (the viewer
  /// pauses while the user scrolls). A page that fails to render simply gets
  /// no preview.
  Future<void> renderPreview(int index, PdfPage page,
      {Color pageColor = const Color(0xFFFFFFFF),
      bool annotations = true,
      PdfRenderWorker? worker}) async {
    if (_disposed || isFresh(index, page)) return;
    try {
      final sw = Stopwatch()..start();
      final size = PdfPageRenderer.pageSize(page);
      final ratio = _ratioFor(size);
      // priority 1: prefetch yields to any on-screen page the worker owes
      final commands = worker != null && worker.isActive
          ? await worker.record(index, annotations: annotations, priority: 1)
          : null;
      if (_disposed || isFresh(index, page)) return;
      final ui.Image image;
      if (commands != null) {
        final picture = await PdfPageRenderer.pictureFromCommands(page, commands,
            pageColor: pageColor);
        try {
          image = await PdfPageRenderer.rasterize(picture, size, ratio);
        } finally {
          picture.dispose();
        }
      } else {
        image = await PdfPageRenderer.renderImage(page,
            pixelRatio: ratio,
            pageColor: pageColor,
            annotations: annotations,
            recorded: true);
      }
      sw.stop();
      PdfPerfLog.log('prerender page=$index '
          '${commands != null ? 'worker ' : ''}'
          'warm=${(sw.elapsedMicroseconds / 1000).toStringAsFixed(1)}ms');
      _store(index, page, image);
    } catch (_) {
      // no preview is strictly better than a crash mid-scroll
    }
  }

  /// Downscales an already-interpreted [picture] into the cache — free
  /// population as pages render on screen (raster-thread work only, no
  /// second interpreter walk). The picture stays owned by the caller.
  Future<void> putFromPicture(int index, PdfPage page,
      ui.Picture picture) async {
    if (_disposed || isFresh(index, page)) return;
    try {
      final size = PdfPageRenderer.pageSize(page);
      final image =
          await PdfPageRenderer.rasterize(picture, size, _ratioFor(size));
      _store(index, page, image);
    } catch (_) {
      // the caller can dispose the picture mid-rasterize (page swap)
    }
  }

  void _store(int index, PdfPage page, ui.Image image) {
    if (_disposed) {
      image.dispose();
      return;
    }
    _entries.remove(index)?.image.dispose();
    _entries[index] = _PreviewEntry(page, image);
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first)!.image.dispose();
    }
    notifyListeners();
  }

  /// Re-binds entries to the page objects of a same-geometry document
  /// revision (an edit swap) without re-rendering. Previews of pages the
  /// edit visually changed go briefly stale — they refresh from the full
  /// render the moment the page is on screen, which is where edits
  /// happen — but the whole document doesn't re-interpret per pen
  /// stroke.
  void rebind(List<PdfPage> pages) {
    for (final entry in _entries.entries) {
      if (entry.key < pages.length) entry.value.page = pages[entry.key];
    }
  }

  /// Drops every preview (different document, page color change...).
  void clear() {
    for (final entry in _entries.values) {
      entry.image.dispose();
    }
    _entries.clear();
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final entry in _entries.values) {
      entry.image.dispose();
    }
    _entries.clear();
    super.dispose();
  }
}

class _PreviewEntry {
  _PreviewEntry(this.page, this.image);

  PdfPage page;
  final ui.Image image;
}
