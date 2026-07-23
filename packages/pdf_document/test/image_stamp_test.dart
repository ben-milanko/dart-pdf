// Inserting a raster image as a /Stamp annotation (PdfEditor.addImageStamp):
// the picture rides an appearance XObject so it inherits move/resize/rotate
// for free. It carries no /Contents, so an opacity restyle re-bakes only its
// alpha over the same picture instead of redrawing a text check-mark.
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

  test('an image stamp is restyleable for opacity but reads as an image stamp',
      () {
    final image = PdfEmbeddableImage.decode(_png);
    final doc = roundTrip(
        (e) => e.addImageStamp(0, const PdfRect(0, 0, 100, 100), image));
    final stamp = doc.page(0).annotations.single;
    // the private marker survives the save/reopen round-trip
    expect(stamp.isImageStamp, isTrue);
    expect(pdfCanRestyleAnnotation(stamp), isTrue);
    expect(stamp.behavior.isImageStamp, isTrue);
    // it is a picture, not a colour swatch, so no tint control applies
    expect(stamp.behavior.supportsColor, isFalse);
    expect(stamp.behavior.supportsOpacity, isTrue);
  });

  test('a template stamp that contains an image is not an image stamp', () {
    // A vector/template stamp can carry an image component alongside shapes
    // and text. It must NOT be mistaken for a bare picture, or its restyle
    // would flatten every other part away.
    final template = PdfStampTemplate(
      width: 200,
      height: 100,
      components: [
        PdfStampTemplateComponent.rectangle(
            x: 0, y: 0, width: 200, height: 100, color: 0x2E7D32),
        PdfStampTemplateComponent.image(
            x: 10, y: 10, width: 40, height: 40, imageBytes: _png),
        PdfStampTemplateComponent.text(
            x: 60, y: 30, width: 130, height: 40, text: 'APPROVED', color: 0),
      ],
    );
    final doc = roundTrip((e) => e.addTemplateStamp(
        0, const PdfRect(100, 500, 300, 600), template,
        contents: 'APPROVED'));
    final stamp = doc.page(0).annotations.single;
    // its appearance really does embed an image...
    final content =
        latin1.decode(doc.cos.decodeStreamData(stamp.normalAppearance!));
    expect(content, contains(' Do'));
    // ...but it is not marked an image stamp, so it keeps its colour control
    // and never routes through the picture-only restyle path
    expect(stamp.isImageStamp, isFalse);
    expect(stamp.behavior.isImageStamp, isFalse);
    expect(stamp.behavior.supportsColor, isTrue);
  });

  test('restyling an image stamp changes its alpha but keeps the picture', () {
    final image = PdfEmbeddableImage.decode(_png);
    final doc = PdfDocument.open(buildClassicPdf());
    final editor = PdfEditor(doc)
      ..addImageStamp(0, const PdfRect(0, 0, 100, 100), image);
    final reopened = PdfDocument.open(editor.save());
    final stamp = reopened.page(0).annotations.single;
    expect(stamp.appearanceOpacity, closeTo(1, 1e-9));

    final restyle = PdfEditor(reopened)
      ..restyleAnnotation(0, stamp, opacity: 0.3);
    final after = PdfDocument.open(restyle.save());
    final restyled = after.page(0).annotations.single;
    expect(restyled.subtype, 'Stamp');
    expect(restyled.appearanceOpacity, closeTo(0.3, 1e-9));

    // the picture survives - the appearance still draws the same image
    final form = restyled.normalAppearance!;
    final content = latin1.decode(after.cos.decodeStreamData(form));
    expect(content, contains('/Img0 Do'));
    final resources =
        after.cos.resolve(form.dictionary['Resources']) as CosDictionary;
    final xobjects = after.cos.resolve(resources['XObject']) as CosDictionary;
    final img = after.cos.resolve(xobjects['Img0']) as CosStream;
    expect((after.cos.resolve(img.dictionary['Subtype']) as CosName).value,
        'Image');
  });

  test('restyling an image stamp preserves its bumped alpha across a save', () {
    // a second restyle reads the current alpha back (not a reset to opaque)
    final image = PdfEmbeddableImage.decode(_png);
    final doc = PdfDocument.open(buildClassicPdf());
    final editor = PdfEditor(doc)
      ..addImageStamp(0, const PdfRect(0, 0, 100, 100), image, opacity: 0.5);
    final reopened = PdfDocument.open(editor.save());
    final stamp = reopened.page(0).annotations.single;

    // restyle with no opacity: the existing 0.5 alpha must be preserved
    final restyle = PdfEditor(reopened)
      ..restyleAnnotation(0, stamp, opacity: 0.5);
    final after = PdfDocument.open(restyle.save());
    expect(after.page(0).annotations.single.appearanceOpacity,
        closeTo(0.5, 1e-9));
  });

  test('an image stamp on a rotated page counter-rotates its appearance', () {
    // pageRotation != 0 wraps the image draw in a save + counter-rotation so
    // the picture reads upright on a /Rotate 90 page.
    final image = PdfEmbeddableImage.decode(_png);
    final doc = roundTrip((e) => e.addImageStamp(
        0, const PdfRect(100, 500, 220, 620), image,
        opacity: 0.5, pageRotation: 90));
    final stamp = doc.page(0).annotations.single;
    expect(stamp.subtype, 'Stamp');
    expect(stamp.isImageStamp, isTrue);
    expect(stamp.appearanceOpacity, closeTo(0.5, 1e-9));
    final content =
        latin1.decode(doc.cos.decodeStreamData(stamp.normalAppearance!));
    // the image is still drawn, now under a counter-rotation matrix
    expect(content, contains('/Img0 Do'));
    expect(content, contains(' cm'));
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

  group('image stamp cropping', () {
    final image = PdfEmbeddableImage.decode(_png);

    test('addImageStamp with a crop clips the box and scales the picture', () {
      // The central half of the source fills the 120x120 box: the scaled
      // picture (240x240) is clipped to the box so only the crop shows.
      final doc = roundTrip((e) => e.addImageStamp(
          0, const PdfRect(100, 500, 220, 620), image,
          crop: const PdfRect(0.25, 0.25, 0.75, 0.75)));
      final stamp = doc.page(0).annotations.single;
      expect(stamp.isImageStamp, isTrue);
      expect(stamp.imageStampCrop, const PdfRect(0.25, 0.25, 0.75, 0.75));
      final content =
          latin1.decode(doc.cos.decodeStreamData(stamp.normalAppearance!));
      expect(content, contains('/Img0 Do'));
      // clip rect = the box; scaled cm maps the crop onto it
      expect(content, contains('100 500 120 120 re'));
      expect(content, contains('W'));
      expect(content, contains('240 0 0 240 40 440 cm'));
    });

    test('a full crop reads back as no crop and bakes an identity map', () {
      final doc = roundTrip((e) => e.addImageStamp(
          0, const PdfRect(100, 500, 220, 620), image,
          crop: const PdfRect(0, 0, 1, 1)));
      final stamp = doc.page(0).annotations.single;
      // full-image crop drops the marker
      expect(stamp.imageStampCrop, isNull);
      expect(stamp.dict.containsKey('DartPdfImageCrop'), isFalse);
      final content =
          latin1.decode(doc.cos.decodeStreamData(stamp.normalAppearance!));
      // identity fit, no clip
      expect(content, contains('120 0 0 120 100 500 cm'));
    });

    test('cropImageStamp crops in place at the current box', () {
      final base = PdfDocument.open(buildClassicPdf());
      final editor = PdfEditor(base)
        ..addImageStamp(0, const PdfRect(0, 0, 100, 100), image);
      final reopened = PdfDocument.open(editor.save());
      final stamp = reopened.page(0).annotations.single;

      final crop = PdfEditor(reopened)
        ..cropImageStamp(0, stamp, crop: const PdfRect(0, 0, 0.5, 1));
      final after = PdfDocument.open(crop.save());
      final cropped = after.page(0).annotations.single;
      // box unchanged, crop recorded
      expect(cropped.rect, const PdfRect(0, 0, 100, 100));
      expect(cropped.imageStampCrop, const PdfRect(0, 0, 0.5, 1));
      final content =
          latin1.decode(after.cos.decodeStreamData(cropped.normalAppearance!));
      // left half fills the box: x scaled by 2, y unchanged
      expect(content, contains('0 0 100 100 re'));
      expect(content, contains('200 0 0 100 0 0 cm'));
    });

    test('cropImageStamp with a rect shrinks the box to the crop', () {
      final base = PdfDocument.open(buildClassicPdf());
      final editor = PdfEditor(base)
        ..addImageStamp(0, const PdfRect(0, 0, 100, 100), image);
      final reopened = PdfDocument.open(editor.save());
      final stamp = reopened.page(0).annotations.single;

      final crop = PdfEditor(reopened)
        ..cropImageStamp(0, stamp,
            crop: const PdfRect(0, 0, 0.5, 1),
            rect: const PdfRect(0, 0, 50, 100));
      final after = PdfDocument.open(crop.save());
      final cropped = after.page(0).annotations.single;
      expect(cropped.rect, const PdfRect(0, 0, 50, 100));
      expect(cropped.imageStampCrop, const PdfRect(0, 0, 0.5, 1));
      final content =
          latin1.decode(after.cos.decodeStreamData(cropped.normalAppearance!));
      // the retained left half keeps its scale (100 pt wide source → 50 pt
      // box shows the left 50 pt), so the cm re-maps at the same scale
      expect(content, contains('0 0 50 100 re'));
      expect(content, contains('100 0 0 100 0 0 cm'));
    });

    test('an opacity restyle preserves the crop', () {
      final base = PdfDocument.open(buildClassicPdf());
      final editor = PdfEditor(base)
        ..addImageStamp(0, const PdfRect(0, 0, 100, 100), image,
            crop: const PdfRect(0.1, 0.2, 0.9, 0.8));
      final reopened = PdfDocument.open(editor.save());
      final stamp = reopened.page(0).annotations.single;
      expect(stamp.imageStampCrop, const PdfRect(0.1, 0.2, 0.9, 0.8));

      final restyle = PdfEditor(reopened)
        ..restyleAnnotation(0, stamp, opacity: 0.4);
      final after = PdfDocument.open(restyle.save());
      final restyled = after.page(0).annotations.single;
      expect(restyled.appearanceOpacity, closeTo(0.4, 1e-9));
      // the crop marker and the clipped appearance both survive
      expect(restyled.imageStampCrop, const PdfRect(0.1, 0.2, 0.9, 0.8));
      final content =
          latin1.decode(after.cos.decodeStreamData(restyled.normalAppearance!));
      expect(content, contains('/Img0 Do'));
      expect(content, contains('W'));
      expect(content, contains(' re'));
    });

    test('cropping composes: a second crop narrows towards the source', () {
      final base = PdfDocument.open(buildClassicPdf());
      final editor = PdfEditor(base)
        ..addImageStamp(0, const PdfRect(0, 0, 100, 100), image,
            crop: const PdfRect(0, 0, 0.5, 1));
      final reopened = PdfDocument.open(editor.save());
      final stamp = reopened.page(0).annotations.single;
      // caller composes against the source: the left quarter overall
      final crop = PdfEditor(reopened)
        ..cropImageStamp(0, stamp, crop: const PdfRect(0, 0, 0.25, 1));
      final after = PdfDocument.open(crop.save());
      expect(after.page(0).annotations.single.imageStampCrop,
          const PdfRect(0, 0, 0.25, 1));
    });

    test('cropImageStamp back to full clears the crop marker', () {
      final base = PdfDocument.open(buildClassicPdf());
      final editor = PdfEditor(base)
        ..addImageStamp(0, const PdfRect(0, 0, 100, 100), image,
            crop: const PdfRect(0.25, 0.25, 0.75, 0.75));
      final reopened = PdfDocument.open(editor.save());
      final stamp = reopened.page(0).annotations.single;

      final reset = PdfEditor(reopened)
        ..cropImageStamp(0, stamp, crop: const PdfRect(0, 0, 1, 1));
      final after = PdfDocument.open(reset.save());
      final cleared = after.page(0).annotations.single;
      expect(cleared.imageStampCrop, isNull);
      expect(cleared.dict.containsKey('DartPdfImageCrop'), isFalse);
    });

    test('cropImageStamp is a no-op on a non-image stamp', () {
      final base = PdfDocument.open(buildClassicPdf());
      final editor = PdfEditor(base)
        ..addNote(0, 100, 100, 'hi');
      final reopened = PdfDocument.open(editor.save());
      final note = reopened.page(0).annotations.single;
      final tried = PdfEditor(reopened)
          .cropImageStamp(0, note, crop: const PdfRect(0, 0, 0.5, 0.5));
      expect(tried, isFalse);
    });
  });
}
