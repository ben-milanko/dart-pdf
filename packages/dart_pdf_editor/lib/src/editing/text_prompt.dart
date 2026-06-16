import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdf_document/pdf_document.dart'
    show PdfFormField, PdfRect, PdfVectorSnapshot;

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

/// Supplies a TrueType (`.ttf`) or OpenType (`.otf`) font file the font
/// menu's "Load font…" entry embeds for new text — typically a file
/// picker. Return null to cancel ([PdfEditingController.setCustomFont]).
typedef PdfFontPicker = Future<Uint8List?> Function(BuildContext context);

/// A region of a page captured by the Snapshot tool ([PdfEditTool.snapshot])
/// — Bluebeam-style: drag out a box and the page region under it is rendered
/// to an image, handed to [PdfViewer.onSnapshot] for the host to copy, save,
/// or share.
class PdfSnapshot {
  const PdfSnapshot({
    required this.pageIndex,
    required this.pageRect,
    required this.pngBytes,
    required this.vector,
  });

  /// The page the region was captured from.
  final int pageIndex;

  /// The captured region in PDF user space (points, origin bottom-left).
  final PdfRect pageRect;

  /// The captured region rendered to a PNG image — for copying to the
  /// clipboard, saving, or sharing as a picture.
  final Uint8List pngBytes;

  /// The captured region as detached **vector** graphics, ready to paste
  /// back into any PDF with [PdfVectorSnapshotEditing.pasteVectorSnapshot]
  /// (or in-app via [PdfEditingController.pasteSnapshot]) — Bluebeam-style,
  /// the snapshot stays sharp at any zoom.
  final PdfVectorSnapshot vector;
}

/// Receives a region captured by the Snapshot tool ([PdfEditTool.snapshot])
/// — typically to copy it to the system clipboard, save it to a file, or
/// share it. With no handler ([PdfViewer.onSnapshot]) the Snapshot tool
/// captures nothing.
typedef PdfSnapshotHandler = Future<void> Function(
    BuildContext context, PdfSnapshot snapshot);

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
