part of 'editor.dart';

/// Authoring reply threads on markup annotations (§12.5.6.x): replies
/// linked by /IRT, and review/marked state recorded as state replies
/// (§12.5.6.2). Regenerated so other readers (Acrobat) show the same
/// thread.
///
/// A reply and a state annotation are markup `/Text` annotations that
/// carry no on-page appearance - they are thread content shown in the
/// comment pane, not a second icon painted over the page (the renderer
/// skips them, [PdfAnnotation.isReply]/[PdfAnnotation.isStateAnnotation]).
/// Each gets a generated /NM, so replies and state changes sync through
/// the same snapshot + diff machinery as any annotation; the snapshot
/// preserves the /IRT link by the parent's /NM and relinks it on replay
/// ([PdfAnnotationSnapshot.inReplyTo]).
extension PdfCommentEditing on PdfEditor {
  /// Adds a reply to [target] on page [pageIndex] with body [contents],
  /// returning the reply's generated (or supplied) /NM.
  ///
  /// The reply is a `/Text` markup annotation with /IRT referencing
  /// [target] and /RT `R`. [target] may itself be a reply, building a
  /// deeper chain. [author] sets /T; [createdAt] overrides the timestamp
  /// (defaults to now) - pass it when replaying a synced reply so /M and
  /// /CreationDate match the origin.
  ///
  /// Throws if [target] is not yet an indirect object (create it, save,
  /// and reopen the document before replying - every editor-authored
  /// annotation is indirect once written).
  String replyToAnnotation(
    int pageIndex,
    PdfAnnotation target,
    String contents, {
    String? author,
    String? subject,
    DateTime? createdAt,
    String? name,
  }) {
    final parentRef = document.cos.referenceTo(target.dict);
    if (parentRef == null) {
      throw ArgumentError(
        'target annotation is not an indirect object; '
        'save and reopen the document before replying to a fresh one',
      );
    }
    final nm = name ?? _generateAnnotationName();
    final when = createdAt ?? DateTime.now();
    final dict = CosDictionary({
      'Type': const CosName('Annot'),
      'Subtype': const CosName('Text'),
      'Rect': _rectArray(target.rect),
      'F': const CosInteger(4),
      'IRT': parentRef,
      'RT': const CosName('R'),
      'Contents': CosString.fromText(contents),
      'NM': CosString.fromText(nm),
      'CreationDate': CosString.fromText(pdfFormatDate(when)),
      'M': CosString.fromText(pdfFormatDate(when)),
    });
    if (author != null && author.isNotEmpty) {
      dict['T'] = CosString.fromText(author);
    }
    if (subject != null && subject.isNotEmpty) {
      dict['Subj'] = CosString.fromText(subject);
    }
    _addThreadAnnotation(pageIndex, dict);
    return nm;
  }

  /// Records review/marked [state] on [target]'s thread by adding a state
  /// reply (§12.5.6.2): a `/Text` annotation with /IRT → [target], empty
  /// /Contents, and /State + /StateModel. Returns its /NM.
  ///
  /// The thread's *current* state is the newest such reply
  /// ([PdfCommentThread.state]); set a new state to change it rather than
  /// editing the old reply, so the history (who set what, when) survives -
  /// which is exactly how Acrobat's review workflow stores it.
  String setReviewState(
    int pageIndex,
    PdfAnnotation target,
    PdfReviewState state, {
    String? author,
    DateTime? at,
    String? name,
  }) {
    final parentRef = document.cos.referenceTo(target.dict);
    if (parentRef == null) {
      throw ArgumentError(
        'target annotation is not an indirect object; '
        'save and reopen the document before setting its state',
      );
    }
    final nm = name ?? _generateAnnotationName();
    final when = at ?? DateTime.now();
    final dict = CosDictionary({
      'Type': const CosName('Annot'),
      'Subtype': const CosName('Text'),
      'Rect': _rectArray(target.rect),
      'F': const CosInteger(4),
      'IRT': parentRef,
      'RT': const CosName('R'),
      // §12.5.6.2: a state annotation's /Contents shall be empty
      'Contents': CosString.fromText(''),
      'State': CosString.fromText(state.pdfName),
      'StateModel': CosString.fromText(state.modelName),
      'NM': CosString.fromText(nm),
      'CreationDate': CosString.fromText(pdfFormatDate(when)),
      'M': CosString.fromText(pdfFormatDate(when)),
    });
    if (author != null && author.isNotEmpty) {
      dict['T'] = CosString.fromText(author);
    }
    _addThreadAnnotation(pageIndex, dict);
    return nm;
  }

  /// Marks [target]'s thread resolved - review state `Completed`
  /// ([PdfCommentThread.isResolved]). A convenience over [setReviewState].
  String resolveThread(
    int pageIndex,
    PdfAnnotation target, {
    String? author,
    DateTime? at,
    String? name,
  }) =>
      setReviewState(
        pageIndex,
        target,
        PdfReviewState.completed,
        author: author,
        at: at,
        name: name,
      );

  /// Reopens [target]'s thread - review state `None`, clearing a prior
  /// resolution. A convenience over [setReviewState].
  String reopenThread(
    int pageIndex,
    PdfAnnotation target, {
    String? author,
    DateTime? at,
    String? name,
  }) =>
      setReviewState(
        pageIndex,
        target,
        PdfReviewState.none,
        author: author,
        at: at,
        name: name,
      );

  /// Stages an appearance-less thread annotation (reply or state) and
  /// links it into the page's /Annots. Unlike [_addAnnotation] it writes
  /// no /AP: replies and state replies carry no page graphics. The caller
  /// is responsible for the /NM (both creators stamp one).
  void _addThreadAnnotation(int pageIndex, CosDictionary annot) {
    _linkAnnotation(pageIndex, _updater.addObject(annot), visual: false);
  }
}
