import 'dart:typed_data';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
