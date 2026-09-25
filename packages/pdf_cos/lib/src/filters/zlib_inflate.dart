/// Inflates a zlib stream (RFC 1950): `inflateZlib(data, {strict})`.
///
/// Every zlib payload in the stack (FlateDecode, the compactor's re-deflate,
/// PNG IDAT) goes through this one helper, so the VM and the web cannot drift
/// apart again:
///
/// - VM/native: archive's `ZLibDecoder`, which there is dart:io's zlib.
/// - Web (dart2js/dart2wasm): archive's pure-Dart `Inflate` over the deflate
///   body, stopping at the final block the way zlib does. archive's own web
///   decoder reads any bytes after the Adler-32 - a trailing CR/LF before
///   `endstream` - as a second zlib stream, fails that "header" and returns
///   nothing for the whole stream: blank pages, missing fonts, and an empty
///   stream written back by Reduce file size.
///
/// With `strict: true` the web path also requires the Adler-32 and checks it,
/// throwing a [FormatException] on a bad header, truncation or a mismatch.
/// That is for callers that must not mistake damaged data for a clean decode
/// (the compactor, which preserves such streams byte for byte).
library;

export 'zlib_inflate_io.dart'
    if (dart.library.js_interop) 'zlib_inflate_web.dart';
