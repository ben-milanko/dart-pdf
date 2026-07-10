// B1 gate: device-vs-device parity for the sparse-strip shader renderer.
//
// Every Ghent page is rendered twice in-process at the same pixel ratio -
// once through the stock CanvasPdfDevice pipeline, once through
// StripPdfDevice - and diffed with the ghent_render_test thresholds
// (8/channel, 0.05% of pixels) plus a classified relaxed tier.
//
// Why a relaxed tier is needed (measured, see strip_curve_probe_test):
// strip coverage is exact-area analytic AA, but Skia's own curve raster
// deviates from the true area by up to ~0.2 coverage on cubic edges (a
// glyph-sized cubic probe read analytic=77, strips=79, skia=135), and
// Skia renders sub-device-pixel strokes as alpha-modulated 1-px hairlines.
// Those disagreements sit exactly on high-contrast anti-aliased edges and
// are cases where the strip raster is CLOSER to ground truth than the
// canvas render, so pixel-level agreement there is neither achievable nor
// desirable. A differing pixel is classified "edge" when the canvas
// render's 3x3 neighborhood spans > 48/channel - the AA band of a
// contrast boundary.
//
// Documented relaxed tolerance and gate:
//   - every page renders non-blank,
//   - structural (non-edge) pixels differing > 8/channel stay <= 0.05% of
//     the page (the strict fraction, applied off-edge),
//   - mean absolute channel difference <= 2.0/255 per page (backstop so
//     "edge" cannot hide a systematically displaced or recolored render),
//   - >= 90% of pages pass both.
// The strict 8/0.05% and 16/0.2% whole-page distributions are reported for
// the record. Run with the default backend AND with --enable-impeller.
//
// Impeller runs must set STRIP_PARITY_IMPELLER=1: Impeller rasterizes path
// AA with 4x MSAA, quantizing the CANVAS baseline's edge coverage (its
// simple-diagonal probe still reads within 2, but dense-page edges drift
// to a mean diff of ~6/255) while the strip side is unchanged and
// byte-accurate there too (strip_device_test passes under Impeller and a
// delegate-everything render diffs 0.000%). The Impeller gate therefore
// loosens to mean <= 8/255 and off-edge strict fraction <= 1% - it guards
// the pipeline, not Impeller's AA quality; beating MSAA AA is Track A's
// whole point.
//
// STRIP_PARITY_FILTER=<substring> narrows the file set for debugging.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/strips.dart';

import 'render_smoke_test.dart' show loadSystemFonts;

const _pixelRatio = 2.0;
const _strictChannel = 8;
const _strictFraction = 0.0005;
const _relaxedChannel = 16;
const _relaxedFraction = 0.002;

/// Channel range in the 3x3 neighborhood above which a pixel counts as
/// sitting on a contrast edge (where analytic-vs-supersampled AA differs).
const _edgeContrast = 48;

/// Mean absolute channel difference allowed per page (backstop, 0..255).
/// Slug glyph mode (STRIP_PARITY_SLUG=1) widens the Skia backstop to 3.5:
/// its dual-ray analytic AA disagrees with Skia's exact-area coverage on
/// every glyph edge pixel (symmetric per-edge noise, measured ~zero signed
/// bias), which on text-dense Ghent pages accumulates to means of 2-3/255
/// at 100% edge share and ~zero off-edge fraction - AA-model difference,
/// not displacement.
final double _maxMeanDiff = _impeller ? 8.0 : (_slug ? 3.5 : 2.0);

/// Off-edge (structural) differing-pixel fraction allowed per page.
final double _structuralFraction = _impeller ? 0.01 : _strictFraction;

/// See the header: Impeller's MSAA canvas baseline needs looser thresholds.
final bool _impeller = Platform.environment['STRIP_PARITY_IMPELLER'] == '1';

/// STRIP_PARITY_SLUG=1 renders the strip side with Slug glyph quads (B3)
/// instead of strip-binned outlines.
final bool _slug = Platform.environment['STRIP_PARITY_SLUG'] == '1';

class _PageStat {
  _PageStat(this.name, this.page);
  final String name;
  final int page;
  int pixels = 0;
  int strictDiff = 0; // > 8/channel
  int relaxedDiff = 0; // > 16/channel
  int edgeDiff = 0; // strict-differing pixels on contrast edges
  int diffSum = 0; // sum of max-channel abs differences
  double ink = 0;

  bool get strictPass => strictDiff <= pixels * _strictFraction;
  bool get relaxedPass => relaxedDiff <= pixels * _relaxedFraction;
  double get edgeShare => strictDiff == 0 ? 1 : edgeDiff / strictDiff;
  double get meanDiff => diffSum / pixels;

  /// The documented B1 relaxed-edge gate: off-edge strict fraction plus a
  /// mean-difference backstop.
  bool get structuralPass =>
      (strictDiff - edgeDiff) <= pixels * _structuralFraction &&
      meanDiff <= _maxMeanDiff;
}

void main() {
  final root = Directory('../../test_corpora/ghent');
  if (!root.existsSync()) {
    test('strip parity', skip: 'test_corpora/ghent not found', () {});
    return;
  }
  final filter = Platform.environment['STRIP_PARITY_FILTER'];


  final files = root
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) =>
          f.path.toLowerCase().endsWith('.pdf') &&
          !f.path.contains('/_baselines/') &&
          !f.path.contains('/_failures/') &&
          !f.path.contains('/_renders/') &&
          (filter == null || f.path.contains(filter)))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  testWidgets('strip device parity vs canvas device (Ghent)', (tester) async {
    await tester.runAsync(() async {
      await loadSystemFonts();
      final stats = <_PageStat>[];
      try {
        for (final file in files) {
          final name = file.path.substring(root.path.length + 1);
          final doc = PdfDocument.open(file.readAsBytesSync());
          for (var i = 0; i < doc.pageCount; i++) {
            PdfPageRenderer.deviceMode = PdfRenderDeviceMode.canvas;
            final canvasImage = await PdfPageRenderer.renderImage(doc.page(i),
                    pixelRatio: _pixelRatio)
                .timeout(const Duration(seconds: 90));
            PdfPageRenderer.deviceMode = PdfRenderDeviceMode.strips;
            StripPdfDevice.slugGlyphs = _slug;
            final stripImage = await PdfPageRenderer.renderImage(doc.page(i),
                    pixelRatio: _pixelRatio)
                .timeout(const Duration(seconds: 90));
            try {
              stats.add(await _diff(name, i, canvasImage, stripImage));
            } finally {
              canvasImage.dispose();
              stripImage.dispose();
            }
          }
        }
      } finally {
        PdfPageRenderer.deviceMode = PdfRenderDeviceMode.canvas;
        StripPdfDevice.slugGlyphs = false;
      }

      // ---- distribution report ----
      final pages = stats.length;
      final strictPass = stats.where((s) => s.strictPass).length;
      final relaxedPass = stats.where((s) => s.relaxedPass).length;
      final structuralPass = stats.where((s) => s.structuralPass).length;
      final blank = stats.where((s) => s.ink <= 0.0005).toList();
      // ignore: avoid_print
      print('STRIP-PARITY: $pages pages | strict(8/0.05%) pass '
          '$strictPass (${(100 * strictPass / pages).toStringAsFixed(1)}%) | '
          'whole-page 16/0.2% pass $relaxedPass '
          '(${(100 * relaxedPass / pages).toStringAsFixed(1)}%) | '
          'relaxed-edge gate pass $structuralPass '
          '(${(100 * structuralPass / pages).toStringAsFixed(1)}%) | '
          'blank ${blank.length}');
      final failing = stats.where((s) => !s.strictPass).toList()
        ..sort((a, b) => (b.strictDiff / b.pixels)
            .compareTo(a.strictDiff / a.pixels));
      for (final s in failing.take(15)) {
        // ignore: avoid_print
        print('  strict-fail ${s.name} p${s.page}: '
            '>${_strictChannel}ch ${(100 * s.strictDiff / s.pixels).toStringAsFixed(3)}% '
            '>${_relaxedChannel}ch ${(100 * s.relaxedDiff / s.pixels).toStringAsFixed(3)}% '
            'edge-share ${(100 * s.edgeShare).toStringAsFixed(0)}% '
            'mean ${s.meanDiff.toStringAsFixed(2)} '
            '${s.structuralPass ? "(edge-only, within relaxed gate)" : "(STRUCTURAL)"}');
      }

      // the gate's actual failures, wherever they sort in the strict list
      for (final s in stats.where((s) => !s.structuralPass)) {
        // ignore: avoid_print
        print('  gate-fail ${s.name} p${s.page}: '
            'off-edge ${(100 * (s.strictDiff - s.edgeDiff) / s.pixels).toStringAsFixed(3)}% '
            'mean ${s.meanDiff.toStringAsFixed(2)}');
      }

      for (final s in blank) {
        fail('${s.name} p${s.page}: strip render is (nearly) blank');
      }
      expect(structuralPass / pages, greaterThanOrEqualTo(0.9),
          reason: 'B1 gate: >= 90% of pages within the documented relaxed '
              'edge tolerance (off-edge >$_strictChannel/channel <= '
              '${_strictFraction * 100}% of pixels, mean diff <= '
              '$_maxMeanDiff/255)');
    });
  }, timeout: const Timeout(Duration(minutes: 60)));
}

Future<_PageStat> _diff(
    String name, int page, ui.Image canvas, ui.Image strips) async {
  final stat = _PageStat(name, page);
  expect('${strips.width}x${strips.height}', '${canvas.width}x${canvas.height}',
      reason: '$name p$page: raster size mismatch');
  final a = (await canvas.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!
      .buffer
      .asUint8List();
  final b = (await strips.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!
      .buffer
      .asUint8List();
  final w = canvas.width, h = canvas.height;
  stat.pixels = w * h;

  var ink = 0;
  for (var i = 0; i < b.length; i += 4) {
    if (b[i] < 250 || b[i + 1] < 250 || b[i + 2] < 250) ink++;
  }
  stat.ink = ink / stat.pixels;

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final o = (y * w + x) * 4;
      var d = 0;
      for (var c = 0; c < 4; c++) {
        final dc = (a[o + c] - b[o + c]).abs();
        if (dc > d) d = dc;
      }
      stat.diffSum += d;
      if (d <= _strictChannel) continue;
      stat.strictDiff++;
      if (d > _relaxedChannel) stat.relaxedDiff++;
      if (_isEdge(a, w, h, x, y)) stat.edgeDiff++;
    }
  }
  return stat;
}

/// Whether the canvas render has a contrast edge in the 3x3 patch at (x,y).
bool _isEdge(Uint8List rgba, int w, int h, int x, int y) {
  for (var c = 0; c < 3; c++) {
    var lo = 255, hi = 0;
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        final nx = x + dx, ny = y + dy;
        if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
        final v = rgba[(ny * w + nx) * 4 + c];
        if (v < lo) lo = v;
        if (v > hi) hi = v;
      }
    }
    if (hi - lo > _edgeContrast) return true;
  }
  return false;
}
