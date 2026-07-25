import 'dart:async';

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
/// viewport ([focus]) first, and never while a fast scroll is in flight
/// ([holding]) - so no frame runs more than one page's walk and the
/// low-res previews cover everything still waiting its turn.
///
/// A grant is only the *start* of a render: on the worker path the
/// callback returns at its first await and the recording finishes
/// hundreds of milliseconds later. The scheduler tracks that window (see
/// [_inFlight]) so a rebuild arriving inside it queues behind the pass
/// already running rather than racing a second one against it.
class PdfPageRenderScheduler {
  PdfPageRenderScheduler();

  final _pending = <_RenderRequest>[];

  /// Tokens whose render has been granted but has not finished. Deduping
  /// only against [_pending] was not enough: the grant removes the
  /// request, so a re-request landing mid-render found an empty queue and
  /// started a second concurrent pass for the same page. Both passes
  /// recorded the page in full and the older one's result was then thrown
  /// away by the page's own generation guard - a whole wasted record, and
  /// the reason the device trace showed every focus page granted twice
  /// and 3-5 records produced per page.
  final _inFlight = <Object, _RenderRequest?>{};

  bool _holding = false;
  int _focus = 0;
  bool _draining = false;
  bool _disposed = false;
  final _activity = _Activity();

  /// Notifies whenever [busy] may have changed - a hold raised or lowered, a
  /// request queued, the queue drained. Background work that must not compete
  /// with the viewer for the platform thread (the thumbnail warm) listens here
  /// to know when to stand down and when to resume, instead of polling frames.
  Listenable get activity => _activity;

  /// Whether the viewer still has foreground page work in flight: a scroll is
  /// holding renders back, or pages are queued for their first interpret.
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
  bool get busy => !_parked && (_holding || _pending.isNotEmpty);

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
    PdfPerfLog.log('renderHold ${_holding ? 'ON' : 'off'} '
        '(pending=${_pending.length} focus=$_focus)');
    if (!_holding) _scheduleDrain();
    _activity.ping();
  }

  /// The page index nearest the viewport. Pending requests closest to it
  /// drain first, so what the user is looking at sharpens before
  /// off-screen neighbours.
  set focus(int index) => _focus = index;

  /// Whether any page is still waiting for its first interpret. The
  /// background preview prerender yields while this is true, so the two
  /// can't both walk a page in the same frame.
  bool get hasPending => _pending.isNotEmpty;

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
  void request(Object token, int priority, FutureOr<void> Function() render) {
    if (_disposed) return;
    final queued = _RenderRequest(token, priority, render);
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
          ..render = render;
        _scheduleDrain();
        return;
      }
    }
    _pending.add(queued);
    _scheduleDrain();
    _activity.ping();
  }

  /// Withdraws [token]'s pending request - its page rendered another way,
  /// or was disposed before its turn. Also drops any re-request queued
  /// behind a render still in flight, so a page recycled onto another
  /// index does not get granted again when that render lands.
  void cancel(Object token) {
    final before = _pending.length;
    _pending.removeWhere((r) => identical(r.token, token));
    if (_inFlight.containsKey(token)) _inFlight[token] = null;
    if (_pending.length != before) _activity.ping();
  }

  void _scheduleDrain() {
    if (_draining || _holding || _disposed || _pending.isEmpty) return;
    _draining = true;
    // off the current build/layout stack (request fires from layout) and
    // off the synchronous gesture turn, so the first grant lands after
    // this frame rather than blocking it
    scheduleMicrotask(_drain);
  }

  Future<void> _drain() async {
    try {
      while (!_disposed && !_holding && _pending.isNotEmpty) {
        // the pending request nearest the viewport focus
        var pick = 0;
        var best = (_pending[0].priority - _focus).abs();
        for (var i = 1; i < _pending.length; i++) {
          final distance = (_pending[i].priority - _focus).abs();
          if (distance < best) {
            best = distance;
            pick = i;
          }
        }
        final next = _pending.removeAt(pick);
        PdfPerfLog.log('scheduler grant page=${next.priority} '
            'focus=$_focus remaining=${_pending.length}');
        _inFlight[next.token] = null;
        try {
          // starts one page render this frame; the callback returns at its
          // first await, so this does not block the pacing below
          final running = next.render();
          if (running is Future<void>) {
            // deliberately not awaited: three workers must stay busy while
            // this page records. Only the token's own re-request waits.
            running.then(
              (_) => _settle(next.token),
              onError: (_) => _settle(next.token),
            );
          } else {
            _settle(next.token);
          }
        } catch (_) {
          // a page that throws mid-walk must not strand the rest of the
          // queue - it simply keeps its preview/placeholder
          _settle(next.token);
        }
        // let the engine breathe before the next walk: paint the frame
        // this produced, service input, run animations. endOfFrame
        // schedules a frame when idle so the drain can't stall;
        // deliberately not a Timer (those pend in widget tests).
        await SchedulerBinding.instance.endOfFrame;
      }
    } finally {
      _draining = false;
      _activity.ping();
    }
  }

  /// [token]'s render has finished (or failed). Releases it and grants
  /// the re-request that arrived while it was running, if any.
  void _settle(Object token) {
    final queued = _inFlight.remove(token);
    if (queued == null || _disposed) return;
    _pending.add(queued);
    _scheduleDrain();
    // re-queueing makes the viewer busy again (#603) - the thumbnail warm
    // must stand down for it, exactly as it would for a fresh request
    _activity.ping();
  }

  /// Drops all pending requests and stops granting. Safe to call more
  /// than once.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _pending.clear();
    _inFlight.clear();
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
  _RenderRequest(this.token, this.priority, this.render);
  final Object token;
  int priority;
  FutureOr<void> Function() render;
}
