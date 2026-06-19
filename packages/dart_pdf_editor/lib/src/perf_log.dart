import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Lightweight, frame-gated performance log for diagnosing scroll/render
/// hangs on heavy documents.
///
/// Off by default. Enable at launch with `--dart-define=PDF_PERF_LOG=true`,
/// or flip [enabled] at runtime (e.g. from the example app). When enabled it
/// prints:
///
///   * every UI-thread interpret with its page index, path (recorded vs
///     plain), and split (interpret/raster) milliseconds — a long interpret
///     while you scroll IS the hang,
///   * render-scheduler grants and render-hold on/off transitions,
///   * background prerender warms,
///   * scroll velocity, and
///   * frame JANK (build or raster over the 16ms budget).
///
/// Each line prints immediately (synchronously, so a hang — which produces
/// no frames — can't swallow the lines that diagnose it); frame JANK is
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
  static bool enabled = const bool.fromEnvironment('PDF_PERF_LOG');

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
    _ensureHook();
    _buf.add('[perf ${_nowMs.toStringAsFixed(0)}] $message');
    // Flush every line immediately: the whole point of this trace is
    // diagnosing hangs, and a hang produces no frames — so the per-frame
    // timings flush never fires and the lines right before the freeze
    // (the ones that pinpoint it) would sit in the buffer and be lost.
    _flush();
  }

  /// Logs a UI-thread interpret. [first] marks a page's first-ever interpret
  /// (the expensive content-stream walk), vs a cheap re-raster.
  static void interpret(int page,
      {required String path,
      required double interpretMs,
      double? rasterMs,
      bool first = true,
      String note = ''}) {
    if (!enabled) return;
    final raster = rasterMs == null ? '' : ' raster=${_ms(rasterMs)}';
    final kind = first ? 'FIRST' : 're-raster';
    log('interpret page=$page path=$path $kind '
        'interpret=${_ms(interpretMs)}$raster$note');
  }

  static String _ms(double v) => '${v.toStringAsFixed(1)}ms';

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
            'total=${_ms(t.totalSpan.inMicroseconds / 1000.0)}');
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
    }
    _buf.clear();
  }
}
