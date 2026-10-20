/// A live page whose GPU/decoded raster memory is counted against the global
/// [PdfLiveRasterBudget]. Implemented by the page view's state.
///
/// Kept `dart:ui`-free (a plain interface) so the budget's accounting and
/// eviction order are unit-testable against fakes without a Flutter binding.
abstract class PdfLiveRasterHolder {
  /// Approximate bytes of raster/decoded-image memory this live page holds
  /// right now (base raster + detail patch + retained-scene decoded images).
  /// 0 while the page holds nothing rasterised.
  int get liveRasterBytes;

  /// Distance in pages from the focused page (0 = the page under the viewport).
  /// Farthest-from-viewport pages are evicted first, and the focused page
  /// (distance 0) is never evicted.
  int get liveRasterDistance;

  /// Whether any part of this page currently overlaps the viewport.
  ///
  /// Distinct from `liveRasterDistance == 0`, and the distinction is the whole
  /// point: focus is a single page index (the one under the viewport centre),
  /// so on any document whose pages are taller than the viewport there is a
  /// second page - often half the screen - sitting at distance 1. Evicting
  /// *that* is not reclaiming an off-screen prefetch, it is blanking a page the
  /// user is looking at, which re-renders immediately and flickers on the way
  /// back (#657). On-screen pages are the working set; they are never reclaimed
  /// by this budget because their next build immediately allocates the same
  /// raster again.
  bool get liveRasterOnScreen;

  /// Drops this page's base + detail rasters (and retained scene) to free
  /// memory. The page keeps its low-res preview up and re-rasterises when it is
  /// next scrolled back into (or near) the viewport. Called only on an
  /// off-screen holder with [liveRasterDistance] > 0.
  void evictLiveRaster();
}

/// Process-wide budget over the rasters live page views hold simultaneously.
///
/// Per-page raster caps are additive: with several pages live in the scroll
/// cacheExtent, each holding a base raster, a detail patch, and a retained
/// scene's decoded images, the sum reaches several hundred MB of GPU memory
/// with no cross-page accounting - the memory-pressure / jetsam shape #405
/// describes on large-format documents. This registers every live page and,
/// whenever the total exceeds [maxBytes], evicts the farthest-from-viewport
/// pages' rasters until it fits, never touching the focused page.
///
/// It is a *reclaim* budget, not a reservation: pages rasterise freely and this
/// trims afterward, so a momentary overshoot is fine. The visible working set
/// may remain over budget: evicting it would not produce lasting headroom,
/// because a visible page immediately requests its raster again. Off-screen
/// eviction is farthest-first and stops the moment the total fits or only
/// visible pages remain.
class PdfLiveRasterBudget {
  PdfLiveRasterBudget._();

  /// The shared instance every live page view registers with.
  static final PdfLiveRasterBudget instance = PdfLiveRasterBudget._();

  /// Total live-raster bytes allowed before eviction kicks in. Set once at
  /// startup, sized to the platform (see `pdfDefaultLiveRasterBudgetBytes`).
  /// 0 or negative disables the budget (no eviction).
  int maxBytes = 256 << 20;

  final _holders = <PdfLiveRasterHolder>{};

  /// Registers a live page (its state's initState). Idempotent.
  void register(PdfLiveRasterHolder holder) => _holders.add(holder);

  /// Unregisters a live page (its state's dispose). Idempotent.
  void unregister(PdfLiveRasterHolder holder) => _holders.remove(holder);

  /// Number of registered live pages - test/diagnostic hook.
  int get holderCount => _holders.length;

  /// Total live-raster bytes across every registered page right now.
  int get totalBytes {
    var total = 0;
    for (final holder in _holders) {
      total += holder.liveRasterBytes;
    }
    return total;
  }

  /// Evicts farthest-from-viewport pages' rasters until [totalBytes] is within
  /// [maxBytes]. Call after a page's raster grows (a base raster or detail
  /// patch lands). Never evicts the focused page (distance 0); stops as soon as
  /// the total fits, so the near-viewport working set is preserved.
  ///
  /// Off-screen pages go first, in full
  /// ([PdfLiveRasterHolder.liveRasterOnScreen]). A large-format document where
  /// two visible pages alone exceed the budget remains temporarily over budget
  /// rather than blanking one page and immediately allocating it again.
  /// Per-page caps still bound each member of that unavoidable working set.
  ///
  /// Returns the bytes freed (0 when already within budget).
  int rebalance() {
    if (maxBytes <= 0) return 0;
    var total = totalBytes;
    if (total <= maxBytes) return 0;

    // Farthest first; on a tie the larger raster goes first (frees more per
    // eviction). A stable order also makes the eviction sequence testable.
    final ordered = _holders.toList()
      ..sort((a, b) {
        final byDistance = b.liveRasterDistance.compareTo(a.liveRasterDistance);
        return byDistance != 0
            ? byDistance
            : b.liveRasterBytes.compareTo(a.liveRasterBytes);
      });

    var freed = 0;
    for (final holder in ordered) {
      if (total <= maxBytes) return freed;
      if (holder.liveRasterDistance <= 0 || holder.liveRasterOnScreen) {
        continue;
      }
      final bytes = holder.liveRasterBytes;
      if (bytes <= 0) continue;
      holder.evictLiveRaster();
      total -= bytes;
      freed += bytes;
    }
    return freed;
  }

  /// Surrenders every reclaimable off-screen page's raster regardless of the
  /// budget - the memory-pressure path. Live-page rasters used to be exempt
  /// from the pressure signal that trims the byte-budgeted caches (#405); this
  /// hands the whole off-viewport working set back on a `didHaveMemoryPressure`.
  ///
  /// On-screen pages are left alone: they re-rasterize the moment they are
  /// dropped, so evicting them costs a visible flicker and *raises* peak RSS
  /// (the re-render allocates before the old raster's memory is reused) - the
  /// same feedback loop the adaptive-memory damper documents. Pressure has to
  /// come from what the user is not looking at.
  ///
  /// Returns the bytes freed.
  int evictReclaimable() {
    var freed = 0;
    for (final holder in _holders.toList()) {
      if (holder.liveRasterDistance <= 0) continue;
      if (holder.liveRasterOnScreen) continue;
      final bytes = holder.liveRasterBytes;
      if (bytes <= 0) continue;
      holder.evictLiveRaster();
      freed += bytes;
    }
    return freed;
  }
}
