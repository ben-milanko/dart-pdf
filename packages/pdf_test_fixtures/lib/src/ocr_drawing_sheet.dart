import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';

/// One ground-truth label for an OCR accuracy run: what is printed and its
/// user-space box (`left`, `bottom`, `right`, `top`).
class OcrTruthLabel {
  const OcrTruthLabel(this.text, this.left, this.bottom, this.right, this.top);

  final String text;
  final double left;
  final double bottom;
  final double right;
  final double top;

  Map<String, Object> toJson() => {
        'text': text,
        'bounds': [left, bottom, right, top],
      };

  static OcrTruthLabel fromJson(Map<String, Object?> json) {
    final b = [for (final v in json['bounds']! as List) (v as num).toDouble()];
    return OcrTruthLabel(json['text']! as String, b[0], b[1], b[2], b[3]);
  }
}

/// A synthetic drawing sheet and the labels printed on it.
class OcrDrawingSheet {
  const OcrDrawingSheet(this.bytes, this.labels);

  final Uint8List bytes;
  final List<OcrTruthLabel> labels;
}

/// Helvetica's (= Arial's) advance widths for ASCII 32..126, per 1000 em.
const List<int> _helveticaWidths = [
  278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333, 278, //
  278, 556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 278, 278, 584, 584,
  584, 556, 1015, 667, 667, 722, 722, 667, 611, 778, 722, 278, 500, 667, 556,
  833, 722, 778, 667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 278,
  278, 278, 469, 556, 333, 556, 556, 500, 556, 556, 278, 556, 556, 222, 222,
  500, 222, 833, 556, 556, 556, 556, 333, 500, 278, 556, 500, 722, 500, 500,
  500, 334, 260, 334, 584,
];

double _measure(String s, double size) {
  var total = 0;
  for (final c in s.codeUnits) {
    total += _helveticaWidths[c - 32];
  }
  return total * size / 1000;
}

/// Builds a deterministic synthetic signalling-drawing sheet with known
/// labels - the ground truth an OCR accuracy benchmark scores against.
///
/// It reproduces the shape that broke OCR on a real A3 interlocking sheet: a
/// landscape drawing stored as a portrait A3 page with /Rotate 90, thin track
/// lines carrying filled ~4.9pt dots, a ~7pt parenthesised code sitting
/// ~0.4pt above each dot (it all but touches it), an ID ~2pt below, and a
/// title block of longer runs. Codes are random capitals, so no language prior
/// can guess them - only reading can.
///
/// [fontProgram] is an Arial-metric TrueType (e.g. Liberation Sans) embedded
/// as the label font, so the glyphs are drawn as outlines by the font engine -
/// like the real sheet's outlined text, and unlike a base-14 substitute, which
/// `flutter test` paints as Ahem boxes. [seed] picks the codes; [labelSize] is
/// every label's size (7.2pt matches the real sheet's ~5.2pt capitals).
OcrDrawingSheet buildOcrDrawingSheet(
  Uint8List fontProgram, {
  int seed = 20261004,
  double labelSize = 7.2,
}) {
  // Drawn in landscape "screen" space (1191 x 842, y up); one cm maps it onto
  // the portrait page that /Rotate 90 turns back to landscape.
  const screenW = 1191.0, screenH = 842.0;
  final rng = math.Random(seed);
  final content = StringBuffer()
    ..writeln('q 0 1 -1 0 ${screenH.toStringAsFixed(0)} 0 cm')
    ..writeln('0 G 0 g 0.6 w 1 J')
    ..writeln('20 20 ${screenW - 40} ${screenH - 40} re S');
  final labels = <OcrTruthLabel>[];

  // Screen box -> user space, the inverse of the page's /Rotate 90 view:
  // user x = screenH - screen y, user y = screen x.
  OcrTruthLabel label(String s, double l, double b, double r, double t) =>
      OcrTruthLabel(s, screenH - t, l, screenH - b, r);

  String letters(int n) =>
      String.fromCharCodes([for (var i = 0; i < n; i++) 65 + rng.nextInt(26)]);

  void text(String s, double cx, double baseline, double size) {
    final w = _measure(s, size);
    final left = cx - w / 2;
    final escaped =
        s.replaceAll(r'\', r'\\').replaceAll('(', r'\(').replaceAll(')', r'\)');
    content.writeln('BT /F1 ${size.toStringAsFixed(2)} Tf '
        '${left.toStringAsFixed(3)} ${baseline.toStringAsFixed(3)} Td '
        '($escaped) Tj ET');
    labels.add(label(
        s, left, baseline - 0.207 * size, left + w, baseline + 0.718 * size));
  }

  void dot(double cx, double cy, double r) {
    const k = 0.5523;
    content.writeln('${cx + r} $cy m '
        '${cx + r} ${cy + k * r} ${cx + k * r} ${cy + r} $cx ${cy + r} c '
        '${cx - k * r} ${cy + r} ${cx - r} ${cy + k * r} ${cx - r} $cy c '
        '${cx - r} ${cy - k * r} ${cx - k * r} ${cy - r} $cx ${cy - r} c '
        '${cx + k * r} ${cy - r} ${cx + r} ${cy - k * r} ${cx + r} $cy c f');
  }

  // Bands of paired tracks (like D27/D28): the upper track carries a code
  // above each dot, both tracks an ID below.
  const dotR = 2.45, gapAboveDot = 0.36, gapBelowDot = 2.0;
  var id = 10;
  for (var band = 0; band < 7; band++) {
    final upper = screenH - 90 - band * 105;
    final lower = upper - 20;
    for (final y in [upper, lower]) {
      content.writeln('40 $y m ${screenW - 40} $y l S');
    }
    for (var col = 0; col < 18; col++) {
      final cx = 75 + col * 60.0 + rng.nextDouble() * 6;
      for (final y in [upper, lower]) {
        dot(cx, y, dotR);
        // Below the dot: an ID whose cap top is gapBelowDot under it.
        final prefix = String.fromCharCode(65 + rng.nextInt(26));
        text('$prefix${id++ % 90 + 1}', cx,
            y - dotR - gapBelowDot - 0.718 * labelSize, labelSize);
      }
      // Above the upper dot: a parenthesised code whose paren bottom sits
      // gapAboveDot over the dot (the paren descends ~0.21 em).
      text('(${letters(3 + rng.nextInt(3))})', cx,
          upper + dotR + gapAboveDot + 0.207 * labelSize, labelSize);
    }
  }

  // A title block of longer runs, the other shape a sheet carries.
  for (var row = 0; row < 4; row++) {
    final words = [for (var i = 0; i < 3; i++) letters(4 + rng.nextInt(5))];
    text(words.join(' '), screenW - 200, 40 + row * 12.0, labelSize);
  }
  content.writeln('Q');

  final builder = CosDocumentBuilder();
  final raw = Uint8List.fromList(content.toString().codeUnits);
  builder.add(CosDictionary({
    'Type': const CosName('Catalog'),
    'Pages': const CosReference(2, 0),
  })); // obj 1
  builder.add(CosDictionary({
    'Type': const CosName('Pages'),
    'Kids': CosArray([const CosReference(3, 0)]),
    'Count': const CosInteger(1),
  })); // obj 2
  builder.add(CosDictionary({
    'Type': const CosName('Page'),
    'Parent': const CosReference(2, 0),
    'MediaBox': CosArray([
      const CosInteger(0),
      const CosInteger(0),
      const CosInteger(842),
      const CosInteger(1191),
    ]),
    'Rotate': const CosInteger(90),
    'Resources': CosDictionary({
      'Font': CosDictionary({'F1': const CosReference(5, 0)}),
    }),
    'Contents': const CosReference(4, 0),
  })); // obj 3
  builder.add(CosStream(
      CosDictionary({'Length': CosInteger(raw.length)}), raw)); // obj 4
  builder.add(CosDictionary({
    'Type': const CosName('Font'),
    'Subtype': const CosName('TrueType'),
    'BaseFont': const CosName('LiberationSans'),
    'Encoding': const CosName('WinAnsiEncoding'),
    'FirstChar': const CosInteger(32),
    'LastChar': const CosInteger(126),
    'Widths': CosArray([for (final w in _helveticaWidths) CosInteger(w)]),
    'FontDescriptor': const CosReference(6, 0),
  })); // obj 5
  builder.add(CosDictionary({
    'Type': const CosName('FontDescriptor'),
    'FontName': const CosName('LiberationSans'),
    'Flags': const CosInteger(32),
    'FontBBox': CosArray([
      const CosInteger(-543),
      const CosInteger(-303),
      const CosInteger(1301),
      const CosInteger(980),
    ]),
    'ItalicAngle': const CosInteger(0),
    'Ascent': const CosInteger(905),
    'Descent': const CosInteger(-212),
    'CapHeight': const CosInteger(729),
    'StemV': const CosInteger(80),
    'FontFile2': const CosReference(7, 0),
  })); // obj 6
  builder.add(CosStream(
      CosDictionary({'Length': CosInteger(fontProgram.length)}),
      fontProgram)); // obj 7
  return OcrDrawingSheet(builder.build(root: const CosReference(1, 0)), labels);
}
