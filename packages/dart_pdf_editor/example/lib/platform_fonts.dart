// Discovers the host platform's installed fonts so the editor's font menu
// can offer them as embeddable choices by default (see the library's
// `pdfPlatformFonts` registry).
//
// The library never reads font files itself (`dart:io` is banned in its
// `lib/` so it keeps running on the web): discovery is a host seam. A
// conditional import gives native targets a real filesystem scanner and the
// web an empty list — there are no readable OS font files to embed there.
export 'platform_fonts_stub.dart'
    if (dart.library.io) 'platform_fonts_io.dart';
