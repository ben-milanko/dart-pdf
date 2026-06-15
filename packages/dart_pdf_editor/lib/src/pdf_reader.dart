import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

import 'editing/editing_controller.dart';
import 'editing/editing_preferences.dart';
import 'editing/editing_thumbnails.dart';
import 'page_number_field.dart';
import 'pdf_reflow_view.dart';
import 'pdf_viewer.dart';
import 'raster_cache.dart';
import 'render_worker.dart';
import 'search_panel.dart';
import 'shell_chrome.dart';
import 'theme.dart';

/// Which pieces of chrome a [PdfReader] shows. Everything defaults on;
/// turn features off rather than rebuilding the layout by hand.
class PdfReaderFeatures {
  const PdfReaderFeatures({
    this.headerBar = true,
    this.search = true,
    this.pageNumber = true,
    this.thumbnails = true,
    this.viewOptions = true,
    this.pageColorEditable = true,
    this.fillForms = true,
  });

  /// Just the pages: no header bar and no panels.
  const PdfReaderFeatures.none()
      : this(
          headerBar: false,
          search: false,
          pageNumber: false,
          thumbnails: false,
          viewOptions: false,
        );

  /// The slim bar above the viewer. With it off the remaining features
  /// lose their buttons, so most are moot — panels still follow the
  /// persisted preferences.
  final bool headerBar;

  /// The search field (with live results stepping) and the ⌘F/Ctrl+F
  /// shortcut.
  final bool search;

  /// The editable "page / count" field.
  final bool pageNumber;

  /// The page-thumbnail sidebar and its header toggle. Read-only here:
  /// tiles navigate, but pages can't be reordered or deleted.
  final bool thumbnails;

  /// The view-options menu: annotation visibility, form-field
  /// highlight, and page (paper) color — display settings only.
  final bool viewOptions;

  /// Whether the view-options menu offers "Page color…". With it false
  /// the paper color can't be changed from the UI — for hosts that set
  /// the page color from the document programmatically and lock it.
  final bool pageColorEditable;

  /// Whether form fields can be filled in (text entry, check boxes,
  /// radio buttons, drop-downs) — the only document mutation the reader
  /// allows, since forms are made to be filled. Filled values live in
  /// the reader's session for the life of the widget; surfacing them as
  /// bytes (to save) needs the full [PdfEditorView]. Off makes the
  /// reader strictly display-only.
  final bool fillForms;
}

/// A drop-in, view-only PDF widget: the [PdfViewer] plus a slim header
/// with search, a page-number field, view options, and a navigational
/// thumbnail sidebar. No editing — for the full editor, use
/// [PdfEditorView].
///
/// ```dart
/// PdfReader(bytes: pdfBytes)
/// ```
///
/// All chrome follows the ambient Material [Theme]; the viewer's own
/// colors can be tuned with [viewerTheme] (or an inherited
/// [PdfViewerTheme]). Features toggle off via [features]. Display
/// preferences (panel visibility and widths, page color) persist on the
/// device through [PdfEditingPreferences] — pass [preferences] to share
/// one instance across widgets, or leave null for a self-contained one.
///
/// The widget is a plain body: give it bounded space (a [Scaffold]
/// body, an [Expanded]...). Swapping [bytes] for a different document
/// reopens in place.
class PdfReader extends StatefulWidget {
  const PdfReader({
    super.key,
    required this.bytes,
    this.documentId,
    this.controller,
    this.preferences,
    this.features = const PdfReaderFeatures(),
    this.onAction,
    this.pageOverlayBuilder,
    this.initialFit = PdfViewerFit.page,
    this.backgroundColor,
    this.pageColor,
    this.viewerTheme,
    this.rasterCache,
    this.textCache,
  });

  /// The PDF to show. Replacing it (by identity) opens the new
  /// document in place.
  final Uint8List bytes;

  /// Optional persistent on-disk preview cache (see [PdfRasterCache]).
  /// Keyed by [documentId] (or the bytes' [pdfContentKey]), so reopening
  /// a previously-seen document paints soft page content immediately.
  /// Share one instance across the app to pool its byte budget.
  final PdfRasterCache? rasterCache;

  /// Optional persistent on-disk text cache (see [PdfPageTextCache]). Keyed
  /// by [documentId], so reopening a document searches it without re-walking
  /// every page's content stream.
  final PdfPageTextCache? textCache;

  /// A stable identifier for this document, used to remember its scroll
  /// position and zoom across sessions (persisted in [preferences]). Null
  /// derives a key from the bytes; pass a file path or URL when you have
  /// one, so the position survives the bytes being re-read.
  final String? documentId;

  /// Optional external viewer controller, for hosts that navigate or
  /// search programmatically.
  final PdfViewerController? controller;

  /// The persisted display preferences. Defaults to a private instance.
  final PdfEditingPreferences? preferences;

  final PdfReaderFeatures features;

  /// See [PdfViewer.onAction].
  final PdfActionHandler? onAction;

  /// See [PdfViewer.pageOverlayBuilder].
  final PdfPageOverlayBuilder? pageOverlayBuilder;

  /// See [PdfViewer.initialFit].
  final PdfViewerFit initialFit;

  /// See [PdfViewer.backgroundColor].
  final Color? backgroundColor;

  /// The paper color. Null follows the persisted preference (white by
  /// default); setting it pins the color and hides nothing else.
  final Color? pageColor;

  /// Viewer colors (selection, search matches, scrollbar...). Null
  /// uses an inherited [PdfViewerTheme] or the stock look.
  final PdfViewerThemeData? viewerTheme;

  @override
  State<PdfReader> createState() => _PdfReaderState();
}

class _PdfReaderState extends State<PdfReader> {
  // the session wraps the bytes for the viewer and the thumbnail
  // strip's caches; the reader makes no structural edits, so the
  // document stays byte-identical to the input — except form fills
  // (PdfReaderFeatures.fillForms), the one mutation a reader allows
  late PdfEditingController _session;
  PdfEditingPreferences? _ownedPrefs;
  PdfViewerController? _ownedViewer;
  PdfViewportMemory? _viewportMemory;

  // Offloads page interpretation to a background isolate (native; a no-op
  // fallback on web). Keyed to the session's current document: pure reading
  // spawns one worker for the life of the document, and the rare form-fill
  // revision respawns it over the new bytes so it never serves a stale page.
  PdfRenderWorker? _worker;
  PdfDocument? _workerDoc;

  final _searchField = TextEditingController();
  final _searchFocus = FocusNode();

  PdfViewerController get _viewer =>
      widget.controller ?? (_ownedViewer ??= PdfViewerController());

  PdfEditingPreferences get _prefs => _session.preferences;

  String get _documentKey => widget.documentId ?? pdfDocumentKey(widget.bytes);

  @override
  void initState() {
    super.initState();
    _openSession();
    // remember and restore where the user left this document
    _viewportMemory = PdfViewportMemory(
      viewer: _viewer,
      preferences: _prefs,
      documentKey: _documentKey,
    );
  }

  void _openSession() {
    final prefs =
        widget.preferences ?? (_ownedPrefs ??= PdfEditingPreferences());
    _session = PdfEditingController(widget.bytes, preferences: prefs);
    _session.addListener(_syncWorker);
    _syncWorker();
  }

  /// Keeps [_worker] tied to the session's current document. Reading never
  /// changes it (one spawn for the document's life); a form fill produces a
  /// new revision, so the old worker — which holds the pre-fill bytes — is
  /// disposed and a fresh one started over the new bytes. Disposing first
  /// means pages render locally (correctly) during the brief respawn rather
  /// than from a stale isolate.
  void _syncWorker() {
    if (identical(_session.document, _workerDoc)) return;
    _worker?.dispose();
    _worker = PdfRenderWorker.start(_session.bytes);
    _workerDoc = _session.document;
  }

  @override
  void didUpdateWidget(PdfReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.bytes, oldWidget.bytes) ||
        widget.documentId != oldWidget.documentId) {
      final previous = _session;
      previous.removeListener(_syncWorker);
      _searchField.clear();
      _openSession();
      _viewportMemory?.rekey(_documentKey);
      previous.dispose();
    }
  }

  @override
  void dispose() {
    _viewportMemory?.dispose();
    _worker?.dispose();
    _session.removeListener(_syncWorker);
    _session.dispose();
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

  @override
  Widget build(BuildContext context) {
    final features = widget.features;
    Widget body = LayoutBuilder(builder: (context, constraints) {
      return ListenableBuilder(
        listenable: _prefs,
        builder: (context, _) {
          final prefs = _prefs;
          final pageColor = widget.pageColor ?? prefs.pageColor;
          final showThumbnails =
              pdfShellShowThumbnailSidebar(prefs, constraints);
          // on a narrow screen the strip floats up from the bottom as a
          // sheet instead of docking to the side and crowding the page
          final useSheets = pdfShellUseBottomSheets(constraints);
          final showThumbnailsPanel =
              features.thumbnails && showThumbnails && !prefs.showReflowView;

          // Distinct keys for docked vs sheet so the strip is remounted, not
          // reparented, when the breakpoint flips — reparenting reactivates
          // the tiles' Tooltip overlays mid-layout (a RenderObject mutation
          // assertion). See the matching note in pdf_editor_view.dart.
          PdfThumbnailSidebar thumbnails({required bool bottomSheet}) =>
              PdfThumbnailSidebar(
                key: ValueKey(
                    'pdf-shell-thumbnails-${bottomSheet ? 'sheet' : 'docked'}'),
                controller: _session,
                viewerController: _viewer,
                pageColor: pageColor,
                showAnnotations: prefs.showAnnotations,
                allowPageEditing: false,
                bottomSheet: bottomSheet,
                renderWorker: _worker,
              );
          return Column(children: [
            if (features.headerBar)
              PdfShellBar(
                leading: [
                  if (features.search && !prefs.showReflowView)
                    PdfSearchField(
                      controller: _viewer,
                      searchController: _searchField,
                      focusNode: _searchFocus,
                    ),
                  if (features.pageNumber && !prefs.showReflowView)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: PdfPageNumberField(controller: _viewer),
                    ),
                ],
                trailing: [
                  if (features.viewOptions)
                    PdfShellViewOptionsButton(
                        preferences: prefs,
                        reflow: true,
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
                ],
              ),
            Expanded(
              // keyed so a panel appearing never recreates the viewer
              // element (which would reset the reading position)
              child: Stack(children: [
                Positioned.fill(
                  child: Row(children: [
                    if (showThumbnailsPanel && !useSheets)
                      thumbnails(bottomSheet: false),
                    Expanded(
                      key: const ValueKey('pdf-shell-viewer'),
                      // rebuilds on session changes too: filling a form
                      // produces a revision, so the viewer must track
                      // _session.document, not the build-time snapshot
                      child: ListenableBuilder(
                        listenable: _session,
                        builder: (context, _) => prefs.showReflowView
                            ? PdfReflowView(
                                document: _session.document,
                                backgroundColor: widget.backgroundColor,
                              )
                            : PdfViewer(
                                document: _session.document,
                                controller: _viewer,
                                formController:
                                    features.fillForms ? _session : null,
                                onAction: widget.onAction,
                                pageOverlayBuilder: widget.pageOverlayBuilder,
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
                    ),
                  ]),
                ),
                if (useSheets && showThumbnailsPanel)
                  pdfShellBottomSheets([
                    PdfPanelBottomSheet(
                      key: const ValueKey('pdf-shell-thumbnails-sheet'),
                      title: 'Pages',
                      closeKey:
                          const ValueKey('pdf-shell-thumbnails-sheet-close'),
                      onClose: () => prefs.showThumbnailSidebar = false,
                      child: thumbnails(bottomSheet: true),
                    ),
                  ]),
              ]),
            ),
          ]);
        },
      );
    });
    if (widget.viewerTheme != null) {
      body = PdfViewerTheme(data: widget.viewerTheme!, child: body);
    }
    if (features.headerBar && features.search) {
      body = CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
              _focusSearch,
          const SingleActivator(LogicalKeyboardKey.keyF, control: true):
              _focusSearch,
        },
        child: body,
      );
    }
    return body;
  }
}
