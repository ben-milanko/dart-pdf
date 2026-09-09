import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf_document/pdf_document.dart';

import 'print_composer.dart';
import 'print_preview_dialog.dart';
import 'print_progress_dialog.dart';
import 'print_printer.dart';
import 'printing.dart';

/// Opens layout options and a preview, composes the confirmed sheets, then
/// prints to the selected Windows queue or opens the system print dialog. Dismissing the preview submits nothing.
///
/// [currentPage] and [selectedPages] are zero-based source page indices.
/// [addFiles] optionally lets the host supply extra PDFs for this job; file
/// selection and password prompting remain under the host's control.
///
/// Commit pending inline text and ink before passing an editing session's
/// document. The preview captures a detached snapshot and never edits it.
/// Errors propagate so the host can show its own error UI.
Future<void> printPdfWithPreview(
  BuildContext context, {
  required PdfDocument document,
  required String title,
  int currentPage = 0,
  List<int> selectedPages = const [],
  Future<List<PdfDocument>> Function()? addFiles,
}) async {
  final job = await showPrintPreviewDialog(
    context,
    document: document,
    title: title,
    currentPage: currentPage,
    selectedPages: selectedPages,
    addFiles: addFiles,
  );
  if (job == null || !context.mounted) return;
  final bytes = preparePrintDocument(job.document, job.settings,
      twoSided: job.destination != null &&
          job.destination!.duplex != PrintDuplex.simplex);
  await printPdfWithProgress(context,
      bytes: bytes,
      title: title,
      useDocumentPageSize: true,
      destination: job.destination);
}

/// Prints a PDF with a progress dialog while desktop pages are prepared.
/// Whole-PDF backends and jobs of at most two pages skip this extra dialog.
/// Set [useDocumentPageSize] for sheets produced by [preparePrintDocument].
Future<void> printPdfWithProgress(
  BuildContext context, {
  required Uint8List bytes,
  required String title,
  bool useDocumentPageSize = false,
  PrintDestination? destination,
}) async {
  final progress = ValueNotifier<(int, int)?>(null);
  final navigator = Navigator.of(context, rootNavigator: true);
  DialogRoute<void>? progressRoute;
  void dismiss() {
    final route = progressRoute;
    progressRoute = null;
    if (route != null && navigator.mounted && route.isActive) {
      // Remove this exact route, even if the host opened another route above
      // it while native page preparation was in flight.
      navigator.removeRoute(route);
    }
  }

  try {
    await printPdfBytes(
      bytes: bytes,
      title: title,
      useDocumentPageSize: useDocumentPageSize,
      destination: destination,
      onProgress: (rendered, total) {
        progress.value = (rendered, total);
        if (total > 2 &&
            rendered < total &&
            progressRoute == null &&
            context.mounted &&
            navigator.mounted) {
          final route = DialogRoute<void>(
            context: context,
            barrierDismissible: false,
            builder: (_) => PopScope(
              canPop: false,
              child: PrintProgressDialog(progress: progress),
            ),
          );
          progressRoute = route;
          unawaited(navigator.push(route));
        }
        if (rendered >= total) dismiss();
      },
    );
  } finally {
    dismiss();
    progress.dispose();
  }
}
