// The example's Cupertino design: the editor in a CupertinoApp. The user
// switches to it from the Material app menu ("Switch to Cupertino design")
// and back from this design's Settings page; the choice is saved.
//
// Nothing here forks the editor. The page canvas, the overlays and the stock
// panels are the library's own; the host only swaps the surfaces around
// them, through public seams:
//
// * the header: PdfEditorView.headerBuilder gets the stock PdfHeaderParts
//   (page number, search, save, ...) and places them in a
//   CupertinoNavigationBar;
// * the toolbar: PdfEditorView.toolbarBuilder lays out the command catalog
//   (PdfEditorCommands.of(context).catalog) as a row of CupertinoButtons -
//   arming a tool through a command runs its prerequisites (the measuring
//   scale, the signature capture) exactly like the stock toolbar;
// * the presenter: the library's PdfCupertinoPresenter
//   (package:dart_pdf_editor/cupertino.dart) shows menus as action sheets,
//   prompts as alert dialogs, form choices as pickers, sheets as modal
//   popups and notices as a toast.
//
// The documents are not this host's: they live in the app-wide
// ExampleWorkspace (workspace.dart), above the app root, so switching design
// re-attaches the same edit sessions instead of reopening anything.
//
// Run the example straight into this design with:
//   fvm flutter run -t lib/cupertino_host.dart
//
// Icons come from material_ui's Icons (bundled by uses-material-design) -
// CupertinoIcons would need the cupertino_icons package, which the editor
// does not depend on.

import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:dart_pdf_editor/cupertino.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show Uint8List;
// Only the widgets delegate: flutter_localizations' Cupertino delegate is the
// legacy one, so cupertino_ui's GlobalCupertinoLocalizations is used instead.
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:material_ui/material_ui.dart' show Icons;

import 'demo_document.dart';
import 'l10n/app_l10n.dart';
import 'l10n/app_localizations.dart';
import 'main.dart' show pdfSaveFileName, pdfTypeGroup, runExample, savePdfBytes;
import 'workspace.dart';

/// Starts the example in the Cupertino design (and saves that choice).
void main() => runExample(initialDesign: ExampleDesign.cupertino);

/// The example's Cupertino app root: a [CupertinoApp] around
/// [CupertinoEditorScreen], following the saved light/dark choice (system by
/// default, so the platform brightness).
class CupertinoEditorApp extends StatelessWidget {
  const CupertinoEditorApp({
    super.key,
    required this.prefs,
    required this.design,
    required this.workspace,
    this.initialBytes,
  });

  final PdfEditingPreferences prefs;
  final ExampleDesignPreference design;
  final ExampleWorkspace workspace;

  /// The launch document when this design is the first on screen; the
  /// feature-showcase demo when null.
  final Uint8List? initialBytes;

  @override
  Widget build(BuildContext context) => CupertinoApp(
        title: 'dart-pdf viewer',
        debugShowCheckedModeBanner: false,
        theme: CupertinoThemeData(
          // null follows the platform brightness
          brightness: switch (prefs.themePreference) {
            PdfThemePreference.system => null,
            PdfThemePreference.light => Brightness.light,
            PdfThemePreference.dark => Brightness.dark,
          },
        ),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          DartPdfEditorLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: CupertinoEditorScreen(
          prefs: prefs,
          design: design,
          workspace: workspace,
          initialBytes: initialBytes,
        ),
      );
}

/// The active document in a Cupertino page: nav bar from the header parts,
/// a command toolbar, and the Cupertino presenter.
class CupertinoEditorScreen extends StatefulWidget {
  const CupertinoEditorScreen({
    super.key,
    required this.prefs,
    required this.design,
    required this.workspace,
    this.initialBytes,
  });

  final PdfEditingPreferences prefs;
  final ExampleDesignPreference design;
  final ExampleWorkspace workspace;
  final Uint8List? initialBytes;

  @override
  State<CupertinoEditorScreen> createState() => _CupertinoEditorScreenState();
}

class _CupertinoEditorScreenState extends State<CupertinoEditorScreen> {
  static const _presenter = PdfCupertinoPresenter();

  ExampleWorkspace get _workspace => widget.workspace;

  @override
  void initState() {
    super.initState();
    // Like the Material screen: open the launch document once per app run,
    // never again on a switch back into this design.
    if (_workspace.launched) return;
    _workspace.launched = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final initial = widget.initialBytes;
      if (initial != null) {
        _open(initial, 'document.pdf');
      } else {
        _openDemo();
      }
    });
  }

  void _open(Uint8List bytes, String title, {bool isDemo = false}) {
    setState(() {
      _workspace.tabs.add(DocumentTab.document(
        title: title,
        bytes: bytes,
        preferences: widget.prefs,
        isDemo: isDemo,
      ));
      _workspace.activeIndex = _workspace.tabs.length - 1;
    });
  }

  void _openDemo() =>
      _open(buildDemoPdf(), appL10n(context).exFeatureShowcase, isDemo: true);

  Future<void> _pickFile() async {
    final file = await openFile(
        acceptedTypeGroups: [pdfTypeGroup(appL10n(context).exFileTypePdf)]);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (mounted) _open(bytes, file.name);
  }

  void _activate(int index) => setState(() => _workspace.activeIndex = index);

  Future<void> _save(DocumentTab tab, Uint8List bytes) async {
    final message =
        await savePdfBytes(context, bytes, pdfSaveFileName(tab.title));
    if (message == null || !mounted) return;
    _presenter.notice(context, PdfEditorNotice(message));
  }

  void _openSettings(BuildContext context) {
    unawaited(Navigator.of(context).push(CupertinoPageRoute<void>(
      builder: (_) => CupertinoSettingsPage(
        prefs: widget.prefs,
        design: widget.design,
        workspace: _workspace,
        onActivate: _activate,
        onOpenDemo: _openDemo,
        onOpenFile: () => unawaited(_pickFile()),
      ),
    )));
  }

  @override
  Widget build(BuildContext context) {
    final tab = _workspace.active;
    final l10n = appL10n(context);
    final settings = _SettingsButton(onPressed: () => _openSettings(context));
    Widget simplePage(Widget child) => CupertinoPageScaffold(
          navigationBar: CupertinoNavigationBar(
            automaticallyImplyLeading: false,
            middle: Text(tab?.title ?? 'dart-pdf viewer'),
            trailing: settings,
          ),
          child: SafeArea(child: Center(child: child)),
        );
    if (tab == null) {
      return simplePage(Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CupertinoButton.filled(
            onPressed: () => unawaited(_pickFile()),
            child: Text(l10n.exOpenPdfButton),
          ),
          const SizedBox(height: 12),
          CupertinoButton(onPressed: _openDemo, child: Text(l10n.exTryDemo)),
        ],
      ));
    }
    if (tab.isLoading) return simplePage(const CupertinoActivityIndicator());
    if (tab.error != null) {
      return simplePage(Text(tab.error!, textAlign: TextAlign.center));
    }
    if (tab.isComparison) {
      return CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          automaticallyImplyLeading: false,
          middle: Text(tab.title),
          trailing: settings,
        ),
        child: SafeArea(
          child: PdfMaterialHost(
            child: PdfComparisonView(
              key: ValueKey(tab),
              before: tab.compareBefore!,
              after: tab.compareAfter!,
            ),
          ),
        ),
      );
    }
    return CupertinoPageScaffold(
      child: PdfEditorView(
        // per tab and worker configuration, like the Material screen
        key: ValueKey<Object>((tab, 'cupertino', _workspace.workerConfigEpoch)),
        documentId: tab.title,
        // the workspace's session: edits made under either design live here
        controller: tab.session,
        viewerController: tab.viewer,
        performance: _workspace.performance,
        presenter: _presenter,
        onSave: (bytes) => unawaited(_save(tab, bytes)),
        alwaysAllowSave: tab.isExtracted,
        // the stock tool groups and panels stay; only the surfaces change
        headerBuilder: (context, parts) =>
            _CupertinoHeader(parts: parts, settings: settings),
        toolbarBuilder: (context, controller, viewer) =>
            const CupertinoCommandBar(),
      ),
    );
  }
}

class _SettingsButton extends StatelessWidget {
  const _SettingsButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = appL10n(context).exSettings;
    return Semantics(
      label: label,
      button: true,
      child: CupertinoButton(
        key: const ValueKey('cupertino-settings'),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(44, 44),
        onPressed: onPressed,
        child: Icon(Icons.settings_outlined,
            size: 22, color: CupertinoTheme.of(context).primaryColor),
      ),
    );
  }
}

/// The editor's header as a [CupertinoNavigationBar], with the host's
/// Settings button at the end.
class _CupertinoHeader extends StatelessWidget {
  const _CupertinoHeader({required this.parts, required this.settings});

  final PdfHeaderParts parts;
  final Widget settings;

  /// Below this width the nav bar has no room for the search field beside
  /// the panel switch and the controls; search stays one tap away in the
  /// search panel.
  static const _searchMinWidth = 1000.0;

  @override
  Widget build(BuildContext context) => CupertinoNavigationBar(
        key: const ValueKey('cupertino-nav-bar'),
        automaticallyImplyLeading: false,
        // No Hero flight into the settings page: the flight rebuilds the
        // bar in the navigator overlay, outside the editor's Material
        // surface, and the stock page-number and search fields need one.
        transitionBetweenRoutes: false,
        leading: parts.pageNumber,
        middle:
            parts.compact || MediaQuery.sizeOf(context).width < _searchMinWidth
                ? null
                : parts.search,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!parts.compact && parts.panelSwitch != null) parts.panelSwitch!,
            if (parts.save != null) parts.save!,
            if (parts.controls(includeSave: false) case final controls?)
              controls,
            settings,
          ],
        ),
      );
}

/// The Cupertino design's settings: the design switch (back to Material),
/// light/dark appearance, and the open documents.
class CupertinoSettingsPage extends StatelessWidget {
  const CupertinoSettingsPage({
    super.key,
    required this.prefs,
    required this.design,
    required this.workspace,
    required this.onActivate,
    required this.onOpenDemo,
    required this.onOpenFile,
  });

  final PdfEditingPreferences prefs;
  final ExampleDesignPreference design;
  final ExampleWorkspace workspace;
  final ValueChanged<int> onActivate;
  final VoidCallback onOpenDemo;
  final VoidCallback onOpenFile;

  @override
  Widget build(BuildContext context) {
    final l10n = appL10n(context);
    final check = Icon(Icons.check,
        size: 20, color: CupertinoTheme.of(context).primaryColor);
    Widget option(
      Key key,
      String title, {
      required bool selected,
      required VoidCallback onTap,
    }) =>
        CupertinoListTile(
          key: key,
          title: Text(title),
          trailing: selected ? check : null,
          onTap: onTap,
        );
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        // the implied back button draws a CupertinoIcons glyph, a font the
        // example does not bundle
        automaticallyImplyLeading: false,
        leading: CupertinoButton(
          key: const ValueKey('cupertino-settings-back'),
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).maybePop(),
          child: Icon(Icons.arrow_back_ios_new,
              size: 20, color: CupertinoTheme.of(context).primaryColor),
        ),
        middle: Text(l10n.exSettings),
      ),
      child: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([prefs, design]),
          builder: (context, _) => ListView(
            children: [
              CupertinoListSection.insetGrouped(
                header: Text(l10n.exDesignSection),
                footer: Text(l10n.exDesignFooter),
                children: [
                  option(
                    const ValueKey('cupertino-design-material'),
                    l10n.exDesignMaterial,
                    selected: design.value == ExampleDesign.material,
                    // swaps the app root; this page goes with it
                    onTap: () => design.value = ExampleDesign.material,
                  ),
                  option(
                    const ValueKey('cupertino-design-cupertino'),
                    l10n.exDesignCupertino,
                    selected: design.value == ExampleDesign.cupertino,
                    onTap: () => design.value = ExampleDesign.cupertino,
                  ),
                ],
              ),
              CupertinoListSection.insetGrouped(
                header: Text(l10n.exAppearanceSection),
                children: [
                  for (final (value, label) in [
                    (PdfThemePreference.system, l10n.exAppearanceSystem),
                    (PdfThemePreference.light, l10n.exAppearanceLight),
                    (PdfThemePreference.dark, l10n.exAppearanceDark),
                  ])
                    option(
                      ValueKey('cupertino-appearance-${value.name}'),
                      label,
                      selected: prefs.themePreference == value,
                      onTap: () => prefs.themePreference = value,
                    ),
                ],
              ),
              CupertinoListSection.insetGrouped(
                header: Text(l10n.exOpenDocumentsSection),
                children: [
                  for (final (i, tab) in workspace.tabs.indexed)
                    option(
                      ValueKey('cupertino-document-$i'),
                      tab.title.isEmpty ? l10n.exUntitled : tab.title,
                      selected: identical(tab, workspace.active),
                      onTap: () {
                        onActivate(i);
                        Navigator.of(context).pop();
                      },
                    ),
                  CupertinoListTile(
                    key: const ValueKey('cupertino-open-pdf'),
                    title: Text(l10n.exOpenPdf),
                    onTap: () {
                      Navigator.of(context).pop();
                      onOpenFile();
                    },
                  ),
                  CupertinoListTile(
                    key: const ValueKey('cupertino-open-demo'),
                    title: Text(l10n.exOpenInteractiveDemo),
                    onTap: () {
                      Navigator.of(context).pop();
                      onOpenDemo();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The editing toolbar, built from [PdfEditorCommands.catalog]: one
/// [CupertinoButton] per tool, highlighted while armed.
class CupertinoCommandBar extends StatelessWidget {
  const CupertinoCommandBar({super.key});

  @override
  Widget build(BuildContext context) {
    final commands = PdfEditorCommands.of(context);
    return ListenableBuilder(
      listenable: commands,
      builder: (context, _) {
        final tools = [
          for (final command in commands.catalog(context))
            if (command.category == PdfCommandCategory.tool) command,
        ];
        return Container(
          key: const ValueKey('cupertino-command-bar'),
          decoration: BoxDecoration(
            color: CupertinoTheme.of(context).barBackgroundColor,
            border: const Border(
                top: BorderSide(color: Color(0x4D000000), width: 0)),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  for (final command in tools) _CommandButton(command),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CommandButton extends StatelessWidget {
  const _CommandButton(this.command);

  final PdfCommand command;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: command.selected,
        builder: (context, selected, _) => ValueListenableBuilder<bool>(
          valueListenable: command.enabled,
          builder: (context, enabled, _) {
            final theme = CupertinoTheme.of(context);
            return Semantics(
              label: command.label(context),
              selected: selected,
              button: true,
              child: CupertinoButton(
                key: ValueKey('cupertino-${command.id}'),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(44, 44),
                color: selected ? theme.primaryColor : null,
                onPressed:
                    enabled ? () => unawaited(command.invoke(context)) : null,
                child: Icon(
                  command.icon,
                  size: 22,
                  color: selected
                      ? theme.primaryContrastingColor
                      : theme.primaryColor,
                ),
              ),
            );
          },
        ),
      );
}
