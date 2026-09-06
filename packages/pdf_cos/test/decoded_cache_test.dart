import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

/// A FlateDecode stream over [plaintext].
CosStream _flate(Uint8List plaintext) {
  final compressed = Uint8List.fromList(const ZLibEncoder().encode(plaintext));
  return CosStream(
    CosDictionary({
      'Filter': const CosName('FlateDecode'),
      'Length': CosInteger(compressed.length),
    }),
    compressed,
  );
}

void main() {
  late CosDocument doc;
  late int savedCap;
  late int savedBudget;

  setUp(() {
    // A minimal real document to own the cache; the streams below are decoded
    // through it but need none of its objects.
    doc = CosDocument.open(buildClassicPdf());
    savedCap = CosDocument.decodedStreamCacheItemCapBytes;
    savedBudget = CosDocument.decodedStreamCacheBudgetBytes;
  });

  tearDown(() {
    CosDocument.decodedStreamCacheItemCapBytes = savedCap;
    CosDocument.decodedStreamCacheBudgetBytes = savedBudget;
  });

  group('decoded-stream cache (#392)', () {
    test('a repeat decode returns the very same buffer, decoded once', () {
      final stream = _flate(ascii('one two three four five'));
      final first = doc.decodeStreamData(stream);
      final second = doc.decodeStreamData(stream);
      expect(first, ascii('one two three four five'));
      expect(identical(first, second), isTrue,
          reason: 'the cached buffer is reused, not re-decoded');
      expect(doc.debugDecodedCacheBytes, first.length);
    });

    test('stopBeforeFilter is part of the key', () {
      final stream = _flate(ascii('payload'));
      final decoded = doc.decodeStreamData(stream);
      final raw = doc.decodeStreamData(stream, stopBeforeFilter: 'FlateDecode');
      // Stopping before the flate filter returns the still-compressed bytes -
      // a different result cached under a different key, not the decoded hit.
      expect(identical(decoded, raw), isFalse);
      expect(raw, isNot(decoded));
      // A repeat of each still hits its own entry.
      expect(identical(doc.decodeStreamData(stream), decoded), isTrue);
      expect(
          identical(
              doc.decodeStreamData(stream, stopBeforeFilter: 'FlateDecode'),
              raw),
          isTrue);
    });

    test('a platform decoder can seed an exact cache entry', () {
      final stream = _flate(ascii('portable decoder result'));
      final seeded = ascii('platform decoder result');

      doc.seedDecodedStreamData(stream, seeded);

      expect(identical(doc.decodeStreamData(stream), seeded), isTrue);
      expect(doc.debugDecodedCacheBytes, seeded.length);
      final encoded = doc.decodeStreamData(
        stream,
        stopBeforeFilter: 'FlateDecode',
      );
      expect(identical(encoded, seeded), isFalse,
          reason: 'a seed only populates its exact stop-before key');
    });

    test('an explicitly allowed oversize platform result stays cached', () {
      CosDocument.decodedStreamCacheItemCapBytes = 8;
      final stream = _flate(ascii('portable decoder result'));
      final seeded = ascii('platform decoder result');

      doc.seedDecodedStreamData(stream, seeded, allowOversize: true);

      expect(identical(doc.decodeStreamData(stream), seeded), isTrue);
      expect(doc.debugDecodedCacheBytes, seeded.length);
    });

    test('a different stream object is a cache miss (immutability contract)',
        () {
      final bytes = ascii('same content, different object');
      final a = doc.decodeStreamData(_flate(bytes));
      final b = doc.decodeStreamData(_flate(bytes));
      // Equal bytes, but a fresh CosStream (what an edit produces) does not
      // serve the previous stream's cached buffer.
      expect(b, a);
      expect(identical(a, b), isFalse);
    });

    test('results larger than the item cap are not cached', () {
      CosDocument.decodedStreamCacheItemCapBytes = 8;
      final stream = _flate(ascii('this is well over eight bytes decoded'));
      final first = doc.decodeStreamData(stream);
      final second = doc.decodeStreamData(stream);
      expect(second, first);
      expect(identical(first, second), isFalse,
          reason: 'an over-cap result re-decodes each call');
      expect(doc.debugDecodedCacheBytes, 0);
    });

    test('evicts least-recently-used entries to stay within budget', () {
      // Each decoded payload is 100 bytes; a 250-byte budget holds two.
      final payloads = [
        for (var i = 0; i < 4; i++)
          _flate(Uint8List.fromList(List.filled(100, 0x41 + i)))
      ];
      CosDocument.decodedStreamCacheBudgetBytes = 250;

      final decoded = [for (final s in payloads) doc.decodeStreamData(s)];
      expect(doc.debugDecodedCacheBytes, lessThanOrEqualTo(250));

      // The two most-recently decoded are still cached (same buffer back);
      // the oldest were evicted (re-decode gives a fresh buffer).
      expect(identical(doc.decodeStreamData(payloads[3]), decoded[3]), isTrue);
      expect(identical(doc.decodeStreamData(payloads[0]), decoded[0]), isFalse);
    });
  });
}
