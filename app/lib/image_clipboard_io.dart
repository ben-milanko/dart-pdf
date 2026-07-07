import 'package:flutter/services.dart';

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
