import 'package:flutter/material.dart';

import '../dialog.dart';
import '../l10n/pdf_l10n.dart';
import '../design/editor_presenter.dart';

export 'models/prompts.dart';

/// The default [PdfTextPrompt]: a one-field Material dialog.
Future<String?> showPdfTextPrompt(
  BuildContext context, {
  required String title,
  String initial = '',
  bool multiline = false,
}) {
  final field = TextEditingController(text: initial);
  return pdfPresentDialog<String>(
    context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: field,
        autofocus: true,
        maxLines: multiline ? 4 : 1,
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(pdfL10n(context).cancel),
        ),
        PdfDialogSubmit.action(
            onSubmit: () => Navigator.of(context).pop(field.text),
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(field.text),
              child: Text(pdfL10n(context).ok),
            )),
      ],
    ),
  );
}
