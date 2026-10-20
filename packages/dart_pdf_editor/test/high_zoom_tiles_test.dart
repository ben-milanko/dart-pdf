import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

void main() {
  testWidgets('grouped PDF reuses sharp tiles while panning at 10000%',
      (tester) async {
    tester.view.physicalSize = const ui.Size(768, 576);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final store = PdfTileStore(
      tilePixels: 256,
      maxBytes: 16 << 20,
      prefetchRing: 0,
      registerForMemoryPressure: false,
    );
    final backend = _CountingCanvasBackend();
    final oldTiles = PdfPageView.tileStoreDetail;
    final oldStore = PdfPageView.debugTileStoreOverride;
    PdfPageView.tileStoreDetail = true;
    PdfPageView.debugTileStoreOverride = store;
    addTearDown(() {
      PdfPageView.tileStoreDetail = oldTiles;
      PdfPageView.debugTileStoreOverride = oldStore;
      store.dispose();
    });

    final page = PdfDocument.open(_groupedSheet()).page(0);
    const pagePoints = 64.0;
    const zoom = 100.0;
    const desiredRatio = zoom * 3;
    final rung = store.ladder.rungAtOrAbove(desiredRatio);
    final ratio = store.ladder.ratioFor(rung);
    // Translate by exactly one tile column, in logical display pixels.
    final pan = store.tilePixels / ratio * zoom;

    Widget build(double dx, int generation) => MediaQuery.fromView(
          view: tester.view,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: Transform.translate(
                offset: Offset(dx, 0),
                child: OverflowBox(
                  maxWidth: double.infinity,
                  maxHeight: double.infinity,
                  child: SizedBox(
                    width: pagePoints * zoom,
                    child: PdfPageView(
                      page: page,
                      settleGeneration: generation,
                      tileRasterBackend: backend,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

    await tester.pumpWidget(build(0, 0));
    await _waitForTiles(tester, store);
    expect(find.byKey(const ValueKey('pdf-page-tile-layer')), findsOneWidget,
        reason: 'a small transparency group must not veto tiling the page');
    expect(tester.getSize(find.byType(PdfPageView)).width / pagePoints, zoom);
    expect(
        backend.scene!.commands.whereType<PdfBeginGroupCommand>(), isNotEmpty);
    expect(backend.scene!.commands.whereType<PdfBeginSoftMaskedCommand>(),
        isNotEmpty);
    expect(ratio, greaterThanOrEqualTo(desiredRatio),
        reason: '10000% must stay sharp on a DPR3 display');
    expect(backend.ratios, everyElement(ratio));
    expect(store.debugTileFractionsForPage(0).map((tile) => tile.rung),
        everyElement(rung));
    final originalFraction = _tileFraction(tester);
    final initialTiles = store.debugTilesScheduled;
    final initialRasters = backend.rasterizations;
    final initialPixels = backend.rasterPixels;
    expect(initialTiles, greaterThan(1));
    expect(initialRasters, greaterThan(0));
    expect(store.debugTilesLanded, initialTiles);
    expect(backend.largestRasterPixels, lessThan(2 << 20),
        reason: 'sharpness must come from viewport slabs, not a giant page');

    await tester.pumpWidget(build(-pan, 1));
    await _waitForTiles(tester, store);
    expect(_tileFraction(tester).left, greaterThan(originalFraction.left));
    final newEdgeTiles = store.debugTilesScheduled - initialTiles;
    expect(newEdgeTiles, greaterThan(0),
        reason: 'the pan must reveal genuinely uncached content');
    expect(newEdgeTiles, lessThan(initialTiles),
        reason: 'the overlapping viewport must reuse its existing tiles');
    expect(backend.rasterizations, greaterThan(initialRasters));
    expect(backend.rasterPixels - initialPixels, lessThan(initialPixels));

    final afterPanTiles = store.debugTilesScheduled;
    final afterPanRasters = backend.rasterizations;
    await tester.pumpWidget(build(0, 2));
    await _waitForTiles(tester, store);
    expect(_tileFraction(tester), originalFraction);
    expect(store.debugTilesScheduled, afterPanTiles,
        reason: 'returning to a cached viewport needs no new tiles');
    expect(backend.rasterizations, afterPanRasters,
        reason: 'returning to a cached viewport needs no Canvas replay');
    expect(store.debugTilesDiscarded, 0);
    expect(store.retainedBytes, lessThanOrEqualTo(store.maxBytes));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 300));
  });
}

ui.Rect _tileFraction(WidgetTester tester) => (tester
        .widget<CustomPaint>(find.byKey(const ValueKey('pdf-page-tile-layer')))
        .painter as dynamic)
    .visibleFraction as ui.Rect;

Future<void> _waitForTiles(WidgetTester tester, PdfTileStore store) async {
  for (var i = 0; i < 300; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    final exception = tester.takeException();
    if (exception != null) fail('high-zoom tile rendering failed: $exception');
    final found = find.byKey(const ValueKey('pdf-page-tile-layer'));
    if (found.evaluate().isNotEmpty) {
      final painter = tester.widget<CustomPaint>(found).painter as dynamic;
      final ui.Rect fraction = painter.visibleFraction;
      final ui.Size size = painter.pageSize;
      final view = store.viewFor(
        id: painter.identity,
        pageSize: size,
        desiredRatio: painter.desiredRatio,
        visiblePageRect: ui.Rect.fromLTRB(
          fraction.left * size.width,
          fraction.top * size.height,
          fraction.right * size.width,
          fraction.bottom * size.height,
        ),
        rasterize: painter.rasterize,
        scheduleMissing: false,
        allowCoarserFallback: false,
      );
      if (view.complete && !view.isEmpty && store.inFlightCount == 0) return;
    }
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
  }
  fail('grouped page did not present a complete high-zoom tile layer');
}

class _CountingCanvasBackend extends PdfCanvasTileRasterBackend {
  PdfRetainedScene? scene;
  final ratios = <double>[];
  int rasterizations = 0;
  int rasterPixels = 0;
  int largestRasterPixels = 0;

  @override
  PdfTileRasterSession createSession(PdfRetainedScene scene) {
    this.scene = scene;
    return _CountingCanvasSession(this, scene);
  }
}

class _CountingCanvasSession implements PdfTileRasterSession {
  _CountingCanvasSession(this.backend, this.scene);

  final _CountingCanvasBackend backend;
  @override
  final PdfRetainedScene scene;

  @override
  Future<ui.Image> rasterizeRegion(ui.Rect region,
      {required double pixelRatio, int? tracePage}) async {
    backend.rasterizations++;
    backend.ratios.add(pixelRatio);
    final image = await scene.rasterizeRegion(region,
        pixelRatio: pixelRatio, tracePage: tracePage);
    final pixels = image.width * image.height;
    backend.rasterPixels += pixels;
    if (pixels > backend.largestRasterPixels) {
      backend.largestRasterPixels = pixels;
    }
    return image;
  }

  @override
  void dispose() {}
}

Uint8List _groupedSheet() {
  final builder = CosDocumentBuilder();
  CosArray box() => CosArray([0, 0, 64, 64].map(CosInteger.new).toList());
  CosDictionary group() => CosDictionary({
        'S': const CosName('Transparency'),
        'I': const CosBoolean(true),
        'CS': const CosName('DeviceRGB'),
      });
  CosReference stream(String content, CosDictionary dictionary) =>
      builder.add(CosStream(dictionary, Uint8List.fromList(content.codeUnits)));
  final mask = stream(
      '0.8 g 0 0 64 64 re f',
      CosDictionary({
        'Type': const CosName('XObject'),
        'Subtype': const CosName('Form'),
        'BBox': box(),
        'Group': group(),
      }));
  final form = stream(
    'q /Masked gs 1 0 0 rg 29 29 6 6 re f Q '
    '0 0 0 RG 0.01 w 31.5 29 m 31.5 35 l S',
    CosDictionary({
      'Type': const CosName('XObject'),
      'Subtype': const CosName('Form'),
      'BBox': box(),
      'Group': group(),
      'Resources': CosDictionary({
        'ExtGState': CosDictionary({
          'Masked': CosDictionary({
            'SMask': CosDictionary({'S': const CosName('Alpha'), 'G': mask}),
          }),
        }),
      }),
    }),
  );
  final pages = CosDictionary({'Type': const CosName('Pages')});
  final pagesRef = builder.add(pages);
  final page = builder.add(CosDictionary({
    'Type': const CosName('Page'),
    'Parent': pagesRef,
    'MediaBox': box(),
    'Resources': CosDictionary({
      'XObject': CosDictionary({'Group': form}),
    }),
    'Contents':
        stream('0.7 0.8 1 rg 0 0 64 64 re f /Group Do', CosDictionary()),
  }));
  pages['Kids'] = CosArray([page]);
  pages['Count'] = const CosInteger(1);
  return builder.build(
      root: builder.add(CosDictionary(
          {'Type': const CosName('Catalog'), 'Pages': pagesRef})));
}
