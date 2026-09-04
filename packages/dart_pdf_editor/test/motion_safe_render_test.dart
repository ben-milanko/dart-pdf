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
  _SyncWorker(this._bytes, {this.decline = false});

  final Uint8List _bytes;
  final bool decline;
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
    if (decline) return null;
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
    bool activeGesture = false,
    bool workerDeclines = false,
  }) async {
    final document = PdfDocument.open(bytes);
    final worker = _SyncWorker(bytes, decline: workerDeclines);
    addTearDown(worker.dispose);
    final scheduler = PdfPageRenderScheduler()
      ..holding = holding
      ..activeGesture = activeGesture;
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

  testWidgets('a page scrolled into view renders during the scroll',
      (tester) async {
    // The end-to-end property: what the reader scrolls onto is sharp before
    // the scroll-quiet window expires. (This layout does not discriminate the
    // *queuing* half of that - here the page mounts already on screen, and a
    // page that mounts on screen has always queued itself. The queuing fix is
    // for a cache-window neighbour that mounted off screen and then crossed
    // in, which is what a real viewport does; its evidence is the wheel-text
    // measurement in the dev-log, settle 505ms -> 0.3ms.)
    final bytes = buildMultiPagePdf(8);
    final document = PdfDocument.open(bytes);
    final worker = _SyncWorker(bytes);
    addTearDown(worker.dispose);
    final controller = PdfViewerController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          document: document,
          controller: controller,
          renderWorker: worker,
          initialFit: PdfViewerFit.page,
        ),
      ),
    ));
    await tester.pump();
    for (var i = 0; i < 40 && !controller.isPageRasterReady(0); i++) {
      await settle(tester);
    }
    // drain the startup settle timer so the hold below is the drag's own
    await tester.pump(const Duration(milliseconds: 550));
    expect(controller.debugRenderHold, isFalse);

    // First scroll: page 1 arrives and page 2 is built as an off-screen
    // cache-window neighbour - mounted, with nothing of its own painted. That
    // is the state the fix is about, and it is why the second scroll is the
    // one that matters: a page that MOUNTS on screen has always queued itself.
    await tester.drag(find.byType(PdfViewer), const Offset(0, -610));
    for (var i = 0; i < 12 && !controller.isPageRasterReady(1); i++) {
      await settle(tester);
    }
    await tester.pump(const Duration(milliseconds: 600));
    await settle(tester);
    expect(controller.debugRenderHold, isFalse);
    expect(controller.isPageRasterReady(2), isFalse,
        reason: 'the neighbour below the fold has not rendered yet');

    // Second scroll: page 2 crosses into the viewport.
    await tester.drag(find.byType(PdfViewer), const Offset(0, -610));
    await tester.pump();
    expect(controller.debugRenderHold, isTrue, reason: 'still scrolling');

    // Well inside the 500 ms scroll-quiet window.
    for (var i = 0; i < 12 && !controller.isPageRasterReady(2); i++) {
      await settle(tester);
    }
    expect(controller.isPageRasterReady(2), isTrue,
        reason: 'the page scrolled onto renders during the scroll');
    expect(controller.debugRenderHold, isTrue,
        reason: 'and it did so without waiting for the scroll to settle');

    // drain the scroll-quiet window so no timer outlives the test
    await tester.pump(const Duration(milliseconds: 600));
    await settle(tester);
  });

  testWidgets('a worker-backed big image waits for input, not full settle',
      (tester) async {
    // A megapixel-class underlay is the decode/upload the hold exists to
    // prevent. Whichever gate catches it - the page's own /XObject
    // dictionary, or the image draws in the returned record - it must not
    // land mid-scroll.
    final bytes = buildSyntheticRasterUnderlaySheet(
      underlays: const [PdfUnderlaySpec(width: 1200, height: 1200)],
      layers: 1,
      ops: 20,
    );
    final scheduler =
        await pumpPage(tester, bytes, holding: true, activeGesture: true);
    for (var i = 0; i < 6; i++) {
      await settle(tester);
    }
    expect(painted(tester), isFalse,
        reason: 'an image decode/upload must not land during live input');

    // Input stops, but the conservative 500ms scroll-settle hold remains.
    // The focused worker-backed page should sharpen in this short quiet lane
    // instead of making the reader stare at its preview for the whole hold.
    scheduler.activeGesture = false;
    for (var i = 0; i < 20 && !painted(tester); i++) {
      await settle(tester);
    }
    expect(painted(tester), isTrue);
    expect(scheduler.holding, isTrue,
        reason: 'background/local heavy work remains protected');
  });

  testWidgets('a declined big image keeps the strict local-render hold',
      (tester) async {
    final bytes = buildSyntheticRasterUnderlaySheet(
      underlays: const [PdfUnderlaySpec(width: 1200, height: 1200)],
      layers: 1,
      ops: 20,
    );
    final scheduler = await pumpPage(
      tester,
      bytes,
      holding: true,
      activeGesture: true,
      workerDeclines: true,
    );

    scheduler.activeGesture = false;
    for (var i = 0; i < 10; i++) {
      await settle(tester);
    }
    expect(painted(tester), isFalse,
        reason: 'a worker declaration is not enough: once it declines, the '
            'large walk would run locally and must retain the strict hold');

    scheduler.holding = false;
    for (var i = 0; i < 20 && !painted(tester); i++) {
      await settle(tester);
    }
    expect(painted(tester), isTrue);
  });

  testWidgets('a page carrying a small image renders through a scroll hold',
      (tester) async {
    // The letterhead case, and the reason the lane's old rule was wrong: a
    // page that declared ONE image - a 42x10 mark in the field trace that
    // prompted this - was refused the lane outright. On a document with that
    // mark on every page the lane never applied at all; every scheduler grant
    // in the trace read `cost=held`.
    final bytes = buildSyntheticRasterUnderlaySheet(
      underlays: const [PdfUnderlaySpec(width: 48, height: 48)],
      layers: 1,
      ops: 20,
    );
    final scheduler = await pumpPage(tester, bytes, holding: true);
    for (var i = 0; i < 20 && !painted(tester); i++) {
      await settle(tester);
    }
    expect(painted(tester), isTrue,
        reason: 'one small image is not a reason to make the reader wait out '
            'the scroll');
    expect(scheduler.holding, isTrue, reason: 'still scrolling');
  });

  testWidgets('the image budget chooses free versus input-quiet rendering',
      (tester) async {
    // The same page as above, with the budget moved under it: what governs is
    // how many pixels the page declares, not whether it declares any.
    final previous = PdfPageView.motionSafeMaxImagePixels;
    PdfPageView.motionSafeMaxImagePixels = 0;
    addTearDown(() => PdfPageView.motionSafeMaxImagePixels = previous);
    final bytes = buildSyntheticRasterUnderlaySheet(
      underlays: const [PdfUnderlaySpec(width: 48, height: 48)],
      layers: 1,
      ops: 20,
    );
    final scheduler =
        await pumpPage(tester, bytes, holding: true, activeGesture: true);
    for (var i = 0; i < 8; i++) {
      await settle(tester);
    }
    expect(painted(tester), isFalse,
        reason: 'the same page, one pixel over budget, stays out of a live '
            'input frame');

    scheduler.activeGesture = false;
    for (var i = 0; i < 20 && !painted(tester); i++) {
      await settle(tester);
    }
    expect(painted(tester), isTrue);
    expect(scheduler.holding, isTrue);
  });

  testWidgets('a large worker record waits for input, not full settle',
      (tester) async {
    final previous = PdfPageView.motionSafeMaxCommands;
    PdfPageView.motionSafeMaxCommands = 0;
    addTearDown(() => PdfPageView.motionSafeMaxCommands = previous);
    final scheduler = await pumpPage(tester, buildClassicPdf(),
        holding: true, activeGesture: true);
    for (var i = 0; i < 6; i++) {
      await settle(tester);
    }
    expect(painted(tester), isFalse,
        reason: 'replaying a large buffer inside a live input frame is the '
            'cost the ceiling bounds');

    scheduler.activeGesture = false;
    for (var i = 0; i < 10 && !painted(tester); i++) {
      await settle(tester);
    }
    expect(painted(tester), isTrue);
    expect(scheduler.holding, isTrue);
  });

  testWidgets('with no worker a small page renders in the scroll-quiet window',
      (tester) async {
    // The user-facing case behind this: a session with no render worker at
    // all (a host that never attached one, or a byte source still
    // completing). The walk is on the UI thread, so it must not run inside a
    // live gesture - but making a 12 ms walk sit out the whole 500 ms
    // scroll-quiet window is the half-second a reader feels after they stop.
    final bytes = buildClassicPdf();
    final document = PdfDocument.open(bytes);
    final scheduler = PdfPageRenderScheduler()
      ..holding = true
      ..activeGesture = true;
    addTearDown(scheduler.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox(
          width: 400,
          child: PdfPageView(
            page: document.page(0),
            renderScheduler: scheduler,
          ),
        ),
      ),
    ));
    for (var i = 0; i < 6; i++) {
      await settle(tester);
    }
    expect(painted(tester), isFalse,
        reason: 'a UI-thread walk must not run inside a live gesture');

    // The reader stops moving. The hold stays up - it is insurance against
    // the scroll resuming - but the gesture is over.
    scheduler.activeGesture = false;
    for (var i = 0; i < 10 && !painted(tester); i++) {
      await settle(tester);
    }
    expect(painted(tester), isTrue,
        reason: 'the quiet window is not a gesture');
    expect(scheduler.holding, isTrue);
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
