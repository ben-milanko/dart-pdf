// The hide-all-annotations display toggle: the renderer's annotations:
// flag, PdfViewer.showAnnotations (rendering AND link taps), and the
// persisted preference. Display-only - the document never changes.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  (int, int, int) pixelAt(ByteData pixels, int width, int x, int y) {
    final i = (y * width + x) * 4;
    return (
      pixels.getUint8(i),
      pixels.getUint8(i + 1),
      pixels.getUint8(i + 2),
    );
  }

  /// A one-page document with a solid green square annotation filling
  /// (100, 600)–(200, 700) - page space, so the raster pixel at
  /// (150, 792-650=142) sits in its middle.
  Uint8List annotated() {
    final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)));
    editor.addSquare(0, const PdfRect(100, 600, 200, 700),
        strokeColor: 0x00A000, fillColor: 0x00A000);
    return editor.save();
  }

  testWidgets('renderImage leaves annotations out when asked', (tester) async {
    await tester.runAsync(() async {
      final page = PdfDocument.open(annotated()).page(0);

      final shown = await PdfPageRenderer.renderImage(page);
      final shownPixels = (await shown.toByteData())!;
      expect(pixelAt(shownPixels, shown.width, 150, 142), (0x00, 0xA0, 0x00));
      shown.dispose();

      final hidden =
          await PdfPageRenderer.renderImage(page, annotations: false);
      final hiddenPixels = (await hidden.toByteData())!;
      expect(pixelAt(hiddenPixels, hidden.width, 150, 142), (0xFF, 0xFF, 0xFF));
      hidden.dispose();
    });
  });

  testWidgets('the eyedropper sampler matches the hidden display',
      (tester) async {
    await tester.runAsync(() async {
      final page = PdfDocument.open(annotated()).page(0);
      final shown = await PdfPageColorSampler.of(page);
      expect(shown.colorAt(const Offset(150, 142)), const Color(0xFF00A000));
      final hidden = await PdfPageColorSampler.of(page, annotations: false);
      expect(hidden.colorAt(const Offset(150, 142)), const Color(0xFFFFFFFF));
    });
  });

  testWidgets('PdfViewer.showAnnotations false renders clean pages',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          document: PdfDocument.open(annotated()),
          showAnnotations: false,
          initialFit: PdfViewerFit.width,
        ),
      ),
    ));
    await tester.pump();
    expect(
      tester
          .widget<PdfPageView>(find.byType(PdfPageView).first)
          .showAnnotations,
      isFalse,
    );
    for (var i = 0; i < 50 && find.byType(RawImage).evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    final raster = tester.widget<RawImage>(find.byType(RawImage).first).image!;
    final pixels = (await tester.runAsync(() => raster.toByteData()))!;
    // the annotation's center scaled to the raster's resolution
    final x = (150 / 612 * raster.width).round();
    final y = (142 / 792 * raster.height).round();
    expect(pixelAt(pixels, raster.width, x, y), (0xFF, 0xFF, 0xFF));
  });

  testWidgets(
      'hidden annotations take no taps - an invisible link must not '
      'navigate', (tester) async {
    // the GoTo link in buildAnnotatedPdf: rect (72, 600)-(200, 624) on a
    // 612x792 page, targeting page 3; fit-width in an 800px viewport
    // scales by 800/612
    const scale = 800 / 612;
    const target = Offset(136 * scale, (792 - 612) * scale);

    Future<PdfViewerController> pumpViewer(bool showAnnotations) async {
      final controller = PdfViewerController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(MaterialApp(
        key: ValueKey(showAnnotations),
        home: Scaffold(
          body: PdfViewer(
            document: PdfDocument.open(buildAnnotatedPdf()),
            controller: controller,
            showAnnotations: showAnnotations,
            initialFit: PdfViewerFit.width,
          ),
        ),
      ));
      await tester.pump();
      return controller;
    }

    Future<void> tapLink() async {
      await tester.tapAt(tester.getTopLeft(find.byType(PdfViewer)) + target);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
    }

    // control: the same tap follows the link while annotations show
    final shown = await pumpViewer(true);
    await tapLink();
    expect(shown.currentPage, 2, reason: 'the tap target is the GoTo link');

    final hidden = await pumpViewer(false);
    await tapLink();
    expect(hidden.currentPage, 0, reason: 'link is hidden, tap is inert');
  });

  testWidgets('thumbnails hide annotations too', (tester) async {
    final editing = PdfEditingController(annotated());
    final viewer = PdfViewerController();
    addTearDown(editing.dispose);
    addTearDown(viewer.dispose);
    final before = PdfThumbnailSidebar.debugRasterizations;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfThumbnailSidebar(
          controller: editing,
          viewerController: viewer,
          showAnnotations: false,
        ),
      ),
    ));
    for (var i = 0; i < 50; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      if (PdfThumbnailSidebar.debugRasterizations > before &&
          find
              .descendant(
                  of: find.byType(AspectRatio), matching: find.byType(RawImage))
              .evaluate()
              .isNotEmpty) {
        break;
      }
    }
    final raster = tester
        .widget<RawImage>(find
            .descendant(
                of: find.byType(AspectRatio), matching: find.byType(RawImage))
            .first)
        .image!;
    final pixels = (await tester.runAsync(() => raster.toByteData()))!;
    final x = (150 / 612 * raster.width).round();
    final y = (142 / 792 * raster.height).round();
    expect(pixelAt(pixels, raster.width, x, y), (0xFF, 0xFF, 0xFF));
  });

  test('the visibility persists as a preference', () async {
    final a = PdfEditingPreferences();
    await a.ready;
    expect(a.showAnnotations, isTrue);
    a.showAnnotations = false;
    await pumpEventQueue();

    final b = PdfEditingPreferences();
    await b.ready;
    expect(b.showAnnotations, isFalse);
  });
}
