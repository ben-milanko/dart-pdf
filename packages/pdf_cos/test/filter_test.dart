import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

void main() {
  group('FlateDecode', () {
    test('round-trips zlib data', () {
      final original = ascii('Hello hello hello hello hello');
      final compressed =
          Uint8List.fromList(const ZLibEncoder().encode(original));
      final stream = CosStream(
        CosDictionary({
          'Filter': const CosName('FlateDecode'),
          'Length': CosInteger(compressed.length),
        }),
        compressed,
      );
      expect(decodeStream(stream), original);
    });

    test('applies PNG up-predictor', () {
      // two rows of 4 columns; row 2 uses filter 2 (Up)
      final raw = Uint8List.fromList([
        0, 1, 2, 3, 4, // row 1: None
        2, 1, 1, 1, 1, // row 2: Up
      ]);
      final compressed = Uint8List.fromList(const ZLibEncoder().encode(raw));
      final stream = CosStream(
        CosDictionary({
          'Filter': const CosName('FlateDecode'),
          'DecodeParms': CosDictionary({
            'Predictor': const CosInteger(12),
            'Columns': const CosInteger(4),
          }),
        }),
        compressed,
      );
      expect(decodeStream(stream), [1, 2, 3, 4, 2, 3, 4, 5]);
    });

    test('applies TIFF horizontal differencing to 16-bit samples', () {
      // Three two-channel pixels. Predictor 2 stores each 16-bit component
      // after the first pixel as a modulo-65536 delta from its left neighbor.
      final predicted = Uint8List.fromList([
        0x01,
        0x02,
        0x03,
        0x04,
        0x10,
        0x20,
        0x20,
        0x30,
        0xEE,
        0xDD,
        0xDC,
        0xCD,
      ]);
      final compressed =
          Uint8List.fromList(const ZLibEncoder().encode(predicted));
      final stream = CosStream(
        CosDictionary({
          'Filter': const CosName('FlateDecode'),
          'DecodeParms': CosDictionary({
            'Predictor': const CosInteger(2),
            'Colors': const CosInteger(2),
            'BitsPerComponent': const CosInteger(16),
            'Columns': const CosInteger(3),
          }),
        }),
        compressed,
      );
      expect(decodeStream(stream), [
        0x01,
        0x02,
        0x03,
        0x04,
        0x11,
        0x22,
        0x23,
        0x34,
        0xFF,
        0xFF,
        0x00,
        0x01,
      ]);
    });
  });

  test('ASCIIHexDecode', () {
    const filter = AsciiHexFilter();
    expect(filter.decode(ascii('48656C6C6F>'), null), ascii('Hello'));
    expect(filter.decode(ascii('90 1F A>'), null), [0x90, 0x1F, 0xA0]);
  });

  group('ASCII85Decode', () {
    const filter = Ascii85Filter();

    test('full group', () {
      expect(filter.decode(ascii('9jqo^~>'), null), ascii('Man '));
    });

    test('partial group', () {
      expect(filter.decode(ascii('9jqo~>'), null), ascii('Man'));
    });

    test('z shorthand', () {
      expect(filter.decode(ascii('z~>'), null), [0, 0, 0, 0]);
    });
  });

  group('LZWDecode', () {
    const filter = LzwFilter();

    test('decodes the spec example (§7.4.4.2)', () {
      // input 45 45 45 45 45 65 45 45 45 66 (decimal) encodes to the
      // code sequence 256 45 258 258 65 259 66 257
      final encoded = Uint8List.fromList(
          [0x80, 0x0B, 0x60, 0x50, 0x22, 0x0C, 0x0C, 0x85, 0x01]);
      expect(filter.decode(encoded, null),
          [45, 45, 45, 45, 45, 65, 45, 45, 45, 66]);
    });

    test('handles a code defined by the step that uses it (KwKwK)', () {
      // "AAAAA" encodes to 256 65 258 258 257, where the first 258 is
      // emitted in the same step that defines it
      final encoded = Uint8List.fromList([0x80, 0x10, 0x60, 0x50, 0x28, 0x08]);
      expect(filter.decode(encoded, null), [65, 65, 65, 65, 65]);
    });

    test('runs as a stream filter with a predictor', () {
      final stream = CosStream(
        CosDictionary({
          'Filter': const CosName('LZWDecode'),
          'DecodeParms': CosDictionary({
            'Predictor': const CosInteger(2), // TIFF horizontal differencing
            'Columns': const CosInteger(10),
          }),
        }),
        Uint8List.fromList(
            [0x80, 0x0B, 0x60, 0x50, 0x22, 0x0C, 0x0C, 0x85, 0x01]),
      );
      // TIFF predictor 2: each byte is a delta from its left neighbor
      expect(
          decodeStream(stream), [45, 90, 135, 180, 225, 34, 79, 124, 169, 235]);
    });
  });

  test('RunLengthDecode', () {
    const filter = RunLengthFilter();
    // copy 2 literal bytes, repeat '!' three times, EOD
    final encoded = Uint8List.fromList([1, 0x48, 0x69, 254, 0x21, 128]);
    expect(filter.decode(encoded, null), ascii('Hi!!!'));
    // data after EOD is ignored
    final padded = Uint8List.fromList([0, 0x41, 128, 0x42, 0x42]);
    expect(filter.decode(padded, null), ascii('A'));
  });

  test('filter chains apply in order', () {
    final original = ascii('chained data chained data');
    final compressed = const ZLibEncoder().encode(original);
    final hex =
        compressed.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final stream = CosStream(
      CosDictionary({
        'Filter': CosArray([
          const CosName('ASCIIHexDecode'),
          const CosName('FlateDecode'),
        ]),
      }),
      ascii('$hex>'),
    );
    expect(decodeStream(stream), original);
  });

  test('unknown filters throw UnsupportedFilterException', () {
    final stream = CosStream(
      CosDictionary({'Filter': const CosName('JBIG2Decode')}),
      Uint8List(0),
    );
    expect(
        () => decodeStream(stream), throwsA(isA<UnsupportedFilterException>()));
  });

  test('stopBeforeFilter unwraps outer filters, keeps the rest encoded', () {
    // a "JPEG" wrapped in Flate: [/FlateDecode /DCTDecode]
    final fakeJpeg = ascii('JFIF-payload');
    final wrapped = Uint8List.fromList(const ZLibEncoder().encode(fakeJpeg));
    final stream = CosStream(
      CosDictionary({
        'Filter': CosArray([
          const CosName('FlateDecode'),
          const CosName('DCTDecode'),
        ]),
      }),
      wrapped,
    );
    expect(decodeStream(stream, stopBeforeFilter: 'DCTDecode'), fakeJpeg);
    // without the stop, the unsupported DCT stage throws
    expect(
        () => decodeStream(stream), throwsA(isA<UnsupportedFilterException>()));
  });
}
