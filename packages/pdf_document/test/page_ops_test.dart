import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

/// The "Page N" label a page draws, parsed out of its content stream.
String labelOf(PdfDocument doc, int index) {
  final content = String.fromCharCodes(doc.page(index).contentBytes());
  final match = RegExp(r'\((Page \d+)\)').firstMatch(content);
  return match?.group(1) ?? '<no label>';
}

List<String> labelsOf(PdfDocument doc) =>
    [for (var i = 0; i < doc.pageCount; i++) labelOf(doc, i)];

PdfDocument reopened(PdfEditor editor) => PdfDocument.open(editor.save());

void main() {
  group('reorder', () {
    test('reorderPages permutes the page sequence', () {
      final doc = PdfDocument.open(buildMultiPagePdf(3));
      final editor = PdfEditor(doc)..reorderPages([2, 0, 1]);
      final out = reopened(editor);
      expect(labelsOf(out), ['Page 3', 'Page 1', 'Page 2']);
      expect(out.pageCount, 3);
    });

    test('movePage shifts a single page', () {
      final doc = PdfDocument.open(buildMultiPagePdf(4));
      final editor = PdfEditor(doc)..movePage(3, 0);
      expect(labelsOf(reopened(editor)),
          ['Page 4', 'Page 1', 'Page 2', 'Page 3']);
    });

    test('the edit is visible before saving too', () {
      final doc = PdfDocument.open(buildMultiPagePdf(3));
      PdfEditor(doc).reorderPages([1, 2, 0]);
      expect(labelsOf(doc), ['Page 2', 'Page 3', 'Page 1']);
    });

    test('a non-permutation is rejected', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(3)));
      expect(() => editor.reorderPages([0, 1]), throwsArgumentError);
      expect(() => editor.reorderPages([0, 1, 1]), throwsArgumentError);
      expect(() => editor.reorderPages([0, 1, 3]), throwsArgumentError);
      expect(editor.hasChanges, isFalse);
    });

    test('saves are incremental: the original bytes survive verbatim', () {
      final original = buildMultiPagePdf(3);
      final editor = PdfEditor(PdfDocument.open(original))
        ..reorderPages([2, 1, 0]);
      final saved = editor.save();
      expect(saved.sublist(0, original.length), original);
    });
  });

  group('remove', () {
    test('removePage drops a page from the tree', () {
      final doc = PdfDocument.open(buildMultiPagePdf(3));
      final editor = PdfEditor(doc)..removePage(1);
      expect(labelsOf(reopened(editor)), ['Page 1', 'Page 3']);
    });

    test('removePages drops several at once', () {
      final doc = PdfDocument.open(buildMultiPagePdf(5));
      final editor = PdfEditor(doc)..removePages([0, 2, 4]);
      expect(labelsOf(reopened(editor)), ['Page 2', 'Page 4']);
    });

    test('removing every page is rejected', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(2)));
      expect(() => editor.removePages([0, 1]), throwsArgumentError);
      expect(editor.hasChanges, isFalse);
    });
  });

  group('rotate', () {
    test('rotatePages turns the named pages clockwise', () {
      final doc = PdfDocument.open(buildMultiPagePdf(3));
      final editor = PdfEditor(doc)..rotatePages([0, 2], 90);
      final out = reopened(editor);
      expect(out.page(0).rotation, 90);
      expect(out.page(1).rotation, 0);
      expect(out.page(2).rotation, 90);
    });

    test('rotation accumulates onto the current display rotation', () {
      final doc = PdfDocument.open(buildMultiPagePdf(2));
      final editor = PdfEditor(doc)
        ..rotatePages([0], 90)
        ..rotatePages([0], 90);
      expect(reopened(editor).page(0).rotation, 180);
    });

    test('a counterclockwise turn normalizes to 0..270', () {
      final doc = PdfDocument.open(buildMultiPagePdf(1));
      final editor = PdfEditor(doc)..rotatePages([0], -90);
      expect(reopened(editor).page(0).rotation, 270);
    });

    test('a full turn (or no pages) changes nothing', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(2)))
        ..rotatePages([0], 360)
        ..rotatePages([], 90);
      expect(editor.hasChanges, isFalse);
    });

    test('a non-quarter turn is rejected', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(2)));
      expect(() => editor.rotatePages([0], 45), throwsArgumentError);
      expect(editor.hasChanges, isFalse);
    });

    test('an out-of-range index is rejected', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(2)));
      expect(() => editor.rotatePages([5], 90), throwsRangeError);
    });
  });

  group('insert blank page', () {
    test('appends a blank page sized to request', () {
      final doc = PdfDocument.open(buildMultiPagePdf(2));
      final editor = PdfEditor(doc)..insertBlankPage(width: 300, height: 400);
      final out = reopened(editor);
      expect(out.pageCount, 3);
      // the existing pages keep their labels and order
      expect(labelOf(out, 0), 'Page 1');
      expect(labelOf(out, 1), 'Page 2');
      expect(labelOf(out, 2), '<no label>'); // blank
      expect(out.page(2).mediaBox, const PdfRect(0, 0, 300, 400));
      expect(out.page(2).contentBytes(), isEmpty);
    });

    test('inserts at the requested position', () {
      final doc = PdfDocument.open(buildMultiPagePdf(2));
      final editor = PdfEditor(doc)..insertBlankPage(at: 1);
      final out = reopened(editor);
      expect(labelsOf(out), ['Page 1', '<no label>', 'Page 2']);
      // default size is US Letter
      expect(out.page(1).mediaBox, const PdfRect(0, 0, 612, 792));
    });

    test('the new page joins the flat tree under the root', () {
      final doc = PdfDocument.open(buildMultiPagePdf(1));
      final editor = PdfEditor(doc)..insertBlankPage();
      final out = reopened(editor);
      final rootRef = out.catalog['Pages'] as CosReference;
      expect(out.page(1).dict['Parent'], rootRef);
    });

    test('rejects non-positive dimensions and an out-of-range index', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(2)));
      expect(() => editor.insertBlankPage(width: 0), throwsArgumentError);
      expect(() => editor.insertBlankPage(height: -1), throwsArgumentError);
      expect(() => editor.insertBlankPage(at: 3), throwsRangeError);
      expect(editor.hasChanges, isFalse);
    });

    test('saves are incremental: the original bytes survive verbatim', () {
      final original = buildMultiPagePdf(2);
      final editor = PdfEditor(PdfDocument.open(original))..insertBlankPage();
      final saved = editor.save();
      expect(saved.sublist(0, original.length), original);
    });
  });

  group('flattening a nested tree', () {
    test('inherited attributes survive on the rearranged pages', () {
      final doc = PdfDocument.open(buildNestedPageTreePdf());
      // sanity: inheritance works before the edit
      expect(doc.page(0).rotation, 90);
      final editor = PdfEditor(doc)..reorderPages([2, 0, 1]);
      final out = reopened(editor);
      expect(labelsOf(out), ['Page 3', 'Page 1', 'Page 2']);

      final movedPage1 = out.page(1);
      expect(movedPage1.rotation, 90,
          reason: 'rotation inherited from the cut-out inner node');
      expect(movedPage1.mediaBox, const PdfRect(0, 0, 400, 400));
      expect(out.cos.resolve(movedPage1.resources['Font']), isA<CosDictionary>());

      final page3 = out.page(0);
      expect(page3.rotation, 0);
      expect(page3.mediaBox, const PdfRect(0, 0, 612, 792));

      // the tree is flat now: every page's parent is the root /Pages node
      final rootRef = out.catalog['Pages'] as CosReference;
      for (var i = 0; i < 3; i++) {
        expect(out.page(i).dict['Parent'], rootRef);
      }
    });
  });

  group('merge', () {
    test('appendPagesFrom copies whole documents', () {
      final dest = PdfDocument.open(buildMultiPagePdf(2));
      final source = PdfDocument.open(buildAnnotatedPdf());
      final editor = PdfEditor(dest)..appendPagesFrom(source);
      final out = reopened(editor);
      expect(labelsOf(out),
          ['Page 1', 'Page 2', 'Page 1', 'Page 2', 'Page 3']);
    });

    test('a subset inserts at the requested position', () {
      final dest = PdfDocument.open(buildMultiPagePdf(2));
      final source = PdfDocument.open(buildAnnotatedPdf());
      final editor = PdfEditor(dest)
        ..appendPagesFrom(source, indices: [2], at: 1);
      final out = reopened(editor);
      expect(labelsOf(out), ['Page 1', 'Page 3', 'Page 2']);
    });

    test('annotations come along and links between imported pages remap',
        () {
      final dest = PdfDocument.open(buildMultiPagePdf(1));
      final source = PdfDocument.open(buildAnnotatedPdf());
      final editor = PdfEditor(dest)..appendPagesFrom(source);
      final out = reopened(editor);

      final annots =
          out.cos.resolve(out.page(1).dict['Annots']) as CosArray;
      expect(annots.length, 6);

      // the GoTo link on imported page 1 pointed at source page 3, which
      // came along — its destination must now be the copy
      final goTo = out.cos.resolve(annots[1]) as CosDictionary;
      final action = out.cos.resolve(goTo['A']) as CosDictionary;
      final destArray = out.cos.resolve(action['D']) as CosArray;
      final target = out.cos.resolve(destArray[0]) as CosDictionary;
      expect(out.pageIndexOf(target), 3);
    });

    test('links to pages left behind become null', () {
      final dest = PdfDocument.open(buildMultiPagePdf(1));
      final source = PdfDocument.open(buildAnnotatedPdf());
      // import only page 1, whose GoTo link targets source page 3
      final editor = PdfEditor(dest)..appendPagesFrom(source, indices: [0]);
      final out = reopened(editor);
      final annots =
          out.cos.resolve(out.page(1).dict['Annots']) as CosArray;
      final goTo = out.cos.resolve(annots[1]) as CosDictionary;
      final action = out.cos.resolve(goTo['A']) as CosDictionary;
      final destArray = out.cos.resolve(action['D']) as CosArray;
      expect(out.cos.resolve(destArray[0]), CosNull.instance);
    });

    test('imported pages materialize attributes their source tree held',
        () {
      final dest = PdfDocument.open(buildMultiPagePdf(1));
      final source = PdfDocument.open(buildNestedPageTreePdf());
      final editor = PdfEditor(dest)..appendPagesFrom(source, indices: [0]);
      final out = reopened(editor);
      expect(out.page(1).rotation, 90);
      expect(out.page(1).mediaBox, const PdfRect(0, 0, 400, 400));
      expect(labelOf(out, 1), 'Page 1');
    });

    test('merging a document into itself is rejected', () {
      final doc = PdfDocument.open(buildMultiPagePdf(2));
      final editor = PdfEditor(doc);
      expect(() => editor.appendPagesFrom(doc), throwsArgumentError);
    });

    test('merge composes with further edits before saving', () {
      final dest = PdfDocument.open(buildMultiPagePdf(2));
      final source = PdfDocument.open(buildMultiPagePdf(3));
      final editor = PdfEditor(dest)
        ..appendPagesFrom(source)
        ..removePage(0)
        ..movePage(3, 0);
      final out = reopened(editor);
      expect(labelsOf(out), ['Page 3', 'Page 2', 'Page 1', 'Page 2']);
    });
  });

  group('split', () {
    test('extractPages builds a standalone document', () {
      final doc = PdfDocument.open(buildMultiPagePdf(3));
      final out = PdfDocument.open(doc.extractPages([1]));
      expect(out.pageCount, 1);
      expect(labelOf(out, 0), 'Page 2');
      expect(out.catalog.typeName, 'Catalog');
    });

    test('order is caller-chosen and duplicates are allowed', () {
      final doc = PdfDocument.open(buildMultiPagePdf(3));
      final out = PdfDocument.open(doc.extractPages([2, 0, 2]));
      expect(labelsOf(out), ['Page 3', 'Page 1', 'Page 3']);
    });

    test('link destinations between extracted pages remap', () {
      final doc = PdfDocument.open(buildAnnotatedPdf());
      final out = PdfDocument.open(doc.extractPages([0, 2]));
      final annots =
          out.cos.resolve(out.page(0).dict['Annots']) as CosArray;
      final goTo = out.cos.resolve(annots[1]) as CosDictionary;
      final action = out.cos.resolve(goTo['A']) as CosDictionary;
      final destArray = out.cos.resolve(action['D']) as CosArray;
      final target = out.cos.resolve(destArray[0]) as CosDictionary;
      expect(out.pageIndexOf(target), 1);
    });

    test('inherited attributes and /Info come along', () {
      final doc = PdfDocument.open(buildNestedPageTreePdf());
      final out = PdfDocument.open(doc.extractPages([1]));
      expect(out.page(0).rotation, 90);
      expect(out.page(0).mediaBox, const PdfRect(0, 0, 400, 400));
      expect(out.info['Title'], 'Nested');
      expect(labelOf(out, 0), 'Page 2');
    });

    test('an empty selection is rejected', () {
      final doc = PdfDocument.open(buildMultiPagePdf(2));
      expect(() => doc.extractPages([]), throwsArgumentError);
      expect(() => doc.extractPages([2]), throwsRangeError);
    });

    test('extractPageRange exports a contiguous span', () {
      final doc = PdfDocument.open(buildMultiPagePdf(5));
      final out = PdfDocument.open(doc.extractPageRange(1, 3));
      expect(labelsOf(out), ['Page 2', 'Page 3', 'Page 4']);
    });

    test('extractPageRange rejects a reversed or out-of-range span', () {
      final doc = PdfDocument.open(buildMultiPagePdf(3));
      expect(() => doc.extractPageRange(2, 1), throwsArgumentError);
      expect(() => doc.extractPageRange(0, 5), throwsRangeError);
    });

    test('extracting from an encrypted document yields plain output', () {
      final doc = PdfDocument.open(buildEncryptedPdf(revision: 4));
      expect(doc.cos.isEncrypted, isTrue);
      final out = PdfDocument.open(doc.extractPages([0]));
      expect(out.cos.isEncrypted, isFalse);
      expect(String.fromCharCodes(out.page(0).contentBytes()),
          contains('Hello, world!'));
    });
  });

  group('round-trip through a second edit session', () {
    test('a rearranged file accepts further incremental edits', () {
      final first = PdfEditor(PdfDocument.open(buildMultiPagePdf(3)))
        ..reorderPages([2, 0, 1]);
      final second =
          PdfEditor(PdfDocument.open(first.save()))..removePage(0);
      expect(labelsOf(reopened(second)), ['Page 1', 'Page 2']);
    });

    test('an extracted file accepts incremental edits', () {
      final doc = PdfDocument.open(buildMultiPagePdf(4));
      final extracted = PdfDocument.open(doc.extractPages([0, 1, 2]));
      final editor = PdfEditor(extracted)..reorderPages([1, 0, 2]);
      expect(labelsOf(reopened(editor)), ['Page 2', 'Page 1', 'Page 3']);
    });
  });

  group('appearance of merged widget annotations', () {
    test('a widget /Parent field chain copies without the page tree', () {
      final dest = PdfDocument.open(buildMultiPagePdf(1));
      final source = PdfDocument.open(buildAnnotatedPdf());
      final editor = PdfEditor(dest)..appendPagesFrom(source, indices: [0]);
      final out = reopened(editor);
      final annots =
          out.cos.resolve(out.page(1).dict['Annots']) as CosArray;
      final widget = out.cos.resolve(annots[3]) as CosDictionary;
      final parent = out.cos.resolve(widget['Parent']) as CosDictionary;
      final title = out.cos.resolve(parent['T']) as CosString;
      expect(title.text, 'actions');
    });
  });
}
