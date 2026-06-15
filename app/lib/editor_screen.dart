import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:url_launcher/url_launcher.dart';

import 'document_tab.dart';
import 'file_io.dart';
import 'incoming_file.dart';
import 'ocr.dart';
import 'recents.dart';
import 'settings_screen.dart';
import 'web_launch.dart';
import 'welcome_screen.dart';

/// Height of the AppBar's browser-style tab strip.
const double _tabStripHeight = 42;

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
  });

  final PdfEditingPreferences prefs;

  /// Desktop launch arguments — a `.pdf` path here opens at startup.
  final List<String> launchArgs;

  /// An in-memory document opened in a tab at startup, regardless of
  /// platform. Used by screenshot/integration harnesses (and handy in
  /// tests) to land directly in the editor without a file picker.
  final ({Uint8List bytes, String title})? initialDocument;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen>
    with WidgetsBindingObserver {
  PdfEditingPreferences get _prefs => widget.prefs;

  final _recents = RecentsStore();
  final _incoming = IncomingFileService();
  final _ocr = OnDeviceOcr();
  StreamSubscription<IncomingFile>? _incomingSub;

  /// True while a file is being dragged over the window (desktop/web).
  bool _dragging = false;

  final List<DocumentTab> _tabs = [];
  int _activeIndex = 0;

  DocumentTab? get _active =>
      _tabs.isEmpty ? null : _tabs[_activeIndex.clamp(0, _tabs.length - 1)];

  /// Whole-app read-only toggle: swaps [PdfEditorView] for [PdfReader].
  bool _readOnly = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _recents.load();
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
  }

  /// Opens a `.pdf` passed on the command line — how Windows and Linux deliver
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
    super.dispose();
  }

  /// Blocks app exit while any document has unsaved changes, offering to
  /// discard. On platforms that don't ask (mobile/web) this is a no-op.
  @override
  Future<AppExitResponse> didRequestAppExit() async {
    final dirty = _tabs.where((t) => t.isDirty).length;
    if (dirty == 0) return AppExitResponse.exit;
    final proceed = await _confirmDiscard(
      dirty == 1
          ? 'A document has unsaved changes.'
          : '$dirty documents have unsaved changes.',
    );
    return proceed ? AppExitResponse.exit : AppExitResponse.cancel;
  }

  // --- opening -------------------------------------------------------------

  /// Opens [bytes] in a brand-new tab and makes it active, recording a recent.
  void _openBytes(Uint8List bytes, String title, {String? originPath}) {
    _addTab(DocumentTab.document(
      title: title,
      bytes: bytes,
      preferences: _prefs,
      originPath: originPath,
    ));
    _recents.add(title: title, path: originPath);
  }

  void _openError(String title, String error) {
    _addTab(DocumentTab.error(title: title, error: error));
  }

  void _addTab(DocumentTab tab) {
    setState(() {
      _tabs.add(tab);
      _activeIndex = _tabs.length - 1;
    });
  }

  DocumentTab _openLoading(String title, {String? originPath}) {
    final tab = DocumentTab.loading(title: title, originPath: originPath);
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
    return true;
  }

  Future<void> _openLoadedBytes(
    Future<Uint8List> bytesFuture, {
    required String title,
    String? originPath,
    String? errorTitle,
  }) async {
    final loading = _openLoading(title, originPath: originPath);
    try {
      final bytes = await bytesFuture;
      // Let the loading tab paint before constructing the edit session, which
      // synchronously opens the PDF and can be noticeable for large files.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final opened = _replaceLoadingTab(
        loading,
        DocumentTab.document(
          title: title,
          bytes: bytes,
          preferences: _prefs,
          originPath: originPath,
        ),
      );
      if (opened) _recents.add(title: title, path: originPath);
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

  Future<void> _pickAndOpen() async {
    try {
      final file = await pickPdfFile();
      if (file == null) return;
      await _openLoadedBytes(
        file.readAsBytes(),
        title: file.name,
        originPath: originPathForPickedFile(file),
      );
    } catch (e) {
      _openError('Open failed', 'Could not open the selected file\n$e');
    }
  }

  /// Opens a file the OS handed us (association, share, launch arg).
  Future<void> _openIncoming(IncomingFile file) async {
    await _openLoadedBytes(
      file.bytes == null
          ? readPdfAtPath(file.path!)
          : Future<Uint8List>.value(file.bytes!),
      title: file.name,
      originPath: file.path,
    );
  }

  /// Opens PDFs dropped onto the window (desktop and web). Non-PDFs are
  /// ignored; each readable PDF opens in its own tab.
  Future<void> _onFilesDropped(List<DropItem> items) async {
    for (final item in items) {
      if (!item.name.toLowerCase().endsWith('.pdf')) continue;
      // desktop_drop exposes a real path on desktop; on web it's a blob ref
      // we don't treat as a writable origin.
      final path = (!kIsWeb && item.path.isNotEmpty) ? item.path : null;
      await _openLoadedBytes(
        item.readAsBytes(),
        title: item.name,
        originPath: path,
      );
    }
  }

  Future<void> _openRecent(RecentFile entry) async {
    final path = entry.path;
    if (path == null) {
      await _pickAndOpen();
      return;
    }
    final loading = _openLoading(entry.title, originPath: path);
    try {
      final bytes = await readPdfAtPath(path);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final opened = _replaceLoadingTab(
        loading,
        DocumentTab.document(
          title: entry.title,
          bytes: bytes,
          preferences: _prefs,
          originPath: path,
        ),
      );
      if (opened) _recents.add(title: entry.title, path: path);
    } catch (e) {
      await _recents.remove(entry.id);
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
    // Snapshot the title now — the source tab may be closed before OCR ends.
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
  }

  /// Opens the right-click context menu for the tab at [index] at [position]
  /// (global coordinates), offering Close / Close others / Close to the right /
  /// Close all. Entries that would close nothing are disabled.
  Future<void> _showTabMenu(int index, Offset position) async {
    final tab = _tabs[index];
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<_TabMenuAction>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: [
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
    // Re-resolve the tab's current position — nothing reorders while the modal
    // menu is up, but indexing by identity is robust regardless.
    final i = _tabs.indexOf(tab);
    if (i < 0) return;
    switch (selected) {
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
    final inPlace =
        !saveAs && tab.originPath != null && supportsInPlaceSave;
    var result = inPlace
        ? await saveBytesToPath(bytes, tab.originPath!)
        : await saveBytesAs(context, bytes, tab.title);
    if (!mounted) return;
    if (inPlace && !result.succeeded) {
      // The origin couldn't be written (moved, read-only) — offer save-as.
      result = await saveBytesAs(context, bytes, tab.title);
      if (!mounted) return;
    }
    if (result.succeeded) {
      setState(() {
        tab.markSaved();
        if (result.path != null) tab.originPath = result.path;
      });
      if (result.path != null) {
        _recents.add(title: tab.title, path: result.path);
      }
    }
    if (result.message != null) _toast(result.message!);
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
        break; // unreachable — handled by the viewer
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

  // --- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final tab = _active;
    return Scaffold(
      appBar: AppBar(
        title: _buildTitle(tab),
        bottom: _tabs.isEmpty
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(_tabStripHeight),
                child: _buildTabStrip(),
              ),
        actions: _buildActions(tab),
      ),
      body: DropTarget(
        onDragEntered: (_) => setState(() => _dragging = true),
        onDragExited: (_) => setState(() => _dragging = false),
        onDragDone: (detail) {
          setState(() => _dragging = false);
          _onFilesDropped(detail.files);
        },
        child: Stack(
          children: [
            Positioned.fill(child: _buildBody(tab)),
            if (_dragging) const Positioned.fill(child: _DropOverlay()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(DocumentTab? tab) {
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
      onPickPdfToInsert: pickPdfBytes,
      onExportPages: (bytes) =>
          unawaited(saveBytesAs(context, bytes, tab.title)),
      onAction: _onAction,
      annotationMenuBuilder: _annotationMenuActions,
      formImagePicker: (context, field) => pickImageBytes(),
      imagePicker: (context) => pickImageBytes(),
    );
  }

  Widget _buildTitle(DocumentTab? tab) {
    if (tab == null || tab.title.isEmpty) return const Text('DartPDF');
    final session = tab.session;
    if (session == null) {
      return Text(tab.title, overflow: TextOverflow.ellipsis);
    }
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) => Text(
        '${tab.isDirty ? '• ' : ''}${tab.title}',
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  List<Widget> _buildActions(DocumentTab? tab) {
    return [
      // Background OCR progress (when a job is running) — non-blocking, so the
      // user keeps using the PDF while hundreds of pages are recognized.
      ValueListenableBuilder<OcrJobStatus?>(
        valueListenable: _ocr.status,
        builder: (context, status, _) => status == null
            ? const SizedBox.shrink()
            : _OcrStatusChip(status: status, onCancel: _ocr.cancel),
      ),
      if (tab?.viewer != null)
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
      if (tab?.session != null && !_readOnly)
        ListenableBuilder(
          listenable: tab!.session!,
          builder: (context, _) => IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.save_outlined),
            tooltip: 'Save (⌘S)',
            onPressed: tab.isDirty ? () => _save(tab) : null,
          ),
        ),
      IconButton(
        visualDensity: VisualDensity.compact,
        icon: Icon(_readOnly ? Icons.edit_off : Icons.edit),
        tooltip: _readOnly ? 'Read-only — tap to edit' : 'Editing — tap for read-only',
        onPressed: () => setState(() => _readOnly = !_readOnly),
      ),
      IconButton(
        visualDensity: VisualDensity.compact,
        icon: Icon(switch (_prefs.themeMode) {
          ThemeMode.system => Icons.brightness_auto,
          ThemeMode.light => Icons.light_mode,
          ThemeMode.dark => Icons.dark_mode,
        }),
        tooltip: 'Theme',
        onPressed: () => _prefs.themeMode = switch (_prefs.themeMode) {
          ThemeMode.system => ThemeMode.light,
          ThemeMode.light => ThemeMode.dark,
          ThemeMode.dark => ThemeMode.system,
        },
      ),
      IconButton(
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.folder_open),
        tooltip: 'Open PDF in a new tab',
        onPressed: _pickAndOpen,
      ),
      PopupMenuButton<VoidCallback>(
        icon: const Icon(Icons.more_vert),
        tooltip: 'More',
        onSelected: (action) => action(),
        itemBuilder: (context) => [
          if (tab?.session != null)
            PopupMenuItem(
              value: () => _save(tab!, saveAs: true),
              child: const ListTile(
                leading: Icon(Icons.save_as_outlined),
                title: Text('Save as…'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          if (tab?.session != null)
            PopupMenuItem(
              value: _compareWith,
              child: const ListTile(
                leading: Icon(Icons.compare_arrows),
                title: Text('Compare with…'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          if (tab?.session != null && OnDeviceOcr.isSupported)
            PopupMenuItem(
              key: const ValueKey('menu-ocr'),
              value: () => unawaited(_runOcr()),
              child: const ListTile(
                leading: Icon(Icons.document_scanner_outlined),
                title: Text('Add OCR text layer…'),
                subtitle: Text('On-device · selectable text over scans'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          PopupMenuItem(
            value: () =>
                showAppSettings(context, prefs: _prefs, recents: _recents),
            child: const ListTile(
              leading: Icon(Icons.settings_outlined),
              title: Text('Settings'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    ];
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
  }

  Widget _buildTabStrip() {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: SizedBox(
        height: _tabStripHeight,
        child: Row(
          children: [
            Expanded(
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
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.add),
              tooltip: 'Open PDF in a new tab',
              onPressed: _pickAndOpen,
            ),
          ],
        ),
      ),
    );
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
          color: selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
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
    return _TabDragStartListener(
      key: ValueKey(tab),
      index: index,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
        child: Material(
          color: selected ? scheme.secondaryContainer : scheme.surfaceContainerHighest,
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
                    constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                    tooltip: 'Close tab',
                    onPressed: () => _closeTab(index),
                  ),
                ],
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
enum _TabMenuAction { close, closeOthers, closeRight, closeAll }

/// Starts a tab drag immediately for mouse pointers (the desktop expectation —
/// a mouse drag never means scrolling the strip) but only after a long press
/// for touch and stylus, so finger drags still scroll the tab strip. Plain
/// taps are unaffected: both recognizers claim the pointer only once it moves
/// past the slop.
class _TabDragStartListener extends ReorderableDragStartListener {
  const _TabDragStartListener({
    super.key,
    required super.index,
    required super.child,
  });

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        // A right-click opens the tab context menu — never a drag-reorder.
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
class _DropOverlay extends StatelessWidget {
  const _DropOverlay();

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
              const Text('Drop PDF to open'),
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
