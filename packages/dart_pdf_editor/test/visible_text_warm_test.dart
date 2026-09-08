import 'dart:async';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_cos/perf.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

class _TextWorker extends PdfRenderWorker {
  final requests =
      <({int page, int priority, Completer<PdfPageText?> reply})>[];

  @override
  bool get isActive => true;

  @override
  Future<PdfPageText?> extractText(int pageIndex, {int priority = 0}) {
    final reply = Completer<PdfPageText?>();
    requests.add((page: pageIndex, priority: priority, reply: reply));
    return reply.future;
  }

  @override
  Future<List<PdfRenderCommand>?> record(int pageIndex,
          {bool annotations = true,
          int priority = 0,
          double? imagePixelRatio,
          bool decodeImages = true,
          int? commandLimit,
          PdfRect? imageDecodeRegion,
          PdfPartialRecordSink? onPartial}) async =>
      null;

  @override
  void cancel(int pageIndex, {int priority = 0}) {}

  @override
  void dispose() {}
}

void main() {
  setUp(() {
    final threshold = PdfViewer.hoverTextExtractMaxRawContentBytes;
    PdfViewer.hoverTextExtractMaxRawContentBytes = 0;
    final perfEnabled = PdfPerf.enabled;
    PdfPerf.enabled = true;
    PdfPerf.reset();
    addTearDown(() {
      PdfViewer.hoverTextExtractMaxRawContentBytes = threshold;
      PdfPerf.enabled = perfEnabled;
    });
  });

  Future<void> pumpUntil(WidgetTester tester, bool Function() ready) async {
    for (var i = 0; i < 80 && !ready(); i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(ready(), isTrue);
  }

  Widget viewer(PdfDocument document, PdfViewerController controller,
          _TextWorker worker,
          {PdfEditingController? editing}) =>
      MaterialApp(
        home: Scaffold(
          body: PdfViewer(
            document: editing == null ? document : null,
            editing: editing,
            controller: controller,
            renderWorker: worker,
            autoRenderWorker: false,
            initialFit: PdfViewerFit.width,
            pagePreviews: false,
          ),
        ),
      );

  int localExtractions() =>
      PdfPerf.snapshot().phaseCalls[PdfPerfPhase.textExtract.index];

  testWidgets('ready heavy page warms on worker and search shares its request',
      (tester) async {
    final document = PdfDocument.open(buildClassicPdf());
    final result = PdfTextExtractor.extract(document, 0);
    PdfPerf.reset();
    final controller = PdfViewerController();
    final worker = _TextWorker();
    addTearDown(controller.dispose);
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await tester.pumpWidget(viewer(document, controller, worker));
    await pumpUntil(tester, () => worker.requests.isNotEmpty);
    expect(worker.requests.single.page, 0);
    expect(worker.requests.single.priority, greaterThan(0));
    expect(localExtractions(), 0);

    final search = controller.search('Hello');
    await tester.pump();
    expect(worker.requests, hasLength(1),
        reason: 'foreground search shares the already-pending text warm');
    worker.requests.single.reply.complete(result);
    await tester.pump();
    await search;
    expect(controller.matchCount, 1);
    expect(localExtractions(), 0);

    // A grab-pan begins by testing text. It must use the warmed text as well.
    final drag = await tester.startGesture(const Offset(450, 400),
        kind: PointerDeviceKind.mouse);
    await drag.moveBy(const Offset(-30, 0));
    await drag.up();
    await tester.pump(const Duration(seconds: 1));
    expect(localExtractions(), 0);
    expect(worker.requests, hasLength(1));
  });

  testWidgets('declined speculative extraction never falls back locally',
      (tester) async {
    final controller = PdfViewerController();
    final worker = _TextWorker();
    addTearDown(controller.dispose);
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await tester.pumpWidget(
        viewer(PdfDocument.open(buildClassicPdf()), controller, worker));
    await pumpUntil(tester, () => worker.requests.isNotEmpty);
    worker.requests.single.reply.complete(null);
    await tester.pump();
    await tester.pump();
    expect(localExtractions(), 0);
    expect(worker.requests, hasLength(1),
        reason: 'a declining worker must not trigger an idle retry loop');
  });

  testWidgets('navigation warms only the latest focused page one at a time',
      (tester) async {
    final document = PdfDocument.open(buildMultiPagePdf(3));
    final firstText = PdfTextExtractor.extract(document, 0);
    final secondText = PdfTextExtractor.extract(document, 1);
    PdfPerf.reset();
    final controller = PdfViewerController();
    final worker = _TextWorker();
    addTearDown(controller.dispose);
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await tester.pumpWidget(viewer(document, controller, worker));
    await pumpUntil(tester, () => worker.requests.isNotEmpty);
    unawaited(controller.jumpToPage(1));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await pumpUntil(tester, () => controller.isPageRasterReady(1));
    expect(controller.currentPage, 1);
    expect(worker.requests, hasLength(1),
        reason: 'navigation must not stack speculative extractions');

    worker.requests.first.reply.complete(firstText);
    await pumpUntil(tester, () => worker.requests.length == 2);
    expect(worker.requests.last.page, 1);
    worker.requests.last.reply.complete(secondText);
    await tester.pump(const Duration(seconds: 1));
    expect(worker.requests, hasLength(2),
        reason: 'off-screen pages must not be extracted speculatively');
    expect(localExtractions(), 0);
  });

  testWidgets(
      'text warm from an earlier editing revision cannot fill the cache',
      (tester) async {
    final editing = PdfEditingController(buildClassicPdf());
    final controller = PdfViewerController();
    final worker = _TextWorker();
    addTearDown(editing.dispose);
    addTearDown(controller.dispose);
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    final oldText = PdfTextExtractor.extract(editing.document, 0);
    PdfPerf.reset();
    await tester.pumpWidget(
        viewer(editing.document, controller, worker, editing: editing));
    await pumpUntil(tester, () => worker.requests.isNotEmpty);

    editing.apply((editor) {
      editor.stampPage(
          0, (stamp) => stamp.text('Revision marker', x: 72, y: 500));
    }, pages: const [0]);
    await tester.pump();
    final newText = PdfTextExtractor.extract(editing.document, 0);
    PdfPerf.reset();
    final search = controller.search('Revision marker');
    await tester.pump();
    expect(worker.requests, hasLength(2),
        reason: 'the new revision must not join an older revision request');

    // Complete the old request first; it must not win putIfAbsent at slot 0.
    worker.requests.first.reply.complete(oldText);
    await tester.pump();
    worker.requests.last.reply.complete(newText);
    await tester.pump();
    await search;
    expect(controller.matchCount, 1);
    await controller.search('Revision marker');
    expect(controller.matchCount, 1,
        reason: 'the current revision text, not the old reply, was cached');
    expect(localExtractions(), 0);
    await tester.pump(const Duration(seconds: 1));
  });
}
