// Covers the bounded-prefix early paint (#527 Option A): on a dense sheet the
// vector-first pass issues a `commandLimit`'d record *before* the full one, so
// real ink reaches the screen while the whole-page transcript is still being
// built. The gate matters as much as the win - an ordinary page must never be
// charged the extra worker job.
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/strips.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart' show PdfRenderCommand;
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

Future<void> _settle(WidgetTester tester, {int rounds = 120}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump();
    tester.takeException();
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
  }
}

void main() {
  late int prevLimit;
  late int prevMin;
  late bool prevOn;

  setUp(() {
    prevLimit = PdfPageView.earlyPrefixCommandLimit;
    prevMin = PdfPageView.earlyPrefixMinContentBytes;
    prevOn = PdfPageView.earlyPrefixPaint;
  });
  tearDown(() {
    PdfPageView.earlyPrefixCommandLimit = prevLimit;
    PdfPageView.earlyPrefixMinContentBytes = prevMin;
    PdfPageView.earlyPrefixPaint = prevOn;
  });

  testWidgets('a dense page records a bounded prefix before the full pass',
      (tester) async {
    PdfPageView.earlyPrefixPaint = true;
    PdfPageView.earlyPrefixCommandLimit = 64;
    PdfPageView.earlyPrefixMinContentBytes = 0; // every page counts as dense
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);

    final bytes = buildSyntheticCadStrip(ops: 2000, streams: 2);
    final page = PdfDocument.open(bytes).page(0);
    final worker = _RecordingWorker(PdfRenderWorker.startUncached(bytes));
    addTearDown(worker.dispose);

    await tester.pumpWidget(Center(
      child: SizedBox(
        width: 600,
        child: PdfPageView(page: page, scale: 1, renderWorker: worker),
      ),
    ));
    await _settle(tester);

    // The prefix must be requested, bounded, and must come first: its whole
    // purpose is to beat the full walk to the screen.
    final limits = worker.commandLimits;
    expect(limits, contains(64),
        reason: 'no bounded prefix record was issued: $limits');
    final firstPrefix = limits.indexOf(64);
    final firstFull = limits.indexOf(null);
    expect(firstPrefix, greaterThanOrEqualTo(0));
    if (firstFull >= 0) {
      expect(firstPrefix, lessThan(firstFull),
          reason: 'the prefix record must precede the full record: $limits');
    }
  });

  testWidgets('an ordinary page is not charged an extra record',
      (tester) async {
    PdfPageView.earlyPrefixPaint = true;
    PdfPageView.earlyPrefixCommandLimit = 64;
    // The real gate: a page whose raw content is below the threshold must skip
    // the prefix entirely, so light documents pay nothing for this feature.
    PdfPageView.earlyPrefixMinContentBytes = 1 << 30;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);

    final bytes = buildSyntheticCadStrip(ops: 2000, streams: 2);
    final page = PdfDocument.open(bytes).page(0);
    final worker = _RecordingWorker(PdfRenderWorker.startUncached(bytes));
    addTearDown(worker.dispose);

    await tester.pumpWidget(Center(
      child: SizedBox(
        width: 600,
        child: PdfPageView(page: page, scale: 1, renderWorker: worker),
      ),
    ));
    await _settle(tester);

    expect(worker.commandLimits.where((l) => l != null), isEmpty,
        reason: 'a below-threshold page must not issue a bounded record: '
            '${worker.commandLimits}');
  });
}

/// Delegates everything, recording the `commandLimit` of each record call in
/// order so the test can assert both that the prefix fires and where.
class _RecordingWorker extends PdfRenderWorker {
  _RecordingWorker(this._inner);

  final PdfRenderWorker _inner;
  final commandLimits = <int?>[];

  @override
  bool get isActive => _inner.isActive;

  @override
  Future<List<PdfRenderCommand>?> record(int pageIndex,
      {bool annotations = true,
      int priority = 0,
      double? imagePixelRatio,
      bool decodeImages = true,
      int? commandLimit,
      PdfRect? imageDecodeRegion}) {
    // Only the base record ladder is interesting; deep-zoom detail records
    // carry a region and would be noise.
    if (imageDecodeRegion == null) commandLimits.add(commandLimit);
    return _inner.record(pageIndex,
        annotations: annotations,
        priority: priority,
        imagePixelRatio: imagePixelRatio,
        decodeImages: decodeImages,
        commandLimit: commandLimit,
        imageDecodeRegion: imageDecodeRegion);
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
