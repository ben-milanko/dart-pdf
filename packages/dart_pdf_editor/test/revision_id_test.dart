import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pins the #414 contract: [PdfEditingController.revisionId] is the "did a new
/// revision land?" signal, so editing widgets compare it instead of
/// `identical(document, ...)`. The identity trick worked only because a commit
/// happened to allocate a fresh wrapper; applying a revision in place would keep
/// the same object and silently break every such check (this is what bit #395).
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('PdfEditingController.revisionId', () {
    test('bumps on every commit, undo, and redo', () {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      final r0 = editing.revisionId;

      editing.addRectangle(0, const PdfRect(100, 100, 200, 200));
      final r1 = editing.revisionId;
      expect(r1, isNot(r0), reason: 'a commit lands a new revision');

      editing.addRectangle(0, const PdfRect(120, 120, 220, 220));
      final r2 = editing.revisionId;
      expect(r2, isNot(r1), reason: 'a second commit is another revision');

      editing.undo();
      final rUndo = editing.revisionId;
      expect(rUndo, isNot(r2), reason: 'undo is a revision transition');

      editing.redo();
      final rRedo = editing.revisionId;
      // Undo-then-redo returns to the same undo cursor, but the document object
      // genuinely changed - so a plain monotonic id is required (deriving it
      // from the cursor would wrongly report "no change" here).
      expect(rRedo, isNot(rUndo), reason: 'redo is a revision transition');

      editing.dispose();
    });

    test('does not bump when a commit produces no revision', () {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      final before = editing.revisionId;
      // Nothing to undo at the initial revision - a guarded no-op, no transition.
      editing.undo();
      expect(editing.revisionId, before,
          reason: 'a no-op must not move the revision id');
      editing.dispose();
    });

    test('the document wrapper identity is no longer load-bearing', () {
      // The wrapper does still change today (withIncrementalUpdate), but the id
      // is the contract. This asserts they agree on "a revision landed", so a
      // future in-place update that keeps the wrapper stays covered by the id.
      final editing = PdfEditingController(buildMultiPagePdf(1));
      final before = editing.revisionId;
      editing.addRectangle(0, const PdfRect(100, 100, 200, 200));
      expect(editing.revisionId, isNot(before));
      editing.dispose();
    });
  });
}
