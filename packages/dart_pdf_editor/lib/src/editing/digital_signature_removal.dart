import 'package:flutter/material.dart';
import 'package:pdf_document/pdf_document.dart' show PdfSignature;

import '../dialog.dart';
import '../l10n/pdf_l10n.dart';

/// Confirms removal of an active digital signature from the document.
///
/// This only asks the question; call `PdfEditingController.removeSignature`
/// when it returns true. Removing the signature is undoable, but its signed
/// bytes remain in the PDF's incremental history and cannot be scrubbed.
Future<bool> showPdfRemoveSignatureDialog(
  BuildContext context,
  PdfSignature signature,
) async {
  final name = signature.signerName;
  final confirmed = await showPdfDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(pdfL10n(context).sidebarRemoveSignatureTitle),
      content: Text(name == null || name.isEmpty
          ? pdfL10n(context).sidebarRemoveSignatureBody
          : pdfL10n(context).sidebarRemoveSignatureBodyNamed(name)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(pdfL10n(context).cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(pdfL10n(context).remove),
        ),
      ],
    ),
  );
  return confirmed == true;
}
