// A CLI-style example that exports the pages of a PDF to PNG/JPEG image
// files - the public "PDF → image" entry point ([PdfPageExport]).
//
// Rasterization needs the Flutter engine (`dart:ui`), so this runs under the
// flutter_test harness rather than `dart run`:
//
//   PDF_PATH=in.pdf OUT_DIR=/tmp/pages DPI=200 FORMAT=png \
//     fvm flutter test example/tool/pdf_to_images.dart
//
// Environment:
//   PDF_PATH   the PDF to export (required)
//   OUT_DIR    where to write the images (default /tmp/pdf_pages)
//   DPI        resolution in dots per inch (default 150)
//   FORMAT     png | jpeg (default png)
//   PAGES      "all" or a 0-based "start-end" range, inclusive (default all)
//
// `dart:io` here is fine - this is an example/tool, not library code.
import 'dart:io';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';

void main() {
  testWidgets('export PDF pages to images', (tester) async {
    final path = Platform.environment['PDF_PATH'];
    if (path == null) {
      // ignore: avoid_print
      print('set PDF_PATH to the PDF to export');
      return;
    }
    final outDir = Platform.environment['OUT_DIR'] ?? '/tmp/pdf_pages';
    final dpi = double.tryParse(Platform.environment['DPI'] ?? '') ?? 150;
    final format = (Platform.environment['FORMAT'] ?? 'png') == 'jpeg'
        ? PdfRasterFormat.jpeg
        : PdfRasterFormat.png;
    final ext = format == PdfRasterFormat.jpeg ? 'jpg' : 'png';

    final doc = PdfDocument.open(File(path).readAsBytesSync());
    var start = 0;
    int? count;
    final pages = Platform.environment['PAGES'];
    if (pages != null && pages != 'all' && pages.contains('-')) {
      final parts = pages.split('-');
      start = int.parse(parts[0]);
      count = int.parse(parts[1]) - start + 1;
    }

    Directory(outDir).createSync(recursive: true);
    await tester.runAsync(() async {
      final images = await PdfPageExport.exportPages(
        doc,
        start: start,
        count: count,
        format: format,
        dpi: dpi,
      );
      for (var i = 0; i < images.length; i++) {
        final n = (start + i).toString().padLeft(4, '0');
        final file = File('$outDir/page_$n.$ext');
        file.writeAsBytesSync(images[i]);
        // ignore: avoid_print
        print('wrote ${file.path} (${images[i].length} bytes)');
      }
    });
  });
}
