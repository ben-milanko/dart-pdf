import 'package:flutter/foundation.dart';
import 'package:pdf_document/pdf_document.dart';

/// A clipboard for copied annotations, shared across documents: copy or cut
/// annotations in one [PdfEditingController], then paste them back into the
/// same document - or into a different open document tab, since every
/// controller shares the process-wide [instance] by default.
///
/// The payload is a list of [PdfAnnotationSnapshot]s: each one is fully
/// detached from the document it was captured in (its dictionary and every
/// object it references - appearance streams included - copied inline), so a
/// paste never depends on the source document staying open, on the revision
/// it was copied from surviving an undo, or even on the tab it came from
/// still existing. That is what lets an annotation copied in one tab paste
/// into another: PDF annotations don't round-trip the OS clipboard, so
/// without a shared clipboard the target tab has nothing to paste.
///
/// A [ChangeNotifier] so paste affordances can enable and disable live as the
/// clipboard fills and clears. Controllers default to the shared [instance] so
/// a copy in one tab pastes into another with no wiring; pass a private
/// clipboard to a controller to isolate it (tests do this).
class PdfAnnotationSnapshotClipboard extends ChangeNotifier {
  /// The process-wide clipboard every [PdfEditingController] shares by
  /// default, so annotations copied in one document tab can be pasted into
  /// another.
  static final PdfAnnotationSnapshotClipboard instance =
      PdfAnnotationSnapshotClipboard();

  List<PdfAnnotationSnapshot> _snapshots = const [];
  Object? _sourceOwner;
  int _sourcePage = -1;
  int _pasteCount = 0;

  /// The captured annotations waiting to be pasted (empty when the
  /// clipboard is empty).
  List<PdfAnnotationSnapshot> get snapshots => _snapshots;

  /// How many annotations the clipboard currently holds (0 when empty).
  int get length => _snapshots.length;

  /// Whether there are annotations waiting to be pasted.
  bool get isNotEmpty => _snapshots.isNotEmpty;

  /// Whether the clipboard is empty.
  bool get isEmpty => _snapshots.isEmpty;

  /// The controller that filled the clipboard, held only to compare identity
  /// (never to read from - the snapshots are detached, and the owner may
  /// have been disposed with its tab). Paired with [sourcePage] it answers
  /// "is this paste landing back on the page the copy came from?", which
  /// decides whether the position cascade kicks in.
  Object? get sourceOwner => _sourceOwner;

  /// The page index the copy came from within [sourceOwner]'s document, or
  /// -1 when the clipboard is empty. Meaningless without [sourceOwner]:
  /// page 3 of another tab's document is not the page this one copied from.
  int get sourcePage => _sourcePage;

  /// Pastes since the clipboard was last filled - each one cascades the
  /// default paste position by another 12pt so copies don't stack. Counted
  /// on the clipboard, not per controller, so the cascade keeps stepping as
  /// one copy is pasted repeatedly, wherever it lands.
  int get pasteCount => _pasteCount;

  /// Fills the clipboard with [snapshots] copied from [sourcePage] of
  /// [owner]'s document, replacing any previous contents (and resetting the
  /// paste cascade) and notifying listeners.
  void set(
    List<PdfAnnotationSnapshot> snapshots, {
    required Object owner,
    required int sourcePage,
  }) {
    _snapshots = List.unmodifiable(snapshots);
    _sourceOwner = owner;
    _sourcePage = sourcePage;
    _pasteCount = 0;
    notifyListeners();
  }

  /// Records that the contents were pasted once more, stepping the position
  /// cascade. Does not notify: what can be pasted has not changed, and a
  /// paste already rebuilds its own controller.
  void markPasted() => _pasteCount++;

  /// Whether a paste onto page [pageIndex] of [owner]'s document is landing
  /// back where the copy came from - the case that has to cascade on the
  /// very first paste so the copy doesn't sit exactly on its source.
  bool isSource(Object owner, int pageIndex) =>
      identical(owner, _sourceOwner) && pageIndex == _sourcePage;

  /// Empties the clipboard (a no-op, no notification, when already empty).
  void clear() {
    if (_snapshots.isEmpty) return;
    _snapshots = const [];
    _sourceOwner = null;
    _sourcePage = -1;
    _pasteCount = 0;
    notifyListeners();
  }
}
