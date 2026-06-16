import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show ValueListenable, kIsWeb, visibleForTesting;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

import 'editing/editing_controller.dart';
import 'editing/editing_form_layer.dart';
import 'editing/editing_menu.dart';
import 'editing/editing_overlay.dart';
import 'editing/text_prompt.dart';
import 'editing/tool_shortcuts.dart';
import 'exact_extent_list.dart';
import 'page_geometry.dart';
import 'perf_log.dart';
import 'pdf_page_view.dart';
import 'preview_cache.dart';
import 'raster_cache.dart';
import 'render_scheduler.dart';
import 'render_worker.dart';
import 'scrollbar.dart';
import 'theme.dart';
import 'viewport.dart';

export 'viewport.dart' show PdfViewport, pdfDocumentKey;

/// One search hit with the text around it, ready for a results list
/// like [PdfSearchResultsPanel].
class PdfSearchResult {
  const PdfSearchResult({
    required this.match,
    required this.prefix,
    required this.matchText,
    required this.suffix,
  });

  final PdfTextMatch match;

  /// Context before the hit on the same line, '… '-led when truncated.
  final String prefix;

  /// The matched text as it appears on the page (original case).
  final String matchText;

  /// Context after the hit on the same line, ' …'-tailed when truncated.
  final String suffix;

  int get pageIndex => match.pageIndex;
}

/// How a document search matches text: case sensitivity, whole-word
/// boundaries, and regular-expression mode. Held by
/// [PdfViewerController.searchOptions]; the search field and results panel
/// expose them as toggle controls.
class PdfSearchOptions {
  const PdfSearchOptions({
    this.matchCase = false,
    this.wholeWord = false,
    this.regex = false,
  });

  /// When true, an upper/lower-case difference fails the match.
  final bool matchCase;

  /// When true, only matches bounded by non-word characters count
  /// (letters, digits, and underscore are word characters).
  final bool wholeWord;

  /// When true, the query is a regular expression rather than literal text.
  /// An invalid pattern simply yields no matches.
  ///
  /// Matching runs synchronously on the calling (UI) thread with no
  /// timeout, so a catastrophically backtracking pattern over a very large
  /// page can briefly stall the frame — acceptable for local desktop use,
  /// but a host exposing this to untrusted input should guard it.
  final bool regex;

  PdfSearchOptions copyWith({bool? matchCase, bool? wholeWord, bool? regex}) =>
      PdfSearchOptions(
        matchCase: matchCase ?? this.matchCase,
        wholeWord: wholeWord ?? this.wholeWord,
        regex: regex ?? this.regex,
      );

  @override
  bool operator ==(Object other) =>
      other is PdfSearchOptions &&
      other.matchCase == matchCase &&
      other.wholeWord == wholeWord &&
      other.regex == regex;

  @override
  int get hashCode => Object.hash(matchCase, wholeWord, regex);
}

/// A snapshot of a viewer's scroll position and zoom, for mirroring one
/// [PdfViewer] onto another — the comparison view's synchronized panes.
/// Read [PdfViewerController.viewSync], hand it to another controller's
/// [PdfViewerController.applyViewSync].
class PdfViewSync {
  const PdfViewSync({
    required this.scrollPixels,
    required this.layoutZoom,
    required this.transform,
  });

  /// Vertical scroll offset, in list pixels at the current [layoutZoom].
  final double scrollPixels;

  /// Zoom applied by laying pages out smaller (≤ fit-width).
  final double layoutZoom;

  /// The InteractiveViewer transform (zoom above fit-width plus pan).
  final Matrix4 transform;
}

/// Drives a [PdfViewer] and reports its state: current page, zoom, and
/// search results. Listeners fire on any change.
class PdfViewerController extends ChangeNotifier {
  _PdfViewerState? _state;

  int _pageCount = 0;
  int _currentPage = 0;
  bool _searching = false;
  String _query = '';
  PdfSearchOptions _searchOptions = const PdfSearchOptions();
  List<PdfSearchResult> _results = const [];
  List<PdfTextMatch> _matches = const [];
  int _currentMatch = -1;

  int get pageCount => _pageCount;

  /// Zero-based index of the page nearest the viewport center.
  int get currentPage => _currentPage;

  /// Current zoom factor (1 = fit width; below 1 the pages lay out
  /// smaller so more of the document is on screen).
  double get zoom => _state?._currentZoom ?? 1;

  bool get isSearching => _searching;
  String get query => _query;
  int get matchCount => _matches.length;

  /// How [search] matches text (case, whole word, regex). Change it with
  /// [setSearchOptions], which re-runs the active search.
  PdfSearchOptions get searchOptions => _searchOptions;

  /// Every hit of the current [query] in document order, with context
  /// snippets — what a search results panel lists.
  List<PdfSearchResult> get searchResults => _results;

  /// Test hook: the attached viewer's low-res preview cache (see
  /// [PdfViewer.pagePreviews]); null when no viewer is attached.
  @visibleForTesting
  PdfPagePreviewCache? get debugPreviewCache => _state?._previews;

  /// Test hook: whether the attached viewer is currently holding page
  /// renders back for a fast scroll; false when no viewer is attached.
  @visibleForTesting
  bool get debugRenderHold => _state?._renderScheduler.holding ?? false;

  String _selectedText = '';

  /// The currently selected text, '' with no selection. Drag with a mouse
  /// (or any pointer the platform doesn't use for scrolling) to select.
  String get selectedText => _selectedText;

  bool get hasSelection => _selectedText.isNotEmpty;

  /// Copies the current selection to the system clipboard. Also bound to
  /// Cmd/Ctrl+C while the viewer has focus.
  Future<void> copySelection() async {
    if (_selectedText.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _selectedText));
  }

  void clearSelection() => _state?._clearSelection();

  /// Pages the current selection touches, in document order; empty
  /// without a selection.
  List<int> get selectionPages {
    final range = _state?._selRange;
    if (range == null) return const [];
    return [for (var i = range.$1.$1; i <= range.$2.$1; i++) i];
  }

  /// The selection's rectangles on [pageIndex], in PDF page coordinates —
  /// ready to use as the quads of a text-markup annotation.
  List<PdfRect> selectionRectsOn(int pageIndex) =>
      _state?._selectionRectsOn(pageIndex) ?? const [];

  void _setSelection(String text) {
    if (text == _selectedText) return;
    _selectedText = text;
    _notifySafely();
  }

  /// Zero-based index into the matches, or -1 with no active match.
  int get currentMatch => _currentMatch;

  Future<void> jumpToPage(int index) async => _state?._jumpToPage(index);

  /// Scrolls — and zooms in when that helps — so [rect] (page space on
  /// [pageIndex]) sits centered in the viewport, filling around 40% of
  /// it. Never zooms out below 100% or in past [PdfViewer.maxZoom]. The
  /// annotation sidebar uses this to zoom to an annotation.
  Future<void> showRect(int pageIndex, PdfRect rect) async =>
      _state?._showRect(pageIndex, rect);

  /// The current scroll position and zoom, as a resolution-independent
  /// snapshot — what to persist so reopening the same document lands the
  /// user where they left off. Null while no viewer is attached or it has
  /// not laid out yet. Restore it with [restoreViewport] or
  /// [PdfViewer.initialViewport].
  PdfViewport? captureViewport() => _state?._captureViewport();

  /// Scrolls and zooms to a [captureViewport] snapshot. A no-op while no
  /// viewer is attached; it applies once the viewer has laid out.
  void restoreViewport(PdfViewport viewport) =>
      _state?._restoreViewport(viewport);

  final _viewport = _ViewportNotifier();

  /// Notifies whenever the visible region changes — scrolling, zooming.
  /// The controller itself stays quiet during scrolling (it only notifies
  /// when [currentPage] flips), so listen to this to track
  /// [visiblePageRegion], e.g. for a thumbnail strip's viewport indicator.
  Listenable get viewportChanges => _viewport;

  /// The visible part of [pageIndex], as fractions of the page's
  /// displayed area (0–1 both axes, y-down from the page's top-left), or
  /// null while the page is entirely off-screen.
  Rect? visiblePageRegion(int pageIndex) =>
      _state?._visibleFractionOf(pageIndex);

  /// A snapshot of the viewer's scroll position and zoom, for mirroring it
  /// onto another viewer (the comparison view's synchronized panes). Null
  /// when no viewer is attached. Pair with [applyViewSync], and listen to
  /// [viewportChanges] to know when to re-read it.
  PdfViewSync? get viewSync => _state?._captureViewSync();

  /// Mirrors [sync] onto this viewer: matches its scroll offset and zoom.
  /// Geometry-dependent — it assumes both viewers lay their pages out the
  /// same way (the comparison view pairs documents with matching page
  /// geometry). Guard against feedback loops at the call site.
  void applyViewSync(PdfViewSync sync) => _state?._applyViewSync(sync);

  void _bumpViewport() {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (_state != null) _viewport.notify();
      });
    } else {
      _viewport.notify();
    }
  }

  @override
  void dispose() {
    _viewport.dispose();
    super.dispose();
  }

  /// Searches the whole document and jumps to the first hit. Pass [options]
  /// to change how matching works (case, whole word, regex) for this and
  /// subsequent searches; omit it to keep the current [searchOptions].
  Future<void> search(String query, {PdfSearchOptions? options}) async {
    final state = _state;
    if (state == null) return;
    if (options != null) _searchOptions = options;
    final opts = _searchOptions;
    _query = query;
    _results = const [];
    _matches = const [];
    _currentMatch = -1;
    _searching = query.isNotEmpty;
    notifyListeners();
    if (query.isEmpty) return;
    final results = await state._searchAllPages(query, opts);
    // superseded by a newer search (changed query or options)
    if (_query != query || _searchOptions != opts) return;
    _results = results;
    _matches = [for (final result in results) result.match];
    _searching = false;
    _currentMatch = results.isEmpty ? -1 : 0;
    notifyListeners();
    if (_matches.isNotEmpty) state._showMatch(_matches[0]);
  }

  /// Sets the matching [options] and re-runs the current search with them,
  /// landing on the first hit. With no active query it just stores the
  /// options for the next [search].
  void setSearchOptions(PdfSearchOptions options) {
    if (options == _searchOptions) return;
    _searchOptions = options;
    if (_query.isNotEmpty) {
      unawaited(search(_query, options: options));
    } else {
      notifyListeners();
    }
  }

  void nextMatch() => _stepMatch(1);

  void previousMatch() => _stepMatch(-1);

  /// Makes match [index] (into [searchResults]) current and scrolls it
  /// into view — what tapping a results-panel entry does.
  void goToMatch(int index) {
    if (index < 0 || index >= _matches.length) return;
    _currentMatch = index;
    notifyListeners();
    _state?._showMatch(_matches[index]);
  }

  void clearSearch() {
    _query = '';
    _results = const [];
    _matches = const [];
    _currentMatch = -1;
    _searching = false;
    _notifySafely();
  }

  void _stepMatch(int delta) {
    if (_matches.isEmpty) return;
    _currentMatch = (_currentMatch + delta) % _matches.length;
    if (_currentMatch < 0) _currentMatch += _matches.length;
    notifyListeners();
    _state?._showMatch(_matches[_currentMatch]);
  }

  void _setCurrentPage(int page) {
    if (page == _currentPage) return;
    _currentPage = page;
    _notifySafely();
  }

  void _setPageCount(int count) {
    _pageCount = count;
    // survive a same-size document swap (an edit revision) in place
    if (_currentPage >= count) _currentPage = 0;
    _notifySafely();
  }

  /// Viewer-internal updates can land mid-frame (initState/didUpdateWidget
  /// run during build; scroll listeners can fire during layout), when
  /// notifying would mark listening widgets dirty illegally — defer those
  /// to after the frame.
  void _notifySafely() {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (_state != null) notifyListeners();
      });
    } else {
      notifyListeners();
    }
  }

  List<PdfTextMatch> _matchesOn(int pageIndex) => [
        for (final m in _matches)
          if (m.pageIndex == pageIndex) m
      ];
}

/// [ChangeNotifier.notifyListeners] is protected; this is the smallest
/// way to hand out a bare [Listenable] the viewer can fire.
class _ViewportNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

/// How [PdfViewer] zooms the document when it first appears.
enum PdfViewerFit {
  /// Pages fill the viewport width.
  width,

  /// The whole first page fits inside the viewport, like desktop
  /// browser PDF viewers. On viewports narrower than the page's own
  /// aspect ratio this is the same as [width].
  page,
}

/// Signature for [PdfViewer.onAction]: the user activated [annotation]
/// (tapped a link or form button) and the viewer doesn't handle its
/// [action] itself.
typedef PdfActionHandler = void Function(
    PdfAction action, PdfAnnotation annotation);

/// Signature for [PdfViewer.pageOverlayBuilder]: returns widgets stacked
/// over one page. Use [geometry] to convert PDF coordinates to view
/// coordinates, e.g. `Positioned.fromRect(rect: geometry.toViewRect(...))`.
typedef PdfPageOverlayBuilder = List<Widget> Function(
    BuildContext context, int pageIndex, PdfPageGeometry geometry);

/// A scrolling, zoomable PDF viewer.
///
/// Supports pinch zoom, double-tap zoom toggle, page tracking, and document
/// search with highlights. Pages re-rasterize at the settled zoom; past the
/// full-page raster caps a detail patch keeps the visible region sharp.
class PdfViewer extends StatefulWidget {
  const PdfViewer({
    super.key,
    required this.document,
    this.controller,
    this.onAction,
    this.pageOverlayBuilder,
    this.editing,
    this.formController,
    this.editingTextPrompt,
    this.annotationMenuBuilder,
    this.formImagePicker,
    this.imagePicker,
    this.onSnapshot,
    this.pageSpacing = 12,
    this.initialFit = PdfViewerFit.page,
    this.initialViewport,
    this.minZoom = 0.25,
    this.maxZoom = 6,
    this.doubleTapZoom = 2.5,
    this.backgroundColor,
    this.pageColor = const Color(0xFFFFFFFF),
    this.showAnnotations = true,
    this.highlightFormFields = true,
    this.interactiveForms = true,
    this.pagePreviews = true,
    this.previewWindow = 20,
    this.predictStrokes = true,
    this.renderWorker,
    this.rasterCache,
    this.textCache,
    this.documentId,
  });

  final PdfDocument document;

  /// Persistent on-disk preview cache (see [PdfRasterCache]). When set
  /// together with [documentId], page previews are written through to the
  /// backing store as they render and loaded back on a cold open, so a
  /// previously-seen document shows soft content immediately instead of
  /// blank paper. Requires [pagePreviews]; null keeps previews session-only.
  final PdfRasterCache? rasterCache;

  /// Persistent on-disk text cache (see [PdfPageTextCache]). When set with
  /// [documentId], full-document search extraction is read back from the
  /// store on a cold reopen instead of re-walking every page's content
  /// stream. Used only when [editing] is null — an edit session mutates the
  /// page content, so its text is never served from the (content-keyed)
  /// persistent cache, only the per-revision in-memory cache.
  final PdfPageTextCache? textCache;

  /// Stable identity for [document], keying its entries in [rasterCache].
  /// A host that has a file path or URL should pass it; otherwise pass the
  /// [pdfContentKey] of the bytes. Without it the [rasterCache] stays idle
  /// (there is no safe key to store under).
  final String? documentId;

  /// Offloads page interpretation (the content-stream parse + walk, the
  /// dominant render cost) to a background isolate, so heavy pages flying
  /// past during a scroll can't stall frames. Caller-owned and caller-
  /// disposed; it must be started over the same bytes as [document] and is
  /// only correct while [document] doesn't change under it — pass one for a
  /// read-only document, leave it null for an editing session whose bytes
  /// change per revision (it would render stale pages). Image-bearing pages
  /// always render locally. Null and the web fallback keep today's
  /// on-thread behavior.
  final PdfRenderWorker? renderWorker;
  final PdfViewerController? controller;

  /// Called when a tapped link or button carries an action the viewer
  /// doesn't follow itself. /GoTo destinations and the four standard
  /// /Named page actions navigate internally and never reach this; URI,
  /// JavaScript, and everything else is the app's call — the conventional
  /// bridge for PDFs that drive the app is a URI action with a custom
  /// scheme, dispatched here.
  final PdfActionHandler? onAction;

  /// Stacks app widgets over each page, positioned in PDF coordinates via
  /// the provided geometry. Overlays live in the page's transformed space,
  /// so they scroll and zoom with the page; they receive pointer events
  /// before the viewer's own selection and link handling.
  final PdfPageOverlayBuilder? pageOverlayBuilder;

  /// Enables annotation editing: while the controller has a tool armed,
  /// each page grows an editing layer that captures the tool's gestures,
  /// and the viewer binds undo/redo/delete shortcuts.
  ///
  /// The controller owns the document revisions, so [document] must be
  /// `editing.document` — rebuild the viewer when the controller
  /// notifies. Because edits are incremental updates, a swap to the next
  /// revision keeps the scroll position and zoom.
  final PdfEditingController? editing;

  /// Enables interactive form filling without the full editing surface —
  /// for the read-only reader, which lets users fill fields but not move
  /// or delete annotations. The controller owns the document revisions
  /// (filling produces one), so [document] must track its current
  /// revision, the same as [editing]. Ignored when [editing] is set (that
  /// controller drives both) or [interactiveForms] is false.
  final PdfEditingController? formController;

  /// How the editing tools ask for annotation text (free text, notes,
  /// stamps). Defaults to [showPdfTextPrompt], a Material dialog.
  final PdfTextPrompt? editingTextPrompt;

  /// Adds the app's own entries to the annotation context menu (the
  /// right-click menu — z-order and delete come stock). Called when the
  /// menu opens, with the selection it acts on; the custom entries
  /// appear below a divider. Needs [editing] — without a controller
  /// there is no context menu.
  final PdfAnnotationMenuBuilder? annotationMenuBuilder;

  /// How the form tool fills a tapped push-button field with an image
  /// (signature and logo fields) — typically a file picker returning
  /// PNG or JPEG bytes. With none, tapping a push button does nothing.
  final PdfFormImagePicker? formImagePicker;

  /// How the image tool ([PdfEditTool.image]) asks for the picture to
  /// insert — typically a file picker returning PNG or JPEG bytes. With
  /// none, the image tool does nothing.
  final PdfImagePicker? imagePicker;

  /// Receives a region captured by the snapshot tool
  /// ([PdfEditTool.snapshot]) — typically to copy it to the clipboard,
  /// save it, or share it. With none, the snapshot tool does nothing.
  final PdfSnapshotHandler? onSnapshot;

  final double pageSpacing;

  /// The zoom the document opens at: the whole first page visible
  /// (default, like desktop browser viewers) or filling the viewport
  /// width. Re-applied when a swapped-in document has a different page
  /// geometry (a different file — not an edit revision). Ignored when
  /// [initialViewport] is given.
  final PdfViewerFit initialFit;

  /// The scroll position and zoom to open at — a [captureViewport]
  /// snapshot from a previous session, so reopening a document lands
  /// where the user left it. Overrides [initialFit] for the first layout;
  /// null falls back to it.
  final PdfViewport? initialViewport;

  /// Smallest zoom factor; below 1 the page shrinks past fit-width and
  /// floats centered in the viewport.
  final double minZoom;
  final double maxZoom;
  final double doubleTapZoom;

  /// The canvas color around and between the pages. Defaults to a
  /// theme-aware grey: the familiar desktop-viewer slate in light themes
  /// and a deeper shade in dark themes.
  final Color? backgroundColor;

  /// The paper color: the fill pages render their content on. PDF pages
  /// have no background of their own — white is only the convention — so
  /// this can be any color (sepia for reading, a tint to match the app).
  /// Purely a display setting; the document is untouched.
  final Color pageColor;

  /// Whether pages render their annotations (highlights, ink, stamps,
  /// form fields...). False shows the clean underlying pages —
  /// a reading mode for heavily marked-up documents. Display-only: the
  /// document is untouched and the annotations come right back. While
  /// hidden, annotations don't respond to taps either (links included),
  /// and editing tools still work but draw over an unannotated page —
  /// hosts typically disarm editing while hiding.
  final bool showAnnotations;

  /// Washes every visible form-field widget with a translucent tint and
  /// a hairline border, the way desktop PDF editors mark fields — most
  /// fields are otherwise invisible until clicked. Display-only; the
  /// tint comes from [PdfViewerThemeData.formFieldHighlightColor]. Off
  /// automatically while [showAnnotations] is false (the fields aren't
  /// rendered, so boxes would mark nothing).
  final bool highlightFormFields;

  /// Whether form fields can be filled in directly, the way Acrobat,
  /// Chrome, and Preview let you — click a text field and type, tap a
  /// check box or radio button, pick from a drop-down — with no editing
  /// tool to arm. Requires an [editing] controller (filling produces a
  /// revision); active in reading and annotation-selection modes, and
  /// suppressed while a drawing or the form-authoring tool is armed (that
  /// tool owns field creation and the field context menu). Tap targets
  /// cover only the field rects, so the rest of the page still scrolls,
  /// selects text, and follows links. Off automatically while
  /// [showAnnotations] is false. The signature/logo push-button fill runs
  /// [formImagePicker] when one is supplied.
  final bool interactiveForms;

  /// Low-resolution page previews under fast scrolling, the way desktop
  /// editors show them: pages whose full render is deferred (the
  /// fast-scroll hold) paint a small cached raster stretched to page
  /// size instead of blank paper. Previews fall out of full renders for
  /// free as pages are viewed; pages never seen are filled in by a
  /// background prerender (nearest the viewport first, paused while the
  /// user scrolls). Costs one interpreter walk per page over the
  /// session plus up to ~40 MB of preview pixels on very long
  /// documents.
  final bool pagePreviews;

  /// How many pages on each side of the current page the background
  /// prerender ([pagePreviews]) warms. Each preview is a full synchronous
  /// interpreter walk, so on a heavy document warming every page stutters
  /// the UI thread for seconds after open; bounding the proactive warm to
  /// a window around the viewport keeps it focused on pages the user might
  /// fast-scroll to. The window recenters automatically as the user
  /// navigates. Pages outside the window still get a preview for free when
  /// they're scrolled onto screen (their on-screen render feeds the cache).
  /// `<= 0` warms every page (the historical behavior — fine for short
  /// documents where warming everything is cheap).
  final int previewWindow;

  /// Draws a short speculative "lead" ahead of the pen while an ink stroke
  /// is in flight, forward-extrapolated from the recent samples' velocity
  /// and curvature, to mask the input+render latency between the pencil
  /// tip and the painted line the way PencilKit's predicted touches do.
  /// The lead is display-only — it never enters the committed stroke — and
  /// is suppressed when prediction would be unstable (too few samples, a
  /// near-stationary pen, or a sharp direction reversal). Pure geometry, so
  /// it helps every stylus platform; it approximates, but does not equal,
  /// Apple's hardware predictor.
  final bool predictStrokes;

  @override
  State<PdfViewer> createState() => _PdfViewerState();
}

class _PdfViewerState extends State<PdfViewer> with TickerProviderStateMixin {
  late PdfViewerController _controller;
  bool _ownsController = false;

  final _scroll = ScrollController();
  final _transform = TransformationController();

  /// The transform's scale alone, for the editing overlays: chrome
  /// (selection outline, handles) divides by it to stay constant-size on
  /// screen while zoomed. A separate notifier so overlays only rebuild
  /// when the scale actually changes, not on every zoomed pan tick.
  final _transformScale = ValueNotifier<double>(1.0);
  late final AnimationController _zoomAnimator;
  Animation<Matrix4>? _zoomAnimation;
  TapDownDetails? _doubleTapDetails;
  bool _zoomed = false;

  /// Resolution multiplier pages render at; follows the zoom level once it
  /// settles (pinch end, wheel pause, double-tap animation end).
  double _renderScale = 1;
  Timer? _settleTimer;
  Timer? _scrollSettleTimer;
  int _settleGeneration = 0;

  /// Paces every page's first (UI-thread) interpret so no frame runs
  /// more than one — [PdfPageRenderScheduler]. Its [holding] flag stands
  /// in for the old render hold: while the list scrolls faster than
  /// pages can usefully render, not-yet-interpreted pages keep their
  /// preview/placeholder instead of stalling the UI thread mid-fling
  /// (the stall is what made the scrollbar leap on heavy documents).
  /// When scrolling settles, held pages drain one per frame, nearest the
  /// viewport first, rather than all firing in one event-loop turn (the
  /// burst that froze fast scrolling on iPad). Released when the velocity
  /// estimate drops or the scroll-settle timer fires.
  final _renderScheduler = PdfPageRenderScheduler();

  /// (frame timestamp, scroll pixels) samples from the last ~200ms,
  /// at most one per frame, for the velocity estimate behind the
  /// scheduler's hold.
  final List<(Duration, double)> _scrollSamples = [];

  /// Frame timestamp of the first sample in the current scroll burst. The
  /// hold stays up unconditionally for a short window past it (see
  /// [_trackScrollVelocity]) — a flick ramps up, so the windowed velocity
  /// underreads its true speed for the first few frames, and releasing
  /// then would let a heavy page interpret and hitch a fraction of a page
  /// into the scroll.
  Duration _scrollBurstStart = Duration.zero;

  /// Low-res previews painted while a page's full render is pending —
  /// what keeps fast-scrolled pages from being blank (see
  /// [PdfViewer.pagePreviews]).
  final _previews = PdfPagePreviewCache();

  /// Pages the background prerender already tried (by page object
  /// identity), so a page whose render throws can't be retried forever.
  final _previewAttempts = Set<PdfPage>.identity();
  bool _prerendering = false;

  late List<PdfPage> _pages;
  late List<double> _aspects; // height / width, after /Rotate
  final Map<int, PdfPageText> _textCache = {};
  final Map<int, List<PdfAnnotation>> _annotCache = {};
  final Map<int, List<PdfRect>> _fieldRectCache = {};
  double _viewWidth = 0;
  double _viewHeight = 0;

  /// Zoom at or below fit-width, applied by laying the pages out smaller
  /// (so zooming out shows more of the document); zoom above fit-width
  /// lives in the InteractiveViewer transform instead.
  double _layoutZoom = 1;

  /// Whether [PdfViewer.initialFit] has been turned into a layout zoom
  /// yet; that needs the viewport size, so it happens on first layout.
  bool _appliedInitialFit = false;

  /// A viewport waiting to be scrolled/zoomed to once the viewer has laid
  /// out — the saved position from [PdfViewer.initialViewport] on first
  /// run, or a runtime [PdfViewerController.restoreViewport]. Applied (and
  /// cleared) in build, then placed in a post-frame callback once the new
  /// scroll extents exist.
  PdfViewport? _pendingViewport;

  /// The effective zoom the user sees. Transform values near 1 defer to
  /// the layout zoom; mid-gesture sub-1 transforms combine with it.
  double get _currentZoom {
    final t = _transform.value.getMaxScaleOnAxis();
    if (t > 1.01 || t < 0.99) return t * _layoutZoom;
    return _layoutZoom;
  }

  /// Cumulative scale of the trackpad pan-zoom gesture in progress.
  double _trackpadScale = 1;

  /// Tracks the gesture's pan velocity for the fling on lift-off.
  VelocityTracker? _trackpadVelocity;

  /// What the gesture turned out to be — see _onTrackpadPanZoomUpdate.
  _TrackpadIntent _trackpadIntent = _TrackpadIntent.undecided;
  Offset _trackpadPendingPan = Offset.zero;

  /// Carries horizontal momentum after a zoomed trackpad pan lifts off:
  /// sideways overflow lives in the zoom window's translation, which the
  /// scroll position's ballistic simulation can't reach.
  late final AnimationController _panFlinger =
      AnimationController.unbounded(vsync: this)..addListener(_onPanFlingTick);

  /// Carries a touch viewport pan's momentum after lift-off. The editing
  /// overlay's pan path moves the document through [_grabPanBy] instead
  /// of the list's scroll physics, so without this every finger fling
  /// stopped dead the moment it lifted. The controller's value is
  /// elapsed time (see [_FlingClock]); each tick feeds the friction
  /// simulations' deltas back through [_grabPanBy], reusing its extent
  /// clamping and zoom-window spillover.
  late final AnimationController _touchFlinger =
      AnimationController.unbounded(vsync: this)
        ..addListener(_onTouchFlingTick);
  FrictionSimulation? _flingSimX;
  FrictionSimulation? _flingSimY;
  Offset _flingLast = Offset.zero;

  final _focusNode = FocusNode(debugLabel: 'PdfViewer');

  // text selection: (pageIndex, offset into that page's text)
  (int, int)? _selAnchor;
  (int, int)? _selFocus;
  MouseCursor _hoverCursor = MouseCursor.defer;

  /// Ctrl/Cmd held: wheel events bypass the list's scrolling and zoom the
  /// InteractiveViewer instead (the standard ctrl+wheel zoom).
  bool _zoomModifierDown = false;

  // double-click-and-drag selects by whole words. The double-tap
  // recognizer rejects as soon as the pointer moves, so the drag arrives
  // as a plain pan — a raw pointer listener spots that the press was the
  // second click of a double-click.
  Duration? _lastMouseDownStamp;
  Offset? _lastMouseDownLocal;
  bool _wordDrag = false;
  ((int, int), (int, int))? _wordAnchor;

  /// The device kind of the latest pointer down — tap callbacks don't
  /// carry one, and default-mode annotation selection is mouse-only.
  PointerDeviceKind? _lastPointerKind;

  /// The latest pointer location (mouse hover or any pointer-down), in the
  /// viewer's local space — so a keyboard ⌘V pastes the annotation
  /// clipboard at the cursor, like the right-click paste does. Null until
  /// a pointer is seen (touch/keyboard-only paste falls back to cascade).
  Offset? _lastPointerLocal;

  /// A long-press (touch/stylus) word selection is mid-gesture: the
  /// handles and copy chip stay hidden until the finger lifts.
  bool _touchSelecting = false;

  /// A selection handle is being dragged (chip hidden meanwhile).
  bool _handleDragging = false;

  /// The widget inside the zoom transform whose render box maps handle
  /// drags' global positions back into list coordinates.
  final GlobalKey _listSpaceKey = GlobalKey();

  /// A mouse drag that started on empty page area (no text under the
  /// press) grab-pans the document instead of selecting text.
  bool _grabPanning = false;

  /// A Shift+drag in default editing mode (no tool armed, nothing
  /// selected) rubber-bands a marquee selection of annotations — the
  /// same gesture the select tool offers, without arming it. The start
  /// and current points are viewport-local (the selection detector's
  /// own coordinate space, which the zoom transform maps to screen);
  /// [_marqueePage] is the page the drag began on, so the box maps to
  /// one page's user space even if it strays onto a neighbour.
  Offset? _marqueeStart;
  Offset? _marqueeCurrent;
  int? _marqueePage;

  /// A single-selection move drag's floating preview, reported by the
  /// page's editing overlay. The overlay's own layer would clip it behind
  /// the page below once the drag crosses a page boundary, so the viewer
  /// paints it in list space (above the whole list) instead.
  PdfMoveDragPreview? _movePreview;

  /// Set when a raw-pointer gesture (mouse double-click word select) has
  /// consumed the press, so the tap recognizer's late-firing callback for
  /// the same press must not clear it again. Reset on every pointer down.
  bool _suppressTap = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? PdfViewerController();
    _ownsController = widget.controller == null;
    _controller._state = this;
    _pendingViewport = widget.initialViewport;
    _zoomAnimator = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200))
      ..addListener(() {
        final animation = _zoomAnimation;
        if (animation != null) _transform.value = animation.value;
      });
    _loadPages();
    _bindRasterCache();
    _scroll.addListener(_onScroll);
    _scroll.addListener(_onScrollForDetail);
    _transform.addListener(_onTransformChanged);
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
    // on the web the browser's native context menu pops on right-click and
    // pre-empts the viewer's own annotation/text menus — suppress it while
    // a viewer is mounted (ref-counted so multiple viewers cooperate)
    _suppressBrowserContextMenu();
    // Cmd+Tab and friends: the modifier's key-up goes to the other app, so
    // the tracked state would stick. Losing focus clears it.
    _lifecycle = AppLifecycleListener(onInactive: () {
      if (_zoomModifierDown && mounted) {
        setState(() => _zoomModifierDown = false);
      }
    });
    // background preview prerender starts once the first frame (and the
    // scroll metrics the priority order needs) exists
    WidgetsBinding.instance.addPostFrameCallback((_) => _prerenderPreviews());
  }

  late final AppLifecycleListener _lifecycle;

  /// How many mounted viewers have suppressed the browser context menu —
  /// `BrowserContextMenu` is a single global toggle, so several viewers
  /// (or a host that re-enables it) must cooperate. The native menu is
  /// re-enabled only when the last viewer goes away.
  static int _browserContextMenuSuppressors = 0;

  void _suppressBrowserContextMenu() {
    if (!kIsWeb) return;
    if (_browserContextMenuSuppressors++ == 0) {
      BrowserContextMenu.disableContextMenu();
    }
  }

  void _restoreBrowserContextMenu() {
    if (!kIsWeb || _browserContextMenuSuppressors == 0) return;
    if (--_browserContextMenuSuppressors == 0) {
      BrowserContextMenu.enableContextMenu();
    }
  }

  bool _onKeyEvent(KeyEvent event) {
    final down = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (down != _zoomModifierDown && mounted) {
      setState(() => _zoomModifierDown = down);
    }
    return false; // observe only, never consume
  }

  /// Wheel events: the viewer owns zooming, not InteractiveViewer (whose
  /// wheel handler acts directly, outside the signal resolver, so it would
  /// zoom on every wheel-up regardless of modifiers — its scaleFactor is
  /// set to infinity to neutralize it).
  ///
  /// With ctrl/cmd held the list is out of the hit path (IgnorePointer),
  /// this registration wins, and the wheel zooms around the pointer.
  /// Without a modifier the list's own registration wins while it can
  /// scroll; this wins instead at the scroll extents AND whenever the
  /// list refuses wheel events outright — with an editing tool armed its
  /// physics is NeverScrollableScrollPhysics, and on web every trackpad
  /// two-finger pan arrives as a wheel event (no PointerPanZoomEvents
  /// there), so this path must scroll the document itself: vertical
  /// deltas drive the scroll position directly (jumpTo bypasses physics,
  /// like the trackpad and scrollbar paths) and whatever the extents
  /// can't absorb pans the zoom window, horizontal deltas pan the zoom
  /// window.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      final scroll = event as PointerScrollEvent;
      _panFlinger.stop();
      _touchFlinger.stop();
      if (_zoomModifierDown) {
        // not while a draw tool is armed — on the web a trackpad pinch
        // surfaces as a modifier-flagged wheel event, and zooming would
        // disrupt the stroke
        if (!_drawToolArmed) _applyWheelZoom(scroll);
        return;
      }
      final matrix = _transform.value.clone();
      final scale = matrix.getMaxScaleOnAxis();
      final zoomed = scale > 1.01;
      if (zoomed) matrix.storage[12] -= scroll.scrollDelta.dx;
      if (_scroll.hasClients && scroll.scrollDelta.dy != 0) {
        final position = _scroll.position;
        // deltas are screen pixels; the list lives under the zoom transform
        final target = position.pixels + scroll.scrollDelta.dy / scale;
        final clamped =
            target.clamp(position.minScrollExtent, position.maxScrollExtent);
        if (clamped != position.pixels) position.jumpTo(clamped);
        if (zoomed) matrix.storage[13] -= (target - clamped) * scale;
      }
      if (zoomed) _transform.value = _clampedTransform(matrix);
    });
  }

  void _applyWheelZoom(PointerScrollEvent event) {
    if (event.scrollDelta.dy == 0) return;
    // InteractiveViewer's wheel feel: e^(-delta/200)
    _zoomTo(_currentZoom * math.exp(-event.scrollDelta.dy / 200),
        event.localPosition);
  }

  /// Applies an absolute zoom level. Above 1 it lives in the
  /// InteractiveViewer transform (a window over fit-width pages); at or
  /// below 1 the pages themselves lay out smaller, so zooming out shows
  /// more of the document rather than a shrunken viewport.
  void _zoomTo(double target, Offset focal) {
    final zoom = target.clamp(widget.minZoom, widget.maxZoom);
    if (zoom <= 1) {
      if (_transform.value.getMaxScaleOnAxis() > 1) {
        _transform.value = Matrix4.identity();
      }
      _setLayoutZoom(zoom, focalY: focal.dy);
    } else {
      if (_layoutZoom < 1) _setLayoutZoom(1, focalY: focal.dy);
      final matrix = _transform.value.clone();
      final factor = zoom / matrix.getMaxScaleOnAxis();
      matrix
        ..translateByDouble(focal.dx, focal.dy, 0, 1)
        ..scaleByDouble(factor, factor, factor, 1)
        ..translateByDouble(-focal.dx, -focal.dy, 0, 1);
      _transform.value = _clampedTransform(matrix);
    }
  }

  /// Lays the pages out at [zoom] × fit-width (≤ 1), keeping the content
  /// at [focalY] (viewport coordinates) as stationary as the new scroll
  /// extents allow.
  void _setLayoutZoom(double zoom, {double? focalY}) {
    final z = zoom.clamp(widget.minZoom, 1.0);
    if (z == _layoutZoom) return;
    final anchor = focalY ?? _viewHeight / 2;
    final pixels = _scroll.hasClients ? _scroll.position.pixels : 0.0;
    final target = (pixels + anchor) * (z / _layoutZoom) - anchor;
    setState(() => _layoutZoom = z);
    _controller._bumpViewport();
    if (_scroll.hasClients) {
      _scroll.jumpTo(math.max(0, target));
      // the new extents only exist after this frame's layout
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        final position = _scroll.position;
        if (position.pixels > position.maxScrollExtent) {
          position.jumpTo(position.maxScrollExtent);
        }
      });
    }
  }

  /// During a gesture the existing rasters scale under the transform
  /// (cheap, momentarily blurry); once the matrix stops changing for a
  /// beat, visible pages re-rasterize sharp at the new zoom. A matrix
  /// listener (rather than onInteractionEnd) also catches wheel zoom and
  /// the double-tap animation.
  void _onTransformChanged() {
    _transformScale.value = _transform.value.getMaxScaleOnAxis();
    _controller._bumpViewport();
    // hold re-rasterization while the zoom is moving: the existing rasters
    // scale under the transform meanwhile (cheap, briefly blurry). Without
    // this, rapid zoom in/out fired a fresh full-resolution toImage per
    // settle, and on web (single-threaded, uncancellable GPU readback)
    // they piled up and froze the UI. The settle below releases the hold,
    // and the scheduler then drains a single coalesced render per page.
    _renderScheduler.holding = true;
    _settleTimer?.cancel();
    _settleTimer = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      _renderScheduler.holding = false;
      final target = math.max(1.0, _transform.value.getMaxScaleOnAxis());
      // wheel zoom never fires onInteractionEnd, so the pan flag also
      // settles here
      final zoomed = target > 1.01;
      setState(() {
        if (zoomed != _zoomed) _zoomed = zoomed;
        if ((target - _renderScale).abs() > 0.1 * _renderScale) {
          _renderScale = target;
        }
        // any settled transform change moves the deep-zoom detail patch
        _settleGeneration++;
      });
      // the background prerender yields while the hold is up; pick it back up
      _prerenderPreviews();
    });
  }

  /// Debounced scroll-settle: scrolling moves pages under a deep-zoom
  /// detail patch, so the patch must follow once movement stops.
  void _onScrollForDetail() {
    _trackScrollVelocity();
    // the scheduler drains held pages nearest the viewport first
    _renderScheduler.focus = _controller.currentPage;
    _scrollSettleTimer?.cancel();
    _scrollSettleTimer = Timer(const Duration(milliseconds: 250), () {
      _scrollSamples.clear();
      _renderScheduler.holding = false;
      if (mounted) setState(() => _settleGeneration++);
      // the prerender pauses while the user scrolls; pick it back up
      _prerenderPreviews();
    });
  }

  /// Fills [_previews] for pages that have never rendered on screen, one
  /// page at a time, nearest the viewport first. Each page is a
  /// synchronous interpreter walk on the UI thread (the same cost the
  /// page would incur when first viewed), so the loop runs only while
  /// the viewer is idle: it bails between pages whenever a scroll is in
  /// progress, and the scroll-settle timer restarts it.
  Future<void> _prerenderPreviews() async {
    if (_prerendering || !mounted || !widget.pagePreviews) return;
    _prerendering = true;
    try {
      while (mounted && widget.pagePreviews) {
        if (_renderScheduler.holding || (_scrollSettleTimer?.isActive ?? false)) {
          return; // restarted by the settle timer
        }
        if (_renderScheduler.hasPending) {
          // near pages are still draining their full render through the
          // scheduler; don't compete for the UI thread this frame
          await SchedulerBinding.instance.endOfFrame;
          if (!mounted) return;
          continue;
        }
        final pages = _pages;
        final index = _nextPreviewIndex(pages);
        if (index == null) return; // every page covered (or attempted)
        final page = pages[index];
        _previewAttempts.add(page);
        await _previews.renderPreview(index, page,
            pageColor: widget.pageColor,
            annotations: widget.showAnnotations,
            worker: widget.renderWorker);
        if (!mounted) return;
        // breathe between interpreter walks — each is a synchronous
        // UI-thread chunk, so give the engine a frame for input and
        // animations (endOfFrame schedules one when idle; deliberately
        // not a Timer, which would pend in widget tests)
        await SchedulerBinding.instance.endOfFrame;
      }
    } finally {
      _prerendering = false;
    }
  }

  /// The next page worth prerendering: missing a fresh preview, not yet
  /// attempted, and not near the viewport (pages in or around the build
  /// window render fully on their own — their full picture feeds the
  /// cache, so prerendering them too would interpret twice).
  int? _nextPreviewIndex(List<PdfPage> pages) {
    final current =
        pages.isEmpty ? 0 : _controller.currentPage.clamp(0, pages.length - 1);
    final hasMetrics = _scroll.hasClients && _viewWidth > 0;
    // just past the list's 250px cacheExtent: pages inside it build and
    // render fully on their own, pages beyond it are prerender's job
    const nearSlack = 300.0;
    final nearTop = hasMetrics ? _scroll.position.pixels - nearSlack : 0.0;
    final nearBottom = hasMetrics
        ? _scroll.position.pixels +
            _scroll.position.viewportDimension +
            nearSlack
        : double.infinity; // pre-layout: every page counts as near
    int? best;
    var bestDistance = 1 << 30;
    var offset = 0.0;
    for (var i = 0; i < pages.length; i++) {
      final height = _pageHeight(i) + widget.pageSpacing;
      final top = offset;
      offset += height;
      if (top + height >= nearTop && top <= nearBottom) continue;
      final distance = (i - current).abs();
      // bound the proactive warm to a window around the viewport — far
      // pages render on demand on arrival (render hold) and feed the
      // cache for free when scrolled through (putFromPicture)
      final window = widget.previewWindow;
      if (window > 0 && distance > window) continue;
      if (_previewAttempts.contains(pages[i])) continue;
      if (_previews.isFresh(i, pages[i])) continue;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = i;
      }
    }
    return best;
  }

  /// Estimates the scroll velocity over a ~200ms window of per-frame
  /// samples and holds the render scheduler past ~2 viewport-heights/sec.
  /// Frame timestamps (not wall clock) collapse the burst of listener
  /// calls a single wheel tick produces into one sample — an instant
  /// 100px jump must not read as infinite velocity.
  void _trackScrollVelocity() {
    if (!_scroll.hasClients) return;
    final now = WidgetsBinding.instance.currentSystemFrameTimeStamp;
    final pixels = _scroll.position.pixels;
    if (_scrollSamples.isEmpty) {
      // First event of a new scroll burst: there's no time span yet to
      // estimate velocity from, but a heavy page entering the build
      // window THIS frame would run its synchronous interpret walk
      // (100-400ms on CAD pages) and drop the frame. Start the burst and
      // hold (see the opening grace below).
      _scrollBurstStart = now;
      _scrollSamples.add((now, pixels));
      _renderScheduler.holding = true;
      return;
    }
    if (_scrollSamples.last.$1 == now) {
      _scrollSamples.last = (now, pixels);
    } else {
      _scrollSamples.add((now, pixels));
    }
    while (_scrollSamples.length > 2 &&
        now - _scrollSamples.first.$1 > const Duration(milliseconds: 200)) {
      _scrollSamples.removeAt(0);
    }
    final span = (now - _scrollSamples.first.$1).inMicroseconds;
    if (span <= 0) return; // all samples this frame: keep the verdict
    final velocity =
        (pixels - _scrollSamples.first.$2).abs() * 1e6 / span; // px/s
    final viewport = _scroll.position.viewportDimension;
    // A flick ramps up: its first inter-frame deltas underread the
    // gesture's true speed, so a velocity verdict taken in the burst's
    // opening frames reads "slow" and releases the hold right as the
    // scroll accelerates — a heavy page entering then interprets
    // synchronously and drops the frame (the hitch felt a fraction of a
    // page into a fast scroll). Hold unconditionally through the opening
    // window, then govern by the windowed velocity (>~2 viewport-
    // heights/sec). Held pages paint their low-res preview, not blank, so
    // a genuinely slow scroll only shows a brief preview before the grace
    // lapses and the page sharpens; the settle timer clears the burst.
    final opening =
        now - _scrollBurstStart < const Duration(milliseconds: 150);
    final hold = opening || velocity > math.max(800, 2 * viewport);
    PdfPerfLog.log('scroll page=${_controller.currentPage} '
        'v=${velocity.toStringAsFixed(0)}px/s '
        'threshold=${math.max(800, 2 * viewport).toStringAsFixed(0)} '
        'opening=$opening hold=${hold ? 'ON' : 'off'}');
    _renderScheduler.holding = hold;
  }

  @override
  void didUpdateWidget(PdfViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.document, widget.document)) {
      // an edit-induced swap to a revision with the same page geometry
      // keeps the reading position; a genuinely different document resets
      final sameGeometry = _sameGeometryAs(widget.document);
      _textCache.clear();
      _annotCache.clear();
      _fieldRectCache.clear();
      _controller.clearSearch();
      _clearSelection();
      _loadPages();
      // an edit revision keeps its previews (rebound to the new page
      // objects — edited pages refresh from their on-screen render); a
      // different document starts clean
      if (sameGeometry) {
        _previews.rebind(_pages);
      } else {
        _previews.clear();
      }
      // re-point (and, for a different file, re-prime) the persistent
      // preview backing; an edit revision keeps its rebound previews so the
      // prime is a no-op there
      _bindRasterCache(prime: !sameGeometry);
      _previewAttempts.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) => _prerenderPreviews());
      if (!sameGeometry) {
        // didUpdateWidget runs mid-build, and jumpTo synchronously
        // dispatches a ScrollNotification — ancestors listening through a
        // ScrollNotificationObserver (a Material AppBar's scrolled-under
        // state, for one) would setState during build. Reset after the frame.
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
        });
        _transform.value = Matrix4.identity();
        // a different file deserves a fresh fit; an edit revision (same
        // geometry) keeps the zoom the user chose
        _appliedInitialFit = false;
      }
      setState(() {});
    }
    if (oldWidget.pageColor != widget.pageColor ||
        oldWidget.showAnnotations != widget.showAnnotations) {
      // previews bake the paper color and annotation visibility in, so the
      // disk key changes with them too — rebind and re-prime under the new key
      _previews.clear();
      _bindRasterCache();
      _previewAttempts.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) => _prerenderPreviews());
    } else if (!identical(oldWidget.rasterCache, widget.rasterCache) ||
        oldWidget.documentId != widget.documentId) {
      // the host swapped the cache or the document's identity without
      // changing the document object (e.g. a path became known)
      _bindRasterCache();
    }
  }

  /// Whether [document] lays out exactly like the one on screen: same
  /// page count, same aspect ratio per page.
  bool _sameGeometryAs(PdfDocument document) {
    if (document.pageCount != _pages.length) return false;
    for (var i = 0; i < _pages.length; i++) {
      final page = document.page(i);
      final aspect = _isRotatedSideways(page)
          ? page.cropBox.width / math.max(1e-6, page.cropBox.height)
          : page.cropBox.height / math.max(1e-6, page.cropBox.width);
      if ((aspect - _aspects[i]).abs() > 1e-6) return false;
    }
    return true;
  }

  void _loadPages() {
    final count = widget.document.pageCount;
    _pages = [for (var i = 0; i < count; i++) widget.document.page(i)];
    _aspects = [
      for (final page in _pages)
        _isRotatedSideways(page)
            ? page.cropBox.width / math.max(1e-6, page.cropBox.height)
            : page.cropBox.height / math.max(1e-6, page.cropBox.width),
    ];
    _controller._setPageCount(count);
  }

  /// The disk-raster key for the current document under the current paper
  /// color and annotation visibility — those are baked into a preview, so
  /// changing either must not load a mismatched cached raster.
  String? _rasterKey() {
    final id = widget.documentId;
    if (id == null) return null;
    return '$id|${widget.pageColor.toARGB32()}|${widget.showAnnotations}';
  }

  /// Binds (or unbinds) the preview cache's persistent backing to the open
  /// document and, when [prime] is set, loads any previews stored in a
  /// previous session so a cold open paints soft content immediately.
  void _bindRasterCache({bool prime = true}) {
    final raster = widget.rasterCache;
    final key = _rasterKey();
    if (!widget.pagePreviews || raster == null || key == null) {
      _previews.disk = null;
      return;
    }
    _previews.disk = raster.forDocument(key);
    if (!prime) return;
    final pages = _pages;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_previews.loadFromDisk(pages));
    });
  }

  static bool _isRotatedSideways(PdfPage page) =>
      page.rotation == 90 || page.rotation == 270;

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    _restoreBrowserContextMenu();
    _lifecycle.dispose();
    _settleTimer?.cancel();
    _scrollSettleTimer?.cancel();
    // when the host recreates the viewer element (e.g. a panel appearing
    // shifts it to a new slot in a Row), the replacement state attaches in
    // initState BEFORE this deferred dispose runs — only detach if the
    // controller still points here, or the new viewer is severed and every
    // controller call (jumpToPage, visiblePageRegion, search) silently
    // no-ops
    if (identical(_controller._state, this)) _controller._state = null;
    if (_ownsController) _controller.dispose();
    _scroll.dispose();
    _transform.dispose();
    _transformScale.dispose();
    _renderScheduler.dispose();
    _previews.dispose();
    _zoomAnimator.dispose();
    _panFlinger.dispose();
    _touchFlinger.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  double _pageHeight(int index) => _aspects[index] * _viewWidth * _layoutZoom;

  double _pageOffset(int index) {
    var offset = 0.0;
    for (var i = 0; i < index; i++) {
      offset += _pageHeight(i) + widget.pageSpacing;
    }
    return offset;
  }

  /// A page's slot extent in the scroll list, mirroring [itemExtentBuilder]:
  /// the leading [PdfViewer.pageSpacing] belongs to every page but the first.
  double _scrollExtentOf(int index) =>
      _pageHeight(index) + (index == 0 ? 0 : widget.pageSpacing);

  /// The list-space offset at which page [index]'s slot begins.
  double _slotStart(int index) {
    var offset = 0.0;
    for (var i = 0; i < index; i++) {
      offset += _scrollExtentOf(i);
    }
    return offset;
  }

  /// Page heights scale with [_viewWidth] (see [_pageHeight]), so when the
  /// viewport width changes — most visibly while a side panel's resize grip
  /// is dragged — a fixed scroll offset maps to a different page and the
  /// document appears to scroll under the reader. This pins the reading
  /// position: capture the page (and fraction within it) at the viewport top
  /// under the OLD geometry, then re-derive the scroll offset once the new
  /// width has laid out. Called from build while [_viewWidth] still holds the
  /// previous width.
  void _preserveReadingAnchor() {
    final top = _scroll.offset;
    var acc = 0.0;
    var anchorPage = _pages.length - 1;
    var fraction = 0.0;
    for (var i = 0; i < _pages.length; i++) {
      final extent = _scrollExtentOf(i);
      if (top < acc + extent || i == _pages.length - 1) {
        anchorPage = i;
        fraction = extent > 0 ? ((top - acc) / extent).clamp(0.0, 1.0) : 0.0;
        break;
      }
      acc += extent;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients || _viewWidth <= 0) return;
      final target = (_slotStart(anchorPage) +
              fraction * _scrollExtentOf(anchorPage))
          .clamp(0.0, _scroll.position.maxScrollExtent);
      if ((target - _scroll.offset).abs() > 0.5) _scroll.jumpTo(target);
    });
  }

  PdfViewSync _captureViewSync() => PdfViewSync(
        scrollPixels: _scroll.hasClients ? _scroll.position.pixels : 0,
        layoutZoom: _layoutZoom,
        transform: _transform.value.clone(),
      );

  void _applyViewSync(PdfViewSync sync) {
    void applyScrollAndTransform() {
      _transform.value = sync.transform.clone();
      if (_scroll.hasClients) {
        final target =
            sync.scrollPixels.clamp(0.0, _scroll.position.maxScrollExtent);
        if ((target - _scroll.position.pixels).abs() > 0.5) {
          _scroll.jumpTo(target);
        }
      }
    }

    // A layout-zoom change relays the pages out, so the new scroll metrics
    // only exist after the next frame.
    if ((_layoutZoom - sync.layoutZoom).abs() > 1e-6) {
      setState(() => _layoutZoom = sync.layoutZoom);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) applyScrollAndTransform();
      });
    } else {
      applyScrollAndTransform();
    }
  }

  void _onScroll() {
    if (_viewWidth <= 0 || !_scroll.hasClients) return;
    _controller._bumpViewport();
    final center = _scroll.offset + _scroll.position.viewportDimension / 2;
    var offset = 0.0;
    for (var i = 0; i < _pages.length; i++) {
      offset += _pageHeight(i) + widget.pageSpacing;
      if (center < offset) {
        _controller._setCurrentPage(i);
        return;
      }
    }
    _controller._setCurrentPage(_pages.length - 1);
  }

  /// While zoomed in, the screen viewport sees list space starting at
  /// (pixels − t_y)/s (see _visibleFractionOf) — scroll targets must
  /// shift by t_y/s, or every jump lands above where the user looks.
  double get _zoomWindowDy {
    final m = _transform.value;
    return m.storage[13] / m.getMaxScaleOnAxis();
  }

  Future<void> _jumpToPage(int index) async {
    if (!_scroll.hasClients) return;
    final target =
        _pageOffset(index.clamp(0, _pages.length - 1)) + _zoomWindowDy;
    await _scroll.animateTo(
      target.clamp(0.0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  /// A resolution-independent snapshot of where the viewport sits: the
  /// page under its top-left corner, fractional offsets into that page,
  /// and the effective zoom. Null until the viewer has laid out.
  PdfViewport? _captureViewport() {
    if (_viewWidth <= 0 || !_scroll.hasClients || _pages.isEmpty) return null;
    // the InteractiveViewer transform is scale + translation only, so the
    // viewport's top-left unprojects to list space as (p - t) / s (see
    // _visibleFractionOf)
    final m = _transform.value;
    final scale = m.getMaxScaleOnAxis();
    final viewTop = -m.storage[13] / scale + _scroll.position.pixels;
    final viewLeft = -m.storage[12] / scale;
    final pageWidth = _viewWidth * _layoutZoom;
    final pageLeft = (_viewWidth - pageWidth) / 2;
    var top = 0.0;
    for (var i = 0; i < _pages.length; i++) {
      final height = _pageHeight(i);
      if (viewTop < top + height + widget.pageSpacing ||
          i == _pages.length - 1) {
        // fractions are layout-zoom independent: numerator and page size
        // scale together
        return PdfViewport(
          page: i,
          top: height <= 0 ? 0 : (viewTop - top) / height,
          left: pageWidth <= 0 ? 0 : (viewLeft - pageLeft) / pageWidth,
          zoom: _currentZoom,
        );
      }
      top += height + widget.pageSpacing;
    }
    return null;
  }

  /// Scrolls and zooms to [viewport]. Defers to the next layout when the
  /// viewer is not ready yet.
  void _restoreViewport(PdfViewport viewport) {
    if (_viewWidth <= 0 || _viewHeight <= 0 || !_scroll.hasClients) {
      _pendingViewport = viewport;
      // ensure a build runs to consume it — the caller (e.g. the saved
      // viewport arriving after an async preferences load) may fire while
      // the app is otherwise idle, with no frame already scheduled
      if (mounted) setState(() {});
      return;
    }
    if (_pages.isEmpty) return;
    final page = viewport.page.clamp(0, _pages.length - 1);
    final z =
        viewport.zoom <= 1 ? viewport.zoom.clamp(widget.minZoom, 1.0) : 1.0;
    if (z != _layoutZoom) {
      // the new layout's scroll extents exist only after this frame; setState
      // schedules it, the post-frame callback then places the viewport
      setState(() => _layoutZoom = z);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _placeViewport(viewport, page);
      });
    } else {
      // the layout already matches — place now, no frame needed (so an idle
      // app with nothing scheduling frames still restores)
      _placeViewport(viewport, page);
    }
  }

  /// Sets the scroll offset and transform so [viewport]'s top-left sits at
  /// the viewport's top-left. The layout zoom is already in place (set in
  /// build or [_restoreViewport]); this needs the post-layout scroll
  /// extents.
  void _placeViewport(PdfViewport viewport, int page) {
    if (_viewWidth <= 0 || _pages.isEmpty) return;
    final listTop = _pageOffset(page) + viewport.top * _pageHeight(page);
    final maxScroll = _scroll.position.maxScrollExtent;
    if (viewport.zoom <= 1) {
      _transform.value = Matrix4.identity();
      _scroll.jumpTo(listTop.clamp(0.0, maxScroll));
    } else {
      // zoom above fit-width rides the transform over fit-width pages, so
      // the page is the full viewport width here (see _zoomTo)
      final scale = viewport.zoom.clamp(1.0, widget.maxZoom);
      final scroll = listTop.clamp(0.0, maxScroll);
      // solve (p - t) / s = target for the translation, matching the
      // unprojection in _captureViewport / _visibleFractionOf
      final tx = (-scale * viewport.left * _viewWidth)
          .clamp(_viewWidth * (1 - scale), 0.0);
      final ty = (scale * (scroll - listTop))
          .clamp(_viewHeight * (1 - scale), 0.0);
      _transform.value = Matrix4.identity()
        ..translateByDouble(tx, ty, 0, 1)
        ..scaleByDouble(scale, scale, scale, 1);
      _scroll.jumpTo(scroll);
      setState(() => _zoomed = scale > 1.01);
    }
    _controller._bumpViewport();
  }

  /// Frames [rect] (page space on page [index]): centers it in the
  /// viewport and zooms so it fills ~40% of the view, clamped to
  /// [1, maxZoom] — tiny annotations don't explode, big ones don't
  /// force a zoom-out.
  Future<void> _showRect(int index, PdfRect rect) async {
    if (!_scroll.hasClients || _viewWidth <= 0 || _pages.isEmpty) return;
    index = index.clamp(0, _pages.length - 1);
    // transform zoom rides on fit-width pages (see _zoomTo); leave a
    // zoomed-out layout first, then let the new scroll extents settle
    if (_layoutZoom < 1) {
      _setLayoutZoom(1);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !_scroll.hasClients) return;
    }
    final page = _pages[index];
    final box = page.cropBox;
    if (box.width <= 0 || box.height <= 0) return;
    final pageWidth = _viewWidth * _layoutZoom;
    final geometry = PdfPageGeometry(
      cropBox: box,
      rotation: page.rotation,
      viewSize: Size(pageWidth, _pageHeight(index)),
    );
    final target = geometry.toViewRect(rect);
    // list space: pages are centered horizontally and stacked vertically
    final center = target.center +
        Offset((_viewWidth - pageWidth) / 2, _pageOffset(index));
    final fit = 0.4 *
        math.min(_viewWidth / math.max(target.width, 8),
            _viewHeight / math.max(target.height, 8));
    final scale = fit.clamp(1.0, widget.maxZoom);
    final scroll = (center.dy - _viewHeight / 2)
        .clamp(0.0, _scroll.position.maxScrollExtent);
    final Matrix4 end;
    if (scale <= 1.01) {
      end = Matrix4.identity();
    } else {
      // the viewport unprojects to list space as (p - t) / s (see
      // _visibleFractionOf); solve its center = `center` for t, with the
      // scroll offset the list actually reaches
      final tx = (_viewWidth / 2 - scale * center.dx)
          .clamp(_viewWidth * (1 - scale), 0.0);
      final ty = (scale * (scroll - center.dy) + _viewHeight / 2)
          .clamp(_viewHeight * (1 - scale), 0.0);
      end = Matrix4.identity()
        ..translateByDouble(tx, ty, 0, 1)
        ..scaleByDouble(scale, scale, scale, 1);
    }
    _zoomAnimation = Matrix4Tween(begin: _transform.value, end: end).animate(
        CurvedAnimation(parent: _zoomAnimator, curve: Curves.easeInOut));
    _zoomAnimator.forward(from: 0);
    setState(() => _zoomed = scale > 1.01);
    await _scroll.animateTo(
      scroll,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  /// Page [index]'s extracted text, from the per-revision in-memory cache,
  /// then the persistent [PdfViewer.textCache] (cold reopen, async), then a
  /// fresh extraction. The persistent cache is consulted only for a static
  /// document ([PdfViewer.editing] null and a [PdfViewer.documentId] to key
  /// by) — an edit session mutates page content, so its text stays
  /// in-memory-only to avoid serving a stale content-keyed entry.
  Future<PdfPageText> _extractText(int index) async {
    final cached = _textCache[index];
    if (cached != null) return cached;
    final textCache = widget.textCache;
    final key = widget.documentId;
    if (textCache != null && key != null && widget.editing == null) {
      final text = await textCache.get(
          key, index, () => PdfTextExtractor.extract(widget.document, index));
      return _textCache[index] ??= text;
    }
    return _textCache[index] ??= PdfTextExtractor.extract(widget.document, index);
  }

  Future<List<PdfSearchResult>> _searchAllPages(
      String query, PdfSearchOptions options) async {
    final results = <PdfSearchResult>[];
    for (var i = 0; i < _pages.length; i++) {
      // A newer keystroke has superseded this search — stop grinding pages
      // immediately instead of interpreting every remaining content stream
      // (100–420ms each) only for the caller to discard the result. Without
      // this, each keystroke on a heavy document stacks another full-document
      // walk on the event loop and the field chugs: the next search sets
      // _query as soon as it runs (during one of the yields below), so this
      // cheap synchronous check lets the stale walk bail at the next page.
      if (_controller._query != query) return const [];
      final text = await _extractText(i);
      final matches = text.findAll(
        query,
        caseSensitive: options.matchCase,
        wholeWord: options.wholeWord,
        regex: options.regex,
      );
      for (final match in matches) {
        results.add(_snippetFor(text, match));
      }
      // Yield to the event loop every few pages so frames paint and the
      // superseding search gets a chance to run (a microtask wouldn't let
      // timers/rendering in, so this is a Duration.zero delay).
      if (i % 5 == 4) await Future<void>.delayed(Duration.zero);
    }
    return results;
  }

  static final RegExp _whitespaceRun = RegExp(r'\s+');

  /// Context for one hit: the rest of its line, capped to a handful of
  /// words each side with ellipses marking what was cut.
  static PdfSearchResult _snippetFor(PdfPageText text, PdfTextMatch match) {
    const beforeChars = 36, afterChars = 48;
    final s = text.text;
    final lineStart =
        match.start == 0 ? 0 : s.lastIndexOf('\n', match.start - 1) + 1;
    var lineEnd = s.indexOf('\n', match.end);
    if (lineEnd < 0) lineEnd = s.length;
    final from = math.max(lineStart, match.start - beforeChars);
    final to = math.min(lineEnd, match.end + afterChars);
    String squash(String part) => part.replaceAll(_whitespaceRun, ' ');
    return PdfSearchResult(
      match: match,
      prefix: (from > lineStart ? '… ' : '') +
          squash(s.substring(from, match.start)).trimLeft(),
      matchText: s.substring(match.start, match.end),
      suffix: squash(s.substring(match.end, to)).trimRight() +
          (to < lineEnd ? ' …' : ''),
    );
  }

  PdfPageText _pageText(int index) =>
      _textCache[index] ??= PdfTextExtractor.extract(widget.document, index);

  /// The visible part of page [index]'s laid-out area, as fractions of
  /// the page (0–1, y-down), or null while the page is off-screen.
  Rect? _visibleFractionOf(int index) {
    if (_viewWidth <= 0 || !_scroll.hasClients || index >= _pages.length) {
      return null;
    }
    // the InteractiveViewer transform is scale + translation only, so the
    // viewport unprojects to list space as (p - t) / s
    final m = _transform.value;
    final scale = m.getMaxScaleOnAxis();
    final view = Rect.fromLTWH(
      -m.storage[12] / scale,
      -m.storage[13] / scale + _scroll.position.pixels,
      _viewWidth / scale,
      _viewHeight / scale,
    );
    final pageWidth = _viewWidth * _layoutZoom;
    final pageRect = Rect.fromLTWH((_viewWidth - pageWidth) / 2,
        _pageOffset(index), pageWidth, _pageHeight(index));
    if (pageRect.isEmpty) return null;
    final overlap = view.intersect(pageRect);
    if (overlap.width <= 0 || overlap.height <= 0) return null;
    return Rect.fromLTRB(
      (overlap.left - pageRect.left) / pageRect.width,
      (overlap.top - pageRect.top) / pageRect.height,
      (overlap.right - pageRect.left) / pageRect.width,
      (overlap.bottom - pageRect.top) / pageRect.height,
    );
  }

  /// Maps a pointer position (list coordinates, inside the
  /// InteractiveViewer transform) to (page index, x, y) in that page's
  /// user space.
  (int, double, double)? _pagePointAt(Offset local) {
    if (_viewWidth <= 0 || !_scroll.hasClients || _pages.isEmpty) return null;
    final contentY = _scroll.offset + local.dy;
    var top = 0.0;
    for (var i = 0; i < _pages.length; i++) {
      final height = _pageHeight(i);
      if (contentY <= top + height || i == _pages.length - 1) {
        final box = _pages[i].cropBox;
        if (box.width <= 0 || box.height <= 0) return null;
        final pageWidth = _viewWidth * _layoutZoom;
        final geometry = PdfPageGeometry(
          cropBox: box,
          rotation: _pages[i].rotation,
          viewSize: Size(pageWidth, height),
        );
        final (x, y) = geometry.toPagePoint(
            Offset(local.dx - (_viewWidth - pageWidth) / 2, contentY - top));
        return (i, x, y);
      }
      top += height + widget.pageSpacing;
    }
    return null;
  }

  /// Resolves a *global* point to the page index and page-space point
  /// under it — the editing overlay hands a cross-page move drag's drop
  /// position here. Conversion runs through the list-space render box, so
  /// the zoom transform is undone for free (same path the text-selection
  /// handles use).
  (int, double, double)? _resolvePagePointGlobal(Offset globalPosition) {
    final box = _listSpaceKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    return _pagePointAt(box.globalToLocal(globalPosition));
  }

  /// A page overlay reports its single-selection move drag here so the
  /// floating ghost paints above every page (a per-page overlay clips it
  /// behind the page below once the drag crosses a boundary). Null clears.
  void _onMoveDragPreview(PdfMoveDragPreview? preview) {
    if (preview == null && _movePreview == null) return;
    setState(() => _movePreview = preview);
  }

  /// The slice of an in-flight single-selection move ghost that lands on
  /// page [index], expressed in that page's own view space — null when no
  /// move is dragging, when [index] is the source page (its own overlay
  /// already draws the in-page part), or when the ghost doesn't reach this
  /// page. Each page draws its own slice in its overlay Stack (clipped to
  /// the page, painted over the page's raster), so the part hanging onto a
  /// neighbour isn't lost behind it — the per-page render path the in-page
  /// ghost already uses, rather than a viewer-level layer that the web
  /// build wouldn't paint.
  PdfMoveDragPreview? _crossPageGhostFor(int index) {
    final preview = _movePreview;
    if (preview == null || index == preview.pageIndex) return null;
    if (index < 0 || index >= _pages.length) return null;
    if (_viewWidth <= 0) return null;
    // [from] is the picture's source anchor and must stay in source view
    // space (paintAnnotationDragPreview places the picture relative to it);
    // only [to] moves into this page's view space. Page tops differ only
    // vertically — both pages share the centred x origin (page width
    // depends only on the viewport, not the page).
    final dy = _pageTop(preview.pageIndex) - _pageTop(index);
    final to = preview.to.shift(Offset(0, dy));
    final pageBox =
        Offset.zero & Size(_viewWidth * _layoutZoom, _pageHeight(index));
    if (!to.overlaps(pageBox)) return null;
    return PdfMoveDragPreview(
      pageIndex: index,
      picture: preview.picture,
      from: preview.from,
      to: to,
      scale: preview.scale,
    );
  }

  /// The cumulative top offset (list coordinates) of page [index].
  double _pageTop(int index) {
    var top = 0.0;
    for (var i = 0; i < index; i++) {
      top += _pageHeight(i) + widget.pageSpacing;
    }
    return top;
  }

  /// The laid-out geometry of page [index], or null when it isn't
  /// measurable yet (no width, junk crop box, out of range).
  PdfPageGeometry? _pageGeometry(int index) {
    if (_viewWidth <= 0 || index < 0 || index >= _pages.length) return null;
    final box = _pages[index].cropBox;
    if (box.width <= 0 || box.height <= 0) return null;
    return PdfPageGeometry(
      cropBox: box,
      rotation: _pages[index].rotation,
      viewSize: Size(_viewWidth * _layoutZoom, _pageHeight(index)),
    );
  }

  /// Maps a viewport-local offset into page [index]'s view-box
  /// coordinates (what [PdfPageGeometry] expects), without clamping — a
  /// marquee dragged past the page edge still maps to sensible (possibly
  /// out-of-page) user-space coordinates.
  Offset _toPageView(int index, Offset local) {
    final pageWidth = _viewWidth * _layoutZoom;
    return Offset(
      local.dx - (_viewWidth - pageWidth) / 2,
      _scroll.offset + local.dy - _pageTop(index),
    );
  }

  /// Maps a pointer position to a text position. [tolerance] is in page
  /// units; pass infinity to snap to the nearest text while dragging.
  (int, int)? _textPositionAt(Offset local, {required double tolerance}) {
    final point = _pagePointAt(local);
    if (point == null) return null;
    final (i, x, y) = point;
    final offset = _pageText(i).positionNear(x, y, tolerance: tolerance);
    return offset < 0 ? null : (i, offset);
  }

  /// Visible annotations with an action on a page, cached.
  List<PdfAnnotation> _interactiveAnnots(int index) => _annotCache[index] ??= [
        for (final a in _pages[index].annotations)
          if (!a.isHidden && !a.isNoView && a.action != null) a,
      ];

  /// Visible form-field widget rects on a page, for the field
  /// highlight. Cached beside [_annotCache] (same lifecycle: pages are
  /// reloaded on every document swap).
  List<PdfRect> _formFieldRects(int index) => _fieldRectCache[index] ??= [
        for (final a in _pages[index].annotations)
          if (a is PdfWidgetAnnotation && !a.isHidden && !a.isNoView) a.rect,
      ];

  PdfAnnotation? _annotationAt(Offset local) {
    // hidden annotations don't render, so they don't take taps either —
    // an invisible link navigating would be baffling
    if (!widget.showAnnotations) return null;
    final point = _pagePointAt(local);
    if (point == null) return null;
    final (i, x, y) = point;
    // later /Annots entries paint on top, so they win the hit test
    for (final annotation in _interactiveAnnots(i).reversed) {
      if (annotation.rect.contains(x, y)) return annotation;
    }
    return null;
  }

  void _onTapUp(TapUpDetails details) {
    if (_suppressTap) {
      _suppressTap = false;
      return;
    }
    _clearSelection();
    final annotation = _annotationAt(details.localPosition);
    if (annotation != null) {
      _activate(annotation);
      return;
    }
    // selection is the default mode for mice: clicking an annotation
    // selects it without arming a tool (the editing overlay then mounts
    // and takes over until the selection is cleared)
    final editing = widget.editing;
    if (editing != null &&
        editing.tool == null &&
        !editing.isPickingColor &&
        _lastPointerKind == PointerDeviceKind.mouse) {
      final point = _pagePointAt(details.localPosition);
      if (point != null) {
        editing.selectAnnotationAt(point.$1, point.$2, point.$3);
      }
    }
  }

  /// Right-click (or two-finger tap): a context menu for mouse
  /// platforms. With the form tool armed and a field under the click it
  /// opens the field menu; over an annotation (or empty page area with
  /// something on the clipboard) it opens the annotation menu — the hit
  /// annotation joins the selection first, an already-selected one
  /// keeping a multi-selection intact. Otherwise — reading mode, or a
  /// click that lands on plain page text — it opens the text menu
  /// (Copy / Select all).
  Future<void> _onSecondaryTapUp(TapUpDetails details) async {
    final point = _pagePointAt(details.localPosition);
    if (point == null) return;
    final (page, x, y) = point;
    final editing = widget.editing;
    if (editing != null && !editing.isPickingColor) {
      // form mode: a right-clicked field widget gets the field menu
      // (rename/convert/delete/flatten) instead of the annotation menu
      if (editing.tool == PdfEditTool.form) {
        final field = editing.formFieldAt(page, x, y);
        if (field != null) {
          await _showFormFieldMenu(details.globalPosition, field.$1.name);
          return;
        }
      } else {
        final hit = editing.selectableAnnotationAt(page, x, y);
        // an annotation, or empty page area with something to paste,
        // gets the annotation menu
        if (hit != null || editing.hasAnnotationClipboard) {
          if (hit != null && !editing.isAnnotationSelected(page, hit.$1)) {
            editing.selectAnnotationAt(page, x, y);
          }
          await showPdfAnnotationMenu(
            context: context,
            position: details.globalPosition,
            controller: editing,
            pageIndex: page,
            customActions: widget.annotationMenuBuilder,
            pagePoint: (x, y),
          );
          return;
        }
      }
    } else if (editing != null) {
      // the eyedropper owns the click while it is armed
      return;
    }
    // reading mode, or nothing under the click in editing mode: the text
    // menu, mirroring the touch selection chip for mouse users
    await _showTextMenu(details.globalPosition, details.localPosition, page);
  }

  /// The mouse right-click text menu: Copy the current selection and
  /// Select all on the page. Mirrors the touch selection chip's actions
  /// for desktop users, who otherwise have only ⌘C. A right-click that
  /// lands outside the current selection first selects the word under
  /// the cursor, like a desktop reader, so Copy has something to act on;
  /// a click inside the selection keeps it. With no selectable word and
  /// no page text the menu does not open.
  Future<void> _showTextMenu(
      Offset globalPosition, Offset local, int page) async {
    final position = _textPositionAt(local, tolerance: 14);
    if (!(position != null && _selectionContains(position))) {
      _selectWordAt(local);
    }
    final hasSelection = _selRange != null;
    final hasText = _pageText(page).text.isNotEmpty;
    if (!hasSelection && !hasText) return;
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final picked = await showMenu<_TextMenuAction>(
      context: context,
      position: RelativeRect.fromRect(
          globalPosition & Size.zero, Offset.zero & overlay.size),
      items: [
        PopupMenuItem<_TextMenuAction>(
          key: const ValueKey('pdf-text-menu-copy'),
          value: _TextMenuAction.copy,
          enabled: hasSelection,
          child: _textMenuRow(Icons.copy, 'Copy', hasSelection),
        ),
        PopupMenuItem<_TextMenuAction>(
          key: const ValueKey('pdf-text-menu-select-all'),
          value: _TextMenuAction.selectAll,
          enabled: hasText,
          child: _textMenuRow(Icons.select_all, 'Select all', hasText),
        ),
      ],
    );
    switch (picked) {
      case _TextMenuAction.copy:
        await _controller.copySelection();
      case _TextMenuAction.selectAll:
        _selectAllTextOn(page);
      case null:
        break;
    }
  }

  Widget _textMenuRow(IconData icon, String label, bool enabled) => Row(
        children: [
          Builder(
            builder: (context) => Icon(icon,
                size: 18,
                color: enabled ? null : Theme.of(context).disabledColor),
          ),
          const SizedBox(width: 10),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      );

  /// Whether [position] (page, char index) falls inside the current text
  /// selection [start, end).
  bool _selectionContains((int, int) position) {
    final range = _selRange;
    if (range == null) return false;
    final (start, end) = range;
    return !_isBefore(position, start) && _isBefore(position, end);
  }

  /// The selection action chip's "more" button and the editing
  /// overlay's touch long-press: the same context menu right-clicking
  /// opens, for input that can't right-click. [pagePoint] anchors a
  /// paste from a press on empty page area.
  Future<void> _showSelectionMenu(Offset globalPosition, int pageIndex,
      {(double, double)? pagePoint}) async {
    final editing = widget.editing;
    if (editing == null) return;
    await showPdfAnnotationMenu(
      context: context,
      position: globalPosition,
      controller: editing,
      pageIndex: pageIndex,
      customActions: widget.annotationMenuBuilder,
      pagePoint: pagePoint,
    );
  }

  /// The form-field context menu, shared by right-click and the editing
  /// overlay's touch long-press (both with the form tool armed).
  Future<void> _showFormFieldMenu(
      Offset globalPosition, String fieldName) async {
    final editing = widget.editing;
    if (editing == null) return;
    await showPdfFormFieldMenu(
      context: context,
      position: globalPosition,
      controller: editing,
      fieldName: fieldName,
      textPrompt: widget.editingTextPrompt ?? showPdfTextPrompt,
    );
  }

  void _activate(PdfAnnotation annotation) {
    final action = annotation.action;
    if (action == null) return;
    switch (action) {
      case PdfGoToAction(:final destination):
        _scrollToDestination(destination);
      case PdfNamedAction(:final name) when _handleNamedAction(name):
        break; // handled internally
      default:
        widget.onAction?.call(action, annotation);
    }
  }

  bool _handleNamedAction(String name) {
    switch (name) {
      case 'NextPage':
        _jumpToPage(_controller.currentPage + 1);
      case 'PrevPage':
        _jumpToPage(_controller.currentPage - 1);
      case 'FirstPage':
        _jumpToPage(0);
      case 'LastPage':
        _jumpToPage(_pages.length - 1);
      default:
        return false;
    }
    return true;
  }

  void _scrollToDestination(PdfDestination destination) {
    if (!_scroll.hasClients) return;
    final index = destination.pageIndex.clamp(0, _pages.length - 1);
    var target = _pageOffset(index) + _zoomWindowDy;
    final box = _pages[index].cropBox;
    final top = destination.top;
    if (top != null && box.height > 0) {
      final fractionDown = ((box.top - top) / box.height).clamp(0.0, 1.0);
      target += fractionDown * _pageHeight(index);
    }
    _scroll.animateTo(
      target.clamp(0.0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  /// Whether the point sits over an annotation a default-mode mouse
  /// click would select.
  bool _selectableAnnotationAt(Offset local) {
    final editing = widget.editing;
    if (editing == null || editing.tool != null) return false;
    final point = _pagePointAt(local);
    return point != null &&
        editing.selectableAnnotationAt(point.$1, point.$2, point.$3) != null;
  }

  void _onHover(PointerHoverEvent event) {
    _lastPointerLocal = event.localPosition;
    if (_grabPanning) return; // grabbing keeps its cursor mid-drag
    final editing = widget.editing;
    final MouseCursor cursor;
    if (editing != null &&
        editing.tool == null &&
        !editing.isPickingColor &&
        !editing.hasAnnotationSelection &&
        HardwareKeyboard.instance.isShiftPressed) {
      // Shift held in default editing mode: a drag rubber-bands a marquee
      cursor = SystemMouseCursors.precise;
    } else if (_annotationAt(event.localPosition) != null ||
        _selectableAnnotationAt(event.localPosition)) {
      cursor = SystemMouseCursors.click;
    } else if (_textPositionAt(event.localPosition, tolerance: 8) != null) {
      cursor = SystemMouseCursors.text;
    } else {
      // empty page or canvas: a mouse drag grab-pans the document
      cursor = SystemMouseCursors.grab;
    }
    if (cursor != _hoverCursor) setState(() => _hoverCursor = cursor);
  }

  /// ⌘C/Ctrl+C: an annotation selection copies to the editing
  /// controller's clipboard; otherwise the text selection copies to the
  /// system clipboard.
  void _onCopy() {
    final editing = widget.editing;
    if (editing != null && editing.hasAnnotationSelection) {
      if (editing.copySelectedAnnotations() > 0) return;
    }
    _controller.copySelection();
  }

  /// ⌘X/Ctrl+X: cut the selected annotations (copy + delete).
  void _onCut() => widget.editing?.cutSelectedAnnotations();

  /// ⌘V/Ctrl+V: paste the annotation clipboard at the cursor — the page
  /// and point under the last pointer, like the right-click paste. With
  /// no pointer seen yet (touch / keyboard-only) it falls back to the
  /// current page's cascade.
  void _onPaste() {
    final editing = widget.editing;
    if (editing == null) return;
    // a captured snapshot pastes back as vector graphics; otherwise the
    // annotation clipboard (the most recent copy wins, mirroring the
    // controller's clipboards)
    final snapshot = editing.hasSnapshotClipboard;
    if (!snapshot && !editing.hasAnnotationClipboard) return;
    final local = _lastPointerLocal;
    final point = local == null ? null : _pagePointAt(local);
    if (snapshot) {
      if (point != null) {
        editing.pasteSnapshot(point.$1, at: (point.$2, point.$3));
      } else {
        editing.pasteSnapshot(_controller.currentPage);
      }
    } else if (point != null) {
      editing.pasteAnnotations(point.$1, at: (point.$2, point.$3));
    } else {
      editing.pasteAnnotations(_controller.currentPage);
    }
  }

  /// ⌘A/Ctrl+A: with the select tool armed (or an annotation selection
  /// in play) selects every annotation on the current page; otherwise
  /// selects the current page's whole text.
  void _onSelectAll() {
    final page = _controller.currentPage;
    final editing = widget.editing;
    if (editing != null &&
        (editing.tool == PdfEditTool.select ||
            editing.hasAnnotationSelection)) {
      editing.selectAllAnnotationsOn(page);
      return;
    }
    _selectAllTextOn(page);
  }

  /// Selects the whole text of one page (⌘A and the touch chip's
  /// Select All).
  void _selectAllTextOn(int page) {
    final length = _pageText(page).text.length;
    if (length == 0) return;
    _wordAnchor = null;
    setState(() {
      _selAnchor = (page, 0);
      _selFocus = (page, length);
    });
    _controller._setSelection(_selectedText());
  }

  /// A single-key tool shortcut ([pdfEditToolShortcuts]) arms [tool],
  /// mirroring the toolbar's chips: pressing a tool's key arms it,
  /// pressing it again drops back to Select. Clears the text selection
  /// like a toolbar tap does.
  void _armTool(PdfEditTool tool) {
    final editing = widget.editing;
    if (editing == null) return;
    editing.tool = editing.tool == tool ? PdfEditTool.select : tool;
    _controller.clearSelection();
  }

  /// Escape backs out of editing state layer by layer before it clears
  /// the text selection: annotation or element selection → pending ink →
  /// armed tool.
  void _onEscape() {
    final editing = widget.editing;
    if (editing != null) {
      if (editing.isPickingColor) {
        editing.cancelColorPick();
        return;
      }
      if (editing.hasAnnotationSelection) {
        editing.clearAnnotationSelection();
        return;
      }
      if (editing.selectedElement != null) {
        editing.clearElementSelection();
        return;
      }
      if (editing.hasPendingInk) {
        editing.discardInk();
        return;
      }
      if (editing.tool != null) {
        editing.tool = null;
        return;
      }
    }
    _clearSelection();
  }

  /// The controller behind any in-place text editor — the editing
  /// session, or (in the reader) the standalone form-fill controller.
  PdfEditingController? get _textEditController =>
      widget.editing ?? widget.formController;

  void _onPointerDown(PointerDownEvent event) {
    _suppressTap = false;
    _lastPointerKind = event.kind;
    _lastPointerLocal = event.localPosition;
    _panFlinger.stop();
    _touchFlinger.stop();
    if (event.kind == PointerDeviceKind.touch) {
      widget.editing?.noteTouchInput();
    }
    // a raw listener fires regardless of who wins the gesture arena, so
    // clicking anywhere — including editing overlays — focuses the viewer
    // and its keyboard shortcuts. Not while an in-place text editor is
    // typing, though: stealing its focus on every click would close it.
    if (_textEditController?.isEditingText != true) _focusNode.requestFocus();
    if (event.kind != PointerDeviceKind.mouse) {
      _wordDrag = false;
      return;
    }
    final lastStamp = _lastMouseDownStamp;
    final lastLocal = _lastMouseDownLocal;
    _wordDrag = lastStamp != null &&
        lastLocal != null &&
        event.timeStamp - lastStamp < kDoubleTapTimeout &&
        (event.localPosition - lastLocal).distance < kDoubleTapSlop;
    _lastMouseDownStamp = event.timeStamp;
    _lastMouseDownLocal = event.localPosition;
  }

  /// Completes a mouse double-click (second press, released without
  /// dragging): select the word under it. Detected from raw pointer
  /// timing so no double-tap recognizer has to sit in the gesture arena
  /// for mice — an arena recognizer would delay every click in the viewer
  /// by the disambiguation timeout and claim the second of two rapid
  /// clicks, starving buttons in page overlays.
  void _onPointerUp(PointerUpEvent event) {
    if (event.kind != PointerDeviceKind.mouse || !_wordDrag) return;
    final downLocal = _lastMouseDownLocal;
    if (downLocal == null ||
        (event.localPosition - downLocal).distance >= kTouchSlop) {
      return; // it became a double-click-drag, handled by the pan flow
    }
    if (_editingTextBoxAt(event.localPosition)) {
      return; // let the editing overlay turn the click into in-place edit
    }
    // the viewer's own tap recognizer fires after this raw event and
    // would immediately clear the selection made here
    _suppressTap = true;
    _selectWordAt(event.localPosition);
  }

  /// Whether a default/select-mode mouse click at [local] is over a
  /// free-text annotation that the editing overlay can edit in place.
  ///
  /// The viewer detects mouse double-clicks from raw pointer events so
  /// normal overlay buttons are not delayed by a double-tap recognizer.
  /// Raw events also see clicks that land on the editing overlay, so a
  /// double-click into a selected text box must stand down here; otherwise
  /// the page-content word selector consumes the second click before the
  /// overlay can open its inline editor.
  bool _editingTextBoxAt(Offset local) {
    final editing = widget.editing;
    if (editing == null || editing.isPickingColor) return false;
    final tool = editing.tool;
    if (tool != null && tool != PdfEditTool.select) return false;
    final point = _pagePointAt(local);
    if (point == null) return false;
    final hit = editing.selectableAnnotationAt(point.$1, point.$2, point.$3);
    return hit?.$2.subtype == 'FreeText';
  }

  /// Whether a pointer of [kind] is drawing through the editing
  /// overlay's raw event stream right now (ink or eraser armed, pen or
  /// drawing finger) — the viewer's own gestures must stand aside.
  bool _kindDrawsInk(PointerDeviceKind? kind) {
    final editing = widget.editing;
    if (editing == null ||
        (editing.tool != PdfEditTool.ink &&
            editing.tool != PdfEditTool.eraser)) {
      return false;
    }
    return switch (kind) {
      PointerDeviceKind.stylus || PointerDeviceKind.invertedStylus => true,
      PointerDeviceKind.touch => editing.fingerDrawsInk,
      _ => false,
    };
  }

  /// Whether a freehand drawing tool (ink or eraser) is armed. In this
  /// "drawing mode" the viewer's trackpad/wheel zoom paths stand down so
  /// a stray pinch can't zoom the page out from under a stroke: on the
  /// web a two-finger trackpad gesture arrives as a pinch
  /// (`PointerScaleEvent`) that [InteractiveViewer] would otherwise apply
  /// directly (its `scaleFactor` neutralization only covers wheel
  /// scrolling). Touch pinch still zooms — it runs through
  /// [_EagerPinchRecognizer], not these paths — so on-screen pinch-to-zoom
  /// while drawing is unaffected; on a trackpad/wheel, switch to another
  /// tool to zoom.
  bool get _drawToolArmed {
    final tool = widget.editing?.tool;
    return tool == PdfEditTool.ink || tool == PdfEditTool.eraser;
  }

  void _onSelectionStart(DragStartDetails details) {
    // a raw-drawing pointer may still win this arena (the overlay's
    // recognizers don't claim every kind) — it must not grab-pan the
    // document out from under its own stroke
    if (_kindDrawsInk(details.kind)) return;
    _focusNode.requestFocus();
    // Shift+drag in default editing mode (no tool armed, nothing
    // selected) rubber-bands a marquee selection — the gesture the
    // select tool offers, without arming it. Shift forces the marquee
    // over whatever is under the press (text, an annotation, empty
    // page), so a normal drag still grab-pans or selects text.
    if (_marqueeShouldStart(details)) {
      // anchor at the pointer-down position, not where the pan was
      // recognized past the slop — the box should start under the press
      final start = _lastMouseDownLocal ?? details.localPosition;
      final point = _pagePointAt(start);
      if (point != null) {
        _marqueePage = point.$1;
        _marqueeStart = start;
        setState(() => _marqueeCurrent = details.localPosition);
        _controller._setSelection('');
        return;
      }
    }
    if (_wordDrag) {
      // double-click-and-drag: anchor on the word under the original
      // press (the drag start has already moved past the touch slop)
      final anchor = _wordRangeAt(_lastMouseDownLocal ?? details.localPosition);
      _wordAnchor = anchor;
      setState(() {
        _selAnchor = anchor?.$1;
        _selFocus = anchor?.$2;
      });
      _controller._setSelection(anchor == null ? '' : _selectedText());
      return;
    }
    _wordAnchor = null;
    final position = _textPositionAt(details.localPosition, tolerance: 14);
    if (position == null) {
      // nothing to select under the press: the drag grabs the document
      // instead (mouse drags don't reach the list's scrollable)
      _grabPanning = true;
      setState(() => _hoverCursor = SystemMouseCursors.grabbing);
      _controller._setSelection('');
      return;
    }
    setState(() {
      _selAnchor = position;
      _selFocus = position;
    });
    _controller._setSelection('');
  }

  /// Whether [_onSelectionStart] should begin a marquee instead of a
  /// text selection or grab-pan: a mouse/trackpad drag with Shift held,
  /// in default editing mode (a tool would own the gesture, and a live
  /// selection mounts the editing overlay, which marquees itself).
  bool _marqueeShouldStart(DragStartDetails details) {
    final editing = widget.editing;
    if (editing == null ||
        editing.tool != null ||
        editing.isPickingColor ||
        editing.hasAnnotationSelection) {
      return false;
    }
    final kind = details.kind;
    final mouseLike = kind == null ||
        kind == PointerDeviceKind.mouse ||
        kind == PointerDeviceKind.trackpad;
    return mouseLike && HardwareKeyboard.instance.isShiftPressed;
  }

  /// Finishes a marquee drag: selects the annotations the box covers on
  /// the page the drag began on. A box too small to be a deliberate drag
  /// is treated as a click (no selection change).
  void _commitMarquee() {
    final editing = widget.editing;
    final page = _marqueePage;
    final start = _marqueeStart;
    final current = _marqueeCurrent ?? start;
    setState(() {
      _marqueeStart = null;
      _marqueeCurrent = null;
      _marqueePage = null;
    });
    if (editing == null || page == null || start == null || current == null) {
      return;
    }
    final box = Rect.fromPoints(start, current);
    if (box.width < 4 && box.height < 4) return; // a click, not a drag
    final geometry = _pageGeometry(page);
    if (geometry == null || !_scroll.hasClients) return;
    editing.selectAnnotationsIn(
      page,
      geometry.toPageRect(Rect.fromPoints(
          _toPageView(page, box.topLeft), _toPageView(page, box.bottomRight))),
    );
  }

  void _onSelectionUpdate(DragUpdateDetails details) {
    if (_marqueeStart != null) {
      setState(() => _marqueeCurrent = details.localPosition);
      return;
    }
    if (_grabPanning) {
      _grabPanBy(details.delta);
      return;
    }
    if (_wordAnchor != null) {
      _extendWordSelection(details.localPosition);
      return;
    }
    if (_selAnchor == null) return;
    final position =
        _textPositionAt(details.localPosition, tolerance: double.infinity);
    if (position == null || position == _selFocus) return;
    setState(() => _selFocus = position);
    _controller._setSelection(_selectedText());
  }

  void _onSelectionEnd(DragEndDetails details) {
    if (_marqueeStart != null) {
      _commitMarquee();
      return;
    }
    if (!_grabPanning) return;
    _grabPanning = false;
    setState(() => _hoverCursor = SystemMouseCursors.grab);
  }

  /// Word granularity: spans from the anchor word through the word
  /// under the pointer (mouse double-click drags and long-press drags).
  void _extendWordSelection(Offset local) {
    final wordAnchor = _wordAnchor;
    if (wordAnchor == null) return;
    final range = _wordRangeAt(local, tolerance: double.infinity);
    if (range == null) return;
    final start = _isBefore(range.$1, wordAnchor.$1) ? range.$1 : wordAnchor.$1;
    final end = _isBefore(wordAnchor.$2, range.$2) ? range.$2 : wordAnchor.$2;
    if (start == _selAnchor && end == _selFocus) return;
    setState(() {
      _selAnchor = start;
      _selFocus = end;
    });
    _controller._setSelection(_selectedText());
  }

  // --- touch text selection ---
  //
  // Touch and stylus drags always scroll; selecting text starts with a
  // long press on a word (the recognizer claims the arena, so the list
  // can't scroll out from under the press) and extends by whole words
  // while the press drags. Lifting shows drag handles at both ends and
  // a Copy/Select-All chip; the handles re-anchor the selection at
  // character granularity.

  /// Whether the touch selection chrome (handles + chip) should show:
  /// there is a selection and the last pointer was touch or stylus.
  bool get _touchSelectionChrome =>
      _selRange != null &&
      (_lastPointerKind == PointerDeviceKind.touch ||
          _lastPointerKind == PointerDeviceKind.stylus);

  void _onLongPressStart(LongPressStartDetails details) {
    final range = _wordRangeAt(details.localPosition);
    if (range == null) {
      // no text under the press: an annotation (or, with something on
      // the clipboard, empty page area) gets the context menu instead —
      // reader mode's touch counterpart of a right-click
      if (!_maybeAnnotationMenu(details)) _clearSelection();
      return;
    }
    HapticFeedback.selectionClick();
    _wordAnchor = range;
    setState(() {
      _touchSelecting = true;
      _selAnchor = range.$1;
      _selFocus = range.$2;
    });
    _controller._setSelection(_selectedText());
  }

  /// Reader-mode touch long-press fallback: with no text under the
  /// press, an annotation joins the selection and gets the context
  /// menu; empty page area gets the paste menu when the clipboard has
  /// content. Returns whether a menu opened.
  bool _maybeAnnotationMenu(LongPressStartDetails details) {
    final editing = widget.editing;
    if (editing == null || editing.tool != null || editing.isPickingColor) {
      return false;
    }
    final point = _pagePointAt(details.localPosition);
    if (point == null) return false;
    final (page, x, y) = point;
    final hit = editing.selectableAnnotationAt(page, x, y);
    if (hit != null) {
      if (!editing.isAnnotationSelected(page, hit.$1)) {
        editing.selectAnnotationAt(page, x, y);
      }
    } else if (!editing.hasAnnotationClipboard) {
      return false;
    }
    HapticFeedback.selectionClick();
    unawaited(
        _showSelectionMenu(details.globalPosition, page, pagePoint: (x, y)));
    return true;
  }

  void _onLongPressMove(LongPressMoveUpdateDetails details) {
    if (!_touchSelecting) return;
    _extendWordSelection(details.localPosition);
  }

  void _onLongPressEnd() {
    if (!_touchSelecting) return;
    setState(() => _touchSelecting = false);
  }

  /// A handle drag begins: the dragged end becomes the moving focus and
  /// the opposite end the fixed anchor, whichever way the original
  /// selection was made.
  void _onHandleDragStart(bool start) {
    final range = _selRange;
    if (range == null) return;
    _wordAnchor = null;
    setState(() {
      _selAnchor = start ? range.$2 : range.$1;
      _selFocus = start ? range.$1 : range.$2;
      _handleDragging = true;
    });
  }

  void _onHandleDragUpdate(Offset globalPosition) {
    final box = _listSpaceKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    // through the render tree, so the zoom transform is applied for free
    final local = box.globalToLocal(globalPosition);
    final position = _textPositionAt(local, tolerance: double.infinity);
    if (position == null || position == _selFocus) return;
    setState(() => _selFocus = position);
    _controller._setSelection(_selectedText());
  }

  void _onHandleDragEnd() {
    if (!_handleDragging) return;
    setState(() => _handleDragging = false);
  }

  Future<void> _copyAndDismiss() async {
    await _controller.copySelection();
    _clearSelection();
  }

  /// The touch selection config for the page at [index], or null when
  /// the page shows no handles (not a boundary page of the selection,
  /// or the chrome is hidden entirely).
  _PageTextSelection? _textSelectionOn(int index) {
    if (!_touchSelectionChrome) return null;
    final range = _selRange;
    if (range == null) return null;
    final isStart = index == range.$1.$1;
    final isEnd = index == range.$2.$1;
    if (!isStart && !isEnd) return null;
    // mid-long-press the live selection wash is the only feedback;
    // handles and chip appear when the finger lifts
    if (_touchSelecting) return null;
    final rects = _selectionRectsOn(index);
    if (rects.isEmpty) return null;
    return _PageTextSelection(
      startRect: isStart ? rects.first : null,
      endRect: isEnd ? rects.last : null,
      chip: isEnd && !_handleDragging,
      onDragStart: _onHandleDragStart,
      onDragUpdate: _onHandleDragUpdate,
      onDragEnd: _onHandleDragEnd,
      onCopy: _copyAndDismiss,
      onSelectAll: () => _selectAllTextOn(index),
    );
  }

  /// Grab panning: moves the document with the pointer. Deltas are in
  /// list-space pixels (the gesture detector sits inside the zoom
  /// transform); the scroll extents absorb what they can and the rest
  /// pans the zoom window, like the scrollbars.
  void _grabPanBy(Offset delta) {
    _scrollbarScrollBy(-delta.dy);
    _scrollbarPanBy(-delta.dx);
  }

  /// Scroll-fling deceleration: velocity decays by e^-2 per second
  /// (≈ UIScrollView's "normal" rate), so a fling travels about half a
  /// second's worth of its release velocity. The tolerance stops the
  /// simulation once motion drops below anything visible.
  static const double _flingFriction = 0.135;
  static const Tolerance _flingTolerance = Tolerance(velocity: 5);

  /// Continues a viewport pan with the gesture's lift-off velocity
  /// (list-space px/s — drag velocity trackers run on local positions,
  /// so the zoom transform is already divided out).
  void _flingViewport(Velocity velocity) {
    final v = velocity.pixelsPerSecond;
    if (v.distance < kMinFlingVelocity) return;
    _flingSimX =
        FrictionSimulation(_flingFriction, 0, v.dx, tolerance: _flingTolerance);
    _flingSimY =
        FrictionSimulation(_flingFriction, 0, v.dy, tolerance: _flingTolerance);
    _flingLast = Offset.zero;
    _touchFlinger.animateWith(_FlingClock(_flingSimX!, _flingSimY!));
  }

  /// One frame of the touch fling: both axes' friction deltas go through
  /// [_grabPanBy] — the scroll extents absorb what they can, the rest
  /// pans the zoom window, both clamped at the document's edges.
  void _onTouchFlingTick() {
    final simX = _flingSimX, simY = _flingSimY;
    if (simX == null || simY == null) return;
    final t = _touchFlinger.value;
    final position = Offset(simX.x(t), simY.x(t));
    final delta = position - _flingLast;
    _flingLast = position;
    final scrollBefore = _scroll.hasClients ? _scroll.position.pixels : 0.0;
    final txBefore = _transform.value.storage[12];
    final tyBefore = _transform.value.storage[13];
    _grabPanBy(delta);
    // every absorber pinned at its edge: the rest of the simulation
    // would tick for nothing
    if (delta != Offset.zero &&
        (!_scroll.hasClients || _scroll.position.pixels == scrollBefore) &&
        _transform.value.storage[12] == txBefore &&
        _transform.value.storage[13] == tyBefore) {
      _touchFlinger.stop();
    }
  }

  void _clearSelection() {
    _wordAnchor = null;
    if (_selAnchor != null || _selFocus != null || _touchSelecting) {
      setState(() {
        _selAnchor = null;
        _selFocus = null;
        _touchSelecting = false;
        _handleDragging = false;
      });
    }
    _controller._setSelection('');
  }

  /// Selection bounds in document order, or null when empty.
  ((int, int), (int, int))? get _selRange {
    final a = _selAnchor, f = _selFocus;
    if (a == null || f == null || a == f) return null;
    final reversed = f.$1 < a.$1 || (f.$1 == a.$1 && f.$2 < a.$2);
    return reversed ? (f, a) : (a, f);
  }

  String _selectedText() {
    final range = _selRange;
    if (range == null) return '';
    final (start, end) = range;
    final parts = <String>[];
    for (var i = start.$1; i <= end.$1; i++) {
      final text = _pageText(i).text;
      final from = (i == start.$1 ? start.$2 : 0).clamp(0, text.length);
      final to = (i == end.$1 ? end.$2 : text.length).clamp(0, text.length);
      if (from < to) parts.add(text.substring(from, to));
    }
    return parts.join('\n');
  }

  List<PdfRect> _selectionRectsOn(int pageIndex) =>
      [for (final quad in _selectionQuadsOn(pageIndex)) quad.bounds];

  /// Baseline-aligned selection quads on [pageIndex], so the highlight
  /// rotates with rotated text instead of painting an axis-aligned box.
  List<PdfTextQuad> _selectionQuadsOn(int pageIndex) {
    final range = _selRange;
    if (range == null) return const [];
    final (start, end) = range;
    if (pageIndex < start.$1 || pageIndex > end.$1) return const [];
    final text = _pageText(pageIndex);
    final from = pageIndex == start.$1 ? start.$2 : 0;
    final to = pageIndex == end.$1 ? end.$2 : text.text.length;
    if (from >= to) return const [];
    return text.quadsFor(from, to);
  }

  void _showMatch(PdfTextMatch match) {
    if (!_scroll.hasClients || _viewWidth <= 0) return;
    final page = _pages[match.pageIndex];
    final box = page.cropBox;
    var target = _pageOffset(match.pageIndex) + _zoomWindowDy;
    if (match.rects.isNotEmpty && box.height > 0) {
      // place the match a third of the way down the screen viewport —
      // which, zoomed in, covers 1/s of the list's space
      final scale = _transform.value.getMaxScaleOnAxis();
      final fractionDown = (box.top - match.rects.first.top) / box.height;
      target += fractionDown * _pageHeight(match.pageIndex) -
          _scroll.position.viewportDimension / (3 * scale);
    }
    _scroll.animateTo(
      target.clamp(0.0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
    setState(() {}); // repaint highlights with the new current match
  }

  /// The whitespace-delimited word range at a point (list coordinates).
  ((int, int), (int, int))? _wordRangeAt(Offset local,
      {double tolerance = 14}) {
    final position = _textPositionAt(local, tolerance: tolerance);
    if (position == null) return null;
    final text = _pageText(position.$1).text;
    var start = position.$2.clamp(0, text.length);
    var end = start;
    bool isWordChar(String c) => c.trim().isNotEmpty;
    while (start > 0 && isWordChar(text[start - 1])) {
      start--;
    }
    while (end < text.length && isWordChar(text[end])) {
      end++;
    }
    if (start == end) return null;
    return ((position.$1, start), (position.$1, end));
  }

  static bool _isBefore((int, int) a, (int, int) b) =>
      a.$1 < b.$1 || (a.$1 == b.$1 && a.$2 < b.$2);

  /// Selects the whitespace-delimited word at a point (list coordinates).
  void _selectWordAt(Offset local) {
    final range = _wordRangeAt(local);
    if (range == null) {
      _clearSelection();
      return;
    }
    _focusNode.requestFocus();
    setState(() {
      _selAnchor = range.$1;
      _selFocus = range.$2;
    });
    _controller._setSelection(_selectedText());
  }

  /// Touch double-tap: toggle zoom. Mice never reach this — the
  /// recognizer is restricted to touch/stylus so desktop clicks resolve
  /// instantly; mouse double-click word selection lives in [_onPointerUp].
  void _onDoubleTap() {
    final details = _doubleTapDetails;
    if (details == null) return;
    // two quick pen dots (dotting an i twice) are ink, not a zoom
    // gesture — the strokes already committed through the raw path
    if (_kindDrawsInk(details.kind)) return;
    final current = _currentZoom;
    final Matrix4 end;
    final bool zoomedAfter;
    if ((current - 1).abs() > 0.01) {
      // from any zoom — in or out — back to 100%
      if (_layoutZoom < 1) {
        _setLayoutZoom(1, focalY: details.localPosition.dy);
      }
      end = Matrix4.identity();
      zoomedAfter = false;
    } else {
      final position = details.localPosition;
      final scale = widget.doubleTapZoom;
      end = Matrix4.identity()
        ..translateByDouble(
            -position.dx * (scale - 1), -position.dy * (scale - 1), 0, 1)
        ..scaleByDouble(scale, scale, scale, 1);
      zoomedAfter = true;
    }
    _zoomAnimation = Matrix4Tween(begin: _transform.value, end: end).animate(
        CurvedAnimation(parent: _zoomAnimator, curve: Curves.easeInOut));
    _zoomAnimator.forward(from: 0);
    setState(() => _zoomed = zoomedAfter);
  }

  // --- touch pinch zoom ---
  //
  // _EagerPinchRecognizer claims the gesture when a second finger lands;
  // the viewer applies the scale ratio around the gesture's focal point
  // (the same _zoomTo the wheel and trackpad use, so pinching out below
  // fit-width crosses into layout zoom) and pans by the focal point's
  // drift, spilling into the scroll position like grab panning.

  /// Cumulative scale of the touch pinch in progress.
  double _pinchScale = 1;

  void _onPinchStart(ScaleStartDetails details) {
    _panFlinger.stop();
    _touchFlinger.stop();
    _pinchScale = 1;
  }

  void _onPinchUpdate(ScaleUpdateDetails details) {
    // a lone finger left over after a pinch shouldn't keep panning; the
    // gesture stays claimed but goes quiet until lift-off
    if (details.pointerCount < 2) return;
    if (details.scale > 0 && details.scale != _pinchScale) {
      _zoomTo(
          _currentZoom * details.scale / _pinchScale, details.localFocalPoint);
      _pinchScale = details.scale;
    }
    // focalPointDelta is local to the receiver, which sits inside the
    // zoom transform — list-space pixels, exactly what _grabPanBy takes
    final delta = details.focalPointDelta;
    if (delta != Offset.zero) _grabPanBy(delta);
  }

  void _onPinchEnd(ScaleEndDetails details) => _settleZoomGesture();

  /// Settles a finished zoom gesture into the layout/transform regime
  /// split: total zoom at or below 1 lives in the page layout, above 1
  /// in the InteractiveViewer transform. Shared by touch pinches and
  /// InteractiveViewer's own gesture end.
  void _settleZoomGesture() {
    final total = _transform.value.getMaxScaleOnAxis() * _layoutZoom;
    if (total <= 1) {
      _transform.value = Matrix4.identity();
      _setLayoutZoom(total);
    } else if (_layoutZoom < 1) {
      // fold the layout factor into the transform zoom
      final fold = _layoutZoom;
      _setLayoutZoom(1);
      final matrix = _transform.value.clone()
        ..translateByDouble(_viewWidth / 2, _viewHeight / 2, 0, 1)
        ..scaleByDouble(fold, fold, fold, 1)
        ..translateByDouble(-_viewWidth / 2, -_viewHeight / 2, 0, 1);
      _transform.value = _clampedTransform(matrix);
    } else {
      _transform.value = _clampedTransform(_transform.value.clone());
    }
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
  }

  // --- trackpad gestures ---
  //
  // A dedicated recognizer owns every trackpad pan-zoom gesture (see
  // _TrackpadPanRecognizer): vertical deltas scroll the list 1:1 with the
  // fingers on screen (spilling into the zoom window's translation at the
  // scroll extents, so the document's ends stay reachable while zoomed),
  // horizontal deltas pan the zoom window, and pinch zooms around the
  // gesture's focal point. Lifting off feeds vertical velocity back through
  // the same direct pan path as live scrolling; the list's ScrollPhysics may
  // be disabled while editing, but trackpad momentum should still continue.

  void _onTrackpadPanZoomStart(PointerPanZoomStartEvent event) {
    _panFlinger.stop();
    _touchFlinger.stop();
    _trackpadScale = 1;
    _trackpadIntent = _TrackpadIntent.undecided;
    _trackpadPendingPan = Offset.zero;
    _trackpadVelocity = VelocityTracker.withKind(PointerDeviceKind.trackpad);
  }

  void _onTrackpadPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    _trackpadVelocity?.addPosition(event.timeStamp, event.pan);

    // macOS delivers magnification and scrolling through the same gesture
    // stream, and a magnify gesture reports the fingers' drift as pan
    // deltas — applying both made every pinch also scroll. The first
    // intent to cross its threshold claims the whole gesture; until then
    // motion accumulates unapplied (and is paid back in one piece when
    // scrolling latches, so nothing is lost to the dead zone).
    var delta = event.panDelta;
    if (_trackpadIntent == _TrackpadIntent.undecided) {
      _trackpadPendingPan += delta;
      // a draw tool armed: never latch zoom, so a pinch can't scale the
      // page mid-stroke — two-finger motion only scrolls
      if ((event.scale - 1).abs() > 0.01 && !_drawToolArmed) {
        _trackpadIntent = _TrackpadIntent.zoom;
      } else if (_trackpadPendingPan.distance > 8) {
        _trackpadIntent = _TrackpadIntent.scroll;
        delta = _trackpadPendingPan;
      } else {
        return;
      }
    }

    if (_trackpadIntent == _TrackpadIntent.zoom) {
      if (event.scale > 0 && event.scale != _trackpadScale) {
        final target = _currentZoom * event.scale / _trackpadScale;
        _trackpadScale = event.scale;
        // pinch zooms around the gesture's start point and may cross the
        // fit-width seam into layout zoom
        _zoomTo(target, event.localPosition);
      }
      return; // a pinch only zooms
    }

    final matrix = _transform.value.clone();
    final scale = matrix.getMaxScaleOnAxis();
    matrix.storage[12] += delta.dx;

    // vertical: scroll the list (deltas are screen pixels; the list lives
    // under the zoom transform). Whatever the extents can't absorb pans
    // the zoom window instead, so the very top and bottom of the document
    // are reachable at any zoom.
    if (_scroll.hasClients && delta.dy != 0) {
      final position = _scroll.position;
      final target = position.pixels - delta.dy / scale;
      final clamped =
          target.clamp(position.minScrollExtent, position.maxScrollExtent);
      if (clamped != position.pixels) position.jumpTo(clamped);
      matrix.storage[13] += (clamped - target) * scale;
    }
    _transform.value = _clampedTransform(matrix);
  }

  void _onTrackpadPanZoomEnd() {
    final velocity =
        _trackpadVelocity?.getVelocity().pixelsPerSecond ?? Offset.zero;
    _trackpadVelocity = null;
    final scale = _transform.value.getMaxScaleOnAxis();
    final zoomed = scale > 1.01;
    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
    // a pinch's lift-off carries no momentum anywhere
    if (_trackpadIntent != _TrackpadIntent.scroll) return;
    // Continue vertical momentum through the same direct path used during
    // the gesture. `goBallistic` is tempting here, but it goes through the
    // list's ScrollPhysics; with an edit tool armed those physics are
    // deliberately NeverScrollable, so a real trackpad fling stops as if it
    // had hit an edge.
    if (_scroll.hasClients && velocity.dy.abs() > kMinFlingVelocity) {
      _flingViewport(Velocity(pixelsPerSecond: Offset(0, velocity.dy / scale)));
    }
    // horizontal momentum continues in the zoom window's translation,
    // with the same friction InteractiveViewer uses for its flings
    if (zoomed && velocity.dx.abs() > kMinFlingVelocity) {
      _panFlinger.animateWith(FrictionSimulation(
          0.0000135, _transform.value.storage[12], velocity.dx));
    }
  }

  /// One frame of the horizontal fling: moves the zoom window's
  /// x-translation along the friction simulation, stopping at the edges.
  void _onPanFlingTick() {
    final matrix = _transform.value.clone();
    final scale = matrix.getMaxScaleOnAxis();
    if (scale <= 1.01) {
      _panFlinger.stop();
      return;
    }
    final min = _viewWidth * (1 - scale);
    final value = _panFlinger.value;
    matrix.storage[12] = value.clamp(min, 0.0);
    _transform.value = matrix;
    if (value <= min || value >= 0) _panFlinger.stop();
  }

  /// Keeps the zoom window over the content: snaps near-1 scales back to
  /// identity (sub-1 zoom is layout zoom, not a transform) and clamps the
  /// translation so no blank edges show.
  Matrix4 _clampedTransform(Matrix4 matrix) {
    final scale = matrix.getMaxScaleOnAxis();
    if (scale <= 1.01) return Matrix4.identity();
    final s = matrix.storage;
    s[12] = s[12].clamp(_viewWidth * (1 - scale), 0.0);
    s[13] = s[13].clamp(_viewHeight * (1 - scale), 0.0);
    return matrix;
  }

  /// Scrollbar motion, in list-space pixels: the scroll extents absorb
  /// what they can and the leftover pans the zoom window — the same
  /// spillover as trackpad scrolling, so the document's very ends stay
  /// reachable from the bar while zoomed in.
  void _scrollbarScrollBy(double delta) {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final target = position.pixels + delta;
    final clamped =
        target.clamp(position.minScrollExtent, position.maxScrollExtent);
    if (clamped != position.pixels) position.jumpTo(clamped);
    final matrix = _transform.value.clone();
    final scale = matrix.getMaxScaleOnAxis();
    if (scale > 1.01) {
      matrix.storage[13] += (clamped - target) * scale;
      _transform.value = _clampedTransform(matrix);
    }
  }

  /// Horizontal scrollbar motion, in list-space pixels. Sideways overflow
  /// exists only inside the zoom window, so this pans the transform.
  void _scrollbarPanBy(double delta) {
    final matrix = _transform.value.clone();
    final scale = matrix.getMaxScaleOnAxis();
    if (scale <= 1.01) return;
    matrix.storage[12] -= delta * scale;
    _transform.value = _clampedTransform(matrix);
  }

  @override
  Widget build(BuildContext context) {
    assert(
        widget.editing == null ||
            identical(widget.editing!.document, widget.document),
        'PdfViewer.editing is set but document is not editing.document. '
        'The editing controller owns the document revisions: rebuild the '
        'viewer with editing.document whenever the controller notifies '
        '(e.g. wrap it in a ListenableBuilder on the controller).');
    final editing = widget.editing;
    final canvasColor = widget.backgroundColor ??
        PdfViewerTheme.of(context).canvasColor ??
        (Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF202124)
            : const Color(0xFF404347));
    // the rubber-band marquee's chrome, matching the editing overlay's
    final marqueeColor =
        PdfViewerTheme.of(context).annotationChromeColor ??
            const Color(0xFF1E88E5);
    return LayoutBuilder(builder: (context, constraints) {
      // _viewWidth still holds the previous layout's width here; a change
      // rescales every page, so pin the reading position before adopting it
      // (skips the very first layout, where there is nothing to preserve).
      if (_viewWidth > 0 &&
          constraints.maxWidth != _viewWidth &&
          _scroll.hasClients &&
          _pages.isNotEmpty) {
        _preserveReadingAnchor();
      }
      _viewWidth = constraints.maxWidth;
      _viewHeight = constraints.maxHeight;
      if (_viewWidth > 0 && _viewHeight > 0) {
        final pending = _pendingViewport;
        if (pending != null) {
          // a saved viewport (initialViewport or restoreViewport) wins
          // over the initial fit: set its layout zoom now, then place the
          // scroll/transform once this frame's new extents exist
          _pendingViewport = null;
          _appliedInitialFit = true;
          _layoutZoom = pending.zoom <= 1
              ? pending.zoom.clamp(widget.minZoom, 1.0)
              : 1.0;
          final page =
              _pages.isEmpty ? 0 : pending.page.clamp(0, _pages.length - 1);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _scroll.hasClients) _placeViewport(pending, page);
          });
        } else if (!_appliedInitialFit) {
          _appliedInitialFit = true;
          _layoutZoom =
              widget.initialFit == PdfViewerFit.page && _aspects.isNotEmpty
                  ? (_viewHeight / (_viewWidth * _aspects.first))
                      .clamp(widget.minZoom, 1.0)
                  : 1.0;
        }
      }
      // no implicit desktop scrollbar: it would attach here, inside the
      // zoom transform — thin, low-contrast, and scaled or translated out
      // of view when zoomed. The viewer paints its own bar outside the
      // transform instead (_PdfScrollbar below).
      final list = ExactExtentListView.builder(
        controller: _scroll,
        // with a tool armed, touch drags belong to the editing overlay —
        // the list's drag recognizer would win vertical-ish strokes in
        // the arena otherwise. Desktop trackpad gestures are unaffected
        // (_onTrackpadPanZoomUpdate drives the position directly); wheel
        // events — including web trackpad pans, which arrive as wheel —
        // are refused by these physics and handled by _onPointerSignal.
        physics:
            editing?.tool != null ? const NeverScrollableScrollPhysics() : null,
        // every page's extent is known up front, so give the sliver exact
        // geometry instead of letting it estimate from built children —
        // estimates drift on long mixed-size documents, landing jumps
        // (search, links, page navigation) off target. ExactExtentListView
        // additionally makes maxScrollExtent the exact total: the stock
        // sliver still ESTIMATES it from the built children's average, which
        // oscillates on mixed-size documents and made the scrollbar thumb
        // jump (AMT-SP-101: 93k↔162k px between frames).
        itemExtentBuilder: (index, dimensions) => index >= _pages.length
            ? null
            : _pageHeight(index) + (index == 0 ? 0 : widget.pageSpacing),
        itemCount: _pages.length,
        padding: EdgeInsets.only(bottom: widget.pageSpacing),
        itemBuilder: (context, index) => Padding(
          padding: EdgeInsets.only(top: index == 0 ? 0 : widget.pageSpacing),
          // zoomed out, each page lays out at a fraction of the viewport
          // width, centered — more of the document on screen at once
          child: Center(
            child: FractionallySizedBox(
              widthFactor: _layoutZoom,
              child: _PdfViewerPage(
                page: _pages[index],
                index: index,
                pageColor: widget.pageColor,
                showAnnotations: widget.showAnnotations,
                formFields: widget.highlightFormFields && widget.showAnnotations
                    ? _formFieldRects(index)
                    : const [],
                interactiveForms:
                    widget.interactiveForms && widget.showAnnotations,
                scale: _renderScale,
                settleGeneration: _settleGeneration,
                matches: _controller._matchesOn(index),
                currentMatch: _controller._currentMatch >= 0
                    ? _controller._matches[_controller._currentMatch]
                    : null,
                selection: _selectionQuadsOn(index),
                textSelection: _textSelectionOn(index),
                overlayBuilder: widget.pageOverlayBuilder,
                editing: editing,
                formController: editing ?? widget.formController,
                editingTextPrompt:
                    widget.editingTextPrompt ?? showPdfTextPrompt,
                formImagePicker: widget.formImagePicker,
                imagePicker: widget.imagePicker,
                onSnapshot: widget.onSnapshot,
                onPanViewport: _grabPanBy,
                onPanViewportEnd: _flingViewport,
                onShowAnnotationMenu: _showSelectionMenu,
                onShowFormFieldMenu: _showFormFieldMenu,
                onResolvePagePoint: _resolvePagePointGlobal,
                onMoveDragPreview: _onMoveDragPreview,
                crossPageGhost: _crossPageGhostFor(index),
                transformScale: _transformScale,
                renderScheduler: _renderScheduler,
                previewCache: widget.pagePreviews ? _previews : null,
                renderWorker: widget.renderWorker,
                predictStrokes: widget.predictStrokes,
              ),
            ),
          ),
        ),
      );
      final scrollable = ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: list,
      );
      return CallbackShortcuts(
        // while an in-place text editor is open every key belongs to it:
        // backspace deletes characters (not the annotation), ⌘C copies
        // field text, Escape is the editor's own cancel
        bindings: editing?.isEditingText ?? false
            ? const {}
            : {
                const SingleActivator(LogicalKeyboardKey.keyC, meta: true):
                    _onCopy,
                const SingleActivator(LogicalKeyboardKey.keyC, control: true):
                    _onCopy,
                const SingleActivator(LogicalKeyboardKey.keyA, meta: true):
                    _onSelectAll,
                const SingleActivator(LogicalKeyboardKey.keyA, control: true):
                    _onSelectAll,
                const SingleActivator(LogicalKeyboardKey.escape): _onEscape,
                if (editing != null) ...{
                  const SingleActivator(LogicalKeyboardKey.keyZ, meta: true):
                      editing.undo,
                  const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
                      editing.undo,
                  const SingleActivator(LogicalKeyboardKey.keyZ,
                      meta: true, shift: true): editing.redo,
                  const SingleActivator(LogicalKeyboardKey.keyZ,
                      control: true, shift: true): editing.redo,
                  const SingleActivator(LogicalKeyboardKey.keyY, control: true):
                      editing.redo,
                  const SingleActivator(LogicalKeyboardKey.keyX, meta: true):
                      _onCut,
                  const SingleActivator(LogicalKeyboardKey.keyX, control: true):
                      _onCut,
                  const SingleActivator(LogicalKeyboardKey.keyV, meta: true):
                      _onPaste,
                  const SingleActivator(LogicalKeyboardKey.keyV, control: true):
                      _onPaste,
                  const SingleActivator(LogicalKeyboardKey.delete):
                      editing.deleteSelected,
                  const SingleActivator(LogicalKeyboardKey.backspace):
                      editing.deleteSelected,
                  // unmodified single-key tool shortcuts (V select, P pen,
                  // R rectangle, …) — safe because an open in-place text
                  // editor disables every binding above
                  for (final entry in pdfEditToolShortcuts.entries)
                    SingleActivator(entry.value): () => _armTool(entry.key),
                },
              },
        child: Focus(
          focusNode: _focusNode,
          child: RawGestureDetector(
            gestures: <Type, GestureRecognizerFactory>{
              // touch/stylus only: a double-tap recognizer that accepted
              // mice would hold every click in the gesture arena for the
              // disambiguation timeout and steal the second of two rapid
              // clicks — links and overlay buttons would feel dead
              DoubleTapGestureRecognizer: GestureRecognizerFactoryWithHandlers<
                  DoubleTapGestureRecognizer>(
                () => DoubleTapGestureRecognizer(
                  debugOwner: this,
                  supportedDevices: const {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.stylus,
                  },
                ),
                (recognizer) => recognizer
                  ..onDoubleTapDown = ((details) => _doubleTapDetails = details)
                  ..onDoubleTap = _onDoubleTap,
              ),
            },
            child: ColoredBox(
              // the canvas color behind the page: visible as margins when
              // zoomed out past fit-width
              color: canvasColor,
              child: Stack(children: [
                InteractiveViewer(
                  transformationController: _transform,
                  maxScale: widget.maxZoom,
                  // wheel zoom is handled in _onPointerSignal; e^(-dy/∞) = 1
                  // disables InteractiveViewer's own (modifier-blind) version
                  scaleFactor: double.maxFinite,
                  // a draw tool armed: stand IV's scale handling down so a
                  // stray trackpad pinch (a PointerScaleEvent on the web,
                  // which scaleFactor does NOT neutralize) can't zoom the
                  // page out from under a stroke. Touch pinch still zooms
                  // through _EagerPinchRecognizer, not IV.
                  scaleEnabled: !_drawToolArmed,
                  minScale: widget.minZoom,
                  // scaling below "cover" needs a free boundary; our own
                  // clamping replaces InteractiveViewer's (live for wheel and
                  // trackpad, on gesture end for touch)
                  boundaryMargin: const EdgeInsets.all(double.infinity),
                  // vertical drags scroll the list; horizontal panning engages
                  // once zoomed in
                  panEnabled: _zoomed,
                  // touch pinches that InteractiveViewer still wins run on
                  // the transform mid-gesture; settle them the same way as
                  // the eager pinch recognizer's
                  onInteractionEnd: (_) => _settleZoomGesture(),
                  // all trackpad pan-zoom gestures are handled here, never by
                  // the list's drag recognizer (whose iOS-style velocity
                  // tracker asserts on macOS trackpad timestamps) nor by
                  // InteractiveViewer (which would pan only within the zoom
                  // window). Innermost recognizers win the arena, and this one
                  // accepts eagerly.
                  child: RawGestureDetector(
                    gestures: <Type, GestureRecognizerFactory>{
                      _TrackpadPanRecognizer:
                          GestureRecognizerFactoryWithHandlers<
                              _TrackpadPanRecognizer>(
                        () => _TrackpadPanRecognizer(debugOwner: this),
                        (recognizer) => recognizer
                          ..onStart = _onTrackpadPanZoomStart
                          ..onUpdate = _onTrackpadPanZoomUpdate
                          ..onEnd = _onTrackpadPanZoomEnd,
                      ),
                      // touch pinch zoom: passive for single touches,
                      // claims the gesture when a second finger lands
                      _EagerPinchRecognizer:
                          GestureRecognizerFactoryWithHandlers<
                              _EagerPinchRecognizer>(
                        () => _EagerPinchRecognizer(debugOwner: this),
                        (recognizer) => recognizer
                          ..onStart = _onPinchStart
                          ..onUpdate = _onPinchUpdate
                          ..onEnd = _onPinchEnd,
                      ),
                    },
                    // plain wheel events the list can't use (at its extents)
                    // must not fall through to InteractiveViewer's wheel-zoom
                    child: Listener(
                      onPointerSignal: _onPointerSignal,
                      // selection drags: scroll wheels and touch scrolling go to
                      // the list (its drag recognizers win the arena for touch);
                      // mouse drags fall through to this detector
                      child: MouseRegion(
                        cursor: _hoverCursor,
                        onHover: _onHover,
                        onExit: (_) {
                          if (_hoverCursor != MouseCursor.defer) {
                            setState(() => _hoverCursor = MouseCursor.defer);
                          }
                        },
                        child: Listener(
                          onPointerDown: _onPointerDown,
                          onPointerUp: _onPointerUp,
                          child: GestureDetector(
                            onTapUp: _onTapUp,
                            onSecondaryTapUp: _onSecondaryTapUp,
                            child: RawGestureDetector(
                              gestures: <Type, GestureRecognizerFactory>{
                                // drag selection is mouse-only: touch and
                                // stylus drags always scroll (a pan
                                // recognizer that accepted touch claimed
                                // any swipe with a horizontal component
                                // before the list's vertical drag could,
                                // and the swipe selected text instead of
                                // scrolling)
                                PanGestureRecognizer:
                                    GestureRecognizerFactoryWithHandlers<
                                        PanGestureRecognizer>(
                                  () => PanGestureRecognizer(
                                    debugOwner: this,
                                    supportedDevices: const {
                                      PointerDeviceKind.mouse,
                                      PointerDeviceKind.trackpad,
                                    },
                                  ),
                                  (recognizer) => recognizer
                                    ..onStart = _onSelectionStart
                                    ..onUpdate = _onSelectionUpdate
                                    ..onEnd = _onSelectionEnd
                                    ..onCancel =
                                        () => _onSelectionEnd(DragEndDetails()),
                                ),
                                // touch text selection starts with a long
                                // press instead; stands aside while an
                                // editing tool owns touch gestures
                                _SelectionLongPressRecognizer:
                                    GestureRecognizerFactoryWithHandlers<
                                        _SelectionLongPressRecognizer>(
                                  () => _SelectionLongPressRecognizer(
                                      debugOwner: this),
                                  (recognizer) => recognizer
                                    ..isEnabled = (() =>
                                        widget.editing?.tool == null &&
                                        widget.editing?.isPickingColor != true)
                                    ..onLongPressStart = _onLongPressStart
                                    ..onLongPressMoveUpdate = _onLongPressMove
                                    ..onLongPressEnd =
                                        ((_) => _onLongPressEnd())
                                    ..onLongPressCancel = _onLongPressEnd,
                                ),
                              },
                              child: ColoredBox(
                                key: _listSpaceKey,
                                color: canvasColor,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    // with ctrl/cmd held the list stops claiming
                                    // wheel events, so they reach the
                                    // InteractiveViewer, which zooms around the
                                    // pointer
                                    IgnorePointer(
                                      ignoring: _zoomModifierDown,
                                      child: scrollable,
                                    ),
                                    // the Shift+drag marquee, drawn in this
                                    // (list) space so it tracks the gesture and
                                    // scales with the zoom transform
                                    if (_marqueeStart != null &&
                                        _marqueeCurrent != null)
                                      Positioned.fill(
                                        child: IgnorePointer(
                                          child: CustomPaint(
                                            painter: _MarqueePainter(
                                              Rect.fromPoints(_marqueeStart!,
                                                  _marqueeCurrent!),
                                              marqueeColor,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // outside the zoom transform, so they keep their place
                // and size at any zoom
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: 0,
                  child: PdfScrollbar(
                    axis: Axis.vertical,
                    scroll: _scroll,
                    transform: _transform,
                    minOverflow: widget.pageSpacing,
                    onScrollBy: _scrollbarScrollBy,
                    thumbKey: const ValueKey('pdf-scrollbar-thumb'),
                  ),
                ),
                // appears only while zoomed in (the only sideways
                // overflow); inset so the corner stays the vertical bar's
                Positioned(
                  left: 0,
                  right: PdfScrollbar.hitExtent,
                  bottom: 0,
                  child: PdfScrollbar(
                    axis: Axis.horizontal,
                    transform: _transform,
                    viewExtent: _viewWidth,
                    onScrollBy: _scrollbarPanBy,
                    thumbKey: const ValueKey('pdf-hscrollbar-thumb'),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );
    });
  }
}

/// Paints the Shift+drag rubber-band marquee (a translucent fill with a
/// hairline border), in list space so the zoom transform scales it.
class _MarqueePainter extends CustomPainter {
  const _MarqueePainter(this.rect, this.color);

  final Rect rect;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(rect, Paint()..color = color.withAlpha(0x14));
    canvas.drawRect(
      rect,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_MarqueePainter oldDelegate) =>
      oldDelegate.rect != rect || oldDelegate.color != color;
}

/// Paints the slice of a cross-page move ghost that lands on a page, in
/// that page's own view space (from/to already mapped there). It sits in
/// the page's overlay Stack, so it paints over the page raster and is
/// clipped to the page — the same per-page render path the in-page ghost
/// uses, so a drag onto a neighbour page shows there.
class _MoveDragPreviewPainter extends CustomPainter {
  const _MoveDragPreviewPainter(this.preview);

  final PdfMoveDragPreview preview;

  @override
  void paint(Canvas canvas, Size size) =>
      paintMoveDragPreview(canvas, preview, Offset.zero);

  @override
  bool shouldRepaint(_MoveDragPreviewPainter oldDelegate) =>
      oldDelegate.preview != preview;
}

class _PdfViewerPage extends StatefulWidget {
  const _PdfViewerPage({
    required this.page,
    required this.index,
    required this.pageColor,
    required this.showAnnotations,
    required this.formFields,
    required this.interactiveForms,
    required this.scale,
    required this.settleGeneration,
    required this.matches,
    required this.currentMatch,
    required this.selection,
    required this.textSelection,
    required this.overlayBuilder,
    required this.editing,
    required this.formController,
    required this.editingTextPrompt,
    required this.formImagePicker,
    required this.imagePicker,
    required this.onSnapshot,
    required this.onPanViewport,
    required this.onPanViewportEnd,
    required this.onShowAnnotationMenu,
    required this.onShowFormFieldMenu,
    required this.onResolvePagePoint,
    required this.onMoveDragPreview,
    required this.crossPageGhost,
    required this.transformScale,
    required this.renderScheduler,
    required this.previewCache,
    required this.renderWorker,
    required this.predictStrokes,
  });

  final PdfPage page;
  final int index;
  final Color pageColor;
  final bool showAnnotations;

  /// Visible form-field widget rects, washed by the field highlight.
  /// Empty when the highlight is off (or annotations are hidden).
  final List<PdfRect> formFields;

  /// Whether the interactive form-fill layer is mounted (see
  /// [PdfViewer.interactiveForms]); needs [editing] and [showAnnotations].
  final bool interactiveForms;

  final double scale;
  final int settleGeneration;
  final List<PdfTextMatch> matches;
  final PdfTextMatch? currentMatch;
  final List<PdfTextQuad> selection;

  /// Touch selection chrome on this page (handles and the copy chip);
  /// null when the page shows none.
  final _PageTextSelection? textSelection;

  final PdfPageOverlayBuilder? overlayBuilder;
  final PdfEditingController? editing;

  /// The controller driving interactive form fill — [editing] in the
  /// editor, or a standalone session in the read-only reader (so forms
  /// fill without enabling annotation editing). Null disables it.
  final PdfEditingController? formController;

  final PdfTextPrompt editingTextPrompt;
  final PdfFormImagePicker? formImagePicker;
  final PdfImagePicker? imagePicker;

  /// See [EditingPageOverlay.onSnapshot].
  final PdfSnapshotHandler? onSnapshot;
  final void Function(Offset delta) onPanViewport;

  /// See [EditingPageOverlay.onPanViewportEnd].
  final void Function(Velocity velocity) onPanViewportEnd;

  /// See [EditingPageOverlay.onShowAnnotationMenu].
  final void Function(Offset globalPosition, int pageIndex,
      {(double, double)? pagePoint}) onShowAnnotationMenu;

  /// See [EditingPageOverlay.onShowFormFieldMenu].
  final void Function(Offset globalPosition, String fieldName)
      onShowFormFieldMenu;

  /// See [EditingPageOverlay.onResolvePagePoint].
  final (int, double, double)? Function(Offset globalPosition)
      onResolvePagePoint;

  /// See [EditingPageOverlay.onMoveDragPreview].
  final PdfMoveDragPreviewCallback onMoveDragPreview;

  /// The slice of an in-flight cross-page move ghost that lands on this
  /// page (from/to in this page's own view space), so it draws the part of
  /// the dragged annotation hanging onto it over its own raster. Null when
  /// nothing is dragging onto this page. See [_PdfViewerState._crossPageGhostFor].
  final PdfMoveDragPreview? crossPageGhost;

  /// The viewer transform's scale — the editing overlay's chrome divides
  /// by it to stay constant-size on screen while zoomed.
  final ValueListenable<double> transformScale;

  /// See [PdfPageView.renderScheduler].
  final PdfPageRenderScheduler renderScheduler;

  /// See [PdfPageView.previewCache]; null when previews are off.
  final PdfPagePreviewCache? previewCache;

  /// See [PdfPageView.renderWorker]; null when interpretation runs on-thread.
  final PdfRenderWorker? renderWorker;

  /// See [PdfViewer.predictStrokes].
  final bool predictStrokes;

  @override
  State<_PdfViewerPage> createState() => _PdfViewerPageState();
}

class _PdfViewerPageState extends State<_PdfViewerPage> {
  /// Whether the on-screen raster shows the current [widget.page] (this
  /// revision). False from the moment an edit swaps the document until
  /// PdfPageView's new render lands — the window the editing overlay
  /// keeps its just-committed preview painted over.
  bool _rastered = false;

  @override
  void didUpdateWidget(_PdfViewerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.page, widget.page)) _rastered = false;
  }

  void _onRasterReady() {
    if (_rastered || !mounted) return;
    setState(() => _rastered = true);
  }

  @override
  Widget build(BuildContext context) {
    // the Stack is always present — toggling it when highlights appear
    // would reshape the element tree and recreate PdfPageView's state
    // (dropping its rendered image: a white flash)
    final builder = widget.overlayBuilder;
    final editing = widget.editing;
    final formController = widget.formController;
    final textSelection = widget.textSelection;
    return Stack(children: [
      PdfPageView(
        page: widget.page,
        scale: widget.scale,
        settleGeneration: widget.settleGeneration,
        pageColor: widget.pageColor,
        showAnnotations: widget.showAnnotations,
        onRasterReady: _onRasterReady,
        renderScheduler: widget.renderScheduler,
        previewCache: widget.previewCache,
        renderWorker: widget.renderWorker,
        previewIndex: widget.index,
      ),
      // the field highlight sits under text highlights and overlays:
      // it marks where fields are, everything else paints over it
      if (widget.formFields.isNotEmpty)
        Positioned.fill(
          child: CustomPaint(
            painter: _FormFieldPainter(
              box: widget.page.cropBox,
              rotation: widget.page.rotation,
              fields: widget.formFields,
              theme: PdfViewerTheme.of(context),
            ),
          ),
        ),
      Positioned.fill(
        child: CustomPaint(
          painter: _HighlightPainter(
            box: widget.page.cropBox,
            rotation: widget.page.rotation,
            matches: widget.matches,
            currentMatch: widget.currentMatch,
            selection: widget.selection,
            theme: PdfViewerTheme.of(context),
          ),
        ),
      ),
      // the slice of a cross-page move ghost landing on this page: drawn
      // over the raster, clipped to the page by the Stack, so a drag onto
      // this page from a neighbour shows here instead of vanishing behind
      if (widget.crossPageGhost case final ghost?)
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _MoveDragPreviewPainter(ghost)),
          ),
        ),
      if (builder != null ||
          editing != null ||
          (formController != null && widget.interactiveForms) ||
          textSelection != null)
        Positioned.fill(
          child: LayoutBuilder(builder: (context, constraints) {
            final geometry = PdfPageGeometry(
              cropBox: widget.page.cropBox,
              rotation: widget.page.rotation,
              viewSize: constraints.biggest,
            );
            return Stack(children: [
              if (builder != null) ...builder(context, widget.index, geometry),
              // the editing layer sits topmost so an armed tool's
              // gestures win over app overlays underneath
              if (editing != null)
                ListenableBuilder(
                  listenable: editing,
                  // mounted for an armed tool, the eyedropper, a
                  // default-mode (mouse click) annotation selection, or
                  // a pending attention flash (the sidebar's zoom-to —
                  // links and form fields flash without a selection)
                  builder: (context, _) => editing.tool == null &&
                          !editing.isPickingColor &&
                          !editing.hasAnnotationSelection &&
                          editing.pendingFlash == null
                      ? const SizedBox.shrink()
                      : Positioned.fill(
                          child: ValueListenableBuilder<double>(
                            valueListenable: widget.transformScale,
                            builder: (context, zoom, _) => EditingPageOverlay(
                              controller: editing,
                              pageIndex: widget.index,
                              geometry: geometry,
                              textPrompt: widget.editingTextPrompt,
                              formImagePicker: widget.formImagePicker,
                              imagePicker: widget.imagePicker,
                              onSnapshot: widget.onSnapshot,
                              pageColor: widget.pageColor,
                              showAnnotations: widget.showAnnotations,
                              onPanViewport: widget.onPanViewport,
                              onPanViewportEnd: widget.onPanViewportEnd,
                              onShowAnnotationMenu: widget.onShowAnnotationMenu,
                              onShowFormFieldMenu: widget.onShowFormFieldMenu,
                              onResolvePagePoint: widget.onResolvePagePoint,
                              onMoveDragPreview: widget.onMoveDragPreview,
                              rasterCurrent: _rastered,
                              zoom: zoom,
                              predictStrokes: widget.predictStrokes,
                            ),
                          ),
                        ),
                ),
              // direct form fill: a per-field tap layer in reading /
              // selection modes (the form-authoring tool owns fields
              // itself, drawing tools own the whole page). It sits over
              // the editing overlay so a field tap beats a select-mode
              // marquee, but covers only the field rects. The reader
              // drives this without an [editing] controller, so it never
              // enables annotation move/resize.
              if (formController != null && widget.interactiveForms)
                Positioned.fill(
                  child: ListenableBuilder(
                    listenable: formController,
                    builder: (context, _) {
                      final tool = editing?.tool;
                      final active = editing == null ||
                          tool == null ||
                          tool == PdfEditTool.select;
                      return active
                          ? FormInteractionLayer(
                              controller: formController,
                              pageIndex: widget.index,
                              geometry: geometry,
                              pageColor: widget.pageColor,
                              rasterCurrent: _rastered,
                              formImagePicker: widget.formImagePicker,
                            )
                          : const SizedBox.shrink();
                    },
                  ),
                ),
              // touch text selection chrome rides topmost — it only
              // shows in reader mode (tool disarmed), so it never
              // competes with an armed tool's gestures
              if (textSelection != null)
                Positioned.fill(
                  child: ValueListenableBuilder<double>(
                    valueListenable: widget.transformScale,
                    builder: (context, zoom, _) => _TextSelectionChrome(
                      geometry: geometry,
                      selection: textSelection,
                      zoom: zoom,
                    ),
                  ),
                ),
            ]);
          }),
        ),
    ]);
  }
}

/// Washes every visible form-field widget with a translucent tint and a
/// hairline border so fields read at a glance ([PdfViewer.
/// highlightFormFields] — most fields are invisible until focused).
class _FormFieldPainter extends CustomPainter {
  _FormFieldPainter({
    required this.box,
    required this.rotation,
    required this.fields,
    required this.theme,
  });

  final PdfRect box;
  final int rotation;
  final List<PdfRect> fields;
  final PdfViewerThemeData theme;

  @override
  void paint(Canvas canvas, Size size) {
    if (box.width <= 0 || box.height <= 0) return;
    final geometry =
        PdfPageGeometry(cropBox: box, rotation: rotation, viewSize: size);
    final fill = theme.formFieldHighlightColor ?? const Color(0x2E4D90FE);
    final fillPaint = Paint()..color = fill;
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = fill.withValues(alpha: (fill.a * 2.5).clamp(0.0, 1.0));
    for (final field in fields) {
      final rect = geometry.toViewRect(field);
      canvas.drawRect(rect, fillPaint);
      canvas.drawRect(rect.deflate(0.5), borderPaint);
    }
  }

  @override
  bool shouldRepaint(_FormFieldPainter oldDelegate) =>
      oldDelegate.fields != fields ||
      oldDelegate.rotation != rotation ||
      oldDelegate.theme != theme;
}

class _HighlightPainter extends CustomPainter {
  _HighlightPainter({
    required this.box,
    required this.rotation,
    required this.matches,
    required this.currentMatch,
    required this.selection,
    required this.theme,
  });

  final PdfRect box;
  final int rotation;
  final List<PdfTextMatch> matches;
  final PdfTextMatch? currentMatch;
  final List<PdfTextQuad> selection;
  final PdfViewerThemeData theme;

  @override
  void paint(Canvas canvas, Size size) {
    if (box.width <= 0 || box.height <= 0) return;
    final geometry =
        PdfPageGeometry(cropBox: box, rotation: rotation, viewSize: size);
    final selected = Paint()
      ..color = theme.selectionColor ?? const Color(0x4D2196F3);
    for (final quad in selection) {
      _paintQuad(canvas, geometry, quad, selected);
    }
    final normal = Paint()
      ..color = theme.searchMatchColor ?? const Color(0x66FFEB3B);
    final current = Paint()
      ..color = theme.currentSearchMatchColor ?? const Color(0x88FF9800);
    for (final match in matches) {
      final paint = identical(match, currentMatch) ? current : normal;
      for (final quad in match.quads) {
        _paintQuad(canvas, geometry, quad, paint);
      }
    }
  }

  /// Maps the quad's four page-space corners into view space and fills the
  /// resulting (possibly rotated) polygon, so highlights follow rotated
  /// text instead of being axis-aligned boxes.
  void _paintQuad(
      Canvas canvas, PdfPageGeometry geometry, PdfTextQuad quad, Paint paint) {
    final points = [
      for (final (x, y) in quad.corners) geometry.toViewOffset(x, y),
    ];
    canvas.drawPath(Path()..addPolygon(points, true), paint);
  }

  @override
  bool shouldRepaint(_HighlightPainter oldDelegate) =>
      oldDelegate.matches != matches ||
      oldDelegate.currentMatch != currentMatch ||
      oldDelegate.selection != selection ||
      oldDelegate.theme != theme;
}

/// Drives the touch fling controller: the controller's value is elapsed
/// time, and the tick handler samples both axes' friction simulations at
/// it (an AnimationController carries one double; the fling needs two).
class _FlingClock extends Simulation {
  _FlingClock(this.horizontal, this.vertical);

  final Simulation horizontal;
  final Simulation vertical;

  @override
  double x(double time) => time;

  @override
  double dx(double time) => 1;

  @override
  bool isDone(double time) => horizontal.isDone(time) && vertical.isDone(time);
}

/// What a trackpad pan-zoom gesture is doing. Decided once per gesture:
/// a pinch only zooms (the fingers' drift is not a scroll) and a scroll
/// never zooms.
enum _TrackpadIntent { undecided, scroll, zoom }

/// The mouse right-click text menu's actions.
enum _TextMenuAction { copy, selectAll }

/// Claims every trackpad pan-zoom gesture, eagerly. The viewer drives
/// scrolling, zoom-window panning, and pinch zoom itself: leaving these
/// gestures to the list's drag recognizer trips the iOS-style velocity
/// tracker's timestamp assert on macOS, and leaving them to
/// InteractiveViewer pans only within the zoom window's bounds, so
/// two-finger scrolling could never move through the document.
class _TrackpadPanRecognizer extends OneSequenceGestureRecognizer {
  _TrackpadPanRecognizer({super.debugOwner})
      : super(supportedDevices: {PointerDeviceKind.trackpad});

  void Function(PointerPanZoomStartEvent event)? onStart;
  void Function(PointerPanZoomUpdateEvent event)? onUpdate;
  VoidCallback? onEnd;

  @override
  void addAllowedPointerPanZoom(PointerPanZoomStartEvent event) {
    startTrackingPointer(event.pointer, event.transform);
    resolve(GestureDisposition.accepted);
    onStart?.call(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerPanZoomUpdateEvent) {
      onUpdate?.call(event);
    } else if (event is PointerPanZoomEndEvent) {
      onEnd?.call();
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'trackpad pan';
}

/// Touch pinch zoom. The stock arena loses pinches: the list's vertical
/// drag (or, with a tool armed, the editing overlay's pan) accepts one
/// finger's motion before InteractiveViewer's scale recognizer can claim
/// the pair, so pinching scrolled — or drew — instead of zooming. This
/// recognizer stays passive for single touches (taps, scrolls, and
/// strokes resolve exactly as before) and claims the whole gesture the
/// moment a second touch pointer lands, while both arenas are still
/// open. A second finger that arrives after a drag already won its
/// pointer simply never forms a pinch (the set stays at one).
class _EagerPinchRecognizer extends ScaleGestureRecognizer {
  _EagerPinchRecognizer({super.debugOwner})
      : super(supportedDevices: {PointerDeviceKind.touch});

  final Set<int> _pointers = {};

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    _pointers.add(event.pointer);
    if (_pointers.length == 2) resolve(GestureDisposition.accepted);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _pointers.remove(event.pointer);
    }
    super.handleEvent(event);
  }

  @override
  void rejectGesture(int pointer) {
    _pointers.remove(pointer);
    super.rejectGesture(pointer);
  }

  @override
  String get debugDescription => 'eager pinch';
}

/// Touch text selection: long-press to select. Sits in the same arena
/// as the list's drag recognizers, so once it fires the press can drag
/// to extend without scrolling. Stands down (never enters the arena)
/// while an editing tool is armed — a held finger must not start
/// selecting text under an ink stroke or a shape drag.
class _SelectionLongPressRecognizer extends LongPressGestureRecognizer {
  _SelectionLongPressRecognizer({super.debugOwner})
      : super(supportedDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus,
        });

  bool Function()? isEnabled;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (isEnabled?.call() == false) return;
    super.addAllowedPointer(event);
  }

  @override
  String get debugDescription => 'selection long press';
}

/// A selection handle's drag must beat the list's scroll drag — the
/// handle is a small, explicit target, so claiming the pointer the
/// moment it lands is right.
class _EagerPanRecognizer extends PanGestureRecognizer {
  _EagerPanRecognizer({super.debugOwner});

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }

  @override
  String get debugDescription => 'eager pan';
}

/// What the viewer hands a boundary page of a touch text selection:
/// which handle(s) to show, whether the copy chip rides this page, and
/// the callbacks the chrome drives.
class _PageTextSelection {
  const _PageTextSelection({
    required this.startRect,
    required this.endRect,
    required this.chip,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onCopy,
    required this.onSelectAll,
  });

  /// The selection's first rect on this page (PDF coordinates) when the
  /// selection starts here, else null. Anchors the start handle.
  final PdfRect? startRect;

  /// The selection's last rect when the selection ends here.
  final PdfRect? endRect;

  /// Whether the Copy/Select-All chip shows on this page.
  final bool chip;

  final void Function(bool isStart) onDragStart;
  final void Function(Offset globalPosition) onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onCopy;
  final VoidCallback onSelectAll;
}

/// The touch selection chrome on one page: iOS-style lollipop handles
/// at the selection's ends and a floating Copy/Select-All chip. Painted
/// inside the zoom transform, so everything counter-scales by 1/zoom to
/// stay constant-size on screen.
class _TextSelectionChrome extends StatelessWidget {
  const _TextSelectionChrome({
    required this.geometry,
    required this.selection,
    required this.zoom,
  });

  final PdfPageGeometry geometry;
  final _PageTextSelection selection;
  final double zoom;

  @override
  Widget build(BuildContext context) {
    final s = zoom > 0 ? 1 / zoom : 1.0;
    final theme = PdfViewerTheme.of(context);
    final color = theme.selectionHandleColor ?? const Color(0xFF2196F3);
    final startRect = selection.startRect;
    final endRect = selection.endRect;
    return Stack(children: [
      if (startRect != null)
        _SelectionHandle(
          rect: geometry.toViewRect(startRect),
          isStart: true,
          chromeScale: s,
          color: color,
          onDragStart: selection.onDragStart,
          onDragUpdate: selection.onDragUpdate,
          onDragEnd: selection.onDragEnd,
        ),
      if (endRect != null)
        _SelectionHandle(
          rect: geometry.toViewRect(endRect),
          isStart: false,
          chromeScale: s,
          color: color,
          onDragStart: selection.onDragStart,
          onDragUpdate: selection.onDragUpdate,
          onDragEnd: selection.onDragEnd,
        ),
      if (selection.chip && endRect != null)
        _buildChip(geometry.toViewRect(endRect), s),
    ]);
  }

  Widget _buildChip(Rect anchor, double s) {
    // clear of the end handle's ball below and the start handle's above
    final clearance = 28 * s;
    final above = anchor.top - clearance - 44 * s >= 0;
    final width = geometry.viewSize.width;
    final halfChip = 90.0 * s;
    final position = Offset(
      width <= 2 * halfChip
          ? width / 2
          : anchor.center.dx.clamp(halfChip, width - halfChip),
      above ? anchor.top - clearance : anchor.bottom + clearance,
    );
    return Positioned(
      left: position.dx,
      top: position.dy,
      child: FractionalTranslation(
        translation: Offset(-0.5, above ? -1 : 0),
        child: Transform.scale(
          scale: s,
          alignment: above ? Alignment.bottomCenter : Alignment.topCenter,
          child: Material(
            key: const ValueKey('pdf-text-selection-chip'),
            elevation: 3,
            borderRadius: BorderRadius.circular(22),
            clipBehavior: Clip.antiAlias,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              TextButton(
                key: const ValueKey('pdf-text-selection-chip-copy'),
                onPressed: selection.onCopy,
                child: const Text('Copy'),
              ),
              const SizedBox(height: 24, child: VerticalDivider(width: 1)),
              TextButton(
                key: const ValueKey('pdf-text-selection-chip-select-all'),
                onPressed: selection.onSelectAll,
                child: const Text('Select all'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// One lollipop: a ball above the selection start (or below the end)
/// with a stem spanning the line height. The hit area is finger-sized;
/// the drag claims the pointer immediately so the list can't scroll it
/// away.
class _SelectionHandle extends StatelessWidget {
  const _SelectionHandle({
    required this.rect,
    required this.isStart,
    required this.chromeScale,
    required this.color,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  /// The boundary selection rect, view coordinates.
  final Rect rect;
  final bool isStart;
  final double chromeScale;
  final Color color;
  final void Function(bool isStart) onDragStart;
  final void Function(Offset globalPosition) onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    final s = chromeScale;
    final ballSpace = 16 * s; // ball diameter + gap, above or below
    final hitWidth = 36 * s;
    final x = isStart ? rect.left : rect.right;
    return Positioned(
      left: x - hitWidth / 2,
      top: isStart ? rect.top - ballSpace : rect.top,
      width: hitWidth,
      height: rect.height + ballSpace,
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: <Type, GestureRecognizerFactory>{
          _EagerPanRecognizer:
              GestureRecognizerFactoryWithHandlers<_EagerPanRecognizer>(
            () => _EagerPanRecognizer(debugOwner: this),
            (recognizer) => recognizer
              ..onStart = ((_) => onDragStart(isStart))
              ..onUpdate = ((details) => onDragUpdate(details.globalPosition))
              ..onEnd = ((_) => onDragEnd())
              ..onCancel = onDragEnd,
          ),
        },
        child: CustomPaint(
          key: ValueKey(
              isStart ? 'pdf-text-handle-start' : 'pdf-text-handle-end'),
          painter: _SelectionHandlePainter(
            isStart: isStart,
            ballSpace: ballSpace,
            ballRadius: 7 * s,
            stemWidth: 2.2 * s,
            color: color,
          ),
        ),
      ),
    );
  }
}

class _SelectionHandlePainter extends CustomPainter {
  _SelectionHandlePainter({
    required this.isStart,
    required this.ballSpace,
    required this.ballRadius,
    required this.stemWidth,
    required this.color,
  });

  final bool isStart;
  final double ballSpace;
  final double ballRadius;
  final double stemWidth;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final cx = size.width / 2;
    if (isStart) {
      canvas.drawCircle(Offset(cx, ballSpace - ballRadius), ballRadius, paint);
      canvas.drawRect(
          Rect.fromLTRB(cx - stemWidth / 2, ballSpace - ballRadius,
              cx + stemWidth / 2, size.height),
          paint);
    } else {
      canvas.drawCircle(
          Offset(cx, size.height - ballSpace + ballRadius), ballRadius, paint);
      canvas.drawRect(
          Rect.fromLTRB(cx - stemWidth / 2, 0, cx + stemWidth / 2,
              size.height - ballSpace + ballRadius),
          paint);
    }
  }

  @override
  bool shouldRepaint(_SelectionHandlePainter oldDelegate) =>
      oldDelegate.isStart != isStart ||
      oldDelegate.ballSpace != ballSpace ||
      oldDelegate.ballRadius != ballRadius ||
      oldDelegate.stemWidth != stemWidth ||
      oldDelegate.color != color;
}
