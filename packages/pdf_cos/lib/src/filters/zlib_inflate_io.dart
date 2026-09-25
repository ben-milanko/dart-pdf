import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Native zlib (archive's `ZLibDecoder` is dart:io's `ZLibCodec` here). It
/// already ignores bytes after the zlib stream and rejects a bad header or a
/// wrong Adler-32 on its own, so [strict] is not consulted.
Uint8List inflateZlib(Uint8List data, {bool strict = false}) =>
    // decodeBytes already returns a Uint8List; copying it again would double
    // the allocation for every inflated stream in the document (#533).
    const ZLibDecoder().decodeBytes(data);
