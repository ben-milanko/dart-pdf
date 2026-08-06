import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';

import '../page_geometry.dart';
import '../renderer.dart';
import 'digital_signature.dart';
import 'editing_measure.dart';
import 'editing_page_clipboard.dart';
import 'editing_preferences.dart';
import 'editing_snapshot_clipboard.dart';
import 'editing_tool_behavior.dart';
import 'line_style.dart';
import 'editing_stamps.dart';
import 'text_prompt.dart';
import 'thumbnail_cache.dart';

PdfEmbeddableImage _decodeEmbeddableImage(Uint8List bytes) =>
    PdfEmbeddableImage.decode(bytes);

Map<String, Object?> _replaceDocumentColorsOnWorker(
  Map<String, Object?> message,
) {
  final document = PdfDocument.open(
    message['bytes']! as Uint8List,
    password: message['password']! as String,
  );
  final editor = PdfEditor(document);
  final count = editor.replaceColorsOnPages(
    (message['pages']! as List).cast<int>(),
    finds: (message['finds']! as List).cast<int>(),
    replace: message['replace']! as int,
    tolerance: message['tolerance']! as int,
    fill: message['fill']! as bool,
    stroke: message['stroke']! as bool,
    transparent: message['transparent']! as bool,
  );
  if (count == 0 || !editor.hasChanges) {
    return const {'count': 0};
  }
  return {
    'count': count,
    'bytes': editor.save(),
    'visualPages': editor.impact.visualPages?.toList(),
    'contentPages': editor.impact.contentPages?.toList(),
    'annotationPages': editor.impact.annotationPages?.toList(),
    'pageStructureChanged': editor.impact.pageStructureChanged,
    'destructive': editor.impact.destructive,
  };
}

Map<String, String> _normalizeStampTemplateValues(Map<String, String> values) {
  final normalized = <String, String>{};
  for (final entry in values.entries) {
    final key = entry.key.trim().toLowerCase();
    if (key.isEmpty) continue;
    normalized[key] = entry.value;
  }
  return Map.unmodifiable(normalized);
}

/// The annotation tools a [PdfEditingController] can arm.
///
/// Text markups (highlight, underline, strike-out, squiggly) are not
/// tools - they act on the viewer's current text selection through
/// [PdfEditingController.addMarkup]. [highlight] is the Draw group's
/// freehand highlighter.
enum PdfEditTool {
  /// Tap to select an annotation; drag it to move, drag its handles to
  /// resize.
  select,

  /// Freehand drawing. Strokes accumulate in the controller until
  /// [PdfEditingController.finishInk] commits them as one Ink annotation.
  ink,

  /// Freehand highlight. Like [ink], but with a separate highlighter style
  /// scope so it defaults to a broad translucent yellow stroke and remembers
  /// later user changes independently of the pen.
  highlight,

  /// Drag (or tap) over ink strokes to delete them. Whole-annotation:
  /// every Ink annotation the pointer crosses is removed; one swipe is
  /// one undo step. Pointer-kind rules mirror the ink tool's
  /// ([PdfEditingController.fingerDrawsInk]): in stylus mode only the
  /// pen erases and fingers keep scrolling.
  eraser,

  /// Drag out a rectangle (/Square) annotation.
  rectangle,

  /// Drag out an ellipse (/Circle) annotation.
  ellipse,

  /// Drag a straight line (/Line) annotation.
  line,

  /// Drag a straight line with a closed arrow ending (/Line /LE).
  arrow,

  /// Drag to create a sampled multi-segment /PolyLine annotation.
  polyline,

  /// Drag to create a sampled closed /Polygon annotation.
  polygon,

  /// Drag out a rectangular cloudy /Polygon annotation.
  cloudPolygon,

  /// Drag a straight segment whose real-world length is shown live and
  /// stamped as a /Line measurement (§12.9). Needs an active
  /// [PdfEditingController.measurementScale].
  measureDistance,

  /// Place a multi-segment /PolyLine measurement whose running real-world
  /// perimeter (sum of segment lengths) is shown live.
  measurePerimeter,

  /// Place a closed /Polygon measurement whose real-world area is shown
  /// live.
  measureArea,

  /// Drag a straight segment read as a slope (rise/run): the inclination
  /// above horizontal, in degrees, is shown live and stamped as a /Line
  /// takeoff measurement.
  measureSlope,

  /// Click three points - arm end, vertex, arm end - to measure the
  /// interior angle (degrees) at the middle vertex. Auto-finishes on the
  /// third click; stamped as a /PolyLine takeoff measurement.
  measureAngle,

  /// Click three points on a circular arc - start, a point on the arc, end
  /// - to measure its swept length. Auto-finishes on the third click;
  /// stamped as a /PolyLine takeoff measurement.
  measureArc,

  /// Place a closed /Polygon, then enter a depth, to measure a volume
  /// (area × depth). Stamped as a /Polygon takeoff measurement carrying the
  /// depth.
  measureVolume,

  /// Drag a straight segment of known real-world length to calibrate the
  /// [PdfEditingController.measurementScale]. On release the editor asks
  /// how long the drawn segment is and derives the scale from it (the
  /// "two-point calibration" flow); nothing is stamped on the page.
  calibrate,

  /// Drag out a box, then type the text shown inside it (/FreeText).
  freeText,

  /// Drag from the terminus you're pointing at to where the text box goes,
  /// then type the text (a /FreeText callout with a leader line and arrow,
  /// like Bluebeam's Callout tool).
  callout,

  /// Tap to place a sticky note (/Text).
  note,

  /// Rubber stamps (/Stamp). With a [PdfEditingController.activeStamp]
  /// a tap places it; otherwise drag out a box and type the caption.
  stamp,

  /// Tap to drop a check-mark and keep a running tally, like Bluebeam's
  /// count tool. Each tap places a /Stamp check-mark annotation (so it can
  /// be moved, resized, and deleted); [PdfEditingController.checkMarkCount]
  /// is the live total.
  count,

  /// Tap to place the saved hand-drawn signature
  /// ([PdfEditingPreferences.signature]) as an Ink annotation.
  signature,

  /// Insert a raster image (PNG or JPEG). Tapping places it at a default
  /// size; dragging out a box fits it within the box. The picked image
  /// comes from [PdfViewer.imagePicker] - **that callback must be wired**
  /// for this tool to do anything. Without it the stock [PdfEditingToolbar]
  /// hides the tool, and arming it directly is a no-op on tap/drag.
  /// The image becomes a /Stamp annotation, so it can be moved, resized,
  /// rotated, and deleted like any other annotation.
  image,

  /// Tap to select a page content element (text run, path, image); the
  /// selection can be deleted, text can be rewritten, and images can be
  /// replaced. Edits remove from the page's content stream itself; replacement
  /// images are inserted as movable image stamps.
  content,

  /// Interactive forms: tap a field widget to fill it (text fields open
  /// an inline editor, check boxes and radio buttons toggle, choice
  /// fields offer their options), drag on empty page area to add a new
  /// field of [PdfEditingController.newFormFieldKind], right-click a
  /// widget for rename/convert/delete.
  form,

  /// Mark regions for redaction. Drag out a rectangle (mouse from empty
  /// page area; touch long-press-drag) to mark a /Redact region, or use
  /// [PdfEditingController.addRedactionQuads] to mark the current text
  /// selection. Marks render as a hatched preview until burned with
  /// [PdfEditingController.applyRedactions], which is irreversible.
  redact,

  /// Drag out a rectangle to capture that region of the page as a raster
  /// image, like Bluebeam's Snapshot. The captured PNG is rendered through
  /// [PdfEditingController.captureSnapshot] and handed to
  /// [PdfViewer.onSnapshot] - typically to copy it to the clipboard, save,
  /// or share it; with no handler the tool does nothing. It only reads the
  /// page: no annotation or page content is written.
  snapshot,

  /// Drag out a rectangle to place a **visible digital-signature** box, the
  /// way Acrobat and Bluebeam let you draw where the signature appears. On
  /// release the host's [PdfViewer.onPlaceSignature] handler runs with the
  /// page and the box (in PDF user space) to collect an identity/appearance
  /// and cryptographically sign into that rectangle
  /// (via [PdfEditingController.addKeylessSignature] et al. with a
  /// [PdfSignatureAppearance]). With no handler the tool does nothing.
  signatureBox,

  /// Drag out a rectangle (or use the current text selection) to add a
  /// hyperlink. On release the Add-link dialog collects the target - an
  /// external URL or a page in this same document - and a /Link annotation
  /// is created over the region ([PdfEditingController.addLink]).
  link,
}

/// Text-markup kinds for [PdfEditingController.addMarkup].
enum PdfMarkupKind { highlight, underline, strikeOut, squiggly }

/// Where a hyperlink created by the link tool points: either an external
/// [PdfLinkTarget.uri] (a web address, `mailto:`, or app scheme) or an
/// in-document jump to a [PdfLinkTarget.page] (a whole-page fit) or a more
/// specific [PdfLinkTarget.destination] (a position, zoom, or rectangle).
///
/// Consumed by [PdfEditingController.addLink] and
/// [PdfEditingController.addLinkToSelection]; produced by the Add-link dialog
/// ([showPdfAddLinkDialog]).
class PdfLinkTarget {
  const PdfLinkTarget._(this.uri, this.page, this.destination);

  /// An external link to [uri].
  const PdfLinkTarget.uri(String uri) : this._(uri, null, null);

  /// An internal link to the top of [page] (zero-based), fit to the window.
  const PdfLinkTarget.page(int page) : this._(null, page, null);

  /// An internal link to an explicit [destination] (a specific view).
  const PdfLinkTarget.destination(PdfExplicitDestination destination)
      : this._(null, null, destination);

  /// The external URI, or null for an internal link.
  final String? uri;

  /// The zero-based target page for a whole-page internal link, or null.
  final int? page;

  /// The explicit destination for a precise internal link, or null.
  final PdfExplicitDestination? destination;

  /// Whether this points outside the document (a [uri]).
  bool get isExternal => uri != null;
}

/// Host veto over which annotations the editing UI may change - see
/// [PdfEditingController.canEditAnnotation].
typedef PdfAnnotationEditPredicate = bool Function(PdfAnnotation annotation);

/// The field kinds the form tool can create (and convert fields to) -
/// the subset of [PdfFieldType] with creation support in [PdfEditor].
enum PdfFormFieldKind { text, checkBox, pushButton }

/// The text styling of a form text field, read from its /DA, /Q and /Ff -
/// what the form-field style controls reflect and edit
/// ([PdfEditingController.selectedFormFieldStyle]).
class PdfFormFieldStyle {
  const PdfFormFieldStyle({
    required this.font,
    required this.size,
    required this.autoSize,
    required this.color,
    required this.align,
    required this.multiline,
  });

  /// The base-14 face the field's /DA names, mapped leniently (an embedded
  /// /DR font maps to Helvetica). Carries the bold/italic state the style
  /// toggles reflect.
  final PdfStandardFont font;

  /// The /DA font size in points; when [autoSize] this is a readable
  /// stand-in (the stored size is 0).
  final double size;

  /// Whether the field auto-sizes its text (the /DA size is 0).
  final bool autoSize;

  /// The /DA text colour (opaque).
  final Color color;

  /// The /Q alignment.
  final PdfTextAlign align;

  /// Whether the field wraps over multiple lines (/Ff multiline flag).
  final bool multiline;
}

/// The byte-level shape of one editor revision transition (an edit, undo, or
/// redo), consumed by the shell to feed the render worker's incremental
/// in-place update instead of restarting it. See
/// [PdfEditingController.lastRevisionDelta].
class PdfWorkerRevisionDelta {
  const PdfWorkerRevisionDelta({
    required this.baseLength,
    required this.newLength,
    required this.changedPages,
  });

  /// Byte length of the prefix shared with the previous revision. Revisions are
  /// prefixes of one growing buffer, so the worker keeps its buffer up to here
  /// and appends the `newLength - baseLength` bytes that follow. A pure undo
  /// (shrinking to an earlier prefix) has [baseLength] == [newLength].
  final int baseLength;

  /// Byte length of the revision after the transition.
  final int newLength;

  /// Pages whose rendering the transition changed, or null when every page may
  /// have (the worker then clears its per-page caches).
  final Set<int>? changedPages;
}

/// An editing session over a PDF document: applies edits through
/// [PdfEditor], owns the resulting document revisions, and carries the
/// UI state of the editing tools (active tool, color, pending ink
/// strokes, selected annotation).
///
/// Every edit is saved as an incremental update, so each revision's bytes
/// are a strict prefix of the next. Undo and redo therefore cost nothing:
/// the controller keeps one byte buffer and a stack of revision lengths,
/// and undoing just reopens the document on a shorter view of the same
/// bytes.
///
/// Pass the controller to [PdfViewer.editing] and rebuild the viewer with
/// [document] when this controller notifies (the document object changes
/// identity on every edit):
///
/// ```dart
/// ListenableBuilder(
///   listenable: editing,
///   builder: (context, _) => PdfViewer(
///     document: editing.document,
///     controller: viewerController,
///     editing: editing,
///   ),
/// )
/// ```
class PdfEditingController extends ChangeNotifier {
  /// Field names that the stamp editor offers by default for `{{field}}`
  /// placeholders. Apps can add more names with [stampTemplateValues].
  static const stampTemplateBuiltinFields = [
    'date',
    'time',
    'datetime',
    'username',
  ];

  PdfEditingController(
    Uint8List bytes, {
    String password = '',
    PdfEditingPreferences? preferences,
    PdfPageClipboard? pageClipboard,
    PdfSnapshotClipboard? snapshotClipboard,
    PdfTrustStore? trustStore,
  })  : _bytes = bytes,
        _used = bytes.length,
        _password = password,
        _revisions = [bytes.length],
        _document = PdfDocument.open(bytes, password: password),
        _trustStore = trustStore,
        preferences = preferences ?? PdfEditingPreferences(),
        pageClipboard = pageClipboard ?? PdfPageClipboard.instance,
        snapshotClipboard =
            snapshotClipboard ?? PdfSnapshotClipboard.instance {
    this.preferences.addListener(notifyListeners);
    // rebuild paste affordances live as the shared page clipboard fills or
    // clears - from this controller or from another document tab sharing it
    this.pageClipboard.addListener(notifyListeners);
    // same for the shared snapshot clipboard, so a region captured in one tab
    // lights up Paste-as-vector in every tab
    this.snapshotClipboard.addListener(notifyListeners);
  }

  /// The persisted UI preferences that own the tool styles (stroke width,
  /// font size, opacity, colour, the stylus [PdfEditingPreferences.fingerDrawsInk]
  /// mode, and so on). Read and write them directly - `controller.preferences.
  /// strokeWidth` - since the controller no longer mirrors them. Every change
  /// is saved to the local device and restored on the next session. Pass one
  /// in to share it with the host's chrome (the sidebar-visibility flags live
  /// there too).
  final PdfEditingPreferences preferences;

  /// The clipboard whole copied/cut pages live in, shared across document
  /// tabs so pages copied from one document paste into another. Defaults to
  /// the process-wide [PdfPageClipboard.instance]; pass a private one to
  /// isolate a session. See [copyPages], [cutPages], and [pastePages].
  final PdfPageClipboard pageClipboard;

  /// The clipboard the Snapshot tool's captured vector region lives in, shared
  /// across document tabs so a region captured in one document pastes back as
  /// vector into another (rather than falling back to the raster the capture
  /// also drops on the system clipboard). Defaults to the process-wide
  /// [PdfSnapshotClipboard.instance]; pass a private one to isolate a session.
  /// See [copyVectorSnapshot] and [pasteSnapshot].
  final PdfSnapshotClipboard snapshotClipboard;

  /// The session's shared page-thumbnail cache (and its viewport-ordered
  /// render queue). Every thumbnail surface - the docked strip, the
  /// full-area page grid - draws from this one cache, so a page rendered for
  /// one is reused by the other and survives a tile scrolling out of view
  /// and back. Lives as long as the session; a new session brings a fresh,
  /// empty cache (render stamps restart at zero, so stale keys can't collide
  /// across sessions). See [PdfThumbnailCache].
  final PdfThumbnailCache thumbnailCache = PdfThumbnailCache();

  @override
  void dispose() {
    _inkTimer?.cancel();
    _flashTimer?.cancel();
    _changeFeed?.close();
    thumbnailCache.dispose();
    preferences.removeListener(notifyListeners);
    pageClipboard.removeListener(notifyListeners);
    snapshotClipboard.removeListener(notifyListeners);
    super.dispose();
  }

  final String _password;

  /// The full byte buffer; revisions are prefixes of it.
  Uint8List _bytes;

  /// Bytes of [_bytes] that hold document data. The buffer may be larger:
  /// [_commitSavedTail] over-allocates so appends amortise, so `_bytes.length`
  /// is capacity, not content.
  int _used;

  /// Byte length of each revision, oldest first. `_revisions[_cursor]`
  /// is the current one; entries past the cursor are redoable.
  final List<int> _revisions;
  int _cursor = 0;

  /// The oldest revision this session may reach with [undo]. A successful
  /// remote replay advances the floor to its newly committed revision, so a
  /// local undo can never remove collaboration state received from another
  /// session. Local revisions committed after the floor remain undoable.
  int _undoFloor = 0;

  /// Parallels [_revisions]: the consequences reported by the document
  /// mutation that produced each revision. Entry 0 is the original document
  /// and is never replayed.
  final List<PdfEditImpact> _revisionImpacts = [PdfEditImpact.none];

  /// Render stamps: how many times each page's rendering has changed.
  /// [_renderStampEpoch] counts the all-pages bumps (structural edits,
  /// unknown-page edits) so they don't iterate a large document.
  final Map<int, int> _renderStamps = {};
  int _renderStampEpoch = 0;
  final Map<int, int> _contentRenderStamps = {};
  int _contentRenderStampEpoch = 0;

  void _bumpRenderStamps(Set<int>? pages) {
    if (pages == null) {
      _renderStampEpoch++;
    } else {
      for (final page in pages) {
        _renderStamps[page] = (_renderStamps[page] ?? 0) + 1;
      }
    }
  }

  void _bumpContentRenderStamps(Set<int>? pages) {
    if (pages == null) {
      _contentRenderStampEpoch++;
    } else {
      for (final page in pages) {
        _contentRenderStamps[page] = (_contentRenderStamps[page] ?? 0) + 1;
      }
    }
  }

  /// A value that changes whenever [pageIndex]'s rendering may have
  /// changed - and stays put across edits, undo, and redo that touched
  /// other pages only. Thumbnails key their raster caches on it instead
  /// of re-rendering every page on every revision.
  int pageRenderStamp(int pageIndex) =>
      _renderStampEpoch + (_renderStamps[pageIndex] ?? 0);

  /// A value that changes only when [pageIndex]'s base page content image
  /// changed. Annotation-only edits leave it stable: the viewer paints those
  /// appearances in an overlay while thumbnails still use [pageRenderStamp].
  int pageContentRenderStamp(int pageIndex) =>
      _contentRenderStampEpoch + (_contentRenderStamps[pageIndex] ?? 0);

  /// Destructive-render epoch: bumped only by edits that *remove* existing
  /// page content (a redaction burn), as opposed to the additive ones (ink,
  /// highlights, shapes, fills) that merely lay new marks on top. The viewer
  /// keeps the on-screen raster painted across an additive edit - so a heavy
  /// page never flashes blank while the new render lands - but must drop it
  /// on a destructive one, so the removed content can't linger on screen (or
  /// in a fast-scroll preview) for even a frame. A burn recompacts the whole
  /// file (every page may have changed), so this is a single all-pages
  /// counter rather than a per-page map.
  int _destructiveStampEpoch = 0;

  /// A value that changes whenever content was *removed* from any page (see
  /// [_destructiveStampEpoch]); stable across additive edits, undo, and redo.
  /// The viewer uses it to decide whether to blank the held raster
  /// (destructive) or keep it up until the re-render lands (additive). Takes
  /// a page index to mirror [pageRenderStamp]'s shape, though the burn that
  /// drives it is always document-wide.
  int pageDestructiveStamp(int pageIndex) => _destructiveStampEpoch;

  PdfDocument _document;
  int _revisionId = 0;

  /// The document at the current revision.
  ///
  /// Do NOT use `identical(document, ...)` as a "did a revision land?" signal -
  /// compare [revisionId] instead. That the wrapper's identity happens to
  /// change on every commit today is an implementation convenience of
  /// [PdfDocument.withIncrementalUpdate], not a contract: applying a revision in
  /// place would keep the same object and silently break every such check (this
  /// is exactly what bit #395). See #414.
  PdfDocument get document => _document;

  /// Monotonic id of the current revision, bumped whenever a commit, undo, or
  /// redo lands (i.e. whenever [document] moves to a different revision - even an
  /// undo-then-redo back to the same undo cursor). Compare this rather than
  /// `identical(document, ...)` to ask "did anything commit?".
  int get revisionId => _revisionId;

  PdfWorkerRevisionDelta? _lastRevisionDelta;

  /// The byte-level shape of the most recent revision transition (edit, undo,
  /// redo) for the render worker's incremental update path, or null when the
  /// last transition cannot be applied incrementally (the initial open, a page
  /// structure change, or a redaction burn that replaced the buffer). Only
  /// meaningful the moment [document]'s identity changes; the shell reads it
  /// then and ignores it otherwise.
  PdfWorkerRevisionDelta? get lastRevisionDelta => _lastRevisionDelta;

  /// The current revision's bytes - what "save to disk" should write.
  Uint8List get bytes => Uint8List.sublistView(_bytes, 0, _revisions[_cursor]);

  /// Set once a redaction burn replaces the byte buffer: the undo history
  /// is reset to a single revision, so [_cursor] no longer reflects that
  /// the document differs from the original.
  bool _hardModified = false;

  /// Whether the current revision differs from the originally opened one.
  bool get isModified => _cursor > 0 || _hardModified;

  bool get canUndo => _cursor > _undoFloor;
  bool get canRedo => _cursor < _revisions.length - 1;

  /// Diagnostics: how many revisions the session buffer retains (every one is
  /// a byte prefix of the same grow-only buffer, so this is the undo/redo
  /// history length, not extra copies).
  int get revisionCount => _revisions.length;

  /// Diagnostics: total bytes retained by the session's grow-only buffer -
  /// the whole edit history, of which [bytes] is the current revision's
  /// prefix view. This only ever grows within a session (see the memory
  /// audit notes); watch it when chasing memory growth during editing.
  int get sessionBufferBytes => _used;

  void undo() {
    if (!canUndo) return;
    final impact = _revisionImpacts[_cursor];
    // reverting revision N un-renders exactly the pages N touched
    _bumpRenderStamps(impact.visualPages);
    _bumpContentRenderStamps(impact.contentPages);
    _cursor--;
    // The worker keeps the shared prefix and re-reads it - no bytes to append.
    _lastRevisionDelta = impact.pageStructureChanged
        ? null
        : PdfWorkerRevisionDelta(
            baseLength: _revisions[_cursor],
            newLength: _revisions[_cursor],
            changedPages: impact.visualPages,
          );
    _reopen();
    _emitAnnotationChanges(impact.annotationPages);
  }

  void redo() {
    if (!canRedo) return;
    final beforeLength = _revisions[_cursor];
    _cursor++;
    final impact = _revisionImpacts[_cursor];
    _bumpRenderStamps(impact.visualPages);
    _bumpContentRenderStamps(impact.contentPages);
    // Re-extend to the redone revision - its bytes already sit in the buffer as
    // a prefix, so the worker re-appends bytes it may already hold.
    _lastRevisionDelta = impact.pageStructureChanged
        ? null
        : PdfWorkerRevisionDelta(
            baseLength: beforeLength,
            newLength: _revisions[_cursor],
            changedPages: impact.visualPages,
          );
    // redo re-extends to a revision already in the buffer: an append
    _reopen(grew: true);
    _emitAnnotationChanges(impact.annotationPages);
  }

  void _reopen({bool grew = false}) {
    _reloadDocument(grew: grew);
    // the same /Annots slot may hold a different annotation now
    _selected.clear();
    _invalidateElements();
    notifyListeners();
  }

  /// Points [_document] at the current [bytes].
  ///
  /// Every edit is an incremental save, so a commit - and a redo, which
  /// re-extends to a revision already sitting in the buffer - only ever
  /// *appends* to what the open document already holds. Reopening from
  /// scratch there re-walks the whole `/Prev` chain, so a session of N
  /// revisions costs O(N^2) xref work and gets visibly slower the longer you
  /// edit. [CosDocument.applyIncrementalUpdate] instead stops the walk at the
  /// previous startxref and evicts only the objects the revision redefined.
  ///
  /// [grew] must be true only when [bytes] extends the currently open
  /// document. Undo shrinks the buffer and [_resetTo] replaces it outright,
  /// and neither is an append - those reopen.
  void _reloadDocument({required bool grew}) {
    if (grew && _tryApplyIncrementalUpdate()) return;
    _document = PdfDocument.open(bytes, password: _password);
    _revisionId++;
  }

  /// Debug-only sanity check behind the assert in [_tryApplyIncrementalUpdate].
  ///
  /// Every revision reaching that method is an append *by construction*: the
  /// updater writes "whole current file, then the appended objects" and the
  /// editor that produced it was built from [_document], while redo just
  /// lengthens a view over the same buffer. This guards against a *future*
  /// call site breaking that, which would silently graft one document's xref
  /// onto another's bytes ([CosDocument.applyIncrementalUpdate] only checks
  /// the length, not the content).
  ///
  /// It deliberately samples rather than comparing the whole prefix: this runs
  /// on every commit in debug builds - which is how the app is developed - and
  /// a full memcmp of a 40 MB drawing per ink stroke is exactly the cost this
  /// change set out to remove. A wrong-document mix-up differs in the header
  /// and around the previous revision's tail; a byte-identical head, tail and
  /// length is not a case any realistic bug produces.
  bool _looksLikeAppend() {
    final next = bytes;
    final current = _document.cos.bytes;
    if (next.length <= current.length) return false;
    // Views over one buffer (the redo path) are provably a prefix - no compare.
    if (identical(next.buffer, current.buffer) &&
        next.offsetInBytes == current.offsetInBytes) {
      return true;
    }
    const window = 4096;
    bool sameRange(int from, int to) {
      for (var i = from; i < to; i++) {
        if (next[i] != current[i]) return false;
      }
      return true;
    }

    final headEnd = current.length < window ? current.length : window;
    final tailStart =
        current.length - window < headEnd ? headEnd : current.length - window;
    return sameRange(0, headEnd) && sameRange(tailStart, current.length);
  }

  /// Folds the appended revision into the open document. False when it can't
  /// be done incrementally (the document was opened through xref recovery,
  /// or the appended xref chain is malformed), leaving [_document] untouched
  /// for the caller to reopen from scratch.
  bool _tryApplyIncrementalUpdate() {
    assert(_looksLikeAppend(),
        'incremental revision is not an append of the open document');
    try {
      // Reuse the same COS layer (the parse does not repeat), wrapped fresh
      // only as a convenience - [revisionId] is now the "did a revision land?"
      // signal, so the wrapper identity no longer has to change (#414).
      _document = _document.withIncrementalUpdate(bytes);
      _revisionId++;
      return true;
    } on CosParseException {
      return false;
    }
  }

  /// Runs [edit] against the current document and commits the result as a
  /// new revision. Returns false (and changes nothing) if [edit] staged no
  /// changes. Redoable revisions are discarded, like any editor's redo
  /// stack on a fresh edit.
  ///
  /// The [PdfEditor] mutation reports its own [PdfEditor.impact], so callers
  /// do not need to coordinate render caches, annotation sync, or structural
  /// selection invalidation. [pages] and [contentPages] remain only for
  /// source compatibility with older custom callers; package mutations do
  /// not use them.
  bool apply(
    void Function(PdfEditor editor) edit, {
    Iterable<int>? pages,
    Iterable<int>? contentPages,
  }) {
    final editor = PdfEditor(_document);
    edit(editor);
    if (!editor.hasChanges) return false;
    final impact = pages != null || contentPages != null
        ? PdfEditImpact.legacy(pages: pages, contentPages: contentPages)
        : editor.impact;
    final beforeLength = _revisions[_cursor];
    // Append-only: the editor hands back just the incremental update and it
    // lands in the session buffer we already own. `save()` would rebuild the
    // whole file here, so a long session re-copied O(file x revisions) bytes
    // into short-lived garbage - and `file` grows with every revision (#413).
    final tail = editor.saveTail();
    _commitSavedTail(
      tail,
      beforeLength: beforeLength,
      impact: impact,
    );
    return true;
  }

  /// Commits a revision delivered as the appended tail only, growing the
  /// session buffer in place.
  void _commitSavedTail(
    Uint8List tail, {
    required int beforeLength,
    required PdfEditImpact impact,
  }) {
    final newLength = beforeLength + tail.length;
    if (newLength > _bytes.length) {
      // Amortised doubling: a realloc every ~log(n) revisions instead of one
      // whole-file copy per revision.
      var capacity = _bytes.isEmpty ? newLength : _bytes.length;
      while (capacity < newLength) {
        capacity *= 2;
      }
      final grown = Uint8List(capacity)..setRange(0, beforeLength, _bytes);
      _bytes = grown;
    }
    _bytes.setRange(beforeLength, newLength, tail);
    _used = newLength;
    _finishRevision(
      newLength: newLength,
      beforeLength: beforeLength,
      impact: impact,
    );
  }

  /// Commits a revision delivered as a complete file (signing, and the worker
  /// batch paths, which build their own buffer).
  void _commitSavedRevision(
    Uint8List saved, {
    required int beforeLength,
    required PdfEditImpact impact,
  }) {
    _bytes = saved;
    _used = saved.length;
    _finishRevision(
      newLength: saved.length,
      beforeLength: beforeLength,
      impact: impact,
    );
  }

  void _finishRevision({
    required int newLength,
    required int beforeLength,
    required PdfEditImpact impact,
  }) {
    _revisions.removeRange(_cursor + 1, _revisions.length);
    _revisionImpacts.removeRange(_cursor + 1, _revisionImpacts.length);
    _revisions.add(newLength);
    _revisionImpacts.add(impact);
    _bumpRenderStamps(impact.visualPages);
    _bumpContentRenderStamps(impact.contentPages);
    if (impact.destructive) _destructiveStampEpoch++;
    _cursor++;
    // The incremental save appended to the previous revision, so its bytes are
    // that revision's prefix plus the new tail: the worker keeps the first
    // [beforeLength] bytes and appends the rest. A structural edit can shift
    // page indices, so fall back to a full worker restart there.
    _lastRevisionDelta = impact.pageStructureChanged
        ? null
        : PdfWorkerRevisionDelta(
            baseLength: beforeLength,
            newLength: newLength,
            changedPages: impact.visualPages,
          );
    if (_committingRemoteRevision) _undoFloor = _cursor;
    final selected = List.of(_selected);
    // the incremental save appended to the previous revision
    _reloadDocument(grew: true);
    // Existing controller mutations remap slots before committing when an
    // /Annots edit shifts them. The transaction validates that post-mutation
    // selection against the reopened revision in one place.
    _selected.clear();
    if (!impact.pageStructureChanged) {
      _selected.addAll([
        for (final slot in selected)
          if (_annotationAt(slot) != null) slot,
      ]);
    } else {
      _selectedPages.clear();
      _pageSelectionAnchor = null;
    }
    _invalidateElements();
    _emitAnnotationChanges(impact.annotationPages);
    notifyListeners();
  }

  /// Adds a certificate-backed PAdES B-B digital signature as a new editor
  /// revision.
  ///
  /// This is distinct from the hand-drawn [preferences.signature] annotation tool. The
  /// returned revision cryptographically covers every byte in the current
  /// document and embeds [identity]'s X.509 chain. It is validated before it
  /// joins the undo stack; malformed, non-matching, or non-covering output is
  /// rejected. Undo removes the signature revision and redo restores it.
  ///
  /// Further edits are legal PDF incremental revisions and leave the
  /// signature cryptographically intact, but it will then cover the signed
  /// revision rather than the new whole file.
  Future<bool> addDigitalSignature(
    PdfDigitalSignatureIdentity identity, {
    String? fieldName,
    String? signerName,
    String? reason,
    String? location,
    String? contactInfo,
    DateTime? signingTime,
    PdfSignatureAppearance? appearance,
  }) async {
    final before = bytes;
    final signed = await identity.sign(
      before,
      password: _password,
      fieldName: fieldName,
      signerName: signerName,
      reason: reason,
      location: location,
      contactInfo: contactInfo,
      signingTime: signingTime,
      appearance: appearance,
    );
    return _adoptDigitalSignature(signed, before: before);
  }

  /// Like [addDigitalSignature] but signs with a one-tap self-signed
  /// [PdfSigningIdentity] (ECDSA over SHA-256), typically minted by
  /// [PdfSigningIdentity.generate]. Produces an `adbe.pkcs7.detached`
  /// signature and goes through the same validation and undo integration.
  Future<bool> addSelfSignedSignature(
    PdfSigningIdentity identity, {
    String? fieldName,
    String? reason,
    String? location,
    String? contactInfo,
    DateTime? signingTime,
    PdfSignatureAppearance? appearance,
  }) async {
    final before = bytes;
    final signed = PdfEditor(PdfDocument.open(before, password: _password))
        .saveSelfSigned(
      identity: identity,
      fieldName: fieldName,
      reason: reason,
      location: location,
      contactInfo: contactInfo,
      signingTime: signingTime,
      appearance: appearance,
    );
    return _adoptDigitalSignature(signed, before: before);
  }

  /// Signs with a **keyless** [PdfSigningIdentity] - a short-lived
  /// Sigstore/Fulcio identity minted from an OIDC-verified email (see
  /// `fulcioSigningIdentity`). Because that certificate expires within minutes,
  /// this always produces a PAdES **B-T** signature: [timestampClient] fetches a
  /// trusted RFC 3161 timestamp so the signing time is preserved after the
  /// certificate lapses. Otherwise identical to [addSelfSignedSignature] -
  /// same validation and undo integration.
  Future<bool> addKeylessSignature(
    PdfSigningIdentity identity, {
    required PdfTimestampClient timestampClient,
    String? fieldName,
    String? reason,
    String? location,
    String? contactInfo,
    DateTime? signingTime,
    PdfSignatureAppearance? appearance,
  }) async {
    final before = bytes;
    final signed = await PdfEditor(PdfDocument.open(before, password: _password))
        .saveSelfSignedPades(
      identity: identity,
      level: PdfPadesLevel.bT,
      timestampClient: timestampClient,
      fieldName: fieldName,
      reason: reason,
      location: location,
      contactInfo: contactInfo,
      signingTime: signingTime,
      appearance: appearance,
    );
    return _adoptDigitalSignature(signed, before: before);
  }

  bool _adoptDigitalSignature(Uint8List signed, {required Uint8List before}) {
    if (signed.length <= before.length) {
      throw const FormatException(
        'The signer did not return a new incremental PDF revision.',
      );
    }
    for (var i = 0; i < before.length; i++) {
      if (signed[i] != before[i]) {
        throw const FormatException(
          'The signed PDF rewrote the current document instead of appending '
          'an incremental signature revision.',
        );
      }
    }
    final existingCount = PdfSignature.of(_document).length;
    final candidate = PdfDocument.open(signed, password: _password);
    final signatures = PdfSignature.of(candidate);
    if (signatures.length <= existingCount) {
      throw const FormatException('The signed PDF has no new signature.');
    }
    final validation = signatures.last.validate();
    if (!validation.intact || !validation.coversWholeDocument) {
      throw FormatException(
        validation.problems.isEmpty
            ? 'The new digital signature did not validate.'
            : 'The new digital signature did not validate: '
                '${validation.problems.join('; ')}',
      );
    }
    _commitSavedRevision(
      signed,
      beforeLength: before.length,
      impact: PdfEditImpact.none,
    );
    return true;
  }

  /// The signatures present in the current revision (`PdfSignature.of`).
  ///
  /// This recomputes the AcroForm walk on every read; to look one up by field
  /// name repeatedly (e.g. per annotation row), use [signatureByFieldName],
  /// which caches the map for the current revision.
  List<PdfSignature> get signatures => PdfSignature.of(_document);

  Map<String, PdfSignature>? _signaturesByField;
  int _signaturesByFieldRevision = -1;

  /// The current revision's signatures keyed by their field's fully qualified
  /// name, computed once per revision. Avoids re-walking the whole AcroForm for
  /// every annotation the sidebar lists (which is quadratic on a form-heavy
  /// document).
  Map<String, PdfSignature> get signatureByFieldName {
    if (_signaturesByFieldRevision != _revisionId) {
      _signaturesByFieldRevision = _revisionId;
      _signaturesByField = {
        for (final signature in PdfSignature.of(_document))
          signature.field.name: signature,
      };
    }
    return _signaturesByField!;
  }

  PdfTrustStore? _trustStore;

  /// The trust anchors [validationFor] chains signer certificates up to, so a
  /// signature can read as "trusted" rather than "validity unknown". The
  /// library ships no built-in roots; a host supplies an AATL/EUTL or
  /// organisation bundle (e.g. `PdfTrustStore.trusting([...])`). Null leaves
  /// every signature's [PdfSignatureValidation.chainTrusted] null - crypto is
  /// still checked, but the signer is never vouched for.
  ///
  /// Setting it re-validates on the next read (the cache is dropped) and
  /// notifies listeners, so a bundle loaded asynchronously lights up the
  /// signature panel when it arrives.
  PdfTrustStore? get trustStore => _trustStore;

  set trustStore(PdfTrustStore? store) {
    if (identical(store, _trustStore)) return;
    _trustStore = store;
    _validationCache.clear();
    _validating.clear();
    notifyListeners();
  }

  /// [validationFor] results for the current revision, keyed by the signature
  /// field's fully qualified name. Dropped whenever the revision moves (or the
  /// trust store changes) so it never reports a stale verdict.
  final Map<String, PdfSignatureValidation> _validationCache = {};

  /// Field names whose validation is in flight, so it is scheduled only once.
  final Set<String> _validating = {};
  int _validationCacheRevision = -1;

  void _dropStaleValidations() {
    if (_validationCacheRevision != _revisionId) {
      _validationCacheRevision = _revisionId;
      _validationCache.clear();
      _validating.clear();
    }
  }

  /// The validation for [signature] at the current revision, or null when it
  /// hasn't been computed yet. Validation walks the CMS/certificate crypto,
  /// which can be slow, so it never runs on the caller's frame: when the
  /// result isn't cached this schedules it off the current event-loop turn and
  /// [notifyListeners] once it lands (the sidebar shows a "checking" state
  /// until then). The result is cached per (revision, field), so repeated
  /// reads while the panel rebuilds are free.
  ///
  /// Pass `schedule: false` to peek at the cache without kicking off work.
  PdfSignatureValidation? validationFor(PdfSignature signature,
      {bool schedule = true}) {
    _dropStaleValidations();
    final key = signature.field.name;
    final cached = _validationCache[key];
    if (cached != null) return cached;
    if (schedule && _validating.add(key)) {
      final revision = _revisionId;
      final store = _trustStore;
      // Off the current frame: opening the panel stays instant even when the
      // signer's certificate chain is expensive to verify.
      Future(() {
        // The document may have moved on while this was queued.
        if (_revisionId != revision) {
          _validating.remove(key);
          return;
        }
        PdfSignatureValidation? result;
        try {
          result = signature.validate(trustStore: store);
        } catch (_) {
          // A signature we can't validate simply stays "checking"-free; the
          // panel falls back to showing it without a verdict.
        }
        _validating.remove(key);
        if (_revisionId != revision || result == null) return;
        _validationCache[key] = result;
        notifyListeners();
      });
    }
    return null;
  }

  /// Removes a digital signature as one undoable revision: drops its signature
  /// field (and its widget) and every "apply to pages" appearance copy - the
  /// /Stamp annotations that share the signature's appearance stream. Use to
  /// delete a signature placed by accident; undo restores it.
  ///
  /// The signature's own signed bytes stay in the file history (they can't be
  /// scrubbed), but the signature is no longer an active field, so it stops
  /// being listed or shown. Returns false if the field can't be resolved.
  bool removeSignature(PdfSignature signature) {
    final fieldName = signature.field.name;
    // The appearance stream object shared by the widget and its repeat stamps.
    final apObjectNumber = _appearanceObjectNumber(signature.field.widgets);
    clearAnnotationSelection();
    return apply((editor) {
      final field = editor.acroForm?.fieldNamed(fieldName);
      if (field != null) editor.removeField(field);
      if (apObjectNumber == null) return;
      for (var page = 0; page < editor.document.pageCount; page++) {
        final copies = [
          for (final annotation in editor.document.page(page).annotations)
            if (annotation.subtype == 'Stamp' &&
                _appearanceObjectNumber([annotation.dict]) == apObjectNumber)
              annotation,
        ];
        if (copies.isNotEmpty) editor.removeAnnotations(page, copies);
      }
    });
  }

  /// The object number of the /AP /N appearance shared by [dicts] (the first
  /// that has one), used to match a signature's repeat stamps to its widget.
  int? _appearanceObjectNumber(List<CosDictionary> dicts) {
    for (final dict in dicts) {
      final ap = _document.cos.resolve(dict['AP']);
      final n = ap is CosDictionary ? ap['N'] : null;
      if (n is CosReference) return n.objectNumber;
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // document outline / bookmarks

  /// The current document outline (`/Outlines`) as nested bookmark items.
  PdfOutline get outline => PdfOutline.of(_document);

  /// Adds a PDF bookmark pointing at [pageIndex], or the first page when no
  /// page is supplied. [parentPath] identifies the parent outline item; null
  /// adds a top-level bookmark. Returns false when the title/page/path is
  /// invalid or the edit stages no PDF changes.
  bool addBookmark(
    String title, {
    int? pageIndex,
    List<int>? parentPath,
    int? index,
    bool open = true,
  }) {
    final text = title.trim();
    if (text.isEmpty) return false;
    final page = (pageIndex ?? 0);
    if (page < 0 || page >= _document.pageCount) return false;
    var resolvedParent = true;
    final changed = apply(
      (editor) {
        final parent = parentPath == null
            ? null
            : _outlineRefAt(editor.document, parentPath);
        if (parentPath != null && parent == null) {
          resolvedParent = false;
          return;
        }
        editor.addOutlineItem(
          text,
          pageIndex: page,
          parent: parent,
          index: index,
          open: open,
        );
      },
    );
    return resolvedParent && changed;
  }

  /// Edits an existing bookmark addressed by [path]. A null field is left
  /// unchanged. Page destinations are written as explicit `/Fit` destinations.
  bool editBookmark(
    List<int> path, {
    String? title,
    int? pageIndex,
    bool? open,
  }) {
    final text = title?.trim();
    if (text != null && text.isEmpty) return false;
    if (pageIndex != null &&
        (pageIndex < 0 || pageIndex >= _document.pageCount)) {
      return false;
    }
    if (text == null && pageIndex == null && open == null) return false;
    var resolved = true;
    final changed = apply(
      (editor) {
        final item = _outlineRefAt(editor.document, path);
        if (item == null) {
          resolved = false;
          return;
        }
        if (text != null) editor.setOutlineTitle(item, text);
        if (pageIndex != null) {
          editor.setOutlineDestination(
            item,
            PdfExplicitDestination.fit(pageIndex),
          );
        }
        if (open != null) editor.setOutlineStyle(item, open: open);
      },
    );
    return resolved && changed;
  }

  /// Deletes the bookmark at [path], including its child bookmark subtree.
  bool deleteBookmark(List<int> path) {
    var resolved = true;
    final changed = apply(
      (editor) {
        final item = _outlineRefAt(editor.document, path);
        if (item == null) {
          resolved = false;
          return;
        }
        editor.removeOutlineItem(item);
      },
    );
    return resolved && changed;
  }

  static CosReference? _outlineRefAt(PdfDocument document, List<int> path) {
    if (path.isEmpty) return null;
    final cos = document.cos;
    final root = cos.resolve(document.catalog['Outlines']);
    if (root is! CosDictionary) return null;
    var parent = root;
    CosReference? foundRef;
    for (final index in path) {
      if (index < 0) return null;
      var cur = parent['First'];
      var i = 0;
      final seen = <int>{};
      CosDictionary? foundDict;
      while (cur is CosReference && seen.add(cur.objectNumber)) {
        final dict = cos.resolve(cur);
        if (dict is! CosDictionary) return null;
        if (i == index) {
          foundRef = cur;
          foundDict = dict;
          break;
        }
        i++;
        cur = dict['Next'];
      }
      if (foundDict == null) return null;
      parent = foundDict;
    }
    return foundRef;
  }

  // ---------------------------------------------------------------------
  // annotation sync (the change feed and its replay half)

  StreamController<List<PdfAnnotationChange>>? _changeFeed;
  bool _applyingRemote = false;
  bool _committingRemoteRevision = false;

  /// A live feed of annotation diffs: after every edit, undo, and redo,
  /// one batch of [PdfAnnotationChange]s describing what happened to the
  /// document's annotations, keyed on their /NM identity
  /// ([PdfAnnotation.name]). Nothing is computed while nobody listens.
  ///
  /// This is the outbound half of annotation sync: serialize each
  /// change's snapshot ([PdfAnnotationSnapshot.toJson]) into your store
  /// (Firestore, a server, ...) and replay batches from other devices
  /// through [applyRemoteChange] - remote applies don't re-emit, so
  /// there is no echo to suppress.
  ///
  /// Caveat: open pre-existing documents with [ensureAnnotationNames] +
  /// [annotationBaseline] so every annotation has a durable identity first.
  /// A successful remote apply becomes a non-crossable undo checkpoint:
  /// local edits made afterward can still be undone, while older local
  /// history remains in the document below that checkpoint.
  Stream<List<PdfAnnotationChange>> get annotationChanges =>
      (_changeFeed ??= StreamController.broadcast(
        // Seed the diff baseline from the clean current document the moment a
        // listener attaches, and drop it when the last one leaves. Every emit
        // then diffs against this cached state instead of re-opening the
        // pre-edit bytes into a second full document (#416).
        onListen: () => _annotationBaseline =
            pdfCollectAnnotationStates(_document),
        onCancel: () => _annotationBaseline = null,
      )).stream;

  /// The annotation states of [_document] as of the last emit, kept live only
  /// while [annotationChanges] has a listener. The pre-edit side of each diff,
  /// so no second [PdfDocument.open] is needed per commit (#416).
  PdfAnnotationStates? _annotationBaseline;

  /// Diffs the current document's annotations against the cached pre-edit
  /// baseline and emits the result, then advances the baseline.
  ///
  /// [annotationPages] limits the walk to the pages an edit touched (null for
  /// structural edits, which can move any annotation). The pre-edit side comes
  /// from [_annotationBaseline] — seeded when a listener attaches and advanced
  /// here every revision — so this pays no second [PdfDocument.open] (#416).
  /// A remote apply still advances the baseline (so its change is not echoed
  /// back on the next local edit) but emits nothing.
  void _emitAnnotationChanges(Iterable<int>? annotationPages) {
    final feed = _changeFeed;
    if (feed == null || !feed.hasListener) return;
    if (annotationPages != null && annotationPages.isEmpty) return;
    final baseline = _annotationBaseline;
    if (baseline == null) return; // no listener was attached at seed time

    final pages = annotationPages?.toSet();
    final after = pdfCollectAnnotationStates(_document, pages: pages);
    final before = pages == null ? baseline : baseline.restrictedTo(pages);
    _annotationBaseline =
        pages == null ? after : baseline.withPagesReplaced(pages, after);

    if (_applyingRemote) return; // baseline advanced; don't echo the remote edit
    final changes = pdfDiffAnnotationStates(before, after);
    if (changes.isNotEmpty) feed.add(changes);
  }

  /// Replays one change from another device or session: upserts the
  /// snapshot of a created/modified change, removes by name for a
  /// removed one. Returns whether the document changed.
  ///
  /// The edit is a normal rendering/thumbnail revision but is never
  /// re-emitted on [annotationChanges] and cannot itself be undone locally.
  /// It establishes a new undo checkpoint, sealing any earlier local history;
  /// edits made after it remain undoable down to that checkpoint.
  bool applyRemoteChange(PdfAnnotationChange change) {
    final snapshot = change.snapshot;
    _applyingRemote = true;
    _committingRemoteRevision = true;
    try {
      switch (change.kind) {
        case PdfAnnotationChangeKind.created:
        case PdfAnnotationChangeKind.modified:
          final name = snapshot?.name;
          if (snapshot == null || name == null) return false;
          if (change.pageIndex < 0 || change.pageIndex >= _document.pageCount) {
            return false;
          }
          // the upsert may also remove the annotation's previous
          // incarnation from the page it used to live on
          final existing = findAnnotationByName(name);
          final touched = {change.pageIndex, if (existing != null) existing.$1};
          // slots on the touched pages shift under the remove + append
          _selected.removeWhere((slot) => touched.contains(slot.$1));
          return apply(
            (e) => e.upsertAnnotation(change.pageIndex, snapshot),
          );
        case PdfAnnotationChangeKind.removed:
          final name = change.name;
          if (name == null) return false;
          final existing = findAnnotationByName(name);
          if (existing == null) return false;
          _selected.removeWhere((slot) => slot.$1 == existing.$1);
          return apply(
            (e) {
              e.removeAnnotation(existing.$1, existing.$2);
            },
          );
      }
    } finally {
      _committingRemoteRevision = false;
      _applyingRemote = false;
    }
  }

  /// Stamps a generated /NM on every annotation that lacks one (see
  /// [PdfAnnotationEditing.nameAnnotations]) - run once when opening a
  /// document for sync, before [annotationBaseline]. Returns how many
  /// were named. Emits nothing: the baseline is the explicit hand-off.
  int ensureAnnotationNames() {
    var named = 0;
    _applyingRemote = true; // names are identity, not an annotation edit
    try {
      apply((e) => named = e.nameAnnotations());
    } finally {
      _applyingRemote = false;
    }
    return named;
  }

  /// The current document's whole annotation state as created-changes -
  /// what a sync layer uploads to seed its store when a document joins
  /// sync. Annotations without /NM (call [ensureAnnotationNames] first)
  /// and non-captureable subtypes (popups, links, widgets) are skipped.
  List<PdfAnnotationChange> annotationBaseline() {
    final changes = <PdfAnnotationChange>[];
    for (var pageIndex = 0; pageIndex < _document.pageCount; pageIndex++) {
      for (final annotation in _page(pageIndex).annotations) {
        if (annotation.name == null) continue;
        final snapshot = PdfAnnotationSnapshot.capture(
          _document,
          annotation,
          keepName: true,
          sourcePageRotation: _page(pageIndex).rotation,
        );
        if (snapshot == null) continue;
        changes.add(
          PdfAnnotationChange(
            kind: PdfAnnotationChangeKind.created,
            pageIndex: pageIndex,
            name: annotation.name,
            snapshot: snapshot,
          ),
        );
      }
    }
    return changes;
  }

  /// Finds the annotation whose /NM is [name] in the current revision,
  /// or null. Pair with [PdfViewerController.showRect] to navigate to a
  /// synced annotation.
  (int pageIndex, PdfAnnotation annotation)? findAnnotationByName(String name) {
    for (var pageIndex = 0; pageIndex < _document.pageCount; pageIndex++) {
      for (final annotation in _page(pageIndex).annotations) {
        if (annotation.name == name) return (pageIndex, annotation);
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // tool state

  PdfEditTool? _tool;
  bool _colorLocked = false;

  static const Set<String> _colorLockedFields = {'color'};

  /// The armed tool, or null when the viewer behaves as a plain reader.
  PdfEditTool? get tool => _tool;

  set tool(PdfEditTool? value) {
    if (value == _tool) return;
    preferences.snapshotActiveStyleScope(lockedFields: _lockedStyleFields);
    // leaving an ink-like tool commits the drawing, like lifting the pen.
    //
    // Switching directly from ink to the eraser is the latency-sensitive
    // path used by Apple Pencil double-tap.  A pending ink commit can rewrite
    // the PDF and trigger a raster refresh, which made the eraser button feel
    // sticky.  Arm the eraser and repaint the toolbar/cursor first, then let
    // the commit run in the next event-loop turn; the stroke is still committed
    // before any subsequent pointer event can erase it.
    final leavingInkTool = _buffersInk(_tool) && value != _tool;
    final deferInkCommit =
        leavingInkTool && value == PdfEditTool.eraser && hasPendingInk;
    if (leavingInkTool && !deferInkCommit) {
      finishInk();
    }
    // arming anything but the eraser by other means breaks the pencil
    // double-tap pairing (see [togglePencilEraser]) - the remembered tool
    // is only valid while the eraser stays the toggled-on partner
    if (value != PdfEditTool.eraser) _eraserToggledOn = false;
    _tool = value;
    if (value != PdfEditTool.select) _selected.clear();
    if (value != PdfEditTool.content) _selectedElement = null;
    _cropModeArmed = false;
    _cropDraft = null;
    // each annotation tool remembers its own colour, stroke, opacity, … -
    // arming one restores its saved style and routes further style changes
    // back into its slot (see [PdfEditingPreferences.beginStyleScope])
    preferences.beginStyleScope(
      _styleScopeKey(value),
      _styleScopeFields(value),
      defaults: _styleScopeDefaults(value),
      lockedFields: _lockedStyleFields,
    );
    notifyListeners();
    if (deferInkCommit) Timer.run(finishInk);
  }

  Set<String> get _lockedStyleFields =>
      _colorLocked ? _colorLockedFields : const {};

  /// Whether tool style scopes are allowed to change [color].
  ///
  /// Hosts use this for color-locked sessions: the current creation color is
  /// still usable and can be changed programmatically, but arming another
  /// tool does not restore that tool's saved color. Stroke width, opacity,
  /// font, fill, and the other style fields keep their normal per-tool memory.
  bool get colorLocked => _colorLocked;

  set colorLocked(bool value) {
    if (value == _colorLocked) return;
    preferences.snapshotActiveStyleScope(lockedFields: _lockedStyleFields);
    _colorLocked = value;
    preferences.beginStyleScope(
      _styleScopeKey(_tool),
      _styleScopeFields(_tool),
      defaults: _styleScopeDefaults(_tool),
      lockedFields: _lockedStyleFields,
      forceRestore: true,
    );
    notifyListeners();
  }

  // Apple Pencil double-tap eraser toggle: the tool that was armed when the
  // eraser was toggled on, and whether the current eraser arming came from a
  // toggle (so toggling off restores exactly what was there - reader mode
  // included - rather than a guessed default).
  PdfEditTool? _toolBeforeEraserToggle;
  bool _eraserToggledOn = false;

  /// Toggles the eraser the way the Apple Pencil's hardware double-tap does
  /// in drawing apps: the first call arms [PdfEditTool.eraser] remembering
  /// whatever tool was active, and the next restores it (reader mode
  /// included). Double-tapping while the eraser was armed by hand - never
  /// paired through this method - falls back to [PdfEditTool.ink] so the
  /// gesture always returns to drawing.
  ///
  /// Flutter exposes no framework event for the pencil's double-tap (or the
  /// Pencil Pro squeeze), so a host wires the native iOS gesture to this; see
  /// [PdfPencilInteraction], which the editor shells attach automatically.
  void togglePencilEraser() {
    if (_tool == PdfEditTool.eraser) {
      tool = _eraserToggledOn ? _toolBeforeEraserToggle : PdfEditTool.ink;
      _eraserToggledOn = false;
      _toolBeforeEraserToggle = null;
    } else {
      _toolBeforeEraserToggle = _tool;
      tool = PdfEditTool.eraser;
      _eraserToggledOn = true; // set after the setter, which clears it
    }
  }

  static bool _buffersInk(PdfEditTool? tool) =>
      PdfEditToolBehavior.maybeOf(tool)?.buffersInk ?? false;

  /// The persisted-style scope key for [tool] - a stable slot name for the
  /// tools that create styled annotations, null for the others (select,
  /// content, form, redact, signature, image, snapshot, calibrate). Owned by
  /// [PdfEditToolBehavior]. See [preferences].
  static String? _styleScopeKey(PdfEditTool? tool) =>
      PdfEditToolBehavior.maybeOf(tool)?.styleScopeKey;

  /// The style fields [tool] remembers - mirrors the controls its toolbar
  /// strip exposes, so a rectangle keeps its fill but not a font, ink keeps
  /// its stroke but not line endings, and so on. Owned by
  /// [PdfEditToolBehavior].
  static Set<String> _styleScopeFields(PdfEditTool? tool) =>
      PdfEditToolBehavior.maybeOf(tool)?.styleScopeFields ?? const {};

  static Map<String, Object?> _styleScopeDefaults(PdfEditTool? tool) =>
      PdfEditToolBehavior.maybeOf(tool)?.styleScopeDefaults ?? const {};

  /// Activates the text-markup style scope (highlight / underline / strike
  /// out / squiggly) - they act on the text selection rather than arming a
  /// tool, so the toolbar calls this when its Markup strip opens, giving
  /// markup its own remembered colour and opacity (the classic yellow
  /// highlighter that stays yellow). See [preferences].
  void useMarkupStyleScope() => preferences.beginStyleScope(
      'markup',
      const {
        'color',
        'opacity',
      },
      lockedFields: _lockedStyleFields);

  /// Whether the armed [tool] creates annotations that carry a colour the
  /// toolbar can offer - i.e. the tool's style scope remembers `color`.
  /// False for tools that ignore colour (select, eraser, content, form,
  /// redact, signature), so the colour swatches aren't shown beside them.
  bool get toolUsesColor => _styleScopeFields(tool).contains('color');

  /// The color new annotations are created with. Persisted in [preferences].
  ///
  /// Kept on the controller (unlike the other style properties, which are
  /// read straight off [preferences]) because the setter has editing-side
  /// effects: it honours the [colorLocked] guard and recolours the active
  /// stamp under the stamp tool.
  Color get color => preferences.color;

  set color(Color value) {
    preferences.setColor(value, recordStyleScope: !_colorLocked);
    if (_tool == PdfEditTool.stamp) _recolorActiveStamp(value);
  }

  /// Font family for free-text annotations - one of the standard PDF
  /// text fonts (sans-serif, serif, monospace). Persisted. Selecting a
  /// standard family also clears any [activeFont] (back to base-14).
  PdfStandardFont get fontFamily => preferences.fontFamily;

  set fontFamily(PdfStandardFont value) {
    if (_activeFont != null) {
      _activeFont = null;
      notifyListeners();
    }
    preferences.fontFamily = value;
  }

  double _lineSpacing = kPdfFreeTextDefaultLineSpacing;
  double _charSpacing = 0;
  double _fontWidth = kPdfFreeTextDefaultHorizontalScale;
  bool _textUnderline = false;

  /// The line-height multiplier new free-text boxes are created with
  /// (baseline-to-baseline distance is `fontSize * lineSpacing`). Session
  /// state (not persisted).
  double get lineSpacing => _lineSpacing;

  set lineSpacing(double value) {
    if (value == _lineSpacing) return;
    _lineSpacing = value;
    notifyListeners();
  }

  /// The character spacing (extra points after each glyph) new free-text
  /// boxes are created with. Session state (not persisted).
  double get charSpacing => _charSpacing;

  set charSpacing(double value) {
    if (value == _charSpacing) return;
    _charSpacing = value;
    notifyListeners();
  }

  /// The horizontal glyph scaling (per cent, 100 = natural width) new
  /// free-text boxes are created with. Session state (not persisted).
  double get fontWidth => _fontWidth;

  set fontWidth(double value) {
    if (value == _fontWidth) return;
    _fontWidth = value;
    notifyListeners();
  }

  /// Whether new free-text boxes are created underlined. Session state.
  bool get textUnderline => _textUnderline;

  set textUnderline(bool value) {
    if (value == _textUnderline) return;
    _textUnderline = value;
    notifyListeners();
  }

  PdfEmbeddedFont? _activeFont;

  /// An embedded TrueType/OpenType font selected for new free text, taking
  /// precedence over [fontFamily] so authored text can use any font (not
  /// just the base-14 faces). Null means a standard family.
  ///
  /// Not persisted - the font program is large, and recovering it from a
  /// box's own appearance keeps editing lossless regardless. A session
  /// starts on the standard fonts; reselect a bundled or custom font to
  /// use it again.
  PdfEmbeddedFont? get activeFont => _activeFont;

  set activeFont(PdfEmbeddedFont? value) {
    if (value == _activeFont) return;
    _activeFont = value;
    notifyListeners();
  }

  /// A human label for the font the font controls currently target - a
  /// selected measurement's caption face, else the font new free text will
  /// be written in (the embedded font's family, or the standard family).
  String get activeFontLabel =>
      selectedMeasurementCaptionStyle?.font.family.label ??
      _activeFont?.displayName ??
      preferences.fontFamily.family.label;

  /// Parses [bytes] as a TrueType (.ttf) or OpenType (.otf) font and
  /// selects it for new free text via [activeFont]. Returns false when the
  /// bytes aren't a usable font (and leaves the selection unchanged).
  bool setCustomFont(Uint8List bytes) {
    try {
      activeFont = PdfEmbeddedFont.parse(bytes);
      return true;
    } catch (_) {
      return false;
    }
  }

  int? _documentFontsForRevision;
  List<PdfEmbeddedFont>? _documentFontsCache;

  /// The embeddable fonts the current document already uses (see
  /// [PdfEmbeddedFont.usedIn]) - offered in the font menu so new free text
  /// can reuse a face the file already carries. Parsed once per revision
  /// and cached; the list is empty when nothing embeddable is found.
  List<PdfEmbeddedFont> get documentFonts {
    if (_documentFontsForRevision != _revisionId ||
        _documentFontsCache == null) {
      _documentFontsForRevision = _revisionId;
      _documentFontsCache = PdfEmbeddedFont.usedIn(_document);
    }
    return _documentFontsCache!;
  }

  /// Whether new annotations are non-solid - the legacy boolean view of
  /// [preferences.lineStyle] (kept for the drag previews that only show
  /// dashed/solid).
  bool get dashedStroke => preferences.lineStyle != PdfLineStyle.solid;

  set dashedStroke(bool value) =>
      preferences.lineStyle = value ? PdfLineStyle.dashed : PdfLineStyle.solid;

  /// The `/BS /D` dash array new annotations get, for the current
  /// [preferences.lineStyle] at the current [preferences.strokeWidth], sized
  /// by [preferences.lineScale] - null for a solid border.
  List<double>? get _lineDashPattern => preferences.lineStyle
      .dashArray(preferences.strokeWidth, scale: preferences.lineScale);

  int get _colorValue => preferences.color.toARGB32() & 0xFFFFFF;

  static int? _rgbOf(Color? color) =>
      color == null ? null : color.toARGB32() & 0xFFFFFF;

  Map<String, String> _stampTemplateValues = const {};

  /// App-supplied values for `{{field}}` placeholders in saved stamp
  /// templates. Keys are normalized to lowercase, matched case-insensitively,
  /// and are not persisted: they describe the current app/session data rather
  /// than the saved stamp design.
  ///
  /// Built-ins are added at placement time: `date`, `time`, `datetime`, and
  /// `username` (which defaults to [preferences.author]). Entries here override
  /// those
  /// built-ins, so a host can provide its own date formatting or user label.
  Map<String, String> get stampTemplateValues => _stampTemplateValues;

  set stampTemplateValues(Map<String, String> value) {
    final normalized = _normalizeStampTemplateValues(value);
    if (mapEquals(_stampTemplateValues, normalized)) return;
    _stampTemplateValues = normalized;
    notifyListeners();
  }

  /// Clock used for the built-in `date`, `time`, and `datetime` stamp
  /// placeholders. Override in tests or when a host app needs a fixed clock.
  DateTime Function() stampTemplateClock = DateTime.now;

  /// The UI locale used to localize the built-in `date`/`datetime` stamp
  /// fields (month names, AM/PM). Kept fresh by the editing overlay from its
  /// ambient [Localizations]; falls back to [PdfEditingPreferences.locale]
  /// (the persisted Settings choice) and finally English. Purely an output
  /// detail of the resolved stamp text - setting it never notifies listeners.
  ui.Locale? uiLocale;

  String? get _stampLocaleName =>
      (uiLocale ?? preferences.locale)?.toString();

  /// Field names the stamp editor should offer for insertion.
  ///
  /// This includes the built-ins plus the current custom value keys.
  List<String> get stampTemplateFieldNames => [
        ...stampTemplateBuiltinFields,
        for (final key in _stampTemplateValues.keys)
          if (!stampTemplateBuiltinFields.contains(key)) key,
      ];

  /// The actual values used for the next stamp placement.
  Map<String, String> get resolvedStampTemplateValues =>
      _resolvedStampTemplateValues();

  /// Sets or removes one custom stamp-template value.
  void setStampTemplateValue(String name, String? value) {
    final key = name.trim().toLowerCase();
    if (key.isEmpty) return;
    final next = {..._stampTemplateValues};
    if (value == null) {
      next.remove(key);
    } else {
      next[key] = value;
    }
    stampTemplateValues = next;
  }

  Map<String, String> _resolvedStampTemplateValues() {
    final now = stampTemplateClock();
    final localeName = _stampLocaleName;
    final date = preferences.stampDateFormat.format(now, localeName: localeName);
    final time = preferences.stampTimeFormat.format(now, localeName: localeName);
    return {
      'date': date,
      'time': time,
      'datetime': '$date $time',
      'username': preferences.author ?? '',
      ..._stampTemplateValues,
    };
  }

  String _resolveStampText(String text) =>
      pdfResolveStampTemplateText(text, _resolvedStampTemplateValues());

  // ---------------------------------------------------------------------
  // in-place text editing

  bool _editingText = false;
  TextSelection? _editingTextSelection;
  int _editingTextStyleRevision = 0;
  ({
    PdfTextFont? font,
    double? size,
    int? color,
    bool? underline
  })? _editingTextStyleRequest;
  int _editSelectedTextRevision = 0;
  int _editingTextFocusHoldCount = 0;
  int _editingTextFocusHoldRevision = 0;
  int _keepEditingTextFocusedCount = 0;

  /// Whether an in-place text editor (the free-text tool's box) is open
  /// on a page. While it is, the viewer releases its keyboard shortcuts -
  /// backspace must delete characters, not the annotation.
  bool get isEditingText => _editingText;

  bool get hasEditingTextSelection =>
      _editingText &&
      _editingTextSelection != null &&
      _editingTextSelection!.isValid &&
      !_editingTextSelection!.isCollapsed;

  int get editingTextStyleRevision => _editingTextStyleRevision;

  ({PdfTextFont? font, double? size, int? color, bool? underline})?
      get editingTextStyleRequest => _editingTextStyleRequest;

  int get editSelectedTextRevision => _editSelectedTextRevision;

  bool get isEditingTextFocusCommitHeld => _editingTextFocusHoldCount > 0;

  int get editingTextFocusHoldRevision => _editingTextFocusHoldRevision;

  /// Whether an open in-place text editor should hold on to keyboard focus.
  /// Set while the tune popup is open over a text-editing session: a
  /// `TextField` only paints its selection highlight while focused, so the
  /// popup's controls (which steal focus on tap on some platforms) would
  /// otherwise hide the very selection they restyle. The overlay reclaims
  /// focus for the field while this is true. Only meaningful while editing.
  bool get shouldKeepEditingTextFocused =>
      _editingText && _keepEditingTextFocusedCount > 0;

  /// Begins a keep-focused window (see [shouldKeepEditingTextFocused]).
  /// Balanced by [endKeepEditingTextFocused]; reference-counted so nested
  /// popups don't drop the guard early.
  void beginKeepEditingTextFocused() {
    _keepEditingTextFocusedCount++;
    notifyListeners();
  }

  void endKeepEditingTextFocused() {
    if (_keepEditingTextFocusedCount == 0) return;
    _keepEditingTextFocusedCount--;
    notifyListeners();
  }

  /// Marks an in-place text editor open/closed. Called by the page
  /// overlay that owns the editor.
  void setEditingText(bool value) {
    if (value == _editingText) return;
    _editingText = value;
    if (!value) {
      _editingTextSelection = null;
      _editingTextStyleRequest = null;
    }
    notifyListeners();
  }

  void setEditingTextSelection(TextSelection selection) {
    if (!_editingText) return;
    if (_editingTextSelection == selection) return;
    final hadSelection = hasEditingTextSelection;
    _editingTextSelection = selection;
    if (hadSelection != hasEditingTextSelection) notifyListeners();
  }

  bool restyleEditingTextSelection({
    PdfTextFont? font,
    double? size,
    int? color,
    bool? underline,
  }) {
    if (!hasEditingTextSelection) return false;
    _editingTextStyleRequest =
        (font: font, size: size, color: color, underline: underline);
    _editingTextStyleRevision++;
    notifyListeners();
    return true;
  }

  bool requestEditSelectedTextInline() {
    if (_selected.length != 1 ||
        selectedAnnotation?.subtype != 'FreeText' ||
        selectedAnnotation?.isLockedContents == true) {
      return false;
    }
    _editSelectedTextRevision++;
    notifyListeners();
    return true;
  }

  void beginEditingTextFocusHold() {
    _editingTextFocusHoldCount++;
    _editingTextFocusHoldRevision++;
    notifyListeners();
  }

  void endEditingTextFocusHold() {
    if (_editingTextFocusHoldCount == 0) return;
    _editingTextFocusHoldCount--;
    _editingTextFocusHoldRevision++;
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // eyedropper

  bool _pickingColor = false;

  /// Whether the eyedropper is armed: the next tap on a page samples the
  /// rendered color there and becomes [color].
  bool get isPickingColor => _pickingColor;

  /// Arms the eyedropper. The viewer's page overlays take the next tap.
  void startColorPick() {
    if (_pickingColor) return;
    _pickingColor = true;
    notifyListeners();
  }

  void cancelColorPick() {
    if (!_pickingColor) return;
    _pickingColor = false;
    notifyListeners();
  }

  /// Disarms the eyedropper and adopts [picked] (forced opaque - alpha is
  /// [preferences.opacity]'s job) as the annotation [color].
  void finishColorPick(Color picked) {
    _pickingColor = false;
    color = Color(0xFF000000 | (picked.toARGB32() & 0xFFFFFF));
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // ink

  final Map<int, List<List<(double, double)>>> _ink = {};
  final Map<int, List<List<double>?>> _inkPressures = {};
  Timer? _inkTimer;

  /// How long after the last stroke the buffer auto-commits as one Ink
  /// annotation - strokes drawn within the window aggregate (dotting an
  /// i, crossing a t), so a multi-stroke drawing still lands as a single
  /// annotation and a single undo step. Null restores fully manual
  /// commits ([finishInk] - the toolbar shows its confirm buttons then).
  Duration? inkCommitDelay = const Duration(milliseconds: 800);

  /// Whether drawn strokes commit on their own ([inkCommitDelay] is set).
  bool get inkAutoCommits => inkCommitDelay != null;

  /// Holds the auto-commit while a stroke is in flight, so a slow
  /// drawing isn't split mid-stroke. The page overlay calls this on
  /// pen-down; the stroke's [addInkStroke] re-arms the timer.
  void beginInkStroke() {
    _inkTimer?.cancel();
    _inkTimer = null;
  }

  /// Releases a [beginInkStroke] hold without adding a stroke - the
  /// gesture was aborted (a second finger landed, the pointer was
  /// canceled). Earlier strokes waiting in the buffer get their
  /// auto-commit timer back; without this they'd sit uncommitted until
  /// the next stroke or tool switch.
  void cancelInkStroke() {
    if (_inkTimer != null || !hasPendingInk) return;
    final delay = inkCommitDelay;
    if (delay != null) _inkTimer = Timer(delay, finishInk);
  }

  /// The strokes of the most recent ink commit, while [document] is
  /// still the revision they landed in - the page overlay keeps painting
  /// them until that revision's raster is on screen, so the drawing
  /// doesn't blink out for the render's duration.
  ({
    int revisionId,
    Map<int, List<List<(double, double)>>> strokes,
    Map<int, List<List<double>?>> pressures,
    Color color,
    double strokeWidth,
  })? _committedInk;

  /// The just-committed ink on [pageIndex] (see [_committedInk]), or
  /// null once the document has moved past the committing revision.
  ({
    List<List<(double, double)>> strokes,
    List<List<double>?> pressures,
    Color color,
    double strokeWidth,
  })? committedInkOn(int pageIndex) {
    final committed = _committedInk;
    if (committed == null || committed.revisionId != _revisionId) {
      return null;
    }
    final strokes = committed.strokes[pageIndex];
    if (strokes == null || strokes.isEmpty) return null;
    return (
      strokes: strokes,
      pressures: committed.pressures[pageIndex] ??
          List<List<double>?>.filled(strokes.length, null),
      color: committed.color,
      strokeWidth: committed.strokeWidth,
    );
  }

  /// Whether touch input is in play this session: always true on
  /// touch-first platforms (iOS/Android/Fuchsia), and flipped on by the
  /// first touch pointer the viewer or toolbar sees elsewhere (a
  /// touchscreen laptop, say). The stock toolbar hides the finger-draws
  /// toggle until this is true - on a mouse-only desktop the control
  /// has nothing to control.
  bool get hasTouchInput =>
      _touchSeen ||
      switch (defaultTargetPlatform) {
        TargetPlatform.iOS ||
        TargetPlatform.android ||
        TargetPlatform.fuchsia =>
          true,
        _ => false,
      };
  bool _touchSeen = false;

  /// Records that a touch pointer was seen, revealing touch-only chrome
  /// ([hasTouchInput]). The viewer and toolbar call this from their raw
  /// pointer-down listeners; not persisted - a session without touch
  /// starts clean.
  void noteTouchInput() {
    if (_touchSeen) return;
    _touchSeen = true;
    notifyListeners();
  }

  /// Drawn-but-uncommitted ink strokes on [pageIndex], in page space.
  List<List<(double, double)>> strokesOn(int pageIndex) =>
      List.unmodifiable(_ink[pageIndex] ?? const []);

  /// Per-point normalized pressures paralleling [strokesOn] - null for
  /// strokes drawn without pressure (finger, mouse).
  List<List<double>?> strokePressuresOn(int pageIndex) =>
      List.unmodifiable(_inkPressures[pageIndex] ?? const []);

  bool get hasPendingInk => _ink.values.any((s) => s.isNotEmpty);

  /// Buffers one drawn stroke; the buffer commits on its own after
  /// [inkCommitDelay], or through [finishInk].
  /// [pressures], when given, must hold one 0–1 value per stroke point.
  void addInkStroke(
    int pageIndex,
    List<(double, double)> stroke, {
    List<double>? pressures,
  }) {
    if (stroke.isEmpty) return;
    assert(pressures == null || pressures.length == stroke.length);
    _ink.putIfAbsent(pageIndex, () => []).add(List.of(stroke));
    _inkPressures
        .putIfAbsent(pageIndex, () => [])
        .add(pressures == null ? null : List.of(pressures));
    _inkTimer?.cancel();
    final delay = inkCommitDelay;
    _inkTimer = delay == null ? null : Timer(delay, finishInk);
    notifyListeners();
  }

  /// Commits the buffered strokes as one Ink annotation per page.
  void finishInk() {
    _inkTimer?.cancel();
    _inkTimer = null;
    if (!hasPendingInk) return;
    final strokes = Map.of(_ink);
    final pressures = Map.of(_inkPressures);
    _ink.clear();
    _inkPressures.clear();
    final committed = apply(
      (editor) {
        strokes.forEach((page, pageStrokes) {
          if (pageStrokes.isNotEmpty) {
            editor.addInk(
              page,
              pageStrokes,
              color: _colorValue,
              strokeWidth: preferences.strokeWidth,
              opacity: preferences.opacity,
              pressures: pressures[page],
              author: preferences.author,
            );
          }
        });
      },
    );
    if (committed) {
      _committedInk = (
        revisionId: _revisionId,
        strokes: strokes,
        pressures: pressures,
        color: preferences.color.withValues(
          alpha: preferences.opacity.clamp(0.0, 1.0),
        ),
        strokeWidth: preferences.strokeWidth,
      );
    }
  }

  /// Throws away the buffered strokes.
  void discardInk() {
    _inkTimer?.cancel();
    _inkTimer = null;
    if (_ink.isEmpty) return;
    _ink.clear();
    _inkPressures.clear();
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // creation

  /// Adds a text markup of [kind] over [quadsByPage] (page index → quad
  /// rects, e.g. from [PdfViewerController.selectionRectsOn]).
  void addMarkup(PdfMarkupKind kind, Map<int, List<PdfRect>> quadsByPage) {
    if (quadsByPage.values.every((quads) => quads.isEmpty)) return;
    apply(
      (editor) {
        quadsByPage.forEach((page, quads) {
          if (quads.isEmpty) return;
          switch (kind) {
            case PdfMarkupKind.highlight:
              editor.addHighlight(
                page,
                quads,
                color: _colorValue,
                opacity: preferences.opacity,
                author: preferences.author,
              );
            case PdfMarkupKind.underline:
              editor.addUnderline(
                page,
                quads,
                color: _colorValue,
                opacity: preferences.opacity,
                author: preferences.author,
              );
            case PdfMarkupKind.strikeOut:
              editor.addStrikeOut(
                page,
                quads,
                color: _colorValue,
                opacity: preferences.opacity,
                author: preferences.author,
              );
            case PdfMarkupKind.squiggly:
              editor.addSquiggly(
                page,
                quads,
                color: _colorValue,
                opacity: preferences.opacity,
                author: preferences.author,
              );
          }
        });
      },
    );
  }

  void addRectangle(int pageIndex, PdfRect rect) => apply(
        (e) => e.addSquare(
          pageIndex,
          rect,
          strokeColor: _colorValue,
          strokeWidth: preferences.strokeWidth,
          fillColor: _rgbOf(preferences.shapeFillColor),
          opacity: preferences.opacity,
          dashPattern: _lineDashPattern,
          cornerRadius: preferences.cornerRadius,
          author: preferences.author,
        ),
      );

  // ---------------------------------------------------------------------
  // redaction

  /// Marks a single rectangular region for redaction (a /Redact
  /// annotation, fill black). This is the MARK phase - nothing is removed
  /// until [applyRedactions]. Undoable like any other edit until burned.
  void addRedaction(int pageIndex, PdfRect rect) => apply(
        (e) => e.addRedaction(pageIndex, [rect], author: preferences.author),
      );

  /// Marks the text runs in [quadsByPage] for redaction (one /Redact
  /// annotation per page, fill black), e.g. from a text selection. Mirrors
  /// [addMarkup].
  void addRedactionQuads(Map<int, List<PdfRect>> quadsByPage) {
    if (quadsByPage.values.every((quads) => quads.isEmpty)) return;
    apply(
      (editor) {
        quadsByPage.forEach((page, quads) {
          if (quads.isNotEmpty) {
            editor.addRedaction(page, quads, author: preferences.author);
          }
        });
      },
    );
  }

  // ---------------------------------------------------------------------
  // links

  /// Adds a hyperlink over [quads] on [pageIndex] pointing at [target] - an
  /// external URI or an in-document jump (see [PdfLinkTarget]). [quads] is
  /// one rectangle per line of a text run, or a single box.
  ///
  /// By default a link over a dragged box is drawn with a visible border so
  /// it can be seen, while a link over selected text is drawn with a subtle
  /// underline; override with [borderColor] / [underlineColor] (pass a
  /// negative value to suppress that decoration and leave the region
  /// invisible, the Acrobat convention for linking existing text).
  void addLink(
    int pageIndex,
    List<PdfRect> quads,
    PdfLinkTarget target, {
    int? borderColor,
    int? underlineColor,
  }) {
    if (quads.isEmpty) return;
    apply((e) => _emitLink(
          e,
          pageIndex,
          quads,
          target,
          borderColor: borderColor,
          underlineColor: underlineColor,
        ));
  }

  /// Adds one hyperlink per page in [quadsByPage] pointing at [target],
  /// e.g. from a multi-page text selection. Mirrors [addMarkup]; links over
  /// selected text default to an underline decoration.
  void addLinkToSelection(
    Map<int, List<PdfRect>> quadsByPage,
    PdfLinkTarget target, {
    int? underlineColor,
    int? borderColor,
  }) {
    if (quadsByPage.values.every((quads) => quads.isEmpty)) return;
    apply((editor) {
      quadsByPage.forEach((page, quads) {
        if (quads.isEmpty) return;
        _emitLink(
          editor,
          page,
          quads,
          target,
          underlineColor:
              underlineColor ?? PdfAnnotationEditing.defaultLinkColor,
          borderColor: borderColor,
        );
      });
    });
  }

  /// Emits one link annotation for [target] over [quads]. When neither
  /// decoration is specified a border is drawn (so a bare box link is
  /// visible); a negative colour clears that decoration.
  void _emitLink(
    PdfEditor editor,
    int pageIndex,
    List<PdfRect> quads,
    PdfLinkTarget target, {
    int? borderColor,
    int? underlineColor,
  }) {
    final resolvedBorder = borderColor == null && underlineColor == null
        ? PdfAnnotationEditing.defaultLinkColor
        : (borderColor != null && borderColor >= 0 ? borderColor : null);
    final resolvedUnderline =
        underlineColor != null && underlineColor >= 0 ? underlineColor : null;
    final uri = target.uri;
    if (uri != null) {
      editor.addLinkToUri(
        pageIndex,
        quads,
        uri: uri,
        borderColor: resolvedBorder,
        underlineColor: resolvedUnderline,
      );
      return;
    }
    final destination = target.destination ??
        PdfExplicitDestination.fit(target.page ?? pageIndex);
    editor.addLinkToDestination(
      pageIndex,
      quads,
      destination: destination,
      borderColor: resolvedBorder,
      underlineColor: resolvedUnderline,
    );
  }

  /// Whether any page carries a marked (unburned) /Redact annotation.
  bool get hasRedactionMarks {
    for (var i = 0; i < _document.pageCount; i++) {
      if (pageAt(i).annotations.any((a) => a.subtype == 'Redact')) return true;
    }
    return false;
  }

  /// Burns every marked redaction across the document, irreversibly -
  /// covered text and images are removed from the content-stream bytes,
  /// the fill is painted, and the /Redact marks are deleted.
  ///
  /// Returns whether anything was burned. This RESETS the undo history:
  /// redaction cannot be undone (bringing the content back would defeat
  /// it), and the burned file is a fresh compaction, not a byte-prefix of
  /// the prior revision, so the prefix-based revision stack cannot hold it.
  bool applyRedactions() {
    if (!hasRedactionMarks) return false;
    final editor = PdfEditor(_document);
    final burned = editor.applyRedactions();
    _resetTo(burned, impact: editor.impact);
    return true;
  }

  /// Replaces the byte buffer with [bytes] as a fresh single revision,
  /// discarding undo history. Used by [applyRedactions] (the burned file
  /// is not a prefix of the prior buffer).
  void _resetTo(Uint8List bytes, {required PdfEditImpact impact}) {
    _bytes = bytes;
    _used = bytes.length;
    _revisions
      ..clear()
      ..add(bytes.length);
    _revisionImpacts
      ..clear()
      ..add(PdfEditImpact.none);
    _cursor = 0;
    _undoFloor = 0;
    _hardModified = true;
    // A burn recompacts the whole file: the new buffer is not a prefix-append
    // of the prior one, so the worker cannot update in place and must restart.
    _lastRevisionDelta = null;
    _selected.clear();
    _bumpRenderStamps(impact.visualPages);
    _bumpContentRenderStamps(impact.contentPages);
    // a burn removes content irreversibly - mark it destructive so the
    // viewer blanks each page's raster instead of holding the (now
    // un-redacted) one up while the fresh render lands
    if (impact.destructive) _destructiveStampEpoch++;
    _document = PdfDocument.open(bytes, password: _password);
    _revisionId++;
    _invalidateElements();
    notifyListeners();
  }

  void addEllipse(int pageIndex, PdfRect rect) => apply(
        (e) => e.addCircle(
          pageIndex,
          rect,
          strokeColor: _colorValue,
          strokeWidth: preferences.strokeWidth,
          fillColor: _rgbOf(preferences.shapeFillColor),
          opacity: preferences.opacity,
          dashPattern: _lineDashPattern,
          author: preferences.author,
        ),
      );

  /// Adds a line from [start] to [end]. With [arrow] the end carries a
  /// closed arrowhead (the dedicated arrow tool); otherwise the start and
  /// end endings come from the persisted [PdfEditingPreferences]
  /// ([preferences.lineStartEnding] / [preferences.lineEndEnding]).
  void addLine(
    int pageIndex,
    (double, double) start,
    (double, double) end, {
    bool arrow = false,
  }) =>
      apply(
        (e) => e.addLine(
          pageIndex,
          start,
          end,
          strokeColor: _colorValue,
          strokeWidth: preferences.strokeWidth,
          opacity: preferences.opacity,
          dashPattern: _lineDashPattern,
          startEnding: arrow ? PdfLineEnding.none : preferences.lineStartEnding,
          endEnding:
              arrow ? PdfLineEnding.closedArrow : preferences.lineEndEnding,
          author: preferences.author,
        ),
      );

  void addPolyLine(int pageIndex, List<(double, double)> points) => apply(
        (e) => e.addPolyLine(
          pageIndex,
          points,
          strokeColor: _colorValue,
          strokeWidth: preferences.strokeWidth,
          opacity: preferences.opacity,
          dashPattern: _lineDashPattern,
          startEnding: preferences.lineStartEnding,
          endEnding: preferences.lineEndEnding,
          author: preferences.author,
        ),
      );

  void addPolygon(int pageIndex, List<(double, double)> points) => apply(
        (e) => e.addPolygon(
          pageIndex,
          points,
          strokeColor: _colorValue,
          strokeWidth: preferences.strokeWidth,
          fillColor: _rgbOf(preferences.shapeFillColor),
          opacity: preferences.opacity,
          dashPattern: _lineDashPattern,
          author: preferences.author,
        ),
      );

  /// Drag out a rectangular cloudy /Polygon from an axis-aligned [rect].
  void addCloudPolygon(int pageIndex, PdfRect rect) =>
      addCloudPolygonPoints(pageIndex, [
        (rect.left, rect.bottom),
        (rect.right, rect.bottom),
        (rect.right, rect.top),
        (rect.left, rect.top),
      ]);

  /// Click out a cloudy /Polygon from an arbitrary vertex list (3+ points).
  void addCloudPolygonPoints(int pageIndex, List<(double, double)> points) =>
      apply(
        (e) => e.addPolygon(
          pageIndex,
          points,
          strokeColor: _colorValue,
          strokeWidth: preferences.strokeWidth,
          fillColor: _rgbOf(preferences.shapeFillColor),
          opacity: preferences.opacity,
          dashPattern: _lineDashPattern,
          cloudy: true,
          cloudScale: preferences.lineScale,
          author: preferences.author,
        ),
      );

  // ---------------------------------------------------------------------
  // measurements (§12.9)

  /// Whether a measurement tool can place an annotation right now - i.e. a
  /// scale has been calibrated.
  bool get hasMeasurementScale => preferences.measurementScale != null;

  /// The active measurement scale, forwarded to [preferences]. Setting it
  /// (e.g. from a calibration dialog or a test) calibrates every measurement
  /// tool at once.
  PdfMeasurementScale? get measurementScale => preferences.measurementScale;

  set measurementScale(PdfMeasurementScale? value) =>
      preferences.measurementScale = value;

  /// Calibrates [preferences.measurementScale] from a reference segment between
  /// [start] and [end] (page-space points) that represents [realLength]
  /// [unitLabel]s. The classic "two-point calibration" flow.
  void calibrateScale(
    (double, double) start,
    (double, double) end,
    double realLength,
    String unitLabel, {
    String pageUnitLabel = 'in',
    String? areaUnitLabel,
    int precision = 100,
  }) {
    final dx = end.$1 - start.$1;
    final dy = end.$2 - start.$2;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length <= 0 || realLength <= 0) return;
    preferences.measurementScale = PdfMeasurementScale.fromReference(
      pointLength: length,
      realLength: realLength,
      unitLabel: unitLabel,
      pageUnitLabel: pageUnitLabel,
      areaUnitLabel: areaUnitLabel,
      precision: precision,
    );
  }

  /// The live distance readout for a segment from [start] to [end]
  /// (page-space points), or null without a scale.
  String? measuredDistance((double, double) start, (double, double) end) {
    final scale = preferences.measurementScale;
    if (scale == null) return null;
    final dx = end.$1 - start.$1;
    final dy = end.$2 - start.$2;
    return scale.toMeasure().formatDistance(math.sqrt(dx * dx + dy * dy));
  }

  /// The live perimeter readout (sum of segment lengths) for a page-space
  /// polyline through [points], or null without a scale.
  String? measuredPerimeter(List<(double, double)> points) {
    final scale = preferences.measurementScale;
    if (scale == null || points.length < 2) return null;
    var total = 0.0;
    for (var i = 0; i + 1 < points.length; i++) {
      final dx = points[i + 1].$1 - points[i].$1;
      final dy = points[i + 1].$2 - points[i].$2;
      total += math.sqrt(dx * dx + dy * dy);
    }
    return scale.toMeasure().formatDistance(total);
  }

  /// The live area readout (shoelace) for a page-space polygon through
  /// [points], or null without a scale or fewer than three points.
  String? measuredArea(List<(double, double)> points) {
    final scale = preferences.measurementScale;
    if (scale == null || points.length < 3) return null;
    return scale.toMeasure().formatArea(pdfShoelaceArea(points));
  }

  /// The live net-area readout (outer shoelace minus [holes]) for a
  /// page-space polygon, or null without a scale or fewer than three points.
  String? measuredNetArea(
    List<(double, double)> points, [
    List<List<(double, double)>> holes = const [],
  ]) {
    final scale = preferences.measurementScale;
    if (scale == null || points.length < 3) return null;
    return scale.toMeasure().formatArea(pdfNetPolygonArea(points, holes));
  }

  /// The live volume readout (area × [depth], depth in the scale's unit)
  /// for a page-space polygon, or null without a scale.
  String? measuredVolume(List<(double, double)> points, double depth) {
    final scale = preferences.measurementScale;
    if (scale == null || points.length < 3) return null;
    return scale.toMeasure().formatVolume(pdfShoelaceArea(points), depth);
  }

  /// The live angle readout (degrees at the middle vertex) for the three
  /// page-space [points], or null with fewer than three. Needs no scale -
  /// an angle is unit-free.
  String? measuredAngle(List<(double, double)> points) {
    if (points.length < 3) return null;
    return (preferences.measurementScale?.toMeasure() ??
            PdfMeasure.scale(unitsPerPoint: 1, unitLabel: ''))
        .formatAngle(pdfMeasurementAngle(points));
  }

  /// The live slope readout (inclination above horizontal, degrees) for a
  /// segment from [start] to [end]. Needs no scale.
  String? measuredSlope((double, double) start, (double, double) end) {
    return (preferences.measurementScale?.toMeasure() ??
            PdfMeasure.scale(unitsPerPoint: 1, unitLabel: ''))
        .formatAngle(pdfSlopeDegrees(start, end));
  }

  /// The live arc-length readout for the three page-space [points] (start,
  /// mid, end on the arc), or null without a scale or fewer than three.
  String? measuredArc(List<(double, double)> points) {
    final scale = preferences.measurementScale;
    if (scale == null || points.length < 3) return null;
    final metrics = pdfArcMetrics(points[0], points[1], points[2]);
    final len = metrics?.length ?? pdfPolylineLength(points);
    return scale.toMeasure().formatDistance(len);
  }

  /// Adds a measurement annotation of [kind] through [points] using the
  /// active [preferences.measurementScale] (count needs none). [depth] feeds a volume,
  /// [holes] cut a net-area polygon, [label] buckets the running total.
  /// A no-op for a scaled kind without a scale.
  void addMeasurement(
    int pageIndex,
    PdfMeasurementKind kind,
    List<(double, double)> points, {
    double? depth,
    List<List<(double, double)>> holes = const [],
    String? label,
  }) {
    final scale = preferences.measurementScale;
    if (scale == null && kind != PdfMeasurementKind.count) return;
    apply(
      (e) => e.addMeasurement(
        pageIndex,
        kind,
        points,
        measure: scale?.toMeasure(),
        depth: depth,
        holes: holes,
        label: label,
        strokeColor: _colorValue,
        strokeWidth: preferences.strokeWidth,
        fillColor: _rgbOf(preferences.shapeFillColor),
        opacity: preferences.opacity,
        dashPattern: _lineDashPattern,
        // the caption is base-14 text; an embedded selection falls back
        // to the active standard family
        captionFont: preferences.fontFamily,
        captionSize: preferences.fontSize,
        startEnding: preferences.lineStartEnding,
        endEnding: preferences.lineEndEnding,
        author: preferences.author,
      ),
    );
  }

  /// Drops a single count marker at the page-space [point], tagged [label]
  /// so the running total tallies it with its siblings.
  void addCountMark(int pageIndex, (double, double) point, {String? label}) =>
      addMeasurement(
          pageIndex,
          PdfMeasurementKind.count,
          [
            point,
          ],
          label: label);

  /// The per-tool running totals over the live document - the takeoff
  /// register's data source. Rebuilt on demand (cheap: a single annotation
  /// walk), so callers refresh it whenever the controller notifies.
  PdfTakeoffSummary get takeoffSummary => PdfTakeoffSummary.of(_document);

  /// Writes the active [preferences.measurementScale] into the document itself (a /VP
  /// viewport /Measure on [pageIndex], or every page when null) so the
  /// drawing scale travels with the file - surviving a reopen and portable
  /// across devices - not just in this device's preferences. A no-op
  /// without a scale.
  void persistScaleToDocument({int? pageIndex}) {
    final scale = preferences.measurementScale;
    if (scale == null) return;
    final measure = scale.toMeasure();
    final pages = pageIndex != null
        ? [pageIndex]
        : List<int>.generate(_document.pageCount, (i) => i);
    apply(
      (e) {
        for (final p in pages) {
          e.setPageMeasurementScale(p, measure);
        }
      },
    );
  }

  /// Adopts the drawing scale the document already carries (a page /VP
  /// /Measure) when this session has none yet, so a reopened or shared file
  /// measures correctly without re-calibration. Returns true when a scale
  /// was adopted. Call after binding a new document.
  bool adoptDocumentScale() {
    if (preferences.measurementScale != null) return false;
    for (var i = 0; i < _document.pageCount; i++) {
      final m = _document.page(i).measure;
      if (m != null) {
        preferences.measurementScale = PdfMeasurementScale.fromMeasure(m);
        return true;
      }
    }
    return false;
  }

  bool _pageIsSideways(int pageIndex) {
    final r = _page(pageIndex).rotation % 360;
    return r == 90 || r == 270;
  }

  double _visualPageWidth(int pageIndex) {
    final box = _page(pageIndex).cropBox;
    return _pageIsSideways(pageIndex) ? box.height : box.width;
  }

  double _visualPageHeight(int pageIndex) {
    final box = _page(pageIndex).cropBox;
    return _pageIsSideways(pageIndex) ? box.width : box.height;
  }

  ({double width, double height}) _visualSizeOfPageRect(
    int pageIndex,
    PdfRect rect,
  ) {
    return _pageIsSideways(pageIndex)
        ? (width: rect.height, height: rect.width)
        : (width: rect.width, height: rect.height);
  }

  PdfRect _pageRectForVisualSize(
    int pageIndex,
    double x,
    double y, {
    required double width,
    required double height,
  }) {
    final box = _page(pageIndex).cropBox;
    final sideways = _pageIsSideways(pageIndex);
    final pageW = sideways ? height : width;
    final pageH = sideways ? width : height;
    final cx = x.clamp(box.left + pageW / 2, box.right - pageW / 2);
    final cy = y.clamp(box.bottom + pageH / 2, box.top - pageH / 2);
    return PdfRect(
      cx - pageW / 2,
      cy - pageH / 2,
      cx + pageW / 2,
      cy + pageH / 2,
    );
  }

  void addFreeText(int pageIndex, PdfRect rect, String text) => apply(
        (e) => e.addFreeText(
          pageIndex,
          rect,
          text,
          fontSize: preferences.fontSize,
          font: _activeFont ?? preferences.fontFamily,
          align: preferences.textAlign,
          color: _colorValue,
          fillColor: _rgbOf(preferences.textFillColor),
          borderColor: _rgbOf(preferences.textBorderColor),
          borderWidth: preferences.strokeWidth,
          lineSpacing: _lineSpacing,
          charSpacing: _charSpacing,
          horizontalScale: _fontWidth,
          underline: _textUnderline,
          pageRotation: _page(pageIndex).rotation,
          author: preferences.author,
        ),
      );

  /// Places a callout: a [text] box at [rect] with a leader line pointing at
  /// [target] on the page (both in page space). Mirrors [addFreeText] for the
  /// box styling and points the arrow with the tool's stroke color/width.
  void addCallout(
    int pageIndex,
    PdfRect rect,
    String text,
    (double, double) target,
  ) =>
      apply(
        (e) => e.addCallout(
          pageIndex,
          rect,
          text,
          target,
          fontSize: preferences.fontSize,
          font: _activeFont ?? preferences.fontFamily,
          align: preferences.textAlign,
          color: _colorValue,
          fillColor: _rgbOf(preferences.textFillColor),
          // the box outline and leader share one stroke; fall back to the
          // text color so the arrow always has a definite color/width
          strokeColor: _rgbOf(preferences.textBorderColor) ?? _colorValue,
          strokeWidth: preferences.strokeWidth,
          pageRotation: _page(pageIndex).rotation,
          author: preferences.author,
        ),
      );

  void addFreeTextRich(
    int pageIndex,
    PdfRect rect,
    List<PdfFreeTextRun> runs,
  ) =>
      apply(
        (e) => e.addFreeTextRich(
          pageIndex,
          rect,
          runs,
          align: preferences.textAlign,
          fillColor: _rgbOf(preferences.textFillColor),
          borderColor: _rgbOf(preferences.textBorderColor),
          borderWidth: preferences.strokeWidth,
          lineSpacing: _lineSpacing,
          charSpacing: _charSpacing,
          horizontalScale: _fontWidth,
          pageRotation: _page(pageIndex).rotation,
          author: preferences.author,
        ),
      );

  /// Places [text] as a default-sized FreeText annotation centered on
  /// ([x], [y]) in page space. This is used by keyboard paste from the
  /// system text clipboard, so the text lands under the cursor like
  /// annotation paste. The box is clamped into the page's crop box and
  /// the new annotation is selected.
  bool placeFreeText(
    int pageIndex,
    double x,
    double y,
    String text, {
    double width = 220,
  }) {
    final value = text.trimRight();
    if (value.trim().isEmpty) return false;
    if (pageIndex < 0 || pageIndex >= _document.pageCount) return false;
    final fontSize = preferences.fontSize;
    final lineHeight = fontSize * 1.2;
    final lines = value.split('\n').length.clamp(1, 12);
    final w = width.clamp(48.0, _visualPageWidth(pageIndex) * 0.9);
    final h = (lineHeight * lines + fontSize).clamp(
      24.0,
      _visualPageHeight(pageIndex) * 0.9,
    );
    final rect = _pageRectForVisualSize(pageIndex, x, y, width: w, height: h);
    final pasted = apply(
      (e) => e.addFreeText(
        pageIndex,
        rect,
        value,
        fontSize: fontSize,
        font: _activeFont ?? preferences.fontFamily,
        align: preferences.textAlign,
        color: _colorValue,
        fillColor: _rgbOf(preferences.textFillColor),
        borderColor: _rgbOf(preferences.textBorderColor),
        borderWidth: preferences.strokeWidth,
        pageRotation: _page(pageIndex).rotation,
        author: preferences.author,
      ),
    );
    if (!pasted) return false;
    tool = PdfEditTool.select;
    final total = _page(pageIndex).annotations.length;
    _selected
      ..clear()
      ..add((pageIndex, total - 1));
    notifyListeners();
    return true;
  }

  void addStamp(int pageIndex, PdfRect rect, String text, {int? color}) =>
      apply(
        (e) => e.addStamp(
          pageIndex,
          rect,
          text,
          color: color ?? _colorValue,
          opacity: preferences.opacity,
          pageRotation: _page(pageIndex).rotation,
          author: preferences.author,
        ),
      );

  void addCustomStamp(int pageIndex, PdfRect rect, PdfCustomStamp stamp) =>
      apply(
        (e) {
          final templateValues = _resolvedStampTemplateValues();
          final text = pdfResolveStampTemplateText(stamp.text, templateValues);
          final template = stamp.template;
          if (template == null) {
            e.addStamp(
              pageIndex,
              rect,
              text,
              color: stamp.color,
              opacity: preferences.opacity,
              pageRotation: _page(pageIndex).rotation,
              author: preferences.author,
              stampType: stamp.type,
              stampTags: stamp.tags,
            );
          } else {
            e.addTemplateStamp(
              pageIndex,
              rect,
              template,
              contents: text,
              color: stamp.color,
              opacity: preferences.opacity,
              pageRotation: _page(pageIndex).rotation,
              author: preferences.author,
              stampType: stamp.type,
              stampTags: stamp.tags,
              templateValues: templateValues,
            );
          }
        },
      );

  /// Places [imageBytes] (PNG or JPEG) centered on ([x], [y]) in page
  /// space, [maxSize] points on its longest side, preserving the image's
  /// aspect ratio and clamped so the whole image stays on the page.
  /// Returns false when the bytes aren't a decodable PNG or JPEG.
  bool placeImage(
    int pageIndex,
    double x,
    double y,
    Uint8List imageBytes, {
    double maxSize = 200,
  }) {
    final PdfEmbeddableImage image;
    try {
      image = PdfEmbeddableImage.decode(imageBytes);
    } catch (_) {
      return false;
    }
    return _placeDecodedImage(pageIndex, x, y, image, maxSize: maxSize);
  }

  /// Async counterpart to [placeImage]. PNG preparation can be CPU-heavy for
  /// large images, so the built-in UI uses this worker-backed path.
  Future<bool> placeImageAsync(
    int pageIndex,
    double x,
    double y,
    Uint8List imageBytes, {
    double maxSize = 200,
  }) async {
    final image = await _decodeEmbeddableImageAsync(imageBytes);
    if (image == null) return false;
    return _placeDecodedImage(pageIndex, x, y, image, maxSize: maxSize);
  }

  /// Inserts [imageBytes] (PNG or JPEG) fitted within [box] (page space),
  /// centered and preserving the image's aspect ratio. The drag-out
  /// counterpart of [placeImage]. Returns false when the bytes aren't a
  /// decodable PNG or JPEG, or [box] is degenerate.
  bool addImageInRect(int pageIndex, PdfRect box, Uint8List imageBytes) {
    if (box.width <= 0 || box.height <= 0) return false;
    final PdfEmbeddableImage image;
    try {
      image = PdfEmbeddableImage.decode(imageBytes);
    } catch (_) {
      return false;
    }
    return _addDecodedImageInRect(pageIndex, box, image);
  }

  /// Async counterpart to [addImageInRect]. See [placeImageAsync].
  Future<bool> addImageInRectAsync(
    int pageIndex,
    PdfRect box,
    Uint8List imageBytes,
  ) async {
    if (box.width <= 0 || box.height <= 0) return false;
    final image = await _decodeEmbeddableImageAsync(imageBytes);
    if (image == null) return false;
    return _addDecodedImageInRect(pageIndex, box, image);
  }

  Future<PdfEmbeddableImage?> _decodeEmbeddableImageAsync(
    Uint8List imageBytes,
  ) async {
    try {
      return await compute(
        _decodeEmbeddableImage,
        imageBytes,
        debugLabel: 'pdf-image-embed',
      );
    } catch (_) {
      return null;
    }
  }

  bool _placeDecodedImage(
    int pageIndex,
    double x,
    double y,
    PdfEmbeddableImage image, {
    required double maxSize,
  }) {
    final aspect = image.height == 0 ? 1.0 : image.width / image.height;
    var w = aspect >= 1 ? maxSize : maxSize * aspect;
    var h = aspect >= 1 ? maxSize / aspect : maxSize;
    final maxW = _visualPageWidth(pageIndex) * 0.9;
    final maxH = _visualPageHeight(pageIndex) * 0.9;
    if (w > maxW) (w, h) = (maxW, h * maxW / w);
    if (h > maxH) (w, h) = (w * maxH / h, maxH);
    return _addImageStamp(
      pageIndex,
      _pageRectForVisualSize(pageIndex, x, y, width: w, height: h),
      image,
    );
  }

  bool _addDecodedImageInRect(
    int pageIndex,
    PdfRect box,
    PdfEmbeddableImage image,
  ) {
    if (box.width <= 0 || box.height <= 0) return false;
    final aspect = image.height == 0 ? 1.0 : image.width / image.height;
    var (width: w, height: h) = _visualSizeOfPageRect(pageIndex, box);
    if (w / h > aspect) {
      w = h * aspect;
    } else {
      h = w / aspect;
    }
    final cx = (box.left + box.right) / 2, cy = (box.bottom + box.top) / 2;
    return _addImageStamp(
      pageIndex,
      _pageRectForVisualSize(pageIndex, cx, cy, width: w, height: h),
      image,
    );
  }

  bool _addImageStamp(int pageIndex, PdfRect rect, PdfEmbeddableImage image) {
    final added = apply(
      (e) => e.addImageStamp(
        pageIndex,
        rect,
        image,
        opacity: preferences.opacity,
        pageRotation: _page(pageIndex).rotation,
        author: preferences.author,
      ),
    );
    if (!added) return false;
    tool = PdfEditTool.select;
    final total = _page(pageIndex).annotations.length;
    _selected
      ..clear()
      ..add((pageIndex, total - 1));
    notifyListeners();
    return true;
  }

  /// Adds a sticky note with its top-left corner at ([x], [y]).
  void addNote(int pageIndex, double x, double y, String text) => apply(
        (e) => e.addNote(
          pageIndex,
          x,
          y,
          text,
          color: _colorValue,
          pageRotation: _page(pageIndex).rotation,
          author: preferences.author,
        ),
      );

  // ---------------------------------------------------------------------
  // signature

  /// The layout [placeSignature] would commit for a tap at ([x], [y]):
  /// the page-space strokes, pressures, ink color, and stroke width -
  /// what the signature tool's live preview paints under the pointer.
  /// The ink follows the currently selected [color] (not the colour the
  /// signature was drawn in), so recolouring the toolbar recolours the
  /// signature. Null when no signature is saved.
  ({
    List<List<(double, double)>> strokes,
    List<List<double>?> pressures,
    int color,
    double strokeWidth,
  })? signaturePlacement(int pageIndex, double x, double y,
      {double width = 160}) {
    final signature = preferences.signature;
    if (signature == null) return null;
    final box = _page(pageIndex).cropBox;
    final aspect = signature.aspect > 0 ? signature.aspect : 2.0;
    var w = width.clamp(8.0, box.width * 0.9);
    var h = w / aspect;
    if (h > box.height * 0.9) {
      h = box.height * 0.9;
      w = h * aspect;
    }
    final cx = x.clamp(box.left + w / 2, box.right - w / 2);
    final cy = y.clamp(box.bottom + h / 2, box.top - h / 2);
    final left = cx - w / 2, top = cy + h / 2;
    return (
      strokes: [
        for (final stroke in signature.strokes)
          [
            // normalized pad space is y-down; page space is y-up
            for (final (nx, ny) in stroke) (left + nx * w, top - ny * h),
          ],
      ],
      pressures: signature.pressures,
      // follow the selected toolbar colour, like every other tool
      color: _colorValue,
      strokeWidth: w / 60, // pen-like: ~2.7pt at the default width
    );
  }

  /// Stamps [preferences.signature] as an Ink annotation centered on ([x], [y]) in
  /// page space, [width] points wide (clamped, with the center, so the
  /// whole signature stays on the page). Keeps the signature's own ink
  /// color and pen pressures. Returns false when none is saved.
  bool placeSignature(int pageIndex, double x, double y, {double width = 160}) {
    final placement = signaturePlacement(pageIndex, x, y, width: width);
    if (placement == null) return false;
    return apply(
      (e) => e.addInk(
        pageIndex,
        placement.strokes,
        color: placement.color,
        strokeWidth: placement.strokeWidth,
        opacity: 1,
        pressures: placement.pressures,
        author: preferences.author,
      ),
    );
  }

  // ---------------------------------------------------------------------
  // custom stamps

  List<PdfCustomStamp> _providedCustomStamps = const [];

  /// Stamps supplied by the host app for this editing session.
  ///
  /// They are shown alongside [savedCustomStamps] in the picker but are not
  /// written to [preferences]. Use this for organization/workflow stamps
  /// managed by the Flutter app.
  List<PdfCustomStamp> get providedCustomStamps => _providedCustomStamps;

  set providedCustomStamps(List<PdfCustomStamp> value) {
    final next = List<PdfCustomStamp>.unmodifiable(value);
    if (listEquals(next, _providedCustomStamps)) return;
    _providedCustomStamps = next;
    final active = _activeStamp;
    if (active != null &&
        !next.contains(active) &&
        !preferences.customStamps.contains(active)) {
      _activeStamp = null;
    }
    notifyListeners();
  }

  /// User-authored custom stamps persisted on this device.
  List<PdfCustomStamp> get savedCustomStamps => preferences.customStamps;

  /// The user's saved custom stamps. Persisted with the other
  /// [preferences], so they survive app restarts. Created in
  /// [showPdfStampEditor] (usually via the picker, [showPdfStampPicker]).
  ///
  /// This combines [providedCustomStamps] and [savedCustomStamps].
  List<PdfCustomStamp> get customStamps => List.unmodifiable([
        ..._providedCustomStamps,
        ...preferences.customStamps,
      ]);

  /// Whether [stamp] is one of the user's saved, removable stamps.
  bool isSavedCustomStamp(PdfCustomStamp stamp) =>
      preferences.customStamps.contains(stamp);

  /// Appends [stamp] to the saved list.
  void saveCustomStamp(PdfCustomStamp stamp) =>
      preferences.customStamps = [...preferences.customStamps, stamp];

  /// Replaces a user-saved stamp with [next]. If [stamp] is active, the
  /// edited stamp remains active. Returns false for app-supplied stamps.
  bool replaceCustomStamp(PdfCustomStamp stamp, PdfCustomStamp next) {
    final saved = preferences.customStamps;
    final index = saved.indexOf(stamp);
    if (index == -1) return false;
    if (_activeStamp == stamp) _activeStamp = next;
    preferences.customStamps = [
      for (var i = 0; i < saved.length; i++) i == index ? next : saved[i],
    ];
    return true;
  }

  /// Removes [stamp] from the saved list. If it was the active stamp,
  /// the stamp tool falls back to prompting for text.
  void removeCustomStamp(PdfCustomStamp stamp) {
    preferences.customStamps = [
      for (final saved in preferences.customStamps)
        if (saved != stamp) saved,
    ];
    if (_activeStamp == stamp) {
      _activeStamp = null;
      notifyListeners();
    }
  }

  PdfCustomStamp? _activeStamp;

  /// The custom stamp the stamp tool places on tap. Null means the
  /// classic flow: drag out a box and type the caption. Not persisted -
  /// each session starts in the classic flow.
  PdfCustomStamp? get activeStamp => _activeStamp;

  set activeStamp(PdfCustomStamp? value) {
    if (value == _activeStamp) return;
    _activeStamp = value;
    notifyListeners();
  }

  void _recolorActiveStamp(Color color) {
    final active = _activeStamp;
    if (active == null) return;
    final rgb = color.toARGB32() & 0xFFFFFF;
    final next = PdfCustomStamp(
      text: active.text,
      color: rgb,
      template: active.template == null
          ? null
          : PdfStampTemplate(
              width: active.template!.width,
              height: active.template!.height,
              components: [
                for (final component in active.template!.components)
                  component.type == PdfStampTemplateComponentType.image
                      ? component
                      : component.copyWith(color: rgb),
              ],
            ),
      type: active.type,
      tags: active.tags,
    );
    if (next == active) return;
    _activeStamp = next;
    final saved = preferences.customStamps;
    final savedIndex = saved.indexOf(active);
    if (savedIndex == -1) {
      notifyListeners();
      return;
    }
    preferences.customStamps = [
      for (var i = 0; i < saved.length; i++) i == savedIndex ? next : saved[i],
    ];
  }

  /// Places [activeStamp] centered on ([x], [y]) in page space. Text-only
  /// stamps default to 40 points tall and auto-size from their caption;
  /// template stamps default to the template's own width/height. Passing
  /// [height] keeps the old explicit-height behavior for either kind. The
  /// result is clamped with the center so the whole stamp stays on the page.
  /// Returns false when no stamp is active.
  bool placeStamp(int pageIndex, double x, double y, {double? height}) {
    final stamp = _activeStamp;
    if (stamp == null) return false;
    final template = stamp.template;
    if (template != null) {
      final rect = _stampTemplatePlacement(
        pageIndex,
        x,
        y,
        template,
        height: height,
      );
      if (rect == null) return false;
      return apply(
        (e) {
          final templateValues = _resolvedStampTemplateValues();
          e.addTemplateStamp(
            pageIndex,
            rect,
            template,
            contents: pdfResolveStampTemplateText(stamp.text, templateValues),
            color: stamp.color,
            opacity: preferences.opacity,
            pageRotation: _page(pageIndex).rotation,
            author: preferences.author,
            stampType: stamp.type,
            stampTags: stamp.tags,
            templateValues: templateValues,
          );
        },
      );
    }
    return placeTextStamp(
      pageIndex,
      x,
      y,
      _resolveStampText(stamp.text),
      height: height ?? 40,
      color: stamp.color,
      stampType: stamp.type,
      stampTags: stamp.tags,
    );
  }

  /// The page-space rect [placeStamp] would use for the current
  /// [activeStamp]. Null when no stamp is active or its template is invalid.
  PdfRect? stampPlacement(int pageIndex, double x, double y, {double? height}) {
    final stamp = _activeStamp;
    if (stamp == null) return null;
    final template = stamp.template;
    return template == null
        ? textStampPlacement(
            pageIndex,
            x,
            y,
            _resolveStampText(stamp.text),
            height: height ?? 40,
          )
        : _stampTemplatePlacement(pageIndex, x, y, template, height: height);
  }

  PdfRect? _stampTemplatePlacement(
    int pageIndex,
    double x,
    double y,
    PdfStampTemplate template, {
    double? height,
  }) {
    if (!template.isValid) return null;
    final h = (height ?? template.height).clamp(
      8.0,
      _visualPageHeight(pageIndex) * 0.9,
    );
    final aspect = template.width / template.height;
    var w = h * aspect;
    final maxW = _visualPageWidth(pageIndex) * 0.9;
    final maxH = _visualPageHeight(pageIndex) * 0.9;
    var fittedH = h;
    if (w > maxW) {
      w = maxW;
      fittedH = w / aspect;
    }
    if (fittedH > maxH) {
      fittedH = maxH;
      w = fittedH * aspect;
    }
    return _pageRectForVisualSize(pageIndex, x, y, width: w, height: fittedH);
  }

  /// Places a default-sized stamp captioned [text], centered on ([x], [y])
  /// in page space and auto-sized from the caption (like [placeStamp], but
  /// with arbitrary text/colour). This is the stamp tool's tap-to-place:
  /// tapping without dragging out a box drops a stamp at a sensible size.
  /// [color] null uses the selected toolbar colour.
  bool placeTextStamp(
    int pageIndex,
    double x,
    double y,
    String text, {
    double height = 40,
    int? color,
    String? stampType,
    Iterable<String> stampTags = const [],
  }) {
    final rect = textStampPlacement(pageIndex, x, y, text, height: height);
    return apply(
      (e) => e.addStamp(
        pageIndex,
        rect,
        text,
        color: color ?? _colorValue,
        opacity: preferences.opacity,
        pageRotation: _page(pageIndex).rotation,
        author: preferences.author,
        stampType: stampType,
        stampTags: stampTags,
      ),
    );
  }

  /// The page-space rect [placeTextStamp] would use.
  PdfRect textStampPlacement(
    int pageIndex,
    double x,
    double y,
    String text, {
    double height = 40,
  }) {
    final h = height.clamp(8.0, _visualPageHeight(pageIndex) * 0.9);
    // mirror addStamp's appearance math (6pt padding, text 72% of the
    // height) so the caption fills the box without shrinking
    final fontSize = (h - 12) * 0.72;
    final w = (measureHelvetica(text, fontSize, bold: true) + 24).clamp(
      h,
      _visualPageWidth(pageIndex) * 0.9,
    );
    return _pageRectForVisualSize(pageIndex, x, y, width: w, height: h);
  }

  // ---------------------------------------------------------------------
  // count tool (check-marks)

  /// The default check-mark side length, in PDF points. A tap with the
  /// count tool drops a mark this big centered on the pointer.
  static const double checkMarkSize = 18.0;

  /// Drops a check-mark centered on ([x], [y]) in page space, [size] points
  /// per side (clamped, with the centre, so the whole mark stays on the
  /// page). The mark follows the selected toolbar [color] and [preferences.opacity] and
  /// is a real /Stamp annotation, so it can be moved, resized, and deleted
  /// like any other. This is the count tool's tap-to-place - repeated taps
  /// build the tally exposed by [checkMarkCount], Bluebeam-style.
  bool placeCheckMark(
    int pageIndex,
    double x,
    double y, {
    double size = checkMarkSize,
  }) {
    final box = _page(pageIndex).cropBox;
    final s = size.clamp(4.0, math.min(box.width, box.height) * 0.9);
    final cx = x.clamp(box.left + s / 2, box.right - s / 2);
    final cy = y.clamp(box.bottom + s / 2, box.top - s / 2);
    return apply(
      (e) => e.addCheckMark(
        pageIndex,
        PdfRect(cx - s / 2, cy - s / 2, cx + s / 2, cy + s / 2),
        color: _colorValue,
        opacity: preferences.opacity,
        pageRotation: _page(pageIndex).rotation,
        author: preferences.author,
      ),
    );
  }

  int? _checkMarkCount;

  /// The live count of check-marks ([PdfAnnotation.isCheckMark]) across the
  /// whole document - the count tool's running tally. Recomputed per
  /// revision (so undo, delete, and remote edits keep it accurate) and
  /// cached. Walking the pages is cheap (counts are small) and only happens
  /// on demand, when the count UI reads it.
  int get checkMarkCount => _checkMarkCount ??= _countCheckMarks();

  int _countCheckMarks() {
    var total = 0;
    for (var i = 0; i < _document.pageCount; i++) {
      for (final annotation in _page(i).annotations) {
        if (annotation.isCheckMark) total++;
      }
    }
    return total;
  }

  /// Bakes every page's annotation appearances into its content and
  /// removes the annotations. Returns whether anything was flattened
  /// (false when no page carried a flattenable annotation).
  bool flattenAllAnnotations() => apply((editor) {
        for (var i = 0; i < _document.pageCount; i++) {
          editor.flattenAnnotations(i);
        }
      });

  // ---------------------------------------------------------------------
  // pages

  /// Moves the page at [from] so it ends up at index [to]. When [from] is
  /// part of a multi-page selection, the whole selection moves with it,
  /// preserving the selected pages' document order. The dragged page lands
  /// at [to] whenever the block fits there; at either document edge the block
  /// is clamped as a unit.
  ///
  /// Structural page edits shift page indices, so the annotation selection
  /// (a page-indexed slot) is cleared first. A moved page selection follows
  /// the pages to their new contiguous positions.
  void movePage(int from, int to) {
    if (from == to) return;
    final moving = selectedPages;
    if (moving.length > 1 && moving.contains(from)) {
      // Dropping anywhere inside the selection is not a move. This also
      // prevents a discontiguous selection from unexpectedly compacting when
      // one of its own tiles is used as the drop target.
      if (moving.contains(to)) return;
      final draggedOffset = moving.indexOf(from);
      final remaining = [
        for (var i = 0; i < _document.pageCount; i++)
          if (!moving.contains(i)) i,
      ];
      final start = (to - draggedOffset).clamp(0, remaining.length);
      final order = List<int>.of(remaining)..insertAll(start, moving);

      _selected.clear();
      final changed = apply((e) => e.reorderPages(order));
      if (!changed) return;
      _selectedPages.addAll([
        for (var i = 0; i < moving.length; i++) start + i,
      ]);
      _pageSelectionAnchor = start + draggedOffset;
      notifyListeners();
      return;
    }
    _selected.clear();
    _selectedPages.clear();
    _pageSelectionAnchor = null;
    apply((e) => e.movePage(from, to));
  }

  /// Removes the page at [index]. Refused (a no-op) on the last page -
  /// a document must keep at least one.
  void removePage(int index) {
    if (_document.pageCount <= 1) return;
    _selected.clear();
    _selectedPages.clear();
    _pageSelectionAnchor = null;
    apply((e) => e.removePage(index));
  }

  /// Inserts a new blank page at [at] (default: appended at the end),
  /// sized [width] × [height] points. When neither dimension is given the
  /// page matches its neighbour's size (the page before [at], else the
  /// last page) so the blank page fits the document instead of jumping to
  /// Letter. Structural page edits shift indices, so the annotation
  /// selection is cleared first.
  void addBlankPage({double? width, double? height, int? at}) {
    _selected.clear();
    _selectedPages.clear();
    _pageSelectionAnchor = null;
    final insertAt = at ?? _document.pageCount;
    if (width == null && height == null && _document.pageCount > 0) {
      final neighbour = (insertAt > 0 ? insertAt - 1 : 0).clamp(
        0,
        _document.pageCount - 1,
      );
      final box = _document.page(neighbour).mediaBox;
      width = box.width;
      height = box.height;
    }
    apply((e) => e.insertBlankPage(width: width, height: height, at: at));
  }

  /// Inserts pages from another open [source] document at [at] (default:
  /// appended at the end). [indices] picks a subset of [source] (default:
  /// all of it, in order). Everything each page references - content,
  /// resources, fonts, images, annotations - is deep-copied across.
  void insertPagesFrom(PdfDocument source, {List<int>? indices, int? at}) {
    _selected.clear();
    _selectedPages.clear();
    _pageSelectionAnchor = null;
    apply((e) => e.appendPagesFrom(source, indices: indices, at: at));
  }

  /// Inserts pages from the PDF in [bytes] (opened with [password] when
  /// encrypted) at [at]. Convenience over [insertPagesFrom] for a file a
  /// host just read off disk.
  void insertPagesFromBytes(
    Uint8List bytes, {
    String password = '',
    List<int>? indices,
    int? at,
  }) {
    insertPagesFrom(
      PdfDocument.open(bytes, password: password),
      indices: indices,
      at: at,
    );
  }

  /// Duplicates [indices] (deep-copying each page and everything it
  /// references), inserting the copies as one contiguous block right
  /// after the last of them and preserving their order. Returns false (a
  /// no-op) when nothing valid is given. Structural page edits shift
  /// indices, so the page selection is cleared first.
  bool duplicatePages(Iterable<int> indices) {
    final targets = indices
        .where((i) => i >= 0 && i < _document.pageCount)
        .toSet()
        .toList()
      ..sort();
    if (targets.isEmpty) return false;
    _selected.clear();
    _selectedPages.clear();
    _pageSelectionAnchor = null;
    // appendPagesFrom refuses a page's own document object; reopening the
    // current bytes gives a separate source, so a page can be copied back
    // into the file it came from.
    final source = PdfDocument.open(bytes, password: _password);
    return apply(
      (e) => e.appendPagesFrom(source, indices: targets, at: targets.last + 1),
    );
  }

  /// Exports [indices] (in that order) as a fresh standalone PDF, leaving
  /// this document untouched. See [PdfPageExtraction.extractPages].
  Uint8List exportPages(List<int> indices) => _document.extractPages(indices);

  /// Exports pages [start] through [end] inclusive as a standalone PDF.
  Uint8List exportPageRange(int start, int end) =>
      _document.extractPageRange(start, end);

  // ---------------------------------------------------------------------
  // page selection (the thumbnail strip's multi-select)

  /// The set of selected page indices - the thumbnail strip's
  /// click/shift-click/⌘-click selection. Distinct from the annotation
  /// selection; it drives bulk page operations (delete, export). Any
  /// structural page edit (move/remove/insert) shifts indices, so it is
  /// cleared by those.
  final Set<int> _selectedPages = {};

  /// The anchor a shift-click extends a range from - the last page
  /// clicked without shift (a plain or ⌘ click).
  int? _pageSelectionAnchor;

  /// The selected page indices, ascending. Empty when nothing is
  /// selected in the strip.
  List<int> get selectedPages => _selectedPages.toList()..sort();

  bool get hasPageSelection => _selectedPages.isNotEmpty;

  /// How many pages are selected in the strip.
  int get selectedPageCount => _selectedPages.length;

  bool isPageSelected(int index) => _selectedPages.contains(index);

  /// Selects exactly [index] (clearing any previous selection) and makes
  /// it the anchor for a subsequent [selectPageRange]. The plain-click
  /// gesture.
  void selectPage(int index) {
    _pageSelectionAnchor = index;
    if (_selectedPages.length == 1 && _selectedPages.contains(index)) return;
    _selectedPages
      ..clear()
      ..add(index);
    notifyListeners();
  }

  /// Toggles [index] in the selection (the ⌘/Ctrl-click gesture) and
  /// re-anchors there so a following shift-click extends from it.
  void togglePageSelection(int index) {
    if (!_selectedPages.remove(index)) _selectedPages.add(index);
    _pageSelectionAnchor = index;
    notifyListeners();
  }

  /// The page a shift-click extends a range from, or null when nothing
  /// has anchored it yet - the strip reads it to preview the range while
  /// Shift is held.
  int? get pageSelectionAnchor => _pageSelectionAnchor;

  /// The pages a shift-click on [index] would select right now: the
  /// contiguous run from the current anchor to [index] (ascending), or
  /// just [index] with no anchor yet. The live preview the strip paints
  /// while Shift is held - mirrors [selectPageRange] without committing.
  List<int> pageRangePreviewTo(int index) {
    final anchor = _pageSelectionAnchor ?? index;
    final lo = math.min(anchor, index);
    final hi = math.max(anchor, index);
    return [for (var i = lo; i <= hi; i++) i];
  }

  /// Selects the contiguous range from the current anchor to [index]
  /// (the shift-click gesture), replacing the selection. With no anchor
  /// yet, behaves like [selectPage]. The anchor stays put, so a further
  /// shift-click re-extends from the same origin.
  void selectPageRange(int index) {
    final anchor = _pageSelectionAnchor ?? index;
    final lo = math.min(anchor, index);
    final hi = math.max(anchor, index);
    _pageSelectionAnchor = anchor;
    _selectedPages
      ..clear()
      ..addAll([for (var i = lo; i <= hi; i++) i]);
    notifyListeners();
  }

  /// Selects every page.
  void selectAllPages() {
    final all = {for (var i = 0; i < _document.pageCount; i++) i};
    if (_selectedPages.length == all.length) return;
    _selectedPages
      ..clear()
      ..addAll(all);
    _pageSelectionAnchor = 0;
    notifyListeners();
  }

  /// Clears the page selection.
  void clearPageSelection() {
    if (_selectedPages.isEmpty) return;
    _selectedPages.clear();
    _pageSelectionAnchor = null;
    notifyListeners();
  }

  /// Removes the selected pages in one edit (one undo). Refused (a no-op,
  /// returns false) when nothing is selected or the selection would empty
  /// the document - at least one page must remain. Clears the selection.
  bool removeSelectedPages() {
    final doomed =
        _selectedPages.where((i) => i >= 0 && i < _document.pageCount).toList();
    if (doomed.isEmpty || doomed.length >= _document.pageCount) return false;
    _selected.clear();
    _selectedPages.clear();
    _pageSelectionAnchor = null;
    return apply((e) => e.removePages(doomed));
  }

  /// Exports the selected pages (ascending) as a fresh standalone PDF,
  /// leaving this document untouched. Null when nothing is selected.
  Uint8List? exportSelectedPages() =>
      _selectedPages.isEmpty ? null : exportPages(selectedPages);

  // ---------------------------------------------------------------------
  // page clipboard (copy / cut / paste, shared across document tabs)

  /// Whether [pastePages] has pages waiting on the shared [pageClipboard].
  bool get hasPageClipboard => pageClipboard.isNotEmpty;

  /// Copies [indices] (de-duplicated, ascending) onto the shared
  /// [pageClipboard] as a self-contained PDF, leaving this document
  /// untouched. Because the clipboard is shared, the copy can then be
  /// pasted into this document or a different open document tab. Returns
  /// false (a no-op) when no valid page is given.
  bool copyPages(Iterable<int> indices) {
    final targets = indices
        .where((i) => i >= 0 && i < _document.pageCount)
        .toSet()
        .toList()
      ..sort();
    if (targets.isEmpty) return false;
    pageClipboard.setPages(exportPages(targets), targets.length);
    return true;
  }

  /// Copies the strip's selected pages onto the shared [pageClipboard].
  /// A no-op (returns false) when nothing is selected.
  bool copySelectedPages() => copyPages(selectedPages);

  /// Copies [indices] onto the shared [pageClipboard] and removes them in
  /// one edit (one undo) - copy + delete. Refused (nothing copied, nothing
  /// removed, returns false) when the pages would empty the document; at
  /// least one page must remain. Clears the page selection, like
  /// [removeSelectedPages].
  bool cutPages(Iterable<int> indices) {
    final targets = indices
        .where((i) => i >= 0 && i < _document.pageCount)
        .toSet()
        .toList()
      ..sort();
    if (targets.isEmpty || targets.length >= _document.pageCount) return false;
    pageClipboard.setPages(exportPages(targets), targets.length);
    _selected.clear();
    _selectedPages.clear();
    _pageSelectionAnchor = null;
    return apply((e) => e.removePages(targets));
  }

  /// Cuts the strip's selected pages onto the shared [pageClipboard].
  /// A no-op (returns false) when nothing is selected or the cut would
  /// empty the document.
  bool cutSelectedPages() => cutPages(selectedPages);

  /// Inserts the shared [pageClipboard]'s pages at [at] (default: appended
  /// at the end) and selects the pasted block. Because the clipboard is
  /// shared across tabs, this pastes pages copied from any document.
  /// Returns false (a no-op) when the clipboard is empty. The paste is one
  /// undoable edit.
  bool pastePages({int? at}) {
    final bytes = pageClipboard.bytes;
    if (bytes == null) return false;
    final count = pageClipboard.pageCount;
    final insertAt = (at ?? _document.pageCount).clamp(0, _document.pageCount);
    insertPagesFromBytes(bytes, at: insertAt);
    // surface what landed: select the pasted run so the strip highlights it
    _selectedPages
      ..clear()
      ..addAll([for (var i = insertAt; i < insertAt + count; i++) i]);
    _pageSelectionAnchor = insertAt;
    notifyListeners();
    return true;
  }

  /// Rotates [indices] clockwise by [degrees] (a multiple of 90; negative
  /// turns counterclockwise) in one edit (one undo). Rotation is a visual
  /// change that does not shift page indices, so the page selection is
  /// preserved. Returns false (a no-op) when nothing is given or the
  /// rotation is a full turn.
  bool rotatePages(Iterable<int> indices, int degrees) {
    final targets = indices
        .where((i) => i >= 0 && i < _document.pageCount)
        .toSet()
        .toList()
      ..sort();
    if (targets.isEmpty || degrees % 360 == 0) return false;
    return apply((e) => e.rotatePages(targets, degrees));
  }

  /// Rotates the selected pages clockwise by [degrees] (default: 90; pass
  /// -90 to turn counterclockwise) in one edit. A no-op (returns false)
  /// when nothing is selected in the strip. The page selection is
  /// preserved.
  bool rotateSelectedPages([int degrees = 90]) =>
      rotatePages(selectedPages, degrees);

  /// Returns explicit page-content colors across [pages], or the whole
  /// document when [pages] is null.
  ///
  /// The list is sorted by frequency descending. It scans content-stream
  /// color operators, not raster image pixels, annotations, shadings,
  /// patterns, form XObjects, or implicit default black.
  List<Color> documentContentColors({
    Iterable<int>? pages,
    bool fill = true,
    bool stroke = true,
  }) {
    final targets = (pages ??
            Iterable<int>.generate(_document.pageCount, (index) => index))
        .where((index) => index >= 0 && index < _document.pageCount)
        .toSet()
        .toList()
      ..sort();
    if (targets.isEmpty || (!fill && !stroke)) return const [];
    final editor = PdfEditor(_document);
    return [
      for (final color in editor.contentColorsOnPages(
        targets,
        fill: fill,
        stroke: stroke,
      ))
        Color(0xFF000000 | color.rgb),
    ];
  }

  /// Asynchronously scans page-content colors, yielding between pages.
  ///
  /// This is intended for UI previews over large documents: [yieldAfterPage]
  /// gives the caller a chance to paint progress between pages, [onProgress]
  /// reports completed pages, and [isCancelled] lets newer scans supersede
  /// older ones.
  Future<List<Color>> documentContentColorsAsync({
    Iterable<int>? pages,
    bool fill = true,
    bool stroke = true,
    bool Function()? isCancelled,
    void Function(int completed, int total)? onProgress,
    Future<void> Function()? yieldAfterPage,
  }) async {
    final targets = (pages ??
            Iterable<int>.generate(_document.pageCount, (index) => index))
        .where((index) => index >= 0 && index < _document.pageCount)
        .toSet()
        .toList()
      ..sort();
    if (targets.isEmpty || (!fill && !stroke)) return const [];
    final editor = PdfEditor(_document);
    final uses = <int, List<int>>{};
    for (var i = 0; i < targets.length; i++) {
      if (isCancelled?.call() ?? false) return const [];
      final pageColors = editor.contentColors(
        targets[i],
        fill: fill,
        stroke: stroke,
      );
      for (final color in pageColors) {
        final counts = uses.putIfAbsent(color.rgb, () => [0, 0]);
        counts[0] += color.fillUses;
        counts[1] += color.strokeUses;
      }
      onProgress?.call(i + 1, targets.length);
      if (i < targets.length - 1 && yieldAfterPage != null) {
        await yieldAfterPage();
      }
    }
    final entries = uses.entries.toList()
      ..sort((a, b) {
        final aUses = a.value[0] + a.value[1];
        final bUses = b.value[0] + b.value[1];
        final byUses = bUses.compareTo(aUses);
        return byUses != 0 ? byUses : a.key.compareTo(b.key);
      });
    return [for (final entry in entries) Color(0xFF000000 | entry.key)];
  }

  /// The colours already used by the document's annotations - each
  /// annotation's /C stroke colour and /IC interior fill - as opaque
  /// Flutter colours, most-frequent first and deduplicated by RGB.
  ///
  /// Cheap and synchronous (a dictionary read per annotation, no content
  /// stream scan), so it is the "In document" quick-pick grid the colour
  /// picker shows while styling annotations. Capped at [limit] entries.
  List<Color> documentAnnotationColors({int limit = 24}) {
    final counts = <int, int>{};
    for (var pageIndex = 0; pageIndex < _document.pageCount; pageIndex++) {
      for (final annotation in _page(pageIndex).annotations) {
        for (final rgb in [annotation.color, annotation.interiorColor]) {
          if (rgb == null) continue;
          counts.update(rgb & 0xFFFFFF, (n) => n + 1, ifAbsent: () => 1);
        }
      }
    }
    final entries = counts.entries.toList()
      ..sort((a, b) {
        final byUses = b.value.compareTo(a.value);
        return byUses != 0 ? byUses : a.key.compareTo(b.key);
      });
    return [
      for (final entry in entries.take(limit)) Color(0xFF000000 | entry.key),
    ];
  }

  /// Replaces matching page-content colors across [pages], or the whole
  /// document when [pages] is null. Returns the number of color-setting
  /// operators rewritten, or the number of paint sides suppressed when
  /// [transparent] is true.
  ///
  /// [find], [findColors], and [replace] are opaque Flutter colors; alpha is
  /// ignored. Pass [findColors] to replace several source colors in one pass.
  /// [replace] may be omitted only when [transparent] is true. [tolerance] is
  /// an 8-bit per-channel tolerance. This is an undoable edit over page
  /// content streams (text/vector colors), not annotation styling or raster
  /// image pixel editing.
  int replaceDocumentColors({
    Color? find,
    Iterable<Color>? findColors,
    Color? replace,
    Iterable<int>? pages,
    int tolerance = 0,
    bool fill = true,
    bool stroke = true,
    bool transparent = false,
  }) {
    final targets = (pages ??
            Iterable<int>.generate(_document.pageCount, (index) => index))
        .where((index) => index >= 0 && index < _document.pageCount)
        .toSet()
        .toList()
      ..sort();
    if (targets.isEmpty || (!fill && !stroke)) return 0;
    final finds = {
      if (find != null) find.toARGB32() & 0xFFFFFF,
      if (findColors != null)
        for (final color in findColors) color.toARGB32() & 0xFFFFFF,
    }.toList()
      ..sort();
    if (finds.isEmpty) return 0;
    if (!transparent && replace == null) {
      throw ArgumentError.notNull('replace');
    }
    var count = 0;
    final changed = apply((editor) {
      count = editor.replaceColorsOnPages(
        targets,
        finds: finds,
        replace: replace?.toARGB32() ?? 0,
        tolerance: tolerance,
        fill: fill,
        stroke: stroke,
        transparent: transparent,
      );
    });
    return changed ? count : 0;
  }

  /// Background version of [replaceDocumentColors].
  ///
  /// The replacement work runs against a reopened copy of the current bytes in
  /// a background worker where Flutter supports one, then commits the returned
  /// file as one undoable revision. This keeps large whole-document jobs from
  /// blocking pointer/paint events in the UI isolate on desktop/mobile. If
  /// another edit lands before the worker returns, the stale result is ignored
  /// and zero is returned.
  Future<int> replaceDocumentColorsAsync({
    Color? find,
    Iterable<Color>? findColors,
    Color? replace,
    Iterable<int>? pages,
    int tolerance = 0,
    bool fill = true,
    bool stroke = true,
    bool transparent = false,
  }) async {
    final targets = (pages ??
            Iterable<int>.generate(_document.pageCount, (index) => index))
        .where((index) => index >= 0 && index < _document.pageCount)
        .toSet()
        .toList()
      ..sort();
    if (targets.isEmpty || (!fill && !stroke)) return 0;
    final finds = {
      if (find != null) find.toARGB32() & 0xFFFFFF,
      if (findColors != null)
        for (final color in findColors) color.toARGB32() & 0xFFFFFF,
    }.toList()
      ..sort();
    if (finds.isEmpty) return 0;
    if (!transparent && replace == null) {
      throw ArgumentError.notNull('replace');
    }

    final beforeCursor = _cursor;
    final beforeLength = _revisions[_cursor];
    final result = await compute<Map<String, Object?>, Map<String, Object?>>(
      _replaceDocumentColorsOnWorker,
      {
        'bytes': bytes,
        'password': _password,
        'pages': targets,
        'finds': finds,
        'replace': replace?.toARGB32() ?? 0,
        'tolerance': tolerance,
        'fill': fill,
        'stroke': stroke,
        'transparent': transparent,
      },
      debugLabel: 'PDF color processing',
    );
    final count = result['count'] as int? ?? 0;
    final saved = result['bytes'] as Uint8List?;
    if (count == 0 || saved == null) return 0;
    if (_cursor != beforeCursor || _revisions[_cursor] != beforeLength) {
      return 0;
    }

    List<int>? pagesFrom(String key) {
      final value = result[key];
      return value == null ? null : (value as List).cast<int>();
    }

    final impact = PdfEditImpact.reported(
      visualPages: pagesFrom('visualPages'),
      contentPages: pagesFrom('contentPages'),
      annotationPages: pagesFrom('annotationPages'),
      pageStructureChanged: result['pageStructureChanged'] as bool? ?? false,
      destructive: result['destructive'] as bool? ?? false,
    );
    _commitSavedRevision(
      saved,
      beforeLength: beforeLength,
      impact: impact,
    );
    return count;
  }

  /// Replaces colors on the thumbnail-strip page selection. Returns zero
  /// when no pages are selected.
  int replaceSelectedPageColors({
    Color? find,
    Iterable<Color>? findColors,
    Color? replace,
    int tolerance = 0,
    bool fill = true,
    bool stroke = true,
    bool transparent = false,
  }) =>
      _selectedPages.isEmpty
          ? 0
          : replaceDocumentColors(
              pages: selectedPages,
              find: find,
              findColors: findColors,
              replace: replace,
              tolerance: tolerance,
              fill: fill,
              stroke: stroke,
              transparent: transparent,
            );

  // ---------------------------------------------------------------------
  // selection

  PdfAnnotationEditPredicate? _canEditAnnotation;

  /// Host veto over which annotations the editing UI may change.
  ///
  /// Consulted (alongside the document's own /F ReadOnly and Locked
  /// flags) by every mutating path: hit-test selection, the marquee,
  /// ⌘A, the sidebar's select, delete, and the eraser. An annotation
  /// the predicate rejects still renders, lists, zooms-to, and flashes -
  /// it just can't be selected for editing or destroyed.
  ///
  /// The typical multi-user host allows only the current user's own
  /// annotations:
  ///
  /// ```dart
  /// editing.canEditAnnotation = (a) => a.author == currentUserName;
  /// ```
  ///
  /// Null (the default) allows everything the flags allow. Changing the
  /// predicate drops newly ineligible annotations from the selection.
  PdfAnnotationEditPredicate? get canEditAnnotation => _canEditAnnotation;

  set canEditAnnotation(PdfAnnotationEditPredicate? value) {
    if (identical(value, _canEditAnnotation)) return;
    _canEditAnnotation = value;
    _selected.removeWhere((slot) {
      final annotation = _annotationAt(slot);
      return annotation == null || !isAnnotationEditable(annotation);
    });
    notifyListeners();
  }

  /// Whether the editing UI may change [annotation]: the document's own
  /// /F ReadOnly and Locked flags (§12.5.3) first, then the host's
  /// [canEditAnnotation] predicate. Display is unaffected either way.
  bool isAnnotationEditable(PdfAnnotation annotation) =>
      !annotation.isReadOnly &&
      !annotation.isLocked &&
      (_canEditAnnotation?.call(annotation) ?? true);

  /// The /F Locked flag (§12.5.3 bit 8): the annotation may not be moved,
  /// resized, or deleted. The bit conforming viewers - Acrobat, Bluebeam
  /// Revu - set when a markup is locked.
  static const int _annotationLockedFlag = 1 << 7; // 128

  /// The /F LockedContents flag (§12.5.3 bit 10): the annotation's
  /// contents may not change. [lockAnnotation] sets it alongside Locked so
  /// a locked markup can't be retyped either, matching Acrobat/Bluebeam.
  static const int _annotationLockedContentsFlag = 1 << 9; // 512

  /// Whether the lock state of [annotation] may be toggled - the way in to
  /// *unlock* it, which [isAnnotationEditable] itself forbids (a locked
  /// annotation is by definition not editable, so unlocking can't route
  /// through the normal edit gate). Only selectable markup annotations
  /// qualify; the document's /F ReadOnly flag and the host's
  /// [canEditAnnotation] predicate still veto it, but the Locked flag
  /// deliberately does not, so a lock can always be lifted.
  bool isAnnotationLockManageable(PdfAnnotation annotation) =>
      annotation.behavior.selectable &&
      !annotation.isReadOnly &&
      (_canEditAnnotation?.call(annotation) ?? true);

  /// Selected (page, /Annots slot) pairs in selection order; the last
  /// one is the primary selection (the one handles and text edits act
  /// on when exactly one is selected).
  final List<(int page, int index)> _selected = [];

  /// True while the interactive image-crop tool is armed on the selection.
  /// See [beginImageCrop].
  bool _cropModeArmed = false;

  /// The pending crop rectangle (page space) the crop overlay is dragging,
  /// or null when not cropping. Always a sub-rectangle of the selected image
  /// stamp's /Rect.
  PdfRect? _cropDraft;

  /// Pages cached per revision: [PdfDocument.page] rebuilds the page
  /// (and its lazily parsed annotation list) on every call, and the
  /// selection hit tests run per pointer event.
  final Map<int, PdfPage> _pageCache = {};

  PdfPage _page(int index) =>
      _pageCache.putIfAbsent(index, () => _document.page(index));

  /// The page at [index], cached for the current revision.
  /// [PdfDocument.page] re-walks the page tree and re-parses /Annots on
  /// every call - UI that reads pages per frame (sidebars, hit tests)
  /// should come through here.
  PdfPage pageAt(int index) => _page(index);

  /// Renders [region] of page [pageIndex] to PNG bytes - the capture
  /// behind the Snapshot tool ([PdfEditTool.snapshot]).
  ///
  /// [region] is page raster space: points with y down, after /Rotate -
  /// i.e. a view position divided by the view scale (`PdfPageGeometry`).
  /// The overlay therefore passes the dragged box straight through.
  /// [pixelRatio] scales the output resolution (2 keeps a snapshot crisp
  /// at 100% zoom). [pageColor] and [annotations] should match how the
  /// page is displayed, so the snapshot looks like what's on screen.
  /// Returns null for a degenerate (sub-pixel) region.
  Future<Uint8List?> captureSnapshot(
    int pageIndex,
    Rect region, {
    double pixelRatio = 2,
    Color pageColor = const Color(0xFFFFFFFF),
    bool annotations = true,
  }) async {
    if (region.width < 1 || region.height < 1) return null;
    final picture = await PdfPageRenderer.renderPicture(
      pageAt(pageIndex),
      pageColor: pageColor,
      annotations: annotations,
    );
    try {
      final image = await PdfPageRenderer.rasterizeRegion(
        picture,
        region,
        pixelRatio,
      );
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return data?.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  }

  PdfAnnotation? _annotationAt((int, int) selected) {
    final (page, index) = selected;
    if (page < 0 || page >= _document.pageCount) return null;
    final annotations = _page(page).annotations;
    return index < annotations.length ? annotations[index] : null;
  }

  /// The annotation in slot [index] of [pageIndex]'s /Annots at the
  /// current revision, or null for invalid slots.
  PdfAnnotation? annotationAt(int pageIndex, int index) =>
      _annotationAt((pageIndex, index));

  /// The selected annotation, resolved against the current revision.
  /// With several selected, the primary (most recently selected) one.
  PdfAnnotation? get selectedAnnotation =>
      _selected.isEmpty ? null : _annotationAt(_selected.last);

  /// The page the (primary) selected annotation lives on.
  int? get selectedPage =>
      selectedAnnotation == null ? null : _selected.last.$1;

  /// (pageIndex, /Annots slot) of the primary selected annotation, for
  /// comparing against a list position (the annotation sidebar's
  /// selected tile).
  (int page, int index)? get selectedAnnotationSlot =>
      selectedAnnotation == null ? null : _selected.last;

  /// Every selected (pageIndex, /Annots slot), in selection order.
  List<(int page, int index)> get selectedAnnotationSlots =>
      List.unmodifiable(_selected);

  bool get hasAnnotationSelection => selectedAnnotation != null;

  /// Whether the annotation in slot [index] of [pageIndex]'s /Annots is
  /// part of the selection.
  bool isAnnotationSelected(int pageIndex, int index) =>
      _selected.contains((pageIndex, index));

  /// Resizing manipulates one /Rect; only a single selection has handles.
  /// Form-field widgets resize too while the form tool is armed (the
  /// editor regenerates their appearance at the new size).
  bool get canResizeSelected =>
      _selected.length == 1 &&
      (selectedAnnotation?.behavior.resizable == true ||
          (tool == PdfEditTool.form &&
              selectedAnnotation?.subtype == 'Widget'));

  /// Rotation rides the appearance stream's /Matrix, so it needs one.
  bool get canRotateSelected =>
      _selected.length == 1 && selectedAnnotation?.behavior.rotatable == true;

  bool get canEditSelectedText =>
      _selected.length == 1 &&
      selectedAnnotation?.behavior.textEditable == true &&
      selectedAnnotation?.isLockedContents != true;

  /// Whether the selection is a single upright image stamp that the crop
  /// tool can operate on. Rotated image stamps are excluded: cropping shrinks
  /// the box to an axis-aligned sub-rectangle, which cannot describe a
  /// rotated frame.
  bool get canCropSelected {
    final annotation = selectedAnnotation;
    if (_selected.length != 1 ||
        annotation == null ||
        !annotation.isImageStamp ||
        annotation.normalAppearance == null) {
      return false;
    }
    final quad = annotation.appearanceQuad;
    if (quad == null || quad.length < 2) return true;
    final (x0, y0) = quad[0];
    final (x1, y1) = quad[1];
    // Upright when the picture's bottom edge is horizontal.
    return (y1 - y0).abs() <= 1e-3 * math.max(1.0, (x1 - x0).abs());
  }

  /// The topmost selectable annotation under ([x], [y]) on [pageIndex],
  /// with its /Annots slot - the select tool's hit test (later entries
  /// draw on top, so they win).
  (int index, PdfAnnotation)? selectableAnnotationAt(
    int pageIndex,
    double x,
    double y,
  ) {
    final annotations = _page(pageIndex).annotations;
    for (var i = annotations.length - 1; i >= 0; i--) {
      final annotation = annotations[i];
      if (annotation.isHidden ||
          !annotation.behavior.selectable ||
          !isAnnotationEditable(annotation)) {
        continue;
      }
      // For text-markups (Highlight / Underline / StrikeOut /
      // Squiggly) the click must land on a /QuadPoints quad - a
      // markup's bounding /Rect spans every line of the marked text
      // (including the gap at line breaks) and so swallows clicks
      // meant for an annotation behind it. The quads are what the user
      // sees as their color swatches; hit-test those, never /Rect.
      final quads = annotation.behavior.markupQuads;
      if (quads != null && quads.isNotEmpty) {
        for (final q in quads) {
          if (q.contains(x, y)) return (i, annotation);
        }
        continue;
      }
      if (annotation.rect.contains(x, y)) return (i, annotation);
    }
    return null;
  }

  /// The topmost *locked* lock-manageable annotation under ([x], [y]) on
  /// [pageIndex], with its /Annots slot - the right-click "Unlock" hit
  /// test. Unlike [selectableAnnotationAt] it deliberately reaches locked
  /// annotations (which can't be selected), so a mouse user can lift the
  /// lock the same way the sidebar row's button does. Skips hidden ones.
  (int index, PdfAnnotation)? lockedAnnotationAt(
    int pageIndex,
    double x,
    double y,
  ) {
    final annotations = _page(pageIndex).annotations;
    for (var i = annotations.length - 1; i >= 0; i--) {
      final annotation = annotations[i];
      if (annotation.isHidden ||
          !annotation.isLocked ||
          !isAnnotationLockManageable(annotation)) {
        continue;
      }
      if (annotation.rect.contains(x, y)) return (i, annotation);
    }
    return null;
  }

  /// The topmost form-field widget under ([x], [y]) on [pageIndex] with
  /// its /Annots slot - the form tool's selection hit test (later
  /// entries draw on top, so they win). Skips hidden widgets and ones
  /// the host or /F Locked flag protects ([isAnnotationEditable]); a
  /// read-only field (one whose *value* can't change) is still
  /// selectable for move/resize/rename. Null when nothing is hit.
  (int index, PdfAnnotation)? selectableWidgetAt(
    int pageIndex,
    double x,
    double y,
  ) {
    final annotations = _page(pageIndex).annotations;
    for (var i = annotations.length - 1; i >= 0; i--) {
      final annotation = annotations[i];
      if (annotation.subtype != 'Widget' ||
          annotation.isHidden ||
          !isAnnotationEditable(annotation)) {
        continue;
      }
      if (annotation.rect.contains(x, y)) return (i, annotation);
    }
    return null;
  }

  /// Selects the topmost form-field widget under ([x], [y]) on
  /// [pageIndex] for manipulation (move/resize/toolbar controls) - the form tool's
  /// tap. Clears the selection when nothing is hit. With [toggle]
  /// (shift/⌘-click) the hit is added to or removed from the selection
  /// and a miss leaves the selection alone. The form tool stays armed.
  /// Returns whether a widget was hit.
  bool selectFormWidgetAt(
    int pageIndex,
    double x,
    double y, {
    bool toggle = false,
  }) {
    final hit = selectableWidgetAt(pageIndex, x, y);
    if (hit == null) {
      if (!toggle) clearAnnotationSelection();
      return false;
    }
    final slot = (pageIndex, hit.$1);
    if (toggle) {
      if (!_selected.remove(slot)) _selected.add(slot);
    } else {
      _selected
        ..clear()
        ..add(slot);
    }
    notifyListeners();
    return true;
  }

  /// The topmost Ink annotation whose strokes pass within [tolerance]
  /// page units of ([x], [y]) on [pageIndex], with its /Annots slot -
  /// the eraser's hit test. Precise: the point must be near the inked
  /// centerline (padded by half the pen width), not merely inside the
  /// bounding rect, so crossing strokes don't erase together. An Ink
  /// annotation without a usable /InkList falls back to its rect.
  (int index, PdfAnnotation)? inkAnnotationAt(
    int pageIndex,
    double x,
    double y, {
    double tolerance = 4,
  }) {
    final annotations = _page(pageIndex).annotations;
    for (var i = annotations.length - 1; i >= 0; i--) {
      final annotation = annotations[i];
      if (annotation.subtype != 'Ink' ||
          annotation.isHidden ||
          !isAnnotationEditable(annotation)) {
        continue;
      }
      final rect = annotation.rect;
      final reach = tolerance + (annotation.borderWidth ?? 1) / 2;
      if (x < rect.left - reach ||
          x > rect.right + reach ||
          y < rect.bottom - reach ||
          y > rect.top + reach) {
        continue;
      }
      final strokes = annotation.inkList;
      if (strokes == null) return (i, annotation); // rect is all we have
      for (final stroke in strokes) {
        if (stroke.length == 1) {
          final (px, py) = stroke.single;
          if (_distanceSquared(x, y, px, py) <= reach * reach) {
            return (i, annotation);
          }
          continue;
        }
        for (var p = 0; p + 1 < stroke.length; p++) {
          if (_segmentDistanceSquared(x, y, stroke[p], stroke[p + 1]) <=
              reach * reach) {
            return (i, annotation);
          }
        }
      }
    }
    return null;
  }

  static double _distanceSquared(double x, double y, double px, double py) {
    final dx = x - px, dy = y - py;
    return dx * dx + dy * dy;
  }

  /// Squared distance from ([x], [y]) to the segment [a]–[b].
  static double _segmentDistanceSquared(
    double x,
    double y,
    (double, double) a,
    (double, double) b,
  ) {
    final (ax, ay) = a;
    final (bx, by) = b;
    final dx = bx - ax, dy = by - ay;
    final lengthSquared = dx * dx + dy * dy;
    if (lengthSquared == 0) return _distanceSquared(x, y, ax, ay);
    final t = (((x - ax) * dx + (y - ay) * dy) / lengthSquared).clamp(0.0, 1.0);
    return _distanceSquared(x, y, ax + t * dx, ay + t * dy);
  }

  /// Selects the topmost selectable annotation under ([x], [y]) on
  /// [pageIndex]; clears the selection when nothing is hit. With
  /// [toggle] (shift/⌘-click) the hit is added to or removed from the
  /// selection instead, and a miss leaves the selection alone. Returns
  /// whether an annotation was hit.
  bool selectAnnotationAt(
    int pageIndex,
    double x,
    double y, {
    bool toggle = false,
  }) {
    final hit = selectableAnnotationAt(pageIndex, x, y);
    if (hit == null) {
      if (!toggle) clearAnnotationSelection();
      return false;
    }
    final slot = (pageIndex, hit.$1);
    if (toggle) {
      if (!_selected.remove(slot)) _selected.add(slot);
      notifyListeners();
    } else if (_selected.length != 1 || _selected.single != slot) {
      _selected
        ..clear()
        ..add(slot);
      notifyListeners();
    }
    return true;
  }

  /// Selects every selectable annotation on [pageIndex] whose rect
  /// intersects [rect] (page space) - the select tool's rubber band.
  /// With [add] the hits join the existing selection instead of
  /// replacing it. Returns how many annotations the band hit.
  int selectAnnotationsIn(int pageIndex, PdfRect rect, {bool add = false}) {
    final annotations = _page(pageIndex).annotations;
    final hits = <(int, int)>[];
    for (var i = 0; i < annotations.length; i++) {
      final annotation = annotations[i];
      if (annotation.isHidden ||
          !annotation.behavior.selectable ||
          !isAnnotationEditable(annotation)) {
        continue;
      }
      final r = annotation.rect;
      if (r.left <= rect.right &&
          r.right >= rect.left &&
          r.bottom <= rect.top &&
          r.top >= rect.bottom) {
        hits.add((pageIndex, i));
      }
    }
    final next = [
      if (add) ..._selected,
      for (final hit in hits)
        if (!add || !_selected.contains(hit)) hit,
    ];
    if (!listEquals(next, _selected)) {
      _selected
        ..clear()
        ..addAll(next);
      notifyListeners();
    }
    return hits.length;
  }

  /// Selects every selectable annotation on [pageIndex] (⌘A). Returns
  /// how many are selected afterwards.
  int selectAllAnnotationsOn(int pageIndex) {
    final box = _page(pageIndex).cropBox;
    return selectAnnotationsIn(
      pageIndex,
      PdfRect(box.left - 1e6, box.bottom - 1e6, box.right + 1e6, box.top + 1e6),
    );
  }

  /// Selects the annotation in slot [index] of [pageIndex]'s /Annots
  /// (the position in [PdfPage.annotations]), arming the select tool so
  /// the viewer shows the selection. Used by the annotation sidebar.
  /// Returns false for invalid slots, unselectable subtypes, and
  /// annotations the host or /F flags lock ([isAnnotationEditable]).
  bool selectAnnotation(int pageIndex, int index) {
    final annotation = _annotationAt((pageIndex, index));
    if (annotation == null ||
        !annotation.behavior.selectable ||
        !isAnnotationEditable(annotation)) {
      return false;
    }
    tool = PdfEditTool.select;
    if (_selected.length != 1 || _selected.single != (pageIndex, index)) {
      _selected
        ..clear()
        ..add((pageIndex, index));
      notifyListeners();
    }
    return true;
  }

  /// Adds or removes the annotation in slot [index] of [pageIndex]'s
  /// /Annots from the selection - the annotation sidebar's ⌘/Ctrl-click.
  /// Arms the select tool and keeps any other selected annotations. An
  /// already-selected slot is deselected; a slot that can't be selected
  /// (invalid, unselectable subtype, or locked) is ignored when it isn't
  /// already in the selection. Returns whether the annotation is selected
  /// afterwards.
  bool toggleAnnotationSelection(int pageIndex, int index) {
    final slot = (pageIndex, index);
    if (_selected.contains(slot)) {
      _selected.remove(slot);
      notifyListeners();
      return false;
    }
    final annotation = _annotationAt(slot);
    if (annotation == null ||
        !annotation.behavior.selectable ||
        !isAnnotationEditable(annotation)) {
      return false;
    }
    tool = PdfEditTool.select;
    _selected.add(slot);
    notifyListeners();
    return true;
  }

  /// Replaces the annotation selection with [slots] (in the given order,
  /// dropping duplicates and any that are invalid, unselectable, or
  /// locked) and arms the select tool - the annotation sidebar's
  /// shift-click range select. Returns how many are selected afterwards.
  int selectAnnotationSlots(Iterable<(int page, int index)> slots) {
    final next = <(int, int)>[];
    for (final slot in slots) {
      if (next.contains(slot)) continue;
      final annotation = _annotationAt(slot);
      if (annotation != null &&
          annotation.behavior.selectable &&
          isAnnotationEditable(annotation)) {
        next.add(slot);
      }
    }
    tool = PdfEditTool.select;
    if (!listEquals(next, _selected)) {
      _selected
        ..clear()
        ..addAll(next);
      notifyListeners();
    }
    return next.length;
  }

  /// Removes the annotation in slot [index] of [pageIndex]'s /Annots
  /// without going through the selection.
  void deleteAnnotation(int pageIndex, int index) {
    final annotation = _annotationAt((pageIndex, index));
    if (annotation == null || !isAnnotationEditable(annotation)) return;
    // removing one /Annots entry shifts the slots after it down by one
    _selected.remove((pageIndex, index));
    for (var i = 0; i < _selected.length; i++) {
      final (page, slot) = _selected[i];
      if (page == pageIndex && slot > index) _selected[i] = (page, slot - 1);
    }
    apply(
      (e) => e.removeAnnotation(pageIndex, annotation),
    );
  }

  /// Removes several annotations - (pageIndex, /Annots slot) pairs - in
  /// one revision, so a single undo restores them all. Invalid slots are
  /// skipped. Used by the annotation sidebar's multi-select delete.
  void deleteAnnotations(Iterable<(int page, int index)> slots) {
    // resolve every slot before the first removal shifts the others
    final targets = <(int, PdfAnnotation)>[
      for (final slot in slots)
        if (_annotationAt(slot) case final annotation?
            when isAnnotationEditable(annotation))
          (slot.$1, annotation),
    ];
    if (targets.isEmpty) return;
    // surviving annotations may land in different slots
    _selected.clear();
    apply(
      (e) {
        final byPage = <int, List<PdfAnnotation>>{};
        for (final (page, annotation) in targets) {
          (byPage[page] ??= []).add(annotation);
        }
        for (final entry in byPage.entries) {
          e.removeAnnotations(entry.key, entry.value);
        }
      },
    );
  }

  // ---------------------------------------------------------------------
  // locking (§12.5.3 /F Locked + LockedContents)

  /// Sets or clears the lock on the annotation in slot [index] of
  /// [pageIndex]'s /Annots.
  ///
  /// Locking sets the /F Locked (bit 8) and LockedContents (bit 10) flags
  /// (§12.5.3) together - the same pair Acrobat and Bluebeam Revu write
  /// when a markup is locked - so conforming viewers refuse to move,
  /// resize, delete, or retype it. Unlocking clears just those two bits,
  /// leaving Print/Hidden/NoView and any other flag untouched.
  ///
  /// This is the *unlock* entry point: it bypasses [isAnnotationEditable]
  /// (a locked annotation is never editable, so it could otherwise never
  /// be reached) but still honours [isAnnotationLockManageable]. Locking
  /// drops the annotation from the selection, since it's no longer
  /// editable. Returns whether the flag word changed.
  bool setAnnotationLocked(int pageIndex, int index, bool locked) {
    final annotation = _annotationAt((pageIndex, index));
    if (annotation == null || !isAnnotationLockManageable(annotation)) {
      return false;
    }
    const lockBits = _annotationLockedFlag | _annotationLockedContentsFlag;
    final next =
        locked ? annotation.flags | lockBits : annotation.flags & ~lockBits;
    if (next == annotation.flags) return false;
    // A locked annotation is no longer selectable; drop it so stale
    // resize/rotate handles don't linger over it (resizable is a
    // capability, not a permission, so the overlay wouldn't hide them).
    if (locked) _selected.remove((pageIndex, index));
    return apply((e) => e.setAnnotationFlags(pageIndex, annotation, next));
  }

  /// Flips the lock on the annotation in slot [index] of [pageIndex]'s
  /// /Annots - the annotation sidebar's per-row lock button, and the
  /// reliable way to unlock (a locked annotation can't be selected).
  /// Returns the lock state it was set to, or the unchanged state when
  /// the annotation isn't lock-manageable.
  bool toggleAnnotationLock(int pageIndex, int index) {
    final annotation = _annotationAt((pageIndex, index));
    if (annotation == null) return false;
    final target = !annotation.isLocked;
    return setAnnotationLocked(pageIndex, index, target)
        ? target
        : annotation.isLocked;
  }

  /// Whether [lockSelectedAnnotations] would lock anything: something is
  /// selected and every selected slot is an unlocked, lock-manageable
  /// markup annotation.
  bool get canLockSelected =>
      _selected.isNotEmpty &&
      _selected.every((slot) {
        final annotation = _annotationAt(slot);
        return annotation != null &&
            !annotation.isLocked &&
            isAnnotationLockManageable(annotation);
      });

  /// Locks every selected annotation (see [setAnnotationLocked]) as one
  /// revision, then clears the selection since a locked annotation is no
  /// longer editable - the context menu's Lock action. Already-locked or
  /// non-lock-manageable members are skipped; a no-op when none qualify.
  void lockSelectedAnnotations() {
    final targets = <(int, PdfAnnotation)>[
      for (final slot in _selected)
        if (_annotationAt(slot) case final annotation?
            when !annotation.isLocked && isAnnotationLockManageable(annotation))
          (slot.$1, annotation),
    ];
    if (targets.isEmpty) return;
    _selected.clear();
    const lockBits = _annotationLockedFlag | _annotationLockedContentsFlag;
    apply((e) {
      for (final (page, annotation) in targets) {
        e.setAnnotationFlags(page, annotation, annotation.flags | lockBits);
      }
    });
  }

  // ---------------------------------------------------------------------
  // comment threads (§12.5.6.x)

  /// Replies to [target] on [pageIndex] with [contents], stamping the
  /// controller's [preferences.author]. The reply is appearance-less thread
  /// content
  /// (it does not repaint the page); one revision, emitted on
  /// [annotationChanges] so it syncs. Returns whether it was added (a
  /// blank [contents] adds nothing).
  bool replyToAnnotation(int pageIndex, PdfAnnotation target, String contents) {
    if (contents.trim().isEmpty) return false;
    // a thread edit changes no page graphics: const [] skips re-raster
    // while still diffing for the change feed (see apply's pages contract)
    return apply(
      (e) => e.replyToAnnotation(pageIndex, target, contents, author: preferences.author),
    );
  }

  /// Records review [state] on [target]'s thread (a state reply). One
  /// revision, emitted on [annotationChanges]. Returns whether it changed.
  bool setReviewState(
    int pageIndex,
    PdfAnnotation target,
    PdfReviewState state,
  ) =>
      apply(
        (e) => e.setReviewState(pageIndex, target, state, author: preferences.author),
      );

  /// Marks [target]'s thread resolved (review state `Completed`).
  bool resolveThread(int pageIndex, PdfAnnotation target) => apply(
        (e) => e.resolveThread(pageIndex, target, author: preferences.author),
      );

  /// Reopens [target]'s thread (review state `None`).
  bool reopenThread(int pageIndex, PdfAnnotation target) => apply(
        (e) => e.reopenThread(pageIndex, target, author: preferences.author),
      );

  /// The reply threads on [pageIndex] (read-only model), assembled from
  /// the current revision's annotations. Mirrors
  /// [PdfCommentThread.forPage] against the controller's live document.
  List<PdfCommentThread> commentThreads(int pageIndex) =>
      PdfCommentThread.forPage(_document, pageIndex);

  /// Erases along [path] (page space) with the circle eraser: every
  /// ink annotation on [pageIndex] is sliced where the swept circle of
  /// [preferences.eraserRadius] crosses its strokes - strokes split, the rest
  /// survives - in one revision, so a single undo restores the whole
  /// swipe. Ink annotations without a usable /InkList can't be sliced
  /// and are deleted whole when the path reaches their rect. Returns
  /// whether anything changed.
  bool sliceErase(int pageIndex, List<(double, double)> path) {
    if (path.isEmpty) return false;
    final radius = preferences.eraserRadius;
    // resolve every target up front: removals shift /Annots slots, but
    // the editor works by dictionary identity
    final targets = [
      for (final annotation in _page(pageIndex).annotations)
        if (annotation.subtype == 'Ink' &&
            !annotation.isHidden &&
            isAnnotationEditable(annotation))
          annotation,
    ];
    if (targets.isEmpty) return false;
    return apply(
      (editor) {
        var changed = false;
        for (final annotation in targets) {
          if (annotation.inkList == null) {
            // no centerline to slice - the rect is all we have
            if (_pathTouchesRect(path, annotation.rect, radius)) {
              editor.removeAnnotation(pageIndex, annotation);
              changed = true;
            }
          } else if (editor.sliceInk(pageIndex, annotation, path, radius)) {
            changed = true;
          }
        }
        // slots may shift under the survivors
        if (changed) _selected.clear();
      },
    );
  }

  static bool _pathTouchesRect(
    List<(double, double)> path,
    PdfRect rect,
    double radius,
  ) {
    for (final (x, y) in path) {
      if (x >= rect.left - radius &&
          x <= rect.right + radius &&
          y >= rect.bottom - radius &&
          y <= rect.top + radius) {
        return true;
      }
    }
    return false;
  }

  /// Whether [bringSelectedToFront] would change anything: some selected
  /// annotation has another one above it in its page's /Annots order.
  bool get canBringSelectedToFront => _reorderChangesSlots(toFront: true);

  /// Whether [sendSelectedToBack] would change anything.
  bool get canSendSelectedToBack => _reorderChangesSlots(toFront: false);

  /// Moves the selected annotations to the top of their pages' z-order
  /// (the end of /Annots - later entries paint on top), preserving their
  /// relative order. One revision, one undo; the selection follows the
  /// annotations to their new slots.
  void bringSelectedToFront() => _reorderSelected(toFront: true);

  /// Moves the selected annotations behind everything else on their
  /// pages (the start of /Annots).
  void sendSelectedToBack() => _reorderSelected(toFront: false);

  /// Simulates the /Annots reorder slot-by-slot: unmoved entries keep
  /// their relative order, the moved block lands at the top or bottom -
  /// exactly what the editor does to the array, expressed on slots.
  Map<(int, int), (int, int)> _reorderRemap({required bool toFront}) {
    final remap = <(int, int), (int, int)>{};
    final byPage = <int, Set<int>>{};
    for (final (page, slot) in _selected) {
      byPage.putIfAbsent(page, () => {}).add(slot);
    }
    for (final MapEntry(key: page, value: moving) in byPage.entries) {
      final count = _page(page).annotations.length;
      final rest = [
        for (var i = 0; i < count; i++)
          if (!moving.contains(i)) i,
      ];
      final block = [
        for (var i = 0; i < count; i++)
          if (moving.contains(i)) i,
      ];
      final order = toFront ? [...rest, ...block] : [...block, ...rest];
      for (var newSlot = 0; newSlot < order.length; newSlot++) {
        remap[(page, order[newSlot])] = (page, newSlot);
      }
    }
    return remap;
  }

  bool _reorderChangesSlots({required bool toFront}) {
    if (_selected.isEmpty) return false;
    return _reorderRemap(
      toFront: toFront,
    ).entries.any((entry) => entry.key != entry.value);
  }

  void _reorderSelected({required bool toFront}) {
    if (!_reorderChangesSlots(toFront: toFront)) return;
    final remap = _reorderRemap(toFront: toFront);
    // resolve everything before the edit, grouped per page
    final byPage = <int, List<PdfAnnotation>>{};
    for (final slot in _selected) {
      final annotation = _annotationAt(slot);
      if (annotation != null) {
        byPage.putIfAbsent(slot.$1, () => []).add(annotation);
      }
    }
    if (byPage.isEmpty) return;
    // remap before apply: its post-save validation reads these slots
    for (var i = 0; i < _selected.length; i++) {
      _selected[i] = remap[_selected[i]] ?? _selected[i];
    }
    apply(
      (e) {
        for (final MapEntry(key: page, value: annotations) in byPage.entries) {
          toFront
              ? e.bringAnnotationsToFront(page, annotations)
              : e.sendAnnotationsToBack(page, annotations);
        }
      },
    );
  }

  void clearAnnotationSelection() {
    if (_selected.isEmpty) return;
    _selected.clear();
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // clipboard

  /// The in-app annotation clipboard: detached snapshots that survive
  /// edits, undo, and document swaps (PDF annotations don't round-trip
  /// the OS clipboard). Filled by copy/cut, consumed by
  /// [pasteAnnotations].
  List<PdfAnnotationSnapshot> _clipboard = const [];
  int _clipboardSourcePage = -1;

  /// Pastes since the clipboard was last filled - each one cascades the
  /// default paste position by another 12pt so copies don't stack.
  int _pasteCount = 0;

  /// Whether [pasteAnnotations] has anything to paste.
  bool get hasAnnotationClipboard => _clipboard.isNotEmpty;

  /// Copies the selected annotations to the in-app clipboard as
  /// detached snapshots. Popups, links, and form widgets never copy
  /// (they can't be selected either). Returns how many were copied; the
  /// document is untouched.
  int copySelectedAnnotations() {
    final snapshots = <PdfAnnotationSnapshot>[];
    for (final slot in _selected) {
      final annotation = _annotationAt(slot);
      if (annotation == null) continue;
      final snapshot = PdfAnnotationSnapshot.capture(_document, annotation,
          sourcePageRotation: _page(slot.$1).rotation);
      if (snapshot != null) snapshots.add(snapshot);
    }
    if (snapshots.isEmpty) return 0;
    _clipboard = snapshots;
    _clipboardSourcePage = _selected.last.$1;
    _pasteCount = 0;
    // the most recent copy wins ⌘V (see [copyVectorSnapshot])
    snapshotClipboard.clear();
    notifyListeners();
    return snapshots.length;
  }

  /// Copy + delete in one gesture (⌘X). The deletion is a single undo
  /// step; the clipboard itself is not part of document history, so
  /// undoing a cut leaves the clipboard filled.
  int cutSelectedAnnotations() {
    final copied = copySelectedAnnotations();
    if (copied > 0) deleteSelected();
    return copied;
  }

  /// Pastes the clipboard onto [pageIndex] and selects the pasted
  /// annotations (one revision - one undo removes them all).
  ///
  /// With [at] the group centers on that page point (the context menu
  /// pastes where the right-click landed). Without it the group keeps
  /// its position, shifted 12pt down-right per repeat paste - and per
  /// the first paste too when it would sit exactly on the source. The
  /// group always clamps into the page's crop box. Returns whether
  /// anything was pasted.
  bool pasteAnnotations(int pageIndex, {(double, double)? at}) {
    if (_clipboard.isEmpty) return false;
    if (pageIndex < 0 || pageIndex >= _document.pageCount) return false;
    var left = double.infinity, bottom = double.infinity;
    var right = double.negativeInfinity, top = double.negativeInfinity;
    for (final snapshot in _clipboard) {
      final r = snapshot.rect;
      if (r.left < left) left = r.left;
      if (r.bottom < bottom) bottom = r.bottom;
      if (r.right > right) right = r.right;
      if (r.top > top) top = r.top;
    }
    double dx, dy;
    if (at != null) {
      dx = at.$1 - (left + right) / 2;
      dy = at.$2 - (bottom + top) / 2;
    } else {
      final cascade = 12.0 *
          (pageIndex == _clipboardSourcePage ? _pasteCount + 1 : _pasteCount);
      dx = cascade;
      dy = -cascade;
    }
    final box = _page(pageIndex).cropBox;
    dx += _clampShift(left + dx, right + dx, box.left, box.right);
    dy += _clampShift(bottom + dy, top + dy, box.bottom, box.top);
    final count = _clipboard.length;
    final pasted = apply(
      (e) {
        for (final snapshot in _clipboard) {
          e.pasteAnnotation(pageIndex, snapshot, dx: dx, dy: dy);
        }
      },
    );
    if (!pasted) return false;
    _pasteCount++;
    // pasted entries appended to /Annots - select them, like any editor
    tool = PdfEditTool.select;
    final total = _page(pageIndex).annotations.length;
    _selected
      ..clear()
      ..addAll([for (var i = total - count; i < total; i++) (pageIndex, i)]);
    notifyListeners();
    return true;
  }

  /// Copies the current annotation selection to every page in [pageIndices],
  /// preserving each annotation's page coordinates.
  ///
  /// Source pages are skipped for their own annotations, so applying a
  /// selection to the whole document does not duplicate it on the page where
  /// it already lives. Returns the number of annotations created. The edit is
  /// a single undoable revision.
  int applySelectedAnnotationsToPages(Iterable<int> pageIndices) {
    final snapshots = <({int page, PdfAnnotationSnapshot snapshot})>[];
    for (final slot in _selected) {
      final annotation = _annotationAt(slot);
      if (annotation == null) continue;
      final snapshot = PdfAnnotationSnapshot.capture(_document, annotation,
          sourcePageRotation: _page(slot.$1).rotation);
      if (snapshot != null) snapshots.add((page: slot.$1, snapshot: snapshot));
    }
    if (snapshots.isEmpty) return 0;

    final targets = pageIndices
        .where((index) => index >= 0 && index < _document.pageCount)
        .toSet()
        .toList()
      ..sort();
    if (targets.isEmpty) return 0;

    final touched = <int>{};
    var count = 0;
    for (final page in targets) {
      var pageCount = 0;
      for (final item in snapshots) {
        if (item.page == page) continue;
        pageCount++;
      }
      if (pageCount == 0) continue;
      touched.add(page);
      count += pageCount;
    }
    if (count == 0) return 0;

    final changed = apply(
      (e) {
        for (final page in targets) {
          for (final item in snapshots) {
            if (item.page == page) continue;
            e.pasteAnnotation(page, item.snapshot);
          }
        }
      },
    );
    return changed ? count : 0;
  }

  // ---------------------------------------------------------------------
  // snapshot clipboard (the Snapshot tool's vector paste)

  int _snapshotPasteCount = 0;

  /// The object number of the captured form materialized by the last paste
  /// of the active snapshot into the current document - reused so repeat
  /// pastes share one XObject instead of re-embedding the page content.
  /// Reset whenever a different snapshot becomes active.
  int? _snapshotCapturedRef;

  /// Which snapshot [_snapshotCapturedRef] / [_snapshotPasteCount] belong to.
  /// The shared [snapshotClipboard] can change under this controller (a
  /// recapture here, or a capture in another tab), so paste keys its
  /// per-document bookkeeping to the snapshot identity and resets when it
  /// differs.
  PdfVectorSnapshot? _snapshotPasteAnchor;

  /// Whether [pasteSnapshot] has a captured region to paste.
  bool get hasSnapshotClipboard => snapshotClipboard.isNotEmpty;

  /// Captures [region] (PDF user space) of [pageIndex] as a detached
  /// vector snapshot - the page graphics under the region, copied inline,
  /// with the page's /Rotate baked in. Read-only: the document is
  /// untouched. See [PdfVectorSnapshotEditing.captureVectorSnapshot].
  PdfVectorSnapshot captureVectorSnapshot(int pageIndex, PdfRect region) =>
      PdfEditor(_document).captureVectorSnapshot(pageIndex, region);

  /// Captures [region] of [pageIndex] and keeps it on the snapshot
  /// clipboard for [pasteSnapshot] - the copy half of the Snapshot tool.
  /// The most recent copy wins, so this also drops the annotation
  /// clipboard. Returns the captured snapshot.
  PdfVectorSnapshot copyVectorSnapshot(int pageIndex, PdfRect region) {
    final snapshot = captureVectorSnapshot(pageIndex, region);
    // publish to the shared clipboard; paste resets its per-document
    // bookkeeping when it sees this new snapshot (identity differs from the
    // anchor).
    snapshotClipboard.set(snapshot);
    _clipboard = const [];
    notifyListeners();
    return snapshot;
  }

  /// Pastes the snapshot clipboard onto [pageIndex] as a vector /Stamp
  /// annotation (movable / resizable / deletable), preserving the captured
  /// graphics as vectors.
  ///
  /// With [at] the region centers on that page point (a right-click /
  /// ⌘V at the cursor). Without it the paste keeps the captured position,
  /// cascading 12pt down-right per repeat. The region always clamps into
  /// the page's crop box. Returns whether anything was pasted.
  bool pasteSnapshot(int pageIndex, {(double, double)? at}) {
    final snapshot = snapshotClipboard.snapshot;
    if (snapshot == null) return false;
    if (pageIndex < 0 || pageIndex >= _document.pageCount) return false;
    // The shared clipboard may hold a different snapshot than the one this
    // controller last pasted (recaptured here, or captured in another tab).
    // Restart the position cascade and drop the captured-form ref, which was
    // materialized from the previous snapshot into this document.
    if (!identical(snapshot, _snapshotPasteAnchor)) {
      _snapshotPasteAnchor = snapshot;
      _snapshotPasteCount = 0;
      _snapshotCapturedRef = null;
    }
    final w = snapshot.displayWidth, h = snapshot.displayHeight;
    if (w <= 0 || h <= 0) return false;
    double left, bottom;
    if (at != null) {
      left = at.$1 - w / 2;
      bottom = at.$2 - h / 2;
    } else {
      final cascade = 12.0 * _snapshotPasteCount;
      left = snapshot.region.left + cascade;
      bottom = snapshot.region.bottom - cascade;
    }
    final box = _page(pageIndex).cropBox;
    left += _clampShift(left, left + w, box.left, box.right);
    bottom += _clampShift(bottom, bottom + h, box.bottom, box.top);
    final target = PdfRect(left, bottom, left + w, bottom + h);
    int? captured;
    final pasted = apply(
      (e) {
        captured = e.pasteVectorSnapshot(
          pageIndex,
          target,
          snapshot,
          author: preferences.author,
          sharedObject: _snapshotCapturedRef,
        );
      },
    );
    if (!pasted) return false;
    // remember the shared captured form so repeat pastes reuse it
    _snapshotCapturedRef = captured;
    _snapshotPasteCount++;
    tool = PdfEditTool.select;
    final total = _page(pageIndex).annotations.length;
    _selected
      ..clear()
      ..add((pageIndex, total - 1));
    notifyListeners();
    return true;
  }

  /// How far to move the interval [lo, hi] so it fits inside
  /// [min, max]; an oversized interval pins to the low edge.
  static double _clampShift(double lo, double hi, double min, double max) {
    if (hi - lo >= max - min || lo < min) return min - lo;
    if (hi > max) return max - hi;
    return 0;
  }

  // ---------------------------------------------------------------------
  // restyle

  /// Whether [restyleSelected] can recolor everything selected in place
  /// (see [pdfCanRestyleAnnotation] for the per-subtype conditions).
  bool get canRestyleSelected =>
      _selected.isNotEmpty &&
      _selected.every((slot) {
        final annotation = _annotationAt(slot);
        return annotation?.behavior.canRestyle == true;
      });

  /// The primary selected annotation's current style, for style controls
  /// to display: its main color (the text color for free text), border
  /// width (null for subtypes without one), and baked-in opacity. Null
  /// without a selection.
  ({Color color, double? strokeWidth, double opacity})?
      get selectedAnnotationStyle {
    final annotation = selectedAnnotation;
    if (annotation == null) return null;
    final style = annotation.behavior.style;
    return (
      color: Color(0xFF000000 | (style.color ?? 0)),
      strokeWidth: style.strokeWidth,
      opacity: style.opacity,
    );
  }

  /// The colour the style controls should show: with a selection they
  /// recolour ([canRestyleSelected]), the primary selected annotation's own
  /// colour rather than [color], the last-used creation colour - a swatch
  /// row is a readout of what the next tap changes, so it has to follow the
  /// selection the way the stroke/opacity controls already do.
  ///
  /// Falls back to [color] when nothing restylable is selected, or when the
  /// annotation carries no colour of its own (an image stamp, a shape with
  /// no /C) - showing black there would be a lie about the annotation.
  Color get displayColor {
    if (!canRestyleSelected) return color;
    final rgb = selectedAnnotation?.behavior.style.color;
    return rgb == null ? color : Color(0xFF000000 | rgb);
  }

  /// Whether [restyleSelected]'s `fill` parameter applies to every selected
  /// annotation (shapes and FreeText boxes).
  bool get canFillSelected =>
      canRestyleSelected &&
      _selected.every((slot) {
        return _annotationAt(slot)?.behavior.supportsFill == true;
      });

  /// The primary selected annotation's interior/background fill, or null
  /// when it has none. For the fill control to display.
  Color? get selectedShapeFill {
    final rgb = selectedAnnotation?.behavior.style.fillColor;
    return rgb == null ? null : Color(0xFF000000 | rgb);
  }

  /// Whether every selected annotation takes a border line style - shapes
  /// and the line family - so [restyleSelected]'s `lineStyle` applies.
  bool get canSetLineStyleSelected =>
      canRestyleSelected &&
      _selected.every((slot) {
        return _annotationAt(slot)?.behavior.supportsLineStyle == true;
      });

  /// The primary selected annotation's border line style (for the line-type
  /// control to display), or null when it isn't a line/shape.
  PdfLineStyle? get selectedLineStyle {
    final annotation = selectedAnnotation;
    if (annotation == null) return null;
    if (!annotation.behavior.supportsLineStyle) return null;
    return PdfLineStyle.ofDashArray(annotation.borderDash);
  }

  /// The primary selected cloudy /Polygon's scallop scale (its `/BE /I`),
  /// for the pattern-scale control to display, or null when the selection
  /// isn't a cloud - other shapes bake their pattern scale into the stored
  /// dash array rather than a readable field, so the control falls back to
  /// the creation default [preferences.lineScale] for them.
  double? get selectedLineScale {
    final annotation = selectedAnnotation;
    if (annotation == null) return null;
    return annotation.hasCloudyBorder ? annotation.cloudBorderScale : null;
  }

  // ---------------------------------------------------------------------
  // Set-as-default: seed a creation tool's remembered style from an
  // existing annotation (the right-click "Set as default" action).

  /// The creation tool that draws [annotation]'s subtype, or null when no
  /// tool authors it (links, widgets, popups, and the appearance-only
  /// subtypes). Used to pick which persisted style scope "set as default"
  /// writes into.
  static PdfEditTool? _creatingToolFor(PdfAnnotation annotation) {
    switch (annotation.subtype) {
      case 'Square':
        return PdfEditTool.rectangle;
      case 'Circle':
        return PdfEditTool.ellipse;
      case 'Line':
        final endings = pdfLineEndings(annotation);
        const arrows = {
          PdfLineEnding.openArrow,
          PdfLineEnding.closedArrow,
          PdfLineEnding.rOpenArrow,
          PdfLineEnding.rClosedArrow,
        };
        final isArrow = endings != null &&
            (arrows.contains(endings.$1) || arrows.contains(endings.$2));
        return isArrow ? PdfEditTool.arrow : PdfEditTool.line;
      case 'PolyLine':
        return PdfEditTool.polyline;
      case 'Polygon':
        return annotation.hasCloudyBorder
            ? PdfEditTool.cloudPolygon
            : PdfEditTool.polygon;
      case 'Ink':
        return PdfEditTool.ink;
      case 'FreeText':
        return annotation.isCallout ? PdfEditTool.callout : PdfEditTool.freeText;
      case 'Text':
        return PdfEditTool.note;
      case 'Stamp':
        return PdfEditTool.stamp;
      default:
        return null;
    }
  }

  /// The persisted style scope "set as default" would write [annotation]'s
  /// style into, and the fields that scope remembers, or null when the
  /// subtype has no creation default to seed. Text markup (highlight /
  /// underline / strike-out / squiggly) acts on a text selection rather than
  /// arming a tool, so it maps to its own shared `markup` scope.
  static ({String scope, Set<String> fields})? _defaultStyleTargetFor(
      PdfAnnotation annotation) {
    switch (annotation.subtype) {
      case 'Highlight' || 'Underline' || 'StrikeOut' || 'Squiggly':
        return (scope: 'markup', fields: const {'color', 'opacity'});
    }
    final tool = _creatingToolFor(annotation);
    if (tool == null) return null;
    final behavior = PdfEditToolBehavior.of(tool);
    final scope = behavior.styleScopeKey;
    final fields = behavior.styleScopeFields;
    if (scope == null || fields.isEmpty) return null;
    return (scope: scope, fields: fields);
  }

  /// The full set of captured style values for [annotation], keyed by the
  /// same field names the persisted style scopes use.
  /// [PdfEditingPreferences.writeScopedStyle] keeps only the fields the
  /// target scope actually remembers.
  Map<String, Object?> _capturedStyleOf(PdfAnnotation annotation) {
    final style = annotation.behavior.style;
    final endings = pdfLineEndings(annotation);
    int? argb(int? rgb) => rgb == null ? null : 0xFF000000 | rgb;
    final values = <String, Object?>{
      if (style.color != null) 'color': argb(style.color),
      if (style.strokeWidth != null) 'strokeWidth': style.strokeWidth,
      'opacity': style.opacity,
      'lineStyle': PdfLineStyle.ofDashArray(annotation.borderDash).name,
      // shapes bake their pattern scale into the dash array; only a cloud
      // exposes a readable scallop scale to seed
      if (annotation.hasCloudyBorder) 'lineScale': annotation.cloudBorderScale,
      'shapeFillColor': argb(style.fillColor),
      if (endings != null) 'lineStartEnding': endings.$1.name,
      if (endings != null) 'lineEndEnding': endings.$2.name,
    };
    if (annotation.subtype == 'FreeText') {
      final text = _freeTextStyleOf(annotation);
      values['fontSize'] = text.size;
      values['fontFamily'] = text.font.name;
      final align = annotation.freeTextStyle?.alignment;
      values['textAlign'] = align?.name;
      // for a text box /C is the background and /DA border colour is separate;
      // the box's tint is its text colour, already captured as `color`
      values['textFillColor'] = argb(style.fillColor);
      values['textBorderColor'] = argb(style.borderColor);
    }
    return values;
  }

  /// Whether the primary selected annotation has a creation style that
  /// [applySelectedStyleAsDefault] can capture as the default for new
  /// annotations of its kind.
  bool get canApplySelectedStyleAsDefault {
    final annotation = selectedAnnotation;
    return annotation != null && _defaultStyleTargetFor(annotation) != null;
  }

  /// Captures the primary selected annotation's appearance (colour, stroke
  /// width, opacity, fill, line style, and - for free text - font, size,
  /// and alignment) as the creation default for the tool that draws its
  /// subtype, so subsequent annotations of that kind inherit it. The
  /// right-click "Set as default" action. Returns whether a default was
  /// captured.
  bool applySelectedStyleAsDefault() {
    final annotation = selectedAnnotation;
    if (annotation == null) return false;
    final target = _defaultStyleTargetFor(annotation);
    if (target == null) return false;
    preferences.writeScopedStyle(
        target.scope, target.fields, _capturedStyleOf(annotation));
    notifyListeners();
    return true;
  }

  /// Restyles every selected annotation in place - one revision, one
  /// undo, and the selection survives (annotations keep their /Annots
  /// slots). Parameters follow [PdfEditor.restyleAnnotation]: [color]
  /// is the stroke/tint (free text's *text* color), [fill] the shape
  /// interior or text-box background (`(null,)` clears it), and
  /// parameters a subtype doesn't have are ignored for it. Returns
  /// whether anything changed.
  bool restyleSelected({
    Color? color,
    (Color?,)? fill,
    double? strokeWidth,
    double? opacity,
    PdfLineStyle? lineStyle,
    double? cornerRadius,
    double? scale,
  }) {
    if (color == null &&
        fill == null &&
        strokeWidth == null &&
        opacity == null &&
        lineStyle == null &&
        cornerRadius == null &&
        scale == null) {
      return false;
    }
    if (!canRestyleSelected) return false;
    final targets = <(int, PdfAnnotation)>[
      for (final slot in _selected)
        if (_annotationAt(slot) case final annotation?) (slot.$1, annotation),
    ];
    if (targets.isEmpty) return false;
    return apply(
      (e) {
        for (final (page, annotation) in targets) {
          final width = strokeWidth ?? annotation.borderWidth ?? 1;
          // Recompute the dash array when the line style *or* the pattern
          // scale changes - both size it, and the scale is otherwise baked
          // into the stored array with no readable field. A pen-width change
          // alone no longer resizes it: thickness and pattern are separate.
          final style =
              lineStyle ?? PdfLineStyle.ofDashArray(annotation.borderDash);
          final recomputeDash = lineStyle != null || scale != null;
          e.restyleAnnotation(
            page,
            annotation,
            color: _rgbOf(color),
            fillColor: fill == null ? null : (_rgbOf(fill.$1),),
            strokeWidth: strokeWidth,
            opacity: opacity,
            dashPattern: recomputeDash
                ? (style.dashArray(width, scale: scale ?? preferences.lineScale),)
                : null,
            cloudScale: scale,
            // rounding only lands on /Square rectangles; other subtypes
            // ignore it, so a mixed selection is safe to pass through
            cornerRadius: cornerRadius,
            pageRotation: _page(page).rotation,
          );
        }
      },
    );
  }

  /// Whether [restyleSelected]'s `cornerRadius` applies - every selected
  /// annotation is a restylable /Square rectangle (the only subtype that
  /// rounds its corners). Gates the selection corner-radius control.
  bool get canRoundSelectedCorners =>
      canRestyleSelected &&
      _selected.every((slot) => _annotationAt(slot)?.subtype == 'Square');

  /// The primary selected rectangle's current corner radius (page points),
  /// or null when the selection isn't a roundable /Square - for the corner
  /// radius control to display.
  double? get selectedCornerRadius {
    final annotation = selectedAnnotation;
    if (annotation == null || annotation.subtype != 'Square') return null;
    return annotation.cornerRadius;
  }

  // ---------------------------------------------------------------------
  // vector snapshot recolour

  /// Whether every selected annotation is a pasted vector snapshot, so
  /// [recolorSnapshotSelected] can retint them as vectors. Vector snapshots
  /// keep the captured page's own colours, which the generic restyle path
  /// ([canRestyleSelected]) can't rewrite, so they get their own recolour.
  bool get canRecolorSnapshotSelected {
    if (_selected.isEmpty) return false;
    final editor = PdfEditor(_document);
    return _selected.every((slot) {
      final annotation = _annotationAt(slot);
      return annotation != null && editor.isVectorSnapshotStamp(annotation);
    });
  }

  /// Recolours every selected vector snapshot to [color] in one revision
  /// (one undo), keeping the selection. The captured graphics are rewritten
  /// to a single ink - see [PdfVectorSnapshotEditing.recolorVectorSnapshot].
  /// Returns whether anything changed.
  bool recolorSnapshotSelected(Color color) {
    if (!canRecolorSnapshotSelected) return false;
    final rgb = _rgbOf(color);
    if (rgb == null) return false;
    final targets = <(int, PdfAnnotation)>[
      for (final slot in _selected)
        if (_annotationAt(slot) case final annotation?) (slot.$1, annotation),
    ];
    if (targets.isEmpty) return false;
    return apply(
      (e) {
        for (final (page, annotation) in targets) {
          e.recolorVectorSnapshot(page, annotation, rgb);
        }
      },
    );
  }

  // ---------------------------------------------------------------------
  // attention flash

  ({int revisionId, int page, int slot})? _flash;
  int _flashSequence = 0;
  Timer? _flashTimer;

  /// How long a [flashAnnotation] pulse stays pending before it expires
  /// on its own (the overlay's animation is shorter).
  static const flashLifetime = Duration(milliseconds: 1600);

  /// Fires a brief attention pulse around the annotation in slot
  /// [index] of [pageIndex]'s /Annots - the page overlay animates it.
  /// The annotation sidebar calls this when a tile zooms the viewer to
  /// its annotation, so the eye lands on the right spot.
  void flashAnnotation(int pageIndex, int index) {
    if (annotationAt(pageIndex, index) == null) return;
    _flash = (revisionId: _revisionId, page: pageIndex, slot: index);
    _flashSequence++;
    _flashTimer?.cancel();
    _flashTimer = Timer(flashLifetime, () {
      _flash = null;
      notifyListeners();
    });
    notifyListeners();
  }

  /// The attention pulse in flight, or null. [sequence] distinguishes
  /// consecutive flashes of the same annotation. Expires when the
  /// overlay finishes the pulse ([expireFlash]), after [flashLifetime]
  /// as the backstop, and with any edit (the slot may mean something
  /// else now).
  ({int page, int slot, int sequence})? get pendingFlash {
    final flash = _flash;
    if (flash == null || flash.revisionId != _revisionId) return null;
    return (page: flash.page, slot: flash.slot, sequence: _flashSequence);
  }

  /// Clears [pendingFlash] once its pulse has run - the page overlay
  /// calls this when the animation completes. The [flashLifetime] timer
  /// stays as the backstop for a flash no overlay ever picked up.
  void expireFlash(int sequence) {
    if (_flash == null || sequence != _flashSequence) return;
    _flashTimer?.cancel();
    _flashTimer = null;
    _flash = null;
    notifyListeners();
  }

  /// Translates every selected annotation by ([dx], [dy]) in page space,
  /// as one revision. The selection survives: annotations keep their
  /// /Annots slots across a move.
  void moveSelected(double dx, double dy) {
    final targets = <(int, PdfAnnotation)>[
      for (final slot in _selected)
        if (_annotationAt(slot) case final annotation?) (slot.$1, annotation),
    ];
    if (targets.isEmpty) return;
    apply(
      (e) {
        for (final (page, annotation) in targets) {
          e.moveAnnotation(page, annotation, dx, dy);
        }
      },
    );
  }

  /// Nudges the selection by ([screenDx], [screenDy]) view-space units - the
  /// way the arrow keys point on screen, with y running *down* as the reader
  /// sees the page. The delta is translated through the primary selected
  /// page's /Rotate so an annotation always slides the direction the key
  /// points regardless of how the page is turned, then handed to
  /// [moveSelected] (one revision; the selection survives). A no-op with
  /// nothing selected.
  void nudgeSelected(double screenDx, double screenDy) {
    final page = selectedPage;
    if (page == null) return;
    // Mirror of PdfPageGeometry.toPagePoint: view y is down and /Rotate turns
    // the page clockwise, so recover the page-space (y-up) delta per rotation.
    final (dx, dy) = switch (_page(page).rotation % 360) {
      90 => (screenDy, screenDx),
      180 => (-screenDx, screenDy),
      270 => (-screenDy, -screenDx),
      _ => (screenDx, -screenDy),
    };
    moveSelected(dx, dy);
  }

  /// The selected annotations that share the primary selection's page, in
  /// selection order - the candidates an alignment acts on. Aligning across
  /// pages has no geometric meaning, so the primary page wins and other
  /// pages' selections are left alone.
  List<PdfAnnotation> _alignmentTargets() {
    final page = selectedPage;
    if (page == null) return const [];
    final out = <PdfAnnotation>[];
    for (final slot in _selected) {
      if (slot.$1 != page) continue;
      final annotation = _annotationAt(slot);
      if (annotation != null) out.add(annotation);
    }
    return out;
  }

  /// Whether [alignSelected] can line the selection up: two or more
  /// annotations selected on the primary selection's page.
  bool get canAlignSelected => _alignmentTargets().length >= 2;

  /// Whether [alignSelected] can distribute the selection: three or more
  /// annotations on the primary page (the extremes anchor, so distribution
  /// only moves anything with a rect in between).
  bool get canDistributeSelected => _alignmentTargets().length >= 3;

  /// Lines up (or spreads out) the selected annotations on the primary
  /// page per [alignment], as one revision. Needs two annotations to align
  /// and three to distribute; a no-op below that, or when the selection is
  /// already aligned (nothing would move). The selection survives - a move
  /// keeps each annotation's /Annots slot.
  void alignSelected(PdfAlignment alignment) {
    final page = selectedPage;
    if (page == null) return;
    final targets = _alignmentTargets();
    if (targets.length < alignment.minimumCount) return;
    final offsets = alignmentOffsets([
      for (final a in targets) a.rect,
    ], alignment);
    final moves = <(PdfAnnotation, double, double)>[];
    for (var i = 0; i < targets.length; i++) {
      final (:dx, :dy) = offsets[i];
      if (dx != 0 || dy != 0) moves.add((targets[i], dx, dy));
    }
    if (moves.isEmpty) return;
    apply(
      (e) {
        for (final (annotation, dx, dy) in moves) {
          e.moveAnnotation(page, annotation, dx, dy);
        }
      },
    );
  }

  /// Re-homes the single selected annotation onto [targetPage], shifted
  /// by ([dx], [dy]) in page space - what a move drag dropped over a
  /// *different* page produces. The annotation leaves its source page and
  /// is appended to the target page's /Annots, so it draws on top instead
  /// of staying on its old page (off the crop box, behind the neighbour).
  /// Its appearance and /NM identity survive (the snapshot keeps them).
  /// One revision; the re-homed annotation becomes the selection. Returns
  /// whether it moved. A same-page target falls back to [moveSelected].
  bool moveSelectedToPage(int targetPage, double dx, double dy) {
    if (targetPage < 0 || targetPage >= _document.pageCount) return false;
    if (_selected.length != 1) return false;
    final slot = _selected.single;
    if (slot.$1 == targetPage) {
      moveSelected(dx, dy);
      return true;
    }
    final annotation = _annotationAt(slot);
    if (annotation == null || !isAnnotationEditable(annotation)) return false;
    final snapshot = PdfAnnotationSnapshot.capture(
      _document,
      annotation,
      keepName: true,
      sourcePageRotation: _page(slot.$1).rotation,
    );
    if (snapshot == null) return false; // links/widgets/popups don't move
    final source = slot.$1;
    final moved = apply(
      (e) {
        e.removeAnnotation(source, annotation);
        e.pasteAnnotation(targetPage, snapshot, dx: dx, dy: dy);
      },
    );
    if (!moved) return false;
    final total = _page(targetPage).annotations.length;
    _selected
      ..clear()
      ..add((targetPage, total - 1));
    notifyListeners();
    return true;
  }

  /// Resizes the selected annotation so its /Rect becomes [to].
  ///
  /// [flipX]/[flipY] mirror the artwork - what a resize handle dragged
  /// past the opposite edge produces.
  void resizeSelected(PdfRect to, {bool flipX = false, bool flipY = false}) {
    final annotation = selectedAnnotation;
    if (annotation == null || !canResizeSelected) return;
    if (to.width < 1 || to.height < 1) return;
    if (annotation.subtype == 'Widget') {
      _resizeWidget(_selected.last, to);
      return;
    }
    if (annotation.isCallout) {
      // a callout's resize handles size the text box; the terminus stays
      // put and the leader stretches (Bluebeam's model)
      apply(
        (e) => e.reshapeCallout(_selected.last.$1, annotation, box: to),
      );
      return;
    }
    apply(
      (e) => e.resizeAnnotation(
        _selected.last.$1,
        annotation,
        to,
        flipX: flipX,
        flipY: flipY,
        pageRotation: _page(_selected.last.$1).rotation,
      ),
    );
  }

  /// Crops the selected image stamp so only the picture currently shown
  /// inside [visibleRect] (page space) survives, shrinking the annotation's
  /// box to that rectangle. [visibleRect] is clamped to the current box, and
  /// the crop composes with any crop already applied, so it always narrows
  /// towards the source picture. A no-op unless [canCropSelected].
  void cropSelectedImage(PdfRect visibleRect) {
    final annotation = selectedAnnotation;
    if (annotation == null || !canCropSelected) return;
    final rect = annotation.rect;
    if (rect.width <= 0 || rect.height <= 0) return;
    final v = visibleRect.intersect(rect);
    if (v.width < 1 || v.height < 1) return;
    // Untouched box → nothing to crop.
    if ((v.left - rect.left).abs() < 0.5 &&
        (v.bottom - rect.bottom).abs() < 0.5 &&
        (v.right - rect.right).abs() < 0.5 &&
        (v.top - rect.top).abs() < 0.5) {
      return;
    }
    final current = annotation.imageStampCrop ?? const PdfRect(0, 0, 1, 1);
    // Fractions of the current box the visible rect covers, composed into the
    // source picture's normalized coordinates.
    final fx0 = (v.left - rect.left) / rect.width;
    final fx1 = (v.right - rect.left) / rect.width;
    final fy0 = (v.bottom - rect.bottom) / rect.height;
    final fy1 = (v.top - rect.bottom) / rect.height;
    final crop = PdfRect(
      current.left + fx0 * current.width,
      current.bottom + fy0 * current.height,
      current.left + fx1 * current.width,
      current.bottom + fy1 * current.height,
    );
    apply(
      (e) => e.cropImageStamp(
        _selected.last.$1,
        annotation,
        crop: crop,
        rect: v,
      ),
    );
  }

  /// Removes any crop from the selected image stamp, restoring the whole
  /// picture. The box grows back to the picture's full extent at the current
  /// scale. A no-op unless [canCropSelected] and a crop is applied.
  void resetSelectedImageCrop() {
    final annotation = selectedAnnotation;
    if (annotation == null || !canCropSelected) return;
    final current = annotation.imageStampCrop;
    if (current == null) return;
    // Grow the box back so the retained pixels keep their scale: the current
    // box shows `current`, so the full picture spans box / current.
    final rect = annotation.rect;
    final fullWidth = rect.width / current.width;
    final fullHeight = rect.height / current.height;
    final left = rect.left - current.left * fullWidth;
    final bottom = rect.bottom - current.bottom * fullHeight;
    final full = PdfRect(left, bottom, left + fullWidth, bottom + fullHeight);
    apply(
      (e) => e.cropImageStamp(
        _selected.last.$1,
        annotation,
        crop: const PdfRect(0, 0, 1, 1),
        rect: full,
      ),
    );
  }

  /// Whether the interactive image-crop tool is armed. The overlay renders
  /// its crop rectangle and handles while this is true, absorbing gestures;
  /// the toolbar shows Done/Cancel. Auto-clears if the selection stops being
  /// a croppable image stamp.
  bool get isCroppingImage => _cropModeArmed && canCropSelected;

  /// The crop rectangle the overlay is currently dragging (page space), or
  /// null when [isCroppingImage] is false. Sub-rectangle of the selected
  /// image stamp's /Rect.
  PdfRect? get imageCropDraft => isCroppingImage ? _cropDraft : null;

  /// Arms the interactive crop tool on the selected image stamp, seeding the
  /// crop rectangle to the whole picture. A no-op unless [canCropSelected].
  void beginImageCrop() {
    final annotation = selectedAnnotation;
    if (annotation == null || !canCropSelected) return;
    _cropModeArmed = true;
    _cropDraft = annotation.rect;
    notifyListeners();
  }

  /// Updates the pending crop rectangle as the overlay drags a handle,
  /// clamped to the selected image stamp's /Rect. A no-op unless cropping.
  void updateImageCropDraft(PdfRect draft) {
    if (!isCroppingImage) return;
    final rect = selectedAnnotation!.rect;
    final clamped = draft.intersect(rect);
    if (clamped.width < 1 || clamped.height < 1) return;
    if (clamped == _cropDraft) return;
    _cropDraft = clamped;
    notifyListeners();
  }

  /// Applies the pending crop and disarms the tool. A no-op (just disarms)
  /// when the draft still covers the whole picture.
  void commitImageCrop() {
    final region = imageCropDraft;
    _cropModeArmed = false;
    _cropDraft = null;
    if (region != null) cropSelectedImage(region);
    // cropSelectedImage may no-op (unchanged box); repaint either way so the
    // crop chrome disappears.
    notifyListeners();
  }

  /// Disarms the crop tool, discarding the pending crop.
  void cancelImageCrop() {
    if (!_cropModeArmed && _cropDraft == null) return;
    _cropModeArmed = false;
    _cropDraft = null;
    notifyListeners();
  }

  /// Moves a selected callout's arrow terminus to [target] (page space),
  /// leaving the text box where it is - the leader stretches to follow.
  /// A no-op unless a single callout is selected.
  void reshapeSelectedCalloutTarget((double, double) target) {
    final annotation = selectedAnnotation;
    if (annotation == null || !annotation.isCallout) return;
    apply(
      (e) => e.reshapeCallout(_selected.last.$1, annotation, target: target),
    );
  }

  /// Moves a selected callout's arrow base (where the leader meets the text
  /// box) to [attach], snapped to the box perimeter. The box and terminus
  /// stay put. A no-op unless a single callout is selected.
  void reshapeSelectedCalloutBase((double, double) attach) {
    final annotation = selectedAnnotation;
    if (annotation == null || !annotation.isCallout) return;
    apply(
      (e) => e.reshapeCallout(_selected.last.$1, annotation, attach: attach),
    );
  }

  /// Resizes the selected form-field [widget] so its /Rect becomes [to],
  /// regenerating the field's appearance ([PdfEditor.resizeFormWidget]).
  /// The field is re-resolved by name inside the save (fields die with
  /// every revision); a no-op when the slot isn't a form widget.
  void _resizeWidget((int, int) slot, PdfRect to) {
    final field = _widgetFieldForSlot(slot);
    if (field == null) return;
    final (name, widgetIndex) = field;
    apply(
      (e) => e.resizeFormWidget(name, widgetIndex, to),
    );
  }

  /// The (field name, widget index) for the Widget annotation in [slot],
  /// or null when it isn't a form-field widget.
  (String name, int widgetIndex)? _widgetFieldForSlot((int, int) slot) {
    final annotation = _annotationAt(slot);
    final form = acroForm;
    if (annotation == null || form == null) return null;
    for (final field in form.fields) {
      final widgets = field.widgets;
      for (var w = 0; w < widgets.length; w++) {
        if (identical(widgets[w], annotation.dict)) return (field.name, w);
      }
    }
    return null;
  }

  /// Resizes the selected annotation in its own (unrotated) frame:
  /// [localTo] rotated by the annotation's resting angle about its
  /// center is where the artwork lands - how the overlay resizes a
  /// rotated selection without shearing it.
  ///
  /// [flipX]/[flipY] mirror the artwork along the local axes.
  void resizeSelectedLocal(
    PdfRect localTo, {
    bool flipX = false,
    bool flipY = false,
  }) {
    final annotation = selectedAnnotation;
    if (annotation == null || !canResizeSelected) return;
    if (localTo.width < 1 || localTo.height < 1) return;
    if (annotation.subtype == 'Widget') {
      // widgets never rotate, so the local frame is the rect itself
      _resizeWidget(_selected.last, localTo);
      return;
    }
    if (annotation.isCallout) {
      apply(
        (e) => e.reshapeCallout(_selected.last.$1, annotation, box: localTo),
      );
      return;
    }
    apply(
      (e) => e.resizeAnnotationLocal(
        _selected.last.$1,
        annotation,
        localTo,
        flipX: flipX,
        flipY: flipY,
        pageRotation: _page(_selected.last.$1).rotation,
      ),
    );
  }

  /// Replaces the defining vertices of the selected Line, PolyLine, or
  /// Polygon annotation. The selection keeps its /Annots slot.
  void reshapeSelectedLine(List<(double, double)> points) {
    final annotation = selectedAnnotation;
    if (annotation == null || !annotation.behavior.lineFamily) {
      return;
    }
    apply(
      (e) => e.reshapeLineAnnotation(_selected.last.$1, annotation, points),
    );
  }

  /// The single selected /PolyLine or /Polygon whose vertices can be edited
  /// by adding or removing nodes. A /Line is fixed at two points, so it is
  /// excluded. Null unless exactly one such annotation is selected.
  PdfAnnotation? get _editableVertexAnnotation {
    if (_selected.length != 1) return null;
    final annotation = selectedAnnotation;
    if (annotation == null) return null;
    final subtype = annotation.subtype;
    if (subtype != 'PolyLine' && subtype != 'Polygon') return null;
    return annotation.vertices == null ? null : annotation;
  }

  /// Whether a node can be added to the selected /PolyLine or /Polygon.
  bool get canAddSelectedVertex => _editableVertexAnnotation != null;

  /// Whether a node can be removed from the selected /PolyLine or /Polygon -
  /// true only when removing one still leaves a valid shape (2+ vertices for
  /// a polyline, 3+ for a polygon).
  bool get canRemoveSelectedVertex {
    final annotation = _editableVertexAnnotation;
    final vertices = annotation?.vertices;
    if (annotation == null || vertices == null) return false;
    final min = annotation.subtype == 'Polygon' ? 3 : 2;
    return vertices.length > min;
  }

  /// Adds a node to the selected /PolyLine or /Polygon at [at] (page space),
  /// splicing it into the edge nearest the point so the shape grows a vertex
  /// there. No-op unless a single editable poly is selected.
  void addSelectedVertexAt((double, double) at) {
    final annotation = _editableVertexAnnotation;
    final vertices = annotation?.vertices;
    if (annotation == null || vertices == null || vertices.length < 2) return;
    final insertAt = _nearestEdgeInsertIndex(
      vertices,
      at,
      closed: annotation.subtype == 'Polygon',
    );
    final points = List<(double, double)>.of(vertices)..insert(insertAt, at);
    apply(
      (e) => e.reshapeLineAnnotation(_selected.last.$1, annotation, points),
    );
  }

  /// Removes the node of the selected /PolyLine or /Polygon nearest [near]
  /// (page space). No-op when removing would drop below the subtype minimum
  /// (see [canRemoveSelectedVertex]) or nothing editable is selected.
  void removeSelectedVertexNear((double, double) near) {
    if (!canRemoveSelectedVertex) return;
    final annotation = _editableVertexAnnotation!;
    final vertices = annotation.vertices!;
    final index = _nearestVertexIndex(vertices, near);
    final points = List<(double, double)>.of(vertices)..removeAt(index);
    apply(
      (e) => e.reshapeLineAnnotation(_selected.last.$1, annotation, points),
    );
  }

  /// Index of the vertex in [pts] closest to [p] (page space).
  static int _nearestVertexIndex(
      List<(double, double)> pts, (double, double) p) {
    var best = 0;
    var bestDist = double.infinity;
    for (var i = 0; i < pts.length; i++) {
      final dx = pts[i].$1 - p.$1, dy = pts[i].$2 - p.$2;
      final dist = dx * dx + dy * dy;
      if (dist < bestDist) {
        bestDist = dist;
        best = i;
      }
    }
    return best;
  }

  /// The list index at which inserting [p] lands it on the edge of [pts]
  /// nearest the point. A [closed] polygon also weighs the wrap-around edge
  /// (last→first), for which the insertion index is the list end.
  static int _nearestEdgeInsertIndex(
    List<(double, double)> pts,
    (double, double) p, {
    required bool closed,
  }) {
    var best = pts.length; // append if nothing beats it
    var bestDist = double.infinity;
    final segments = closed ? pts.length : pts.length - 1;
    for (var i = 0; i < segments; i++) {
      final a = pts[i];
      final b = pts[(i + 1) % pts.length];
      final dist = _segmentDistanceSq(p, a, b);
      if (dist < bestDist) {
        bestDist = dist;
        best = i + 1;
      }
    }
    return best;
  }

  /// Squared distance from point [p] to the segment [a]–[b] (page space).
  static double _segmentDistanceSq(
    (double, double) p,
    (double, double) a,
    (double, double) b,
  ) {
    final abx = b.$1 - a.$1, aby = b.$2 - a.$2;
    final apx = p.$1 - a.$1, apy = p.$2 - a.$2;
    final len2 = abx * abx + aby * aby;
    var t = len2 == 0 ? 0.0 : (apx * abx + apy * aby) / len2;
    t = t.clamp(0.0, 1.0);
    final cx = a.$1 + t * abx, cy = a.$2 + t * aby;
    final dx = p.$1 - cx, dy = p.$2 - cy;
    return dx * dx + dy * dy;
  }

  /// Whether every selected annotation is a /Line or /PolyLine whose endings
  /// can be set together ([setSelectedLineEndings]).
  bool get canSetLineEndings {
    return _selected.isNotEmpty &&
        _selected.every((slot) {
          final annotation = _annotationAt(slot);
          return annotation != null &&
              annotation.behavior.supportsLineEndings &&
              annotation.normalAppearance != null;
        });
  }

  /// The primary selected /Line or /PolyLine's start/end line endings, or
  /// null when the selection cannot edit line endings. Multi-selection UIs
  /// may compare each annotation when they need a mixed-value indicator.
  (PdfLineEnding, PdfLineEnding)? get selectedLineEndings {
    final annotation = selectedAnnotation;
    if (annotation == null || !canSetLineEndings) return null;
    return pdfLineEndings(annotation);
  }

  /// Swaps the start and/or end ending of every selected /Line or /PolyLine
  /// in place - one revision, one undo, and the annotations keep their
  /// /Annots slots and object numbers. Pass null for an axis to leave it
  /// unchanged.
  void setSelectedLineEndings({PdfLineEnding? start, PdfLineEnding? end}) {
    if (!canSetLineEndings) return;
    final targets = <(int, PdfAnnotation)>[
      for (final slot in _selected)
        if (_annotationAt(slot) case final annotation?) (slot.$1, annotation),
    ];
    apply((e) {
      for (final (page, annotation) in targets) {
        e.setLineEndings(
          page,
          annotation,
          startEnding: start,
          endEnding: end,
        );
      }
    });
  }

  /// Whether the single selected annotation is a measurement (a /Line,
  /// /PolyLine, or /Polygon carrying a /Measure) whose caption font and
  /// size can be restyled in place ([setSelectedMeasurementCaption]).
  bool get canRestyleMeasurementCaption {
    final annotation = selectedAnnotation;
    return _selected.length == 1 &&
        annotation != null &&
        annotation.measure != null &&
        annotation.normalAppearance != null &&
        const {'Line', 'PolyLine', 'Polygon'}.contains(annotation.subtype);
  }

  /// The selected measurement caption's font and size, parsed from its
  /// /DA, or null when no single measurement is selected - for the font
  /// controls to reflect the current caption.
  ({PdfStandardFont font, double size})? get selectedMeasurementCaptionStyle {
    if (!canRestyleMeasurementCaption) return null;
    return _freeTextStyleOf(selectedAnnotation!);
  }

  /// Restyles the selected measurement's caption font and/or size in
  /// place - one revision, one undo, and the annotation keeps its /Annots
  /// slot and object number. Pass null for an axis to leave it unchanged.
  void setSelectedMeasurementCaption({PdfStandardFont? font, double? size}) {
    final annotation = selectedAnnotation;
    if (annotation == null || !canRestyleMeasurementCaption) return;
    apply(
      (e) => e.setMeasurementCaptionStyle(
        _selected.last.$1,
        annotation,
        font: font,
        size: size,
      ),
    );
  }

  /// Rotates the selected annotation by [degrees] counterclockwise (page
  /// space) about its center. The selection keeps its /Annots slot.
  void rotateSelected(double degrees) {
    final annotation = selectedAnnotation;
    if (annotation == null || !canRotateSelected) return;
    if (degrees.abs() < 0.01) return;
    apply(
      (e) => e.rotateAnnotation(_selected.last.$1, annotation, degrees),
    );
  }

  /// Deletes whatever is selected: the content element when the content
  /// tool has one, otherwise every selected annotation (one revision, so
  /// a single undo restores them all).
  void deleteSelected() {
    if (_selectedElement != null) {
      deleteSelectedElement();
      return;
    }
    if (_selected.isEmpty) return;
    // A field can now be selected from normal/select mode as well as the
    // form tool (including by right-click). Dropping only its /Annots entry
    // would leave /AcroForm /Fields dangling, so remove the whole field
    // regardless of which tool happened to make the selection.
    final fieldNames = <String>{};
    for (final slot in _selected) {
      final field = _widgetFieldForSlot(slot);
      if (field != null) fieldNames.add(field.$1);
    }
    if (fieldNames.isNotEmpty) {
      clearAnnotationSelection();
      apply((e) {
        for (final name in fieldNames) {
          final field = e.acroForm?.fieldNamed(name);
          if (field != null) e.removeField(field);
        }
      });
      return;
    }
    deleteAnnotations(List.of(_selected));
  }

  /// The selected annotation's text, for pre-filling an edit prompt.
  String? get selectedText => selectedAnnotation?.contents;

  /// Parses a free-text annotation's /DA: the font it was written with
  /// and its size, falling back to the current preferences.
  ({PdfStandardFont font, double size}) _freeTextStyleOf(
    PdfAnnotation annotation,
  ) {
    final tf = RegExp(
      r'/(\S+)\s+(\d+(?:\.\d+)?)\s+Tf',
    ).firstMatch(annotation.defaultAppearance ?? '');
    return (
      font: tf == null
          ? preferences.fontFamily
          : PdfStandardFont.fromName(tf.group(1)!),
      size: double.tryParse(tf?.group(2) ?? '') ?? preferences.fontSize,
    );
  }

  /// The font a free-text annotation should be re-created with on a text
  /// or size edit: its embedded font recovered from the appearance when
  /// present (so editing an embedded-font box keeps its font rather than
  /// reverting to Helvetica), else the base-14 face parsed from /DA.
  ({PdfTextFont font, double size}) _freeTextFontOf(PdfAnnotation annotation) {
    final standard = _freeTextStyleOf(annotation);
    final embedded = PdfEmbeddedFont.fromFreeText(annotation);
    return (font: embedded ?? standard.font, size: standard.size);
  }

  /// Whether the selection is a single free-text annotation whose font
  /// and size [restyleSelectedText] can change.
  bool get canRestyleSelectedText =>
      _selected.length == 1 && selectedAnnotation?.subtype == 'FreeText';

  /// The selected free-text annotation's font and size (parsed from its
  /// /DA), or null when the selection isn't free text.
  ({PdfStandardFont font, double size})? get selectedTextStyle {
    final annotation = selectedAnnotation;
    if (annotation?.subtype != 'FreeText') return null;
    return _freeTextStyleOf(annotation!);
  }

  /// The selected free-text annotation's per-run rich styling, parsed
  /// from its /RC (§12.7.3.4) with any missing attribute defaulted from
  /// the flat /DA. Null when the box carries no /RC (plain free text, or
  /// authored before rich styling) so the editor falls back to seeding a
  /// single uniform style. Lets reopening a mixed-format box rebuild its
  /// bold/italic/colour runs instead of collapsing to one style.
  List<PdfFreeTextRun>? get selectedRichRuns {
    final annotation = selectedAnnotation;
    if (annotation == null || annotation.subtype != 'FreeText') return null;
    final rc = annotation.richContent;
    if (rc == null) return null;
    final style = _freeTextStyleOf(annotation);
    final runs = PdfAnnotationEditing.parseFreeTextRichContent(
      rc,
      fallbackFont: style.font,
      fallbackSize: style.size,
    );
    return runs.isEmpty ? null : runs;
  }

  /// The selected free-text annotation's horizontal alignment (its /Q
  /// quadding), or null when the selection isn't a single free-text box.
  PdfTextAlign? get selectedTextAlign {
    if (!canRestyleSelectedText) return null;
    return selectedAnnotation?.freeTextStyle?.alignment ?? PdfTextAlign.left;
  }

  /// The actual font of the selected free-text box - its embedded font
  /// recovered from the appearance when present, else the base-14 face from
  /// /DA. Unlike [selectedTextStyle] (which only parses a standard family)
  /// this reports the real face, so the font picker shows a bundled/custom
  /// font's own name instead of collapsing to "Sans".
  PdfTextFont? get selectedTextFont {
    final annotation = selectedAnnotation;
    if (annotation == null || annotation.subtype != 'FreeText') return null;
    return _freeTextFontOf(annotation).font;
  }

  /// The selected free-text box's full parsed style (spacing, underline,
  /// alignment, colours), or null when the selection isn't a free-text box.
  PdfFreeTextStyle? get selectedFreeTextStyle {
    final annotation = selectedAnnotation;
    if (annotation == null || annotation.subtype != 'FreeText') return null;
    return annotation.freeTextStyle;
  }

  /// Sets box-level free-text styling (line spacing, character spacing,
  /// horizontal glyph width, whole-box underline) on the selected box,
  /// regenerating its appearance and preserving any per-run styling. Each
  /// value also becomes the creation default. Omitted values are left as-is.
  /// A no-op when the selection isn't a single free-text box.
  void setSelectedTextBoxStyle({
    double? lineSpacing,
    double? charSpacing,
    double? fontWidth,
    bool? underline,
  }) {
    if (lineSpacing != null) this.lineSpacing = lineSpacing;
    if (charSpacing != null) this.charSpacing = charSpacing;
    if (fontWidth != null) this.fontWidth = fontWidth;
    if (underline != null) textUnderline = underline;
    // while the inline editor owns the box, rewriting the annotation would
    // swap the document under it - the change rides the creation defaults
    // and lands when the edit commits instead
    if (isEditingText) return;
    final annotation = selectedAnnotation;
    if (annotation == null || !canRestyleSelectedText) return;
    final richRuns = selectedRichRuns;
    if (richRuns != null && richRuns.isNotEmpty) {
      final runs = underline == null
          ? richRuns
          : [
              for (final r in richRuns)
                PdfFreeTextRun(r.text,
                    font: r.font,
                    fontSize: r.fontSize,
                    color: r.color,
                    underline: underline)
            ];
      _rewriteSelectedRich(annotation, runs,
          lineSpacing: lineSpacing,
          charSpacing: charSpacing,
          fontWidth: fontWidth);
    } else {
      _rewriteSelected(
        annotation,
        annotation.contents ?? '',
        lineSpacing: lineSpacing,
        charSpacing: charSpacing,
        fontWidth: fontWidth,
        underline: underline,
      );
    }
  }

  PdfRect _autosizeTextRect(
    PdfAnnotation annotation,
    String text, {
    required PdfStandardFont font,
    required double size,
  }) {
    const pad = 3.0;
    final lines = text.split('\n');
    final maxLineWidth = lines.fold<double>(0, (max, line) {
      final w = measureStandardText(line, size, font: font);
      return w > max ? w : max;
    });
    final width = math.max(24.0, maxLineWidth + 2 * pad);
    final height = math.max(18.0, lines.length * size * 1.2 + 2 * pad);
    final page = _page(_selected.last.$1);
    final bounds = page.cropBox;
    // a callout autosizes its text box, not the /Rect that also spans the
    // leader + arrow: anchor at the box's top-left so the arrow stays put
    final anchor = annotation.calloutBox ?? annotation.rect;
    final left = anchor.left
        .clamp(bounds.left, math.max(bounds.left, bounds.right - width))
        .toDouble();
    final top = anchor.top
        .clamp(math.min(bounds.top, bounds.bottom + height), bounds.top)
        .toDouble();
    return PdfRect(left, top - height, left + width, top);
  }

  /// Shrinks or grows the selected free-text annotation to the natural
  /// bounds of its contents. Explicit newlines are preserved and the box is
  /// anchored at its current top-left corner, clamped to the page crop box.
  void autosizeSelectedTextBox() {
    final annotation = selectedAnnotation;
    if (annotation == null || !canRestyleSelectedText) return;
    final style = _freeTextStyleOf(annotation);
    final rect = _autosizeTextRect(
      annotation,
      annotation.contents ?? '',
      font: style.font,
      size: style.size,
    );
    resizeSelected(rect);
  }

  /// Rewrites the selected free-text annotation with a new [font] and/or
  /// [size], keeping its text, place, color, and author. The selection
  /// survives (the annotation keeps its /Annots slot).
  ///
  /// [fill] and [border] change the box's background and border color:
  /// the single-field record distinguishes "set to this RGB" - including
  /// `(null,)`, removing the fill/border - from an omitted parameter,
  /// which leaves the annotation's own style alone. A border set without
  /// [borderWidth] keeps the annotation's width (or 1pt when it had no
  /// border to keep).
  void restyleSelectedText({
    PdfStandardFont? font,
    double? size,
    PdfTextAlign? align,
    (int?,)? fill,
    (int?,)? border,
    double? borderWidth,
  }) {
    final annotation = selectedAnnotation;
    if (annotation == null || !canRestyleSelectedText) return;
    // Default to the box's own (possibly embedded) font, so changing only
    // the size never silently converts an embedded font to Helvetica; an
    // explicit [font] (the family picker) still wins.
    final style = _freeTextFontOf(annotation);
    _rewriteSelected(
      annotation,
      annotation.contents ?? '',
      font: font ?? style.font,
      size: size ?? style.size,
      align: align,
      fill: fill,
      border: border,
      borderWidth: borderWidth,
    );
  }

  /// Sets the horizontal alignment of the selected free-text box (its /Q
  /// quadding), regenerating its appearance, and makes it the default for
  /// new boxes. A no-op when the selection isn't a single free-text box.
  void setSelectedTextAlign(PdfTextAlign align) {
    preferences.textAlign = align; // the new default either way
    if (canRestyleSelectedText) restyleSelectedText(align: align);
  }

  /// Rewrites the selected free-text annotation in [font] - a base-14
  /// face or an embedded TrueType/OpenType font - keeping its text, size,
  /// place, color, and author. Unlike [restyleSelectedText] (which only
  /// takes the standard families) this can switch a box to any embedded
  /// font.
  void restyleSelectedFont(PdfTextFont font) {
    final annotation = selectedAnnotation;
    if (annotation == null || !canRestyleSelectedText) return;
    final style = _freeTextFontOf(annotation);
    _rewriteSelected(
      annotation,
      annotation.contents ?? '',
      font: font,
      size: style.size,
    );
  }

  /// Applies font, size, and/or text color to a substring of the selected
  /// FreeText annotation, leaving the rest of the annotation in its current
  /// style. [start] and [end] are UTF-16 string offsets, matching Flutter's
  /// [TextSelection] offsets.
  bool restyleSelectedTextRange(
    int start,
    int end, {
    PdfTextFont? font,
    double? size,
    int? color,
  }) {
    final annotation = selectedAnnotation;
    if (annotation == null || !canRestyleSelectedText) return false;
    final text = annotation.contents ?? '';
    final from = math.max(0, math.min(start, end)).clamp(0, text.length);
    final to = math.min(text.length, math.max(start, end));
    if (from == to) return false;
    final base = _freeTextFontOf(annotation);
    final parsed = annotation.freeTextStyle;
    final baseColor = parsed?.color ?? annotation.color ?? _colorValue;
    final target = PdfFreeTextRun(
      text.substring(from, to),
      font: font ?? base.font,
      fontSize: size ?? base.size,
      color: color ?? baseColor,
    );
    final runs = <PdfFreeTextRun>[
      if (from > 0)
        PdfFreeTextRun(
          text.substring(0, from),
          font: base.font,
          fontSize: base.size,
          color: baseColor,
        ),
      target,
      if (to < text.length)
        PdfFreeTextRun(
          text.substring(to),
          font: base.font,
          fontSize: base.size,
          color: baseColor,
        ),
    ];
    return _rewriteSelectedRich(annotation, runs);
  }

  /// Rewrites the selected annotation's text: same place, same style, new
  /// text. Implemented as remove + re-add, which regenerates the
  /// appearance stream.
  void setSelectedText(String text) {
    final annotation = selectedAnnotation;
    if (annotation == null || !canEditSelectedText) return;
    _rewriteSelected(annotation, text);
  }

  bool setSelectedRichText(List<PdfFreeTextRun> runs) {
    final annotation = selectedAnnotation;
    if (annotation == null || !canEditSelectedText) return false;
    return _rewriteSelectedRich(annotation, runs);
  }

  /// Whether /Contents can be assigned to the whole selection without
  /// changing visible annotation text. Free-text boxes and caption stamps
  /// need their appearances rebuilt individually, so bulk contents editing
  /// deliberately stands down for a selection containing either subtype.
  bool get canSetSelectedContents =>
      _selected.isNotEmpty &&
      _selected.every((slot) {
        final annotation = _annotationAt(slot);
        return annotation != null &&
            annotation.subtype != 'Widget' &&
            annotation.subtype != 'FreeText' &&
            annotation.subtype != 'Stamp' &&
            !annotation.isLockedContents;
      });

  /// Sets the selected annotation's /Contents. For a single subtype whose
  /// contents are displayed text (free text, stamps, notes), this rewrites
  /// the annotation so the page matches. Other annotations receive a
  /// metadata-only comment edit. A bulk-safe selection is updated in one
  /// revision. Returns whether anything changed.
  bool setSelectedContents(String text) {
    final annotation = selectedAnnotation;
    if (annotation == null) return false;
    if (_selected.length == 1) {
      if (annotation.isLockedContents) return false;
      if ((annotation.contents ?? '') == text) return false;
      if (canEditSelectedText) {
        setSelectedText(text);
        return true;
      }
      final page = _selected.last.$1;
      return apply(
        (e) => e.setAnnotationContents(page, annotation, text),
      );
    }
    if (!canSetSelectedContents) return false;
    final targets = <(int, PdfAnnotation)>[
      for (final slot in _selected)
        if (_annotationAt(slot) case final target?) (slot.$1, target),
    ];
    if (targets.every((target) => (target.$2.contents ?? '') == text)) {
      return false;
    }
    // Tooltip/comment edits change no page rendering.
    return apply((e) {
      for (final (page, target) in targets) {
        e.setAnnotationContents(page, target, text);
      }
    });
  }

  /// Whether /T is an author property for every selected annotation. Form
  /// widgets use /T as their field name and therefore cannot participate.
  bool get canSetSelectedAuthor =>
      _selected.isNotEmpty &&
      _selected.every((slot) {
        final annotation = _annotationAt(slot);
        return annotation != null && annotation.subtype != 'Widget';
      });

  /// Sets the author (/T) on every selected annotation - one revision,
  /// one undo. Null or empty removes it. Returns whether anything
  /// changed.
  bool setSelectedAuthor(String? author) {
    if (!canSetSelectedAuthor) return false;
    final value = (author != null && author.isEmpty) ? null : author;
    final targets = <(int, PdfAnnotation)>[
      for (final slot in _selected)
        if (_annotationAt(slot) case final annotation?) (slot.$1, annotation),
    ];
    if (targets.isEmpty) return false;
    if (targets.every((t) => t.$2.author == value)) return false;
    return apply((e) {
      for (final (page, annotation) in targets) {
        e.setAnnotationAuthor(page, annotation, value);
      }
    });
  }

  void _rewriteSelected(
    PdfAnnotation annotation,
    String text, {
    PdfTextFont? font,
    double? size,
    PdfTextAlign? align,
    (int?,)? fill,
    (int?,)? border,
    double? borderWidth,
    double? lineSpacing,
    double? charSpacing,
    double? fontWidth,
    bool? underline,
  }) {
    if (_selected.isEmpty) return;
    final page = _selected.last.$1;
    // a rotated text box flattens to horizontal under plain remove +
    // re-add (addFreeText/addStamp/addNote bake a horizontal matrix), so
    // re-create it in its un-rotated local frame and re-apply the resting
    // rotation afterwards - the same shape resizeAnnotationLocal uses.
    final rotation = _appearanceRotationOf(annotation);
    final rect = rotation == 0 ? annotation.rect : _localFrameOf(annotation);
    final color = annotation.color;
    final by = annotation.author; // a text edit doesn't change ownership
    final nm = annotation.name; // ... nor identity (sync tracks /NM)
    _selected.clear();
    apply(
      (e) {
        e.removeAnnotation(page, annotation);
        switch (annotation.subtype) {
          case 'FreeText':
            final style = _freeTextFontOf(annotation);
            // the parsed style carries what /C alone can't: the text color
            // (from /DA) plus any background fill and border; a wrapped
            // [fill]/[border] overrides it (see restyleSelectedText)
            final parsed = annotation.freeTextStyle;
            e.addFreeText(
              page,
              rect,
              text,
              fontSize: size ?? style.size,
              font: font ?? style.font,
              // keep the box's own alignment unless this edit changes it
              align: align ?? parsed?.alignment ?? PdfTextAlign.left,
              color: parsed?.color ?? color ?? 0x000000,
              fillColor: fill != null ? fill.$1 : parsed?.fillColor,
              borderColor: border != null ? border.$1 : parsed?.borderColor,
              borderWidth: borderWidth ??
                  ((parsed?.borderWidth ?? 0) > 0 ? parsed!.borderWidth : 1),
              // keep the box's own spacing/decoration unless changed
              lineSpacing: lineSpacing ??
                  parsed?.lineSpacing ??
                  kPdfFreeTextDefaultLineSpacing,
              charSpacing: charSpacing ?? parsed?.charSpacing ?? 0,
              horizontalScale: fontWidth ??
                  parsed?.horizontalScale ??
                  kPdfFreeTextDefaultHorizontalScale,
              underline: underline ?? parsed?.underline ?? false,
              pageRotation: _page(page).rotation,
              author: by,
              name: nm,
            );
          case 'Stamp':
            e.addStamp(
              page,
              rect,
              text,
              color: color ?? 0xC03030,
              pageRotation: _page(page).rotation,
              author: by,
              name: nm,
            );
          default: // 'Text'
            e.addNote(
              page,
              rect.left,
              rect.top,
              text,
              color: color ?? 0xFFD100,
              pageRotation: _page(page).rotation,
              author: by,
              name: nm,
            );
        }
        // spin the freshly horizontal box back onto the resting rotation:
        // the just-added annotation is the last /Annots entry
        if (rotation != 0) {
          final added = _document.page(page).annotations;
          if (added.isNotEmpty) {
            e.rotateAnnotation(page, added.last, rotation * 180 / math.pi);
          }
        }
      },
    );
    // the rewritten annotation lands in the last /Annots slot - keep it
    // selected so consecutive restyles (a settings popup) stay anchored
    final annotations = _page(page).annotations;
    if (annotations.isNotEmpty) {
      _selected
        ..clear()
        ..add((page, annotations.length - 1));
      notifyListeners();
    }
  }

  bool _rewriteSelectedRich(
    PdfAnnotation annotation,
    List<PdfFreeTextRun> runs, {
    double? lineSpacing,
    double? charSpacing,
    double? fontWidth,
    PdfTextAlign? align,
  }) {
    if (_selected.isEmpty || annotation.subtype != 'FreeText') return false;
    final page = _selected.last.$1;
    final rotation = _appearanceRotationOf(annotation);
    final rect = rotation == 0 ? annotation.rect : _localFrameOf(annotation);
    final by = annotation.author;
    final nm = annotation.name;
    final parsed = annotation.freeTextStyle;
    _selected.clear();
    final changed = apply(
      (e) {
        e.removeAnnotation(page, annotation);
        e.addFreeTextRich(
          page,
          rect,
          runs,
          align: align ?? parsed?.alignment ?? PdfTextAlign.left,
          fillColor: parsed?.fillColor,
          borderColor: parsed?.borderColor,
          borderWidth: (parsed?.borderWidth ?? 0) > 0 ? parsed!.borderWidth : 1,
          lineSpacing: lineSpacing ??
              parsed?.lineSpacing ??
              kPdfFreeTextDefaultLineSpacing,
          charSpacing: charSpacing ?? parsed?.charSpacing ?? 0,
          horizontalScale: fontWidth ??
              parsed?.horizontalScale ??
              kPdfFreeTextDefaultHorizontalScale,
          pageRotation: _page(page).rotation,
          author: by,
          name: nm,
        );
        if (rotation != 0) {
          final added = _document.page(page).annotations;
          if (added.isNotEmpty) {
            e.rotateAnnotation(page, added.last, rotation * 180 / math.pi);
          }
        }
      },
    );
    final annotations = _page(page).annotations;
    if (annotations.isNotEmpty) {
      _selected
        ..clear()
        ..add((page, annotations.length - 1));
      notifyListeners();
    }
    return changed;
  }

  /// The page-space rotation baked into [annotation]'s appearance (radians
  /// CCW, derived from its appearance quad), or 0 when it carries no
  /// rotation or has no appearance stream.
  static double _appearanceRotationOf(PdfAnnotation annotation) {
    final quad = annotation.appearanceQuad;
    if (quad == null) return 0;
    final dx = quad[1].$1 - quad[0].$1;
    final dy = quad[1].$2 - quad[0].$2;
    if (dx == 0 && dy == 0) return 0;
    final angle = math.atan2(dy, dx);
    return angle.abs() < 0.005 ? 0 : angle;
  }

  /// The un-rotated local box of a rotated [annotation]: its appearance
  /// quad's edge lengths about the quad center - the frame the text is
  /// re-created in before [PdfEditor.rotateAnnotation] spins it back.
  static PdfRect _localFrameOf(PdfAnnotation annotation) {
    final quad = annotation.appearanceQuad!;
    final (llx, lly) = quad[0];
    final (lrx, lry) = quad[1];
    final (urx, ury) = quad[2];
    final (ulx, uly) = quad[3];
    final cx = (llx + urx) / 2, cy = (lly + ury) / 2;
    final w = math.sqrt((lrx - llx) * (lrx - llx) + (lry - lly) * (lry - lly));
    final h = math.sqrt((ulx - llx) * (ulx - llx) + (uly - lly) * (uly - lly));
    return PdfRect(cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2);
  }

  // ---------------------------------------------------------------------
  // content elements

  /// Parsed page elements, cached per page for the current revision.
  final Map<int, PdfPageElements> _elements = {};

  /// (pageIndex, element id) of the selected content element. Element ids
  /// only mean anything within one revision, so any edit clears this.
  (int page, int id)? _selectedElement;

  void _invalidateElements() {
    _elements.clear();
    _pageCache.clear();
    _selectedElement = null;
    _form = null;
    _formResolved = false;
    _checkMarkCount = null;
  }

  /// The content elements of [pageIndex] at the current revision.
  PdfPageElements elementsOn(int pageIndex) => _elements.putIfAbsent(
        pageIndex,
        () => PdfPageElements.of(_document, pageIndex),
      );

  /// The selected content element, or null.
  PdfContentElement? get selectedElement {
    final selected = _selectedElement;
    if (selected == null) return null;
    final elements = elementsOn(selected.$1).elements;
    return selected.$2 < elements.length ? elements[selected.$2] : null;
  }

  /// The page the selected content element lives on.
  int? get selectedElementPage =>
      selectedElement == null ? null : _selectedElement!.$1;

  /// Whether the selected element is a text run whose characters the
  /// controller can rewrite.
  bool get canEditSelectedElementText =>
      selectedElement?.kind == PdfElementKind.text &&
      (selectedElement?.text?.isNotEmpty ?? false);

  /// Resolves a viewer text selection to the one editable page-content text
  /// element underneath all of its [rects]. Returns null for multi-run text,
  /// text inside a Form XObject, or ambiguous overlapping text layers.
  ///
  /// Keeping this conservative lets the selection menu promise that an edit
  /// changes exactly the occurrence the user selected. Broader paragraph and
  /// Form-XObject edits continue to use their dedicated content workflows.
  PdfContentElement? textElementForSelection(
    int pageIndex,
    List<PdfRect> rects,
    String text,
  ) {
    if (text.isEmpty || rects.isEmpty || text.contains('\n')) return null;
    final candidates = elementsOn(pageIndex).elements.where((element) {
      final bounds = element.bounds;
      final elementText = element.text;
      if (element.kind != PdfElementKind.text ||
          bounds == null ||
          elementText == null) {
        return false;
      }
      final occurrence = elementText.indexOf(text);
      if (occurrence < 0 ||
          elementText.indexOf(text, occurrence + text.length) >= 0) {
        return false;
      }
      return rects.every((rect) {
        final overlap = bounds.intersect(rect);
        return overlap.width > 0 && overlap.height > 0;
      });
    }).toList(growable: false);
    return candidates.length == 1 ? candidates.single : null;
  }

  /// Whether [element]'s current font can accept rich style overrides.
  /// Composite Type0 text can be re-typed in supported encodings, but the
  /// content editor deliberately preserves its appearance.
  bool canStyleContentText(int pageIndex, PdfContentElement element) {
    if (element.kind != PdfElementKind.text) return false;
    final name = element.resourceName;
    if (name == null) return true;
    final cos = _document.cos;
    final fonts = cos.resolve(pageAt(pageIndex).resources['Font']);
    if (fonts is! CosDictionary) return true;
    final font = cos.resolve(fonts[name]);
    if (font is! CosDictionary) return true;
    final subtype = cos.resolve(font['Subtype']);
    return subtype is! CosName || subtype.value != 'Type0';
  }

  /// Whether the selected element is an image-like content draw that can be
  /// removed from the page stream and replaced by an image stamp in the same
  /// bounds.
  bool get canReplaceSelectedElementImage {
    return _isReplaceableImageElement(selectedElement);
  }

  /// Whether the selected content element can be exported as a PNG image.
  bool get canExportSelectedElementImage {
    return _isReplaceableImageElement(selectedElement);
  }

  bool _isReplaceableImageElement(PdfContentElement? element) {
    return element?.bounds != null &&
        (element?.kind == PdfElementKind.image ||
            element?.kind == PdfElementKind.inlineImage);
  }

  /// Selects the topmost content element whose bounds contain ([x], [y])
  /// on [pageIndex]; clears the selection when nothing is hit. Bounds are
  /// approximate (see [PdfContentElement.bounds]).
  bool selectElementAt(int pageIndex, double x, double y) {
    final hits = elementsOn(pageIndex).elementsAt(x, y);
    if (hits.isEmpty) {
      clearElementSelection();
      return false;
    }
    final hit = (pageIndex, hits.first.id);
    if (_selectedElement != hit) {
      _selectedElement = hit;
      notifyListeners();
    }
    return true;
  }

  void clearElementSelection() {
    if (_selectedElement == null) return;
    _selectedElement = null;
    notifyListeners();
  }

  /// Deletes the selected content element from its page's content stream.
  void deleteSelectedElement() {
    final selected = _selectedElement;
    final element = selectedElement;
    if (selected == null || element == null) return;
    apply(
      (e) => e.deleteElements(elementsOn(selected.$1), [element.id]),
    );
  }

  /// Rewrites the selected text element's characters to [text] and
  /// returns how many text runs changed.
  ///
  /// Built on [PdfEditor.replaceText], so its limits apply: identical runs
  /// elsewhere on the page change too, and matches do not cross a line
  /// break. Replacements are re-measured so the rest of the line keeps its
  /// position. Composite (/Type0) text is handled; [fallbackFonts] (the
  /// bundled DejaVu trio, see `loadFallbackFonts`) draw any character the
  /// document's own font can't, so typing outside its subset still works.
  int replaceSelectedElementText(
    String text, {
    List<PdfEmbeddedFont> fallbackFonts = const [],
  }) {
    final selected = _selectedElement;
    final element = selectedElement;
    if (selected == null || element == null || !canEditSelectedElementText) {
      return 0;
    }
    var count = 0;
    apply(
      (e) => count = e.replaceText(
        selected.$1,
        element.text!,
        text,
        fallbackFonts: fallbackFonts,
      ),
    );
    return count;
  }

  /// Like [replaceSelectedElementText] but restyles the replacement with
  /// [style] (fill colour, size, bold, italic) via [PdfEditor.replaceText].
  ///
  /// Styling lands on simple-font runs; a composite (/Type0) element is still
  /// re-typed but keeps its original colour, size, and face. Returns how many
  /// runs changed.
  int replaceStyledSelectedElementText(
    String text,
    PdfTextStyle style, {
    List<PdfEmbeddedFont> fallbackFonts = const [],
  }) {
    final selected = _selectedElement;
    final element = selectedElement;
    if (selected == null || element == null || !canEditSelectedElementText) {
      return 0;
    }
    var count = 0;
    apply(
      (e) => count = e.replaceText(
        selected.$1,
        element.text!,
        text,
        fallbackFonts: fallbackFonts,
        style: style,
      ),
    );
    return count;
  }

  /// Rewrites [find] only inside [element], the occurrence resolved from a
  /// viewer text selection. Returns zero if the selection became stale while
  /// a prompt was open or if the PDF font cannot safely draw [text].
  int replaceTextInElement(
    int pageIndex,
    PdfContentElement element,
    String find,
    String text,
    PdfTextStyle style, {
    List<PdfEmbeddedFont> fallbackFonts = const [],
  }) {
    final elements = elementsOn(pageIndex);
    if (element.id < 0 ||
        element.id >= elements.elements.length ||
        !identical(elements.elements[element.id], element)) {
      return 0;
    }
    var count = 0;
    apply(
      (editor) => count = editor.replaceElementText(
        elements,
        element,
        find,
        text,
        fallbackFonts: fallbackFonts,
        style: style,
      ),
    );
    return count;
  }

  /// Replaces the selected page-content image with [imageBytes] (PNG or JPEG).
  ///
  /// The original image draw is removed from the content stream and the new
  /// image is inserted as a stamp annotation fitted into the same page-space
  /// bounds. This keeps the replacement movable/resizable while ensuring the
  /// old baked-in image is not left underneath it. Returns false when the
  /// selection is not a replaceable image or [imageBytes] cannot be decoded.
  bool replaceSelectedElementImage(Uint8List imageBytes) {
    final selected = _selectedElement;
    final element = selectedElement;
    final bounds = element?.bounds;
    if (selected == null ||
        element == null ||
        bounds == null ||
        !_isReplaceableImageElement(element) ||
        bounds.width <= 0 ||
        bounds.height <= 0) {
      return false;
    }
    final PdfEmbeddableImage image;
    try {
      image = PdfEmbeddableImage.decode(imageBytes);
    } catch (_) {
      return false;
    }
    return _replaceElementImage(selected, element, bounds, image);
  }

  /// Async counterpart to [replaceSelectedElementImage]. The built-in toolbar
  /// uses this so large PNG replacement does its decode/compress work off the
  /// UI isolate before the PDF revision is committed.
  Future<bool> replaceSelectedElementImageAsync(Uint8List imageBytes) async {
    final selected = _selectedElement;
    final element = selectedElement;
    final bounds = element?.bounds;
    if (selected == null ||
        element == null ||
        bounds == null ||
        !_isReplaceableImageElement(element) ||
        bounds.width <= 0 ||
        bounds.height <= 0) {
      return false;
    }
    final image = await _decodeEmbeddableImageAsync(imageBytes);
    if (image == null || _selectedElement != selected) return false;
    final current = selectedElement;
    final currentBounds = current?.bounds;
    if (current == null ||
        currentBounds == null ||
        current.id != element.id ||
        !_isReplaceableImageElement(current) ||
        currentBounds.width <= 0 ||
        currentBounds.height <= 0) {
      return false;
    }
    return _replaceElementImage(selected, current, currentBounds, image);
  }

  bool _replaceElementImage(
    (int page, int id) selected,
    PdfContentElement element,
    PdfRect bounds,
    PdfEmbeddableImage image,
  ) {
    final aspect = image.height == 0 ? 1.0 : image.width / image.height;
    var (width: w, height: h) = _visualSizeOfPageRect(selected.$1, bounds);
    if (w / h > aspect) {
      w = h * aspect;
    } else {
      h = w / aspect;
    }
    final cx = (bounds.left + bounds.right) / 2;
    final cy = (bounds.bottom + bounds.top) / 2;
    final elements = elementsOn(selected.$1);
    return apply(
      (e) => e
        ..deleteElements(elements, [element.id])
        ..addImageStamp(
          selected.$1,
          _pageRectForVisualSize(selected.$1, cx, cy, width: w, height: h),
          image,
          opacity: preferences.opacity,
          pageRotation: _page(selected.$1).rotation,
          author: preferences.author,
        ),
    );
  }

  /// Renders the selected page-content image element to a standalone PNG.
  ///
  /// This exports the selected element's page bounds as they render in the
  /// document. Image pixels are sampled from the clean page content only:
  /// annotations are omitted. Returns null when the current selection is not an
  /// image-like content element or the crop is degenerate.
  Future<PdfSelectedContentImage?> exportSelectedElementImage({
    double dpi = 150,
    Color pageColor = const Color(0xFFFFFFFF),
  }) async {
    if (dpi <= 0) throw ArgumentError.value(dpi, 'dpi', 'must be positive');
    final selected = _selectedElement;
    final element = selectedElement;
    final bounds = element?.bounds;
    if (selected == null ||
        element == null ||
        bounds == null ||
        !_isReplaceableImageElement(element) ||
        bounds.width <= 0 ||
        bounds.height <= 0) {
      return null;
    }

    final revisionAtStart = _revisionId;
    final page = _page(selected.$1);
    final size = PdfPageRenderer.pageSize(page, rotation: page.rotation);
    final geometry = PdfPageGeometry(
      cropBox: page.cropBox,
      rotation: page.rotation,
      viewSize: size,
    );
    final pageRegion = Offset.zero & size;
    final region = geometry.toViewRect(bounds).intersect(pageRegion);
    if (region.width <= 0 || region.height <= 0) return null;

    final nativeRatio = _nativeImagePixelRatio(element, region);
    final requestedRatio = math.max(dpi / 72, nativeRatio);
    final maxSideRatio = 8192 / math.max(region.width, region.height);
    final pixelRatio =
        requestedRatio.clamp(1.0, math.max(1.0, maxSideRatio)).toDouble();

    final picture = await PdfPageRenderer.renderPicture(
      page,
      pageColor: pageColor,
      annotations: false,
      rotation: page.rotation,
    );
    ui.Image? image;
    try {
      image = await PdfPageRenderer.rasterizeRegion(
        picture,
        region,
        pixelRatio,
      );
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null ||
          revisionAtStart != _revisionId ||
          _selectedElement != selected) {
        return null;
      }
      return PdfSelectedContentImage(
        pageIndex: selected.$1,
        pageRect: bounds,
        pngBytes: Uint8List.fromList(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        ),
      );
    } finally {
      image?.dispose();
      picture.dispose();
    }
  }

  double _nativeImagePixelRatio(PdfContentElement element, Rect region) {
    final width = element.imageWidth;
    final height = element.imageHeight;
    if (width == null || height == null || width <= 0 || height <= 0) {
      return 1;
    }
    return math.max(width / region.width, height / region.height);
  }

  /// Edits the selected text element and re-flows its whole paragraph via
  /// [PdfEditor.reflowText]: when the replacement changes the paragraph's
  /// line count, the paragraph re-wraps at its right margin and the lines
  /// that follow it cascade up or down so nothing overlaps.
  ///
  /// Returns true when a paragraph was reflowed, false (nothing changed)
  /// when the selection isn't part of a reflowable paragraph - single
  /// column, left aligned, one font/size, regular leading (see
  /// [PdfParagraphReflow]); the caller can fall back to
  /// [replaceSelectedElementText] for an in-line correction.
  bool reflowSelectedElementText(String text) {
    final selected = _selectedElement;
    final element = selectedElement;
    if (selected == null || element == null || !canEditSelectedElementText) {
      return false;
    }
    var reflowed = false;
    apply(
      (e) => reflowed = e.reflowText(selected.$1, element.text!, text),
    );
    return reflowed;
  }

  // ---------------------------------------------------------------------
  // forms

  PdfAcroForm? _form;
  bool _formResolved = false;

  /// The document's interactive form at the current revision, or null
  /// when it has none. Cached per revision - enumerating fields walks
  /// the whole field tree, and the form tool's hit tests run per
  /// pointer event.
  PdfAcroForm? get acroForm {
    if (!_formResolved) {
      _form = PdfAcroForm.of(_document);
      _formResolved = true;
    }
    return _form;
  }

  /// The topmost visible form-field widget under ([x], [y]) on
  /// [pageIndex], with the hit widget's index within its field - for a
  /// radio group that index says which button was tapped
  /// ([PdfFormField.widgetOnState]). Null when nothing is hit.
  (PdfFormField field, int widgetIndex)? formFieldAt(
    int pageIndex,
    double x,
    double y,
  ) {
    final form = acroForm;
    if (form == null) return null;
    final annotations = _page(pageIndex).annotations;
    // later /Annots entries paint on top, so they win the hit test
    for (var i = annotations.length - 1; i >= 0; i--) {
      final annotation = annotations[i];
      if (annotation.subtype != 'Widget' || annotation.isHidden) continue;
      if (!annotation.rect.contains(x, y)) continue;
      for (final field in form.fields) {
        final widgets = field.widgets;
        for (var w = 0; w < widgets.length; w++) {
          if (identical(widgets[w], annotation.dict)) return (field, w);
        }
      }
    }
    return null;
  }

  /// Every visible form-field widget shown on [pageIndex], paired with
  /// its field and the widget's index within that field (a radio group
  /// has one entry per button, and [PdfFormField.widgetOnState] says
  /// which state each selects). The reader's interactive form layer
  /// places a tap target over each entry's [PdfAnnotation.rect].
  ///
  /// Hidden / no-view widgets are skipped - they don't render, so they
  /// take no taps. Resolved against the per-revision page cache and
  /// [acroForm]; the returned fields die with the next revision.
  List<(PdfFormField field, int widgetIndex, PdfAnnotation widget)>
      formWidgetsOn(int pageIndex) {
    final form = acroForm;
    if (form == null) return const [];
    final annotations = _page(pageIndex).annotations;
    final result = <(PdfFormField, int, PdfAnnotation)>[];
    for (final annotation in annotations) {
      if (annotation.subtype != 'Widget' ||
          annotation.isHidden ||
          annotation.isNoView) {
        continue;
      }
      for (final field in form.fields) {
        final widgets = field.widgets;
        for (var w = 0; w < widgets.length; w++) {
          if (identical(widgets[w], annotation.dict)) {
            result.add((field, w, annotation));
          }
        }
      }
    }
    return result;
  }

  /// Shared fill plumbing: resolves the field by [name] (fields die with
  /// every revision, so names are the stable handle), guards type and
  /// read-only, and turns editor complaints into a false return - a UI
  /// tap must never crash on a quirky field.
  bool _fillField(
    String name,
    Set<PdfFieldType> types,
    void Function(PdfEditor e, PdfFormField f) fill,
  ) {
    final field = acroForm?.fieldNamed(name);
    if (field == null || field.isReadOnly || !types.contains(field.type)) {
      return false;
    }
    try {
      return apply(
        (e) {
          final f = e.acroForm?.fieldNamed(name);
          if (f != null) fill(e, f);
        },
      );
    } on ArgumentError {
      return false;
    } on StateError {
      return false;
    }
  }

  /// Sets the text field [name]'s value, regenerating its appearance.
  /// Returns false for missing/read-only fields and unchanged values.
  bool setFormFieldText(String name, String value) {
    final field = acroForm?.fieldNamed(name);
    if (field != null && (field.value ?? '') == value) return false;
    return _fillField(
        name,
        const {
          PdfFieldType.text,
        },
        (e, f) => e.setTextValue(f, value));
  }

  /// Toggles the check box [name].
  bool toggleFormCheckBox(String name) => _fillField(
      name,
      const {
        PdfFieldType.checkBox,
      },
      (e, f) => e.setCheckBoxValue(f, !f.isChecked));

  /// Selects [onState] in the radio group [name] (the tapped widget's
  /// [PdfFormField.widgetOnState]).
  bool setFormRadioValue(String name, String onState) {
    final field = acroForm?.fieldNamed(name);
    if (field != null && field.value == onState) return false;
    return _fillField(
        name,
        const {
          PdfFieldType.radioGroup,
        },
        (e, f) => e.setRadioValue(f, onState));
  }

  /// Sets the choice field [name] to [value] (an export or display
  /// value, per [PdfEditor.setChoiceValue]).
  bool setFormChoiceValue(String name, String value) => _fillField(
      name,
      const {
        PdfFieldType.comboBox,
        PdfFieldType.listBox,
      },
      (e, f) => e.setChoiceValue(f, value));

  /// Fills the push button [name] with [imageBytes] (PNG or JPEG),
  /// aspect-fit - signature and logo fields in template pipelines.
  bool setFormButtonImage(String name, Uint8List imageBytes) {
    final PdfEmbeddableImage image;
    try {
      image = PdfEmbeddableImage.decode(imageBytes);
    } catch (_) {
      return false;
    }
    return _fillField(
        name,
        const {
          PdfFieldType.pushButton,
        },
        (e, f) => e.setButtonImage(f, image));
  }

  /// Async counterpart to [setFormButtonImage]. See [placeImageAsync].
  Future<bool> setFormButtonImageAsync(
    String name,
    Uint8List imageBytes,
  ) async {
    final image = await _decodeEmbeddableImageAsync(imageBytes);
    if (image == null) return false;
    return _fillField(
        name,
        const {
          PdfFieldType.pushButton,
        },
        (e, f) => e.setButtonImage(f, image));
  }

  PdfFormFieldKind _newFormFieldKind = PdfFormFieldKind.text;

  /// The kind of field a form-tool drag on empty page area creates.
  /// Not persisted - each session starts adding text fields.
  PdfFormFieldKind get newFormFieldKind => _newFormFieldKind;

  set newFormFieldKind(PdfFormFieldKind value) {
    if (value == _newFormFieldKind) return;
    _newFormFieldKind = value;
    notifyListeners();
  }

  /// Adds a new [kind] field covering [rect] on [pageIndex], creating
  /// the document's /AcroForm when it has none. The name is generated
  /// ('Field 1', 'Field 2', …); rename it via [renameFormField].
  /// Returns the new field's name, or null when nothing was added.
  String? addFormField(PdfFormFieldKind kind, int pageIndex, PdfRect rect) {
    var i = 1;
    while (acroForm?.fieldNamed('Field $i') != null) {
      i++;
    }
    final name = 'Field $i';
    final added = apply(
      (e) {
        switch (kind) {
          case PdfFormFieldKind.text:
            e.addTextField(pageIndex, name, rect);
          case PdfFormFieldKind.checkBox:
            e.addCheckBoxField(pageIndex, name, rect);
          case PdfFormFieldKind.pushButton:
            e.addPushButtonField(pageIndex, name, rect);
        }
      },
    );
    return added ? name : null;
  }

  /// Renames the field [name] to [newName]. Returns false when the
  /// field is missing, [newName] is empty, or another field already
  /// carries it.
  bool renameFormField(String name, String newName) {
    if (acroForm?.fieldNamed(name) == null) return false;
    try {
      // a rename changes no page's rendering
      return apply((e) {
        final f = e.acroForm?.fieldNamed(name);
        if (f != null) e.renameField(f, newName);
      });
    } on ArgumentError {
      return false;
    }
  }

  /// Removes the field [name] and its widgets.
  bool removeFormField(String name) {
    if (acroForm?.fieldNamed(name) == null) return false;
    return apply(
      (e) {
        final f = e.acroForm?.fieldNamed(name);
        if (f != null) e.removeField(f);
      },
    );
  }

  /// Rebuilds the field [name] as [kind] at its first widget's place,
  /// keeping the name ([PdfEditor.changeFieldType]). Returns false when
  /// the field is missing, already that kind, or unrebuildable.
  bool changeFormFieldKind(String name, PdfFormFieldKind kind) {
    final field = acroForm?.fieldNamed(name);
    if (field == null) return false;
    final type = switch (kind) {
      PdfFormFieldKind.text => PdfFieldType.text,
      PdfFormFieldKind.checkBox => PdfFieldType.checkBox,
      PdfFormFieldKind.pushButton => PdfFieldType.pushButton,
    };
    if (field.type == type) return false;
    final reselect = selectedWidgetFieldName == name;
    try {
      final changed = apply(
        (e) {
          final f = e.acroForm?.fieldNamed(name);
          if (f != null) e.changeFieldType(f, type);
        },
      );
      // A conversion removes the old widget and appends a rebuilt one, so
      // its /Annots slot is not a stable selection handle. Follow the field
      // name (which changeFieldType preserves) to keep the contextual
      // toolbar and properties panel anchored on the converted field.
      if (changed && reselect) selectFormFieldByName(name);
      return changed;
    } on ArgumentError {
      return false;
    } on StateError {
      return false;
    }
  }

  /// Flattens the interactive form: bakes every widget's appearance
  /// into its page and removes all fields ([PdfEditor.flattenForm]).
  bool flattenFormFields() => apply((e) => e.flattenForm());

  /// The selected text field (name + field), or null unless exactly one
  /// text-field widget is selected - the styling controls' target.
  (String name, PdfFormField field)? get _selectedFormTextField {
    if (_selected.length != 1) return null;
    if (selectedAnnotation?.subtype != 'Widget') return null;
    final ref = _widgetFieldForSlot(_selected.last);
    if (ref == null) return null;
    final field = acroForm?.fieldNamed(ref.$1);
    if (field == null || field.type != PdfFieldType.text) return null;
    return (ref.$1, field);
  }

  /// Whether a single text-field widget is selected, so its text styling
  /// (font, size, colour, alignment, auto-size, multiline) can be changed
  /// via [setFormFieldStyle] / [selectedFormFieldStyle].
  bool get canStyleSelectedFormField => _selectedFormTextField != null;

  /// The name of the selected text field, or null unless exactly one is
  /// selected - the handle the style controls pass to [setFormFieldStyle].
  String? get selectedFormFieldName => _selectedFormTextField?.$1;

  /// The field name of the selected form widget of any field type (text,
  /// check box, radio, button, …), or null unless exactly one form widget
  /// is selected - for the properties panel's field-name row.
  String? get selectedWidgetFieldName {
    if (_selected.length != 1 || selectedAnnotation?.subtype != 'Widget') {
      return null;
    }
    return _widgetFieldForSlot(_selected.last)?.$1;
  }

  /// The type of the selected form widget's field, or null unless exactly
  /// one widget belonging to a resolvable field is selected.
  PdfFieldType? get selectedWidgetFieldType {
    final name = selectedWidgetFieldName;
    return name == null ? null : acroForm?.fieldNamed(name)?.type;
  }

  /// Converts the single selected form widget's field to [kind], preserving
  /// its name, first-widget rectangle, and selection. Returns false when no
  /// field widget is selected, it already has that kind, or it cannot be
  /// rebuilt.
  bool changeSelectedFormFieldKind(PdfFormFieldKind kind) {
    final name = selectedWidgetFieldName;
    return name != null && changeFormFieldKind(name, kind);
  }

  /// Selects the field [name]'s first widget (so the style controls and
  /// move/resize act on it) by hit-testing its rectangle's centre. Returns
  /// false when the field or its first widget's page/rect can't be found.
  bool selectFormFieldByName(String name) {
    final field = acroForm?.fieldNamed(name);
    if (field == null) return false;
    final page = field.widgetPageIndex(0);
    final rect = field.widgetRect(0);
    if (page < 0 || rect == null) return false;
    return selectFormWidgetAt(
      page,
      (rect.left + rect.right) / 2,
      (rect.bottom + rect.top) / 2,
    );
  }

  /// The selected text field's current style, or null when no single text
  /// field is selected - drives the form-field style controls.
  PdfFormFieldStyle? get selectedFormFieldStyle {
    final sel = _selectedFormTextField;
    if (sel == null) return null;
    final field = sel.$2;
    final name = RegExp(
          r'/(\S+)\s+[\d.]+\s+Tf',
        ).firstMatch(field.defaultAppearance ?? '')?.group(1) ??
        'Helv';
    final size = field.appearanceFontSize;
    return PdfFormFieldStyle(
      font: PdfStandardFont.fromName(name),
      size: size == 0 ? 12 : size,
      autoSize: size == 0,
      color: Color(0xFF000000 | (field.appearanceColor ?? 0)),
      align: PdfTextAlign.values.firstWhere(
        (a) => a.quadding == field.quadding,
        orElse: () => PdfTextAlign.left,
      ),
      multiline: field.isMultiline,
    );
  }

  /// Restyles the text field [name] ([PdfEditor.setTextFieldStyle]): each
  /// non-null argument is applied. [font] may be a base-14 [PdfStandardFont]
  /// or an embedded [PdfEmbeddedFont]; [autoSize] true (or [preferences.fontSize] 0)
  /// fits the text to the box; [color] is 0xRRGGBB. Returns false for a
  /// missing, read-only, or non-text field.
  bool setFormFieldStyle(
    String name, {
    PdfTextFont? font,
    double? fontSize,
    bool? autoSize,
    int? color,
    PdfTextAlign? align,
    bool? multiline,
  }) {
    final field = acroForm?.fieldNamed(name);
    if (field == null || field.isReadOnly || field.type != PdfFieldType.text) {
      return false;
    }
    try {
      return apply(
        (e) {
          final f = e.acroForm?.fieldNamed(name);
          if (f != null) {
            e.setTextFieldStyle(
              f,
              font: font,
              fontSize: fontSize,
              autoSize: autoSize,
              color: color,
              align: align,
              multiline: multiline,
            );
          }
        },
      );
    } on ArgumentError {
      return false;
    } on StateError {
      return false;
    }
  }
}
