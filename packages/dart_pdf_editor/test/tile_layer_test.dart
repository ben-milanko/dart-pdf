// PdfTileLayer: the presentation seam must drive the store from paint (schedule
// missing tiles), then repaint and composite them once they land.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ui.Image> _solidImage(int w, int h) {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..color = const Color(0xFF2277EE));
  final picture = recorder.endRecording();
  final image = picture.toImage(w, h);
  picture.dispose();
  return image;
}

class _Rasterizer {
  _Rasterizer({this.tileSize = 32});
  final int tileSize;
  var calls = 0;
  final _pending = <Completer<ui.Image>>[];

  Future<ui.Image> call(Rect region, double ratio) {
    calls++;
    final completer = Completer<ui.Image>();
    _pending.add(completer);
    return completer.future;
  }

  Future<void> flush() async {
    final pending = _pending.where((c) => !c.isCompleted).toList();
    final images = <ui.Image>[
      for (var i = 0; i < pending.length; i++)
        await _solidImage(tileSize, tileSize),
    ];
    for (var i = 0; i < pending.length; i++) {
      pending[i].complete(images[i]);
    }
    await pumpEventQueue();
  }
}

PdfTilePageIdentity _id(int page) => PdfTilePageIdentity(
      pageIndex: page,
      pageEpoch: 0,
      contentStamp: 0,
      destructiveStamp: 0,
      plan: const PdfPageRenderPlan(),
    );

void main() {
  testWidgets('schedules on first paint, then composites tiles as they land',
      (tester) async {
    await tester.runAsync(() async {
      final store = PdfTileStore(
        tilePixels: 32,
        prefetchRing: 0,
        registerForMemoryPressure: false,
      );
      final raster = _Rasterizer(tileSize: 32);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 128,
              height: 128,
              child: PdfTileLayer(
                store: store,
                identity: _id(0),
                pageSize: const Size(128, 128),
                desiredRatio: 2.0,
                visibleFraction: const Rect.fromLTRB(0, 0, 1, 1),
                rasterize: raster.call,
              ),
            ),
          ),
        ),
      );

      // The first paint asked the store for a view, which scheduled the
      // missing tiles.
      expect(raster.calls, greaterThan(0));
      expect(store.inFlightCount, greaterThan(0));
      final ticksBefore = store.debugTicks;

      await raster.flush();
      await tester.pump(); // the store's tick repaints the layer

      expect(store.tileCount, greaterThan(0));
      expect(store.debugTilesLanded, greaterThan(0));
      expect(store.debugTicks, greaterThan(ticksBefore));

      store.dispose();
    });
  });

  testWidgets('an empty store paints nothing and does not throw',
      (tester) async {
    await tester.runAsync(() async {
      final store = PdfTileStore(registerForMemoryPressure: false);
      // A rasterizer that never completes: the view stays empty (base-only).
      Future<ui.Image> never(Rect region, double ratio) =>
          Completer<ui.Image>().future;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 64,
            height: 64,
            child: PdfTileLayer(
              store: store,
              identity: _id(0),
              pageSize: const Size(64, 64),
              desiredRatio: 1.0,
              visibleFraction: const Rect.fromLTRB(0, 0, 1, 1),
              rasterize: never,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      store.dispose();
    });
  });
}
