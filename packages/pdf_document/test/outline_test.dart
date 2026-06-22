import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

PdfDocument reopened(PdfEditor editor) => PdfDocument.open(editor.save());

/// Walks the raw /Outlines tree asserting the First/Last/Next/Prev/Parent
/// linkage is internally consistent, and returns the visible-descendant
/// count the way a conforming reader computes /Count.
int checkLinkage(PdfDocument doc, CosDictionary node) {
  final cos = doc.cos;
  final nodeRef = cos.referenceTo(node);
  final first = node['First'];
  final last = node['Last'];
  if (first == null) {
    expect(last, isNull,
        reason: 'a childless node carries neither First nor Last');
    return 0;
  }
  expect(first, isA<CosReference>());
  expect(last, isA<CosReference>());

  var total = 0;
  CosObject? cur = first;
  CosObject? prevSeen;
  CosReference? lastSeen;
  final guard = <int>{};
  while (cur is CosReference) {
    expect(guard.add(cur.objectNumber), isTrue, reason: 'no cycles');
    final child = cos.resolve(cur) as CosDictionary;
    expect(child['Parent'], nodeRef, reason: 'Parent points back at us');
    expect(child['Prev'], prevSeen, reason: 'Prev matches the prior sibling');
    final sub = checkLinkage(doc, child);
    final c = cos.resolve(child['Count']);
    final open = c is! CosInteger || c.value >= 0;
    total += 1 + (open ? sub : 0);
    prevSeen = cur;
    lastSeen = cur;
    cur = child['Next'];
  }
  expect(lastSeen, last, reason: 'Last points at the final child');
  return total;
}

void main() {
  group('outline authoring', () {
    test('a flat list of bookmarks round-trips with valid linkage', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(3)));
      editor.addOutlineItem('First', pageIndex: 0);
      editor.addOutlineItem('Second', pageIndex: 1);
      editor.addOutlineItem('Third', pageIndex: 2);

      final out = reopened(editor);
      final outline = PdfOutline.of(out);
      expect(outline.items.map((i) => i.title), ['First', 'Second', 'Third']);
      expect(outline.items.map((i) => i.destination?.pageIndex), [0, 1, 2]);

      final root = out.cos.resolve(out.catalog['Outlines']) as CosDictionary;
      expect(checkLinkage(out, root), 3);
      expect((out.cos.resolve(root['Count']) as CosInteger).value, 3);
    });

    test('nested children maintain /Count of visible descendants', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(4)));
      final ch1 = editor.addOutlineItem('Chapter 1', pageIndex: 0);
      editor.addOutlineItem('1.1', pageIndex: 1, parent: ch1);
      editor.addOutlineItem('1.2', pageIndex: 2, parent: ch1);
      editor.addOutlineItem('Chapter 2', pageIndex: 3);

      final out = reopened(editor);
      final outline = PdfOutline.of(out);
      expect(outline.items.map((i) => i.title), ['Chapter 1', 'Chapter 2']);
      expect(outline.items[0].children.map((i) => i.title), ['1.1', '1.2']);

      final root = out.cos.resolve(out.catalog['Outlines']) as CosDictionary;
      // 2 top-level + 2 visible children = 4
      expect((out.cos.resolve(root['Count']) as CosInteger).value, 4);
      expect(checkLinkage(out, root), 4);

      final chapter1 = out.cos.resolve(root['First']) as CosDictionary;
      expect((out.cos.resolve(chapter1['Count']) as CosInteger).value, 2);
    });

    test('a closed parent has a negative /Count and hides its children', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(3)));
      final parent =
          editor.addOutlineItem('Closed', pageIndex: 0, open: false);
      editor.addOutlineItem('hidden a', pageIndex: 1, parent: parent);
      editor.addOutlineItem('hidden b', pageIndex: 2, parent: parent);

      final out = reopened(editor);
      final root = out.cos.resolve(out.catalog['Outlines']) as CosDictionary;
      final parentDict = out.cos.resolve(root['First']) as CosDictionary;
      expect((out.cos.resolve(parentDict['Count']) as CosInteger).value, -2);
      // closed: only the parent itself is visible at the root level
      expect((out.cos.resolve(root['Count']) as CosInteger).value, 1);
      expect(PdfOutline.of(out).items.single.open, isFalse);
    });

    test('index controls sibling order; null appends, 0 prepends', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(3)));
      editor.addOutlineItem('B', pageIndex: 1);
      editor.addOutlineItem('A', pageIndex: 0, index: 0);
      editor.addOutlineItem('C', pageIndex: 2);
      editor.addOutlineItem('B.5', pageIndex: 1, index: 2);

      expect(PdfOutline.of(reopened(editor)).items.map((i) => i.title),
          ['A', 'B', 'B.5', 'C']);
    });

    test('move re-parents an item and recomputes counts', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(3)));
      final ch1 = editor.addOutlineItem('Chapter 1', pageIndex: 0);
      final ch2 = editor.addOutlineItem('Chapter 2', pageIndex: 1);
      final loose = editor.addOutlineItem('Section', pageIndex: 2);

      editor.moveOutlineItem(loose, parent: ch1);

      final out = reopened(editor);
      final outline = PdfOutline.of(out);
      expect(outline.items.map((i) => i.title), ['Chapter 1', 'Chapter 2']);
      expect(outline.items[0].children.single.title, 'Section');
      expect(outline.items[1].children, isEmpty);

      final root = out.cos.resolve(out.catalog['Outlines']) as CosDictionary;
      expect(checkLinkage(out, root), 3);
      // confirm the API objects still resolve
      expect(out.cos.resolve(ch2), isA<CosDictionary>());
    });

    test('moving an item under its own descendant is rejected', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(2)));
      final parent = editor.addOutlineItem('Parent', pageIndex: 0);
      final child = editor.addOutlineItem('Child', pageIndex: 1, parent: parent);
      expect(() => editor.moveOutlineItem(parent, parent: child),
          throwsArgumentError);
      expect(() => editor.moveOutlineItem(parent, parent: parent),
          throwsArgumentError);
    });

    test('remove drops an item and keeps linkage valid', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(3)));
      editor.addOutlineItem('A', pageIndex: 0);
      final b = editor.addOutlineItem('B', pageIndex: 1);
      editor.addOutlineItem('C', pageIndex: 2);

      editor.removeOutlineItem(b);

      final out = reopened(editor);
      final outline = PdfOutline.of(out);
      expect(outline.items.map((i) => i.title), ['A', 'C']);
      final root = out.cos.resolve(out.catalog['Outlines']) as CosDictionary;
      expect(checkLinkage(out, root), 2);
      expect((out.cos.resolve(root['Count']) as CosInteger).value, 2);
    });

    test('title, destination and style mutators round-trip', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(3)));
      final item = editor.addOutlineItem('draft', pageIndex: 0);
      editor.setOutlineTitle(item, 'Final');
      editor.setOutlineDestination(
          item, const PdfExplicitDestination.fit(2));
      editor.setOutlineStyle(item, color: 0xFF0000, bold: true, italic: true);

      final outline = PdfOutline.of(reopened(editor));
      final read = outline.items.single;
      expect(read.title, 'Final');
      expect(read.destination?.pageIndex, 2);
      expect(read.bold, isTrue);
      expect(read.italic, isTrue);
      expect(read.color, [1.0, 0.0, 0.0]);
    });

    test('XYZ destinations carry their parameters', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(2)));
      editor.addOutlineItem('Zoomed',
          destination:
              PdfExplicitDestination.xyz(1, left: 10, top: 700, zoom: 2));
      final dest = PdfOutline.of(reopened(editor)).items.single.destination!;
      expect(dest.fit, 'XYZ');
      expect(dest.left, 10);
      expect(dest.top, 700);
      expect(dest.zoom, 2);
    });

    test('the edit is visible before saving', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(2)));
      editor.addOutlineItem('Live', pageIndex: 0);
      expect(PdfOutline.of(editor.document).items.single.title, 'Live');
    });

    test('saves are incremental: original bytes survive verbatim', () {
      final original = buildMultiPagePdf(2);
      final editor = PdfEditor(PdfDocument.open(original))
        ..addOutlineItem('Bookmark', pageIndex: 0);
      final saved = editor.save();
      expect(saved.sublist(0, original.length), original);
    });
  });
}
