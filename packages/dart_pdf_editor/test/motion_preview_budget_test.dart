// The in-motion vector preview budget (#998): a wheel burst rasterizes at
// most one command-limited preview, and only for a page with nothing to
// paint. Each of those previews is a UI-thread replay + readback; on a plan
// sheet they were the 67-175 ms gaps behind the wheel rAF p95 regression.
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

/// Records on the test isolate and counts the viewer's motion previews: the
/// command-limited, image-free, priority-1 records `_prerenderPreviews` asks
/// for while a scroll is in flight.
class _CountingWorker extends PdfRenderWorker {
  _CountingWorker(this._bytes);

  final Uint8List _bytes;
  late final PdfDocument _doc = PdfDocument.open(_bytes);
  bool _disposed = false;
  final motionPreviewPages = <int>[];

  @override
  bool get isActive => !_disposed;

  @override
  Future<List<PdfRenderCommand>?> record(int pageIndex,
      {bool annotations = true,
      Set<String> hiddenAnnotationSubtypes = const {},
      int priority = 0,
      double? imagePixelRatio,
      bool decodeImages = true,
      int? commandLimit,
      PdfRect? imageDecodeRegion,
      PdfPartialRecordSink? onPartial,
      PdfRecordDecodeGate? decodeGate}) async {
    if (_disposed || pageIndex < 0 || pageIndex >= _doc.pageCount) return null;
    if (!decodeImages && commandLimit == 2000 && priority == 1) {
      motionPreviewPages.add(pageIndex);
    }
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
  testWidgets('a wheel burst rasterizes at most one motion preview',
      (tester) async {
    final bytes = buildMultiPagePdf(40);
    final worker = _CountingWorker(bytes);
    addTearDown(worker.dispose);
    final controller = PdfViewerController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          document: PdfDocument.open(bytes),
          controller: controller,
          renderWorker: worker,
          initialFit: PdfViewerFit.width,
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    worker.motionPreviewPages.clear();

    // One fast, continuous wheel burst - a page per frame, far past the
    // pages any startup warm could have touched.
    final pointer = TestPointer(7, PointerDeviceKind.mouse);
    pointer.hover(const Offset(400, 300));
    for (var i = 0; i < 24; i++) {
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 600)));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 2)));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(controller.debugRenderHold, isTrue, reason: 'still in the burst');
    expect(worker.motionPreviewPages.length, lessThanOrEqualTo(1),
        reason: 'pages entering the viewport render through the scroll on '
            'their own; each further motion preview is a UI-thread replay '
            'and readback inside a wheel frame');

    // drain the scroll-quiet window so no timer outlives the test
    await tester.pump(const Duration(milliseconds: 600));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
  });
}
