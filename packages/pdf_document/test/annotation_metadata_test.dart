// In-place annotation metadata edits: PdfEditor.setAnnotationContents
// and setAnnotationAuthor change the dictionary without touching the
// appearance.

import 'dart:convert';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

PdfDocument edited(PdfDocument doc, void Function(PdfEditor) edit) {
  final editor = PdfEditor(doc);
  edit(editor);
  return PdfDocument.open(editor.save());
}

void main() {
  test('contents and author round-trip without touching the appearance', () {
    final doc = edited(
        PdfDocument.open(buildMultiPagePdf(1)),
        (e) => e.addSquare(0, const PdfRect(100, 600, 200, 660),
            strokeWidth: 2, contents: 'old', author: 'Someone'));
    final before = doc.page(0).annotations.single;
    final appearanceBefore =
        latin1.decode(doc.cos.decodeStreamData(before.normalAppearance!));

    final out = edited(doc, (e) {
      e.setAnnotationContents(0, before, 'a comment - naïve ✓');
      e.setAnnotationAuthor(0, before, 'Ben');
    });
    final after = out.page(0).annotations.single;
    expect(after.contents, 'a comment - naïve ✓'); // UTF-16BE round trip
    expect(after.author, 'Ben');
    expect(after.rect, const PdfRect(100, 600, 200, 660));
    expect(
        latin1.decode(out.cos.decodeStreamData(after.normalAppearance!)),
        appearanceBefore);
  });

  test('empty contents and a null author remove the entries', () {
    final doc = edited(
        PdfDocument.open(buildMultiPagePdf(1)),
        (e) => e.addSquare(0, const PdfRect(100, 600, 200, 660),
            strokeWidth: 2, contents: 'old', author: 'Someone'));
    final annotation = doc.page(0).annotations.single;

    final out = edited(doc, (e) {
      e.setAnnotationContents(0, annotation, '');
      e.setAnnotationAuthor(0, annotation, null);
    });
    final after = out.page(0).annotations.single;
    expect(after.contents, isNull);
    expect(after.dict['Contents'], isNull);
    expect(after.author, isNull);
    expect(after.dict['T'], isNull);
  });

  test('setAnnotationFlags round-trips and the lock getters read §12.5.3',
      () {
    final doc = edited(
        PdfDocument.open(buildMultiPagePdf(1)),
        (e) =>
            e.addSquare(0, const PdfRect(100, 600, 200, 660), strokeWidth: 2));
    final annotation = doc.page(0).annotations.single;
    expect(annotation.isReadOnly, isFalse);
    expect(annotation.isLocked, isFalse);
    expect(annotation.isLockedContents, isFalse);

    // print(4) + readOnly(64) + locked(128) + lockedContents(512)
    final out =
        edited(doc, (e) => e.setAnnotationFlags(0, annotation, 4 | 64 | 128 | 512));
    final flagged = out.page(0).annotations.single;
    expect(flagged.flags, 4 | 64 | 128 | 512);
    expect(flagged.isReadOnly, isTrue);
    expect(flagged.isLocked, isTrue);
    expect(flagged.isLockedContents, isTrue);
    expect(flagged.isHidden, isFalse);
  });

  test('authoring a widget refuses - /T is the field name there', () {
    final doc = PdfDocument.open(buildAcroFormPdf());
    final widget = doc
        .page(0)
        .annotations
        .firstWhere((a) => a.subtype == 'Widget');
    final editor = PdfEditor(doc);
    expect(() => editor.setAnnotationAuthor(0, widget, 'Ben'),
        throwsArgumentError);
  });
}
