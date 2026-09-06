// PdfTileLayer: the presentation seam must drive the store from paint (schedule
// missing tiles), then repaint and composite them once they land.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/rendering.dart';
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

Future<Color> _pixel(ui.Image image, int x, int y) async {
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final offset = (y * image.width + x) * 4;
  return Color.fromARGB(
    bytes!.getUint8(offset + 3),
    bytes.getUint8(offset),
    bytes.getUint8(offset + 1),
    bytes.getUint8(offset + 2),
  );
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

  testWidgets('a coarse fallback cannot cover a sharper patch', (tester) async {
    await tester.runAsync(() async {
      final store = PdfTileStore(
        tilePixels: 32,
        prefetchRing: 0,
        registerForMemoryPressure: false,
      );
      final raster = _Rasterizer(tileSize: 32);
      const boundaryKey = ValueKey('tile-fallback-occlusion');

      Widget layer(double ratio, {Rect? occlusion}) => Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: RepaintBoundary(
                key: boundaryKey,
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: ColoredBox(
                    color: const Color(0xFFFF0000),
                    child: PdfTileLayer(
                      store: store,
                      identity: _id(0),
                      pageSize: const Size(64, 64),
                      desiredRatio: ratio,
                      visibleFraction: const Rect.fromLTRB(0, 0, 1, 1),
                      rasterize: raster.call,
                      fallbackOcclusionFraction: occlusion,
                    ),
                  ),
                ),
              ),
            ),
          );

      // Seed a complete blue 1x rung.
      await tester.pumpWidget(layer(1));
      await raster.flush();
      await tester.pump();

      // Ask for 2x but leave those exact tiles pending. The store now presents
      // the blue 1x rung as a fallback; the central refined fraction must show
      // the red backing through instead of being covered by stretched blue.
      await tester.pumpWidget(layer(
        2,
        occlusion: const Rect.fromLTRB(0.25, 0.25, 0.75, 0.75),
      ));
      await tester.pump();
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundaryKey),
      );
      final image = await boundary.toImage();
      expect(await _pixel(image, 4, 4), const Color(0xFF2277EE),
          reason: 'fallback remains useful outside the sharp patch');
      expect(await _pixel(image, 32, 32), const Color(0xFFFF0000),
          reason: 'fallback is clipped out of the sharp patch');
      image.dispose();
      store.dispose();
    });
  });
}
