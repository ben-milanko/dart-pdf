import 'dart:typed_data';

/// Off the web a paste key goes to the viewer alone; see browser_paste.dart.
bool get pasteKeyReachesBrowser => false;

void ensureWatching() {}

Future<({Uint8List? image, String? text})?> browserPaste() async => null;
