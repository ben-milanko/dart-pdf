import 'dart:typed_data';

import 'browser_paste_stub.dart'
    if (dart.library.js_interop) 'browser_paste_web.dart' as platform;

/// What a browser paste event carried: the first PNG/JPEG file and the plain
/// text, either of which may be missing.
class PdfBrowserPaste {
  const PdfBrowserPaste({this.image, this.text});

  final Uint8List? image;
  final String? text;
}

/// Whether ⌘V/Ctrl+V should reach the browser as well as the viewer's paste
/// action: true on the web, where the browser's paste event is the one
/// clipboard read that needs no permission.
bool get pdfPasteKeyReachesBrowser => platform.pasteKeyReachesBrowser;

/// Starts watching for keyboard pastes; idempotent, and a no-op off the web.
/// The viewer calls it when it mounts.
void ensurePdfBrowserPasteWatch() => platform.ensureWatching();

/// The clipboard as the browser's paste event for the current keyboard paste
/// delivered it, or null when no keyboard paste is in flight (a context-menu
/// Paste, or off the web) or the browser fired none - then read the clipboard
/// another way.
///
/// The paste event needs no clipboard-read permission, unlike
/// `navigator.clipboard.read()`, which fails silently once its prompt has
/// been dismissed. Every read of one paste (image, then text) gets the same
/// payload.
Future<PdfBrowserPaste?> pdfBrowserPaste() async {
  final read = await platform.browserPaste();
  return read == null
      ? null
      : PdfBrowserPaste(image: read.image, text: read.text);
}
