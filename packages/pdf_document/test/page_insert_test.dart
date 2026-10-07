import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:test/test.dart';

/// [count] pages drawing `<prefix><n>` (one-based), optionally with a single
/// top-level bookmark titled [outline] on the first page.
Uint8List labeledPdf(String prefix, int count, {String? outline}) {
  final b = CosDocumentBuilder();
  final pages = CosDictionary({'Type': const CosName('Pages')});
  final pagesRef = b.add(pages);
  final refs = [
    for (var i = 0; i < count; i++)
      b.add(CosDictionary({
        'Type': const CosName('Page'),
        'Parent': pagesRef,
        'MediaBox': CosArray([
          const CosInteger(0),
          const CosInteger(0),
          const CosInteger(612),
          const CosInteger(792)
        ]),
        'Resources': CosDictionary(),
        'Contents': b.add(CosStream(CosDictionary(),
            Uint8List.fromList('BT ($prefix${i + 1}) Tj ET'.codeUnits))),
      })),
  ];
  pages['Kids'] = CosArray(refs);
  pages['Count'] = CosInteger(count);
  final catalog = CosDictionary({
    'Type': const CosName('Catalog'),
    'Pages': pagesRef,
  });
  if (outline != null) {
    final root = CosDictionary({'Type': const CosName('Outlines')});
    final rootRef = b.add(root);
    final item = b.add(CosDictionary({
      'Title': CosString.fromText(outline),
      'Parent': rootRef,
      'Dest': CosArray([refs.first, const CosName('Fit')]),
    }));
    root['First'] = item;
    root['Last'] = item;
    root['Count'] = const CosInteger(1);
    catalog['Outlines'] = rootRef;
  }
  return b.build(root: b.add(catalog));
}

List<String> labelsOf(PdfDocument doc) => [
      for (var i = 0; i < doc.pageCount; i++)
        RegExp(r'\(([A-Z]\d+)\)')
                .firstMatch(String.fromCharCodes(doc.page(i).contentBytes()))
                ?.group(1) ??
            '?',
    ];

PdfDocument open(Uint8List bytes) => PdfDocument.open(bytes);

void main() {
  group('PdfPageInterleave.order', () {
    test('a block insert splices the new pages in at the point', () {
      expect(
        PdfPageInterleave.order(existingCount: 3, insertedCount: 2, at: 1),
        [0, 3, 4, 1, 2],
      );
    });

    test('one-for-one weave starting at the insertion point', () {
      expect(
        PdfPageInterleave.order(
          existingCount: 3,
          insertedCount: 3,
          at: 1,
          interleave: const PdfPageInterleave(),
        ),
        [0, 3, 1, 4, 2, 5],
      );
    });

    test('custom run lengths, with leftovers following in order', () {
      expect(
        PdfPageInterleave.order(
          existingCount: 5,
          insertedCount: 3,
          at: 0,
          interleave: const PdfPageInterleave(existing: 2, inserted: 2),
        ),
        [5, 6, 0, 1, 7, 2, 3, 4],
      );
      // more inserted pages than existing: the rest trail at the end
      expect(
        PdfPageInterleave.order(
          existingCount: 2,
          insertedCount: 4,
          at: 0,
          interleave: const PdfPageInterleave(),
        ),
        [2, 0, 3, 1, 4, 5],
      );
    });

    test('the order is always a permutation', () {
      for (var e = 0; e < 6; e++) {
        for (var n = 0; n < 6; n++) {
          for (var at = 0; at <= e; at++) {
            for (final weave in [
              null,
              const PdfPageInterleave(),
              const PdfPageInterleave(existing: 3, inserted: 2),
            ]) {
              final order = PdfPageInterleave.order(
                  existingCount: e,
                  insertedCount: n,
                  at: at,
                  interleave: weave);
              expect(
                  order.toList()..sort(), [for (var i = 0; i < e + n; i++) i]);
            }
          }
        }
      }
    });
  });

  group('PdfPageInsertSource.select', () {
    test('blank means every page', () {
      expect(PdfPageInsertSource.select(4), [0, 1, 2, 3]);
      expect(PdfPageInsertSource.select(4, ranges: '  '), [0, 1, 2, 3]);
    });

    test('ranges, odd/even and reverse compose', () {
      expect(PdfPageInsertSource.select(10, ranges: '2-5, 9'), [1, 2, 3, 4, 8]);
      expect(
          PdfPageInsertSource.select(6, subset: PdfPageSubset.odd), [0, 2, 4]);
      expect(
          PdfPageInsertSource.select(6,
              subset: PdfPageSubset.even, reverse: true),
          [5, 3, 1]);
      expect(
          PdfPageInsertSource.select(10,
              ranges: '1-4', subset: PdfPageSubset.even),
          [1, 3]);
    });

    test('repeats keep their first position; bad input throws', () {
      expect(PdfPageInsertSource.select(5, ranges: '3, 1-3'), [2, 0, 1]);
      expect(() => PdfPageInsertSource.select(3, ranges: '2-9'),
          throwsFormatException);
      expect(() => PdfPageInsertSource.select(3, ranges: 'x'),
          throwsFormatException);
    });
  });

  group('insertPages', () {
    test('several documents insert as one block, in order', () {
      final editor = PdfEditor(open(labeledPdf('T', 3)));
      final positions = editor.insertPages([
        PdfPageInsertSource(open(labeledPdf('A', 2))),
        PdfPageInsertSource(open(labeledPdf('B', 3)), indices: [2, 0]),
      ], at: 1);
      expect(positions, [1, 2, 3, 4]);
      final doc = open(editor.save());
      expect(labelsOf(doc), ['T1', 'A1', 'A2', 'B3', 'B1', 'T2', 'T3']);
    });

    test('interleave rejoins separately scanned odd and even pages', () {
      final editor = PdfEditor(open(labeledPdf('O', 3)));
      // the back sides came out of the scanner last page first
      final evens = open(labeledPdf('E', 3));
      final positions = editor.insertPages([
        PdfPageInsertSource(evens,
            indices: PdfPageInsertSource.select(3, reverse: true)),
      ], at: 1, interleave: const PdfPageInterleave());
      expect(positions, [1, 3, 5]);
      expect(
          labelsOf(open(editor.save())), ['O1', 'E3', 'O2', 'E2', 'O3', 'E1']);
    });

    test('a separator sheet after every two pages', () {
      final editor = PdfEditor(open(labeledPdf('T', 4)));
      editor.insertPages([PdfPageInsertSource(open(labeledPdf('S', 2)))],
          at: 2, interleave: const PdfPageInterleave(existing: 2));
      expect(
          labelsOf(open(editor.save())), ['T1', 'T2', 'S1', 'T3', 'T4', 'S2']);
    });

    test('bookmarks: imported, dropped, or nested under a file bookmark', () {
      List<String> titles(PdfDocument d) =>
          [for (final i in PdfOutline.of(d).items) i.title];

      final kept = PdfEditor(open(labeledPdf('T', 2)))
        ..insertPages(
            [PdfPageInsertSource(open(labeledPdf('A', 2, outline: 'Intro')))]);
      expect(titles(open(kept.save())), ['Intro']);

      final dropped = PdfEditor(open(labeledPdf('T', 2)))
        ..insertPages(
            [PdfPageInsertSource(open(labeledPdf('A', 2, outline: 'Intro')))],
            bookmarks: false);
      expect(PdfOutline.of(open(dropped.save())).items, isEmpty);

      final nested = PdfEditor(open(labeledPdf('T', 2, outline: 'Cover')))
        ..insertPages([
          PdfPageInsertSource(open(labeledPdf('A', 2, outline: 'Intro')),
              bookmarkTitle: 'a.pdf'),
          PdfPageInsertSource(open(labeledPdf('B', 1)), bookmarkTitle: 'b.pdf'),
        ], at: 1, interleave: const PdfPageInterleave());
      final doc = open(nested.save());
      expect(labelsOf(doc), ['T1', 'A1', 'T2', 'A2', 'B1']);
      final items = PdfOutline.of(doc).items;
      expect(titles(doc), ['Cover', 'a.pdf', 'b.pdf']);
      expect(items[1].destination!.pageIndex, 1);
      expect(items[1].children.single.title, 'Intro');
      expect(items[1].children.single.destination!.pageIndex, 1);
      expect(items[2].destination!.pageIndex, 4);
    });

    test('no pages means no edit', () {
      final editor = PdfEditor(open(labeledPdf('T', 2)));
      expect(
          editor.insertPages(
              [PdfPageInsertSource(open(labeledPdf('A', 2)), indices: [])]),
          isEmpty);
      expect(editor.hasChanges, isFalse);
    });
  });
}
