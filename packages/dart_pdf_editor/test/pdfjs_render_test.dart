// pdf.js test corpus — rasterization smoke pass.
//
// Every corpus page renders through the real pipeline (interpreter →
// display list → raster), which is what exercises the image decoders
// (JBIG2, JPX, CCITT, JPEG flavors, PNG predictors) that the pure-Dart
// corpus test never touches. By default the pin is that nothing throws and
// nothing hangs; with PDFJS_BASELINE_DIR set, the rendered pages are compared
// against the checked-in PDF.js reference PNGs. Expectations (passwords,
// unopenable fuzz files) mirror packages/pdf_graphics/test/pdfjs_corpus_test.dart.
//
// For visual review, set PDFJS_RENDER_OUT to write PNGs plus an index.html:
//   PDFJS_RENDER_OUT=../../test_corpora/pdfjs/_renders \
//     fvm flutter test test/pdfjs_render_test.dart
// For PDF.js reference comparison, first generate baselines with
// tool/pdfjs_baseline, then set PDFJS_BASELINE_DIR. If PDFJS_RENDER_OUT is
// omitted during comparison, test_corpora/pdfjs/_renders is used.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';

import 'render_gallery.dart';
import 'render_smoke_test.dart' show loadSystemFonts;

const passwords = {
  'issue6010_1.pdf': 'abc',
  'issue6010_2.pdf': 'æøå',
  'issue15893_reduced.pdf': 'test',
  'bug1782186.pdf': 'Hello',
  'issue3371.pdf': 'ELXRTQWS',
  'encrypted-attachment.pdf': '000000',
};

/// Files the pure-Dart corpus test pins as not opening (fuzzed beyond
/// recovery) or demanding a password we don't have.
const skipped = {
  'GHOSTSCRIPT-698804-1-fuzzed.pdf',
  'REDHAT-1531897-0.pdf',
  'poppler-395-0-fuzzed.pdf',
  'poppler-742-0-fuzzed.pdf',
  'poppler-85140-0.pdf',
  'poppler-937-0-fuzzed.pdf',
  'print_protection.pdf',
};

/// Files the Dart renderer intentionally smoke-tests, but PDF.js itself cannot
/// produce a reference PNG for.
const baselineUnavailable = {
  'Pages-tree-refs.pdf',
};

/// Pages rendered per file: enough to hit every codec the file carries
/// without rasterizing all of a long document.
const maxPages = 5;

const _channelTolerance = 8;
const _maxDifferingFraction = 0.0005;

void main() {
  final root = Directory('../../test_corpora/pdfjs');
  if (!root.existsSync()) {
    test('pdf.js suite', skip: 'test_corpora/pdfjs not found', () {});
    return;
  }
  final renderOut = Platform.environment['PDFJS_RENDER_OUT'];
  final baselineEnv = Platform.environment['PDFJS_BASELINE_DIR'];
  final galleryOut = renderOut ??
      (baselineEnv == null ? null : '../../test_corpora/pdfjs/_renders');
  final gallery =
      galleryOut == null ? null : RenderGallery(Directory(galleryOut));
  if (gallery != null) {
    // ignore: avoid_print
    print('PDF.js render results: ${gallery.indexFile.absolute.uri}');
  }
  final visualMaxPages = _envPositiveInt('PDFJS_RENDER_MAX_PAGES', maxPages);
  final visualPixelRatio = _envPositiveDouble('PDFJS_RENDER_PIXEL_RATIO', 1.0);
  final defaultBaselineDir = Directory('../../test_corpora/pdfjs/_baselines');
  final baselineDir = baselineEnv == null
      ? gallery != null && defaultBaselineDir.existsSync()
          ? defaultBaselineDir
          : null
      : Directory(baselineEnv);
  final compareBaselines = baselineEnv != null;
  final channelTolerance =
      _envPositiveInt('PDFJS_COMPARE_CHANNEL_TOLERANCE', _channelTolerance);
  final maxDifferingFraction = _envPositiveDouble(
      'PDFJS_COMPARE_MAX_DIFF_FRACTION', _maxDifferingFraction);

  // PDFJS_ONLY filters to a comma-separated list of filename substrings, so a
  // single file can be re-rendered while iterating on a fix.
  final only = (Platform.environment['PDFJS_ONLY'] ?? '')
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  final files = root
      .listSync()
      .whereType<File>()
      .where((f) => f.path.toLowerCase().endsWith('.pdf'))
      .where((f) => !skipped.contains(f.uri.pathSegments.last))
      .where((f) => only.isEmpty ||
          only.any((s) => f.uri.pathSegments.last.contains(s)))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in files) {
    final name = file.uri.pathSegments.last;
    testWidgets(name, (tester) async {
      await tester.runAsync(() async {
        await loadSystemFonts();
        final doc = PdfDocument.open(file.readAsBytesSync(),
            password: passwords[name] ?? '');
        final pages = doc.pageCount;
        final pageLimit = gallery == null ? maxPages : visualMaxPages;
        final failures = <String>[];
        for (var i = 0; i < pages && i < pageLimit; i++) {
          final image = await PdfPageRenderer.renderImage(doc.page(i),
                  pixelRatio: visualPixelRatio)
              .timeout(const Duration(seconds: 90));
          _Comparison? comparison;
          final baseline = baselineDir == null
              ? null
              : File('${baselineDir.path}/${_safeName(name)}.p$i.png');
          try {
            expect(image.width, greaterThan(0));
            expect(image.height, greaterThan(0));

            if (baseline != null) {
              if (!baseline.existsSync()) {
                if (compareBaselines && !baselineUnavailable.contains(name)) {
                  failures.add('page $i: missing PDF.js baseline '
                      '${baseline.path}');
                }
              } else {
                comparison = await _compareBaseline(
                  actual: image,
                  baseline: baseline,
                  channelTolerance: channelTolerance,
                );
              }
            }

            if (gallery != null) {
              await gallery.add(
                pdfName: name,
                page: i,
                image: image,
                baseline: baseline?.existsSync() == true ? baseline : null,
                diff: comparison?.diff,
                differenceFraction: comparison?.differenceFraction,
              );
            }

            if (compareBaselines && comparison != null) {
              if (comparison.sizeMismatch != null) {
                failures.add('page $i: ${comparison.sizeMismatch}');
              } else if (comparison.differenceFraction > maxDifferingFraction) {
                failures.add(
                    'page $i: ${(comparison.differenceFraction * 100).toStringAsFixed(3)}% '
                    'differing pixels');
              }
            }
          } finally {
            comparison?.diff?.dispose();
            image.dispose();
          }
        }
        if (failures.isNotEmpty) {
          fail('$name differs from the PDF.js baseline:\n'
              '${failures.join('\n')}');
        }
      });
    }, timeout: const Timeout(Duration(minutes: 3)));
  }
}

int _envPositiveInt(String name, int fallback) {
  final value = int.tryParse(Platform.environment[name] ?? '');
  return value == null || value < 1 ? fallback : value;
}

double _envPositiveDouble(String name, double fallback) {
  final value = double.tryParse(Platform.environment[name] ?? '');
  return value == null || value <= 0 ? fallback : value;
}

String _safeName(String name) =>
    name.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');

Future<_Comparison> _compareBaseline({
  required ui.Image actual,
  required File baseline,
  required int channelTolerance,
}) async {
  final codec = await ui.instantiateImageCodec(baseline.readAsBytesSync());
  final expected = (await codec.getNextFrame()).image;
  try {
    if (actual.width != expected.width || actual.height != expected.height) {
      return _Comparison(
        differenceFraction: 1,
        sizeMismatch:
            'raster size changed: Dart ${actual.width}x${actual.height}, '
            'PDF.js ${expected.width}x${expected.height}',
      );
    }

    final actualPixels =
        (await actual.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!
            .buffer
            .asUint8List();
    final expectedPixels =
        (await expected.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!
            .buffer
            .asUint8List();
    // Shared with the Ghent suite and the comparison feature: the changes
    // alone, red on a white field.
    final diff = PdfPageComparison.comparePixels(
      actualPixels,
      expectedPixels,
      width: actual.width,
      height: actual.height,
      channelTolerance: channelTolerance,
      style: PdfDiffStyle.redOnWhite,
    );
    return _Comparison(
      differenceFraction: diff.differenceFraction,
      diff: await diff.toImage(),
    );
  } finally {
    expected.dispose();
  }
}

class _Comparison {
  const _Comparison({
    required this.differenceFraction,
    this.diff,
    this.sizeMismatch,
  });

  final double differenceFraction;
  final ui.Image? diff;
  final String? sizeMismatch;
}
