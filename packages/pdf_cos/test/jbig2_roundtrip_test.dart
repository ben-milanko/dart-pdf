import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

/// Round-trips the pure-Dart JBIG2 encoder in pdf_test_fixtures through the
/// shipping decoder. The encoder exists to build the scanned-book perf
/// scenario (#557) - a separate /JBIG2Globals symbol dictionary shared by many
/// page images, the one shape no corpus file has - so what has to hold is that
/// its output decodes to exactly the bitmaps that went in.
void main() {
  /// The rendered page as a `width * height` list of 0/1 ink values, unpacking
  /// the decoder's PDF-polarity output (a 0 bit is black).
  List<int> ink(Uint8List packed, int width, int height) {
    final rowBytes = (width + 7) >> 3;
    return [
      for (var y = 0; y < height; y++)
        for (var x = 0; x < width; x++)
          (packed[y * rowBytes + (x >> 3)] >> (7 - (x & 7))) & 1 ^ 1,
    ];
  }

  /// The same page composed directly, as the decoder should reproduce it.
  List<int> expected(
    int width,
    int height,
    List<Jbig2Bitmap> symbols,
    List<Jbig2Placement> placements,
  ) {
    final page = Jbig2Bitmap(width, height);
    for (final placement in placements) {
      final symbol = symbols[placement.symbol];
      for (var y = 0; y < symbol.height; y++) {
        for (var x = 0; x < symbol.width; x++) {
          if (symbol.get(x, y) != 0) page.set(placement.x + x, placement.y + y, 1);
        }
      }
    }
    return page.data.toList();
  }

  /// A deterministic, glyph-shaped symbol: a left stem plus a feature or two,
  /// so the arithmetic contexts adapt the way they do on real text.
  Jbig2Bitmap glyph(int seed, int width, int height) {
    final bitmap = Jbig2Bitmap(width, height);
    bitmap.fillRect(1, 1, 2, height - 2);
    if (seed.isEven) bitmap.fillRect(1, height ~/ 2, width - 3, 2);
    if (seed % 3 == 0) bitmap.fillRect(width - 3, 1, 2, height - 2);
    if (seed % 5 == 0) bitmap.fillRect(1, 1, width - 3, 2);
    return bitmap;
  }

  test('a shared globals dictionary decodes back to the placed symbols', () {
    final symbols = sortSymbolsForDictionary([
      for (var i = 0; i < 12; i++) glyph(i, 6 + i % 4, 8 + i % 5),
    ]);
    final globals = encodeJbig2Globals(symbols);

    const width = 160;
    const height = 90;
    // Three lines of "text", the shape the scanned-book scenario emits.
    final placements = <Jbig2Placement>[];
    for (var line = 0; line < 3; line++) {
      var x = 4;
      for (var i = 0; i < 14; i++) {
        final id = (line * 7 + i * 5) % symbols.length;
        placements.add(Jbig2Placement(id, x, 6 + line * 24));
        x += symbols[id].width + 2;
      }
    }
    final page = encodeJbig2TextPage(
      width: width,
      height: height,
      symbols: symbols,
      placements: placements,
    );

    Jbig2Decoder.debugResetGlobalsCache();
    final decoded = Jbig2Decoder.decode(
      data: page,
      globals: globals,
      width: width,
      height: height,
    );
    expect(decoded, isNotNull);
    expect(ink(decoded!, width, height),
        expected(width, height, symbols, placements));
  });

  test('a second page reuses the cached globals and decodes identically (#532)',
      () {
    final symbols = sortSymbolsForDictionary([
      for (var i = 0; i < 9; i++) glyph(i, 7 + i % 3, 10 + i % 4),
    ]);
    final globals = encodeJbig2Globals(symbols);
    const width = 96;
    const height = 40;
    final placements = [
      for (var i = 0; i < 8; i++) Jbig2Placement(i % symbols.length, 2 + i * 11, 5),
      for (var i = 0; i < 8; i++) Jbig2Placement(i % symbols.length, 2 + i * 11, 22),
    ];
    final page = encodeJbig2TextPage(
      width: width,
      height: height,
      symbols: symbols,
      placements: placements,
    );

    Jbig2Decoder.debugResetGlobalsCache();
    Uint8List? run() => Jbig2Decoder.decode(
          data: page,
          globals: globals,
          width: width,
          height: height,
        );
    final cold = run();
    final warm = run();
    expect(cold, isNotNull);
    expect(warm, cold);
    expect(ink(cold!, width, height),
        expected(width, height, symbols, placements));
  });

  test('the page stream alone carries no symbols', () {
    final symbols = sortSymbolsForDictionary([glyph(1, 8, 12), glyph(2, 9, 12)]);
    final page = encodeJbig2TextPage(
      width: 40,
      height: 20,
      symbols: symbols,
      placements: const [Jbig2Placement(0, 2, 2), Jbig2Placement(1, 14, 2)],
    );
    // No globals: the text region refers to a dictionary that isn't there, so
    // the decoder bails rather than inventing symbols.
    Jbig2Decoder.debugResetGlobalsCache();
    expect(
      Jbig2Decoder.decode(data: page, width: 40, height: 20),
      isNull,
    );
  });
}
