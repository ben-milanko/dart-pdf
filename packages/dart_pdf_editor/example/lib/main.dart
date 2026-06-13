import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'demo_document.dart';

/// The project's source repository, opened from the AppBar links menu.
final _githubUrl = Uri.parse('https://github.com/ben-milanko/dart-pdf');

/// The published Flutter package the example is built on.
final _pubDevUrl = Uri.parse('https://pub.dev/packages/dart_pdf_editor');

/// One filter, every platform: desktop and web match on the extension,
/// Android on the MIME type, iOS/macOS on the uniform type identifier —
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

void main() => runApp(const ViewerApp());

class ViewerApp extends StatefulWidget {
  const ViewerApp({super.key});

  @override
  State<ViewerApp> createState() => _ViewerAppState();
}

class _ViewerAppState extends State<ViewerApp> {
  /// UI preferences saved on this device — tool styles, which panels
  /// are open, and the theme mode. Owned here so the MaterialApp can
  /// follow the persisted light/dark choice; the screen below shares
  /// the same instance with every editing session.
  final _prefs = PdfEditingPreferences();

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
        home: ViewerScreen(prefs: _prefs),
      ),
    );
  }
}

class ViewerScreen extends StatefulWidget {
  const ViewerScreen({super.key, required this.prefs});

  final PdfEditingPreferences prefs;

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  PdfEditingPreferences get _prefs => widget.prefs;

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

  /// GoTo and the standard named page actions never get here (the viewer
  /// follows them itself). Custom-scheme URIs are dispatched as app
  /// commands — the conventional way a PDF drives its host app — and
  /// anything else just gets described in a snackbar.
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

  /// The app's own entries in the annotation right-click menu — here a
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

  void _toast(String message) {
    // Floating in the bottom-right corner (lifted clear of the editing
    // toolbar) on desktop, so toasts stay a compact pill off to the side and
    // never cover the chrome; a near-full-width pill on narrow windows.
    final width = MediaQuery.of(context).size.width;
    const bottom = 68.0;
    final margin = width >= 600
        ? EdgeInsets.only(left: width - 360 - 24, right: 24, bottom: bottom)
        : const EdgeInsets.fromLTRB(16, 0, 16, bottom);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: margin,
        duration: const Duration(seconds: 2),
      ));
  }

  /// Opens [bytes] in a brand-new tab and makes it the active one.
  void _openBytes(Uint8List bytes, String title, {bool isDemo = false}) {
    setState(() {
      _tabs.add(_DocumentTab.document(
        title: title,
        bytes: bytes,
        preferences: _prefs,
        isDemo: isDemo,
      ));
      _activeIndex = _tabs.length - 1;
    });
  }

  /// Adds a tab that just reports an open failure.
  void _openError(String title, String error) {
    setState(() {
      _tabs.add(_DocumentTab.error(title: title, error: error));
      _activeIndex = _tabs.length - 1;
    });
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
    // open a file straight away with:
    //   flutter run -d macos --dart-define=PDF=/path/to/file.pdf
    const preset = String.fromEnvironment('PDF');
    if (preset.isNotEmpty) {
      _openPath(preset);
    } else {
      _openDemo();
    }
  }

  @override
  void dispose() {
    for (final tab in _tabs) {
      tab.dispose();
    }
    super.dispose();
  }

  Future<void> _pickFile() async {
    final file = await openFile(acceptedTypeGroups: const [_pdfTypeGroup]);
    if (file == null) return;
    try {
      _openBytes(await file.readAsBytes(), file.name);
    } catch (e) {
      _openError(file.name, 'Could not open ${file.name}\n$e');
    }
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
    } catch (e) {
      _openError(file.name, 'Could not open ${file.name}\n$e');
    }
  }

  Future<void> _openPath(String path) async {
    final name = path.split(RegExp(r'[/\\]')).last;
    try {
      _openBytes(await XFile(path).readAsBytes(), name);
    } catch (e) {
      _openError(name, 'Could not open $path\n$e');
    }
  }

  /// Saves with whatever the platform offers: a save dialog on desktop,
  /// a browser download on the web, the share sheet on phones and
  /// tablets (where apps can't write outside their sandbox directly).
  Future<void> _saveAs(Uint8List bytes) async {
    const name = 'annotated.pdf';
    final file = XFile.fromData(bytes, mimeType: 'application/pdf');
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
          fileNameOverrides: const [name],
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
          await file.saveTo(location.path);
          _toast('Saved to ${location.path}');
        } catch (e) {
          _toast('Save failed: $e');
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tab = _active;
    return Scaffold(
      appBar: AppBar(
        title: Text(tab == null || tab.title.isEmpty
            ? 'dart-pdf viewer'
            : tab.title, overflow: TextOverflow.ellipsis),
        // a browser-style tab strip under the title; hidden until the
        // first document is open
        bottom: _tabs.isEmpty
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(_tabStripHeight),
                child: _buildTabStrip(),
              ),
        actions: [
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
          // every plain action is compact: the row overflows an 800px
          // window (the widget-test viewport included) at full density
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(_readOnly ? Icons.edit_off : Icons.edit),
            tooltip: _readOnly
                ? 'Read-only (PdfReader) — tap to edit'
                : 'Editing (PdfEditorView) — tap for read-only',
            onPressed: () => setState(() => _readOnly = !_readOnly),
          ),
          ListenableBuilder(
            listenable: _prefs,
            builder: (context, _) => IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(switch (_prefs.themeMode) {
                ThemeMode.system => Icons.brightness_auto,
                ThemeMode.light => Icons.light_mode,
                ThemeMode.dark => Icons.dark_mode,
              }),
              tooltip: switch (_prefs.themeMode) {
                ThemeMode.system => 'Theme: system — tap for light',
                ThemeMode.light => 'Theme: light — tap for dark',
                ThemeMode.dark => 'Theme: dark — tap for system',
              },
              onPressed: () => _prefs.themeMode = switch (_prefs.themeMode) {
                ThemeMode.system => ThemeMode.light,
                ThemeMode.light => ThemeMode.dark,
                ThemeMode.dark => ThemeMode.system,
              },
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'Open the interactive demo in a new tab',
            onPressed: _openDemo,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.folder_open),
            tooltip: 'Open PDF in a new tab',
            onPressed: _pickFile,
          ),
          // Compare + project links share one overflow slot so the action
          // row stays inside the 800px test window (every standalone
          // button would push it over).
          PopupMenuButton<VoidCallback>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'More actions',
            onSelected: (action) => action(),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _compareWith,
                enabled: _active?.session != null,
                child: const ListTile(
                  leading: Icon(Icons.compare_arrows),
                  title: Text('Compare with another PDF…'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: () => _openLink(_githubUrl),
                child: const ListTile(
                  leading: Icon(Icons.code),
                  title: Text('View source on GitHub'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: () => _openLink(_pubDevUrl),
                child: const ListTile(
                  leading: Icon(Icons.inventory_2_outlined),
                  title: Text('dart_pdf_editor on pub.dev'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
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
          : tab.error != null
              ? Center(child: Text(tab.error!, textAlign: TextAlign.center))
              : tab.isComparison
              ? PdfComparisonView(
                  key: ValueKey(tab),
                  before: tab.compareBefore!,
                  after: tab.compareAfter!,
                )
              // the two drop-in widgets carry all the PDF chrome (search,
              // page number, panels, toolbar) — the app supplies the edit
              // session, its file handling, and the demo's app-side wiring
              : _readOnly
                  ? PdfReader(
                      key: ValueKey(tab),
                      bytes: tab.session!.bytes,
                      // a stable id per document so reopening it (across
                      // app restarts) restores its scroll position and zoom
                      documentId: tab.title,
                      controller: tab.viewer,
                      preferences: _prefs,
                      onAction: _onAction,
                      pageOverlayBuilder: tab.isDemo ? _demoOverlays : null,
                    )
                  : PdfEditorView(
                      key: ValueKey(tab),
                      documentId: tab.title,
                      controller: tab.session,
                      viewerController: tab.viewer,
                      onSave: (saved) => unawaited(_saveAs(saved)),
                      onAction: _onAction,
                      pageOverlayBuilder: tab.isDemo ? _demoOverlays : null,
                      annotationMenuBuilder: _annotationMenuActions,
                      formImagePicker: _pickFormImage,
                    ),
    );
  }

  /// The horizontally scrolling row of open-document tabs plus the
  /// new-tab button.
  Widget _buildTabStrip() {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: SizedBox(
        height: _tabStripHeight,
        child: Row(
          children: [
            Expanded(
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                itemCount: _tabs.length,
                itemBuilder: (context, i) => _buildTab(i),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.add),
              tooltip: 'Open PDF in a new tab',
              onPressed: _pickFile,
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

/// One open document. Holds its own edit session and viewer controller
/// so switching tabs preserves edits, undo history, scroll position,
/// and any demo-specific overlay state.
class _DocumentTab {
  _DocumentTab.document({
    required this.title,
    required Uint8List bytes,
    required PdfEditingPreferences preferences,
    this.isDemo = false,
  })  : session = PdfEditingController(bytes, preferences: preferences),
        viewer = PdfViewerController(),
        error = null,
        compareBefore = null,
        compareAfter = null;

  _DocumentTab.error({required this.title, required this.error})
      : session = null,
        viewer = null,
        isDemo = false,
        compareBefore = null,
        compareAfter = null;

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
        compareAfter = after;

  final String title;
  final String? error;
  final bool isDemo;

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

/// Shows the counter the PDF's "Increment" link annotation drives —
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

/// Ticks every second — proof the overlay is a live widget, not artwork.
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
