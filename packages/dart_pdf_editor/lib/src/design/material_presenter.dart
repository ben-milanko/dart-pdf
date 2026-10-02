// The stock (Material) look behind PdfEditorPresenter's defaults for menus,
// sheets, notices, confirmations and form-choice menus. The one place the
// editor calls showMenu / showModalBottomSheet / ScaffoldMessenger, so a
// presenter that overrides those methods takes all of them over.

import 'package:flutter/material.dart';

import '../dialog.dart';
import '../l10n/pdf_l10n.dart';
import '../toast.dart';
import 'editor_presenter.dart';

/// [PdfEditorPresenter.sheet]'s default: a Material modal bottom sheet.
Future<T?> pdfStockSheet<T>(BuildContext context, PdfSheetRequest<T> request) {
  final factor = request.maxHeightFactor;
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: request.showDragHandle,
    isScrollControlled: request.scrollControlled,
    constraints: factor == null
        ? null
        : BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * factor),
    builder: request.builder,
  );
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
  final child = entry.child ?? _defaultRow(entry);
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
/// [ScaffoldMessenger]; false (nothing shown) when there is none.
bool pdfStockNotice(BuildContext context, PdfEditorNotice notice) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return false;
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
