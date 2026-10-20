import 'package:dart_pdf_editor/dart_pdf_editor.dart'
    show PdfDialogSubmit, showPdfDialog;
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf_document/pdf_document.dart';

import 'incoming_file.dart';
import 'l10n/app_l10n.dart';

/// What to do with several PDFs the OS opened at once.
enum IncomingFilesAction { separate, combine }

/// Asks whether several PDFs the OS opened together should open in their own
/// tabs or be combined into one new document, and in which order. The list
/// starts in file-name order (the order the OS delivers them in is not the
/// order the user selected them in on every platform) and can be reordered
/// by dragging. Returns null when cancelled.
///
/// [combineOnly] is for files the user already chose to combine (the OS's
/// "Combine with DartPDF" entry): the dialog then only sets the order.
Future<({IncomingFilesAction action, List<IncomingFile> files})?>
    showIncomingFilesDialog(BuildContext context, List<IncomingFile> files,
        {bool combineOnly = false}) {
  final order = [...files]
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return showPdfDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final l10n = appL10n(context);
        void close(IncomingFilesAction action) =>
            Navigator.of(context).pop((action: action, files: order));
        return AlertDialog(
          key: const ValueKey('incoming-files-dialog'),
          title: Text(combineOnly
              ? l10n.incomingFilesCombineTitle(order.length)
              : l10n.incomingFilesTitle(order.length)),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(combineOnly
                    ? l10n.incomingFilesCombineMessage
                    : l10n.incomingFilesMessage),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: ReorderableListView.builder(
                    key: const ValueKey('incoming-files-order'),
                    shrinkWrap: true,
                    buildDefaultDragHandles: false,
                    itemCount: order.length,
                    onReorderItem: (from, to) =>
                        setState(() => order.insert(to, order.removeAt(from))),
                    itemBuilder: (context, index) => ListTile(
                      key: ObjectKey(order[index]),
                      dense: true,
                      leading: const Icon(Icons.picture_as_pdf_outlined),
                      title: Text(
                        order[index].name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: ReorderableDragStartListener(
                        index: index,
                        child: const Icon(Icons.drag_handle),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.cancel),
            ),
            if (!combineOnly)
              TextButton(
                key: const ValueKey('incoming-files-separate'),
                onPressed: () => close(IncomingFilesAction.separate),
                child: Text(l10n.editorOpenInNewTab(order.length)),
              ),
            PdfDialogSubmit.action(
              onSubmit: () => close(IncomingFilesAction.combine),
              child: FilledButton(
                key: const ValueKey('incoming-files-combine'),
                onPressed: () => close(IncomingFilesAction.combine),
                child: Text(l10n.incomingFilesCombine),
              ),
            ),
          ],
        );
      },
    ),
  );
}

/// Concatenates [pdfs] into one new PDF, off the UI isolate where there is
/// one. See [PdfMerger.merge] for what carries over.
Future<Uint8List> combinePdfs(List<Uint8List> pdfs) =>
    compute(_merge, pdfs, debugLabel: 'combine PDFs');

Uint8List _merge(List<Uint8List> pdfs) => PdfMerger.merge(pdfs);
