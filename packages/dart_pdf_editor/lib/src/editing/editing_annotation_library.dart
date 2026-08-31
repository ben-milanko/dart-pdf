import 'package:flutter/material.dart';

import '../dialog.dart';
import '../l10n/pdf_l10n.dart';
import 'annotation_presentation.dart';
import 'editing_controller.dart';
import 'editing_stamps.dart';
import 'saved_annotation.dart';
import 'text_prompt.dart';

/// Opens the reusable annotation library.
///
/// Tapping an item places it on [pageIndex] and leaves it on the ordinary
/// annotation clipboard, so Paste can repeat it in this PDF or another one.
/// The Custom stamps action keeps the specialized stamp designer alongside
/// the broader snapshot-based library.
Future<void> showPdfAnnotationLibrary(
  BuildContext context, {
  required PdfEditingController controller,
  required int pageIndex,
  PdfImagePicker? imagePicker,
  PdfStampExportCallback? onExportStamps,
  PdfStampImportCallback? onImportStamps,
}) =>
    showPdfDialog<void>(
      context: context,
      builder: (context) => PdfAnnotationLibraryDialog(
        controller: controller,
        pageIndex: pageIndex,
        imagePicker: imagePicker,
        onExportStamps: onExportStamps,
        onImportStamps: onImportStamps,
      ),
    );

/// Stock UI for saved annotation snapshots.
class PdfAnnotationLibraryDialog extends StatelessWidget {
  const PdfAnnotationLibraryDialog({
    super.key,
    required this.controller,
    required this.pageIndex,
    this.imagePicker,
    this.onExportStamps,
    this.onImportStamps,
  });

  final PdfEditingController controller;
  final int pageIndex;
  final PdfImagePicker? imagePicker;
  final PdfStampExportCallback? onExportStamps;
  final PdfStampImportCallback? onImportStamps;

  Future<void> _rename(
      BuildContext context, PdfSavedAnnotation annotation) async {
    final name = await showPdfTextPrompt(
      context,
      title: pdfL10n(context).annotationLibraryRenameTitle,
      initial: annotation.name,
      multiline: false,
    );
    if (name != null) controller.renameSavedAnnotation(annotation, name);
  }

  void _place(BuildContext context, PdfSavedAnnotation annotation) {
    if (!controller.placeSavedAnnotation(annotation, pageIndex)) return;
    Navigator.of(context).pop();
  }

  Future<void> _stamps(BuildContext context) => showPdfStampPicker(
        context,
        controller: controller,
        imagePicker: imagePicker,
        onExportStamps: onExportStamps,
        onImportStamps: onImportStamps,
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(pdfL10n(context).annotationLibraryTitle),
      content: SizedBox(
        width: 380,
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final annotations = controller.savedAnnotations;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: annotations.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(pdfL10n(context).annotationLibraryEmpty),
                        )
                      : ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 360),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: annotations.length,
                            itemBuilder: (context, index) {
                              final annotation = annotations[index];
                              return ListTile(
                                key: ValueKey(
                                    'pdf-annotation-library-item-$index'),
                                leading: PdfSavedAnnotationPreview(
                                    annotation: annotation),
                                title: Text(annotation.name),
                                subtitle: Text(pdfAnnotationLabel(
                                    context, annotation.snapshot.subtype)),
                                onTap: () => _place(context, annotation),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      key: ValueKey(
                                          'pdf-annotation-library-rename-$index'),
                                      icon: const Icon(Icons.edit_outlined),
                                      tooltip: pdfL10n(context).rename,
                                      onPressed: () =>
                                          _rename(context, annotation),
                                    ),
                                    IconButton(
                                      key: ValueKey(
                                          'pdf-annotation-library-delete-$index'),
                                      icon: const Icon(Icons.delete_outline),
                                      tooltip: pdfL10n(context).delete,
                                      onPressed: () => controller
                                          .removeSavedAnnotation(annotation),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                ),
                const SizedBox(height: 12),
                Text(
                  pdfL10n(context).annotationLibraryHelp,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton.icon(
          key: const ValueKey('pdf-annotation-library-stamps'),
          onPressed: () => _stamps(context),
          icon: const Icon(Icons.approval_outlined),
          label: Text(pdfL10n(context).annotationLibraryCustomStamps),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(pdfL10n(context).close),
        ),
      ],
    );
  }
}

/// Compact subtype preview used by the stock annotation library.
class PdfSavedAnnotationPreview extends StatelessWidget {
  const PdfSavedAnnotationPreview({
    super.key,
    required this.annotation,
  });

  final PdfSavedAnnotation annotation;

  @override
  Widget build(BuildContext context) {
    final icon = pdfAnnotationIcon(annotation.snapshot.subtype);
    final rect = annotation.snapshot.rect;
    return Container(
      width: 48,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Tooltip(
        message:
            '${rect.width.toStringAsFixed(0)} × ${rect.height.toStringAsFixed(0)} pt',
        child: Icon(icon,
            size: 23,
            color: Theme.of(context).colorScheme.onSecondaryContainer),
      ),
    );
  }
}
