// The motion-safe render lane: with a render worker attached, an ordinary
// page's interpret walk does not run on the UI thread, so holding it back for
// the whole of a scroll is latency and nothing else. These tests pin which
// pages render *through* a hold and which keep the classic behaviour - held
// until the scroll settles - which is the guarantee the dense sheets rely on.
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

/// An in-process [PdfRenderWorker] that records on the test isolate, so the
/// worker render path runs deterministically under pump().
class _SyncWorker extends PdfRenderWorker {
  _SyncWorker(this._bytes);

  final Uint8List _bytes;
  late final PdfDocument _doc = PdfDocument.open(_bytes);
  bool _disposed = false;

  @override
  bool get isActive => !_disposed;

  @override
  Future<List<PdfRenderCommand>?> record(int pageIndex,
      {bool annotations = true,
      int priority = 0,
      double? imagePixelRatio,
      bool decodeImages = true,
      int? commandLimit,
      PdfRect? imageDecodeRegion,
      PdfPartialRecordSink? onPartial}) async {
    if (_disposed || pageIndex < 0 || pageIndex >= _doc.pageCount) return null;
    final page = _doc.page(pageIndex);
    final ops = ContentStreamParser.parse(page.contentBytes(),
        operationLimit: decodeImages ? null : commandLimit);
    final recorder = RecordingPdfDevice();
    PdfInterpreter(cos: _doc.cos, device: recorder)
        .drawPageOperations(page, ops);
    final bytes = serializeCommands(recorder.commands,
        cos: _doc.cos,
        decodeImages: decodeImages,
        maxImagePixelRatio: imagePixelRatio,
        imageDecodeRegion: imageDecodeRegion,
        imagePlaceholders: !decodeImages,
        commandLimit: commandLimit,
        compactStateScopes: true);
    return bytes == null ? null : deserializeCommands(bytes);
  }

  @override
  void cancel(int pageIndex, {int priority = 0}) {}

  @override
  void dispose() => _disposed = true;
}

void main() {
  /// Lets the real async render make progress, then pumps a frame.
  Future<void> settle(WidgetTester tester) async {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }

  /// Whether the page has painted real content rather than the paper
  /// placeholder: a full-resolution raster, or - on the direct
  /// picture-presentation path - the retained display list itself.
  bool painted(WidgetTester tester) =>
      tester.widgetList<RawImage>(find.byType(RawImage)).any((w) =>
          w.image != null && (w.image!.width > 200 || w.image!.height > 200)) ||
      tester.widgetList<CustomPaint>(find.byType(CustomPaint)).any((w) =>
          w.painter.runtimeType.toString() == '_RetainedPagePicturePainter');

  Future<PdfPageRenderScheduler> pumpPage(
    WidgetTester tester,
    Uint8List bytes, {
    required bool holding,
  }) async {
    final document = PdfDocument.open(bytes);
    final worker = _SyncWorker(bytes);
    addTearDown(worker.dispose);
    final scheduler = PdfPageRenderScheduler()..holding = holding;
    addTearDown(scheduler.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox(
          width: 400,
          child: PdfPageView(
            page: document.page(0),
            renderWorker: worker,
            renderScheduler: scheduler,
          ),
        ),
      ),
    ));
    return scheduler;
  }

  testWidgets('a worker-backed text page renders through a scroll hold',
      (tester) async {
    final scheduler = await pumpPage(tester, buildClassicPdf(), holding: true);
    for (var i = 0; i < 8 && !painted(tester); i++) {
      await settle(tester);
    }
    expect(painted(tester), isTrue,
        reason: 'the walk ran in the worker and the record is a few dozen '
            'commands - waiting out the scroll buys the frame nothing');
    expect(scheduler.holding, isTrue, reason: 'still scrolling');
  });

  testWidgets('an image-bearing page waits for the scroll to settle',
      (tester) async {
    // The fixture draws an inline image, so nothing at page level advertises
    // it. Whichever gate catches it - the record's own image draws, or the
    // fall-through to a local walk when the worker declines the buffer - the
    // page must not paint mid-scroll.
    final scheduler =
        await pumpPage(tester, buildEmbeddedFontImagePdf(), holding: true);
    for (var i = 0; i < 6; i++) {
      await settle(tester);
    }
    expect(painted(tester), isFalse,
        reason: 'an image decode/upload mid-fling is the hitch the hold '
            'exists to prevent');

    scheduler.holding = false;
    for (var i = 0; i < 10 && !painted(tester); i++) {
      await settle(tester);
    }
    expect(painted(tester), isTrue);
  });

  testWidgets('a record over the command ceiling waits for the settle',
      (tester) async {
    final previous = PdfPageView.motionSafeMaxCommands;
    PdfPageView.motionSafeMaxCommands = 0;
    addTearDown(() => PdfPageView.motionSafeMaxCommands = previous);
    final scheduler = await pumpPage(tester, buildClassicPdf(), holding: true);
    for (var i = 0; i < 6; i++) {
      await settle(tester);
    }
    expect(painted(tester), isFalse,
        reason: 'replaying a large buffer inside a scrolling frame is the '
            'cost the ceiling bounds');

    scheduler.holding = false;
    for (var i = 0; i < 10 && !painted(tester); i++) {
      await settle(tester);
    }
    expect(painted(tester), isTrue);
  });

  testWidgets('motionSafeRenders: false restores the strict hold',
      (tester) async {
    final previous = PdfPageView.motionSafeRenders;
    PdfPageView.motionSafeRenders = false;
    addTearDown(() => PdfPageView.motionSafeRenders = previous);
    final scheduler = await pumpPage(tester, buildClassicPdf(), holding: true);
    for (var i = 0; i < 6; i++) {
      await settle(tester);
    }
    expect(painted(tester), isFalse);

    scheduler.holding = false;
    for (var i = 0; i < 10 && !painted(tester); i++) {
      await settle(tester);
    }
    expect(painted(tester), isTrue);
  });
}
