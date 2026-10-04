import 'dart:async';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_document/pdf_document.dart' show PdfEditor;
import 'package:pdf_ocr_ondevice/pp_ocr.dart';

/// Runs [engine] over every page of [editor]'s document - the loop both the
/// native and the browser OCR jobs share - and returns how many spans were
/// written.
///
/// Each page is rasterized at [OcrRunnerEngine.pixelRatioFor] (216 dpi, capped
/// at 4000 px a side). [isCancelled] is checked before each page; [onPage] is
/// told which page is starting (0-based) and the page count, for a progress
/// UI. The event loop gets a turn between pages so the UI stays responsive.
Future<int> ocrAllPages(
  PdfEditor editor,
  PdfOcrEngine engine, {
  required bool Function() isCancelled,
  required void Function(int page, int pageCount) onPage,
}) async {
  final count = editor.document.pageCount;
  var spans = 0;
  for (var i = 0; i < count; i++) {
    if (isCancelled()) break;
    onPage(i, count);
    spans += await editor.applyOcr(i, engine,
        pixelRatio: OcrRunnerEngine.pixelRatioFor(editor.document.page(i)));
    await Future<void>.delayed(Duration.zero);
  }
  return spans;
}
