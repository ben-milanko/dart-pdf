// The devtools debug-overlay registries. Both are process singletons fed from
// page-view initState/dispose - which run mid-build, where a synchronous
// notifyListeners is a build-phase violation for a listening overlay (the
// crash that motivated the microtask coalescing). These tests pin the
// mutation logic AND that a burst of mutations coalesces to exactly one
// deferred notification.
import 'dart:ui' show Rect;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PdfTileRasterDiagnostics', () {
    final diagnostics = PdfTileRasterDiagnostics.instance;

    setUp(() async {
      diagnostics.clear();
      await pumpEventQueue();
    });

    tearDown(() async {
      diagnostics.clear();
      await pumpEventQueue();
    });

    test('publishes immutable typed routes and coalesces notifications',
        () async {
      final namespace = Object();
      var ticks = 0;
      void listener() => ticks++;
      diagnostics.addListener(listener);
      addTearDown(() => diagnostics.removeListener(listener));

      diagnostics.reportSession(
        cacheNamespace: namespace,
        document: Object(),
        scene: Object(),
        pageIndex: 2,
        requestedBackend: 'flutter_gpu',
        effectiveBackend: 'flutter_gpu',
        commandCount: 41,
        pageColor: 0xFFFFFFFF,
        annotations: true,
        rotation: 90,
      );
      diagnostics.reportTile(
        cacheNamespace: namespace,
        pageIndex: 2,
        region: const Rect.fromLTWH(0, 0, 10, 20),
        pixelRatio: 2,
        width: 20,
        height: 40,
      );

      expect(ticks, 0, reason: 'reports may arrive during lazy-page build');
      await pumpEventQueue();
      expect(ticks, 1);

      final accelerated = diagnostics.page(namespace, 2)!;
      expect(accelerated.pageNumber, 3);
      expect(accelerated.route, PdfTileRasterRoute.accelerated);
      expect(accelerated.tileRasters, 1);
      expect(accelerated.commandCount, 41);
      final namespaceEntries =
          diagnostics.forNamespace(identityHashCode(namespace));
      expect(namespaceEntries, hasLength(1));
      expect(namespaceEntries.single.pageIndex, accelerated.pageIndex);
      expect(namespaceEntries.single.route, accelerated.route);

      diagnostics.reportFallback(
        cacheNamespace: namespace,
        pageIndex: 2,
        error: StateError('device lost'),
      );
      await pumpEventQueue();
      final fallback = diagnostics.page(namespace, 2)!;
      expect(fallback.route, PdfTileRasterRoute.canvasFallback);
      expect(fallback.fallbackReason, contains('device lost'));
      expect(accelerated.route, PdfTileRasterRoute.accelerated,
          reason: 'previous snapshots stay immutable');
    });

    test('distinguishes an explicitly requested Canvas backend', () {
      final namespace = Object();
      diagnostics.reportSession(
        cacheNamespace: namespace,
        document: Object(),
        scene: Object(),
        pageIndex: 0,
        requestedBackend: 'canvas',
        effectiveBackend: 'canvas',
        commandCount: 3,
        pageColor: 0xFFFFFFFF,
        annotations: false,
        rotation: null,
      );
      expect(
        diagnostics.page(namespace, 0)!.route,
        PdfTileRasterRoute.canvas,
      );
    });
  });

  group('PdfLivePageRegistry', () {
    final registry = PdfLivePageRegistry.instance;

    // A singleton: leave it as we found it so tests stay order-independent.
    tearDown(() {
      for (final page in registry.pages.toList()) {
        registry.remove(page);
      }
    });

    test('add/remove/contains/length track the live set', () async {
      expect(registry.contains(3), isFalse);
      registry.add(3);
      registry.add(7);
      expect(registry.contains(3), isTrue);
      expect(registry.contains(7), isTrue);
      expect(registry.length, 2);
      expect(registry.pages, {3, 7});

      registry.remove(3);
      expect(registry.contains(3), isFalse);
      expect(registry.length, 1);
    });

    test('pages is an unmodifiable snapshot', () {
      registry.add(1);
      final view = registry.pages;
      expect(() => view.add(2), throwsUnsupportedError);
    });

    test('move relabels a slot without changing the count', () {
      registry.add(4);
      registry.add(5);
      registry.move(4, 9);
      expect(registry.contains(4), isFalse);
      expect(registry.contains(9), isTrue);
      expect(registry.contains(5), isTrue);
      expect(registry.length, 2);
    });

    test('a burst of mutations coalesces to one deferred notification',
        () async {
      var ticks = 0;
      void listener() => ticks++;
      registry.addListener(listener);
      addTearDown(() => registry.removeListener(listener));

      // Synchronous burst (a lazy list inflating a screenful of pages).
      registry.add(10);
      registry.add(11);
      registry.add(12);
      registry.move(12, 13);
      // Nothing has fired yet: the notify is deferred past the current stack.
      expect(ticks, 0, reason: 'notify must not run synchronously (mid-build)');

      await pumpEventQueue();
      expect(ticks, 1, reason: 'the whole burst coalesces to one tick');
    });

    test('a no-op mutation schedules no notification', () async {
      registry.add(20);
      await pumpEventQueue();

      var ticks = 0;
      void listener() => ticks++;
      registry.addListener(listener);
      addTearDown(() => registry.removeListener(listener));

      registry.add(20); // already present
      registry.remove(21); // absent
      registry.move(22, 22); // same slot
      await pumpEventQueue();
      expect(ticks, 0);
    });
  });

  group('PdfDebugDetailRegions', () {
    final regions = PdfDebugDetailRegions.instance;

    tearDown(() {
      for (final page in [0, 1, 2, 3]) {
        regions.report(page, null);
      }
    });

    test('report records and patchFractionOf reads back', () {
      const rect = Rect.fromLTRB(0.1, 0.2, 0.5, 0.6);
      expect(regions.patchFractionOf(0), isNull);
      regions.report(0, rect);
      expect(regions.patchFractionOf(0), rect);
    });

    test('reporting null clears the page', () {
      regions.report(1, const Rect.fromLTRB(0, 0, 1, 1));
      expect(regions.patchFractionOf(1), isNotNull);
      regions.report(1, null);
      expect(regions.patchFractionOf(1), isNull);
    });

    test('an unchanged report schedules no notification', () async {
      const rect = Rect.fromLTRB(0, 0, 0.5, 0.5);
      regions.report(2, rect);
      await pumpEventQueue();

      var ticks = 0;
      void listener() => ticks++;
      regions.addListener(listener);
      addTearDown(() => regions.removeListener(listener));

      regions.report(2, rect); // identical bounds
      regions.report(3, null); // clear an already-absent page
      await pumpEventQueue();
      expect(ticks, 0);
    });

    test('a burst of reports coalesces to one deferred notification', () async {
      var ticks = 0;
      void listener() => ticks++;
      regions.addListener(listener);
      addTearDown(() => regions.removeListener(listener));

      regions.report(0, const Rect.fromLTRB(0, 0, 0.2, 0.2));
      regions.report(1, const Rect.fromLTRB(0, 0, 0.3, 0.3));
      regions.report(2, const Rect.fromLTRB(0, 0, 0.4, 0.4));
      expect(ticks, 0, reason: 'notify must not run synchronously (mid-build)');

      await pumpEventQueue();
      expect(ticks, 1);
    });
  });

  group('pdfDebug flags', () {
    test('default off', () {
      expect(pdfDebugPaintDetailBounds.value, isFalse);
      expect(pdfDebugShowRenderWindow.value, isFalse);
      expect(pdfDebugShowGpuRasterRoutes.value, isFalse);
    });

    test('are ValueNotifiers that notify on change', () {
      var ticks = 0;
      void listener() => ticks++;
      pdfDebugPaintDetailBounds.addListener(listener);
      addTearDown(() {
        pdfDebugPaintDetailBounds.removeListener(listener);
        pdfDebugPaintDetailBounds.value = false;
        pdfDebugShowGpuRasterRoutes.value = false;
      });
      pdfDebugPaintDetailBounds.value = true;
      expect(ticks, 1);
    });
  });
}
