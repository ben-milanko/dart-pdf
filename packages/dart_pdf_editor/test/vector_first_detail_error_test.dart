import 'dart:async';
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/strips.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart' show PdfRenderCommand;
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

Future<void> _waitUntil(
  WidgetTester tester,
  bool Function() predicate, {
  String label = 'condition',
}) async {
  for (var i = 0; i < 400; i++) {
    await tester.pump();
    final exception = tester.takeException();
    if (exception != null) fail('$label failed: $exception');
    if (predicate()) return;
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
  }
  fail('$label did not arrive');
}

/// A page whose single image covers the whole MediaBox, so every deep-zoom
/// detail region intersects an image draw. That forces the vector-first detail
/// patch through the worker (the local vector rasterize is skipped when an
/// image overlaps the region), which is exactly the path whose failure used to
/// strand the deferred full-image render.
Uint8List _fullPageImagePdf() {
  final font = buildTestTrueTypeFont();
  const content = 'q 612 0 0 792 0 0 cm '
      'BI /Width 1 /Height 1 /ColorSpace /DeviceRGB /BitsPerComponent 8 '
      '/Filter /ASCIIHexDecode ID E0E8FF> EI Q '
      'BT /F1 24 Tf 72 700 Td 0 0 0 rg (AB) Tj ET';
  final bodies = <Uint8List>[
    ascii('<< /Type /Catalog /Pages 2 0 R >>'),
    ascii('<< /Type /Pages /Kids [3 0 R] /Count 1 >>'),
    ascii('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>'),
    ascii('<< /Length ${content.length} >>\nstream\n$content\nendstream'),
    ascii('<< /Type /Font /Subtype /TrueType /BaseFont /TestFont '
        '/FirstChar 65 /LastChar 66 /Widths [600 1000] '
        '/Encoding /WinAnsiEncoding /FontDescriptor 7 0 R >>'),
    (BytesBuilder()
          ..add(ascii('<< /Length ${font.length} /Length1 ${font.length} >>'
              '\nstream\n'))
          ..add(font)
          ..add(ascii('\nendstream')))
        .takeBytes(),
    ascii('<< /Type /FontDescriptor /FontName /TestFont /Flags 32 '
        '/FontBBox [0 0 1000 1000] /ItalicAngle 0 /Ascent 800 '
        '/Descent -200 /CapHeight 800 /StemV 80 /FontFile2 6 0 R >>'),
  ];
  final out = BytesBuilder()..add(ascii('%PDF-1.4\n'));
  final offsets = <int>[];
  for (var i = 0; i < bodies.length; i++) {
    offsets.add(out.length);
    out.add(ascii('${i + 1} 0 obj\n'));
    out.add(bodies[i]);
    out.add(ascii('\nendobj\n'));
  }
  final xrefOffset = out.length;
  final buffer = StringBuffer()
    ..write('xref\n0 ${bodies.length + 1}\n')
    ..write('0000000000 65535 f \n');
  for (final offset in offsets) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer
    ..write('trailer\n<< /Size ${bodies.length + 1} /Root 1 0 R >>\n')
    ..write('startxref\n$xrefOffset\n%%EOF\n');
  out.add(ascii(buffer.toString()));
  return out.takeBytes();
}

void main() {
  testWidgets(
      'a failed deep-zoom detail render still lets the full image record land',
      (tester) async {
    // The single detail patch (not the tile pyramid) is the path a dense
    // deep-zoom page takes when the pyramid is off; pin it so the region
    // record whose failure we are exercising is actually requested.
    final wasTiles = PdfPageView.tileStoreDetail;
    final wasDefer = PdfPageView.deferFullRenderUntilDetailPaint;
    PdfPageView.tileStoreDetail = false;
    PdfPageView.deferFullRenderUntilDetailPaint = true;
    addTearDown(() {
      PdfPageView.tileStoreDetail = wasTiles;
      PdfPageView.deferFullRenderUntilDetailPaint = wasDefer;
    });
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);

    final bytes = _fullPageImagePdf();
    final page = PdfDocument.open(bytes).page(0);
    final worker = _FailingDetailWorker(PdfRenderWorker.startUncached(bytes));
    addTearDown(worker.dispose);

    await tester.pumpWidget(Center(
      child: SizedBox(
        width: 612,
        child: PdfPageView(
          page: page,
          scale: 8,
          renderWorker: worker,
        ),
      ),
    ));

    // The visible region record fails (the worker throws). Before the fix the
    // deferred full render awaited the detail paint forever, so this never ran
    // and the page stayed on its blurry base raster. It must now warm.
    await _waitUntil(tester, () => worker.fullRecordStarted.isCompleted,
        label: 'full image record after a failed detail render');
    expect(worker.detailRecordFailed, isTrue,
        reason: 'the regression requires the detail render to have failed');

    // The sharp full-page base raster lands - the page recovered without any
    // external relayout (opening devtools, resizing) to kick it.
    await _waitUntil(
      tester,
      () => find.byType(RawImage).evaluate().isNotEmpty,
      label: 'sharp base raster',
    );
  });
}

/// Delegates the cheap vector-first record but fails every image-decode-region
/// (deep-zoom detail) record, while signalling when the ordinary full-page
/// image record starts.
class _FailingDetailWorker extends PdfRenderWorker {
  _FailingDetailWorker(this._inner);

  final PdfRenderWorker _inner;
  final fullRecordStarted = Completer<void>();
  bool detailRecordFailed = false;

  @override
  bool get isActive => _inner.isActive;

  // The deep-zoom detail record that fires from the vector-first pass, before
  // the full-page image record: failing it is what used to strand the deferred
  // full render. A real failure is transient, so detail records that fire after
  // the full record has escaped the strand are allowed through (otherwise the
  // full pass's own detail refresh would throw uncaught here).
  bool get _detailShouldFail => !fullRecordStarted.isCompleted;

  @override
  Future<List<PdfRenderCommand>?> record(int pageIndex,
      {bool annotations = true,
      int priority = 0,
      double? imagePixelRatio,
      bool decodeImages = true,
      int? commandLimit,
      PdfRect? imageDecodeRegion}) {
    if (decodeImages && imageDecodeRegion != null && _detailShouldFail) {
      detailRecordFailed = true;
      return Future.error(StateError('detail record failed'));
    }
    if (decodeImages && imageDecodeRegion == null) {
      if (!fullRecordStarted.isCompleted) fullRecordStarted.complete();
    }
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
      int priority = 0}) {
    if (_detailShouldFail) {
      detailRecordFailed = true;
      return Future.error(StateError('strip detail record failed'));
    }
    return _inner.recordStripDetail(pageIndex,
        annotations: annotations,
        pageToDevice: pageToDevice,
        deviceWidth: deviceWidth,
        deviceHeight: deviceHeight,
        pixelRatio: pixelRatio,
        imageDecodeRegion: imageDecodeRegion,
        priority: priority);
  }

  @override
  void cancelBinStrips(int pageIndex, {int priority = 0}) =>
      _inner.cancelBinStrips(pageIndex, priority: priority);

  @override
  void dispose() => _inner.dispose();
}
