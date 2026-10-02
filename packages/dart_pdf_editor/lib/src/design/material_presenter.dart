// The stock (Material) look behind PdfEditorPresenter's defaults for menus,
// sheets, notices, confirmations and form-choice menus. The one place the
// editor calls showMenu / ScaffoldMessenger or pushes a bottom sheet, so a
// presenter that overrides those methods takes all of them over.

import 'dart:async';

import 'package:flutter/material.dart';

import '../dialog.dart';
import '../l10n/pdf_l10n.dart';
import '../toast.dart';
import 'editor_presenter.dart';
import 'material_host.dart';

/// [PdfEditorPresenter.sheet]'s default: a Material modal bottom sheet on
/// the library's own [_PdfSheetRoute] - `showModalBottomSheet`'s route,
/// presented identically, except that it re-injects whatever the host lacks
/// (Material localizations, a theme) inside the route, where wrapping the
/// sheet's content alone could not reach.
Future<T?> pdfStockSheet<T>(BuildContext context, PdfSheetRequest<T> request) {
  final factor = request.maxHeightFactor;
  final navigator = Navigator.of(context);
  final localizations =
      Localizations.of<MaterialLocalizations>(context, MaterialLocalizations);
  final sheetLabel = localizations?.bottomSheetLabel;
  return navigator.push(_PdfSheetRoute<T>(
    builder: request.builder,
    capturedThemes:
        InheritedTheme.capture(from: context, to: navigator.context),
    isScrollControlled: request.scrollControlled,
    barrierLabel: localizations?.scrimLabel ?? pdfL10n(context).dialogDismiss,
    barrierOnTapHint:
        sheetLabel == null ? null : localizations!.scrimOnTapHint(sheetLabel),
    constraints: factor == null
        ? null
        : BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * factor),
    modalBarrierColor: Theme.of(context).bottomSheetTheme.modalBarrierColor,
    showDragHandle: request.showDragHandle,
  ));
}

/// `showModalBottomSheet`'s route, with the host re-injected inside it: the
/// sheet's drag handle and route label read Material localizations in the
/// route's own context, under the root navigator, which a non-Material host
/// does not provide.
class _PdfSheetRoute<T> extends ModalBottomSheetRoute<T> {
  _PdfSheetRoute({
    required super.builder,
    super.capturedThemes,
    required super.isScrollControlled,
    super.barrierLabel,
    super.barrierOnTapHint,
    super.constraints,
    super.modalBarrierColor,
    super.showDragHandle,
  });

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation) =>
      pdfHostRoute(
          context, super.buildPage(context, animation, secondaryAnimation));
}

/// [PdfEditorPresenter.menu]'s default: a Material popup menu anchored at
/// the request's global rectangle (mapped into the receiving overlay, which
/// a nested navigator may offset).
Future<T?> pdfStockMenu<T>(BuildContext context, PdfMenuRequest<T> request) {
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final anchor = request.anchor;
  final local = Rect.fromPoints(
    overlay.globalToLocal(anchor.topLeft),
    overlay.globalToLocal(anchor.bottomRight),
  );
  return showMenu<T>(
    context: context,
    position: RelativeRect.fromRect(local, Offset.zero & overlay.size),
    items: [for (final entry in request.entries) _popupEntry(entry)],
  );
}

PopupMenuEntry<T> _popupEntry<T>(PdfMenuEntry<T> entry) {
  if (entry is! PdfMenuItem<T>) return const PopupMenuDivider();
  final content = entry.child ?? _defaultRow(entry);
  // a row may embed controls (the form text-style popup's fields); the
  // popup route builds under the root navigator, so re-inject what a
  // non-Material host lacks there (a pass-through under a Material host)
  final child = Builder(builder: (context) => pdfHostRoute(context, content));
  final height = entry.height ?? kMinInteractiveDimension;
  final checked = entry.checked;
  if (checked != null) {
    return CheckedPopupMenuItem<T>(
      key: entry.key,
      value: entry.value,
      enabled: entry.enabled,
      checked: checked,
      height: height,
      padding: entry.padding,
      child: child,
    );
  }
  return PopupMenuItem<T>(
    key: entry.key,
    value: entry.value,
    enabled: entry.enabled,
    height: height,
    padding: entry.padding,
    child: child,
  );
}

Widget _defaultRow(PdfMenuItem<Object?> item) => Builder(
      builder: (context) => Row(children: [
        if (item.icon != null) ...[
          // PopupMenuItem dims only its text when disabled; match it
          Icon(item.icon,
              size: 18,
              color: item.enabled ? null : Theme.of(context).disabledColor),
          const SizedBox(width: 10),
        ],
        Flexible(child: Text(item.label, overflow: TextOverflow.ellipsis)),
      ]),
    );

/// [PdfEditorPresenter.notice]'s default: a SnackBar on the nearest
/// [ScaffoldMessenger], or - under a host without one (a `CupertinoApp`, a
/// `WidgetsApp`, a bare `MaterialApp` home) - the same notice as a toast in
/// the root [Overlay]. False (nothing shown) only with neither.
bool pdfStockNotice(BuildContext context, PdfEditorNotice notice) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return _PdfOverlayToast.show(context, notice);
  if (notice.replaceCurrent) messenger.clearSnackBars();
  final onUndo = notice.onUndo;
  messenger.showSnackBar(SnackBar(
    key: notice.key,
    content: Text(notice.message),
    behavior: notice.placement == PdfNoticePlacement.attached
        ? null
        : SnackBarBehavior.floating,
    margin: notice.placement == PdfNoticePlacement.aboveToolbar
        ? pdfFloatingToastMargin(context)
        : null,
    duration: notice.duration ?? const Duration(milliseconds: 4000),
    showCloseIcon: notice.showClose ? true : null,
    action: onUndo == null
        ? null
        : SnackBarAction(label: pdfL10n(context).undo, onPressed: onUndo),
  ));
  return true;
}

/// A [PdfEditorNotice] drawn like a floating SnackBar, in the root overlay,
/// for hosts without a [ScaffoldMessenger]. One at a time: a notice that
/// [PdfEditorNotice.replaceCurrent]s takes the place of the one showing,
/// any other waits for it.
class _PdfOverlayToast extends StatefulWidget {
  const _PdfOverlayToast({
    super.key,
    required this.notice,
    required this.themes,
    required this.onDone,
  });

  final PdfEditorNotice notice;
  final CapturedThemes themes;
  final VoidCallback onDone;

  static (OverlayState, OverlayEntry)? _current;
  static final _queue = <(OverlayState, OverlayEntry)>[];

  static bool show(BuildContext context, PdfEditorNotice notice) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return false;
    final themes = InheritedTheme.capture(from: context, to: overlay.context);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _PdfOverlayToast(
        key: notice.key,
        notice: notice,
        themes: themes,
        onDone: () => _dismiss(entry),
      ),
    );
    // a toast whose overlay went away (the host tree was replaced) is gone
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
  State<_PdfOverlayToast> createState() => _PdfOverlayToastState();
}

class _PdfOverlayToastState extends State<_PdfOverlayToast> {
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
    // removing the entry mid-frame (a tap) is fine; from a timer, too
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) =>
      widget.themes.wrap(pdfHostRoute(context, Builder(builder: _toast)));

  Widget _toast(BuildContext context) {
    final notice = widget.notice;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final onUndo = notice.onUndo;
    final margin = notice.placement == PdfNoticePlacement.aboveToolbar
        ? pdfFloatingToastMargin(context).resolve(Directionality.of(context))
        : EdgeInsets.fromLTRB(
            16, 0, 16, 16 + MediaQuery.paddingOf(context).bottom);
    // an overlay entry fills the overlay; the Align hit-tests only the toast
    return SafeArea(
      top: false,
      bottom: false,
      child: Padding(
        padding: margin,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            color: scheme.inverseSurface,
            elevation: 6,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: 16, end: 8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        notice.message,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: scheme.onInverseSurface),
                      ),
                    ),
                  ),
                  if (onUndo != null)
                    TextButton(
                      style: TextButton.styleFrom(
                          foregroundColor: scheme.inversePrimary),
                      onPressed: () {
                        _close();
                        onUndo();
                      },
                      child: Text(pdfL10n(context).undo),
                    ),
                  if (notice.showClose)
                    IconButton(
                      color: scheme.onInverseSurface,
                      icon: const Icon(Icons.close),
                      onPressed: _close,
                    ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// [PdfEditorPresenter.confirm]'s default: an alert dialog with Cancel and
/// the confirm action (Enter confirms).
Future<bool> pdfStockConfirm(
    BuildContext context, PdfConfirmRequest request) async {
  final confirmed = await pdfPresentDialog<bool>(
    context,
    builder: (context) => AlertDialog(
      key: request.key,
      title: Text(request.title),
      content: Text(request.message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(pdfL10n(context).cancel),
        ),
        PdfDialogSubmit.action(
            onSubmit: () => Navigator.of(context).pop(true),
            child: FilledButton(
              key: request.confirmKey,
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(request.confirmLabel),
            )),
      ],
    ),
  );
  return confirmed == true;
}

/// [PdfEditorPresenter.formChoice]'s default: the options as a
/// [PdfEditorPresenter.menu] (checkable for a multi-select field, where a
/// pick toggles that option).
Future<List<String>?> pdfStockFormChoice(PdfEditorPresenter presenter,
    BuildContext context, PdfFormChoiceRequest request) async {
  final style = request.compact
      ? Theme.of(context).textTheme.labelMedium?.copyWith(height: 1.1)
      : null;
  final picked = await presenter.menu<String>(
    context,
    PdfMenuRequest<String>(
      anchor: request.anchor,
      entries: [
        for (final (export, display) in request.options)
          PdfMenuItem<String>(
            key: ValueKey('${request.optionKeyPrefix}$export'),
            value: export,
            label: display,
            checked:
                request.multiSelect ? request.selected.contains(export) : null,
            height: request.compact ? 34 : null,
            child: Text(display, style: style),
          ),
      ],
    ),
  );
  if (picked == null) return null;
  if (!request.multiSelect) return [picked];
  return [
    for (final value in request.selected)
      if (value != picked) value,
    if (!request.selected.contains(picked)) picked,
  ];
}
