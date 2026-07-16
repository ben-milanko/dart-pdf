import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:pdf_document/pdf_document.dart';

import 'perf_log.dart';
import 'raster_cache.dart';
import 'render_worker.dart';
import 'renderer.dart';

/// Low-resolution page previews shown while a page's full render is
/// pending - most visibly during fast scrolling, when [PdfPageView]
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
  PdfPagePreviewCache({
    this.longestSide = 200,
    this.capacity = 300,
    this.maxFullRasterPixels = 8 << 20,
    this.maxFullRasterEntryPixels = 4 << 20,
  })  : assert(maxFullRasterPixels >= 0),
        assert(maxFullRasterEntryPixels >= 0);

  /// Pixel size of a preview's longest side. Stretched to page size on
  /// screen the result is soft but recognizable - enough to navigate by.
  final double longestSide;

  /// Maximum number of cached previews (LRU eviction past it).
  final int capacity;

  /// Total pixel budget for exact, recently-viewed page rasters.
  ///
  /// These entries remove the soft-preview delay when a lazy page widget is
  /// rebuilt during back-and-forth scrolling. The default is about 32 MiB of
  /// RGBA pixels. Set to zero to keep only low-resolution previews.
  final int maxFullRasterPixels;

  /// Largest exact raster admitted to the recent-page cache.
  ///
  /// Oversized/high-zoom pages keep the existing preview + scheduled-render
  /// path instead of consuming the whole budget. The default is about 16 MiB
  /// of RGBA pixels, which covers ordinary document pages while excluding the
  /// large CAD rasters this cache is not intended to retain.
  final int maxFullRasterEntryPixels;

  // LinkedHashMap insertion order doubles as the LRU order: lookups
  // re-insert, eviction takes the first key.
  final _entries = <int, _PreviewEntry>{};
  final _fullEntries = <int, _FullRasterEntry>{};
  int _fullRasterPixels = 0;
  bool _disposed = false;

  /// Pixels currently retained by the exact recent-page cache.
  @visibleForTesting
  int get debugFullRasterPixels => _fullRasterPixels;

  /// Optional persistent backing (see [PdfRasterCache]). When set, fresh
  /// previews are written through to disk as they render, and [loadFromDisk]
  /// can prime the in-memory cache from a previous session. The viewer
  /// binds this to the open document; null leaves the cache session-only,
  /// exactly as before.
  PdfRasterCache? disk;

  /// Loads any persisted previews for [pages] into memory, so a cold open
  /// of a previously-seen document paints soft content at once. Pages that
  /// already hold a (fresher, in-session) preview are left alone, and the
  /// loaded entries are bound to the current [pages] objects so the
  /// background prerender treats them as done - the on-screen full render
  /// still replaces them when it lands.
  Future<void> loadFromDisk(List<PdfPage> pages) async {
    final cache = disk;
    if (cache == null || _disposed) return;
    for (var i = 0; i < pages.length; i++) {
      if (_disposed) return;
      if (_entries.containsKey(i)) continue;
      final image = await cache.loadPreview(i);
      if (image == null) continue;
      if (_disposed || _entries.containsKey(i)) {
        image.dispose();
        continue;
      }
      // adopt without writing back - these bytes just came from disk
      _entries[i] = _PreviewEntry(pages[i], image, includesImages: true);
      while (_entries.length > capacity) {
        final oldest = _entries.keys.first;
        if (oldest == i) break;
        _entries.remove(oldest)!.image.dispose();
      }
      notifyListeners();
    }
  }

  /// The preview for page [index], as a clone the caller owns (and must
  /// dispose), or null when none is cached. Counts as a use for LRU.
  ui.Image? imageFor(int index) {
    final entry = _entries.remove(index);
    if (entry == null) return null;
    _entries[index] = entry;
    return entry.image.clone();
  }

  /// Returns an exact cached raster matching this page and display geometry.
  ///
  /// The caller owns the returned clone. A mismatch is a miss: page content,
  /// paper color, annotation visibility, rotation, and physical pixel size
  /// all affect the baked raster.
  ui.Image? fullImageFor(
    int index,
    PdfPage page, {
    required int width,
    required int height,
    required Color pageColor,
    required bool annotations,
    required int? rotation,
  }) {
    final entry = _fullEntries.remove(index);
    if (entry == null) return null;
    _fullEntries[index] = entry;
    if (!identical(entry.page, page) ||
        entry.image.width != width ||
        entry.image.height != height ||
        entry.pageColor != pageColor ||
        entry.annotations != annotations ||
        entry.rotation != rotation) {
      return null;
    }
    return entry.image.clone();
  }

  /// Retains a clone of a completed on-screen raster for immediate reuse.
  ///
  /// The cache is an LRU bounded by [maxFullRasterPixels], and rejects a
  /// single image over [maxFullRasterEntryPixels]. Cloning shares the engine
  /// image rather than performing another GPU readback.
  void putFullImage(
    int index,
    PdfPage page,
    ui.Image image, {
    required Color pageColor,
    required bool annotations,
    required int? rotation,
  }) {
    if (_disposed) return;
    final pixels = image.width * image.height;
    if (maxFullRasterPixels == 0 ||
        pixels > maxFullRasterEntryPixels ||
        pixels > maxFullRasterPixels) {
      return;
    }
    final old = _fullEntries.remove(index);
    if (old != null) {
      _fullRasterPixels -= old.pixels;
      old.image.dispose();
    }
    final entry = _FullRasterEntry(
      page,
      image.clone(),
      pageColor: pageColor,
      annotations: annotations,
      rotation: rotation,
    );
    _fullEntries[index] = entry;
    _fullRasterPixels += entry.pixels;
    while (_fullRasterPixels > maxFullRasterPixels && _fullEntries.isNotEmpty) {
      final evicted = _fullEntries.remove(_fullEntries.keys.first)!;
      _fullRasterPixels -= evicted.pixels;
      evicted.image.dispose();
    }
  }

  /// Whether any preview (fresh or stale) exists for page [index].
  bool has(int index) => _entries.containsKey(index);

  /// Whether the cached preview for [index] was rendered from exactly
  /// this [page] object - the staleness test both fill paths use to
  /// skip redundant work.
  bool isFresh(int index, PdfPage page, {bool requireImages = false}) {
    final entry = _entries[index];
    if (!identical(entry?.page, page)) return false;
    return !requireImages || entry!.includesImages;
  }

  double _ratioFor(Size size) {
    final longest = math.max(size.width, size.height);
    if (longest <= 0) return 1;
    return math.min(1, longestSide / longest);
  }

  /// Interprets [page] and stores its preview - the background-prerender
  /// path for pages that have never rendered on screen. When [worker] is
  /// supplied the interpreter walk is offloaded to a background isolate and
  /// only the (cheap) replay + downscale run here; otherwise the walk is
  /// synchronous UI-thread work, so callers pace and gate these (the viewer
  /// pauses while the user scrolls). A page that fails to render simply gets
  /// no preview.
  Future<void> renderPreview(int index, PdfPage page,
      {Color pageColor = const Color(0xFFFFFFFF),
      bool annotations = true,
      PdfRenderWorker? worker,
      int? rotation,
      bool decodeImages = true,
      int priority = 1,
      int? commandLimit,
      bool Function()? deferUiWork}) async {
    if (_disposed || isFresh(index, page, requireImages: decodeImages)) return;
    if (!decodeImages && (worker == null || !worker.isActive)) {
      // A vector-first preview is only cheap through the worker. The local
      // fallback would run a full UI-thread render and decode the images, which
      // is exactly what fast-scroll prefetch is trying to avoid.
      return;
    }
    try {
      final sw = Stopwatch()..start();
      final size = PdfPageRenderer.pageSize(page, rotation: rotation);
      final ratio = _ratioFor(size);
      // priority 1: prefetch yields to any on-screen page the worker owes.
      // The preview is rasterized at [ratio] (longest side ~200px), so cap the
      // worker's images to that - a heavy raster underlay need not ship at full
      // resolution just to be downscaled into a thumbnail.
      final commands = worker != null && worker.isActive
          ? await worker.record(index,
              annotations: annotations,
              priority: priority,
              imagePixelRatio: decodeImages ? ratio : null,
              decodeImages: decodeImages,
              commandLimit: commandLimit)
          : null;
      if (!decodeImages && commands == null) {
        // Worker-declined vector warms must stay cheap. Falling back to
        // renderImage here would synchronously interpret/decode images on the
        // UI thread during the fast-scroll path.
        return;
      }
      if (deferUiWork?.call() ?? false) return;
      if (_disposed || isFresh(index, page, requireImages: decodeImages)) {
        return;
      }
      final ui.Image image;
      var includesImages = decodeImages;
      if (commands != null) {
        includesImages = commandLimit == null &&
            (decodeImages || !PdfPageRenderer.hasImageDraws(commands));
        final picture = await PdfPageRenderer.pictureFromCommands(
            page, commands,
            pageColor: pageColor,
            rotation: rotation,
            includeImages: decodeImages);
        if (deferUiWork?.call() ?? false) {
          picture.dispose();
          return;
        }
        try {
          image = await PdfPageRenderer.rasterize(picture, size, ratio);
        } finally {
          picture.dispose();
        }
      } else {
        if (deferUiWork?.call() ?? false) return;
        image = await PdfPageRenderer.renderImage(page,
            pixelRatio: ratio,
            pageColor: pageColor,
            annotations: annotations,
            recorded: true,
            rotation: rotation);
      }
      if (deferUiWork?.call() ?? false) {
        image.dispose();
        return;
      }
      sw.stop();
      PdfPerfLog.log('prerender page=$index '
          '${commands != null ? 'worker ' : ''}'
          '${includesImages ? 'full' : 'vector'} '
          'warm=${(sw.elapsedMicroseconds / 1000).toStringAsFixed(1)}ms');
      if (_disposed || isFresh(index, page, requireImages: decodeImages)) {
        image.dispose();
        return;
      }
      _store(index, page, image, includesImages: includesImages);
    } catch (_) {
      // no preview is strictly better than a crash mid-scroll
    }
  }

  /// Downscales an already-interpreted [picture] into the cache - free
  /// population as pages render on screen (raster-thread work only, no
  /// second interpreter walk). The picture stays owned by the caller.
  Future<void> putFromPicture(int index, PdfPage page, ui.Picture picture,
      {int? rotation}) async {
    if (_disposed || isFresh(index, page, requireImages: true)) return;
    try {
      final size = PdfPageRenderer.pageSize(page, rotation: rotation);
      final image =
          await PdfPageRenderer.rasterize(picture, size, _ratioFor(size));
      _store(index, page, image, includesImages: true);
    } catch (_) {
      // the caller can dispose the picture mid-rasterize (page swap)
    }
  }

  void _store(int index, PdfPage page, ui.Image image,
      {required bool includesImages}) {
    if (_disposed) {
      image.dispose();
      return;
    }
    _entries.remove(index)?.image.dispose();
    _entries[index] =
        _PreviewEntry(page, image, includesImages: includesImages);
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first)!.image.dispose();
    }
    // Write through to disk so the next session opens with this preview
    // already on screen. Fire-and-forget: the encode is a raster-thread
    // readback and a slow/failed store must never stall rendering.
    if (includesImages) disk?.storePreview(index, image);
    notifyListeners();
  }

  /// Re-binds entries to the page objects of a same-geometry document
  /// revision (an edit swap) without re-rendering. Previews of pages the
  /// edit visually changed go briefly stale - they refresh from the full
  /// render the moment the page is on screen, which is where edits
  /// happen - but the whole document doesn't re-interpret per pen
  /// stroke.
  ///
  /// [changed] (when given) names pages whose *content* changed in the new
  /// revision - most importantly a redaction burn, where the old preview
  /// still shows the removed glyphs/images. Their previews are dropped
  /// rather than rebound, so a fresh page state scrolled past during a fast
  /// scroll paints blank (then re-renders) instead of flashing now-deleted
  /// content. The rest rebind in place as before.
  void rebind(List<PdfPage> pages, {bool Function(int index)? changed}) {
    var dropped = false;
    for (final index in _entries.keys.toList()) {
      if (changed != null && changed(index)) {
        _entries.remove(index)!.image.dispose();
        dropped = true;
      } else if (index < pages.length) {
        _entries[index]!.page = pages[index];
      }
    }
    for (final index in _fullEntries.keys.toList()) {
      if (changed != null && changed(index)) {
        final entry = _fullEntries.remove(index)!;
        _fullRasterPixels -= entry.pixels;
        entry.image.dispose();
        dropped = true;
      } else if (index < pages.length) {
        _fullEntries[index]!.page = pages[index];
      }
    }
    if (dropped && !_disposed) notifyListeners();
  }

  /// Drops every preview (different document, page color change...).
  void clear() {
    for (final entry in _entries.values) {
      entry.image.dispose();
    }
    _entries.clear();
    for (final entry in _fullEntries.values) {
      entry.image.dispose();
    }
    _fullEntries.clear();
    _fullRasterPixels = 0;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final entry in _entries.values) {
      entry.image.dispose();
    }
    _entries.clear();
    for (final entry in _fullEntries.values) {
      entry.image.dispose();
    }
    _fullEntries.clear();
    _fullRasterPixels = 0;
    super.dispose();
  }
}

class _PreviewEntry {
  _PreviewEntry(this.page, this.image, {required this.includesImages});

  PdfPage page;
  final ui.Image image;
  final bool includesImages;
}

class _FullRasterEntry {
  _FullRasterEntry(
    this.page,
    this.image, {
    required this.pageColor,
    required this.annotations,
    required this.rotation,
  });

  PdfPage page;
  final ui.Image image;
  final Color pageColor;
  final bool annotations;
  final int? rotation;

  int get pixels => image.width * image.height;
}
