// Discovers the host platform's installed fonts so the editor's font menu
// can offer them as embeddable choices by default.
//
// The editor library never reads font files itself (`dart:io` is banned in
// its `lib/` so it keeps running on the web): platform-font discovery is a
// host seam, populated into `pdfPlatformFonts`. A conditional import gives
// native targets a real filesystem scanner and the web (and any other
// dart:io-less target) an empty list — there are no readable OS font files
// to embed there.
export 'platform_fonts_stub.dart'
    if (dart.library.io) 'platform_fonts_io.dart';
