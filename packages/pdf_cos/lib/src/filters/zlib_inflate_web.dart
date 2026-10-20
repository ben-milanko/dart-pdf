import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Pure-Dart zlib for the web, tolerant of bytes after the stream.
///
/// archive's `ZLibDecoder` on the web loops "while not at end of input": a
/// trailing CR/LF after the Adler-32 is read as the header of a second zlib
/// stream, fails the header check, and the whole decode returns nothing. A
/// missing Adler-32 throws a RangeError. Native zlib (and pdf.js) stop at the
/// final deflate block instead, so this does the same: check the 2-byte zlib
/// header, run archive's `Inflate` over the body, and ignore what follows.
///
/// A header that is not zlib keeps archive's behaviour (an empty result);
/// no raw-deflate leniency is added that the VM does not have. [strict] makes
/// that, a truncated stream, or an Adler-32 that is missing or wrong throw a
/// [FormatException] instead of returning what was recovered.
Uint8List inflateZlib(Uint8List data, {bool strict = false}) {
  if (!_isZlibHeader(data)) {
    if (strict) throw const FormatException('Not a zlib stream');
    // What archive's decoder does here on the web (named explicitly so the
    // VM tests of this file see the same).
    return const ZLibDecoderWeb().decodeBytes(data);
  }
  final input = InputMemoryStream(data, offset: 2);
  final output = _PdfInflateOutput(data.length * 4);
  Inflate.stream(input, output: output);
  final inflated = output.takeBytes();
  if (strict) {
    // Inflate stops on the byte after the final block, where RFC 1950 puts
    // the big-endian Adler-32 of the uncompressed data. A damaged or
    // truncated body leaves it pointing elsewhere, so this catches those too.
    final at = 2 + input.position;
    if (at + 4 > data.length) {
      throw const FormatException('Truncated zlib stream');
    }
    final stored =
        data[at] << 24 | data[at + 1] << 16 | data[at + 2] << 8 | data[at + 3];
    if (stored != getAdler32(inflated)) {
      throw const FormatException('zlib Adler-32 mismatch');
    }
  }
  return inflated;
}

/// CMF/FLG: deflate (CM 8) with a window of at most 32 KB (CINFO <= 7), a
/// valid FCHECK, and no preset dictionary (PDF never uses one).
bool _isZlibHeader(Uint8List data) {
  if (data.length < 2) return false;
  final cmf = data[0];
  final flg = data[1];
  return (cmf & 0x0f) == 8 &&
      (cmf >> 4) <= 7 &&
      (cmf << 8 | flg) % 31 == 0 &&
      (flg & 0x20) == 0;
}

/// archive's `OutputStream` over a growable [Uint8List].
///
/// Unlike `OutputMemoryStream`, a short back-reference is a byte loop.
/// Deflate matches are mostly a few bytes long, and on dart2js each
/// `setRange` allocates a typed-array view, which made the per-match copy
/// the hot spot of web inflate.
class _PdfInflateOutput extends OutputStream {
  _PdfInflateOutput(int sizeHint)
      : _buffer = Uint8List(sizeHint.clamp(_minCapacity, _maxInitialCapacity)),
        super(byteOrder: ByteOrder.littleEndian);

  static const _minCapacity = 1024;

  /// A huge payload starts here and doubles, rather than allocating 4x a
  /// poorly compressed image up front.
  static const _maxInitialCapacity = 16 << 20;

  /// Matches at least this long, that do not overlap what they copy, use
  /// `setRange`; anything shorter is cheaper as a loop.
  static const _bulkCopyMin = 64;

  Uint8List _buffer;

  @override
  int length = 0;

  void _reserve(int extra) {
    final need = length + extra;
    if (need <= _buffer.length) return;
    var capacity = _buffer.length * 2;
    if (capacity < need) capacity = need;
    _buffer = Uint8List(capacity)..setRange(0, length, _buffer);
  }

  @override
  void clear() => length = 0;

  @override
  void flush() {}

  @override
  void writeByte(int value) {
    if (length == _buffer.length) _reserve(1);
    _buffer[length++] = value;
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    final count = length ?? bytes.length;
    _reserve(count);
    _buffer.setRange(this.length, this.length + count, bytes);
    this.length += count;
  }

  @override
  void writeStream(InputStream stream) {
    final count = stream.length;
    _reserve(count);
    if (stream is InputMemoryStream) {
      final source = stream.buffer;
      if (source != null) {
        _buffer.setRange(length, length + count, source, stream.position);
      }
    } else {
      _buffer.setRange(length, length + count, stream.toUint8List());
    }
    length += count;
  }

  @override
  void writeBackReference(int distance, int count) {
    _reserve(count);
    final buffer = _buffer;
    final end = length + count;
    if (count >= _bulkCopyMin && distance >= count) {
      buffer.setRange(length, end, buffer, length - distance);
    } else {
      // Also correct for an overlapping (run-length) match: each byte copied
      // is read back once the source catches up with it.
      var from = length - distance;
      var to = length;
      while (to < end) {
        buffer[to++] = buffer[from++];
      }
    }
    length = end;
  }

  @override
  Uint8List subset(int start, [int? end]) {
    if (start < 0) start += length;
    end ??= length;
    if (end < 0) end += length;
    return Uint8List.sublistView(_buffer, start, end);
  }

  /// The inflated bytes, copied into a buffer of their own size unless the
  /// spare capacity is under 1/16 of them. A decoded stream can live on in
  /// a cache, and must not keep the size hint's or a doubling's slack alive
  /// with it (archive's web decoder finished with a copy as well).
  Uint8List takeBytes() {
    final bytes = Uint8List.sublistView(_buffer, 0, length);
    return _buffer.length - length <= length >> 4
        ? bytes
        : Uint8List.fromList(bytes);
  }
}
