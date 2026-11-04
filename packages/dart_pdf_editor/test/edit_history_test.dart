// Edit-history invariants, without opening a PDF: revision records, the
// undo floor, and draft layers that undo consumes first.

import 'package:dart_pdf_editor/src/editing/edit_history.dart';
import 'package:dart_pdf_editor/src/editing/ink_draft.dart';
import 'package:flutter_test/flutter_test.dart';

PdfRevisionRecord _rev(int length, [Map<String, String> secrets = const {}]) =>
    PdfRevisionRecord(length: length, secrets: secrets);

void main() {
  group('revisions', () {
    test('undo/redo walk the records and report both ends', () {
      final history = PdfEditHistory(100)
        ..commit(_rev(150))
        ..commit(_rev(200));
      final back = history.undo()! as PdfRevisionStep;
      expect(
          (back.from.length, back.to.length, back.forward), (200, 150, false));
      final forward = history.redo()! as PdfRevisionStep;
      expect((forward.from.length, forward.to.length, forward.forward),
          (150, 200, true));
      expect(history.redo(), isNull);
    });

    test('a commit after undo drops the redo branch', () {
      final history = PdfEditHistory(100)
        ..commit(_rev(150))
        ..commit(_rev(200))
        ..undo()
        ..commit(_rev(180));
      expect(history.length, 3);
      expect(history.canRedo, isFalse);
      expect(history.current.length, 180);
    });

    test('a remote commit raises the floor; local commits stay undoable', () {
      final history = PdfEditHistory(100)
        ..commit(_rev(150))
        ..commit(_rev(200), remote: true)
        ..commit(_rev(250));
      expect(history.undo(), isA<PdfRevisionStep>());
      expect(history.undo(), isNull,
          reason: 'the remote revision is the floor');
      expect(history.current.length, 200);
    });

    test('secrets follow the cursor', () {
      final history = PdfEditHistory(100)
        ..commit(_rev(150, {'pin': '1234'}))
        ..commit(_rev(200, {'pin': ''}));
      history.undo();
      expect(history.current.secrets, {'pin': '1234'});
      history.undo();
      expect(history.current.secrets, isEmpty);
    });

    test('updateSecrets keeps shared maps shared', () {
      const shared = {'a': '1'};
      final history = PdfEditHistory(100, secrets: shared)
        ..commit(_rev(150, shared));
      history.updateSecrets((s) => {'b': '2', ...s});
      expect(history.current.secrets, {'a': '1', 'b': '2'});
      expect(
          identical(history.current.secrets, history.opened.secrets), isTrue);
    });

    test('resetTo leaves one revision and lowers the floor', () {
      final history = PdfEditHistory(100)
        ..commit(_rev(150), remote: true)
        ..resetTo(_rev(90));
      expect((history.length, history.cursor, history.floor), (1, 0, 0));
      expect(history.canUndo, isFalse);
    });
  });

  group('drafts', () {
    late PdfEditHistory history;
    late PdfInkDraft ink;

    setUp(() {
      history = PdfEditHistory(100)..commit(_rev(150));
      ink = PdfInkDraft();
      history.pushDraft(ink, ink);
    });

    test('ink undoes stroke by stroke before any revision', () {
      ink
        ..add(0, [(1, 1)])
        ..add(1, [(2, 2)]);
      expect(history.undo(), isA<PdfDraftStep>());
      expect(ink.strokesOn(1), isEmpty);
      expect(ink.strokesOn(0), hasLength(1));
      expect(history.undo(), isA<PdfDraftStep>());
      expect(ink.isNotEmpty, isFalse);
      expect(history.undo(), isA<PdfRevisionStep>());
      expect(history.cursor, 0);
    });

    test('redo replays revisions before undone ink', () {
      ink.add(0, [(1, 1)]);
      history
        ..undo() // the stroke
        ..undo(); // the revision
      expect(history.redo(), isA<PdfRevisionStep>());
      expect(ink.isNotEmpty, isFalse);
      expect(history.redo(), isA<PdfDraftStep>());
      expect(ink.strokesOn(0), hasLength(1));
      expect(history.canRedo, isFalse);
    });

    test('a partial ink undo stays redoable until a fresh edit', () {
      ink
        ..add(0, [(1, 1)])
        ..add(0, [(2, 2)]);
      history.undo();
      expect(history.canRedo, isTrue);
      history.commit(_rev(180));
      expect(ink.hasUndone, isFalse, reason: 'the commit drops draft redo');
      expect(history.canRedo, isFalse);
    });

    test('drawing after an undo truncates the revision redo branch', () {
      history.undo();
      expect(history.canRedoRevision, isTrue);
      history.dropRedo();
      ink.add(0, [(1, 1)]);
      expect(history.canRedoRevision, isFalse);
      expect(history.length, 1);
    });

    test('the newest draft undoes first; a spent one falls through', () {
      var vertices = 2;
      final placement = _FakeDraft(() => vertices-- > 0);
      ink.add(0, [(1, 1)]);
      history.pushDraft('placement', placement);
      expect(history.undo(), isA<PdfDraftStep>());
      expect(history.undo(), isA<PdfDraftStep>());
      expect(ink.isNotEmpty, isTrue, reason: 'vertices go first');
      final third = history.undo()! as PdfDraftStep;
      expect(identical(third.draft, ink), isTrue);
      history.removeDraft('placement');
      expect(history.hasDraft('placement'), isFalse);
    });

    test('a spent draft with no revision to undo steps nothing', () {
      final fresh = PdfEditHistory(100)
        ..pushDraft('placement', _FakeDraft(() => false));
      expect(fresh.undo(), isNull);
      expect(fresh.cursor, 0);
    });
  });
}

class _FakeDraft implements PdfHistoryDraft {
  _FakeDraft(this._undo);

  final bool Function() _undo;

  @override
  bool get canUndo => true;

  @override
  bool get canRedo => false;

  @override
  bool undo() => _undo();

  @override
  bool redo() => false;

  @override
  void dropRedo() {}
}
