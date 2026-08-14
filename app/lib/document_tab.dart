import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';

/// A detached snapshot used to move a live document into another native
/// window.
///
/// The current revision and its saved baseline travel together, preserving
/// the dirty/unsaved state and save destination. The receiving window creates
/// fresh editor and viewer controllers, so undo history and viewport state do
/// not cross the window boundary.
@immutable
class DocumentHandoff {
  const DocumentHandoff({
    required this.bytes,
    required this.title,
    required this.savedLength,
    this.originPath,
    this.originBookmark,
    this.originToken,
    this.cachePath,
  });

  final Uint8List bytes;
  final String title;
  final int savedLength;
  final String? originPath;
  final String? originBookmark;
  final String? originToken;
  final String? cachePath;

  bool get isDirty => bytes.length != savedLength;
}

/// One open document. Holds its own edit session and viewer controller so
/// switching tabs preserves edits, undo history, and scroll position.
///
/// A tab is one of five kinds: a normal editable [document], a [loading]
/// placeholder, a read-only [preview] painting from a progressive first paint
/// while the full bytes stream in, an [error] placeholder, or a two-file
/// [comparison].
class DocumentTab {
  DocumentTab.loading(
      {required this.title,
      this.originPath,
      this.originBookmark,
      this.originToken,
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
    this.originToken,
    this.cachePath,
    bool initiallyDirty = false,
    int? savedLength,
  })  : session = PdfEditingController(bytes, preferences: preferences),
        viewer = PdfViewerController(),
        // Normally the opened bytes *are* the saved baseline. Crash recovery is
        // the exception: it reopens a document at the revision that was in
        // flight, and passes the baseline the lost tab had, so the recovered
        // tab comes back dirty in exactly the same way (see autosave.dart).
        savedLength = savedLength ?? (initiallyDirty ? -1 : bytes.length),
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

  /// A file-backed document known only by its path (session restore), with no
  /// bytes read yet: reading and rendering are postponed until the tab is first
  /// shown, when it opens *progressively* (see [EditorScreen] materialization).
  /// This keeps launch cheap even when the last session held several big
  /// cloud-synced files - only the active tab pulls any bytes, and it first-
  /// paints from ranges rather than waiting on a whole-file read.
  DocumentTab.deferredPath({
    required this.title,
    this.originPath,
    this.originBookmark,
    this.cachePath,
  })  : session = null,
        viewer = null,
        savedLength = 0,
        error = null,
        compareBefore = null,
        compareAfter = null,
        isLoading = false {
    _deferredPath = true;
  }

  /// A read-only first paint from a progressive open: the ranged loader has
  /// assembled just enough of the file to render (a sparse buffer - live
  /// objects present, free space still zero), so the viewer paints in ~1-2 s
  /// even from a slow cloud-synced file while the complete bytes stream in
  /// behind it. [progress] tracks that background full read (0-1); [cancel]
  /// aborts both the read and any in-flight ranged fetch when the tab closes.
  /// When the full bytes land the app swaps this for a real
  /// [DocumentTab.document] (see EditorScreen), so edit affordances (Save,
  /// Digitally sign) light up only once the whole file is in hand.
  DocumentTab.preview({
    required this.title,
    required PdfDocument document,
    required Uint8List previewBytes,
    required this.progress,
    required this.cancel,
    this.originPath,
    this.originBookmark,
    this.originToken,
    this.cachePath,
  })  : session = null,
        viewer = PdfViewerController(),
        previewDocument = document,
        _previewBytes = previewBytes,
        savedLength = 0,
        error = null,
        compareBefore = null,
        compareAfter = null,
        isLoading = false;

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

  bool _deferredPath = false;

  /// True while this tab knows only its path and has read no bytes yet - it
  /// opens progressively the first time it is shown (see [DocumentTab.deferredPath]).
  bool get isDeferredPath => _deferredPath;

  /// The read-only document rendered during a progressive first paint (see
  /// [DocumentTab.preview]); null on every other kind.
  PdfDocument? previewDocument;

  /// The sparse buffer the [previewDocument] renders from.
  Uint8List? _previewBytes;

  /// The sparse bytes a [preview] tab paints from until the full read lands.
  Uint8List? get previewBytes => _previewBytes;

  /// Progress (0-1) of the background full read behind a [preview] first paint.
  ValueNotifier<double>? progress;

  /// Cancels the progressive load (ranged fetch + background full read) when a
  /// [preview] tab is closed before its full bytes arrive.
  PdfCancelToken? cancel;

  /// True while this tab is a read-only progressive first paint awaiting its
  /// complete bytes.
  bool get isPreview => previewDocument != null;

  /// Guards against kicking off materialization more than once while the
  /// placeholder frame is still on screen (build can run several times).
  bool materializing = false;

  /// The writable on-disk origin (desktop), when the document was opened from
  /// a real path. Save writes back here; updated when a Save As lands on a new
  /// path. Null means save-as only.
  String? originPath;

  /// macOS security-scoped bookmark for [originPath], when available.
  String? originBookmark;

  /// Opaque native reference to a mobile pick's *original* file (Android
  /// persisted `content://` Uri; iOS security-scoped bookmark), when the tab
  /// was opened progressively through the mobile reference picker (#364). Used
  /// to build the ranged byte source and the full-read fallback while the
  /// progressive first paint is on screen; null on desktop/web and after the
  /// tab swaps to its complete, snapshotted bytes.
  String? originToken;

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
    // Closing a still-loading preview cancels its ranged fetch and background
    // full read so a closed tab stops pulling bytes.
    cancel?.cancel();
    progress?.dispose();
    session?.dispose();
    viewer?.dispose();
  }
}
