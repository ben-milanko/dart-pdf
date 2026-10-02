// Which device a native worker record walks into: the streaming wire writer,
// or the command-graph recorder. A decoding record of a page that declares an
// image has to deserialize a streamed buffer and serialize it again with
// decoding on, which costs more than the graph it saved until the page's
// content is very large - so a light text-plus-image page (a letterhead
// report) keeps the recorder, and everything else streams.
import 'package:dart_pdf_editor/src/render_worker_isolate.dart'
    show pdfWorkerRecordStreams, pdfWorkerStreamedImagePageMinContentBytes;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main() {
  final imagePage = PdfDocument.open(PdfImageDocument.fromImageBytes([
    img.encodePng(img.Image(width: 8, height: 8)),
  ])).page(0);
  final vectorPage =
      PdfDocument.open(buildSyntheticCadStrip(ops: 200, streams: 1)).page(0);
  final imageContent = imagePage.contentBytes().length;
  final vectorContent = vectorPage.contentBytes().length;

  test('a decoding record of a light page that declares an image records', () {
    expect(imageContent, lessThan(pdfWorkerStreamedImagePageMinContentBytes));
    expect(pdfWorkerRecordStreams(imagePage, imageContent, decodeImages: true),
        isFalse);
  });

  test('the same page streams when the record does not decode', () {
    expect(pdfWorkerRecordStreams(imagePage, imageContent, decodeImages: false),
        isTrue);
  });

  test('a heavy image page streams even when decoding', () {
    expect(
        pdfWorkerRecordStreams(imagePage, imageContent,
            decodeImages: true, minContentBytes: imageContent),
        isTrue);
  });

  test('an image-free page streams when decoding', () {
    expect(
        pdfWorkerRecordStreams(vectorPage, vectorContent, decodeImages: true),
        isTrue);
  });

  test('a command-limited record always records', () {
    for (final decodeImages in [true, false]) {
      expect(
          pdfWorkerRecordStreams(vectorPage, vectorContent,
              decodeImages: decodeImages, commandLimit: 500),
          isFalse);
    }
  });
}
