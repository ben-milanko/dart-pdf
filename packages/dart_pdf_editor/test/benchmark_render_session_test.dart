// Reproducible control-plane benchmark for PdfPageRenderSession.
//
//   cd packages/dart_pdf_editor
//   PDF_BENCHMARK_SESSION=1 \
//     fvm flutter test test/benchmark_render_session_test.dart --reporter expanded
import 'dart:io';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main() {
  testWidgets('page render control-plane updates', (tester) async {
    if (Platform.environment['PDF_BENCHMARK_SESSION'] != '1') {
      markTestSkipped('set PDF_BENCHMARK_SESSION=1');
      return;
    }
    final page = PdfDocument.open(buildMultiPagePdf(1)).page(0);
    final hold = ValueNotifier<bool>(true);
    addTearDown(hold.dispose);

    Widget view(int generation) => MaterialApp(
          home: SizedBox(
            width: 612,
            child: PdfPageView(
              page: page,
              scale: generation.isEven ? 1.0 : 1.01,
              settleGeneration: generation,
              renderHold: hold,
            ),
          ),
        );

    await tester.pumpWidget(view(0));
    for (var i = 1; i <= 30; i++) {
      await tester.pumpWidget(view(i));
    }

    const trials = 9;
    const updates = 300;
    final samples = <int>[];
    var generation = 31;
    for (var trial = 0; trial < trials; trial++) {
      final sw = Stopwatch()..start();
      for (var i = 0; i < updates; i++) {
        await tester.pumpWidget(view(generation++));
      }
      samples.add(sw.elapsedMicroseconds);
    }
    samples.sort();
    final median = samples[samples.length ~/ 2];
    // ignore: avoid_print
    print('RENDER_SESSION_BENCH median_us=$median updates=$updates '
        'us_per_update=${(median / updates).toStringAsFixed(2)} '
        'samples=$samples');
  });
}
