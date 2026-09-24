import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

void main() {
  test('setInfo creates an Info dictionary when none exists', () {
    final doc = PdfDocument.open(buildClassicPdf());
    final editor = PdfEditor(doc)
      ..setInfo(title: 'Edited Title', author: 'Ben');

    final reopened = PdfDocument.open(editor.save());
    expect(reopened.info['Title'], 'Edited Title');
    expect(reopened.info['Author'], 'Ben');
    expect(reopened.pageCount, 1);
  });

  test('setInfo preserves entries it does not touch', () {
    final doc = PdfDocument.open(buildClassicPdf());
    final first = PdfEditor(doc)..setInfo(title: 'Keep Me', author: 'Ben');

    final second = PdfDocument.open(first.save());
    final editor = PdfEditor(second)..setInfo(author: 'Someone Else');

    final reopened = PdfDocument.open(editor.save());
    expect(reopened.info['Title'], 'Keep Me');
    expect(reopened.info['Author'], 'Someone Else');
  });

  test('rotatePage on a classic file', () {
    final doc = PdfDocument.open(buildClassicPdf());
    final editor = PdfEditor(doc)..rotatePage(0, 90);

    final reopened = PdfDocument.open(editor.save());
    expect(reopened.page(0).rotation, 90);
    // page content is untouched
    expect(String.fromCharCodes(reopened.page(0).contentBytes()),
        contains('Hello, world!'));
  });

  test('rotatePage on a page stored in an object stream', () {
    final doc = PdfDocument.open(buildXrefStreamPdf());
    final editor = PdfEditor(doc)..rotatePage(0, -90);

    final reopened = PdfDocument.open(editor.save());
    expect(reopened.page(0).rotation, 270);
    expect(reopened.pageCount, 1);
  });

  test('rotations accumulate across edit sessions', () {
    var bytes = buildClassicPdf();
    for (var i = 0; i < 3; i++) {
      final editor = PdfEditor(PdfDocument.open(bytes))..rotatePage(0, 90);
      bytes = editor.save();
    }
    expect(PdfDocument.open(bytes).page(0).rotation, 270);
  });

  test('non-right-angle rotation is rejected', () {
    final editor = PdfEditor(PdfDocument.open(buildClassicPdf()));
    expect(() => editor.rotatePage(0, 45), throwsArgumentError);
  });

  test('encrypted documents edit end-to-end (encrypt-on-write)', () {
    final doc = PdfDocument.open(buildEncryptedPdf(revision: 4));
    final editor = PdfEditor(doc)
      ..rotatePage(0, 90)
      ..setInfo(title: 'Re-encrypted');
    final reopened = PdfDocument.open(editor.save());
    expect(reopened.cos.isEncrypted, isTrue);
    expect(reopened.page(0).rotation, 90);
    expect(reopened.info['Title'], 'Re-encrypted');
  });
}
