import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:pdf_cos/perf.dart';

import 'performance_memory.dart';

/// Lightweight, frame-gated performance log for diagnosing scroll/render
/// hangs on heavy documents.
///
/// Off by default. Enable at launch with `--dart-define=PDF_PERF_LOG=true`,
/// or flip [enabled] at runtime (e.g. from the example app). When enabled it
/// prints:
///
///   * every UI-thread interpret with its page index, path (recorded vs
///     plain), and split (interpret/raster) milliseconds - a long interpret
///     while you scroll IS the hang,
///   * render-scheduler grants and render-hold on/off transitions,
///   * background prerender warms,
///   * scroll velocity, and
///   * frame JANK (build or raster over the 16ms budget).
///
/// Each line prints immediately (synchronously, so a hang - which produces
/// no frames - can't swallow the lines that diagnose it); frame JANK is
/// appended from [SchedulerBinding]'s timings callback. Printing is
/// [debugPrintSynchronously], never a [Timer], so it cannot trip widget
/// tests' `!timersPending` invariant (and it stays off there anyway: the
/// dart-define defaults false and tests never set it).
///
/// Enable on the live web demo without a rebuild by appending `?perf=1` to
/// the URL, then read the `[perf …]` lines in the browser console.
class PdfPerfLog {
  PdfPerfLog._();

  /// Master switch. Defaults to the `PDF_PERF_LOG` dart-define so it is
  /// inert unless explicitly turned on for a diagnostic run.
  ///
  /// Enabling also switches on the COS-layer [PdfPerf] facade (pdf_cos) and
  /// points its event sink here, so one flag lights up the whole stack. The
  /// dart-define path bridges lazily on the first [enabled] read - every
  /// instrumented call site checks it, so that is effectively process start.
  static bool get enabled {
    final on = _enabled;
    if (on && !_bridged) _bridge(true);
    return on;
  }

  static set enabled(bool value) {
    _enabled = value;
    if (value) _stampPending = true;
    _bridge(value);
  }

  /// Identifies the build a trace came from - set by the host at startup, e.g.
  /// `commit=<sha>` from a `--dart-define`. Emitted as the first line whenever
  /// the log turns on, however it was turned on (URL flag, devtools toggle, or
  /// dart-define). Empty means the host did not supply one, which is reported
  /// honestly as no line rather than as a guess.
  static String buildTag = '';

  static bool _enabled = const bool.fromEnvironment('PDF_PERF_LOG');
  static bool _bridged = false;
  static bool _stampPending = const bool.fromEnvironment('PDF_PERF_LOG');

  static void _bridge(bool on) {
    _bridged = on;
    PdfPerf.enabled = on;
    if (on) PdfPerf.sink = log;
  }

  /// Optional host sink that receives every flushed line IN ADDITION to the
  /// console. This is the seam by which a host app (whose devtools export
  /// must never depend on a console the user can't reach) mirrors the trace
  /// into its own log - the package must not import the host, so the host
  /// hands us a closure instead. Not consulted at all while the log is off.
  static void Function(String line)? sink;

  static final Stopwatch _clock = Stopwatch()..start();
  static final List<String> _buf = <String>[];
  static bool _hooked = false;

  static double get _nowMs => _clock.elapsedMicroseconds / 1000.0;

  static void _ensureHook() {
    if (_hooked) return;
    _hooked = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  /// Records a line (cheap; the no-op path is a single bool check).
  static void log(String message) {
    if (!enabled) return;
    // Stamp the build as the first line of every trace. Emitted lazily on the
    // first line rather than from the `enabled` setter because a host sets its
    // [sink] AFTER flipping the switch, and a stamp written before that exists
    // reaches only the console - not the devtools log the user actually
    // exports. That is exactly how #451 lost several rounds: traces that could
    // not be attributed to a build.
    if (_stampPending) {
      _stampPending = false;
      if (buildTag.isNotEmpty) log('build $buildTag');
    }
    _ensureHook();
    _buf.add('[perf ${_nowMs.toStringAsFixed(0)}] $message');
    // Flush every line immediately: the whole point of this trace is
    // diagnosing hangs, and a hang produces no frames - so the per-frame
    // timings flush never fires and the lines right before the freeze
    // (the ones that pinpoint it) would sit in the buffer and be lost.
    _flush();
  }

  /// Logs a UI-thread interpret. [first] marks a page's first-ever interpret
  /// (the expensive content-stream walk), vs a cheap re-raster.
  ///
  /// [waitMs]/[buildMs] split [interpretMs] into its two real phases on the
  /// worker path - waiting for the worker's record reply vs turning the
  /// returned command buffer into a picture (image decode + build). Without
  /// them a trace shows one multi-second interpret that is indistinguishable
  /// from scheduler/hold queuing. [interpretMs] is still printed unchanged so
  /// older traces stay comparable.
  ///
  /// [decodeMs]/[replayMs] split the build phase one level deeper - image
  /// decode vs the canvas-call picture construction - because a cold-open
  /// trace showed build dominating the whole open while saying nothing about
  /// which half costs it. Printed only when BOTH are non-null: the split is
  /// meaningless as a lone number, and call sites where decode and
  /// construction are fused pass neither.
  static void interpret(int page,
      {required String path,
      required double interpretMs,
      double? waitMs,
      double? buildMs,
      double? decodeMs,
      double? replayMs,
      double? textShapeMs,
      int? textShapeMiss,
      int? textShapeHit,
      double? rasterMs,
      bool first = true,
      String note = ''}) {
    if (!enabled) return;
    final raster = rasterMs == null ? '' : ' raster=${_ms(rasterMs)}';
    final phases = (waitMs == null || buildMs == null)
        ? ''
        : ' wait=${_ms(waitMs)} build=${_ms(buildMs)}';
    final buildSplit = (decodeMs == null || replayMs == null)
        ? ''
        : ' decode=${_ms(decodeMs)} replay=${_ms(replayMs)}';
    // A third level inside replay (#454): how much of the canvas-call
    // construction is substituted-text shaping, and the run-cache hit rate that
    // decides whether a per-glyph cache would help. Printed only when measured.
    final shapeSplit = textShapeMs == null
        ? ''
        : ' shape=${_ms(textShapeMs)}'
            ' shaped=${textShapeMiss ?? 0} cached=${textShapeHit ?? 0}';
    final kind = first ? 'FIRST' : 're-raster';
    log('interpret page=$page path=$path $kind '
        'interpret=${_ms(interpretMs)}$phases$buildSplit$shapeSplit$raster$note');
  }

  static String _ms(double v) => '${v.toStringAsFixed(1)}ms';

  /// ` rss=NNNMB` for the current process, or `''` where RSS is unavailable
  /// (web) - a suffix any log line can append so the memory climb shows on the
  /// same timeline.
  ///
  /// Returns `''` when the log is off *before* reading [currentProcessRssBytes]:
  /// call sites interpolate this into a message argument, which Dart evaluates
  /// before [log] can check [enabled], so without this guard every one of them
  /// would pay a `ProcessInfo.currentRss` syscall on an ordinary run.
  static String rssSuffix() {
    if (!enabled) return '';
    final rss = currentProcessRssBytes;
    return rss == null ? '' : ' rss=${(rss / (1 << 20)).round()}MB';
  }

  static int _rasterSeq = 0;

  /// Logs one raster allocation, the number that matters when diagnosing a
  /// native-memory (GPU/Impeller) climb the Dart-side cache clears can't touch:
  /// each line carries the raster's output size in megapixels, a monotonic
  /// sequence number (so a per-frame *loop* is obvious - `n` racing up), and the
  /// process RSS *after* the allocation (so the climb toward the OS high-water
  /// limit is visible against the same timeline as the JANK/`vector-first`
  /// lines). Read in the DevTools console (the `[perf … raster …]` lines) or in
  /// an exported trace.
  ///
  /// [kind] is the raster path (e.g. 'detail', 'vector-first', 'base'). [region]
  /// is null for a full-page raster. [elapsedMs] is the measured duration of the
  /// rasterize call itself - without it the cost of a 1.5MP readback can only
  /// be inferred from the gap between log timestamps, which is unmeasurable
  /// during the hangs this log exists to diagnose. Off unless the perf log is
  /// [enabled].
  static void raster(
    String kind, {
    required int page,
    required int imageWidth,
    required int imageHeight,
    double? ratio,
    double? elapsedMs,
    ({double width, double height})? region,
  }) {
    if (!enabled) return;
    final mp = (imageWidth * imageHeight) / 1e6;
    final ratioStr = ratio == null ? '' : ' ratio=${ratio.toStringAsFixed(1)}';
    final msStr = elapsedMs == null ? '' : ' ms=${elapsedMs.toStringAsFixed(1)}';
    final regionStr = region == null
        ? ' full'
        : ' region=${region.width.toStringAsFixed(0)}x'
            '${region.height.toStringAsFixed(0)}pt';
    log('raster kind=$kind page=$page n=${++_rasterSeq}$regionStr$ratioStr '
        'img=${imageWidth}x$imageHeight '
        '(${mp.toStringAsFixed(1)}MP)$msStr${rssSuffix()}');
  }

  static void _onTimings(List<FrameTiming> timings) {
    if (!enabled) {
      _flush();
      return;
    }
    for (final t in timings) {
      final build = t.buildDuration.inMicroseconds / 1000.0;
      final raster = t.rasterDuration.inMicroseconds / 1000.0;
      if (build > 16.0 || raster > 16.0) {
        _buf.add('[perf ${_nowMs.toStringAsFixed(0)}] JANK '
            'build=${_ms(build)} raster=${_ms(raster)} '
            'total=${_ms(t.totalSpan.inMicroseconds / 1000.0)}${rssSuffix()}');
      }
    }
    _flush();
  }

  static void _flush() {
    if (_buf.isEmpty) return;
    for (final line in _buf) {
      // Synchronous print, NOT debugPrint: debugPrint throttles output
      // through a Timer that never fires during a synchronous hang, so
      // the most diagnostic lines would never reach the console. This
      // path only runs when [enabled] (a diagnostic build/run), so the
      // extra cost is irrelevant, and it's still Timer-free, so it can't
      // trip widget tests' `!timersPending` (which stay off anyway).
      debugPrintSynchronously(line);
      // A host's sink is foreign code: a throwing one must never break the
      // render path this log is diagnosing, so its failures are swallowed.
      try {
        sink?.call(line);
      } catch (_) {}
    }
    _buf.clear();
  }
}
