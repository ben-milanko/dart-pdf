import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';

/// One open document. Holds its own edit session and viewer controller so
/// switching tabs preserves edits, undo history, and scroll position.
///
/// A tab is one of four kinds: a normal editable [document], a [loading]
/// placeholder, an [error] placeholder, or a two-file [comparison].
class DocumentTab {
  DocumentTab.loading(
      {required this.title,
      this.originPath,
      this.originBookmark,
      this.cachePath})
      : session = null,
        viewer = null,
        savedLength = 0,
        error = null,
        compareBefore = null,
        compareAfter = null,
        isLoading = true;

  DocumentTab.document({
    required this.title,
    required Uint8List bytes,
    required PdfEditingPreferences preferences,
    this.originPath,
    this.originBookmark,
    this.cachePath,
    bool initiallyDirty = false,
  })  : session = PdfEditingController(bytes, preferences: preferences),
        viewer = PdfViewerController(),
        savedLength = initiallyDirty ? -1 : bytes.length,
        error = null,
        compareBefore = null,
        compareAfter = null,
        isLoading = false;

  /// A document whose bytes are already in hand but not yet parsed: the
  /// expensive [PdfEditingController] construction (a synchronous PDF open,
  /// noticeable for large files) is postponed until this tab is first
  /// activated. Opening a batch of files this way keeps only the tab the user
  /// is looking at on the parse hot path; the rest materialize as they are
  /// visited. See [EditorScreen] materialization.
  DocumentTab.deferred({
    required this.title,
    required Uint8List bytes,
    this.originPath,
    this.originBookmark,
    this.cachePath,
  })  : session = null,
        viewer = null,
        savedLength = bytes.length,
        error = null,
        compareBefore = null,
        compareAfter = null,
        isLoading = false,
        deferredBytes = bytes;

  DocumentTab.error({required this.title, required this.error})
      : session = null,
        viewer = null,
        originPath = null,
        originBookmark = null,
        cachePath = null,
        savedLength = 0,
        compareBefore = null,
        compareAfter = null,
        isLoading = false;

  /// A document-comparison tab hosting a [PdfComparisonView] over two files.
  DocumentTab.comparison({
    required this.title,
    required Uint8List before,
    required Uint8List after,
  })  : session = null,
        viewer = null,
        error = null,
        originPath = null,
        originBookmark = null,
        cachePath = null,
        savedLength = 0,
        compareBefore = before,
        compareAfter = after,
        isLoading = false;

  /// The filename shown by the tab. Save As updates it to the chosen file's
  /// name while keeping this tab's editing and viewer sessions alive.
  String title;
  final String? error;
  final bool isLoading;

  /// The unparsed bytes of a [DocumentTab.deferred] tab, held until the tab is
  /// activated and its edit session is built. Null on every other kind.
  Uint8List? deferredBytes;

  /// True while this tab holds bytes it has not yet parsed into a session.
  bool get isDeferred => deferredBytes != null;

  /// Guards against kicking off materialization more than once while the
  /// placeholder frame is still on screen (build can run several times).
  bool materializing = false;

  /// The writable on-disk origin (desktop), when the document was opened from
  /// a real path. Save writes back here; updated when a Save As lands on a new
  /// path. Null means save-as only.
  String? originPath;

  /// macOS security-scoped bookmark for [originPath], when available.
  String? originBookmark;

  /// The app-private byte snapshot backing a mobile pick (see pdf_cache.dart),
  /// or null when the document has a real [originPath] (desktop) or can't be
  /// snapshotted (web). Carried so the tab re-persists into the session and
  /// keeps its Recent entry reopenable across edits. Written just after open on
  /// mobile, once the snapshot is on disk, so it stays off the open hot path.
  String? cachePath;

  /// Byte length of the last-saved revision. Revisions are byte prefixes of one
  /// buffer, so length uniquely identifies a revision - the document is dirty
  /// when the current [PdfEditingController.bytes] length differs from this.
  int savedLength;

  /// The two documents a comparison tab diffs; null on every other tab.
  final Uint8List? compareBefore;
  final Uint8List? compareAfter;

  bool get isComparison => compareAfter != null;

  /// True when the document has edits not yet written to disk.
  bool get isDirty => session != null && session!.bytes.length != savedLength;

  /// True until this document has been saved at least once. A brand-new
  /// document (created via New, [initiallyDirty]) has no saved baseline, so
  /// it is savable even before the first edit; [markSaved] establishes the
  /// baseline and clears this.
  bool get isUnsaved => session != null && savedLength < 0;

  /// Marks the current revision as the saved baseline (call after a save).
  void markSaved() {
    if (session != null) savedLength = session!.bytes.length;
  }

  /// Null for an error or comparison tab. Preferences are owned by the app,
  /// so they outlive every tab.
  final PdfEditingController? session;
  final PdfViewerController? viewer;

  /// A stable identity per open document, used by the shells to remember the
  /// scroll position and zoom across reopens.
  String get documentId => title;

  void dispose() {
    session?.dispose();
    viewer?.dispose();
  }
}
