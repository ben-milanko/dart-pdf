import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:pdf_document/pdf_document.dart';

import 'editing_measure.dart';
import 'editing_preferences.dart';
import 'editing_signature.dart';
import 'editing_stamps.dart';

/// The annotation tools a [PdfEditingController] can arm.
///
/// Text markups (highlight, underline, strike-out, squiggly) are not
/// tools — they act on the viewer's current text selection through
/// [PdfEditingController.addMarkup].
enum PdfEditTool {
  /// Tap to select an annotation; drag it to move, drag its handles to
  /// resize.
  select,

  /// Freehand drawing. Strokes accumulate in the controller until
  /// [PdfEditingController.finishInk] commits them as one Ink annotation.
  ink,

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

  /// Drag out a box, then type the text shown inside it (/FreeText).
  freeText,

  /// Tap to place a sticky note (/Text).
  note,

  /// Rubber stamps (/Stamp). With a [PdfEditingController.activeStamp]
  /// a tap places it; otherwise drag out a box and type the caption.
  stamp,

  /// Tap to place the saved hand-drawn signature
  /// ([PdfEditingController.signature]) as an Ink annotation.
  signature,

  /// Tap to select a page content element (text run, path, image); the
  /// selection can be deleted or, for text, rewritten. Edits the page's
  /// content stream itself, not annotations.
  content,

  /// Interactive forms: tap a field widget to fill it (text fields open
  /// an inline editor, check boxes and radio buttons toggle, choice
  /// fields offer their options), drag on empty page area to add a new
  /// field of [PdfEditingController.newFormFieldKind], right-click a
  /// widget for rename/convert/delete.
  form,
}

/// Text-markup kinds for [PdfEditingController.addMarkup].
enum PdfMarkupKind { highlight, underline, strikeOut, squiggly }

/// Host veto over which annotations the editing UI may change — see
/// [PdfEditingController.canEditAnnotation].
typedef PdfAnnotationEditPredicate = bool Function(PdfAnnotation annotation);

/// The field kinds the form tool can create (and convert fields to) —
/// the subset of [PdfFieldType] with creation support in [PdfEditor].
enum PdfFormFieldKind { text, checkBox, pushButton }

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
  PdfEditingController(Uint8List bytes,
      {String password = '', PdfEditingPreferences? preferences})
      : _bytes = bytes,
        _password = password,
        _revisions = [bytes.length],
        _document = PdfDocument.open(bytes, password: password),
        preferences = preferences ?? PdfEditingPreferences() {
    this.preferences.addListener(notifyListeners);
  }

  /// The persisted UI preferences backing [color], [strokeWidth],
  /// [fontSize], [opacity], and [fingerDrawsInk] — every change is saved
  /// to the local device and restored on the next session. Pass one in
  /// to share it with the host's chrome (the sidebar-visibility flags
  /// live there too).
  final PdfEditingPreferences preferences;

  @override
  void dispose() {
    _inkTimer?.cancel();
    _flashTimer?.cancel();
    _changeFeed?.close();
    preferences.removeListener(notifyListeners);
    super.dispose();
  }

  final String _password;

  /// The full byte buffer; revisions are prefixes of it.
  Uint8List _bytes;

  /// Byte length of each revision, oldest first. `_revisions[_cursor]`
  /// is the current one; entries past the cursor are redoable.
  final List<int> _revisions;
  int _cursor = 0;

  /// Parallels [_revisions]: the page indices each revision changed
  /// visually (null = unknown, treat as all). Entry 0 — the original
  /// document — is never consulted.
  final List<Set<int>?> _revisionPages = [null];

  /// Render stamps: how many times each page's rendering has changed.
  /// [_renderStampEpoch] counts the all-pages bumps (structural edits,
  /// unknown-page edits) so they don't iterate a large document.
  final Map<int, int> _renderStamps = {};
  int _renderStampEpoch = 0;

  void _bumpRenderStamps(Set<int>? pages) {
    if (pages == null) {
      _renderStampEpoch++;
    } else {
      for (final page in pages) {
        _renderStamps[page] = (_renderStamps[page] ?? 0) + 1;
      }
    }
  }

  /// A value that changes whenever [pageIndex]'s rendering may have
  /// changed — and stays put across edits, undo, and redo that touched
  /// other pages only. Thumbnails key their raster caches on it instead
  /// of re-rendering every page on every revision.
  int pageRenderStamp(int pageIndex) =>
      _renderStampEpoch + (_renderStamps[pageIndex] ?? 0);

  PdfDocument _document;

  /// The document at the current revision. Changes identity on every
  /// edit, undo, and redo.
  PdfDocument get document => _document;

  /// The current revision's bytes — what "save to disk" should write.
  Uint8List get bytes => Uint8List.sublistView(_bytes, 0, _revisions[_cursor]);

  /// Whether the current revision differs from the originally opened one.
  bool get isModified => _cursor > 0;

  bool get canUndo => _cursor > 0;
  bool get canRedo => _cursor < _revisions.length - 1;

  void undo() {
    if (!canUndo) return;
    final beforeLength = _revisions[_cursor];
    final pages = _revisionPages[_cursor];
    // reverting revision N un-renders exactly the pages N touched
    _bumpRenderStamps(pages);
    _cursor--;
    _reopen();
    _emitAnnotationChanges(beforeLength, pages);
  }

  void redo() {
    if (!canRedo) return;
    final beforeLength = _revisions[_cursor];
    _cursor++;
    final pages = _revisionPages[_cursor];
    _bumpRenderStamps(pages);
    _reopen();
    _emitAnnotationChanges(beforeLength, pages);
  }

  void _reopen() {
    _document = PdfDocument.open(bytes, password: _password);
    // the same /Annots slot may hold a different annotation now
    _selected.clear();
    _invalidateElements();
    notifyListeners();
  }

  /// Runs [edit] against the current document and commits the result as a
  /// new revision. Returns false (and changes nothing) if [edit] staged no
  /// changes. Redoable revisions are discarded, like any editor's redo
  /// stack on a fresh edit.
  ///
  /// [pages] names the page indices the edit changes visually — it feeds
  /// [pageRenderStamp], which lets page thumbnails skip re-rendering
  /// pages an edit didn't touch. Omit it (null) when the affected pages
  /// are unknown and every page's stamp is bumped.
  bool apply(void Function(PdfEditor editor) edit, {Iterable<int>? pages}) {
    final editor = PdfEditor(_document);
    edit(editor);
    if (!editor.hasChanges) return false;
    final saved = editor.save();
    final beforeLength = _revisions[_cursor];
    final touched = pages == null ? null : Set<int>.unmodifiable(pages);
    _revisions.removeRange(_cursor + 1, _revisions.length);
    _revisionPages.removeRange(_cursor + 1, _revisionPages.length);
    _bytes = saved;
    _revisions.add(saved.length);
    _revisionPages.add(touched);
    _bumpRenderStamps(touched);
    _cursor++;
    final selected = List.of(_selected);
    _document = PdfDocument.open(bytes, password: _password);
    // annotations keep their /Annots slot across move/resize edits, so a
    // still-valid selection survives the document swap
    _selected
      ..clear()
      ..addAll([
        for (final slot in selected)
          if (_annotationAt(slot) != null) slot
      ]);
    _invalidateElements();
    _emitAnnotationChanges(beforeLength, touched);
    notifyListeners();
    return true;
  }

  // ---------------------------------------------------------------------
  // annotation sync (the change feed and its replay half)

  StreamController<List<PdfAnnotationChange>>? _changeFeed;
  bool _applyingRemote = false;

  /// A live feed of annotation diffs: after every edit, undo, and redo,
  /// one batch of [PdfAnnotationChange]s describing what happened to the
  /// document's annotations, keyed on their /NM identity
  /// ([PdfAnnotation.name]). Nothing is computed while nobody listens.
  ///
  /// This is the outbound half of annotation sync: serialize each
  /// change's snapshot ([PdfAnnotationSnapshot.toJson]) into your store
  /// (Firestore, a server, ...) and replay batches from other devices
  /// through [applyRemoteChange] — remote applies don't re-emit, so
  /// there is no echo to suppress.
  ///
  /// Caveats: open pre-existing documents with [ensureAnnotationNames] +
  /// [annotationBaseline] so every annotation has a durable identity
  /// first, and remember that remote applies join the revision (undo)
  /// stack — undoing past one reverts it locally and broadcasts the
  /// revert as a local change.
  Stream<List<PdfAnnotationChange>> get annotationChanges =>
      (_changeFeed ??= StreamController.broadcast()).stream;

  /// Diffs the revision that was [beforeLength] bytes long against the
  /// current document and emits the result. The before state reopens
  /// from its bytes (a prefix of the live buffer): the editor mutates
  /// the in-memory COS of the document it ran on, so the pre-edit
  /// [PdfDocument] object is already contaminated with the edit.
  void _emitAnnotationChanges(int beforeLength, Iterable<int>? pages) {
    final feed = _changeFeed;
    if (feed == null || !feed.hasListener || _applyingRemote) return;
    final before = PdfDocument.open(
        Uint8List.sublistView(_bytes, 0, beforeLength),
        password: _password);
    // `pages` names render-changed pages; metadata edits (contents,
    // author) pass an empty set because nothing repaints, yet the
    // annotation content did change — diff everything for those.
    final diffPages = pages != null && pages.isEmpty ? null : pages;
    final changes = pdfDiffAnnotations(before, _document, pages: diffPages);
    if (changes.isNotEmpty) feed.add(changes);
  }

  /// Replays one change from another device or session: upserts the
  /// snapshot of a created/modified change, removes by name for a
  /// removed one. Returns whether the document changed.
  ///
  /// The edit is a normal revision (rendering, thumbnails, and undo all
  /// see it) but is never re-emitted on [annotationChanges].
  bool applyRemoteChange(PdfAnnotationChange change) {
    final snapshot = change.snapshot;
    _applyingRemote = true;
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
          return apply((e) => e.upsertAnnotation(change.pageIndex, snapshot),
              pages: touched);
        case PdfAnnotationChangeKind.removed:
          final name = change.name;
          if (name == null) return false;
          final existing = findAnnotationByName(name);
          if (existing == null) return false;
          _selected.removeWhere((slot) => slot.$1 == existing.$1);
          return apply((e) {
            e.removeAnnotation(existing.$1, existing.$2);
          }, pages: [existing.$1]);
      }
    } finally {
      _applyingRemote = false;
    }
  }

  /// Stamps a generated /NM on every annotation that lacks one (see
  /// [PdfAnnotationEditing.nameAnnotations]) — run once when opening a
  /// document for sync, before [annotationBaseline]. Returns how many
  /// were named. Emits nothing: the baseline is the explicit hand-off.
  int ensureAnnotationNames() {
    var named = 0;
    _applyingRemote = true; // names are identity, not an annotation edit
    try {
      apply((e) => named = e.nameAnnotations(), pages: const <int>[]);
    } finally {
      _applyingRemote = false;
    }
    return named;
  }

  /// The current document's whole annotation state as created-changes —
  /// what a sync layer uploads to seed its store when a document joins
  /// sync. Annotations without /NM (call [ensureAnnotationNames] first)
  /// and non-captureable subtypes (popups, links, widgets) are skipped.
  List<PdfAnnotationChange> annotationBaseline() {
    final changes = <PdfAnnotationChange>[];
    for (var pageIndex = 0; pageIndex < _document.pageCount; pageIndex++) {
      for (final annotation in _page(pageIndex).annotations) {
        if (annotation.name == null) continue;
        final snapshot = PdfAnnotationSnapshot.capture(_document, annotation,
            keepName: true);
        if (snapshot == null) continue;
        changes.add(PdfAnnotationChange(
          kind: PdfAnnotationChangeKind.created,
          pageIndex: pageIndex,
          name: annotation.name,
          snapshot: snapshot,
        ));
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

  /// The armed tool, or null when the viewer behaves as a plain reader.
  PdfEditTool? get tool => _tool;

  set tool(PdfEditTool? value) {
    if (value == _tool) return;
    // leaving the ink tool commits the drawing, like lifting the pen
    if (_tool == PdfEditTool.ink && value != PdfEditTool.ink) finishInk();
    _tool = value;
    if (value != PdfEditTool.select) _selected.clear();
    if (value != PdfEditTool.content) _selectedElement = null;
    notifyListeners();
  }

  /// The color new annotations are created with. Persisted (these four
  /// style properties live in [preferences]).
  Color get color => preferences.color;

  set color(Color value) => preferences.color = value;

  /// Stroke width for ink and shape annotations, in PDF points. Persisted.
  double get strokeWidth => preferences.strokeWidth;

  set strokeWidth(double value) => preferences.strokeWidth = value;

  /// The circle eraser's radius, in PDF points — the eraser removes
  /// every part of an ink stroke within this distance of its swept
  /// path, PSPDFKit-style. Persisted.
  double get eraserRadius => preferences.eraserRadius;

  set eraserRadius(double value) => preferences.eraserRadius = value;

  /// Font size for free-text annotations, in PDF points. Persisted.
  double get fontSize => preferences.fontSize;

  set fontSize(double value) => preferences.fontSize = value;

  /// Font family for free-text annotations — one of the standard PDF
  /// text fonts (sans-serif, serif, monospace). Persisted.
  PdfStandardFont get fontFamily => preferences.fontFamily;

  set fontFamily(PdfStandardFont value) => preferences.fontFamily = value;

  /// Opacity (0–1] new ink, shape, markup, and stamp annotations are
  /// created with. Free text and notes are always opaque. Persisted.
  double get opacity => preferences.opacity;

  set opacity(double value) => preferences.opacity = value;

  bool get dashedStroke => preferences.dashedStroke;

  set dashedStroke(bool value) => preferences.dashedStroke = value;

  /// The line ending new /Line and /PolyLine annotations carry at their
  /// start vertex (§12.5.6.7). Persisted.
  PdfLineEnding get lineStartEnding => preferences.lineStartEnding;

  set lineStartEnding(PdfLineEnding value) =>
      preferences.lineStartEnding = value;

  /// The line ending new /Line and /PolyLine annotations carry at their
  /// end vertex (§12.5.6.7). Persisted.
  PdfLineEnding get lineEndEnding => preferences.lineEndEnding;

  set lineEndEnding(PdfLineEnding value) => preferences.lineEndEnding = value;

  /// The background fill new text boxes get, or null for none (the
  /// default — a bare text box, like before). Persisted.
  Color? get textFillColor => preferences.textFillColor;

  set textFillColor(Color? value) => preferences.textFillColor = value;

  /// The border color new text boxes get, or null for none (the
  /// default). The border is [strokeWidth] points wide. Persisted.
  Color? get textBorderColor => preferences.textBorderColor;

  set textBorderColor(Color? value) => preferences.textBorderColor = value;

  int get _colorValue => preferences.color.toARGB32() & 0xFFFFFF;

  static int? _rgbOf(Color? color) =>
      color == null ? null : color.toARGB32() & 0xFFFFFF;

  /// The author name new annotations carry (/T — shown in
  /// [PdfAnnotationSidebar] and other viewers' comment lists). Null
  /// (the default) leaves them unsigned. Persisted.
  String? get author => preferences.author;

  set author(String? value) => preferences.author = value;

  // ---------------------------------------------------------------------
  // in-place text editing

  bool _editingText = false;

  /// Whether an in-place text editor (the free-text tool's box) is open
  /// on a page. While it is, the viewer releases its keyboard shortcuts —
  /// backspace must delete characters, not the annotation.
  bool get isEditingText => _editingText;

  /// Marks an in-place text editor open/closed. Called by the page
  /// overlay that owns the editor.
  void setEditingText(bool value) {
    if (value == _editingText) return;
    _editingText = value;
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

  /// Disarms the eyedropper and adopts [picked] (forced opaque — alpha is
  /// [opacity]'s job) as the annotation [color].
  void finishColorPick(Color picked) {
    _pickingColor = false;
    preferences.color = Color(0xFF000000 | (picked.toARGB32() & 0xFFFFFF));
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // ink

  final Map<int, List<List<(double, double)>>> _ink = {};
  final Map<int, List<List<double>?>> _inkPressures = {};
  Timer? _inkTimer;

  /// How long after the last stroke the buffer auto-commits as one Ink
  /// annotation — strokes drawn within the window aggregate (dotting an
  /// i, crossing a t), so a multi-stroke drawing still lands as a single
  /// annotation and a single undo step. Null restores fully manual
  /// commits ([finishInk] — the toolbar shows its confirm buttons then).
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

  /// Releases a [beginInkStroke] hold without adding a stroke — the
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
  /// still the revision they landed in — the page overlay keeps painting
  /// them until that revision's raster is on screen, so the drawing
  /// doesn't blink out for the render's duration.
  ({
    PdfDocument document,
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
    if (committed == null || !identical(committed.document, _document)) {
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

  /// Whether touch pointers draw with the ink tool. When false they
  /// scroll and zoom as usual and only stylus (and mouse) input draws —
  /// palm rejection. The viewer turns this off automatically the first
  /// time a stylus (Apple Pencil) touches a page with the ink tool armed,
  /// and the choice is persisted with the other [preferences].
  bool get fingerDrawsInk => preferences.fingerDrawsInk;

  set fingerDrawsInk(bool value) => preferences.fingerDrawsInk = value;

  /// Whether touch input is in play this session: always true on
  /// touch-first platforms (iOS/Android/Fuchsia), and flipped on by the
  /// first touch pointer the viewer or toolbar sees elsewhere (a
  /// touchscreen laptop, say). The stock toolbar hides the finger-draws
  /// toggle until this is true — on a mouse-only desktop the control
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
  /// pointer-down listeners; not persisted — a session without touch
  /// starts clean.
  void noteTouchInput() {
    if (_touchSeen) return;
    _touchSeen = true;
    notifyListeners();
  }

  /// Drawn-but-uncommitted ink strokes on [pageIndex], in page space.
  List<List<(double, double)>> strokesOn(int pageIndex) =>
      List.unmodifiable(_ink[pageIndex] ?? const []);

  /// Per-point normalized pressures paralleling [strokesOn] — null for
  /// strokes drawn without pressure (finger, mouse).
  List<List<double>?> strokePressuresOn(int pageIndex) =>
      List.unmodifiable(_inkPressures[pageIndex] ?? const []);

  bool get hasPendingInk => _ink.values.any((s) => s.isNotEmpty);

  /// Buffers one drawn stroke; the buffer commits on its own after
  /// [inkCommitDelay], or through [finishInk].
  /// [pressures], when given, must hold one 0–1 value per stroke point.
  void addInkStroke(int pageIndex, List<(double, double)> stroke,
      {List<double>? pressures}) {
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
    final committed = apply((editor) {
      strokes.forEach((page, pageStrokes) {
        if (pageStrokes.isNotEmpty) {
          editor.addInk(page, pageStrokes,
              color: _colorValue,
              strokeWidth: preferences.strokeWidth,
              opacity: preferences.opacity,
              pressures: pressures[page],
              author: author);
        }
      });
    }, pages: strokes.keys);
    if (committed) {
      _committedInk = (
        document: _document,
        strokes: strokes,
        pressures: pressures,
        color: preferences.color
            .withValues(alpha: preferences.opacity.clamp(0.0, 1.0)),
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
    apply((editor) {
      quadsByPage.forEach((page, quads) {
        if (quads.isEmpty) return;
        switch (kind) {
          case PdfMarkupKind.highlight:
            editor.addHighlight(page, quads,
                color: _colorValue,
                opacity: preferences.opacity,
                author: author);
          case PdfMarkupKind.underline:
            editor.addUnderline(page, quads,
                color: _colorValue,
                opacity: preferences.opacity,
                author: author);
          case PdfMarkupKind.strikeOut:
            editor.addStrikeOut(page, quads,
                color: _colorValue,
                opacity: preferences.opacity,
                author: author);
          case PdfMarkupKind.squiggly:
            editor.addSquiggly(page, quads,
                color: _colorValue,
                opacity: preferences.opacity,
                author: author);
        }
      });
    }, pages: quadsByPage.keys);
  }

  void addRectangle(int pageIndex, PdfRect rect) => apply(
      (e) => e.addSquare(pageIndex, rect,
          strokeColor: _colorValue,
          strokeWidth: preferences.strokeWidth,
          opacity: preferences.opacity,
          author: author),
      pages: [pageIndex]);

  void addEllipse(int pageIndex, PdfRect rect) => apply(
      (e) => e.addCircle(pageIndex, rect,
          strokeColor: _colorValue,
          strokeWidth: preferences.strokeWidth,
          opacity: preferences.opacity,
          author: author),
      pages: [pageIndex]);

  /// Adds a line from [start] to [end]. With [arrow] the end carries a
  /// closed arrowhead (the dedicated arrow tool); otherwise the start and
  /// end endings come from the persisted [PdfEditingPreferences]
  /// ([lineStartEnding] / [lineEndEnding]).
  void addLine(int pageIndex, (double, double) start, (double, double) end,
          {bool arrow = false}) =>
      apply(
          (e) => e.addLine(pageIndex, start, end,
              strokeColor: _colorValue,
              strokeWidth: preferences.strokeWidth,
              opacity: preferences.opacity,
              dashed: preferences.dashedStroke,
              startEnding:
                  arrow ? PdfLineEnding.none : preferences.lineStartEnding,
              endEnding: arrow
                  ? PdfLineEnding.closedArrow
                  : preferences.lineEndEnding,
              author: author),
          pages: [pageIndex]);

  void addPolyLine(int pageIndex, List<(double, double)> points) => apply(
      (e) => e.addPolyLine(pageIndex, points,
          strokeColor: _colorValue,
          strokeWidth: preferences.strokeWidth,
          opacity: preferences.opacity,
          dashed: preferences.dashedStroke,
          startEnding: preferences.lineStartEnding,
          endEnding: preferences.lineEndEnding,
          author: author),
      pages: [pageIndex]);

  void addPolygon(int pageIndex, List<(double, double)> points) => apply(
      (e) => e.addPolygon(pageIndex, points,
          strokeColor: _colorValue,
          strokeWidth: preferences.strokeWidth,
          opacity: preferences.opacity,
          dashed: preferences.dashedStroke,
          author: author),
      pages: [pageIndex]);

  // ---------------------------------------------------------------------
  // measurements (§12.9)

  /// The active measurement calibration the measure tools stamp onto new
  /// annotations, or null until [calibrateScale] (or setting
  /// [measurementScale]) provides one. Persisted with the other
  /// [preferences].
  PdfMeasurementScale? get measurementScale => preferences.measurementScale;

  set measurementScale(PdfMeasurementScale? value) =>
      preferences.measurementScale = value;

  /// Whether a measurement tool can place an annotation right now — i.e. a
  /// scale has been calibrated.
  bool get hasMeasurementScale => preferences.measurementScale != null;

  /// Calibrates [measurementScale] from a reference segment between
  /// [start] and [end] (page-space points) that represents [realLength]
  /// [unitLabel]s. The classic "two-point calibration" flow.
  void calibrateScale(
    (double, double) start,
    (double, double) end,
    double realLength,
    String unitLabel, {
    String? areaUnitLabel,
    int precision = 100,
  }) {
    final dx = end.$1 - start.$1;
    final dy = end.$2 - start.$2;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length <= 0 || realLength <= 0) return;
    measurementScale = PdfMeasurementScale.fromReference(
      pointLength: length,
      realLength: realLength,
      unitLabel: unitLabel,
      areaUnitLabel: areaUnitLabel,
      precision: precision,
    );
  }

  /// The live distance readout for a segment from [start] to [end]
  /// (page-space points), or null without a scale.
  String? measuredDistance((double, double) start, (double, double) end) {
    final scale = measurementScale;
    if (scale == null) return null;
    final dx = end.$1 - start.$1;
    final dy = end.$2 - start.$2;
    return scale.toMeasure().formatDistance(math.sqrt(dx * dx + dy * dy));
  }

  /// The live perimeter readout (sum of segment lengths) for a page-space
  /// polyline through [points], or null without a scale.
  String? measuredPerimeter(List<(double, double)> points) {
    final scale = measurementScale;
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
    final scale = measurementScale;
    if (scale == null || points.length < 3) return null;
    return scale.toMeasure().formatArea(pdfShoelaceArea(points));
  }

  /// Adds a measurement annotation of [kind] through [points] using the
  /// active [measurementScale]. A no-op without a scale.
  void addMeasurement(
      int pageIndex, PdfMeasurementKind kind, List<(double, double)> points) {
    final scale = measurementScale;
    if (scale == null) return;
    apply(
      (e) => e.addMeasurement(pageIndex, kind, points,
          measure: scale.toMeasure(),
          strokeColor: _colorValue,
          strokeWidth: preferences.strokeWidth,
          opacity: preferences.opacity,
          dashed: preferences.dashedStroke,
          author: author),
      pages: [pageIndex],
    );
  }

  void addFreeText(int pageIndex, PdfRect rect, String text) => apply(
      (e) => e.addFreeText(pageIndex, rect, text,
          fontSize: preferences.fontSize,
          font: preferences.fontFamily,
          color: _colorValue,
          fillColor: _rgbOf(preferences.textFillColor),
          borderColor: _rgbOf(preferences.textBorderColor),
          borderWidth: preferences.strokeWidth,
          author: author),
      pages: [pageIndex]);

  void addStamp(int pageIndex, PdfRect rect, String text, {int? color}) =>
      apply(
          (e) => e.addStamp(pageIndex, rect, text,
              color: color ?? _colorValue,
              opacity: preferences.opacity,
              author: author),
          pages: [pageIndex]);

  /// Adds a sticky note with its top-left corner at ([x], [y]).
  void addNote(int pageIndex, double x, double y, String text) => apply(
      (e) =>
          e.addNote(pageIndex, x, y, text, color: _colorValue, author: author),
      pages: [pageIndex]);

  // ---------------------------------------------------------------------
  // signature

  /// The saved hand-drawn signature the signature tool stamps. Persisted
  /// with the other [preferences], so it survives app restarts. Drawn in
  /// [showPdfSignatureDialog].
  PdfInkSignature? get signature => preferences.signature;

  set signature(PdfInkSignature? value) => preferences.signature = value;

  /// The layout [placeSignature] would commit for a tap at ([x], [y]):
  /// the page-space strokes, pressures, ink color, and stroke width —
  /// what the signature tool's live preview paints under the pointer.
  /// Null when no signature is saved.
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
            for (final (nx, ny) in stroke) (left + nx * w, top - ny * h)
          ]
      ],
      pressures: signature.pressures,
      color: signature.color,
      strokeWidth: w / 75, // pen-like: ~2pt at the default width
    );
  }

  /// Stamps [signature] as an Ink annotation centered on ([x], [y]) in
  /// page space, [width] points wide (clamped, with the center, so the
  /// whole signature stays on the page). Keeps the signature's own ink
  /// color and pen pressures. Returns false when none is saved.
  bool placeSignature(int pageIndex, double x, double y, {double width = 160}) {
    final placement = signaturePlacement(pageIndex, x, y, width: width);
    if (placement == null) return false;
    return apply(
        (e) => e.addInk(pageIndex, placement.strokes,
            color: placement.color,
            strokeWidth: placement.strokeWidth,
            opacity: 1,
            pressures: placement.pressures,
            author: author),
        pages: [pageIndex]);
  }

  // ---------------------------------------------------------------------
  // custom stamps

  /// The user's saved custom stamps. Persisted with the other
  /// [preferences], so they survive app restarts. Created in
  /// [showPdfStampEditor] (usually via the picker, [showPdfStampPicker]).
  List<PdfCustomStamp> get customStamps => preferences.customStamps;

  /// Appends [stamp] to the saved list.
  void saveCustomStamp(PdfCustomStamp stamp) =>
      preferences.customStamps = [...preferences.customStamps, stamp];

  /// Removes [stamp] from the saved list. If it was the active stamp,
  /// the stamp tool falls back to prompting for text.
  void removeCustomStamp(PdfCustomStamp stamp) {
    preferences.customStamps = [
      for (final saved in preferences.customStamps)
        if (saved != stamp) saved
    ];
    if (_activeStamp == stamp) {
      _activeStamp = null;
      notifyListeners();
    }
  }

  PdfCustomStamp? _activeStamp;

  /// The custom stamp the stamp tool places on tap. Null means the
  /// classic flow: drag out a box and type the caption. Not persisted —
  /// each session starts in the classic flow.
  PdfCustomStamp? get activeStamp => _activeStamp;

  set activeStamp(PdfCustomStamp? value) {
    if (value == _activeStamp) return;
    _activeStamp = value;
    notifyListeners();
  }

  /// Places [activeStamp] centered on ([x], [y]) in page space,
  /// [height] points tall and auto-sized from its caption (clamped,
  /// with the center, so the whole stamp stays on the page). Returns
  /// false when no stamp is active.
  bool placeStamp(int pageIndex, double x, double y, {double height = 40}) {
    final stamp = _activeStamp;
    if (stamp == null) return false;
    final box = _page(pageIndex).cropBox;
    final h = height.clamp(8.0, box.height * 0.9);
    // mirror addStamp's appearance math (6pt padding, text 72% of the
    // height) so the caption fills the box without shrinking
    final fontSize = (h - 12) * 0.72;
    final w = (measureHelvetica(stamp.text, fontSize, bold: true) + 24)
        .clamp(h, box.width * 0.9);
    final cx = x.clamp(box.left + w / 2, box.right - w / 2);
    final cy = y.clamp(box.bottom + h / 2, box.top - h / 2);
    return apply(
        (e) => e.addStamp(pageIndex,
            PdfRect(cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2), stamp.text,
            color: stamp.color, opacity: preferences.opacity, author: author),
        pages: [pageIndex]);
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

  /// Moves the page at [from] so it ends up at index [to]. Structural
  /// page edits shift page indices, so the annotation selection (a
  /// page-indexed slot) is cleared first.
  void movePage(int from, int to) {
    if (from == to) return;
    _selected.clear();
    apply((e) => e.movePage(from, to));
  }

  /// Removes the page at [index]. Refused (a no-op) on the last page —
  /// a document must keep at least one.
  void removePage(int index) {
    if (_document.pageCount <= 1) return;
    _selected.clear();
    apply((e) => e.removePage(index));
  }

  // ---------------------------------------------------------------------
  // selection

  /// Annotation subtypes the select tool ignores: popups belong to their
  /// parent, links and widgets are interactive objects with their own
  /// semantics (widgets are form fields — moving one breaks its field).
  static const _unselectable = {'Popup', 'Link', 'Widget'};

  /// Subtypes whose geometry is defined by /Rect (plus point arrays the
  /// editor rescales), so resizing keeps them consistent everywhere.
  static const _resizable = {
    'Square',
    'Circle',
    'FreeText',
    'Stamp',
    'Ink',
    'Line',
    'PolyLine',
    'Polygon',
  };

  /// Subtypes whose text the controller can rewrite in place.
  static const _textEditable = {'FreeText', 'Stamp', 'Text'};

  PdfAnnotationEditPredicate? _canEditAnnotation;

  /// Host veto over which annotations the editing UI may change.
  ///
  /// Consulted (alongside the document's own /F ReadOnly and Locked
  /// flags) by every mutating path: hit-test selection, the marquee,
  /// ⌘A, the sidebar's select, delete, and the eraser. An annotation
  /// the predicate rejects still renders, lists, zooms-to, and flashes —
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

  /// Selected (page, /Annots slot) pairs in selection order; the last
  /// one is the primary selection (the one handles and text edits act
  /// on when exactly one is selected).
  final List<(int page, int index)> _selected = [];

  /// Pages cached per revision: [PdfDocument.page] rebuilds the page
  /// (and its lazily parsed annotation list) on every call, and the
  /// selection hit tests run per pointer event.
  final Map<int, PdfPage> _pageCache = {};

  PdfPage _page(int index) =>
      _pageCache.putIfAbsent(index, () => _document.page(index));

  /// The page at [index], cached for the current revision.
  /// [PdfDocument.page] re-walks the page tree and re-parses /Annots on
  /// every call — UI that reads pages per frame (sidebars, hit tests)
  /// should come through here.
  PdfPage pageAt(int index) => _page(index);

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
  bool get canResizeSelected =>
      _selected.length == 1 && _resizable.contains(selectedAnnotation?.subtype);

  /// Rotation rides the appearance stream's /Matrix, so it needs one.
  bool get canRotateSelected =>
      _selected.length == 1 &&
      _resizable.contains(selectedAnnotation?.subtype) &&
      selectedAnnotation?.normalAppearance != null;

  bool get canEditSelectedText =>
      _selected.length == 1 &&
      _textEditable.contains(selectedAnnotation?.subtype) &&
      selectedAnnotation?.isLockedContents != true;

  /// The topmost selectable annotation under ([x], [y]) on [pageIndex],
  /// with its /Annots slot — the select tool's hit test (later entries
  /// draw on top, so they win).
  (int index, PdfAnnotation)? selectableAnnotationAt(
      int pageIndex, double x, double y) {
    final annotations = _page(pageIndex).annotations;
    for (var i = annotations.length - 1; i >= 0; i--) {
      final annotation = annotations[i];
      if (annotation.isHidden ||
          _unselectable.contains(annotation.subtype) ||
          !isAnnotationEditable(annotation)) {
        continue;
      }
      if (annotation.rect.contains(x, y)) return (i, annotation);
    }
    return null;
  }

  /// The topmost Ink annotation whose strokes pass within [tolerance]
  /// page units of ([x], [y]) on [pageIndex], with its /Annots slot —
  /// the eraser's hit test. Precise: the point must be near the inked
  /// centerline (padded by half the pen width), not merely inside the
  /// bounding rect, so crossing strokes don't erase together. An Ink
  /// annotation without a usable /InkList falls back to its rect.
  (int index, PdfAnnotation)? inkAnnotationAt(int pageIndex, double x, double y,
      {double tolerance = 4}) {
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
      double x, double y, (double, double) a, (double, double) b) {
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
  bool selectAnnotationAt(int pageIndex, double x, double y,
      {bool toggle = false}) {
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
  /// intersects [rect] (page space) — the select tool's rubber band.
  /// With [add] the hits join the existing selection instead of
  /// replacing it. Returns how many annotations the band hit.
  int selectAnnotationsIn(int pageIndex, PdfRect rect, {bool add = false}) {
    final annotations = _page(pageIndex).annotations;
    final hits = <(int, int)>[];
    for (var i = 0; i < annotations.length; i++) {
      final annotation = annotations[i];
      if (annotation.isHidden ||
          _unselectable.contains(annotation.subtype) ||
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
        if (!add || !_selected.contains(hit)) hit
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
        PdfRect(
            box.left - 1e6, box.bottom - 1e6, box.right + 1e6, box.top + 1e6));
  }

  /// Selects the annotation in slot [index] of [pageIndex]'s /Annots
  /// (the position in [PdfPage.annotations]), arming the select tool so
  /// the viewer shows the selection. Used by the annotation sidebar.
  /// Returns false for invalid slots, unselectable subtypes, and
  /// annotations the host or /F flags lock ([isAnnotationEditable]).
  bool selectAnnotation(int pageIndex, int index) {
    final annotation = _annotationAt((pageIndex, index));
    if (annotation == null ||
        _unselectable.contains(annotation.subtype) ||
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
    apply((e) => e.removeAnnotation(pageIndex, annotation), pages: [pageIndex]);
  }

  /// Removes several annotations — (pageIndex, /Annots slot) pairs — in
  /// one revision, so a single undo restores them all. Invalid slots are
  /// skipped. Used by the annotation sidebar's multi-select delete.
  void deleteAnnotations(Iterable<(int page, int index)> slots) {
    // resolve every slot before the first removal shifts the others
    final targets = <(int, PdfAnnotation)>[
      for (final slot in slots)
        if (_annotationAt(slot) case final annotation?
            when isAnnotationEditable(annotation))
          (slot.$1, annotation)
    ];
    if (targets.isEmpty) return;
    // surviving annotations may land in different slots
    _selected.clear();
    apply((e) {
      for (final (page, annotation) in targets) {
        e.removeAnnotation(page, annotation);
      }
    }, pages: [for (final (page, _) in targets) page]);
  }

  /// Erases along [path] (page space) with the circle eraser: every
  /// ink annotation on [pageIndex] is sliced where the swept circle of
  /// [eraserRadius] crosses its strokes — strokes split, the rest
  /// survives — in one revision, so a single undo restores the whole
  /// swipe. Ink annotations without a usable /InkList can't be sliced
  /// and are deleted whole when the path reaches their rect. Returns
  /// whether anything changed.
  bool sliceErase(int pageIndex, List<(double, double)> path) {
    if (path.isEmpty) return false;
    final radius = eraserRadius;
    // resolve every target up front: removals shift /Annots slots, but
    // the editor works by dictionary identity
    final targets = [
      for (final annotation in _page(pageIndex).annotations)
        if (annotation.subtype == 'Ink' &&
            !annotation.isHidden &&
            isAnnotationEditable(annotation))
          annotation
    ];
    if (targets.isEmpty) return false;
    return apply((editor) {
      var changed = false;
      for (final annotation in targets) {
        if (annotation.inkList == null) {
          // no centerline to slice — the rect is all we have
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
    }, pages: [pageIndex]);
  }

  static bool _pathTouchesRect(
      List<(double, double)> path, PdfRect rect, double radius) {
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
  /// (the end of /Annots — later entries paint on top), preserving their
  /// relative order. One revision, one undo; the selection follows the
  /// annotations to their new slots.
  void bringSelectedToFront() => _reorderSelected(toFront: true);

  /// Moves the selected annotations behind everything else on their
  /// pages (the start of /Annots).
  void sendSelectedToBack() => _reorderSelected(toFront: false);

  /// Simulates the /Annots reorder slot-by-slot: unmoved entries keep
  /// their relative order, the moved block lands at the top or bottom —
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
          if (!moving.contains(i)) i
      ];
      final block = [
        for (var i = 0; i < count; i++)
          if (moving.contains(i)) i
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
    return _reorderRemap(toFront: toFront)
        .entries
        .any((entry) => entry.key != entry.value);
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
    apply((e) {
      for (final MapEntry(key: page, value: annotations) in byPage.entries) {
        toFront
            ? e.bringAnnotationsToFront(page, annotations)
            : e.sendAnnotationsToBack(page, annotations);
      }
    }, pages: byPage.keys);
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

  /// Pastes since the clipboard was last filled — each one cascades the
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
      final snapshot = PdfAnnotationSnapshot.capture(_document, annotation);
      if (snapshot != null) snapshots.add(snapshot);
    }
    if (snapshots.isEmpty) return 0;
    _clipboard = snapshots;
    _clipboardSourcePage = _selected.last.$1;
    _pasteCount = 0;
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
  /// annotations (one revision — one undo removes them all).
  ///
  /// With [at] the group centers on that page point (the context menu
  /// pastes where the right-click landed). Without it the group keeps
  /// its position, shifted 12pt down-right per repeat paste — and per
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
    final pasted = apply((e) {
      for (final snapshot in _clipboard) {
        e.pasteAnnotation(pageIndex, snapshot, dx: dx, dy: dy);
      }
    }, pages: [pageIndex]);
    if (!pasted) return false;
    _pasteCount++;
    // pasted entries appended to /Annots — select them, like any editor
    tool = PdfEditTool.select;
    final total = _page(pageIndex).annotations.length;
    _selected
      ..clear()
      ..addAll([for (var i = total - count; i < total; i++) (pageIndex, i)]);
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
        return annotation != null && pdfCanRestyleAnnotation(annotation);
      });

  /// The primary selected annotation's current style, for style controls
  /// to display: its main color (the text color for free text), border
  /// width (null for subtypes without one), and baked-in opacity. Null
  /// without a selection.
  ({Color color, double? strokeWidth, double opacity})?
      get selectedAnnotationStyle {
    final annotation = selectedAnnotation;
    if (annotation == null) return null;
    final rgb = annotation.subtype == 'FreeText'
        ? annotation.freeTextStyle?.color ?? annotation.color
        : annotation.color;
    return (
      color: Color(0xFF000000 | (rgb ?? 0)),
      strokeWidth: annotation.borderWidth,
      opacity: annotation.appearanceOpacity,
    );
  }

  /// Restyles every selected annotation in place — one revision, one
  /// undo, and the selection survives (annotations keep their /Annots
  /// slots). Parameters follow [PdfEditor.restyleAnnotation]: [color]
  /// is the stroke/tint (free text's *text* color), [fill] the shape
  /// interior or text-box background (`(null,)` clears it), and
  /// parameters a subtype doesn't have are ignored for it. Returns
  /// whether anything changed.
  bool restyleSelected(
      {Color? color, (Color?,)? fill, double? strokeWidth, double? opacity}) {
    if (color == null &&
        fill == null &&
        strokeWidth == null &&
        opacity == null) {
      return false;
    }
    if (!canRestyleSelected) return false;
    final targets = <(int, PdfAnnotation)>[
      for (final slot in _selected)
        if (_annotationAt(slot) case final annotation?) (slot.$1, annotation)
    ];
    if (targets.isEmpty) return false;
    return apply((e) {
      for (final (page, annotation) in targets) {
        e.restyleAnnotation(page, annotation,
            color: _rgbOf(color),
            fillColor: fill == null ? null : (_rgbOf(fill.$1),),
            strokeWidth: strokeWidth,
            opacity: opacity);
      }
    }, pages: [for (final (page, _) in targets) page]);
  }

  // ---------------------------------------------------------------------
  // attention flash

  ({PdfDocument document, int page, int slot})? _flash;
  int _flashSequence = 0;
  Timer? _flashTimer;

  /// How long a [flashAnnotation] pulse stays pending before it expires
  /// on its own (the overlay's animation is shorter).
  static const flashLifetime = Duration(milliseconds: 1600);

  /// Fires a brief attention pulse around the annotation in slot
  /// [index] of [pageIndex]'s /Annots — the page overlay animates it.
  /// The annotation sidebar calls this when a tile zooms the viewer to
  /// its annotation, so the eye lands on the right spot.
  void flashAnnotation(int pageIndex, int index) {
    if (annotationAt(pageIndex, index) == null) return;
    _flash = (document: _document, page: pageIndex, slot: index);
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
    if (flash == null || !identical(flash.document, _document)) return null;
    return (page: flash.page, slot: flash.slot, sequence: _flashSequence);
  }

  /// Clears [pendingFlash] once its pulse has run — the page overlay
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
        if (_annotationAt(slot) case final annotation?) (slot.$1, annotation)
    ];
    if (targets.isEmpty) return;
    apply((e) {
      for (final (page, annotation) in targets) {
        e.moveAnnotation(page, annotation, dx, dy);
      }
    }, pages: [for (final (page, _) in targets) page]);
  }

  /// Resizes the selected annotation so its /Rect becomes [to].
  ///
  /// [flipX]/[flipY] mirror the artwork — what a resize handle dragged
  /// past the opposite edge produces.
  void resizeSelected(PdfRect to, {bool flipX = false, bool flipY = false}) {
    final annotation = selectedAnnotation;
    if (annotation == null || !canResizeSelected) return;
    if (to.width < 1 || to.height < 1) return;
    apply(
        (e) => e.resizeAnnotation(_selected.last.$1, annotation, to,
            flipX: flipX, flipY: flipY),
        pages: [_selected.last.$1]);
  }

  /// Resizes the selected annotation in its own (unrotated) frame:
  /// [localTo] rotated by the annotation's resting angle about its
  /// center is where the artwork lands — how the overlay resizes a
  /// rotated selection without shearing it.
  ///
  /// [flipX]/[flipY] mirror the artwork along the local axes.
  void resizeSelectedLocal(PdfRect localTo,
      {bool flipX = false, bool flipY = false}) {
    final annotation = selectedAnnotation;
    if (annotation == null || !canResizeSelected) return;
    if (localTo.width < 1 || localTo.height < 1) return;
    apply(
        (e) => e.resizeAnnotationLocal(_selected.last.$1, annotation, localTo,
            flipX: flipX, flipY: flipY),
        pages: [_selected.last.$1]);
  }

  /// Replaces the defining vertices of the selected Line, PolyLine, or
  /// Polygon annotation. The selection keeps its /Annots slot.
  void reshapeSelectedLine(List<(double, double)> points) {
    final annotation = selectedAnnotation;
    if (annotation == null ||
        annotation.subtype != 'Line' &&
            annotation.subtype != 'PolyLine' &&
            annotation.subtype != 'Polygon') {
      return;
    }
    apply((e) => e.reshapeLineAnnotation(_selected.last.$1, annotation, points),
        pages: [_selected.last.$1]);
  }

  /// Whether the single selected annotation is a /Line or /PolyLine whose
  /// endings can be set ([setSelectedLineEndings]).
  bool get canSetLineEndings {
    final annotation = selectedAnnotation;
    return _selected.length == 1 &&
        annotation != null &&
        (annotation.subtype == 'Line' || annotation.subtype == 'PolyLine') &&
        annotation.normalAppearance != null;
  }

  /// The start/end line endings of the selected /Line or /PolyLine, or
  /// null when no such single annotation is selected — for the ending
  /// picker to show.
  (PdfLineEnding, PdfLineEnding)? get selectedLineEndings {
    final annotation = selectedAnnotation;
    if (annotation == null || _selected.length != 1) return null;
    return pdfLineEndings(annotation);
  }

  /// Swaps the start and/or end ending of the selected /Line or
  /// /PolyLine in place — one revision, one undo, and the annotation
  /// keeps its /Annots slot and object number. Pass null for an axis to
  /// leave it unchanged.
  void setSelectedLineEndings(
      {PdfLineEnding? start, PdfLineEnding? end}) {
    final annotation = selectedAnnotation;
    if (annotation == null || !canSetLineEndings) return;
    apply(
        (e) => e.setLineEndings(_selected.last.$1, annotation,
            startEnding: start, endEnding: end),
        pages: [_selected.last.$1]);
  }

  /// Rotates the selected annotation by [degrees] counterclockwise (page
  /// space) about its center. The selection keeps its /Annots slot.
  void rotateSelected(double degrees) {
    final annotation = selectedAnnotation;
    if (annotation == null || !canRotateSelected) return;
    if (degrees.abs() < 0.01) return;
    apply((e) => e.rotateAnnotation(_selected.last.$1, annotation, degrees),
        pages: [_selected.last.$1]);
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
    deleteAnnotations(List.of(_selected));
  }

  /// The selected annotation's text, for pre-filling an edit prompt.
  String? get selectedText => selectedAnnotation?.contents;

  /// Parses a free-text annotation's /DA: the font it was written with
  /// and its size, falling back to the current preferences.
  ({PdfStandardFont font, double size}) _freeTextStyleOf(
      PdfAnnotation annotation) {
    final tf = RegExp(r'/(\S+)\s+(\d+(?:\.\d+)?)\s+Tf')
        .firstMatch(annotation.defaultAppearance ?? '');
    return (
      font: tf == null
          ? preferences.fontFamily
          : PdfStandardFont.fromName(tf.group(1)!),
      size: double.tryParse(tf?.group(2) ?? '') ?? preferences.fontSize,
    );
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

  /// Rewrites the selected free-text annotation with a new [font] and/or
  /// [size], keeping its text, place, color, and author. The selection
  /// survives (the annotation keeps its /Annots slot).
  ///
  /// [fill] and [border] change the box's background and border color:
  /// the single-field record distinguishes "set to this RGB" — including
  /// `(null,)`, removing the fill/border — from an omitted parameter,
  /// which leaves the annotation's own style alone. A border set without
  /// [borderWidth] keeps the annotation's width (or 1pt when it had no
  /// border to keep).
  void restyleSelectedText(
      {PdfStandardFont? font,
      double? size,
      (int?,)? fill,
      (int?,)? border,
      double? borderWidth}) {
    final annotation = selectedAnnotation;
    if (annotation == null || !canRestyleSelectedText) return;
    final style = _freeTextStyleOf(annotation);
    _rewriteSelected(annotation, annotation.contents ?? '',
        font: font ?? style.font,
        size: size ?? style.size,
        fill: fill,
        border: border,
        borderWidth: borderWidth);
  }

  /// Rewrites the selected annotation's text: same place, same style, new
  /// text. Implemented as remove + re-add, which regenerates the
  /// appearance stream.
  void setSelectedText(String text) {
    final annotation = selectedAnnotation;
    if (annotation == null || !canEditSelectedText) return;
    _rewriteSelected(annotation, text);
  }

  /// Sets the (single) selected annotation's /Contents. For subtypes
  /// whose contents are the displayed text (free text, stamps, notes)
  /// this rewrites the annotation so the page matches; for everything
  /// else it's a metadata edit — the comment shown in annotation lists —
  /// and the artwork is untouched. Returns whether anything changed.
  bool setSelectedContents(String text) {
    final annotation = selectedAnnotation;
    if (annotation == null || _selected.length != 1) return false;
    if (annotation.isLockedContents) return false;
    if ((annotation.contents ?? '') == text) return false;
    if (canEditSelectedText) {
      setSelectedText(text);
      return true;
    }
    final page = _selected.last.$1;
    // a tooltip/comment edit changes no page's rendering
    return apply((e) => e.setAnnotationContents(page, annotation, text),
        pages: const <int>[]);
  }

  /// Sets the author (/T) on every selected annotation — one revision,
  /// one undo. Null or empty removes it. Returns whether anything
  /// changed.
  bool setSelectedAuthor(String? author) {
    final value = (author != null && author.isEmpty) ? null : author;
    final targets = <(int, PdfAnnotation)>[
      for (final slot in _selected)
        if (_annotationAt(slot) case final annotation?) (slot.$1, annotation)
    ];
    if (targets.isEmpty) return false;
    if (targets.every((t) => t.$2.author == value)) return false;
    return apply((e) {
      for (final (page, annotation) in targets) {
        e.setAnnotationAuthor(page, annotation, value);
      }
    }, pages: const <int>[]);
  }

  void _rewriteSelected(PdfAnnotation annotation, String text,
      {PdfStandardFont? font,
      double? size,
      (int?,)? fill,
      (int?,)? border,
      double? borderWidth}) {
    if (_selected.isEmpty) return;
    final page = _selected.last.$1;
    final rect = annotation.rect;
    final color = annotation.color;
    final by = annotation.author; // a text edit doesn't change ownership
    final nm = annotation.name; // ... nor identity (sync tracks /NM)
    _selected.clear();
    apply((e) {
      e.removeAnnotation(page, annotation);
      switch (annotation.subtype) {
        case 'FreeText':
          final style = _freeTextStyleOf(annotation);
          // the parsed style carries what /C alone can't: the text color
          // (from /DA) plus any background fill and border; a wrapped
          // [fill]/[border] overrides it (see restyleSelectedText)
          final parsed = annotation.freeTextStyle;
          e.addFreeText(page, rect, text,
              fontSize: size ?? style.size,
              font: font ?? style.font,
              color: parsed?.color ?? color ?? 0x000000,
              fillColor: fill != null ? fill.$1 : parsed?.fillColor,
              borderColor: border != null ? border.$1 : parsed?.borderColor,
              borderWidth: borderWidth ??
                  ((parsed?.borderWidth ?? 0) > 0 ? parsed!.borderWidth : 1),
              author: by,
              name: nm);
        case 'Stamp':
          e.addStamp(page, rect, text,
              color: color ?? 0xC03030, author: by, name: nm);
        default: // 'Text'
          e.addNote(page, rect.left, rect.top, text,
              color: color ?? 0xFFD100, author: by, name: nm);
      }
    }, pages: [page]);
    // the rewritten annotation lands in the last /Annots slot — keep it
    // selected so consecutive restyles (a settings popup) stay anchored
    final annotations = _page(page).annotations;
    if (annotations.isNotEmpty) {
      _selected
        ..clear()
        ..add((page, annotations.length - 1));
      notifyListeners();
    }
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
  }

  /// The content elements of [pageIndex] at the current revision.
  PdfPageElements elementsOn(int pageIndex) => _elements.putIfAbsent(
      pageIndex, () => PdfPageElements.of(_document, pageIndex));

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
    apply((e) => e.deleteElements(elementsOn(selected.$1), [element.id]),
        pages: [selected.$1]);
  }

  /// Rewrites the selected text element's characters to [text] and
  /// returns how many text runs changed.
  ///
  /// Built on [PdfEditor.replaceText], so its limits apply: identical
  /// runs elsewhere on the page change too, composite (Type0) fonts are
  /// skipped, and glyphs are not re-measured — longer replacements can
  /// overlap what follows on the line.
  int replaceSelectedElementText(String text) {
    final selected = _selectedElement;
    final element = selectedElement;
    if (selected == null || element == null || !canEditSelectedElementText) {
      return 0;
    }
    var count = 0;
    apply((e) => count = e.replaceText(selected.$1, element.text!, text),
        pages: [selected.$1]);
    return count;
  }

  // ---------------------------------------------------------------------
  // forms

  PdfAcroForm? _form;
  bool _formResolved = false;

  /// The document's interactive form at the current revision, or null
  /// when it has none. Cached per revision — enumerating fields walks
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
  /// [pageIndex], with the hit widget's index within its field — for a
  /// radio group that index says which button was tapped
  /// ([PdfFormField.widgetOnState]). Null when nothing is hit.
  (PdfFormField field, int widgetIndex)? formFieldAt(
      int pageIndex, double x, double y) {
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

  /// The pages a field's widgets are displayed on, or null when any
  /// widget's page is unknown (then every page's render stamp bumps).
  List<int>? _fieldPages(String name) {
    final field = acroForm?.fieldNamed(name);
    if (field == null) return null;
    final pages = <int>{};
    for (var i = 0; i < field.widgets.length; i++) {
      final page = field.widgetPageIndex(i);
      if (page < 0) return null;
      pages.add(page);
    }
    return pages.toList();
  }

  /// Shared fill plumbing: resolves the field by [name] (fields die with
  /// every revision, so names are the stable handle), guards type and
  /// read-only, and turns editor complaints into a false return — a UI
  /// tap must never crash on a quirky field.
  bool _fillField(String name, Set<PdfFieldType> types,
      void Function(PdfEditor e, PdfFormField f) fill) {
    final field = acroForm?.fieldNamed(name);
    if (field == null || field.isReadOnly || !types.contains(field.type)) {
      return false;
    }
    final pages = _fieldPages(name);
    try {
      return apply((e) {
        final f = e.acroForm?.fieldNamed(name);
        if (f != null) fill(e, f);
      }, pages: pages);
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
        name, const {PdfFieldType.text}, (e, f) => e.setTextValue(f, value));
  }

  /// Toggles the check box [name].
  bool toggleFormCheckBox(String name) => _fillField(
      name,
      const {PdfFieldType.checkBox},
      (e, f) => e.setCheckBoxValue(f, !f.isChecked));

  /// Selects [onState] in the radio group [name] (the tapped widget's
  /// [PdfFormField.widgetOnState]).
  bool setFormRadioValue(String name, String onState) {
    final field = acroForm?.fieldNamed(name);
    if (field != null && field.value == onState) return false;
    return _fillField(name, const {PdfFieldType.radioGroup},
        (e, f) => e.setRadioValue(f, onState));
  }

  /// Sets the choice field [name] to [value] (an export or display
  /// value, per [PdfEditor.setChoiceValue]).
  bool setFormChoiceValue(String name, String value) => _fillField(
      name,
      const {PdfFieldType.comboBox, PdfFieldType.listBox},
      (e, f) => e.setChoiceValue(f, value));

  /// Fills the push button [name] with [imageBytes] (PNG or JPEG),
  /// aspect-fit — signature and logo fields in template pipelines.
  bool setFormButtonImage(String name, Uint8List imageBytes) {
    final PdfEmbeddableImage image;
    try {
      image = PdfEmbeddableImage.decode(imageBytes);
    } catch (_) {
      return false;
    }
    return _fillField(name, const {PdfFieldType.pushButton},
        (e, f) => e.setButtonImage(f, image));
  }

  PdfFormFieldKind _newFormFieldKind = PdfFormFieldKind.text;

  /// The kind of field a form-tool drag on empty page area creates.
  /// Not persisted — each session starts adding text fields.
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
    final added = apply((e) {
      switch (kind) {
        case PdfFormFieldKind.text:
          e.addTextField(pageIndex, name, rect);
        case PdfFormFieldKind.checkBox:
          e.addCheckBoxField(pageIndex, name, rect);
        case PdfFormFieldKind.pushButton:
          e.addPushButtonField(pageIndex, name, rect);
      }
    }, pages: [pageIndex]);
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
      }, pages: const <int>[]);
    } on ArgumentError {
      return false;
    }
  }

  /// Removes the field [name] and its widgets.
  bool removeFormField(String name) {
    if (acroForm?.fieldNamed(name) == null) return false;
    final pages = _fieldPages(name);
    return apply((e) {
      final f = e.acroForm?.fieldNamed(name);
      if (f != null) e.removeField(f);
    }, pages: pages);
  }

  /// Rebuilds the field [name] as [kind] at its first widget's place,
  /// keeping the name ([PdfEditor.changeFieldType]). Returns false when
  /// the field is missing, already that kind, or unrebuildable.
  bool changeFormFieldKind(String name, PdfFormFieldKind kind) {
    if (acroForm?.fieldNamed(name) == null) return false;
    final type = switch (kind) {
      PdfFormFieldKind.text => PdfFieldType.text,
      PdfFormFieldKind.checkBox => PdfFieldType.checkBox,
      PdfFormFieldKind.pushButton => PdfFieldType.pushButton,
    };
    final pages = _fieldPages(name);
    try {
      return apply((e) {
        final f = e.acroForm?.fieldNamed(name);
        if (f != null) e.changeFieldType(f, type);
      }, pages: pages);
    } on ArgumentError {
      return false;
    } on StateError {
      return false;
    }
  }

  /// Flattens the interactive form: bakes every widget's appearance
  /// into its page and removes all fields ([PdfEditor.flattenForm]).
  bool flattenFormFields() => apply((e) => e.flattenForm());
}
