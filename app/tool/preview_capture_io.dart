import 'dart:io';
import 'dart:typed_data';

/// A fresh directory for the captured frames, in the app's temporary
/// directory (on the simulator that is a folder on the host's disk).
Future<String?> prepareFrameDirectory() async {
  final dir = Directory('${Directory.systemTemp.path}/preview-frames');
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);
  return dir.path;
}

/// Writes tour frame [frame] as `<directory>/NNNNNN.png`.
Future<void> writeFrame(String directory, int frame, Uint8List png) =>
    File('$directory/${frame.toString().padLeft(6, '0')}.png')
        .writeAsBytes(png, flush: true);
