import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

import 'editing/editing_bookmarks.dart';
import 'editing/editing_controller.dart';
import 'editing/editing_interaction.dart';
import 'editing/editing_preferences.dart';
import 'editing/editing_thumbnails.dart';
import 'l10n/pdf_l10n.dart';
import 'page_number_field.dart';
import 'performance_policy.dart';
import 'pdf_reflow_view.dart';
import 'pdf_viewer.dart';
import 'preview_cache.dart';
import 'raster_warm.dart';
import 'progressive_source.dart';
import 'raster_cache.dart';
import 'search_panel.dart';
import 'shell_chrome.dart';
import 'shell_session.dart';
import 'theme.dart';
import 'tile_raster_backend.dart';

/// Which pieces of chrome a [PdfReader] shows. Everything defaults on;
/// turn features off rather than rebuilding the layout by hand.
class PdfReaderFeatures {
  const PdfReaderFeatures({
    this.headerBar = true,
    this.search = true,
    this.pageNumber = true,
    this.thumbnails = true,
    this.bookmarks = true,
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
          bookmarks: false,
          viewOptions: false,
        );

  /// The slim bar above the viewer. With it off the remaining features
  /// lose their buttons, so most are moot - panels still follow the
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

  /// The PDF bookmarks/outline sidebar and its header toggle. Read-only
  /// here: items navigate but cannot be authored.
  final bool bookmarks;

  /// The view-options menu: annotation visibility, form-field
  /// highlight, and page (paper) color - display settings only.
  final bool viewOptions;

  /// Whether the view-options menu offers "Page color…". With it false
  /// the paper color can't be changed from the UI - for hosts that set
  /// the page color from the document programmatically and lock it.
  final bool pageColorEditable;

  /// Whether form fields can be filled in (text entry, check boxes,
  /// radio buttons, drop-downs) - the only document mutation the reader
  /// allows, since forms are made to be filled. Filled values live in
  /// the reader's session for the life of the widget; surfacing them as
  /// bytes (to save) needs the full [PdfEditorView]. Off makes the
  /// reader strictly display-only.
  final bool fillForms;
}

/// A drop-in, view-only PDF widget: the [PdfViewer] plus a slim header
/// with search, a page-number field, view options, and a navigational
/// thumbnail sidebar. No editing - for the full editor, use
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
/// device through [PdfEditingPreferences] - pass [preferences] to share
/// one instance across widgets, or leave null for a self-contained one.
///
/// The widget is a plain body: give it bounded space (a [Scaffold]
/// body, an [Expanded]...). Swapping [bytes] for a different document
/// reopens in place.
///
/// ## Progressive open from a source
///
/// [PdfReader.source] points the reader at a [PdfByteSource] (an HTTP URL via
/// [PdfHttpByteSource], a host's own file or cloud source) and paints page one
/// from ranged reads before the whole file has downloaded, then swaps the
/// complete buffer in behind the scenes:
///
/// ```dart
/// PdfReader.source(
///   PdfHttpByteSource(Uri.parse(url)),
///   documentId: url,
///   onProgress: (received, total) => setDownloadFraction(received, total),
/// )
/// ```
class PdfReader extends StatefulWidget {
  const PdfReader({
    super.key,
    required Uint8List this.bytes,
    this.documentId,
    this.controller,
    this.preferences,
    this.performance,
    this.tileRasterBackend = const PdfCanvasTileRasterBackend(),
    this.features = const PdfReaderFeatures(),
    this.onAction,
    this.onAnnotationTap,
    this.onLaunchUrl,
    this.onShareReflowImage,
    this.pageOverlayBuilder,
    this.contextMenuEnabled = true,
    this.onContextMenuRequested,
    this.pageLayout = const PdfPageLayout.verticalContinuous(),
    this.initialFit = PdfViewerFit.page,
    this.backgroundColor,
    this.pageColor,
    this.viewerTheme,
    this.rasterCache,
    this.textCache,
    this.pageRasterCachePolicy = const PdfPageRasterCachePolicy(),
    this.pageRasterWarmPolicy = const PdfPageRasterWarmPolicy.disabled(),
  })  : source = null,
        options = const PdfSourceLoadOptions(firstPaintPages: 1),
        onProgress = null,
        onFirstPaint = null,
        loadingBuilder = null,
        errorBuilder = null;

  /// A view-only reader that opens progressively from a [PdfByteSource].
  ///
  /// Page one paints from a sparse first-paint open ([options],
  /// defaulting to the first page) while the rest of the file downloads in the
  /// background; when it lands the full buffer swaps in place. Pass a stable
  /// [documentId] (the URL or path) so remembered scroll/zoom survive the swap.
  /// [onProgress] reports the background read; [onFirstPaint] fires when
  /// the first page is ready. Falls back to a plain full read (no early paint)
  /// when the source can't serve useful ranges. The in-flight load is cancelled
  /// when the widget is disposed; the [source] is host-owned and not closed.
  const PdfReader.source(
    PdfByteSource this.source, {
    super.key,
    this.options = const PdfSourceLoadOptions(firstPaintPages: 1),
    this.documentId,
    this.onProgress,
    this.onFirstPaint,
    this.loadingBuilder,
    this.errorBuilder,
    this.controller,
    this.preferences,
    this.performance,
    this.tileRasterBackend = const PdfCanvasTileRasterBackend(),
    this.features = const PdfReaderFeatures(),
    this.onAction,
    this.onAnnotationTap,
    this.onLaunchUrl,
    this.onShareReflowImage,
    this.pageOverlayBuilder,
    this.contextMenuEnabled = true,
    this.onContextMenuRequested,
    this.pageLayout = const PdfPageLayout.verticalContinuous(),
    this.initialFit = PdfViewerFit.page,
    this.backgroundColor,
    this.pageColor,
    this.viewerTheme,
    this.rasterCache,
    this.textCache,
    this.pageRasterCachePolicy = const PdfPageRasterCachePolicy(),
    this.pageRasterWarmPolicy = const PdfPageRasterWarmPolicy.disabled(),
  }) : bytes = null;

  /// The PDF to show. Replacing it (by identity) opens the new
  /// document in place. Null when opened from a [source].
  final Uint8List? bytes;

  /// The source to open progressively (via [PdfReader.source]); null for the
  /// byte-based reader.
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
  /// Keyed by [documentId] (or the bytes' [pdfContentKey]), so reopening
  /// a previously-seen document paints soft page content immediately.
  /// Share one instance across the app to pool its byte budget.
  final PdfRasterCache? rasterCache;

  /// Optional persistent on-disk text cache (see [PdfPageTextCache]). Keyed
  /// by [documentId], so reopening a document searches it without re-walking
  /// every page's content stream.
  final PdfPageTextCache? textCache;

  /// Memory policy for exact full-resolution rasters of previously visited
  /// pages. See [PdfViewer.pageRasterCachePolicy].
  final PdfPageRasterCachePolicy pageRasterCachePolicy;

  /// Whether idle time is spent baking exact page rasters ahead of
  /// navigation. See [PdfViewer.pageRasterWarmPolicy].
  final PdfPageRasterWarmPolicy pageRasterWarmPolicy;

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

  /// Optional adaptive/fixed performance controller. Null creates an owned
  /// Auto controller. Pass one to select fixed worker settings at runtime or
  /// expose [PdfPerformanceController.diagnostics] in host UI.
  final PdfPerformanceController? performance;

  /// See [PdfViewer.tileRasterBackend].
  final PdfTileRasterBackend tileRasterBackend;

  final PdfReaderFeatures features;

  /// See [PdfViewer.onAction].
  final PdfActionHandler? onAction;

  /// See [PdfViewer.onAnnotationTap].
  final PdfAnnotationTapHandler? onAnnotationTap;

  /// See [PdfViewer.onLaunchUrl].
  final PdfUrlLauncher? onLaunchUrl;

  /// Saves or shares a figure the reader taps to open fullscreen in the text
  /// reflow view (see [PdfReflowView.onShareImage]). Null still allows
  /// fullscreen pan/pinch-zoom viewing; it just hides the share action.
  final PdfReflowImageShareHandler? onShareReflowImage;

  /// See [PdfViewer.pageOverlayBuilder].
  final PdfPageOverlayBuilder? pageOverlayBuilder;

  /// See [PdfViewer.contextMenuEnabled].
  final bool contextMenuEnabled;

  /// See [PdfViewer.onContextMenuRequested].
  final PdfContextMenuHost? onContextMenuRequested;

  /// See [PdfViewer.pageLayout].
  final PdfPageLayout pageLayout;

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
  late PdfShellSessionLifecycle _shell;

  PdfEditingController get _session => _shell.session;
  PdfViewerController get _viewer => _shell.viewer;
  PdfEditingPreferences get _prefs => _shell.preferences;
  PdfPerformanceController get _performance => _shell.performance;
  String get _documentKey => _shell.documentKey!;
  TextEditingController get _searchField => _shell.searchController;
  FocusNode get _searchFocus => _shell.searchFocus;

  bool get _isSource => widget.source != null;

  @override
  void initState() {
    super.initState();
    // In source mode the shell is owned by the inner byte-based PdfReader the
    // progressive builder mounts once the first-paint bytes arrive.
    if (_isSource) return;
    _shell = PdfShellSessionLifecycle(
      bytes: widget.bytes,
      controller: null,
      preferences: widget.preferences,
      viewerController: widget.controller,
      performance: widget.performance,
      documentId: widget.documentId,
    );
  }

  @override
  void didUpdateWidget(PdfReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isSource) return;
    _shell.update(
      bytes: widget.bytes,
      controller: null,
      preferences: widget.preferences,
      viewerController: widget.controller,
      performanceController: widget.performance,
      documentId: widget.documentId,
    );
  }

  @override
  void dispose() {
    if (!_isSource) _shell.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isSource) return _buildFromSource();
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
          // Pages and Bookmarks stay available in the reflow reading view -
          // they drive it through the shared controller (page taps scroll the
          // reader, the strip tracks the reading position).
          final showThumbnailsPanel = features.thumbnails && showThumbnails;
          final showBookmarksPanel =
              features.bookmarks && prefs.showBookmarkSidebar;

          // Distinct keys for docked vs sheet so the strip is remounted, not
          // reparented, when the breakpoint flips - reparenting reactivates
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
                // the sheet chrome carries its own close button
                onClose: bottomSheet
                    ? null
                    : () => prefs.showThumbnailSidebar = false,
                renderWorker: _shell.worker,
              );
          PdfBookmarkSidebar bookmarks({required bool bottomSheet}) =>
              PdfBookmarkSidebar(
                key: ValueKey(
                    'pdf-shell-bookmarks-${bottomSheet ? 'sheet' : 'docked'}'),
                controller: _session,
                viewerController: _viewer,
                editable: false,
                bottomSheet: bottomSheet,
                onClose: bottomSheet
                    ? null
                    : () => prefs.showBookmarkSidebar = false,
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
                      preferences: prefs,
                    ),
                  if (features.pageNumber && !prefs.showReflowView)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: PdfPageNumberField(controller: _viewer),
                    ),
                  if (!prefs.showReflowView)
                    PdfShellZoomControl(controller: _viewer),
                ],
                compactLeading: [
                  if (features.search && !prefs.showReflowView)
                    PdfSearchField(
                      controller: _viewer,
                      searchController: _searchField,
                      focusNode: _searchFocus,
                      preferences: prefs,
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
                  PdfShellPanelSwitch(items: [
                    if (features.thumbnails)
                      PdfShellPanelItem(
                        key: const ValueKey('pdf-shell-thumbnails-toggle'),
                        icon: Icons.grid_view,
                        tooltip: pdfL10n(context).shellPanelPages,
                        selected: showThumbnails,
                        onPressed: () =>
                            prefs.showThumbnailSidebar = !showThumbnails,
                      ),
                    if (features.bookmarks)
                      PdfShellPanelItem(
                        key: const ValueKey('pdf-shell-bookmarks-toggle'),
                        icon: Icons.bookmarks_outlined,
                        tooltip: pdfL10n(context).shellPanelBookmarks,
                        selected: prefs.showBookmarkSidebar,
                        onPressed: () => prefs.showBookmarkSidebar =
                            !prefs.showBookmarkSidebar,
                      ),
                  ]),
                ],
                compactSheetChildren: [
                  if (!prefs.showReflowView)
                    PdfShellZoomControl(controller: _viewer),
                ],
                compactControls: [
                  if (features.viewOptions)
                    PdfShellControlItem(
                      key: const ValueKey('pdf-shell-view-options'),
                      icon: Icons.display_settings_outlined,
                      label: pdfL10n(context).shellSettings,
                      onPressed: () {
                        showPdfShellViewOptionsSheet(
                          context,
                          preferences: prefs,
                          reflow: true,
                          pageColor: features.pageColorEditable,
                        );
                      },
                    ),
                  // A direct Reflow toggle for phone readers, who reach for the
                  // reading view most - no need to dig into Settings.
                  PdfShellControlItem(
                    key: const ValueKey('pdf-shell-reflow-toggle'),
                    icon: Icons.article_outlined,
                    label: pdfL10n(context).shellReflow,
                    selected: prefs.showReflowView,
                    onPressed: () =>
                        prefs.showReflowView = !prefs.showReflowView,
                  ),
                  if (features.thumbnails)
                    PdfShellControlItem(
                      key: const ValueKey('pdf-shell-thumbnails-toggle'),
                      icon: Icons.grid_view,
                      label: pdfL10n(context).shellPanelPages,
                      selected: showThumbnails,
                      onPressed: () =>
                          prefs.showThumbnailSidebar = !showThumbnails,
                    ),
                  if (features.bookmarks)
                    PdfShellControlItem(
                      key: const ValueKey('pdf-shell-bookmarks-toggle'),
                      icon: Icons.bookmarks_outlined,
                      label: pdfL10n(context).shellPanelBookmarks,
                      selected: prefs.showBookmarkSidebar,
                      onPressed: () => prefs.showBookmarkSidebar =
                          !prefs.showBookmarkSidebar,
                    ),
                ],
              ),
            Expanded(
              child: PdfShellPanelLayout(
                leadingPanels: [
                  if (showThumbnailsPanel && !useSheets)
                    thumbnails(bottomSheet: false),
                  if (showBookmarksPanel && !useSheets)
                    bookmarks(bottomSheet: false),
                ],
                // rebuilds on session changes too: filling a form produces a
                // revision, so the viewer must track _session.document, not
                // the build-time snapshot
                viewer: ListenableBuilder(
                  listenable: _session,
                  builder: (context, _) => prefs.showReflowView
                      ? PdfReflowView(
                          document: _session.document,
                          controller: _viewer,
                          onShareImage: widget.onShareReflowImage,
                          backgroundColor: widget.backgroundColor,
                        )
                      : PdfViewer(
                          document: _session.document,
                          controller: _viewer,
                          formController: features.fillForms ? _session : null,
                          onAction: widget.onAction,
                          onAnnotationTap: widget.onAnnotationTap,
                          onLaunchUrl: widget.onLaunchUrl,
                          pageOverlayBuilder: widget.pageOverlayBuilder,
                          contextMenuEnabled: widget.contextMenuEnabled,
                          onContextMenuRequested: widget.onContextMenuRequested,
                          pageLayout: widget.pageLayout,
                          initialFit: widget.initialFit,
                          backgroundColor: widget.backgroundColor,
                          pageColor: pageColor,
                          showAnnotations: prefs.showAnnotations,
                          showScrollbarChapters: prefs.showScrollbarChapters,
                          highlightFormFields: prefs.highlightFormFields,
                          renderWorker: _shell.worker,
                          performance: _performance,
                          tileRasterBackend: widget.tileRasterBackend,
                          rasterCache: widget.rasterCache,
                          textCache: widget.textCache,
                          pageRasterCachePolicy: widget.pageRasterCachePolicy,
                          pageRasterWarmPolicy: widget.pageRasterWarmPolicy,
                          documentId: _documentKey,
                        ),
                ),
                bottomSheets: [
                  if (useSheets && showThumbnailsPanel)
                    PdfPanelBottomSheet(
                      key: const ValueKey('pdf-shell-thumbnails-sheet'),
                      title: pdfL10n(context).shellPanelPages,
                      closeKey:
                          const ValueKey('pdf-shell-thumbnails-sheet-close'),
                      onClose: () => prefs.showThumbnailSidebar = false,
                      child: thumbnails(bottomSheet: true),
                    ),
                  if (useSheets && showBookmarksPanel)
                    PdfPanelBottomSheet(
                      key: const ValueKey('pdf-shell-bookmarks-sheet'),
                      title: pdfL10n(context).shellPanelBookmarks,
                      closeKey:
                          const ValueKey('pdf-shell-bookmarks-sheet-close'),
                      onClose: () => prefs.showBookmarkSidebar = false,
                      child: bookmarks(bottomSheet: true),
                    ),
                ],
              ),
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
        bindings: _shell.searchShortcuts(enabled: true),
        child: body,
      );
    }
    return body;
  }

  /// The progressive-open path: paint page one from the sparse first-paint
  /// buffer, then swap the full buffer in place. The inner byte-based
  /// [PdfReader] owns the session/worker, so it reopens in place across the
  /// swap and (with a stable [PdfReader.documentId]) keeps its scroll position.
  Widget _buildFromSource() {
    return PdfProgressiveSourceBuilder(
      source: widget.source!,
      options: widget.options,
      onProgress: widget.onProgress,
      onFirstPaint: widget.onFirstPaint,
      loadingBuilder: widget.loadingBuilder,
      errorBuilder: widget.errorBuilder,
      builder: (context, bytes, complete) => PdfReader(
        bytes: bytes,
        documentId: widget.documentId,
        controller: widget.controller,
        preferences: widget.preferences,
        performance: widget.performance,
        tileRasterBackend: widget.tileRasterBackend,
        features: widget.features,
        onAction: widget.onAction,
        onAnnotationTap: widget.onAnnotationTap,
        onLaunchUrl: widget.onLaunchUrl,
        pageOverlayBuilder: widget.pageOverlayBuilder,
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
}
