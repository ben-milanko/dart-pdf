// CI perf gate for the document-lifecycle phases the PdfPerf facade times:
// open (xref parse), stream decode, incremental save. Mirrors
// dart_pdf_editor's render_trace_gate_test.dart: runs by default in
// `dart test`, budgets are coarse order-of-magnitude tripwires (generous
// headroom over observed best-of-N, so CI noise never trips them but a
// blow-up does), and best-of-N sampling defeats GC/scheduler jitter.
//
// The structural tripwires are the sharp edge here and cost nothing:
// a well-formed fixture must NEVER take the xref-recovery or
// scanned-header-rescue path. Either firing silently is a 10-100x open-time
// regression on real files, long before wall-clock budgets notice.
//
// If a legitimate change shifts real cost, re-baseline the budgets here -
// deliberately, in one place - rather than muting the gate.
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_cos/perf.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

/// Best-of-[samples] PdfPerf stats for [workload], after [warmups] discarded
/// runs to pay JIT costs once. "Best" is per-phase minimum via repeated
/// single-run snapshots.
PdfPerfStats _bestOf(void Function() workload,
    {int warmups = 3, int samples = 8}) {
  for (var i = 0; i < warmups; i++) {
    workload();
  }
  PdfPerfStats? best;
  for (var i = 0; i < samples; i++) {
    PdfPerf.reset();
    workload();
    final s = PdfPerf.snapshot();
    if (best == null) {
      best = s;
    } else {
      for (var p = 0; p < best.phaseUs.length; p++) {
        if (s.phaseUs[p] < best.phaseUs[p]) best.phaseUs[p] = s.phaseUs[p];
      }
    }
  }
  return best!;
}

void main() {
  setUpAll(() => PdfPerf.enabled = true);
  tearDownAll(() {
    PdfPerf.enabled = false;
    PdfPerf.reset();
  });
  setUp(PdfPerf.reset);

  // ~50x headroom over warm best-of-N on a 2020 laptop; micro-fixtures open
  // in well under a millisecond.
  const openBudget = PdfPerfBudget(
    maxPhaseUs: {
      PdfPerfPhase.docOpen: 50000,
      PdfPerfPhase.xrefParse: 25000,
    },
    maxCounts: {
      // Structural: a well-formed file must never fall back.
      PdfPerfCount.xrefRecovered: 0,
      PdfPerfCount.xrefOffsetRescue: 0,
    },
  );

  final wellFormed = {
    'classic-table': buildClassicPdf(),
    'xref-stream': buildXrefStreamPdf(),
    'multi-page-40': buildMultiPagePdf(40),
    'nested-page-tree': buildNestedPageTreePdf(),
    'annotated': buildAnnotatedPdf(),
  };

  for (final entry in wellFormed.entries) {
    test('open stays in budget and structurally clean: ${entry.key}', () {
      final stats = _bestOf(() => CosDocument.open(entry.value));
      expect(openBudget.exceedances(stats), isEmpty,
          reason: 'open-phase budget/structural tripwire fired; if the cost '
              'shift is intentional, re-baseline in perf_gate_test.dart');
    });
  }

  test('incremental save stays in budget', () {
    const saveBudget = PdfPerfBudget(
      maxPhaseUs: {PdfPerfPhase.saveIncremental: 50000},
    );
    final bytes = buildMultiPagePdf(40);
    final stats = _bestOf(() {
      final doc = CosDocument.open(bytes);
      final updater = CosIncrementalUpdater(doc)
        ..replaceObject(1, doc.catalog);
      updater.save();
    });
    expect(saveBudget.exceedances(stats), isEmpty);
  });

  test('object loading on the multi-page fixture is bounded', () {
    // A count tripwire: resolving every page of the 40-page fixture loads a
    // known-order-of-magnitude number of objects. A 10x jump means lazy
    // loading broke (e.g. something walks the whole xref per page).
    final doc = CosDocument.open(buildMultiPagePdf(40));
    PdfPerf.reset();
    for (final number in doc.objectNumbers.toList()) {
      doc.getObject(number, 0);
    }
    final loaded = PdfPerf.snapshot().count(PdfPerfCount.objectsLoaded);
    expect(loaded, greaterThan(0));
    expect(loaded, lessThan(1000),
        reason: '40-page fixture should stay in the low hundreds of objects');
  });
}
