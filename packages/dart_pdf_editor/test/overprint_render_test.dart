// Overprint compositing guard (issue #502).
//
// The renderer composites in RGB and cannot reproduce faithful subtractive
// (CMYK/spot colorant) overprint, but it now approximates the common case -
// a neutral/dark ink overprinting a coloured backdrop - with a `darken`
// (per-channel min) composite when the ExtGState /op (fill) or /OP (stroke)
// flag is set (§8.6.7). `darken` preserves the darker colorant channels the
// backdrop already carries and clips the lighter ones, which is why the Ghent
// GWG030 "over spot" patches, whose spot-green backdrop survives the neutral
// overprint, now render patch-uniform: their self-grading "X" marker is drawn
// in the same overprinting ink and lands on the same colour, so it disappears.
//
// This pins that behaviour directly against the fixture rather than through the
// macOS-only raster baseline (skipped on CI), in the spirit of
// ghent_jpx_indexed_test.dart: render the real page with overprint compositing
// on and off and assert the marker is present without it and absent with it.
//
// The "over CMYK" patches (DeviceCMYK backdrop, overprint mode 0) still need a
// real colorant buffer - their process channels are knocked out, which an RGB
// `darken` cannot distinguish from a spot backdrop of the same colour - so
// GWG030 as a whole stays an accepted deviation in ghent_render_test.dart.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';

import 'render_smoke_test.dart' show loadSystemFonts;

/// Patch 'a' of GWG030 (top-left of the left, "over spot" group) in the
/// 511x284 raster at pixelRatio 2: a green square whose overprinting neutral
/// ink forms an "X". The box is the patch interior, clear of its border, the
/// legend, and the arrow.
const _patchA = (left: 32, top: 72, right: 74, bottom: 122);

void main() {
  final file =
      File('../../test_corpora/ghent/2-SPOT/GWG030_Gray_K_black_OP_X1.pdf');

  testWidgets('GWG030 "over spot" overprint hides the self-grading X marker',
      (tester) async {
    if (!file.existsSync()) {
      markTestSkipped('test_corpora/ghent not found');
      return;
    }
    await tester.runAsync(() async {
      await loadSystemFonts();
      final doc = PdfDocument.open(file.readAsBytesSync());

      final withOverprint = await _lightInkPixels(doc.page(0), on: true);
      final withoutOverprint = await _lightInkPixels(doc.page(0), on: false);

      // Without overprint the neutral ink knocks the spot green out to a light
      // grey "X" - many light-neutral pixels inside the patch.
      expect(withoutOverprint.lightInk, greaterThan(150),
          reason: 'the fail-marker X should be visible without overprint');
      // With overprint the ink darkens onto the spot green instead of knocking
      // it out, so the X vanishes and the patch is (near) uniform green.
      expect(withOverprint.lightInk, lessThan(10),
          reason: 'overprint compositing should hide the X marker');
      expect(withOverprint.green, greaterThan(withOverprint.total * 0.8),
          reason: 'the patch should read as (near) uniform green');
    });
  });
}

class _PatchStats {
  _PatchStats(this.lightInk, this.green, this.total);
  final int lightInk;
  final int green;
  final int total;
}

Future<_PatchStats> _lightInkPixels(dynamic page, {required bool on}) async {
  CanvasPdfDevice.debugOverprintCompositing = on;
  final image = await PdfPageRenderer.renderImage(page, pixelRatio: 2.0);
  try {
    expect(image.width, 511);
    expect(image.height, 284);
    final rgba = (await image.toByteData(
            format: ui.ImageByteFormat.rawStraightRgba))!
        .buffer
        .asUint8List();
    return _statsIn(rgba, image.width, _patchA);
  } finally {
    image.dispose();
    CanvasPdfDevice.debugOverprintCompositing = true;
  }
}

_PatchStats _statsIn(
    Uint8List rgba, int width, ({int left, int top, int right, int bottom}) b) {
  var lightInk = 0, green = 0, total = 0;
  for (var y = b.top; y < b.bottom; y++) {
    for (var x = b.left; x < b.right; x++) {
      final i = (y * width + x) * 4;
      final r = rgba[i], g = rgba[i + 1], bl = rgba[i + 2];
      total++;
      final mx = r > g ? (r > bl ? r : bl) : (g > bl ? g : bl);
      final mn = r < g ? (r < bl ? r : bl) : (g < bl ? g : bl);
      if ((mx - mn) < 35 && mn > 130) {
        lightInk++; // light, near-neutral: the knocked-out grey X
      } else if (g > r && g > bl) {
        green++;
      }
    }
  }
  return _PatchStats(lightInk, green, total);
}
