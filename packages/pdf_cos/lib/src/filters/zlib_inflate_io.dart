import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Native zlib (archive's `ZLibDecoder` is dart:io's `ZLibCodec` here). It
/// ignores bytes after the zlib stream and throws on a bad header or damaged
/// deflate data.
///
/// Since archive 4.6 the decoder swallows dart:io's trailer check, so the
/// Adler-32 is only compared under `verify`, which costs a pass over the
/// output - [strict] callers (the compactor) pay it, the lenient read path
/// does not, which also matches the web inflater. `verify` additionally
/// rejects a missing or truncated trailer, which is what [strict] means.
Uint8List inflateZlib(Uint8List data, {bool strict = false}) =>
    // decodeBytes already returns a Uint8List; copying it again would double
    // the allocation for every inflated stream in the document (#533).
    strict
        ? const ZLibDecoder().decodeBytes(data, verify: true)
        : const ZLibDecoder().decodeBytes(data, throwOnError: true);
