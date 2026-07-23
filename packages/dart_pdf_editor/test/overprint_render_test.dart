// Overprint compositing guard (issue #502).
//
// The renderer composites in RGB and cannot reproduce faithful subtractive
// (CMYK/spot colorant) overprint, but it approximates the common case - a
// neutral/dark ink overprinting a coloured backdrop - with a `darken`
// (per-channel min) composite when the ExtGState /op (fill) or /OP (stroke)
// flag is set (§8.6.7). `darken` preserves the darker colorant channels the
// backdrop already carries and clips the lighter ones, so a neutral ink lands
// on the same colour it overprints and the self-grading "X" marker disappears.
//
// This pins that behaviour directly against the GWG030 fixture rather than
// through the macOS-only raster baseline (skipped on CI), in the spirit of
// ghent_jpx_indexed_test.dart: render the real page with overprint compositing
// on and off and measure, per patch, how much of the patch interior is a
// non-green neutral (the knocked-out grey "X").
//
// The fixture is a 6x2 grid of self-grading patches (labels a-l). Each patch
// overprints a 50% neutral ink - 50% K (DeviceCMYK), 50% gray (DeviceGray), or
// 50% "separation black" (Separation) - over either a DeviceN spot-green
// backdrop or a DeviceCMYK-green backdrop, under overprint mode 0 or 1. The
// darken approximation flattens the marker on every "over spot" patch and on
// the "over CMYK" patches whose ink only darkens (K under OPM 1, separation
// black). It cannot flatten the "over CMYK" patches where a neutral ink knocks
// the process colorants out to grey - 50% K over CMYK under OPM 0, and 50% gray
// over CMYK under either mode - because distinguishing a DeviceCMYK backdrop's
// process channels from a spot backdrop of the same RGB colour needs a colorant
// buffer this RGB compositor does not have. Those three patches (d, e, k) are
// therefore the residual gap, and GWG030 as a whole stays an accepted deviation
// in ghent_render_test.dart. See doc/dev-log/2026-07-23-overprint-rgb-ceiling.md
// for the full per-patch breakdown and the empirical strategy comparison that
// shows darken-always is the RGB optimum.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';

import 'render_smoke_test.dart' show loadSystemFonts;

/// Patch interior boxes in the 511x284 raster at pixelRatio 2, each well clear
/// of the patch border, the legend, and the arrows. The two 3x2 groups are the
/// OPM-0 block (left) and the OPM-1 block (right). Column 1 is the spot
/// backdrop, column 2 the DeviceCMYK backdrop.
const _patches = <String, (int, int, int, int)>{
  // --- OPM 0 (left block) ---
  'a: 50% K over spot': (34, 74, 72, 120),
  'd: 50% K over CMYK': (100, 72, 140, 120),
  'e: 50% gray over CMYK': (100, 128, 140, 176),
  'f: 50% sep. black over CMYK': (100, 184, 140, 228),
  // --- OPM 1 (right block) ---
  'g: 50% K over spot': (368, 74, 406, 120),
  'h: 50% gray over spot': (368, 128, 406, 176),
  'i: 50% sep. black over spot': (368, 184, 406, 228),
  'j: 50% K over CMYK': (440, 74, 480, 120),
  'k: 50% gray over CMYK': (440, 128, 480, 176),
  'l: 50% sep. black over CMYK': (440, 184, 480, 228),
};

/// Patches the darken approximation flattens - after overprint they read as
/// (near) uniform green, the self-grading marker gone.
const _faithful = ['a: 50% K over spot', 'g: 50% K over spot',
  'h: 50% gray over spot', 'i: 50% sep. black over spot', 'j: 50% K over CMYK'];

/// The residual colorant-buffer gap: a neutral ink knocks the process colorants
/// of a DeviceCMYK backdrop out to grey, which an RGB `darken` cannot reproduce,
/// so the marker survives. A future colorant buffer should flatten these too -
/// at which point these assertions flip (and GWG030 leaves the deviation set).
const _cmykKnockoutGap = [
  'd: 50% K over CMYK',
  'e: 50% gray over CMYK',
  'k: 50% gray over CMYK',
];

void main() {
  final file =
      File('../../test_corpora/ghent/2-SPOT/GWG030_Gray_K_black_OP_X1.pdf');

  testWidgets('GWG030 overprint flattens the self-grading markers it can',
      (tester) async {
    if (!file.existsSync()) {
      markTestSkipped('test_corpora/ghent not found');
      return;
    }
    await tester.runAsync(() async {
      await loadSystemFonts();
      final doc = PdfDocument.open(file.readAsBytesSync());

      final on = await _neutralFractions(doc.page(0), on: true);
      final off = await _neutralFractions(doc.page(0), on: false);

      // Without overprint every patch knocks the ink out over the backdrop, so
      // a large neutral "X" (and knocked-out square) is present throughout.
      for (final name in [..._faithful, ..._cmykKnockoutGap]) {
        expect(off[name]!, greaterThan(200),
            reason: 'without overprint the marker on "$name" should be visible');
      }

      // With overprint the darken approximation flattens the marker on the
      // patches it can reach: the interior reads as (near) uniform green.
      for (final name in _faithful) {
        expect(on[name]!, lessThan(80),
            reason: 'overprint should flatten the marker on "$name" '
                '(was ${off[name]} without, ${on[name]} with)');
      }

      // The DeviceCMYK-backdrop knockout patches stay non-uniform: their marker
      // survives because the RGB compositor cannot knock out the backdrop's
      // process colorants. Pin the gap so a colorant-buffer fix flips it here.
      for (final name in _cmykKnockoutGap) {
        expect(on[name]!, greaterThan(350),
            reason: 'the "$name" marker still needs a colorant buffer '
                '(#502); overprint left it at ${on[name]}');
      }
    });
  });
}

/// Renders GWG030 with overprint compositing [on] or off and returns, per
/// patch, the fraction (per-mille) of the interior that is a non-green neutral
/// - the knocked-out grey marker - excluding the near-black border and any
/// near-white.
Future<Map<String, int>> _neutralFractions(dynamic page,
    {required bool on}) async {
  CanvasPdfDevice.debugOverprintCompositing = on;
  final image = await PdfPageRenderer.renderImage(page, pixelRatio: 2.0);
  try {
    expect(image.width, 511);
    expect(image.height, 284);
    final rgba = (await image.toByteData(
            format: ui.ImageByteFormat.rawStraightRgba))!
        .buffer
        .asUint8List();
    return {
      for (final entry in _patches.entries)
        entry.key: _neutralPerMille(rgba, image.width, entry.value),
    };
  } finally {
    image.dispose();
    CanvasPdfDevice.debugOverprintCompositing = true;
  }
}

int _neutralPerMille(Uint8List rgba, int width, (int, int, int, int) box) {
  final (x0, y0, x1, y1) = box;
  var neutral = 0, total = 0;
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      final i = (y * width + x) * 4;
      final r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
      final mx = r > g ? (r > b ? r : b) : (g > b ? g : b);
      final mn = r < g ? (r < b ? r : b) : (g < b ? g : b);
      total++;
      // near-neutral, but not the near-black border or a near-white pixel
      if ((mx - mn) < 28 && mn > 55 && mx < 245) neutral++;
    }
  }
  return total == 0 ? 0 : 1000 * neutral ~/ total;
}
