import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'perf_log.dart';

/// Paces the first interpretation of PDF pages so a single frame never
/// runs more than one synchronous content-stream walk.
///
/// Interpreting a page (the walk behind `PdfPageRenderer.renderPicture`)
/// runs on the UI thread, and on heavy pages takes long enough to drop
/// frames. The viewer holds those walks back during a fast scroll; the
/// trap was the *release*. Every page in the cache window deferred
/// against one shared flag, so when scrolling settled they all
/// interpreted in the same event-loop turn - N heavy walks back to back,
/// a multi-hundred-millisecond frozen frame (the iPad fast-scroll hang).
///
/// Pages register a [request] here instead of interpreting on their own.
/// The scheduler grants requests one per frame, the one nearest the
/// viewport ([focus]) first, and - unless the request is [motionSafe], see
/// below - not while a fast scroll is in flight ([holding]), so no frame runs
/// more than one page's walk and the low-res previews cover everything still
/// waiting its turn.
///
/// A render grant is only the *start* of a render: on the worker path the
/// callback returns at its first await and the recording finishes
/// hundreds of milliseconds later. The scheduler tracks that window (see
/// [_inFlight]) so a rebuild arriving inside it queues behind the pass
/// already running rather than racing a second one against it.
///
/// Worker replies have their own [paceUiWork] gate. Keeping several workers
/// busy is valuable, but replaying all of their returned command buffers in
/// the same UI frame is not; that gate separates the completion-side work
/// without serializing the records themselves.
///
/// ## The motion-safe lane
///
/// All of the above is priced for the page that made it necessary: a dense
/// vector sheet whose interpret walk is 100-400 ms of UI thread. Most pages
/// are nothing like that, and two facts about them make the blanket hold pure
/// latency:
///
/// - With a render worker attached, the walk does not run here at all. STARTING
///   a page's record during a scroll costs the frame nothing.
/// - What does run here is the replay of the returned command buffer, and by
///   then its size is *known* - no guessing needed.
///
/// So a request may declare itself [motionSafe], and the caller re-declares it
/// at [paceUiWork] once the record's real size is in hand
/// (`PdfPageView.motionSafeMaxCommands`). Motion-safe work is granted **during**
/// a hold - one per frame, and only near the scroll's destination
/// ([motionSafeHoldRadius], so a fling does not record every page it passes) -
/// and several may start in one frame once the scroll settles. Everything else
/// keeps exactly the old behaviour - held, then one per frame - because those
/// are the pages the pacing exists for.
///
/// On a long text document that is the difference between arriving on a page
/// and waiting out the scroll before the render even starts (~600 ms to
/// readable) and rendering through the scroll (the record lands about when the
/// animation does).
class PdfPageRenderScheduler {
  PdfPageRenderScheduler();

  /// Motion-safe first renders started in a single frame while the viewer is
  /// NOT holding. Their walk is off-thread and their records overlap, so
  /// filling the cache window takes a few frames instead of one frame per
  /// page.
  static int motionSafeGrantsPerFrame = 3;

  /// Motion-safe first renders started in a single frame while a scroll
  /// [holding] is in flight. One: the record itself is off-thread, but its
  /// reply still replays here, and a fling must not queue those faster than
  /// the [paceUiWork] gate releases them.
  static int motionSafeGrantsWhileHolding = 1;

  /// How far from [focus] a motion-safe first render may be granted while a
  /// scroll is in flight.
  ///
  /// The pages streaming past during a fling are not the pages the reader is
  /// navigating to. Recording all of them fills the worker, the transcript
  /// caches and the heap with pages nobody stopped on: measured on a 16-sheet
  /// plan set, an unbounded lane recorded every sheet it flew past for +34%
  /// tab memory and +21% median frame build, while the arrival latency it
  /// bought was all on the destination. One page either side of the
  /// destination is what pays - and a jump sets [focus] to its target before
  /// the animation starts, so that IS the destination, not where the scroll
  /// happens to be passing.
  static int motionSafeHoldRadius = 1;

  final _pending = <_RenderRequest>[];

  /// Worker records finish independently, so records started one-per-frame can
  /// still return together and replay several command buffers in one build
  /// frame. This second queue paces those platform-thread completions while
  /// leaving all workers busy in parallel.
  final _uiPending = <_UiWorkRequest>[];
  int? _uiFrameCallbackId;

  /// Tokens whose render has been granted but has not finished. Deduping
  /// only against [_pending] was not enough: the grant removes the
  /// request, so a re-request landing mid-render found an empty queue and
  /// started a second concurrent pass for the same page. Both passes
  /// recorded the page in full and the older one's result was then thrown
  /// away by the page's own generation guard - a whole wasted record, and
  /// the reason the device trace showed every focus page granted twice
  /// and 3-5 records produced per page.
  final _inFlight = <Object, _RenderRequest?>{};

  /// Page index for each active token. While the current focus page is in
  /// flight, neighbouring first renders stay pending: their worker replies
  /// deserialize and replay on the same UI thread, so filling every worker one
  /// frame after the focused request can delay the pixels the user asked for
  /// by hundreds of milliseconds. Once focus lands, ordinary background
  /// concurrency resumes unchanged.
  final _activePriorities = <Object, int>{};

  /// Whether each active token's render was granted through the motion-safe
  /// lane. Only a *held-class* focus render parks the rest of the queue.
  final _activeMotionSafe = <Object, bool>{};

  bool _holding = false;
  int _focus = 0;
  int? _renderFrameCallbackId;
  bool _disposed = false;
  final _activity = _Activity();

  /// Notifies whenever [busy] may have changed - a hold raised or lowered, a
  /// request queued, the queue drained. Background work that must not compete
  /// with the viewer for the platform thread (the thumbnail warm) listens here
  /// to know when to stand down and when to resume, instead of polling frames.
  Listenable get activity => _activity;

  /// Whether the viewer still has foreground page work in flight: a scroll is
  /// holding renders back, pages are queued for their first interpret, or a
  /// granted page is still replaying/rasterizing.
  ///
  /// This is the *platform-thread* gate. The render worker's own priorities
  /// order the isolate's queue, but the picture build and rasterization that
  /// follow every record run here, on the one thread the visible page's build
  /// also needs - so a background pass that only lowers its worker priority
  /// still lands its replay on top of a foreground frame (#603).
  ///
  /// A [parked] viewer reads idle however much it has queued: it is overlaid
  /// by another view and will not render any of it, so it is not competing for
  /// anything. Without that the full-area page grid - which parks the viewer
  /// it covers - would gate its own thumbnails behind a hold that never lifts.
  bool get busy =>
      !_parked && (_holding || _pending.isNotEmpty || _inFlight.isNotEmpty);

  bool _parked = false;

  /// True while the viewer is overlaid by another view and renders nothing
  /// (`PdfViewer.active` false). Distinct from [holding], which is a *live*
  /// viewer deferring work it still intends to do.
  bool get parked => _parked;
  set parked(bool value) {
    if (_parked == value || _disposed) return;
    _parked = value;
    _activity.ping();
  }

  /// True while a fast scroll is in flight: the viewer raises it from its
  /// velocity estimate. No request is granted while held; lowering it
  /// drains the queue.
  bool get holding => _holding;
  set holding(bool value) {
    if (_holding == value || _disposed) return;
    _holding = value;
    // inFlight is reported alongside pending because [busy] is the sum of the
    // two (plus the hold), and background work - the thumbnail warm - stands
    // down for exactly as long as it reads true. A trace showing `renderHold
    // off (pending=0)` followed by silence gives no way to tell an idle viewer
    // from one whose in-flight set never drained; with this it does.
    PdfPerfLog.log('renderHold ${_holding ? 'ON' : 'off'} '
        '(pending=${_pending.length} inFlight=${_inFlight.length} '
        'uiPending=${_uiPending.length} focus=$_focus)');
    if (!_holding) _scheduleDrain();
    if (!_holding) _scheduleUiDrain();
    _activity.ping();
  }

  /// The page index nearest the viewport. Pending requests closest to it
  /// drain first, so what the user is looking at sharpens before
  /// off-screen neighbours.
  set focus(int index) {
    if (_focus == index || _disposed) return;
    _focus = index;
    // The drain deliberately parks neighbouring requests while the focused
    // page is in flight. If navigation moves the focus in that window, the
    // old drain has already returned and no request will settle just because
    // the focus changed. Re-arm it so the new visible page is granted now,
    // rather than waiting for the previous page's worker/replay to finish.
    _scheduleDrain();
  }

  /// Whether any page is still waiting for its first interpret. The
  /// background preview prerender yields while this is true, so the two
  /// can't both walk a page in the same frame.
  bool get hasPending => _pending.isNotEmpty;

  /// Whether [token] already has a render queued or running here.
  ///
  /// A page that is visible with nothing to paint re-asks on every rebuild
  /// (that is how a page scrolled into view gets queued at all - see
  /// `PdfPageView`). Without this the ask would also land while its own render
  /// was in flight, and the scheduler would faithfully queue a second pass
  /// behind the first for a page that is simply not finished yet.
  bool isQueued(Object token) =>
      _inFlight.containsKey(token) ||
      _pending.any((r) => identical(r.token, token));

  /// Registers (or refreshes) [token]'s request to run its first
  /// interpret. [render] is invoked on the UI thread when the request's
  /// turn comes; [priority] is the page index, ranked against [focus].
  /// Calling again for the same [token] (a re-layout before the grant)
  /// just refreshes it - the page is interpreted at most once.
  ///
  /// If [render] returns a future the scheduler treats the page as busy
  /// until it settles: a re-request in that window is held back and
  /// granted once, after the running pass finishes. It is not dropped -
  /// the rebuild that asked may carry a new scale or revision - but by
  /// then the page has its picture, so the deferred pass re-rasters
  /// instead of recording the page from scratch a second time.
  ///
  /// [motionSafe] marks a render that may run during a scroll (see the
  /// motion-safe lane above). It is a property of the *pass*, so a re-request
  /// may correct it - the refresh below carries it across.
  void request(
    Object token,
    int priority,
    FutureOr<void> Function() render, {
    bool motionSafe = false,
  }) {
    if (_disposed) return;
    final queued =
        _RenderRequest(token, priority, render, motionSafe: motionSafe);
    if (_inFlight.containsKey(token)) {
      PdfPerfLog.log('scheduler defer page=$priority '
          '(render in flight)${_inFlight[token] == null ? '' : ' [repeat]'}');
      _inFlight[token] = queued;
      return;
    }
    for (final r in _pending) {
      if (identical(r.token, token)) {
        r
          ..priority = priority
          ..render = render
          ..motionSafe = motionSafe;
        _scheduleDrain();
        return;
      }
    }
    _pending.add(queued);
    _scheduleDrain();
    _activity.ping();
  }

  /// Waits for this worker result's platform-thread replay turn.
  ///
  /// Page records are deliberately allowed to run concurrently in workers,
  /// but their returned command buffers are decoded/replayed on Flutter's UI
  /// isolate. Several workers finishing together used to put all of those
  /// builds in one frame. This grants one completion per frame, nearest
  /// [focus] first, and waits through a fast-scroll [holding] interval.
  /// Returns false when [token] was cancelled or the scheduler was disposed.
  Future<bool> paceUiWork(
    Object token,
    int priority, {
    bool replacePending = false,
    bool motionSafe = false,
  }) {
    if (_disposed) return Future<bool>.value(false);
    // Progressive worker replies are cumulative snapshots. If five prefixes
    // arrive while this page is waiting for its UI replay turn, only the fifth
    // can improve the pixels: replaying all five builds five successively
    // larger pictures and transient rasters, then immediately discards four.
    // Let the caller mark those results replaceable so a page owns at most one
    // pending completion. The already-granted result remains uncancellable,
    // but the queue behind it collapses to the newest snapshot (or final
    // worker result).
    if (replacePending) {
      for (final pending
          in _uiPending.where((r) => identical(r.token, token)).toList()) {
        _uiPending.remove(pending);
        if (!pending.ready.isCompleted) pending.ready.complete(false);
      }
    }
    final request = _UiWorkRequest(token, priority, motionSafe: motionSafe);
    _uiPending.add(request);
    _scheduleUiDrain();
    return request.ready.future;
  }

  /// Withdraws [token]'s pending request - its page rendered another way,
  /// or was disposed before its turn. Also drops any re-request queued
  /// behind a render still in flight, so a page recycled onto another
  /// index does not get granted again when that render lands.
  void cancel(Object token) {
    final before = _pending.length;
    _pending.removeWhere((r) => identical(r.token, token));
    for (final request
        in _uiPending.where((r) => identical(r.token, token)).toList()) {
      _uiPending.remove(request);
      if (!request.ready.isCompleted) request.ready.complete(false);
    }
    if (_inFlight.containsKey(token)) _inFlight[token] = null;
    if (_pending.length != before) _activity.ping();
  }

  void _scheduleDrain() {
    if (_renderFrameCallbackId != null || _disposed || _pending.isEmpty) return;
    // A hold no longer silences the drain outright: motion-safe requests near
    // the destination are granted through it (one per frame). With none
    // queued this is the old early return.
    if (_holding &&
        !_pending.any((r) =>
            r.motionSafe &&
            (r.priority - _focus).abs() <= math.max(0, motionSafeHoldRadius))) {
      return;
    }
    // request() commonly fires from layout. A transient frame callback gets
    // the walk off that stack and gives the same hard one-grant-per-engine-
    // frame guarantee as the worker-completion queue below.
    _renderFrameCallbackId = SchedulerBinding.instance.scheduleFrameCallback(
      _grantNextRender,
    );
  }

  void _grantNextRender(Duration _) {
    _renderFrameCallbackId = null;
    if (_disposed || _pending.isEmpty) return;
    // Keep the focused page's first visual ahead of neighbouring first
    // renders. Once it settles, the normal one-grant-per-frame pool fill
    // resumes and keeps all available workers productive. A motion-safe focus
    // page does not earn that protection: its record is a worker round trip
    // that costs this thread nothing, and stalling the whole queue behind it
    // is latency for no gain.
    if (_focusRenderIsHeavyInFlight()) return;
    final budget = _holding
        ? math.max(0, motionSafeGrantsWhileHolding)
        : math.max(1, motionSafeGrantsPerFrame);
    for (var granted = 0; granted < budget; granted++) {
      if (_disposed || _pending.isEmpty) return;
      final pick = _pickNearestFocus(
        _pending,
        motionSafeOnly: _holding,
        maxDistance: _holding ? math.max(0, motionSafeHoldRadius) : null,
      );
      if (pick == null) return;
      final next = _pending.removeAt(pick);
      _grant(next);
      // Held-class pages keep the historical one-per-frame guarantee: their
      // walk or replay is the frame. Only the motion-safe lane may start
      // another.
      if (!next.motionSafe) return;
    }
  }

  /// True while the page the user is looking at owns a held-class render that
  /// has not settled. See [_grantNextRender].
  bool _focusRenderIsHeavyInFlight() {
    for (final entry in _activePriorities.entries) {
      if (entry.value == _focus && !(_activeMotionSafe[entry.key] ?? false)) {
        return true;
      }
    }
    return false;
  }

  /// Index of the queued request nearest [focus], or null when none qualifies.
  /// With [motionSafeOnly] set (a hold in flight) only motion-safe requests
  /// qualify, and [maxDistance] bounds how far from the focus they may be.
  int? _pickNearestFocus(
    List<_RenderRequest> queue, {
    bool motionSafeOnly = false,
    int? maxDistance,
  }) {
    int? pick;
    var best = 0;
    for (var i = 0; i < queue.length; i++) {
      if (motionSafeOnly && !queue[i].motionSafe) continue;
      final distance = (queue[i].priority - _focus).abs();
      if (maxDistance != null && distance > maxDistance) continue;
      if (pick == null || distance < best) {
        best = distance;
        pick = i;
      }
    }
    return pick;
  }

  void _grant(_RenderRequest next) {
    PdfPerfLog.log('scheduler grant page=${next.priority} '
        'focus=$_focus cost=${next.motionSafe ? 'motion-safe' : 'held'} '
        'hold=${_holding ? 'ON' : 'off'} remaining=${_pending.length}');
    _inFlight[next.token] = null;
    _activePriorities[next.token] = next.priority;
    _activeMotionSafe[next.token] = next.motionSafe;
    // A granted async render has left the pending queue but still owns the
    // platform thread for its replay/raster phase. Background thumbnail work
    // must keep treating the viewer as busy through that window.
    _activity.ping();
    try {
      // Start the record without awaiting it so several workers remain busy.
      // Only another *grant* waits for the following engine frame.
      final running = next.render();
      if (running is Future<void>) {
        running.then(
          (_) => _settle(next.token),
          onError: (_) => _settle(next.token),
        );
      } else {
        _settle(next.token);
      }
    } catch (_) {
      // A page that throws mid-walk must not strand the rest of the queue - it
      // simply keeps its preview/placeholder.
      _settle(next.token);
    }
    _scheduleDrain();
  }

  void _scheduleUiDrain() {
    if (_uiFrameCallbackId != null || _disposed || _uiPending.isEmpty) return;
    // As in [_scheduleDrain]: a small record replays through the hold rather
    // than waiting the scroll out. Its size is what made it motion-safe.
    if (_holding && !_uiPending.any((r) => r.motionSafe)) return;
    // `endOfFrame` can already be complete when a continuation reaches it in
    // the post-frame turn. A while-loop awaiting it therefore occasionally
    // released several worker results only 1-2ms apart inside the same display
    // frame. A transient callback is an actual next-frame boundary: exactly
    // one result is granted by each engine frame, regardless of when the
    // previous result's future resumed.
    _uiFrameCallbackId = SchedulerBinding.instance.scheduleFrameCallback(
      _grantNextUiWork,
    );
  }

  void _grantNextUiWork(Duration _) {
    _uiFrameCallbackId = null;
    if (_disposed || _uiPending.isEmpty) return;
    int? pick;
    var best = 0;
    for (var i = 0; i < _uiPending.length; i++) {
      if (_holding && !_uiPending[i].motionSafe) continue;
      final distance = (_uiPending[i].priority - _focus).abs();
      if (pick == null || distance < best) {
        best = distance;
        pick = i;
      }
    }
    if (pick == null) return;
    final next = _uiPending.removeAt(pick);
    PdfPerfLog.log('scheduler ui grant page=${next.priority} '
        'focus=$_focus cost=${next.motionSafe ? 'motion-safe' : 'held'} '
        'remaining=${_uiPending.length}');
    if (!next.ready.isCompleted) next.ready.complete(true);
    // Schedule the following result for the following engine frame before the
    // resumed future starts its replay. Enqueues during that replay see this
    // callback and cannot accidentally schedule a second grant in the frame.
    _scheduleUiDrain();
  }

  /// [token]'s render has finished (or failed). Releases it and grants
  /// the re-request that arrived while it was running, if any.
  void _settle(Object token) {
    final queued = _inFlight.remove(token);
    _activePriorities.remove(token);
    _activeMotionSafe.remove(token);
    if (_disposed) return;
    if (queued != null) {
      _pending.add(queued);
    }
    _scheduleDrain();
    // Finishing the last in-flight render may make the viewer idle; if a
    // repeat was queued it remains busy. Either transition must wake the
    // foreground gate so thumbnail work can re-read [busy].
    _activity.ping();
  }

  /// Drops all pending requests and stops granting. Safe to call more
  /// than once.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final renderFrameCallbackId = _renderFrameCallbackId;
    if (renderFrameCallbackId != null) {
      SchedulerBinding.instance
          .cancelFrameCallbackWithId(renderFrameCallbackId);
      _renderFrameCallbackId = null;
    }
    final uiFrameCallbackId = _uiFrameCallbackId;
    if (uiFrameCallbackId != null) {
      SchedulerBinding.instance.cancelFrameCallbackWithId(uiFrameCallbackId);
      _uiFrameCallbackId = null;
    }
    _pending.clear();
    for (final request in _uiPending) {
      if (!request.ready.isCompleted) request.ready.complete(false);
    }
    _uiPending.clear();
    _inFlight.clear();
    _activePriorities.clear();
    _activeMotionSafe.clear();
    _activity.ping();
    _activity.dispose();
  }
}

/// A bare [Listenable] the scheduler pings when [PdfPageRenderScheduler.busy]
/// may have moved. Deliberately not a value notifier: listeners re-read [busy]
/// themselves, so a redundant ping is harmless and no state can go stale.
class _Activity extends ChangeNotifier {
  void ping() {
    if (!_alive) return;
    notifyListeners();
  }

  bool _alive = true;

  @override
  void dispose() {
    _alive = false;
    super.dispose();
  }
}

class _RenderRequest {
  _RenderRequest(this.token, this.priority, this.render,
      {this.motionSafe = false});
  final Object token;
  int priority;
  FutureOr<void> Function() render;
  bool motionSafe;
}

class _UiWorkRequest {
  _UiWorkRequest(this.token, this.priority, {this.motionSafe = false});

  final Object token;
  final int priority;
  final bool motionSafe;
  final Completer<bool> ready = Completer<bool>();
}
