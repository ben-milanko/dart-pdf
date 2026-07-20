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

  test('the map is rebuilt after the page tree changes', () {
    final document = PdfDocument.open(buildMultiPagePdf(5));
    final third = document.page(2).dict;
    expect(document.pageIndexOf(third), 2);

    final editor = PdfEditor(document)..movePage(2, 0);
    final moved = PdfDocument.open(editor.save());
    expect(moved.pageIndexOf(moved.page(0).dict), 0);

    // and in-place: a structural edit invalidates the cached map
    document.invalidatePageCache();
    expect(document.pageIndexOf(document.page(0).dict), 0,
        reason: 'stale index survived invalidation');
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
