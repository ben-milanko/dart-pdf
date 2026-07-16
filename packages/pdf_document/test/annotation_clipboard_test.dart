// Annotation copy/paste: PdfAnnotationSnapshot (detached deep copies of
// an annotation and its appearance) and PdfEditor.pasteAnnotation.

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

List<double> numbers(PdfDocument doc, CosObject? raw) {
  final array = doc.cos.resolve(raw) as CosArray;
  return [
    for (final item in array.items)
      switch (doc.cos.resolve(item)) {
        CosInteger(:final value) => value.toDouble(),
        CosReal(:final value) => value,
        _ => double.nan,
      }
  ];
}

void main() {
  test('snapshot + paste round-trips a square onto another page', () {
    final doc = edited(
        PdfDocument.open(buildMultiPagePdf(2)),
        (e) => e.addSquare(0, const PdfRect(100, 600, 200, 660),
            strokeColor: 0xE53935,
            strokeWidth: 4,
            opacity: 0.5,
            contents: 'Box',
            author: 'Ben'));
    final original = doc.page(0).annotations.single;
    final snapshot = PdfAnnotationSnapshot.capture(doc, original)!;
    expect(snapshot.subtype, 'Square');
    expect(snapshot.rect, const PdfRect(100, 600, 200, 660));

    final out = edited(doc, (e) => e.pasteAnnotation(1, snapshot, dx: 12, dy: -12));
    expect(out.page(0).annotations, hasLength(1)); // original untouched
    final pasted = out.page(1).annotations.single;
    expect(pasted.subtype, 'Square');
    expect(pasted.rect.left, closeTo(112, 1e-6));
    expect(pasted.rect.top, closeTo(648, 1e-6));
    expect(pasted.author, 'Ben');
    expect(pasted.contents, 'Box');
    expect(pasted.color, 0xE53935);
    expect(pasted.borderWidth, 4);
    expect(pasted.appearanceOpacity, closeTo(0.5, 1e-6));
    // identity-bound entries don't travel - a pasted copy is a new
    // annotation and mints its own fresh /NM
    expect(pasted.name, isNotNull);
    expect(pasted.name, isNot(original.name));
    expect(pasted.dict['P'], isNull);
    // the appearance traveled byte for byte (§12.5.5 maps its BBox onto
    // the shifted /Rect, so the content needs no rewrite)
    expect(
      latin1.decode(out.cos.decodeStreamData(pasted.normalAppearance!)),
      latin1.decode(doc.cos.decodeStreamData(original.normalAppearance!)),
    );
  });

  test('paste shifts ink strokes and markup quads with the rect', () {
    final doc = edited(PdfDocument.open(buildMultiPagePdf(1)), (e) {
      e.addInk(0, [
        [(100, 600), (150, 640)],
      ], strokeWidth: 2);
      e.addHighlight(0, [const PdfRect(100, 500, 200, 515)]);
    });
    final ink = PdfAnnotationSnapshot.capture(doc, doc.page(0).annotations[0])!;
    final mark =
        PdfAnnotationSnapshot.capture(doc, doc.page(0).annotations[1])!;

    final out = edited(doc, (e) {
      e.pasteAnnotation(0, ink, dx: 10, dy: 20);
      e.pasteAnnotation(0, mark, dx: 10, dy: 20);
    });
    final annotations = out.page(0).annotations;
    expect(annotations, hasLength(4));
    final pastedInk = annotations[2];
    expect(pastedInk.inkList!.single.first.$1, closeTo(110, 1e-6));
    expect(pastedInk.inkList!.single.first.$2, closeTo(620, 1e-6));
    final quads = numbers(out, annotations[3].dict['QuadPoints']);
    expect(quads[0], closeTo(110, 1e-6)); // ul x
    expect(quads[1], closeTo(535, 1e-6)); // ul y
  });

  test('a snapshot is independent of the source document', () {
    final doc = edited(
        PdfDocument.open(buildMultiPagePdf(1)),
        (e) =>
            e.addSquare(0, const PdfRect(100, 600, 200, 660), strokeWidth: 2));
    final snapshot =
        PdfAnnotationSnapshot.capture(doc, doc.page(0).annotations.single)!;

    // the source moves on: the original annotation shifts 50pt right
    final moved = edited(doc,
        (e) => e.moveAnnotation(0, doc.page(0).annotations.single, 50, 0));
    expect(moved.page(0).annotations.single.rect.left, closeTo(150, 1e-6));

    // pasting into the edited document still lands at the captured place
    final out = edited(moved, (e) => e.pasteAnnotation(0, snapshot));
    expect(out.page(0).annotations[1].rect.left, closeTo(100, 1e-6));
  });

  test('pasting twice yields two independent annotations', () {
    final doc = edited(
        PdfDocument.open(buildMultiPagePdf(1)),
        (e) =>
            e.addSquare(0, const PdfRect(100, 600, 200, 660), strokeWidth: 2));
    final snapshot =
        PdfAnnotationSnapshot.capture(doc, doc.page(0).annotations.single)!;

    final out = edited(doc, (e) {
      e.pasteAnnotation(0, snapshot, dx: 12, dy: -12);
      e.pasteAnnotation(0, snapshot, dx: 24, dy: -24);
    });
    final annotations = out.page(0).annotations;
    expect(annotations, hasLength(3));
    expect(annotations[1].rect.left, closeTo(112, 1e-6));
    expect(annotations[2].rect.left, closeTo(124, 1e-6));
    // separate objects, not shared structure
    expect(identical(annotations[1].dict, annotations[2].dict), isFalse);
  });

  test('snapshots paste across documents', () {
    final source = edited(
        PdfDocument.open(buildMultiPagePdf(1)),
        (e) => e.addStamp(0, const PdfRect(100, 600, 240, 650), 'APPROVED',
            color: 0xC03030, author: 'Ben'));
    final snapshot =
        PdfAnnotationSnapshot.capture(source, source.page(0).annotations.single)!;

    final out = edited(
        PdfDocument.open(buildMultiPagePdf(2)), // a different document
        (e) => e.pasteAnnotation(1, snapshot));
    final pasted = out.page(1).annotations.single;
    expect(pasted.subtype, 'Stamp');
    expect(pasted.contents, 'APPROVED');
    expect(pasted.author, 'Ben');
    // the appearance came along whole, fonts included
    final form = pasted.normalAppearance!;
    final resources = out.cos.resolve(form.dictionary['Resources']);
    expect(resources, isA<CosDictionary>());
    expect((resources as CosDictionary)['Font'], isNotNull);
    expect(
      latin1.decode(out.cos.decodeStreamData(form)),
      contains('APPROVED'),
    );
  });

  test('popups, links, and widgets refuse to capture', () {
    final doc = PdfDocument.open(buildMultiPagePdf(1));
    for (final subtype in ['Popup', 'Link', 'Widget']) {
      final annotation = PdfAnnotation.fromDict(
          doc,
          CosDictionary({
            'Subtype': CosName(subtype),
            'Rect': CosArray([
              const CosInteger(0),
              const CosInteger(0),
              const CosInteger(10),
              const CosInteger(10),
            ]),
          }));
      expect(PdfAnnotationSnapshot.capture(doc, annotation), isNull,
          reason: subtype);
    }
  });

  test('the pasted file survives a save/reopen parse', () {
    final doc = edited(PdfDocument.open(buildMultiPagePdf(1)), (e) {
      e.addFreeText(0, const PdfRect(100, 560, 300, 620), 'Hello paste',
          fillColor: 0xFFF59D, borderColor: 0x1E88E5, borderWidth: 2);
    });
    final snapshot =
        PdfAnnotationSnapshot.capture(doc, doc.page(0).annotations.single)!;
    final out = edited(doc, (e) => e.pasteAnnotation(0, snapshot, dx: 6));
    final pasted = out.page(0).annotations[1];
    final style = pasted.freeTextStyle!;
    expect(pasted.contents, 'Hello paste');
    expect(style.fillColor, 0xFFF59D);
    expect(style.borderColor, 0x1E88E5);
    expect(style.borderWidth, 2);
  });
}
