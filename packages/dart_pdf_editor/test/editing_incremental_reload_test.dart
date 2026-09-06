import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

/// The editing commit path folds each appended revision into the already-open
/// document instead of reopening it, so a long session stops paying an
/// O(revisions^2) walk of the `/Prev` chain.
///
/// Every test here is really the same assertion: **the incrementally updated
/// document must be indistinguishable from one opened from scratch over the
/// same bytes.** That is the entire risk of the change - a stale cached
/// object or an unrefreshed trailer would show up as an edit that renders
/// correctly right after it is made and wrongly after the file is reloaded.
void main() {
  /// Everything about a document that an edit can move.
  ///
  /// `pageIndexOf` is in here deliberately: it is the only reader of
  /// `PdfDocument`'s lazily built leaf cache, so without it a stale
  /// `_leafCache` surviving an in-place update would go unnoticed (verified -
  /// deleting `invalidatePageCache()` from `applyIncrementalUpdate` passes
  /// every other assertion here).
  Map<String, Object?> snapshot(PdfDocument document) {
    final pages = <Map<String, Object?>>[];
    for (var i = 0; i < document.pageCount; i++) {
      final page = document.page(i);
      pages.add({
        'mediaBox': page.mediaBox.toString(),
        'rotation': page.rotation,
        'contentLength': page.contentBytes().length,
        'contentHash': Object.hashAll(page.contentBytes()),
        'indexOf': document.pageIndexOf(page.dict),
        'annotations': [
          for (final annotation in page.annotations)
            {
              'subtype': annotation.subtype,
              'rect': annotation.rect.toString(),
              'contents': annotation.contents,
            }
        ],
      });
    }
    return {'pageCount': document.pageCount, 'pages': pages};
  }

  /// The controller's live document vs. a cold open of the same bytes.
  void expectMatchesColdOpen(PdfEditingController editing, String reason,
      {String password = ''}) {
    final cold = PdfDocument.open(editing.bytes, password: password);
    // Deep map/list equality, not `.toString()` - the matcher reports which
    // key diverged instead of dumping two multi-KB strings side by side.
    expect(snapshot(editing.document), snapshot(cold), reason: reason);
  }

  test('a long session stays identical to a cold open at every revision', () {
    final editing = PdfEditingController(buildMultiPagePdf(3));
    addTearDown(editing.dispose);

    // 40 revisions across both pages - well past the point where the /Prev
    // chain is long enough for the old full-reopen path to be doing real work.
    for (var i = 0; i < 40; i++) {
      final page = i % 3;
      editing.addRectangle(
          page, PdfRect(100 + i.toDouble(), 200, 180 + i.toDouble(), 260));
      expectMatchesColdOpen(editing, 'after revision ${i + 1}');
    }

    expect(editing.document.page(0).annotations, hasLength(14));
    expect(editing.document.page(1).annotations, hasLength(13));
    expect(editing.document.page(2).annotations, hasLength(13));
  });

  test('undo and redo both land on a document matching a cold open', () {
    final editing = PdfEditingController(buildMultiPagePdf(2));
    addTearDown(editing.dispose);

    for (var i = 0; i < 6; i++) {
      editing.addRectangle(0, PdfRect(100, 200 + i.toDouble() * 10, 180, 240));
    }
    expectMatchesColdOpen(editing, 'after the initial edits');

    // undo shrinks the buffer - not an append, so this exercises the reopen
    // fallback rather than the incremental path
    for (var i = 0; i < 4; i++) {
      editing.undo();
      expectMatchesColdOpen(editing, 'after undo ${i + 1}');
    }

    // redo re-extends to bytes already in the buffer: an append again
    for (var i = 0; i < 4; i++) {
      editing.redo();
      expectMatchesColdOpen(editing, 'after redo ${i + 1}');
    }

    expect(editing.document.page(0).annotations, hasLength(6));
  });

  test('editing after an undo (a discarded redo branch) stays consistent', () {
    // The new revision is built on the *truncated* buffer, so its prefix is a
    // different byte sequence from the one the previous head carried. If the
    // append check were keyed on buffer identity rather than content this is
    // where it would graft the wrong xref on.
    final editing = PdfEditingController(buildMultiPagePdf(2));
    addTearDown(editing.dispose);

    editing.addRectangle(0, const PdfRect(100, 200, 180, 260));
    editing.addRectangle(0, const PdfRect(200, 200, 280, 260));
    editing.addRectangle(0, const PdfRect(300, 200, 380, 260));
    editing.undo();
    editing.undo();
    expect(editing.document.page(0).annotations, hasLength(1));

    editing.addRectangle(1, const PdfRect(120, 300, 200, 360));
    expectMatchesColdOpen(editing, 'after branching off an undone revision');
    expect(editing.document.page(0).annotations, hasLength(1));
    expect(editing.document.page(1).annotations, hasLength(1));

    expect(editing.canRedo, isFalse, reason: 'the redo branch was discarded');
  });

  test('structural page edits stay consistent through the incremental path',
      () {
    // Page reorder/removal rewrites the page tree, which is exactly the case
    // where a stale cached /Pages node would survive an in-place update.
    final editing = PdfEditingController(buildMultiPagePdf(4));
    addTearDown(editing.dispose);

    editing.addRectangle(0, const PdfRect(100, 200, 180, 260));
    editing.addRectangle(3, const PdfRect(100, 200, 180, 260));

    editing.movePage(0, 2);
    expectMatchesColdOpen(editing, 'after movePage');
    expect(editing.document.pageCount, 4);

    editing.removePage(1);
    expectMatchesColdOpen(editing, 'after removePage');
    expect(editing.document.pageCount, 3);

    editing.addRectangle(0, const PdfRect(140, 220, 200, 280));
    expectMatchesColdOpen(editing, 'after editing a reordered document');
  });

  test('an encrypted document survives a session on the incremental path', () {
    // The two paths differ here in a way nothing else in this file exercises:
    // the reopen fallback re-derives the security handler from the password,
    // while the incremental path keeps the handler already on the shared
    // CosDocument. If an in-place update ever dropped or re-derived it wrongly,
    // strings and streams would decrypt to garbage from the second revision on.
    final editing = PdfEditingController(buildEncryptedPdf(revision: 4));
    addTearDown(editing.dispose);

    for (var i = 0; i < 10; i++) {
      editing.addRectangle(
          0, PdfRect(100, 200 + i.toDouble() * 5, 180, 250));
      expectMatchesColdOpen(editing, 'encrypted revision ${i + 1}');
    }
    expect(editing.document.page(0).annotations, hasLength(10));

    // the decrypted content stream still reads as plaintext operators, so the
    // file key survived the in-place updates rather than silently going stale
    expect(String.fromCharCodes(editing.document.page(0).contentBytes()),
        contains('Hello, world!'));

    editing.undo();
    expectMatchesColdOpen(editing, 'encrypted undo (reopen fallback)');
    editing.redo();
    expectMatchesColdOpen(editing, 'encrypted redo (incremental path)');
  });

  test('an AES-256 (R6) document survives the incremental path', () {
    // R6 uses the file key directly rather than per-object keys, so it walks a
    // different branch of the handler than the R4 case above.
    final editing = PdfEditingController(buildEncryptedPdf(revision: 6));
    addTearDown(editing.dispose);

    for (var i = 0; i < 5; i++) {
      editing.addRectangle(0, PdfRect(100, 200 + i.toDouble() * 5, 180, 250));
      expectMatchesColdOpen(editing, 'R6 revision ${i + 1}');
    }
    expect(String.fromCharCodes(editing.document.page(0).contentBytes()),
        contains('Hello, world!'));
  });

  test('the revision buffer stays a prefix chain (saves are still appends)',
      () {
    // The incremental path is only sound while each revision appends to the
    // last. If a mutation ever stopped being an append without routing through
    // _resetTo, this is the guard that catches it.
    final editing = PdfEditingController(buildMultiPagePdf(2));
    addTearDown(editing.dispose);

    var previous = editing.bytes;
    for (var i = 0; i < 8; i++) {
      editing.addRectangle(i.isEven ? 0 : 1,
          PdfRect(100, 200 + i.toDouble() * 5, 180, 250));
      final current = editing.bytes;
      expect(current.length, greaterThan(previous.length));
      expect(current.sublist(0, previous.length), previous,
          reason: 'revision ${i + 1} is not an append of its predecessor');
      previous = current;
    }
  });
}
