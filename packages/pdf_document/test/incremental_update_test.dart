import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

void main() {
  // An incremental editor save appends a new xref section pointing /Prev at the
  // old one, so the new bytes are a strict prefix-append of the old document.
  Uint8List editThenSave(Uint8List bytes, void Function(PdfEditor) edit) {
    final editor = PdfEditor(PdfDocument.open(bytes));
    edit(editor);
    final saved = editor.save();
    // Sanity: the save is genuinely a prefix-append (the shape the worker's
    // incremental update relies on).
    expect(saved.length, greaterThan(bytes.length));
    for (var i = 0; i < bytes.length; i++) {
      expect(saved[i], bytes[i], reason: 'byte $i diverged from the prefix');
    }
    return saved;
  }

  test('applyIncrementalUpdate matches a full reopen of the new bytes', () {
    final original = buildMultiPagePdf(4);
    final updated = editThenSave(
      original,
      (e) => e.setInfo(title: 'Revised', author: 'Ben'),
    );

    final incremental = PdfDocument.open(original);
    final changed = incremental.applyIncrementalUpdate(updated);
    final full = PdfDocument.open(updated);

    expect(changed, isNotEmpty);
    expect(incremental.pageCount, full.pageCount);
    expect(incremental.info['Title'], 'Revised');
    expect(incremental.info['Author'], 'Ben');
    // The buffer now points at the appended revision.
    expect(incremental.cos.bytes.length, updated.length);
  });

  test('unedited pages keep byte-identical content across the update', () {
    final original = buildMultiPagePdf(5);
    // Draw a rectangle on page 2 only.
    final updated = editThenSave(
      original,
      (e) => e.addSquare(2, const PdfRect(20, 20, 80, 80)),
    );

    final full = PdfDocument.open(updated);
    final incremental = PdfDocument.open(original);
    incremental.applyIncrementalUpdate(updated);

    for (var page = 0; page < full.pageCount; page++) {
      expect(
        incremental.page(page).contentBytes(),
        full.page(page).contentBytes(),
        reason: 'page $page content differs from a full reopen',
      );
    }
  });

  test('a redefined object resolves to the new value after the update', () {
    final original = buildMultiPagePdf(2);
    final updated = editThenSave(
      original,
      (e) => e.setInfo(title: 'After'),
    );

    final incremental = PdfDocument.open(original);
    expect(incremental.info['Title'], isNot('After'));
    incremental.applyIncrementalUpdate(updated);
    expect(incremental.info['Title'], 'After');
  });

  test('rejects a non-append buffer', () {
    final original = buildMultiPagePdf(2);
    final shorter = Uint8List.sublistView(original, 0, original.length - 1);
    final doc = PdfDocument.open(original);
    expect(
      () => doc.applyIncrementalUpdate(shorter),
      throwsA(isA<CosParseException>()),
    );
  });
}
