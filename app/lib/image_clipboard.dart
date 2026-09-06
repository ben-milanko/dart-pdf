import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';

// copyPngToClipboard is platform-specific: an app-owned platform channel on
// native, and the browser Async Clipboard API on web. Conditional import picks
// the right one at compile time.
import 'image_clipboard_io.dart'
    if (dart.library.js_interop) 'image_clipboard_web.dart';

export 'image_clipboard_io.dart'
    if (dart.library.js_interop) 'image_clipboard_web.dart'
    show
        copyPngToClipboard,
        copySnapshotToClipboard,
        readPdfFromClipboard,
        readImageFromClipboard,
        readTextFromClipboard;

/// Writes PNG-encoded image [bytes] to the system clipboard. Returns true on
/// success, false (or throws) when the running platform can't.
///
/// Flutter's built-in [Clipboard] only carries text, so putting a picture on
/// the OS clipboard needs platform code. This typedef is the seam the editor
/// screen injects a fake through in tests (the real writers' channels are
/// unavailable under `flutter test`).
typedef ImageClipboardWriter = Future<bool> Function(Uint8List bytes);

/// Writes PDF and PNG representations atomically, keeping vectors available
/// to PDF consumers and an image fallback for other applications.
typedef SnapshotClipboardWriter = Future<bool> Function(
    Uint8List pdf, Uint8List png);

/// Reads PDF bytes copied by another app. Local copies return null so the
/// shared in-app clipboard retains repeat-paste bookkeeping.
typedef PdfClipboardReader = Future<PdfClipboardPdf?> Function();

/// Reads PNG/JPEG-compatible image bytes from the system clipboard. Returns
/// null when the clipboard has no image or the platform denies access.
typedef ImageClipboardReader = Future<Uint8List?> Function();

/// Reads plain text from the system clipboard. Returns null when the clipboard
/// has no text or the platform denies access.
typedef TextClipboardReader = Future<String?> Function();

/// Builds the [PdfSnapshotHandler] the editor passes to the viewer's Snapshot
/// tool. The tool already keeps a *vector* copy on the in-app clipboard for
/// paste-back; this handler publishes PDF and PNG representations together on
/// desktop. Mobile and web retain PNG copying.
///
/// [snapshotWriter] defaults to [copySnapshotToClipboard]. [writer] retains
/// the existing PNG-only override for hosts and tests that need it.
/// [onResult] reports whether the copy succeeded (the screen surfaces a toast).
PdfSnapshotHandler clipboardSnapshotHandler({
  ImageClipboardWriter? writer,
  SnapshotClipboardWriter? snapshotWriter,
  required void Function(bool copied) onResult,
}) {
  return (context, snapshot) async {
    bool copied;
    try {
      if (snapshotWriter != null) {
        copied = await snapshotWriter(snapshot.pdfBytes, snapshot.pngBytes);
      } else if (writer != null || !supportsPdfClipboard) {
        copied = await (writer ?? copyPngToClipboard)(snapshot.pngBytes);
      } else {
        copied =
            await copySnapshotToClipboard(snapshot.pdfBytes, snapshot.pngBytes);
      }
    } catch (_) {
      copied = false;
    }
    onResult(copied);
  };
}
