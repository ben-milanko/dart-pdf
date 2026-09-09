import 'dart:math' as math;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/high_zoom_pdf.dart';

void main() {
  testWidgets('default zoom reaches 10000% with desktop side panels',
      (tester) async {
    final document = PdfDocument.open(buildHighZoomPagePdf());
    final controller = PdfViewerController();
    addTearDown(controller.dispose);

    Widget build(double panelWidth) => MaterialApp(
          home: Scaffold(
            body: Row(children: [
              SizedBox(width: panelWidth),
              Expanded(
                child: PdfViewer(
                  key: const ValueKey('viewer'),
                  document: document,
                  controller: controller,
                  pagePreviews: false,
                ),
              ),
            ]),
          ),
        );

    for (final panelWidth in [0.0, 400.0]) {
      await tester.pumpWidget(build(panelWidth));
      await tester.pump();
      controller.setZoom(100);
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expect(controller.zoom, closeTo(100, 0.01));

      // These viewports used to cap below 10000%. Larger requests still
      // clamp instead of growing a page or its tile demand without bound.
      controller.setZoom(1000);
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expect(controller.zoom, closeTo(100, 0.01));
    }
  });

  for (final width in [360.0, 800.0]) {
    for (final maxZoom in [6.0, 24.0]) {
      testWidgets('explicit maxZoom $maxZoom keeps its limit at width $width',
          (tester) async {
        tester.view.physicalSize = Size(width, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final controller = PdfViewerController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: PdfViewer(
              document: PdfDocument.open(buildHighZoomPagePdf()),
              controller: controller,
              maxZoom: maxZoom,
              pagePreviews: false,
            ),
          ),
        ));
        await tester.pump();

        final fitWidth = width / 612;
        final expected = maxZoom == 24
            ? math.max(24.0, maxZoom * fitWidth)
            : maxZoom * fitWidth;
        controller.setZoom(100);
        await tester.pumpAndSettle(const Duration(milliseconds: 300));
        expect(controller.zoom, closeTo(expected, 0.01));
      });
    }
  }
}
