// Overprint compositing guard (issue #502).
//
// Overprint (§8.6.7) is subtractive: an overprinting paint writes only the
// device colorants its colour space specifies and leaves the rest of the
// backdrop's alone. The renderer resolves that in a real CMYK/spot colorant
// buffer one layer above the painting device (PdfOverprintCompositor), so a
// DeviceCMYK backdrop and a spot backdrop of the same RGB colour - which the
// old `BlendMode.darken` approximation could not tell apart - now composite
// differently.
//
// This pins the result directly against the GWG030 fixture rather than through
// the macOS-only raster baseline (skipped on CI), in the spirit of
// ghent_jpx_indexed_test.dart.
//
// The fixture is a 6x2 grid of self-grading patches (labels a-l). Each patch
// paints a coloured backdrop - a DeviceN spot green, or a DeviceCMYK green of
// the same RGB colour - and overprints a 50% neutral ink over it: 50% K
// (DeviceCMYK), 50% gray (DeviceGray), or 50% "separation black" (Separation),
// under overprint mode 0 or 1. Each patch is drawn so a correct overprint
// leaves the whole patch one flat colour and an incorrect one leaves an "X"
// marker standing out against it. *Which* flat colour is per-patch:
//
//   - over the spot backdrop, and over CMYK where the neutral ink writes no
//     colorant the backdrop does not already carry at the same tint (K under
//     OPM 1, separation black), the patch stays green;
//   - over CMYK where the ink writes all four process colorants (K under
//     OPM 0, and gray under either mode - OPM's zero rule is DeviceCMYK's
//     alone), the backdrop's C/M/Y are knocked out and the patch goes grey.
//
// So the test measures, per patch, both how flat the interior is and which
// colour it settled on, under three compositing modes: the colorant buffer,
// the RGB `darken` approximation alone, and neither.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_graphics/pdf_graphics.dart' show PdfInterpreter;

import 'render_smoke_test.dart' show loadSystemFonts;

/// Patch interior boxes in the 511x284 raster at pixelRatio 2, inset ~8 px
/// from each patch border so the boxes clear the border stroke, the a-l
/// labels, and - the trap the previous, coarser measure fell into - the
/// neighbouring patch. The two 3x2 groups are the OPM-0 block (left) and the
/// OPM-1 block (right); column 1 is the spot backdrop, column 2 the DeviceCMYK
/// backdrop.
const _patches = <String, (int, int, int, int)>{
  // --- OPM 0 (left block) ---
  'a: 50% K over spot': (30, 67, 74, 119),
  'b: 50% gray over spot': (30, 135, 74, 186),
  'c: 50% sep. black over spot': (30, 202, 74, 251),
  'd: 50% K over CMYK': (90, 67, 134, 119),
  'e: 50% gray over CMYK': (90, 135, 134, 186),
  'f: 50% sep. black over CMYK': (90, 202, 134, 251),
  // --- OPM 1 (right block) ---
  'g: 50% K over spot': (375, 67, 419, 119),
  'h: 50% gray over spot': (375, 135, 419, 186),
  'i: 50% sep. black over spot': (375, 202, 419, 251),
  'j: 50% K over CMYK': (435, 67, 479, 119),
  'k: 50% gray over CMYK': (435, 135, 479, 186),
  'l: 50% sep. black over CMYK': (435, 202, 479, 251),
};

/// Patches whose ink writes only colorants the backdrop already carries at the
/// same tint, so a faithful overprint leaves the backdrop untouched and the
/// patch reads as the backdrop's green.
const _staysGreen = [
  'a: 50% K over spot',
  'b: 50% gray over spot',
  'c: 50% sep. black over spot',
  'f: 50% sep. black over CMYK',
  'g: 50% K over spot',
  'h: 50% gray over spot',
  'i: 50% sep. black over spot',
  'j: 50% K over CMYK',
  'l: 50% sep. black over CMYK',
];

/// The colorant-buffer patches: a neutral ink writing all four process
/// colorants over a DeviceCMYK backdrop knocks its C/M/Y out, so the patch
/// goes grey. No RGB compositor can produce this - in RGB the CMYK green and
/// the spot green are the same pixels, and the spot must survive - which is
/// why the buffer exists (issue #502,
/// doc/dev-log/2026-07-23-overprint-rgb-ceiling.md).
const _knocksOutToGrey = [
  'd: 50% K over CMYK',
  'e: 50% gray over CMYK',
  'k: 50% gray over CMYK',
];

/// How overprint composites for one render pass.
enum _Mode {
  /// The colorant buffer resolves the composite in ink space (shipped).
  colorants,

  /// No buffer; the painting device's RGB `darken` stand-in only.
  darken,

  /// Neither: an overprinting paint knocks the backdrop out like any other.
  none,
}

void main() {
  final file =
      File('../../test_corpora/ghent/2-SPOT/GWG030_Gray_K_black_OP_X1.pdf');

  testWidgets('GWG030 overprint flattens every self-grading marker',
      (tester) async {
    if (!file.existsSync()) {
      markTestSkipped('test_corpora/ghent not found');
      return;
    }
    await tester.runAsync(() async {
      await loadSystemFonts();
      final doc = PdfDocument.open(file.readAsBytesSync());

      final colorants = await _measure(doc.page(0), _Mode.colorants);
      final darken = await _measure(doc.page(0), _Mode.darken);
      final none = await _measure(doc.page(0), _Mode.none);

      // 1. Every patch grades itself as passing: one flat field, no marker.
      //    The tolerance is anti-aliasing on the patch border, nothing more.
      for (final name in _patches.keys) {
        expect(colorants[name]!.spread, lessThan(60),
            reason: 'overprint should flatten the marker on "$name" '
                '(spread ${colorants[name]!.spread})');
      }

      // 2. ...at the right colour, which is what makes "flat" mean anything:
      //    the backdrop's green where the ink adds no colorant, and the ink's
      //    own neutral where it knocks the process colorants out.
      for (final name in _staysGreen) {
        expect(colorants[name]!.isGreen, isTrue,
            reason: '"$name" should settle on the backdrop green, got '
                '${colorants[name]!.dominant}');
      }
      for (final name in _knocksOutToGrey) {
        expect(colorants[name]!.isNeutral, isTrue,
            reason: '"$name" should knock the process colorants out to grey, '
                'got ${colorants[name]!.dominant}');
      }

      // 3. Without any overprint compositing the ink knocks the backdrop out,
      //    so every "stays green" patch shows its marker over the green.
      for (final name in _staysGreen) {
        expect(none[name]!.spread, greaterThan(150),
            reason: 'without overprint the marker on "$name" should be '
                'visible (spread ${none[name]!.spread})');
      }

      // 4. The RGB ceiling this buffer removes: `darken` alone flattens the
      //    patches whose ink only darkens, but cannot knock a DeviceCMYK
      //    backdrop out - it leaves the marker standing on d, e and k.
      for (final name in _knocksOutToGrey) {
        expect(darken[name]!.spread, greaterThan(200),
            reason: 'the RGB darken approximation should still leave "$name" '
                'marked (spread ${darken[name]!.spread})');
      }
    });
  });
}

/// One patch interior, summarised.
class _Patch {
  _Patch(this.spread, this.dominant);

  /// Per-mille of interior pixels that are not the patch's dominant colour -
  /// near 0 for a flat field, hundreds when a marker stands on it.
  final int spread;

  /// The dominant colour, as (r, g, b).
  final (int, int, int) dominant;

  bool get isGreen =>
      dominant.$2 > dominant.$1 + 25 && dominant.$2 > dominant.$3 + 25;

  bool get isNeutral =>
      (dominant.$1 - dominant.$2).abs() < 24 &&
      (dominant.$2 - dominant.$3).abs() < 24 &&
      dominant.$1 > 80 &&
      dominant.$1 < 220;
}

/// Renders GWG030 under [mode] and summarises every patch interior.
Future<Map<String, _Patch>> _measure(dynamic page, _Mode mode) async {
  PdfInterpreter.debugResolveOverprint = mode == _Mode.colorants;
  CanvasPdfDevice.debugOverprintCompositing = mode != _Mode.none;
  final image = await PdfPageRenderer.renderImage(page, pixelRatio: 2.0);
  try {
    expect(image.width, 511);
    expect(image.height, 284);
    final rgba =
        (await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!
            .buffer
            .asUint8List();
    return {
      for (final entry in _patches.entries)
        entry.key: _summarise(rgba, image.width, entry.value),
    };
  } finally {
    image.dispose();
    PdfInterpreter.debugResolveOverprint = true;
    CanvasPdfDevice.debugOverprintCompositing = true;
  }
}

/// Summarises a patch interior as its median colour plus the share of pixels
/// visibly away from it.
///
/// A median (not a modal bucket) is what makes the measure stable: the flat
/// fields carry a one-or-two-level anti-aliasing fringe along the shapes drawn
/// inside them, which any fixed quantisation can split across buckets, while a
/// marker is 50-130 levels away. [_markerTolerance] sits between the two.
_Patch _summarise(Uint8List rgba, int width, (int, int, int, int) box) {
  final (x0, y0, x1, y1) = box;
  final histogram = List.generate(3, (_) => List<int>.filled(256, 0));
  var total = 0;
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      final i = (y * width + x) * 4;
      for (var channel = 0; channel < 3; channel++) {
        histogram[channel][rgba[i + channel]]++;
      }
      total++;
    }
  }
  if (total == 0) return _Patch(0, (0, 0, 0));
  final median = [
    for (final channel in histogram) _median(channel, total),
  ];
  var away = 0;
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      final i = (y * width + x) * 4;
      for (var channel = 0; channel < 3; channel++) {
        if ((rgba[i + channel] - median[channel]).abs() > _markerTolerance) {
          away++;
          break;
        }
      }
    }
  }
  return _Patch(1000 * away ~/ total, (median[0], median[1], median[2]));
}

/// Per-channel distance from the patch median past which a pixel counts as
/// "not part of the flat field".
const _markerTolerance = 16;

int _median(List<int> histogram, int total) {
  var seen = 0;
  for (var value = 0; value < histogram.length; value++) {
    seen += histogram[value];
    if (seen * 2 >= total) return value;
  }
  return 255;
}
