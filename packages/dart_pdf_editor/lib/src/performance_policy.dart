import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'performance_memory.dart';
import 'performance_processors.dart';

/// Coarse runtime family used by the adaptive render policy.
enum PdfPerformancePlatform { mobile, desktop, web, other }

/// The current runtime family, however the platform will admit to it.
PdfPerformancePlatform get detectedPdfPerformancePlatform => kIsWeb
    ? PdfPerformancePlatform.web
    : switch (defaultTargetPlatform) {
        TargetPlatform.android ||
        TargetPlatform.iOS ||
        TargetPlatform.fuchsia =>
          PdfPerformancePlatform.mobile,
        TargetPlatform.linux ||
        TargetPlatform.macOS ||
        TargetPlatform.windows =>
          PdfPerformancePlatform.desktop,
      };

/// Whether the deep-zoom tile pyramid ([PdfPageView.tileStoreDetail], issue
/// #314) is on by default. On for **every platform** since the budget-vs-demand
/// guard (issues #314/#360) removed the eviction thrash a HiDPI/web view could
/// hit: a view too dense to tile within budget now falls back to the single
/// detail patch instead of re-rastering evicted tiles on every repaint
/// ([PdfTileStore.viewFitsBudget]).
///
/// - **Desktop**: validated interactively on dense CAD sheets and 198-page scan
///   books (see doc/dev-log).
/// - **Web**: on-device release traces show the pyramid settling *under* budget
///   (no longer pinned/evicting), panning at deep zoom reusing cached tiles
///   with no green-grid flicker (2026-07-19 dev-log).
/// - **Mobile**: on for parity, but the least-exercised path - and the 96 MB
///   pyramid budget is a meaningful slice of a jetsam-limited process. A
///   memory-pressure regression here surfaces as tile eviction, not a crash;
///   [PdfTileStore.maxBytes] is live-adjustable if a lower mobile budget proves
///   necessary.
bool pdfDefaultTileStoreDetail() => true;

/// The default byte budget for the process-wide decoded-image cache
/// ([PdfImageCache]) on this platform.
///
/// ## What the budget actually buys
///
/// The budget is a ceiling, not a reservation: a document whose images decode
/// to 40 MB costs 40 MB under any budget. Raising it only changes behaviour for
/// documents that *exceed* it - and for those, measurements (issue #281) say a
/// budget short of the whole working set buys very little, because the cache
/// only pays off when it can hold everything a reader revisits:
///
/// - Decoded footprint of a 49-document real-world corpus: 88% fit in 64 MB,
///   94% in 128 MB, 96% in 256 MB. Beyond that the curve is flat - the only
///   documents left are a 1.2 GB and a 1.9 GB CAD drawing, which no sane budget
///   holds.
/// - On a 62-page print PDF whose images decode to 436 MB (so every budget
///   below is pegged and evicting), reading straight through: 64 MB → 180
///   ms/page, 128 MB → 147, 256 MB → 145. The last doubling buys 2 ms/page and
///   costs ~100 MB of RSS. Re-reading the same pages, where a fitting cache
///   would pay off, 256 MB → 149 ms/page against 128 MB's 164 - real, but only
///   a fifth of what actually holding the document (512 MB → 113 ms/page)
///   would give.
///
/// So the budget is sized to hold the *common* document outright, and is only
/// raised past that where the memory is genuinely free.
///
/// ## Why the platforms differ
///
/// - **Desktop** keeps 256 MB: it covers 96% of the corpus whole, and ~700 MB
///   of RSS on a pathological document is affordable where a machine has tens
///   of GB.
/// - **Mobile** takes 128 MB: it still covers 94% of documents outright, and on
///   the documents it cannot hold, the ~100 MB it gives back matters under an
///   iOS jetsam limit far more than 2 ms/page does.
/// - **Web** takes 128 MB, less on a small device. A tab is the tightest target
///   (Chrome caps the JS heap near 4 GB) and CanvasKit's wasm heap, where
///   decoded pixels live, never shrinks back. Notably this budget is *not* what
///   pressures a tab: measured over a 62-page scroll, tab memory ran to ~2.3 GB
///   whatever the budget, of which the image cache was ~60-200 MB - the rest is
///   per-page retention (issue #283). 128 MB is cheap insurance under a
///   ceiling that other retention is already spending, not a fix for it.
int pdfDefaultImageCacheBytes({
  PdfPerformancePlatform? platform,
  double? deviceMemoryGb,
}) {
  const mb = 1024 * 1024;
  final family = platform ?? detectedPdfPerformancePlatform;
  final ram = deviceMemoryGb ?? detectedPdfDeviceMemoryGb;
  return switch (family) {
    PdfPerformancePlatform.desktop => 256 * mb,
    PdfPerformancePlatform.mobile => 128 * mb,
    // Only Chromium reports deviceMemory, and only over a secure context, so
    // the constant is the common case rather than the fallback. A device that
    // admits to 2 GB or less is a phone browser, where the tab's ceiling is
    // lower than the desktop's by more than this budget is wide.
    PdfPerformancePlatform.web =>
      ram != null && ram <= 2 ? 64 * mb : 128 * mb,
    PdfPerformancePlatform.other => 128 * mb,
  };
}

/// The current auto-policy posture. Exposed in diagnostics and tests.
enum PdfPerformanceTier { conservative, balanced, throughput }

/// Fixed performance settings or an adaptive policy with a worker ceiling.
class PdfPerformanceMode {
  const PdfPerformanceMode.auto({this.maxWorkers = 4})
      : workerCount = null,
        previewWindow = null,
        imagePixelRatioCap = null,
        vectorFirstPreviews = null;

  const PdfPerformanceMode.fixed({
    required int workerCount,
    this.previewWindow = 6,
    this.imagePixelRatioCap = double.infinity,
    this.vectorFirstPreviews = false,
  })  : workerCount = workerCount,
        maxWorkers = workerCount;

  final int? workerCount;
  final int maxWorkers;
  final int? previewWindow;
  final double? imagePixelRatioCap;
  final bool? vectorFirstPreviews;

  bool get isAuto => workerCount == null;

  @override
  bool operator ==(Object other) =>
      other is PdfPerformanceMode &&
      workerCount == other.workerCount &&
      maxWorkers == other.maxWorkers &&
      previewWindow == other.previewWindow &&
      imagePixelRatioCap == other.imagePixelRatioCap &&
      vectorFirstPreviews == other.vectorFirstPreviews;

  @override
  int get hashCode => Object.hash(workerCount, maxWorkers, previewWindow,
      imagePixelRatioCap, vectorFirstPreviews);
}

/// Stable inputs known when a document worker is opened.
class PdfPerformanceEnvironment {
  const PdfPerformanceEnvironment({
    required this.platform,
    required this.logicalProcessors,
    required this.pageCount,
    required this.documentBytes,
  });

  factory PdfPerformanceEnvironment.detect({
    required int pageCount,
    required int documentBytes,
  }) {
    return PdfPerformanceEnvironment(
      platform: detectedPdfPerformancePlatform,
      logicalProcessors: detectedPdfLogicalProcessors,
      pageCount: pageCount,
      documentBytes: documentBytes,
    );
  }

  final PdfPerformancePlatform platform;
  final int logicalProcessors;
  final int pageCount;
  final int documentBytes;
}

/// One synthetic or observed performance sample. Durations are optional so
/// callers can feed the signals they own without manufacturing the rest.
class PdfPerformanceSample {
  const PdfPerformanceSample({
    this.workerRecordDuration,
    this.fullRenderDuration,
    this.resultBytes,
    this.jankyFrame = false,
  });

  final Duration? workerRecordDuration;
  final Duration? fullRenderDuration;
  final int? resultBytes;
  final bool jankyFrame;
}

/// Runtime knobs selected by [PdfPerformanceController].
class PdfPerformanceTuning {
  const PdfPerformanceTuning({
    required this.tier,
    required this.workerCount,
    required this.previewWindow,
    required this.imagePixelRatioCap,
    required this.vectorFirstPreviews,
  });

  final PdfPerformanceTier tier;

  /// Recommended count for the NEXT worker generation. Existing workers are
  /// never resized in place.
  final int workerCount;

  /// Pages on each side of the viewport worth warming.
  final int previewWindow;

  /// Maximum display pixels per PDF point requested in ordinary full-page
  /// worker records. Deep-zoom region requests remain uncapped.
  final double imagePixelRatioCap;

  /// Whether idle background warming should produce a vector/text preview
  /// before paying for the full image-bearing preview.
  final bool vectorFirstPreviews;

  @override
  bool operator ==(Object other) =>
      other is PdfPerformanceTuning &&
      tier == other.tier &&
      workerCount == other.workerCount &&
      previewWindow == other.previewWindow &&
      imagePixelRatioCap == other.imagePixelRatioCap &&
      vectorFirstPreviews == other.vectorFirstPreviews;

  @override
  int get hashCode => Object.hash(tier, workerCount, previewWindow,
      imagePixelRatioCap, vectorFirstPreviews);
}

/// Snapshot suitable for a diagnostics panel or support log.
class PdfPerformanceDiagnostics {
  const PdfPerformanceDiagnostics({
    required this.mode,
    required this.tuning,
    required this.currentWorkerCount,
    required this.pendingWorkerCount,
    required this.observations,
    required this.meanLatencyMs,
    required this.meanResultBytes,
    required this.jankFraction,
  });

  final PdfPerformanceMode mode;
  final PdfPerformanceTuning tuning;
  final int currentWorkerCount;
  final int? pendingWorkerCount;
  final int observations;
  final double meanLatencyMs;
  final double meanResultBytes;
  final double jankFraction;

  @override
  String toString() {
    final pending = pendingWorkerCount == null
        ? ''
        : ' pendingWorkers=$pendingWorkerCount(next restart)';
    return 'performance mode=${mode.isAuto ? 'auto' : 'fixed'} '
        'tier=${tuning.tier.name} workers=$currentWorkerCount$pending '
        'preview=${tuning.previewWindow} imageCap='
        '${tuning.imagePixelRatioCap.toStringAsFixed(2)} '
        'vectorFirst=${tuning.vectorFirstPreviews} samples=$observations '
        'latency=${meanLatencyMs.toStringAsFixed(1)}ms '
        'resultKB=${(meanResultBytes / 1024).toStringAsFixed(0)} '
        'jank=${(jankFraction * 100).toStringAsFixed(0)}%';
  }
}

/// Deterministic policy functions, split from the controller for direct tests.
class PdfPerformancePolicy {
  const PdfPerformancePolicy._();

  static PdfPerformanceTier initialTier(PdfPerformanceEnvironment env) =>
      env.documentBytes >= (192 << 20) || env.pageCount >= 300
          ? PdfPerformanceTier.conservative
          : PdfPerformanceTier.balanced;

  static int initialWorkerCount(
      PdfPerformanceEnvironment env, PdfPerformanceMode mode) {
    if (!mode.isAuto) return math.max(1, mode.workerCount!);
    if (env.pageCount < 12) return 1;

    final cores = env.logicalProcessors > 0 ? env.logicalProcessors : 4;
    final available = math.max(1, cores - 1);
    final platformBase = switch (env.platform) {
      PdfPerformancePlatform.mobile => 2,
      PdfPerformancePlatform.desktop => 3,
      PdfPerformancePlatform.web => 3,
      PdfPerformancePlatform.other => 2,
    };
    var count = math.min(platformBase, math.min(available, mode.maxWorkers));
    if (env.documentBytes >= (256 << 20)) {
      count = math.min(
          count, env.platform == PdfPerformancePlatform.mobile ? 1 : 2);
    }
    if (env.documentBytes >= (512 << 20)) count = 1;
    return math.max(1, count);
  }

  static PdfPerformanceTuning tuning({
    required PdfPerformanceEnvironment environment,
    required PdfPerformanceMode mode,
    required PdfPerformanceTier tier,
  }) {
    if (!mode.isAuto) {
      return PdfPerformanceTuning(
        tier: PdfPerformanceTier.balanced,
        workerCount: math.max(1, mode.workerCount!),
        previewWindow: math.max(1, mode.previewWindow!),
        imagePixelRatioCap: math.max(0.25, mode.imagePixelRatioCap!),
        vectorFirstPreviews: mode.vectorFirstPreviews!,
      );
    }

    final initial = initialWorkerCount(environment, mode);
    final maxForMachine = math.max(
      1,
      math.min(
          mode.maxWorkers,
          environment.logicalProcessors > 0
              ? math.max(1, environment.logicalProcessors - 1)
              : mode.maxWorkers),
    );
    return switch (tier) {
      PdfPerformanceTier.conservative => PdfPerformanceTuning(
          tier: tier,
          workerCount: math.max(1, initial - 1),
          previewWindow: 2,
          imagePixelRatioCap: 1.25,
          vectorFirstPreviews: true,
        ),
      PdfPerformanceTier.balanced => PdfPerformanceTuning(
          tier: tier,
          workerCount: initial,
          previewWindow: 6,
          imagePixelRatioCap: 2,
          vectorFirstPreviews: false,
        ),
      PdfPerformanceTier.throughput => PdfPerformanceTuning(
          tier: tier,
          workerCount: math.min(maxForMachine, initial + 1),
          previewWindow: 10,
          imagePixelRatioCap: 3,
          vectorFirstPreviews: false,
        ),
    };
  }
}

/// Owns adaptive state for one shell/viewer and exposes diagnostics.
///
/// Runtime-safe knobs update live. [beginWorkerGeneration] is the only method
/// that applies a new worker count, so observations never resize a pool during
/// scrolling; a changed recommendation remains visible as
/// [PdfPerformanceDiagnostics.pendingWorkerCount] until the host naturally
/// restarts the worker for a new document/revision.
class PdfPerformanceController extends ChangeNotifier {
  PdfPerformanceController({
    PdfPerformanceMode mode = const PdfPerformanceMode.auto(),
    PdfPerformanceEnvironment? environment,
  })  : _mode = mode,
        _environment = environment ??
            const PdfPerformanceEnvironment(
              platform: PdfPerformancePlatform.other,
              logicalProcessors: 0,
              pageCount: 1,
              documentBytes: 0,
            ) {
    _tier = PdfPerformancePolicy.initialTier(_environment);
    _tuning = PdfPerformancePolicy.tuning(
        environment: _environment, mode: _mode, tier: _tier);
  }

  PdfPerformanceMode _mode;
  late PdfPerformanceEnvironment _environment;
  late PdfPerformanceTier _tier;
  late PdfPerformanceTuning _tuning;
  int _currentWorkerCount = 0;
  int _observations = 0;
  int _cooldownUntil = 0;
  PdfPerformanceTier? _candidate;
  int _candidateStreak = 0;
  double _meanLatencyMs = 0;
  double _meanResultBytes = 0;
  double _jankFraction = 0;

  PdfPerformanceMode get mode => _mode;
  set mode(PdfPerformanceMode value) {
    if (value == _mode) return;
    _mode = value;
    _candidate = null;
    _candidateStreak = 0;
    _recompute(forceNotify: true);
  }

  PdfPerformanceTuning get tuning => _tuning;

  PdfPerformanceDiagnostics get diagnostics => PdfPerformanceDiagnostics(
        mode: _mode,
        tuning: _tuning,
        currentWorkerCount: _currentWorkerCount,
        pendingWorkerCount: _currentWorkerCount > 0 &&
                _currentWorkerCount != _tuning.workerCount
            ? _tuning.workerCount
            : null,
        observations: _observations,
        meanLatencyMs: _meanLatencyMs,
        meanResultBytes: _meanResultBytes,
        jankFraction: _jankFraction,
      );

  void configureDocument({required int pageCount, required int documentBytes}) {
    _environment = PdfPerformanceEnvironment.detect(
        pageCount: pageCount, documentBytes: documentBytes);
    _tier = PdfPerformancePolicy.initialTier(_environment);
    _observations = 0;
    _cooldownUntil = 0;
    _candidate = null;
    _candidateStreak = 0;
    _meanLatencyMs = 0;
    _meanResultBytes = 0;
    _jankFraction = 0;
    _recompute(forceNotify: true);
  }

  /// Applies the recommended count at a safe worker restart boundary.
  int beginWorkerGeneration() {
    final next = _tuning.workerCount;
    if (_currentWorkerCount != next) {
      _currentWorkerCount = next;
      notifyListeners();
    }
    return next;
  }

  void observe(PdfPerformanceSample sample) {
    if (!_mode.isAuto) return;
    _observations++;
    const alpha = 0.25;
    final record = sample.workerRecordDuration?.inMicroseconds;
    final render = sample.fullRenderDuration?.inMicroseconds;
    final latencyMicros = math.max(record ?? 0, render ?? 0);
    if (latencyMicros > 0) {
      final value = latencyMicros / 1000;
      _meanLatencyMs = _meanLatencyMs == 0
          ? value
          : _meanLatencyMs * (1 - alpha) + value * alpha;
    }
    if (sample.resultBytes case final bytes?) {
      _meanResultBytes = _meanResultBytes == 0
          ? bytes.toDouble()
          : _meanResultBytes * (1 - alpha) + bytes * alpha;
    }
    _jankFraction = _observations == 1
        ? (sample.jankyFrame ? 1 : 0)
        : _jankFraction * (1 - alpha) + (sample.jankyFrame ? 1 : 0) * alpha;

    final next = _classify(sample);
    if (next == _tier) {
      _candidate = null;
      _candidateStreak = 0;
      return;
    }
    if (_candidate == next) {
      _candidateStreak++;
    } else {
      _candidate = next;
      _candidateStreak = 1;
    }
    if (_candidateStreak < 3 || _observations < _cooldownUntil) return;
    _tier = next;
    _candidate = null;
    _candidateStreak = 0;
    _cooldownUntil = _observations + 5;
    _recompute();
  }

  PdfPerformanceTier _classify(PdfPerformanceSample sample) {
    final record = sample.workerRecordDuration?.inMicroseconds ?? 0;
    final render = sample.fullRenderDuration?.inMicroseconds ?? 0;
    final latencyMs = math.max(record, render) / 1000;
    final resultBytes = sample.resultBytes;
    if (latencyMs >= 120 ||
        (resultBytes != null && resultBytes >= (12 << 20)) ||
        sample.jankyFrame) {
      return PdfPerformanceTier.conservative;
    }
    if (latencyMs > 0 &&
        latencyMs < 35 &&
        (resultBytes == null || resultBytes < (2 << 20))) {
      return PdfPerformanceTier.throughput;
    }
    return PdfPerformanceTier.balanced;
  }

  void _recompute({bool forceNotify = false}) {
    final next = PdfPerformancePolicy.tuning(
        environment: _environment, mode: _mode, tier: _tier);
    if (next == _tuning && !forceNotify) return;
    _tuning = next;
    notifyListeners();
  }
}
