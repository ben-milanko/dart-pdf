import 'package:flutter/widgets.dart';
import 'package:pdf_document/pdf_document.dart';
import '../design/table_editor_dialog.dart';
import 'editing_controller.dart';
import '../dialog.dart';

export '../design/table_editor_dialog.dart' show PdfTableEditorDialog;

/// The PDF is changed only on Apply. Context-menu callers freeze a target and
/// revision; changing selection/document while the dialog is open cannot edit
/// an unrelated annotation.
Future<void> showPdfTableEditor(
  BuildContext context, {
  required PdfEditingController controller,
  required int pageIndex,
  int? annotationSlot,
  (double, double)? position,
}) async {
  final revision = controller.revisionId;
  final original = annotationSlot == null
      ? null
      : controller.annotationAt(pageIndex, annotationSlot);
  if (original != null &&
      (!controller.isAnnotationEditable(original) ||
          original.isLockedContents)) {
    return;
  }
  final initial = original?.table;
  if (annotationSlot != null && initial == null) return;
  final result = await showPdfDialog<PdfTableData>(
      context: context,
      builder: (_) => PdfTableEditorDialog(
          initial: initial, onCopyCells: controller.copyTableCellsText));
  if (result == null || controller.revisionId != revision) return;
  if (annotationSlot != null) {
    controller.updateTable(pageIndex, annotationSlot, result,
        expectedRevision: revision);
  } else {
    if (pageIndex < 0 || pageIndex >= controller.document.pageCount) return;
    final box = controller.document.page(pageIndex).cropBox;
    controller.placeTable(pageIndex, position?.$1 ?? (box.left + box.right) / 2,
        position?.$2 ?? (box.bottom + box.top) / 2, result);
  }
}
