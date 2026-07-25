part of 'editor.dart';

/// What happened to one annotation between two document states.
enum PdfAnnotationChangeKind { created, modified, removed }

/// One entry of an annotation diff ([pdfDiffAnnotations]): the unit a
/// sync layer stores and replays.
///
/// [name] is the /NM identity the change is keyed on ([PdfAnnotation.name]);
/// it is null only for annotations that never had one, which can't be
/// tracked across states and therefore surface as removed + created pairs
/// instead of modifications. [snapshot] carries the annotation's full
/// content (appearance included) for created/modified changes — encode it
/// with [PdfAnnotationSnapshot.toJson] and replay it elsewhere with
/// [PdfAnnotationSyncEditing.upsertAnnotation].
class PdfAnnotationChange {
  const PdfAnnotationChange({
    required this.kind,
    required this.pageIndex,
    required this.name,
    this.snapshot,
  });

  final PdfAnnotationChangeKind kind;

  /// The page the annotation lives on (for [PdfAnnotationChangeKind.removed],
  /// lived on before the change).
  final int pageIndex;

  /// The /NM identity, when the annotation has one.
  final String? name;

  /// The annotation's content after the change; null for removals.
  final PdfAnnotationSnapshot? snapshot;

  @override
  String toString() =>
      'PdfAnnotationChange(${kind.name}, page $pageIndex, $name)';
}

/// Diffs the annotations of two states of a document, keyed on /NM.
///
/// [before] and [after] are typically two revisions of the same document
/// (the editing controller diffs across each apply/undo/redo); [pages]
/// limits the walk to the page indices an edit touched — null walks
/// everything, which structural edits (page reorder/removal) need.
///
/// Popups, links, and form widgets are outside the diff: they can't be
/// captured as snapshots, so a sync layer can't replay them anyway.
/// Annotations without /NM match only when their content is identical —
/// an edit to one reads as a removal plus a creation. Run
/// [PdfAnnotationEditing.nameAnnotations] once over legacy documents
/// to give everything a durable identity first.
List<PdfAnnotationChange> pdfDiffAnnotations(
  PdfDocument before,
  PdfDocument after, {
  Iterable<int>? pages,
}) =>
    pdfDiffAnnotationStates(
      pdfCollectAnnotationStates(before, pages: pages),
      pdfCollectAnnotationStates(after, pages: pages),
    );

/// An opaque snapshot of a document's annotation states, keyed on identity
/// (/NM, or serialized content for anonymous annotations).
///
/// Capturing this (proportional to annotation count) lets a caller diff a
/// later document state against an earlier one *without* re-opening the
/// earlier bytes — the editing controller keeps one as a live baseline so a
/// sync session pays no second [PdfDocument.open] per commit (#416).
class PdfAnnotationStates {
  const PdfAnnotationStates._(this._byKey);

  final Map<String, _AnnotationState> _byKey;

  /// The number of tracked annotations.
  int get length => _byKey.length;

  /// The subset of these states that live on any of [pages] — the pre-edit
  /// side of a page-limited diff.
  PdfAnnotationStates restrictedTo(Set<int> pages) => PdfAnnotationStates._({
        for (final entry in _byKey.entries)
          if (pages.contains(entry.value.pageIndex)) entry.key: entry.value,
      });

  /// These states with every annotation on [pages] dropped and [replacement]'s
  /// entries added in — how the baseline advances after a page-limited edit.
  /// [replacement] must have been collected for exactly [pages].
  PdfAnnotationStates withPagesReplaced(
          Set<int> pages, PdfAnnotationStates replacement) =>
      PdfAnnotationStates._({
        for (final entry in _byKey.entries)
          if (!pages.contains(entry.value.pageIndex)) entry.key: entry.value,
        ...replacement._byKey,
      });
}

/// Captures the annotation states of [document] (optionally limited to
/// [pages]) as an identity-keyed snapshot for later diffing. See
/// [PdfAnnotationStates].
PdfAnnotationStates pdfCollectAnnotationStates(PdfDocument document,
        {Iterable<int>? pages}) =>
    PdfAnnotationStates._(_collectAnnotations(document, pages));

/// Diffs two annotation-state snapshots ([pdfCollectAnnotationStates]),
/// keyed on identity — the state-level core of [pdfDiffAnnotations].
List<PdfAnnotationChange> pdfDiffAnnotationStates(
  PdfAnnotationStates before,
  PdfAnnotationStates after,
) {
  final old = before._byKey;
  final now = after._byKey;
  final changes = <PdfAnnotationChange>[];

  now.forEach((key, entry) {
    final was = old[key];
    if (was == null) {
      changes.add(PdfAnnotationChange(
        kind: PdfAnnotationChangeKind.created,
        pageIndex: entry.pageIndex,
        name: entry.name,
        snapshot: entry.snapshot,
      ));
    } else if (was.fingerprint != entry.fingerprint ||
        was.pageIndex != entry.pageIndex) {
      changes.add(PdfAnnotationChange(
        kind: PdfAnnotationChangeKind.modified,
        pageIndex: entry.pageIndex,
        name: entry.name,
        snapshot: entry.snapshot,
      ));
    }
  });
  old.forEach((key, entry) {
    if (!now.containsKey(key)) {
      changes.add(PdfAnnotationChange(
        kind: PdfAnnotationChangeKind.removed,
        pageIndex: entry.pageIndex,
        name: entry.name,
      ));
    }
  });
  return changes;
}

class _AnnotationState {
  _AnnotationState(this.pageIndex, this.name, this.snapshot, this.fingerprint);

  final int pageIndex;
  final String? name;
  final PdfAnnotationSnapshot snapshot;
  final String fingerprint;
}

/// One side of the diff: identity key → state. Named annotations key on
/// /NM; anonymous ones key on their full serialized content (and page),
/// so an unchanged one matches itself and a changed one diffs as
/// removed + created.
Map<String, _AnnotationState> _collectAnnotations(
    PdfDocument document, Iterable<int>? pages) {
  final out = <String, _AnnotationState>{};
  final pageCount = document.pageCount;
  final indices = pages ?? Iterable<int>.generate(pageCount);
  for (final pageIndex in indices) {
    if (pageIndex < 0 || pageIndex >= pageCount) continue;
    for (final annotation in document.page(pageIndex).annotations) {
      final snapshot = PdfAnnotationSnapshot.capture(document, annotation,
          keepName: true,
          sourcePageRotation: document.page(pageIndex).rotation);
      if (snapshot == null) continue; // Popup/Widget/Link
      final fingerprint = jsonEncode(snapshot.toJson());
      final name = annotation.name;
      final key = name != null ? 'nm:$name' : 'anon:$pageIndex:$fingerprint';
      out[key] = _AnnotationState(pageIndex, name, snapshot, fingerprint);
    }
  }
  return out;
}

/// Name-keyed annotation editing: the replay half of a sync layer.
extension PdfAnnotationSyncEditing on PdfEditor {
  /// Finds the annotation whose /NM is [name], searching [pageIndex]
  /// first (the common case) and then the rest of the document.
  (int pageIndex, PdfAnnotation annotation)? _findByName(String name,
      {int? pageIndex}) {
    (int, PdfAnnotation)? scan(int index) {
      for (final annotation in document.page(index).annotations) {
        if (annotation.name == name) return (index, annotation);
      }
      return null;
    }

    final pageCount = document.pageCount;
    if (pageIndex != null && pageIndex >= 0 && pageIndex < pageCount) {
      final hit = scan(pageIndex);
      if (hit != null) return hit;
    }
    for (var index = 0; index < pageCount; index++) {
      if (index == pageIndex) continue;
      final hit = scan(index);
      if (hit != null) return hit;
    }
    return null;
  }

  /// Creates or replaces the annotation identified by [snapshot]'s /NM
  /// on page [pageIndex] — the receiving end of a
  /// [PdfAnnotationChangeKind.created] or `modified` change.
  ///
  /// The snapshot must carry a name (capture with `keepName: true`, or
  /// arrive through [PdfAnnotationChange.snapshot]). An existing
  /// annotation with that name is removed first wherever it lives —
  /// a modification that moved pages replays correctly. The replayed
  /// copy keeps the snapshot's exact geometry and appearance.
  void upsertAnnotation(int pageIndex, PdfAnnotationSnapshot snapshot) {
    final name = snapshot.name;
    if (name == null) {
      throw ArgumentError(
          'snapshot carries no /NM — capture it with keepName: true');
    }
    final existing = _findByName(name, pageIndex: pageIndex);
    if (existing != null) {
      removeAnnotation(existing.$1, existing.$2);
    }
    pasteAnnotation(pageIndex, snapshot);
  }

  /// Removes the annotation whose /NM is [name] — the receiving end of a
  /// [PdfAnnotationChangeKind.removed] change. Returns whether it was
  /// found. [pageIndex] is a search hint, not a constraint.
  bool removeAnnotationByName(String name, {int? pageIndex}) {
    final existing = _findByName(name, pageIndex: pageIndex);
    if (existing == null) return false;
    removeAnnotation(existing.$1, existing.$2);
    return true;
  }
}
