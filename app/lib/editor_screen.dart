import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_info.dart';
import 'autosave.dart';
import 'devtools.dart';
import 'devtools_panel.dart';
import 'digital_signature.dart';
import 'doc_scan.dart';
import 'document_tab.dart';
import 'file_io.dart';
import 'image_clipboard.dart';
import 'image_export.dart';
import 'image_source_picker.dart';
import 'incoming_file.dart';
import 'keyless_identity_cache.dart';
import 'keyless_signing.dart';
import 'l10n/app_l10n.dart';
import 'new_document.dart';
import 'ocr.dart';
import 'ocr_status_label.dart';
import 'pdf_cache.dart';
import 'print_preview_dialog.dart';
import 'print_progress_dialog.dart';
import 'printing.dart';
import 'recent_thumbnails.dart';
import 'recents.dart';
import 'session_store.dart';
import 'settings_screen.dart';
import 'tab_drag.dart';
import 'unsaved_changes.dart';
import 'unsaved_changes_store.dart';
import 'update.dart';
import 'update_install_flow.dart';
import 'update_installer.dart';
import 'update_platform.dart';
import 'web_launch.dart';
import 'welcome_screen.dart';
import 'window_support.dart';

/// Height of the AppBar's browser-style tab strip.
const double _tabStripHeight = 42;

/// Chrome-style tab sizing: tabs share the strip equally, growing no wider
/// than [_tabMaxWidth] and shrinking no narrower than [_tabMinWidth] before
/// the strip starts to scroll.
const double _tabMaxWidth = 240;
const double _tabMinWidth = 56;

/// Below this per-tab width the close button is hidden on inactive tabs (as in
/// Chrome) so the label still has room; the active tab always keeps its close.
const double _tabCloseHideWidth = 100;

/// How long the tabs take to grow back after the pointer leaves the strip
/// following a close (the width-hold release animation).
const Duration _tabResizeDuration = Duration(milliseconds: 150);

const double _mobileTabsBreakpoint = 700;
const double _appMenuLeadingWidth = 60;
const double _appMenuIconSize = 24;
const double _compactAppMenuItemHeight = 36;
const double _compactRecentMenuItemHeight = 48;
const int _maxRecentMenuItems = 8;
const Duration _tabHoverPreviewDelay = Duration(milliseconds: 400);
const double _tabHoverPreviewWidth = 240;
const double _tabHoverPreviewHeight = 300;

/// The editor's main screen: a strip of open-document tabs over the drop-in
/// [PdfEditorView] / [PdfReader] shells, which carry all the PDF chrome
/// (search, page number, panels, toolbar). The screen supplies the edit
/// sessions, file handling, recents, dirty-state, and app-side wiring.
class EditorScreen extends StatefulWidget {
  const EditorScreen({
    super.key,
    required this.prefs,
    this.launchArgs = const [],
    this.initialDocument,
    this.updateService,
    this.updateInstaller,
    this.autoCheckUpdates = false,
    this.printDocument,
    this.digitalSignatureOptionsProvider,
    this.oidcTokenProvider,
    this.oidcSilentTokenProvider,
    this.saveDocumentAs,
    this.saveDocumentToPath,
    this.imageClipboardWriter,
    this.imageClipboardReader,
    this.textClipboardReader,
    this.unsavedChangesStore,
    this.documentScanner,
    this.onNewWindow,
    this.tabDragCoordinator,
    this.initialHandoff,
    this.ownsApplicationSession = true,
  });

  final PdfEditingPreferences prefs;

  /// Desktop launch arguments - a `.pdf` path here opens at startup.
  final List<String> launchArgs;

  /// An in-memory document opened in a tab at startup, regardless of
  /// platform. Used by screenshot/integration harnesses (and handy in
  /// tests) to land directly in the editor without a file picker.
  final ({Uint8List bytes, String title})? initialDocument;

  /// An update checker to use instead of the one the screen builds itself -
  /// the seam tests use to inject a fake without real network.
  final UpdateService? updateService;

  /// The in-app updater used to download and apply a newer release (desktop).
  /// Injected by tests with fake platform ops / HTTP; defaults to a real one.
  final UpdateInstaller? updateInstaller;

  /// Whether to check for a newer release on startup (and show a banner if one
  /// is found). The host (production) sets this true; it defaults to false so
  /// plain widget tests stay hermetic - no startup network traffic. The
  /// Settings panel can still check on demand regardless.
  final bool autoCheckUpdates;

  /// Override for the print action. Tests inject a fake to assert the menu and
  /// shortcut wiring without the real `printing` plugin (its method channel is
  /// unavailable under flutter_test). Production leaves this null and the screen
  /// falls back to [printPdfBytes].
  final PdfPrinter? printDocument;

  /// Overrides the certificate/key dialog used by Digitally sign. Tests and
  /// hosts with an OS keychain or HSM can supply an identity without exposing
  /// it through the app's file picker.
  final DigitalSignatureOptionsProvider? digitalSignatureOptionsProvider;

  /// Enables Sigstore/Fulcio **keyless** signing in the Digitally sign dialog.
  /// A deployment supplies this to run its OAuth sign-in and return an OIDC
  /// token; DartPDF then exchanges it with Fulcio (production HTTPS) and stamps
  /// the signature with the default TSA. Null (the default) hides the keyless
  /// option, since no OAuth client ships with the app.
  final OidcTokenProvider? oidcTokenProvider;

  /// A **silent** OIDC token source (returns a cached/refreshable token, or
  /// null when a browser sign-in would be needed). When wired, the Digitally
  /// sign dialog uses it to pre-select the keyless identity on open without
  /// ever launching sign-in as a side effect of opening.
  final OidcTokenProvider? oidcSilentTokenProvider;

  /// Overrides the Save As backend. Tests use this seam to assert that the
  /// active tab adopts the chosen file without opening platform dialogs.
  final Future<SaveResult> Function(
    BuildContext context,
    Uint8List bytes,
    String suggestedName,
  )? saveDocumentAs;

  /// Overrides in-place saving after a document has a writable origin.
  final Future<SaveResult> Function(
    Uint8List bytes,
    String path, {
    String? bookmark,
  })? saveDocumentToPath;

  /// Override for writing a captured snapshot to the system clipboard. Tests
  /// inject a fake to assert the Snapshot tool's clipboard wiring without the
  /// real host clipboard channel (unavailable under
  /// flutter_test). Production leaves this null and the screen falls back to
  /// [copyPngToClipboard].
  final ImageClipboardWriter? imageClipboardWriter;

  /// Override for reading an image from the system clipboard. Tests inject a
  /// fake; production falls back to [readImageFromClipboard].
  final ImageClipboardReader? imageClipboardReader;

  /// Override for reading text from the system clipboard. Tests inject a fake;
  /// production falls back to [readTextFromClipboard] (which on the web reads
  /// through the browser Async Clipboard API instead of Flutter's unreliable
  /// `Clipboard.getData`).
  final TextClipboardReader? textClipboardReader;

  /// Overrides the crash-recovery mirror for unsaved changes. Tests inject an
  /// in-memory store to drive recovery without a real filesystem or IndexedDB;
  /// production leaves this null and the screen opens the platform store
  /// ([openUnsavedChangesStore]).
  final UnsavedChangesStore? unsavedChangesStore;

  /// Overrides the device document scanner behind "Scan to new document" and
  /// "Insert scan". Tests inject a fake that returns a known PDF so the menu
  /// wiring can run without the native ML Kit / VisionKit channels. Production
  /// leaves this null and the screen uses the platform scanner on mobile
  /// ([scanDocumentToPdf]); where scanning isn't supported the entries hide.
  final DocumentScanner? documentScanner;

  /// Opens another native editor window. A [document] moves a live tab into
  /// it; null creates an empty window. The boolean reports whether the native
  /// window was registered successfully.
  ///
  /// Null keeps all multi-window UI and shortcuts hidden. DartPDF's desktop
  /// shell supplies the native opener; embedded hosts may leave it absent.
  final bool Function(
    BuildContext context, {
    DocumentHandoff? document,
  })? onNewWindow;

  /// Process-wide native drag router. The desktop app supplies one shared
  /// instance to every native window; null keeps the single-view reorder path
  /// used by embedded hosts and widget tests.
  final TabDragCoordinator? tabDragCoordinator;

  /// A document moved from another window and opened during initialization.
  final DocumentHandoff? initialHandoff;

  /// Whether this window owns process-wide session restoration, incoming OS
  /// file events, update checks, and the application-exit confirmation.
  /// Secondary windows set this false so they cannot race or replace the
  /// primary window's state.
  final bool ownsApplicationSession;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen>
    with WidgetsBindingObserver
    implements TabDragWindow {
  PdfEditingPreferences get _prefs => widget.prefs;

  /// The device document scanner, or null where scanning isn't available. An
  /// injected fake wins; otherwise the platform scanner is used on mobile
  /// (and nothing on desktop/web). Drives whether the scan menu entries show.
  late final DocumentScanner? _documentScanner = widget.documentScanner ??
      (documentScanSupported ? scanDocumentToPdf : null);

  bool get _canScan => _documentScanner != null;

  final _recents = RecentsStore();
  final _recentThumbnails = RecentThumbnailCache();
  final _session = SessionStore();

  /// Mirrors dirty documents to durable storage (a private directory on
  /// native, IndexedDB on the web) so a crash never costs unsaved work, and
  /// hands back whatever a previous run lost. See autosave.dart.
  late final AutosaveController _autosave = AutosaveController(
      store: widget.unsavedChangesStore ?? openUnsavedChangesStore());

  final _incoming = IncomingFileService();
  final _ocr = OnDeviceOcr();
  StreamSubscription<IncomingFile>? _incomingSub;
  final Object _windowCloseOwner = Object();
  DartPdfWindowCloseCoordinator? _windowCloseCoordinator;
  bool _nativeWindowCloseApproved = false;

  /// Gates session persistence until the previous session has been read back,
  /// so an early tab open (e.g. an OS file-open) doesn't clobber the stored set
  /// before [_restoreSession] has had a chance to re-open it.
  bool _sessionLoaded = false;

  /// True while [_restoreSession] is re-adding the last session's tabs, so a
  /// restored path-only tab that is briefly active mid-restore does not start
  /// opening. Only the tab active when restore finishes materializes.
  bool _restoringSession = false;

  /// How many tabs at the head of [_tabs] were put there by startup restore
  /// (recovered unsaved work, then the last session's documents).
  ///
  /// Restore races the OS file-open that launched the app: on macOS the file
  /// arrives on the warm `openFile` stream whenever the runner finishes
  /// building its payload, which can land before, during, or after the store
  /// read. Restored tabs therefore slot in at this index rather than at the
  /// end, so the document the user actually double-clicked stays last in the
  /// strip - and keeps focus (see [_addTab]).
  int _restoredTabs = 0;

  /// The update checker, owned here unless the host injected one.
  late final UpdateService _updates = widget.updateService ??
      UpdateService(
        currentVersion: AppInfo.version,
        currentBuildCommit: AppInfo.buildCommit,
      );
  bool get _ownsUpdates => widget.updateService == null;

  /// The in-app updater that downloads and applies a newer release.
  late final UpdateInstaller _updateInstaller =
      widget.updateInstaller ?? UpdateInstaller();

  /// True once the "update available" banner has been shown this session, so a
  /// later check (or rebuild) doesn't stack a second copy.
  bool _updateBannerShown = false;

  /// True while a file is being dragged over the window (desktop/web).
  bool _dragging = false;

  /// Bridges that drag to the page thumbnails: while it hovers the strip or
  /// the page grid the panel marks the slot the pages would land in, and the
  /// drop inserts them there instead of asking open-or-append.
  final PdfThumbnailDropController _thumbnailDrop =
      PdfThumbnailDropController();

  /// True while the drag is over a thumbnail panel - the panel's own
  /// insertion marker says everything, so the full-window hint steps aside.
  bool _draggingOverThumbnails = false;

  final List<DocumentTab> _tabs = [];
  int _activeIndex = 0;
  final _tabStripGeometryKey = GlobalKey();
  final _tabScrollController = ScrollController();
  TabDragCoordinator? _registeredTabDragCoordinator;
  int? _nativeWindowHandle;
  OverlayEntry? _destinationTabDragOverlay;
  TabDragPreview? _destinationTabDragPreview;
  final Map<DocumentTab, String> _nativeTabDragTokens = Map.identity();
  int _nextNativeTabDragToken = 0;

  /// Whether the pointer is currently hovering the desktop tab strip. While it
  /// is, closing a tab pins the remaining tabs' width (see [_heldTabWidth]) so
  /// the close buttons stay under the cursor for a rapid close streak.
  bool _tabStripHovered = false;

  /// The most recent natural (unheld) per-tab width computed during the tab
  /// strip layout, captured so a close can pin to it.
  double _lastNaturalTabWidth = 0;
  double _lastRenderedTabWidth = 0;
  double _lastRenderedTabsWidth = 0;

  /// When non-null, the tabs render at this fixed width instead of growing to
  /// fill the freed space. Set on close while the strip is hovered and released
  /// (animating back to the natural width) once the pointer leaves the strip.
  double? _heldTabWidth;

  /// Whether the developer tools panel is docked over the editor (F12).
  bool _devToolsOpen = false;

  DocumentTab? get _active =>
      _tabs.isEmpty ? null : _tabs[_activeIndex.clamp(0, _tabs.length - 1)];

  /// Whole-app read-only toggle: swaps [PdfEditorView] for [PdfReader].
  bool _readOnly = false;
  bool _digitallySigning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (kDevToolsEnabled) {
      HardwareKeyboard.instance.addHandler(_onGlobalKeyEvent);
    }
    _recents.load().then((_) {
      if (mounted) _pruneRecentCache();
    });
    if (widget.ownsApplicationSession) {
      // One process-wide owner receives OS file-open events. Method channels
      // have one Dart handler, so letting every window register would make the
      // newest secondary window steal delivery from the primary.
      _incoming.start();
      _incomingSub = _incoming.files.listen(_openIncoming);
      _incoming.initialFile().then((file) {
        if (file != null && mounted) _openIncoming(file);
      });
      _openLaunchArgs();
      // PWA file-handler opens (installed web app); no-op off the web.
      startWebLaunchQueue(_openIncoming);
    }
    final doc = widget.initialDocument;
    if (doc != null) _openBytes(doc.bytes, doc.title);
    final handoff = widget.initialHandoff;
    if (handoff != null) _openHandoff(handoff);
    // Re-open the documents that were open when the app last closed, unless the
    // app was launched to open a specific file (that explicit target wins).
    if (widget.ownsApplicationSession) unawaited(_restoreSession());
    if (widget.autoCheckUpdates && _updates.supported) {
      _updates.addListener(_onUpdateStatus);
      unawaited(_startupUpdateCheck());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTabDragRegistration(DartPdfNativeWindowScope.maybeHandleOf(context));
    final coordinator = DartPdfWindowCloseScope.maybeOf(context);
    if (identical(coordinator, _windowCloseCoordinator)) return;
    _windowCloseCoordinator?.unregister(_windowCloseOwner);
    _windowCloseCoordinator = coordinator;
    coordinator?.register(_windowCloseOwner, _requestNativeWindowClose);
  }

  @override
  void didUpdateWidget(EditorScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.tabDragCoordinator, widget.tabDragCoordinator)) {
      _syncTabDragRegistration(_nativeWindowHandle);
    }
  }

  void _syncTabDragRegistration(int? handle) {
    final coordinator = widget.tabDragCoordinator;
    if (identical(_registeredTabDragCoordinator, coordinator) &&
        _nativeWindowHandle == handle) {
      return;
    }
    _registeredTabDragCoordinator
      ?..removeListener(_syncDestinationTabDragOverlay)
      ..unregister(this);
    _removeDestinationTabDragOverlay();
    _registeredTabDragCoordinator = null;
    _nativeWindowHandle = handle;
    if (coordinator != null && handle != null) {
      _registeredTabDragCoordinator = coordinator;
      coordinator.register(this);
      coordinator.addListener(_syncDestinationTabDragOverlay);
    }
  }

  void _syncDestinationTabDragOverlay() {
    if (!mounted) return;
    final preview = _registeredTabDragCoordinator?.preview;
    final show = preview?.isOverTabStrip == true &&
        preview?.targetWindowHandle == _nativeWindowHandle &&
        preview?.localPoint != null &&
        !_tabs.contains(preview?.tab);
    if (!show) {
      _removeDestinationTabDragOverlay();
      return;
    }

    _destinationTabDragPreview = preview;
    final existingEntry = _destinationTabDragOverlay;
    if (existingEntry != null) {
      existingEntry.markNeedsBuild();
      return;
    }
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final entry = OverlayEntry(
      builder: (overlayContext) {
        final current = _destinationTabDragPreview;
        final point = current?.localPoint;
        if (current == null || point == null) return const SizedBox.shrink();
        final size = MediaQuery.sizeOf(overlayContext);
        const cardWidth = 280.0;
        const estimatedHeight = 64.0;
        final left = (point.dx + 12)
            .clamp(8.0, math.max(8.0, size.width - cardWidth - 8))
            .toDouble();
        final top = (point.dy + 12)
            .clamp(8.0, math.max(8.0, size.height - estimatedHeight - 8))
            .toDouble();
        return Positioned(
          left: left,
          top: top,
          child: IgnorePointer(
            child: _buildTabDragFeedback(
              overlayContext,
              current.tab,
              overStrip: true,
              movingToAnotherWindow: true,
              key: const ValueKey('tab-drag-destination-feedback'),
            ),
          ),
        );
      },
    );
    _destinationTabDragOverlay = entry;
    overlay.insert(entry);
  }

  void _removeDestinationTabDragOverlay() {
    _destinationTabDragPreview = null;
    final entry = _destinationTabDragOverlay;
    if (entry == null) return;
    _destinationTabDragOverlay = null;
    entry.remove();
    entry.dispose();
  }

  /// Runs the one-shot startup update check. When we built the service
  /// ourselves it may have captured the compile-time version fallback, so
  /// refresh it from the loaded package metadata before comparing.
  Future<void> _startupUpdateCheck() async {
    if (_ownsUpdates) {
      await AppInfo.load();
      _updates.currentVersion = AppInfo.version;
    }
    if (!mounted) return;
    await _updates.checkForUpdates();
  }

  /// Surfaces a one-time, non-blocking banner when a newer release is found
  /// and the user hasn't dismissed that exact version before.
  void _onUpdateStatus() {
    if (_updateBannerShown || !_updates.shouldNotify || !mounted) return;
    _updateBannerShown = true;
    final release = _updates.latest!;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showMaterialBanner(MaterialBanner(
      key: const ValueKey('update-available-banner'),
      content:
          Text(appL10n(context).editorUpdateAvailable(release.displayVersion)),
      leading: const Icon(Icons.system_update_alt),
      actions: [
        TextButton(
          onPressed: () {
            messenger.hideCurrentMaterialBanner();
            unawaited(_updates.dismiss());
          },
          child: Text(appL10n(context).editorUpdateLater),
        ),
        FilledButton(
          key: const ValueKey('update-banner-download'),
          onPressed: () {
            messenger.hideCurrentMaterialBanner();
            unawaited(startUpdateInstall(
              context,
              updates: _updates,
              installer: _updateInstaller,
            ));
          },
          child: Text(_updates.downloadAssetName != null &&
                  _updateInstaller.modeFor(_updates.downloadAssetName) !=
                      UpdateApplyMode.unsupported
              ? appL10n(context).updateInstallNow
              : appL10n(context).editorDownload),
        ),
      ],
    ));
  }

  /// Opens a `.pdf` passed on the command line - how Windows and Linux deliver
  /// a file association / "open with" at cold start (macOS and mobile use the
  /// channel instead).
  void _openLaunchArgs() {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.windows &&
        defaultTargetPlatform != TargetPlatform.linux) {
      return;
    }
    for (final arg in widget.launchArgs) {
      if (!arg.toLowerCase().endsWith('.pdf')) continue;
      final name = arg.split(RegExp(r'[/\\]')).last;
      _openIncoming(IncomingFile(name: name, path: arg));
      break; // open only the first file
    }
  }

  @override
  void dispose() {
    _registeredTabDragCoordinator
      ?..removeListener(_syncDestinationTabDragOverlay)
      ..unregister(this);
    _removeDestinationTabDragOverlay();
    _tabScrollController.dispose();
    _windowCloseCoordinator?.unregister(_windowCloseOwner);
    WidgetsBinding.instance.removeObserver(this);
    if (kDevToolsEnabled) {
      HardwareKeyboard.instance.removeHandler(_onGlobalKeyEvent);
    }
    _incomingSub?.cancel();
    _incoming.dispose();
    _ocr.dispose();
    // Detaches only - the mirrored records stay, so an editor torn down with
    // dirty tabs (a crash, a forced quit) can still hand the work back.
    _autosave.dispose();
    for (final tab in _tabs) {
      tab.dispose();
    }
    _recents.dispose();
    _recentThumbnails.dispose();
    _thumbnailDrop.dispose();
    _updates.removeListener(_onUpdateStatus);
    if (_ownsUpdates) _updates.dispose();
    super.dispose();
  }

  /// Blocks app exit while any document has unsaved changes, offering to
  /// discard. On platforms that don't ask (mobile/web) this is a no-op.
  @override
  Future<ui.AppExitResponse> didRequestAppExit() async {
    if (_nativeWindowCloseApproved) return ui.AppExitResponse.exit;
    if (!widget.ownsApplicationSession) return ui.AppExitResponse.exit;
    final dirty = _tabs.where((t) => t.isDirty).length;
    if (dirty == 0) return ui.AppExitResponse.exit;
    final proceed = await _confirmDiscard(
      appL10n(context).editorUnsavedChangesCount(dirty),
    );
    if (!proceed) return ui.AppExitResponse.cancel;
    // The user was asked and chose to throw the edits away - so drop the
    // mirrored copies too, or the next launch would offer back work they
    // already declined.
    await _autosave.discardAll();
    return ui.AppExitResponse.exit;
  }

  Future<bool> _requestNativeWindowClose() async {
    final dirty = _tabs.where((tab) => tab.isDirty).length;
    if (dirty > 0) {
      final proceed = await _confirmDiscard(
        appL10n(context).editorUnsavedChangesCount(dirty),
      );
      if (!proceed || !mounted) return false;
      await _autosave.discardAll();
    }
    _nativeWindowCloseApproved = true;
    return true;
  }

  /// Mirrors pending edits when the app leaves the foreground. On mobile and
  /// the web this can be the last callback we get before the process is
  /// reclaimed, so it writes now rather than waiting out the debounce.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      unawaited(_autosave.flushPending());
    }
  }

  // --- session restore -----------------------------------------------------

  /// True when the app was launched to open a specific document (a screenshot/
  /// test harness document, or a `.pdf` passed on the command line). In that
  /// case the explicit target wins and we don't also restore the last session.
  bool get _hasExplicitLaunchTarget =>
      widget.initialDocument != null ||
      widget.initialHandoff != null ||
      (!kIsWeb &&
          widget.launchArgs.any((a) => a.toLowerCase().endsWith('.pdf')));

  /// Re-opens the file-backed documents that were open when the app last closed.
  /// Runs once at startup, then enables session persistence so this run's open
  /// set is captured for next time. Documents whose file has since moved or been
  /// deleted are dropped silently rather than surfacing an error tab.
  Future<void> _restoreSession() async {
    // Unsaved work comes back first, so a document recovered with its edits
    // wins over the same file restored flat from disk below (the loop skips
    // paths already open).
    await _recoverUnsavedChanges();
    if (!mounted) return;
    final documents = await _session.load();
    if (mounted && !_hasExplicitLaunchTarget) {
      // Suppress lazy materialization while restoring: each tab is briefly the
      // active one as it is added, and we don't want every restored file to
      // start opening. Only the tab left active when restore finishes should
      // materialize (see _buildBody / _materializeDeferredPath).
      _restoringSession = true;
      try {
        for (final doc in documents) {
          // Skip anything already open (e.g. an OS file-open that arrived first).
          final key = doc.readPath;
          if (key != null &&
              _tabs.any((t) => t.originPath == key || t.cachePath == key)) {
            continue;
          }
          await _reopenSessionDocument(doc);
          if (!mounted) return;
        }
      } finally {
        _restoringSession = false;
      }
      // Let the tab left active materialize now that restore is done.
      if (mounted) setState(() {});
    }
    if (mounted) {
      setState(() => _sessionLoaded = true);
    } else {
      _sessionLoaded = true;
    }
    unawaited(_persistSession());
  }

  /// Re-opens the documents that had unsaved edits when the app last went
  /// away, at the revision they were on.
  ///
  /// The mirror holds a record only while a document has unsaved work (saving
  /// or closing drops it), so anything here is by construction work a previous
  /// run lost - to a crash, an OOM kill, or a browser tab closed out from under
  /// us. Each comes back as a normal editable tab that is still dirty and still
  /// points at its original save destination, so the user finishes the save
  /// they were interrupted in.
  ///
  /// What is *not* recovered is the undo stack: the mirrored bytes are one flat
  /// chain of incremental updates, so the recovered document opens as a single
  /// revision. The edits survive; the history behind them does not.
  Future<void> _recoverUnsavedChanges() async {
    if (!_autosave.enabled) return;
    final recovered = await _autosave.recover();
    if (!mounted) return;
    for (final doc in recovered) {
      final record = doc.record;
      final tab = DocumentTab.document(
        title: record.title,
        bytes: doc.bytes,
        preferences: _prefs,
        originPath: record.originPath.isEmpty ? null : record.originPath,
        originBookmark: record.originBookmark,
        cachePath: record.cachePath,
        // Comes back dirty exactly as it was: the baseline is what had been
        // written to the real destination, not the revision we recovered.
        savedLength: record.savedLength,
      );
      // Adopt the existing record *before* the tab is tracked by the usual
      // open path, so continued editing appends to it instead of mirroring the
      // whole document again under a fresh id.
      _autosave.track(tab, recovered: record);
      _addTab(tab, restored: true);
    }
    // Anything nothing adopted (bytes gone, a record we couldn't read) would
    // otherwise be offered back on every launch forever.
    await _autosave.pruneAfterRecovery();
    if (recovered.isEmpty || !mounted) return;
    final count = recovered.length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _toast(appL10n(context).editorRecoveredUnsavedChanges(count));
      }
    });
  }

  Future<void> _reopenSessionDocument(SessionDocument doc) async {
    final readPath = doc.readPath;
    if (readPath == null) return;
    // Desktop restores by its writable origin; a mobile pick has none and
    // restores from its private snapshot instead.
    final originPath = doc.path.isNotEmpty ? doc.path : null;

    // Desktop origin: restore every tab immediately, without awaiting even a
    // metadata probe. A cloud provider can stall file coordination for one
    // origin; making the restore loop await it would hide every later tab until
    // that provider responded. Path-only tabs read nothing until selected, so
    // the user can switch to another restored document while a remote one is
    // hydrating. A missing file is dropped when its lazy open fails.
    if (progressiveOpenSupported(originPath)) {
      _addTab(
        DocumentTab.deferredPath(
          title: doc.title,
          originPath: originPath!,
          originBookmark: doc.bookmark,
          cachePath: doc.cachePath,
        ),
        restored: true,
      );
      _recents.add(
          title: doc.title,
          path: originPath,
          cachePath: doc.cachePath,
          bookmark: doc.bookmark);
      return;
    }

    // Snapshot-only restore (mobile private cache, or a platform without
    // progressive open): read the bytes and defer only the parse.
    final loading = _openLoading(
      doc.title,
      originPath: originPath,
      originBookmark: doc.bookmark,
      cachePath: doc.cachePath,
      restored: true,
    );
    try {
      final bytes = await readPdfAtPath(readPath, bookmark: doc.bookmark);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      // Reading the bytes already confirmed the file is still there (a gone
      // file threw and dropped its placeholder above); defer the parse so a
      // multi-document session doesn't open every file at once on launch. The
      // active tab materializes as soon as it's shown (see _buildBody).
      final opened = _replaceLoadingTab(
        loading,
        DocumentTab.deferred(
          title: doc.title,
          bytes: bytes,
          originPath: originPath,
          originBookmark: doc.bookmark,
          cachePath: doc.cachePath,
        ),
      );
      if (opened) {
        _recents.add(
            title: doc.title,
            path: originPath,
            cachePath: doc.cachePath,
            bookmark: doc.bookmark);
      }
    } catch (e) {
      // The file is gone (moved/deleted): drop the placeholder quietly.
      AppDevTools.instance.addLog('deferred open failed (file moved?): $e',
          level: DevLogLevel.error);
      if (mounted) await _closeTabs([loading]);
    }
  }

  /// Persists the current open set (file-backed tabs, in order) so the next
  /// launch can restore it. A no-op until the previous session has been read
  /// back, so early opens can't clobber the stored set before [_restoreSession].
  Future<void> _persistSession() async {
    // Every tab-set mutation lands here, so this is also where the crash-
    // recovery mirror learns which documents it should be watching. It runs
    // ahead of the session-load gate below: a document opened before the last
    // session has been read back still deserves its unsaved edits protected.
    _autosave.syncTracking(_tabs);
    if (!widget.ownsApplicationSession || !_sessionLoaded) return;
    final documents = <SessionDocument>[];
    final seen = <String>{};
    for (final tab in _tabs) {
      final path = tab.originPath;
      final cachePath = tab.cachePath;
      // Track by the writable origin (desktop) or the private snapshot
      // (mobile file cache / web IndexedDB); tabs with neither (a derived or
      // comparison tab, or a web pick whose snapshot failed) can't be read back
      // and are skipped.
      final key = (path != null && path.isNotEmpty) ? path : cachePath;
      if (key == null || key.isEmpty || !seen.add(key)) continue;
      documents.add(SessionDocument(
          title: tab.title,
          path: path ?? '',
          cachePath: cachePath,
          bookmark: tab.originBookmark));
    }
    await _session.save(documents);
  }

  /// Deletes cached mobile snapshots that no Recent entry still references, so
  /// the private store can't grow without bound as entries roll off the list.
  /// A no-op on desktop/web (nothing is cached there).
  void _pruneRecentCache() {
    final keep = {
      for (final entry in _recents.items)
        if (entry.cachePath != null) entry.cachePath!,
    };
    unawaited(pruneCachedPdfs(keep));
  }

  // --- opening -------------------------------------------------------------

  /// Opens [bytes] in a brand-new tab and makes it active, recording a recent.
  void _openBytes(Uint8List bytes, String title,
      {String? originPath, String? originBookmark}) {
    _addTab(DocumentTab.document(
      title: title,
      bytes: bytes,
      preferences: _prefs,
      originPath: originPath,
      originBookmark: originBookmark,
    ));
    _recents.add(title: title, path: originPath, bookmark: originBookmark);
  }

  void _openError(String title, String error) {
    AppDevTools.instance
        .addLog('open error: $title - $error', level: DevLogLevel.error);
    _addTab(DocumentTab.error(title: title, error: error));
  }

  void _openHandoff(DocumentHandoff handoff) {
    insertTab(handoff, _tabs.length);
  }

  DocumentTab _tabFromHandoff(DocumentHandoff handoff) => DocumentTab.document(
        title: handoff.title,
        bytes: handoff.bytes,
        preferences: _prefs,
        originPath: handoff.originPath,
        originBookmark: handoff.originBookmark,
        originToken: handoff.originToken,
        cachePath: handoff.cachePath,
        savedLength: handoff.savedLength,
      );

  @override
  bool insertTab(DocumentHandoff handoff, int insertionIndex) {
    if (!mounted) return false;
    try {
      final tab = _tabFromHandoff(handoff);
      final index = insertionIndex.clamp(0, _tabs.length).toInt();
      setState(() {
        _heldTabWidth = null;
        _tabs.insert(index, tab);
        _activeIndex = index;
      });
      _recents.add(
        title: handoff.title,
        path: handoff.originPath,
        cachePath: handoff.cachePath,
        bookmark: handoff.originBookmark,
      );
      unawaited(_persistSession());
      return true;
    } catch (error) {
      AppDevTools.instance.addLog(
        'tab handoff failed: $error',
        level: DevLogLevel.error,
      );
      return false;
    }
  }

  @override
  int get windowHandle => _nativeWindowHandle!;

  bool get _nativeTabDragging => _registeredTabDragCoordinator != null;

  @override
  bool containsTab(DocumentTab tab) => mounted && _tabs.contains(tab);

  @override
  bool removeTab(DocumentTab tab) {
    if (!containsTab(tab)) return false;
    _removeTabs([tab]);
    return true;
  }

  @override
  void closeWindowIfEmpty() {
    if (!mounted || _tabs.isNotEmpty) return;
    // Let _removeTabs finish painting out the transferred tab and dispose its
    // session before the native view disappears. Its post-frame callback was
    // registered first, so disposal also runs before this close request.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _tabs.isNotEmpty) return;
      unawaited(_windowCloseCoordinator?.closeWindow());
    });
  }

  @override
  bool openTabInNewWindow(DocumentHandoff handoff) {
    final open = widget.onNewWindow;
    return mounted && open != null && open(context, document: handoff);
  }

  @override
  bool reorderTab(DocumentTab tab, int insertionIndex) {
    final oldIndex = _tabs.indexOf(tab);
    if (oldIndex < 0) return false;
    var newIndex = insertionIndex.clamp(0, _tabs.length).toInt();
    if (oldIndex < newIndex) newIndex--;
    newIndex = newIndex.clamp(0, _tabs.length - 1).toInt();
    if (oldIndex != newIndex) _reorderTabs(oldIndex, newIndex);
    return true;
  }

  @override
  int? tabInsertionIndex(Offset localPoint) {
    final strip = _tabStripGeometryKey.currentContext?.findRenderObject();
    if (strip is! RenderBox || !strip.attached) return null;
    final stripRect = strip.localToGlobal(Offset.zero) & strip.size;
    if (!stripRect.contains(localPoint)) return null;
    if (_tabs.isEmpty) return 0;

    if (_lastRenderedTabWidth <= 0 || _lastRenderedTabsWidth <= 0) {
      return _tabs.length;
    }
    final rtl = Directionality.of(context) == TextDirection.rtl;
    // The tab list is always the Row's first child, so it begins at the
    // strip's logical leading edge. Derive its coordinates from the stable
    // outer strip instead of a GlobalKey on the MouseRegion: rebuilding that
    // region for live hover feedback briefly left its RenderObject unavailable
    // and every same-strip drop fell back to the append slot.
    final visibleOffset =
        rtl ? stripRect.right - localPoint.dx : localPoint.dx - stripRect.left;
    if (visibleOffset < 0) return 0;
    if (visibleOffset > _lastRenderedTabsWidth) return _tabs.length;
    final scrollOffset =
        _tabScrollController.hasClients ? _tabScrollController.offset : 0.0;
    const listPadding = 4.0;
    var contentOffset = visibleOffset + scrollOffset - listPadding;
    final externalGap = _externalTabDragGap;
    if (externalGap != null) {
      final gapStart = externalGap * _lastRenderedTabWidth;
      final gapEnd = gapStart + _lastRenderedTabWidth;
      if (contentOffset >= gapStart && contentOffset <= gapEnd) {
        return externalGap;
      }
      if (contentOffset > gapEnd) contentOffset -= _lastRenderedTabWidth;
    }
    return ((contentOffset / _lastRenderedTabWidth) + 0.5)
        .floor()
        .clamp(0, _tabs.length)
        .toInt();
  }

  int? get _externalTabDragGap {
    final preview = _registeredTabDragCoordinator?.preview;
    if (preview?.targetWindowHandle != _nativeWindowHandle ||
        preview?.insertionIndex == null ||
        _tabs.contains(preview?.tab)) {
      return null;
    }
    return preview!.insertionIndex!.clamp(0, _tabs.length).toInt();
  }

  double _tabDragShift(int index) {
    final preview = _registeredTabDragCoordinator?.preview;
    final insertion = preview?.targetWindowHandle == _nativeWindowHandle
        ? preview?.insertionIndex
        : null;
    if (insertion == null) return 0;

    final sourceIndex = _tabs.indexOf(preview!.tab);
    if (sourceIndex < 0) return index >= insertion ? 1 : 0;
    if (index == sourceIndex) return 0;

    var destination = insertion.clamp(0, _tabs.length).toInt();
    if (sourceIndex < destination) destination--;
    destination = destination.clamp(0, _tabs.length - 1).toInt();
    if (destination < sourceIndex &&
        index >= destination &&
        index < sourceIndex) {
      return 1;
    }
    if (destination > sourceIndex &&
        index > sourceIndex &&
        index <= destination) {
      return -1;
    }
    return 0;
  }

  /// Adds [tab] to the strip and makes it active.
  ///
  /// A tab added by startup restore ([restored]) is the exception on both
  /// counts: it joins the restored block at the head of the strip instead of
  /// the end, and it takes focus only while nothing else is open. A document
  /// the user asked for - the file the OS launched us with - keeps its place
  /// at the end and stays the one on screen, whichever order the two
  /// asynchronous sources happen to resolve in.
  void _addTab(DocumentTab tab, {bool restored = false}) {
    setState(() {
      // A new tab shrinks the others to fit; drop any close-streak width hold.
      _heldTabWidth = null;
      if (!restored) {
        _tabs.add(tab);
        _activeIndex = _tabs.length - 1;
        return;
      }
      final at = _restoredTabs.clamp(0, _tabs.length);
      // Anything at or past the restored block was opened explicitly this
      // launch; if one of those is active it stays active, just shifted along.
      final userTabActive = _tabs.isNotEmpty && _activeIndex >= at;
      _tabs.insert(at, tab);
      _restoredTabs = at + 1;
      _activeIndex = userTabActive ? _activeIndex + 1 : at;
    });
    unawaited(_persistSession());
  }

  /// Releases the close-streak width hold, letting the tabs animate back out to
  /// fill the strip. Called when the pointer leaves the tab strip.
  void _releaseTabWidthHold() {
    if (_heldTabWidth == null) return;
    setState(() => _heldTabWidth = null);
  }

  DocumentTab _openLoading(String title,
      {String? originPath,
      String? originBookmark,
      String? originToken,
      String? cachePath,
      bool restored = false}) {
    final tab = DocumentTab.loading(
        title: title,
        originPath: originPath,
        originBookmark: originBookmark,
        originToken: originToken,
        cachePath: cachePath);
    _addTab(tab, restored: restored);
    return tab;
  }

  bool _replaceLoadingTab(DocumentTab loading, DocumentTab replacement) {
    final index = _tabs.indexOf(loading);
    if (index == -1) {
      replacement.dispose();
      return false;
    }
    // Swap in place, leaving the selection alone: the placeholder is normally
    // the active tab already, and when it isn't - a session restore finishing
    // behind the file the OS launched us with - stealing focus here would undo
    // the ordering _addTab just got right.
    setState(() => _tabs[index] = replacement);
    loading.dispose();
    unawaited(_persistSession());
    return true;
  }

  Future<void> _openLoadedBytes(
    Future<Uint8List> bytesFuture, {
    required String title,
    String? originPath,
    String? originBookmark,
    String? errorTitle,
    bool defer = false,
  }) async {
    final loading = _openLoading(
      title,
      originPath: originPath,
      originBookmark: originBookmark,
    );
    AppDevTools.instance
        .addLog('open-trace: "$title" placeholder shown, awaiting bytes '
            '(defer=$defer, path=${originPath ?? "-"})');
    try {
      final bytes = await bytesFuture;
      AppDevTools.instance
          .addLog('open-trace: "$title" bytes ready — ${bytes.length} B; '
              'waiting for end of frame');
      // Let the loading tab paint before constructing the edit session, which
      // synchronously opens the PDF and can be noticeable for large files.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      AppDevTools.instance.addLog(
          'open-trace: "$title" building ${defer ? "deferred tab" : "session"}');
      // A batch open ([defer]) parses only the tab the user lands on; the
      // rest stay unparsed until first activated (see _materializeDeferred),
      // so opening many large files no longer stalls on every one at once.
      final tab = defer
          ? DocumentTab.deferred(
              title: title,
              bytes: bytes,
              originPath: originPath,
              originBookmark: originBookmark,
            )
          : DocumentTab.document(
              title: title,
              bytes: bytes,
              preferences: _prefs,
              originPath: originPath,
              originBookmark: originBookmark,
            );
      final opened = _replaceLoadingTab(loading, tab);
      AppDevTools.instance.addLog(
          'open-trace: "$title" tab ${opened ? "shown" : "replace-skipped"}');
      if (opened) {
        // With a reusable file origin (desktop) or no writable store (web),
        // record the recent right away. Without one (mobile), snapshot the
        // bytes off the open hot path - awaiting the disk write here would hold
        // the loading placeholder up - and record the recent once it lands.
        if (originPath == null && canCacheRecentPdfs) {
          unawaited(_snapshotOpenedDocument(tab, bytes));
        } else {
          _recents.add(
              title: title, path: originPath, bookmark: originBookmark);
        }
      }
    } catch (e) {
      if (!mounted) return;
      _replaceLoadingTab(
        loading,
        DocumentTab.error(
          title: errorTitle ?? title,
          error: appL10n(context)
              .editorCouldNotOpenDetail(errorTitle ?? title, '$e'),
        ),
      );
    }
  }

  /// Snapshots a just-opened mobile document's [bytes] into the app's private
  /// store so it can reopen from Recent / restore next launch without a fresh
  /// pick, then records the recent (and re-persists the session) once the
  /// snapshot is on disk. Runs off the open hot path - the tab is already
  /// visible - so a slow disk write never blocks the loading placeholder.
  Future<void> _snapshotOpenedDocument(DocumentTab tab, Uint8List bytes) async {
    final cachePath = await cacheOpenedPdf(bytes);
    if (!mounted || !_tabs.contains(tab)) return;
    if (cachePath == null) {
      // The snapshot failed: still record a (non-reopenable) recent.
      _recents.add(title: tab.title, bookmark: tab.originBookmark);
      return;
    }
    tab.cachePath = cachePath;
    _recents.add(
        title: tab.title, cachePath: cachePath, bookmark: tab.originBookmark);
    unawaited(_persistSession());
  }

  /// Builds the edit session for a [DocumentTab.deferred] tab the first time
  /// it is shown, swapping it for a real document tab in place. The heavy
  /// parse runs after the current frame paints the placeholder, so landing on
  /// a deferred tab feels the same as opening a fresh document - and the tabs
  /// the user never visits are never parsed.
  void _materializeDeferred(DocumentTab tab) {
    if (tab.materializing) return;
    tab.materializing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final index = _tabs.indexOf(tab);
      final bytes = tab.deferredBytes;
      if (index == -1 || bytes == null) return;
      AppDevTools.instance
          .addLog('open-trace: materializing deferred "${tab.title}" '
              '— building session over ${bytes.length} B');
      final built = DocumentTab.document(
        title: tab.title,
        bytes: bytes,
        preferences: _prefs,
        originPath: tab.originPath,
        originBookmark: tab.originBookmark,
        cachePath: tab.cachePath,
      );
      setState(() => _tabs[index] = built);
      AppDevTools.instance.addLog(
          'open-trace: materialized deferred "${tab.title}" — session ready');
      tab.dispose();
      unawaited(_persistSession());
    });
  }

  /// Opens a [DocumentTab.deferredPath] (a session-restored file known only by
  /// its path) the first time it is shown, progressively and in place. The read
  /// starts after the placeholder paints, so landing on a restored tab feels
  /// like a fresh progressive open - and restored tabs the user never visits
  /// never read a byte.
  void _materializeDeferredPath(DocumentTab tab) {
    if (tab.materializing) return;
    tab.materializing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !_tabs.contains(tab) || tab.originPath == null) return;
      await _openProgressive(
        title: tab.title,
        path: tab.originPath!,
        bookmark: tab.originBookmark,
        cachePath: tab.cachePath,
        into: tab,
        onOpenFailed: (_) {
          // Session restoration is best-effort. A source that disappeared
          // since the previous run should vanish quietly rather than leave a
          // permanent error tab. `_closeTabs` removes synchronously until its
          // first await for these clean placeholders, so the fallback's later
          // replacement sees that the tab is already gone.
          if (mounted && _tabs.contains(tab)) {
            unawaited(_closeTabs([tab]));
          }
        },
      );
    });
  }

  /// Builds the ranged byte source for a progressive open from whichever origin
  /// the tab has: a desktop file [path] (optionally security-scoped by
  /// [bookmark]) or a mobile reference [token] (#364).
  PdfByteSource _progressiveSource({
    String? path,
    String? bookmark,
    String? token,
    PdfCancelToken? cancel,
    void Function(int received, int? total)? onProgress,
  }) {
    if (token != null && token.isNotEmpty) {
      return pdfByteSourceForMobileToken(token,
          cancelToken: cancel, onProgress: onProgress);
    }
    return pdfByteSourceForPath(path!,
        bookmark: bookmark, cancelToken: cancel, onProgress: onProgress);
  }

  /// Reads an origin whole (the fallback behind a progressive open): a desktop
  /// [path] through the normal path read, or a mobile [token] by draining its
  /// ranged source. Both yield the complete bytes the edit session needs.
  Future<Uint8List> _readOriginFully({
    String? path,
    String? bookmark,
    String? token,
  }) async {
    if (token != null && token.isNotEmpty) {
      final source = pdfByteSourceForMobileToken(token);
      try {
        return await readSourceFully(source);
      } finally {
        await source.close();
      }
    }
    return readPdfAtPath(path!, bookmark: bookmark);
  }

  /// Opens a file-backed document progressively: the ranged loader assembles
  /// just the header/xref/live-object bytes needed to render, so the viewer
  /// paints read-only in ~1-2 s even from a slow cloud-synced file, then the
  /// complete bytes stream in behind that first paint and the tab swaps to a
  /// full edit session. Save / Digitally sign light up only after the swap
  /// (a preview tab has no session, so those actions stay disabled meanwhile).
  ///
  /// Returns once the first paint (or a fallback full read) is on screen; the
  /// background read finishes later. Falls back to the plain full read the rest
  /// of the app uses if the progressive first paint can't be assembled, so
  /// nothing a normal open handles regresses. Opened from a desktop file [path]
  /// (see [progressiveOpenSupported]) or a mobile reference [token] (#364, see
  /// [supportsMobileProgressiveOpen]); [onOpenFailed] lets recents drop a stale
  /// entry.
  ///
  /// Pass [into] to reuse an existing placeholder tab (a lazily-materialized
  /// [DocumentTab.deferredPath] from session restore) instead of adding a fresh
  /// loading tab.
  Future<void> _openProgressive({
    required String title,
    String? path,
    String? bookmark,
    String? token,
    String? cachePath,
    void Function(Object error)? onOpenFailed,
    DocumentTab? into,
  }) async {
    assert((path != null) != (token != null),
        'a progressive open needs exactly one of path/token');
    final loading = into ??
        _openLoading(
          title,
          originPath: path,
          originBookmark: bookmark,
          originToken: token,
          cachePath: cachePath,
        );
    final cancel = PdfCancelToken();
    final progress = ValueNotifier<double>(0);
    final source = _progressiveSource(
        path: path, bookmark: bookmark, token: token, cancel: cancel);

    PdfDocument doc;
    try {
      // Fetch just the first page's worth of bytes for the read-only first
      // paint - for an image-heavy scan/CAD file the live objects are the page
      // images, so fetching every object would be the whole file (tens of
      // seconds). The background read behind the preview then completes the
      // buffer for the full edit session.
      doc = await PdfDocument.openSource(source,
          options: const PdfSourceLoadOptions(firstPaintPages: 1));
    } on PdfHttpCancelledException {
      progress.dispose();
      await source.close();
      return;
    } catch (error) {
      // The progressive first paint could not be assembled (IO error, or a
      // shape the ranged loader gives up on). Fall back to the plain read the
      // rest of the app uses, reusing the same loading placeholder.
      progress.dispose();
      await source.close();
      if (!mounted) return;
      await _fallbackFullOpen(loading,
          title: title,
          path: path,
          bookmark: bookmark,
          token: token,
          cachePath: cachePath,
          onOpenFailed: onOpenFailed);
      return;
    }

    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) {
      progress.dispose();
      cancel.cancel();
      await source.close();
      return;
    }

    final preview = DocumentTab.preview(
      title: title,
      document: doc,
      previewBytes: doc.cos.bytes,
      progress: progress,
      cancel: cancel,
      originPath: path,
      originBookmark: bookmark,
      originToken: token,
      cachePath: cachePath,
    );
    if (!_replaceLoadingTab(loading, preview)) {
      // The loading tab was closed while opening; preview.dispose() cancels the
      // load and frees the progress notifier.
      await source.close();
      return;
    }
    // Record the recent on first paint, so a briefly-opened document still
    // lands in the list even if it's closed before the full read completes.
    // A mobile pick has no reopenable origin yet (path/cachePath both null - it
    // snapshots on the full-read swap); skip it here so it doesn't briefly show
    // a non-reopenable recent, and let the swap add it once the snapshot lands.
    if (path != null || cachePath != null) {
      _recents.add(
          title: title, path: path, cachePath: cachePath, bookmark: bookmark);
    }
    AppDevTools.instance.addLog(
        'progressive open: "$title" first paint — ${doc.pageCount} pages; '
        'reading full file…');

    // Stream the rest in behind the first paint, then swap to a full session.
    unawaited(_finishProgressive(preview, source));
  }

  /// The background half of [_openProgressive]: reads the whole file (reporting
  /// progress on the preview's [DocumentTab.progress]) and swaps the read-only
  /// [preview] for a full edit session once the complete bytes land.
  Future<void> _finishProgressive(
      DocumentTab preview, PdfByteSource source) async {
    final progress = preview.progress!;
    final cancel = preview.cancel!;
    try {
      final full = await readSourceFully(
        source,
        cancelToken: cancel,
        onProgress: (received, total) {
          if (total != null && total > 0) {
            progress.value = (received / total).clamp(0.0, 1.0);
          }
        },
      );
      await source.close();
      if (!mounted) return;
      if (_swapPreviewToDocument(preview, full)) {
        AppDevTools.instance
            .addLog('progressive open: "${preview.title}" full read complete — '
                '${full.length} bytes');
      }
    } on PdfHttpCancelledException {
      // The tab was closed mid-read (its dispose fired the token); the preview
      // is already gone, so there is nothing to swap.
      await source.close();
    } catch (error) {
      await source.close();
      if (!mounted || !_tabs.contains(preview)) return;
      // First paint worked but the full read failed. Try the plain read so the
      // user still gets a fully-editable document where possible; otherwise
      // surface the error in place of the preview.
      try {
        final full = await _readOriginFully(
          path: preview.originPath,
          bookmark: preview.originBookmark,
          token: preview.originToken,
        );
        if (!mounted) return;
        _swapPreviewToDocument(preview, full);
      } catch (error2) {
        if (!mounted) return;
        final index = _tabs.indexOf(preview);
        if (index == -1) return;
        setState(() => _tabs[index] = DocumentTab.error(
              title: preview.title,
              error: appL10n(context)
                  .editorCouldNotOpenDetail(preview.title, '$error2'),
            ));
        preview.dispose();
      }
    }
  }

  /// Replaces the read-only [preview] with a full [DocumentTab.document] built
  /// from the complete [bytes], in place (keeping the tab's position and, if it
  /// is active, focus). Returns false if the tab was closed meanwhile.
  bool _swapPreviewToDocument(DocumentTab preview, Uint8List bytes) {
    final index = _tabs.indexOf(preview);
    if (index == -1) return false;
    final built = DocumentTab.document(
      title: preview.title,
      bytes: bytes,
      preferences: _prefs,
      originPath: preview.originPath,
      originBookmark: preview.originBookmark,
      cachePath: preview.cachePath,
    );
    setState(() => _tabs[index] = built);
    // A mobile progressive open (#364) has no reopenable origin - the reference
    // token dies with the pick - so snapshot the now-complete bytes into the
    // app's private store, behind the first paint, so Recent/restore reopen
    // from the local copy instead of re-picking. Desktop keeps its path/bookmark
    // origin and needs no snapshot.
    if (preview.originToken != null &&
        preview.originPath == null &&
        preview.cachePath == null &&
        canCacheRecentPdfs) {
      unawaited(_snapshotOpenedDocument(built, bytes));
    }
    // Dispose the preview's live viewer only after this frame swaps the
    // read-only PdfReader out of the tree - disposing its controller while the
    // widget is still mounted would fault its in-flight render.
    WidgetsBinding.instance.addPostFrameCallback((_) => preview.dispose());
    unawaited(_persistSession());
    return true;
  }

  /// Reads the origin whole (the app's normal open path) into the [loading]
  /// tab - the fallback when a progressive first paint can't be assembled.
  /// Reads from a desktop [path] or a mobile reference [token] (#364).
  Future<void> _fallbackFullOpen(
    DocumentTab loading, {
    required String title,
    String? path,
    String? bookmark,
    String? token,
    String? cachePath,
    void Function(Object error)? onOpenFailed,
  }) async {
    try {
      final bytes =
          await _readOriginFully(path: path, bookmark: bookmark, token: token);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final built = DocumentTab.document(
        title: title,
        bytes: bytes,
        preferences: _prefs,
        originPath: path,
        originBookmark: bookmark,
        cachePath: cachePath,
      );
      final opened = _replaceLoadingTab(loading, built);
      if (opened) {
        // With a reusable file origin (desktop) record the recent directly;
        // a mobile pick (no path) snapshots the bytes so Recent/restore reopen
        // from the local copy - the same reopen path a plain mobile open takes.
        if (path != null || !canCacheRecentPdfs) {
          _recents.add(
              title: title,
              path: path,
              cachePath: cachePath,
              bookmark: bookmark);
        } else {
          unawaited(_snapshotOpenedDocument(built, bytes));
        }
      }
    } catch (error) {
      onOpenFailed?.call(error);
      if (!mounted) return;
      _replaceLoadingTab(
        loading,
        DocumentTab.error(
          title: title,
          error: appL10n(context).editorCouldNotOpenDetail(title, '$error'),
        ),
      );
    }
  }

  Future<void> _pickAndOpen() async {
    // Resolve error-toast strings before the async gaps below.
    final l10n = appL10n(context);
    // On phones/tablets the OS picker copies the whole file into the sandbox
    // before the app sees a byte, paying the full cloud transport up front
    // (#364). Prefer the reference picker there: it keeps the original file so
    // a cloud pick can first-paint from ranged reads. Falls back to the plain
    // copy-based picker on a runner without the channel, or a non-seekable
    // provider.
    if (supportsMobileProgressiveOpen) {
      try {
        await _pickAndOpenMobile();
        return;
      } on MissingPluginException {
        // Older runner without the mobile_file channel - fall through to the
        // copy-based picker below.
      } catch (e) {
        _openError(
            l10n.editorOpenFailedTitle, l10n.editorCouldNotOpenSelected('$e'));
        return;
      }
    }
    try {
      final files = await pickPdfFiles(l10n.fileTypePdf);
      if (files.isEmpty) return;
      // Opening a batch: defer parsing every file but the one that ends up
      // active, so the picker doesn't freeze while it opens all of them.
      final defer = files.length > 1;
      for (final file in files) {
        if (!mounted) return;
        final path = originPathForPickedFile(file);
        final bookmark = await securityBookmarkForPath(path);
        // A single desktop pick opens progressively (first paint from ranged
        // reads, full bytes behind it). A batch keeps the deferred whole-file
        // path so the picker doesn't fan out many concurrent streams.
        if (!defer && progressiveOpenSupported(path)) {
          await _openProgressive(
              title: file.name, path: path!, bookmark: bookmark);
        } else {
          // Probe the pick's declared size before the read, so a stalled
          // readAsBytes shows up as "size known, bytes never ready".
          int? pickLength;
          try {
            pickLength = await file.length();
          } catch (_) {}
          AppDevTools.instance.addLog('open-trace: picked "${file.name}" '
              '(declared ${pickLength ?? "?"} B, path=${path ?? "-"}); '
              'starting readAsBytes');
          await _openLoadedBytes(
            file.readAsBytes(),
            title: file.name,
            originPath: path,
            originBookmark: bookmark,
            defer: defer,
          );
        }
      }
    } catch (e) {
      _openError(
          l10n.editorOpenFailedTitle, l10n.editorCouldNotOpenSelected('$e'));
    }
  }

  /// Opens phone/tablet picks through the reference picker (#364): the runner
  /// hands back a token to the *original* file (not a sandbox copy) plus a
  /// seekability probe. A single seekable pick opens progressively (first paint
  /// from native ranged reads, full bytes streamed in behind it, then a private
  /// snapshot for reopen). A non-seekable provider - many cloud providers hand
  /// SAF a pipe - streams the reference whole instead, the same cost as the old
  /// picker copy. A batch defers parsing every tab but the active one, as the
  /// desktop path does. Throws [MissingPluginException] up to [_pickAndOpen] on
  /// a runner without the channel.
  Future<void> _pickAndOpenMobile() async {
    final picks = await pickPdfMobileReferences();
    if (picks.isEmpty) return;
    final defer = picks.length > 1;
    for (final pick in picks) {
      if (!mounted) return;
      if (!defer && pick.seekable) {
        await _openProgressive(title: pick.name, token: pick.token);
      } else {
        // Non-seekable, or a batch we won't fan out into concurrent streams:
        // drain the reference whole (still one read of the original, no OS
        // copy) and open it like any other loaded document.
        await _openLoadedBytes(
          _readOriginFully(token: pick.token),
          title: pick.name,
          defer: defer,
        );
      }
    }
  }

  String _nextUntitledTitle() {
    final titles = {for (final tab in _tabs) tab.title};
    var number = 1;
    while (true) {
      final title = number == 1 ? 'Untitled.pdf' : 'Untitled $number.pdf';
      if (!titles.contains(title)) return title;
      number++;
    }
  }

  Future<void> _newDocument() async {
    final pageSize = await showNewDocumentDialog(context);
    if (!mounted || pageSize == null) return;
    final tab = DocumentTab.document(
      title: _nextUntitledTitle(),
      bytes: PdfBlankDocument.create(pageSize: pageSize),
      preferences: _prefs,
      initiallyDirty: true,
    );
    // A newly-created file is always an editing session, even if the previous
    // document had switched the whole app into read-only mode.
    _readOnly = false;
    _addTab(tab);
  }

  void _newWindow() {
    final open = widget.onNewWindow;
    if (open == null) return;
    if (!open(context)) {
      _toast(appL10n(context).editorUnableToOpenNewWindow);
    }
  }

  /// True while a device scan is up. The platform scanner runs one session at a
  /// time - a second request while the camera is open comes straight back as an
  /// error ("Another scan is already running") - so a second tap no-ops instead
  /// of turning into a failure toast.
  bool _scanInFlight = false;

  /// Runs the device scanner. Null means "no pages": cancelled, unavailable, or
  /// failed - a failure has already been logged and toasted by the time this
  /// returns, so callers just stop.
  ///
  /// The toast carries the platform's own reason. "The camera never opened" and
  /// "the capture couldn't be read back" are different bugs with the same
  /// symptom, and the message has to say which one happened.
  Future<Uint8List?> _runScan() async {
    final scan = _documentScanner;
    if (scan == null || _scanInFlight) return null;
    _scanInFlight = true;
    try {
      return await scan();
    } catch (e) {
      AppDevTools.instance.addLog('scan failed: $e', level: DevLogLevel.error);
      if (mounted) {
        _toast(_scanFailureMessage(e), duration: const Duration(seconds: 6));
      }
      return null;
    } finally {
      _scanInFlight = false;
    }
  }

  /// The localized "couldn't scan" sentence plus the underlying error, trimmed
  /// to something a snack bar can hold.
  String _scanFailureMessage(Object error) {
    var detail = error.toString();
    if (detail.length > 140) detail = '${detail.substring(0, 140)}…';
    return '${appL10n(context).editorScanFailed} $detail';
  }

  /// Scans a document with the device camera (mobile/tablet only) and opens
  /// the captured pages as a new tab. The scanner returns the pages as a PDF;
  /// a cancelled scan is a silent no-op, a failed one toasts.
  Future<void> _newDocumentFromScan() async {
    final bytes = await _runScan();
    if (!mounted || bytes == null) return;
    final tab = DocumentTab.document(
      title: _nextUntitledTitle(),
      bytes: bytes,
      preferences: _prefs,
      initiallyDirty: true,
    );
    _readOnly = false;
    _addTab(tab);
  }

  /// Scans a document (mobile/tablet only) and inserts its pages into [tab]'s
  /// edit session, after the page currently in view. One undoable step.
  Future<void> _insertScan(DocumentTab tab) async {
    final session = tab.session;
    if (session == null) return;
    final bytes = await _runScan();
    if (!mounted || bytes == null) return;
    final insertedAt = (tab.viewer?.currentPage ?? 0) + 1;
    try {
      session.insertPagesFromBytes(bytes, at: insertedAt);
    } catch (e) {
      AppDevTools.instance
          .addLog('scan insert failed: $e', level: DevLogLevel.error);
      if (mounted) _toast(appL10n(context).editorScanFailed);
      return;
    }
    // Reveal the first inserted page. The revision swap rebuilds the viewer and
    // a geometry-changing revision resets its scroll to the top in a post-frame
    // callback, so navigate after two frames - once the new page metrics and
    // that reset have both landed (mirrors the thumbnail insert/paste flow).
    final viewer = tab.viewer;
    if (viewer != null) {
      unawaited(() async {
        await SchedulerBinding.instance.endOfFrame;
        await SchedulerBinding.instance.endOfFrame;
        await viewer.jumpToPage(insertedAt);
      }());
    }
    if (mounted) _toast(appL10n(context).editorInsertedScan);
  }

  /// Opens a file the OS handed us (association, share, launch arg).
  ///
  /// The document lands at the end of the strip and becomes the active tab -
  /// it is the one the user just asked for. Startup restore keeps out of its
  /// way (see [_addTab]), so this holds however the two race.
  ///
  /// If a tab already holds this exact path, focus it instead of opening a
  /// duplicate. The same launch file can arrive twice - once via the
  /// command-line launch args and once via the native `getInitialFile`
  /// channel (Windows delivers both) - and re-opening an already-open
  /// document from the OS should surface the existing tab, not stack copies.
  /// When that existing tab is one startup restore put back, it moves to the
  /// end: the user opened this file, so it belongs exactly where it would
  /// have landed had the OS beaten restore to it.
  Future<void> _openIncoming(IncomingFile file) async {
    final path = file.path;
    if (path != null && path.isNotEmpty) {
      final existing = _tabs.indexWhere((t) => t.originPath == path);
      if (existing != -1) {
        final tab = _tabs[existing];
        // Only a restored tab the user has never opened moves: it is still a
        // placeholder, so re-slotting it is invisible. A document already on
        // its feet keeps its place - the user put it there.
        final move = existing < _restoredTabs &&
            (tab.isDeferredPath || tab.isDeferred || tab.isLoading);
        setState(() {
          if (move) {
            _restoredTabs--;
            _tabs.add(_tabs.removeAt(existing));
          }
          _activeIndex = move ? _tabs.length - 1 : existing;
        });
        if (move) unawaited(_persistSession());
        return;
      }
    }
    // An OS-handed file with a real path opens progressively; one delivered as
    // raw bytes (Android content://, web handle) is already fully in memory.
    if (file.bytes == null && progressiveOpenSupported(file.path)) {
      await _openProgressive(
          title: file.name, path: file.path!, bookmark: file.bookmark);
      return;
    }
    await _openLoadedBytes(
      file.bytes == null
          ? readPdfAtPath(file.path!, bookmark: file.bookmark)
          : Future<Uint8List>.value(file.bytes!),
      title: file.name,
      originPath: file.path,
      originBookmark: file.bookmark,
    );
  }

  /// Handles PDFs dropped onto the window (desktop and web). Non-PDFs are
  /// ignored. A drop onto the page thumbnails (the strip or the full-area
  /// grid) inserts the pages at the marked position - the drop point picked
  /// the answer, so there's nothing to ask. Anywhere else, with an editable
  /// document already open, the drop offers a choice - open each PDF in its
  /// own tab, or append their pages to the current document; with nothing
  /// open (or in read-only mode) each PDF just opens in its own tab.
  Future<void> _onFilesDropped(DropDoneDetails details) async {
    final pdfs = [
      for (final item in details.files)
        if (item.name.toLowerCase().endsWith('.pdf')) item,
    ];
    // Read the drop slot before clearing the drag: the panels answer from
    // their live geometry, which the clear repaints away.
    final at = _thumbnailDrop.indexAt(details.globalPosition);
    _thumbnailDrop.endDrag();
    if (pdfs.isEmpty) return;

    final tab = _active;
    final session = tab?.session;
    if (session != null && !_readOnly) {
      if (at != null) {
        await _insertDropped(pdfs, session, tab!.title, at: at);
        return;
      }
      final action = await _promptDropAction(pdfs.length, tab!.title);
      if (action == null || !mounted) return; // cancelled / disposed
      if (action == _DropAction.insert) {
        await _insertDropped(pdfs, session, tab.title);
        return;
      }
    }
    await _openDropped(pdfs);
  }

  /// Tracks a file drag across the window so the thumbnail panels can mark
  /// where a drop would insert the pages.
  void _onDragMoved(Offset globalPosition) {
    final over = _thumbnailDrop.dragOver(globalPosition) != null;
    if (over == _draggingOverThumbnails && _dragging) return;
    setState(() {
      _dragging = true;
      _draggingOverThumbnails = over;
    });
  }

  /// The drag left the window (or ended): drop the hint and the marker.
  void _onDragEnded() {
    _thumbnailDrop.endDrag();
    setState(() {
      _dragging = false;
      _draggingOverThumbnails = false;
    });
  }

  /// Opens each dropped [pdfs] item in its own tab.
  Future<void> _openDropped(List<DropItem> pdfs) async {
    // Dropping a batch: parse only the tab that ends up active, deferring the
    // rest until they're visited (see _materializeDeferred).
    final defer = pdfs.length > 1;
    for (final item in pdfs) {
      // desktop_drop exposes a real path on desktop; on web it's a blob ref
      // we don't treat as a writable origin.
      final path = (!kIsWeb && item.path.isNotEmpty) ? item.path : null;
      final bookmark = await securityBookmarkForPath(path);
      if (!defer && progressiveOpenSupported(path)) {
        await _openProgressive(
            title: item.name, path: path!, bookmark: bookmark);
      } else {
        await _openLoadedBytes(
          item.readAsBytes(),
          title: item.name,
          originPath: path,
          originBookmark: bookmark,
          defer: defer,
        );
      }
    }
  }

  /// Inserts the pages of each dropped PDF into the active document's edit
  /// session, in drop order: at page [at] when the drop landed on a
  /// thumbnail panel, appended at the end otherwise. Unreadable files are
  /// skipped and reported; the result is one undoable step per inserted
  /// file. A positioned insert scrolls the viewer to the first new page.
  Future<void> _insertDropped(
      List<DropItem> pdfs, PdfEditingController session, String title,
      {int? at}) async {
    var inserted = 0;
    // each file lands after the ones already inserted, so a multi-file drop
    // keeps its order
    var next = at;
    final failed = <String>[];
    for (final item in pdfs) {
      try {
        final bytes = await item.readAsBytes();
        final before = session.document.pageCount;
        session.insertPagesFromBytes(bytes, at: next);
        if (next != null) next += session.document.pageCount - before;
        inserted++;
      } catch (e) {
        AppDevTools.instance.addLog('insert failed: ${item.name} - $e',
            level: DevLogLevel.error);
        failed.add(item.name);
      }
    }
    if (!mounted) return;
    if (at != null && inserted > 0) _revealInsertedPage(at);
    if (inserted == 0) {
      _toast(appL10n(context).editorCouldNotInsertDropped(pdfs.length));
    } else if (failed.isEmpty) {
      _toast(appL10n(context).editorInsertedIntoTitle(inserted, title));
    } else {
      _toast(appL10n(context)
          .editorInsertedButFailed(inserted, failed.join(', ')));
    }
  }

  /// Scrolls the active viewer to [index] - the first page a positioned
  /// insert just added. The revision swap rebuilds the viewer and a
  /// geometry-changing revision resets its scroll in a post-frame callback,
  /// so navigate after two frames, once both have landed (the same route the
  /// thumbnail strip's insert/paste takes).
  void _revealInsertedPage(int index) {
    final viewer = _active?.viewer;
    if (viewer == null) return;
    unawaited(() async {
      await SchedulerBinding.instance.endOfFrame;
      await SchedulerBinding.instance.endOfFrame;
      await viewer.jumpToPage(index);
    }());
  }

  /// Asks whether dropped PDFs (with a document already open) should open in
  /// new tabs or have their pages inserted into the current document. Returns
  /// null when cancelled.
  Future<_DropAction?> _promptDropAction(int count, String title) {
    return showPdfDialog<_DropAction>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('drop-action-dialog'),
        title: Text(appL10n(context).editorAddDroppedTitle(count)),
        content: Text(appL10n(context).editorAddDroppedMessage(count, title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(appL10n(context).cancel),
          ),
          TextButton(
            key: const ValueKey('drop-action-open'),
            onPressed: () => Navigator.of(context).pop(_DropAction.open),
            child: Text(appL10n(context).editorOpenInNewTab(count)),
          ),
          FilledButton(
            key: const ValueKey('drop-action-insert'),
            onPressed: () => Navigator.of(context).pop(_DropAction.insert),
            child: Text(appL10n(context).editorInsertPages),
          ),
        ],
      ),
    );
  }

  Future<void> _openRecent(RecentFile entry) async {
    final readPath = entry.readPath;
    if (readPath == null) {
      // No usable source (web): fall back to a fresh pick.
      await _pickAndOpen();
      return;
    }
    // Desktop reopens by its writable origin; a mobile entry reads back its
    // private snapshot but has no origin, so saves there still go save-as.
    final originPath = entry.path;
    // A desktop origin reopens progressively - the whole point of #359 is the
    // big cloud-synced file that took tens of seconds to reopen whole.
    if (progressiveOpenSupported(originPath)) {
      await _openProgressive(
        title: entry.title,
        path: originPath!,
        bookmark: entry.bookmark,
        cachePath: entry.cachePath,
        onOpenFailed: (_) {
          unawaited(_recents.remove(entry.id));
          _pruneRecentCache();
          _toast(appL10n(context).editorCouldNotReopen(entry.title));
        },
      );
      return;
    }
    final loading = _openLoading(
      entry.title,
      originPath: originPath,
      originBookmark: entry.bookmark,
      cachePath: entry.cachePath,
    );
    try {
      final bytes = await readPdfAtPath(readPath, bookmark: entry.bookmark);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final opened = _replaceLoadingTab(
        loading,
        DocumentTab.document(
          title: entry.title,
          bytes: bytes,
          preferences: _prefs,
          originPath: originPath,
          originBookmark: entry.bookmark,
          cachePath: entry.cachePath,
        ),
      );
      if (opened) {
        _recents.add(
            title: entry.title,
            path: originPath,
            cachePath: entry.cachePath,
            bookmark: entry.bookmark);
      }
    } catch (e) {
      await _recents.remove(entry.id);
      _pruneRecentCache();
      if (!mounted) return;
      _replaceLoadingTab(
        loading,
        DocumentTab.error(
          title: entry.title,
          error: appL10n(context).editorCouldNotOpenDetail(entry.title, '$e'),
        ),
      );
      _toast(appL10n(context).editorCouldNotReopen(entry.title));
    }
  }

  List<RecentFile> _recentMenuEntries() {
    return _availableRecentEntries().take(_maxRecentMenuItems).toList();
  }

  Set<String> _openRecentIds() => {
        for (final tab in _tabs)
          if (tab.originPath != null && tab.originPath!.isNotEmpty)
            tab.originPath!
          else if (tab.cachePath != null && tab.cachePath!.isNotEmpty)
            tab.cachePath!
          else
            tab.title,
      };

  List<RecentFile> _availableRecentEntries() {
    final openIds = _openRecentIds();
    return [
      for (final entry in _recents.items)
        if (!openIds.contains(entry.id)) entry,
    ];
  }

  void _showRecentFiles() {
    unawaited(Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RecentFilesScreen(
          recents: _recents,
          thumbnails: _recentThumbnails,
          excludedIds: _openRecentIds(),
          onOpenRecent: (entry) => unawaited(_openRecent(entry)),
        ),
      ),
    ));
  }

  void _openMostRecent() {
    final recents = _recentMenuEntries();
    if (recents.isEmpty) {
      _toast(appL10n(context).editorNoRecentFiles);
      return;
    }
    unawaited(_openRecent(recents.first));
  }

  /// Opens a second PDF and compares it against the active document. The
  /// active document is the "before".
  Future<void> _compareWith() async {
    final tab = _active;
    final current = tab?.session?.bytes;
    if (current == null) return;
    final l10n = appL10n(context);
    try {
      final other = await pickPdfBytes(l10n.fileTypePdf);
      if (other == null) return;
      setState(() {
        _tabs.add(DocumentTab.comparison(
          title: l10n.editorCompareTitle(tab!.title),
          before: current,
          after: other,
        ));
        _activeIndex = _tabs.length - 1;
      });
    } catch (e) {
      _openError(
          l10n.editorCompareFailedTitle, l10n.editorCouldNotOpenSecond('$e'));
    }
  }

  /// Adds an invisible, selectable/searchable OCR text layer over the active
  /// document, running entirely on-device (pdf_ocr_ondevice). The model
  /// downloads once on first use; OCR runs in the **background** (progress in
  /// the app bar, cancellable) so the user keeps interacting with the PDF.
  /// The result opens in a new tab; the original is left untouched.
  Future<void> _runOcr() async {
    final tab = _active;
    final bytes = tab?.session?.bytes;
    if (tab == null || bytes == null) {
      _toast(appL10n(context).editorOpenDocBeforeOcr);
      return;
    }
    // Snapshot the title now - the source tab may be closed before OCR ends.
    final title = tab.title;
    await _ocr.start(
      context,
      bytes: bytes,
      title: title,
      onToast: (message) {
        if (mounted) _toast(message);
      },
      onComplete: (result) {
        if (mounted) {
          _openBytes(result, appL10n(context).editorOcrTitle(title));
        }
      },
    );
  }

  /// Closes the tab at [index], confirming first when it has unsaved edits.
  Future<void> _closeTab(int index) => _closeTabs([_tabs[index]]);

  /// Closes every tab in [targets] (tab objects, stable across the removals),
  /// confirming once when any of them has unsaved edits. The previously active
  /// document stays active wherever it lands; if it was closed, the selection
  /// falls to a surviving neighbour.
  Future<void> _closeTabs(List<DocumentTab> targets) async {
    if (targets.isEmpty) return;
    final dirty = targets.where((t) => t.isDirty).length;
    if (dirty > 0) {
      final ok = await _confirmDiscard(
        appL10n(context).editorUnsavedChangesCount(dirty),
      );
      if (!ok || !mounted) return;
    }
    _removeTabs(targets);
  }

  /// Removes tabs after their contents have either been discarded or handed
  /// safely to another window.
  void _removeTabs(List<DocumentTab> targets) {
    final active = _active;
    // Chrome-style width hold: while the cursor is over the strip, keep the
    // surviving tabs at their current width so the next close button lands
    // under the cursor. `??=` preserves the width from the first close of a
    // streak; it's released when the pointer leaves the strip.
    if (_tabStripHovered && _lastNaturalTabWidth > 0) {
      _heldTabWidth ??= _lastNaturalTabWidth;
    }
    setState(() {
      for (final tab in targets) {
        final index = _tabs.indexOf(tab);
        if (index == -1) continue;
        // Keep the restored-block count honest: a session document whose file
        // has vanished drops its placeholder mid-restore.
        if (index < _restoredTabs) _restoredTabs--;
        _tabs.removeAt(index);
      }
      // Keep the previously active document active when it survived.
      final keep = active == null ? -1 : _tabs.indexOf(active);
      if (keep >= 0) {
        _activeIndex = keep;
      } else {
        if (_activeIndex >= _tabs.length) _activeIndex = _tabs.length - 1;
        if (_activeIndex < 0) _activeIndex = 0;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final tab in targets) {
        tab.dispose();
      }
    });
    unawaited(_persistSession());
  }

  void _moveTabToNewWindow(DocumentTab tab) {
    final open = widget.onNewWindow;
    final session = tab.session;
    if (open == null || session == null) return;

    final handoff = DocumentHandoff.fromTab(tab);
    if (!open(context, document: handoff)) {
      _toast(appL10n(context).editorUnableToOpenNewWindow);
      return;
    }
    _removeTabs([tab]);
  }

  /// Opens the right-click context menu for the tab at [index] at [position]
  /// (global coordinates), offering Close / Close others / Close to the right /
  /// Close all. Entries that would close nothing are disabled.
  ///
  /// [onChanged] runs after the chosen action resolves; the tabs-grid overlay
  /// passes it to refresh (or dismiss itself once the last tab is gone), since
  /// the modal grid does not rebuild off the screen's own [setState].
  Future<void> _showTabMenu(
    int index,
    Offset position, {
    VoidCallback? onChanged,
  }) async {
    final tab = _tabs[index];
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<_TabMenuAction>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: [
        // Match the app menu's tight rows on desktop (kMinInteractiveDimension
        // stays on touch platforms) so every popup reads at one size.
        if (supportsOpenContainingFolder && tab.originPath != null) ...[
          PopupMenuItem(
            key: const ValueKey('tab-menu-open-folder'),
            height: _appMenuItemHeight(),
            value: _TabMenuAction.openFolder,
            child: Text(openContainingFolderLabel),
          ),
          const PopupMenuDivider(),
        ],
        if (widget.onNewWindow != null && tab.session != null) ...[
          PopupMenuItem(
            key: const ValueKey('tab-menu-move-window'),
            height: _appMenuItemHeight(),
            value: _TabMenuAction.moveToNewWindow,
            child: Text(appL10n(context).editorMoveToNewWindow),
          ),
          const PopupMenuDivider(),
        ],
        PopupMenuItem(
          key: const ValueKey('tab-menu-close'),
          height: _appMenuItemHeight(),
          value: _TabMenuAction.close,
          child: Text(appL10n(context).close),
        ),
        PopupMenuItem(
          key: const ValueKey('tab-menu-close-others'),
          height: _appMenuItemHeight(),
          value: _TabMenuAction.closeOthers,
          enabled: _tabs.length > 1,
          child: Text(appL10n(context).editorCloseOthers),
        ),
        PopupMenuItem(
          key: const ValueKey('tab-menu-close-right'),
          height: _appMenuItemHeight(),
          value: _TabMenuAction.closeRight,
          enabled: index < _tabs.length - 1,
          child: Text(appL10n(context).editorCloseTabsToRight),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          key: const ValueKey('tab-menu-close-all'),
          height: _appMenuItemHeight(),
          value: _TabMenuAction.closeAll,
          child: Text(appL10n(context).editorCloseAll),
        ),
      ],
    );
    if (selected == null || !mounted) return;
    // Re-resolve the tab's current position - nothing reorders while the modal
    // menu is up, but indexing by identity is robust regardless.
    final i = _tabs.indexOf(tab);
    if (i < 0) return;
    switch (selected) {
      case _TabMenuAction.openFolder:
        final opened = await openContainingFolder(
          tab.originPath,
          bookmark: tab.originBookmark,
        );
        if (!opened && mounted) {
          _toast(appL10n(context).editorCouldNotOpenFolder);
        }
      case _TabMenuAction.moveToNewWindow:
        _moveTabToNewWindow(tab);
      case _TabMenuAction.close:
        await _closeTabs([tab]);
      case _TabMenuAction.closeOthers:
        await _closeTabs(_tabs.where((t) => t != tab).toList());
      case _TabMenuAction.closeRight:
        await _closeTabs(_tabs.sublist(i + 1));
      case _TabMenuAction.closeAll:
        await _closeTabs(List.of(_tabs));
    }
    onChanged?.call();
  }

  Future<bool> _confirmDiscard(String message) async {
    final result = await showPdfDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(appL10n(context).editorDiscardChangesTitle),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(appL10n(context).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(appL10n(context).editorDiscard),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // --- saving --------------------------------------------------------------

  /// Saves [tab]. A plain Save overwrites the document's on-disk origin when
  /// there is one (desktop); otherwise, and for an explicit `saveAs`, it
  /// prompts for a location (save dialog / browser download / share sheet).
  /// An in-place write that fails (e.g. permissions) falls back to save-as.
  Future<void> _save(DocumentTab tab, {bool saveAs = false}) async {
    final bytes = tab.session?.bytes;
    if (bytes == null) return;
    final saveAsDocument = widget.saveDocumentAs ??
        (ctx, bytes, name) =>
            saveBytesAs(ctx, bytes, name, pdfLabel: appL10n(ctx).fileTypePdf);
    final saveToPath = widget.saveDocumentToPath ?? saveBytesToPath;
    final inPlace = !saveAs && tab.originPath != null && supportsInPlaceSave;
    var result = inPlace
        ? await saveToPath(
            bytes,
            tab.originPath!,
            bookmark: tab.originBookmark,
          )
        : await saveAsDocument(context, bytes, tab.title);
    if (!mounted) return;
    if (inPlace && !result.succeeded) {
      // The origin couldn't be written (moved, read-only) - offer save-as.
      result = await saveAsDocument(context, bytes, tab.title);
      if (!mounted) return;
    }
    if (result.succeeded) {
      final path = result.path;
      final existingBookmark =
          path != null && path == tab.originPath ? tab.originBookmark : null;
      final bookmark = path == null
          ? null
          : (await securityBookmarkForPath(path)) ?? existingBookmark;
      if (!mounted) return;
      setState(() {
        tab.markSaved();
        if (path != null) {
          tab.title = path.split(RegExp(r'[/\\]')).last;
          tab.originPath = path;
          tab.originBookmark = bookmark;
          // A stable Save As destination supersedes a private mobile/open
          // snapshot. Session restore and future Save now follow the new file.
          tab.cachePath = null;
        }
      });
      // Saving never touches the edit session, so nothing notifies the mirror -
      // tell it directly. The bytes are on the user's own disk now and the
      // recovery copy has nothing left to protect.
      unawaited(_autosave.noteSaved(tab));
      if (path != null) {
        _recents.add(
            title: tab.title, path: path, bookmark: tab.originBookmark);
        // A Save As gave the tab a reusable origin - remember it for next time.
        unawaited(_persistSession());
      }
    }
    if (result.message != null) _toast(result.message!);
  }

  // --- printing ------------------------------------------------------------

  /// Reuses a keyless (Sigstore/Fulcio) identity across signatures while its
  /// short-lived certificate (~10 min) stays valid, so most boxes need no
  /// fresh OIDC sign-in.
  final _keylessCache = KeylessIdentityCache();

  /// A keyless identity for signing: the cached one while its cert is valid,
  /// else freshly minted via [tokenProvider] (interactive or silent).
  Future<PdfSigningIdentity?> _obtainKeyless(
          BuildContext context, OidcTokenProvider tokenProvider) =>
      _keylessCache.obtain(
          context,
          (context) =>
              keylessSigningIdentity(context, tokenProvider: tokenProvider));

  /// Opens the digital-signature dialog and signs. When [placement] is set
  /// (the signature-box tool drew a rectangle), the dialog offers the visible
  /// appearance (hand-drawn mark, logo backdrop) and the signature is rendered
  /// into that box; otherwise the signature is invisible.
  Future<void> _digitallySign(DocumentTab tab,
      {SignaturePlacement? placement}) async {
    final session = tab.session;
    if (session == null || _digitallySigning) return;
    setState(() => _digitallySigning = true);
    try {
      final tokenProvider = widget.oidcTokenProvider;
      final silentProvider = widget.oidcSilentTokenProvider;
      final options = await (widget.digitalSignatureOptionsProvider ??
          (context) => showDigitalSigningDialog(
                context,
                createKeylessIdentity: tokenProvider == null
                    ? null
                    : (context) => _obtainKeyless(context, tokenProvider),
                timestampClient:
                    tokenProvider == null ? null : defaultTimestampClient,
                // On the web the OAuth broker can't complete in a browser tab,
                // so keyless is native-only; tell the user where to find it.
                keylessUnavailable: kIsWeb,
                // Pre-select keyless on open only via the silent provider, so
                // opening the dialog never launches the browser. It reuses the
                // cached Fulcio identity while its cert is valid (~10 min), so
                // most boxes need no OIDC token at all.
                autoCreateKeylessIdentity:
                    (tokenProvider == null || silentProvider == null)
                        ? null
                        : (context) => _obtainKeyless(context, silentProvider),
                placement: placement,
                logoPicker: placement == null ? null : pickImageBytesFromSource,
                pageCount: session.document.pageCount,
              ))(context);
      if (!mounted || options == null || !_tabs.contains(tab)) return;
      final keyless = options.keylessIdentity;
      final selfSigned = options.selfSignedIdentity;
      if (keyless != null) {
        await session.addKeylessSignature(
          keyless,
          timestampClient: options.timestampClient!,
          fieldName: options.fieldName,
          reason: options.reason,
          location: options.location,
          contactInfo: options.contactInfo,
          signingTime: options.signingTime,
          appearance: options.appearance,
        );
      } else if (selfSigned != null) {
        await session.addSelfSignedSignature(
          selfSigned,
          fieldName: options.fieldName,
          reason: options.reason,
          location: options.location,
          contactInfo: options.contactInfo,
          signingTime: options.signingTime,
          appearance: options.appearance,
        );
      } else {
        await session.addDigitalSignature(
          options.identity!,
          fieldName: options.fieldName,
          reason: options.reason,
          location: options.location,
          contactInfo: options.contactInfo,
          signingTime: options.signingTime,
          appearance: options.appearance,
        );
      }
      if (!mounted || !_tabs.contains(tab)) return;
      // Signing is a document revision, then follows the normal save path so
      // an existing origin is overwritten and an untitled document gets a
      // Save As destination. Cancelling Save As leaves the signed tab dirty.
      await _save(tab);
      // Offer an immediate undo, in case the signature was placed by accident.
      if (mounted && _tabs.contains(tab)) _offerSignatureUndo(tab);
    } on FormatException catch (error) {
      if (mounted) {
        _toast(appL10n(context).editorCouldNotSign(error.message));
      }
    } catch (error) {
      if (mounted) _toast(appL10n(context).editorCouldNotSign('$error'));
    } finally {
      if (mounted) setState(() => _digitallySigning = false);
    }
  }

  /// Shows a snackbar offering to undo a signature just placed (its revision
  /// sits on the undo stack), removing it and re-saving without it.
  void _offerSignatureUndo(DocumentTab tab) {
    final session = tab.session;
    if (session == null || !session.canUndo) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(appL10n(context).editorDocumentSigned),
        behavior: SnackBarBehavior.floating,
        margin: pdfFloatingToastMargin(context),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: appL10n(context).undo,
          onPressed: () => unawaited(_undoSignature(tab)),
        ),
      ));
  }

  /// Removes the just-placed signature (undoes its revision) and re-saves so
  /// the file no longer carries it.
  Future<void> _undoSignature(DocumentTab tab) async {
    final session = tab.session;
    if (session == null || !session.canUndo || !_tabs.contains(tab)) return;
    session.undo();
    if (!mounted || !_tabs.contains(tab)) return;
    await _save(tab);
    if (mounted) _toast(appL10n(context).editorSignatureRemoved);
  }

  /// Hands the active document to the OS print system (the app's own
  /// `native_print` channel - the OS dialog on desktop/mobile, browser print on
  /// the web). The current revision is printed, so unsaved edits are included.
  /// A failed or unavailable backend surfaces as a toast rather than throwing.
  ///
  /// Where the platform's print flow has no preview of its own (Windows and
  /// Linux - see [platformProvidesPrintPreview]), DartPDF previews the job
  /// first and prints the page range chosen there. A narrowed range prints an
  /// extract of the document rather than the whole file, which is also how the
  /// range reaches the platforms whose print path takes a whole PDF.
  Future<void> _print(DocumentTab tab) async {
    final session = tab.session;
    if (session == null) return;
    var bytes = session.bytes;
    try {
      if (!platformProvidesPrintPreview()) {
        final pages = await showPrintPreviewDialog(
          context,
          document: session.document,
          title: tab.title,
          currentPage: tab.viewer?.currentPage ?? 0,
        );
        if (pages == null || !mounted || !_tabs.contains(tab)) return;
        // The preview is modal, but the session stays the source of truth for
        // what prints - re-read it rather than trusting the pre-dialog bytes.
        final document = session.document;
        final selection = pages
            .where((page) => page >= 0 && page < document.pageCount)
            .toList();
        if (selection.isEmpty) return;
        bytes = selection.length == document.pageCount
            ? session.bytes
            : document.extractPages(selection);
      }
      final injected = widget.printDocument;
      if (injected != null) {
        await injected(bytes: bytes, title: tab.title);
      } else {
        await _printWithProgress(bytes, tab.title);
      }
    } catch (_) {
      if (mounted) _toast(appL10n(context).editorCouldNotPrint(tab.title));
    }
  }

  /// Runs [printPdfBytes] with a modal progress dialog that tracks page
  /// rendering. The print path rasterises every page up front, which is slow
  /// for large documents, so we surface "page X of Y" progress rather than
  /// appearing frozen.
  ///
  /// The dialog appears only for multi-page (slow) jobs - a one/two-page print
  /// finishes too fast to be worth a flash - and is dismissed once rendering
  /// finishes, before the OS print dialog opens.
  Future<void> _printWithProgress(Uint8List bytes, String title) async {
    final progress = ValueNotifier<(int, int)?>(null);
    final navigator = Navigator.of(context, rootNavigator: true);
    var dialogShown = false;
    void dismiss() {
      if (dialogShown) {
        dialogShown = false;
        navigator.pop();
      }
    }

    try {
      await printPdfBytes(
        bytes: bytes,
        title: title,
        onProgress: (rendered, total) {
          progress.value = (rendered, total);
          if (total > _printProgressThreshold &&
              rendered < total &&
              !dialogShown &&
              mounted) {
            dialogShown = true;
            unawaited(showPdfDialog<void>(
              context: context,
              barrierDismissible: false,
              useRootNavigator: true,
              builder: (_) => PrintProgressDialog(progress: progress),
            ));
          }
          // Rendering done: drop the dialog before the OS print dialog opens.
          if (rendered >= total && mounted) dismiss();
        },
      );
    } finally {
      if (mounted) dismiss();
      progress.dispose();
    }
  }

  /// A print of this many pages or fewer skips the progress dialog - it renders
  /// fast enough that a dialog would just flash.
  static const _printProgressThreshold = 2;

  /// Prints the active document, if one is open - bound to ⌘P / Ctrl+P.
  void _printActive() {
    final tab = _active;
    if (tab?.session != null) unawaited(_print(tab!));
  }

  // --- image export --------------------------------------------------------

  /// Renders the page the viewer is currently on to a PNG/JPEG and saves it
  /// (save dialog on desktop, download on web, share sheet on mobile). The
  /// current revision is used, so unsaved edits are included. Prompts for the
  /// format and resolution first.
  Future<void> _exportImage(DocumentTab tab) async {
    final session = tab.session;
    final viewer = tab.viewer;
    if (session == null || viewer == null) return;

    final options = await showImageExportDialog(context);
    if (options == null || !mounted) return;

    final pageIndex =
        viewer.currentPage.clamp(0, session.document.pageCount - 1);
    try {
      final bytes = await PdfPageExport.exportPage(
        session.document.page(pageIndex),
        format: options.format.rasterFormat,
        dpi: options.dpi,
      );
      if (!mounted) return;
      final name =
          imageExportFileName(tab.title, pageIndex + 1, options.format);
      final result = await saveImageBytesAs(
          context, bytes, name, options.format.mimeType,
          imageLabel: appL10n(context).fileTypeImages);
      if (result.message != null) _toast(result.message!);
    } catch (_) {
      if (mounted) _toast(appL10n(context).editorCouldNotExport(tab.title));
    }
  }

  Future<void> _exportSelectedContentImage(
    BuildContext exportContext,
    DocumentTab tab,
    PdfSelectedContentImage image,
  ) async {
    final name = selectedContentImageFileName(tab.title, image.pageIndex + 1);
    final result = await saveImageBytesAs(
        exportContext, image.pngBytes, name, 'image/png',
        imageLabel: appL10n(exportContext).fileTypeImages);
    if (mounted && result.message != null) _toast(result.message!);
  }

  Future<void> _exportCustomStamps(
    BuildContext exportContext,
    List<PdfCustomStamp> stamps,
  ) async {
    final result = await exportCustomStampsAs(exportContext, stamps,
        stampLabel: appL10n(exportContext).fileTypeStampBundle);
    if (mounted && result.message != null) _toast(result.message!);
  }

  Future<List<PdfCustomStamp>?> _importCustomStamps(BuildContext _) async {
    try {
      return await importCustomStamps(appL10n(context).fileTypeStampBundle);
    } catch (e) {
      if (mounted) _toast(appL10n(context).editorCouldNotImportStamps('$e'));
      return null;
    }
  }

  // --- link actions --------------------------------------------------------

  /// GoTo and named page actions never reach here (the viewer follows them).
  /// URI links open in the system browser; anything else is surfaced.
  void _onAction(PdfAction action, PdfAnnotation annotation) {
    switch (action) {
      case PdfUriAction(:final uri):
        final parsed = Uri.tryParse(uri);
        if (parsed != null) {
          unawaited(_openExternal(parsed));
        } else {
          _toast(appL10n(context).editorInvalidLink(uri));
        }
      case PdfNamedAction(:final name):
        _toast(appL10n(context).editorNamedAction(name));
      case PdfJavaScriptAction():
        _toast(appL10n(context).editorJavaScriptIgnored);
      case PdfUnknownAction(:final type):
        _toast(appL10n(context).editorUnsupportedAction(type));
      case PdfGoToAction():
        break; // unreachable - handled by the viewer
    }
  }

  Future<void> _openExternal(Uri url) async {
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) _toast(appL10n(context).editorCouldNotOpenUrl('$url'));
    }
  }

  List<PdfAnnotationMenuItem> _annotationMenuActions(
      BuildContext context, PdfAnnotationMenuRequest request) {
    final contents = request.primary?.contents;
    if (contents == null || contents.isEmpty) return const [];
    return [
      PdfAnnotationMenuItem(
        label: appL10n(context).editorCopyText,
        icon: Icons.copy_outlined,
        onSelected: (request) {
          Clipboard.setData(ClipboardData(text: contents));
          _toast(appL10n(context).editorAnnotationTextCopied);
        },
      ),
    ];
  }

  /// Shows a transient message. [duration] overrides the default for the rare
  /// toast that carries something to read rather than to acknowledge (an error
  /// with the platform's reason in it).
  void _toast(String message, {Duration? duration}) {
    // Toasts are transient; mirroring them into the devtools log keeps a
    // history (and puts them in the exported snapshot).
    AppDevTools.instance.addLog('toast: $message');
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: pdfFloatingToastMargin(context),
        duration: duration ?? const Duration(seconds: 2),
      ));
  }

  bool get _usesAppleShortcuts =>
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.iOS;

  bool get _usesCompactAppMenu => switch (defaultTargetPlatform) {
        TargetPlatform.macOS ||
        TargetPlatform.windows ||
        TargetPlatform.linux =>
          true,
        _ => false,
      };

  double _appMenuItemHeight({bool twoLine = false}) => !_usesCompactAppMenu
      ? kMinInteractiveDimension
      : twoLine
          ? _compactRecentMenuItemHeight
          : _compactAppMenuItemHeight;

  bool get _showsSelectionCopyAction => switch (defaultTargetPlatform) {
        TargetPlatform.android ||
        TargetPlatform.iOS ||
        TargetPlatform.fuchsia =>
          true,
        TargetPlatform.macOS ||
        TargetPlatform.windows ||
        TargetPlatform.linux =>
          false,
      };

  String _menuShortcut(String key, {bool shift = false}) => _usesAppleShortcuts
      ? '${shift ? '⇧' : ''}⌘$key'
      : 'Ctrl+${shift ? 'Shift+' : ''}$key';

  Widget _appMenuTile({
    required IconData icon,
    required String title,
    String? shortcut,
    Widget? trailing,
    Widget? subtitle,
    TextOverflow? overflow,
  }) =>
      ListTile(
        leading: Icon(icon),
        title: Text(title, overflow: overflow),
        subtitle: subtitle,
        trailing: trailing ??
            (shortcut == null
                ? null
                : Text(
                    shortcut,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  )),
        contentPadding: EdgeInsets.zero,
        minTileHeight: _usesCompactAppMenu
            ? subtitle == null
                ? _compactAppMenuItemHeight
                : _compactRecentMenuItemHeight
            : null,
        minVerticalPadding: _usesCompactAppMenu ? 0 : null,
      );

  List<PopupMenuEntry<VoidCallback>> _recentMenuItems(
      BuildContext menuContext) {
    final recents = _recentMenuEntries();
    final trailing = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _menuShortcut('O', shift: true),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(width: 12),
        const Icon(Icons.arrow_right),
      ],
    );
    return [
      PopupMenuItem<VoidCallback>(
        height: _appMenuItemHeight(),
        value: () {},
        padding: EdgeInsets.zero,
        child: PopupMenuButton<VoidCallback>(
          key: const ValueKey('open-recent-submenu'),
          tooltip: appL10n(context).editorOpenRecent,
          onSelected: (action) {
            action();
            if (Navigator.of(menuContext).canPop()) {
              Navigator.of(menuContext).pop();
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem<VoidCallback>(
              key: const ValueKey('view-all-recent-files'),
              height: _appMenuItemHeight(),
              enabled: _availableRecentEntries().isNotEmpty,
              value: () {
                // The submenu's onSelected callback closes the parent popup.
                // Push the browser on the next frame so that pop cannot close
                // the newly opened route as well.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _showRecentFiles();
                });
              },
              child: _appMenuTile(
                icon: Icons.grid_view_outlined,
                title: appL10n(context).editorViewAllRecentFiles,
              ),
            ),
            if (recents.isNotEmpty) const PopupMenuDivider(),
            if (recents.isEmpty)
              PopupMenuItem<VoidCallback>(
                height: _appMenuItemHeight(),
                enabled: false,
                child: _appMenuTile(
                  icon: Icons.history_toggle_off,
                  title: appL10n(context).editorNoRecentFiles,
                ),
              )
            else ...[
              for (final entry in recents)
                PopupMenuItem<VoidCallback>(
                  height: _appMenuItemHeight(twoLine: entry.path != null),
                  value: () => unawaited(_openRecent(entry)),
                  child: _appMenuTile(
                    icon: Icons.picture_as_pdf_outlined,
                    title: entry.title.isEmpty
                        ? appL10n(context).editorUntitled
                        : entry.title,
                    overflow: TextOverflow.ellipsis,
                    subtitle: entry.path == null
                        ? null
                        : Text(
                            entry.path!,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                  ),
                ),
              const PopupMenuDivider(),
              PopupMenuItem<VoidCallback>(
                height: _appMenuItemHeight(),
                value: () => unawaited(_recents.clear()),
                child: _appMenuTile(
                  icon: Icons.clear_all,
                  title: appL10n(context).editorClearRecentFiles,
                ),
              ),
            ],
          ],
          // The item carries no padding so the submenu button fills the whole
          // row for hit-testing; inset the visible content by the stock menu
          // padding so this row's icon/label line up with the plain items
          // above it (New, Open…), which sit inside that default padding.
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _appMenuTile(
              icon: Icons.history,
              title: appL10n(context).editorOpenRecent,
              trailing: trailing,
            ),
          ),
        ),
      ),
    ];
  }

  List<PopupMenuEntry<VoidCallback>> _appMenuItems(
          BuildContext menuContext, DocumentTab? tab) =>
      [
        PopupMenuItem(
          key: const ValueKey('menu-new-document'),
          height: _appMenuItemHeight(),
          value: () => unawaited(_newDocument()),
          child: _appMenuTile(
            icon: Icons.note_add_outlined,
            title: appL10n(context).editorMenuNewDocument,
            shortcut: _menuShortcut('N'),
          ),
        ),
        if (widget.onNewWindow != null)
          PopupMenuItem(
            key: const ValueKey('menu-new-window'),
            height: _appMenuItemHeight(),
            value: _newWindow,
            child: _appMenuTile(
              icon: Icons.open_in_new,
              title: appL10n(context).editorMenuNewWindow,
              shortcut: _menuShortcut('N', shift: true),
            ),
          ),
        if (_canScan)
          PopupMenuItem(
            key: const ValueKey('menu-scan-document'),
            height: _appMenuItemHeight(),
            value: () => unawaited(_newDocumentFromScan()),
            child: _appMenuTile(
              icon: Icons.document_scanner_outlined,
              title: appL10n(context).editorMenuScanDocument,
            ),
          ),
        PopupMenuItem(
          key: const ValueKey('menu-open'),
          height: _appMenuItemHeight(),
          value: () => unawaited(_pickAndOpen()),
          child: _appMenuTile(
            icon: Icons.folder_open,
            title: appL10n(context).editorMenuOpen,
            shortcut: _menuShortcut('O'),
          ),
        ),
        ..._recentMenuItems(menuContext),
        const PopupMenuDivider(),
        if (tab?.session != null) ...[
          PopupMenuItem(
            key: const ValueKey('menu-save-as'),
            height: _appMenuItemHeight(),
            value: () => _save(tab!, saveAs: true),
            child: _appMenuTile(
              icon: Icons.save_as_outlined,
              title: appL10n(context).editorMenuSaveAs,
              shortcut: _menuShortcut('S', shift: true),
            ),
          ),
          if (_canScan && !_readOnly)
            PopupMenuItem(
              key: const ValueKey('menu-insert-scan'),
              height: _appMenuItemHeight(),
              value: () => unawaited(_insertScan(tab!)),
              child: _appMenuTile(
                icon: Icons.add_a_photo_outlined,
                title: appL10n(context).editorMenuInsertScan,
              ),
            ),
          PopupMenuItem(
            key: const ValueKey('menu-digital-signature'),
            height: _appMenuItemHeight(),
            enabled: !_digitallySigning,
            value: () => unawaited(_digitallySign(tab!)),
            child: _appMenuTile(
              icon: Icons.verified_user_outlined,
              title: _digitallySigning
                  ? appL10n(context).editorMenuDigitallySigning
                  : appL10n(context).editorMenuDigitallySign,
            ),
          ),
          PopupMenuItem(
            key: const ValueKey('menu-print'),
            height: _appMenuItemHeight(),
            value: () => unawaited(_print(tab!)),
            child: _appMenuTile(
              icon: Icons.print_outlined,
              title: appL10n(context).editorMenuPrint,
              shortcut: _menuShortcut('P'),
            ),
          ),
          PopupMenuItem(
            key: const ValueKey('menu-export-image'),
            height: _appMenuItemHeight(),
            value: () => unawaited(_exportImage(tab!)),
            child: _appMenuTile(
              icon: Icons.image_outlined,
              title: appL10n(context).editorMenuExportImage,
            ),
          ),
          PopupMenuItem(
            height: _appMenuItemHeight(),
            value: _compareWith,
            child: _appMenuTile(
              icon: Icons.compare_arrows,
              title: appL10n(context).editorMenuCompareWith,
            ),
          ),
          PopupMenuItem(
            height: _appMenuItemHeight(),
            value: () => setState(() => _readOnly = !_readOnly),
            child: _appMenuTile(
              icon: _readOnly ? Icons.edit : Icons.edit_off,
              title: _readOnly
                  ? appL10n(context).editorMenuSwitchToEdit
                  : appL10n(context).editorMenuSwitchToReadOnly,
            ),
          ),
          if (OnDeviceOcr.isSupported)
            PopupMenuItem(
              key: const ValueKey('menu-ocr'),
              height: _appMenuItemHeight(),
              value: () => unawaited(_runOcr()),
              child: _appMenuTile(
                icon: Icons.document_scanner_outlined,
                title: appL10n(context).editorMenuOcr,
              ),
            ),
          const PopupMenuDivider(),
        ],
        PopupMenuItem(
          height: _appMenuItemHeight(),
          value: () => showAppSettings(
            context,
            prefs: _prefs,
            recents: _recents,
            updates: _updates,
            updateInstaller: _updateInstaller,
            onOpenDevTools: kDevToolsEnabled ? _toggleDevTools : null,
          ),
          child: _appMenuTile(
            icon: Icons.settings_outlined,
            title: appL10n(context).editorMenuSettings,
          ),
        ),
      ];

  /// Shows/hides the developer tools panel (F12; every build mode unless
  /// stripped with --dart-define=DEVTOOLS=false).
  void _toggleDevTools() {
    if (!kDevToolsEnabled) return;
    setState(() => _devToolsOpen = !_devToolsOpen);
  }

  /// Global F12 hook (registered in initState): a devtools toggle must work
  /// regardless of where focus sits - a CallbackShortcuts binding goes deaf
  /// whenever the focused node leaves its subtree (e.g. after the panel
  /// itself opens).
  bool _onGlobalKeyEvent(KeyEvent event) {
    if (kDevToolsEnabled &&
        event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.f12) {
      _toggleDevTools();
      return true;
    }
    return false;
  }

  // --- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final tab = _active;
    return Scaffold(
      appBar: AppBar(
        leading: _buildAppMenu(tab),
        leadingWidth: _appMenuLeadingWidth,
        centerTitle: false,
        title: _tabs.isEmpty ? _buildEmptyTabsTitle() : _buildTabsTitle(),
        titleSpacing: _tabs.isEmpty ? null : 8,
        actions: _buildActions(tab),
      ),
      body: CallbackShortcuts(
        // ⌘P (macOS) / Ctrl+P (Windows, Linux, web) print the active document.
        // Placed above the editor so the SDK's own shortcuts take precedence;
        // an unhandled print key bubbles up to here.
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.keyP, meta: true):
              _printActive,
          const SingleActivator(LogicalKeyboardKey.keyP, control: true):
              _printActive,
          const SingleActivator(LogicalKeyboardKey.keyO, meta: true):
              _pickAndOpen,
          const SingleActivator(LogicalKeyboardKey.keyO, control: true):
              _pickAndOpen,
          const SingleActivator(LogicalKeyboardKey.keyN, meta: true):
              _newDocument,
          const SingleActivator(LogicalKeyboardKey.keyN, control: true):
              _newDocument,
          if (widget.onNewWindow != null)
            const SingleActivator(LogicalKeyboardKey.keyN,
                meta: true, shift: true): _newWindow,
          if (widget.onNewWindow != null)
            const SingleActivator(LogicalKeyboardKey.keyN,
                control: true, shift: true): _newWindow,
          const SingleActivator(LogicalKeyboardKey.keyO,
              meta: true, shift: true): _openMostRecent,
          const SingleActivator(LogicalKeyboardKey.keyO,
              control: true, shift: true): _openMostRecent,
        },
        child: DropTarget(
          onDragEntered: (detail) => _onDragMoved(detail.globalPosition),
          onDragUpdated: (detail) => _onDragMoved(detail.globalPosition),
          onDragExited: (_) => _onDragEnded(),
          onDragDone: (detail) {
            setState(() {
              _dragging = false;
              _draggingOverThumbnails = false;
            });
            _onFilesDropped(detail);
          },
          child: Builder(builder: (context) {
            final compactDevTools = _isCompactWidth(context);
            return Stack(
              children: [
                // On wide screens the devtools panel docks beside the body
                // (like the editor's own sidebars), so the viewer relays out
                // narrower instead of being overlaid - zoom and scroll
                // gestures keep their space. On phones there is no room for a
                // side dock, so it rides up as a bottom sheet instead (below).
                Positioned.fill(
                  child: Row(
                    children: [
                      Expanded(child: _buildBodyWithDevTools(tab)),
                      if (_devToolsOpen && kDevToolsEnabled && !compactDevTools)
                        DevToolsPanel(
                          onClose: _toggleDevTools,
                          session: tab?.session,
                          viewerController: tab?.viewer,
                          documentTitle: tab?.title,
                        ),
                    ],
                  ),
                ),
                // The full-window hint yields to the thumbnails' own
                // insertion marker once the drag is over a page panel - the
                // marker already says exactly where the pages will land.
                if (_dragging && !_draggingOverThumbnails)
                  Positioned.fill(
                    child: _DropOverlay(
                      canInsert: tab?.session != null && !_readOnly,
                    ),
                  ),
                // Phone devtools: a bottom sheet over the viewer. Scrim-less,
                // so the page underneath still takes gestures (matching the
                // docked panel, which never blocked the viewer either).
                if (_devToolsOpen && kDevToolsEnabled && compactDevTools)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: SafeArea(
                      top: false,
                      child: DevToolsPanel(
                        onClose: _toggleDevTools,
                        session: tab?.session,
                        viewerController: tab?.viewer,
                        documentTitle: tab?.title,
                        bottomSheet: true,
                      ),
                    ),
                  ),
              ],
            );
          }),
        ),
      ),
    );
  }

  /// Rebuild only the mounted document shell when its raster-cache policy
  /// changes. Listening to the full [AppDevTools] model here would also rebuild
  /// it for every captured log line and periodic panel refresh.
  Widget _buildBodyWithDevTools(DocumentTab? tab) {
    if (!kDevToolsEnabled) return _buildBody(tab);
    return ValueListenableBuilder<PdfPageRasterCachePolicy>(
      valueListenable: AppDevTools.instance.pageRasterCachePolicy,
      builder: (context, _, __) =>
          ValueListenableBuilder<PdfPageRasterWarmPolicy>(
        valueListenable: AppDevTools.instance.pageRasterWarmPolicy,
        builder: (context, _, __) =>
            ValueListenableBuilder<TileRasterBackendMode>(
          valueListenable: AppDevTools.instance.tileRasterBackendMode,
          builder: (context, _, __) => ValueListenableBuilder<int>(
            valueListenable: AppDevTools.instance.tileRasterBackendRevision,
            builder: (context, _, __) => _devToolsPointerLog(_buildBody(tab)),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(DocumentTab? tab) {
    final compact = _isCompactWidth(context);
    final pageRasterCachePolicy =
        AppDevTools.instance.pageRasterCachePolicy.value;
    final pageRasterWarmPolicy =
        AppDevTools.instance.pageRasterWarmPolicy.value;
    final tileRasterBackend = AppDevTools.instance.tileRasterBackend;
    if (tab == null) {
      return WelcomeScreen(
        recents: _recents,
        onOpen: _pickAndOpen,
        onOpenRecent: _openRecent,
        // Recents can load before the session list. Starting their first-page
        // renders during that transient welcome frame wastes enough platform-
        // thread work to beachball macOS, only for restore to replace the
        // welcome screen immediately. Enable them once restore has decided
        // that there really is no document to show.
        thumbnails: _sessionLoaded ? _recentThumbnails : null,
      );
    }
    if (tab.isDeferredPath) {
      // First time we show a restored path-only tab: open it progressively
      // (after this frame), showing the placeholder meanwhile. Held off while
      // the session is still restoring, so only the finally-active tab opens.
      if (!_restoringSession) _materializeDeferredPath(tab);
      return _OpeningDocument(title: tab.title);
    }
    if (tab.isDeferred) {
      // First time we show a deferred tab: parse it (after this frame) and
      // show the same placeholder a fresh open uses meanwhile.
      _materializeDeferred(tab);
      return _OpeningDocument(title: tab.title);
    }
    if (tab.isLoading) {
      return _OpeningDocument(title: tab.title);
    }
    if (tab.error != null) {
      return Center(child: Text(tab.error!, textAlign: TextAlign.center));
    }
    if (tab.isComparison) {
      return PdfComparisonView(
        key: ValueKey(tab),
        before: tab.compareBefore!,
        after: tab.compareAfter!,
        pageRasterCachePolicy: pageRasterCachePolicy,
        pageRasterWarmPolicy: pageRasterWarmPolicy,
        tileRasterBackend: tileRasterBackend,
      );
    }
    if (tab.isPreview) {
      // A progressive first paint: render the read-only sparse document while
      // the complete bytes stream in, with a slim progress bar for that read.
      return _ProgressivePreview(
        key: ValueKey(tab),
        tab: tab,
        preferences: _prefs,
        onAction: _onAction,
        pageRasterCachePolicy: pageRasterCachePolicy,
        pageRasterWarmPolicy: pageRasterWarmPolicy,
        tileRasterBackend: tileRasterBackend,
      );
    }
    if (_readOnly) {
      return PdfReader(
        key: ValueKey(tab),
        bytes: tab.session!.bytes,
        documentId: tab.documentId,
        controller: tab.viewer,
        preferences: _prefs,
        onAction: _onAction,
        // View mode is for reading the document as it is: the paper colour is
        // an authoring choice, so the View options menu drops "Page color…"
        // here and keeps it in edit mode.
        features: const PdfReaderFeatures(pageColorEditable: false),
        pageRasterCachePolicy: pageRasterCachePolicy,
        pageRasterWarmPolicy: pageRasterWarmPolicy,
        tileRasterBackend: tileRasterBackend,
      );
    }
    return PdfEditorView(
      key: ValueKey(tab),
      documentId: tab.documentId,
      controller: tab.session,
      viewerController: tab.viewer,
      pageRasterCachePolicy: pageRasterCachePolicy,
      pageRasterWarmPolicy: pageRasterWarmPolicy,
      tileRasterBackend: tileRasterBackend,
      onSave: (_) => unawaited(_save(tab)),
      onSaveAs: (_) => unawaited(_save(tab, saveAs: true)),
      showSaveButton: !compact,
      // The shell enables Save off its *own* session history, which misses two
      // cases the app knows about. A brand-new untitled document has no on-disk
      // origin yet, so Save (button + Ctrl/⌘+S) stays live even before the
      // first edit - the first save writes the file via the Save As flow. And a
      // crash-recovered document opens at the revision it was lost on, so the
      // session sees no edits of its own while the app knows the file on disk
      // is still behind - without this the user could not save the very work we
      // just handed back.
      alwaysAllowSave: tab.isUnsaved || tab.isDirty,
      onPickPdfToInsert: () => pickPdfBytes(appL10n(context).fileTypePdf),
      // a PDF dragged in from the desktop can be dropped between two page
      // thumbnails; the drop lands its pages exactly there
      thumbnailDropController: _thumbnailDrop,
      onExportPages: (bytes) => unawaited(saveBytesAs(context, bytes, tab.title,
          pdfLabel: appL10n(context).fileTypePdf)),
      onAction: _onAction,
      annotationMenuBuilder: _annotationMenuActions,
      formImagePicker: (context, field) => pickImageBytesFromSource(context),
      imagePicker: pickImageBytesFromSource,
      systemImagePasteProvider: (context) =>
          (widget.imageClipboardReader ?? readImageFromClipboard)(),
      systemTextPasteProvider: (context) =>
          (widget.textClipboardReader ?? readTextFromClipboard)(),
      onExportSelectedContentImage: (context, image) =>
          _exportSelectedContentImage(context, tab, image),
      onExportCustomStamps: _exportCustomStamps,
      onImportCustomStamps: _importCustomStamps,
      // The Snapshot tool keeps a vector copy on the in-app clipboard for
      // paste-back; this also drops the captured PNG on the system clipboard.
      onSnapshot: clipboardSnapshotHandler(
        writer: widget.imageClipboardWriter,
        onResult: (copied) {
          if (!mounted) return;
          _toast(copied
              ? appL10n(context).editorSnapshotCopied
              : appL10n(context).editorSnapshotCopyFailed);
        },
      ),
      // The signature-box tool: drag a box, then pick an identity and
      // appearance and cryptographically sign into that rectangle.
      onPlaceSignature: (context, {required pageIndex, required pageRect}) =>
          _digitallySign(tab, placement: (page: pageIndex, rect: pageRect)),
    );
  }

  List<Widget> _buildActions(DocumentTab? tab) {
    final compact = _isCompactWidth(context);
    return [
      // Background OCR progress (when a job is running) - non-blocking, so the
      // user keeps using the PDF while hundreds of pages are recognized.
      ValueListenableBuilder<OcrJobStatus?>(
        valueListenable: _ocr.status,
        builder: (context, status, _) => status == null
            ? const SizedBox.shrink()
            : _OcrStatusChip(status: status, onCancel: _ocr.cancel),
      ),
      if (_showsSelectionCopyAction && tab?.viewer != null)
        ListenableBuilder(
          listenable: tab!.viewer!,
          builder: (context, _) => !tab.viewer!.hasSelection
              ? const SizedBox.shrink()
              : IconButton(
                  icon: const Icon(Icons.copy),
                  tooltip: appL10n(context).editorCopySelectedTextTooltip,
                  onPressed: () async {
                    await tab.viewer!.copySelection();
                    if (!context.mounted) return;
                    _toast(appL10n(context).editorCopiedToClipboard);
                  },
                ),
        ),
      if (compact && _tabs.isNotEmpty) _buildMobileTabsButton(),

      if (compact && !_readOnly && tab?.session != null)
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 8),
          child: FilledButton.icon(
            key: const ValueKey('mobile-app-save'),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            icon: const Icon(Icons.save_alt, size: 18),
            label: Text(appL10n(context).save),
            onPressed: () => unawaited(_save(tab!)),
          ),
        ),
    ];
  }

  Widget _buildAppMenu(DocumentTab? tab) => PopupMenuButton<VoidCallback>(
        key: const ValueKey('dartpdf-app-menu'),
        iconSize: _appMenuIconSize,
        icon: Image.asset(
          'web/icons/Icon-512.png',
          width: _appMenuIconSize,
          height: _appMenuIconSize,
          semanticLabel: 'DartPDF',
        ),
        tooltip: appL10n(context).editorAppMenuTooltip,
        onSelected: (action) => action(),
        itemBuilder: (context) => _appMenuItems(context, tab),
      );

  Widget _buildTabsTitle() {
    if (!_isCompactWidth(context)) return _buildTabStrip();
    final tab = _active;
    Widget title = Text(
      tab?.title.isEmpty ?? true ? appL10n(context).editorUntitled : tab!.title,
      overflow: TextOverflow.ellipsis,
    );
    if (_nativeTabDragging && tab?.session != null) {
      title = _buildNativeTabDragSource(tab!, title);
    }
    return _buildCompactTabDropTarget(title);
  }

  Widget _buildEmptyTabsTitle() {
    if (_isCompactWidth(context)) {
      return _buildCompactTabDropTarget(const Text('DartPDF'));
    }
    // Keep a real drop target in an otherwise empty desktop window. This is
    // the natural destination after New window, and lets the first dragged tab
    // populate it without requiring a placeholder document.
    return _buildTabDropSurface(
      const Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text('DartPDF'),
      ),
    );
  }

  Widget _buildCompactTabDropTarget(Widget child) {
    if (!_nativeTabDragging) return child;
    // Narrow desktop windows use the compact single-title chrome. It cannot
    // expose a precise insertion slot, but remains a valid append target.
    return _buildTabDropSurface(
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: child,
      ),
    );
  }

  Widget _buildTabDropSurface(Widget child) {
    final coordinator = _registeredTabDragCoordinator;
    Widget buildSurface() {
      final targeted = coordinator?.insertionIndexFor(windowHandle) != null;
      final scheme = Theme.of(context).colorScheme;
      return AnimatedContainer(
        key: _tabStripGeometryKey,
        duration: const Duration(milliseconds: 90),
        height: _tabStripHeight,
        width: double.infinity,
        foregroundDecoration: targeted
            ? BoxDecoration(
                color: scheme.primary.withAlpha(0x18),
                border: Border.all(color: scheme.primary, width: 2),
                borderRadius: BorderRadius.circular(8),
              )
            : null,
        child: child,
      );
    }

    if (coordinator == null) return buildSurface();
    return ListenableBuilder(
      listenable: coordinator,
      builder: (context, _) => buildSurface(),
    );
  }

  bool _isCompactWidth(BuildContext context) =>
      MediaQuery.sizeOf(context).width < _mobileTabsBreakpoint;

  /// Wraps the body in a passive [Listener] that feeds the devtools touch-input
  /// log. It is not a gesture recognizer, so it never joins the arena and
  /// cannot affect panning/zoom; the callbacks no-op unless the log is on.
  /// Gated on [kDevToolsEnabled] so a stripped build carries no wrapper.
  Widget _devToolsPointerLog(Widget body) {
    if (!kDevToolsEnabled) return body;
    final tools = AppDevTools.instance;
    return Listener(
      onPointerDown: tools.logPointerEvent,
      onPointerMove: tools.logPointerEvent,
      onPointerUp: tools.logPointerEvent,
      onPointerCancel: tools.logPointerEvent,
      child: body,
    );
  }

  Widget _buildMobileTabsButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: IconButton(
        key: const ValueKey('mobile-tabs-button'),
        tooltip: appL10n(context).editorOpenTabs,
        icon: Badge(
          label: Text(
            '${_tabs.length}',
            key: const ValueKey('mobile-tabs-count'),
          ),
          child: const Icon(Icons.tab_outlined),
        ),
        onPressed: _showTabsSheet,
      ),
    );
  }

  Future<void> _showTabsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          return SafeArea(
            top: false,
            child: SizedBox(
              height: MediaQuery.sizeOf(sheetContext).height * 0.72,
              child: _buildTabsGrid(
                sheetContext,
                setOverlayState: setSheetState,
                keyPrefix: 'mobile',
                headerTopPadding: 0,
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showTabsDialog() async {
    await showPdfDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final viewport = MediaQuery.sizeOf(dialogContext);
          final width = viewport.width > 888 ? 840.0 : viewport.width - 48;
          final height = viewport.height > 688 ? 640.0 : viewport.height - 48;
          return Dialog(
            key: const ValueKey('desktop-tabs-dialog'),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: width,
              height: height,
              child: _buildTabsGrid(
                dialogContext,
                setOverlayState: setDialogState,
                keyPrefix: 'desktop',
                headerTopPadding: 12,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTabsGrid(
    BuildContext overlayContext, {
    required StateSetter setOverlayState,
    required String keyPrefix,
    required double headerTopPadding,
  }) {
    final scheme = Theme.of(overlayContext).colorScheme;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(20, headerTopPadding, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  appL10n(overlayContext).editorTabs,
                  style: Theme.of(overlayContext).textTheme.titleMedium,
                ),
              ),
              IconButton(
                key: ValueKey('$keyPrefix-tabs-open'),
                icon: const Icon(Icons.add),
                tooltip: appL10n(overlayContext).editorOpenPdfNewTab,
                onPressed: () {
                  Navigator.of(overlayContext).pop();
                  unawaited(_pickAndOpen());
                },
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: GridView.builder(
            key: ValueKey('$keyPrefix-tabs-grid'),
            // A tile paints a real PDF thumbnail. Do not build the next row
            // speculatively: with large documents that work competes with a
            // fling even though the thumbnails are still off-screen.
            scrollCacheExtent: const ScrollCacheExtent.pixels(0),
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.78,
            ),
            itemCount: _tabs.length,
            itemBuilder: (context, index) {
              final tab = _tabs[index];
              final selected = index == _activeIndex;
              // Refresh the modal grid after a mutation (or dismiss it once no
              // tabs remain); it does not rebuild off the screen's setState.
              void refreshOverlay() {
                if (!mounted || !overlayContext.mounted) return;
                if (_tabs.isEmpty) {
                  Navigator.of(overlayContext).pop();
                } else {
                  setOverlayState(() {});
                }
              }

              return _MobileTabTile(
                key: ValueKey('$keyPrefix-tab-${tab.hashCode}'),
                tab: tab,
                selected: selected,
                onTap: () {
                  setState(() => _activeIndex = index);
                  Navigator.of(overlayContext).pop();
                },
                onClose: () async {
                  await _closeTabs([tab]);
                  refreshOverlay();
                },
                onContextMenu: (position) {
                  // Re-resolve by identity: the grid can reorder under us.
                  final i = _tabs.indexOf(tab);
                  if (i < 0) return;
                  unawaited(
                    _showTabMenu(i, position, onChanged: refreshOverlay),
                  );
                },
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(
            appL10n(overlayContext).editorTabsOpenCount(_tabs.length),
            style: Theme.of(overlayContext)
                .textTheme
                .labelMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  /// Moves the tab at [oldIndex] to [newIndex] (drag-reorder), keeping the
  /// currently active document active wherever it lands. [newIndex] is already
  /// adjusted for the removed item (the `onReorderItem` convention).
  void _reorderTabs(int oldIndex, int newIndex) {
    setState(() {
      final active = _tabs[_activeIndex.clamp(0, _tabs.length - 1)];
      final moved = _tabs.removeAt(oldIndex);
      _tabs.insert(newIndex, moved);
      _activeIndex = _tabs.indexOf(active);
    });
    unawaited(_persistSession());
  }

  Widget _buildTabStrip() {
    final coordinator = _registeredTabDragCoordinator;
    Widget buildStrip() => SizedBox(
          height: _tabStripHeight,
          child: LayoutBuilder(
            builder: (context, constraints) {
              const buttonWidth = 40.0;
              const controlsWidth = buttonWidth * 2;
              const listPadding =
                  8.0; // 4px each side (see the list's padding).
              final maxTabsWidth = (constraints.maxWidth - controlsWidth)
                  .clamp(0.0, double.infinity)
                  .toDouble();

              // Chrome-style sizing: every tab gets an equal share of the strip,
              // clamped between the min and max tab width. As tabs are added the
              // share shrinks until it hits the floor, after which the list scrolls.
              final natural = _chromeTabWidth(maxTabsWidth - listPadding);
              _lastNaturalTabWidth = natural;
              // While a close streak is held, keep the surviving tabs at the pinned
              // width; otherwise use the natural share (never wider than natural, so
              // a stale hold can't overflow after a resize).
              final tabWidth = _heldTabWidth == null
                  ? natural
                  : math.min(_heldTabWidth!, natural);
              _lastRenderedTabWidth = tabWidth;
              final externalGap = _externalTabDragGap;
              final visualTabCount =
                  _tabs.length + (externalGap == null ? 0 : 1);
              final tabsWidth = _tabs.isEmpty
                  ? 0.0
                  : math.min(
                      tabWidth * visualTabCount + listPadding, maxTabsWidth);
              _lastRenderedTabsWidth = tabsWidth;
              final insertion = coordinator?.insertionIndexFor(windowHandle);
              final scheme = Theme.of(context).colorScheme;
              final rtl = Directionality.of(context) == TextDirection.rtl;
              final gapPadding = externalGap == null ? 0.0 : tabWidth;

              return SizedBox(
                key: _tabStripGeometryKey,
                child: Stack(
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        if (tabsWidth > 0)
                          // A window or AppBar-action resize can make the new
                          // title constraint narrower than the container's
                          // previous animated width. Clamp outside the animation
                          // so even its first frame fits the current Row.
                          ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: maxTabsWidth),
                            child: MouseRegion(
                              onEnter: (_) => _tabStripHovered = true,
                              onExit: (_) {
                                _tabStripHovered = false;
                                _releaseTabWidthHold();
                              },
                              // Grow back smoothly once the hold releases; both the strip
                              // and each tab animate to the same width with a linear curve,
                              // so they stay pixel-consistent throughout.
                              child: AnimatedContainer(
                                duration: _tabResizeDuration,
                                curve: Curves.linear,
                                width: tabsWidth,
                                child: ReorderableListView.builder(
                                  key: const ValueKey('tab-strip'),
                                  scrollController: _tabScrollController,
                                  scrollDirection: Axis.horizontal,
                                  // The whole tab is the drag handle (see _buildTab); the
                                  // stock trailing handles don't fit a horizontal tab strip.
                                  buildDefaultDragHandles: false,
                                  padding: EdgeInsets.only(
                                    left: rtl ? 4 + gapPadding : 4,
                                    right: rtl ? 4 : 4 + gapPadding,
                                  ),
                                  itemCount: _tabs.length,
                                  onReorderItem: _reorderTabs,
                                  itemBuilder: (context, i) =>
                                      _buildTab(i, tabWidth),
                                ),
                              ),
                            ),
                          ),
                        SizedBox(
                          width: buttonWidth,
                          height: _tabStripHeight,
                          child: IconButton(
                            key: const ValueKey('desktop-tab-add-button'),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                                width: buttonWidth),
                            icon: const Icon(Icons.add),
                            tooltip: appL10n(context).editorOpenPdfNewTab,
                            onPressed: _pickAndOpen,
                          ),
                        ),
                        const Spacer(key: ValueKey('desktop-tabs-spacer')),
                        SizedBox(
                          width: buttonWidth,
                          height: _tabStripHeight,
                          child: IconButton(
                            key: const ValueKey('desktop-tabs-button'),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                                width: buttonWidth),
                            icon: const Icon(Icons.grid_view),
                            tooltip: appL10n(context).editorViewAllTabs,
                            onPressed: _showTabsDialog,
                          ),
                        ),
                      ],
                    ),
                    if (insertion != null)
                      PositionedDirectional(
                        start: 0,
                        width: tabsWidth > 0 ? tabsWidth : maxTabsWidth,
                        top: 0,
                        bottom: 0,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            key: const ValueKey('tab-drag-drop-highlight'),
                            decoration: BoxDecoration(
                              color: scheme.primary.withAlpha(0x12),
                              border: Border.all(
                                color: scheme.primary.withAlpha(0xB0),
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    if (insertion != null && tabsWidth > 0)
                      PositionedDirectional(
                        start: (4 +
                                insertion * tabWidth -
                                (_tabScrollController.hasClients
                                    ? _tabScrollController.offset
                                    : 0.0))
                            .clamp(2.0, math.max(2.0, tabsWidth - 2))
                            .toDouble(),
                        top: 4,
                        bottom: 4,
                        child: IgnorePointer(
                          child: Container(
                            key: const ValueKey('tab-drag-insertion-indicator'),
                            width: 3,
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              borderRadius: BorderRadius.circular(2),
                              boxShadow: [
                                BoxShadow(
                                  color: scheme.shadow.withAlpha(0x50),
                                  blurRadius: 3,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        );
    if (coordinator == null) return buildStrip();
    return ListenableBuilder(
      listenable: coordinator,
      builder: (context, _) => buildStrip(),
    );
  }

  /// The equal-share width for one tab given the space [available] to the whole
  /// tab list, clamped to the Chrome-style min/max. Below the min the tabs stop
  /// shrinking and the strip scrolls instead.
  double _chromeTabWidth(double available) {
    final count = _tabs.length;
    if (count == 0) return 0;
    final share = available / count;
    return share.clamp(_tabMinWidth, _tabMaxWidth).toDouble();
  }

  Widget _buildTab(int index, double width) {
    final tab = _tabs[index];
    final selected = index == _activeIndex;
    final scheme = Theme.of(context).colorScheme;
    // Like Chrome, drop the close button on inactive tabs once they get narrow
    // so the label keeps room; the active tab always keeps it.
    final showClose = selected || width >= _tabCloseHideWidth;
    Widget label() {
      final text = Text(
        tab.title.isEmpty ? appL10n(context).editorUntitled : tab.title,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          color:
              selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
        ),
      );
      final session = tab.session;
      if (session == null) return text;
      return ListenableBuilder(
        listenable: session,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (tab.isDirty)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 6),
                child: Icon(Icons.circle, size: 8, color: scheme.primary),
              ),
            Flexible(child: text),
          ],
        ),
      );
    }

    final chrome = AnimatedContainer(
      duration: _tabResizeDuration,
      curve: Curves.linear,
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
      child: Material(
        color: selected
            ? scheme.secondaryContainer
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _activeIndex = index),
          onSecondaryTapUp: (details) =>
              _showTabMenu(index, details.globalPosition),
          child: Padding(
            padding:
                EdgeInsetsDirectional.only(start: 12, end: showClose ? 2 : 12),
            child: Row(
              mainAxisSize: MainAxisSize.max,
              children: [
                Expanded(child: label()),
                if (showClose)
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 30,
                      minHeight: 30,
                    ),
                    tooltip: appL10n(context).editorCloseTab,
                    onPressed: () => _closeTab(index),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    // The process-wide drag owns editable tabs when this window participates
    // in the router. Placeholders keep the local reorder recognizer until their
    // bytes have materialized and can be handed to another window.
    final dragSource = _nativeTabDragging && tab.session != null
        ? _buildNativeTabDragSource(tab, chrome)
        : _TabDragStartListener(index: index, child: chrome);
    final hoverPreview = _TabHoverPreview(
      tab: tab,
      enabled: !selected,
      child: dragSource,
    );
    final coordinator = _registeredTabDragCoordinator;
    if (coordinator == null) {
      return KeyedSubtree(key: ValueKey(tab), child: hoverPreview);
    }
    return ListenableBuilder(
      key: ValueKey(tab),
      listenable: coordinator,
      builder: (context, child) {
        final logicalShift = _tabDragShift(index);
        final direction =
            Directionality.of(context) == TextDirection.rtl ? -1 : 1;
        return AnimatedSlide(
          offset: Offset(logicalShift * direction, 0),
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: child,
        );
      },
      child: hoverPreview,
    );
  }

  Widget _buildNativeTabDragSource(DocumentTab tab, Widget child) {
    final coordinator = _registeredTabDragCoordinator!;
    return Draggable<String>(
      maxSimultaneousDrags: 1,
      data: 'dartpdf-tab',
      dragAnchorStrategy: childDragAnchorStrategy,
      feedback: ListenableBuilder(
        listenable: coordinator,
        builder: (feedbackContext, _) {
          final preview = coordinator.previewFor(tab);
          // Before the first native cursor poll returns the drag has only just
          // started on this strip, so paint the in-strip state by default.
          final overStrip = preview?.isOverTabStrip ?? true;
          final movingToAnotherWindow = overStrip &&
              preview?.targetWindowHandle != null &&
              preview!.targetWindowHandle != windowHandle;
          return _buildTabDragFeedback(
            feedbackContext,
            tab,
            overStrip: overStrip,
            movingToAnotherWindow: movingToAnotherWindow,
            key: ValueKey(overStrip
                ? 'tab-drag-feedback-over-strip'
                : 'tab-drag-feedback-detached'),
          );
        },
      ),
      childWhenDragging: Opacity(opacity: 0, child: child),
      onDragStarted: () {
        if (!containsTab(tab) || tab.session == null) return;
        final token =
            '$windowHandle:${_nextNativeTabDragToken++}:${identityHashCode(tab)}';
        final previous = _nativeTabDragTokens[tab];
        if (previous != null) coordinator.cancel(previous);
        _nativeTabDragTokens[tab] = token;
        coordinator.begin(
          this,
          tab,
          () => DocumentHandoff.fromTab(tab),
          token: token,
        );
        coordinator.update(token);
      },
      onDragUpdate: (_) {
        final token = _nativeTabDragTokens[tab];
        if (token != null) coordinator.update(token);
      },
      onDragEnd: (_) {
        final token = _nativeTabDragTokens.remove(tab);
        if (token == null) return;
        unawaited(
            coordinator.finish(token, userCancelled: false).then((result) {
          if (mounted && result == TabDragResult.failed) {
            _toast(appL10n(context).editorUnableToOpenNewWindow);
          }
        }));
      },
      child: child,
    );
  }

  Widget _buildTabDragFeedback(
    BuildContext feedbackContext,
    DocumentTab tab, {
    required bool overStrip,
    required bool movingToAnotherWindow,
    required Key key,
  }) {
    final scheme = Theme.of(feedbackContext).colorScheme;
    return Material(
      key: key,
      color: overStrip ? scheme.primaryContainer : scheme.tertiaryContainer,
      elevation: 8,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: overStrip ? scheme.primary : scheme.tertiary,
          width: 2,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                overStrip
                    ? (movingToAnotherWindow
                        ? Icons.move_to_inbox_outlined
                        : Icons.reorder)
                    : Icons.open_in_new,
                size: 18,
                color: overStrip
                    ? scheme.onPrimaryContainer
                    : scheme.onTertiaryContainer,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tab.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: overStrip
                            ? scheme.onPrimaryContainer
                            : scheme.onTertiaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      overStrip
                          ? appL10n(feedbackContext).editorTabs
                          : appL10n(feedbackContext).editorMoveToNewWindow,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(feedbackContext)
                          .textTheme
                          .labelSmall
                          ?.copyWith(
                            color: overStrip
                                ? scheme.onPrimaryContainer
                                : scheme.onTertiaryContainer,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OpeningDocument extends StatelessWidget {
  const _OpeningDocument({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        label: appL10n(context).editorOpeningDocumentSemantic,
        liveRegion: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              title.isEmpty
                  ? appL10n(context).editorOpeningPdf
                  : appL10n(context).editorOpeningTitle(title),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// The read-only first paint of a progressive open: a [PdfReader] over the
/// sparse document the ranged loader assembled, with a slim top progress bar
/// tracking the background full read. When that read lands the host swaps this
/// for a full [PdfEditorView] (see [EditorScreen._swapPreviewToDocument]), so
/// Save / Digitally sign appear only once the whole file is in hand.
class _ProgressivePreview extends StatelessWidget {
  const _ProgressivePreview({
    super.key,
    required this.tab,
    required this.preferences,
    required this.onAction,
    required this.pageRasterCachePolicy,
    required this.pageRasterWarmPolicy,
    required this.tileRasterBackend,
  });

  final DocumentTab tab;
  final PdfEditingPreferences preferences;
  final PdfActionHandler onAction;
  final PdfPageRasterCachePolicy pageRasterCachePolicy;
  final PdfPageRasterWarmPolicy pageRasterWarmPolicy;
  final PdfTileRasterBackend tileRasterBackend;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: PdfReader(
            bytes: tab.previewBytes!,
            documentId: tab.documentId,
            controller: tab.viewer,
            preferences: preferences,
            onAction: onAction,
            pageRasterCachePolicy: pageRasterCachePolicy,
            pageRasterWarmPolicy: pageRasterWarmPolicy,
            tileRasterBackend: tileRasterBackend,
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: ValueListenableBuilder<double>(
            valueListenable: tab.progress!,
            builder: (context, value, _) {
              // Hide the bar once the full read is essentially done - the swap
              // to the edit session is imminent.
              if (value >= 0.999) return const SizedBox.shrink();
              return Semantics(
                label: appL10n(context).editorLoadingFullDocument,
                value: '${(value * 100).round()}%',
                liveRegion: true,
                child: LinearProgressIndicator(
                  value: value == 0 ? null : value,
                  minHeight: 3,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// The actions offered by a tab's right-click context menu.
enum _TabMenuAction {
  openFolder,
  moveToNewWindow,
  close,
  closeOthers,
  closeRight,
  closeAll,
}

/// Shows a non-interactive thumbnail card for an inactive desktop tab after a
/// short hover. This uses a plain [OverlayEntry], not an OverlayPortal: the tab
/// is a reorderable-list item, and portals must not be reactivated from that
/// subtree while the list is laying out or moving its drag proxy.
class _TabHoverPreview extends StatefulWidget {
  const _TabHoverPreview({
    required this.tab,
    required this.enabled,
    required this.child,
  });

  final DocumentTab tab;
  final bool enabled;
  final Widget child;

  @override
  State<_TabHoverPreview> createState() => _TabHoverPreviewState();
}

class _TabHoverPreviewState extends State<_TabHoverPreview> {
  final _imageCache = _TabPreviewImageCache();
  Timer? _timer;
  OverlayEntry? _entry;
  bool _hovering = false;

  @override
  void didUpdateWidget(_TabHoverPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.tab, widget.tab)) {
      _imageCache.clear();
    }
    if (!widget.enabled || !identical(oldWidget.tab, widget.tab)) {
      _hide();
    } else if (widget.enabled && !oldWidget.enabled && _hovering) {
      _schedule();
    }
  }

  void _schedule() {
    _timer?.cancel();
    if (!widget.enabled) return;
    _timer = Timer(_tabHoverPreviewDelay, _show);
  }

  void _show() {
    _timer = null;
    if (!mounted || !widget.enabled || !_hovering || _entry != null) return;
    final target = context.findRenderObject();
    final overlay = Overlay.of(context, rootOverlay: true);
    final overlayBox = overlay.context.findRenderObject();
    if (target is! RenderBox || overlayBox is! RenderBox) return;

    final origin = target.localToGlobal(Offset.zero, ancestor: overlayBox);
    final overlaySize = overlayBox.size;
    final width = math
        .min(
          _tabHoverPreviewWidth,
          math.max(0.0, overlaySize.width - 16),
        )
        .toDouble();
    final height = math
        .min(
          _tabHoverPreviewHeight,
          math.max(0.0, overlaySize.height - 16),
        )
        .toDouble();
    if (width <= 0 || height <= 0) return;

    final maxLeft = math.max(8.0, overlaySize.width - width - 8);
    final left = (origin.dx + (target.size.width - width) / 2)
        .clamp(8.0, maxLeft)
        .toDouble();
    final below = origin.dy + target.size.height + 4;
    final top = below + height <= overlaySize.height - 8
        ? below
        : math.max(8.0, origin.dy - height - 4);

    _entry = OverlayEntry(
      builder: (context) => Positioned(
        left: left,
        top: top,
        width: width,
        height: height,
        child: IgnorePointer(
          child: _DesktopTabPreviewCard(
            tab: widget.tab,
            imageCache: _imageCache,
          ),
        ),
      ),
    );
    overlay.insert(_entry!);
  }

  void _hide() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }

  @override
  void dispose() {
    _hide();
    _imageCache.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        _hovering = true;
        _schedule();
      },
      onExit: (_) {
        _hovering = false;
        _hide();
      },
      child: Listener(
        // A click may activate/close/reorder the tab or open its context menu.
        // Dismiss before any of those operations mutate the strip.
        onPointerDown: (_) => _hide(),
        child: widget.child,
      ),
    );
  }
}

class _DesktopTabPreviewCard extends StatelessWidget {
  const _DesktopTabPreviewCard({required this.tab, required this.imageCache});

  final DocumentTab tab;
  final _TabPreviewImageCache imageCache;

  @override
  Widget build(BuildContext context) {
    final listeners = <Listenable>[
      if (tab.session != null) tab.session!,
      if (tab.viewer != null) tab.viewer!,
    ];
    if (listeners.isEmpty) return _buildCard(context);
    return ListenableBuilder(
      listenable: Listenable.merge(listeners),
      builder: (context, _) => _buildCard(context),
    );
  }

  Widget _buildCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pageIndex = _tabPreviewPage(tab);
    return Material(
      key: const ValueKey('tab-hover-preview'),
      elevation: 10,
      shadowColor: scheme.shadow.withValues(alpha: 0.28),
      color: scheme.surfaceContainerHigh,
      surfaceTintColor: scheme.surfaceTint,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _TabPreview(
                tab: tab,
                pageIndex: pageIndex,
                imageCache: imageCache,
                previewKey: const ValueKey('tab-hover-preview-thumbnail'),
                imageKey: const ValueKey('tab-hover-preview-image'),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (tab.isDirty)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(Icons.circle, size: 8, color: scheme.primary),
                  ),
                Expanded(
                  child: Text(
                    tab.title.isEmpty
                        ? appL10n(context).editorUntitled
                        : tab.title,
                    key: const ValueKey('tab-hover-preview-title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                if (tab.session != null)
                  Text(
                    appL10n(context).editorPageNumber(pageIndex + 1),
                    key: const ValueKey('tab-hover-preview-page'),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

int _tabPreviewPage(DocumentTab tab) {
  final session = tab.session;
  if (session == null || session.document.pageCount <= 0) return 0;
  return (tab.viewer?.currentPage ?? 0)
      .clamp(0, session.document.pageCount - 1)
      .toInt();
}

/// Starts a tab drag immediately for mouse pointers (the desktop expectation -
/// a mouse drag never means scrolling the strip) but only after a long press
/// for touch and stylus, so finger drags still scroll the tab strip. Plain
/// taps are unaffected: both recognizers claim the pointer only once it moves
/// past the slop.
class _TabDragStartListener extends ReorderableDragStartListener {
  const _TabDragStartListener({
    required super.index,
    required super.child,
  });

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        // A right-click opens the tab context menu - never a drag-reorder.
        if (event.buttons == kSecondaryButton) return;
        SliverReorderableList.maybeOf(context)?.startItemDragReorder(
          index: index,
          event: event,
          recognizer: (event.kind == PointerDeviceKind.mouse
              ? ImmediateMultiDragGestureRecognizer(debugOwner: this)
              : DelayedMultiDragGestureRecognizer(debugOwner: this))
            ..gestureSettings = MediaQuery.maybeGestureSettingsOf(context),
        );
      },
      child: child,
    );
  }
}

/// The translucent "drop a PDF here" scrim shown while a file is dragged over
/// the window.
/// How a drop should be handled when a document is already open.
enum _DropAction { open, insert }

class _DropOverlay extends StatelessWidget {
  const _DropOverlay({this.canInsert = false});

  /// Whether the drop can be inserted into the open document (vs. only
  /// opened in a new tab) - drives the hint text.
  final bool canInsert;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: Container(
        color: scheme.primary.withValues(alpha: 0.12),
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.primary, width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.file_download_outlined,
                  size: 40, color: scheme.primary),
              const SizedBox(height: 8),
              Text(canInsert
                  ? appL10n(context).editorDropToOpenOrInsert
                  : appL10n(context).editorDropToOpen),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact app-bar indicator for a running background OCR job: a progress
/// ring, a short label, and a cancel button.
class _OcrStatusChip extends StatelessWidget {
  const _OcrStatusChip({required this.status, required this.onCancel});

  final OcrJobStatus status;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: appL10n(context).editorOcrTooltip(status.title),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          key: const ValueKey('ocr-status-chip'),
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: status.fraction,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  ocrStatusLabel(appL10n(context), status),
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSecondaryContainer,
                  ),
                ),
                IconButton(
                  key: const ValueKey('ocr-status-cancel'),
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  icon: const Icon(Icons.close),
                  tooltip: appL10n(context).editorCancelOcr,
                  onPressed: onCancel,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileTabTile extends StatelessWidget {
  const _MobileTabTile({
    super.key,
    required this.tab,
    required this.selected,
    required this.onTap,
    required this.onClose,
    this.onContextMenu,
  });

  final DocumentTab tab;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onClose;

  /// Opens the tab's context menu at the given global position (right-click on
  /// desktop, long-press on touch). Null disables the affordance.
  final void Function(Offset globalPosition)? onContextMenu;

  @override
  Widget build(BuildContext context) {
    final session = tab.session;
    if (session == null) return _build(context);
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey('mobile-tab-tile'),
      color: selected ? scheme.secondaryContainer : scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onSecondaryTapUp: onContextMenu == null
            ? null
            : (details) => onContextMenu!(details.globalPosition),
        onLongPress: onContextMenu == null
            ? null
            : () {
                // InkWell's long-press carries no position, so anchor the menu
                // at the tile's centre (touch parity for the right-click menu).
                final box = context.findRenderObject() as RenderBox?;
                if (box == null || !box.hasSize) return;
                onContextMenu!(box.localToGlobal(box.size.center(Offset.zero)));
              },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                child: _TabPreview(
                  tab: tab,
                  pageIndex: 0,
                  previewKey: const ValueKey('mobile-tab-preview'),
                  imageKey: const ValueKey('mobile-tab-preview-image'),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 4, 6),
              child: Row(
                children: [
                  if (tab.isDirty)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(Icons.circle, size: 8, color: scheme.primary),
                    ),
                  Expanded(
                    child: Text(
                      tab.title.isEmpty
                          ? appL10n(context).editorUntitled
                          : tab.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.normal,
                        color: selected
                            ? scheme.onSecondaryContainer
                            : scheme.onSurface,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: appL10n(context).editorCloseTab,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints.tightFor(width: 32, height: 32),
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabPreview extends StatelessWidget {
  const _TabPreview({
    required this.tab,
    required this.pageIndex,
    required this.previewKey,
    required this.imageKey,
    this.imageCache,
  });

  final DocumentTab tab;
  final int pageIndex;
  final Key previewKey;
  final Key imageKey;
  final _TabPreviewImageCache? imageCache;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final session = tab.session;
    if (session != null) {
      return _TabDocumentPreview(
        controller: session,
        pageIndex: pageIndex,
        stamp: session.pageRenderStamp(pageIndex),
        pageColor: session.preferences.pageColor,
        showAnnotations: session.preferences.showAnnotations,
        rotation: tab.viewer?.viewRotation,
        previewKey: previewKey,
        imageKey: imageKey,
        imageCache: imageCache,
      );
    }
    final l10n = appL10n(context);
    final (icon, label) = tab.isLoading
        ? (Icons.hourglass_empty, l10n.editorPreviewOpening)
        : tab.error != null
            ? (Icons.error_outline, l10n.editorPreviewCouldNotOpen)
            : tab.isComparison
                ? (Icons.compare_arrows, l10n.editorPreviewComparison)
                : (Icons.picture_as_pdf_outlined, l10n.editorPreviewPdf);
    return DecoratedBox(
      key: previewKey,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (tab.isLoading)
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            else
              Icon(icon, size: 36, color: scheme.onSurfaceVariant),
            const SizedBox(height: 8),
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabPreviewImageCache {
  Object? _key;
  ui.Image? _image;
  bool _disposed = false;

  ui.Image? claim(Object key) {
    if (_disposed || _key != key) return null;
    return _image?.clone();
  }

  void store(Object key, ui.Image image) {
    if (_disposed) {
      image.dispose();
      return;
    }
    _image?.dispose();
    _key = key;
    _image = image;
  }

  void clear() {
    _image?.dispose();
    _image = null;
    _key = null;
  }

  void dispose() {
    _disposed = true;
    clear();
  }
}

class _TabDocumentPreview extends StatefulWidget {
  const _TabDocumentPreview({
    required this.controller,
    required this.pageIndex,
    required this.stamp,
    required this.pageColor,
    required this.showAnnotations,
    required this.rotation,
    required this.previewKey,
    required this.imageKey,
    this.imageCache,
  });

  final PdfEditingController controller;
  final int pageIndex;
  final int stamp;
  final Color pageColor;
  final bool showAnnotations;
  final int? rotation;
  final Key previewKey;
  final Key imageKey;
  final _TabPreviewImageCache? imageCache;

  @override
  State<_TabDocumentPreview> createState() => _TabDocumentPreviewState();
}

class _TabDocumentPreviewState extends State<_TabDocumentPreview> {
  ui.Image? _image;
  Object? _pendingKey;
  Object? _imageKey;
  bool _deferredFrameScheduled = false;

  Object get _key => (
        widget.controller,
        widget.pageIndex,
        widget.stamp,
        widget.pageColor.toARGB32(),
        widget.showAnnotations,
        widget.rotation,
      );

  @override
  void didUpdateWidget(_TabDocumentPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller) ||
        oldWidget.pageIndex != widget.pageIndex ||
        oldWidget.stamp != widget.stamp ||
        oldWidget.pageColor != widget.pageColor ||
        oldWidget.showAnnotations != widget.showAnnotations ||
        oldWidget.rotation != widget.rotation) {
      _image?.dispose();
      _image = null;
      _imageKey = null;
      _pendingKey = null;
    }
  }

  @override
  void dispose() {
    _pendingKey = null;
    _image?.dispose();
    _image = null;
    super.dispose();
  }

  Future<void> _render(Object key, double pixelRatio) async {
    _pendingKey = key;
    try {
      final page = widget.controller.pageAt(widget.pageIndex);
      final size = PdfPageRenderer.pageSize(page, rotation: widget.rotation);
      if (size.width <= 0 || size.height <= 0) return;
      final ratio = (150 * pixelRatio / size.width).clamp(0.08, 0.5);
      final image = await PdfPageRenderer.renderImage(
        page,
        pixelRatio: ratio,
        pageColor: widget.pageColor,
        annotations: widget.showAnnotations,
        rotation: widget.rotation,
      );
      if (!mounted || _pendingKey != key) {
        image.dispose();
        return;
      }
      final cache = widget.imageCache;
      final ui.Image shown;
      if (cache == null) {
        shown = image;
      } else {
        cache.store(key, image);
        final cached = cache.claim(key);
        if (cached == null) return;
        shown = cached;
      }
      setState(() {
        _image?.dispose();
        _image = shown;
        _imageKey = key;
        _pendingKey = null;
      });
    } catch (_) {
      if (mounted && _pendingKey == key) _pendingKey = null;
    }
  }

  void _retryAfterDeferredFrame() {
    if (_deferredFrameScheduled) return;
    _deferredFrameScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _deferredFrameScheduled = false;
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final key = _key;
    if (_imageKey != key) {
      final cached = widget.imageCache?.claim(key);
      if (cached != null) {
        _image?.dispose();
        _image = cached;
        _imageKey = key;
        _pendingKey = null;
      }
    }
    if (_imageKey != key && _pendingKey != key) {
      // Flutter recommends deferring image decoding during fast scrolling.
      // PDF thumbnail generation is substantially heavier than decoding, so
      // obey the same signal and retry once the scroll begins to settle.
      if (Scrollable.recommendDeferredLoadingForContext(context)) {
        _retryAfterDeferredFrame();
      } else {
        unawaited(_render(key, MediaQuery.devicePixelRatioOf(context)));
      }
    }
    final page = widget.controller.pageAt(widget.pageIndex);
    final pageSize = PdfPageRenderer.pageSize(
      page,
      rotation: widget.rotation,
    );
    final aspectRatio = pageSize.width > 0 && pageSize.height > 0
        ? pageSize.width / pageSize.height
        : 1.0;
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: DecoratedBox(
          key: widget.previewKey,
          decoration: BoxDecoration(
            color: widget.pageColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: scheme.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: scheme.shadow.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: _image == null
                ? const SizedBox.expand()
                : RawImage(
                    key: widget.imageKey,
                    image: _image,
                    fit: BoxFit.contain,
                  ),
          ),
        ),
      ),
    );
  }
}
