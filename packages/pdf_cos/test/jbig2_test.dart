import 'dart:io';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:test/test.dart';

/// The same 64x24 monochrome test image as the CCITT suite, encoded by
/// jbig2enc. The generic stream is lossless (expected raster = source);
/// symbol mode is lossy, so its expected raster is what the reference
/// decoder (jbig2dec) produces for the same data. PDF polarity: black
/// pixels are 0 bits.

const _genericExpected = [
  255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
  255, 255, 255, 255, 252, 31, 127, 255, 255, 255, 255, 255, 252, 31, 191,
  255, 255, 240, 0, 7, 252, 31, 223, 255, 255, 240, 0, 7, 252, 31, 239, 255,
  255, 240, 0, 7, 252, 31, 255, 255, 255, 240, 0, 7, 252, 31, 255, 255, 255,
  240, 0, 7, 252, 31, 254, 255, 255, 240, 0, 7, 252, 31, 255, 127, 255, 240,
  0, 7, 252, 31, 255, 191, 255, 240, 0, 7, 252, 31, 255, 223, 255, 240, 0,
  7, 252, 31, 255, 239, 255, 255, 255, 255, 252, 31, 255, 247, 255, 255,
  255, 255, 252, 31, 255, 251, 255, 255, 255, 255, 252, 31, 255, 255, 255,
  255, 255, 255, 252, 31, 255, 255, 255, 255, 255, 255, 252, 31, 255, 255,
  191, 255, 255, 255, 252, 31, 255, 255, 223, 255, 255, 255, 252, 31, 255,
  255, 239, 255, 255, 255, 252, 31, 255, 255, 247, 255, 255, 255, 255, 255,
  255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
  255, 255, 255, 255,
];

const _symbolExpected = [
  255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 252, 31, 255, 255,
  255, 255, 255, 255, 252, 31, 127, 255, 255, 224, 0, 15, 252, 31, 191, 255,
  255, 224, 0, 15, 252, 31, 223, 255, 255, 224, 0, 15, 252, 31, 239, 255,
  255, 224, 0, 15, 252, 31, 255, 255, 255, 224, 0, 15, 252, 31, 255, 255,
  255, 224, 0, 15, 252, 31, 254, 255, 255, 224, 0, 15, 252, 31, 255, 127,
  255, 224, 0, 15, 252, 31, 255, 191, 255, 224, 0, 15, 252, 31, 255, 223,
  255, 255, 255, 255, 252, 31, 255, 239, 255, 255, 255, 255, 252, 31, 255,
  247, 255, 255, 255, 255, 252, 31, 255, 251, 255, 255, 255, 255, 252, 31,
  255, 255, 255, 255, 255, 255, 252, 31, 255, 255, 255, 255, 255, 255, 252,
  31, 255, 255, 191, 255, 255, 255, 252, 31, 255, 255, 223, 255, 255, 255,
  252, 31, 255, 255, 239, 255, 255, 255, 255, 255, 255, 255, 247, 255, 255,
  255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
  255, 255, 255, 255, 255, 255, 255,
];

const _genericEmbedded = [
  0, 0, 0, 0, 48, 0, 1, 0, 0, 0, 19, 0, 0, 0, 64, 0, 0, 0, 24, 0, 0, 0, 0,
  0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 38, 0, 1, 0, 0, 0, 60, 0, 0, 0, 64, 0, 0,
  0, 24, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 255, 253, 255, 2, 254, 254, 254,
  166, 9, 136, 71, 171, 62, 142, 34, 67, 252, 32, 123, 51, 79, 25, 243, 25,
  24, 78, 234, 161, 31, 181, 191, 215, 14, 37, 247, 174, 242, 123, 103, 255,
  172,
];

const _symbolGlobals = [
  0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 41, 0, 0, 3, 255, 253, 255, 2, 254, 254,
  254, 0, 0, 0, 4, 0, 0, 0, 4, 85, 82, 55, 183, 56, 30, 214, 116, 64, 103,
  36, 66, 172, 231, 67, 88, 194, 157, 165, 26, 123, 255, 172,
];

const _symbolPage = [
  0, 0, 0, 1, 48, 0, 1, 0, 0, 0, 19, 0, 0, 0, 64, 0, 0, 0, 24, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 6, 34, 0, 1, 0, 0, 0, 38, 0, 0, 0, 64, 0,
  0, 0, 24, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 159, 117, 238, 240,
  241, 108, 197, 150, 89, 20, 32, 28, 127, 255, 172,
];

void main() {
  test('arithmetic generic regions decode losslessly', () {
    final out = Jbig2Decoder.decode(
      data: Uint8List.fromList(_genericEmbedded),
      width: 64,
      height: 24,
    );
    expect(out, _genericExpected);
  });

  test('symbol dictionaries + text regions match the reference decoder', () {
    final out = Jbig2Decoder.decode(
      data: Uint8List.fromList(_symbolPage),
      globals: Uint8List.fromList(_symbolGlobals),
      width: 64,
      height: 24,
    );
    expect(out, _symbolExpected);
  });

  test('halftone regions render PDF.js bitmap-halftone corpus image', () {
    final raw = _pdfjsImageData('bitmap-halftone.pdf', 'Im');
    final out = Jbig2Decoder.decode(
      data: raw,
      width: 399,
      height: 400,
    );
    expect(out, isNotNull);
    expect(_blackPixelCount(out!, 399, 400), 10950);
    expect(_isBlack(out, 399, 259, 78), isTrue);
    expect(_isBlack(out, 399, 270, 79), isTrue);
    expect(_isBlack(out, 399, 200, 150), isTrue);
    expect(_isBlack(out, 399, 0, 0), isFalse);
    expect(_isBlack(out, 399, 250, 90), isFalse);
    expect(_isBlack(out, 399, 398, 399), isFalse);
  });

  test('generic refinement regions render PDF.js bitmap-refine corpus image',
      () {
    final raw = _pdfjsImageData('bitmap-refine.pdf', 'Im');
    final out = Jbig2Decoder.decode(
      data: raw,
      width: 399,
      height: 400,
    );
    expect(out, isNotNull);
    expect(_blackPixelCount(out!, 399, 400), 10950);
    expect(_isBlack(out, 399, 259, 78), isTrue);
    expect(_isBlack(out, 399, 270, 79), isTrue);
    expect(_isBlack(out, 399, 200, 150), isTrue);
    expect(_isBlack(out, 399, 0, 0), isFalse);
    expect(_isBlack(out, 399, 250, 90), isFalse);
    expect(_isBlack(out, 399, 398, 399), isFalse);
  });

  test('Huffman symbol dictionaries and text regions render PDF.js corpus image',
      () {
    final raw = _pdfjsImageData('bitmap-symbol-symhuff-texthuff.pdf', 'Im');
    final out = Jbig2Decoder.decode(
      data: raw,
      width: 399,
      height: 400,
    );
    expect(out, isNotNull);
    expect(_blackPixelCount(out!, 399, 400), 10950);
    expect(_isBlack(out, 399, 259, 78), isTrue);
    expect(_isBlack(out, 399, 270, 79), isTrue);
    expect(_isBlack(out, 399, 200, 150), isTrue);
    expect(_isBlack(out, 399, 0, 0), isFalse);
    expect(_isBlack(out, 399, 250, 90), isFalse);
    expect(_isBlack(out, 399, 398, 399), isFalse);
  });

  test('garbage decodes to null, not an exception', () {
    expect(
        Jbig2Decoder.decode(
            data: ascii('this is not jbig2'), width: 8, height: 8),
        isNull);
  });
}

Uint8List ascii(String s) => Uint8List.fromList(s.codeUnits);

Uint8List _pdfjsImageData(String fileName, String imageName) {
  final bytes = File('../../test_corpora/pdfjs/$fileName').readAsBytesSync();
  final doc = CosDocument.open(bytes);
  final pages = doc.resolve(doc.catalog['Pages']) as CosDictionary;
  final kids = doc.resolve(pages['Kids']) as CosArray;
  final page = doc.resolve(kids[0]) as CosDictionary;
  final resources = doc.resolve(page['Resources']) as CosDictionary;
  final xobjects = doc.resolve(resources['XObject']) as CosDictionary;
  final image = doc.resolve(xobjects[imageName]) as CosStream;
  return doc.decodeStreamData(image, stopBeforeFilter: 'JBIG2Decode');
}

int _blackPixelCount(Uint8List data, int width, int height) {
  var count = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (_isBlack(data, width, x, y)) count++;
    }
  }
  return count;
}

bool _isBlack(Uint8List data, int width, int x, int y) {
  final rowBytes = (width + 7) >> 3;
  return (data[y * rowBytes + (x >> 3)] & (0x80 >> (x & 7))) == 0;
}
