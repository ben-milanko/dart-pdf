// In-place annotation restyling: PdfEditor.restyleAnnotation regenerates
// appearances at the current geometry (same object numbers), and
// pdfCanRestyleAnnotation gates what restyles faithfully.

import 'dart:convert';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

PdfDocument edited(PdfDocument doc, void Function(PdfEditor) edit) {
  final editor = PdfEditor(doc);
  edit(editor);
  return PdfDocument.open(editor.save());
}

String content(PdfDocument doc, PdfAnnotation annotation) =>
    latin1.decode(doc.cos.decodeStreamData(annotation.normalAppearance!));

String rgb(int color) =>
    ContentWriter.rgbComponents(color).map(ContentWriter.fmt).join(' ');

double matrixEntry(PdfDocument doc, PdfAnnotation annotation, int i) {
  final matrix = doc.cos
      .resolve(annotation.normalAppearance!.dictionary['Matrix']) as CosArray;
  return switch (doc.cos.resolve(matrix[i])) {
    CosInteger(:final value) => value.toDouble(),
    CosReal(:final value) => value,
    _ => double.nan,
  };
}

void main() {
  test('square: color, width, fill, and opacity restyle in place', () {
    final doc = edited(
        PdfDocument.open(buildMultiPagePdf(1)),
        (e) => e.addSquare(0, const PdfRect(100, 600, 200, 660),
            strokeColor: 0xE53935, strokeWidth: 2, author: 'Ben'));
    final before = doc.page(0).annotations.single;
    final formRef = doc.cos.referenceTo(before.normalAppearance!)!;
    expect(pdfCanRestyleAnnotation(before), isTrue);

    final out = edited(
        doc,
        (e) => e.restyleAnnotation(0, before,
            color: 0x1E88E5,
            fillColor: (0x43A047,),
            strokeWidth: 4,
            opacity: 0.5));
    final after = out.page(0).annotations.single;
    expect(after.color, 0x1E88E5);
    expect(after.interiorColor, 0x43A047);
    expect(after.borderWidth, 4);
    expect(after.appearanceOpacity, closeTo(0.5, 1e-6));
    expect(after.rect, const PdfRect(100, 600, 200, 660));
    expect(after.author, 'Ben'); // identity survives an in-place restyle
    final stream = content(out, after);
    expect(stream, contains('${rgb(0x1E88E5)} RG'));
    expect(stream, contains('${rgb(0x43A047)} rg'));
    expect(stream, contains('4 w'));
    // the appearance kept its object number - replaced, not re-added
    expect(out.cos.referenceTo(after.normalAppearance!)!.objectNumber,
        formRef.objectNumber);
  });

  test('square: (null,) clears the fill', () {
    final doc = edited(
        PdfDocument.open(buildMultiPagePdf(1)),
        (e) => e.addSquare(0, const PdfRect(100, 600, 200, 660),
            strokeWidth: 2, fillColor: 0x43A047));
    final out = edited(
        doc,
        (e) => e.restyleAnnotation(0, doc.page(0).annotations.single,
            fillColor: (null,)));
    final after = out.page(0).annotations.single;
    expect(after.interiorColor, isNull);
    expect(content(out, after), isNot(contains(' rg')));
  });

  test('ink: a width restyle scales pressured segments and re-pads /Rect',
      () {
    final doc = edited(
        PdfDocument.open(buildMultiPagePdf(1)),
        (e) => e.addInk(0, [
              [(100, 600), (150, 640), (200, 600)],
            ], color: 0xE53935, strokeWidth: 2, pressures: [
              [1.0, 0.5, 0.0],
            ]));
    final before = doc.page(0).annotations.single;
    // the base lineWidth op, then one `w` per pressured segment
    final widthsBefore = RegExp(r'([\d.]+) w')
        .allMatches(content(doc, before))
        .map((m) => double.parse(m.group(1)!))
        .toList();
    expect(widthsBefore, hasLength(3));

    final out = edited(doc,
        (e) => e.restyleAnnotation(0, before, color: 0x1E88E5, strokeWidth: 4));
    final after = out.page(0).annotations.single;
    expect(after.color, 0x1E88E5);
    expect(after.borderWidth, 4);
    final widthsAfter = RegExp(r'([\d.]+) w')
        .allMatches(content(out, after))
        .map((m) => double.parse(m.group(1)!))
        .toList();
    // segment widths [2.6, 1.4] invert to point pressures
    // [0.75, 0.5, 0.25] (the segment→point averaging smooths the ends),
    // which re-render at base 4 as [4.6, 3.4] - still clearly pressured
    expect(widthsAfter, hasLength(3));
    expect(widthsAfter[0], closeTo(4, 1e-3)); // the base lineWidth op
    expect(widthsAfter[1], closeTo(4.6, 1e-3));
    expect(widthsAfter[2], closeTo(3.4, 1e-3));
    // the rect re-pads from the widest recovered pen point
    expect(after.rect.left,
        closeTo(100 - (pdfInkStrokeWidth(4, 0.75) / 2 + 1), 1e-6));
    // the centerline is untouched
    expect(after.inkList!.single, hasLength(3));
  });

  test('highlight: recolor keeps Multiply blending and the old opacity', () {
    final doc = edited(
        PdfDocument.open(buildMultiPagePdf(1)),
        (e) => e.addHighlight(0, [const PdfRect(100, 500, 200, 515)],
            color: 0xFFD100, opacity: 0.5));
    final before = doc.page(0).annotations.single;
    expect(pdfCanRestyleAnnotation(before), isTrue);

    final out =
        edited(doc, (e) => e.restyleAnnotation(0, before, color: 0x43A047));
    final after = out.page(0).annotations.single;
    expect(after.color, 0x43A047);
    expect(after.appearanceOpacity, closeTo(0.5, 1e-6));
    expect(content(out, after), contains('${rgb(0x43A047)} rg'));
    final resources = out.cos
        .resolve(after.normalAppearance!.dictionary['Resources']) as CosDictionary;
    final gs = out.cos.resolve(
            (out.cos.resolve(resources['ExtGState']) as CosDictionary)['GS0'])
        as CosDictionary;
    expect((out.cos.resolve(gs['BM']) as CosName).value, 'Multiply');
  });

  test('free text: color restyles the text, fill the background', () {
    final doc = edited(
        PdfDocument.open(buildMultiPagePdf(1)),
        (e) => e.addFreeText(0, const PdfRect(100, 560, 300, 620), 'Hello'));
    final recolored = edited(
        doc,
        (e) => e.restyleAnnotation(0, doc.page(0).annotations.single,
            color: 0xE53935));
    final style = recolored.page(0).annotations.single.freeTextStyle!;
    expect(style.color, 0xE53935);
    // no background: /C mirrors the text color, which parses as none
    expect(style.fillColor, isNull);

    final filled = edited(
        recolored,
        (e) => e.restyleAnnotation(0, recolored.page(0).annotations.single,
            fillColor: (0xFFF59D,)));
    final filledStyle = filled.page(0).annotations.single.freeTextStyle!;
    expect(filledStyle.color, 0xE53935); // text color survives a fill change
    expect(filledStyle.fillColor, 0xFFF59D);
    expect(content(filled, filled.page(0).annotations.single),
        contains('${rgb(0xFFF59D)} rg'));
  });

  test('free text opacity restyles in place and preserves rich runs', () {
    final doc = edited(
        PdfDocument.open(buildMultiPagePdf(1)),
        (e) => e.addFreeTextRich(
              0,
              const PdfRect(100, 560, 320, 630),
              const [
                PdfFreeTextRun('Bold ',
                    font: PdfStandardFont.helveticaBold),
                PdfFreeTextRun('red', color: 0xFF0000),
              ],
              opacity: 0.7,
            ));
    final before = doc.page(0).annotations.single;

    final out = edited(
        doc,
        (e) => e.restyleAnnotation(0, before, opacity: 0.25));
    final after = out.page(0).annotations.single;
    final appearance = content(out, after);

    expect(after.appearanceOpacity, closeTo(0.25, 1e-9));
    expect(after.richContent, isNotNull);
    expect(appearance, contains('/HelvBold'));
    expect(appearance, contains('1 0 0 rg'));
  });

  test('note and stamp recolor with regenerated artwork', () {
    final doc = edited(PdfDocument.open(buildMultiPagePdf(1)), (e) {
      e.addNote(0, 100, 700, 'A note');
      e.addStamp(0, const PdfRect(100, 600, 240, 650), 'DRAFT',
          opacity: 0.8);
    });
    final out = edited(doc, (e) {
      e.restyleAnnotation(0, doc.page(0).annotations[0], color: 0x1E88E5);
      e.restyleAnnotation(0, doc.page(0).annotations[1], color: 0x43A047);
    });
    final note = out.page(0).annotations[0];
    final stamp = out.page(0).annotations[1];
    expect(note.color, 0x1E88E5);
    expect(content(out, note), contains('${rgb(0x1E88E5)} rg'));
    expect(stamp.color, 0x43A047);
    expect(stamp.contents, 'DRAFT'); // the caption is untouched
    expect(content(out, stamp), contains('DRAFT'));
    expect(stamp.appearanceOpacity, closeTo(0.8, 1e-6)); // kept
  });

  test('a rotated square restyles in its local frame, keeping the turn',
      () {
    var doc = edited(
        PdfDocument.open(buildMultiPagePdf(1)),
        (e) => e.addSquare(0, const PdfRect(100, 650, 250, 750),
            strokeColor: 0xE53935, strokeWidth: 4));
    doc = edited(
        doc, (e) => e.rotateAnnotation(0, doc.page(0).annotations.single, 90));
    final rotated = doc.page(0).annotations.single;
    expect(rotated.rect.left, closeTo(125, 1e-6));

    final out = edited(doc,
        (e) => e.restyleAnnotation(0, rotated, color: 0x1E88E5));
    final after = out.page(0).annotations.single;
    expect(after.color, 0x1E88E5);
    // still a pure 90° turn about the same center
    expect(matrixEntry(out, after, 0), closeTo(0, 1e-6));
    expect(matrixEntry(out, after, 1), closeTo(1, 1e-6));
    expect(after.rect.left, closeTo(125, 0.5));
    expect(after.rect.bottom, closeTo(625, 0.5));
    expect(after.rect.right, closeTo(225, 0.5));
    expect(after.rect.top, closeTo(775, 0.5));
    // regenerated at the local 150×100 box with the constant pen width
    final stream = content(out, after);
    expect(stream, contains('${rgb(0x1E88E5)} RG'));
    expect(stream, contains('4 w'));
  });

  test('gates: foreign subtypes and no-op calls refuse; dashed shapes restyle',
      () {
    final doc = edited(
        PdfDocument.open(buildMultiPagePdf(1)),
        (e) => e.addSquare(0, const PdfRect(100, 600, 200, 660),
            strokeWidth: 2));
    final square = doc.page(0).annotations.single;

    // a no-op restyle (nothing to change) stages nothing
    final editor = PdfEditor(doc);
    expect(editor.restyleAnnotation(0, square), isFalse);
    expect(editor.hasChanges, isFalse);

    // dashed borders regenerate just like solid ones now
    (doc.cos.resolve(square.dict['BS']) as CosDictionary)['D'] =
        CosArray([const CosInteger(3)]);
    expect(pdfCanRestyleAnnotation(square), isTrue);
    expect(editor.restyleAnnotation(0, square, color: 0x1E88E5), isTrue);

    // foreign subtypes refuse
    final link = PdfAnnotation.fromDict(
        doc,
        CosDictionary({
          'Subtype': const CosName('Link'),
          'Rect': CosArray([
            const CosInteger(0),
            const CosInteger(0),
            const CosInteger(10),
            const CosInteger(10),
          ]),
        }));
    expect(pdfCanRestyleAnnotation(link), isFalse);
  });

  test('square: corner radius restyles in place, rebaking rounded corners',
      () {
    final doc = edited(
        PdfDocument.open(buildMultiPagePdf(1)),
        (e) => e.addSquare(0, const PdfRect(100, 600, 200, 660),
            strokeColor: 0xE53935, strokeWidth: 2));
    final before = doc.page(0).annotations.single;
    expect(before.cornerRadius, 0);
    expect(content(doc, before), contains(' re'));
    final formRef = doc.cos.referenceTo(before.normalAppearance!)!;

    // round the corners of the already-placed rectangle
    final out = edited(
        doc, (e) => e.restyleAnnotation(0, before, cornerRadius: 10));
    final after = out.page(0).annotations.single;
    expect(after.cornerRadius, 10);
    // §12.5.4 /Border = [hCornerRadius vCornerRadius width]; width mirrors /BS
    final border = out.cos.resolve(after.dict['Border']) as CosArray;
    expect(border.length, 3);
    expect((out.cos.resolve(border[0]) as CosReal).value, 10);
    expect((out.cos.resolve(border[1]) as CosReal).value, 10);
    expect((out.cos.resolve(border[2]) as CosReal).value, 2);
    // the appearance now curves its corners rather than a single `re`
    final stream = content(out, after);
    expect(stream, contains('c'));
    expect(stream, isNot(contains(' re')));
    // identity and geometry survive; the appearance was replaced, not re-added
    expect(after.rect, const PdfRect(100, 600, 200, 660));
    expect(out.cos.referenceTo(after.normalAppearance!)!.objectNumber,
        formRef.objectNumber);

    // dialing it back to 0 restores square corners and drops /Border
    final squared = edited(
        out, (e) => e.restyleAnnotation(0, after, cornerRadius: 0));
    final plain = squared.page(0).annotations.single;
    expect(plain.cornerRadius, 0);
    expect(plain.dict['Border'], isNull);
    expect(content(squared, plain), contains(' re'));
  });

  test('corner radius is a no-op on circles (nothing to round)', () {
    final doc = edited(
        PdfDocument.open(buildMultiPagePdf(1)),
        (e) => e.addCircle(0, const PdfRect(100, 600, 200, 660),
            strokeColor: 0xE53935, strokeWidth: 2));
    final circle = doc.page(0).annotations.single;
    final editor = PdfEditor(doc);
    // only /Square rounds; a lone cornerRadius on a circle changes nothing
    expect(editor.restyleAnnotation(0, circle, cornerRadius: 10), isFalse);
    expect(editor.hasChanges, isFalse);
    expect(circle.dict['Border'], isNull);
  });
}
