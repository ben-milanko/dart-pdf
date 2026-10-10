// The support export's per-page render state (PdfPageViewDiagnostics): a field
// report of "this page never sharpened" must say which route the page is on,
// what its last detail pass decided, and which visible tiles are missing.
import 'dart:convert';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main() {
  testWidgets('a deep-zoom page reports its detail and tile state',
      (tester) async {
    tester.view.physicalSize = const Size(400, 300);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = PdfTileStore(
      tilePixels: 128,
      prefetchRing: 1,
      registerForMemoryPressure: false,
    );
    final oldTiles = PdfPageView.tileStoreDetail;
    PdfPageView.tileStoreDetail = true;
    PdfPageView.debugTileStoreOverride = store;
    addTearDown(() {
      PdfPageView.tileStoreDetail = oldTiles;
      PdfPageView.debugTileStoreOverride = null;
      store.dispose();
    });

    final doc = PdfDocument.open(buildClassicPdf());
    await tester.pumpWidget(
      Center(
        child: OverflowBox(
          maxWidth: double.infinity,
          maxHeight: double.infinity,
          child: SizedBox(
            width: 1024,
            child: PdfPageView(
              page: doc.page(0),
              baseRasterScale: 1,
              scale: 4,
            ),
          ),
        ),
      ),
    );

    Map<String, Object?> page() {
      final pages = PdfPageViewDiagnostics.instance.snapshot();
      expect(pages, hasLength(1));
      return pages.single;
    }

    Map<String, Object?>? liveCoverage() {
      final tiles = page()['tiles']! as Map<String, Object?>;
      final coverage = tiles['coverage'] as Map<String, Object?>?;
      return coverage?['liveViewport'] as Map<String, Object?>?;
    }

    for (var i = 0;
        i < 400 && (liveCoverage()?['missing'] ?? 1) != 0 ||
            store.inFlightCount > 0;
        i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }

    final snapshot = page();
    // Exported verbatim, so it must survive JSON encoding.
    expect(() => jsonEncode(snapshot), returnsNormally);
    expect(snapshot['pageIndex'], 0);
    final detail = snapshot['detail']! as Map<String, Object?>;
    expect(detail['awaitingExactPaint'], isFalse);
    expect(detail['lastOutcome'], isNotNull);
    expect(detail['outcomes'], greaterThan(0));
    final tiles = snapshot['tiles']! as Map<String, Object?>;
    expect(tiles['pathStatus'], 'active');
    expect(tiles['layerMounted'], isTrue);
    final live = liveCoverage()!;
    expect(live['visible'], greaterThan(0));
    expect(live['retained'], live['visible']);
    expect(live['missing'], 0);
    expect(live['missingVetoed'], 0);

    // Reading the snapshot is a pure peek: it must not schedule tile work.
    final scheduled = store.debugTilesScheduled;
    PdfPageViewDiagnostics.instance.snapshot();
    expect(store.debugTilesScheduled, scheduled);

    await tester.pumpWidget(const SizedBox());
    expect(PdfPageViewDiagnostics.instance.snapshot(), isEmpty,
        reason: 'a disposed page view must unregister');
  });
}
