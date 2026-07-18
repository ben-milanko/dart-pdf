/// The model half of the in-app developer tools: a process-wide singleton that
/// captures logs ([debugPrint] + [FlutterError.onError]), samples frame
/// timings, and exposes the toggles the panel flips (performance overlay).
///
/// [AppDevTools.install] is idempotent and cheap; the capture hooks chain to
/// the previous handlers so nothing is swallowed. The panel UI lives in
/// `devtools_panel.dart`.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:ui' show FramePhase;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'devtools_memory_stub.dart'
    if (dart.library.io) 'devtools_memory_io.dart' as memory;

/// One captured log line.
class DevLogEntry {
  DevLogEntry(this.time, this.level, this.message);

  final DateTime time;
  final DevLogLevel level;
  final String message;
}

enum DevLogLevel { info, error }

/// Rolling frame-timing aggregates over the sample window.
class DevFrameStats {
  const DevFrameStats({
    required this.frames,
    required this.fps,
    required this.avgBuildMs,
    required this.avgRasterMs,
    required this.worstFrameMs,
    required this.jankFrames,
  });

  static const empty = DevFrameStats(
    frames: 0,
    fps: 0,
    avgBuildMs: 0,
    avgRasterMs: 0,
    worstFrameMs: 0,
    jankFrames: 0,
  );

  /// Frames in the sample window (up to [AppDevTools.frameWindow]).
  final int frames;

  /// Frame rate over the window's wall-clock span (0 when idle - Flutter only
  /// produces frames when something animates or repaints).
  final double fps;

  final double avgBuildMs;
  final double avgRasterMs;
  final double worstFrameMs;

  /// Frames whose build+raster exceeded ~16.7 ms in the window.
  final int jankFrames;
}

/// Process-wide devtools state. Install once from the app root.
class AppDevTools extends ChangeNotifier {
  AppDevTools._();

  static final AppDevTools instance = AppDevTools._();

  static const int maxLogEntries = 500;
  static const int frameWindow = 120;

  /// Mirrored into [MaterialApp.showPerformanceOverlay] by the app root.
  final ValueNotifier<bool> showPerformanceOverlay = ValueNotifier(false);

  final ListQueue<DevLogEntry> _log = ListQueue();
  final ListQueue<FrameTiming> _timings = ListQueue();

  bool _installed = false;
  bool _capturing = false;
  bool _notifyScheduled = false;
  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);

  /// Captured log, oldest first. A fixed-size ring of [maxLogEntries].
  List<DevLogEntry> get log => List.unmodifiable(_log);

  /// Hooks [debugPrint], [FlutterError.onError], and the frame-timings
  /// callback. Idempotent; chains to the previous handlers. A no-op under
  /// `flutter test`, whose binding asserts those globals stay untouched -
  /// the panel still works there via [addLog].
  void install() {
    if (_installed || memory.inFlutterTest()) return;
    _installed = true;

    final previousPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      _record(DevLogLevel.info, message ?? '');
      previousPrint(message, wrapWidth: wrapWidth);
    };

    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      _record(DevLogLevel.error, details.exceptionAsString());
      previousOnError?.call(details);
    };

    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  /// Adds an app-authored entry (the capture hooks use this too).
  void addLog(String message, {DevLogLevel level = DevLogLevel.info}) =>
      _record(level, message);

  void clearLog() {
    _log.clear();
    notifyListeners();
  }

  void _record(DevLogLevel level, String message) {
    // debugPrint re-entrance guard: recording must never print.
    if (_capturing) return;
    _capturing = true;
    _log.addLast(DevLogEntry(DateTime.now(), level, message));
    while (_log.length > maxLogEntries) {
      _log.removeFirst();
    }
    _capturing = false;
    _scheduleNotify();
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      _timings.addLast(timing);
    }
    while (_timings.length > frameWindow) {
      _timings.removeFirst();
    }
    _scheduleNotify();
  }

  /// Aggregates over the retained frame window.
  DevFrameStats frameStats() {
    if (_timings.isEmpty) return DevFrameStats.empty;
    var buildUs = 0, rasterUs = 0, worstUs = 0, jank = 0;
    for (final t in _timings) {
      final b = t.buildDuration.inMicroseconds;
      final r = t.rasterDuration.inMicroseconds;
      buildUs += b;
      rasterUs += r;
      if (b + r > worstUs) worstUs = b + r;
      if (b + r > 16700) jank++;
    }
    final spanUs = _timings.last.timestampInMicroseconds(FramePhase.rasterFinish) -
        _timings.first.timestampInMicroseconds(FramePhase.buildStart);
    return DevFrameStats(
      frames: _timings.length,
      fps: spanUs <= 0 ? 0 : (_timings.length - 1) * 1e6 / spanUs,
      avgBuildMs: buildUs / _timings.length / 1000,
      avgRasterMs: rasterUs / _timings.length / 1000,
      worstFrameMs: worstUs / 1000,
      jankFrames: jank,
    );
  }

  /// Resident set size, null on the web.
  int? get currentRssBytes => memory.currentRssBytes();

  /// RSS high-water mark, null on the web.
  int? get maxRssBytes => memory.maxRssBytes();

  /// Throttle bursts (a frame's timings, a multi-line print) to at most one
  /// notification per quarter second, and always notify from a microtask:
  /// records can arrive mid-build (a FlutterError reported during layout
  /// lands here via the onError hook), where a synchronous notify makes any
  /// listening panel widget a build-phase violation - which reports another
  /// error, which records again, cascading. No trailing Timer (a pending
  /// Timer on this process-wide singleton would leak across widget tests);
  /// the panel's own 1 s poll picks up whatever the throttle dropped.
  void _scheduleNotify() {
    if (_notifyScheduled) return;
    if (DateTime.now().difference(_lastNotify) <
        const Duration(milliseconds: 250)) {
      return;
    }
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      _lastNotify = DateTime.now();
      notifyListeners();
    });
  }
}
