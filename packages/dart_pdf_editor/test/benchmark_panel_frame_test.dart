// Reproducible build/resize benchmark for PdfSidebarPanelFrame.
//
//   cd packages/dart_pdf_editor
//   PDF_BENCHMARK_PANEL_FRAME=1 \
//     fvm flutter test test/benchmark_panel_frame_test.dart --reporter expanded
import 'dart:io';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('panel layout and resize control plane', (tester) async {
    if (Platform.environment['PDF_BENCHMARK_PANEL_FRAME'] != '1') {
      markTestSkipped('set PDF_BENCHMARK_PANEL_FRAME=1');
      return;
    }
    final controller = PdfViewerController();
    addTearDown(controller.dispose);

    Widget panel(int generation) => MaterialApp(
          home: SizedBox(
            width: 800,
            height: 600,
            child: Align(
              alignment: Alignment.topLeft,
              child: PdfSearchResultsPanel(
                controller: controller,
                side: generation.isEven
                    ? PdfSidebarSide.left
                    : PdfSidebarSide.right,
                bottomSheet: generation % 3 == 0,
              ),
            ),
          ),
        );

    await tester.pumpWidget(panel(0));
    for (var i = 1; i <= 30; i++) {
      await tester.pumpWidget(panel(i));
    }
    const trials = 9;
    const updates = 250;
    final buildSamples = <int>[];
    var generation = 31;
    for (var trial = 0; trial < trials; trial++) {
      final sw = Stopwatch()..start();
      for (var i = 0; i < updates; i++) {
        await tester.pumpWidget(panel(generation++));
      }
      buildSamples.add(sw.elapsedMicroseconds);
    }
    buildSamples.sort();

    final resizeSamples = <int>[];
    for (var trial = 0; trial < trials; trial++) {
      await tester.pumpWidget(panel(1));
      final grip = find.byKey(const ValueKey('pdf-search-resize-grip'));
      final gesture = await tester.startGesture(tester.getCenter(grip));
      final sw = Stopwatch()..start();
      for (var i = 0; i < 80; i++) {
        await gesture.moveBy(const Offset(-0.5, 0));
        await tester.pump();
      }
      resizeSamples.add(sw.elapsedMicroseconds);
      await gesture.up();
      await tester.pump();
    }
    resizeSamples.sort();

    final buildMedian = buildSamples[trials ~/ 2];
    final resizeMedian = resizeSamples[trials ~/ 2];
    // ignore: avoid_print
    print('PANEL_FRAME_BENCH build_median_us=$buildMedian '
        'build_us_per_update=${(buildMedian / updates).toStringAsFixed(2)} '
        'resize_median_us=$resizeMedian '
        'resize_us_per_frame=${(resizeMedian / 80).toStringAsFixed(2)}');
  });
}
