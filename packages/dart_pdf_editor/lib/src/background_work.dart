import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:pdf_document/pdf_document.dart';

import 'page_set.dart';
import 'perf_log.dart';
import 'preview_cache.dart'
    show PdfPagePreviewLodPolicy, PdfPageRasterSignature;
import 'raster_warm.dart';
import 'tile_raster_backend.dart';

/// The flags a [PdfBackgroundWork] raises on the visible-page scheduler, and
/// the two things it reads back. `PdfPageRenderScheduler` implements it; unit
/// tests substitute a plain fake.
abstract interface class PdfBackgroundScheduler {
  /// A fast scroll or quiet window holding page renders back.
  bool get holding;
  set holding(bool value);

  /// Input is arriving right now.
  bool get activeGesture;
  set activeGesture(bool value);

  /// The sustained slow-scroll sharpening lane is open.
  bool get slowMotion;
  set slowMotion(bool value);

  /// The viewer is paused under another view.
  bool get parked;
  set parked(bool value);

  /// The page held renders drain from, nearest first.
  set focus(int index);

  /// Foreground page work is queued or in flight.
  bool get busy;
  bool get hasForegroundWork;
}

/// What a raster warm must produce for a page: the pixel ratio it renders at
/// and the exact-raster key it is stored under. The viewer prices it through
/// `PdfPageRasterGeometry` - the arithmetic the on-screen page runs - so a
/// warmed raster is exactly the one the page later asks for.
typedef PdfRasterWarmTarget = ({
  double ratio,
  PdfPageRasterSignature signature,
});

/// The facts and lane bodies a [PdfBackgroundWork] needs from its viewer.
///
/// The coordinator decides *when* a lane runs and keeps every piece of lane
/// state; the host answers questions about the viewer and does the rendering.
/// Tests implement it with plain fields.
abstract interface class PdfBackgroundHost {
  bool get mounted;

  /// Foreground (not paused under another view).
  bool get active;
  bool get pagePreviews;
  PdfPageRasterWarmPolicy get rasterWarmPolicy;

  /// The quiet window before the preview pass starts.
  Duration get previewIdleDelay;

  /// A direct pan/zoom gesture or animation is moving the view (the motion
  /// hold's release window is the coordinator's own and is added on top).
  bool get directGesture;

  /// The list's scroll-settle window is open.
  bool get scrollSettling;

  /// A zoom transform change has not settled yet.
  bool get zoomSettling;

  /// Zoomed past fit (deep zoom is region driven; warming resumes at fit).
  bool get deepZoom;

  /// An editing tool is armed: the next thing to happen is an edit.
  bool get toolArmed;

  List<PdfPage> get pages;
  int get currentPage;

  /// Whether page [index] is in or around the live build window (it renders
  /// on its own), or null before layout.
  bool Function(int index)? nearViewport();

  /// Whether page [index] is on screen.
  bool onScreen(int index);

  /// The preview LoD ladder in force and the intermediate rungs it holds.
  PdfPagePreviewLodPolicy get previewLodPolicy;
  List<double> get intermediateLongestSides;

  /// How far from the current page the base preview pass reaches (0 = no
  /// limit), after the worker-cache and document-size horizons.
  int previewWindow({required bool requireImages});

  /// Page [index] already has a fresh preview at that level.
  bool previewFresh(int index,
      {required bool requireImages, double? targetLongestSide});

  /// Page [index] has any preview at all, even a stale revision's.
  bool hasPreview(int index);

  /// What warming page [index] must produce; null before layout.
  PdfRasterWarmTarget? rasterWarmTarget(int index);

  bool hasFullRaster(int index, PdfPageRasterSignature signature);
  int get maxFullRasterBytes;
  int get maxFullRasterEntryBytes;

  /// Warms page [index]'s exact raster; true once it is stored.
  Future<bool> warmFullRaster(
    int index,
    PdfRasterWarmTarget target, {
    required int priority,
    required bool Function() shouldStop,
    bool acceleratedOnly = false,
  });

  /// An accelerated full-page backend and a spare worker lane exist, so the
  /// slow-scroll look-ahead has capacity of its own.
  bool get slowScrollWarmCapable;

  /// Runs the preview prerender pass (it reads the coordinator's state).
  void runPreviewPass();

  /// The focused page is worth a speculative text warm.
  bool get textWarmWanted;

  /// Starts the text warm for the focused page, or returns null when it
  /// declined without starting.
  Future<void>? runTextWarm();

  PdfTileRasterBackend get tileBackend;

  /// Runs [callback] after the current frame.
  void postFrame(VoidCallback callback);

  /// Completes once the engine has produced the next frame.
  Future<void> get endOfFrame;
}

/// One coordinator for a viewer's background render work.
///
/// Six lanes share the viewer's idle time: the motion hold, the preview
/// prerender/LoD ladder, the command warm, the full and slow-scroll raster
/// warms, the visible-page text warm, and the tile backend warm-up. This owns
/// all of their attempt sets, generations, timers and running flags, raises
/// the visible-page scheduler's flags, and answers the idle question once per
/// lane from one set of facts. The viewer reports events - motion started,
/// settled, invalidated, a policy changed - instead of directing each lane.
class PdfBackgroundWork {
  PdfBackgroundWork({required this.host, required this.scheduler});

  final PdfBackgroundHost host;
  final PdfBackgroundScheduler scheduler;

  // --- facts -----------------------------------------------------------------

  Timer? _motionHoldReleaseTimer;
  Timer? _gestureQuietTimer;

  /// Direct gestures and animations that defer even the cheap vector preview
  /// replay. A list/wheel scroll is deliberately not included: its
  /// command-limited vector preview keeps fast-scrolled pages visible.
  bool get directMotion =>
      host.directGesture || (_motionHoldReleaseTimer?.isActive ?? false);

  /// Full page/thumbnail rasters also stay held for the scroll quiet window.
  bool get motionHold => directMotion || host.scrollSettling;

  /// A wheel signal also leaves the transform's short release timer active,
  /// but the live scroll timer distinguishes that from a direct gesture: the
  /// command-limited vector preview may run while the list scrolls.
  bool get previewUiMustDefer => directMotion && !host.scrollSettling;

  /// Idle enough for background full-raster work. Every clause is a way the
  /// warm could land on top of something the user is waiting for: its replay
  /// and readback run on the platform thread, so only not starting can
  /// govern them (#603).
  bool get rasterWarmIdle =>
      host.mounted &&
      host.active &&
      host.pagePreviews &&
      host.rasterWarmPolicy.enabled &&
      // a fast scroll holding renders, a page queued for its first interpret,
      // or a granted render still replaying/rasterizing
      !scheduler.busy &&
      // the quiet windows a scroll or zoom leaves behind
      !motionHold &&
      !host.zoomSettling &&
      !host.deepZoom &&
      !host.toolArmed;

  /// Idle enough for the visible page's speculative text walk, which cannot
  /// yield to an urgent render once it starts.
  bool get textWarmIdle =>
      host.mounted &&
      host.active &&
      !scheduler.busy &&
      !motionHold &&
      !host.zoomSettling;

  /// Idle enough for a command warm's platform-thread replay or upload.
  bool get commandWarmUiIdle => !scheduler.busy && !motionHold;

  // --- motion hold -------------------------------------------------------------

  /// How long after the last scroll event the viewer stops calling it a
  /// gesture: two frames.
  static const gestureQuietDelay = Duration(milliseconds: 120);

  /// How long a direct gesture's hold outlasts its end.
  static const motionHoldReleaseDelay = Duration(milliseconds: 250);

  set focus(int index) => scheduler.focus = index;

  /// A direct gesture, zoom or scroll burst began: hold renders, stop the
  /// preview and text lanes, close the slow lane.
  void beginMotion() {
    cancelPreviews();
    cancelTextWarm();
    _motionHoldReleaseTimer?.cancel();
    _motionHoldReleaseTimer = null;
    scheduler.slowMotion = false;
    setSlowScrollDirection(0);
    scheduler.holding = true;
  }

  /// A direct gesture ended: keep holding for [motionHoldReleaseDelay], then
  /// settle.
  void endMotionSoon() {
    _motionHoldReleaseTimer?.cancel();
    late final Timer timer;
    timer = Timer(motionHoldReleaseDelay, () {
      if (!identical(_motionHoldReleaseTimer, timer)) return;
      _motionHoldReleaseTimer = null;
      if (!host.mounted) return;
      settle();
      if (!scheduler.holding) schedulePreviews();
    });
    _motionHoldReleaseTimer = timer;
  }

  /// Re-derives the scheduler's flags from the facts.
  void settle() {
    scheduler.holding = motionHold || !host.active;
    // A live gesture is what a UI-thread walk must not run inside; the quiet
    // window that follows one is not.
    scheduler.activeGesture = directMotion;
    if (!motionHold) {
      scheduler.slowMotion = false;
      setSlowScrollDirection(0);
    }
    scheduler.parked = !host.active;
    scheduleTextWarm();
  }

  /// Settles after this frame has rebuilt the pages with their new settle
  /// generation, then re-arms the preview and raster lanes. Releasing
  /// synchronously let the scheduler grant a page that then rebuilt and
  /// discarded the job it had just started.
  void settleAfterBuild() {
    host.postFrame(() {
      if (!host.mounted) return;
      settle();
      schedulePreviews();
      scheduleRasterWarm();
    });
  }

  /// Scroll input arrived: input-quiet page work stays deferred until it
  /// has been quiet for [gestureQuietDelay].
  void markScrollGesture() {
    scheduler.activeGesture = true;
    _gestureQuietTimer?.cancel();
    _gestureQuietTimer = Timer(gestureQuietDelay, () {
      if (!host.mounted) return;
      scheduler.activeGesture = directMotion;
    });
    scheduler.parked = !host.active;
  }

  /// The scroll velocity's verdict on the slow lane: [slow] opens it, aimed
  /// at [direction] for the look-ahead.
  void slowScroll(bool slow, {required int direction}) {
    scheduler.slowMotion = slow;
    setSlowScrollDirection(slow ? direction : 0);
  }

  /// The scroll velocity's verdict on the hold.
  void holdForScroll(bool hold) {
    // a paused viewer (overlaid by another view) holds unconditionally
    scheduler.holding = hold || !host.active;
  }

  /// The viewer mounted: a viewer mounted paused holds from the first frame
  /// so covered pages never interpret.
  void start() {
    if (!host.active) scheduler.holding = true;
    scheduler.parked = !host.active;
  }

  /// The scroll-settle window closed.
  void scrollSettled() {
    scheduler.slowMotion = false;
    setSlowScrollDirection(0);
  }

  // --- preview prerender / LoD ladder ----------------------------------------

  /// Pages the prerender already tried (by page identity), so a page whose
  /// render throws is not retried forever.
  final previewAttempts = Set<PdfPage>.identity();
  final previewVectorAttempts = Set<PdfPage>.identity();
  final Map<double, Set<PdfPage>> intermediatePreviewAttempts = {};

  /// Bumped by every cancel; a pass or a pending start from an older
  /// generation is inert.
  int previewGeneration = 0;

  /// A pass is running; a new start asks it to restart when it ends.
  bool prerendering = false;
  bool previewRestartPending = false;
  Timer? _previewIdleTimer;

  /// Starts the preview pass after this frame's layout has queued visible
  /// renders and the quiet window has elapsed.
  void schedulePreviews() {
    cancelPreviews();
    if (!host.pagePreviews || !host.active) return;
    final generation = previewGeneration;
    host.postFrame(() {
      if (!host.mounted || generation != previewGeneration) return;
      final delay = host.previewIdleDelay;
      if (delay <= Duration.zero) {
        scheduleMicrotask(host.runPreviewPass);
        return;
      }
      late final Timer timer;
      timer = Timer(delay, () {
        if (!host.mounted ||
            generation != previewGeneration ||
            !identical(_previewIdleTimer, timer)) {
          return;
        }
        _previewIdleTimer = null;
        host.runPreviewPass();
      });
      _previewIdleTimer = timer;
    });
  }

  /// The next page worth prerendering: missing a fresh preview at the level
  /// asked for, not yet attempted, inside the preview window, and - unless
  /// [allowNearViewport] - not near the viewport (pages in or around the
  /// build window render fully on their own, and their full picture feeds the
  /// cache). Nearest the current page first. [blankOnly] skips pages with any
  /// preview at all.
  int? nextPreviewPage({
    required bool requireImages,
    required bool allowNearViewport,
    int? maxDistance,
    double? targetLongestSide,
    bool blankOnly = false,
  }) {
    final lod = host.previewLodPolicy;
    if (targetLongestSide != null &&
        (!lod.enabled ||
            lod.intermediateWindow == 0 ||
            !host.intermediateLongestSides.contains(targetLongestSide))) {
      return null;
    }
    final pages = host.pages;
    final current =
        pages.isEmpty ? 0 : host.currentPage.clamp(0, pages.length - 1);
    // pre-layout every page counts as near
    final near = host.nearViewport() ?? (_) => true;
    // bound the proactive warm to a window around the viewport - far pages
    // render on demand on arrival and feed the cache when scrolled through
    final window = targetLongestSide == null
        ? host.previewWindow(requireImages: requireImages)
        : lod.intermediateWindow;
    final attempted = targetLongestSide != null
        ? intermediatePreviewAttempts[targetLongestSide]
        : requireImages
            ? previewAttempts
            : previewVectorAttempts;
    int? best;
    var bestDistance = 1 << 30;
    for (var i = 0; i < pages.length; i++) {
      if (!allowNearViewport && near(i)) continue;
      final distance = (i - current).abs();
      if (maxDistance != null && distance > maxDistance) continue;
      if (window > 0 && distance > window) continue;
      if (attempted?.contains(pages[i]) ?? false) continue;
      if (host.previewFresh(i,
          requireImages: requireImages, targetLongestSide: targetLongestSide)) {
        continue;
      }
      if (blankOnly && host.hasPreview(i)) continue;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = i;
      }
    }
    return best;
  }

  void cancelPreviews() {
    previewGeneration++;
    _previewIdleTimer?.cancel();
    _previewIdleTimer = null;
  }

  // --- command warm ------------------------------------------------------------

  /// Pages offered to the command/image warm in this document.
  final commandWarmAttempts = Set<PdfPage>.identity();
  int commandWarmGeneration = 0;
  int? commandWarmAnchor;

  /// The once-per-document heavy-tail warm has been offered.
  bool commandHeavyWarmStarted = false;

  /// Starts a command warm around [anchor]: the [radius] pages either side
  /// plus, once per document, the [heavyCount] heaviest pages. Returns the
  /// pass's generation and the pages in the order to offer them.
  ///
  /// The heavy tail goes first, processed cheapest to dearest: the
  /// speculative pool leaves a lane idle for foreground work, so
  /// shortest-job-first makes the most cold cliffs reusable in a short idle
  /// window, and one pathological stream cannot strand the rest. Forward
  /// neighbours come before reverse ones because reading advances.
  ({int generation, List<int> indices}) planCommandWarm(
    int anchor, {
    required int radius,
    required int heavyCount,
  }) {
    commandWarmAnchor = anchor;
    final generation = ++commandWarmGeneration;
    final pages = host.pages;
    final includeHeavy = heavyCount > 0 && !commandHeavyWarmStarted;
    if (includeHeavy) commandHeavyWarmStarted = true;
    final heavy = includeHeavy
        ? (<(int, int)>[
            for (var i = 0; i < pages.length; i++)
              if (i != anchor) (i, pages[i].rawContentLength),
          ]..sort((a, b) => b.$2.compareTo(a.$2)))
        : const <(int, int)>[];
    final selectedHeavy = heavy.take(math.max(0, heavyCount)).toList()
      ..sort((a, b) => a.$2.compareTo(b.$2));
    final indices = <int>{
      for (final entry in selectedHeavy) entry.$1,
      for (var distance = 1; distance <= radius; distance++)
        if (anchor + distance < pages.length) anchor + distance,
      for (var distance = 1; distance <= radius; distance++)
        if (anchor - distance >= 0) anchor - distance,
    }.toList(growable: false);
    return (generation: generation, indices: indices);
  }

  /// Gives an already-completed command warm a short chance to hand its
  /// platform replay to a genuinely idle frame. Readiness and scheduler
  /// release can straddle adjacent frames, so a one-shot check discarded
  /// useful warmed commands in that gap; a new anchor supersedes [generation]
  /// at once.
  Future<bool> waitForCommandWarmUiIdle(int generation) async {
    for (var frame = 0; frame < 16; frame++) {
      if (!host.mounted || generation != commandWarmGeneration) return false;
      if (commandWarmUiIdle) return true;
      await host.endOfFrame;
    }
    return host.mounted &&
        generation == commandWarmGeneration &&
        commandWarmUiIdle;
  }

  /// Stops any command warm in flight.
  void fenceCommandWarm() {
    commandWarmAnchor = null;
    commandWarmGeneration++;
  }

  // --- full and slow-scroll raster warm ----------------------------------------

  /// Pages the idle full-raster warm produced or gave up on. A page abandoned
  /// mid-warm because the viewer stopped being idle is removed again.
  final rasterWarmAttempts = Set<PdfPage>.identity();
  bool warmingRasters = false;
  Timer? _rasterWarmTimer;

  /// Pages offered to the accelerated slow-scroll look-ahead - separate, so a
  /// page the GPU declines in motion still gets the Canvas warm at idle.
  final slowScrollRasterWarmAttempts = Set<PdfPage>.identity();
  bool warmingSlowScrollRasters = false;
  int slowScrollDirection = 0;
  int slowScrollGeneration = 0;

  /// The look-ahead may describe at most this fraction of the exact-raster
  /// LRU (the nearest page always gets one chance).
  static const double slowScrollRasterBudgetFraction = 1 / 3;

  /// Worker priority for idle warm records: behind every visible page and the
  /// fast-scroll prefetch, the first thing the queue drops.
  static const rasterWarmWorkerPriority = 4;

  /// Restarts the idle countdown. Called whenever now is a bad time to warm -
  /// which is when the delay before the next attempt should begin again.
  void scheduleRasterWarm() {
    _rasterWarmTimer?.cancel();
    _rasterWarmTimer = null;
    final policy = host.rasterWarmPolicy;
    if (!host.mounted || !policy.enabled) return;
    if (!host.active || !host.pagePreviews) return;
    _rasterWarmTimer = Timer(policy.idleDelay, () {
      _rasterWarmTimer = null;
      if (host.mounted) warmFullRasters();
    });
  }

  /// Bakes exact rasters for pages the user has not visited, nearest first,
  /// one page per frame, while [rasterWarmIdle] holds (it is also the
  /// mid-render abort). Whatever it abandons is retried after the next
  /// settle.
  Future<void> warmFullRasters() async {
    if (warmingRasters || warmingSlowScrollRasters || !rasterWarmIdle) return;
    warmingRasters = true;
    try {
      while (rasterWarmIdle) {
        final pages = host.pages;
        final index = nextRasterWarmPage();
        if (index == null) return; // every eligible page covered (or attempted)
        final page = pages[index];
        final target = host.rasterWarmTarget(index);
        if (target == null) return; // no layout yet; the next settle retries
        rasterWarmAttempts.add(page);
        final stored = await host.warmFullRaster(
          index,
          target,
          priority: rasterWarmWorkerPriority,
          shouldStop: () => !rasterWarmIdle,
        );
        if (!host.mounted) return;
        if (!stored && !rasterWarmIdle) {
          // preempted rather than finished - retry after the settle
          rasterWarmAttempts.remove(page);
          return;
        }
        // breathe between pages (deliberately not a Timer, which would pend
        // in widget tests)
        await host.endOfFrame;
      }
    } finally {
      warmingRasters = false;
      startSlowScrollWarm();
    }
  }

  /// The next page worth warming: outside the live build window, inside the
  /// policy's reach, not attempted, and not already holding the exact raster
  /// it would produce. Nearest the current page first, so the pass re-aims
  /// itself whenever navigation moves.
  int? nextRasterWarmPage() {
    final policy = host.rasterWarmPolicy;
    final pages = host.pages;
    if (!policy.enabled || pages.isEmpty) return null;
    // nothing to size a raster against before layout
    final near = host.nearViewport();
    if (near == null) return null;
    final current = host.currentPage.clamp(0, pages.length - 1);
    final window =
        policy.mode == PdfPageRasterWarmMode.nearby ? policy.window : 0;
    int? best;
    var bestDistance = 1 << 30;
    for (var i = 0; i < pages.length; i++) {
      if (near(i)) continue;
      final distance = (i - current).abs();
      if (window > 0 && distance > window) continue;
      if (distance >= bestDistance) continue;
      if (rasterWarmAttempts.contains(pages[i])) continue;
      final target = host.rasterWarmTarget(i);
      if (target == null) continue;
      if (host.hasFullRaster(i, target.signature)) continue;
      // Admissibility is deliberately not filtered here: warmFullRaster
      // decides it and records the decision in its diagnostics.
      bestDistance = distance;
      best = i;
    }
    return best;
  }

  void setSlowScrollDirection(int direction) {
    final normalized = direction.sign;
    if (slowScrollDirection == normalized) return;
    slowScrollDirection = normalized;
    slowScrollGeneration++;
  }

  /// Whether the directional look-ahead may use spare accelerated capacity
  /// while slow scroll input is still arriving. Stricter than the visible
  /// page's slow lane: look-ahead is optional.
  bool slowScrollWarmAllowed(int generation, int direction) {
    final policy = host.rasterWarmPolicy;
    return host.mounted &&
        generation == slowScrollGeneration &&
        direction != 0 &&
        direction == slowScrollDirection &&
        host.active &&
        host.pagePreviews &&
        policy.enabled &&
        policy.slowScrollWindow > 0 &&
        host.slowScrollWarmCapable &&
        scheduler.slowMotion &&
        !scheduler.hasForegroundWork &&
        !previewUiMustDefer &&
        !host.deepZoom &&
        !host.toolArmed;
  }

  /// Starts the serial look-ahead; repeated calls coalesce on the running
  /// flag and the loop re-aims from the current page before every page.
  void startSlowScrollWarm() {
    if (warmingRasters || warmingSlowScrollRasters) return;
    final generation = slowScrollGeneration;
    final direction = slowScrollDirection;
    if (!slowScrollWarmAllowed(generation, direction)) return;
    unawaited(_warmSlowScrollRasters(generation, direction));
  }

  Future<void> _warmSlowScrollRasters(int generation, int direction) async {
    warmingSlowScrollRasters = true;
    try {
      while (slowScrollWarmAllowed(generation, direction)) {
        final pages = host.pages;
        final index = nextSlowScrollWarmPage(direction);
        if (index == null) return;
        final page = pages[index];
        final target = host.rasterWarmTarget(index);
        if (target == null) return;
        slowScrollRasterWarmAttempts.add(page);
        final stored = await host.warmFullRaster(
          index,
          target,
          // foreground pages are 0, fast-scroll previews 1; exact look-ahead
          // outranks the idle command/raster warms (3/4)
          priority: 2,
          shouldStop: () => !slowScrollWarmAllowed(generation, direction),
          acceleratedOnly: true,
        );
        if (!host.mounted) return;
        if (!stored && !slowScrollWarmAllowed(generation, direction)) {
          // preemption is temporary; a genuine GPU rejection stays attempted
          slowScrollRasterWarmAttempts.remove(page);
          return;
        }
        await host.endOfFrame;
      }
    } finally {
      warmingSlowScrollRasters = false;
    }
  }

  /// The nearest not-yet-visible page in the scroll [direction], within the
  /// policy's page cap and a byte window of the exact-raster cache.
  int? nextSlowScrollWarmPage(int direction) {
    final pages = host.pages;
    if (pages.isEmpty || direction == 0) return null;
    final policy = host.rasterWarmPolicy;
    var window = policy.slowScrollWindow;
    if (policy.mode == PdfPageRasterWarmMode.nearby) {
      window = math.min(window, policy.window);
    }
    if (window <= 0) return null;
    final totalBudget = host.maxFullRasterBytes;
    if (totalBudget <= 0) return null;
    final byteWindow = math.min(
      totalBudget,
      math.max(
        host.maxFullRasterEntryBytes,
        (totalBudget * slowScrollRasterBudgetFraction).floor(),
      ),
    );
    final current = host.currentPage.clamp(0, pages.length - 1);
    var plannedBytes = 0;
    for (var distance = 1; distance <= window; distance++) {
      final index = current + direction * distance;
      if (index < 0 || index >= pages.length) break;
      if (host.onScreen(index)) continue;
      final target = host.rasterWarmTarget(index);
      if (target == null) continue;
      final nextBytes = plannedBytes + target.signature.bytes;
      if (plannedBytes > 0 && nextBytes > byteWindow) break;
      plannedBytes = nextBytes;
      if (slowScrollRasterWarmAttempts.contains(pages[index])) continue;
      if (host.hasFullRaster(index, target.signature)) continue;
      return index;
    }
    return null;
  }

  // --- visible-page text warm --------------------------------------------------

  /// How long the viewport must stay quiet before the text walk.
  static const textWarmIdleDelay = Duration(milliseconds: 500);

  /// The page last offered to the text warm.
  WeakReference<PdfPage>? textWarmAttempt;
  bool textWarmRunning = false;
  Timer? _textWarmTimer;

  void cancelTextWarm() {
    _textWarmTimer?.cancel();
    _textWarmTimer = null;
  }

  void scheduleTextWarm() {
    cancelTextWarm();
    if (textWarmRunning || !textWarmIdle || !host.textWarmWanted) return;
    _textWarmTimer = Timer(textWarmIdleDelay, () {
      _textWarmTimer = null;
      if (textWarmIdle) unawaited(_runTextWarm());
    });
  }

  Future<void> _runTextWarm() async {
    if (textWarmRunning || !textWarmIdle) return;
    final run = host.runTextWarm();
    if (run == null) return;
    textWarmRunning = true;
    try {
      await run;
    } finally {
      textWarmRunning = false;
      // navigation or a revision may have moved the focused page meanwhile;
      // only the latest page gets the next turn
      if (host.mounted) scheduleTextWarm();
    }
  }

  // --- tile backend warm-up ----------------------------------------------------

  /// How long the scheduler must stay idle before a driver-compilation pass.
  static const tileWarmUpIdleDelay = Duration(milliseconds: 750);

  PdfTileRasterBackend? _pendingTileWarmUp;
  bool _tileWarmUpFramePending = false;
  Timer? _tileWarmUpTimer;

  /// A tile backend warm-up is waiting for idle.
  bool get tileWarmUpPending => _pendingTileWarmUp != null;

  void scheduleTileWarmUp() {
    final backend = host.tileBackend;
    if (!host.active || !backend.supportsWarmUp) {
      _cancelTileWarmUp();
      return;
    }
    if (!identical(_pendingTileWarmUp, backend)) {
      _tileWarmUpTimer?.cancel();
      _tileWarmUpTimer = null;
    }
    _pendingTileWarmUp = backend;
    _armTileWarmUp();
  }

  void _cancelTileWarmUp() {
    _pendingTileWarmUp = null;
    _tileWarmUpTimer?.cancel();
    _tileWarmUpTimer = null;
  }

  void _armTileWarmUp() {
    if (_tileWarmUpFramePending) return;
    _tileWarmUpFramePending = true;
    host.postFrame(() {
      _tileWarmUpFramePending = false;
      final backend = _pendingTileWarmUp;
      if (!host.mounted || backend == null || !host.active) return;
      if (!identical(host.tileBackend, backend)) {
        scheduleTileWarmUp();
        return;
      }
      // First frame is not first useful pixels: let the focused page finish
      // before a driver compile enters the GPU queue; the scheduler's idle
      // edge re-arms this.
      if (scheduler.busy) return;
      _tileWarmUpTimer ??= Timer(tileWarmUpIdleDelay, () {
        _tileWarmUpTimer = null;
        if (!host.mounted ||
            !host.active ||
            !identical(host.tileBackend, backend) ||
            !identical(_pendingTileWarmUp, backend)) {
          return;
        }
        if (scheduler.busy) return;
        _pendingTileWarmUp = null;
        unawaited(backend.warmUp().catchError((Object error) {
          // Acceleration is optional: createSession's Canvas fallback stays in
          // charge of the first tile.
          PdfPerfLog.log('tile backend warm-up failed '
              'backend=${backend.debugLabel} error=$error');
        }));
      });
    });
  }

  // --- events -------------------------------------------------------------------

  /// The scheduler's busy state may have moved: re-arm what waits for idle.
  void schedulerActivity() {
    scheduleRasterWarm();
    scheduleTextWarm();
    if (scheduler.busy) {
      _tileWarmUpTimer?.cancel();
      _tileWarmUpTimer = null;
    } else {
      startSlowScrollWarm();
      schedulePreviews();
      if (_pendingTileWarmUp != null) _armTileWarmUp();
    }
  }

  /// The page set moved ([PdfPageSetChange]): drop the attempts its
  /// invalidation names, fence the command warm, and re-arm the preview and
  /// raster lanes.
  void invalidate(PdfPageSetChange change) {
    final warmPages = change.invalidation.warmPages;
    if (warmPages == null) {
      previewAttempts.clear();
      previewVectorAttempts.clear();
      intermediatePreviewAttempts.clear();
      rasterWarmAttempts.clear();
      slowScrollRasterWarmAttempts.clear();
      slowScrollGeneration++;
      commandWarmAttempts.clear();
      commandHeavyWarmStarted = false;
    } else {
      for (final index in warmPages) {
        final oldPage = change.previous.pages[index];
        previewAttempts.remove(oldPage);
        previewVectorAttempts.remove(oldPage);
        for (final attempted in intermediatePreviewAttempts.values) {
          attempted.remove(oldPage);
        }
        rasterWarmAttempts.remove(oldPage);
        slowScrollRasterWarmAttempts.remove(oldPage);
        commandWarmAttempts.remove(oldPage);
      }
    }
    fenceCommandWarm();
    schedulePreviews();
    scheduleRasterWarm();
  }

  /// The exact-raster cache policy changed. Only a raised budget can admit
  /// pages the warm declined, so only then is the document re-offered (an
  /// adaptive host re-prices every few seconds, usually downward).
  void rasterCachePolicyChanged({required bool raised}) {
    if (raised) {
      rasterWarmAttempts.clear();
      slowScrollRasterWarmAttempts.clear();
    }
    scheduleRasterWarm();
  }

  void rasterWarmPolicyChanged() {
    rasterWarmAttempts.clear();
    slowScrollRasterWarmAttempts.clear();
    slowScrollGeneration++;
    scheduleRasterWarm();
  }

  void previewPolicyChanged() {
    if (host.pagePreviews && host.active) {
      schedulePreviews();
    } else {
      cancelPreviews();
    }
  }

  /// The preview LoD ladder changed: every intermediate rung may be owed.
  void previewLodPolicyChanged() {
    intermediatePreviewAttempts.clear();
    host.postFrame(() {
      if (host.mounted) host.runPreviewPass();
    });
  }

  void tileBackendChanged() {
    slowScrollRasterWarmAttempts.clear();
    slowScrollGeneration++;
    scheduleTileWarmUp();
  }

  /// The viewer was paused under another view or came back to the
  /// foreground.
  void activeChanged() {
    scheduler.parked = !host.active;
    if (!host.active) {
      setSlowScrollDirection(0);
      _cancelTileWarmUp();
      fenceCommandWarm();
      cancelPreviews();
      scheduler.holding = true;
    } else {
      scheduler.holding = false;
      schedulePreviews();
      scheduleTileWarmUp();
    }
    // a parked viewer does no background full-raster work; a foregrounded
    // one restarts its idle countdown
    scheduleRasterWarm();
  }

  /// The platform is short of memory and the previews were dropped: every
  /// preview and command warm may be offered again.
  void memoryPressure() {
    commandWarmAttempts.clear();
    commandHeavyWarmStarted = false;
    fenceCommandWarm();
    previewAttempts.clear();
    previewVectorAttempts.clear();
    intermediatePreviewAttempts.clear();
    slowScrollRasterWarmAttempts.clear();
    setSlowScrollDirection(0);
  }

  /// Performance policy moved: re-arm the preview and raster lanes.
  void performanceChanged() {
    schedulePreviews();
    scheduleRasterWarm();
  }

  void dispose() {
    commandWarmGeneration++;
    slowScrollGeneration++;
    cancelTextWarm();
    cancelPreviews();
    _motionHoldReleaseTimer?.cancel();
    _gestureQuietTimer?.cancel();
    _rasterWarmTimer?.cancel();
    _tileWarmUpTimer?.cancel();
  }
}
