// Reproducible page-reconciliation control-plane benchmark.
//
//   cd packages/dart_pdf_editor
//   PDF_BENCHMARK_RECONCILIATION=1 \
//   PDF_BENCHMARK_RECONCILIATION_PAGES=10000 \
//     fvm flutter test test/benchmark_reconciliation_test.dart \
//       --reporter expanded
//
// Measures only PdfViewer's synchronous reconciliation transaction, as
// reported by PdfPageReconciliationDiagnostics. Document editing/saving and
// the next frame's rendering are intentionally outside the samples.
import 'dart:io';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('dirty, geometry, and keyed-structure reconciliation',
      (tester) async {
    if (Platform.environment['PDF_BENCHMARK_RECONCILIATION'] != '1') {
      markTestSkipped('set PDF_BENCHMARK_RECONCILIATION=1');
      return;
    }
    final pageCount = int.tryParse(
            Platform.environment['PDF_BENCHMARK_RECONCILIATION_PAGES'] ?? '') ??
        1000;
    SharedPreferences.setMockInitialValues({});
    final editing = PdfEditingController(buildMultiPagePdf(pageCount));
    addTearDown(editing.dispose);
    final controller = PdfViewerController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      home: PdfViewer(
        editing: editing,
        controller: controller,
        pagePreviews: false,
        autoRenderWorker: false,
      ),
    ));
    await tester.pump();

    int sample(PdfPageReconciliationMode expected) {
      final diagnostics = controller.debugPageReconciliationDiagnostics!;
      expect(diagnostics.mode, expected);
      return diagnostics.elapsed.inMicroseconds;
    }

    final dirty = <int>[];
    for (var i = 0; i < 9; i++) {
      final page = (i * 997) % pageCount;
      editing.addRectangle(page, const PdfRect(20, 20, 80, 80));
      dirty.add(sample(PdfPageReconciliationMode.incremental));
      await tester.pump();
    }

    final geometry = <int>[];
    for (var i = 0; i < 8; i++) {
      final page = (i * 991) % pageCount;
      editing.rotatePages([page], 90);
      geometry.add(sample(PdfPageReconciliationMode.incremental));
      await tester.pump();
    }

    final reorder = <int>[];
    for (var i = 0; i < 5; i++) {
      editing.movePage(0, pageCount - 1);
      reorder.add(sample(PdfPageReconciliationMode.keyedStructure));
      await tester.pump();
    }

    ({int median, int p95, int max}) summary(List<int> values) {
      final sorted = List<int>.of(values)..sort();
      return (
        median: sorted[sorted.length ~/ 2],
        p95: sorted[((sorted.length - 1) * 0.95).round()],
        max: sorted.last,
      );
    }

    String report(String name, List<int> values) {
      final result = summary(values);
      return '$name-median-us=${result.median} '
          '$name-p95-us=${result.p95} $name-max-us=${result.max}';
    }

    // ignore: avoid_print
    print('RECONCILIATION_BENCH pages=$pageCount '
        '${report('dirty', dirty)} ${report('geometry', geometry)} '
        '${report('reorder', reorder)}');
  });
}
