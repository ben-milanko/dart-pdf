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
/// Buffered and flushed once per frame from [SchedulerBinding]'s timings
/// callback — never a [Timer], so it cannot trip widget tests'
/// `!timersPending` invariant (and it stays off there anyway: the dart-define
/// defaults false and tests never set it).
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
    // Safety flush so a long hang (no frames) can't grow the buffer
    // unbounded before the timings callback fires.
    if (_buf.length >= 256) _flush();
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
      debugPrint(line);
    }
    _buf.clear();
  }
}
