import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:pdf_cos/pdf_cos.dart';

/// Deterministic 64-bit LCG. VM-only (the mask is int64-negative on the web);
/// these fixtures are built and consumed on the Dart VM under `dart`/`flutter
/// test`, never in a browser.
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

/// Builds a deterministic synthetic CAD PDF that reproduces the *pathological
/// single-sheet* shape behind the "iPad janky pan" report on a
/// cathodic-protection strip drawing: one ultra-wide page (~8504 x 842 pt, a
/// ~10:1 strip), dense vector linework spread across the whole width, and the
/// content split into several concatenated `/Contents` streams like a real
/// multi-pass export.
///
/// That shape is what makes region replay expensive - one page (no page-level
/// parallelism), hundreds of thousands of paint commands in a single
/// transcript. It is the exact case the grid-cull region replay
/// (`PdfRetainedScene`) exists to keep interactive, so both the perf-scenario
/// generator (`gen_cad_wide_pdf.dart`) and the region-replay exercise test
/// build the document here, from the same code, seeded identically.
///
/// [ops] is the number of drawing primitives, each roughly one render command,
/// so ~850k reproduces the real file's ~850k-command transcript / ~24 MB
/// decoded content. [streams] splits the content into that many `/Contents`
/// streams (the real file has 8). The result is FlateDecode-compressed like a
/// real export and carries no timestamps, so the bytes are identical across
/// machines and runs.
Uint8List buildSyntheticCadStrip({
  required int ops,
  int streams = 8,
  int seed = 20260718,
  double pageW = 8503.939,
  double pageH = 841.89,
}) {
  assert(ops > 0);
  assert(streams > 0);

  final builder = CosDocumentBuilder();
  const zlib = ZLibEncoder();

  // Registration order: 1 = catalog, 2 = pages tree, 3 = shared font, then the
  // N content streams, then the page (referencing all N in a /Contents array).
  final treeRef = const CosReference(2, 0);
  final fontRef = const CosReference(3, 0);
  final contentRefs = [
    for (var i = 0; i < streams; i++) CosReference(4 + i, 0),
  ];
  final pageRef = CosReference(4 + streams, 0);

  builder.add(CosDictionary({
    'Type': const CosName('Catalog'),
    'Pages': treeRef,
  })); // obj 1
  builder.add(CosDictionary({
    'Type': const CosName('Pages'),
    'Kids': CosArray([pageRef]),
    'Count': const CosInteger(1),
  })); // obj 2
  builder.add(CosDictionary({
    'Type': const CosName('Font'),
    'Subtype': const CosName('Type1'),
    'BaseFont': const CosName('Helvetica'),
  })); // obj 3

  // One buffer per output stream; primitives round-robin across them so every
  // /Contents stream is comparably sized (like a real multi-pass export where
  // each pass writes a band of the drawing). The first stream opens the
  // graphics state and draws the title-block frame; the interpreter
  // concatenates the streams, so state set in stream k is visible in k+1.
  final buffers = List.generate(streams, (_) => StringBuffer());
  buffers[0]
    ..writeln('1 w 0 0 0 RG')
    ..writeln('20 20 ${pageW - 40} ${pageH - 40} re S');

  final rng = _Lcg(seed);
  var emitted = 0;
  var s = 0;
  while (emitted < ops) {
    final content = buffers[s];
    s = (s + 1) % streams;
    switch (rng.intBelow(10)) {
      case 0 || 1 || 2 || 3 || 4 || 5 || 6:
        // Thin linework: short connected polylines (pipe runs, cable trays),
        // clustered locally so a zoomed tile only intersects a handful - the
        // spatial locality the grid cull relies on. Real strip sheets reuse the
        // line width across long runs, so only set /w occasionally.
        final x = rng.range(30, pageW - 200);
        final y = rng.range(30, pageH - 120);
        final segments = 1 + rng.intBelow(2); // 2-3 vertices, like the real file
        if (rng.intBelow(4) == 0) {
          content.write('${rng.range(0.2, 1.0).toStringAsFixed(2)} w ');
        }
        content.write('${x.toStringAsFixed(1)} ${y.toStringAsFixed(1)} m ');
        var cx = x, cy = y;
        for (var seg = 0; seg < segments; seg++) {
          cx += rng.range(-80, 160);
          cy += rng.range(-40, 60);
          content.write('${cx.toStringAsFixed(1)} ${cy.toStringAsFixed(1)} l ');
        }
        content.writeln('S');
        emitted++;
      case 7:
        // Hatch fill: a small run of parallel lines (coating / section
        // shading). One stroke command over many little paths.
        final x = rng.range(30, pageW - 120);
        final y = rng.range(30, pageH - 80);
        final n = 3 + rng.intBelow(3);
        content.write('0.3 w ');
        for (var h = 0; h < n; h++) {
          final off = h * 4.0;
          content.write('${(x + off).toStringAsFixed(1)} '
              '${y.toStringAsFixed(1)} m '
              '${(x + off + 30).toStringAsFixed(1)} '
              '${(y + 30).toStringAsFixed(1)} l ');
        }
        content.writeln('S');
        emitted++;
      case 8:
        // Filled detail rectangle (equipment marker, test-post swatch).
        final g = rng.range(0.3, 0.9).toStringAsFixed(2);
        content.writeln('$g $g $g rg '
            '${rng.range(30, pageW - 80).toStringAsFixed(1)} '
            '${rng.range(30, pageH - 60).toStringAsFixed(1)} '
            '${rng.range(10, 60).toStringAsFixed(1)} '
            '${rng.range(8, 40).toStringAsFixed(1)} re f');
        emitted++;
      case 9:
        // Chainage / dimension label - text is the other paint kind on the
        // sheet, and its own hit-test / extract cost.
        final tag = 1000 + rng.intBelow(9000);
        content.writeln('BT /F1 ${6 + rng.intBelow(3)} Tf '
            '${rng.range(30, pageW - 100).toStringAsFixed(1)} '
            '${rng.range(30, pageH - 30).toStringAsFixed(1)} Td '
            '(CH $tag+${rng.intBelow(1000).toString().padLeft(3, '0')}) Tj ET');
        emitted++;
    }
  }

  for (final buf in buffers) {
    final raw = Uint8List.fromList(buf.toString().codeUnits);
    final deflated = Uint8List.fromList(zlib.encode(raw));
    builder.add(CosStream(
      CosDictionary({
        'Filter': const CosName('FlateDecode'),
        'Length': CosInteger(deflated.length),
      }),
      deflated,
    ));
  }

  builder.add(CosDictionary({
    'Type': const CosName('Page'),
    'Parent': treeRef,
    'MediaBox': CosArray([
      const CosInteger(0),
      const CosInteger(0),
      CosReal(pageW),
      CosReal(pageH),
    ]),
    'Resources': CosDictionary({
      'Font': CosDictionary({'F1': fontRef}),
    }),
    // A /Contents *array* of N streams: the real file's multi-pass shape.
    'Contents': CosArray(contentRefs),
  }));

  return builder.build(root: const CosReference(1, 0));
}
