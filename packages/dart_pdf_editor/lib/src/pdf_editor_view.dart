import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'editing/editing_controller.dart';
import 'editing/editing_menu.dart';
import 'editing/editing_preferences.dart';
import 'editing/editing_properties.dart';
import 'editing/editing_sidebar.dart';
import 'editing/editing_thumbnails.dart';
import 'editing/editing_toolbar.dart';
import 'editing/text_prompt.dart';
import 'page_number_field.dart';
import 'pdf_viewer.dart';
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
    this.tools,
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

  /// The tool buttons to offer, null meaning all of them. See
  /// [PdfEditingToolbar.tools].
  final Set<PdfEditTool>? tools;
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
    this.onAction,
    this.pageOverlayBuilder,
    this.annotationMenuBuilder,
    this.formImagePicker,
    this.textPrompt,
    this.palette = PdfEditingToolbar.defaultPalette,
    this.toolbarLeading = const [],
    this.toolbarTrailing = const [],
    this.initialFit = PdfViewerFit.page,
    this.backgroundColor,
    this.pageColor,
    this.viewerTheme,
  })  : assert((bytes == null) != (controller == null),
            'Provide bytes or a controller, not both.'),
        assert(controller == null || preferences == null,
            'With an external controller, preferences come from it.');

  /// The PDF to edit. The widget owns the session; replacing the bytes
  /// (by identity) opens a fresh session in place.
  final Uint8List? bytes;

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

  /// See [PdfViewer.onAction].
  final PdfActionHandler? onAction;

  /// See [PdfViewer.pageOverlayBuilder].
  final PdfPageOverlayBuilder? pageOverlayBuilder;

  /// See [PdfViewer.annotationMenuBuilder].
  final PdfAnnotationMenuBuilder? annotationMenuBuilder;

  /// See [PdfViewer.formImagePicker].
  final PdfFormImagePicker? formImagePicker;

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
  }

  void _closeSession() {
    _session.removeListener(_onSessionChanged);
    _ownedSession?.dispose();
    _ownedSession = null;
  }

  void _onSessionChanged() {
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

          PdfThumbnailSidebar thumbnails({required bool bottomSheet}) =>
              PdfThumbnailSidebar(
                key: const ValueKey('pdf-shell-thumbnails'),
                controller: session,
                viewerController: _viewer,
                pageColor: pageColor,
                showAnnotations: prefs.showAnnotations,
                allowPageEditing: features.pageEditing,
                bottomSheet: bottomSheet,
              );
          PdfSearchResultsPanel searchResults({required bool bottomSheet}) =>
              PdfSearchResultsPanel(
                key: const ValueKey('pdf-shell-search-panel'),
                controller: _viewer,
                preferences: prefs,
                bottomSheet: bottomSheet,
              );
          PdfAnnotationSidebar annotations({required bool bottomSheet}) =>
              PdfAnnotationSidebar(
                key: const ValueKey('pdf-shell-annotations'),
                controller: session,
                viewerController: _viewer,
                bottomSheet: bottomSheet,
              );
          PdfAnnotationPropertiesPanel properties({required bool bottomSheet}) =>
              PdfAnnotationPropertiesPanel(
                key: const ValueKey('pdf-shell-properties'),
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
          return Column(children: [
            if (features.headerBar)
              PdfShellBar(
                leading: [
                  if (features.search) ...[
                    PdfSearchField(
                      controller: _viewer,
                      searchController: _searchField,
                      focusNode: _searchFocus,
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
              // the toolbar floats over the bottom of the content,
              // Acrobat/Bluebeam-style, rather than sitting in a solid
              // edge-to-edge bar below it
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
                        editingTextPrompt: widget.textPrompt,
                        initialFit: widget.initialFit,
                        backgroundColor: widget.backgroundColor,
                        pageColor: pageColor,
                        showAnnotations: prefs.showAnnotations,
                        highlightFormFields: prefs.highlightFormFields,
                      ),
                    ),
                    if (showAnnotationsPanel && !useSheets)
                      annotations(bottomSheet: false),
                    if (showPropertiesPanel && !useSheets)
                      properties(bottomSheet: false),
                  ]),
                ),
                if (features.toolbar && sheets.isEmpty)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: PdfEditingToolbar(
                      controller: session,
                      viewerController: _viewer,
                      // save lives in the header now, not the dock
                      textPrompt: widget.textPrompt ?? showPdfTextPrompt,
                      palette: widget.palette,
                      tools: features.tools,
                      showMarkup: features.markup,
                      showUndoRedo: features.undoRedo,
                      showColor: features.colorControls,
                      showStyle: features.styleControls,
                      showFlatten: features.flatten,
                      leading: widget.toolbarLeading,
                      trailing: widget.toolbarTrailing,
                    ),
                  ),
                if (sheets.isNotEmpty) pdfShellBottomSheets(sheets),
              ]),
            ),
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
