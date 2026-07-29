import 'dart:async';
import 'dart:math' as math;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/widgets.dart';

import 'devtools.dart';
import 'memory_probe.dart';
import 'memory_snapshot.dart';

const _mb = 1024 * 1024;
const _gb = 1024 * _mb;

typedef AppMemoryProbe = Future<AppMemorySnapshot?> Function();

/// One computed allocation across the caches that can be reconstructed.
@immutable
class AdaptiveMemoryDecision {
  const AdaptiveMemoryDecision({
    required this.pageRasterPolicy,
    required this.registryCeilingBytes,
    required this.liveRasterBudgetBytes,
    required this.safeProcessLimitBytes,
    required this.reason,
  });

  final PdfPageRasterCachePolicy pageRasterPolicy;
  final int registryCeilingBytes;
  final int liveRasterBudgetBytes;
  final int safeProcessLimitBytes;
  final String reason;
}

/// Computes a conservative process-wide cache allocation from one memory
/// snapshot. This is pure so synthetic 4/8/16/64-GB machines and low-headroom
/// transitions can be tested without allocating memory.
AdaptiveMemoryDecision computeAdaptiveMemoryDecision({
  required AppMemorySnapshot snapshot,
  required PdfPerformancePlatform platform,
  required int reclaimableRegistryBytes,
  required int liveRasterBytes,
  int maxPageRasterBytes = 5 * _gb,
}) {
  final physical = snapshot.physicalBytes;
  final rss = snapshot.processRssBytes;
  final available = snapshot.availableBytes;

  final candidates = <int>[];
  if (snapshot.processLimitBytes case final limit?) {
    candidates.add((limit * .72).round());
  }
  if (physical != null) {
    final fraction = switch (platform) {
      PdfPerformancePlatform.desktop => .20,
      PdfPerformancePlatform.mobile => .12,
      PdfPerformancePlatform.web => .10,
      PdfPerformancePlatform.other => .15,
    };
    candidates.add((physical * fraction).round());
  }
  if (rss != null && available != null) {
    final fraction = switch (platform) {
      PdfPerformancePlatform.desktop => .50,
      PdfPerformancePlatform.mobile => .30,
      PdfPerformancePlatform.web => .25,
      PdfPerformancePlatform.other => .35,
    };
    // Leave most currently-available memory to the OS and other apps. This
    // candidate makes the target fall immediately when system headroom falls.
    candidates.add(rss + (available * fraction).round());
  }

  final fallback = switch (platform) {
    PdfPerformancePlatform.desktop => 2 * _gb,
    PdfPerformancePlatform.mobile => 640 * _mb,
    PdfPerformancePlatform.web => 512 * _mb,
    PdfPerformancePlatform.other => 1 * _gb,
  };
  var safeProcessLimit =
      candidates.isEmpty ? fallback : candidates.reduce(math.min);
  final absoluteProcessCap = switch (platform) {
    PdfPerformancePlatform.desktop => 8 * _gb,
    PdfPerformancePlatform.mobile => 1280 * _mb,
    PdfPerformancePlatform.web => 1 * _gb,
    PdfPerformancePlatform.other => 2 * _gb,
  };
  safeProcessLimit = math.min(safeProcessLimit, absoluteProcessCap);

  final reserveBase = switch (platform) {
    PdfPerformancePlatform.desktop => 384 * _mb,
    PdfPerformancePlatform.mobile => 96 * _mb,
    PdfPerformancePlatform.web => 96 * _mb,
    PdfPerformancePlatform.other => 192 * _mb,
  };
  final reserveCap = switch (platform) {
    PdfPerformancePlatform.desktop => 1 * _gb,
    PdfPerformancePlatform.mobile => 192 * _mb,
    PdfPerformancePlatform.web => 192 * _mb,
    PdfPerformancePlatform.other => 512 * _mb,
  };
  final reserve = physical == null
      ? reserveBase
      : math.min(
          reserveCap,
          math.max(reserveBase, (physical * .04).round()),
        );

  final reclaimable = reclaimableRegistryBytes + liveRasterBytes;
  final estimatedNonCache = switch (platform) {
    PdfPerformancePlatform.desktop => 384 * _mb,
    PdfPerformancePlatform.mobile => 192 * _mb,
    PdfPerformancePlatform.web => 192 * _mb,
    PdfPerformancePlatform.other => 256 * _mb,
  };
  final nonCacheRss =
      rss == null ? estimatedNonCache : math.max(0, rss - reclaimable);
  final cacheEnvelope = math.max(0, safeProcessLimit - reserve - nonCacheRss);

  // Live viewport pages need priority: exact visited-page rasters are a revisit
  // optimization, while the live budget keeps the current page and neighbours
  // responsive. The focused page remains exempt even when this reaches zero.
  final defaultLive = pdfDefaultLiveRasterBudgetBytes(platform: platform);
  final liveBudget =
      math.max(32 * _mb, math.min(defaultLive, cacheEnvelope ~/ 4));
  final allocatableRegistry = math.max(0, cacheEnvelope - liveBudget);
  // PdfCacheRegistry uses zero to mean "ceiling disabled", so retain a small
  // positive floor even when the calculation leaves no speculative headroom.
  final registryCeiling = math.max(64 * _mb, allocatableRegistry);

  final platformPageCap = switch (platform) {
    PdfPerformancePlatform.desktop => maxPageRasterBytes,
    PdfPerformancePlatform.mobile => math.min(maxPageRasterBytes, 256 * _mb),
    PdfPerformancePlatform.web => math.min(maxPageRasterBytes, 256 * _mb),
    PdfPerformancePlatform.other => math.min(maxPageRasterBytes, 512 * _mb),
  };
  final pageBytes =
      math.min(platformPageCap, (allocatableRegistry * .88).round());
  final minimumEntry =
      platform == PdfPerformancePlatform.desktop ? 16 * _mb : 8 * _mb;
  final entryBytes = pageBytes == 0
      ? 0
      : math.min(
          pageBytes,
          math.min(
            256 * _mb,
            math.max(minimumEntry, pageBytes ~/ 8),
          ),
        );

  final hasMachineData = physical != null ||
      available != null ||
      snapshot.processLimitBytes != null;
  final constrainedByAvailability = rss != null &&
      available != null &&
      safeProcessLimit ==
          rss +
              (available *
                      switch (platform) {
                        PdfPerformancePlatform.desktop => .50,
                        PdfPerformancePlatform.mobile => .30,
                        PdfPerformancePlatform.web => .25,
                        PdfPerformancePlatform.other => .35,
                      })
                  .round();
  final reason = constrainedByAvailability
      ? 'available-memory headroom'
      : hasMachineData
          ? 'machine memory headroom'
          : 'conservative platform fallback';

  return AdaptiveMemoryDecision(
    pageRasterPolicy: PdfPageRasterCachePolicy(
      maxBytes: pageBytes,
      maxEntryBytes: entryBytes,
    ),
    registryCeilingBytes: registryCeiling,
    liveRasterBudgetBytes: liveBudget,
    safeProcessLimitBytes: safeProcessLimit,
    reason: reason,
  );
}

/// Samples machine memory and continuously tunes reconstructible PDF caches.
///
/// Shrinks are immediate. Growth is rate-limited after the first sample and
/// blocked for five minutes after memory pressure, avoiding oscillation around
/// an OS threshold. A fixed Developer-tools page budget still passes through
/// the process-wide registry ceiling, so a diagnostic 5-GB override cannot make
/// two viewers reserve 10 GB between them.
class AdaptiveMemoryBudgetController with WidgetsBindingObserver {
  AdaptiveMemoryBudgetController({
    AppDevTools? tools,
    AppMemoryProbe? probe,
    PdfPerformancePlatform? platform,
    DateTime Function()? clock,
    this.sampleInterval = const Duration(seconds: 15),
    this.growthInterval = const Duration(seconds: 45),
    this.pressureCooldown = const Duration(minutes: 5),
  })  : tools = tools ?? AppDevTools.instance,
        _probe = probe ?? readAppMemorySnapshot,
        platform = platform ?? detectedPdfPerformancePlatform,
        _clock = clock ?? DateTime.now;

  final AppDevTools tools;
  final AppMemoryProbe _probe;
  final PdfPerformancePlatform platform;
  final DateTime Function() _clock;
  final Duration sampleInterval;
  final Duration growthInterval;
  final Duration pressureCooldown;

  Timer? _timer;
  bool _started = false;
  bool _sampling = false;
  bool _hasSample = false;
  DateTime? _lastGrowth;
  DateTime? _lastPressure;
  int? _pressureRegistryCap;
  bool _lowMemoryActive = false;
  int? _lastRssBytes;

  /// Share of process RSS the registered caches must hold before a pressure
  /// event is allowed to shrink their ceiling for [pressureCooldown].
  ///
  /// Below this the caches are not what is consuming the process, and cutting
  /// them is not a mitigation - it is a self-inflicted wound with a feedback
  /// loop attached. The 2026-07-29 trace is the worked example: a low-memory
  /// signal at ~1350MB RSS reclaimed 22MB (1.6%) from a registry holding 7MB,
  /// halved the ceiling 140MB -> 70MB, and the pages whose rasters that ceiling
  /// had been retaining promptly re-rasterized four more times - raising RSS,
  /// arming the next sample, halving the ceiling again. The cache was never the
  /// problem; the live rasters and worker buffers were, and those are what
  /// [PdfLiveRasterBudget] governs.
  ///
  /// 5% is deliberately permissive: a registry genuinely holding hundreds of MB
  /// clears it easily and still gets the old behaviour.
  static const registryMaterialityPercent = 5;

  Future<void> start({bool periodic = true}) async {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    await sample();
    if (periodic && _started) {
      _timer = Timer.periodic(sampleInterval, (_) => unawaited(sample()));
    }
  }

  void dispose() {
    if (!_started) return;
    _started = false;
    _timer?.cancel();
    _timer = null;
    WidgetsBinding.instance.removeObserver(this);
  }

  Future<void> sample() async {
    if (!_started || _sampling) return;
    _sampling = true;
    try {
      final snapshot = await _probe() ?? const AppMemorySnapshot();
      if (!_started) return;
      // Kept across the low-memory early-return below: [_applyPressure] needs a
      // reading of the whole process to judge whether the caches it is about to
      // punish are where the memory actually is.
      _lastRssBytes = snapshot.processRssBytes ?? _lastRssBytes;
      if (snapshot.lowMemory) {
        if (!_lowMemoryActive) {
          _lowMemoryActive = true;
          _applyPressure('platform low-memory threshold');
        }
        return;
      }
      _lowMemoryActive = false;
      applySnapshot(snapshot);
    } catch (error) {
      tools.addLog('memory-auto: sample failed: $error',
          level: DevLogLevel.error);
    } finally {
      _sampling = false;
    }
  }

  @visibleForTesting
  void applySnapshot(AppMemorySnapshot snapshot) {
    final now = _clock();
    _lastRssBytes = snapshot.processRssBytes ?? _lastRssBytes;
    if (_lastPressure != null &&
        now.difference(_lastPressure!) >= pressureCooldown) {
      _pressureRegistryCap = null;
    }

    final decision = computeAdaptiveMemoryDecision(
      snapshot: snapshot,
      platform: platform,
      reclaimableRegistryBytes: PdfCacheRegistry.instance.totalWeight,
      liveRasterBytes: PdfLiveRasterBudget.instance.totalBytes,
    );

    var registryCeiling = decision.registryCeilingBytes;
    if (_pressureRegistryCap != null) {
      registryCeiling = math.min(registryCeiling, _pressureRegistryCap!);
    }
    PdfCacheRegistry.instance.maxTotalWeight = registryCeiling;
    PdfLiveRasterBudget.instance.maxBytes = decision.liveRasterBudgetBytes;

    var pagePolicy = decision.pageRasterPolicy;
    final current = tools.pageRasterCachePolicy.value;
    if (_hasSample && pagePolicy.maxBytes > current.maxBytes) {
      final inCooldown = _lastPressure != null &&
          now.difference(_lastPressure!) < pressureCooldown;
      final canGrow = !inCooldown &&
          (_lastGrowth == null ||
              now.difference(_lastGrowth!) >= growthInterval);
      if (!canGrow) {
        pagePolicy = PdfPageRasterCachePolicy(
          maxBytes: current.maxBytes,
          maxEntryBytes: math.min(
            current.maxBytes,
            current.maxEntryBytes,
          ),
        );
      } else {
        final growthLimit = math.max(
          current.maxBytes + 64 * _mb,
          (current.maxBytes * 1.25).round(),
        );
        final bytes = math.min(pagePolicy.maxBytes, growthLimit);
        pagePolicy = PdfPageRasterCachePolicy(
          maxBytes: bytes,
          maxEntryBytes: _entryLimitFor(bytes, platform),
        );
        _lastGrowth = now;
      }
    }

    _hasSample = true;
    tools.updateAutoPageRasterCache(
      pagePolicy,
      reason: decision.reason,
      safeProcessLimitBytes: decision.safeProcessLimitBytes,
    );
  }

  @override
  void didHaveMemoryPressure() => _applyPressure('OS memory pressure');

  void _applyPressure(String reason) {
    final now = _clock();
    // Coalesce a sustained low-memory state: repeated 15-second samples should
    // not halve an already-empty cache all the way to zero.
    if (_lastPressure != null &&
        now.difference(_lastPressure!) < const Duration(seconds: 30)) {
      return;
    }
    _lastPressure = now;
    final currentRegistry = PdfCacheRegistry.instance.maxTotalWeight;
    // Measured BEFORE the clear below, which is what makes this a judgement
    // about where the process's memory lives rather than a tautology.
    final registryHeld = PdfCacheRegistry.instance.totalWeight;
    final rss = _lastRssBytes;
    final registryIsMaterial = rss == null || rss <= 0
        ? true // no reading to judge by: keep the conservative old behaviour
        : registryHeld * 100 >= rss * registryMaterialityPercent;

    // Reclaim regardless: pressure is a hard signal and freeing what is
    // reclaimable is always right. It is the LASTING half of the old response -
    // the halved ceiling and halved page budget, both held for pressureCooldown
    // - that is gated, because that half is what starves the cache into the
    // re-raster loop when the memory was never in the cache to begin with.
    final freed = PdfCacheRegistry.instance.handleMemoryPressure();
    final liveFreed = PdfLiveRasterBudget.instance.evictReclaimable();
    if (registryIsMaterial) {
      _pressureRegistryCap = math.max(
        64 * _mb,
        currentRegistry > 0 ? currentRegistry ~/ 2 : 64 * _mb,
      );
      PdfCacheRegistry.instance.maxTotalWeight = _pressureRegistryCap!;
    }
    // Always halved: the live rasters ARE the process's large reconstructible
    // allocation, so this is the lever that corresponds to the signal.
    PdfLiveRasterBudget.instance.maxBytes = math.max(
      32 * _mb,
      PdfLiveRasterBudget.instance.maxBytes ~/ 2,
    );

    final current = tools.pageRasterCachePolicy.value;
    final bytes = !registryIsMaterial
        ? current.maxBytes
        : current.maxBytes == 0
            ? 0
            : math.max(
                platform == PdfPerformancePlatform.desktop
                    ? 32 * _mb
                    : 16 * _mb,
                current.maxBytes ~/ 2,
              );
    final share = rss == null || rss <= 0 ? null : registryHeld * 100 ~/ rss;
    final note = registryIsMaterial
        ? ''
        : '; caches held ${registryHeld >> 20}MB of ${rss >> 20}MB RSS '
            '($share%), ceiling held';
    tools.updateAutoPageRasterCache(
      PdfPageRasterCachePolicy(
        maxBytes: bytes,
        maxEntryBytes: _entryLimitFor(bytes, platform),
      ),
      reason: '$reason; ${freed + liveFreed >> 20}MB reclaimed$note',
      safeProcessLimitBytes: tools.safeProcessLimitBytes,
    );
    tools.addLog('memory-auto: $reason, reclaimed '
        '${(freed + liveFreed) >> 20}MB$note; growth paused for '
        '${pressureCooldown.inMinutes} min');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(sample());
      return;
    }
    if (platform != PdfPerformancePlatform.mobile ||
        (state != AppLifecycleState.hidden &&
            state != AppLifecycleState.paused &&
            state != AppLifecycleState.detached)) {
      return;
    }
    final freed = PdfCacheRegistry.instance.clearLabel('page-full-raster');
    if (freed > 0) {
      tools.addLog('memory-auto: backgrounded; cleared '
          '${freed >> 20}MB of visited-page rasters');
    }
  }
}

int _entryLimitFor(int bytes, PdfPerformancePlatform platform) {
  if (bytes <= 0) return 0;
  final floor = platform == PdfPerformancePlatform.desktop ? 16 * _mb : 8 * _mb;
  return math.min(bytes, math.min(256 * _mb, math.max(floor, bytes ~/ 8)));
}
