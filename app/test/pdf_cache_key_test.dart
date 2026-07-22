// The Recent-snapshot content key. It replaced a whole-file SHA-1 that
// measured 171 ms warm on a 24 MB document - more than parsing the file and
// interpreting its first page put together - so the properties that make
// sampling safe are pinned here.
import 'dart:typed_data';

import 'package:dart_pdf_editor_app/pdf_cache_key.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _bytes(int length, {int seed = 1}) {
  final out = Uint8List(length);
  var x = seed;
  for (var i = 0; i < length; i++) {
    x = (x * 1103515245 + 12345) & 0x7FFFFFFF;
    out[i] = x & 0xFF;
  }
  return out;
}

void main() {
  const chunk = 64 * 1024;

  test('the same bytes always produce the same key', () {
    final a = _bytes(5 << 20);
    final b = Uint8List.fromList(a);
    expect(pdfContentKey(a), pdfContentKey(b));
  });

  test('a different length can never collide', () {
    // Identical content, one byte longer: the length prefix separates them
    // even though every sampled window could otherwise coincide.
    final short = Uint8List(4 << 20);
    final long = Uint8List(4 << 20 | 1);
    expect(pdfContentKey(short), isNot(pdfContentKey(long)));
  });

  test('a change in any sampled window changes the key', () {
    final base = _bytes(5 << 20);
    for (final (label, index) in [
      ('head', 10),
      ('middle', (5 << 20) ~/ 2),
      ('tail', (5 << 20) - 10),
    ]) {
      final edited = Uint8List.fromList(base);
      edited[index] ^= 0xFF;
      expect(pdfContentKey(edited), isNot(pdfContentKey(base)),
          reason: 'a $label byte must move the key');
    }
  });

  test('small files are hashed whole, so every byte counts', () {
    final small = _bytes(3 * chunk);
    for (var i = 0; i < small.length; i += 4093) {
      final edited = Uint8List.fromList(small);
      edited[i] ^= 0xFF;
      expect(pdfContentKey(edited), isNot(pdfContentKey(small)),
          reason: 'byte $i must move the key of a fully hashed file');
    }
  });

  test('sampling actually happens above the full-hash limit', () {
    // A byte between the sampled windows is deliberately NOT covered. This
    // pins the documented trade rather than leaving it implicit: if someone
    // later hashes the whole file again, this test tells them they changed
    // the contract, not just an implementation detail.
    final big = _bytes(5 << 20);
    final edited = Uint8List.fromList(big);
    edited[chunk + 1000] ^= 0xFF; // past the head window, before the middle
    expect(pdfContentKey(edited), pdfContentKey(big));
  });

  test('an empty file has a key', () {
    expect(pdfContentKey(Uint8List(0)), isNotEmpty);
  });

  test('files shorter than one window still work', () {
    expect(pdfContentKey(_bytes(10)), isNot(pdfContentKey(_bytes(11))));
  });
}
