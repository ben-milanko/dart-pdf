import 'package:pdf_cos/pdf_cos.dart';

import 'annotation.dart';
import 'document.dart';

/// A review or marked state an annotation can be put in (§12.5.6.2,
/// Tables 178–179). Each value names both the /State string and the
/// /StateModel family it belongs to.
///
/// The [PdfReviewModel.review] family records a reviewer's verdict on a
/// comment; the [PdfReviewModel.marked] family is a simple flag. The
/// comment editor writes a state by adding a dedicated reply annotation
/// (`PdfCommentEditing.setReviewState`), and a thread's *current* state is
/// the most recent such reply ([PdfCommentThread.state]).
enum PdfReviewState {
  accepted('Accepted', PdfReviewModel.review),
  rejected('Rejected', PdfReviewModel.review),
  cancelled('Cancelled', PdfReviewModel.review),
  completed('Completed', PdfReviewModel.review),
  none('None', PdfReviewModel.review),
  marked('Marked', PdfReviewModel.marked),
  unmarked('Unmarked', PdfReviewModel.marked);

  const PdfReviewState(this.pdfName, this.model);

  /// The /State string written to (and read from) the dictionary.
  final String pdfName;

  /// Which /StateModel family this state belongs to.
  final PdfReviewModel model;

  /// The /StateModel string (`Review` or `Marked`).
  String get modelName => model.pdfName;

  /// The state for a (/State, /StateModel) pair, or null when unrecognized.
  static PdfReviewState? fromNames(String? state, String? model) {
    if (state == null) return null;
    for (final value in values) {
      if (value.pdfName == state &&
          (model == null || value.modelName == model)) {
        return value;
      }
    }
    return null;
  }
}

/// The two /StateModel families (§12.5.6.2).
enum PdfReviewModel {
  review('Review'),
  marked('Marked');

  const PdfReviewModel(this.pdfName);
  final String pdfName;
}

/// One state change recorded in a thread: a reply annotation carrying a
/// /State + /StateModel (§12.5.6.2). The current state of a comment is the
/// newest entry by [at].
class PdfReviewStateEntry {
  const PdfReviewStateEntry({
    required this.annotation,
    required this.state,
    this.author,
    this.at,
  });

  /// The state annotation itself (its /NM is the sync identity).
  final PdfAnnotation annotation;

  /// The state it set.
  final PdfReviewState state;

  /// Who set it (/T).
  final String? author;

  /// When it was set (/CreationDate, falling back to /M).
  final DateTime? at;
}

/// One comment in a thread: an annotation with text plus its direct
/// replies and the state history recorded against it (§12.5.6.x).
///
/// A comment is built from any markup annotation that is not itself a
/// *state* annotation; replies link to their parent through /IRT. The root
/// of a thread is a comment with no content parent.
class PdfComment {
  PdfComment._(this.annotation);

  /// The annotation carrying this comment's text.
  final PdfAnnotation annotation;

  /// Direct replies, oldest first.
  final List<PdfComment> replies = [];

  /// State changes recorded against this comment, oldest first.
  final List<PdfReviewStateEntry> stateHistory = [];

  /// The /NM identity (every editor-authored comment has one).
  String? get name => annotation.name;

  /// The reply/comment text (/Contents).
  String get text => annotation.contents ?? '';

  /// The author (/T).
  String? get author => annotation.author;

  /// When the comment was written (/CreationDate, falling back to /M).
  DateTime? get createdAt =>
      annotation.creationDate ?? annotation.modificationDate;

  /// The most recent state set on this comment, or null when none.
  PdfReviewStateEntry? get currentState =>
      stateHistory.isEmpty ? null : stateHistory.last;

  /// Whether this comment (or any descendant) carries replies or state.
  bool get hasThread => replies.isNotEmpty || stateHistory.isNotEmpty;

  /// This comment and all its descendants in document/pre-order.
  List<PdfComment> get flattened {
    final out = <PdfComment>[this];
    for (final reply in replies) {
      out.addAll(reply.flattened);
    }
    return out;
  }
}

/// A reply thread rooted at one markup annotation (§12.5.6.x), with its
/// replies linked by /IRT and its review state recorded as state replies.
///
/// Assemble the threads on a page with [forPage]; find the thread a given
/// annotation belongs to with [of]. The model is read-only — author and
/// edit threads through `PdfCommentEditing` on the editor.
class PdfCommentThread {
  PdfCommentThread._(this.root);

  /// The comment at the head of the thread.
  final PdfComment root;

  /// The root's /NM identity.
  String? get name => root.name;

  /// Every comment in the thread (root first), pre-order.
  List<PdfComment> get comments => root.flattened;

  /// The number of replies under the root (the whole thread minus the
  /// root itself).
  int get replyCount => comments.length - 1;

  /// The thread's current review state: the newest state recorded on any
  /// comment in the thread, or null when none has been set.
  PdfReviewStateEntry? get state {
    PdfReviewStateEntry? latest;
    for (final comment in comments) {
      final entry = comment.currentState;
      if (entry == null) continue;
      if (latest == null ||
          (entry.at != null &&
              (latest.at == null || entry.at!.isAfter(latest.at!)))) {
        latest = entry;
      }
    }
    return latest;
  }

  /// Whether the thread has been resolved — its current state is
  /// `Completed` (see `PdfCommentEditing.resolveThread`).
  bool get isResolved => state?.state == PdfReviewState.completed;

  /// The reply threads on page [pageIndex]: one [PdfCommentThread] per
  /// root markup annotation that carries replies or state, plus single
  /// roots that have neither (so every comment surfaces exactly once).
  ///
  /// Pass [rootsWithThreadsOnly] true to keep only roots that actually
  /// have replies or a recorded state.
  static List<PdfCommentThread> forPage(PdfDocument document, int pageIndex,
      {bool rootsWithThreadsOnly = false}) {
    final cos = document.cos;
    final annotations = document.page(pageIndex).annotations;

    // index every annotation by its dictionary identity, so /IRT (an
    // indirect reference to the parent dict) links without depending on
    // /NM being present
    final byDict = <CosDictionary, PdfAnnotation>{};
    for (final annotation in annotations) {
      byDict[annotation.dict] = annotation;
    }
    CosDictionary? parentDictOf(PdfAnnotation annotation) {
      final irt = cos.resolve(annotation.dict['IRT']);
      return irt is CosDictionary ? irt : null;
    }

    // content comments keyed by dict; state annotations handled separately
    final comments = <CosDictionary, PdfComment>{};
    final stateAnnotations = <PdfAnnotation>[];
    for (final annotation in annotations) {
      if (const {'Popup', 'Widget', 'Link'}.contains(annotation.subtype)) {
        continue;
      }
      if (annotation.isStateAnnotation) {
        stateAnnotations.add(annotation);
      } else {
        comments[annotation.dict] = PdfComment._(annotation);
      }
    }

    // link replies to their parent comment; collect roots
    final roots = <PdfComment>[];
    for (final comment in comments.values) {
      final parentDict = parentDictOf(comment.annotation);
      final parent = parentDict == null ? null : comments[parentDict];
      if (parent != null && !identical(parent, comment)) {
        parent.replies.add(comment);
      } else {
        roots.add(comment);
      }
    }

    // attach state history to the comment it refers to (or, failing that,
    // the root of its chain so the verdict still surfaces)
    for (final annotation in stateAnnotations) {
      final state = PdfReviewState.fromNames(
          annotation.reviewState, annotation.stateModel);
      if (state == null) continue;
      final parentDict = parentDictOf(annotation);
      final target = parentDict == null ? null : comments[parentDict];
      (target ?? (roots.isNotEmpty ? roots.first : null))
          ?.stateHistory
          .add(PdfReviewStateEntry(
            annotation: annotation,
            state: state,
            author: annotation.author,
            at: annotation.creationDate ?? annotation.modificationDate,
          ));
    }

    int byDate(DateTime? a, DateTime? b) {
      if (a == null && b == null) return 0;
      if (a == null) return -1;
      if (b == null) return 1;
      return a.compareTo(b);
    }

    void sort(PdfComment comment) {
      comment.replies.sort((a, b) => byDate(a.createdAt, b.createdAt));
      comment.stateHistory.sort((a, b) => byDate(a.at, b.at));
      for (final reply in comment.replies) {
        sort(reply);
      }
    }

    final threads = <PdfCommentThread>[];
    for (final root in roots) {
      sort(root);
      final thread = PdfCommentThread._(root);
      if (rootsWithThreadsOnly && !root.hasThread) continue;
      threads.add(thread);
    }
    return threads;
  }

  /// The thread on page [pageIndex] that [annotation] belongs to (as a
  /// root or anywhere in the reply tree), or null when it is not part of
  /// any (e.g. a link or widget).
  static PdfCommentThread? of(
      PdfDocument document, int pageIndex, PdfAnnotation annotation) {
    for (final thread in forPage(document, pageIndex)) {
      for (final comment in thread.comments) {
        if (identical(comment.annotation.dict, annotation.dict)) return thread;
      }
    }
    return null;
  }
}
