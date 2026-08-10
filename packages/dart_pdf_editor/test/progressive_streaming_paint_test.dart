// PR4 of #564: the host progressive reveal. On a dense page, the vector-first
// record now streams the growing linework prefix the worker records, and
// PdfPageView paints each prefix into the preview slot BEFORE the vector-first
// full raster lands - a top-down reveal instead of blank paper then a snapshot.
// It supersedes the single bounded early prefix (#527) on a dense page.
//
// Tested separately:
//  - GATE/WIRING: only a dense page, only with the flag on, gives the
//    vector-first record a non-null onPartial (deterministic);
//  - PAINT: a streamed partial reaches the screen (a 'progressive-partial' perf
//    line is logged after setState). The record's FINAL is held behind a gate so
//    the partials paint while _image is still null instead of racing the raster.
import 'dart:async';
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/strips.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart' show PdfRenderCommand;
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

/// A dense linework CAD sheet: ~12k ops span several worker chunks, so the
/// vector-first record emits partials. No images needed - the vector-first
/// record streams regardless of image content.
Uint8List _densePdf() => buildSyntheticCadStrip(ops: 12000, streams: 2);

Future<void> _settle(WidgetTester tester, {int rounds = 120}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump();
    tester.takeException();
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
  }
}

void main() {
  late bool prevProgressive;
  late Duration? prevProgressiveBudget;
  late bool prevEarly;
  late int prevMin;

  setUp(() {
    prevProgressive = PdfPageView.progressiveStreamingPaint;
    prevProgressiveBudget = PdfPageView.progressivePartialUiBudget;
    prevEarly = PdfPageView.earlyPrefixPaint;
    prevMin = PdfPageView.earlyPrefixMinContentBytes;
  });
  tearDown(() {
    PdfPageView.progressiveStreamingPaint = prevProgressive;
    PdfPageView.progressivePartialUiBudget = prevProgressiveBudget;
    PdfPageView.earlyPrefixPaint = prevEarly;
    PdfPageView.earlyPrefixMinContentBytes = prevMin;
    PdfPerfLog.enabled = false;
    PdfPerfLog.sink = null;
  });

  testWidgets('a dense page streams the vector-first record', (tester) async {
    PdfPageView.progressiveStreamingPaint = true;
    PdfPageView.earlyPrefixMinContentBytes = 0; // every page counts as dense
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);

    final bytes = _densePdf();
    final page = PdfDocument.open(bytes).page(0);
    final worker = _StreamProbeWorker(PdfRenderWorker.startUncached(bytes));
    addTearDown(worker.dispose);

    await tester.pumpWidget(Center(
      child: SizedBox(
        width: 600,
        child: PdfPageView(page: page, scale: 1, renderWorker: worker),
      ),
    ));
    await _settle(tester);

    expect(worker.baseRecordHadPartial, contains(true),
        reason: 'the vector-first record must get an onPartial sink when the '
            'flag is on and the page is dense: ${worker.baseRecordHadPartial}');
  });

  testWidgets('opting the flag back off streams nothing', (tester) async {
    PdfPageView.progressiveStreamingPaint = false; // the documented opt-out
    PdfPageView.earlyPrefixMinContentBytes = 0;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);

    final bytes = _densePdf();
    final page = PdfDocument.open(bytes).page(0);
    final worker = _StreamProbeWorker(PdfRenderWorker.startUncached(bytes));
    addTearDown(worker.dispose);

    await tester.pumpWidget(Center(
      child: SizedBox(
        width: 600,
        child: PdfPageView(page: page, scale: 1, renderWorker: worker),
      ),
    ));
    await _settle(tester);

    expect(worker.baseRecordHadPartial.every((had) => !had), isTrue,
        reason: 'no record may carry a sink with the flag off: '
            '${worker.baseRecordHadPartial}');
  });

  testWidgets('an ordinary page never streams even with the flag on',
      (tester) async {
    PdfPageView.progressiveStreamingPaint = true;
    PdfPageView.earlyPrefixMinContentBytes = 1 << 30; // nothing counts as dense
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);

    final bytes = _densePdf();
    final page = PdfDocument.open(bytes).page(0);
    final worker = _StreamProbeWorker(PdfRenderWorker.startUncached(bytes));
    addTearDown(worker.dispose);

    await tester.pumpWidget(Center(
      child: SizedBox(
        width: 600,
        child: PdfPageView(page: page, scale: 1, renderWorker: worker),
      ),
    ));
    await _settle(tester);

    expect(worker.baseRecordHadPartial.every((had) => !had), isTrue,
        reason: 'a below-threshold page must not stream: '
            '${worker.baseRecordHadPartial}');
  });

  testWidgets('a streamed partial paints before the full raster lands',
      (tester) async {
    PdfPageView.progressiveStreamingPaint = true;
    // One prefix is enough to prove the reveal. A zero budget deterministically
    // exercises the adaptive stop: the latest-only mailbox must not replay the
    // three larger cumulative snapshots queued behind it.
    PdfPageView.progressivePartialUiBudget = Duration.zero;
    PdfPageView.earlyPrefixMinContentBytes = 0;
    final logs = <String>[];
    PdfPerfLog.enabled = true;
    PdfPerfLog.sink = logs.add;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);

    final bytes = _densePdf();
    final page = PdfDocument.open(bytes).page(0);
    // Hold the vector-first record's FINAL behind a gate so the partials (which
    // stream live during the inner record) paint while _image is still null,
    // rather than being overtaken by the vector-first raster.
    final gate = Completer<void>();
    final worker = _StreamProbeWorker(PdfRenderWorker.startUncached(bytes),
        finalGate: gate);
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
      worker.dispose();
    });

    await tester.pumpWidget(Center(
      child: SizedBox(
        width: 600,
        child: PdfPageView(page: page, scale: 1, renderWorker: worker),
      ),
    ));
    await _settle(tester, rounds: 60);

    final partialLogs =
        logs.where((l) => l.contains('progressive-partial')).toList();
    expect(partialLogs, hasLength(1),
        reason: 'a streamed partial should have painted into the preview while '
            'the vector-first final was held, without replaying cumulative '
            'snapshots after the UI budget was spent: ${logs.length} logs');
    expect(partialLogs.single, contains('budgetStop=true'));

    gate.complete();
    await _settle(tester, rounds: 60);
  });
}

/// Wraps a real worker: records whether each base (non-region) record was given
/// an `onPartial` sink, forwards partials live, and optionally holds the final
/// of the streaming record behind [finalGate] so a test can observe the reveal
/// before the full raster overtakes it.
class _StreamProbeWorker extends PdfRenderWorker {
  _StreamProbeWorker(this._inner, {this.finalGate});

  final PdfRenderWorker _inner;
  final Completer<void>? finalGate;
  final baseRecordHadPartial = <bool>[];

  @override
  bool get isActive => _inner.isActive;

  @override
  Future<List<PdfRenderCommand>?> record(int pageIndex,
      {bool annotations = true,
      int priority = 0,
      double? imagePixelRatio,
      bool decodeImages = true,
      int? commandLimit,
      PdfRect? imageDecodeRegion,
      PdfPartialRecordSink? onPartial}) async {
    if (imageDecodeRegion == null) baseRecordHadPartial.add(onPartial != null);
    final result = await _inner.record(pageIndex,
        annotations: annotations,
        priority: priority,
        imagePixelRatio: imagePixelRatio,
        decodeImages: decodeImages,
        commandLimit: commandLimit,
        imageDecodeRegion: imageDecodeRegion,
        onPartial: onPartial);
    if (imageDecodeRegion == null && onPartial != null && finalGate != null) {
      await finalGate!.future;
    }
    return result;
  }

  @override
  void cancel(int pageIndex, {int priority = 0}) =>
      _inner.cancel(pageIndex, priority: priority);

  @override
  Future<StripPlan?> binStrips(int pageIndex,
          {required bool annotations,
          required List<double> pageToDevice,
          required int deviceWidth,
          required int deviceHeight,
          required double pixelRatio,
          bool slugGlyphs = false,
          int priority = 0}) =>
      _inner.binStrips(pageIndex,
          annotations: annotations,
          pageToDevice: pageToDevice,
          deviceWidth: deviceWidth,
          deviceHeight: deviceHeight,
          pixelRatio: pixelRatio,
          slugGlyphs: slugGlyphs,
          priority: priority);

  @override
  Future<PdfStripDetail?> recordStripDetail(int pageIndex,
          {required bool annotations,
          required List<double> pageToDevice,
          required int deviceWidth,
          required int deviceHeight,
          required double pixelRatio,
          required PdfRect imageDecodeRegion,
          int priority = 0}) =>
      _inner.recordStripDetail(pageIndex,
          annotations: annotations,
          pageToDevice: pageToDevice,
          deviceWidth: deviceWidth,
          deviceHeight: deviceHeight,
          pixelRatio: pixelRatio,
          imageDecodeRegion: imageDecodeRegion,
          priority: priority);

  @override
  void cancelBinStrips(int pageIndex, {int priority = 0}) =>
      _inner.cancelBinStrips(pageIndex, priority: priority);

  @override
  void dispose() => _inner.dispose();
}
