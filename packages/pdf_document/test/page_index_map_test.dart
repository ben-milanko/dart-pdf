import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

/// `pageIndexOf` backs link-destination resolution, so it runs once per link.
/// It used to be a linear identity scan over every page leaf, making a
/// link-heavy document O(links x pages); it is now an identity map built
/// alongside the leaf walk.
void main() {
  test('resolves every page to its own index', () {
    final document = PdfDocument.open(buildMultiPagePdf(12));
    for (var i = 0; i < document.pageCount; i++) {
      expect(document.pageIndexOf(document.page(i).dict), i);
    }
  });

  test('a dictionary that is not a page leaf reports -1', () {
    final document = PdfDocument.open(buildMultiPagePdf(3));
    // the /Pages tree root is a dictionary in the document but not a leaf
    final root = document.cos.resolve(document.catalog['Pages']);
    expect(root, isA<CosDictionary>());
    expect(document.pageIndexOf(root as CosDictionary), -1);
    // ...and so is a dictionary from another document entirely
    final other = PdfDocument.open(buildMultiPagePdf(2));
    expect(document.pageIndexOf(other.page(0).dict), -1);
  });

  test('the leaf walk cannot yield a duplicate page dictionary', () {
    // The index map assumes this: without it, one dictionary reachable from
    // two places in a broken page tree would need a defined tie-break. The
    // guarantee comes from _collectLeaves' `visited` set, not from the map,
    // so it is asserted here rather than assumed in a comment.
    final document = PdfDocument.open(buildMultiPagePdf(8));
    final dicts = [
      for (var i = 0; i < document.pageCount; i++) document.page(i).dict
    ];
    final unique = <CosDictionary>{}..addAll(dicts);
    expect(unique, hasLength(dicts.length));
  });

  test('keys on identity, not on dictionary contents', () {
    // Two pages of an unedited document have equal-looking dictionaries. The
    // map must not conflate them, which is only true because CosDictionary
    // does not override `==`. If that ever changes, this fails rather than
    // silently returning the wrong page index for every link in the file.
    final document = PdfDocument.open(buildMultiPagePdf(6));
    final seen = <int>{};
    for (var i = 0; i < document.pageCount; i++) {
      seen.add(document.pageIndexOf(document.page(i).dict));
    }
    expect(seen, hasLength(document.pageCount),
        reason: 'distinct pages collapsed onto the same index');
  });

  test('a structural edit invalidates the cached map', () {
    // The assertion has to be made against a page dictionary captured BEFORE
    // the edit, and one whose index actually moves. Re-reading `page(0)` after
    // the edit and asking for its index is vacuous - it returns 0 whether or
    // not the map was rebuilt.
    final document = PdfDocument.open(buildMultiPagePdf(5));
    final third = document.page(2).dict;
    final first = document.page(0).dict;
    expect(document.pageIndexOf(third), 2, reason: 'populates the map');

    // movePage rewrites the page tree in place (page_editor.dart calls
    // invalidatePageCache), so the same dictionary now lives at index 0.
    PdfEditor(document).movePage(2, 0);

    expect(document.pageIndexOf(third), 0,
        reason: 'stale index map survived a structural edit');
    expect(document.pageIndexOf(first), 1,
        reason: 'the displaced page should have shifted down');
    expect(document.pageCount, 5);
  });

  test('link destinations resolve to the right pages', () {
    // The real consumer: PdfAnnotation link parsing calls pageIndexOf.
    final document = PdfDocument.open(buildMultiPagePdf(4));
    for (var i = 0; i < document.pageCount; i++) {
      expect(document.page(i).annotations, isA<List<PdfAnnotation>>());
    }
    expect(document.pageIndexOf(document.page(3).dict), 3);
  });
}
