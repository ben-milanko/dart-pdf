// PdfDocument caches PdfPage instances (#418), which is what makes
// PdfPage.annotations' cache reachable at all. These pin the two hazards that
// caching introduces, both of which sank an earlier attempt.
import 'dart:typed_data';

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

  test(
      'a page inherits from its ancestors when it carries no entry of its '
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

  group('page(i) caching the leaves that follow it', () {
    Uint8List pdfOf(List<String> objects) {
      final buffer = StringBuffer('%PDF-1.4\n');
      final offsets = <int>[];
      for (var i = 0; i < objects.length; i++) {
        offsets.add(buffer.length);
        buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
      }
      final xrefOffset = buffer.length;
      buffer
        ..write('xref\n0 ${objects.length + 1}\n')
        ..write('0000000000 65535 f \n');
      for (final offset in offsets) {
        buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
      }
      buffer
        ..write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n')
        ..write('startxref\n$xrefOffset\n%%EOF\n');
      return ascii(buffer.toString());
    }

    const catalog = '<< /Type /Catalog /Pages 2 0 R >>';
    String leaf(int parent) => '<< /Type /Page /Parent $parent 0 R >>';

    /// Object number of page [index], or null when the lookup throws.
    int? objectOf(PdfDocument doc, int index) {
      try {
        return doc.cos.referenceTo(doc.page(index).dict)?.objectNumber;
      } on RangeError {
        return null;
      }
    }

    /// A single page(i) on a fresh document is unaffected by caching, so it
    /// is the oracle: whatever an earlier lookup seeded must agree with it -
    /// for a forward loop, and for a lookup after any one earlier lookup.
    void expectSeedsMatchFreshLookups(Uint8List bytes) {
      final count = PdfDocument.open(bytes).pageCount;
      final fresh = [
        for (var i = 0; i < count + 1; i++)
          objectOf(PdfDocument.open(bytes), i),
      ];
      final loop = PdfDocument.open(bytes);
      expect([for (var i = 0; i < count + 1; i++) objectOf(loop, i)], fresh);
      for (var a = 0; a < count; a++) {
        for (var b = a + 1; b < count + 1; b++) {
          final doc = PdfDocument.open(bytes);
          objectOf(doc, a);
          expect(objectOf(doc, b), fresh[b], reason: 'page($b) after page($a)');
        }
      }
    }

    test('seeded lookups agree with fresh ones on a well-formed tree', () {
      expectSeedsMatchFreshLookups(buildMultiPagePdf(7));
      expectSeedsMatchFreshLookups(buildNestedPageTreePdf());
    });

    test('an understated /Count skipped before leaf siblings', () {
      // page(0) is object 4; page(1) skips the inner node and lands on 6.
      expectSeedsMatchFreshLookups(pdfOf([
        catalog,
        '<< /Type /Pages /Kids [3 0 R 6 0 R 7 0 R 8 0 R] /Count 5 >>',
        '<< /Type /Pages /Parent 2 0 R /Kids [4 0 R 5 0 R] /Count 1 >>',
        leaf(3),
        leaf(3),
        leaf(2),
        leaf(2),
        leaf(2),
      ]));
    });

    test('an overstated /Count entered before leaf siblings', () {
      // page(2) enters the inner node on its /Count 3, finds two leaves and
      // lands on 6 - but page(3) skips the node and lands on 6 again, so
      // page(2) must not seed 7 as page(3).
      expectSeedsMatchFreshLookups(pdfOf([
        catalog,
        '<< /Type /Pages /Kids [3 0 R 6 0 R 7 0 R 8 0 R] /Count 5 >>',
        '<< /Type /Pages /Parent 2 0 R /Kids [4 0 R 5 0 R] /Count 3 >>',
        leaf(3),
        leaf(3),
        leaf(2),
        leaf(2),
        leaf(2),
      ]));
    });

    test('leaf siblings inside a subtree whose /Count is too small', () {
      // page(2) is object 6, a direct kid of the inner node, but page(3)
      // skips that node (/Count 3) and lands on 8, not on sibling 7.
      expectSeedsMatchFreshLookups(pdfOf([
        catalog,
        '<< /Type /Pages /Kids [3 0 R 8 0 R] /Count 5 >>',
        '<< /Type /Pages /Parent 2 0 R /Kids [4 0 R 5 0 R 6 0 R 7 0 R] '
            '/Count 3 >>',
        leaf(3),
        leaf(3),
        leaf(3),
        leaf(3),
        leaf(2),
      ]));
    });

    test('repeated and non-dictionary kids take no index', () {
      expectSeedsMatchFreshLookups(pdfOf([
        catalog,
        '<< /Type /Pages /Kids [3 0 R 4 0 R 3 0 R null 5 0 R 99 0 R 6 0 R] '
            '/Count 4 >>',
        leaf(2),
        leaf(2),
        leaf(2),
        leaf(2),
      ]));
    });

    List<CosDictionary> reverseKidsInPlace(PdfDocument doc) {
      final root = doc.cos.resolve(doc.catalog['Pages']) as CosDictionary;
      final kids = root['Kids'] as CosArray;
      final original = [
        for (final kid in kids.items) doc.cos.resolve(kid) as CosDictionary,
      ];
      // A structural change the page cache is not told about: any lookup
      // that walks the tree from here disagrees with one served from cache.
      final reversed = kids.items.reversed.toList();
      kids.items
        ..clear()
        ..addAll(reversed);
      return original;
    }

    test('a lookup caches as many following leaves as it walked past', () {
      final doc = PdfDocument.open(buildMultiPagePdf(8));
      doc.page(2);
      final original = reverseKidsInPlace(doc);
      expect(doc.page(3).dict, same(original[3]));
      expect(doc.page(4).dict, same(original[4]));
      expect(doc.page(5).dict, same(original[2]), reason: 'walked afresh');
    });

    test('page(0) caches nothing beyond itself', () {
      final doc = PdfDocument.open(buildMultiPagePdf(4));
      doc.page(0);
      final original = reverseKidsInPlace(doc);
      expect(doc.page(1).dict, same(original[2]), reason: 'walked afresh');
    });
  });
}
