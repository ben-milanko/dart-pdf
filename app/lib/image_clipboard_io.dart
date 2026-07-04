import 'dart:typed_data';

import 'package:super_clipboard/super_clipboard.dart';

/// Native [copyPngToClipboard]: hands the PNG [bytes] to the OS clipboard via
/// super_clipboard (macOS, Windows, Linux, iOS, Android). Returns true once
/// the write completes; [clipboardSnapshotHandler] turns a thrown error (an
/// unsupported platform / missing native binding) into a false result.
Future<bool> copyPngToClipboard(Uint8List bytes) async {
  final item = DataWriterItem()..add(Formats.png(bytes));
  await ClipboardWriter.instance.write([item]);
  return true;
}
