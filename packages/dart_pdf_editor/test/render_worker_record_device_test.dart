// Which device a native worker record walks into: the streaming wire writer,
// or the command-graph recorder. A decoding record of a page that draws an
// image has to deserialize a streamed buffer and serialize it again with
// decoding on, which costs more than the graph it saved until the page's
// content is very large - so a light text-plus-image page (a letterhead
// report) keeps the recorder, and everything else streams.
import 'dart:typed_data';

import 'package:dart_pdf_editor/src/render_worker_isolate.dart'
    show pdfWorkerRecordStreams, pdfWorkerStreamedImagePageMinContentBytes;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

CosStream _image() => CosStream(
      CosDictionary({
        'Type': const CosName('XObject'),
        'Subtype': const CosName('Image'),
        'Width': const CosInteger(2),
        'Height': const CosInteger(2),
        'BitsPerComponent': const CosInteger(8),
        'ColorSpace': const CosName('DeviceGray'),
      }),
      Uint8List(4),
    );

CosStream _form(CosObject resources, String content) => CosStream(
      CosDictionary({
        'Type': const CosName('XObject'),
        'Subtype': const CosName('Form'),
        'BBox': CosArray(const [
          CosInteger(0),
          CosInteger(0),
          CosInteger(10),
          CosInteger(10),
        ]),
        'Resources': resources,
      }),
      Uint8List.fromList(content.codeUnits),
    );

/// A one-page document: [content] over [resources], plus [annots].
PdfPage _page(
  CosDocumentBuilder builder, {
  required String content,
  CosDictionary? resources,
  List<CosObject> annots = const [],
}) {
  final pages = CosDictionary({
    'Type': const CosName('Pages'),
    'Count': const CosInteger(1),
  });
  final pagesRef = builder.add(pages);
  final page = CosDictionary({
    'Type': const CosName('Page'),
    'Parent': pagesRef,
    'MediaBox': CosArray(const [
      CosInteger(0),
      CosInteger(0),
      CosInteger(200),
      CosInteger(200),
    ]),
    'Resources': resources ?? CosDictionary(),
    'Contents': builder
        .add(CosStream(CosDictionary(), Uint8List.fromList(content.codeUnits))),
  });
  if (annots.isNotEmpty) page['Annots'] = CosArray(annots.toList());
  final pageRef = builder.add(page);
  pages['Kids'] = CosArray([pageRef]);
  final catalog = builder.add(CosDictionary({
    'Type': const CosName('Catalog'),
    'Pages': pagesRef,
  }));
  return PdfDocument.open(builder.build(root: catalog)).page(0);
}

bool _streams(PdfPage page, {bool annotations = true}) =>
    pdfWorkerRecordStreams(page, page.contentBytes(),
        decodeImages: true, annotations: annotations);

void main() {
  final imagePage = PdfDocument.open(PdfImageDocument.fromImageBytes([
    img.encodePng(img.Image(width: 8, height: 8)),
  ])).page(0);
  final vectorPage =
      PdfDocument.open(buildSyntheticCadStrip(ops: 200, streams: 1)).page(0);
  final imageContent = imagePage.contentBytes();
  final vectorContent = vectorPage.contentBytes();

  test('a decoding record of a light page that declares an image records', () {
    expect(imageContent.length,
        lessThan(pdfWorkerStreamedImagePageMinContentBytes));
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
            decodeImages: true, minContentBytes: imageContent.length),
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

  // Images that do not sit directly in the page's /XObject dictionary.
  test('an image inside a form (a wrapped logo) records', () {
    final builder = CosDocumentBuilder();
    final image = builder.add(_image());
    final inner = builder.add(_form(
        CosDictionary({
          'XObject': CosDictionary({'Im0': image}),
        }),
        '/Im0 Do'));
    // Two forms deep, as a PDF-in-PDF include wraps it.
    final outer = builder.add(_form(
        CosDictionary({
          'XObject': CosDictionary({'Fm1': inner}),
        }),
        '/Fm1 Do'));
    final page = _page(builder,
        content: 'q /Fm0 Do Q',
        resources: CosDictionary({
          'XObject': CosDictionary({'Fm0': outer}),
        }));
    expect(_streams(page), isFalse);
  });

  test('a form that draws no image still streams, and a cycle terminates', () {
    final builder = CosDocumentBuilder();
    final formDict = CosDictionary();
    final selfRef = builder.add(_form(formDict, '0 0 m 10 10 l S'));
    // The form's resources name the form itself.
    formDict['XObject'] = CosDictionary({'Fm0': selfRef});
    final page = _page(builder,
        content: '/Fm0 Do',
        resources: CosDictionary({
          'XObject': CosDictionary({'Fm0': selfRef}),
        }));
    expect(_streams(page), isTrue);
  });

  test('an inline image records', () {
    final builder = CosDocumentBuilder();
    final page = _page(builder,
        content: 'q 10 0 0 10 0 0 cm\nBI /W 1 /H 1 /BPC 8 /CS /G ID \x80 EI Q');
    expect(_streams(page), isFalse);
  });

  test('BI inside a longer token is not an inline image', () {
    final builder = CosDocumentBuilder();
    final page = _page(builder, content: '/BIG gs 0 0 m 1 1 l S');
    expect(_streams(page), isTrue);
  });

  test('an image in an annotation appearance records when annotations draw',
      () {
    // The editor's image stamps and signatures draw through their /AP.
    final builder = CosDocumentBuilder();
    final image = builder.add(_image());
    final appearance = builder.add(_form(
        CosDictionary({
          'XObject': CosDictionary({'Im0': image}),
        }),
        'q 10 0 0 10 0 0 cm /Im0 Do Q'));
    final annot = builder.add(CosDictionary({
      'Type': const CosName('Annot'),
      'Subtype': const CosName('Stamp'),
      'Rect': CosArray(const [
        CosInteger(0),
        CosInteger(0),
        CosInteger(10),
        CosInteger(10),
      ]),
      'AP': CosDictionary({'N': appearance}),
    }));
    final page = _page(builder, content: '0 0 m 1 1 l S', annots: [annot]);
    expect(_streams(page), isFalse);
    expect(_streams(page, annotations: false), isTrue,
        reason: 'a record without annotations never draws the appearance');
  });
}
