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
import 'dart:convert';
import 'dart:ui' show FramePhase, Locale;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor_flutter_gpu/dart_pdf_editor_flutter_gpu.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'devtools_memory_stub.dart'
    if (dart.library.io) 'devtools_memory_io.dart' as memory;

/// Whether the developer tools (F12 panel, capture hooks, option restore)
/// are enabled in this build. On by default in EVERY mode, release included -
/// the tools are the user's own metrics and logs, and release is where real
/// performance questions live. A store/CI build that wants them gone passes
/// `--dart-define=DEVTOOLS=false`, which also lets the tree-shaker drop the
/// panel. Debug-engine-only toggles (repaint rainbow) and profile-only ones
/// (performance overlay) stay additionally gated inside the panel.
const bool kDevToolsEnabled =
    bool.fromEnvironment('DEVTOOLS', defaultValue: true);

/// Test seam for app-owned services that would otherwise leave periodic
/// timers behind under `flutter test`.
bool get runningUnderFlutterTest => memory.inFlutterTest();

/// One captured log line.
class DevLogEntry {
  DevLogEntry(this.time, this.level, this.message);

  final DateTime time;
  final DevLogLevel level;
  final String message;
}

enum DevLogLevel { info, error }

/// Whether the visited-page raster cache follows machine headroom or a fixed
/// diagnostic override chosen in Developer tools.
enum PageRasterCacheMode { auto, fixed }

/// The preferred renderer for deep-zoom tile slabs.
///
/// This is a preference rather than a promise: flutter_gpu can reject a page
/// or fail to initialize, in which case the viewer permanently falls back to
/// Canvas for that retained scene.
enum TileRasterBackendMode { canvas, flutterGpu }

/// Per-pointer accumulator for touch-input logging: the net displacement,
/// total path length, and move count between a pointer's down and up.
class _TouchTrack {
  _TouchTrack(this.start, this.startTime);

  final Offset start;
  final Duration startTime;
  double pathLength = 0;
  int moves = 0;

  void accumulate(Offset delta) {
    pathLength += delta.distance;
    moves++;
  }
}

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

  /// Full-resolution rasters retained after their page widgets leave the
  /// viewport. The editor listens to this separately from [AppDevTools]
  /// itself: log traffic notifies the panel frequently and must not rebuild
  /// the mounted document, while a policy change should apply immediately.
  final ValueNotifier<PdfPageRasterCachePolicy> pageRasterCachePolicy =
      ValueNotifier(const PdfPageRasterCachePolicy());

  /// Whether idle viewer time is spent baking exact page rasters ahead of
  /// navigation (#614). The product warms only the nearby working set by
  /// default: it removes the blurry first-arrival pause without committing to
  /// a whole-document raster pass. The work remains preemptible and bounded by
  /// [pageRasterCachePolicy]; Developer tools can disable or expand it. Kept
  /// as its own notifier for the same reason as [pageRasterCachePolicy] - a
  /// policy change must reach the mounted document without waiting for the
  /// log-traffic rebuild.
  final ValueNotifier<PdfPageRasterWarmPolicy> pageRasterWarmPolicy =
      ValueNotifier(const PdfPageRasterWarmPolicy.nearby());

  /// Runtime tile-backend selection exposed by Developer tools.
  ///
  /// The app listens to this separately from the noisy devtools log. Changing
  /// it rebuilds the mounted viewer in place; [PdfPageView] then retires its
  /// old scene sessions without reopening the PDF; the base raster stays
  /// visible while the selected backend repopulates the invalidated LoD.
  ///
  /// DartPDF prefers flutter_gpu wherever the compiled backend is available.
  /// The preference remains switchable at runtime, and unsupported scenes or
  /// raster failures still replay exactly through Canvas.
  late final ValueNotifier<TileRasterBackendMode> tileRasterBackendMode =
      ValueNotifier(
    flutterGpuTileRasterBackend.isPlatformSupported
        ? TileRasterBackendMode.flutterGpu
        : TileRasterBackendMode.canvas,
  );

  /// Changes when the selected backend instance is replaced without changing
  /// its mode (for example after editing a GPU byte ceiling).
  final ValueNotifier<int> tileRasterBackendRevision = ValueNotifier(0);

  /// One process-wide backend instance preserves textures, pooled geometry,
  /// and diagnostics across pages, tabs, and backend switches.
  FlutterGpuTileRasterBackend? _flutterGpuTileRasterBackend;
  int _gpuTextureBytes = 256 << 20;
  int _gpuGeometryBytes = 256 << 20;
  bool _gpuOverprintApproximation = false;

  bool get gpuOverprintApproximation => _gpuOverprintApproximation;

  FlutterGpuTileRasterBackend get flutterGpuTileRasterBackend =>
      _flutterGpuTileRasterBackend ??= FlutterGpuTileRasterBackend(
        maxTextureBytes: _gpuTextureBytes,
        maxGeometryBytes: _gpuGeometryBytes,
        allowOverprintApproximation: _gpuOverprintApproximation,
        systemTextOutlines: true,
      );

  static const PdfCanvasTileRasterBackend _canvasTileRasterBackend =
      PdfCanvasTileRasterBackend();

  PdfTileRasterBackend get tileRasterBackend =>
      tileRasterBackendMode.value == TileRasterBackendMode.flutterGpu
          ? flutterGpuTileRasterBackend
          : _canvasTileRasterBackend;

  void setTileRasterBackendMode(TileRasterBackendMode mode) {
    if (tileRasterBackendMode.value == mode) return;
    tileRasterBackendMode.value = mode;
    // A backend A/B switch must not keep serving already-rendered slabs from
    // the old backend. The full-page/base raster remains visible while the
    // selected backend repopulates the current LoD, so this is still a live
    // handoff rather than a document reopen or a blank first paint.
    if (PdfPageView.tileStoreDetail) {
      (PdfPageView.debugTileStoreOverride ?? PdfTileStore.instanceOrNull)
          ?.invalidate();
    }
    _flutterGpuTileRasterBackend?.stats
        .logPerfSummary('backend-switch-to-${mode.name}');
    addLog('devtools: tile raster backend → ${mode.name}');
  }

  /// Replaces the process-wide GPU backend with new strict byte ceilings.
  ///
  /// The limits do not allocate eagerly. A live selected backend is swapped
  /// in place, which retires its page sessions and rebuilds the current LoD
  /// through the new instance while the base raster remains on screen.
  void setGpuTileBudgets({int? maxTextureBytes, int? maxGeometryBytes}) {
    final textureBytes = maxTextureBytes ?? _gpuTextureBytes;
    final geometryBytes = maxGeometryBytes ?? _gpuGeometryBytes;
    if (textureBytes == _gpuTextureBytes &&
        geometryBytes == _gpuGeometryBytes) {
      return;
    }
    final previous = _flutterGpuTileRasterBackend;
    _gpuTextureBytes = textureBytes;
    _gpuGeometryBytes = geometryBytes;
    _flutterGpuTileRasterBackend = FlutterGpuTileRasterBackend(
      maxTextureBytes: textureBytes,
      maxGeometryBytes: geometryBytes,
      allowOverprintApproximation: _gpuOverprintApproximation,
      systemTextOutlines: true,
    );
    // Unpinned texture ownership can go immediately. Active sessions keep
    // their leases until the viewer rebuild below disposes them.
    previous?.clearImageCache();
    if (tileRasterBackendMode.value == TileRasterBackendMode.flutterGpu) {
      if (PdfPageView.tileStoreDetail) {
        (PdfPageView.debugTileStoreOverride ?? PdfTileStore.instanceOrNull)
            ?.invalidate();
      }
      tileRasterBackendRevision.value++;
    }
    addLog('devtools: GPU budgets → '
        '${textureBytes >> 20}MB textures, '
        '${geometryBytes >> 20}MB geometry');
  }

  /// Enables the deliberately inexact source-over approximation for
  /// non-black overprint paints. Exact Canvas fallback remains the default.
  /// Replacing the backend retires all scene sessions so a toggle can never
  /// leave already-compiled scenes using the previous correctness policy.
  void setGpuOverprintApproximation(bool enabled) {
    if (_gpuOverprintApproximation == enabled) return;
    final previous = _flutterGpuTileRasterBackend;
    _gpuOverprintApproximation = enabled;
    _flutterGpuTileRasterBackend = FlutterGpuTileRasterBackend(
      maxTextureBytes: _gpuTextureBytes,
      maxGeometryBytes: _gpuGeometryBytes,
      allowOverprintApproximation: enabled,
      systemTextOutlines: true,
    );
    previous?.clearImageCache();
    if (tileRasterBackendMode.value == TileRasterBackendMode.flutterGpu) {
      if (PdfPageView.tileStoreDetail) {
        (PdfPageView.debugTileStoreOverride ?? PdfTileStore.instanceOrNull)
            ?.invalidate();
      }
      tileRasterBackendRevision.value++;
    }
    addLog('devtools: GPU non-black overprint approximation '
        '${enabled ? 'ON' : 'off (exact Canvas fallback)'}');
  }

  /// Releases reusable GPU image-cache ownership. Active scene leases remain
  /// valid and geometry stays in its bounded reusable pool.
  void clearGpuImageCache() => flutterGpuTileRasterBackend.clearImageCache();

  PageRasterCacheMode _pageRasterCacheMode = PageRasterCacheMode.auto;
  PdfPageRasterCachePolicy _fixedPageRasterCachePolicy =
      const PdfPageRasterCachePolicy();
  PdfPageRasterCachePolicy _lastAutoPageRasterCachePolicy =
      const PdfPageRasterCachePolicy();
  String _lastAutoPageRasterCacheReason = 'Waiting for a memory sample';
  String _pageRasterCacheReason = 'Waiting for a memory sample';
  int? _safeProcessLimitBytes;

  PageRasterCacheMode get pageRasterCacheMode => _pageRasterCacheMode;
  bool get pageRasterCacheAuto =>
      _pageRasterCacheMode == PageRasterCacheMode.auto;
  PdfPageRasterCachePolicy get fixedPageRasterCachePolicy =>
      _fixedPageRasterCachePolicy;
  String get pageRasterCacheReason => _pageRasterCacheReason;
  int? get safeProcessLimitBytes => _safeProcessLimitBytes;

  /// Forces the whole app onto a locale for testing, bypassing the normal
  /// [MaterialApp] resolution against `supportedLocales`. `null` follows the
  /// platform. Set from the DevTools panel's Locale section; session-only (not
  /// persisted, so a forced RTL locale never survives a restart). The main use
  /// is exercising the RTL layout sweep by picking an RTL locale like Arabic —
  /// even before its translations land, the Material delegates translate their
  /// own strings and `Directionality` flips.
  final ValueNotifier<Locale?> localeOverride = ValueNotifier(null);

  final ListQueue<DevLogEntry> _log = ListQueue();
  final ListQueue<FrameTiming> _timings = ListQueue();

  bool _installed = false;
  bool _capturing = false;
  bool _notifyScheduled = false;
  bool _logTouchInput = false;
  bool _logPerfTrace = false;
  final Map<int, _TouchTrack> _touchTracks = {};
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

  // --- touch input logging --------------------------------------------------

  /// Whether raw pointer events over the viewer are summarized into the log,
  /// and the viewer's own gesture-decision sink ([pdfDebugGestureLog]) is
  /// captured too. Off by default; the diagnostic for "panning does nothing
  /// while zoomed" and similar touch reports, which never reproduce off the
  /// affected device. Toggling it installs/removes the viewer sink.
  bool get logTouchInput => _logTouchInput;

  set logTouchInput(bool value) {
    if (_logTouchInput == value) return;
    _logTouchInput = value;
    // The viewer's discrete gesture decisions (which recognizer claimed a
    // drag) join the same log, tagged so the panel filter can isolate them.
    pdfDebugGestureLog = value ? (m) => addLog('gesture: $m') : null;
    if (!value) _touchTracks.clear();
    addLog('devtools: touch input logging ${value ? 'on' : 'off'}');
    _scheduleNotify();
  }

  /// Feeds one raw pointer event from a host [Listener]. A no-op unless
  /// [logTouchInput] is on. Emits one line per gesture on down and up/cancel
  /// (with a moved-distance/duration summary), never per move - a dragging
  /// finger fires moves at 60-120 Hz and would drown the ring buffer.
  void logPointerEvent(PointerEvent event) {
    if (!_logTouchInput) return;
    // Mice and trackpads are not the subject here (touch/stylus panning is);
    // logging their hover/move stream would bury the finger events.
    if (event.kind != PointerDeviceKind.touch &&
        event.kind != PointerDeviceKind.stylus &&
        event.kind != PointerDeviceKind.invertedStylus) {
      return;
    }
    if (event is PointerDownEvent) {
      _touchTracks[event.pointer] =
          _TouchTrack(event.position, event.timeStamp);
      addLog('touch: DOWN id=${event.pointer} ${event.kind.name} '
          '@${_fmt(event.position)} contacts=${_touchTracks.length}');
    } else if (event is PointerMoveEvent) {
      _touchTracks[event.pointer]?.accumulate(event.delta);
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      final track = _touchTracks.remove(event.pointer);
      final verb = event is PointerCancelEvent ? 'CANCEL' : 'UP';
      if (track == null) {
        addLog('touch: $verb id=${event.pointer}');
        return;
      }
      final net = event.position - track.start;
      final ms = (event.timeStamp - track.startTime).inMilliseconds;
      addLog('touch: $verb id=${event.pointer} net=${_fmt(net)} '
          'path=${track.pathLength.toStringAsFixed(0)}px '
          'moves=${track.moves} ${ms}ms');
    }
  }

  static String _fmt(Offset o) =>
      '(${o.dx.toStringAsFixed(0)},${o.dy.toStringAsFixed(0)})';

  // --- perf trace forwarding --------------------------------------------------

  /// Whether [PdfPerfLog] runs AND its lines are forwarded into this log,
  /// tagged `perf:`. Off by default. The export's pdfPerf block only covers
  /// the document-open path; this is how the render path (worker traffic,
  /// interprets, rasters, jank) gets into the same exported trace. Toggling
  /// installs/removes the package's sink - the package never imports the app,
  /// so the sink is the seam.
  bool get logPerfTrace => _logPerfTrace;

  set logPerfTrace(bool value) {
    if (_logPerfTrace == value) return;
    // Bracket the trace with the GPU backend's lifetime totals: turning the
    // log ON stamps the baseline the following lines accumulate from, and
    // turning it OFF stamps where they ended, so an exported trace carries
    // both without the reader having to open the panel and read counters that
    // have since moved. Emitted while the log is still on in both directions.
    if (!value) _flutterGpuTileRasterBackend?.stats.logPerfSummary('trace-end');
    _logPerfTrace = value;
    PdfPerfLog.enabled = value;
    // The trace is verbose - a line per worker request/reply, interpret, and
    // raster - and this log is a ring of only maxLogEntries, so a sustained
    // trace WILL evict the earlier entries (the open-trace: lines included).
    // Reproduce the problem, then export promptly; don't leave it running.
    PdfPerfLog.sink = value
        ? (m) => _record(DevLogLevel.info, 'perf: $m', notify: false)
        : null;
    addLog('devtools: perf trace logging ${value ? 'on' : 'off'}');
    if (value) {
      _flutterGpuTileRasterBackend?.stats.logPerfSummary('trace-start');
    }
    _scheduleNotify();
  }

  /// Appends one entry to the ring.
  ///
  /// [notify] false is for high-volume lines - the [PdfPerfLog] trace, which
  /// emits a JANK line per janky frame. Notifying there would schedule a panel
  /// rebuild, which is itself a frame, which can produce the next JANK line:
  /// the measurement driving the thing it measures. Those lines still appear,
  /// because the panel refreshes anyway (the 250 ms throttle from [_onTimings]
  /// while frames are produced, and its own 1 s poll while open) - they simply
  /// stop being a rebuild trigger of their own.
  void _record(DevLogLevel level, String message, {bool notify = true}) {
    // debugPrint re-entrance guard: recording must never print.
    if (_capturing) return;
    _capturing = true;
    _log.addLast(DevLogEntry(DateTime.now(), level, message));
    while (_log.length > maxLogEntries) {
      _log.removeFirst();
    }
    _capturing = false;
    if (notify) _scheduleNotify();
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      _timings.addLast(timing);
    }
    while (_timings.length > frameWindow) {
      _timings.removeFirst();
    }
    // Deliberately does NOT notify (#452). A notify rebuilds the panel, and a
    // panel rebuild is itself a frame, which fires this callback again - a
    // self-sustaining ~1 Hz rebuild loop that keeps the app producing janky
    // frames while it sits idle, and makes the measurement drive the thing it
    // measures. The panel's own 1 s poll (devtools_panel.dart) refreshes the
    // frame stats instead; the window keeps accumulating here regardless.
  }

  /// Test seam (#452): drive the frame-timings path directly, to assert it
  /// accumulates the sample window without scheduling a notify (which would
  /// self-sustain a rebuild loop).
  @visibleForTesting
  void debugAddTimings(List<FrameTiming> timings) => _onTimings(timings);

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
    final spanUs =
        _timings.last.timestampInMicroseconds(FramePhase.rasterFinish) -
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

  // --- deep-zoom detail mode (shared by the panel and option restore) -------

  static const modePatch = 'patch';
  static const modeTiles = 'tiles (per-tile)';
  static const modeBatched = 'tiles (batched)';

  /// The active deep-zoom detail mechanism (#314 experiment switch).
  String get deepZoomMode {
    if (!PdfPageView.tileStoreDetail) return modePatch;
    final store = PdfPageView.debugTileStoreOverride;
    return (store?.batchRasters ?? true) ? modeBatched : modeTiles;
  }

  /// Applies [mode], swapping the tile store via the debug override seam.
  /// Takes effect from the next zoom or pan settle.
  void setDeepZoomMode(String mode) {
    if (mode == deepZoomMode) return;
    final old = PdfPageView.debugTileStoreOverride;
    switch (mode) {
      case modePatch:
        PdfPageView.tileStoreDetail = false;
        PdfPageView.debugTileStoreOverride = null;
      case modeTiles:
        PdfPageView.tileStoreDetail = true;
        PdfPageView.debugTileStoreOverride = PdfTileStore(batchRasters: false);
      case modeBatched:
        PdfPageView.tileStoreDetail = true;
        PdfPageView.debugTileStoreOverride = PdfTileStore();
      default:
        return;
    }
    // Free the previous pyramid's tiles but keep its notifier alive: a
    // mounted PdfTileLayer may still listen until the next rebuild.
    old?.invalidate();
    addLog('devtools: deep-zoom detail → $mode');
  }

  /// Applies a fixed visited-page raster cache policy to every mounted viewer.
  ///
  /// This is the explicit diagnostic override. [useAutoPageRasterCache]
  /// returns control to the machine-headroom policy.
  void setPageRasterCachePolicy(PdfPageRasterCachePolicy policy) {
    final unchanged = _pageRasterCacheMode == PageRasterCacheMode.fixed &&
        _fixedPageRasterCachePolicy == policy;
    _pageRasterCacheMode = PageRasterCacheMode.fixed;
    _fixedPageRasterCachePolicy = policy;
    _pageRasterCacheReason = 'Fixed Developer tools override';
    pageRasterCachePolicy.value = policy;
    PdfPerfLog.log(
      'page-raster mode=fixed total=${policy.maxBytes} '
      'entry=${policy.maxEntryBytes} '
      'ceiling=${PdfCacheRegistry.instance.maxTotalWeight}'
      '${PdfPerfLog.rssSuffix()}',
    );
    if (unchanged) return;
    addLog('devtools: visited-page rasters → '
        '${policy.maxBytes >> 20}MB total, '
        '${policy.maxEntryBytes >> 20}MB/page');
  }

  /// Applies an idle full-raster warm policy to every mounted viewer.
  void setPageRasterWarmPolicy(PdfPageRasterWarmPolicy policy) {
    if (pageRasterWarmPolicy.value == policy) return;
    pageRasterWarmPolicy.value = policy;
    PdfPerfLog.log('raster-warm policy mode=${policy.mode.name} '
        'window=${policy.window} idleMs=${policy.idleDelay.inMilliseconds}');
    addLog('devtools: idle raster warm \u2192 ${policy.mode.name}'
        '${policy.mode == PdfPageRasterWarmMode.nearby ? ' (\u00b1${policy.window})' : ''}');
  }

  /// Returns the visited-page raster cache to adaptive machine-headroom mode.
  void useAutoPageRasterCache() {
    if (pageRasterCacheAuto) return;
    _pageRasterCacheMode = PageRasterCacheMode.auto;
    pageRasterCachePolicy.value = _lastAutoPageRasterCachePolicy;
    _pageRasterCacheReason = _lastAutoPageRasterCacheReason;
    PdfPerfLog.log(
      'page-raster mode=auto '
      'total=${_lastAutoPageRasterCachePolicy.maxBytes} '
      'entry=${_lastAutoPageRasterCachePolicy.maxEntryBytes} '
      'processTarget=${_safeProcessLimitBytes ?? 0} '
      'ceiling=${PdfCacheRegistry.instance.maxTotalWeight}'
      '${PdfPerfLog.rssSuffix()}',
    );
    addLog('devtools: visited-page rasters → Auto');
  }

  /// Receives one effective policy from the adaptive memory controller.
  void updateAutoPageRasterCache(
    PdfPageRasterCachePolicy policy, {
    required String reason,
    int? safeProcessLimitBytes,
  }) {
    _safeProcessLimitBytes = safeProcessLimitBytes;
    _lastAutoPageRasterCachePolicy = policy;
    _lastAutoPageRasterCacheReason = reason;
    if (!pageRasterCacheAuto) return;
    final changed = pageRasterCachePolicy.value != policy;
    pageRasterCachePolicy.value = policy;
    _pageRasterCacheReason = reason;
    if (changed) {
      addLog('memory-auto: visited rasters ${policy.maxBytes >> 20}MB, '
          '${policy.maxEntryBytes >> 20}MB/page ($reason)');
      PdfPerfLog.log(
        'page-raster mode=auto total=${policy.maxBytes} '
        'entry=${policy.maxEntryBytes} '
        'processTarget=${safeProcessLimitBytes ?? 0} '
        'ceiling=${PdfCacheRegistry.instance.maxTotalWeight} '
        'reason=$reason${PdfPerfLog.rssSuffix()}',
      );
    } else {
      _scheduleNotify();
    }
  }

  // --- option persistence ---------------------------------------------------

  static const _optionsKey = 'devtools.options';

  /// Restores persisted devtools options. Call once at app start, after the
  /// platform defaults are set (the persisted values override them). A pool
  /// spawned before this async load completes just uses the default size
  /// until its next respawn.
  Future<void> restoreOptions() async {
    try {
      final raw =
          (await SharedPreferences.getInstance()).getString(_optionsKey);
      if (raw == null) return;
      final map = jsonDecode(raw);
      if (map is! Map) return;
      if (map['deepZoomMode'] case final String mode) {
        setDeepZoomMode(mode);
      }
      final textureBytes = switch (map['gpuTextureBytes']) {
        final int value when value >= 16 << 20 => value,
        _ => _gpuTextureBytes,
      };
      final geometryBytes = switch (map['gpuGeometryBytes']) {
        final int value when value >= 16 << 20 => value,
        _ => _gpuGeometryBytes,
      };
      setGpuTileBudgets(
        maxTextureBytes: textureBytes,
        maxGeometryBytes: geometryBytes,
      );
      if (map['gpuOverprintApproximation'] case final bool enabled) {
        setGpuOverprintApproximation(enabled);
      }
      if (map['tileRasterBackend'] case final String mode) {
        final restored = TileRasterBackendMode.values
            .where((value) => value.name == mode)
            .firstOrNull;
        if (restored != null) {
          // Keep an explicit stored preference. A stored flutter_gpu choice
          // falls back to Canvas only when this build cannot provide it; the
          // old opt-in marker is intentionally no longer required now that
          // flutter_gpu is DartPDF's supported-platform default.
          final restoreFlutterGpu =
              restored == TileRasterBackendMode.flutterGpu &&
                  flutterGpuTileRasterBackend.isPlatformSupported;
          setTileRasterBackendMode(
            restoreFlutterGpu
                ? TileRasterBackendMode.flutterGpu
                : TileRasterBackendMode.canvas,
          );
        }
      }
      if (map['tileBorders'] case final bool v) {
        pdfDebugPaintDetailBounds.value = v;
      }
      if (map['renderWindow'] case final bool v) {
        pdfDebugShowRenderWindow.value = v;
      }
      if (map['gpuRouteOverlay'] case final bool v) {
        pdfDebugShowGpuRasterRoutes.value = v;
      }
      if (map['perfOverlay'] case final bool v) {
        showPerformanceOverlay.value = v;
      }
      if (map['perfLog'] case final bool v) logPerfTrace = v;
      if (map['logTouchInput'] case final bool v) logTouchInput = v;
      if (map['workers'] case final int v) {
        pdfRenderWorkerPoolSize = v.clamp(1, 8);
      }
      final currentRasterPolicy = _fixedPageRasterCachePolicy;
      final rasterBytes = switch (map['pageRasterCacheBytes']) {
        final int v when v >= 0 => v,
        _ => currentRasterPolicy.maxBytes,
      };
      final rasterEntryBytes = switch (map['pageRasterCacheEntryBytes']) {
        final int v when v >= 0 => v,
        _ => currentRasterPolicy.maxEntryBytes,
      };
      final fixedPolicy = PdfPageRasterCachePolicy(
        maxBytes: rasterBytes,
        maxEntryBytes: rasterEntryBytes,
      );
      _fixedPageRasterCachePolicy = fixedPolicy;
      if (map['pageRasterWarmMode'] case final String mode) {
        final window = switch (map['pageRasterWarmWindow']) {
          final int v when v > 0 => v,
          _ => 3,
        };
        setPageRasterWarmPolicy(switch (mode) {
          'nearby' => PdfPageRasterWarmPolicy.nearby(window: window),
          'document' => const PdfPageRasterWarmPolicy.document(),
          _ => const PdfPageRasterWarmPolicy.disabled(),
        });
      }
      if (map['pageRasterCacheMode'] == PageRasterCacheMode.auto.name) {
        useAutoPageRasterCache();
      } else if (map['pageRasterCacheMode'] == PageRasterCacheMode.fixed.name ||
          map.containsKey('pageRasterCacheBytes') ||
          map.containsKey('pageRasterCacheEntryBytes')) {
        setPageRasterCachePolicy(fixedPolicy);
      }
      _scheduleNotify();
    } catch (e) {
      addLog('devtools options restore failed: $e', level: DevLogLevel.error);
    }
  }

  /// Persists the current option set. The panel calls this after each change.
  Future<void> persistOptions() async {
    try {
      await (await SharedPreferences.getInstance()).setString(
        _optionsKey,
        jsonEncode({
          'deepZoomMode': deepZoomMode,
          'tileRasterBackend': tileRasterBackendMode.value.name,
          // Retain the marker for backwards compatibility with builds that
          // predate flutter_gpu becoming the default.
          'flutterGpuOptIn':
              tileRasterBackendMode.value == TileRasterBackendMode.flutterGpu,
          'gpuTextureBytes': flutterGpuTileRasterBackend.maxTextureBytes,
          'gpuGeometryBytes': flutterGpuTileRasterBackend.maxGeometryBytes,
          'gpuOverprintApproximation': _gpuOverprintApproximation,
          'tileBorders': pdfDebugPaintDetailBounds.value,
          'renderWindow': pdfDebugShowRenderWindow.value,
          'gpuRouteOverlay': pdfDebugShowGpuRasterRoutes.value,
          'perfOverlay': showPerformanceOverlay.value,
          'perfLog': _logPerfTrace,
          'logTouchInput': _logTouchInput,
          'workers': pdfRenderWorkerPoolSize,
          'pageRasterCacheMode': _pageRasterCacheMode.name,
          'pageRasterCacheBytes': _fixedPageRasterCachePolicy.maxBytes,
          'pageRasterCacheEntryBytes':
              _fixedPageRasterCachePolicy.maxEntryBytes,
          'pageRasterWarmMode': pageRasterWarmPolicy.value.mode.name,
          'pageRasterWarmWindow': pageRasterWarmPolicy.value.window,
        }),
      );
    } catch (e) {
      addLog('devtools options persist failed: $e', level: DevLogLevel.error);
    }
  }

  /// Throttle bursts (a frame's timings, a multi-line print) to at most one
  /// notification per quarter second, and always notify from a microtask:
  /// records can arrive mid-build (a FlutterError reported during layout
  /// lands here via the onError hook), where a synchronous notify makes any
  /// listening panel widget a build-phase violation - which reports another
  /// error, which records again, cascading. No trailing Timer (a pending
  /// Timer on this process-wide singleton would leak across widget tests);
  /// the panel's own 1 s poll picks up whatever the throttle dropped.
  void _scheduleNotify() {
    // Nothing listening (panel closed): rebuilds would be pure waste, and a
    // panel rebuild is itself a frame that feeds back into the frame timings
    // being measured. Recording above is unaffected - entries and timings
    // still accumulate so the history is there when the panel opens.
    if (!hasListeners) return;
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
