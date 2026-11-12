import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:pdf_cos/pdf_cos.dart';

/// Deterministic 64-bit LCG (VM-only, like the CAD-strip fixture's).
class _Lcg {
  _Lcg(this._state);
  int _state;

  int _next() => _state =
      (_state * 6364136223846793005 + 1442695040888963407) & 0x7FFFFFFFFFFFFFFF;

  double unit() => (_next() >> 11) * (1.0 / (1 << 52));

  double range(double lo, double hi) => lo + unit() * (hi - lo);

  int intBelow(int n) => (unit() * n).floor();
}

/// Builds a one-page synthetic plan sheet whose strokes match the measured
/// shape of `test_corpora/dartpdf/plan-set-16p.pdf` (#1270):
///
/// - [strokes] straight polyline strokes (the real sheet has ~3,050 a page);
/// - 2-11 segments each, median ~5;
/// - about 1 in 8 is a multi-subpath stroke of 2-11 short hatch segments;
/// - widths 0.3-1.0 pt, butt caps, miter joins, opaque colours.
///
/// The content is deterministic and FlateDecode-compressed, with no
/// timestamps, so the bytes are identical across machines.
Uint8List buildSyntheticPlanPolylines({
  int strokes = 3000,
  int seed = 20261112,
  double pageW = 1190.55, // A3 landscape
  double pageH = 841.89,
}) {
  assert(strokes > 0);
  final builder = CosDocumentBuilder();
  const zlib = ZLibEncoder();
  const treeRef = CosReference(2, 0);
  const contentRef = CosReference(3, 0);
  const pageRef = CosReference(4, 0);

  builder.add(CosDictionary({
    'Type': const CosName('Catalog'),
    'Pages': treeRef,
  })); // obj 1
  builder.add(CosDictionary({
    'Type': const CosName('Pages'),
    'Kids': CosArray([pageRef]),
    'Count': const CosInteger(1),
  })); // obj 2

  final rng = _Lcg(seed);
  final content = StringBuffer('0 J 0 j 10 M\n');
  const colours = ['0 0 0', '0.1 0.2 0.6', '0.6 0.1 0.1', '0.2 0.45 0.2'];
  String f(double v) => v.toStringAsFixed(2);
  for (var i = 0; i < strokes; i++) {
    content
      ..write('${colours[rng.intBelow(colours.length)]} RG ')
      ..write('${f(rng.range(0.3, 1.0))} w ');
    if (rng.intBelow(8) == 0) {
      // Hatching: several short one-segment subpaths in one stroke.
      final x = rng.range(20, pageW - 60), y = rng.range(20, pageH - 60);
      final count = 2 + rng.intBelow(10);
      for (var k = 0; k < count; k++) {
        final dx = k * 3.0;
        content
            .write('${f(x + dx)} ${f(y)} m ${f(x + dx + 20)} ${f(y + 20)} l ');
      }
    } else {
      // A run of 2-11 segments with mostly orthogonal turns, like walls,
      // ducts and cable routes.
      var x = rng.range(20, pageW - 20), y = rng.range(20, pageH - 20);
      final segments = 2 + rng.intBelow(4) + rng.intBelow(4) + rng.intBelow(3);
      content.write('${f(x)} ${f(y)} m ');
      for (var k = 0; k < segments; k++) {
        final len = rng.range(8, 90);
        switch (rng.intBelow(5)) {
          case 0:
            x += len;
          case 1:
            x -= len;
          case 2:
            y += len;
          case 3:
            y -= len;
          default:
            x += rng.range(-len, len);
            y += rng.range(-len, len);
        }
        x = x.clamp(10, pageW - 10);
        y = y.clamp(10, pageH - 10);
        content.write('${f(x)} ${f(y)} l ');
      }
    }
    content.writeln('S');
  }

  final raw = Uint8List.fromList(content.toString().codeUnits);
  final deflated = Uint8List.fromList(zlib.encode(raw));
  builder.add(CosStream(
    CosDictionary({
      'Filter': const CosName('FlateDecode'),
      'Length': CosInteger(deflated.length),
    }),
    deflated,
  )); // obj 3
  builder.add(CosDictionary({
    'Type': const CosName('Page'),
    'Parent': treeRef,
    'MediaBox': CosArray([
      const CosInteger(0),
      const CosInteger(0),
      CosReal(pageW),
      CosReal(pageH),
    ]),
    'Resources': CosDictionary(),
    'Contents': contentRef,
  })); // obj 4

  return builder.build(root: const CosReference(1, 0));
}
