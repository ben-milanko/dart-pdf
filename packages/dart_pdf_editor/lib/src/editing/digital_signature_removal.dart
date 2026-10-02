import 'package:flutter/widgets.dart';
import 'package:pdf_document/pdf_document.dart' show PdfSignature;

import '../design/material_presenter.dart' show pdfStockConfirm;
import '../l10n/pdf_l10n.dart';
import '../design/editor_presenter.dart';

/// Confirms removal of an active digital signature from the document.
///
/// This only asks the question; call `PdfEditingController.removeSignature`
/// when it returns true. Removing the signature is undoable, but its signed
/// bytes remain in the PDF's incremental history and cannot be scrubbed.
Future<bool> showPdfRemoveSignatureDialog(
  BuildContext context,
  PdfSignature signature,
) =>
    pdfStockConfirm(context, pdfRemoveSignatureRequest(context, signature));

/// The [PdfConfirmRequest] behind [showPdfRemoveSignatureDialog].
PdfConfirmRequest pdfRemoveSignatureRequest(
    BuildContext context, PdfSignature signature) {
  final name = signature.signerName;
  return PdfConfirmRequest(
    title: pdfL10n(context).sidebarRemoveSignatureTitle,
    message: name == null || name.isEmpty
        ? pdfL10n(context).sidebarRemoveSignatureBody
        : pdfL10n(context).sidebarRemoveSignatureBodyNamed(name),
    confirmLabel: pdfL10n(context).remove,
    destructive: true,
  );
}

/// Asks the nearest presenter to confirm removing [signature].
Future<bool> pdfConfirmRemoveSignature(
        BuildContext context, PdfSignature signature) =>
    PdfEditorPresenter.of(context)
        .confirm(context, pdfRemoveSignatureRequest(context, signature));
