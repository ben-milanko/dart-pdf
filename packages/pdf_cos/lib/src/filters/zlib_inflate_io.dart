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
///
/// The lenient path - every FlateDecode stream a page reads - goes through
/// `decodeStream` into [InflatedChunks] rather than `decodeBytes`. They run
/// the same native inflate under the same error rules; `decodeBytes` then
/// copies each piece of output into a buffer that starts at 32 KB and doubles
/// (copying again each time), and copies the result once more when that buffer
/// ends up less than half full. Collecting the pieces and joining them once
/// measured 10-30% off inflating a page's content or a scanned image.
Uint8List inflateZlib(Uint8List data, {bool strict = false}) {
  if (strict) return const ZLibDecoder().decodeBytes(data, verify: true);
  final output = InflatedChunks();
  // Throws on damaged data, as decodeBytes(throwOnError: true) does, so a
  // false return never gets here.
  const ZLibDecoder()
      .decodeStream(InputMemoryStream(data), output, throwOnError: true);
  return output.takeBytes();
}

/// archive's `OutputStream` that keeps the pieces the native decoder hands it
/// and joins them once, at their exact total size.
///
/// The decoder writes each piece as a list of its own (dart:io allocates one
/// per call into zlib, and `Sink.add` lets the receiver keep what it is
/// given), so a piece is held, not copied. A stream that inflates to a single
/// piece - most content streams and nearly every small object - is returned
/// as that piece, with no copy at all.
///
/// Public only so the tests can reach the branches the native decoder never
/// takes (a partial write, a view, a plain list); nothing exports this file.
class InflatedChunks extends OutputStream {
  InflatedChunks() : super(byteOrder: ByteOrder.littleEndian);

  final List<Uint8List> _chunks = [];

  @override
  int length = 0;

  @override
  void clear() {
    _chunks.clear();
    length = 0;
  }

  @override
  void flush() {}

  @override
  void writeByte(int value) {
    _chunks.add(Uint8List(1)..[0] = value);
    length++;
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    final count = length ?? bytes.length;
    if (count == 0) return;
    // Held as given only when it is a whole byte list of its own: a partial
    // write, a view into a larger buffer or any other list is copied, so the
    // result can never alias - or pin - memory it was not handed outright.
    final own = bytes is Uint8List &&
        count == bytes.length &&
        bytes.lengthInBytes == bytes.buffer.lengthInBytes;
    _chunks.add(own
        ? bytes
        : Uint8List.fromList(
            count == bytes.length ? bytes : bytes.sublist(0, count)));
    this.length += count;
  }

  @override
  void writeStream(InputStream stream) =>
      writeBytes(Uint8List.fromList(stream.toUint8List()));

  @override
  Uint8List subset(int start, [int? end]) {
    if (start < 0) start += length;
    end ??= length;
    if (end < 0) end += length;
    return Uint8List.sublistView(takeBytes(), start, end);
  }

  /// The inflated bytes in a buffer of exactly their size.
  Uint8List takeBytes() {
    if (_chunks.isEmpty) return Uint8List(0);
    if (_chunks.length == 1) return _chunks.first;
    final out = Uint8List(length);
    var at = 0;
    for (final chunk in _chunks) {
      out.setRange(at, at + chunk.length, chunk);
      at += chunk.length;
    }
    // Later calls (subset) reuse the joined buffer instead of joining again.
    _chunks
      ..clear()
      ..add(out);
    return out;
  }
}
