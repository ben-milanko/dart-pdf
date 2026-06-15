import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

import 'editing/editing_controller.dart';
import 'editing/editing_menu.dart';
import 'editing/editing_pencil.dart';
import 'editing/editing_preferences.dart';
import 'editing/editing_properties.dart';
import 'editing/editing_sidebar.dart';
import 'editing/editing_thumbnails.dart';
import 'editing/editing_toolbar.dart';
import 'editing/text_prompt.dart';
import 'page_number_field.dart';
import 'pdf_viewer.dart';
import 'raster_cache.dart';
import 'render_worker.dart';
import 'search_panel.dart';
import 'shell_chrome.dart';
import 'theme.dart';

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
    this.pageColorEditable = true,
    this.thumbnails = true,
    this.pageEditing = true,
    this.annotationSidebar = true,
    this.propertiesPanel = true,
    this.toolbar = true,
    this.markup = true,
    this.undoRedo = true,
    this.colorControls = true,
    this.styleControls = true,
    this.flatten = true,
    this.pencilEraserToggle = true,
    this.tools,
    this.toolGroups,
  });

  /// The slim bar above the viewer (search, page number, panel
  /// toggles). With it off, panels still follow the persisted
  /// preferences — they just lose their toggles.
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
  /// highlight, and page (paper) color — display settings only.
  final bool viewOptions;

  /// Whether the view-options menu offers "Page color…". With it false
  /// the paper color can't be changed from the UI — for hosts that set
  /// the page color from the document programmatically and lock it.
  final bool pageColorEditable;

  /// The page-thumbnail sidebar and its toggle.
  final bool thumbnails;

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
  /// stroke/opacity/font editable — pass `colorControls: false,
  /// styleControls: true`.
  final bool colorControls;

  /// The toolbar's style popup (stroke width, opacity, and font
  /// controls). Independent of [colorControls].
  final bool styleControls;

  /// The toolbar's flatten-annotations button.
  final bool flatten;

  /// Whether the Apple Pencil's hardware double-tap toggles the eraser
  /// (iOS only; a no-op elsewhere, where the gesture doesn't exist). The
  /// shell binds the native gesture via [PdfPencilInteraction]; see
  /// [PdfEditingController.togglePencilEraser].
  final bool pencilEraserToggle;

  /// The tool buttons to offer, null meaning all of them. See
  /// [PdfEditingToolbar.tools].
  final Set<PdfEditTool>? tools;

  /// The tool *types* (dock groups — Select, Markup, Draw, Shapes,
  /// Insert, Measure, Edit) to offer, null meaning all of them. This is
  /// the way to disable a whole tool type at once. See
  /// [PdfEditingToolbar.groups].
  final Set<PdfEditToolGroup>? toolGroups;
}

/// A drop-in PDF editor: the [PdfViewer] with every editing tool wired
/// up — header with search and panel toggles, thumbnail/annotation/
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
/// on the device through [PdfEditingPreferences] — pass [preferences]
/// to share one instance across widgets, or leave null for a
/// self-contained one.
///
/// The widget owns the edit session (undo/redo, revisions). Hosts that
/// need programmatic access pass their own [controller] instead of
/// [bytes] — exactly one of the two must be given. [onSave] receives
/// the current revision's bytes from the toolbar's save button or the
/// ⌘S / Ctrl+S shortcut; [onDocumentChanged] fires after every revision
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
    this.features = const PdfEditorFeatures(),
    this.onSave,
    this.onDocumentChanged,
    this.onPickPdfToInsert,
    this.onExportPages,
    this.onAction,
    this.pageOverlayBuilder,
    this.annotationMenuBuilder,
    this.formImagePicker,
    this.imagePicker,
    this.onSnapshot,
    this.textPrompt,
    this.palette = PdfEditingToolbar.defaultPalette,
    this.toolbarLeading = const [],
    this.toolbarTrailing = const [],
    this.initialFit = PdfViewerFit.page,
    this.backgroundColor,
    this.pageColor,
    this.viewerTheme,
    this.rasterCache,
    this.textCache,
  })  : assert((bytes == null) != (controller == null),
            'Provide bytes or a controller, not both.'),
        assert(controller == null || preferences == null,
            'With an external controller, preferences come from it.');

  /// The PDF to edit. The widget owns the session; replacing the bytes
  /// (by identity) opens a fresh session in place.
  final Uint8List? bytes;

  /// Optional persistent on-disk preview cache (see [PdfRasterCache]).
  /// Keyed by [documentId] (or, with [bytes], their [pdfContentKey]), so
  /// reopening a previously-seen document paints soft page content
  /// immediately. Share one instance across the app to pool its budget.
  final PdfRasterCache? rasterCache;

  /// Optional persistent on-disk text cache (see [PdfPageTextCache]).
  /// Threaded to the viewer, but only consulted in read-only mode — an
  /// active edit session mutates page content, so its text is never served
  /// from the content-keyed persistent cache (in-memory only).
  final PdfPageTextCache? textCache;

  /// A stable identifier for this document, used to remember its scroll
  /// position and zoom across sessions (persisted in the preferences).
  /// With [bytes] a key is derived from the content when this is null;
  /// with an external [controller] (no bytes) pass one explicitly to
  /// enable the memory — a file path or URL is ideal.
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

  final PdfEditorFeatures features;

  /// Receives the current revision's bytes when the toolbar's save
  /// button is pressed or ⌘S / Ctrl+S is hit; the button (and the
  /// shortcut) are off when null. Writing the bytes somewhere is the
  /// app's job.
  final void Function(Uint8List bytes)? onSave;

  /// Called after every revision — edits, undo, redo — with the new
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

  /// See [PdfViewer.pageOverlayBuilder].
  final PdfPageOverlayBuilder? pageOverlayBuilder;

  /// See [PdfViewer.annotationMenuBuilder].
  final PdfAnnotationMenuBuilder? annotationMenuBuilder;

  /// See [PdfViewer.formImagePicker].
  final PdfFormImagePicker? formImagePicker;

  /// See [PdfViewer.imagePicker].
  final PdfImagePicker? imagePicker;

  /// See [PdfViewer.onSnapshot]. The snapshot tool always keeps a vector
  /// copy on the clipboard for in-app paste; this callback additionally
  /// exports the captured raster image (copy/save/share).
  final PdfSnapshotHandler? onSnapshot;

  /// How dialog-based tools ask for text. Defaults to
  /// [showPdfTextPrompt], a Material dialog.
  final PdfTextPrompt? textPrompt;

  /// The toolbar's color palette.
  final List<Color> palette;

  /// Custom widgets shown before the stock editing toolbar controls.
  ///
  /// Builders receive this editor view's edit session and viewer
  /// controller, including the internally owned ones when [bytes] is
  /// used.
  final List<PdfEditingToolbarWidgetBuilder> toolbarLeading;

  /// Custom widgets shown after the stock editing toolbar controls.
  final List<PdfEditingToolbarWidgetBuilder> toolbarTrailing;

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
  PdfEditingController? _ownedSession;
  PdfEditingPreferences? _ownedPrefs;
  PdfViewerController? _ownedViewer;
  PdfViewportMemory? _viewportMemory;

  // Routes the Apple Pencil's native double-tap to the session's eraser
  // toggle. Created only on iOS (the only platform with the gesture) so the
  // method-channel handler isn't claimed needlessly elsewhere.
  PdfPencilInteraction? _pencil;

  // Offloads page interpretation to a background isolate (native; a no-op
  // fallback on web), keyed to the session's current document. Pure scrolling
  // spawns one worker; every edit revision produces a new document, so the
  // stale worker is dropped (pages render locally = correct) and a fresh one
  // is started over the new bytes. Edits commit at most about once a second
  // (stroke auto-commit, blur, fill), so respawning per revision is cheap
  // enough without debouncing.
  PdfRenderWorker? _worker;
  PdfDocument? _workerDoc;

  final _searchField = TextEditingController();
  final _searchFocus = FocusNode();

  /// The revision length last reported through onDocumentChanged —
  /// revisions are byte prefixes of one buffer, so equal length means
  /// the same revision.
  late int _reportedLength;

  PdfEditingController get _session => widget.controller ?? _ownedSession!;

  PdfViewerController get _viewer =>
      widget.viewerController ?? (_ownedViewer ??= PdfViewerController());

  PdfEditingPreferences get _prefs => _session.preferences;

  /// A stable key for the open document, or null when there is nothing to
  /// key a remembered position on — an external controller with no
  /// [documentId]. With [bytes] one is derived from the content.
  String? get _documentKey {
    if (widget.documentId != null) return widget.documentId;
    final bytes = widget.bytes;
    return bytes == null ? null : pdfDocumentKey(bytes);
  }

  @override
  void initState() {
    super.initState();
    _openSession();
    // remember and restore where the user left this document
    final key = _documentKey;
    if (key != null) {
      _viewportMemory = PdfViewportMemory(
        viewer: _viewer,
        preferences: _prefs,
        documentKey: key,
      );
    }
  }

  void _openSession() {
    if (widget.bytes != null) {
      final prefs =
          widget.preferences ?? (_ownedPrefs ??= PdfEditingPreferences());
      _ownedSession = PdfEditingController(widget.bytes!, preferences: prefs);
    }
    _reportedLength = _session.bytes.length;
    _session.addListener(_onSessionChanged);
    _attachPencil();
    _syncWorker();
  }

  void _closeSession() {
    _pencil?.dispose();
    _pencil = null;
    _worker?.dispose();
    _worker = null;
    _workerDoc = null;
    _session.removeListener(_onSessionChanged);
    _ownedSession?.dispose();
    _ownedSession = null;
  }

  /// Binds the Apple Pencil double-tap to the session's eraser toggle on
  /// iOS, where the gesture exists. The shell stays plugin-free — the host's
  /// iOS runner registers the `UIPencilInteraction` and forwards it over
  /// [PdfPencilInteraction.channel]; this is the Dart end.
  void _attachPencil() {
    if (!widget.features.pencilEraserToggle) return;
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    (_pencil ??= PdfPencilInteraction()).attach(_session);
  }

  /// Keeps [_worker] tied to the session's current document — see the field
  /// doc. A revision (edit, undo, redo) changes the document identity, so
  /// the old worker is disposed and a new one started over the current bytes;
  /// disposing first means the just-edited page renders locally (correctly)
  /// until the new worker is ready.
  void _syncWorker() {
    if (identical(_session.document, _workerDoc)) return;
    _worker?.dispose();
    _worker = PdfRenderWorker.start(_session.bytes);
    _workerDoc = _session.document;
  }

  void _onSessionChanged() {
    // the merged ListenableBuilder rebuilds the viewer on this same notify,
    // so swapping the worker here is enough — no setState needed
    _syncWorker();
    final length = _session.bytes.length;
    if (length == _reportedLength) return;
    _reportedLength = length;
    widget.onDocumentChanged?.call(_session.bytes);
  }

  @override
  void didUpdateWidget(PdfEditorView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller ||
        !identical(widget.bytes, oldWidget.bytes) ||
        widget.documentId != oldWidget.documentId) {
      _closeSession();
      _searchField.clear();
      _openSession();
      final key = _documentKey;
      if (key != null) _viewportMemory?.rekey(key);
    }
  }

  @override
  void dispose() {
    _viewportMemory?.dispose();
    _closeSession();
    _ownedPrefs?.dispose();
    _ownedViewer?.dispose();
    _searchField.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _focusSearch() {
    _searchFocus.requestFocus();
    _searchField.selection =
        TextSelection(baseOffset: 0, extentOffset: _searchField.text.length);
  }

  void _save() => widget.onSave?.call(_session.bytes);

  Future<void> _promptAuthor() async {
    final session = _session;
    final name = await showPdfTextPrompt(context,
        title: 'Author name', initial: session.author ?? '');
    if (name == null) return;
    session.author = name.trim().isEmpty ? null : name.trim();
  }

  @override
  Widget build(BuildContext context) {
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
                bottomSheet: bottomSheet,
                // page-level file actions live in the strip's footer; insert
                // needs page editing on, export stands on its own
                onPickPdfToInsert:
                    features.pageEditing ? widget.onPickPdfToInsert : null,
                onExportPages: widget.onExportPages,
                renderWorker: _worker,
              );
          PdfSearchResultsPanel searchResults({required bool bottomSheet}) =>
              PdfSearchResultsPanel(
                key: ValueKey(
                    'pdf-shell-search-panel-${bottomSheet ? 'sheet' : 'docked'}'),
                controller: _viewer,
                preferences: prefs,
                bottomSheet: bottomSheet,
              );
          PdfAnnotationSidebar annotations({required bool bottomSheet}) =>
              PdfAnnotationSidebar(
                key: ValueKey(
                    'pdf-shell-annotations-${bottomSheet ? 'sheet' : 'docked'}'),
                controller: session,
                viewerController: _viewer,
                bottomSheet: bottomSheet,
              );
          PdfAnnotationPropertiesPanel properties({required bool bottomSheet}) =>
              PdfAnnotationPropertiesPanel(
                key: ValueKey(
                    'pdf-shell-properties-${bottomSheet ? 'sheet' : 'docked'}'),
                controller: session,
                showAuthor: features.authorEditable,
                bottomSheet: bottomSheet,
              );

          final showThumbnailsPanel = features.thumbnails && showThumbnails;
          final showSearchPanel = features.search &&
              features.searchResultsPanel &&
              prefs.showSearchResultsPanel;
          final showAnnotationsPanel =
              features.annotationSidebar && prefs.showAnnotationSidebar;
          final showPropertiesPanel =
              features.propertiesPanel && prefs.showPropertiesPanel;

          final sheets = !useSheets
              ? const <Widget>[]
              : <Widget>[
                  if (showThumbnailsPanel)
                    PdfPanelBottomSheet(
                      key: const ValueKey('pdf-shell-thumbnails-sheet'),
                      title: 'Pages',
                      closeKey:
                          const ValueKey('pdf-shell-thumbnails-sheet-close'),
                      onClose: () => prefs.showThumbnailSidebar = false,
                      child: thumbnails(bottomSheet: true),
                    ),
                  if (showSearchPanel)
                    PdfPanelBottomSheet(
                      key: const ValueKey('pdf-shell-search-sheet'),
                      title: 'Search results',
                      closeKey: const ValueKey('pdf-shell-search-sheet-close'),
                      onClose: () => prefs.showSearchResultsPanel = false,
                      child: searchResults(bottomSheet: true),
                    ),
                  if (showAnnotationsPanel)
                    PdfPanelBottomSheet(
                      key: const ValueKey('pdf-shell-annotations-sheet'),
                      title: 'Annotations',
                      closeKey:
                          const ValueKey('pdf-shell-annotations-sheet-close'),
                      onClose: () => prefs.showAnnotationSidebar = false,
                      child: annotations(bottomSheet: true),
                    ),
                  if (showPropertiesPanel)
                    PdfPanelBottomSheet(
                      key: const ValueKey('pdf-shell-properties-sheet'),
                      title: 'Properties',
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
          final showToolbar = features.toolbar && sheets.isEmpty;
          final dockToolbar = showToolbar &&
              constraints.maxWidth < PdfEditingToolbar.mobileBreakpoint;
          final toolbar = !showToolbar
              ? null
              : PdfEditingToolbar(
                  controller: session,
                  viewerController: _viewer,
                  // save lives in the header now, not the dock
                  textPrompt: widget.textPrompt ?? showPdfTextPrompt,
                  palette: widget.palette,
                  tools: features.tools,
                  groups: features.toolGroups,
                  showMarkup: features.markup,
                  showUndoRedo: features.undoRedo,
                  showColor: features.colorControls,
                  showStyle: features.styleControls,
                  showFlatten: features.flatten,
                  leading: widget.toolbarLeading,
                  trailing: widget.toolbarTrailing,
                );
          return Column(children: [
            if (features.headerBar)
              PdfShellBar(
                leading: [
                  if (features.search) ...[
                    PdfSearchField(
                      controller: _viewer,
                      searchController: _searchField,
                      focusNode: _searchFocus,
                      preferences: prefs,
                      // the match-case / whole-word / regex controls live in
                      // the results panel here, keeping the header compact
                      showOptions: !features.searchResultsPanel,
                    ),
                    if (features.searchResultsPanel)
                      PdfShellToggleButton(
                        key: const ValueKey('pdf-shell-search-results-toggle'),
                        icon: Icons.manage_search,
                        tooltip: 'Search results',
                        selected: prefs.showSearchResultsPanel,
                        onPressed: () => prefs.showSearchResultsPanel =
                            !prefs.showSearchResultsPanel,
                      ),
                  ],
                  if (features.pageNumber)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: PdfPageNumberField(controller: _viewer),
                    ),
                ],
                trailing: [
                  // Save sits in the header (near the host's Open), not in
                  // the floating toolbar — ⌘S/Ctrl+S takes the same path.
                  if (widget.onSave != null)
                    IconButton(
                      key: const ValueKey('pdf-shell-save'),
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.save_alt),
                      tooltip: 'Save… (⌘S / Ctrl+S)',
                      onPressed: _save,
                    ),
                  // insert/export of pages now live in the thumbnail
                  // strip's footer (see thumbnails() above)
                  if (features.author)
                    IconButton(
                      key: const ValueKey('pdf-shell-author'),
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.person_outline),
                      tooltip: 'Author name',
                      onPressed: _promptAuthor,
                    ),
                  if (features.viewOptions)
                    PdfShellViewOptionsButton(
                        preferences: prefs,
                        pageColor: features.pageColorEditable),
                  if (features.thumbnails)
                    PdfShellToggleButton(
                      key: const ValueKey('pdf-shell-thumbnails-toggle'),
                      icon: Icons.grid_view,
                      tooltip: 'Pages',
                      selected: showThumbnails,
                      onPressed: () =>
                          prefs.showThumbnailSidebar = !showThumbnails,
                    ),
                  if (features.annotationSidebar)
                    PdfShellToggleButton(
                      key: const ValueKey('pdf-shell-annotations-toggle'),
                      icon: Icons.list_alt,
                      tooltip: 'Annotations',
                      selected: prefs.showAnnotationSidebar,
                      onPressed: () => prefs.showAnnotationSidebar =
                          !prefs.showAnnotationSidebar,
                    ),
                  if (features.propertiesPanel)
                    PdfShellToggleButton(
                      key: const ValueKey('pdf-shell-properties-toggle'),
                      icon: Icons.tune,
                      tooltip: 'Properties',
                      selected: prefs.showPropertiesPanel,
                      onPressed: () => prefs.showPropertiesPanel =
                          !prefs.showPropertiesPanel,
                    ),
                ],
              ),
            Expanded(
              // on wide screens the toolbar floats over the bottom of the
              // content, Acrobat/Bluebeam-style; on phones it docks below
              // (see dockToolbar) so its solid bar never hides the page
              child: Stack(children: [
                Positioned.fill(
                  // keyed so a panel appearing never recreates the viewer
                  // element (which would reset the reading position)
                  child: Row(children: [
                    if (showThumbnailsPanel && !useSheets)
                      thumbnails(bottomSheet: false),
                    if (showSearchPanel && !useSheets)
                      searchResults(bottomSheet: false),
                    Expanded(
                      key: const ValueKey('pdf-shell-viewer'),
                      child: PdfViewer(
                        document: session.document,
                        controller: _viewer,
                        editing: session,
                        onAction: widget.onAction,
                        pageOverlayBuilder: widget.pageOverlayBuilder,
                        annotationMenuBuilder: widget.annotationMenuBuilder,
                        formImagePicker: widget.formImagePicker,
                        imagePicker: widget.imagePicker,
                        onSnapshot: widget.onSnapshot,
                        editingTextPrompt: widget.textPrompt,
                        initialFit: widget.initialFit,
                        backgroundColor: widget.backgroundColor,
                        pageColor: pageColor,
                        showAnnotations: prefs.showAnnotations,
                        highlightFormFields: prefs.highlightFormFields,
                        renderWorker: _worker,
                        rasterCache: widget.rasterCache,
                        textCache: widget.textCache,
                        documentId: _documentKey,
                      ),
                    ),
                    if (showAnnotationsPanel && !useSheets)
                      annotations(bottomSheet: false),
                    if (showPropertiesPanel && !useSheets)
                      properties(bottomSheet: false),
                  ]),
                ),
                if (toolbar != null && !dockToolbar)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: toolbar,
                  ),
                if (sheets.isNotEmpty) pdfShellBottomSheets(sheets),
              ]),
            ),
            // the mobile (solid-bar) toolbar docks below the content so it
            // never covers the page; the floating variant stays in the Stack
            if (toolbar != null && dockToolbar) toolbar,
          ]);
        },
      );
    });
    if (widget.viewerTheme != null) {
      body = PdfViewerTheme(data: widget.viewerTheme!, child: body);
    }
    final bindings = <ShortcutActivator, VoidCallback>{
      if (features.headerBar && features.search) ...{
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
            _focusSearch,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _focusSearch,
      },
      // ⌘S / Ctrl+S saves through the host's [onSave], the same path the
      // toolbar's save button takes.
      if (widget.onSave != null) ...{
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _save,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
      },
    };
    if (bindings.isNotEmpty) {
      body = CallbackShortcuts(bindings: bindings, child: body);
    }
    return body;
  }
}
