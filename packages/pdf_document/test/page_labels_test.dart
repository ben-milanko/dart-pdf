import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

PdfDocument reopened(PdfEditor editor) => PdfDocument.open(editor.save());

void main() {
  group('page label formatting', () {
    test('decimal, roman and alpha styles render correctly', () {
      const decimal = PdfPageLabelRange(startPage: 0);
      expect([for (var i = 0; i < 3; i++) decimal.labelAt(i)], ['1', '2', '3']);

      const roman = PdfPageLabelRange(
          startPage: 0, style: PdfPageLabelStyle.romanLower);
      expect([for (var i = 0; i < 4; i++) roman.labelAt(i)],
          ['i', 'ii', 'iii', 'iv']);

      const upper = PdfPageLabelRange(
          startPage: 0, style: PdfPageLabelStyle.romanUpper, start: 9);
      expect([upper.labelAt(0), upper.labelAt(1)], ['IX', 'X']);
    });

    test('alphabetic labels wrap A..Z then AA..ZZ', () {
      const alpha = PdfPageLabelRange(
          startPage: 0, style: PdfPageLabelStyle.alphaUpper);
      expect(alpha.labelAt(0), 'A');
      expect(alpha.labelAt(25), 'Z');
      expect(alpha.labelAt(26), 'AA');
      expect(alpha.labelAt(27), 'BB');
    });

    test('prefix and start offset apply', () {
      const range = PdfPageLabelRange(
          startPage: 0,
          style: PdfPageLabelStyle.decimal,
          prefix: 'A-',
          start: 5);
      expect([range.labelAt(0), range.labelAt(1)], ['A-5', 'A-6']);
    });

    test('the none style emits only the prefix', () {
      const range = PdfPageLabelRange(
          startPage: 0, style: PdfPageLabelStyle.none, prefix: 'Cover');
      expect(range.labelAt(0), 'Cover');
      expect(range.labelAt(1), 'Cover');
    });
  });

  group('page label authoring', () {
    test('a single range round-trips and labels every page', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(4)))
        ..setPageLabel(0, style: PdfPageLabelStyle.romanLower);
      final labels = PdfPageLabels.of(reopened(editor));
      expect([for (var i = 0; i < 4; i++) labels.labelFor(i)],
          ['i', 'ii', 'iii', 'iv']);
    });

    test('multiple ranges compose: front matter then body', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(6)))
        ..setPageLabel(0, style: PdfPageLabelStyle.romanLower)
        ..setPageLabel(2, style: PdfPageLabelStyle.decimal, start: 1);
      final labels = PdfPageLabels.of(reopened(editor));
      expect([for (var i = 0; i < 6; i++) labels.labelFor(i)],
          ['i', 'ii', '1', '2', '3', '4']);
    });

    test('prefix and start value persist', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(3)))
        ..setPageLabel(0,
            style: PdfPageLabelStyle.decimal, prefix: 'A-', start: 10);
      final labels = PdfPageLabels.of(reopened(editor));
      expect([for (var i = 0; i < 3; i++) labels.labelFor(i)],
          ['A-10', 'A-11', 'A-12']);
    });

    test('the /Nums tree is key-sorted', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(6)))
        ..setPageLabel(4, style: PdfPageLabelStyle.alphaUpper)
        ..setPageLabel(0, style: PdfPageLabelStyle.romanLower)
        ..setPageLabel(2, style: PdfPageLabelStyle.decimal);
      final out = reopened(editor);
      final tree = out.cos.resolve(out.catalog['PageLabels']) as CosDictionary;
      final nums = out.cos.resolve(tree['Nums']) as CosArray;
      final keys = [
        for (var i = 0; i < nums.length; i += 2)
          (out.cos.resolve(nums[i]) as CosInteger).value
      ];
      expect(keys, [0, 2, 4]);
    });

    test('setPageLabel replaces a range at the same start page', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(3)))
        ..setPageLabel(0, style: PdfPageLabelStyle.decimal)
        ..setPageLabel(0, style: PdfPageLabelStyle.romanUpper);
      final labels = PdfPageLabels.of(reopened(editor));
      expect(labels.ranges, hasLength(1));
      expect(labels.labelFor(0), 'I');
    });

    test('removePageLabelRange and clearPageLabels', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(4)))
        ..setPageLabel(0, style: PdfPageLabelStyle.romanLower)
        ..setPageLabel(2, style: PdfPageLabelStyle.decimal);
      expect(editor.removePageLabelRange(2), isTrue);
      expect(editor.removePageLabelRange(2), isFalse);
      expect(PdfPageLabels.of(reopened(editor)).ranges, hasLength(1));

      editor.clearPageLabels();
      expect(PdfPageLabels.of(reopened(editor)).isEmpty, isTrue);
    });

    test('labelFor falls back to the physical number without labels', () {
      final doc = PdfDocument.open(buildMultiPagePdf(2));
      expect(PdfPageLabels.of(doc).labelFor(1), '2');
    });

    test('saves are incremental: original bytes survive verbatim', () {
      final original = buildMultiPagePdf(2);
      final editor = PdfEditor(PdfDocument.open(original))
        ..setPageLabel(0, style: PdfPageLabelStyle.romanLower);
      final saved = editor.save();
      expect(saved.sublist(0, original.length), original);
    });
  });
}
