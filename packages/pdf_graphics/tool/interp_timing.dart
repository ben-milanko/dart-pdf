// Times the interpreter walk per page across a set of PDFs and prints
// the slowest, worst page first:
//
//   fvm dart run tool/interp_timing.dart ../../corpus/*.pdf
//
// One walk is roughly half of what PdfPageRenderer.renderPicture costs
// on the UI thread (it walks twice: image collection, then painting) -
// the stall the viewer's fast-scroll render hold exists to avoid.
import 'dart:io';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

class NullDevice implements PdfDevice {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main(List<String> args) {
  final results = <(String, int, int, int)>[]; // file, page, pages, ms
  for (final path in args) {
    try {
      final doc = PdfDocument.open(File(path).readAsBytesSync());
      var worstMs = 0;
      var worstPage = 0;
      final pages = doc.pageCount;
      for (var i = 0; i < pages && i < 30; i++) {
        final sw = Stopwatch()..start();
        try {
          PdfInterpreter(cos: doc.cos, device: NullDevice())
              .drawPage(doc.page(i));
        } catch (_) {}
        sw.stop();
        if (sw.elapsedMilliseconds > worstMs) {
          worstMs = sw.elapsedMilliseconds;
          worstPage = i;
        }
      }
      results.add((path.split('/').last, worstPage, pages, worstMs));
    } catch (_) {
      // unreadable file: skip
    }
  }
  results.sort((a, b) => b.$4.compareTo(a.$4));
  for (final r in results.take(12)) {
    print('${r.$4.toString().padLeft(6)} ms  page ${r.$2} of ${r.$3}  ${r.$1}');
  }
}
