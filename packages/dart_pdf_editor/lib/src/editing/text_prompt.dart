import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdf_document/pdf_document.dart'
    show PdfFormField, PdfRect, PdfVectorSnapshot;

import '../dialog.dart';
import '../l10n/pdf_l10n.dart';

/// Supplies the image a tapped push-button field should be filled with
/// - typically a file picker. Return null to leave the button alone.
/// PNG and JPEG bytes are accepted
/// ([PdfEditingController.setFormButtonImage]).
typedef PdfFormImagePicker = Future<Uint8List?> Function(
    BuildContext context, PdfFormField field);

/// Supplies the image bytes the image tool ([PdfEditTool.image]) inserts
/// - typically a file picker. Return null to cancel. PNG and JPEG bytes
/// are accepted ([PdfEditingController.placeImage]).
typedef PdfImagePicker = Future<Uint8List?> Function(BuildContext context);

/// Supplies image bytes for a system clipboard paste. Return null when the
/// clipboard does not currently carry a pasteable image. PNG and JPEG bytes
/// are accepted ([PdfEditingController.placeImage]).
typedef PdfSystemImagePasteProvider = Future<Uint8List?> Function(
    BuildContext context);

/// Supplies an external PDF clipboard payload for vector paste. Return null
/// for clipboard data written by this app, so its in-app snapshot keeps its
/// repeat-paste position and shared resources. Invoked before in-app paste;
/// a newly copied external PDF therefore supersedes an older local copy.
typedef PdfSystemPdfPasteProvider = Future<PdfClipboardPdf?> Function(
    BuildContext context);

/// A PDF clipboard representation and an optional native clipboard revision.
/// [changeToken] must change on every clipboard replacement, including when
/// the bytes are identical. Once pasted, an unchanged revision yields to the
/// in-app clipboard so a subsequent local annotation copy remains usable.
/// Omit the token when the host cannot observe clipboard revisions.
class PdfClipboardPdf {
  const PdfClipboardPdf(this.bytes, {this.changeToken});

  final Uint8List bytes;
  final Object? changeToken;
}

/// Supplies plain text for a system clipboard paste, used in preference to
/// Flutter's [Clipboard] when set. Return null when the clipboard carries no
/// text. Exists mainly for the web, where Flutter's `Clipboard.getData` is
/// unreliable: the host injects a reader built on the browser Async Clipboard
/// API so ⌘V/Ctrl+V can paste text into a [PdfEditTool.freeText] box.
typedef PdfSystemTextPasteProvider = Future<String?> Function(
    BuildContext context);

/// A selected page-content image exported by the Content tool.
class PdfSelectedContentImage {
  const PdfSelectedContentImage({
    required this.pageIndex,
    required this.pageRect,
    required this.pngBytes,
  });

  /// The page the selected content image lives on.
  final int pageIndex;

  /// The selected image's page-space bounds (points, origin bottom-left).
  final PdfRect pageRect;

  /// The selected image rendered as a complete PNG file.
  final Uint8List pngBytes;
}

/// Receives a selected content image from the Content tool — typically to
/// save, share, or download it. Return when the host export is complete.
typedef PdfSelectedContentImageHandler = Future<void> Function(
  BuildContext context,
  PdfSelectedContentImage image,
);

/// Supplies a TrueType (`.ttf`) or OpenType (`.otf`) font file the font
/// menu's "Load font…" entry embeds for new text — typically a file
/// picker. Return null to cancel ([PdfEditingController.setCustomFont]).
typedef PdfFontPicker = Future<Uint8List?> Function(BuildContext context);

/// A region of a page captured by the Snapshot tool ([PdfEditTool.snapshot])
/// - Bluebeam-style: drag out a box and the page region under it is rendered
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

  /// The captured region rendered to a PNG image - for copying to the
  /// clipboard, saving, or sharing as a picture.
  final Uint8List pngBytes;

  /// The captured region as detached **vector** graphics, ready to paste
  /// back into any PDF with [PdfVectorSnapshotEditing.pasteVectorSnapshot]
  /// (or in-app via [PdfEditingController.pasteSnapshot]) - Bluebeam-style,
  /// the snapshot stays sharp at any zoom.
  final PdfVectorSnapshot vector;

  /// The captured region as a self-contained, single-page PDF (the
  /// [vector] serialized via [PdfVectorSnapshot.toPdfBytes]). Put these on
  /// the OS clipboard as `application/pdf` to paste the snapshot, as
  /// vectors, into another application that accepts PDF clipboard data.
  Uint8List get pdfBytes => vector.toPdfBytes();
}

/// Receives a region captured by the Snapshot tool ([PdfEditTool.snapshot])
/// - typically to copy it to the system clipboard, save it to a file, or
/// share it. With no handler ([PdfViewer.onSnapshot]) the Snapshot tool
/// captures nothing.
typedef PdfSnapshotHandler = Future<void> Function(
    BuildContext context, PdfSnapshot snapshot);

/// Receives a signature box the user drew with the Signature-box tool
/// ([PdfEditTool.signatureBox]) - Acrobat/Bluebeam-style placement. The host
/// collects an identity and appearance (reason, location, a hand-drawn mark,
/// a logo backdrop) and cryptographically signs into [pageRect] on [pageIndex]
/// via [PdfEditingController.addKeylessSignature] / addSelfSignedSignature /
/// addDigitalSignature with a `PdfSignatureAppearance(page: pageIndex,
/// rect: pageRect, …)`. With no handler ([PdfViewer.onPlaceSignature]) the
/// tool does nothing. [pageRect] is in PDF user space (points, origin
/// bottom-left).
typedef PdfSignaturePlacer = Future<void> Function(
  BuildContext context, {
  required int pageIndex,
  required PdfRect pageRect,
});

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
  return showPdfDialog<String>(
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
          child: Text(pdfL10n(context).cancel),
        ),
        PdfDialogSubmit(
            child: FilledButton(
          onPressed: () => Navigator.of(context).pop(field.text),
          child: Text(pdfL10n(context).ok),
        )),
      ],
    ),
  );
}
