// PdfDocument caches PdfPage instances (#418), which is what makes
// PdfPage.annotations' cache reachable at all. These pin the two hazards that
// caching introduces, both of which sank an earlier attempt.
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

void main() {
  test('page(i) hands back one instance', () {
    final doc = PdfDocument.open(buildMultiPagePdf(3));
    expect(identical(doc.page(1), doc.page(1)), isTrue);
    expect(identical(doc.page(0), doc.page(1)), isFalse);
  });

  test('pages bulk-loads once and seeds indexed lookup', () {
    final doc = PdfDocument.open(buildNestedPageTreePdf());
    final previouslyLoaded = doc.page(1);
    final pages = doc.pages;

    expect(pages, hasLength(3));
    expect(doc.pages, same(pages));
    expect(doc.page(1), same(pages[1]));
    expect(pages[1], same(previouslyLoaded));
    expect(pages[0].rotation, 90);
    expect(pages[0].mediaBox, const PdfRect(0, 0, 400, 400));
  });

  test('annotations parse once and are reused', () {
    final doc = PdfDocument.open(buildMultiPagePdf(1));
    final editor = PdfEditor(doc);
    editor.addHighlight(0, [const PdfRect(72, 72, 200, 88)]);
    final reopened = PdfDocument.open(editor.save());
    final page = reopened.page(0);
    final first = page.annotations;
    expect(first, hasLength(1));
    expect(identical(page.annotations, first), isTrue,
        reason: 'a second read must not re-parse /Annots');
  });

  test('a cached page sees an in-place /Rotate edit', () {
    // The hazard that sank the naive cache: PdfEditor mutates page dicts in
    // place, and _regenerateFormAppearancesOnPage re-reads the page during
    // the same call - before any invalidation hook could run.
    final doc = PdfDocument.open(buildMultiPagePdf(1));
    final page = doc.page(0);
    expect(page.rotation, 0);
    page.dict['Rotate'] = const CosInteger(90);
    expect(doc.page(0).rotation, 90, reason: 'cached instance went stale');
    expect(page.rotation, 90, reason: 'the held instance went stale too');
  });

  test('a cached page sees an in-place MediaBox edit', () {
    final doc = PdfDocument.open(buildMultiPagePdf(1));
    final page = doc.page(0);
    final before = page.mediaBox;
    page.dict['MediaBox'] = CosArray(const [
      CosInteger(0),
      CosInteger(0),
      CosInteger(200),
      CosInteger(400),
    ]);
    expect(page.mediaBox.width, 200);
    expect(page.mediaBox.height, 400);
    expect(before.width, isNot(200));
  });

  test('the annotation cache notices entries added in place', () {
    final doc = PdfDocument.open(buildMultiPagePdf(1));
    final editor = PdfEditor(doc);
    editor.addHighlight(0, [const PdfRect(72, 72, 200, 88)]);
    final reopened = PdfDocument.open(editor.save());
    final page = reopened.page(0);
    expect(page.annotations, hasLength(1));

    // Append straight into the live array, the way the editors do.
    final annots = reopened.cos.resolve(page.dict['Annots']) as CosArray;
    annots.items.add(CosDictionary({
      'Type': const CosName('Annot'),
      'Subtype': const CosName('Square'),
      'Rect': CosArray(const [
        CosInteger(10),
        CosInteger(10),
        CosInteger(50),
        CosInteger(50),
      ]),
    }));
    expect(page.annotations, hasLength(2),
        reason: 'the cache must not hide an in-place append');
  });

  test('a page inherits from its ancestors when it carries no entry of its '
      'own', () {
    final doc = PdfDocument.open(buildMultiPagePdf(2));
    final page = doc.page(0);
    // Fixture pages inherit MediaBox from the tree root; removing the page's
    // own entry (if any) must fall back to the inherited value, not to Letter.
    page.dict.entries.remove('MediaBox');
    expect(page.mediaBox.width, greaterThan(0));
    expect(page.mediaBox.height, greaterThan(0));
  });

  test('incremental re-wrap preserves inherited page-tree values', () {
    final doc = PdfDocument.open(buildNestedPageTreePdf());
    final page = doc.page(0);
    final inheritedBox = page.mediaBox;
    final inheritedRotation = page.rotation;
    final inheritedResources = page.resources;
    final ref = doc.cos.referenceTo(page.dict)!;
    final editor = PdfEditor(doc)..addSquare(0, const PdfRect(20, 20, 80, 80));
    final newer = doc.withIncrementalUpdate(editor.save());
    final currentDict = newer.cos.resolve(ref) as CosDictionary;

    final revised = page.forIncrementalRevision(newer, currentDict);

    expect(revised.mediaBox, inheritedBox);
    expect(revised.rotation, inheritedRotation);
    expect(revised.resources, same(inheritedResources));
    expect(revised.annotations, hasLength(1));
  });

  test('incremental re-wrap rejects an unrelated COS graph', () {
    final first = PdfDocument.open(buildMultiPagePdf(1));
    final second = PdfDocument.open(buildMultiPagePdf(1));

    expect(
      () => first.page(0).forIncrementalRevision(
            second,
            second.page(0).dict,
          ),
      throwsArgumentError,
    );
  });
}
