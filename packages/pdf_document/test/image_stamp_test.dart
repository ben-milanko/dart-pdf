// Inserting a raster image as a /Stamp annotation (PdfEditor.addImageStamp):
// the picture rides an appearance XObject so it inherits move/resize/rotate
// for free, and carries no /Contents so the text-stamp restyle never
// regenerates over it.
import 'dart:convert';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

// 2x2 RGBA-8 PNG (shared with image_pdf_test.dart / png_test.dart).
final _png = base64.decode('iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0k'
    'AAAAGUlEQVR4nGP4z8DwHwgbWBgZ/jNyicr7AgA3BAUOTnqjAAAAAABJRU5ErkJggg==');

void main() {
  PdfDocument roundTrip(void Function(PdfEditor) edit) {
    final editor = PdfEditor(PdfDocument.open(buildClassicPdf()));
    edit(editor);
    return PdfDocument.open(editor.save());
  }

  test('addImageStamp embeds an image XObject in a /Stamp appearance', () {
    final image = PdfEmbeddableImage.decode(_png);
    final doc = roundTrip(
        (e) => e.addImageStamp(0, const PdfRect(100, 500, 220, 620), image));
    final stamp = doc.page(0).annotations.single;
    expect(stamp.subtype, 'Stamp');
    // no /Contents: this is a picture, not a text stamp
    expect(stamp.contents, anyOf(isNull, isEmpty));

    final form = stamp.normalAppearance!;
    final content = latin1.decode(doc.cos.decodeStreamData(form));
    expect(content, contains('/Img0 Do'));
    // the unit image is mapped onto the rect (width 120, height 120, at
    // the rect's lower-left corner)
    expect(content, contains('120 0 0 120 100 500 cm'));

    final resources =
        doc.cos.resolve(form.dictionary['Resources']) as CosDictionary;
    final xobjects =
        doc.cos.resolve(resources['XObject']) as CosDictionary;
    final img = doc.cos.resolve(xobjects['Img0']) as CosStream;
    expect((doc.cos.resolve(img.dictionary['Subtype']) as CosName).value,
        'Image');
    expect((doc.cos.resolve(img.dictionary['Width']) as CosInteger).value, 2);
    expect((doc.cos.resolve(img.dictionary['Height']) as CosInteger).value, 2);
  });

  test('an image stamp is not restyleable (text-stamp regen would wipe it)',
      () {
    final image = PdfEmbeddableImage.decode(_png);
    final doc = roundTrip(
        (e) => e.addImageStamp(0, const PdfRect(0, 0, 100, 100), image));
    final stamp = doc.page(0).annotations.single;
    expect(pdfCanRestyleAnnotation(stamp), isFalse);
  });

  test('an image stamp resizes by stretching its appearance', () {
    final image = PdfEmbeddableImage.decode(_png);
    final doc = PdfDocument.open(buildClassicPdf());
    final editor = PdfEditor(doc)
      ..addImageStamp(0, const PdfRect(0, 0, 100, 100), image);
    final reopened = PdfDocument.open(editor.save());
    final stamp = reopened.page(0).annotations.single;

    final resize = PdfEditor(reopened)
      ..resizeAnnotation(0, stamp, const PdfRect(0, 0, 200, 50));
    final after = PdfDocument.open(resize.save());
    final resized = after.page(0).annotations.single;
    expect(resized.subtype, 'Stamp');
    expect(resized.rect.width, 200);
    expect(resized.rect.height, 50);
    // the picture survives the resize
    final content = latin1.decode(
        after.cos.decodeStreamData(resized.normalAppearance!));
    expect(content, contains('/Img0 Do'));
  });

  test('an opacity sets an alpha graphics state', () {
    final image = PdfEmbeddableImage.decode(_png);
    final doc = roundTrip((e) => e.addImageStamp(
        0, const PdfRect(0, 0, 100, 100), image,
        opacity: 0.5));
    final stamp = doc.page(0).annotations.single;
    expect(stamp.appearanceOpacity, closeTo(0.5, 1e-9));
  });
}
