// Generates the scanned-book JBIG2 document the #557 perf scenarios measure:
// ONE shared /JBIG2Globals stream carrying a multi-symbol arithmetic symbol
// dictionary, referenced by every page's JBIG2Decode image.
//
//   fvm dart run packages/pdf_test_fixtures/tool/gen_jbig2_scanned_pdf.dart \
//       <out.pdf> [pages] [symbols] [width] [height] [seed]
//
// Defaults: 32 pages, 900 symbols, 1700x2200 px images (~200 dpi US Letter).
//
// That shape is the point. Every in-repo JBIG2 file (the pdfjs bitmap-*/jbig2_*
// samples, ghent GWG173) inlines its globals into a single image stream, so
// none of them can exhibit the #532 globals cache: the saving is one symbol
// dictionary arithmetic-decode per *page* that no longer happens, and it needs
// many pages sharing one dictionary to show up at all. Real scanners emit
// exactly this - jbig2enc's `-s -p` mode writes a book-wide symbol dictionary
// to a separate stream and each page becomes a text region referring to it.
//
// jbig2enc is not in CI (and JBIG2 arithmetic *encoding* was out of scope for
// the pure-Dart writers), so the encoder lives in pdf_test_fixtures instead -
// enough of T.88 to emit this profile, round-tripped against the shipping
// decoder in pdf_cos/test/jbig2_roundtrip_test.dart. Output is deterministic
// for a given seed: generate once, pre-seed the same bytes into every backfill
// worktree so each version measures identical input.
import 'dart:io';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main(List<String> args) {
  final outPath = args.isNotEmpty ? args[0] : 'jbig2-scanned.pdf';
  final pageCount = args.length > 1 ? int.parse(args[1]) : 32;
  final symbolCount = args.length > 2 ? int.parse(args[2]) : 900;
  final imgW = args.length > 3 ? int.parse(args[3]) : 1700;
  final imgH = args.length > 4 ? int.parse(args[4]) : 2200;
  final seed = args.length > 5 ? int.parse(args[5]) : 20260725;

  const pageW = 612.0; // US Letter, points
  const pageH = 792.0;

  final symbols = sortSymbolsForDictionary(_buildGlyphs(symbolCount, seed));
  final globals = encodeJbig2Globals(symbols);

  final builder = CosDocumentBuilder();

  // Object numbers are assigned in registration order starting at 1:
  //   1 = catalog, 2 = page tree, 3 = the shared globals stream, then per page
  //   i (0-based) three objects in this add() order:
  //   content = 4+i*3, image = 4+i*3+1, page = 4+i*3+2.
  const catalogNum = 1;
  const treeNum = 2;
  const globalsNum = 3;
  final treeRef = const CosReference(treeNum, 0);
  final globalsRef = const CosReference(globalsNum, 0);
  final pageRefs = [
    for (var i = 0; i < pageCount; i++) CosReference(4 + i * 3 + 2, 0),
  ];

  builder.add(CosDictionary({
    'Type': const CosName('Catalog'),
    'Pages': treeRef,
  }));
  builder.add(CosDictionary({
    'Type': const CosName('Pages'),
    'Kids': CosArray(pageRefs),
    'Count': CosInteger(pageCount),
  }));
  // The globals stream is stored raw: JBIG2 data is already arithmetic-coded,
  // and that is how scanners write it.
  builder.add(CosStream(
    CosDictionary({'Length': CosInteger(globals.length)}),
    globals,
  ));

  final content = Uint8List.fromList(
      'q\n$pageW 0 0 $pageH 0 0 cm\n/Im0 Do\nQ\n'.codeUnits);

  var instances = 0;
  var imageBytes = 0;
  for (var i = 0; i < pageCount; i++) {
    final contentRef = CosReference(4 + i * 3, 0);
    final imageRef = CosReference(4 + i * 3 + 1, 0);

    builder.add(CosStream(
      CosDictionary({'Length': CosInteger(content.length)}),
      content,
    ));

    final placements = _layoutPage(symbols, imgW, imgH, i, symbolCount);
    instances += placements.length;
    final page = encodeJbig2TextPage(
      width: imgW,
      height: imgH,
      symbols: symbols,
      placements: placements,
    );
    imageBytes += page.length;
    builder.add(CosStream(
      CosDictionary({
        'Type': const CosName('XObject'),
        'Subtype': const CosName('Image'),
        'Width': CosInteger(imgW),
        'Height': CosInteger(imgH),
        'ColorSpace': const CosName('DeviceGray'),
        'BitsPerComponent': CosInteger(1),
        'Filter': const CosName('JBIG2Decode'),
        'DecodeParms': CosDictionary({'JBIG2Globals': globalsRef}),
        'Length': CosInteger(page.length),
      }),
      page,
    ));

    builder.add(CosDictionary({
      'Type': const CosName('Page'),
      'Parent': treeRef,
      'MediaBox': CosArray([
        CosInteger(0),
        CosInteger(0),
        CosReal(pageW),
        CosReal(pageH),
      ]),
      'Resources': CosDictionary({
        'XObject': CosDictionary({'Im0': imageRef}),
      }),
      'Contents': contentRef,
    }));
  }

  final bytes = builder.build(root: const CosReference(catalogNum, 0));
  File(outPath).writeAsBytesSync(bytes);
  stdout.writeln('wrote $outPath: ${bytes.length} bytes, $pageCount pages, '
      'image ${imgW}x$imgH, $symbolCount shared symbols '
      '(${globals.length} B globals), $instances symbol instances '
      '(${(imageBytes / pageCount).round()} B/page)');
}

/// A deterministic bank of glyph-shaped symbols: a left stem plus a few
/// features, at text-ish sizes. Structured strokes (rather than noise) matter -
/// they are what make the arithmetic contexts adapt the way they do on real
/// scanned text, so the per-page decode this scenario measures is honest.
List<Jbig2Bitmap> _buildGlyphs(int count, int seed) {
  var state = seed & 0x7FFFFFFF;
  int next(int bound) {
    state = (state * 1103515245 + 12345) & 0x7FFFFFFF;
    return state % bound;
  }

  return [
    for (var i = 0; i < count; i++) _glyph(next, 14 + next(12), 18 + next(16)),
  ];
}

Jbig2Bitmap _glyph(int Function(int) next, int width, int height) {
  final bitmap = Jbig2Bitmap(width, height);
  final stroke = 2 + next(2);
  final ascender = next(4) == 0 ? 0 : height ~/ 4;
  // Left stem: the one feature almost every glyph has.
  bitmap.fillRect(1, ascender, stroke, height - ascender - 1);
  switch (next(6)) {
    case 0: // a bar across the middle, like e/f/t
      bitmap.fillRect(1, height ~/ 2, width - 3, stroke);
    case 1: // a right stem, like n/u/h
      bitmap.fillRect(width - stroke - 1, ascender, stroke, height - ascender - 1);
    case 2: // a closed bowl, like o/d/p
      bitmap
        ..fillRect(width - stroke - 1, ascender, stroke, height - ascender - 1)
        ..fillRect(1, ascender, width - 2, stroke)
        ..fillRect(1, height - stroke - 1, width - 2, stroke);
    case 3: // a top bar and a foot, like z/s
      bitmap
        ..fillRect(1, ascender, width - 2, stroke)
        ..fillRect(1, height - stroke - 1, width - 2, stroke);
    case 4: // a diagonal, like v/x/y
      for (var y = ascender; y < height - 1; y++) {
        final x = 1 + ((y - ascender) * (width - 3)) ~/ (height - ascender - 1);
        bitmap.fillRect(x, y, stroke, 1);
      }
    case _: // a descender tail, like g/q/j
      bitmap.fillRect(1, height - stroke - 1, width ~/ 2, stroke);
  }
  return bitmap;
}

/// Lays a page of "text" out: justified-ish lines of words, drawn from a
/// page-local window over the shared dictionary. The window is the scanned-book
/// property that makes the #532 saving visible - every page re-decoded the
/// *whole* book-wide dictionary before the cache, while only ever drawing a
/// slice of it.
List<Jbig2Placement> _layoutPage(
  List<Jbig2Bitmap> symbols,
  int width,
  int height,
  int pageIndex,
  int symbolCount,
) {
  var state = (pageIndex + 1) * 2654435761 & 0x7FFFFFFF;
  int next(int bound) {
    state = (state * 1103515245 + 12345) & 0x7FFFFFFF;
    return state % bound;
  }

  const margin = 120;
  const leading = 44;
  const wordGap = 12;
  const letterGap = 3;
  // Roughly a third of the dictionary per page, sliding across the book.
  final windowSize = (symbolCount / 3).ceil();
  final windowStart = symbolCount <= windowSize
      ? 0
      : (pageIndex * 37) % (symbolCount - windowSize);

  final placements = <Jbig2Placement>[];
  for (var y = margin; y + leading < height - margin; y += leading) {
    var x = margin;
    while (x < width - margin) {
      final wordLength = 2 + next(8);
      for (var i = 0; i < wordLength && x < width - margin; i++) {
        final id = windowStart + next(windowSize);
        placements.add(Jbig2Placement(id, x, y));
        x += symbols[id].width + letterGap;
      }
      x += wordGap;
    }
  }
  return placements;
}
