// Generates a deterministic synthetic hatched-drawing PDF: many regions
// filled with PDF tiling patterns (PatternType 1) - diagonal hatch,
// cross-hatch, dots, and an uncolored (PaintType 2) hatch - the workload
// shape of a sectioned CAD/engineering sheet, reproducible byte-for-byte
// on CI (seeded PRNG, no timestamps) so perf runs across machines and
// weeks compare the same document.
//
// The interpreter currently re-executes a pattern's cell content for every
// tile (#524), so this class of document is quadratic-feeling in practice:
// region area / (XStep*YStep) cell runs per fill. This corpus file is the
// measurement anchor for the record-once/replay-per-tile fix.
//
//   fvm dart run packages/pdf_cos/tool/gen_hatch_pdf.dart <out.pdf> \
//       [pages] [regionsPerPage] [seed]
//
// Defaults: 4 pages, 70 hatched regions per A1 landscape sheet. Content
// streams are FlateDecode-compressed like real exports.
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

  double range(double lo, double hi) => lo + unit() * (hi - lo);

  int intBelow(int n) => (unit() * n).floor();
}

void main(List<String> args) {
  final outPath = args.isNotEmpty ? args[0] : 'perf_hatch.pdf';
  final pageCount = args.length > 1 ? int.parse(args[1]) : 4;
  final regionsPerPage = args.length > 2 ? int.parse(args[2]) : 70;
  final seed = args.length > 3 ? int.parse(args[3]) : 20260724;

  // A1 landscape in points - big sheets are the CAD norm.
  const pageW = 2384.0;
  const pageH = 1684.0;

  final builder = CosDocumentBuilder();
  final zlib = ZLibCodec(level: 6);

  // Registration order: 1 = catalog, 2 = pages tree, 3 = shared font,
  // 4-7 = the four pattern cells, then per page i: content = 8+i*2,
  // page = 8+i*2+1.
  final treeRef = const CosReference(2, 0);
  final fontRef = const CosReference(3, 0);
  final patternRefs = [
    for (var i = 0; i < 4; i++) CosReference(4 + i, 0),
  ];
  final pageRefs = [
    for (var i = 0; i < pageCount; i++) CosReference(8 + i * 2 + 1, 0),
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
  builder.add(CosDictionary({
    'Type': const CosName('Font'),
    'Subtype': const CosName('Type1'),
    'BaseFont': const CosName('Helvetica'),
  })); // obj 3

  // The four pattern cells. Steps are small (8-12 pt) so a typical region
  // spans hundreds of tiles - the shape that makes per-tile re-execution
  // hurt. All cells stay inside their BBox (no clip-tested overrun here;
  // ghent covers that semantics).
  CosReference addPattern(String cell, double step,
      {int paintType = 1, List<double>? matrix}) {
    final raw = Uint8List.fromList(cell.codeUnits);
    final deflated = Uint8List.fromList(zlib.encode(raw));
    return builder.add(CosStream(
      CosDictionary({
        'Type': const CosName('Pattern'),
        'PatternType': const CosInteger(1),
        'PaintType': CosInteger(paintType),
        'TilingType': const CosInteger(1),
        'BBox': CosArray([
          const CosInteger(0),
          const CosInteger(0),
          CosReal(step),
          CosReal(step),
        ]),
        'XStep': CosReal(step),
        'YStep': CosReal(step),
        'Resources': CosDictionary({}),
        if (matrix != null) 'Matrix': CosArray([...matrix.map(CosReal.new)]),
        'Filter': const CosName('FlateDecode'),
        'Length': CosInteger(deflated.length),
      }),
      deflated,
    ));
  }

  // P0: diagonal hatch - one stroked line per cell (obj 4).
  addPattern('0.4 w 0.1 0.1 0.5 RG 0 0 m 8 8 l S\n', 8);
  // P1: cross-hatch - two strokes per cell (obj 5).
  addPattern('0.3 w 0.5 0.1 0.1 RG 0 0 m 10 10 l S 0 10 m 10 0 l S\n', 10);
  // P2: dot grid - one filled circle per cell, Bezier'd (obj 6).
  addPattern(
      '0.2 0.4 0.2 rg 6 4 m 6 5.1 5.1 6 4 6 c 2.9 6 2 5.1 2 4 c '
      '2 2.9 2.9 2 4 2 c 5.1 2 6 2.9 6 4 c f\n',
      12);
  // P3: uncolored (PaintType 2) diagonal hatch, rotated 30deg - the colour
  // comes from the fill state per use (obj 7).
  addPattern('0.5 w 0 0 m 9 9 l S\n', 9,
      paintType: 2,
      matrix: [0.8660, 0.5, -0.5, 0.8660, 0, 0]);

  final rng = _Lcg(seed);
  final content = StringBuffer();
  for (var p = 0; p < pageCount; p++) {
    content.clear();

    // Title block frame.
    content.writeln('1 w 0 0 0 RG');
    content.writeln('20 20 ${pageW - 40} ${pageH - 40} re S');

    for (var r = 0; r < regionsPerPage; r++) {
      // Region sizes keep tiles-per-fill in the hundreds and always under
      // the interpreter's 4096-tile cap (500x500 max at 8 pt step ~ 3900).
      final w = rng.range(80, 480);
      final h = rng.range(60, 400);
      final x = rng.range(30, pageW - 40 - w);
      final y = rng.range(30, pageH - 40 - h);
      final which = rng.intBelow(4);
      content.writeln('q /Pattern cs');
      if (which == 3) {
        // Uncolored: pattern + a colour, varied per region.
        final cr = rng.range(0.1, 0.9).toStringAsFixed(2);
        final cg = rng.range(0.1, 0.9).toStringAsFixed(2);
        final cb = rng.range(0.1, 0.9).toStringAsFixed(2);
        content.writeln('$cr $cg $cb /P3 scn');
      } else {
        content.writeln('/P$which scn');
      }
      switch (rng.intBelow(3)) {
        case 0:
          // Plain rectangle region.
          content.writeln('${x.toStringAsFixed(1)} ${y.toStringAsFixed(1)} '
              '${w.toStringAsFixed(1)} ${h.toStringAsFixed(1)} re f');
        case 1:
          // Right-trapezoid region (sectioned wall/slab).
          content.writeln('${x.toStringAsFixed(1)} ${y.toStringAsFixed(1)} m '
              '${(x + w).toStringAsFixed(1)} ${y.toStringAsFixed(1)} l '
              '${(x + w * 0.8).toStringAsFixed(1)} '
              '${(y + h).toStringAsFixed(1)} l '
              '${x.toStringAsFixed(1)} ${(y + h).toStringAsFixed(1)} l h f');
        case 2:
          // L-shaped region (plan cutout).
          content.writeln('${x.toStringAsFixed(1)} ${y.toStringAsFixed(1)} m '
              '${(x + w).toStringAsFixed(1)} ${y.toStringAsFixed(1)} l '
              '${(x + w).toStringAsFixed(1)} '
              '${(y + h * 0.5).toStringAsFixed(1)} l '
              '${(x + w * 0.5).toStringAsFixed(1)} '
              '${(y + h * 0.5).toStringAsFixed(1)} l '
              '${(x + w * 0.5).toStringAsFixed(1)} '
              '${(y + h).toStringAsFixed(1)} l '
              '${x.toStringAsFixed(1)} ${(y + h).toStringAsFixed(1)} l h f');
      }
      content.writeln('Q');
      // Outline + label, like a real sectioned detail.
      content.writeln('0.6 w 0 0 0 RG ${x.toStringAsFixed(1)} '
          '${y.toStringAsFixed(1)} ${w.toStringAsFixed(1)} '
          '${h.toStringAsFixed(1)} re S');
      content.writeln('BT /F1 7 Tf ${(x + 4).toStringAsFixed(1)} '
          '${(y + 4).toStringAsFixed(1)} Td (H-${100 + r}) Tj ET');
    }

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
        'Font': CosDictionary({'F1': fontRef}),
        'Pattern': CosDictionary({
          for (var i = 0; i < 4; i++) 'P$i': patternRefs[i],
        }),
      }),
      'Contents': contentRef,
    }));
  }

  final bytes = builder.build(root: const CosReference(1, 0));
  File(outPath)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(bytes);
  stderr.writeln('wrote $outPath: $pageCount pages, '
      '${(bytes.length / (1 << 20)).toStringAsFixed(1)} MB, seed $seed');
}
