// Ghent PDF Output Suite V5.0 — rasterization regression suite.
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
// never match there. Under CI the comparison is skipped — every page is still
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
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';

import 'render_gallery.dart';
import 'render_smoke_test.dart' show loadSystemFonts;

const _pixelRatio = 2.0;

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

            if (compare) {
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
            '${(fraction * 100).toStringAsFixed(3)}% of pixels — actual and '
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
