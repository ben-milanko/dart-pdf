import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:super_clipboard/super_clipboard.dart';

/// Writes PNG-encoded image [bytes] to the system clipboard. Returns true on
/// success, false when the running platform offers no image clipboard.
///
/// Flutter's built-in [Clipboard] only carries text, so putting a picture on
/// the OS clipboard needs a plugin — [super_clipboard]. This typedef is the
/// seam the editor screen injects a fake through in tests (the real plugin's
/// platform channel is unavailable under `flutter test`).
typedef ImageClipboardWriter = Future<bool> Function(Uint8List bytes);

/// The default [ImageClipboardWriter]: hands the PNG [bytes] to the OS
/// clipboard via [super_clipboard]. Returns true once the write completes;
/// [clipboardSnapshotHandler] turns a thrown error (an unsupported platform)
/// into a false result.
Future<bool> copyPngToClipboard(Uint8List bytes) async {
  final item = DataWriterItem()..add(Formats.png(bytes));
  await ClipboardWriter.instance.write([item]);
  return true;
}

/// Builds the [PdfSnapshotHandler] the editor passes to the viewer's Snapshot
/// tool. The tool already keeps a *vector* copy on the in-app clipboard for
/// paste-back; this handler additionally copies the captured PNG raster to the
/// **system** clipboard so it can be pasted into other apps.
///
/// [writer] defaults to [copyPngToClipboard]; tests inject a fake. [onResult]
/// reports whether the copy succeeded (the screen surfaces a toast).
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
