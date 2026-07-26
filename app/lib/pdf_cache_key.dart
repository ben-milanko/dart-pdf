import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Bytes sampled from each of the three probe positions.
const int _chunk = 64 * 1024;

/// Files at or below this size are hashed whole - sampling saves nothing and
/// the full hash is the stronger key.
const int _fullHashLimit = 3 * _chunk;

/// A stable content key for a picked PDF, used to name its Recent snapshot.
///
/// Hashing the whole file is the obvious implementation and was the original
/// one, but it is the single most expensive step in opening a large document:
/// on a 24 MB, 62-page book it measured **171 ms warm**, against 3 ms to parse
/// the document, 3 ms to reach page 1's content, and 2 ms to interpret it - so
/// the snapshot key cost more than everything the user was actually waiting
/// for, and it scales with file size while the rest does not.
///
/// This samples instead: the length, then up to three 64 KiB windows (head,
/// middle, tail). Same bytes always produce the same key, which is all the
/// Recent store needs - it dedupes re-picks of one file and gives a stable
/// identity across sessions. It is deliberately **not** a cryptographic
/// checksum of the file, and nothing security-bearing may use it.
///
/// The length is mixed in first, so two files of different sizes can never
/// collide however similar their sampled windows. Two same-length PDFs that
/// agree across all three windows would collide; for a store whose worst
/// failure is reopening the wrong Recent entry, that is an acceptable trade
/// for an ~80x saving on the open path.
String pdfContentKey(Uint8List bytes) {
  final length = bytes.length;
  if (length <= _fullHashLimit) {
    return '${length}_${sha1.convert(bytes)}';
  }
  // One 192 KiB sample buffer: the copy is immaterial next to the hash, and
  // it keeps this readable against a chunked-conversion sink.
  final middle = ((length - _chunk) ~/ 2).clamp(0, length - _chunk);
  final sample = Uint8List(3 * _chunk);
  sample.setRange(0, _chunk, bytes, 0);
  sample.setRange(_chunk, 2 * _chunk, bytes, middle);
  sample.setRange(2 * _chunk, 3 * _chunk, bytes, length - _chunk);
  return '${length}_${sha1.convert(sample)}';
}
