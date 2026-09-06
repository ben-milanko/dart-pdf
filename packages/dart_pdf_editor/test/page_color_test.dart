import 'dart:typed_data';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// An in-process [PdfRenderWorker] that records on the test isolate, so the
/// sampler's off-thread path runs deterministically under a test.
class _SyncWorker extends PdfRenderWorker {
  _SyncWorker(this._bytes);

  final Uint8List _bytes;
  late final PdfDocument _doc = PdfDocument.open(_bytes);
  bool _disposed = false;

  /// The page indices [record] was asked for - the sampler's own claim to
  /// have gone through the worker rather than quietly rendering locally.
  final List<int> recorded = [];

  @override
  bool get isActive => !_disposed;

  @override
  Future<List<PdfRenderCommand>?> record(int pageIndex,
      {bool annotations = true,
      int priority = 0,
      double? imagePixelRatio,
      bool decodeImages = true,
      int? commandLimit,
      PdfRect? imageDecodeRegion,
      PdfPartialRecordSink? onPartial}) async {
    if (_disposed || pageIndex < 0 || pageIndex >= _doc.pageCount) return null;
    recorded.add(pageIndex);
    final page = _doc.page(pageIndex);
    final ops = ContentStreamParser.parse(page.contentBytes());
    final recorder = RecordingPdfDevice();
    PdfInterpreter(cos: _doc.cos, device: recorder)
        .drawPageOperations(page, ops);
    final bytes = serializeCommands(recorder.commands,
        cos: _doc.cos,
        maxImagePixelRatio: imagePixelRatio,
        compactStateScopes: true);
    return bytes == null ? null : deserializeCommands(bytes);
  }

  @override
  void cancel(int pageIndex, {int priority = 0}) {}

  @override
  void dispose() => _disposed = true;
}

/// A worker that declines every page, as the real one does for an inline
/// image or on a platform with no worker at all.
class _DecliningWorker extends _SyncWorker {
  _DecliningWorker(super.bytes);

  @override
  Future<List<PdfRenderCommand>?> record(int pageIndex,
      {bool annotations = true,
      int priority = 0,
      double? imagePixelRatio,
      bool decodeImages = true,
      int? commandLimit,
      PdfRect? imageDecodeRegion,
      PdfPartialRecordSink? onPartial}) async {
    recorded.add(pageIndex);
    return null;
  }
}

void main() {
  (int, int, int) pixelAt(ByteData pixels, int width, int x, int y) {
    final i = (y * width + x) * 4;
    return (
      pixels.getUint8(i),
      pixels.getUint8(i + 1),
      pixels.getUint8(i + 2),
    );
  }

  testWidgets('the page renders on the given paper color', (tester) async {
    await tester.runAsync(() async {
      final document = PdfDocument.open(buildMultiPagePdf(1));
      final page = document.page(0);
      final picture = await PdfPageRenderer.renderPicture(page,
          pageColor: const Color(0xFF2244AA));
      final image = await PdfPageRenderer.rasterize(
          picture, PdfPageRenderer.pageSize(page), 1);
      picture.dispose();
      final pixels = (await image.toByteData())!;
      // the top-left margin is bare paper
      expect(pixelAt(pixels, image.width, 2, 2), (0x22, 0x44, 0xAA));
      image.dispose();
    });
  });

  testWidgets('a translucent paper color washes over white', (tester) async {
    await tester.runAsync(() async {
      final document = PdfDocument.open(buildMultiPagePdf(1));
      final page = document.page(0);
      // 50% red over white paper → pink, not pure red. Without the white
      // backing the raster would read straight (255, 0, 0).
      final picture = await PdfPageRenderer.renderPicture(page,
          pageColor: const Color(0x80FF0000));
      final image = await PdfPageRenderer.rasterize(
          picture, PdfPageRenderer.pageSize(page), 1);
      picture.dispose();
      final pixels = (await image.toByteData())!;
      final (r, g, b) = pixelAt(pixels, image.width, 2, 2);
      expect(r, 255); // red stays saturated over white
      expect(g, greaterThan(110)); // green/blue lifted by the white backing
      expect(g, lessThan(140));
      expect(b, equals(g)); // symmetric: a true pink wash
      image.dispose();
    });
  });

  testWidgets('the eyedropper sampler sees the displayed paper color',
      (tester) async {
    await tester.runAsync(() async {
      final document = PdfDocument.open(buildMultiPagePdf(1));
      final sampler = await PdfPageColorSampler.of(document.page(0),
          pageColor: const Color(0xFF1B5E20));
      expect(sampler.colorAt(const Offset(5, 5)), const Color(0xFF1B5E20));
    });
  });

  testWidgets('the sampler narrows its patch as the page is magnified',
      (tester) async {
    await tester.runAsync(() async {
      final document = PdfDocument.open(buildMultiPagePdf(1));
      final sampler = await PdfPageColorSampler.of(document.page(0));
      // 3x3 at 1:1, and no wider than the pointer covers once zoomed in -
      // 3 points of a magnified page is most of a glyph stem
      expect(sampler.patchRadiusForZoom(1), 1);
      expect(sampler.patchRadiusForZoom(2), 0);
      expect(sampler.patchRadiusForZoom(8), 0);
      expect(sampler.patchRadiusForZoom(0.5), 2);
      // a nonsense zoom falls back to the unzoomed reading
      expect(sampler.patchRadiusForZoom(0), 1);
      expect(sampler.patchRadiusForZoom(double.nan), 1);
    });
  });

  testWidgets('an oversized page samples through a scaled-down raster',
      (tester) async {
    await tester.runAsync(() async {
      // 4000x4000 pt is 16 MP at 1 px per point - 64 MB of RGBA for a
      // handful of reads. The raster scales down; sampling still speaks
      // page points.
      final document =
          PdfDocument.open(buildMultiPagePdf(1, width: 4000, height: 4000));
      final sampler = await PdfPageColorSampler.of(document.page(0),
          pageColor: const Color(0xFF1B5E20));
      expect(
          sampler.colorAt(const Offset(2000, 2000)), const Color(0xFF1B5E20));
      expect(sampler.colorAt(const Offset(4200, 2000)), isNull,
          reason: 'off the page is still off the page');
    });
  });

  testWidgets('the sampler reads the same page through a worker as locally',
      (tester) async {
    await tester.runAsync(() async {
      final bytes = buildMultiPagePdf(2);
      // Every sample the eyedropper can take must agree whether the walk ran
      // on the worker or here - the worker path is the whole point of the
      // freeze fix, and a wrong replay would show up as a wrong colour.
      final local =
          await PdfPageColorSampler.of(PdfDocument.open(bytes).page(0));
      final worker = _SyncWorker(bytes);
      addTearDown(worker.dispose);
      final offloaded = await PdfPageColorSampler.of(
          PdfDocument.open(bytes).page(0),
          worker: worker,
          pageIndex: 0);
      expect(worker.recorded, [0], reason: 'the walk went to the worker');

      var ink = 0;
      for (var y = 40.0; y < 100; y += 4) {
        for (var x = 60.0; x < 200; x += 4) {
          final point = Offset(x, y);
          final here = local.colorAt(point);
          expect(offloaded.colorAt(point), here, reason: 'differs at $point');
          if (here != const Color(0xFFFFFFFF)) ink++;
        }
      }
      // the sweep crosses the page's "Page 1" text, so the agreement above is
      // about drawn content and not just blank paper
      expect(ink, greaterThan(0));
    });
  });

  testWidgets('a worker that declines falls back to the local render',
      (tester) async {
    await tester.runAsync(() async {
      final bytes = buildMultiPagePdf(1);
      final worker = _DecliningWorker(bytes);
      addTearDown(worker.dispose);
      final sampler = await PdfPageColorSampler.of(
          PdfDocument.open(bytes).page(0),
          pageColor: const Color(0xFF1B5E20),
          worker: worker,
          pageIndex: 0);
      expect(worker.recorded, [0]);
      expect(sampler.colorAt(const Offset(5, 5)), const Color(0xFF1B5E20));
    });
  });

  testWidgets('PdfViewer pages display on the given paper', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          document: PdfDocument.open(buildMultiPagePdf(1)),
          pageColor: const Color(0xFFE8F5E9),
        ),
      ),
    ));
    await tester.pump();
    expect(
      tester.widget<PdfPageView>(find.byType(PdfPageView).first).pageColor,
      const Color(0xFFE8F5E9),
    );
    // the rasterized page itself carries the paper color
    for (var i = 0; i < 50 && find.byType(RawImage).evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    final raster = tester.widget<RawImage>(find.byType(RawImage).first).image!;
    final pixels = (await tester.runAsync(() => raster.toByteData()))!;
    expect(pixelAt(pixels, raster.width, 2, 2), (0xE8, 0xF5, 0xE9));
  });

  testWidgets('thumbnails take the same paper color', (tester) async {
    final editing = PdfEditingController(buildMultiPagePdf(2));
    final viewer = PdfViewerController();
    addTearDown(editing.dispose);
    addTearDown(viewer.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfThumbnailSidebar(
          controller: editing,
          viewerController: viewer,
          pageColor: Color(0xFFFFF8E1),
        ),
      ),
    ));
    // let the rasterized thumbnails land, then capture a tile's pixels
    for (var i = 0; i < 50; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      if (find
          .descendant(
              of: find.byType(AspectRatio), matching: find.byType(RawImage))
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }
    final boundary = tester.renderObject<RenderRepaintBoundary>(find
        .ancestor(
            of: find.byType(AspectRatio).first,
            matching: find.byType(RepaintBoundary))
        .first);
    final image = (await tester.runAsync(() => boundary.toImage()))!;
    final pixels = (await tester.runAsync(() => image.toByteData()))!;
    expect(pixelAt(pixels, image.width, 3, 3), (0xFF, 0xF8, 0xE1));
    image.dispose();
  });

  test('the page color persists as a preference', () async {
    SharedPreferences.setMockInitialValues({});
    final a = PdfEditingPreferences();
    await a.ready;
    expect(a.pageColor, const Color(0xFFFFFFFF));
    a.pageColor = const Color(0xFF80CBC4);
    await pumpEventQueue();

    final b = PdfEditingPreferences();
    await b.ready;
    expect(b.pageColor, const Color(0xFF80CBC4));
  });
}
