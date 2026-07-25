// PdfViewer stands up its own render worker when the host provides none, so a
// bare embed gets off-thread interpretation (#396 part 1). These pin the wiring
// via the host's debug spawn seam - no real isolate - so they assert *whether*
// a default worker is created, disposed, and sized, not the isolate itself.
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/render_worker_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

class _FakeWorker extends PdfRenderWorker {
  bool disposed = false;

  @override
  bool get isActive => !disposed;

  @override
  Future<List<PdfRenderCommand>?> record(int pageIndex,
          {bool annotations = true,
          int priority = 0,
          double? imagePixelRatio,
          bool decodeImages = true,
          int? commandLimit,
          PdfRect? imageDecodeRegion, PdfPartialRecordSink? onPartial}) async =>
      null;

  @override
  void cancel(int pageIndex, {int priority = 0}) {}

  @override
  void dispose() => disposed = true;
}

void main() {
  late List<_FakeWorker> spawned;
  late List<int?> spawnedCounts;

  setUp(() {
    // flutter_test_config.dart disables the default worker suite-wide; this file
    // is the one that exercises it, so turn it back on.
    PdfViewer.debugAutoRenderWorkerEnabled = true;
    spawned = [];
    spawnedCounts = [];
    PdfRenderWorkerHost.debugSpawnOverride = (bytes,
        {required int pageCount, int? workerCount, bool copySource = false}) {
      final worker = _FakeWorker();
      spawned.add(worker);
      spawnedCounts.add(workerCount);
      return worker;
    };
  });

  tearDown(() {
    PdfRenderWorkerHost.debugSpawnOverride = null;
    PdfViewer.debugAutoRenderWorkerEnabled = false; // restore the suite default
  });

  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
        MaterialApp(home: Scaffold(body: child)),
      );

  Widget viewer(Uint8List bytes,
          {bool autoRenderWorker = true, PdfRenderWorker? renderWorker}) =>
      PdfViewer(
        document: PdfDocument.open(bytes),
        initialFit: PdfViewerFit.width,
        autoRenderWorker: autoRenderWorker,
        renderWorker: renderWorker,
      );

  testWidgets('a bare viewer starts its own single default worker',
      (tester) async {
    await pump(tester, viewer(buildMultiPagePdf(3)));
    expect(spawned, hasLength(1), reason: 'the viewer must own a default worker');
    expect(spawnedCounts.single, 1, reason: 'the default is a single worker');
  });

  testWidgets('autoRenderWorker: false leaves interpretation on-thread',
      (tester) async {
    await pump(tester, viewer(buildMultiPagePdf(3), autoRenderWorker: false));
    expect(spawned, isEmpty);
  });

  testWidgets('an explicit renderWorker suppresses the default', (tester) async {
    final host = _FakeWorker();
    await pump(tester, viewer(buildMultiPagePdf(3), renderWorker: host));
    expect(spawned, isEmpty, reason: 'the host worker is used, none is spawned');
    expect(host.disposed, isFalse, reason: 'the viewer does not own the host worker');
  });

  testWidgets('the default worker is disposed with the viewer', (tester) async {
    await pump(tester, viewer(buildMultiPagePdf(3)));
    final worker = spawned.single;
    expect(worker.disposed, isFalse);

    await pump(tester, const SizedBox());
    expect(worker.disposed, isTrue);
  });

  testWidgets('an editing session gets a default worker too', (tester) async {
    final controller = PdfEditingController(buildMultiPagePdf(3));
    addTearDown(controller.dispose);
    await pump(
      tester,
      PdfViewer(editing: controller, initialFit: PdfViewerFit.width),
    );
    expect(spawned, hasLength(1),
        reason: 'the editing branch reads the controller bytes and spawns one');
  });
}
