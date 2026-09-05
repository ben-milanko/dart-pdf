// Diagnostic: lists every image a page references and whether it decodes.
// Skipped unless PDF_PATH is set:
//   PDF_PATH=/path.pdf PDF_PAGE=0 flutter test test/probe_images_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/src/image_decoder.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

void main() {
  final path = Platform.environment['PDF_PATH'];

  testWidgets('probe image decoding', (tester) async {
    if (path == null) {
      markTestSkipped('set PDF_PATH to probe a document');
      return;
    }
    await tester.runAsync(() async {
      final doc = PdfDocument.open(File(path).readAsBytesSync());
      final cos = doc.cos;
      final pageIndex =
          int.tryParse(Platform.environment['PDF_PAGE'] ?? '') ?? 0;
      final collector = ImageCollector();
      PdfInterpreter(cos: cos, device: collector).drawPage(doc.page(pageIndex));
      // ignore: avoid_print
      print('collected ${collector.streams.length} image draws');
      final images = await decodeImages(cos, collector.streams);
      for (final request in collector.streams) {
        final dict = request.stream.dictionary;
        final mask = cos.resolve(dict['SMask']);
        final maskDict = mask is CosStream ? mask.dictionary : null;
        // ignore: avoid_print
        print('${images.containsKey(pdfImageKey(request)) ? 'OK  ' : 'FAIL'} '
            '${cos.resolve(dict['Filter'])} '
            '${cos.resolve(dict['Width'])}x${cos.resolve(dict['Height'])} '
            'mask=${dict['ImageMask'] != null} '
            'smask=${dict['SMask'] != null}'
            '${maskDict == null ? '' : '(${cos.resolve(maskDict['Filter'])} '
                '${cos.resolve(maskDict['Width'])}x'
                '${cos.resolve(maskDict['Height'])})'}');
      }
    });
  });
}
