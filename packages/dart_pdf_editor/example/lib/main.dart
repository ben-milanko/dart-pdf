import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart' show PdfPageTextCache;
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_ocr_vlm/pdf_ocr_vlm.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'demo_brand_assets.dart';
import 'demo_document.dart';
import 'error_log.dart';
import 'feedback.dart';
import 'persistent_cache.dart';
import 'platform_fonts.dart';
import 'recent_files.dart';

/// The project's source repository, opened from the AppBar links menu.
final _githubUrl = Uri.parse('https://github.com/ben-milanko/dart-pdf');

/// The published Flutter package the example is built on.
final _pubDevUrl = Uri.parse('https://pub.dev/packages/dart_pdf_editor');

/// One filter, every platform: desktop and web match on the extension,
/// Android on the MIME type, iOS/macOS on the uniform type identifier -
/// a type group missing the field a platform filters by throws there.
const _pdfTypeGroup = XTypeGroup(
  label: 'PDF documents',
  extensions: ['pdf'],
  mimeTypes: ['application/pdf'],
  uniformTypeIdentifiers: ['com.adobe.pdf'],
);

/// Images the form tool's push-button fill accepts.
const _imageTypeGroup = XTypeGroup(
  label: 'Images',
  extensions: ['png', 'jpg', 'jpeg'],
  mimeTypes: ['image/png', 'image/jpeg'],
  uniformTypeIdentifiers: ['public.png', 'public.jpeg'],
);

/// The form tool's image picker: tapped push-button fields (signature
/// and logo slots in templates) fill with the chosen PNG or JPEG.
Future<Uint8List?> _pickFormImage(BuildContext context, PdfFormField field) =>
    openFile(acceptedTypeGroups: const [_imageTypeGroup])
        .then((file) => file?.readAsBytes());

/// The image tool's picker: inserts the chosen PNG or JPEG as a stamp
/// annotation the user can move, resize, and rotate.
Future<Uint8List?> _pickImage(BuildContext context) =>
    openFile(acceptedTypeGroups: const [_imageTypeGroup])
        .then((file) => file?.readAsBytes());

/// Fonts the "Load font…" entry accepts.
const _fontTypeGroup = XTypeGroup(
  label: 'Fonts',
  extensions: ['ttf', 'otf'],
  mimeTypes: ['font/ttf', 'font/otf'],
  uniformTypeIdentifiers: ['public.truetype-ttf-font', 'public.opentype-font'],
);

/// The font menu's "Load font…" picker: embeds the chosen TrueType or
/// OpenType file so new text can use any font.
Future<Uint8List?> _pickFont(BuildContext context) =>
    openFile(acceptedTypeGroups: const [_fontTypeGroup])
        .then((file) => file?.readAsBytes());

@visibleForTesting
String pdfSavePathWithExtension(String path) {
  final trimmed = path.trimRight();
  if (trimmed.isEmpty) return 'document.pdf';
  final slash = trimmed.lastIndexOf('/');
  final backslash = trimmed.lastIndexOf('\\');
  final separator = slash > backslash ? slash : backslash;
  final basename = trimmed.substring(separator + 1);
  if (basename.toLowerCase().endsWith('.pdf')) return trimmed;
  return '$trimmed.pdf';
}

void main() {
  // Diagnostics: turn on the in-app performance trace (interpret times,
  // render-hold/scheduler transitions, prerender warms, and frame JANK,
  // streamed to the browser console) without a rebuild by opening the demo
  // with `?perf=1`. Off otherwise - it's verbose and adds per-line print
  // overhead. `Uri.base` carries the page URL on web (and is harmless on
  // native, where there's no query string), so no `package:web` import.
  if (Uri.base.queryParameters['perf'] == '1') {
    PdfPerfLog.enabled = true;
  }
  // Capture uncaught framework, platform, and async errors into the in-app
  // log so a user can attach them to feedback (see AppLog / the feedback
  // dialog). install() also returns the zone handler for the async path.
  final onZoneError = AppLog.instance.install();
  AppLog.instance.info('App started (version $kAppVersion)');
  runZonedGuarded(() => runApp(const ViewerApp()), onZoneError);
}

class ViewerApp extends StatefulWidget {
  const ViewerApp({super.key, this.cacheStore});

  /// The persistent backend the on-disk caches and the recent-files list
  /// share. Defaults to the platform store (filesystem / IndexedDB); tests
  /// inject an in-memory one.
  final PdfCacheStore? cacheStore;

  @override
  State<ViewerApp> createState() => _ViewerAppState();
}

class _ViewerAppState extends State<ViewerApp> {
  /// UI preferences saved on this device - tool styles, which panels
  /// are open, and the theme mode. Owned here so the MaterialApp can
  /// follow the persisted light/dark choice; the screen below shares
  /// the same instance with every editing session.
  final _prefs = PdfEditingPreferences();

  @override
  void initState() {
    super.initState();
    // Offer the host's installed fonts in the editor's font menu by default.
    // Fire-and-forget: the registry is read when a font menu opens, and an
    // empty result (web, or a locked-down platform) just leaves the base-14,
    // bundled and "Load font…" choices.
    unawaited(_loadPlatformFonts());
  }

  Future<void> _loadPlatformFonts() async {
    try {
      pdfPlatformFonts = await loadPlatformFonts();
    } catch (e, s) {
      // Font discovery is best-effort; the menu degrades to its other choices.
      AppLog.instance
          .warning('Platform font discovery failed', error: e, stackTrace: s);
    }
  }

  @override
  void dispose() {
    _prefs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _prefs,
      builder: (context, _) => MaterialApp(
        title: 'dart-pdf viewer',
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
        darkTheme: ThemeData(
          colorSchemeSeed: Colors.indigo,
          brightness: Brightness.dark,
          useMaterial3: true,
        ),
        themeMode: _prefs.themeMode,
        home: ViewerScreen(prefs: _prefs, cacheStore: widget.cacheStore),
      ),
    );
  }
}

class ViewerScreen extends StatefulWidget {
  const ViewerScreen({super.key, required this.prefs, this.cacheStore});

  final PdfEditingPreferences prefs;

  /// Optional override for the persistent cache backend (see [ViewerApp]).
  final PdfCacheStore? cacheStore;

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  PdfEditingPreferences get _prefs => widget.prefs;

  /// App-wide on-disk caches sharing one persistent backend (filesystem on
  /// native, IndexedDB on web - see persistent_cache.dart). The raster
  /// cache makes a reopened document paint soft page content immediately
  /// instead of blank paper; the text cache lets search reuse a prior
  /// session's extraction instead of re-walking every page. Separate
  /// namespaces keep their byte budgets independent.
  late final PdfCacheStore _cacheStore =
      widget.cacheStore ?? createPersistentCacheStore();
  late final PdfRasterCache _rasterCache = PdfRasterCache(
    PdfDiskCache(_cacheStore, namespace: 'previews'),
  );
  late final PdfPageTextCache _textCache = PdfPageTextCache(
    PdfDiskCache(_cacheStore, namespace: 'text'),
  );

  /// The "Open recent" list shown in the app menu, persisted on the shared
  /// cache backend so a picked file reopens across sessions on every
  /// platform.
  late final RecentFilesStore _recents = RecentFilesStore(_cacheStore);

  /// One entry per open document. Each tab owns its own edit session and
  /// viewer controller, so switching tabs preserves each document's
  /// edits, undo history, and any demo-specific state.
  final List<_DocumentTab> _tabs = [];
  int _activeIndex = 0;

  _DocumentTab? get _active =>
      _tabs.isEmpty ? null : _tabs[_activeIndex.clamp(0, _tabs.length - 1)];

  /// Demo of the two drop-in widgets: the toggle swaps the full
  /// [PdfEditorView] for the view-only [PdfReader]. App-wide.
  bool _readOnly = false;

  /// Demo of [PdfViewer.pageLayout]: the toggle flips the viewer between the
  /// default vertical continuous layout and horizontal continuous
  /// (left-to-right, book-like). App-wide.
  bool _horizontalLayout = false;

  PdfPageLayout get _pageLayout => _horizontalLayout
      ? const PdfPageLayout.horizontalContinuous()
      : const PdfPageLayout.verticalContinuous();

  final PdfPerformanceController _performance = PdfPerformanceController();
  int _workerConfigEpoch = 0;

  String get _workerPoolTooltip {
    final mode = _performance.mode;
    if (mode.isAuto) return 'Performance: Auto';
    final count = mode.workerCount!;
    return count == 1
        ? 'Performance: single worker'
        : 'Performance: $count workers';
  }

  /// OCR connection settings, supplied through the credentials dialog and
  /// remembered for the app's lifetime (the API key is deliberately kept in
  /// memory only - the example never writes a secret to disk). Defaults to a
  /// local vLLM/dots.ocr server; see the pdf_ocr_vlm README to run one.
  String _ocrEndpoint = 'http://localhost:8000/v1/chat/completions';
  String _ocrModel = 'model';
  String? _ocrApiKey;

  /// GoTo, the standard named page actions, and real web links (the
  /// page's https pub.dev link) never get here - the viewer follows them
  /// itself. Custom-scheme URIs are dispatched as app commands - the
  /// conventional way a PDF drives its host app - and anything else just
  /// gets described in a snackbar.
  void _onAction(PdfAction action, PdfAnnotation annotation) {
    final tab = _active;
    if (action is PdfUriAction) {
      final uri = Uri.tryParse(action.uri);
      if (uri?.scheme == 'app') {
        switch (uri!.host) {
          case 'counter':
            if (tab != null) setState(() => tab.counter++);
            return;
          case 'message':
            _toast(uri.queryParameters['text'] ?? 'No message');
            return;
        }
      }
    }
    _toast(switch (action) {
      PdfUriAction(:final uri) => 'Link: $uri',
      PdfJavaScriptAction(:final script) =>
        'JavaScript surfaced to the app: $script',
      PdfNamedAction(:final name) => 'Named action: $name',
      PdfUnknownAction(:final type) => 'Unhandled action type: $type',
      PdfGoToAction() => 'GoTo', // unreachable
    });
  }

  /// The app's own entries in the annotation right-click menu - here a
  /// "Copy text" action when the clicked annotation carries any.
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

  Future<void> _openLink(Uri url) async {
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      _toast('Could not open $url');
    }
  }

  /// Opens the feedback dialog: the user reviews the diagnostics captured this
  /// session and opens the GitHub feedback form with the report prefilled.
  void _openFeedback() {
    unawaited(showFeedbackDialog(
      context,
      onOpen: _openLink,
      onCopied: () => _toast('Diagnostics copied to clipboard'),
    ));
  }

  void _cycleTheme() {
    _prefs.themeMode = switch (_prefs.themeMode) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
  }

  void _setPerformanceMode(int value) {
    final next = value == 0
        ? const PdfPerformanceMode.auto()
        : PdfPerformanceMode.fixed(workerCount: value);
    if (next == _performance.mode) return;
    setState(() {
      _performance.mode = next;
      _workerConfigEpoch++;
    });
    _toast(_workerPoolTooltip);
  }

  Key _pdfShellKey(_DocumentTab tab, String mode) =>
      ValueKey<Object>((tab, mode, _workerConfigEpoch));

  String get _nextThemeLabel => switch (_prefs.themeMode) {
        ThemeMode.system => 'Theme: system - switch to light',
        ThemeMode.light => 'Theme: light - switch to dark',
        ThemeMode.dark => 'Theme: dark - switch to system',
      };

  bool get _usesAppleShortcuts =>
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.iOS;

  String _menuShortcut(String key, {bool shift = false}) => _usesAppleShortcuts
      ? '${shift ? '⇧' : ''}⌘$key'
      : 'Ctrl+${shift ? 'Shift+' : ''}$key';

  Widget _appMenuTile({
    required IconData icon,
    required String title,
    String? shortcut,
    Widget? trailing,
  }) =>
      ListTile(
        leading: Icon(icon),
        title: Text(title),
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
      );

  List<PopupMenuEntry<VoidCallback>> _appMenuItems(
          BuildContext menuContext, _DocumentTab? tab) =>
      [
        PopupMenuItem(
          value: () {
            final bytes = tab?.session?.bytes;
            if (bytes != null) unawaited(_saveAs(bytes));
          },
          enabled: tab?.session != null,
          child: _appMenuTile(
            icon: Icons.save_as_outlined,
            title: 'Save as…',
            shortcut: _menuShortcut('S'),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: () => unawaited(_pickFile()),
          child: _appMenuTile(
            icon: Icons.folder_open,
            title: 'Open a PDF…',
            shortcut: _menuShortcut('O'),
          ),
        ),
        PopupMenuItem(
          value: _openDemo,
          child: _appMenuTile(
            icon: Icons.auto_awesome,
            title: 'Open the interactive demo',
          ),
        ),
        ..._recentMenuItems(menuContext),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: () => unawaited(_runOcr()),
          enabled: tab?.session != null,
          child: _appMenuTile(
            icon: Icons.document_scanner_outlined,
            title: 'OCR…',
          ),
        ),
        PopupMenuItem(
          value: _compareWith,
          enabled: tab?.session != null,
          child: _appMenuTile(
            icon: Icons.compare_arrows,
            title: 'Compare with another PDF…',
          ),
        ),
        PopupMenuItem(
          value: () => setState(() => _readOnly = !_readOnly),
          enabled: tab?.session != null,
          child: _appMenuTile(
            icon: _readOnly ? Icons.edit : Icons.edit_off,
            title: _readOnly ? 'Switch to edit mode' : 'Switch to read-only',
          ),
        ),
        PopupMenuItem(
          value: () =>
              setState(() => _horizontalLayout = !_horizontalLayout),
          enabled: tab?.session != null,
          child: _appMenuTile(
            icon: _horizontalLayout
                ? Icons.swap_vert
                : Icons.swap_horiz,
            title: _horizontalLayout
                ? 'Vertical page layout'
                : 'Horizontal page layout',
          ),
        ),
        PopupMenuItem(
          value: () => unawaited(_exportImage()),
          enabled: tab?.session != null,
          child: _appMenuTile(
            icon: Icons.image_outlined,
            title: 'Export page as image…',
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _cycleTheme,
          child: _appMenuTile(
            icon: Icons.dark_mode,
            title: _nextThemeLabel,
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _openFeedback,
          child: _appMenuTile(
            icon: Icons.feedback_outlined,
            title: 'Supply feedback…',
          ),
        ),
        PopupMenuItem(
          value: () => _openLink(_githubUrl),
          child: _appMenuTile(
            icon: Icons.code,
            title: 'View source on GitHub',
          ),
        ),
        PopupMenuItem(
          value: () => _openLink(_pubDevUrl),
          child: _appMenuTile(
            icon: Icons.inventory_2_outlined,
            title: 'dart_pdf_editor on pub.dev',
          ),
        ),
      ];

  /// The "Open Recent" entry of the app menu: a single row
  /// that expands into a submenu listing remembered files (newest first)
  /// plus a clear action. Files already open in a tab are left out - there's
  /// no point offering a shortcut to reopen them. The row stays visible
  /// even when empty, so users can discover where recents will appear.
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
        // A no-op: the nested button below owns the row's taps (opening the
        // submenu). This only guards a stray tap on the row from invoking a
        // null action.
        value: () {},
        enabled: recents.isNotEmpty,
        padding: EdgeInsets.zero,
        child: PopupMenuButton<VoidCallback>(
          key: const ValueKey('open-recent-submenu'),
          tooltip: 'Open Recent',
          enabled: recents.isNotEmpty,
          // Run the chosen submenu action, then dismiss the parent menu,
          // which stays open behind the submenu otherwise.
          onSelected: (action) {
            action();
            if (Navigator.of(menuContext).canPop()) {
              Navigator.of(menuContext).pop();
            }
          },
          itemBuilder: (_) => [
            if (recents.isEmpty)
              const PopupMenuItem<VoidCallback>(
                enabled: false,
                child: ListTile(
                  leading: Icon(Icons.history_toggle_off),
                  title: Text('No recent files'),
                  contentPadding: EdgeInsets.zero,
                ),
              )
            else ...[
              for (final entry in recents)
                PopupMenuItem<VoidCallback>(
                  value: () => unawaited(_openRecent(entry)),
                  child: ListTile(
                    leading: const Icon(Icons.picture_as_pdf_outlined),
                    title: Text(
                      entry.title.isEmpty ? 'Untitled' : entry.title,
                      overflow: TextOverflow.ellipsis,
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              const PopupMenuDivider(),
              PopupMenuItem<VoidCallback>(
                value: () => unawaited(_recents.clear()),
                child: const ListTile(
                  leading: Icon(Icons.clear_all),
                  title: Text('Clear recent files'),
                  contentPadding: EdgeInsets.zero,
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

  List<RecentFile> _recentMenuEntries() {
    final openTitles = {for (final tab in _tabs) tab.title};
    return [
      for (final entry in _recents.entries)
        if (!openTitles.contains(entry.title)) entry,
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

  void _toast(String message) {
    // Floating in the bottom-right corner on desktop, so toasts stay a
    // compact pill off to the side and never cover the chrome; a
    // near-full-width pill on narrow windows. pdfFloatingToastMargin lifts
    // it clear of the editing toolbar dock and the device safe-area inset.
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: pdfFloatingToastMargin(context),
        duration: const Duration(seconds: 2),
      ));
  }

  /// Opens [bytes] in a brand-new tab and makes it the active one.
  void _openBytes(Uint8List bytes, String title, {bool isDemo = false}) {
    _addTab(_DocumentTab.document(
      title: title,
      bytes: bytes,
      preferences: _prefs,
      isDemo: isDemo,
    ));
  }

  /// Adds a tab that just reports an open failure.
  void _openError(String title, String error) {
    _addTab(_DocumentTab.error(title: title, error: error));
  }

  /// Adds [tab] as the active tab.
  void _addTab(_DocumentTab tab) {
    setState(() {
      _tabs.add(tab);
      _activeIndex = _tabs.length - 1;
    });
  }

  /// Adds a placeholder tab immediately so large files don't leave the app
  /// looking idle while their bytes are read and parsed. Returns the exact
  /// tab object so the async completion can replace it, unless the user
  /// closes it first.
  _DocumentTab _openLoading(String title) {
    final tab = _DocumentTab.loading(title: title);
    _addTab(tab);
    return tab;
  }

  void _replaceLoadingTab(_DocumentTab loading, _DocumentTab replacement) {
    final index = _tabs.indexOf(loading);
    if (index == -1) {
      replacement.dispose();
      return;
    }
    setState(() {
      _tabs[index] = replacement;
      _activeIndex = index;
    });
    loading.dispose();
  }

  void _openDemo() =>
      _openBytes(buildDemoPdf(), 'Feature showcase', isDemo: true);

  /// Disposes the tab at [index] and drops it, keeping a sensible tab
  /// active. The controllers are torn down after the frame so the
  /// outgoing viewer can detach from them cleanly first.
  void _closeTab(int index) {
    final tab = _tabs[index];
    setState(() {
      _tabs.removeAt(index);
      if (_activeIndex >= _tabs.length) _activeIndex = _tabs.length - 1;
      if (_activeIndex < 0) _activeIndex = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => tab.dispose());
  }

  /// Pins [child] into a page slot at its design size in PDF points and
  /// lets it scale with the page, so the overlays hold together at any
  /// zoom level and on any screen size.
  Widget _slot(PdfPageGeometry geometry, PdfRect rect, Widget child) =>
      Positioned.fromRect(
        rect: geometry.toViewRect(rect),
        child: FittedBox(
          child: SizedBox(width: rect.width, height: rect.height, child: child),
        ),
      );

  /// Flutter widgets pinned into the slots the demo document draws.
  List<Widget> _demoOverlays(
      BuildContext context, int pageIndex, PdfPageGeometry geometry) {
    final tab = _active;
    if (tab == null) return const [];
    switch (pageIndex) {
      case 0:
        return [
          _slot(geometry, DemoLayout.counterBadge,
              _CounterBadge(count: tab.counter)),
        ];
      case 1:
        return [
          _slot(geometry, DemoLayout.clock, const _ClockTile()),
          _slot(
            geometry,
            DemoLayout.counter,
            _CounterControl(
              count: tab.counter,
              onChanged: (value) => setState(() => tab.counter = value),
            ),
          ),
          _slot(
            geometry,
            DemoLayout.toggle,
            FittedBox(
              child: Switch(
                value: tab.switchOn,
                onChanged: (value) => setState(() => tab.switchOn = value),
              ),
            ),
          ),
          _slot(
            geometry,
            DemoLayout.note,
            Material(
              color: const Color(0xF2FFFFFF),
              shape: RoundedRectangleBorder(
                side: BorderSide(color: Colors.indigo.shade200),
                borderRadius: BorderRadius.circular(4),
              ),
              child: TextField(
                key: const ValueKey('demo-note'),
                controller: tab.noteField,
                decoration: const InputDecoration(
                  hintText: 'Type here - this text box floats above the page',
                  isDense: true,
                  contentPadding: EdgeInsets.all(10),
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
        ];
      default:
        return const [];
    }
  }

  @override
  void initState() {
    super.initState();
    // the app menu rebuilds with the current recents whenever they change
    _recents.addListener(_onRecentsChanged);
    // open a file straight away with:
    //   flutter run -d macos --dart-define=PDF=/path/to/file.pdf
    const preset = String.fromEnvironment('PDF');
    if (preset.isNotEmpty) {
      _openPath(preset);
    } else {
      _openDemo();
    }
  }

  void _onRecentsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _recents.removeListener(_onRecentsChanged);
    _recents.dispose();
    for (final tab in _tabs) {
      tab.dispose();
    }
    _performance.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final file = await openFile(acceptedTypeGroups: const [_pdfTypeGroup]);
    if (file == null) return;
    final loading = _openLoading(file.name);
    try {
      final bytes = await file.readAsBytes();
      // Let the loading tab paint before constructing the edit session, which
      // synchronously opens the PDF and can be noticeable for large files.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      _replaceLoadingTab(
        loading,
        _DocumentTab.document(
          title: file.name,
          bytes: bytes,
          preferences: _prefs,
        ),
      );
      unawaited(_recents.record(file.name, bytes));
    } catch (e, s) {
      AppLog.instance
          .error('Could not open ${file.name}', error: e, stackTrace: s);
      if (!mounted) return;
      _replaceLoadingTab(
        loading,
        _DocumentTab.error(
          title: file.name,
          error: 'Could not open ${file.name}\n$e',
        ),
      );
    }
  }

  /// Picks a PDF and returns its bytes (null when cancelled) - the source
  /// for the editor's "Insert PDF…" action.
  Future<Uint8List?> _pickPdfBytes() async {
    final file = await openFile(acceptedTypeGroups: const [_pdfTypeGroup]);
    return file?.readAsBytes();
  }

  /// Opens a second PDF and compares it against the active document in a
  /// new tab ([PdfComparisonView]). The active document is the "before".
  Future<void> _compareWith() async {
    final tab = _active;
    final current = tab?.session?.bytes;
    if (current == null) return;
    final file = await openFile(acceptedTypeGroups: const [_pdfTypeGroup]);
    if (file == null) return;
    try {
      final other = await file.readAsBytes();
      setState(() {
        _tabs.add(_DocumentTab.comparison(
          title: 'Compare: ${tab!.title} ↔ ${file.name}',
          before: current,
          after: other,
        ));
        _activeIndex = _tabs.length - 1;
      });
    } catch (e, s) {
      AppLog.instance
          .error('Could not open ${file.name}', error: e, stackTrace: s);
      _openError(file.name, 'Could not open ${file.name}\n$e');
    }
  }

  Future<void> _openPath(String path) async {
    final name = path.split(RegExp(r'[/\\]')).last;
    final loading = _openLoading(name);
    try {
      final bytes = await XFile(path).readAsBytes();
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      _replaceLoadingTab(
        loading,
        _DocumentTab.document(
          title: name,
          bytes: bytes,
          preferences: _prefs,
        ),
      );
      unawaited(_recents.record(name, bytes));
    } catch (e, s) {
      AppLog.instance.error('Could not open $path', error: e, stackTrace: s);
      if (!mounted) return;
      _replaceLoadingTab(
        loading,
        _DocumentTab.error(title: name, error: 'Could not open $path\n$e'),
      );
    }
  }

  /// Reopens a file from the "Open recent" list by reading its stored bytes
  /// back from the cache. A recent whose bytes have aged out is dropped
  /// from the list with an explanatory tab.
  Future<void> _openRecent(RecentFile entry) async {
    final loading = _openLoading(entry.title);
    try {
      final bytes = await _recents.bytesFor(entry.id);
      if (!mounted) return;
      if (bytes == null) {
        _replaceLoadingTab(
          loading,
          _DocumentTab.error(
            title: entry.title,
            error: 'Could not reopen ${entry.title} - its saved copy is no '
                'longer available.',
          ),
        );
        unawaited(_recents.remove(entry.id));
        return;
      }
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      _replaceLoadingTab(
        loading,
        _DocumentTab.document(
          title: entry.title,
          bytes: bytes,
          preferences: _prefs,
        ),
      );
      unawaited(_recents.touch(entry.id));
    } catch (e, s) {
      AppLog.instance
          .error('Could not reopen ${entry.title}', error: e, stackTrace: s);
      if (!mounted) return;
      _replaceLoadingTab(
        loading,
        _DocumentTab.error(
          title: entry.title,
          error: 'Could not reopen ${entry.title}\n$e',
        ),
      );
    }
  }

  /// The suggested save name - the active tab's title (the opened file's
  /// name, or the demo's title), with a `.pdf` extension guaranteed.
  String _saveFileName() {
    var name = (_active?.title ?? '').trim();
    if (name.isEmpty) name = 'document';
    if (!name.toLowerCase().endsWith('.pdf')) name = '$name.pdf';
    return name;
  }

  /// Saves with whatever the platform offers: a save dialog on desktop,
  /// a browser download on the web, the share sheet on phones and
  /// tablets (where apps can't write outside their sandbox directly).
  Future<void> _saveAs(Uint8List bytes) async {
    final name = _saveFileName();
    final file = XFile.fromData(bytes, mimeType: 'application/pdf', name: name);
    if (kIsWeb) {
      await file.saveTo(name);
      _toast('Downloaded $name');
      return;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android || TargetPlatform.iOS:
        final box = context.findRenderObject() as RenderBox?;
        final origin =
            box == null ? null : box.localToGlobal(Offset.zero) & box.size;
        await SharePlus.instance.share(ShareParams(
          files: [file],
          fileNameOverrides: [name],
          // required on iPad: the share popover anchors to this rect
          sharePositionOrigin: origin ?? const Rect.fromLTWH(0, 0, 1, 1),
        ));
      default:
        final location = await getSaveLocation(
          suggestedName: name,
          acceptedTypeGroups: const [_pdfTypeGroup],
        );
        if (location == null) return;
        try {
          final path = pdfSavePathWithExtension(location.path);
          await file.saveTo(path);
          _toast('Saved to $path');
        } catch (e, s) {
          AppLog.instance.error('Save failed', error: e, stackTrace: s);
          _toast('Save failed: $e');
        }
    }
  }

  /// Exports a Snapshot tool capture as a PNG image - a save dialog on
  /// desktop, a download on the web, the share sheet on phones. The vector
  /// copy of the same region stays on the editor's clipboard, so ⌘V/Ctrl+V
  /// (or the right-click Paste) drops it back into the PDF as vectors.
  Future<void> _saveSnapshot(BuildContext context, PdfSnapshot snapshot) async {
    const name = 'snapshot.png';
    final file =
        XFile.fromData(snapshot.pngBytes, mimeType: 'image/png', name: name);
    if (kIsWeb) {
      await file.saveTo(name);
      _toast('Downloaded $name - paste back into the PDF with Ctrl+V');
      return;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android || TargetPlatform.iOS:
        final box = context.findRenderObject() as RenderBox?;
        final origin =
            box == null ? null : box.localToGlobal(Offset.zero) & box.size;
        await SharePlus.instance.share(ShareParams(
          files: [file],
          fileNameOverrides: [name],
          sharePositionOrigin: origin ?? const Rect.fromLTWH(0, 0, 1, 1),
        ));
      default:
        final location = await getSaveLocation(
          suggestedName: name,
          acceptedTypeGroups: const [_imageTypeGroup],
        );
        if (location == null) return;
        try {
          await file.saveTo(location.path);
          _toast('Saved $name - paste back into the PDF with ⌘V');
        } catch (e, s) {
          AppLog.instance.error('Save failed', error: e, stackTrace: s);
          _toast('Save failed: $e');
        }
    }
  }

  /// Renders the page the viewer is currently on to a raster image
  /// ([PdfPageExport]) and saves it as PNG/JPEG, after prompting for the
  /// format and resolution. The current edit revision is exported, so unsaved
  /// changes are included.
  Future<void> _exportImage() async {
    final tab = _active;
    final session = tab?.session;
    final viewer = tab?.viewer;
    if (tab == null || session == null || viewer == null) {
      _toast('Open a document first');
      return;
    }
    final choice = await _showImageExportDialog();
    if (choice == null || !mounted) return;
    final (format, dpi) = choice;

    final pageIndex =
        viewer.currentPage.clamp(0, session.document.pageCount - 1);
    final isPng = format == PdfRasterFormat.png;
    try {
      final bytes = await PdfPageExport.exportPage(
        session.document.page(pageIndex),
        format: format,
        dpi: dpi,
      );
      if (!mounted) return;
      var stem = tab.title.trim();
      if (stem.toLowerCase().endsWith('.pdf')) {
        stem = stem.substring(0, stem.length - 4).trim();
      }
      if (stem.isEmpty) stem = 'page';
      final name = '$stem-p${pageIndex + 1}.${isPng ? 'png' : 'jpg'}';
      await _saveImageBytes(bytes, name, isPng ? 'image/png' : 'image/jpeg');
    } catch (e, s) {
      AppLog.instance.error('Image export failed', error: e, stackTrace: s);
      if (mounted) _toast('Export failed: $e');
    }
  }

  /// Saves a page-image [bytes] as [name] ([mimeType] PNG/JPEG): a save dialog
  /// on desktop, a download on the web, the share sheet on phones.
  Future<void> _saveImageBytes(
      Uint8List bytes, String name, String mimeType) async {
    final file = XFile.fromData(bytes, mimeType: mimeType, name: name);
    if (kIsWeb) {
      await file.saveTo(name);
      _toast('Downloaded $name');
      return;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android || TargetPlatform.iOS:
        final box = context.findRenderObject() as RenderBox?;
        final origin =
            box == null ? null : box.localToGlobal(Offset.zero) & box.size;
        await SharePlus.instance.share(ShareParams(
          files: [file],
          fileNameOverrides: [name],
          sharePositionOrigin: origin ?? const Rect.fromLTWH(0, 0, 1, 1),
        ));
      default:
        final location = await getSaveLocation(
          suggestedName: name,
          acceptedTypeGroups: const [_imageTypeGroup],
        );
        if (location == null) return;
        try {
          await file.saveTo(location.path);
          _toast('Saved $name');
        } catch (e, s) {
          AppLog.instance.error('Save failed', error: e, stackTrace: s);
          _toast('Save failed: $e');
        }
    }
  }

  /// Prompts for the export format (PNG/JPEG) and resolution (dpi). Returns
  /// null when cancelled.
  Future<(PdfRasterFormat, double)?> _showImageExportDialog() {
    var format = PdfRasterFormat.png;
    var dpi = 150.0;
    return showDialog<(PdfRasterFormat, double)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Export page as image'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Format'),
              const SizedBox(height: 8),
              SegmentedButton<PdfRasterFormat>(
                segments: const [
                  ButtonSegment(value: PdfRasterFormat.png, label: Text('PNG')),
                  ButtonSegment(
                      value: PdfRasterFormat.jpeg, label: Text('JPEG')),
                ],
                selected: {format},
                onSelectionChanged: (s) => setState(() => format = s.first),
              ),
              const SizedBox(height: 16),
              const Text('Resolution'),
              const SizedBox(height: 8),
              DropdownButton<double>(
                value: dpi,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 72, child: Text('72 dpi')),
                  DropdownMenuItem(value: 150, child: Text('150 dpi')),
                  DropdownMenuItem(value: 300, child: Text('300 dpi')),
                  DropdownMenuItem(value: 600, child: Text('600 dpi')),
                ],
                onChanged: (d) => setState(() => dpi = d ?? dpi),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop((format, dpi)),
              child: const Text('Export'),
            ),
          ],
        ),
      ),
    );
  }

  /// Adds an invisible, selectable/searchable OCR text layer over the
  /// active document using a self-hosted vision-language OCR model
  /// (pdf_ocr_vlm). Prompts for the service endpoint and an optional API
  /// key/token first, then runs every page and opens the result in a new
  /// tab. The original is left untouched.
  Future<void> _runOcr() async {
    final tab = _active;
    final bytes = tab?.session?.bytes;
    if (tab == null || bytes == null) {
      _toast('Open a document before running OCR');
      return;
    }

    // Supply / confirm the OCR service credentials.
    final settings = await showDialog<_OcrSettings>(
      context: context,
      builder: (_) => _OcrSettingsDialog(
        endpoint: _ocrEndpoint,
        model: _ocrModel,
        apiKey: _ocrApiKey,
        onOpenDocs: () => _openLink(Uri.parse(
            'https://github.com/ben-milanko/dart-pdf/tree/main/packages/pdf_ocr_vlm')),
      ),
    );
    if (settings == null) return; // cancelled
    setState(() {
      _ocrEndpoint = settings.endpoint;
      _ocrModel = settings.model;
      _ocrApiKey = settings.apiKey;
    });

    final progress = ValueNotifier<String>('Preparing…');
    if (!mounted) return;
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _OcrProgressDialog(progress: progress),
    ));

    final engine = VlmOcrEngine.dotsOcr(
      endpoint: Uri.parse(settings.endpoint),
      model: settings.model.isEmpty ? 'model' : settings.model,
      apiKey: (settings.apiKey?.isNotEmpty ?? false) ? settings.apiKey : null,
    );
    try {
      final editor = PdfEditor(PdfDocument.open(bytes));
      final count = editor.document.pageCount;
      var spans = 0;
      for (var i = 0; i < count; i++) {
        progress.value = 'Recognising page ${i + 1} of $count…';
        spans += await editor.applyOcr(i, engine, pixelRatio: 2);
      }
      final result = editor.save();
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // dismiss progress
      _openBytes(result, '${tab.title} (OCR)');
      _toast('OCR added $spans text spans - the page text is now selectable');
    } on VlmOcrException catch (e, s) {
      AppLog.instance.error('OCR failed: ${e.message}', error: e, stackTrace: s);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _toast('OCR failed: ${e.message}');
    } catch (e, s) {
      AppLog.instance.error('OCR failed', error: e, stackTrace: s);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _toast('OCR failed: $e');
    } finally {
      engine.close();
      progress.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tab = _active;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyO, meta: true): () =>
            unawaited(_pickFile()),
        const SingleActivator(LogicalKeyboardKey.keyO, control: true): () =>
            unawaited(_pickFile()),
        const SingleActivator(LogicalKeyboardKey.keyO, meta: true, shift: true):
            _openMostRecent,
        const SingleActivator(LogicalKeyboardKey.keyO,
            control: true, shift: true): _openMostRecent,
        if (tab?.session != null) ...{
          const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () =>
              unawaited(_saveAs(tab!.session!.bytes)),
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
              unawaited(_saveAs(tab!.session!.bytes)),
        },
      },
      child: Scaffold(
        appBar: AppBar(
          leading: _buildAppMenu(tab),
          leadingWidth: _appMenuLeadingWidth,
          centerTitle: false,
          title:
              _tabs.isEmpty ? const Text('dart-pdf viewer') : _buildTabStrip(),
          titleSpacing: _tabs.isEmpty ? null : 8,
          actions: [
            if (tab?.session != null && !tab!.isComparison)
              PopupMenuButton<int>(
                key: const ValueKey('dartpdf-worker-pool-menu'),
                tooltip: _workerPoolTooltip,
                icon: Icon(_performance.mode.isAuto
                    ? Icons.auto_awesome
                    : Icons.memory),
                onSelected: _setPerformanceMode,
                itemBuilder: (context) => [
                  CheckedPopupMenuItem<int>(
                    key: const ValueKey('dartpdf-worker-pool-auto'),
                    value: 0,
                    checked: _performance.mode.isAuto,
                    child: const Text('Auto'),
                  ),
                  const PopupMenuDivider(),
                  CheckedPopupMenuItem<int>(
                    key: const ValueKey('dartpdf-worker-pool-off'),
                    value: 1,
                    checked: _performance.mode.workerCount == 1,
                    child: const Text('Single worker'),
                  ),
                  for (final size in const [2, 3, 4, 6])
                    CheckedPopupMenuItem<int>(
                      key: ValueKey('dartpdf-worker-pool-$size'),
                      value: size,
                      checked: _performance.mode.workerCount == size,
                      child: Text('$size workers'),
                    ),
                ],
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
          ],
        ),
        // each tab is keyed so switching rebuilds against its own
        // controllers (which keep the edits and scroll position alive);
        // only the active tab is mounted, so there's one viewer at a time
        body: tab == null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton.icon(
                      onPressed: _pickFile,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Open a PDF'),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed: _openDemo,
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('Try the interactive demo'),
                    ),
                  ],
                ),
              )
            : tab.isLoading
                ? _OpeningDocument(title: tab.title)
                : tab.error != null
                    ? Center(
                        child: Text(tab.error!, textAlign: TextAlign.center))
                    : tab.isComparison
                        ? PdfComparisonView(
                            key: ValueKey(tab),
                            before: tab.compareBefore!,
                            after: tab.compareAfter!,
                          )
                        // the two drop-in widgets carry all the PDF chrome (search,
                        // page number, panels, toolbar) - the app supplies the edit
                        // session, its file handling, and the demo's app-side wiring
                        : _readOnly
                            ? PdfReader(
                                key: _pdfShellKey(tab, 'reader'),
                                bytes: tab.session!.bytes,
                                // a stable id per document so reopening it (across
                                // app restarts) restores its scroll position and zoom
                                documentId: tab.title,
                                controller: tab.viewer,
                                preferences: _prefs,
                                performance: _performance,
                                rasterCache: _rasterCache,
                                textCache: _textCache,
                                pageLayout: _pageLayout,
                                onAction: _onAction,
                                pageOverlayBuilder:
                                    tab.isDemo ? _demoOverlays : null,
                              )
                            : PdfEditorView(
                                key: _pdfShellKey(tab, 'editor'),
                                documentId: tab.title,
                                controller: tab.session,
                                viewerController: tab.viewer,
                                performance: _performance,
                                rasterCache: _rasterCache,
                                textCache: _textCache,
                                pageLayout: _pageLayout,
                                onSave: (saved) => unawaited(_saveAs(saved)),
                                onPickPdfToInsert: _pickPdfBytes,
                                onExportPages: (bytes) =>
                                    unawaited(_saveAs(bytes)),
                                onAction: _onAction,
                                pageOverlayBuilder:
                                    tab.isDemo ? _demoOverlays : null,
                                annotationMenuBuilder: _annotationMenuActions,
                                formImagePicker: _pickFormImage,
                                imagePicker: _pickImage,
                                fontPicker: _pickFont,
                                onSnapshot: _saveSnapshot,
                              ),
      ),
    );
  }

  Widget _buildAppMenu(_DocumentTab? tab) => PopupMenuButton<VoidCallback>(
        key: const ValueKey('dartpdf-app-menu'),
        iconSize: _appMenuIconSize,
        icon: Image.memory(
          demoLogoPng(),
          width: _appMenuIconSize,
          height: _appMenuIconSize,
          semanticLabel: 'DartPDF',
        ),
        tooltip: 'DartPDF menu',
        onSelected: (action) => action(),
        itemBuilder: (context) => _appMenuItems(context, tab),
      );

  /// The horizontally scrolling row of open-document tabs plus the sticky
  /// new-tab button.
  Widget _buildTabStrip() {
    return SizedBox(
      height: _tabStripHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const buttonWidth = 40.0;
          final maxTabsWidth = (constraints.maxWidth - buttonWidth)
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
                  child: ListView.builder(
                    key: const ValueKey('tab-strip'),
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    itemCount: _tabs.length,
                    itemBuilder: (context, i) => _buildTab(i),
                  ),
                ),
              SizedBox(
                width: buttonWidth,
                height: _tabStripHeight,
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints.tightFor(width: buttonWidth),
                  icon: const Icon(Icons.add),
                  tooltip: 'Open PDF in a new tab',
                  onPressed: _pickFile,
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
      width += 4 + 12 + painter.width.clamp(40.0, 160.0).toDouble() + 30;
    }
    return width;
  }

  Widget _buildTab(int index) {
    final tab = _tabs[index];
    final selected = index == _activeIndex;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
      child: Material(
        color: selected
            ? scheme.secondaryContainer
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _activeIndex = index),
          child: Padding(
            padding: const EdgeInsets.only(left: 12, right: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Text(
                    tab.title.isEmpty ? 'Untitled' : tab.title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.normal,
                      color: selected
                          ? scheme.onSecondaryContainer
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 30, minHeight: 30),
                  tooltip: 'Close tab',
                  onPressed: () => _closeTab(index),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Height of the AppBar's tab strip.
const double _tabStripHeight = 42;
const double _appMenuLeadingWidth = 60;
const double _appMenuIconSize = 24;

/// How many recent files the app menu lists at once.
const int _maxRecentMenuItems = 8;

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

/// One open document. Holds its own edit session and viewer controller
/// so switching tabs preserves edits, undo history, scroll position,
/// and any demo-specific overlay state.
class _DocumentTab {
  _DocumentTab.loading({required this.title})
      : session = null,
        viewer = null,
        isDemo = false,
        error = null,
        compareBefore = null,
        compareAfter = null,
        isLoading = true;

  _DocumentTab.document({
    required this.title,
    required Uint8List bytes,
    required PdfEditingPreferences preferences,
    this.isDemo = false,
  })  : session = PdfEditingController(bytes, preferences: preferences),
        viewer = PdfViewerController(),
        error = null,
        compareBefore = null,
        compareAfter = null,
        isLoading = false;

  _DocumentTab.error({required this.title, required this.error})
      : session = null,
        viewer = null,
        isDemo = false,
        compareBefore = null,
        compareAfter = null,
        isLoading = false;

  /// A document-comparison tab: hosts a [PdfComparisonView] over two
  /// files. No edit session or viewer controller of its own.
  _DocumentTab.comparison({
    required this.title,
    required Uint8List before,
    required Uint8List after,
  })  : session = null,
        viewer = null,
        isDemo = false,
        error = null,
        compareBefore = before,
        compareAfter = after,
        isLoading = false;

  final String title;
  final String? error;
  final bool isDemo;
  final bool isLoading;

  /// The two documents a comparison tab diffs; null on every other tab.
  final Uint8List? compareBefore;
  final Uint8List? compareAfter;

  bool get isComparison => compareAfter != null;

  /// Null for an error tab. Shared preferences are owned by the app, so
  /// they outlive the tab.
  final PdfEditingController? session;
  final PdfViewerController? viewer;

  // demo-specific state the PDF links and overlays drive, per document
  int counter = 0;
  bool switchOn = false;
  final noteField = TextEditingController();

  void dispose() {
    session?.dispose();
    viewer?.dispose();
    noteField.dispose();
  }
}

/// The OCR service connection the credentials dialog returns.
class _OcrSettings {
  const _OcrSettings(
      {required this.endpoint, required this.model, this.apiKey});

  final String endpoint;
  final String model;
  final String? apiKey;
}

/// Collects the OCR service endpoint, model name, and an optional API
/// key/token before a run - the "supply credentials / login" step. The key
/// is sent as an `Authorization: Bearer …` header by the engine.
class _OcrSettingsDialog extends StatefulWidget {
  const _OcrSettingsDialog({
    required this.endpoint,
    required this.model,
    required this.apiKey,
    required this.onOpenDocs,
  });

  final String endpoint;
  final String model;
  final String? apiKey;
  final VoidCallback onOpenDocs;

  @override
  State<_OcrSettingsDialog> createState() => _OcrSettingsDialogState();
}

class _OcrSettingsDialogState extends State<_OcrSettingsDialog> {
  late final _endpoint = TextEditingController(text: widget.endpoint);
  late final _model = TextEditingController(text: widget.model);
  late final _apiKey = TextEditingController(text: widget.apiKey ?? '');
  bool _obscureKey = true;

  @override
  void dispose() {
    _endpoint.dispose();
    _model.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Run OCR'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Adds a selectable, searchable text layer over scanned pages '
              'using a vision-language OCR model you host (dots.ocr on vLLM, '
              'or any OpenAI-compatible OCR endpoint).',
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('ocr-endpoint'),
              controller: _endpoint,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Service endpoint',
                hintText: 'http://localhost:8000/v1/chat/completions',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('ocr-model'),
              controller: _model,
              decoration: const InputDecoration(
                labelText: 'Model name',
                hintText: 'model',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('ocr-api-key'),
              controller: _apiKey,
              obscureText: _obscureKey,
              decoration: InputDecoration(
                labelText: 'API key / token (optional)',
                helperText: 'Sent as Authorization: Bearer …',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                      _obscureKey ? Icons.visibility : Icons.visibility_off),
                  tooltip: _obscureKey ? 'Show' : 'Hide',
                  onPressed: () => setState(() => _obscureKey = !_obscureKey),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.help_outline, size: 18),
                label: const Text('How to set up an OCR server'),
                onPressed: widget.onOpenDocs,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          key: const ValueKey('ocr-run'),
          icon: const Icon(Icons.document_scanner_outlined),
          label: const Text('Run OCR'),
          onPressed: () {
            final endpoint = _endpoint.text.trim();
            if (endpoint.isEmpty) return;
            final key = _apiKey.text.trim();
            Navigator.of(context).pop(_OcrSettings(
              endpoint: endpoint,
              model: _model.text.trim(),
              apiKey: key.isEmpty ? null : key,
            ));
          },
        ),
      ],
    );
  }
}

/// Modal shown while OCR runs; [progress] reports the current page.
class _OcrProgressDialog extends StatelessWidget {
  const _OcrProgressDialog({required this.progress});

  final ValueListenable<String> progress;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Row(
        children: [
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ValueListenableBuilder<String>(
              valueListenable: progress,
              builder: (context, value, _) => Text(value),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows the counter the PDF's "Increment" link annotation drives -
/// PDF → app state → widget, completing the loop on the same page.
class _CounterBadge extends StatelessWidget {
  const _CounterBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.indigo,
      borderRadius: BorderRadius.circular(6),
      child: Center(
        child: Text(
          '$count',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

/// Ticks every second - proof the overlay is a live widget, not artwork.
class _ClockTile extends StatefulWidget {
  const _ClockTile();

  @override
  State<_ClockTile> createState() => _ClockTileState();
}

class _ClockTileState extends State<_ClockTile> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    String pad(int v) => v.toString().padLeft(2, '0');
    return Material(
      color: Colors.black87,
      borderRadius: BorderRadius.circular(6),
      child: Center(
        child: Text(
          '${pad(now.hour)}:${pad(now.minute)}:${pad(now.second)}',
          style: const TextStyle(
            color: Colors.greenAccent,
            fontSize: 18,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

/// Edits the same counter the PDF link on page 1 increments.
class _CounterControl extends StatelessWidget {
  const _CounterControl({required this.count, required this.onChanged});

  final int count;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xF2FFFFFF),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.indigo.shade200),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            icon: const Icon(Icons.remove),
            onPressed: () => onChanged(count - 1),
          ),
          Text('$count', style: Theme.of(context).textTheme.titleMedium),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => onChanged(count + 1),
          ),
        ],
      ),
    );
  }
}
