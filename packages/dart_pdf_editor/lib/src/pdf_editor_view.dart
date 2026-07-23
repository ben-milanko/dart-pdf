import 'package:flutter/foundation.dart' show defaultTargetPlatform, mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

import 'editing/editing_bookmarks.dart';
import 'editing/editing_controller.dart';
import 'editing/editing_menu.dart';
import 'editing/editing_panel.dart';
import 'editing/editing_pencil.dart';
import 'editing/editing_preferences.dart';
import 'editing/editing_properties.dart';
import 'editing/editing_sidebar.dart';
import 'editing/editing_stamps.dart';
import 'editing/editing_thumbnails.dart';
import 'editing/editing_toolbar.dart';
import 'editing/text_prompt.dart';
import 'editing/text_style_prompt.dart';
import 'editing/tool_shortcuts.dart';
import 'l10n/pdf_l10n.dart';
import 'page_number_field.dart';
import 'performance_policy.dart';
import 'pdf_reflow_view.dart';
import 'pdf_viewer.dart';
import 'progressive_source.dart';
import 'raster_cache.dart';
import 'search_panel.dart';
import 'shell_chrome.dart';
import 'shell_session.dart';
import 'theme.dart';

/// Builds the editing toolbar for [PdfEditorView].
///
/// Hosts can return [PdfEditingToolbar] with their own configuration, wrap it,
/// or replace it entirely with custom Material chrome that drives the supplied
/// [PdfEditingController] and [PdfViewerController]. Returning null hides the
/// toolbar for this build while leaving editing gestures and keyboard shortcuts
/// active.
typedef PdfEditorToolbarBuilder = Widget? Function(
  BuildContext context,
  PdfEditingController controller,
  PdfViewerController viewerController,
);

/// Which pieces of chrome a [PdfEditorView] shows. Everything defaults
/// on; turn features off rather than rebuilding the layout by hand.
class PdfEditorFeatures {
  const PdfEditorFeatures({
    this.headerBar = true,
    this.search = true,
    this.searchResultsPanel = true,
    this.pageNumber = true,
    this.author = true,
    this.authorEditable = true,
    this.viewOptions = true,
    this.reflowView = true,
    this.pageColorEditable = true,
    this.thumbnails = true,
    this.bookmarks = true,
    this.pageEditing = true,
    this.annotationSidebar = true,
    this.propertiesPanel = true,
    this.toolbar = true,
    this.markup = true,
    this.undoRedo = true,
    this.colorControls = true,
    this.styleControls = true,
    this.flatten = true,
    this.colorProcessing = true,
    this.pencilEraserToggle = true,
    this.tools,
    this.toolGroups,
  });

  /// The slim bar above the viewer (search, page number, panel
  /// toggles). With it off, panels still follow the persisted
  /// preferences - they just lose their toggles.
  final bool headerBar;

  /// The search field, the ⌘F/Ctrl+F shortcut, and (with
  /// [searchResultsPanel]) the results panel.
  final bool search;

  /// The dockable search-results panel and its toggle.
  final bool searchResultsPanel;

  /// The editable "page / count" field.
  final bool pageNumber;

  /// The author-name button; the name stamps new annotations' /T.
  final bool author;

  /// Whether the properties panel's "Author" row is shown, letting the
  /// user edit a selected annotation's author. Independent of [author]
  /// (the header button), so a host that sets the author
  /// programmatically can lock it while leaving the button as it likes.
  final bool authorEditable;

  /// The view-options menu: annotation visibility, form-field
  /// highlight, text reflow, and page (paper) color - display settings only.
  final bool viewOptions;

  /// Whether the view-options menu offers "Reflow text". Reflow is a
  /// display-only reading view over the current document revision; while it
  /// is active, canvas-bound editing panels and the editing toolbar are
  /// hidden because there is no page canvas to manipulate.
  final bool reflowView;

  /// Whether the view-options menu offers "Page color…". With it false
  /// the paper color can't be changed from the UI - for hosts that set
  /// the page color from the document programmatically and lock it.
  final bool pageColorEditable;

  /// The page-thumbnail sidebar and its toggle.
  final bool thumbnails;

  /// The PDF bookmarks/outline sidebar and its toggle.
  final bool bookmarks;

  /// Whether the thumbnail strip can reorder (drag) and delete pages.
  final bool pageEditing;

  /// The annotation-list sidebar and its toggle.
  final bool annotationSidebar;

  /// The annotation properties panel and its toggle.
  final bool propertiesPanel;

  /// The bottom editing toolbar.
  final bool toolbar;

  /// The toolbar's text-markup buttons (highlight, underline...).
  final bool markup;

  /// The toolbar's undo/redo buttons (⌘Z works regardless).
  final bool undoRedo;

  /// The toolbar's color controls: the palette swatches, the "More
  /// colors…" picker, the eyedropper, and the text-box fill/border color
  /// rows in the style popup. Split from [styleControls] so a
  /// color-locked session can hide the color changer while keeping
  /// stroke/opacity/font editable - pass `colorControls: false,
  /// styleControls: true`.
  final bool colorControls;

  /// The toolbar's style popup (stroke width, opacity, and font
  /// controls). Independent of [colorControls].
  final bool styleControls;

  /// The toolbar's flatten-annotations button.
  final bool flatten;

  /// The toolbar's "Color processing" action: find and replace page-content
  /// drawing colors across selected pages or the whole document.
  final bool colorProcessing;

  /// Whether the Apple Pencil's hardware double-tap toggles the eraser
  /// (iOS only; a no-op elsewhere, where the gesture doesn't exist). The
  /// shell binds the native gesture via [PdfPencilInteraction]; see
  /// [PdfEditingController.togglePencilEraser].
  final bool pencilEraserToggle;

  /// The tool buttons to offer, null meaning all of them. See
  /// [PdfEditingToolbar.tools].
  final Set<PdfEditTool>? tools;

  /// The tool *types* (dock groups - Select, Markup, Draw, Shapes,
  /// Insert, Measure, Edit) to offer, null meaning all of them. This is
  /// the way to disable a whole tool type at once. See
  /// [PdfEditingToolbar.groups].
  final Set<PdfEditToolGroup>? toolGroups;
}

/// A drop-in PDF editor: the [PdfViewer] with every editing tool wired
/// up - header with search and panel toggles, thumbnail/annotation/
/// properties panels, and the bottom editing toolbar. For a view-only
/// widget, use [PdfReader].
///
/// ```dart
/// PdfEditorView(
///   bytes: pdfBytes,
///   onSave: (bytes) => File('out.pdf').writeAsBytes(bytes),
/// )
/// ```
///
/// All chrome follows the ambient Material [Theme]; the viewer's own
/// colors can be tuned with [viewerTheme] (or an inherited
/// [PdfViewerTheme]). Features and tools toggle off via [features].
/// Tool styles, panel visibility/widths, and display settings persist
/// on the device through [PdfEditingPreferences] - pass [preferences]
/// to share one instance across widgets, or leave null for a
/// self-contained one.
///
/// The widget owns the edit session (undo/redo, revisions). Hosts that
/// need programmatic access pass their own [controller] instead of
/// [bytes] - exactly one of the two must be given. [onSave] receives
/// the current revision's bytes from the toolbar's save button or the
/// ⌘S / Ctrl+S shortcut. [onSaveAs] receives the same bytes from
/// ⌘⇧S / Ctrl+Shift+S; [onDocumentChanged] fires after every revision
/// (edit, undo, redo) for hosts that autosave.
///
/// The widget is a plain body: give it bounded space (a [Scaffold]
/// body, an [Expanded]...). Swapping [bytes] for a different document
/// opens a fresh session in place.
class PdfEditorView extends StatefulWidget {
  const PdfEditorView({
    super.key,
    this.bytes,
    this.documentId,
    this.controller,
    this.viewerController,
    this.preferences,
    this.performance,
    this.features = const PdfEditorFeatures(),
    this.onSave,
    this.onSaveAs,
    this.showSaveButton = true,
    this.alwaysAllowSave = false,
    this.onDocumentChanged,
    this.onPickPdfToInsert,
    this.onExportPages,
    this.onAction,
    this.onAnnotationTap,
    this.pageOverlayBuilder,
    this.annotationMenuBuilder,
    this.contextMenuEnabled = true,
    this.formImagePicker,
    this.imagePicker,
    this.systemImagePasteProvider,
    this.systemTextPasteProvider,
    this.onExportSelectedContentImage,
    this.onExportCustomStamps,
    this.onImportCustomStamps,
    this.customStamps = const [],
    this.fontPicker,
    this.onSnapshot,
    this.onPlaceSignature,
    this.onShareReflowImage,
    this.textPrompt,
    this.styledTextPrompt,
    this.palette = PdfEditingToolbar.defaultPalette,
    this.toolShortcuts = pdfEditToolShortcuts,
    this.toolbarLeading = const [],
    this.toolbarTrailing = const [],
    this.toolbarBuilder,
    this.pageLayout = const PdfPageLayout.verticalContinuous(),
    this.initialFit = PdfViewerFit.page,
    this.backgroundColor,
    this.pageColor,
    this.viewerTheme,
    this.rasterCache,
    this.textCache,
  })  : source = null,
        options = const PdfSourceLoadOptions(firstPaintPages: 1),
        onProgress = null,
        onFirstPaint = null,
        loadingBuilder = null,
        errorBuilder = null,
        assert((bytes == null) != (controller == null),
            'Provide bytes or a controller, not both.'),
        assert(controller == null || preferences == null,
            'With an external controller, preferences come from it.');

  /// An editor that opens progressively from a [PdfByteSource].
  ///
  /// Page one paints from a sparse first-paint open ([options],
  /// defaulting to the first page) while the rest of the file downloads in the
  /// background; when it lands the full buffer swaps in place. Editing stays
  /// disabled until the whole file is present - the first-paint buffer is
  /// deliberately incomplete, so it must not be edited or saved - then the full
  /// toolbar and [onSave]/[onSaveAs]/[onDocumentChanged] callbacks come alive.
  ///
  /// Pass a stable [documentId] (the URL or path) so remembered scroll/zoom
  /// survive the swap. [onProgress] reports the background read;
  /// [onFirstPaint] fires when the first page is ready. Falls back to a plain
  /// full read (no early paint) when the source can't serve useful ranges. The
  /// in-flight load is cancelled when the widget is disposed; the [source] is
  /// host-owned and not closed.
  const PdfEditorView.source(
    PdfByteSource this.source, {
    super.key,
    this.options = const PdfSourceLoadOptions(firstPaintPages: 1),
    this.documentId,
    this.onProgress,
    this.onFirstPaint,
    this.loadingBuilder,
    this.errorBuilder,
    this.viewerController,
    this.preferences,
    this.performance,
    this.features = const PdfEditorFeatures(),
    this.onSave,
    this.onSaveAs,
    this.showSaveButton = true,
    this.alwaysAllowSave = false,
    this.onDocumentChanged,
    this.onPickPdfToInsert,
    this.onExportPages,
    this.onAction,
    this.onAnnotationTap,
    this.pageOverlayBuilder,
    this.annotationMenuBuilder,
    this.contextMenuEnabled = true,
    this.formImagePicker,
    this.imagePicker,
    this.systemImagePasteProvider,
    this.systemTextPasteProvider,
    this.onExportSelectedContentImage,
    this.onExportCustomStamps,
    this.onImportCustomStamps,
    this.customStamps = const [],
    this.fontPicker,
    this.onSnapshot,
    this.onPlaceSignature,
    this.onShareReflowImage,
    this.textPrompt,
    this.styledTextPrompt,
    this.palette = PdfEditingToolbar.defaultPalette,
    this.toolShortcuts = pdfEditToolShortcuts,
    this.toolbarLeading = const [],
    this.toolbarTrailing = const [],
    this.toolbarBuilder,
    this.pageLayout = const PdfPageLayout.verticalContinuous(),
    this.initialFit = PdfViewerFit.page,
    this.backgroundColor,
    this.pageColor,
    this.viewerTheme,
    this.rasterCache,
    this.textCache,
  })  : bytes = null,
        controller = null;

  /// The PDF to edit. The widget owns the session; replacing the bytes
  /// (by identity) opens a fresh session in place. Null when opened from a
  /// [source] or an external [controller].
  final Uint8List? bytes;

  /// The source to open progressively (via [PdfEditorView.source]); null
  /// otherwise.
  final PdfByteSource? source;

  /// First-paint tuning for the [source] open. See
  /// [PdfProgressiveSourceBuilder.options].
  final PdfSourceLoadOptions options;

  /// Background full-read progress for the [source] open, `(received, total)`.
  final void Function(int received, int? total)? onProgress;

  /// Fires when the first page painted from the [source].
  final VoidCallback? onFirstPaint;

  /// Shown while the first-paint bytes are still loading (source mode only).
  final WidgetBuilder? loadingBuilder;

  /// Shown when a [source] open fails before any page could paint.
  final Widget Function(BuildContext context, Object error)? errorBuilder;

  /// Optional persistent on-disk preview cache (see [PdfRasterCache]).
  /// Keyed by [documentId] (or, with [bytes], their [pdfContentKey]), so
  /// reopening a previously-seen document paints soft page content
  /// immediately. Share one instance across the app to pool its budget.
  final PdfRasterCache? rasterCache;

  /// Optional persistent on-disk text cache (see [PdfPageTextCache]).
  /// Threaded to the viewer, but only consulted in read-only mode - an
  /// active edit session mutates page content, so its text is never served
  /// from the content-keyed persistent cache (in-memory only).
  final PdfPageTextCache? textCache;

  /// A stable identifier for this document, used to remember its scroll
  /// position and zoom across sessions (persisted in the preferences).
  /// With [bytes] a key is derived from the content when this is null;
  /// with an external [controller] (no bytes) pass one explicitly to
  /// enable the memory - a file path or URL is ideal.
  final String? documentId;

  /// An external edit session, for hosts that drive edits
  /// programmatically (then [bytes] must be null). The host keeps
  /// ownership and disposes it.
  final PdfEditingController? controller;

  /// Optional external viewer controller, for hosts that navigate or
  /// search programmatically.
  final PdfViewerController? viewerController;

  /// The persisted preferences backing tool styles and panel state.
  /// Only with [bytes]; an external [controller] brings its own.
  final PdfEditingPreferences? preferences;

  /// Optional adaptive/fixed performance controller. Null creates an owned
  /// Auto controller. Worker-count recommendations apply only when this shell
  /// naturally restarts its revision-bound worker.
  final PdfPerformanceController? performance;

  final PdfEditorFeatures features;

  /// Receives the current revision's bytes when the toolbar's save
  /// button is pressed or ⌘S / Ctrl+S is hit; the button (and the
  /// shortcut) are off when null. Writing the bytes somewhere is the
  /// app's job.
  final void Function(Uint8List bytes)? onSave;

  /// Receives the current revision's bytes when ⌘⇧S / Ctrl+Shift+S is hit;
  /// the save-as dialog or share/download flow is the app's job.
  final void Function(Uint8List bytes)? onSaveAs;

  /// Whether the stock shell chrome shows its Save button when [onSave]
  /// is present. Hosts can set this false when they provide their own
  /// save affordance while still keeping [onSave] and the keyboard
  /// shortcut active.
  final bool showSaveButton;

  /// Keeps Save (the button and ⌘S / Ctrl+S) enabled even when the
  /// document has no unsaved edits. Hosts set this for a document that has
  /// never been written to disk - a new untitled file - so the first Save
  /// can create the file before any edit is made. Defaults to false, where
  /// Save is gated on [PdfEditingController.isModified] as usual.
  final bool alwaysAllowSave;

  /// Called after every revision - edits, undo, redo - with the new
  /// current bytes. For autosaving hosts.
  final void Function(Uint8List bytes)? onDocumentChanged;

  /// Picks a PDF whose pages are inserted after the current page (the
  /// host shows a file picker and returns the bytes, or null to cancel).
  /// When null the thumbnail strip's "Insert PDF…" action is hidden. Needs
  /// [PdfEditorFeatures.pageEditing].
  final Future<Uint8List?> Function()? onPickPdfToInsert;

  /// Receives a standalone PDF of a user-chosen page range to save (the
  /// thumbnail strip's "Export pages…" action asks for the range, then
  /// hands the bytes here). When null the action is hidden.
  final void Function(Uint8List bytes)? onExportPages;

  /// See [PdfViewer.onAction].
  final PdfActionHandler? onAction;

  /// See [PdfViewer.onAnnotationTap].
  final PdfAnnotationTapHandler? onAnnotationTap;

  /// See [PdfViewer.pageOverlayBuilder].
  final PdfPageOverlayBuilder? pageOverlayBuilder;

  /// See [PdfViewer.annotationMenuBuilder].
  final PdfAnnotationMenuBuilder? annotationMenuBuilder;

  /// See [PdfViewer.contextMenuEnabled].
  final bool contextMenuEnabled;

  /// See [PdfViewer.formImagePicker].
  final PdfFormImagePicker? formImagePicker;

  /// See [PdfViewer.imagePicker].
  final PdfImagePicker? imagePicker;

  /// See [PdfViewer.systemImagePasteProvider].
  final PdfSystemImagePasteProvider? systemImagePasteProvider;

  /// See [PdfViewer.systemTextPasteProvider].
  final PdfSystemTextPasteProvider? systemTextPasteProvider;

  /// See [PdfEditingToolbar.onExportSelectedContentImage].
  final PdfSelectedContentImageHandler? onExportSelectedContentImage;

  /// Host-provided export for user-saved custom stamps in the stock Manage
  /// Stamps dialog. When null, the Export button is hidden.
  final PdfStampExportCallback? onExportCustomStamps;

  /// Host-provided import for user-saved custom stamps in the stock Manage
  /// Stamps dialog. When null, the Import button is hidden.
  final PdfStampImportCallback? onImportCustomStamps;

  /// Stamps supplied by the host app. These appear in the stock stamp picker
  /// alongside user-saved stamps but are not persisted or deletable there.
  final List<PdfCustomStamp> customStamps;

  /// How the font menu's "Load font…" entry loads a custom `.ttf`/`.otf`
  /// font to embed for new text. When null, only the standard families
  /// and bundled fonts are offered.
  final PdfFontPicker? fontPicker;

  /// See [PdfViewer.onSnapshot]. The snapshot tool always keeps a vector
  /// copy on the clipboard for in-app paste; this callback additionally
  /// exports the captured raster image (copy/save/share).
  final PdfSnapshotHandler? onSnapshot;

  /// See [PdfViewer.onPlaceSignature].
  final PdfSignaturePlacer? onPlaceSignature;

  /// Saves or shares a figure the reader taps to open fullscreen in the text
  /// reflow view (see [PdfReflowView.onShareImage]). Null still allows
  /// fullscreen pan/pinch-zoom viewing; it just hides the share action.
  final PdfReflowImageShareHandler? onShareReflowImage;

  /// How dialog-based tools ask for text. Defaults to
  /// [showPdfTextPrompt], a Material dialog.
  final PdfTextPrompt? textPrompt;

  /// How selected page-content text is edited together with its rich style.
  /// Defaults to [showPdfStyledTextPrompt].
  final PdfStyledTextPrompt? styledTextPrompt;

  /// The toolbar's color palette.
  final List<Color> palette;

  /// Single-key shortcuts for arming editing tools. Threaded to both the
  /// embedded [PdfViewer] bindings and [PdfEditingToolbar] tooltip labels.
  /// Pass an empty map to disable tool shortcuts.
  final Map<PdfEditTool, PdfToolShortcut> toolShortcuts;

  /// Custom widgets shown before the stock editing toolbar controls.
  ///
  /// Builders receive this editor view's edit session and viewer
  /// controller, including the internally owned ones when [bytes] is
  /// used.
  final List<PdfEditingToolbarWidgetBuilder> toolbarLeading;

  /// Custom widgets shown after the stock editing toolbar controls.
  final List<PdfEditingToolbarWidgetBuilder> toolbarTrailing;

  /// Builds or replaces the bottom editing toolbar.
  ///
  /// This is the escape hatch for apps that need fully custom editor
  /// components. The stock toolbar already supports hiding tool groups,
  /// filtering individual tools, and adding [toolbarLeading] /
  /// [toolbarTrailing] actions; use [toolbarBuilder] when the whole toolbar
  /// should be host-owned instead. The builder receives the active edit session
  /// and viewer controller, including internally owned instances when [bytes]
  /// is used.
  ///
  /// [PdfEditorFeatures.toolbar] still gates this builder. Set that feature to
  /// false to disable all toolbar chrome regardless of this value.
  final PdfEditorToolbarBuilder? toolbarBuilder;

  /// See [PdfViewer.pageLayout].
  final PdfPageLayout pageLayout;

  /// See [PdfViewer.initialFit].
  final PdfViewerFit initialFit;

  /// See [PdfViewer.backgroundColor].
  final Color? backgroundColor;

  /// The paper color. Null follows the persisted preference (white by
  /// default).
  final Color? pageColor;

  /// Viewer colors (selection, search matches, scrollbar...). Null
  /// uses an inherited [PdfViewerTheme] or the stock look.
  final PdfViewerThemeData? viewerTheme;

  @override
  State<PdfEditorView> createState() => _PdfEditorViewState();
}

class _PdfEditorViewState extends State<PdfEditorView> {
  late PdfShellSessionLifecycle _shell;

  // Routes the Apple Pencil's native double-tap to the session's eraser
  // toggle. Created only on iOS (the only platform with the gesture) so the
  // method-channel handler isn't claimed needlessly elsewhere.
  PdfPencilInteraction? _pencil;

  late Map<PdfEditTool, PdfToolShortcut> _toolShortcuts;

  /// The revision length last reported through onDocumentChanged -
  /// revisions are byte prefixes of one buffer, so equal length means
  /// the same revision.
  late int _reportedLength;

  PdfEditingController get _session => _shell.session;
  PdfViewerController get _viewer => _shell.viewer;
  PdfEditingPreferences get _prefs => _shell.preferences;
  PdfPerformanceController get _performance => _shell.performance;
  TextEditingController get _searchField => _shell.searchController;
  FocusNode get _searchFocus => _shell.searchFocus;

  /// A stable key for the open document, or null when there is nothing to
  /// key a remembered position on - an external controller with no
  /// [documentId]. With [bytes] one is derived from the content.
  String? get _documentKey => _shell.documentKey;

  bool get _isSource => widget.source != null;

  @override
  void initState() {
    super.initState();
    _toolShortcuts =
        Map<PdfEditTool, PdfToolShortcut>.of(widget.toolShortcuts);
    // In source mode the shell is owned by the inner byte-based PdfEditorView
    // the progressive builder mounts once the first-paint bytes arrive.
    if (_isSource) return;
    _shell = PdfShellSessionLifecycle(
      bytes: widget.bytes,
      controller: widget.controller,
      preferences: widget.preferences,
      viewerController: widget.viewerController,
      performance: widget.performance,
      documentId: widget.documentId,
      prepareSession: _prepareSession,
      onSessionChanged: _onSessionChanged,
    );
    _reportedLength = _session.bytes.length;
    _attachPencil();
  }

  void _prepareSession(PdfEditingController session) {
    session
      ..providedCustomStamps = widget.customStamps
      ..colorLocked = !widget.features.colorControls;
  }

  /// Binds the Apple Pencil double-tap to the session's eraser toggle on
  /// iOS, where the gesture exists. The shell stays plugin-free - the host's
  /// iOS runner registers the `UIPencilInteraction` and forwards it over
  /// [PdfPencilInteraction.channel]; this is the Dart end.
  void _attachPencil() {
    if (!widget.features.pencilEraserToggle) return;
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    (_pencil ??= PdfPencilInteraction()).attach(_session);
  }

  void _onSessionChanged(PdfEditingController session) {
    final length = session.bytes.length;
    if (length == _reportedLength) return;
    _reportedLength = length;
    widget.onDocumentChanged?.call(session.bytes);
  }

  @override
  void didUpdateWidget(PdfEditorView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!mapEquals(widget.toolShortcuts, oldWidget.toolShortcuts)) {
      _toolShortcuts =
          Map<PdfEditTool, PdfToolShortcut>.of(widget.toolShortcuts);
    }
    if (_isSource) return;
    final sourceChanging = widget.controller != oldWidget.controller ||
        !identical(widget.bytes, oldWidget.bytes) ||
        (widget.controller == null &&
            !identical(widget.preferences, oldWidget.preferences));
    if (sourceChanging) {
      _pencil?.dispose();
      _pencil = null;
    }
    final update = _shell.update(
      bytes: widget.bytes,
      controller: widget.controller,
      preferences: widget.preferences,
      viewerController: widget.viewerController,
      performanceController: widget.performance,
      documentId: widget.documentId,
      prepareSession: _prepareSession,
      onSessionChanged: _onSessionChanged,
    );
    if (update.sessionChanged) {
      _reportedLength = _session.bytes.length;
      _attachPencil();
    }
  }

  @override
  void dispose() {
    _pencil?.dispose();
    if (!_isSource) _shell.dispose();
    super.dispose();
  }

  /// The progressive-open path: paint page one from the sparse first-paint
  /// buffer, then swap the full buffer in place. The inner byte-based
  /// [PdfEditorView] owns the session/worker, so it reopens in place across the
  /// swap. Editing is gated off until the full file lands - the first-paint
  /// buffer is deliberately incomplete, so it must not be edited or saved.
  Widget _buildFromSource() {
    return PdfProgressiveSourceBuilder(
      source: widget.source!,
      options: widget.options,
      onProgress: widget.onProgress,
      onFirstPaint: widget.onFirstPaint,
      loadingBuilder: widget.loadingBuilder,
      errorBuilder: widget.errorBuilder,
      builder: (context, bytes, complete) => PdfEditorView(
        bytes: bytes,
        documentId: widget.documentId,
        viewerController: widget.viewerController,
        preferences: widget.preferences,
        performance: widget.performance,
        features: complete ? widget.features : _gatedFeatures(widget.features),
        // The first-paint buffer is incomplete: no save/change/insert/export
        // until the whole file is present.
        onSave: complete ? widget.onSave : null,
        onSaveAs: complete ? widget.onSaveAs : null,
        showSaveButton: widget.showSaveButton,
        alwaysAllowSave: complete && widget.alwaysAllowSave,
        onDocumentChanged: complete ? widget.onDocumentChanged : null,
        onPickPdfToInsert: complete ? widget.onPickPdfToInsert : null,
        onExportPages: complete ? widget.onExportPages : null,
        onAction: widget.onAction,
        onAnnotationTap: widget.onAnnotationTap,
        pageOverlayBuilder: widget.pageOverlayBuilder,
        annotationMenuBuilder: widget.annotationMenuBuilder,
        contextMenuEnabled: widget.contextMenuEnabled,
        formImagePicker: widget.formImagePicker,
        imagePicker: widget.imagePicker,
        systemImagePasteProvider: widget.systemImagePasteProvider,
        systemTextPasteProvider: widget.systemTextPasteProvider,
        onExportSelectedContentImage: widget.onExportSelectedContentImage,
        onExportCustomStamps: widget.onExportCustomStamps,
        onImportCustomStamps: widget.onImportCustomStamps,
        customStamps: widget.customStamps,
        fontPicker: widget.fontPicker,
        onSnapshot: widget.onSnapshot,
        onPlaceSignature: widget.onPlaceSignature,
        textPrompt: widget.textPrompt,
        styledTextPrompt: widget.styledTextPrompt,
        palette: widget.palette,
        toolShortcuts: widget.toolShortcuts,
        toolbarLeading: widget.toolbarLeading,
        toolbarTrailing: widget.toolbarTrailing,
        toolbarBuilder: widget.toolbarBuilder,
        pageLayout: widget.pageLayout,
        initialFit: widget.initialFit,
        backgroundColor: widget.backgroundColor,
        pageColor: widget.pageColor,
        viewerTheme: widget.viewerTheme,
        // The first-paint buffer only holds the first page(s); its later pages
        // render blank (and its text extracts empty). Keep the persistent
        // content-keyed caches off until the full buffer lands so those blanks
        // aren't written under the document's stable id and served back after
        // the swap (and across app restarts).
        rasterCache: complete ? widget.rasterCache : null,
        textCache: complete ? widget.textCache : null,
      ),
    );
  }

  /// A read-only projection of [features] for the incomplete first-paint view:
  /// the viewer, search, and navigation panels stay, but every editing
  /// surface - the toolbar, page editing, markup, undo/redo, the
  /// annotation/properties panels - is off until the full buffer lands.
  static PdfEditorFeatures _gatedFeatures(PdfEditorFeatures f) =>
      PdfEditorFeatures(
        headerBar: f.headerBar,
        search: f.search,
        searchResultsPanel: f.searchResultsPanel,
        pageNumber: f.pageNumber,
        author: false,
        authorEditable: false,
        viewOptions: f.viewOptions,
        reflowView: f.reflowView,
        pageColorEditable: f.pageColorEditable,
        thumbnails: f.thumbnails,
        bookmarks: f.bookmarks,
        pageEditing: false,
        annotationSidebar: false,
        propertiesPanel: false,
        toolbar: false,
        markup: false,
        undoRedo: false,
        colorControls: f.colorControls,
        styleControls: f.styleControls,
        flatten: false,
        colorProcessing: false,
        pencilEraserToggle: false,
        tools: f.tools,
        toolGroups: f.toolGroups,
      );

  /// Whether there's anything to save: false while the document still
  /// matches what was opened, which disables the Save button (and makes
  /// the ⌘S / Ctrl+S shortcut a no-op). A host that flags the document as
  /// never-saved ([PdfEditorView.alwaysAllowSave]) keeps Save enabled so a
  /// brand-new file can be written before its first edit.
  bool get _canSave => _session.isModified || widget.alwaysAllowSave;

  void _save() {
    if (!_canSave) return;
    widget.onSave?.call(_session.bytes);
  }

  void _saveAs() => widget.onSaveAs?.call(_session.bytes);

  Future<void> _promptAuthor() async {
    final session = _session;
    final name = await showPdfTextPrompt(context,
        title: pdfL10n(context).editorViewAuthorNameTitle,
        initial: session.preferences.author ?? '');
    if (name == null) return;
    session.preferences.author = name.trim().isEmpty ? null : name.trim();
  }

  /// Redocks [panel] standalone onto [dock] (an edge drop zone): writes its
  /// dock and splits it out of any tab group. The pref change notifies and
  /// rebuilds, re-routing the panel. Wired to
  /// [PdfShellPanelLayout.onPanelDock].
  void _setPanelDock(PdfDockablePanel panel, PdfPanelDock dock) {
    _prefs.setPanelDock(panel, dock);
    _prefs.setPanelGroup(panel, _prefs.standalonePanelGroup(panel));
  }

  /// Tabs [panel] into the group at [dock]/[group] (a drop onto another
  /// panel): matches its dock and group id so the two render as one tabbed
  /// panel. Wired to [PdfPanelTabDropRegion.onJoin].
  void _joinPanel(PdfDockablePanel panel, PdfPanelDock dock, int group) {
    _prefs.setPanelDock(panel, dock);
    _prefs.setPanelGroup(panel, group);
  }

  @override
  Widget build(BuildContext context) {
    if (_isSource) return _buildFromSource();
    final features = widget.features;
    Widget body = LayoutBuilder(builder: (context, constraints) {
      return ListenableBuilder(
        // the session owns the document revisions: the viewer must
        // rebuild with the current document whenever it notifies
        listenable: Listenable.merge([_session, _prefs]),
        builder: (context, _) {
          final session = _session;
          final prefs = _prefs;
          final pageColor = widget.pageColor ?? prefs.pageColor;
          // the persistent thumbnail cache, bound to this document, so the
          // page grid/strip persist their rasters and reopen onto them
          final key = _documentKey;
          final thumbnailDisk = (widget.rasterCache != null && key != null)
              ? widget.rasterCache!.forDocument(key)
              : null;
          final showThumbnails =
              pdfShellShowThumbnailSidebar(prefs, constraints);
          // on a narrow screen the panels float up from the bottom as
          // sheets instead of docking to the side and crowding the page
          final useSheets = pdfShellUseBottomSheets(constraints);

          // The docked and bottom-sheet variants carry DISTINCT keys: when
          // the responsive breakpoint flips, the panel must be disposed and
          // remounted, never reparented across the docked<->sheet boundary.
          // Reparenting reactivates any OverlayPortal in the subtree (the
          // thumbnail tiles' delete-button Tooltips) during the enclosing
          // LayoutBuilder's layout pass, which trips a RenderObject mutation
          // assertion. A fresh mount has no such overlay reactivation.
          PdfThumbnailSidebar thumbnails({required bool bottomSheet}) =>
              PdfThumbnailSidebar(
                key: ValueKey(
                    'pdf-shell-thumbnails-${bottomSheet ? 'sheet' : 'docked'}'),
                controller: session,
                viewerController: _viewer,
                pageColor: pageColor,
                showAnnotations: prefs.showAnnotations,
                allowPageEditing: features.pageEditing,
                dock: prefs.thumbnailSidebarDock,
                bottomSheet: bottomSheet,
                // the sheet chrome carries its own close button
                onClose: bottomSheet
                    ? null
                    : () => prefs.showThumbnailSidebar = false,
                // page-level file actions live in the strip's footer; insert
                // needs page editing on, export stands on its own
                onPickPdfToInsert:
                    features.pageEditing ? widget.onPickPdfToInsert : null,
                onExportPages: widget.onExportPages,
                renderWorker: _shell.worker,
                rasterCache: thumbnailDisk,
              );
          PdfSearchResultsPanel searchResults({required bool bottomSheet}) =>
              PdfSearchResultsPanel(
                key: ValueKey(
                    'pdf-shell-search-panel-${bottomSheet ? 'sheet' : 'docked'}'),
                controller: _viewer,
                preferences: prefs,
                dock: prefs.searchPanelDock,
                bottomSheet: bottomSheet,
                onClose: bottomSheet
                    ? null
                    : () => prefs.showSearchResultsPanel = false,
              );
          PdfBookmarkSidebar bookmarks({required bool bottomSheet}) =>
              PdfBookmarkSidebar(
                key: ValueKey(
                    'pdf-shell-bookmarks-${bottomSheet ? 'sheet' : 'docked'}'),
                controller: session,
                viewerController: _viewer,
                editable: true,
                dock: prefs.bookmarkSidebarDock,
                bottomSheet: bottomSheet,
                onClose: bottomSheet
                    ? null
                    : () => prefs.showBookmarkSidebar = false,
              );
          PdfAnnotationSidebar annotations({required bool bottomSheet}) =>
              PdfAnnotationSidebar(
                key: ValueKey(
                    'pdf-shell-annotations-${bottomSheet ? 'sheet' : 'docked'}'),
                controller: session,
                viewerController: _viewer,
                dock: prefs.annotationSidebarDock,
                bottomSheet: bottomSheet,
                onClose: bottomSheet
                    ? null
                    : () => prefs.showAnnotationSidebar = false,
              );
          PdfAnnotationPropertiesPanel properties(
                  {required bool bottomSheet}) =>
              PdfAnnotationPropertiesPanel(
                key: ValueKey(
                    'pdf-shell-properties-${bottomSheet ? 'sheet' : 'docked'}'),
                controller: session,
                showAuthor: features.authorEditable,
                dock: prefs.propertiesPanelDock,
                bottomSheet: bottomSheet,
                onClose: bottomSheet
                    ? null
                    : () => prefs.showPropertiesPanel = false,
                fontPicker: widget.fontPicker,
              );
          // the dedicated full-area page grid, overlaid on the (still
          // mounted) viewer so a tapped page can scroll it before the grid
          // closes to reveal the page
          PdfThumbnailView pageGrid() => PdfThumbnailView(
                key: const ValueKey('pdf-shell-page-grid'),
                controller: session,
                viewerController: _viewer,
                pageColor: pageColor,
                showAnnotations: prefs.showAnnotations,
                allowPageEditing: features.pageEditing,
                onPickPdfToInsert:
                    features.pageEditing ? widget.onPickPdfToInsert : null,
                onExportPages: widget.onExportPages,
                onOpenPage: (_) => prefs.showThumbnailView = false,
                renderWorker: _shell.worker,
                rasterCache: thumbnailDisk,
              );

          // the full-area page grid replaces the page viewer; it wins over
          // reflow if both prefs are somehow on (the toggle below also
          // clears reflow). [altView] is "the viewer is hidden" - it
          // suppresses the docked panels, the editing toolbar, and the
          // viewer-only header controls, just as reflow does.
          final gridActive = features.thumbnails && prefs.showThumbnailView;
          final reflowActive =
              features.reflowView && prefs.showReflowView && !gridActive;
          final altView = reflowActive || gridActive;
          // The navigational panels (Pages, Bookmarks) drive the reflow view
          // through the shared controller, so they stay available while
          // reading; only the full-area page grid hides them. The canvas-bound
          // panels (search results, annotations, properties) have no page to
          // act on in reflow, so they still yield to [altView].
          final showThumbnailsPanel =
              features.thumbnails && showThumbnails && !gridActive;
          final showSearchPanel = features.search &&
              features.searchResultsPanel &&
              prefs.showSearchResultsPanel &&
              !altView;
          final showBookmarksPanel =
              features.bookmarks && prefs.showBookmarkSidebar && !gridActive;
          final showAnnotationsPanel = features.annotationSidebar &&
              prefs.showAnnotationSidebar &&
              !altView;
          final showPropertiesPanel =
              features.propertiesPanel && prefs.showPropertiesPanel && !altView;

          // The visible docked panels, in canonical order. Each is placed on
          // its persisted edge ([PdfEditingPreferences.panelDock]) and, within
          // that edge, its persisted tab group ([panelGroup]): panels sharing
          // an edge and a group id render as one tabbed panel, otherwise as
          // side-by-side panels. Dragging a panel's handle onto an edge zone
          // redocks it standalone; dragging it onto another panel tabs them.
          final visiblePanels = <PdfDockablePanel>[
            if (showThumbnailsPanel && !useSheets) PdfDockablePanel.thumbnails,
            if (showSearchPanel && !useSheets) PdfDockablePanel.search,
            if (showBookmarksPanel && !useSheets) PdfDockablePanel.bookmarks,
            if (showAnnotationsPanel && !useSheets)
              PdfDockablePanel.annotations,
            if (showPropertiesPanel && !useSheets) PdfDockablePanel.properties,
          ];
          Widget standalonePanel(PdfDockablePanel p) => switch (p) {
                PdfDockablePanel.thumbnails => thumbnails(bottomSheet: false),
                PdfDockablePanel.search => searchResults(bottomSheet: false),
                PdfDockablePanel.bookmarks => bookmarks(bottomSheet: false),
                PdfDockablePanel.annotations => annotations(bottomSheet: false),
                PdfDockablePanel.properties => properties(bottomSheet: false),
              };
          // a chromeless body for use inside a tab group (the group supplies
          // the frame, tab strip, and close buttons); reuses the panels'
          // bottom-sheet content mode
          Widget tabBody(PdfDockablePanel p) => switch (p) {
                PdfDockablePanel.thumbnails => thumbnails(bottomSheet: true),
                PdfDockablePanel.search => searchResults(bottomSheet: true),
                PdfDockablePanel.bookmarks => bookmarks(bottomSheet: true),
                PdfDockablePanel.annotations => annotations(bottomSheet: true),
                PdfDockablePanel.properties => properties(bottomSheet: true),
              };
          VoidCallback closePanel(PdfDockablePanel p) => switch (p) {
                PdfDockablePanel.thumbnails => () =>
                    prefs.showThumbnailSidebar = false,
                PdfDockablePanel.search => () =>
                    prefs.showSearchResultsPanel = false,
                PdfDockablePanel.bookmarks => () =>
                    prefs.showBookmarkSidebar = false,
                PdfDockablePanel.annotations => () =>
                    prefs.showAnnotationSidebar = false,
                PdfDockablePanel.properties => () =>
                    prefs.showPropertiesPanel = false,
              };
          List<Widget> dockedPanels(PdfPanelDock dock) {
            final onDock = [
              for (final p in visiblePanels)
                if (prefs.panelDock(p) == dock) p
            ];
            // partition into tab groups by group id, preserving the order in
            // which each group first appears
            final order = <int>[];
            final byGroup = <int, List<PdfDockablePanel>>{};
            for (final p in onDock) {
              final g = prefs.panelGroup(p);
              if (!byGroup.containsKey(g)) {
                byGroup[g] = [];
                order.add(g);
              }
              byGroup[g]!.add(p);
            }
            final children = <Widget>[];
            for (final g in order) {
              final members = byGroup[g]!;
              final Widget child;
              if (members.length == 1) {
                child = standalonePanel(members.first);
              } else {
                child = PdfPanelTabGroup(
                  key: ValueKey('pdf-panel-tabgroup-${dock.name}-$g'),
                  dock: dock,
                  width: 300,
                  minWidth: 200,
                  maxWidth: 560,
                  persistedWidth: prefs.panelGroupWidth(dock),
                  onPersistWidth: (w) => prefs.setPanelGroupWidth(dock, w),
                  gripKey: ValueKey('pdf-panel-tabgroup-grip-${dock.name}-$g'),
                  entries: [
                    for (final m in members)
                      PdfPanelTabEntry(
                        panel: m,
                        body: tabBody(m),
                        onClose: closePanel(m),
                      ),
                  ],
                );
              }
              // dropping another panel onto this one tabs it into this group
              children.add(PdfPanelTabDropRegion(
                members: members.toSet(),
                onJoin: (dragged) => _joinPanel(dragged, dock, g),
                child: child,
              ));
            }
            return children;
          }

          final sheets = !useSheets
              ? const <Widget>[]
              : <Widget>[
                  if (showThumbnailsPanel)
                    PdfPanelBottomSheet(
                      key: const ValueKey('pdf-shell-thumbnails-sheet'),
                      title: pdfL10n(context).shellPanelPages,
                      closeKey:
                          const ValueKey('pdf-shell-thumbnails-sheet-close'),
                      onClose: () => prefs.showThumbnailSidebar = false,
                      child: thumbnails(bottomSheet: true),
                    ),
                  if (showSearchPanel)
                    PdfPanelBottomSheet(
                      key: const ValueKey('pdf-shell-search-sheet'),
                      title: pdfL10n(context).shellPanelSearchResults,
                      closeKey: const ValueKey('pdf-shell-search-sheet-close'),
                      onClose: () => prefs.showSearchResultsPanel = false,
                      child: searchResults(bottomSheet: true),
                    ),
                  if (showBookmarksPanel)
                    PdfPanelBottomSheet(
                      key: const ValueKey('pdf-shell-bookmarks-sheet'),
                      title: pdfL10n(context).shellPanelBookmarks,
                      closeKey:
                          const ValueKey('pdf-shell-bookmarks-sheet-close'),
                      onClose: () => prefs.showBookmarkSidebar = false,
                      child: bookmarks(bottomSheet: true),
                    ),
                  if (showAnnotationsPanel)
                    PdfPanelBottomSheet(
                      key: const ValueKey('pdf-shell-annotations-sheet'),
                      title: pdfL10n(context).shellPanelAnnotations,
                      closeKey:
                          const ValueKey('pdf-shell-annotations-sheet-close'),
                      onClose: () => prefs.showAnnotationSidebar = false,
                      child: annotations(bottomSheet: true),
                    ),
                  if (showPropertiesPanel)
                    PdfPanelBottomSheet(
                      key: const ValueKey('pdf-shell-properties-sheet'),
                      title: pdfL10n(context).shellPanelProperties,
                      closeKey:
                          const ValueKey('pdf-shell-properties-sheet-close'),
                      onClose: () => prefs.showPropertiesPanel = false,
                      child: properties(bottomSheet: true),
                    ),
                ];
          // On a phone the toolbar collapses to a solid bar (see
          // PdfEditingToolbar.mobileBreakpoint); floating it over the page
          // there hides the bottom of the content behind it, so dock it
          // below the viewer instead, where it takes its own layout space.
          // Above the breakpoint it stays a set of transparent floating
          // cards with the page showing through the gaps.
          final showToolbar = features.toolbar && sheets.isEmpty && !altView;
          final dockToolbar = showToolbar &&
              constraints.maxWidth < PdfEditingToolbar.mobileBreakpoint;
          final toolbar = !showToolbar
              ? null
              : widget.toolbarBuilder?.call(context, session, _viewer) ??
                  PdfEditingToolbar(
                    controller: session,
                    viewerController: _viewer,
                    // save lives in the header now, not the dock
                    textPrompt: widget.textPrompt ?? showPdfTextPrompt,
                    styledTextPrompt:
                        widget.styledTextPrompt ?? showPdfStyledTextPrompt,
                    imagePicker: widget.imagePicker,
                    formImagePicker: widget.formImagePicker,
                    onExportSelectedContentImage:
                        widget.onExportSelectedContentImage,
                    fontPicker: widget.fontPicker,
                    onExportCustomStamps: widget.onExportCustomStamps,
                    onImportCustomStamps: widget.onImportCustomStamps,
                    palette: widget.palette,
                    tools: features.tools,
                    groups: features.toolGroups,
                    toolShortcuts: _toolShortcuts,
                    showMarkup: features.markup,
                    showUndoRedo: features.undoRedo,
                    showColor: features.colorControls,
                    showStyle: features.styleControls,
                    showFlatten: features.flatten,
                    showColorProcessing: features.colorProcessing,
                    leading: widget.toolbarLeading,
                    trailing: widget.toolbarTrailing,
                  );
          final viewOptionsControl = PdfShellControlItem(
            key: const ValueKey('pdf-shell-view-options'),
            icon: Icons.display_settings_outlined,
            label: pdfL10n(context).shellSettings,
            onPressed: () {
              showPdfShellViewOptionsSheet(
                context,
                preferences: prefs,
                reflow: features.reflowView,
                pageGrid: features.thumbnails,
                pageColor: features.pageColorEditable,
                author: features.author,
                authorName: session.preferences.author,
                onAuthorPressed: _promptAuthor,
                toolShortcuts: _toolShortcuts,
                onToolShortcutsChanged: (value) =>
                    setState(() => _toolShortcuts = value),
                tools: features.tools,
              );
            },
          );
          // A one-tap Reflow toggle for the compact Controls sheet - reading
          // reflow is something phone users reach for often, so it earns a
          // direct tile instead of living only inside Settings. Mirrors the
          // Settings toggle: turning reflow on clears the page grid.
          final reflowControl = PdfShellControlItem(
            key: const ValueKey('pdf-shell-reflow-toggle'),
            icon: Icons.article_outlined,
            label: pdfL10n(context).shellReflow,
            selected: reflowActive,
            onPressed: () {
              prefs.showThumbnailView = false;
              prefs.showReflowView = !prefs.showReflowView;
            },
          );
          final panelItems = [
            if (features.searchResultsPanel)
              PdfShellPanelItem(
                key: const ValueKey('pdf-shell-search-results-toggle'),
                icon: Icons.manage_search,
                tooltip: pdfL10n(context).shellPanelSearchResults,
                selected: prefs.showSearchResultsPanel,
                onPressed: () => prefs.showSearchResultsPanel =
                    !prefs.showSearchResultsPanel,
              ),
            if (features.thumbnails)
              PdfShellPanelItem(
                key: const ValueKey('pdf-shell-thumbnails-toggle'),
                icon: Icons.grid_view,
                tooltip: pdfL10n(context).shellPanelPages,
                selected: showThumbnails,
                onPressed: () => prefs.showThumbnailSidebar = !showThumbnails,
              ),
            if (features.bookmarks)
              PdfShellPanelItem(
                key: const ValueKey('pdf-shell-bookmarks-toggle'),
                icon: Icons.bookmarks_outlined,
                tooltip: pdfL10n(context).shellPanelBookmarks,
                selected: prefs.showBookmarkSidebar,
                onPressed: () =>
                    prefs.showBookmarkSidebar = !prefs.showBookmarkSidebar,
              ),
            if (features.annotationSidebar)
              PdfShellPanelItem(
                key: const ValueKey('pdf-shell-annotations-toggle'),
                icon: Icons.list_alt,
                tooltip: pdfL10n(context).shellPanelAnnotations,
                selected: prefs.showAnnotationSidebar,
                onPressed: () =>
                    prefs.showAnnotationSidebar = !prefs.showAnnotationSidebar,
              ),
            if (features.propertiesPanel)
              PdfShellPanelItem(
                key: const ValueKey('pdf-shell-properties-toggle'),
                icon: Icons.tune,
                tooltip: pdfL10n(context).shellPanelProperties,
                selected: prefs.showPropertiesPanel,
                onPressed: () =>
                    prefs.showPropertiesPanel = !prefs.showPropertiesPanel,
              ),
          ];
          return Column(children: [
            if (features.headerBar)
              PdfShellBar(
                leading: [
                  if (features.pageNumber && !altView)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: PdfPageNumberField(controller: _viewer),
                    ),
                  if (!altView) PdfShellZoomControl(controller: _viewer),
                  if (features.search && !altView) ...[
                    PdfSearchField(
                      controller: _viewer,
                      searchController: _searchField,
                      focusNode: _searchFocus,
                      preferences: prefs,
                      // the match-case / whole-word / regex controls live in
                      // the results panel here, keeping the header compact
                      showOptions: !features.searchResultsPanel,
                    ),
                  ],
                ],
                compactLeading: [
                  if (features.pageNumber && !altView)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: PdfPageNumberField(controller: _viewer),
                    ),
                  if (features.search && !altView)
                    PdfSearchField(
                      controller: _viewer,
                      searchController: _searchField,
                      focusNode: _searchFocus,
                      preferences: prefs,
                      showOptions: !features.searchResultsPanel,
                    ),
                ],
                trailing: [
                  if (features.viewOptions)
                    PdfShellViewOptionsButton(
                        preferences: prefs,
                        reflow: features.reflowView,
                        pageGrid: features.thumbnails,
                        pageColor: features.pageColorEditable,
                        author: features.author,
                        authorName: session.preferences.author,
                        onAuthorPressed: _promptAuthor,
                        toolShortcuts: _toolShortcuts,
                        onToolShortcutsChanged: (value) =>
                            setState(() => _toolShortcuts = value),
                        tools: features.tools),
                  PdfShellPanelSwitch(
                    key: const ValueKey('pdf-shell-panels'),
                    items: panelItems,
                  ),
                  // Save sits in the header, not in the floating toolbar -
                  // ⌘S/Ctrl+S takes the same path.
                  if (widget.onSave != null && widget.showSaveButton)
                    FilledButton.icon(
                      key: const ValueKey('pdf-shell-save'),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      icon: const Icon(Icons.save_alt, size: 18),
                      label: Text(pdfL10n(context).save),
                      onPressed: _canSave ? _save : null,
                    ),
                ],
                compactSheetChildren: [
                  if (!altView) PdfShellZoomControl(controller: _viewer),
                ],
                compactControls: [
                  if (features.viewOptions) viewOptionsControl,
                  if (features.reflowView) reflowControl,
                  for (final item in panelItems)
                    PdfShellControlItem(
                      key: item.key,
                      icon: item.icon,
                      label: item.tooltip,
                      selected: item.selected,
                      onPressed: item.onPressed,
                    ),
                  if (widget.onSave != null && widget.showSaveButton)
                    PdfShellControlItem(
                      key: const ValueKey('pdf-shell-save'),
                      icon: Icons.save_alt,
                      label: pdfL10n(context).save,
                      enabled: _canSave,
                      onPressed: _save,
                    ),
                ],
              ),
            Expanded(
              child: PdfShellPanelLayout(
                leadingPanels: dockedPanels(PdfPanelDock.left),
                topPanels: dockedPanels(PdfPanelDock.top),
                bottomPanels: dockedPanels(PdfPanelDock.bottom),
                onPanelDock: _setPanelDock,
                viewer: reflowActive
                    ? PdfReflowView(
                        document: session.document,
                        controller: _viewer,
                        onShareImage: widget.onShareReflowImage,
                        backgroundColor: widget.backgroundColor,
                      )
                    : PdfViewer(
                        document: session.document,
                        controller: _viewer,
                        editing: session,
                        onAction: widget.onAction,
                        onAnnotationTap: widget.onAnnotationTap,
                        pageOverlayBuilder: widget.pageOverlayBuilder,
                        annotationMenuBuilder: widget.annotationMenuBuilder,
                        contextMenuEnabled: widget.contextMenuEnabled,
                        formImagePicker: widget.formImagePicker,
                        imagePicker: widget.imagePicker,
                        systemImagePasteProvider:
                            widget.systemImagePasteProvider,
                        systemTextPasteProvider:
                            widget.systemTextPasteProvider,
                        onSnapshot: widget.onSnapshot,
                        onPlaceSignature: widget.onPlaceSignature,
                        editingTextPrompt: widget.textPrompt,
                        editingStyledTextPrompt: widget.styledTextPrompt,
                        editingPalette: widget.palette,
                        textSelectionEditing: (features.tools == null ||
                                features.tools!
                                    .contains(PdfEditTool.content)) &&
                            (features.toolGroups == null ||
                                features.toolGroups!
                                    .contains(PdfEditToolGroup.edit)),
                        textSelectionMarkup: features.markup &&
                            (features.toolGroups == null ||
                                features.toolGroups!
                                    .contains(PdfEditToolGroup.markup)),
                        pageLayout: widget.pageLayout,
                        initialFit: widget.initialFit,
                        toolShortcuts: _toolShortcuts,
                        backgroundColor: widget.backgroundColor,
                        pageColor: pageColor,
                        showAnnotations: prefs.showAnnotations,
                        highlightFormFields: prefs.highlightFormFields,
                        renderWorker: _shell.worker,
                        performance: _performance,
                        rasterCache: widget.rasterCache,
                        textCache: widget.textCache,
                        documentId: _documentKey,
                        // while the full-area page grid overlays the viewer,
                        // pause the viewer entirely: its (invisible) page
                        // renders and preview prerender both compete for the
                        // single render worker and would starve the grid's own
                        // thumbnails. It stays laid out, so tapping a grid
                        // page still scrolls it before the grid closes.
                        active: !gridActive,
                      ),
                trailingPanels: dockedPanels(PdfPanelDock.right),
                bottomSheets: sheets,
                overlays: [
                  // the page grid covers the (still-mounted) viewer: a tap can
                  // scroll the live viewer underneath, then the grid closes to
                  // reveal the chosen page. Opaque, so the viewer takes no
                  // taps while it shows.
                  if (gridActive) Positioned.fill(child: pageGrid()),
                ],
                // on wide screens the toolbar floats over the bottom of the
                // content, Acrobat/Bluebeam-style; on phones it docks below
                // (see dockToolbar) so its solid bar never hides the page
                floatingToolbar:
                    toolbar != null && !dockToolbar ? toolbar : null,
                dockedToolbar: toolbar != null && dockToolbar ? toolbar : null,
              ),
            ),
          ]);
        },
      );
    });
    if (widget.viewerTheme != null) {
      body = PdfViewerTheme(data: widget.viewerTheme!, child: body);
    }
    final bindings = <ShortcutActivator, VoidCallback>{
      ..._shell.searchShortcuts(enabled: features.headerBar && features.search),
      // ⌘S / Ctrl+S saves through the host's [onSave], the same path the
      // toolbar's save button takes. ⌘⇧S / Ctrl+Shift+S invokes the
      // host's Save As path when one is provided.
      if (widget.onSave != null) ...{
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _save,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
      },
      if (widget.onSaveAs != null) ...{
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true, shift: true):
            _saveAs,
        const SingleActivator(LogicalKeyboardKey.keyS,
            control: true, shift: true): _saveAs,
      },
    };
    if (bindings.isNotEmpty) {
      body = CallbackShortcuts(bindings: bindings, child: body);
    }
    return body;
  }
}
