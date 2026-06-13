import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdf_document/pdf_document.dart' show PdfFormField;

/// Supplies the image a tapped push-button field should be filled with
/// — typically a file picker. Return null to leave the button alone.
/// PNG and JPEG bytes are accepted
/// ([PdfEditingController.setFormButtonImage]).
typedef PdfFormImagePicker = Future<Uint8List?> Function(
    BuildContext context, PdfFormField field);

/// Supplies the image bytes the image tool ([PdfEditTool.image]) inserts
/// — typically a file picker. Return null to cancel. PNG and JPEG bytes
/// are accepted ([PdfEditingController.placeImage]).
typedef PdfImagePicker = Future<Uint8List?> Function(BuildContext context);

/// Signature of the prompt the editing UI uses to ask for annotation text
/// (free text, notes, stamps). Returns null when the user cancels.
typedef PdfTextPrompt = Future<String?> Function(
  BuildContext context, {
  required String title,
  String initial,
  bool multiline,
});

/// The default [PdfTextPrompt]: a one-field Material dialog.
Future<String?> showPdfTextPrompt(
  BuildContext context, {
  required String title,
  String initial = '',
  bool multiline = false,
}) {
  final field = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
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
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(field.text),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
