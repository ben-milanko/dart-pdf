import 'dart:async';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:url_launcher/url_launcher.dart';

import 'document_tab.dart';
import 'file_io.dart';

/// Height of the AppBar's browser-style tab strip.
const double _tabStripHeight = 42;

/// The editor's main screen: a strip of open-document tabs over the drop-in
/// [PdfEditorView] / [PdfReader] shells, which carry all the PDF chrome
/// (search, page number, panels, toolbar). The screen supplies the edit
/// sessions, file handling, and app-side wiring.
class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.prefs});

  final PdfEditingPreferences prefs;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  PdfEditingPreferences get _prefs => widget.prefs;

  final List<DocumentTab> _tabs = [];
  int _activeIndex = 0;

  DocumentTab? get _active =>
      _tabs.isEmpty ? null : _tabs[_activeIndex.clamp(0, _tabs.length - 1)];

  /// Whole-app read-only toggle: swaps [PdfEditorView] for [PdfReader].
  bool _readOnly = false;

  @override
  void dispose() {
    for (final tab in _tabs) {
      tab.dispose();
    }
    super.dispose();
  }

  // --- opening -------------------------------------------------------------

  /// Opens [bytes] in a brand-new tab and makes it active.
  void _openBytes(Uint8List bytes, String title, {String? originPath}) {
    setState(() {
      _tabs.add(DocumentTab.document(
        title: title,
        bytes: bytes,
        preferences: _prefs,
        originPath: originPath,
      ));
      _activeIndex = _tabs.length - 1;
    });
  }

  void _openError(String title, String error) {
    setState(() {
      _tabs.add(DocumentTab.error(title: title, error: error));
      _activeIndex = _tabs.length - 1;
    });
  }

  Future<void> _pickAndOpen() async {
    try {
      final picked = await pickPdf();
      if (picked == null) return;
      _openBytes(picked.bytes, picked.name, originPath: picked.path);
    } catch (e) {
      _openError('Open failed', 'Could not open the selected file\n$e');
    }
  }

  /// Opens a second PDF and compares it against the active document in a new
  /// tab. The active document is the "before".
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

  /// Disposes the tab at [index] and drops it, keeping a sensible tab active.
  /// Controllers are torn down after the frame so the outgoing viewer detaches
  /// from them cleanly first.
  void _closeTab(int index) {
    final tab = _tabs[index];
    setState(() {
      _tabs.removeAt(index);
      if (_activeIndex >= _tabs.length) _activeIndex = _tabs.length - 1;
      if (_activeIndex < 0) _activeIndex = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => tab.dispose());
  }

  // --- saving --------------------------------------------------------------

  Future<void> _save(Uint8List bytes) async {
    final result = await saveBytesAs(context, bytes, _active?.title ?? 'document');
    if (!mounted) return;
    if (result.message != null) _toast(result.message!);
  }

  // --- link actions --------------------------------------------------------

  /// GoTo and the standard named page actions never reach here (the viewer
  /// follows them itself). URI links open in the system browser; anything
  /// else is surfaced in a snackbar.
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

  /// App entries in the annotation right-click menu — a "Copy text" action
  /// when the clicked annotation carries any.
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
        title: Text(
          tab == null || tab.title.isEmpty ? 'dart-pdf Editor' : tab.title,
          overflow: TextOverflow.ellipsis,
        ),
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
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(_readOnly ? Icons.edit_off : Icons.edit),
            tooltip: _readOnly
                ? 'Read-only — tap to edit'
                : 'Editing — tap for read-only',
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
          if (tab?.session != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.compare_arrows),
              tooltip: 'Compare with another PDF…',
              onPressed: _compareWith,
            ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.folder_open),
            tooltip: 'Open PDF in a new tab',
            onPressed: _pickAndOpen,
          ),
        ],
      ),
      body: tab == null
          ? _buildEmptyState()
          : tab.error != null
              ? Center(child: Text(tab.error!, textAlign: TextAlign.center))
              : tab.isComparison
                  ? PdfComparisonView(
                      key: ValueKey(tab),
                      before: tab.compareBefore!,
                      after: tab.compareAfter!,
                    )
                  : _readOnly
                      ? PdfReader(
                          key: ValueKey(tab),
                          bytes: tab.session!.bytes,
                          documentId: tab.documentId,
                          controller: tab.viewer,
                          preferences: _prefs,
                          onAction: _onAction,
                        )
                      : PdfEditorView(
                          key: ValueKey(tab),
                          documentId: tab.documentId,
                          controller: tab.session,
                          viewerController: tab.viewer,
                          onSave: (saved) => unawaited(_save(saved)),
                          onPickPdfToInsert: pickPdfBytes,
                          onExportPages: (bytes) => unawaited(_save(bytes)),
                          onAction: _onAction,
                          annotationMenuBuilder: _annotationMenuActions,
                          formImagePicker: (context, field) => pickImageBytes(),
                          imagePicker: (context) => pickImageBytes(),
                        ),
    );
  }

  Widget _buildEmptyState() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.picture_as_pdf_outlined,
                size: 72, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text('dart-pdf Editor',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _pickAndOpen,
              icon: const Icon(Icons.folder_open),
              label: const Text('Open a PDF'),
            ),
          ],
        ),
      );

  Widget _buildTabStrip() {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: SizedBox(
        height: _tabStripHeight,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          itemCount: _tabs.length + 1,
          itemBuilder: (context, i) => i < _tabs.length
              ? _buildTab(i)
              : IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.add),
                  tooltip: 'Open PDF in a new tab',
                  onPressed: _pickAndOpen,
                ),
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
