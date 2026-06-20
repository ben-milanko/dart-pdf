import 'dart:async';

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
/// interpreted in the same event-loop turn — N heavy walks back to back,
/// a multi-hundred-millisecond frozen frame (the iPad fast-scroll hang).
///
/// Pages register a [request] here instead of interpreting on their own.
/// The scheduler grants requests one per frame, the one nearest the
/// viewport ([focus]) first, and never while a fast scroll is in flight
/// ([holding]) — so no frame runs more than one page's walk and the
/// low-res previews cover everything still waiting its turn.
class PdfPageRenderScheduler {
  PdfPageRenderScheduler();

  final _pending = <_RenderRequest>[];
  bool _holding = false;
  int _focus = 0;
  bool _draining = false;
  bool _disposed = false;

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
  /// just refreshes it — the page is interpreted at most once.
  void request(Object token, int priority, VoidCallback render) {
    if (_disposed) return;
    for (final r in _pending) {
      if (identical(r.token, token)) {
        r
          ..priority = priority
          ..render = render;
        _scheduleDrain();
        return;
      }
    }
    _pending.add(_RenderRequest(token, priority, render));
    _scheduleDrain();
  }

  /// Withdraws [token]'s pending request — its page rendered another way,
  /// or was disposed before its turn.
  void cancel(Object token) {
    _pending.removeWhere((r) => identical(r.token, token));
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
        try {
          next.render(); // one synchronous interpret this frame
        } catch (_) {
          // a page that throws mid-walk must not strand the rest of the
          // queue — it simply keeps its preview/placeholder
        }
        // let the engine breathe before the next walk: paint the frame
        // this produced, service input, run animations. endOfFrame
        // schedules a frame when idle so the drain can't stall;
        // deliberately not a Timer (those pend in widget tests).
        await SchedulerBinding.instance.endOfFrame;
      }
    } finally {
      _draining = false;
    }
  }

  /// Drops all pending requests and stops granting. Safe to call more
  /// than once.
  void dispose() {
    _disposed = true;
    _pending.clear();
  }
}

class _RenderRequest {
  _RenderRequest(this.token, this.priority, this.render);
  final Object token;
  int priority;
  VoidCallback render;
}
