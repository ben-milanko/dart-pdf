// Devtools options persist across app restarts: every panel change writes
// the whole option set to SharedPreferences, and restoreOptions applies it
// over the platform defaults at startup.
import 'dart:convert';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/devtools.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    // Reset the globals the options touch so tests stay independent.
    AppDevTools.instance.setDeepZoomMode(AppDevTools.modePatch);
    pdfDebugPaintDetailBounds.value = false;
    pdfDebugShowRenderWindow.value = false;
    AppDevTools.instance.showPerformanceOverlay.value = false;
    AppDevTools.instance.setPageRasterCachePolicy(
      const PdfPageRasterCachePolicy(),
    );
    AppDevTools.instance.updateAutoPageRasterCache(
      const PdfPageRasterCachePolicy(),
      reason: 'test reset',
    );
    AppDevTools.instance.useAutoPageRasterCache();
    AppDevTools.instance
        .setPageRasterWarmPolicy(const PdfPageRasterWarmPolicy.disabled());
    AppDevTools.instance.setGpuTileBudgets(
      maxTextureBytes: 256 << 20,
      maxGeometryBytes: 256 << 20,
    );
    AppDevTools.instance.setGpuOverprintApproximation(false);
    AppDevTools.instance.setTileRasterBackendMode(TileRasterBackendMode.canvas);
    AppDevTools.instance.flutterGpuTileRasterBackend.stats.reset();
    PdfPerfLog.enabled = false;
    pdfRenderWorkerPoolSize = defaultPdfRenderWorkerPoolSize;
  });

  test('Canvas is the default tile raster backend', () {
    expect(
      AppDevTools.instance.tileRasterBackendMode.value,
      TileRasterBackendMode.canvas,
    );
  });

  test('options round-trip through SharedPreferences', () async {
    SharedPreferences.setMockInitialValues({});
    final tools = AppDevTools.instance;

    tools.setDeepZoomMode(AppDevTools.modeBatched);
    tools.setTileRasterBackendMode(TileRasterBackendMode.flutterGpu);
    tools.setGpuTileBudgets(
      maxTextureBytes: 1 << 30,
      maxGeometryBytes: 512 << 20,
    );
    tools.setGpuOverprintApproximation(true);
    pdfDebugPaintDetailBounds.value = true;
    pdfDebugShowRenderWindow.value = true;
    pdfRenderWorkerPoolSize = 5;
    tools.setPageRasterCachePolicy(const PdfPageRasterCachePolicy(
      maxBytes: 5 * 1024 * 1024 * 1024,
      maxEntryBytes: 128 * 1024 * 1024,
    ));
    await tools.persistOptions();

    // "Restart": globals back to defaults, then restore.
    tools.setDeepZoomMode(AppDevTools.modePatch);
    tools.setTileRasterBackendMode(TileRasterBackendMode.canvas);
    tools.setGpuTileBudgets(
      maxTextureBytes: 256 << 20,
      maxGeometryBytes: 256 << 20,
    );
    tools.setGpuOverprintApproximation(false);
    pdfDebugPaintDetailBounds.value = false;
    pdfDebugShowRenderWindow.value = false;
    pdfRenderWorkerPoolSize = 3;
    tools.setPageRasterCachePolicy(const PdfPageRasterCachePolicy());
    await tools.restoreOptions();

    expect(tools.deepZoomMode, AppDevTools.modeBatched);
    expect(tools.tileRasterBackendMode.value, TileRasterBackendMode.flutterGpu);
    expect(tools.flutterGpuTileRasterBackend.maxTextureBytes, 1 << 30);
    expect(tools.flutterGpuTileRasterBackend.maxGeometryBytes, 512 << 20);
    expect(tools.gpuOverprintApproximation, isTrue);
    expect(
        tools.flutterGpuTileRasterBackend.allowOverprintApproximation, isTrue);
    expect(PdfPageView.tileStoreDetail, isTrue);
    expect(PdfPageView.debugTileStoreOverride!.batchRasters, isTrue);
    expect(pdfDebugPaintDetailBounds.value, isTrue);
    expect(pdfDebugShowRenderWindow.value, isTrue);
    expect(pdfRenderWorkerPoolSize, 5);
    expect(
      tools.pageRasterCachePolicy.value,
      const PdfPageRasterCachePolicy(
        maxBytes: 5 * 1024 * 1024 * 1024,
        maxEntryBytes: 128 * 1024 * 1024,
      ),
    );
    expect(tools.pageRasterCacheMode, PageRasterCacheMode.fixed);
  });

  test('Auto mode round-trips independently of its effective budget', () async {
    SharedPreferences.setMockInitialValues({});
    final tools = AppDevTools.instance;
    tools.setPageRasterCachePolicy(const PdfPageRasterCachePolicy(
      maxBytes: 5 * 1024 * 1024 * 1024,
      maxEntryBytes: 128 * 1024 * 1024,
    ));
    tools.updateAutoPageRasterCache(
      const PdfPageRasterCachePolicy(
        maxBytes: 512 * 1024 * 1024,
        maxEntryBytes: 64 * 1024 * 1024,
      ),
      reason: 'test machine headroom',
    );
    tools.useAutoPageRasterCache();
    await tools.persistOptions();

    tools.setPageRasterCachePolicy(const PdfPageRasterCachePolicy.disabled());
    await tools.restoreOptions();

    expect(tools.pageRasterCacheMode, PageRasterCacheMode.auto);
    expect(
      tools.fixedPageRasterCachePolicy.maxBytes,
      5 * 1024 * 1024 * 1024,
      reason: 'the last fixed diagnostic preset is retained behind Auto',
    );
  });

  test('the idle raster warm policy round-trips', () async {
    SharedPreferences.setMockInitialValues({});
    final tools = AppDevTools.instance;
    expect(tools.pageRasterWarmPolicy.value.enabled, isFalse,
        reason: 'warming is off until a host asks for it');

    tools.setPageRasterWarmPolicy(
        const PdfPageRasterWarmPolicy.nearby(window: 5));
    await tools.persistOptions();

    tools.setPageRasterWarmPolicy(const PdfPageRasterWarmPolicy.disabled());
    await tools.restoreOptions();
    expect(tools.pageRasterWarmPolicy.value,
        const PdfPageRasterWarmPolicy.nearby(window: 5));

    tools.setPageRasterWarmPolicy(const PdfPageRasterWarmPolicy.document());
    await tools.persistOptions();
    tools.setPageRasterWarmPolicy(const PdfPageRasterWarmPolicy.disabled());
    await tools.restoreOptions();
    expect(
        tools.pageRasterWarmPolicy.value.mode, PdfPageRasterWarmMode.document);
  });

  test('restore with nothing persisted leaves the defaults alone', () async {
    SharedPreferences.setMockInitialValues({});
    pdfRenderWorkerPoolSize = 3;
    AppDevTools.instance.setTileRasterBackendMode(TileRasterBackendMode.canvas);
    AppDevTools.instance.setPageRasterCachePolicy(
      const PdfPageRasterCachePolicy(),
    );
    AppDevTools.instance.updateAutoPageRasterCache(
      const PdfPageRasterCachePolicy(),
      reason: 'test reset',
    );
    AppDevTools.instance.useAutoPageRasterCache();
    await AppDevTools.instance.restoreOptions();
    expect(AppDevTools.instance.deepZoomMode, AppDevTools.modePatch);
    expect(
      AppDevTools.instance.tileRasterBackendMode.value,
      TileRasterBackendMode.canvas,
    );
    expect(pdfRenderWorkerPoolSize, 3);
    expect(
      AppDevTools.instance.pageRasterCachePolicy.value,
      const PdfPageRasterCachePolicy(),
    );
    expect(AppDevTools.instance.pageRasterWarmPolicy.value.enabled, isFalse);
  });

  test('legacy automatic flutter_gpu selection migrates to Canvas', () async {
    SharedPreferences.setMockInitialValues({
      'flutter.devtools.options': jsonEncode({
        'tileRasterBackend': TileRasterBackendMode.flutterGpu.name,
      }),
    });
    final tools = AppDevTools.instance;
    tools.setTileRasterBackendMode(TileRasterBackendMode.flutterGpu);

    await tools.restoreOptions();

    expect(tools.tileRasterBackendMode.value, TileRasterBackendMode.canvas);

    await tools.persistOptions();
    final stored =
        (await SharedPreferences.getInstance()).getString('devtools.options');
    expect(jsonDecode(stored!)['flutterGpuOptIn'], isFalse);
  });

  test('a corrupt payload is logged, not thrown', () async {
    SharedPreferences.setMockInitialValues(
        {'flutter.devtools.options': '{not json'});
    await AppDevTools.instance.restoreOptions();
    expect(
      AppDevTools.instance.log
          .any((e) => e.message.contains('devtools options restore failed')),
      isTrue,
    );
  });
}
