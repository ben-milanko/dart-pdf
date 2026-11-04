import 'package:pdf_document/pdf_document.dart';

/// One committed revision of an edit session: everything undo and redo need
/// to restore it, kept together so nothing can fall out of step.
class PdfRevisionRecord {
  const PdfRevisionRecord({
    required this.length,
    this.impact = PdfEditImpact.none,
    this.secrets = const {},
  });

  /// Byte length of the revision - a prefix of the session buffer.
  final int length;

  /// The consequences reported by the mutation that produced it. The opened
  /// document's record carries [PdfEditImpact.none] and is never replayed.
  final PdfEditImpact impact;

  /// The withheld password values (field name -> value, `''` for an explicit
  /// clear) in effect at this revision.
  final Map<String, String> secrets;

  PdfRevisionRecord withSecrets(Map<String, String> secrets) =>
      PdfRevisionRecord(length: length, impact: impact, secrets: secrets);
}

/// A transient layer of work above the newest revision - buffered ink, a
/// multi-click placement - that undo consumes before the byte history and
/// redo restores after it.
abstract interface class PdfHistoryDraft {
  bool get canUndo;

  bool get canRedo;

  /// Steps the draft back once. False when nothing was stepped back, so the
  /// undo falls through to the next layer.
  bool undo();

  /// Restores the most recently undone step. False when there was none.
  bool redo();

  /// A fresh edit landed: forget what [redo] would have restored.
  void dropRedo();
}

/// What one [PdfEditHistory.undo] or [PdfEditHistory.redo] did.
sealed class PdfHistoryStep {
  const PdfHistoryStep();
}

/// A draft stepped; the document did not change.
final class PdfDraftStep extends PdfHistoryStep {
  const PdfDraftStep(this.draft);

  final PdfHistoryDraft draft;
}

/// The cursor moved from [from] to [to].
final class PdfRevisionStep extends PdfHistoryStep {
  const PdfRevisionStep(
      {required this.from, required this.to, required this.forward});

  final PdfRevisionRecord from;
  final PdfRevisionRecord to;

  /// Whether this was a redo (the buffer re-extends) rather than an undo.
  final bool forward;

  /// The pages the step re-renders: the impact of the revision that was
  /// reverted (undo) or replayed (redo).
  PdfEditImpact get impact => forward ? to.impact : from.impact;
}

/// The undo/redo history of an edit session: one [PdfRevisionRecord] per
/// revision with a cursor and an undo floor, plus a stack of transient
/// [PdfHistoryDraft]s that undo consumes first.
///
/// Pure bookkeeping - it never touches bytes or documents. The controller
/// commits through it and fans out the impact of each step it returns.
class PdfEditHistory {
  PdfEditHistory(int openedLength, {Map<String, String> secrets = const {}})
      : _records = [PdfRevisionRecord(length: openedLength, secrets: secrets)];

  final List<PdfRevisionRecord> _records;
  int _cursor = 0;
  int _floor = 0;

  /// Drafts in registration order; undo tries the newest first.
  final List<(Object, PdfHistoryDraft)> _drafts = [];

  /// The current revision.
  PdfRevisionRecord get current => _records[_cursor];

  /// The revision as opened (or as last [resetTo]).
  PdfRevisionRecord get opened => _records.first;

  /// Index of [current]; 0 is the opened document.
  int get cursor => _cursor;

  /// How many revisions are retained, redoable ones included.
  int get length => _records.length;

  /// The oldest revision undo may reach. A remote commit advances it, so a
  /// local undo never removes collaboration state another session sent.
  int get floor => _floor;

  bool get canUndoRevision => _cursor > _floor;

  bool get canRedoRevision => _cursor < _records.length - 1;

  bool get canUndo => canUndoRevision || _drafts.any((d) => d.$2.canUndo);

  bool get canRedo => canRedoRevision || _drafts.any((d) => d.$2.canRedo);

  /// Registers [draft] as [owner]'s layer, replacing any it already had.
  void pushDraft(Object owner, PdfHistoryDraft draft) {
    _drafts
      ..removeWhere((d) => identical(d.$1, owner))
      ..add((owner, draft));
  }

  /// Drops [owner]'s draft layer, if it still has one.
  void removeDraft(Object owner) =>
      _drafts.removeWhere((d) => identical(d.$1, owner));

  /// Whether [owner] has a draft layer registered.
  bool hasDraft(Object owner) => _drafts.any((d) => identical(d.$1, owner));

  /// Steps back: the newest draft that can, else one revision. Null when
  /// nothing stepped.
  PdfHistoryStep? undo() {
    for (final (_, draft) in _drafts.reversed) {
      if (draft.canUndo && draft.undo()) return PdfDraftStep(draft);
    }
    if (!canUndoRevision) return null;
    final from = current;
    _cursor--;
    return PdfRevisionStep(from: from, to: current, forward: false);
  }

  /// Steps forward: revisions first (drafts sit above the newest one), then
  /// the oldest draft with something to restore. Null when nothing stepped.
  PdfHistoryStep? redo() {
    if (canRedoRevision) {
      final from = current;
      _cursor++;
      return PdfRevisionStep(from: from, to: current, forward: true);
    }
    for (final (_, draft) in _drafts) {
      if (draft.canRedo && draft.redo()) return PdfDraftStep(draft);
    }
    return null;
  }

  /// A fresh edit started: the redo branch - revisions and drafts alike -
  /// can no longer be reached.
  void dropRedo() {
    _records.removeRange(_cursor + 1, _records.length);
    for (final (_, draft) in _drafts) {
      draft.dropRedo();
    }
  }

  /// Records [record] as the new current revision, dropping the redo branch.
  /// A [remote] commit raises the undo floor to it.
  void commit(PdfRevisionRecord record, {bool remote = false}) {
    dropRedo();
    _records.add(record);
    _cursor++;
    if (remote) _floor = _cursor;
  }

  /// Replaces the whole history with [record] as its only revision.
  void resetTo(PdfRevisionRecord record) {
    _records
      ..clear()
      ..add(record);
    _cursor = 0;
    _floor = 0;
  }

  /// Rewrites every record's secrets through [update]. Records that shared
  /// one map still share one afterwards.
  void updateSecrets(
      Map<String, String> Function(Map<String, String> secrets) update) {
    final updated = Map<Map<String, String>, Map<String, String>>.identity();
    for (var i = 0; i < _records.length; i++) {
      final record = _records[i];
      _records[i] = record.withSecrets(
          updated.putIfAbsent(record.secrets, () => update(record.secrets)));
    }
  }
}
