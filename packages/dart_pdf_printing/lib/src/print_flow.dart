import 'dart:async';
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart' show showPdfDialog;
import 'package:flutter/widgets.dart';
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
  _ProgressRoute? progressRoute;
  void dismiss() {
    final route = progressRoute;
    progressRoute = null;
    route?.close(navigator);
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
          final route = _ProgressRoute();
          progressRoute = route;
          // showPdfDialog keeps the dialog in this view (no native-window
          // promotion) and carries the host's themes and editor scope.
          unawaited(showPdfDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) {
              route.attach(navigator, ModalRoute.of(dialogContext));
              return PopScope(
                canPop: false,
                child: PrintProgressDialog(progress: progress),
              );
            },
          ));
        }
        if (rendered >= total) dismiss();
      },
    );
  } finally {
    dismiss();
    progress.dispose();
  }
}

/// The progress dialog's route, learnt from inside its builder (showPdfDialog
/// does not hand the route back). Closing removes this exact route, even if
/// the host opened another route above it while native page preparation was
/// in flight; closing before the route first builds removes it as it does.
class _ProgressRoute {
  ModalRoute<Object?>? _route;
  bool _closed = false;

  void attach(NavigatorState navigator, ModalRoute<Object?>? route) {
    if (route == null || identical(route, _route)) return;
    _route = route;
    if (_closed) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _remove(navigator));
    }
  }

  void close(NavigatorState navigator) {
    _closed = true;
    _remove(navigator);
  }

  void _remove(NavigatorState navigator) {
    final route = _route;
    _route = null;
    if (route != null && navigator.mounted && route.isActive) {
      navigator.removeRoute(route);
    }
  }
}
