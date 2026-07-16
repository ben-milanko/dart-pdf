// CI perf gate: a small, deterministic micro-corpus whose per-phase render
// timings must stay within budget. Unlike the nine `benchmark_*_test.dart`
// probes (all skip-unless-env, so nothing gates a PR), this runs by default in
// `flutter test` and is the single surface a regression trips.
//
// It measures the VM-observable, off-thread half of a page render through one
// call - `PdfRenderTrace.captureOffThread` - the interface this ticket adds so
// parse/interpret/serialize/deserialize/replay come back as one comparable
// record. Rasterization needs `dart:ui` and a real backend, so it stays out of
// this gate (the Flutter `benchmark_phases_test.dart` still covers paint/raster).
//
// The budgets are coarse tripwires, not micro-benchmarks: each has generous
// headroom over the observed best-of-N so ordinary CI noise never trips it, but
// an order-of-magnitude blow-up in any one phase does. Timings are taken
// best-of-N (the per-phase minimum) to defeat GC/scheduler jitter on a shared
// runner. If a legitimate change shifts the real cost, re-baseline the budgets
// here - deliberately, in one place - rather than muting the gate.
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

/// One micro-corpus entry: a programmatically-built document, the page to
/// measure, and the budget its render must stay within.
class _Case {
  _Case(this.name, this.bytes, this.budget, {this.page = 0});

  final String name;
  final Uint8List bytes;
  final int page;
  final PdfRenderPhaseBudget budget;
}

/// Best-of-[samples] trace for [pageIndex] of [document] (the per-phase minimum
/// across runs), after [warmups] discarded warm-up captures to pay the JIT and
/// lazy-loading costs once.
PdfRenderTrace _bestOf(
  PdfDocument document,
  int pageIndex, {
  int warmups = 3,
  int samples = 8,
}) {
  for (var i = 0; i < warmups; i++) {
    PdfRenderTrace.captureOffThread(document, pageIndex);
  }
  PdfRenderTrace? best;
  for (var i = 0; i < samples; i++) {
    final trace = PdfRenderTrace.captureOffThread(document, pageIndex);
    expect(trace, isNotNull,
        reason: 'captureOffThread must offload this page');
    best = best == null ? trace : best.min(trace!);
  }
  return best!;
}

void main() {
  // Generous, order-of-magnitude tripwires. These tiny fixtures render each
  // phase in well under a millisecond on a warm VM; the budgets sit ~50x above
  // that so only a genuine regression trips them.
  const light = PdfRenderPhaseBudget(
    parseUs: 20000,
    interpretUs: 40000,
    serializeUs: 40000,
    deserializeUs: 20000,
    replayUs: 20000,
    endToEndUs: 120000,
  );
  const fontHeavy = PdfRenderPhaseBudget(
    parseUs: 20000,
    interpretUs: 80000,
    serializeUs: 80000,
    deserializeUs: 40000,
    replayUs: 40000,
    endToEndUs: 200000,
  );

  final cases = <_Case>[
    _Case('classic-text', buildClassicPdf(), light),
    _Case('multipage', buildMultiPagePdf(4), light, page: 2),
    _Case('annotations', buildAppearanceAnnotationsPdf(), light),
    _Case('acroform', buildAcroFormPdf(), light),
    _Case('embedded-font', buildEmbeddedFontPdf(), fontHeavy),
  ];

  for (final testCase in cases) {
    test('render trace within budget: ${testCase.name}', () {
      final document = PdfDocument.open(testCase.bytes);
      final trace = _bestOf(document, testCase.page);

      // ignore: avoid_print
      print('[perf-gate] ${testCase.name}: ${trace.format()}');

      // The record is coherent. serialize always allocates a wire buffer and
      // endToEnd sums every phase, so both are reliably positive; the cheaper
      // phases (parse, replay) can legitimately measure 0us of Stopwatch
      // resolution on a tiny fixture, so only assert they are non-negative.
      expect(trace.serializeUs, greaterThan(0));
      expect(trace.endToEndUs, greaterThan(0));
      expect(trace.parseUs, greaterThanOrEqualTo(0));
      expect(trace.interpretUs, greaterThanOrEqualTo(0));
      expect(trace.deserializeUs, greaterThanOrEqualTo(0));
      expect(trace.replayUs, greaterThanOrEqualTo(0));

      final over = testCase.budget.exceedances(trace);
      expect(over, isEmpty,
          reason: 'phase budget exceeded for ${testCase.name}: '
              '${over.join('; ')}\nfull trace: ${trace.format()}');
    });
  }

  test('captureOffThread declines an out-of-range page', () {
    final document = PdfDocument.open(buildClassicPdf());
    expect(PdfRenderTrace.captureOffThread(document, 99), isNull);
    expect(PdfRenderTrace.captureOffThread(document, -1), isNull);
  });

  test('endToEnd sums the queue, worker, transfer and main phases', () {
    final trace = PdfRenderTrace(pageIndex: 0)
      ..queueUs = 1000
      ..workerUs = 5000
      ..transferUs = 2000
      ..deserializeUs = 300
      ..replayUs = 400
      ..rasterizeUs = 600;
    expect(trace.mainPhasesUs, 1300);
    expect(trace.endToEndUs, 1000 + 5000 + 2000 + 1300);
  });
}
