import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dart_pdf_editor_app/adaptive_memory.dart';
import 'package:dart_pdf_editor_app/devtools.dart';
import 'package:dart_pdf_editor_app/memory_snapshot.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const mb = 1024 * 1024;
  const gb = 1024 * mb;
  final tools = AppDevTools.instance;
  late int oldRegistryCeiling;
  late int oldLiveBudget;

  void resetAuto() {
    tools.setPageRasterCachePolicy(const PdfPageRasterCachePolicy());
    tools.updateAutoPageRasterCache(
      const PdfPageRasterCachePolicy(),
      reason: 'test reset',
    );
    tools.useAutoPageRasterCache();
  }

  setUp(() {
    oldRegistryCeiling = PdfCacheRegistry.instance.maxTotalWeight;
    oldLiveBudget = PdfLiveRasterBudget.instance.maxBytes;
    resetAuto();
  });

  tearDown(() {
    PdfCacheRegistry.instance.handleMemoryPressure();
    PdfCacheRegistry.instance.maxTotalWeight = oldRegistryCeiling;
    PdfLiveRasterBudget.instance.maxBytes = oldLiveBudget;
    resetAuto();
    tools.clearLog();
  });

  test('larger desktop machines receive larger bounded raster budgets', () {
    AdaptiveMemoryDecision desktop(int ramGb) => computeAdaptiveMemoryDecision(
          snapshot: AppMemorySnapshot(
            physicalBytes: ramGb * gb,
            availableBytes: (ramGb * .7 * gb).round(),
            processRssBytes: 400 * mb,
          ),
          platform: PdfPerformancePlatform.desktop,
          reclaimableRegistryBytes: 0,
          liveRasterBytes: 0,
        );

    final small = desktop(8);
    final large = desktop(64);
    expect(large.pageRasterPolicy.maxBytes,
        greaterThan(small.pageRasterPolicy.maxBytes));
    expect(large.pageRasterPolicy.maxBytes, 5 * gb,
        reason: 'a high-headroom workstation may use the configured hard cap');
    expect(small.pageRasterPolicy.maxBytes, lessThan(1 * gb));
    expect(large.pageRasterPolicy.maxEntryBytes, lessThanOrEqualTo(256 * mb));
  });

  test('falling available memory shrinks the decision immediately', () {
    AdaptiveMemoryDecision decide(int availableMb) =>
        computeAdaptiveMemoryDecision(
          snapshot: AppMemorySnapshot(
            physicalBytes: 16 * gb,
            availableBytes: availableMb * mb,
            processRssBytes: 900 * mb,
          ),
          platform: PdfPerformancePlatform.desktop,
          reclaimableRegistryBytes: 200 * mb,
          liveRasterBytes: 100 * mb,
        );

    final roomy = decide(8000);
    final tight = decide(500);
    expect(tight.safeProcessLimitBytes, lessThan(roomy.safeProcessLimitBytes));
    expect(tight.pageRasterPolicy.maxBytes,
        lessThan(roomy.pageRasterPolicy.maxBytes));
    expect(tight.reason, 'available-memory headroom');
  });

  test('mobile process limits cap exact rasters independently of device RAM',
      () {
    final decision = computeAdaptiveMemoryDecision(
      snapshot: const AppMemorySnapshot(
        physicalBytes: 16 * gb,
        availableBytes: 8 * gb,
        processRssBytes: 180 * mb,
        processLimitBytes: 768 * mb,
      ),
      platform: PdfPerformancePlatform.mobile,
      reclaimableRegistryBytes: 0,
      liveRasterBytes: 0,
    );

    expect(decision.safeProcessLimitBytes, lessThanOrEqualTo(768 * mb));
    expect(decision.pageRasterPolicy.maxBytes, lessThanOrEqualTo(256 * mb));
  });

  // Gives the process-wide registry real occupancy, so a pressure event is
  // judged against caches that are actually holding something. Without this the
  // registry is empty and the controller (rightly) declines to punish it.
  PdfBudgetedCache<int, int> heavyCache(int bytes) {
    final cache = PdfBudgetedCache<int, int>(
      weigher: (entry) => entry,
      maxWeight: bytes * 8,
      clearsUnderMemoryPressure: true, // what enrolls it in the registry
      debugLabel: 'test-heavy',
    );
    cache.put(0, bytes);
    addTearDown(cache.dispose);
    return cache;
  }

  test('pressure halves Auto immediately and rate-limits regrowth', () {
    var now = DateTime(2026, 7, 27, 12);
    final controller = AdaptiveMemoryBudgetController(
      platform: PdfPerformancePlatform.desktop,
      clock: () => now,
    );
    const roomy = AppMemorySnapshot(
      physicalBytes: 64 * gb,
      availableBytes: 40 * gb,
      processRssBytes: 400 * mb,
    );
    // The caches hold half the process here, so cutting them is a real
    // mitigation and the halving below is the right response.
    heavyCache(200 * mb);

    controller.applySnapshot(roomy);
    final before = tools.pageRasterCachePolicy.value.maxBytes;
    expect(before, 5 * gb);

    controller.didHaveMemoryPressure();
    final pressured = tools.pageRasterCachePolicy.value.maxBytes;
    expect(pressured, lessThanOrEqualTo(before ~/ 2));
    expect(tools.pageRasterCacheReason, contains('memory pressure'));

    now = now.add(const Duration(minutes: 1));
    controller.applySnapshot(roomy);
    expect(tools.pageRasterCachePolicy.value.maxBytes, pressured,
        reason: 'growth stays frozen during the pressure cooldown');

    now = now.add(const Duration(minutes: 5));
    controller.applySnapshot(roomy);
    final regrown = tools.pageRasterCachePolicy.value.maxBytes;
    expect(regrown, greaterThan(pressured));
    final growthLimit = pressured + 64 * mb > (pressured * 1.25).round()
        ? pressured + 64 * mb
        : (pressured * 1.25).round();
    expect(
      regrown,
      lessThanOrEqualTo(growthLimit),
      reason: 'one sample cannot jump straight back to 5 GB',
    );
  });

  test('pressure spares the caches when they are not where the memory is', () {
    var now = DateTime(2026, 7, 27, 12);
    final controller = AdaptiveMemoryBudgetController(
      platform: PdfPerformancePlatform.desktop,
      clock: () => now,
    );
    // 8MB of registered cache in a 1350MB process - the 2026-07-29 trace's
    // proportions. Halving the ceiling there reclaims essentially nothing and
    // costs every retained raster, so the pages re-rasterize, RSS climbs, the
    // next sample halves it again. The memory is in live rasters and worker
    // buffers, and those have their own budget.
    heavyCache(8 * mb);
    const tight = AppMemorySnapshot(
      physicalBytes: 16 * gb,
      availableBytes: 2 * gb,
      processRssBytes: 1350 * mb,
    );

    controller.applySnapshot(tight);
    final budgetBefore = tools.pageRasterCachePolicy.value.maxBytes;
    final ceilingBefore = PdfCacheRegistry.instance.maxTotalWeight;
    final liveBefore = PdfLiveRasterBudget.instance.maxBytes;

    controller.didHaveMemoryPressure();

    expect(tools.pageRasterCachePolicy.value.maxBytes, budgetBefore,
        reason: 'a cache holding 0.5% of RSS is not the thing to cut');
    expect(PdfLiveRasterBudget.instance.maxBytes, lessThan(liveBefore),
        reason: 'the live rasters ARE the large reconstructible allocation');
    expect(tools.pageRasterCacheReason, contains('ceiling held'));

    // ...and the cooldown must not then freeze the budget at a starved value:
    // with nothing cut, the next sample is free to track the machine again.
    now = now.add(const Duration(minutes: 1));
    controller.applySnapshot(tight);
    expect(PdfCacheRegistry.instance.maxTotalWeight,
        greaterThanOrEqualTo(ceilingBefore ~/ 2),
        reason: 'no lasting pressure cap was installed');
  });

  test('a fixed page override still obeys the process safety ceiling', () {
    tools.setPageRasterCachePolicy(const PdfPageRasterCachePolicy(
      maxBytes: 5 * gb,
      maxEntryBytes: 1 * gb,
    ));
    final controller = AdaptiveMemoryBudgetController(
      platform: PdfPerformancePlatform.desktop,
    );

    controller.applySnapshot(const AppMemorySnapshot(
      physicalBytes: 8 * gb,
      availableBytes: 2 * gb,
      processRssBytes: 700 * mb,
    ));

    expect(tools.pageRasterCachePolicy.value.maxBytes, 5 * gb,
        reason: 'the explicit diagnostic setting remains visible');
    expect(PdfCacheRegistry.instance.maxTotalWeight, lessThan(1 * gb),
        reason: 'actual combined cache occupancy keeps the machine-safe cap');
  });

  test('mobile backgrounding clears only visited-page raster caches', () {
    final pageCache = PdfBudgetedCache<int, int>(
      weigher: (value) => value,
      maxWeight: 1000,
      clearsUnderMemoryPressure: true,
      debugLabel: 'page-full-raster',
    );
    final otherCache = PdfBudgetedCache<int, int>(
      weigher: (value) => value,
      maxWeight: 1000,
      clearsUnderMemoryPressure: true,
      debugLabel: 'other-test-cache',
    );
    addTearDown(pageCache.dispose);
    addTearDown(otherCache.dispose);
    pageCache.put(0, 100);
    otherCache.put(0, 100);
    final controller = AdaptiveMemoryBudgetController(
      platform: PdfPerformancePlatform.mobile,
    );

    controller.didChangeAppLifecycleState(AppLifecycleState.hidden);

    expect(pageCache.length, 0);
    expect(otherCache.length, 1);
  });
}
