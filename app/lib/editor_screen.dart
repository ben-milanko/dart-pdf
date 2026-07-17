import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_info.dart';
import 'digital_signature.dart';
import 'document_tab.dart';
import 'file_io.dart';
import 'image_clipboard.dart';
import 'image_export.dart';
import 'incoming_file.dart';
import 'new_document.dart';
import 'ocr.dart';
import 'pdf_cache.dart';
import 'print_progress_dialog.dart';
import 'printing.dart';
import 'recents.dart';
import 'session_store.dart';
import 'settings_screen.dart';
import 'update.dart';
import 'web_launch.dart';
import 'welcome_screen.dart';

/// Height of the AppBar's browser-style tab strip.
const double _tabStripHeight = 42;
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
    this.autoCheckUpdates = false,
    this.printDocument,
    this.digitalSignatureOptionsProvider,
    this.saveDocumentAs,
    this.saveDocumentToPath,
    this.imageClipboardWriter,
    this.imageClipboardReader,
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

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen>
    with WidgetsBindingObserver {
  PdfEditingPreferences get _prefs => widget.prefs;

  final _recents = RecentsStore();
  final _session = SessionStore();
  final _incoming = IncomingFileService();
  final _ocr = OnDeviceOcr();
  StreamSubscription<IncomingFile>? _incomingSub;

  /// Gates session persistence until the previous session has been read back,
  /// so an early tab open (e.g. an OS file-open) doesn't clobber the stored set
  /// before [_restoreSession] has had a chance to re-open it.
  bool _sessionLoaded = false;

  /// The update checker, owned here unless the host injected one.
  late final UpdateService _updates =
      widget.updateService ?? UpdateService(currentVersion: AppInfo.version);
  bool get _ownsUpdates => widget.updateService == null;

  /// True once the "update available" banner has been shown this session, so a
  /// later check (or rebuild) doesn't stack a second copy.
  bool _updateBannerShown = false;

  /// True while a file is being dragged over the window (desktop/web).
  bool _dragging = false;

  final List<DocumentTab> _tabs = [];
  int _activeIndex = 0;

  DocumentTab? get _active =>
      _tabs.isEmpty ? null : _tabs[_activeIndex.clamp(0, _tabs.length - 1)];

  /// Whole-app read-only toggle: swaps [PdfEditorView] for [PdfReader].
  bool _readOnly = false;
  bool _digitallySigning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _recents.load().then((_) {
      if (mounted) _pruneRecentCache();
    });
    // Files the OS opens in the app: the launch file, then any later opens.
    _incoming.start();
    _incomingSub = _incoming.files.listen(_openIncoming);
    _incoming.initialFile().then((file) {
      if (file != null && mounted) _openIncoming(file);
    });
    _openLaunchArgs();
    // PWA file-handler opens (installed web app); no-op off the web.
    startWebLaunchQueue(_openIncoming);
    final doc = widget.initialDocument;
    if (doc != null) _openBytes(doc.bytes, doc.title);
    // Re-open the documents that were open when the app last closed, unless the
    // app was launched to open a specific file (that explicit target wins).
    unawaited(_restoreSession());
    if (widget.autoCheckUpdates && UpdateService.supported) {
      _updates.addListener(_onUpdateStatus);
      unawaited(_startupUpdateCheck());
    }
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
      content: Text('DartPDF ${release.version} is available.'),
      leading: const Icon(Icons.system_update_alt),
      actions: [
        TextButton(
          onPressed: () {
            messenger.hideCurrentMaterialBanner();
            unawaited(_updates.dismiss());
          },
          child: const Text('Later'),
        ),
        FilledButton(
          key: const ValueKey('update-banner-download'),
          onPressed: () {
            messenger.hideCurrentMaterialBanner();
            final url = _updates.downloadUrl;
            if (url != null) unawaited(_openExternal(Uri.parse(url)));
          },
          child: const Text('Download'),
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
    WidgetsBinding.instance.removeObserver(this);
    _incomingSub?.cancel();
    _incoming.dispose();
    _ocr.dispose();
    for (final tab in _tabs) {
      tab.dispose();
    }
    _recents.dispose();
    _updates.removeListener(_onUpdateStatus);
    if (_ownsUpdates) _updates.dispose();
    super.dispose();
  }

  /// Blocks app exit while any document has unsaved changes, offering to
  /// discard. On platforms that don't ask (mobile/web) this is a no-op.
  @override
  Future<ui.AppExitResponse> didRequestAppExit() async {
    final dirty = _tabs.where((t) => t.isDirty).length;
    if (dirty == 0) return ui.AppExitResponse.exit;
    final proceed = await _confirmDiscard(
      dirty == 1
          ? 'A document has unsaved changes.'
          : '$dirty documents have unsaved changes.',
    );
    return proceed ? ui.AppExitResponse.exit : ui.AppExitResponse.cancel;
  }

  // --- session restore -----------------------------------------------------

  /// True when the app was launched to open a specific document (a screenshot/
  /// test harness document, or a `.pdf` passed on the command line). In that
  /// case the explicit target wins and we don't also restore the last session.
  bool get _hasExplicitLaunchTarget =>
      widget.initialDocument != null ||
      (!kIsWeb &&
          widget.launchArgs.any((a) => a.toLowerCase().endsWith('.pdf')));

  /// Re-opens the file-backed documents that were open when the app last closed.
  /// Runs once at startup, then enables session persistence so this run's open
  /// set is captured for next time. Documents whose file has since moved or been
  /// deleted are dropped silently rather than surfacing an error tab.
  Future<void> _restoreSession() async {
    final documents = await _session.load();
    if (mounted && !_hasExplicitLaunchTarget) {
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
    }
    _sessionLoaded = true;
    unawaited(_persistSession());
  }

  Future<void> _reopenSessionDocument(SessionDocument doc) async {
    final readPath = doc.readPath;
    if (readPath == null) return;
    // Desktop restores by its writable origin; a mobile pick has none and
    // restores from its private snapshot instead.
    final originPath = doc.path.isNotEmpty ? doc.path : null;
    final loading = _openLoading(
      doc.title,
      originPath: originPath,
      originBookmark: doc.bookmark,
      cachePath: doc.cachePath,
    );
    try {
      final bytes = await readPdfAtPath(readPath, bookmark: doc.bookmark);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final opened = _replaceLoadingTab(
        loading,
        DocumentTab.document(
          title: doc.title,
          bytes: bytes,
          preferences: _prefs,
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
    } catch (_) {
      // The file is gone (moved/deleted): drop the placeholder quietly.
      if (mounted) await _closeTabs([loading]);
    }
  }

  /// Persists the current open set (file-backed tabs, in order) so the next
  /// launch can restore it. A no-op until the previous session has been read
  /// back, so early opens can't clobber the stored set before [_restoreSession].
  Future<void> _persistSession() async {
    if (!_sessionLoaded) return;
    final documents = <SessionDocument>[];
    final seen = <String>{};
    for (final tab in _tabs) {
      final path = tab.originPath;
      final cachePath = tab.cachePath;
      // Track by the writable origin (desktop) or the private snapshot
      // (mobile); tabs with neither (web, or a derived/comparison tab) can't
      // be read back and are skipped.
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
    _addTab(DocumentTab.error(title: title, error: error));
  }

  void _addTab(DocumentTab tab) {
    setState(() {
      _tabs.add(tab);
      _activeIndex = _tabs.length - 1;
    });
    unawaited(_persistSession());
  }

  DocumentTab _openLoading(String title,
      {String? originPath, String? originBookmark, String? cachePath}) {
    final tab = DocumentTab.loading(
        title: title,
        originPath: originPath,
        originBookmark: originBookmark,
        cachePath: cachePath);
    _addTab(tab);
    return tab;
  }

  bool _replaceLoadingTab(DocumentTab loading, DocumentTab replacement) {
    final index = _tabs.indexOf(loading);
    if (index == -1) {
      replacement.dispose();
      return false;
    }
    setState(() {
      _tabs[index] = replacement;
      _activeIndex = index;
    });
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
  }) async {
    final loading = _openLoading(
      title,
      originPath: originPath,
      originBookmark: originBookmark,
    );
    try {
      final bytes = await bytesFuture;
      // Let the loading tab paint before constructing the edit session, which
      // synchronously opens the PDF and can be noticeable for large files.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final tab = DocumentTab.document(
        title: title,
        bytes: bytes,
        preferences: _prefs,
        originPath: originPath,
        originBookmark: originBookmark,
      );
      final opened = _replaceLoadingTab(loading, tab);
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
          error: 'Could not open ${errorTitle ?? title}\n$e',
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

  Future<void> _pickAndOpen() async {
    try {
      final files = await pickPdfFiles();
      if (files.isEmpty) return;
      for (final file in files) {
        if (!mounted) return;
        final path = originPathForPickedFile(file);
        final bookmark = await securityBookmarkForPath(path);
        await _openLoadedBytes(
          file.readAsBytes(),
          title: file.name,
          originPath: path,
          originBookmark: bookmark,
        );
      }
    } catch (e) {
      _openError('Open failed', 'Could not open the selected file\n$e');
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

  /// Opens a file the OS handed us (association, share, launch arg).
  ///
  /// If a tab already holds this exact path, focus it instead of opening a
  /// duplicate. The same launch file can arrive twice - once via the
  /// command-line launch args and once via the native `getInitialFile`
  /// channel (Windows delivers both) - and re-opening an already-open
  /// document from the OS should surface the existing tab, not stack copies.
  Future<void> _openIncoming(IncomingFile file) async {
    final path = file.path;
    if (path != null && path.isNotEmpty) {
      final existing = _tabs.indexWhere((t) => t.originPath == path);
      if (existing != -1) {
        setState(() => _activeIndex = existing);
        return;
      }
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
  /// ignored. With an editable document already open, the drop offers a
  /// choice - open each PDF in its own tab, or insert their pages into the
  /// current document; with nothing open (or in read-only mode) each PDF
  /// just opens in its own tab.
  Future<void> _onFilesDropped(List<DropItem> items) async {
    final pdfs = [
      for (final item in items)
        if (item.name.toLowerCase().endsWith('.pdf')) item,
    ];
    if (pdfs.isEmpty) return;

    final tab = _active;
    final session = tab?.session;
    if (session != null && !_readOnly) {
      final action = await _promptDropAction(pdfs.length, tab!.title);
      if (action == null || !mounted) return; // cancelled / disposed
      if (action == _DropAction.insert) {
        await _insertDropped(pdfs, session, tab.title);
        return;
      }
    }
    await _openDropped(pdfs);
  }

  /// Opens each dropped [pdfs] item in its own tab.
  Future<void> _openDropped(List<DropItem> pdfs) async {
    for (final item in pdfs) {
      // desktop_drop exposes a real path on desktop; on web it's a blob ref
      // we don't treat as a writable origin.
      final path = (!kIsWeb && item.path.isNotEmpty) ? item.path : null;
      final bookmark = await securityBookmarkForPath(path);
      await _openLoadedBytes(
        item.readAsBytes(),
        title: item.name,
        originPath: path,
        originBookmark: bookmark,
      );
    }
  }

  /// Inserts the pages of each dropped PDF, appended in drop order, into the
  /// active document's edit session. Unreadable files are skipped and
  /// reported; the result is one undoable step per inserted file.
  Future<void> _insertDropped(
      List<DropItem> pdfs, PdfEditingController session, String title) async {
    var inserted = 0;
    final failed = <String>[];
    for (final item in pdfs) {
      try {
        final bytes = await item.readAsBytes();
        session.insertPagesFromBytes(bytes);
        inserted++;
      } catch (_) {
        failed.add(item.name);
      }
    }
    if (!mounted) return;
    if (inserted == 0) {
      _toast(
          'Could not insert the dropped ${pdfs.length == 1 ? 'PDF' : 'PDFs'}');
    } else if (failed.isEmpty) {
      _toast(inserted == 1
          ? 'Inserted pages into $title'
          : 'Inserted $inserted PDFs into $title');
    } else {
      _toast('Inserted $inserted; could not read ${failed.join(', ')}');
    }
  }

  /// Asks whether dropped PDFs (with a document already open) should open in
  /// new tabs or have their pages inserted into the current document. Returns
  /// null when cancelled.
  Future<_DropAction?> _promptDropAction(int count, String title) {
    final noun = count == 1 ? 'this PDF' : 'these $count PDFs';
    final pages = count == 1 ? 'its pages' : 'their pages';
    return showDialog<_DropAction>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('drop-action-dialog'),
        title: Text('Add dropped ${count == 1 ? 'PDF' : 'PDFs'}'),
        content: Text('Open $noun in a new tab, or insert $pages into '
            '"$title"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const ValueKey('drop-action-open'),
            onPressed: () => Navigator.of(context).pop(_DropAction.open),
            child: Text(count == 1 ? 'Open in new tab' : 'Open in new tabs'),
          ),
          FilledButton(
            key: const ValueKey('drop-action-insert'),
            onPressed: () => Navigator.of(context).pop(_DropAction.insert),
            child: const Text('Insert pages'),
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
          error: 'Could not open ${entry.title}\n$e',
        ),
      );
      _toast('Could not reopen ${entry.title}');
    }
  }

  List<RecentFile> _recentMenuEntries() {
    final openIds = {
      for (final tab in _tabs)
        if (tab.originPath != null && tab.originPath!.isNotEmpty)
          tab.originPath!
        else if (tab.cachePath != null && tab.cachePath!.isNotEmpty)
          tab.cachePath!
        else
          tab.title,
    };
    return [
      for (final entry in _recents.items)
        if (!openIds.contains(entry.id)) entry,
    ].take(_maxRecentMenuItems).toList();
  }

  void _openMostRecent() {
    final recents = _recentMenuEntries();
    if (recents.isEmpty) {
      _toast('No recent files');
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
    try {
      final other = await pickPdfBytes();
      if (other == null) return;
      setState(() {
        _tabs.add(DocumentTab.comparison(
          title: 'Compare: ${tab!.title}',
          before: current,
          after: other,
        ));
        _activeIndex = _tabs.length - 1;
      });
    } catch (e) {
      _openError('Compare failed', 'Could not open the second file\n$e');
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
      _toast('Open a document before running OCR');
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
        if (mounted) _openBytes(result, '$title (OCR)');
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
        dirty == 1
            ? 'A document has unsaved changes.'
            : '$dirty documents have unsaved changes.',
      );
      if (!ok || !mounted) return;
    }
    final active = _active;
    setState(() {
      for (final tab in targets) {
        _tabs.remove(tab);
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

  /// Opens the right-click context menu for the tab at [index] at [position]
  /// (global coordinates), offering Close / Close others / Close to the right /
  /// Close all. Entries that would close nothing are disabled.
  Future<void> _showTabMenu(int index, Offset position) async {
    final tab = _tabs[index];
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<_TabMenuAction>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: [
        if (supportsOpenContainingFolder && tab.originPath != null) ...[
          PopupMenuItem(
            key: const ValueKey('tab-menu-open-folder'),
            value: _TabMenuAction.openFolder,
            child: Text(openContainingFolderLabel),
          ),
          const PopupMenuDivider(),
        ],
        const PopupMenuItem(
          key: ValueKey('tab-menu-close'),
          value: _TabMenuAction.close,
          child: Text('Close'),
        ),
        PopupMenuItem(
          key: const ValueKey('tab-menu-close-others'),
          value: _TabMenuAction.closeOthers,
          enabled: _tabs.length > 1,
          child: const Text('Close others'),
        ),
        PopupMenuItem(
          key: const ValueKey('tab-menu-close-right'),
          value: _TabMenuAction.closeRight,
          enabled: index < _tabs.length - 1,
          child: const Text('Close tabs to the right'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          key: ValueKey('tab-menu-close-all'),
          value: _TabMenuAction.closeAll,
          child: Text('Close all'),
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
        final opened = await openContainingFolder(tab.originPath);
        if (!opened && mounted) _toast('Could not open containing folder');
      case _TabMenuAction.close:
        await _closeTabs([tab]);
      case _TabMenuAction.closeOthers:
        await _closeTabs(_tabs.where((t) => t != tab).toList());
      case _TabMenuAction.closeRight:
        await _closeTabs(_tabs.sublist(i + 1));
      case _TabMenuAction.closeAll:
        await _closeTabs(List.of(_tabs));
    }
  }

  Future<bool> _confirmDiscard(String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
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
    final saveAsDocument = widget.saveDocumentAs ?? saveBytesAs;
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

  Future<void> _digitallySign(DocumentTab tab) async {
    final session = tab.session;
    if (session == null || _digitallySigning) return;
    setState(() => _digitallySigning = true);
    try {
      final options = await (widget.digitalSignatureOptionsProvider ??
          showDigitalSigningDialog)(context);
      if (!mounted || options == null || !_tabs.contains(tab)) return;
      await session.addDigitalSignature(
        options.identity,
        fieldName: options.fieldName,
        reason: options.reason,
        location: options.location,
        contactInfo: options.contactInfo,
      );
      if (!mounted || !_tabs.contains(tab)) return;
      // Signing is a document revision, then follows the normal save path so
      // an existing origin is overwritten and an untitled document gets a
      // Save As destination. Cancelling Save As leaves the signed tab dirty.
      await _save(tab);
    } on FormatException catch (error) {
      if (mounted) _toast('Could not digitally sign: ${error.message}');
    } catch (error) {
      if (mounted) _toast('Could not digitally sign: $error');
    } finally {
      if (mounted) setState(() => _digitallySigning = false);
    }
  }

  /// Hands the active document to the OS print dialog (the `printing` plugin -
  /// native dialog on desktop/mobile, browser print on the web). The current
  /// revision is printed, so unsaved edits are included. A failed or
  /// unavailable backend surfaces as a toast rather than throwing.
  Future<void> _print(DocumentTab tab) async {
    final bytes = tab.session?.bytes;
    if (bytes == null) return;
    try {
      final injected = widget.printDocument;
      if (injected != null) {
        await injected(bytes: bytes, title: tab.title);
      } else {
        await _printWithProgress(bytes, tab.title);
      }
    } catch (_) {
      if (mounted) _toast('Could not print ${tab.title}');
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
            unawaited(showDialog<void>(
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
      final result =
          await saveImageBytesAs(context, bytes, name, options.format.mimeType);
      if (result.message != null) _toast(result.message!);
    } catch (_) {
      if (mounted) _toast('Could not export ${tab.title}');
    }
  }

  Future<void> _exportSelectedContentImage(
    BuildContext exportContext,
    DocumentTab tab,
    PdfSelectedContentImage image,
  ) async {
    final name = selectedContentImageFileName(tab.title, image.pageIndex + 1);
    final result = await saveImageBytesAs(
        exportContext, image.pngBytes, name, 'image/png');
    if (mounted && result.message != null) _toast(result.message!);
  }

  Future<void> _exportCustomStamps(
    BuildContext exportContext,
    List<PdfCustomStamp> stamps,
  ) async {
    final result = await exportCustomStampsAs(exportContext, stamps);
    if (mounted && result.message != null) _toast(result.message!);
  }

  Future<List<PdfCustomStamp>?> _importCustomStamps(BuildContext _) async {
    try {
      return await importCustomStamps();
    } catch (e) {
      if (mounted) _toast('Could not import stamps: $e');
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
          _toast('Invalid link: $uri');
        }
      case PdfNamedAction(:final name):
        _toast('Named action: $name');
      case PdfJavaScriptAction():
        _toast('This document tried to run JavaScript (ignored)');
      case PdfUnknownAction(:final type):
        _toast('Unsupported action: $type');
      case PdfGoToAction():
        break; // unreachable - handled by the viewer
    }
  }

  Future<void> _openExternal(Uri url) async {
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) _toast('Could not open $url');
    }
  }

  List<PdfAnnotationMenuItem> _annotationMenuActions(
      BuildContext context, PdfAnnotationMenuRequest request) {
    final contents = request.primary?.contents;
    if (contents == null || contents.isEmpty) return const [];
    return [
      PdfAnnotationMenuItem(
        label: 'Copy text',
        icon: Icons.copy_outlined,
        onSelected: (request) {
          Clipboard.setData(ClipboardData(text: contents));
          _toast('Annotation text copied');
        },
      ),
    ];
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: pdfFloatingToastMargin(context),
        duration: const Duration(seconds: 2),
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
          tooltip: 'Open Recent',
          onSelected: (action) {
            action();
            if (Navigator.of(menuContext).canPop()) {
              Navigator.of(menuContext).pop();
            }
          },
          itemBuilder: (_) => [
            if (recents.isEmpty)
              PopupMenuItem<VoidCallback>(
                height: _appMenuItemHeight(),
                enabled: false,
                child: _appMenuTile(
                  icon: Icons.history_toggle_off,
                  title: 'No recent files',
                ),
              )
            else ...[
              for (final entry in recents)
                PopupMenuItem<VoidCallback>(
                  height: _appMenuItemHeight(twoLine: entry.path != null),
                  value: () => unawaited(_openRecent(entry)),
                  child: _appMenuTile(
                    icon: Icons.picture_as_pdf_outlined,
                    title: entry.title.isEmpty ? 'Untitled' : entry.title,
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
                  title: 'Clear recent files',
                ),
              ),
            ],
          ],
          child: _appMenuTile(
            icon: Icons.history,
            title: 'Open Recent',
            trailing: trailing,
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
            title: 'New document…',
            shortcut: _menuShortcut('N'),
          ),
        ),
        PopupMenuItem(
          key: const ValueKey('menu-open'),
          height: _appMenuItemHeight(),
          value: () => unawaited(_pickAndOpen()),
          child: _appMenuTile(
            icon: Icons.folder_open,
            title: 'Open a PDF…',
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
              title: 'Save as…',
              shortcut: _menuShortcut('S', shift: true),
            ),
          ),
          PopupMenuItem(
            key: const ValueKey('menu-digital-signature'),
            height: _appMenuItemHeight(),
            enabled: !_digitallySigning,
            value: () => unawaited(_digitallySign(tab!)),
            child: _appMenuTile(
              icon: Icons.verified_user_outlined,
              title:
                  _digitallySigning ? 'Digitally signing…' : 'Digitally sign…',
            ),
          ),
          PopupMenuItem(
            key: const ValueKey('menu-print'),
            height: _appMenuItemHeight(),
            value: () => unawaited(_print(tab!)),
            child: _appMenuTile(
              icon: Icons.print_outlined,
              title: 'Print…',
              shortcut: _menuShortcut('P'),
            ),
          ),
          PopupMenuItem(
            key: const ValueKey('menu-export-image'),
            height: _appMenuItemHeight(),
            value: () => unawaited(_exportImage(tab!)),
            child: _appMenuTile(
              icon: Icons.image_outlined,
              title: 'Export page as image…',
            ),
          ),
          PopupMenuItem(
            height: _appMenuItemHeight(),
            value: _compareWith,
            child: _appMenuTile(
              icon: Icons.compare_arrows,
              title: 'Compare with…',
            ),
          ),
          PopupMenuItem(
            height: _appMenuItemHeight(),
            value: () => setState(() => _readOnly = !_readOnly),
            child: _appMenuTile(
              icon: _readOnly ? Icons.edit : Icons.edit_off,
              title: _readOnly ? 'Switch to edit mode' : 'Switch to read-only',
            ),
          ),
          if (OnDeviceOcr.isSupported)
            PopupMenuItem(
              key: const ValueKey('menu-ocr'),
              height: _appMenuItemHeight(),
              value: () => unawaited(_runOcr()),
              child: _appMenuTile(
                icon: Icons.document_scanner_outlined,
                title: 'OCR…',
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
          ),
          child: _appMenuTile(
            icon: Icons.settings_outlined,
            title: 'Settings',
          ),
        ),
      ];

  // --- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final tab = _active;
    return Scaffold(
      appBar: AppBar(
        leading: _buildAppMenu(tab),
        leadingWidth: _appMenuLeadingWidth,
        centerTitle: false,
        title: _tabs.isEmpty ? const Text('DartPDF') : _buildTabsTitle(),
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
          const SingleActivator(LogicalKeyboardKey.keyO,
              meta: true, shift: true): _openMostRecent,
          const SingleActivator(LogicalKeyboardKey.keyO,
              control: true, shift: true): _openMostRecent,
        },
        child: DropTarget(
          onDragEntered: (_) => setState(() => _dragging = true),
          onDragExited: (_) => setState(() => _dragging = false),
          onDragDone: (detail) {
            setState(() => _dragging = false);
            _onFilesDropped(detail.files);
          },
          child: Stack(
            children: [
              Positioned.fill(child: _buildBody(tab)),
              if (_dragging)
                Positioned.fill(
                  child: _DropOverlay(
                    canInsert: tab?.session != null && !_readOnly,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(DocumentTab? tab) {
    final compact = _isCompactWidth(context);
    if (tab == null) {
      return WelcomeScreen(
        recents: _recents,
        onOpen: _pickAndOpen,
        onOpenRecent: _openRecent,
      );
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
      );
    }
    return PdfEditorView(
      key: ValueKey(tab),
      documentId: tab.documentId,
      controller: tab.session,
      viewerController: tab.viewer,
      onSave: (_) => unawaited(_save(tab)),
      onSaveAs: (_) => unawaited(_save(tab, saveAs: true)),
      showSaveButton: !compact,
      // A brand-new untitled document has no on-disk origin yet, so keep
      // Save (button + Ctrl/⌘+S) live even before the first edit - the first
      // save writes the file via the Save As flow.
      alwaysAllowSave: tab.isUnsaved,
      onPickPdfToInsert: pickPdfBytes,
      onExportPages: (bytes) =>
          unawaited(saveBytesAs(context, bytes, tab.title)),
      onAction: _onAction,
      annotationMenuBuilder: _annotationMenuActions,
      formImagePicker: (context, field) => pickImageBytes(),
      imagePicker: (context) => pickImageBytes(),
      systemImagePasteProvider: (context) =>
          (widget.imageClipboardReader ?? readImageFromClipboard)(),
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
              ? 'Snapshot copied to clipboard'
              : 'Could not copy snapshot to clipboard');
        },
      ),
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
                  tooltip: 'Copy selected text (⌘C)',
                  onPressed: () async {
                    await tab.viewer!.copySelection();
                    if (!context.mounted) return;
                    _toast('Copied to clipboard');
                  },
                ),
        ),
      if (compact && _tabs.isNotEmpty) _buildMobileTabsButton(),

      if (compact && !_readOnly && tab?.session != null)
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: FilledButton.icon(
            key: const ValueKey('mobile-app-save'),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            icon: const Icon(Icons.save_alt, size: 18),
            label: const Text('Save'),
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
        tooltip: 'DartPDF menu',
        onSelected: (action) => action(),
        itemBuilder: (context) => _appMenuItems(context, tab),
      );

  Widget _buildTabsTitle() {
    if (!_isCompactWidth(context)) return _buildTabStrip();
    final tab = _active;
    return Text(
      tab?.title.isEmpty ?? true ? 'Untitled' : tab!.title,
      overflow: TextOverflow.ellipsis,
    );
  }

  bool _isCompactWidth(BuildContext context) =>
      MediaQuery.sizeOf(context).width < _mobileTabsBreakpoint;

  Widget _buildMobileTabsButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: IconButton(
        key: const ValueKey('mobile-tabs-button'),
        tooltip: 'Open tabs',
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
    await showDialog<void>(
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
                  'Tabs',
                  style: Theme.of(overlayContext).textTheme.titleMedium,
                ),
              ),
              IconButton(
                key: ValueKey('$keyPrefix-tabs-open'),
                icon: const Icon(Icons.add),
                tooltip: 'Open PDF in a new tab',
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
                  if (!mounted || !overlayContext.mounted) return;
                  if (_tabs.isEmpty) {
                    Navigator.of(overlayContext).pop();
                  } else {
                    setOverlayState(() {});
                  }
                },
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(
            '${_tabs.length} open',
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
    return SizedBox(
      height: _tabStripHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const buttonWidth = 40.0;
          const controlsWidth = buttonWidth * 2;
          final maxTabsWidth = (constraints.maxWidth - controlsWidth)
              .clamp(0.0, double.infinity)
              .toDouble();
          final desiredTabsWidth = _estimatedTabStripWidth(context);
          final tabsWidth =
              desiredTabsWidth < maxTabsWidth ? desiredTabsWidth : maxTabsWidth;
          return Row(
            mainAxisSize: MainAxisSize.max,
            children: [
              if (tabsWidth > 0)
                SizedBox(
                  width: tabsWidth,
                  child: ReorderableListView.builder(
                    key: const ValueKey('tab-strip'),
                    scrollDirection: Axis.horizontal,
                    // The whole tab is the drag handle (see _buildTab); the stock
                    // trailing handles don't fit a horizontal tab strip.
                    buildDefaultDragHandles: false,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    itemCount: _tabs.length,
                    onReorderItem: _reorderTabs,
                    itemBuilder: (context, i) => _buildTab(i),
                  ),
                ),
              SizedBox(
                width: buttonWidth,
                height: _tabStripHeight,
                child: IconButton(
                  key: const ValueKey('desktop-tab-add-button'),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints.tightFor(width: buttonWidth),
                  icon: const Icon(Icons.add),
                  tooltip: 'Open PDF in a new tab',
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
                  constraints:
                      const BoxConstraints.tightFor(width: buttonWidth),
                  icon: const Icon(Icons.grid_view),
                  tooltip: 'View all tabs',
                  onPressed: _showTabsDialog,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  double _estimatedTabStripWidth(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
    final direction = Directionality.of(context);
    var width = 8.0; // Horizontal list padding.
    for (final tab in _tabs) {
      final painter = TextPainter(
        text: TextSpan(
          text: tab.title.isEmpty ? 'Untitled' : tab.title,
          style: style,
        ),
        maxLines: 1,
        textDirection: direction,
      )..layout(maxWidth: 160);
      final dirtyWidth = tab.isDirty ? 14.0 : 0.0;
      width += 4 +
          12 +
          (painter.width + dirtyWidth).clamp(40.0, 160.0).toDouble() +
          30;
    }
    return width;
  }

  Widget _buildTab(int index) {
    final tab = _tabs[index];
    final selected = index == _activeIndex;
    final scheme = Theme.of(context).colorScheme;
    Widget label() {
      final text = Text(
        tab.title.isEmpty ? 'Untitled' : tab.title,
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
                padding: const EdgeInsets.only(right: 6),
                child: Icon(Icons.circle, size: 8, color: scheme.primary),
              ),
            Flexible(child: text),
          ],
        ),
      );
    }

    // Dragging anywhere on the tab reorders it; the tap/close gestures still
    // win when the pointer doesn't travel (gesture arena resolves drag vs tap).
    return _TabHoverPreview(
      key: ValueKey(tab),
      tab: tab,
      enabled: !selected,
      child: _TabDragStartListener(
        index: index,
        child: Padding(
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
                padding: const EdgeInsets.only(left: 12, right: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 160),
                      child: label(),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 30,
                        minHeight: 30,
                      ),
                      tooltip: 'Close tab',
                      onPressed: () => _closeTab(index),
                    ),
                  ],
                ),
              ),
            ),
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
        label: 'Opening document',
        liveRegion: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              title.isEmpty ? 'Opening PDF…' : 'Opening $title…',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// The actions offered by a tab's right-click context menu.
enum _TabMenuAction { openFolder, close, closeOthers, closeRight, closeAll }

/// Shows a non-interactive thumbnail card for an inactive desktop tab after a
/// short hover. This uses a plain [OverlayEntry], not an OverlayPortal: the tab
/// is a reorderable-list item, and portals must not be reactivated from that
/// subtree while the list is laying out or moving its drag proxy.
class _TabHoverPreview extends StatefulWidget {
  const _TabHoverPreview({
    super.key,
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
    final width = math.min(
      _tabHoverPreviewWidth,
      math.max(0.0, overlaySize.width - 16),
    ).toDouble();
    final height = math.min(
      _tabHoverPreviewHeight,
      math.max(0.0, overlaySize.height - 16),
    ).toDouble();
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
                    tab.title.isEmpty ? 'Untitled' : tab.title,
                    key: const ValueKey('tab-hover-preview-title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                if (tab.session != null)
                  Text(
                    'Page ${pageIndex + 1}',
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
                  ? 'Drop PDF to open or insert'
                  : 'Drop PDF to open'),
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
      message: 'OCR · ${status.title}',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          key: const ValueKey('ocr-status-chip'),
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.only(left: 10),
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
                  status.label,
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
                  tooltip: 'Cancel OCR',
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
  });

  final DocumentTab tab;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onClose;

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
                      tab.title.isEmpty ? 'Untitled' : tab.title,
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
                    tooltip: 'Close tab',
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
    final (icon, label) = tab.isLoading
        ? (Icons.hourglass_empty, 'Opening')
        : tab.error != null
            ? (Icons.error_outline, 'Could not open')
            : tab.isComparison
                ? (Icons.compare_arrows, 'Comparison')
                : (Icons.picture_as_pdf_outlined, 'PDF');
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
      unawaited(_render(key, MediaQuery.devicePixelRatioOf(context)));
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
