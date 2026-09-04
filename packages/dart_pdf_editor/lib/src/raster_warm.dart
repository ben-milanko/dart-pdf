import 'package:flutter/foundation.dart';

/// How much of a document the viewer rasterizes ahead of navigation while it
/// is genuinely idle.
enum PdfPageRasterWarmMode {
  /// No background full-resolution work at all. The exact-raster cache is
  /// still populated for free by pages that render on screen.
  disabled,

  /// Warm a bounded window of pages either side of the viewport
  /// ([PdfPageRasterWarmPolicy.window]).
  nearby,

  /// Warm every page of the document, nearest the viewport first.
  document,
}

/// Whether - and how far ahead - the viewer bakes exact, display-sized page
/// rasters for pages the user has not visited.
///
/// [PdfPageRasterCachePolicy] governs how much of that result is *retained*.
/// This governs whether it is ever *produced*: without it the exact-raster
/// cache fills only as pages render on screen, so the first arrival on a page
/// always pays for its own interpretation and readback.
///
/// The ordinary warm is idle work in the strict sense. It starts only after
/// the viewer has been quiet for [idleDelay], stands down the instant a zoom,
/// edit, or foreground page render needs the platform thread, and paces itself
/// to one page at a time with a frame yielded between pages. During a sustained
/// slow scroll, [slowScrollWindow] additionally admits a directional look-ahead
/// through an accelerated full-page backend. That lane remains serial,
/// requires a spare render-worker lane, and never falls back to Canvas while
/// input is live. Fast motion immediately prevents another submission and
/// preempts work that has not yet reached the GPU.
///
/// Both paths target the settled fit-size raster only - deep zoom stays
/// region/tile driven - and never render a page whose raster the cache policy
/// could not admit.
///
/// When the selected [PdfTileRasterBackend] advertises full-page warm support,
/// the viewer records a retained scene and produces the resident image through
/// that backend. The temporary scene session is then released; the exact image
/// remains in the same byte-budgeted LRU used for visited pages. A backend that
/// rejects or fails one page falls back to the exact Canvas path for that page.
///
/// The default is [PdfPageRasterWarmMode.disabled]: warming trades CPU, GPU,
/// and memory for navigation latency, and only the host knows whether that
/// trade is wanted. A desktop reader with room to spare might use:
///
/// ```dart
/// PdfViewer(
///   document: document,
///   pageRasterCachePolicy: const PdfPageRasterCachePolicy(
///     maxBytes: 4 * 1024 * 1024 * 1024,
///     maxEntryBytes: 64 * 1024 * 1024,
///   ),
///   pageRasterWarmPolicy: const PdfPageRasterWarmPolicy.document(),
/// )
/// ```
@immutable
class PdfPageRasterWarmPolicy {
  /// No background full-raster work (the default).
  const PdfPageRasterWarmPolicy.disabled()
      : mode = PdfPageRasterWarmMode.disabled,
        window = 0,
        slowScrollWindow = 0,
        idleDelay = const Duration(milliseconds: 750);

  /// Warms up to [window] pages either side of the viewport - a conservative
  /// setting that removes the arrival cost of the next few pages without
  /// committing the memory a whole document would.
  const PdfPageRasterWarmPolicy.nearby({
    this.window = 3,
    this.slowScrollWindow = 3,
    this.idleDelay = const Duration(milliseconds: 750),
  })  : mode = PdfPageRasterWarmMode.nearby,
        assert(window > 0),
        assert(slowScrollWindow >= 0);

  /// Warms every page, nearest the viewport first. Bounded in practice by
  /// [PdfPageRasterCachePolicy.maxBytes]: pages past the budget evict the
  /// least-recently-used rasters, so a document larger than the budget settles
  /// into a moving window rather than growing without limit.
  const PdfPageRasterWarmPolicy.document({
    this.slowScrollWindow = 3,
    this.idleDelay = const Duration(milliseconds: 750),
  })  : mode = PdfPageRasterWarmMode.document,
        window = 0,
        assert(slowScrollWindow >= 0);

  /// How far the warm reaches.
  final PdfPageRasterWarmMode mode;

  /// Pages either side of the viewport warmed under
  /// [PdfPageRasterWarmMode.nearby]. Unused by the other modes.
  final int window;

  /// Maximum number of not-yet-visible pages to keep sharp ahead of a
  /// sustained slow scroll.
  ///
  /// The effective count is also bounded by the exact-raster byte budget. In
  /// [PdfPageRasterWarmMode.nearby] it cannot exceed [window]. Set to zero to
  /// retain idle warming while disabling live directional look-ahead.
  final int slowScrollWindow;

  /// How long the viewer must be quiet - no scroll, zoom, edit, or queued
  /// page render - before warming starts or resumes.
  ///
  /// This is deliberately longer than the viewer's own scroll/zoom settle
  /// windows: settling means the viewer may render, and the warm must not be
  /// the thing competing with that render for the platform thread.
  final Duration idleDelay;

  /// Whether any background full-raster work is permitted.
  bool get enabled => mode != PdfPageRasterWarmMode.disabled;

  @override
  bool operator ==(Object other) =>
      other is PdfPageRasterWarmPolicy &&
      mode == other.mode &&
      window == other.window &&
      slowScrollWindow == other.slowScrollWindow &&
      idleDelay == other.idleDelay;

  @override
  int get hashCode => Object.hash(mode, window, slowScrollWindow, idleDelay);

  @override
  String toString() => switch (mode) {
        PdfPageRasterWarmMode.disabled => 'PdfPageRasterWarmPolicy.disabled()',
        PdfPageRasterWarmMode.nearby =>
          'PdfPageRasterWarmPolicy.nearby(window: $window, '
              'slowScrollWindow: $slowScrollWindow)',
        PdfPageRasterWarmMode.document => 'PdfPageRasterWarmPolicy.document('
            'slowScrollWindow: $slowScrollWindow)',
      };
}

/// A snapshot of what the idle full-raster warm and the exact-raster cache
/// have actually done - the diagnostic counterpart to
/// [PdfPageRasterWarmPolicy].
///
/// Everything here is lifetime-cumulative for one [PdfPagePreviewCache] except
/// [retainedBytes] and [entries], which are live occupancy.
@immutable
class PdfPageRasterWarmStats {
  const PdfPageRasterWarmStats({
    required this.attempts,
    required this.completions,
    required this.skipped,
    required this.rejected,
    required this.preempted,
    required this.warmedBytes,
    required this.hits,
    required this.misses,
    required this.evictions,
    required this.retainedBytes,
    required this.entries,
  });

  /// Pages the warm started rendering (admissible, not already cached).
  final int attempts;

  /// Warm renders that finished and were stored.
  final int completions;

  /// Pages the warm passed over because the raster was already cached.
  final int skipped;

  /// Pages the warm declined *before* rendering because the cache policy
  /// could not admit a raster that size.
  final int rejected;

  /// Warm renders abandoned part-way because the viewer stopped being idle.
  final int preempted;

  /// Approximate RGBA bytes the warm has added to the cache.
  final int warmedBytes;

  /// Exact-raster lookups served from cache (warmed or visited alike).
  final int hits;

  /// Exact-raster lookups that had to render.
  final int misses;

  /// Cached rasters dropped by a byte/entry budget.
  final int evictions;

  /// Approximate RGBA bytes currently retained by the exact-raster cache.
  final int retainedBytes;

  /// Exact rasters currently retained.
  final int entries;

  @override
  String toString() => 'PdfPageRasterWarmStats(attempts: $attempts, '
      'completions: $completions, skipped: $skipped, rejected: $rejected, '
      'preempted: $preempted, warmedBytes: $warmedBytes, hits: $hits, '
      'misses: $misses, evictions: $evictions, '
      'retainedBytes: $retainedBytes, entries: $entries)';
}
