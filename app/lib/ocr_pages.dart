import 'dart:async';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_document/pdf_document.dart'
    show PdfEditor, PdfOcrEditing, PdfOcrSpan;
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
  var spans = 0;
  final recognized = await recognizeAllPages(editor, engine,
      isCancelled: isCancelled, onPage: onPage);
  for (final MapEntry(key: page, value: pageSpans) in recognized.entries) {
    spans += editor.injectTextLayer(page, pageSpans);
  }
  return spans;
}

/// The recognition half of [ocrAllPages]: the same page loop, but the spans
/// come back keyed by page index instead of being written, so the caller can
/// lay them onto a later revision of the document (see `ocr_auto.dart`).
///
/// [includePage], when given, picks which pages are worth the model at all;
/// the others are skipped without being rasterized. Pages with nothing new to
/// add are left out of the result.
Future<Map<int, List<PdfOcrSpan>>> recognizeAllPages(
  PdfEditor editor,
  PdfOcrEngine engine, {
  required bool Function() isCancelled,
  required void Function(int page, int pageCount) onPage,
  bool Function(int page)? includePage,
}) async {
  final count = editor.document.pageCount;
  final result = <int, List<PdfOcrSpan>>{};
  for (var i = 0; i < count; i++) {
    if (isCancelled()) break;
    if (includePage != null && !includePage(i)) continue;
    onPage(i, count);
    final spans = await editor.recognizeOcr(i, engine,
        pixelRatio: OcrRunnerEngine.pixelRatioFor(editor.document.page(i)));
    if (spans.isNotEmpty) result[i] = spans;
    await Future<void>.delayed(Duration.zero);
  }
  return result;
}
