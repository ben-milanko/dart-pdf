import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';

// copyPngToClipboard is platform-specific: super_clipboard on native, the
// browser Async Clipboard API on web (the pinned super_clipboard's web layer
// is unreliable). Conditional import picks the right one at compile time.
import 'image_clipboard_io.dart'
    if (dart.library.js_interop) 'image_clipboard_web.dart';

export 'image_clipboard_io.dart'
    if (dart.library.js_interop) 'image_clipboard_web.dart' show copyPngToClipboard;

/// Writes PNG-encoded image [bytes] to the system clipboard. Returns true on
/// success, false (or throws) when the running platform can't.
///
/// Flutter's built-in [Clipboard] only carries text, so putting a picture on
/// the OS clipboard needs platform code — super_clipboard on native, the
/// browser clipboard API on web. This typedef is the seam the editor screen
/// injects a fake through in tests (the real writers' channels are unavailable
/// under `flutter test`).
typedef ImageClipboardWriter = Future<bool> Function(Uint8List bytes);

/// Builds the [PdfSnapshotHandler] the editor passes to the viewer's Snapshot
/// tool. The tool already keeps a *vector* copy on the in-app clipboard for
/// paste-back; this handler additionally copies the captured PNG raster to the
/// **system** clipboard so it can be pasted into other apps.
///
/// [writer] defaults to the platform [copyPngToClipboard]; tests inject a fake.
/// [onResult] reports whether the copy succeeded (the screen surfaces a toast).
PdfSnapshotHandler clipboardSnapshotHandler({
  ImageClipboardWriter? writer,
  required void Function(bool copied) onResult,
}) {
  final write = writer ?? copyPngToClipboard;
  return (context, snapshot) async {
    bool copied;
    try {
      copied = await write(snapshot.pngBytes);
    } catch (_) {
      copied = false;
    }
    onResult(copied);
  };
}
