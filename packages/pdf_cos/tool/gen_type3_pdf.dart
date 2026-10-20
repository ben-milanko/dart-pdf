// Generates a deterministic Type3-font text document: the TeX-era /
// bitmap-font-scan document class where every glyph is a tiny content
// stream (CharProc) the interpreter re-executes per occurrence (#535).
// Reproducible byte-for-byte on CI (seeded PRNG, no timestamps).
//
// The font carries 26 vector CharProcs (blocky pseudo-letterforms, 6-14
// path ops each, d0 + own gray fill so the glyph is state-independent) on
// a 1000-unit em; pages are dense two-column "scanned report" text laid
// out glyph by glyph.
//
//   fvm dart run packages/pdf_cos/tool/gen_type3_pdf.dart <out.pdf> \
//       [pages] [glyphsPerPage] [seed]
//
// Defaults: 6 pages, 9000 glyphs per A4 page. Content streams are
// FlateDecode-compressed like real exports.
import 'dart:io';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';

/// Deterministic 64-bit LCG (VM-only tool; no web number concerns).
class _Lcg {
  _Lcg(this._state);
  int _state;

  int _next() =>
      _state = (_state * 6364136223846793005 + 1442695040888963407) &
          0x7FFFFFFFFFFFFFFF;

  /// Uniform in [0, 1). Top 52 bits of the 63-bit state; never divide by
  /// 0x8000000000000000 - that literal is int64-negative on the VM.
  double unit() => (_next() >> 11) * (1.0 / (1 << 52));

  int intBelow(int n) => (unit() * n).floor();
}

void main(List<String> args) {
  final outPath = args.isNotEmpty ? args[0] : 'perf_type3.pdf';
  final pageCount = args.length > 1 ? int.parse(args[1]) : 6;
  final glyphsPerPage = args.length > 2 ? int.parse(args[2]) : 9000;
  final seed = args.length > 3 ? int.parse(args[3]) : 20260724;

  const pageW = 595.0; // A4
  const pageH = 842.0;

  final builder = CosDocumentBuilder();
  final zlib = ZLibCodec(level: 6);
  final rng = _Lcg(seed);

  // Object plan: 1 catalog, 2 pages tree, 3 font, 4 CharProcs dict,
  // 5..30 the 26 glyph procs, 31 encoding, then per page i:
  // content = 32+i*2, page = 33+i*2.
  final treeRef = const CosReference(2, 0);
  final fontRef = const CosReference(3, 0);
  final charProcsRef = const CosReference(4, 0);
  final encodingRef = const CosReference(31, 0);
  final pageRefs = [
    for (var i = 0; i < pageCount; i++) CosReference(33 + i * 2, 0),
  ];

  builder.add(CosDictionary({
    'Type': const CosName('Catalog'),
    'Pages': treeRef,
  })); // obj 1
  builder.add(CosDictionary({
    'Type': const CosName('Pages'),
    'Kids': CosArray(pageRefs),
    'Count': CosInteger(pageCount),
  })); // obj 2

  // Widths: all glyphs 600/1000 em.
  builder.add(CosDictionary({
    'Type': const CosName('Font'),
    'Subtype': const CosName('Type3'),
    'FontBBox': CosArray([
      const CosInteger(0),
      const CosInteger(0),
      const CosInteger(600),
      const CosInteger(700),
    ]),
    'FontMatrix': CosArray([
      const CosReal(0.001),
      const CosInteger(0),
      const CosInteger(0),
      const CosReal(0.001),
      const CosInteger(0),
      const CosInteger(0),
    ]),
    'CharProcs': charProcsRef,
    'Encoding': encodingRef,
    'FirstChar': const CosInteger(97),
    'LastChar': const CosInteger(122),
    'Widths': CosArray([
      for (var i = 0; i < 26; i++) const CosInteger(600),
    ]),
  })); // obj 3

  builder.add(CosDictionary({
    for (var i = 0; i < 26; i++)
      'g${String.fromCharCode(0x61 + i)}': CosReference(5 + i, 0),
  })); // obj 4

  // 26 blocky pseudo-letterforms: a seeded arrangement of filled bars and
  // triangles in the 600x700 glyph box - 6-14 path ops each, d0 with the
  // glyph's own gray so its recording is independent of the text state.
  final glyphRng = _Lcg(seed ^ 0x7f4a7c15);
  for (var i = 0; i < 26; i++) {
    final b = StringBuffer('600 0 d0\n');
    if (i.isOdd) {
      // Half the alphabet is the TeX-pk shape: a 1-bit inline ImageMask per
      // glyph, re-parsed by the interpreter at every occurrence - the
      // expensive Type3 class #535 targets.
      const mw = 24, mh = 28; // 3 bytes/row
      final rows = <int>[];
      for (var r = 0; r < mh; r++) {
        var bits = 0;
        for (var c = 0; c < mw; c++) {
          // seeded blobby coverage
          final on = glyphRng.unit() <
              (0.35 + 0.4 * ((r / mh - 0.5).abs() < 0.3 ? 1 : 0));
          bits = (bits << 1) | (on ? 1 : 0);
        }
        rows.add((bits >> 16) & 0xFF);
        rows.add((bits >> 8) & 0xFF);
        rows.add(bits & 0xFF);
      }
      final hex =
          rows.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
      b.writeln('0.1 g 600 0 0 700 0 0 cm');
      b.writeln('BI /IM true /W $mw /H $mh /BPC 1 /D [1 0] /F /AHx ID');
      b.writeln('$hex>');
      b.writeln('EI');
    } else {
      final gray = (0.05 + glyphRng.unit() * 0.25).toStringAsFixed(2);
      b.writeln('$gray g');
      final bars = 2 + glyphRng.intBelow(3);
      for (var k = 0; k < bars; k++) {
        final x = glyphRng.intBelow(400);
        final y = glyphRng.intBelow(500);
        final w = 60 + glyphRng.intBelow(140);
        final h = 60 + glyphRng.intBelow(180);
        b.writeln('$x $y $w $h re f');
      }
      // one triangle for a non-rectilinear edge
      final tx = glyphRng.intBelow(300);
      final ty = glyphRng.intBelow(400);
      b.writeln('$tx $ty m ${tx + 220} ${ty + 40} l ${tx + 60} ${ty + 260} l '
          'h f');
    }
    final raw = Uint8List.fromList(b.toString().codeUnits);
    final deflated = Uint8List.fromList(zlib.encode(raw));
    builder.add(CosStream(
      CosDictionary({
        'Filter': const CosName('FlateDecode'),
        'Length': CosInteger(deflated.length),
      }),
      deflated,
    )); // objs 5..30
  }

  builder.add(CosDictionary({
    'Type': const CosName('Encoding'),
    'Differences': CosArray([
      const CosInteger(97),
      for (var i = 0; i < 26; i++)
        CosName('g${String.fromCharCode(0x61 + i)}'),
    ]),
  })); // obj 31

  final content = StringBuffer();
  for (var p = 0; p < pageCount; p++) {
    content.clear();
    content.writeln('0.5 w 0 0 0 RG 30 30 ${pageW - 60} ${pageH - 60} re S');
    // Two-column dense text: word-like bursts of 2-9 glyphs.
    var glyphs = 0;
    var column = 0;
    var y = pageH - 60;
    content.writeln('BT /F3 9 Tf');
    content.writeln('${30 + column * 280} ${y.toStringAsFixed(0)} Td');
    while (glyphs < glyphsPerPage) {
      final line = StringBuffer();
      var lineLen = 0;
      while (lineLen < 52) {
        final word = 2 + rng.intBelow(8);
        for (var k = 0; k < word && lineLen < 52; k++) {
          line.writeCharCode(0x61 + rng.intBelow(26));
          lineLen++;
        }
        if (lineLen < 52) {
          line.write(' ');
          lineLen++;
        }
      }
      content.writeln('(${line.toString()}) Tj 0 -11 Td');
      glyphs += lineLen;
      y -= 11;
      if (y < 60) {
        column++;
        if (column > 1) break;
        y = pageH - 60;
        content.writeln('ET BT /F3 9 Tf '
            '${30 + column * 280} ${y.toStringAsFixed(0)} Td');
      }
    }
    content.writeln('ET');

    final raw = Uint8List.fromList(content.toString().codeUnits);
    final deflated = Uint8List.fromList(zlib.encode(raw));
    final contentRef = builder.add(CosStream(
      CosDictionary({
        'Filter': const CosName('FlateDecode'),
        'Length': CosInteger(deflated.length),
      }),
      deflated,
    ));
    builder.add(CosDictionary({
      'Type': const CosName('Page'),
      'Parent': treeRef,
      'MediaBox': CosArray([
        const CosInteger(0),
        const CosInteger(0),
        const CosReal(pageW),
        const CosReal(pageH),
      ]),
      'Resources': CosDictionary({
        'Font': CosDictionary({'F3': fontRef}),
      }),
      'Contents': contentRef,
    }));
  }

  final bytes = builder.build(root: const CosReference(1, 0));
  File(outPath)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(bytes);
  stderr.writeln('wrote $outPath: $pageCount pages, '
      '${(bytes.length / 1024).toStringAsFixed(0)} KB, seed $seed');
}
