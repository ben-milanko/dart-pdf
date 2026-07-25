// #451: a worker records the same page several times in one scroll, and each
// serialize re-decoded every image - one device page paid ~900ms of pure-Dart
// CMYK decode three times. These pin that the cache reuses a decode, that reuse
// is byte-identical to decoding again, and that it never serves the wrong
// pixels for a different target size.
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:test/test.dart';

CosStream _stream(int marker) => CosStream(
      CosDictionary({
        'Width': const CosInteger(2),
        'Height': const CosInteger(2),
        'Marker': CosInteger(marker),
      }),
      Uint8List.fromList([marker]),
    );

PdfDecodedPixels _pixels(int fill, {int width = 2, int height = 2}) =>
    PdfDecodedPixels(
      Uint8List.fromList(List.filled(width * height * 4, fill)),
      width,
      height,
    );

void main() {
  group('PdfImageDecodeCache (#451)', () {
    test('a second record of the same page reuses the first decode', () {
      final cache = PdfImageDecodeCache();
      final stream = _stream(1);
      var decodes = 0;
      PdfDecodedPixels? decode() {
        decodes++;
        return _pixels(7);
      }

      final first = cache.decode(stream, 64, 64, decode);
      final second = cache.decode(stream, 64, 64, decode);

      expect(decodes, 1, reason: 'the second record must not decode again');
      expect(identical(first, second), isTrue);
      expect(cache.hits, 1);
      expect(cache.misses, 1);
    });

    test('a different target size decodes separately', () {
      final cache = PdfImageDecodeCache();
      final stream = _stream(1);
      var decodes = 0;
      // A thumbnail tile asks for a smaller target than the full-page record.
      // Serving it the page-sized entry would ship the wrong pixel count.
      final page = cache.decode(stream, 64, 64, () {
        decodes++;
        return _pixels(1, width: 64, height: 64);
      });
      final tile = cache.decode(stream, 8, 8, () {
        decodes++;
        return _pixels(2, width: 8, height: 8);
      });

      expect(decodes, 2);
      expect(page!.width, 64);
      expect(tile!.width, 8);
    });

    test('native resolution is its own key, distinct from a sized target', () {
      final cache = PdfImageDecodeCache();
      final stream = _stream(1);
      var decodes = 0;
      cache.decode(stream, null, null, () {
        decodes++;
        return _pixels(1);
      });
      cache.decode(stream, 2, 2, () {
        decodes++;
        return _pixels(2);
      });
      expect(decodes, 2);
    });

    test('two streams of identical shape do not share an entry', () {
      // CosStream has no ==, so the key is object identity - two loaded
      // streams that happen to look alike are different images.
      final cache = PdfImageDecodeCache();
      var decodes = 0;
      final a = cache.decode(_stream(1), 2, 2, () {
        decodes++;
        return _pixels(1);
      });
      final b = cache.decode(_stream(1), 2, 2, () {
        decodes++;
        return _pixels(2);
      });
      expect(decodes, 2);
      expect(a!.rgba.first, 1);
      expect(b!.rgba.first, 2);
    });

    test('a decline is not cached', () {
      final cache = PdfImageDecodeCache();
      final stream = _stream(1);
      var decodes = 0;
      final first = cache.decode(stream, 2, 2, () {
        decodes++;
        return null;
      });
      final second = cache.decode(stream, 2, 2, () {
        decodes++;
        return _pixels(3);
      });
      expect(first, isNull);
      expect(decodes, 2, reason: 'a decline must not pin the failure');
      expect(second, isNotNull);
    });

    test('evicts least-recently-used once over budget', () {
      // 4 pixels x 4 bytes = 16 bytes per entry; hold two.
      final cache = PdfImageDecodeCache(maxBytes: 40);
      final a = _stream(1), b = _stream(2), c = _stream(3);
      cache.decode(a, 2, 2, () => _pixels(1));
      cache.decode(b, 2, 2, () => _pixels(2));
      // Touch a so b becomes the least recently used.
      cache.decode(a, 2, 2, () => fail('a should still be cached'));
      cache.decode(c, 2, 2, () => _pixels(3));

      expect(cache.bytes, lessThanOrEqualTo(40));
      var decoded = 0;
      cache.decode(a, 2, 2, () {
        decoded++;
        return _pixels(1);
      });
      expect(decoded, 0, reason: 'a was touched most recently, so it survives');
      cache.decode(b, 2, 2, () {
        decoded++;
        return _pixels(2);
      });
      expect(decoded, 1, reason: 'b was the least recently used, so it went');
    });

    test('an image bigger than the whole budget is not cached', () {
      final cache = PdfImageDecodeCache(maxBytes: 16);
      final stream = _stream(1);
      var decodes = 0;
      PdfDecodedPixels? decode() {
        decodes++;
        return _pixels(1, width: 8, height: 8); // 256 bytes
      }

      expect(cache.decode(stream, 8, 8, decode), isNotNull);
      expect(cache.decode(stream, 8, 8, decode), isNotNull);
      // It still decodes correctly - it just never evicts everything else to
      // sit alone in the cache.
      expect(decodes, 2);
      expect(cache.bytes, 0);
    });

    test('clear drops everything', () {
      final cache = PdfImageDecodeCache();
      final stream = _stream(1);
      cache.decode(stream, 2, 2, () => _pixels(1));
      cache.clear();
      expect(cache.bytes, 0);
      expect(cache.length, 0);
      var decodes = 0;
      cache.decode(stream, 2, 2, () {
        decodes++;
        return _pixels(1);
      });
      expect(decodes, 1);
    });
  });
}
