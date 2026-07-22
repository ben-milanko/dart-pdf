// Generates a deterministic synthetic CAD-style PDF: dense vector linework,
// hatch fills, dimension-style text labels, and a sprinkling of filled
// detail rectangles per sheet - the workload shape of a construction
// drawing set, reproducible byte-for-byte on CI (seeded PRNG, no
// timestamps) so perf runs across machines and weeks compare the same
// document.
//
//   fvm dart run packages/pdf_cos/tool/gen_cad_pdf.dart <out.pdf> \
//       [pages] [opsPerPage] [seed]
//
// Defaults: 138 pages (the local synthetic-cad-benchmark shape), ~6000
// content ops per page on an A1 landscape sheet. Content streams are
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

  double range(double lo, double hi) => lo + unit() * (hi - lo);

  int intBelow(int n) => (unit() * n).floor();
}

void main(List<String> args) {
  final outPath = args.isNotEmpty ? args[0] : 'perf_cad.pdf';
  final pageCount = args.length > 1 ? int.parse(args[1]) : 138;
  final opsPerPage = args.length > 2 ? int.parse(args[2]) : 6000;
  final seed = args.length > 3 ? int.parse(args[3]) : 20260718;

  // A1 landscape in points - big sheets are the CAD norm.
  const pageW = 2384.0;
  const pageH = 1684.0;

  final builder = CosDocumentBuilder();
  final zlib = ZLibCodec(level: 6);

  // Registration order: 1 = catalog, 2 = pages tree, 3 = shared font, then
  // per page i: content = 4+i*2, page = 4+i*2+1.
  final treeRef = const CosReference(2, 0);
  final fontRef = const CosReference(3, 0);
  final pageRefs = [
    for (var i = 0; i < pageCount; i++) CosReference(4 + i * 2 + 1, 0),
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

  final rng = _Lcg(seed);
  final content = StringBuffer();
  for (var p = 0; p < pageCount; p++) {
    content.clear();

    // Title block frame.
    content.writeln('1 w 0 0 0 RG');
    content.writeln('20 20 ${pageW - 40} ${pageH - 40} re S');

    var ops = 0;
    while (ops < opsPerPage) {
      switch (rng.intBelow(10)) {
        case 0 || 1 || 2 || 3 || 4 || 5:
          // Thin linework: short connected polylines (walls, wiring runs).
          final x = rng.range(30, pageW - 200);
          final y = rng.range(30, pageH - 200);
          final segments = 2 + rng.intBelow(6);
          content.write('${rng.range(0.2, 1.0).toStringAsFixed(2)} w ');
          content.write('${x.toStringAsFixed(1)} ${y.toStringAsFixed(1)} m ');
          var cx = x, cy = y;
          for (var s = 0; s < segments; s++) {
            cx += rng.range(-80, 160);
            cy += rng.range(-60, 120);
            content
                .write('${cx.toStringAsFixed(1)} ${cy.toStringAsFixed(1)} l ');
            ops++;
          }
          content.writeln('S');
          ops += 2;
        case 6 || 7:
          // Hatch fill: a small run of parallel lines (section shading).
          final x = rng.range(30, pageW - 120);
          final y = rng.range(30, pageH - 120);
          final n = 4 + rng.intBelow(8);
          content.write('0.3 w ');
          for (var h = 0; h < n; h++) {
            final off = h * 4.0;
            content.write('${(x + off).toStringAsFixed(1)} '
                '${y.toStringAsFixed(1)} m '
                '${(x + off + 30).toStringAsFixed(1)} '
                '${(y + 30).toStringAsFixed(1)} l ');
            ops++;
          }
          content.writeln('S');
        case 8:
          // Filled detail rectangle (equipment, legend swatch).
          final g = rng.range(0.3, 0.9).toStringAsFixed(2);
          content.writeln('$g $g $g rg '
              '${rng.range(30, pageW - 80).toStringAsFixed(1)} '
              '${rng.range(30, pageH - 60).toStringAsFixed(1)} '
              '${rng.range(10, 60).toStringAsFixed(1)} '
              '${rng.range(8, 40).toStringAsFixed(1)} re f');
          ops += 2;
        case 9:
          // Dimension-style label.
          final tag = 1000 + rng.intBelow(9000);
          content.writeln('BT /F1 ${6 + rng.intBelow(3)} Tf '
              '${rng.range(30, pageW - 100).toStringAsFixed(1)} '
              '${rng.range(30, pageH - 30).toStringAsFixed(1)} Td '
              '(D-$tag ${rng.intBelow(12000)}mm) Tj ET');
          ops += 4;
      }
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
