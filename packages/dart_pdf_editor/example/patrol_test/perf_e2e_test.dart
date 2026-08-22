// Patrol targets live outside Flutter's conventional test/ directory, but
// this is still test code and deliberately exercises the diagnostic seams.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor_assets/dart_pdf_editor_assets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:pdf_test_fixtures/cad_image_strip.dart';

const _buildCommit = String.fromEnvironment('PDF_BUILD_COMMIT');
const _mb = 1024 * 1024;

void main() {
  // Patrol owns the entrypoint, so the example app's main() does not register
  // its optional assets for us. Keep this benchmark on the production web
  // path: the bundled worker must open the document and return a real trace.
  registerBundledEditorAssets();
  pdfRenderWorkerScriptUrl = 'pdf_render_worker.dart.js';

  if (_buildCommit.isNotEmpty) {
    PdfPerfLog.buildTag = 'commit=$_buildCommit';
  }

  patrolTest(
      'retains capped rasters, reuses previews, and keys pure page reorders',
      ($) async {
    // This target is deliberately run only by the web lane with a 2600px
    // viewport. At that width a letter page reaches the whole-page pixel cap,
    // producing the ~16.01 MiB RGBA raster that exposed the admission-floor
    // bug. A normal phone-sized native viewport would not exercise that seam.
    expect($.isWeb, isTrue);

    final preferences = PdfEditingPreferences();
    await preferences.ready;
    preferences
      ..showThumbnailSidebar = false
      ..showBookmarkSidebar = false
      ..showAnnotationSidebar = false
      ..showPropertiesPanel = false
      ..showSearchResultsPanel = false
      ..showThumbnailView = false
      ..showReflowView = false;
    final editing = PdfEditingController(
      _buildPerfDocument(),
      preferences: preferences,
    );
    final viewer = PdfViewerController();
    PdfThumbnailSidebar.debugRasterizations = 0;

    PdfPerfLog.log(
      'scenario name=heavy-document phase=start pages=${editing.document.pageCount}',
    );
    PdfPerfLog.log(
      'scenario name=web-worker phase=start backend=production',
    );
    try {
      await $.pumpWidget(MaterialApp(
        home: PdfEditorView(
          controller: editing,
          viewerController: viewer,
          initialFit: PdfViewerFit.width,
          features: const PdfEditorFeatures(
            headerBar: false,
            search: false,
            searchResultsPanel: false,
            pageNumber: false,
            author: false,
            viewOptions: false,
            reflowView: false,
            pageColorEditable: false,
            bookmarks: false,
            annotationSidebar: false,
            propertiesPanel: false,
            toolbar: false,
          ),
          // Mirrors the app's admission policy while idle warming is active.
          // The entry floor intentionally sits above the renderer's capped
          // image after independent edge rounding.
          pageRasterCachePolicy: const PdfPageRasterCachePolicy(
            maxBytes: 64 * _mb,
            maxEntryBytes: 24 * _mb,
          ),
          pageRasterWarmPolicy: const PdfPageRasterWarmPolicy.nearby(
            window: 3,
            // The test invokes the pass explicitly after foreground work is
            // quiet; a long automatic delay removes timer races from CI.
            idleDelay: Duration(hours: 1),
          ),
        ),
      ));

      await _waitFor(
        $,
        () => viewer.pageCount == 6 && viewer.isPageRasterReady(0),
        reason: 'the capped first-page raster should finish',
      );
      await _waitFor(
        $,
        () => viewer.debugRenderWorkerActive,
        reason: 'the production web render worker should stay active',
      );
      await _waitFor(
        $,
        () => viewer.debugLastRenderTrace != null,
        reason: 'an off-thread page render should complete with phase timings',
      );
      final workerTrace = viewer.debugLastRenderTrace!;
      expect(workerTrace.pageIndex, inInclusiveRange(0, 5));
      PdfPerfLog.log(
        'scenario name=web-worker phase=validated '
        'page=${workerTrace.pageIndex} total=${workerTrace.endToEndUs}us',
      );
      await _waitFor(
        $,
        () => !viewer.isPageRenderBusy,
        reason: 'foreground rendering should settle before idle warming',
      );
      await _waitFor(
        $,
        () => (viewer.pageRasterWarmStats?.entries ?? 0) > 0,
        reason: 'the completed display raster should enter the exact cache',
      );
      await $.pump(const Duration(milliseconds: 350));

      var stats = viewer.pageRasterWarmStats!;
      expect(
        stats.retainedBytes ~/ stats.entries,
        greaterThan(16 * _mb),
        reason: 'each capped fit-width raster should cross the historical '
            '16 MiB admission boundary',
      );

      // Web intentionally avoids a second readback of the just-painted page.
      // Wait for the idle offscreen prerender to seed the shared low-res tier
      // that the thumbnail panel is expected to consume.
      int? previewPage;
      await _waitFor(
        $,
        () {
          final cache = viewer.pagePreviewCache;
          if (cache == null) return false;
          for (var page = 1; page < editing.document.pageCount; page++) {
            if (cache.isFresh(
              page,
              editing.pageAt(page),
              requireImages: true,
            )) {
              previewPage = page;
              return true;
            }
          }
          return false;
        },
        reason: 'idle prerender should seed an offscreen web preview',
      );

      final warm = viewer.debugWarmFullRasters();
      for (var i = 0; i < 80 && viewer.debugRasterWarming; i++) {
        await $.pump(const Duration(milliseconds: 100));
      }
      await warm.timeout(const Duration(seconds: 30));
      stats = viewer.pageRasterWarmStats!;
      expect(stats.attempts, greaterThan(0));
      expect(stats.completions, greaterThan(0));
      expect(stats.rejected, 0,
          reason: 'the 24 MiB warm entry floor must admit capped pages');

      // Prove the viewer's complete preview is large enough for the sidebar's
      // web softness allowance before mounting the panel that consumes it.
      final previewCache = viewer.pagePreviewCache!;
      previewPage = null;
      for (var page = 1; page < editing.document.pageCount; page++) {
        if (previewCache.isFresh(
          page,
          editing.pageAt(page),
          requireImages: true,
          targetLongestSide: 400,
        )) {
          previewPage = page;
          break;
        }
      }
      expect(previewPage, isNotNull,
          reason: 'a complete 400px preview should survive exact warming');
      final reusable = previewCache.thumbnailImageFor(
        previewPage!,
        editing.pageAt(previewPage!),
        width: 192,
        height: 249,
        minimumScale: 0.75,
      );
      expect(reusable, isNotNull);
      reusable!.dispose();

      preferences.showThumbnailSidebar = true;
      await _waitFor(
        $,
        () => find.byType(PdfThumbnailSidebar).evaluate().isNotEmpty,
        reason: 'the thumbnail panel should mount from preferences',
      );
      await _waitFor(
        $,
        () => find
            .descendant(
              of: find.byType(PdfThumbnailSidebar),
              matching: find.byType(RawImage),
            )
            .evaluate()
            .isNotEmpty,
        reason: 'the panel should paint a preview-backed thumbnail',
      );

      final originalFirst = viewer.debugPageIdentity(0);
      final originalState = $.tester.state(find.byWidgetPredicate(
        (widget) =>
            widget is PdfPageView && identical(widget.page, originalFirst),
      ));
      final presentationEpoch = viewer.pagePresentationEpoch;
      final tileNamespace = viewer.debugTileCacheNamespace;
      final keyedBefore = viewer.debugKeyedPageReconciliations;
      editing.movePage(0, editing.document.pageCount - 1);
      await _waitFor(
        $,
        () => viewer.debugKeyedPageReconciliations == keyedBefore + 1,
        reason: 'a pure move must use stable page identities',
      );
      expect(
        viewer.debugPageReconciliationDiagnostics!.mode,
        PdfPageReconciliationMode.keyedStructure,
      );
      expect(
        viewer.debugPageIdentity(editing.document.pageCount - 1),
        isNot(same(originalFirst)),
        reason: 'the page wrapper must belong to the current revision',
      );
      final reorderedFirst = viewer.debugPageIdentity(
        editing.document.pageCount - 1,
      );
      final reorderedFirstView = find.byWidgetPredicate(
        (widget) =>
            widget is PdfPageView && identical(widget.page, reorderedFirst),
      );
      await _waitFor(
        $,
        () => reorderedFirstView.evaluate().isNotEmpty,
        reason: 'the remapped viewport should build the moved page',
      );
      expect(
        $.tester.state(reorderedFirstView),
        same(originalState),
        reason: 'the moved page State should follow its stable page key',
      );
      expect(viewer.pagePresentationEpoch, presentationEpoch);
      expect(viewer.debugTileCacheNamespace, same(tileNamespace));

      PdfPerfLog.log(
        'scenario name=heavy-document phase=validated '
        'rasterBytes=${stats.retainedBytes} rasterEntries=${stats.entries} '
        'warmCompletions=${stats.completions} '
        'thumbnailRasters=${PdfThumbnailSidebar.debugRasterizations} '
        'keyed=${viewer.debugKeyedPageReconciliations}',
      );
    } finally {
      await $.pumpWidget(const SizedBox());
      await $.pump(const Duration(milliseconds: 50));
      viewer.dispose();
      editing.dispose();
      preferences.dispose();
    }
  });

  patrolTest('deep-zooms an image-heavy CAD sheet through worker-backed tiles',
      ($) async {
    expect($.isWeb, isTrue);

    // Build before opening the scenario window: this journey measures the
    // viewer/worker pipeline, not fixture compression. Eighteen 1024x768 image
    // XObjects represent ~54 MiB if all are decoded to RGBA, while the wide
    // page and 30k vector operations force the dense-page region/tile route.
    final bytes = _buildCadPerfDocument();
    final preferences = PdfEditingPreferences();
    await preferences.ready;
    preferences
      ..showThumbnailSidebar = false
      ..showBookmarkSidebar = false
      ..showAnnotationSidebar = false
      ..showPropertiesPanel = false
      ..showSearchResultsPanel = false
      ..showThumbnailView = false
      ..showReflowView = false;
    final editing = PdfEditingController(bytes, preferences: preferences);
    final viewer = PdfViewerController();
    final tileStore = PdfTileStore.instance;
    final tilesLandedBefore = tileStore.debugTilesLanded;
    final imageAdoptionsBefore = PdfPageView.debugTileImageDetailAdoptions;

    PdfPerfLog.log(
      'scenario name=cad-image-deep-zoom phase=start pages=1 '
      'images=18 decodedRgbaBytes=${18 * 1024 * 768 * 4} ops=30000',
    );
    try {
      await $.pumpWidget(MaterialApp(
        home: PdfEditorView(
          controller: editing,
          viewerController: viewer,
          initialFit: PdfViewerFit.width,
          features: const PdfEditorFeatures(
            headerBar: false,
            search: false,
            searchResultsPanel: false,
            pageNumber: false,
            author: false,
            viewOptions: false,
            reflowView: false,
            pageColorEditable: false,
            bookmarks: false,
            annotationSidebar: false,
            propertiesPanel: false,
            toolbar: false,
          ),
        ),
      ));

      await _waitFor(
        $,
        () => viewer.pageCount == 1 && viewer.debugRenderWorkerActive,
        reason: 'the CAD document should open on the production worker',
        attempts: 240,
      );
      await _waitFor(
        $,
        () => viewer.isPageRasterReady(0),
        reason: 'the CAD fit-width backing raster should finish',
        attempts: 300,
      );

      PdfRenderTrace? fitTrace;
      await _waitFor(
        $,
        () {
          final trace = viewer.debugLastRenderTrace;
          if (trace == null ||
              trace.pageIndex != 0 ||
              trace.decodeUs <= 0 ||
              trace.imageDecodeSummary == null) {
            return false;
          }
          fitTrace = trace.copy();
          return true;
        },
        reason: 'the worker should report a real browser image decode',
        attempts: 240,
      );

      // At 400%, only a window of this 10:1 sheet is visible. The dense scene
      // must warm its spatial index off-thread, re-decode intersecting images
      // for that window, and populate reusable fixed-size tiles.
      // The initial worker decode carries 2x image headroom by design, so 2x
      // would correctly remain on the whole-page raster without exercising
      // the incremental detail path this journey is intended to validate.
      viewer.setZoom(4);
      final deepZoom = viewer.captureViewport();
      expect(deepZoom, isNotNull);
      // setZoom focuses the viewport centre. This ultra-wide page is only
      // ~258px tall at fit width, so the centre is empty canvas and the page
      // would otherwise zoom out of view. Re-anchor the completed zoom onto
      // the sheet; PdfViewport stores the fit-relative multiplier rather than
      // the controller's public px/pt zoom.
      viewer.restoreViewport(PdfViewport(
        page: 0,
        left: 0.02,
        zoom: deepZoom!.zoom,
      ));
      await $.pump(const Duration(milliseconds: 300));
      expect(viewer.zoom, closeTo(4, 0.05));
      PdfPerfLog.log(
        'scenario name=cad-image-deep-zoom phase=zoom '
        'display=${viewer.zoom.toStringAsFixed(2)} '
        'viewport=${deepZoom.zoom.toStringAsFixed(2)}',
      );
      await _waitFor(
        $,
        () =>
            PdfPageView.debugTileImageDetailAdoptions > imageAdoptionsBefore &&
            tileStore.debugTilesLanded > tilesLandedBefore &&
            find
                .byKey(const ValueKey('pdf-page-tile-layer'))
                .evaluate()
                .isNotEmpty,
        reason: 'deep zoom should adopt image detail and land CAD tiles',
        attempts: 360,
      );

      // Visit three distant windows. Returning to the first one leaves the
      // cache free to prove reuse in later traces while this journey records
      // the one-time decode/bin cost and the incremental edge-tile fills.
      for (final left in const [0.02, 0.48, 0.90, 0.02]) {
        viewer.restoreViewport(PdfViewport(
          page: 0,
          left: left,
          zoom: deepZoom.zoom,
        ));
        await $.pump(const Duration(milliseconds: 400));
        await $.pump(const Duration(milliseconds: 100));
      }
      await _waitFor(
        $,
        () => tileStore.inFlightCount == 0,
        reason: 'CAD tile work should settle after the pan sequence',
        attempts: 360,
      );

      final tilesLanded = tileStore.debugTilesLanded - tilesLandedBefore;
      final imageAdoptions =
          PdfPageView.debugTileImageDetailAdoptions - imageAdoptionsBefore;
      final trace = viewer.debugLastRenderTrace ?? fitTrace!;
      expect(tilesLanded, greaterThan(0));
      expect(imageAdoptions, greaterThan(0));
      expect(tileStore.retainedBytes, greaterThan(0));
      expect(trace.endToEndUs, greaterThan(0));

      PdfPerfLog.log(
        'scenario name=cad-image-deep-zoom phase=validated '
        'tilesLanded=$tilesLanded tileCount=${tileStore.tileCount} '
        'tileBytes=${tileStore.retainedBytes} '
        'imageAdoptions=$imageAdoptions '
        'fitTotal=${fitTrace!.endToEndUs}us '
        'fitWorker=${fitTrace!.workerUs}us fitDecode=${fitTrace!.decodeUs}us '
        'lastTotal=${trace.endToEndUs}us lastDecode=${trace.decodeUs}us',
      );
    } finally {
      await $.pumpWidget(const SizedBox());
      await $.pump(const Duration(milliseconds: 50));
      viewer.dispose();
      editing.dispose();
      preferences.dispose();
    }
  });
}

Future<void> _waitFor(
  PatrolIntegrationTester $,
  bool Function() predicate, {
  required String reason,
  int attempts = 120,
}) async {
  for (var i = 0; i < attempts && !predicate(); i++) {
    await $.pump(const Duration(milliseconds: 100));
  }
  expect(predicate(), isTrue, reason: reason);
}

/// A deterministic, browser-safe six-page drawing.
///
/// The repeated linework gives the render and preview paths meaningful work
/// without depending on a corpus file or network fetch. All arithmetic stays
/// comfortably inside JavaScript's exact integer range, unlike the VM-only
/// 64-bit CAD fixture generator used by the benchmark suite.
Uint8List _buildPerfDocument() {
  const pageCount = 6;
  final objects = <String>[];
  final kids = [
    for (var i = 0; i < pageCount; i++) '${3 + i * 2} 0 R',
  ].join(' ');
  final fontNumber = 3 + pageCount * 2;
  objects
    ..add('<< /Type /Catalog /Pages 2 0 R >>')
    ..add('<< /Type /Pages /Kids [$kids] /Count $pageCount >>');

  for (var page = 0; page < pageCount; page++) {
    final content = StringBuffer()
      ..writeln('q 0.35 w 0.12 0.18 0.24 RG')
      ..writeln('24 24 564 744 re S');
    // Stay over PdfPageView's 5k-command direct-picture threshold: the
    // scenario must produce a whole-page raster, not retain a display list.
    for (var i = 0; i < 6000; i++) {
      final x = 30 + ((i * 37 + page * 19) % 540);
      final y = 34 + ((i * 53 + page * 23) % 710);
      final dx = 8 + (i % 37);
      final dy = (i % 9) - 4;
      content.writeln('$x $y m ${x + dx} ${y + dy} l S');
      if (i % 80 == 0) {
        content.writeln(
          '0.88 g ${36 + (i % 480)} ${48 + (i % 660)} 24 12 re f '
          '0.12 0.18 0.24 RG',
        );
      }
    }
    content
      ..writeln('BT /F1 20 Tf 42 744 Td (Patrol perf page ${page + 1}) Tj ET')
      ..writeln('Q');
    final body = content.toString();
    objects
      ..add('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
          '/Contents ${4 + page * 2} 0 R '
          '/Resources << /Font << /F1 $fontNumber 0 R >> >> >>')
      ..add('<< /Length ${body.length} >>\nstream\n$body\nendstream');
  }
  objects.add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');

  final output = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(output.length);
    output.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xrefOffset = output.length;
  output
    ..write('xref\n0 ${objects.length + 1}\n')
    ..write('0000000000 65535 f \n');
  for (final offset in offsets) {
    output.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  output
    ..write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n')
    ..write('startxref\n$xrefOffset\n%%EOF\n');
  return Uint8List.fromList(output.toString().codeUnits);
}

Uint8List _buildCadPerfDocument() {
  final tiles = <PdfTileSpec>[
    for (var i = 0; i < 18; i++)
      PdfTileSpec(
        codec: i == 17
            ? PdfTileCodec.indexed
            : i % 3 == 2
                ? PdfTileCodec.flateRgb
                : PdfTileCodec.imageMask,
        width: 1024,
        height: 768,
      ),
  ];
  return buildSyntheticCadImageStrip(
    tiles: tiles,
    ops: 30000,
    streams: 4,
  );
}
