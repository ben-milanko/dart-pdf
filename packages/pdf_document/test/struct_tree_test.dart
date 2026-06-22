import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

void main() {
  group('PdfStructTree read path', () {
    late PdfDocument doc;

    setUp(() => doc = PdfDocument.open(buildTaggedPdf()));

    test('detects a marked, tagged document', () {
      expect(pdfIsMarkedTagged(doc), isTrue);
      expect(PdfStructTree.of(doc), isNotNull);
    });

    test('untagged documents have no structure tree', () {
      final plain = PdfDocument.open(buildClassicPdf());
      expect(PdfStructTree.of(plain), isNull);
      expect(pdfIsMarkedTagged(plain), isFalse);
    });

    test('walks the structure tree top-down', () {
      final tree = PdfStructTree.of(doc)!;
      final roots = tree.children;
      expect(roots, hasLength(1));
      final document = roots.single;
      expect(document.structureType, 'Document');
      expect(document.standardType, 'Document');

      final kids = document.children;
      expect(kids.map((e) => e.structureType),
          ['Title', 'P', 'Figure', 'Link']);
    });

    test('maps custom roles through the role map', () {
      final tree = PdfStructTree.of(doc)!;
      expect(tree.roleMap, containsPair('Title', 'H1'));
      final heading =
          tree.elementsInReadingOrder().firstWhere((e) => e.structureType == 'Title');
      expect(heading.standardType, 'H1');
    });

    test('reading order is a depth-first pre-order walk', () {
      final tree = PdfStructTree.of(doc)!;
      expect(tree.elementsInReadingOrder().map((e) => e.structureType),
          ['Document', 'Title', 'P', 'Figure', 'Link']);
    });

    test('exposes alt text, actual text, language, and title', () {
      final tree = PdfStructTree.of(doc)!;
      final byType = {
        for (final e in tree.elementsInReadingOrder()) e.structureType: e
      };
      expect(byType['Figure']!.alt, 'A sample figure');
      expect(byType['Figure']!.actualText, 'Figure 1');
      expect(byType['Title']!.language, 'en-US');
      expect(byType['Title']!.title, 'heading');
      // P inherits no /Lang itself; the document /Lang is the catalog's.
      expect(byType['P']!.language, isNull);
    });

    test('maps structure elements to marked content via /MCID', () {
      final tree = PdfStructTree.of(doc)!;
      final byType = {
        for (final e in tree.elementsInReadingOrder()) e.structureType: e
      };
      final heading = byType['Title']!.markedContent;
      expect(heading, hasLength(1));
      expect(heading.single.mcid, 0);
      expect(heading.single.pageIndex, 0);

      expect(byType['P']!.markedContent.single.mcid, 1);
      expect(byType['Figure']!.markedContent.single.mcid, 2);
    });

    test('OBJR ties a structure element to an annotation object', () {
      final tree = PdfStructTree.of(doc)!;
      final link = tree
          .elementsInReadingOrder()
          .firstWhere((e) => e.structureType == 'Link');
      final refs = link.objectReferences;
      expect(refs, hasLength(1));
      final obj = refs.single.object;
      expect(obj, isA<CosDictionary>());
      expect((obj as CosDictionary).typeName, 'Annot');
    });

    test('reading-order content flattens MCIDs in document order', () {
      final tree = PdfStructTree.of(doc)!;
      final mcids = tree.children.single
          .markedContentInReadingOrder()
          .map((m) => m.mcid)
          .toList();
      expect(mcids, [0, 1, 2]);
    });

    test('parent tree resolves MCID and object back to elements', () {
      final pt = PdfStructParentTree.of(doc)!;
      final pageKey = pageStructParentsKey(doc.page(0));
      expect(pageKey, 0);

      expect(pt.elementForMcid(pageKey!, 0)!.structureType, 'Title');
      expect(pt.elementForMcid(pageKey, 1)!.structureType, 'P');
      expect(pt.elementForMcid(pageKey, 2)!.structureType, 'Figure');

      // The link annotation's /StructParent is 1.
      expect(pt.elementForObject(1)!.structureType, 'Link');
    });
  });
}
