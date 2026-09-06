import 'package:dart_pdf_editor/dart_pdf_editor.dart' show PdfClipboardPdf;
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;

bool get supportsPdfClipboard => switch (defaultTargetPlatform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux =>
        true,
      _ => false,
    };

const _channel = MethodChannel('dev.milanko.dartpdf/image_clipboard');

/// Native [copyPngToClipboard]: hands the PNG [bytes] to the host app, which
/// writes it to the OS clipboard. Returns true once the write completes;
/// [clipboardSnapshotHandler] turns a thrown error (an unsupported platform /
/// missing native binding) into a false result.
Future<bool> copyPngToClipboard(Uint8List bytes) async {
  return await _channel.invokeMethod<bool>('copyPng', bytes) ?? false;
}

/// Reads PNG/JPEG-compatible image bytes from the native system clipboard.
/// Returns null when there is no image or the host platform does not expose
/// one through the app channel.
Future<Uint8List?> readImageFromClipboard() async {
  return await _channel.invokeMethod<Uint8List>('readImage');
}

/// Reads plain text from the native system clipboard. Flutter's [Clipboard]
/// works fine on desktop/mobile, so this just delegates to it (the web variant
/// bypasses it because `Clipboard.getData` is unreliable in the browser).
Future<String?> readTextFromClipboard() async {
  final data = await Clipboard.getData(Clipboard.kTextPlain);
  return data?.text;
}

/// Desktop runners publish both representations in one clipboard update.
/// Older runners and mobile platforms retain the PNG transport.
Future<bool> copySnapshotToClipboard(Uint8List pdf, Uint8List png) async {
  try {
    return await _channel
            .invokeMethod<bool>('copySnapshot', {'pdf': pdf, 'png': png}) ??
        false;
  } on MissingPluginException {
    return copyPngToClipboard(png);
  }
}

/// Reads only PDF data from an external clipboard owner. Native runners
/// recognize their own snapshot write and return null for it.
Future<PdfClipboardPdf?> readPdfFromClipboard() async {
  try {
    final value = await _channel.invokeMapMethod<String, Object?>('readPdf');
    final bytes = value?['pdf'];
    return bytes is Uint8List
        ? PdfClipboardPdf(bytes, changeToken: value?['changeToken'])
        : null;
  } on MissingPluginException {
    return null;
  }
}
