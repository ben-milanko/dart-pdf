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
//
// Issue #604 extended the same guard to *image* overprint. GWG190/191/192 each
// grade four patches - two vector, two image - and GWG031 grades an
// overprinting grayscale raster over a spot green. Both are covered below,
// against the same measure.
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

  // --- image overprint (issue #604) ---

  for (final page in _deviceNPages) {
    testWidgets(
        '${page.name} flattens its image patches as well as its vector '
        'ones', (tester) async {
      final file = File('../../test_corpora/ghent/1-CMYK/${page.file}');
      if (!file.existsSync()) {
        markTestSkipped('test_corpora/ghent not found');
        return;
      }
      await tester.runAsync(() async {
        await loadSystemFonts();
        final doc = PdfDocument.open(file.readAsBytesSync());
        final boxes = page.patchBoxes;

        final colorants = await _measure(doc.page(0), _Mode.colorants, boxes);
        final none = await _measure(doc.page(0), _Mode.none, boxes);

        for (final entry in boxes.entries) {
          final patch = colorants[entry.key]!;
          // Each patch is a rectangle with an X-shaped hole through which the
          // overprinting paint shows; when overprint is honoured the composite
          // is the rectangle's own colour and the X vanishes.
          expect(patch.spread, lessThan(60),
              reason: '${page.name} "${entry.key}" should render flat '
                  '(spread ${patch.spread})');
          expect(_near(patch.dominant, page.reference(entry.key)), isTrue,
              reason: '${page.name} "${entry.key}" should settle on '
                  '${page.reference(entry.key)}, got ${patch.dominant}');
        }

        // Patch b is the one this issue moved: without overprint compositing
        // the raster knocks the CMYK-black backdrop out and its X stands proud,
        // which is the marker the fixture grades ("a faint X means that OP is
        // not honored, or the image was converted to DeviceCMYK for b").
        //
        // Patch d is flat either way - its DeviceN ink and the reference
        // rectangle are the same cyan - so what it grades is not overprint but
        // the overprint *mode*: applying the OPM-1 zero rule to a DeviceN space
        // (it is DeviceCMYK's alone, §8.6.7.3) would leave the backdrop's black
        // standing. That is what the colour assertion above pins.
        const marked = 'b: image over CMYK black';
        expect(none[marked]!.spread, greaterThan(150),
            reason: '${page.name} "$marked" should be marked without overprint '
                '(spread ${none[marked]!.spread})');
      });
    });
  }

  testWidgets('GWG031 lets an overprinting gray raster keep the spot backdrop',
      (tester) async {
    final file = File(
        '../../test_corpora/ghent/2-SPOT/GWG031_Gray Image Overprint_CMYK+Spot_X1a.pdf');
    if (!file.existsSync()) {
      markTestSkipped('test_corpora/ghent not found');
      return;
    }
    await tester.runAsync(() async {
      await loadSystemFonts();
      final doc = PdfDocument.open(file.readAsBytesSync());

      // Margins of the big panel: covered by the overprinting raster's *white*
      // background over a Separation "GWG Green" backdrop, and clear of both
      // the cyan rectangle and the drop shadow. Under overprint mode 1 a
      // DeviceCMYK 0/0/0/0 sample writes no colorant at all, so the green must
      // survive - the fixture's whole point ("Overprinting must be honored for
      // the output"), and exactly what separates its own Correct and Wrong
      // thumbnails: a white box around the drop shadow, or none.
      const corners = <String, (int, int, int, int)>{
        'panel right margin': (310, 110, 334, 118),
        'panel bottom margin': (196, 202, 300, 207),
      };
      final colorants = await _measure(doc.page(0), _Mode.colorants, corners);
      final none = await _measure(doc.page(0), _Mode.none, corners);
      for (final name in corners.keys) {
        expect(colorants[name]!.isGreen, isTrue,
            reason: '"$name" should keep the spot green under the raster\'s '
                'white background, got ${colorants[name]!.dominant}');
        expect(none[name]!.isGreen, isFalse,
            reason: 'without overprint "$name" is knocked out to the raster\'s '
                'white, which is what the fixture grades as wrong');
      }

      // The same page through the two-walk render path, which discovers the
      // images to decode in a *separate* scan before painting. An overprinting
      // raster is drawn as a substitute stream the colorant buffer builds, so
      // the two walks have to agree on which stream that is - otherwise the
      // paint walk asks the decoded-image cache for something the collect walk
      // never decoded and the image is silently skipped (a blank panel, not a
      // wrong colour). See `_beginOverprint`'s scan-walk note.
      final twoWalk =
          await _measure(doc.page(0), _Mode.colorants, corners, false);
      for (final name in corners.keys) {
        expect(twoWalk[name]!.dominant, colorants[name]!.dominant,
            reason: 'the collect walk and the paint walk must draw the same '
                'stream for "$name"');
      }
    });
  });

  testWidgets('GWG020 grades all ten spot/process overprint patches as passing',
      (tester) async {
    final file =
        File('../../test_corpora/ghent/2-SPOT/GWG020_CMYKSpot_OP_x1a.pdf');
    if (!file.existsSync()) {
      markTestSkipped('test_corpora/ghent not found');
      return;
    }
    await tester.runAsync(() async {
      await loadSystemFonts();
      final doc = PdfDocument.open(file.readAsBytesSync());

      // Ten patches in two rows of five (font / vector / image / mask /
      // shading), each a spot-green square with a white X that must vanish
      // when overprint is honoured. This intentionally covers every painting
      // primitive in the sample: exact glyph outlines, vector paths, decoded
      // image colorants, /ImageMask stencils, and sampled shadings.
      const patches = <String, (int, int, int, int)>{
        'a: font, cmyk over spot': (79, 81, 115, 117),
        'b: vector, cmyk over spot': (164, 81, 200, 117),
        'c: image, cmyk over spot': (249, 81, 284, 117),
        'd: mask, cmyk over spot': (335, 81, 370, 117),
        'e: shading, cmyk over spot': (419, 81, 454, 117),
        'f: font, spot over cmyk': (79, 162, 115, 198),
        'g: vector, spot over cmyk': (164, 162, 200, 198),
        'h: image, spot over cmyk': (249, 162, 284, 198),
        'i: mask, spot over cmyk': (335, 162, 370, 198),
        'j: shading, spot over cmyk': (419, 162, 454, 198),
      };
      final colorants = await _measure(doc.page(0), _Mode.colorants, patches);
      final none = await _measure(doc.page(0), _Mode.none, patches);
      for (final name in patches.keys) {
        expect(colorants[name]!.spread, lessThan(60),
            reason: '"$name" should render flat '
                '(spread ${colorants[name]!.spread})');
        expect(colorants[name]!.isGreen, isTrue,
            reason: '"$name" should settle on the spot green, got '
                '${colorants[name]!.dominant}');
        expect(none[name]!.spread, greaterThan(150),
            reason: 'without overprint "$name" should show its white X '
                '(spread ${none[name]!.spread})');
      }
    });
  });
}

/// A Ghent DeviceN overprint page: four self-grading patches, two painted with
/// vector art and two with an image XObject in the same colour space.
class _DeviceNPage {
  const _DeviceNPage(
      this.name, this.file, this.bottom, this.vector, this.image);

  final String name;
  final String file;

  /// Bottom edge of the patch row in user space; the patches are 22.678 tall
  /// and sit at four fixed columns.
  final double bottom;

  /// sRGB the first pair of patches (a/b, "over CMYK black") must settle on,
  /// and the second pair (c/d, "0% channels").
  final (int, int, int) vector;
  final (int, int, int) image;

  (int, int, int) reference(String patch) =>
      patch.startsWith('a') || patch.startsWith('b') ? vector : image;

  /// The four patch interiors as raster boxes, inset to clear their borders.
  Map<String, (int, int, int, int)> get patchBoxes {
    // Left edges of patches a-d, from the fixture's own `re` operands.
    const lefts = <String, double>{
      'a: vector over CMYK black': 0,
      'b: image over CMYK black': 51.56,
      'c: vector 0% channels': 103.12,
      'd: image 0% channels': 154.96,
    };
    return {
      for (final entry in lefts.entries)
        entry.key: _patchPixels(_originX + entry.value, bottom),
    };
  }

  /// Left edge of patch a; the pages differ by a hair (35.83 vs 36.00) and the
  /// inset below absorbs it.
  static const double _originX = 35.92;
}

const _deviceNPages = <_DeviceNPage>[
  // "a + b must be rendered to solid Black (100C100K) rectangles"; "c + d must
  // be rendered to solid Cyan rectangles". The RGB values below are those
  // inks after the files' CMYK OutputIntent, not the old unmanaged alternates.
  _DeviceNPage('GWG190', 'GWG190_DeviceN_Overprint_Black_X1a.pdf', 80.34,
      (4, 34, 44), (0, 160, 227)),
  _DeviceNPage('GWG191', 'GWG191_DeviceN_Overprint_Yellow_X1a.pdf', 94.14,
      (0, 152, 71), (0, 160, 227)),
  _DeviceNPage('GWG192', 'GWG192_DeviceN_Overprint_White_X1a.pdf', 80.34,
      (227, 31, 37), (255, 255, 255)),
];

/// A 22.678pt patch at ([left], [bottom]) in user space, as a raster box inset
/// far enough to clear the patch border and its anti-aliasing.
(int, int, int, int) _patchPixels(double left, double bottom) {
  const size = 22.678, inset = 2.5, height = 141.732;
  int px(double x) => ((x + inset) * _pixelRatio).round();
  return (
    px(left),
    ((height - bottom - size + inset) * _pixelRatio).round(),
    ((left + size - inset) * _pixelRatio).round(),
    ((height - bottom - inset) * _pixelRatio).round(),
  );
}

bool _near((int, int, int) a, (int, int, int) b, {int tolerance = 12}) =>
    (a.$1 - b.$1).abs() <= tolerance &&
    (a.$2 - b.$2).abs() <= tolerance &&
    (a.$3 - b.$3).abs() <= tolerance;

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

/// The ratio every box in this file is stated at; the Ghent overprint pages are
/// all 255.118 x 141.732 pt, so 511 x 284 raster pixels.
const double _pixelRatio = 2.0;

/// Renders [page] under [mode] and summarises each of [boxes].
///
/// [recorded] false takes the two-walk render path (a scan-only collect pass,
/// then a paint pass) instead of the single recorded walk.
Future<Map<String, _Patch>> _measure(dynamic page, _Mode mode,
    [Map<String, (int, int, int, int)> boxes = _patches,
    bool recorded = true]) async {
  PdfInterpreter.debugResolveOverprint = mode == _Mode.colorants;
  CanvasPdfDevice.debugOverprintCompositing = mode != _Mode.none;
  final image = await PdfPageRenderer.renderImage(page,
      pixelRatio: _pixelRatio, recorded: recorded);
  try {
    expect(image.width, 511);
    expect(image.height, 284);
    final rgba =
        (await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!
            .buffer
            .asUint8List();
    return {
      for (final entry in boxes.entries)
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
