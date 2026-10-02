// The editor in a CupertinoApp: the acceptance test for the 5.x UI seams.
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
// Run it with:
//   fvm flutter run -t lib/cupertino_host.dart
//
// Icons come from the commands' IconData (Material glyphs, bundled by
// uses-material-design) - CupertinoIcons would need the cupertino_icons
// package, which the editor does not depend on.

import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:dart_pdf_editor/cupertino.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
// Only the widgets delegate: flutter_localizations' Cupertino delegate is the
// legacy one, so cupertino_ui's GlobalCupertinoLocalizations is used instead.
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;

import 'demo_document.dart';

void main() => runApp(const CupertinoHostApp());

/// A CupertinoApp hosting [CupertinoEditorScreen] on the demo document.
class CupertinoHostApp extends StatelessWidget {
  const CupertinoHostApp({super.key, this.bytes});

  /// The document to open; the feature-showcase demo PDF when null.
  final Uint8List? bytes;

  @override
  Widget build(BuildContext context) => CupertinoApp(
        title: 'DartPDF (Cupertino host)',
        debugShowCheckedModeBanner: false,
        localizationsDelegates: const [
          DartPdfEditorLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: DartPdfEditorLocalizations.supportedLocales,
        home: CupertinoEditorScreen(bytes: bytes ?? buildDemoPdf()),
      );
}

/// One document in a Cupertino page: nav bar from the header parts, a
/// command toolbar, and the Cupertino presenter.
class CupertinoEditorScreen extends StatefulWidget {
  const CupertinoEditorScreen({super.key, required this.bytes});

  final Uint8List bytes;

  @override
  State<CupertinoEditorScreen> createState() => _CupertinoEditorScreenState();
}

class _CupertinoEditorScreenState extends State<CupertinoEditorScreen> {
  int _saves = 0;

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
        child: PdfEditorView(
          bytes: widget.bytes,
          presenter: const PdfCupertinoPresenter(),
          onSave: (_) {
            setState(() => _saves++);
            const PdfCupertinoPresenter().notice(
              context,
              PdfEditorNotice('Saved ($_saves)', kind: PdfNoticeKind.success),
            );
          },
          alwaysAllowSave: true,
          // the stock tool groups and panels stay; only the surfaces change
          headerBuilder: (context, parts) => _CupertinoHeader(parts: parts),
          toolbarBuilder: (context, controller, viewer) =>
              const CupertinoCommandBar(),
        ),
      );
}

/// The editor's header as a [CupertinoNavigationBar].
class _CupertinoHeader extends StatelessWidget {
  const _CupertinoHeader({required this.parts});

  final PdfHeaderParts parts;

  @override
  Widget build(BuildContext context) => CupertinoNavigationBar(
        key: const ValueKey('cupertino-nav-bar'),
        automaticallyImplyLeading: false,
        leading: parts.pageNumber,
        middle: parts.compact ? null : parts.search,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!parts.compact && parts.panelSwitch != null) parts.panelSwitch!,
            if (parts.save != null) parts.save!,
            if (parts.controls(includeSave: false) case final controls?)
              controls,
          ],
        ),
      );
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
