import 'dart:js_interop';

import 'incoming_file.dart';

/// One launched file delivered from `index.html`'s launch-queue consumer:
/// `{ name: string, bytes: Uint8Array }`.
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

void startWebLaunchQueue(void Function(IncomingFile) onFile) {
  // The bridge always exists when index.html loaded our snippet; guard anyway.
  if (_bridge == null) return;
  void onEntry(_LaunchEntry entry) {
    onFile(IncomingFile(name: entry.name, bytes: entry.bytes.toDart));
  }
  _drainLaunchFiles(onEntry.toJS);
}
