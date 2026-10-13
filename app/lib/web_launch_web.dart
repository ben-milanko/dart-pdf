import 'dart:js_interop';

import 'incoming_file.dart';

/// One launched file delivered from `index.html`'s launch-queue consumer:
/// `{ name: string, bytes: Uint8Array }`. Each launch arrives as an array of
/// these - every file the user opened together.
extension type _LaunchEntry(JSObject _) implements JSObject {
  external String get name;
  external JSUint8Array get bytes;
}

/// Registers our consumer with the bridge `index.html` installs; the bridge
/// replays any files queued before Flutter started, then forwards later ones.
@JS('__dartPdfDrainLaunchFiles')
external void _drainLaunchFiles(JSFunction callback);

@JS('__dartPdfDrainLaunchFiles')
external JSAny? get _bridge;

void startWebLaunchQueue(void Function(List<IncomingFile>) onFiles) {
  // The bridge always exists when index.html loaded our snippet; guard anyway.
  if (_bridge == null) return;
  void onLaunch(JSArray<_LaunchEntry> entries) {
    onFiles([
      for (final entry in entries.toDart)
        IncomingFile(name: entry.name, bytes: entry.bytes.toDart),
    ]);
  }

  _drainLaunchFiles(onLaunch.toJS);
}
