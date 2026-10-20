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
// * the presenter: CupertinoEditorPresenter shows menus as action sheets,
//   confirmations and text prompts as alert dialogs, and notices as a
//   toast.
//
// Run it with:
//   fvm flutter run -t lib/cupertino_host.dart
//
// Icons come from the commands' IconData (Material glyphs, bundled by
// uses-material-design) - CupertinoIcons would need the cupertino_icons
// package, which the editor does not depend on.

import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
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
          presenter: const CupertinoEditorPresenter(),
          onSave: (_) {
            setState(() => _saves++);
            const CupertinoEditorPresenter().notice(
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

/// A [PdfEditorPresenter] in Cupertino style. It overrides only the "how"
/// methods a Cupertino app would restyle; everything else (the stock
/// dialogs, pickers, sheets) keeps the editor's own UI, which runs under a
/// CupertinoApp as is.
class CupertinoEditorPresenter extends PdfEditorPresenter {
  const CupertinoEditorPresenter();

  @override
  Future<T?> menu<T>(BuildContext context, PdfMenuRequest<T> request) =>
      showCupertinoModalPopup<T>(
        context: context,
        builder: (context) => CupertinoActionSheet(
          key: const ValueKey('cupertino-menu'),
          actions: [
            for (final entry in request.entries)
              if (entry is PdfMenuItem<T> && entry.value != null)
                CupertinoActionSheetAction(
                  key: entry.key,
                  onPressed: entry.enabled
                      ? () => Navigator.of(context).pop(entry.value)
                      : () {},
                  child: Text(
                    entry.checked == true ? '✓ ${entry.label}' : entry.label,
                    style: entry.enabled
                        ? null
                        : const TextStyle(color: CupertinoColors.inactiveGray),
                  ),
                ),
          ],
          cancelButton: CupertinoActionSheetAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(context).pop(),
            child: Text(pdfL10n(context).cancel),
          ),
        ),
      );

  @override
  Future<bool> confirm(BuildContext context, PdfConfirmRequest request) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        key: request.key,
        title: Text(request.title),
        content: Text(request.message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(pdfL10n(context).cancel),
          ),
          CupertinoDialogAction(
            key: request.confirmKey,
            isDestructiveAction: request.destructive,
            isDefaultAction: !request.destructive,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(request.confirmLabel),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  @override
  Future<String?> text(BuildContext context, PdfTextRequest request) =>
      showCupertinoDialog<String>(
        context: context,
        builder: (context) => _CupertinoTextPrompt(request: request),
      );

  @override
  bool notice(BuildContext context, PdfEditorNotice notice) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return false;
    late final OverlayEntry entry;
    var removed = false;
    void remove() {
      if (removed) return;
      removed = true;
      entry.remove();
      entry.dispose();
    }

    entry = OverlayEntry(
      builder: (context) => _CupertinoToast(notice: notice, onDone: remove),
    );
    overlay.insert(entry);
    return true;
  }
}

class _CupertinoTextPrompt extends StatefulWidget {
  const _CupertinoTextPrompt({required this.request});

  final PdfTextRequest request;

  @override
  State<_CupertinoTextPrompt> createState() => _CupertinoTextPromptState();
}

class _CupertinoTextPromptState extends State<_CupertinoTextPrompt> {
  late final _text = TextEditingController(text: widget.request.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_text.text);

  @override
  Widget build(BuildContext context) => CupertinoAlertDialog(
        key: const ValueKey('cupertino-text-prompt'),
        title: Text(widget.request.title),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            key: const ValueKey('cupertino-text-field'),
            controller: _text,
            autofocus: true,
            minLines: widget.request.multiline ? 3 : 1,
            maxLines: widget.request.multiline ? 6 : 1,
            onSubmitted: widget.request.multiline ? null : (_) => _submit(),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(pdfL10n(context).cancel),
          ),
          CupertinoDialogAction(
            key: const ValueKey('cupertino-text-ok'),
            isDefaultAction: true,
            onPressed: _submit,
            child: Text(pdfL10n(context).ok),
          ),
        ],
      );
}

/// A rounded toast above the bottom edge, with Undo when the notice can be
/// undone.
class _CupertinoToast extends StatefulWidget {
  const _CupertinoToast({required this.notice, required this.onDone});

  final PdfEditorNotice notice;
  final VoidCallback onDone;

  @override
  State<_CupertinoToast> createState() => _CupertinoToastState();
}

class _CupertinoToastState extends State<_CupertinoToast> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(
        widget.notice.duration ?? const Duration(seconds: 3), widget.onDone);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onUndo = widget.notice.onUndo;
    final lift = PdfEditorThemeData.of(context).toastLift ?? 96;
    return Positioned(
      left: 24,
      right: 24,
      bottom: lift + MediaQuery.paddingOf(context).bottom,
      child: Center(
        child: DecoratedBox(
          key: const ValueKey('cupertino-toast'),
          decoration: BoxDecoration(
            color: const Color(0xE6303030),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                child: Text(
                  widget.notice.message,
                  style: const TextStyle(
                      color: CupertinoColors.white, fontSize: 15),
                ),
              ),
              if (onUndo != null)
                CupertinoButton(
                  padding: const EdgeInsets.only(left: 12),
                  minimumSize: const Size(0, 32),
                  onPressed: () {
                    widget.onDone();
                    onUndo();
                  },
                  child: Text(pdfL10n(context).undo),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
