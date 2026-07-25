// Ghent PDF Output Suite V5.0 - rasterization regression suite.
//
// One test per patch PDF in test_corpora/ghent. Every page is rendered
// through the real pipeline and must
//   1. rasterize without throwing,
//   2. actually put ink on the page (patches are never blank), and
//   3. match the stored baseline raster pixel-for-pixel within tolerance.
//
// Baselines live in test_corpora/ghent/_baselines (checked in). A missing
// baseline is seeded automatically on first run; to accept an intentional
// rendering change:
//   GHENT_UPDATE=1 fvm flutter test test/ghent_render_test.dart
// On mismatch the actual render and a per-pixel diff map are written to
// test_corpora/ghent/_failures (git-ignored) for inspection.
//
// The pixel diff is a LOCAL golden check: baselines are rendered on macOS, and
// CI (Linux) rasterizes text with different fonts/antialiasing, so the diff can
// never match there. Under CI the comparison is skipped - every page is still
// rasterized and asserted non-blank (catching crashes and blank-render
// regressions), matching how pdfjs_render_test only diffs when opted in. Force
// the comparison anywhere with GHENT_COMPARE=1.
//
// For visual review, set GHENT_RENDER_OUT to write PNGs plus an index.html:
//   GHENT_RENDER_OUT=../../test_corpora/ghent/_renders \
//     fvm flutter test test/ghent_render_test.dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';

import 'render_gallery.dart';
import 'render_smoke_test.dart' show loadSystemFonts;

const _pixelRatio = 2.0;

/// Patches whose baseline pixel-diff is a known, accepted deviation: their
/// colour handling (overprint simulation, DeviceN/spot separations, ICC v4
/// CMYK, 16-bit images) is not reproduced pixel-for-pixel by this renderer,
/// as documented in CLAUDE.md (the baselines pin current behavior, not GWG
/// conformance). They are still rendered and asserted non-blank - only the
/// baseline comparison is skipped, so crashes and blank-render regressions
/// are still caught. Accept an intentional change to any of these with
/// GHENT_UPDATE=1 after removing it from this set.
///
/// The two `GWG08x_DeviceN-Support` spot pages deliberately stay OUT of this
/// set: their images are /Indexed over a Separation/DeviceN base, and the
/// tolerance here was broad enough to hide those images failing to draw at all
/// (issue #430 - the pages self-grade with a ✗ that the missing images left
/// exposed). Pixel-enforcing them against fresh baselines catches a future
/// total image-loss instead of tolerating it as a colour deviation.
///
/// `GWG170_JPEG2000...DeviceCMYK` likewise stays OUT: its JPEG2000 image is
/// /Indexed over DeviceCMYK with a single-entry palette (hival 0), and once
/// that palette is honoured (issue #431) the image and the page's fail-marker
/// "X" are the same DeviceCMYK colour, so the X vanishes and the page grades
/// itself as passing - it is pixel-enforced to keep it that way. Its ICC
/// sibling `GWG172_JPEG2000...ICCBasedRGB` below stays IN the set: the same
/// fix makes its image draw (it was solid black), but the square is DeviceCMYK
/// green while the image is ICCBased-RGB green, and those two greens are not
/// colour-managed to match here, so a faint X remains as a genuine colour
/// deviation. The dedicated JPX decode guard (pdf_graphics
/// ghent_jpx_indexed_test.dart) pins both images to their palette colour so a
/// regression back to the black square cannot hide behind this tolerance.
///
/// `GWG030_Gray_K_black_OP_X1` used to be here and is now pixel-enforced: the
/// CMYK/spot colorant buffer (issue #502) makes overprint subtractive, so all
/// twelve of its self-grading patches come out uniform - including the three
/// where a neutral ink must knock a DeviceCMYK backdrop's process colorants out
/// to grey while a spot backdrop of the same RGB colour survives, which no RGB
/// compositor could separate. `overprint_render_test.dart` pins the per-patch
/// result platform-independently.
///
/// The three `GWG19x_DeviceN_Overprint` pages left the set with issue #604,
/// which gave a decoded raster the same colorant reading vector paint has: an
/// overprinting image is now drawn as a substitute raster whose samples are the
/// subtractive composite, so all four patches on each page (two vector, two
/// image) come out uniform. `overprint_render_test.dart` pins those per patch
/// too, alongside GWG031 - whose whole subject is an overprinting grayscale
/// raster over a spot green, and which now matches its own "Correct" thumbnail
/// rather than its "Wrong" one.
///
/// `GWG010_CMYK_OP` (never in this set) moved with the same change and was
/// re-seeded: its "mask" patch draws an /Indexed-over-DeviceCMYK 50%-magenta
/// raster over a rich-black X, and under OPM 1 that raster's zero components
/// leave the backdrop's C/Y/K standing - so the X now shows through in the
/// OPM-1 row and is still knocked out to flat pink in the OPM-0 row, which is
/// the contrast the page exists to draw. (Its "image" patch straddles two
/// backdrops at once and still declines; see the dev log.)
const _knownBaselineDeviations = <String>{
  '1-CMYK/Ghent_PDF-Output-Test-V50_CMYK_X4.pdf',
  '2-SPOT/Ghent_PDF-Output-Test-V50_SPOT_X4.pdf',
  '2-SPOT/GWG020_CMYKSpot_OP_x1a.pdf',
  '3-ICC-CMS/Ghent_PDF-Output-Test-V50_ICC-CMS_X4.pdf',
  '3-ICC-CMS/GWG172_JPEG2000_compression_ICCBasedRGB_x4.pdf',
  '3-ICC-CMS/GWG182_16Bit_Images_ICCbasedGray_x4.pdf',
  '3-ICC-CMS/GWG184_16Bit_Images_ICCbasedCMYK_x4.pdf',
  '3-ICC-CMS/GWG205_ICC-V4-CMYK-Image_x4.pdf',
  '3-ICC-CMS/GWG221_OutputIntentChangeIndicator_x4.pdf',
  '3-ICC-CMS/GWG230_Four_different Grays_x1a.pdf',
};

/// Per-channel difference below this is treated as identical.
const _channelTolerance = 8;

/// Fraction of differing pixels allowed before the test fails.
const _maxDifferingFraction = 0.0005;

void main() {
  final root = Directory('../../test_corpora/ghent');
  if (!root.existsSync()) {
    test('Ghent suite', skip: 'test_corpora/ghent not found', () {});
    return;
  }
  final update = Platform.environment['GHENT_UPDATE'] == '1';
  // Pixel-diff against the (macOS) baselines locally; in CI just render every
  // page. GHENT_COMPARE=1 forces the diff; GHENT_UPDATE implies it.
  final compare = update ||
      Platform.environment['GHENT_COMPARE'] == '1' ||
      Platform.environment['CI'] != 'true';
  final renderOut = Platform.environment['GHENT_RENDER_OUT'];
  final gallery =
      renderOut == null ? null : RenderGallery(Directory(renderOut));

  final files = root
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) =>
          f.path.toLowerCase().endsWith('.pdf') &&
          !f.path.contains('/_baselines/') &&
          !f.path.contains('/_failures/') &&
          !f.path.contains('/_renders/'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in files) {
    final name = file.path.substring(root.path.length + 1);
    // a baseline diff here is an accepted colour-fidelity deviation: render
    // and assert non-blank, but don't enforce the pixel match (and surface
    // the test as skipped). GHENT_UPDATE always re-seeds, even these.
    final knownDeviation = _knownBaselineDeviations.contains(name) && !update;
    testWidgets(name, (tester) async {
      await tester.runAsync(() async {
        await loadSystemFonts();
        final doc = PdfDocument.open(file.readAsBytesSync());
        for (var i = 0; i < doc.pageCount; i++) {
          final baseline = File('${root.path}/_baselines/$name.p$i.png');
          final image = await PdfPageRenderer.renderImage(doc.page(i),
                  pixelRatio: _pixelRatio)
              .timeout(const Duration(seconds: 90));
          try {
            final pixels = (await image.toByteData(
                    format: ui.ImageByteFormat.rawStraightRgba))!
                .buffer
                .asUint8List();

            expect(_inkFraction(pixels), greaterThan(0.0005),
                reason: '$name page $i rendered (nearly) blank');

            if (compare && !knownDeviation) {
              await _checkBaseline(
                root: root,
                name: name,
                page: i,
                image: image,
                pixels: pixels,
                update: update,
              );
            }
            if (gallery != null) {
              await gallery.add(
                pdfName: name,
                page: i,
                image: image,
                baseline: baseline.existsSync() ? baseline : null,
              );
            }
          } finally {
            image.dispose();
          }
        }
        if (knownDeviation) {
          markTestSkipped('$name: known baseline deviation - colour handling '
              '(overprint/DeviceN/spot/ICC-v4/16-bit) is not pixel-exact; '
              'still asserted to render non-blank. GHENT_UPDATE=1 to re-baseline.');
        }
      });
    }, timeout: const Timeout(Duration(minutes: 3)));
  }
}

/// Fraction of pixels that are not (close to) the white page background.
double _inkFraction(Uint8List rgba) {
  var ink = 0;
  for (var i = 0; i < rgba.length; i += 4) {
    if (rgba[i] < 250 || rgba[i + 1] < 250 || rgba[i + 2] < 250) ink++;
  }
  return ink / (rgba.length ~/ 4);
}

Future<void> _checkBaseline({
  required Directory root,
  required String name,
  required int page,
  required ui.Image image,
  required Uint8List pixels,
  required bool update,
}) async {
  final baseline = File('${root.path}/_baselines/$name.p$page.png');

  if (update || !baseline.existsSync()) {
    baseline.parent.createSync(recursive: true);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    baseline.writeAsBytesSync(png!.buffer.asUint8List());
    return;
  }

  final codec = await ui.instantiateImageCodec(baseline.readAsBytesSync());
  final expected = (await codec.getNextFrame()).image;
  try {
    expect('${image.width}x${image.height}',
        '${expected.width}x${expected.height}',
        reason: '$name page $page raster size changed '
            '(GHENT_UPDATE=1 to accept)');

    final expectedPixels =
        (await expected.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!
            .buffer
            .asUint8List();

    // Shared with the PDF.js suite and the comparison feature: differing
    // pixels marked red over the actual render.
    final diff = PdfPageComparison.comparePixels(
      pixels,
      expectedPixels,
      width: image.width,
      height: image.height,
      channelTolerance: _channelTolerance,
      style: PdfDiffStyle.redOverImage,
    );
    final fraction = diff.differenceFraction;

    if (fraction > _maxDifferingFraction) {
      await _writeFailure(root, name, page, image, diff);
    }
    expect(fraction, lessThanOrEqualTo(_maxDifferingFraction),
        reason: '$name page $page deviates from the baseline in '
            '${(fraction * 100).toStringAsFixed(3)}% of pixels - actual and '
            'diff written to test_corpora/ghent/_failures '
            '(GHENT_UPDATE=1 to accept)');
  } finally {
    expected.dispose();
  }
}

Future<void> _writeFailure(Directory root, String name, int page,
    ui.Image actual, PdfPixelDiff diff) async {
  final dir = Directory('${root.path}/_failures')..createSync(recursive: true);
  final flat = name.replaceAll('/', '_');

  final png = await actual.toByteData(format: ui.ImageByteFormat.png);
  File('${dir.path}/$flat.p$page.actual.png')
      .writeAsBytesSync(png!.buffer.asUint8List());

  final diffImage = await diff.toImage();
  final diffPng = await diffImage.toByteData(format: ui.ImageByteFormat.png);
  File('${dir.path}/$flat.p$page.diff.png')
      .writeAsBytesSync(diffPng!.buffer.asUint8List());
  diffImage.dispose();
}
