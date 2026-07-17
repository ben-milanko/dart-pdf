import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdf_document/pdf_document.dart';

import '../page_range_dialog.dart';
import 'editing_color_picker.dart';
import 'editing_controller.dart';
import 'editing_form_style.dart';
import 'text_prompt.dart';

const _densePopupMenuHeight = 34.0;

TextStyle? _densePopupTextStyle(BuildContext context, {Color? color}) =>
    Theme.of(context).textTheme.labelMedium?.copyWith(
          color: color,
          height: 1.1,
        );

/// What an annotation context menu acts on: the controller and the
/// selection at the moment the menu opened. The right-clicked annotation
/// is always part of the selection (the viewer selects it before the
/// menu shows); a right-click on an already-selected annotation keeps a
/// multi-selection intact, so [annotations] can hold several entries.
class PdfAnnotationMenuRequest {
  PdfAnnotationMenuRequest._(this.controller, this.pageIndex)
      : slots = controller.selectedAnnotationSlots,
        annotations = [
          for (final (page, slot) in controller.selectedAnnotationSlots)
            if (controller.annotationAt(page, slot) case final annotation?)
              annotation
        ];

  final PdfEditingController controller;

  /// The page the menu was opened on (where the right-click landed).
  final int pageIndex;

  /// The selected (page, /Annots slot) pairs, primary last.
  final List<(int page, int slot)> slots;

  /// The selected annotations, in [slots] order.
  final List<PdfAnnotation> annotations;

  /// The primary selected annotation - the one right-clicked, when the
  /// click started a fresh selection.
  PdfAnnotation? get primary => annotations.isEmpty ? null : annotations.last;
}

/// One entry in the annotation context menu. Hosts add their own through
/// [PdfViewer.annotationMenuBuilder]; the stock entries (z-order, delete)
/// are built the same way internally.
class PdfAnnotationMenuItem {
  const PdfAnnotationMenuItem({
    this.key,
    required this.label,
    this.icon,
    this.enabled = true,
    required this.onSelected,
  });

  /// Optional key on the menu row, for tests.
  final Key? key;

  final String label;
  final IconData? icon;
  final bool enabled;

  /// Runs when the entry is picked. The request carries the controller
  /// and the selection the menu was opened on.
  final FutureOr<void> Function(PdfAnnotationMenuRequest request) onSelected;
}

/// Builds the host's extra context-menu entries for the current
/// selection. Returning an empty list adds nothing; the stock entries
/// always come first, with a divider before the custom ones.
typedef PdfAnnotationMenuBuilder = List<PdfAnnotationMenuItem> Function(
    BuildContext context, PdfAnnotationMenuRequest request);

/// Shows the annotation context menu at [position] (global coordinates)
/// for [controller]'s current selection: copy/cut/apply-to-pages/paste,
/// bring to front, send to back, add/remove node (a single /PolyLine or
/// /Polygon, when [pagePoint] is known), delete, then whatever
/// [customActions] adds. Resolves when the menu closes, after the picked
/// action ran.
///
/// [pagePoint] is where on the page the menu was opened (page space) -
/// Paste centers the clipboard there; without it the paste falls back
/// to [PdfEditingController.pasteAnnotations]' cascade. With nothing
/// selected the menu still opens when the clipboard has content (the
/// empty-area right-click), offering Paste alone.
Future<void> showPdfAnnotationMenu({
  required BuildContext context,
  required Offset position,
  required PdfEditingController controller,
  required int pageIndex,
  PdfAnnotationMenuBuilder? customActions,
  (double, double)? pagePoint,
}) async {
  final request = PdfAnnotationMenuRequest._(controller, pageIndex);
  // a captured snapshot pastes back as vector graphics; otherwise the
  // annotation clipboard (the most recent copy wins)
  final canPasteSnapshot = controller.hasSnapshotClipboard;
  final canPaste = canPasteSnapshot || controller.hasAnnotationClipboard;
  final hasSelection = request.annotations.isNotEmpty;
  if (!hasSelection && !canPaste) return;
  final stock = <PdfAnnotationMenuItem>[
    if (hasSelection) ...[
      PdfAnnotationMenuItem(
        key: const ValueKey('pdf-annot-menu-copy'),
        label: 'Copy',
        icon: Icons.copy,
        onSelected: (request) => request.controller.copySelectedAnnotations(),
      ),
      PdfAnnotationMenuItem(
        key: const ValueKey('pdf-annot-menu-cut'),
        label: 'Cut',
        icon: Icons.cut,
        onSelected: (request) => request.controller.cutSelectedAnnotations(),
      ),
      PdfAnnotationMenuItem(
        key: const ValueKey('pdf-annot-menu-apply-pages'),
        label: 'Apply to pages…',
        icon: Icons.copy_all_outlined,
        onSelected: (request) async {
          final pageCount = request.controller.document.pageCount;
          final range = await showPdfPageRangeDialog(
            context,
            pageCount: pageCount,
            title: request.annotations.length == 1
                ? 'Apply annotation to pages'
                : 'Apply annotations to pages',
            confirmLabel: 'Apply',
          );
          if (range == null) return;
          request.controller.applySelectedAnnotationsToPages(
            Iterable<int>.generate(
              range.end - range.start + 1,
              (i) => range.start + i,
            ),
          );
        },
      ),
    ],
    PdfAnnotationMenuItem(
      key: const ValueKey('pdf-annot-menu-paste'),
      label: 'Paste',
      icon: Icons.paste,
      enabled: canPaste,
      onSelected: (request) => canPasteSnapshot
          ? request.controller.pasteSnapshot(pageIndex, at: pagePoint)
          : request.controller.pasteAnnotations(pageIndex, at: pagePoint),
    ),
    if (hasSelection) ...[
      PdfAnnotationMenuItem(
        key: const ValueKey('pdf-annot-menu-front'),
        label: 'Bring to front',
        icon: Icons.flip_to_front,
        enabled: controller.canBringSelectedToFront,
        onSelected: (request) => request.controller.bringSelectedToFront(),
      ),
      PdfAnnotationMenuItem(
        key: const ValueKey('pdf-annot-menu-back'),
        label: 'Send to back',
        icon: Icons.flip_to_back,
        enabled: controller.canSendSelectedToBack,
        onSelected: (request) => request.controller.sendSelectedToBack(),
      ),
      // A right-click on a /PolyLine or /Polygon can grow or drop a vertex
      // at the click point. Needs the page point the menu opened on; the
      // selection-chip "More" path (no point) hides these.
      if (pagePoint != null && controller.canAddSelectedVertex) ...[
        PdfAnnotationMenuItem(
          key: const ValueKey('pdf-annot-menu-add-node'),
          label: 'Add node',
          icon: Icons.add_location_alt_outlined,
          onSelected: (request) =>
              request.controller.addSelectedVertexAt(pagePoint),
        ),
        PdfAnnotationMenuItem(
          key: const ValueKey('pdf-annot-menu-remove-node'),
          label: 'Remove node',
          icon: Icons.wrong_location_outlined,
          enabled: controller.canRemoveSelectedVertex,
          onSelected: (request) =>
              request.controller.removeSelectedVertexNear(pagePoint),
        ),
      ],
      if (controller.canRecolorSnapshotSelected)
        PdfAnnotationMenuItem(
          key: const ValueKey('pdf-annot-menu-recolor-snapshot'),
          label: 'Recolour…',
          icon: Icons.palette_outlined,
          onSelected: (request) async {
            final picked = await showPdfColorPicker(
              context,
              initial: request.controller.color,
              initialFormat: request.controller.preferences.colorPickerFormat,
              onFormatChanged: (format) =>
                  request.controller.preferences.colorPickerFormat = format,
            );
            if (picked != null) {
              request.controller.recolorSnapshotSelected(picked);
            }
          },
        ),
      PdfAnnotationMenuItem(
        key: const ValueKey('pdf-annot-menu-delete'),
        label: 'Delete',
        icon: Icons.delete_outline,
        enabled: true,
        onSelected: (request) => request.controller.deleteSelected(),
      ),
    ],
  ];
  final custom =
      customActions?.call(context, request) ?? const <PdfAnnotationMenuItem>[];

  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final picked = await showMenu<PdfAnnotationMenuItem>(
    context: context,
    position:
        RelativeRect.fromRect(position & Size.zero, Offset.zero & overlay.size),
    items: [
      for (final item in stock) _menuRow(item),
      if (custom.isNotEmpty) const PopupMenuDivider(),
      for (final item in custom) _menuRow(item),
    ],
  );
  await picked?.onSelected(request);
}

/// Shows the form tool's field context menu at [position] (global
/// coordinates) for the field named [fieldName]: rename, convert to the
/// other creatable kinds, delete, and flatten the whole form. Resolves
/// when the menu closes, after the picked action ran.
Future<void> showPdfFormFieldMenu({
  required BuildContext context,
  required Offset position,
  required PdfEditingController controller,
  required String fieldName,
  int? widgetIndex,
  PdfTextPrompt textPrompt = showPdfTextPrompt,
  PdfFontPicker? fontPicker,
  PdfFormImagePicker? formImagePicker,
}) async {
  final field = controller.acroForm?.fieldNamed(fieldName);
  if (field == null) return;
  final type = field.type;
  bool convertsTo(PdfFormFieldKind kind) => switch (kind) {
        PdfFormFieldKind.text => type != PdfFieldType.text,
        PdfFormFieldKind.checkBox => type != PdfFieldType.checkBox,
        PdfFormFieldKind.pushButton => type != PdfFieldType.pushButton,
      };

  PdfAnnotationMenuItem? editItem() {
    final enabled = !field.isReadOnly;
    switch (type) {
      case PdfFieldType.text:
        return PdfAnnotationMenuItem(
          key: const ValueKey('pdf-form-menu-edit'),
          label: 'Edit value…',
          icon: Icons.edit_outlined,
          enabled: enabled,
          onSelected: (_) async {
            final value = await textPrompt(context,
                title: 'Field value', initial: field.value ?? '');
            if (value != null) controller.setFormFieldText(fieldName, value);
          },
        );
      case PdfFieldType.checkBox:
        return PdfAnnotationMenuItem(
          key: const ValueKey('pdf-form-menu-edit'),
          label: field.isChecked ? 'Clear check' : 'Check',
          icon: field.isChecked
              ? Icons.check_box_outline_blank
              : Icons.check_box_outlined,
          enabled: enabled,
          onSelected: (_) => controller.toggleFormCheckBox(fieldName),
        );
      case PdfFieldType.radioGroup:
        final state =
            widgetIndex == null ? null : field.widgetOnState(widgetIndex);
        return PdfAnnotationMenuItem(
          key: const ValueKey('pdf-form-menu-edit'),
          label: 'Select option',
          icon: Icons.radio_button_checked,
          enabled: enabled && state != null && field.value != state,
          onSelected: (_) {
            if (state != null) controller.setFormRadioValue(fieldName, state);
          },
        );
      case PdfFieldType.comboBox || PdfFieldType.listBox:
        return PdfAnnotationMenuItem(
          key: const ValueKey('pdf-form-menu-edit'),
          label: 'Choose value…',
          icon: Icons.list_alt_outlined,
          enabled: enabled && field.options.isNotEmpty,
          onSelected: (_) async {
            final overlay =
                Overlay.of(context).context.findRenderObject()! as RenderBox;
            final picked = await showMenu<String>(
              context: context,
              position: RelativeRect.fromRect(
                  position & Size.zero, Offset.zero & overlay.size),
              items: [
                for (final (export, display) in field.options)
                  PopupMenuItem(
                    key: ValueKey('pdf-form-edit-option-$export'),
                    value: export,
                    height: _densePopupMenuHeight,
                    child: Text(display, style: _densePopupTextStyle(context)),
                  ),
              ],
            );
            if (picked != null) {
              controller.setFormChoiceValue(fieldName, picked);
            }
          },
        );
      case PdfFieldType.pushButton:
        return PdfAnnotationMenuItem(
          key: const ValueKey('pdf-form-menu-edit'),
          label: 'Set image…',
          icon: Icons.image_outlined,
          enabled: enabled && formImagePicker != null,
          onSelected: (_) async {
            final picker = formImagePicker;
            if (picker == null) return;
            final fresh = controller.acroForm?.fieldNamed(fieldName);
            if (fresh == null) return;
            final bytes = await picker(context, fresh);
            if (bytes != null) {
              await controller.setFormButtonImageAsync(fieldName, bytes);
            }
          },
        );
      case PdfFieldType.signature || PdfFieldType.unknown:
        return null;
    }
  }

  final items = <PdfAnnotationMenuItem>[
    if (editItem() case final item?) item,
    if (type == PdfFieldType.text)
      PdfAnnotationMenuItem(
        key: const ValueKey('pdf-form-menu-style'),
        label: 'Text style…',
        icon: Icons.text_format,
        onSelected: (_) async {
          if (!controller.selectFormFieldByName(fieldName)) return;
          if (!context.mounted) return;
          await showPdfFormTextStylePopup(
            context: context,
            position: position,
            controller: controller,
            fontPicker: fontPicker,
          );
        },
      ),
    PdfAnnotationMenuItem(
      key: const ValueKey('pdf-form-menu-rename'),
      label: 'Rename…',
      icon: Icons.drive_file_rename_outline,
      onSelected: (_) async {
        final newName =
            await textPrompt(context, title: 'Field name', initial: fieldName);
        if (newName == null || newName.isEmpty || newName == fieldName) {
          return;
        }
        controller.renameFormField(fieldName, newName);
      },
    ),
    PdfAnnotationMenuItem(
      key: const ValueKey('pdf-form-menu-text'),
      label: 'Convert to text field',
      icon: Icons.text_fields,
      enabled: convertsTo(PdfFormFieldKind.text),
      onSelected: (_) =>
          controller.changeFormFieldKind(fieldName, PdfFormFieldKind.text),
    ),
    PdfAnnotationMenuItem(
      key: const ValueKey('pdf-form-menu-checkbox'),
      label: 'Convert to check box',
      icon: Icons.check_box_outlined,
      enabled: convertsTo(PdfFormFieldKind.checkBox),
      onSelected: (_) =>
          controller.changeFormFieldKind(fieldName, PdfFormFieldKind.checkBox),
    ),
    PdfAnnotationMenuItem(
      key: const ValueKey('pdf-form-menu-button'),
      label: 'Convert to image button',
      icon: Icons.smart_button,
      enabled: convertsTo(PdfFormFieldKind.pushButton),
      onSelected: (_) => controller.changeFormFieldKind(
          fieldName, PdfFormFieldKind.pushButton),
    ),
    PdfAnnotationMenuItem(
      key: const ValueKey('pdf-form-menu-delete'),
      label: 'Delete field',
      icon: Icons.delete_outline,
      onSelected: (_) => controller.removeFormField(fieldName),
    ),
    PdfAnnotationMenuItem(
      key: const ValueKey('pdf-form-menu-flatten'),
      label: 'Flatten form',
      icon: Icons.layers_clear_outlined,
      onSelected: (_) => controller.flattenFormFields(),
    ),
  ];

  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final picked = await showMenu<PdfAnnotationMenuItem>(
    context: context,
    position:
        RelativeRect.fromRect(position & Size.zero, Offset.zero & overlay.size),
    items: [for (final item in items) _menuRow(item)],
  );
  // the request param is unused by these closures; reuse the row type
  // so the menu plumbing stays shared with the annotation menu
  await picked?.onSelected(PdfAnnotationMenuRequest._(controller, -1));
}

PopupMenuItem<PdfAnnotationMenuItem> _menuRow(PdfAnnotationMenuItem item) =>
    PopupMenuItem<PdfAnnotationMenuItem>(
      key: item.key,
      value: item,
      enabled: item.enabled,
      height: _densePopupMenuHeight,
      child: Builder(
        builder: (context) {
          final disabledColor = Theme.of(context).disabledColor;
          final color = item.enabled ? null : disabledColor;
          return Row(
            children: [
              if (item.icon != null) ...[
                // PopupMenuItem dims only text when disabled; match it
                Icon(item.icon, size: 16, color: color),
                const SizedBox(width: 8),
              ],
              // flexible: long labels ellipsize at the popup's width cap
              // instead of overflowing
              Flexible(
                child: Text(
                  item.label,
                  overflow: TextOverflow.ellipsis,
                  style: _densePopupTextStyle(context, color: color),
                ),
              ),
            ],
          );
        },
      ),
    );
