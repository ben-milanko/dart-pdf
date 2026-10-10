import 'dart:typed_data';

/// No file system: the web draft is recorded from the page instead.
Future<String?> prepareFrameDirectory() async => null;

Future<void> writeFrame(String directory, int frame, Uint8List png) async {}
