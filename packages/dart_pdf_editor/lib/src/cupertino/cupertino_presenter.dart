// PdfCupertinoPresenter: the editor's dialogs, sheets, menus, notices and
// prompts in iOS style, on cupertino_ui. Exported only by
// package:dart_pdf_editor/cupertino.dart, so Material hosts never compile it.
//
// Glyphs come from the Material Icons font the stock chrome already bundles
// (uses-material-design), never CupertinoIcons: that font ships only with the
// cupertino_icons package, which the editor does not depend on.

import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart'
    show Icons, Material, MaterialType;
import 'package:pdf_document/pdf_document.dart' show PdfPageRange;

import '../design/editor_presenter.dart';
import '../design/material_host.dart' show pdfHostRoute;
import '../dialog.dart';
import '../editing/editing_controller.dart' show PdfLinkTarget;
import '../editing/models/measurement_scale.dart';
import '../editing/text_style_prompt.dart' show PdfStyledTextEdit;
import '../l10n/pdf_l10n.dart';
import '../toast.dart' show pdfFloatingToastMargin;
import 'cupertino_prompts.dart';

/// A [PdfEditorPresenter] in iOS style, built on `cupertino_ui`:
///
/// * [dialog]: every stock dialog on a `CupertinoDialogRoute` (the iOS
///   fade-and-scale entrance, the Cupertino barrier), Enter-to-submit and
///   host re-injection kept;
/// * [confirm], [text], [styledText], [link], [pageRange], [splitRanges],
///   [measurementScale] and [measurementInput]: `CupertinoAlertDialog`s with
///   `CupertinoTextField`s, sliding segmented controls and sliders;
/// * [menu]: a `CupertinoActionSheet` (see [menu] for why not a
///   `CupertinoContextMenu`);
/// * [formChoice]: a `CupertinoPicker` (single-select) or a checklist
///   (multi-select) in a modal popup with Cancel and Done;
/// * [sheet]: a modal popup sliding up from the bottom
///   (`CupertinoModalPopupRoute`);
/// * [notice]: a toast in the root overlay with Undo;
/// * [actionBar] and [readout]: dark iOS edit-menu style capsules.
///
/// [color], [font] and [signature] keep the stock pickers (a full colour
/// picker, the searchable font catalogue and the signature pad are not
/// worth duplicating); they open on this presenter's Cupertino dialog route,
/// and `PdfMaterialHost` supplies what they need under a `CupertinoApp`.
///
/// Text fields in its prompts use [pdfCupertinoTextContextMenu]: the system
/// menu where the platform offers one, else the Cupertino toolbar. The
/// prompts carry the stock prompts' `pdf-*` keys, so finders and integration
/// tests work under either presenter.
///
/// Works under any host - a `CupertinoApp` with no `MaterialApp` at all
/// included. Extend it to change one method and keep the rest.
class PdfCupertinoPresenter extends PdfEditorPresenter {
  /// The Cupertino presenter.
  const PdfCupertinoPresenter();

  // ---- how ---------------------------------------------------------------

  /// Shows [request]'s dialog on a `CupertinoDialogRoute`. The content is
  /// the dialog the request builds (a Material one for the stock dialogs
  /// this presenter does not restyle), with the same Enter-to-submit
  /// handling and host re-injection as [showPdfDialog].
  @override
  Future<T?> dialog<T>(BuildContext context, PdfDialogRequest<T> request) {
    final navigator = Navigator.of(context, rootNavigator: true);
    final themes = InheritedTheme.capture(from: context, to: navigator.context);
    final scope = PdfEditorScope.maybeOf(context, listen: false);
    return navigator.push<T>(CupertinoDialogRoute<T>(
      context: context,
      barrierDismissible: request.barrierDismissible,
      barrierLabel: pdfL10n(context).dialogDismiss,
      barrierColor:
          CupertinoDynamicColor.resolve(kCupertinoModalBarrierColor, context),
      builder: (routeContext) => themes
          .wrap(pdfDialogRouteContent(routeContext, request.builder, scope)),
    ));
  }

  /// Shows the sheet as a modal popup sliding up from the bottom edge, on a
  /// rounded system-background surface (with a grabber when
  /// [PdfSheetRequest.showDragHandle]). Its height is capped at
  /// [PdfSheetRequest.maxHeightFactor] of the screen, else 9/16 of it
  /// (nearly all of it for a [PdfSheetRequest.scrollControlled] sheet).
  @override
  Future<T?> sheet<T>(BuildContext context, PdfSheetRequest<T> request) {
    final height = MediaQuery.sizeOf(context).height;
    final factor =
        request.maxHeightFactor ?? (request.scrollControlled ? 0.92 : 9 / 16);
    return pdfCupertinoPopup<T>(
      context,
      (context) => CupertinoSheetSurface(
        key: const ValueKey('pdf-cupertino-sheet'),
        maxHeight: height * factor,
        showDragHandle: request.showDragHandle,
        // stock sheet content is Material (list tiles, switches): give it a
        // surface to draw ink on
        child: Material(
          type: MaterialType.transparency,
          child: Builder(builder: request.builder),
        ),
      ),
    );
  }

  /// Shows the menu as a `CupertinoActionSheet` with a Cancel button,
  /// resolving to the picked row's value.
  ///
  /// Not a `CupertinoContextMenu`: that widget lifts a preview of a child it
  /// wraps and opens on a long press of it, while the editor asks for a menu
  /// at a rectangle (a right-click, a toolbar button, a selection) with no
  /// widget to lift. An action sheet is the iOS presentation for a set of
  /// choices about the current context.
  ///
  /// A checkable row shows a check mark; a disabled row is greyed and does
  /// nothing; a row without a value (a section label, an embedded control)
  /// draws its [PdfMenuItem.child], or its label as a caption. Dividers are
  /// dropped: the sheet separates every action already.
  @override
  Future<T?> menu<T>(BuildContext context, PdfMenuRequest<T> request) =>
      pdfCupertinoPopup<T>(
        context,
        (context) => CupertinoActionSheet(
          key: const ValueKey('pdf-cupertino-menu'),
          actions: [
            for (final entry in request.entries)
              if (entry is PdfMenuItem<T>) _menuRow<T>(context, entry),
          ],
          cancelButton: CupertinoActionSheetAction(
            key: const ValueKey('pdf-cupertino-menu-cancel'),
            isDefaultAction: true,
            onPressed: () => Navigator.of(context).pop(),
            child: Text(pdfL10n(context).cancel),
          ),
        ),
      );

  /// Shows the notice as a toast in the root overlay: a dark capsule with
  /// the message, Undo when it can be undone and a close button when it
  /// asks for one. One at a time, like the stock notice; false only without
  /// an overlay.
  @override
  bool notice(BuildContext context, PdfEditorNotice notice) =>
      _CupertinoToast.show(context, notice);

  /// The action bar as a dark iOS edit-menu capsule: labels for the text
  /// selection chip, icons (where the stock chip has them) for the
  /// annotation selection and crop bars; a group opens its actions as a
  /// [menu]. Each button keeps its action's `pdf-*` id as its key.
  @override
  Widget actionBar(BuildContext context, PdfActionBarRequest request) =>
      _CupertinoActionBar(presenter: this, request: request);

  /// The readout as a small dark capsule.
  @override
  Widget readout(BuildContext context, PdfReadoutRequest request) =>
      _CupertinoCapsule(
        key: const ValueKey('pdf-cupertino-readout'),
        radius: 8,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Text(
            request.text,
            style: const TextStyle(
              color: CupertinoColors.white,
              fontSize: 13,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      );

  // ---- prompts ------------------------------------------------------------

  /// A `CupertinoAlertDialog` with Cancel and confirm actions; a
  /// [PdfConfirmRequest.destructive] confirmation is drawn in red.
  @override
  Future<bool> confirm(BuildContext context, PdfConfirmRequest request) async {
    final confirmed = await _present<bool>(
      context,
      builder: (context) {
        void yes() => Navigator.of(context).pop(true);
        return CupertinoAlertDialog(
          key: request.key,
          title: Text(request.title),
          content: Text(request.message),
          actions: [
            CupertinoDialogAction(
              key: const ValueKey('pdf-cupertino-confirm-cancel'),
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(pdfL10n(context).cancel),
            ),
            PdfDialogSubmit.action(
              onSubmit: yes,
              child: CupertinoDialogAction(
                key: request.confirmKey,
                isDestructiveAction: request.destructive,
                isDefaultAction: !request.destructive,
                onPressed: yes,
                child: Text(request.confirmLabel),
              ),
            ),
          ],
        );
      },
    );
    return confirmed == true;
  }

  /// A `CupertinoAlertDialog` around a `CupertinoTextField`.
  @override
  Future<String?> text(BuildContext context, PdfTextRequest request) =>
      _present<String>(context,
          builder: (context) => CupertinoTextPrompt(request: request));

  /// A `CupertinoAlertDialog` with the text, a size slider, the font (the
  /// request's font picker, else a Sans/Serif/Mono segmented control),
  /// Bold/Italic toggles and the fill swatches. Every override stays unset
  /// until its control is touched, like the stock prompt.
  @override
  Future<PdfStyledTextEdit?> styledText(
          BuildContext context, PdfStyledTextRequest request) =>
      _present<PdfStyledTextEdit>(context,
          builder: (context) => CupertinoStyledTextPrompt(request: request));

  /// A `CupertinoAlertDialog` with a Web address / Page segmented control
  /// over the matching `CupertinoTextField`.
  @override
  Future<PdfLinkTarget?> link(BuildContext context, PdfLinkRequest request) =>
      _present<PdfLinkTarget>(context,
          builder: (context) => CupertinoLinkPrompt(request: request));

  /// A `CupertinoPicker` (single-select) or a checklist (multi-select) in a
  /// modal popup with Cancel and Done; Done resolves to the whole new
  /// selection. Option rows are keyed
  /// `'${PdfFormChoiceRequest.optionKeyPrefix}$export'`.
  @override
  Future<List<String>?> formChoice(
          BuildContext context, PdfFormChoiceRequest request) =>
      pdfCupertinoPopup<List<String>>(
          context, (context) => CupertinoFormChoice(request: request));

  /// A `CupertinoAlertDialog` reading "1 [in] = [value] [ft]"; the units
  /// open as action sheets ([menu]). Offers Calibrate when the request
  /// does.
  @override
  Future<PdfMeasurementScale?> measurementScale(
          BuildContext context, PdfMeasurementScaleRequest request) =>
      _present<PdfMeasurementScale>(context,
          builder: (context) =>
              CupertinoScalePrompt(presenter: this, request: request));

  /// A `CupertinoAlertDialog` asking for the calibration segment's real
  /// length (with a unit button) or the volume's depth.
  @override
  Future<PdfMeasurementInput?> measurementInput(
          BuildContext context, PdfMeasurementInputRequest request) =>
      _present<PdfMeasurementInput>(context,
          builder: (context) => CupertinoMeasurementInputPrompt(
              presenter: this, request: request));

  /// A `CupertinoAlertDialog` with From and To fields (1-based on screen,
  /// 0-based in the result) and an inline error.
  @override
  Future<({int start, int end})?> pageRange(
          BuildContext context, PdfPageRangeRequest request) =>
      _present<({int start, int end})>(context,
          builder: (context) => CupertinoPageRangePrompt(request: request));

  /// A `CupertinoAlertDialog` with one ranges field (`1-3, 7, 10-12`) and
  /// an inline error.
  @override
  Future<List<PdfPageRange>?> splitRanges(
          BuildContext context, PdfSplitRangesRequest request) =>
      _present<List<PdfPageRange>>(context,
          builder: (context) => CupertinoSplitPrompt(request: request));

  // color, font and signature: the stock pickers, on [dialog]'s route.

  /// Shows a prompt through this presenter's own [dialog] (not the scope's:
  /// a subclass's dialog override still applies, and a prompt asked outside
  /// any scope is Cupertino too).
  Future<T?> _present<T>(BuildContext context,
          {required WidgetBuilder builder}) =>
      dialog<T>(context, PdfDialogRequest<T>(builder: builder));
}

/// The context menu builder for text fields in the Cupertino prompts: the
/// system menu where the field supports it (iOS 16+), else
/// `CupertinoAdaptiveTextSelectionToolbar` - never the Material toolbar -
/// with whatever the host lacks re-injected (the menu builds in the root
/// overlay). Use it for `CupertinoTextField`s in your own dialogs:
///
/// ```dart
/// CupertinoTextField(contextMenuBuilder: pdfCupertinoTextContextMenu)
/// ```
Widget pdfCupertinoTextContextMenu(
    BuildContext context, EditableTextState editableTextState) {
  final menu = SystemContextMenu.isSupportedByField(editableTextState)
      ? SystemContextMenu.editableText(editableTextState: editableTextState)
      : CupertinoAdaptiveTextSelectionToolbar.editableText(
          key: const ValueKey('pdf-cupertino-text-menu'),
          editableTextState: editableTextState);
  return pdfHostRoute(context, menu, themesFrom: editableTextState.context);
}

/// Pushes [builder]'s content on a `CupertinoModalPopupRoute` on the root
/// navigator, carrying [context]'s themes (and the editor's scope) into it
/// and re-injecting whatever the host lacks.
Future<T?> pdfCupertinoPopup<T>(BuildContext context, WidgetBuilder builder) {
  final navigator = Navigator.of(context, rootNavigator: true);
  final themes = InheritedTheme.capture(from: context, to: navigator.context);
  return navigator.push<T>(CupertinoModalPopupRoute<T>(
    barrierLabel: pdfL10n(context).dialogDismiss,
    barrierColor:
        CupertinoDynamicColor.resolve(kCupertinoModalBarrierColor, context),
    builder: (routeContext) =>
        pdfHostRoute(routeContext, themes.wrap(Builder(builder: builder))),
  ));
}

Widget _menuRow<T>(BuildContext context, PdfMenuItem<T> entry) {
  final value = entry.value;
  if (value == null) {
    // content, not a choice: an embedded control or a section label
    final child = entry.child;
    return Padding(
      key: entry.key,
      padding: entry.padding ??
          const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: child != null
          ? Material(type: MaterialType.transparency, child: child)
          : Text(
              entry.label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
    );
  }
  final enabled = entry.enabled;
  final colour =
      enabled ? null : CupertinoColors.inactiveGray.resolveFrom(context);
  final checked = entry.checked;
  return Semantics(
    enabled: enabled,
    checked: checked,
    child: CupertinoActionSheetAction(
      key: entry.key,
      onPressed: enabled ? () => Navigator.of(context).pop(value) : () {},
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (entry.icon != null) ...[
            Icon(entry.icon, size: 20, color: colour),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              entry.label,
              overflow: TextOverflow.ellipsis,
              style: colour == null ? null : TextStyle(color: colour),
            ),
          ),
          if (checked != null) ...[
            const SizedBox(width: 8),
            // keep the label centred whether or not the row is checked
            Opacity(
              opacity: checked ? 1 : 0,
              child: Icon(Icons.check, size: 20, color: colour),
            ),
          ],
        ],
      ),
    ),
  );
}

/// A bottom sheet's surface: rounded top corners on the system background,
/// an optional grabber, safe-area padding at the bottom.
class CupertinoSheetSurface extends StatelessWidget {
  /// A surface at most [maxHeight] tall holding [child].
  const CupertinoSheetSurface({
    super.key,
    required this.maxHeight,
    required this.showDragHandle,
    required this.child,
  });

  /// The surface's maximum height.
  final double maxHeight;

  /// Whether a grabber is drawn at the top.
  final bool showDragHandle;

  /// The sheet's content.
  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: CupertinoColors.systemBackground.resolveFrom(context),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showDragHandle)
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 6, bottom: 4),
                        width: 36,
                        height: 5,
                        decoration: BoxDecoration(
                          color:
                              CupertinoColors.systemFill.resolveFrom(context),
                          borderRadius: BorderRadius.circular(2.5),
                        ),
                      ),
                    ),
                  Flexible(child: child),
                ],
              ),
            ),
          ),
        ),
      );
}

/// The dark, rounded backdrop of the toast, the action bar and the readout
/// (the iOS edit menu's look).
class _CupertinoCapsule extends StatelessWidget {
  const _CupertinoCapsule({super.key, required this.child, this.radius = 10});

  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: CupertinoDynamicColor.resolve(_capsuleColour, context),
          borderRadius: BorderRadius.circular(radius),
          boxShadow: const [
            BoxShadow(
                color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4)),
          ],
        ),
        child: DefaultTextStyle(
          style: const TextStyle(
              color: CupertinoColors.white, fontSize: 15, inherit: false),
          child: IconTheme(
            data: const IconThemeData(color: CupertinoColors.white, size: 20),
            child: child,
          ),
        ),
      );
}

const _capsuleColour = CupertinoDynamicColor.withBrightness(
  color: Color(0xF0262626),
  darkColor: Color(0xF0484848),
);

class _CupertinoActionBar extends StatelessWidget {
  const _CupertinoActionBar({required this.presenter, required this.request});

  final PdfCupertinoPresenter presenter;
  final PdfActionBarRequest request;

  @override
  Widget build(BuildContext context) {
    final labels = request.kind == PdfActionBarKind.textSelection;
    final divider =
        Container(width: 0.5, height: 22, color: const Color(0x55FFFFFF));
    final buttons = <Widget>[];
    for (final action in request.actions) {
      if (buttons.isNotEmpty) buttons.add(divider);
      buttons.add(_button(context, action, labels));
    }
    return _CupertinoCapsule(
      key: ValueKey('pdf-cupertino-action-bar-${request.kind.name}'),
      child: Row(mainAxisSize: MainAxisSize.min, children: buttons),
    );
  }

  Widget _button(BuildContext context, PdfActionBarAction action, bool labels) {
    final icon = action.icon;
    final showLabel = labels || icon == null;
    final group = action.onPressed == null && action.children.isNotEmpty;
    return Semantics(
      button: true,
      label: showLabel ? null : action.label,
      child: CupertinoButton(
        key: ValueKey(action.id),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        minimumSize: const Size(40, 40),
        onPressed: group
            ? () => unawaited(_openGroup(context, action))
            : action.onPressed,
        child: showLabel
            ? Text(action.label,
                style:
                    const TextStyle(color: CupertinoColors.white, fontSize: 15))
            : Icon(icon, color: CupertinoColors.white, size: 20),
      ),
    );
  }

  Future<void> _openGroup(
      BuildContext context, PdfActionBarAction group) async {
    final box = context.findRenderObject() as RenderBox?;
    final anchor =
        box == null ? Rect.zero : box.localToGlobal(Offset.zero) & box.size;
    final picked = await presenter.menu<PdfActionBarAction>(
      context,
      PdfMenuRequest(anchor: anchor, entries: [
        for (final child in group.children)
          PdfMenuItem(
            key: ValueKey(child.id),
            value: child,
            label: child.label,
            icon: child.icon,
            enabled: child.onPressed != null,
          ),
      ]),
    );
    picked?.onPressed?.call();
  }
}

/// A [PdfEditorNotice] as an iOS-style toast in the root overlay. One at a
/// time: a notice that [PdfEditorNotice.replaceCurrent]s takes the place of
/// the one showing, any other waits for it.
class _CupertinoToast extends StatefulWidget {
  const _CupertinoToast({
    super.key,
    required this.notice,
    required this.undoLabel,
    required this.closeLabel,
    required this.themes,
    required this.onDone,
  });

  final PdfEditorNotice notice;
  final String undoLabel;
  final String closeLabel;
  final CapturedThemes themes;
  final VoidCallback onDone;

  static (OverlayState, OverlayEntry)? _current;
  static final _queue = <(OverlayState, OverlayEntry)>[];

  static bool show(BuildContext context, PdfEditorNotice notice) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return false;
    final themes = InheritedTheme.capture(from: context, to: overlay.context);
    final l10n = pdfL10n(context);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _CupertinoToast(
        key: notice.key,
        notice: notice,
        undoLabel: l10n.undo,
        closeLabel: l10n.close,
        themes: themes,
        onDone: () => _dismiss(entry),
      ),
    );
    if (_current != null && !_current!.$1.mounted) _current = null;
    _queue.removeWhere((q) => !q.$1.mounted);
    if (notice.replaceCurrent) {
      _queue.clear();
      final current = _current;
      _current = null;
      if (current != null) _remove(current.$2);
    }
    if (_current != null) {
      _queue.add((overlay, entry));
    } else {
      _current = (overlay, entry);
      overlay.insert(entry);
    }
    return true;
  }

  static void _remove(OverlayEntry entry) {
    entry.remove();
    entry.dispose();
  }

  static void _dismiss(OverlayEntry entry) {
    final current = _current;
    if (current == null || !identical(current.$2, entry)) return;
    _current = null;
    if (current.$1.mounted) _remove(entry);
    while (_queue.isNotEmpty) {
      final next = _queue.removeAt(0);
      if (!next.$1.mounted) continue;
      _current = next;
      next.$1.insert(next.$2);
      break;
    }
  }

  @override
  State<_CupertinoToast> createState() => _CupertinoToastState();
}

class _CupertinoToastState extends State<_CupertinoToast> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(
        widget.notice.duration ?? const Duration(milliseconds: 4000), _close);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _close() {
    _timer?.cancel();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) =>
      widget.themes.wrap(Builder(builder: _toast));

  Widget _toast(BuildContext context) {
    final notice = widget.notice;
    final onUndo = notice.onUndo;
    final margin = switch (notice.placement) {
      PdfNoticePlacement.aboveToolbar =>
        pdfFloatingToastMargin(context).resolve(Directionality.of(context)),
      PdfNoticePlacement.floating => EdgeInsets.fromLTRB(
          16, 0, 16, 24 + MediaQuery.paddingOf(context).bottom),
      PdfNoticePlacement.attached =>
        EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
    };
    // the capsule is dark in either brightness: take the dark variants
    final accent = notice.kind == PdfNoticeKind.error
        ? CupertinoColors.systemRed.darkColor
        : CupertinoColors.systemBlue.darkColor;
    // an overlay entry fills the overlay; the Align hit-tests only the toast
    return Padding(
      padding: margin,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Semantics(
          liveRegion: true,
          child: _CupertinoCapsule(
            key: const ValueKey('pdf-cupertino-toast'),
            radius: notice.placement == PdfNoticePlacement.attached ? 0 : 14,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: 16, end: 4),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(notice.message),
                    ),
                  ),
                  if (onUndo != null)
                    CupertinoButton(
                      key: const ValueKey('pdf-cupertino-toast-undo'),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      minimumSize: const Size(44, 44),
                      onPressed: () {
                        _close();
                        onUndo();
                      },
                      child: Text(widget.undoLabel,
                          style: TextStyle(
                              color: accent, fontWeight: FontWeight.w600)),
                    ),
                  if (notice.showClose)
                    Semantics(
                      button: true,
                      label: widget.closeLabel,
                      child: CupertinoButton(
                        key: const ValueKey('pdf-cupertino-toast-close'),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(44, 44),
                        onPressed: _close,
                        child: const Icon(Icons.close,
                            size: 18, color: CupertinoColors.white),
                      ),
                    ),
                  if (onUndo == null && !notice.showClose)
                    const SizedBox(width: 12),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
