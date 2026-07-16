// Characterises the decoded-image cache budget (PdfImageCache.maxBytes) on a
// real document: for each candidate budget, renders every page in reading
// order (the scroll a reader actually performs) and reports the cache's hit
// rate, the re-decode work the budget costs, and the process RSS it buys.
//
// The point is to put a number on the trade the budget makes - a bigger cache
// only pays for itself when the document's working set fits it, and RSS is the
// price. Not a CI test: skipped unless PDF_BENCHMARK_PDF is set.
//
//   cd packages/dart_pdf_editor
//   PDF_BENCHMARK_PDF=/path/to/doc.pdf fvm flutter test \
//     test/benchmark_image_cache_budget_test.dart
//
//   PDF_BENCHMARK_BUDGETS=32,64,128,256,512   # MB, in sweep order
//   PDF_BENCHMARK_SCALE=1                     # raster pixel ratio
//   PDF_BENCHMARK_PASSES=1                    # sweeps of the document
import 'dart:io';
import 'dart:math' as math;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';

import 'render_smoke_test.dart' show loadSystemFonts;

void main() {
  _footprintTest();

  final path = Platform.environment['PDF_BENCHMARK_PDF'];
  final scale =
      double.tryParse(Platform.environment['PDF_BENCHMARK_SCALE'] ?? '') ?? 1.0;
  final passes =
      int.tryParse(Platform.environment['PDF_BENCHMARK_PASSES'] ?? '') ?? 1;
  final budgetsMb = (Platform.environment['PDF_BENCHMARK_BUDGETS'] ??
          '16,32,64,128,256,512')
      .split(',')
      .map((s) => int.parse(s.trim()))
      .toList();

  testWidgets('image cache budget sweep', (tester) async {
    if (path == null) {
      markTestSkipped('set PDF_BENCHMARK_PDF');
      return;
    }
    await tester.runAsync(() async {
      await loadSystemFonts();
      final bytes = File(path).readAsBytesSync();
      final doc = PdfDocument.open(bytes);
      final cache = PdfImageCache.instance;

      // The unique decoded footprint of the document: every image, decoded
      // once, with eviction effectively off. Also warms every lazy structure
      // (fonts, xref, glyph atlases) so the measured sweeps below differ only
      // in their cache budget.
      cache
        ..clear()
        ..maxBytes = 1 << 62;
      var uniqueImages = 0, uniqueBytes = 0;
      for (var i = 0; i < doc.pageCount; i++) {
        await _renderPage(doc.page(i), scale);
        uniqueImages = cache.debugLength;
        uniqueBytes = cache.bytes;
      }
      final baselineRss = ProcessInfo.currentRss;

      _line('');
      _line('=== image cache budget sweep ===');
      _line('  document:   ${path.split('/').last}');
      _line('  pages:      ${doc.pageCount}  (${_mb(bytes.length)} on disk, '
          'rendered at ${scale}x, $passes pass(es))');
      _line('  unique decoded images: $uniqueImages  '
          '(${_mb(uniqueBytes)} of RGBA)');
      _line('  RSS after an unbounded sweep: ${_mb(baselineRss)} '
          '(peak ${_mb(ProcessInfo.maxRss)})');
      _line('');
      _line('  budget    hit rate    decodes    render    RSS after    '
          'peak cache');
      _line('  ${'-' * 62}');

      for (final mb in budgetsMb) {
        cache
          ..clear()
          ..maxBytes = mb * 1024 * 1024
          ..debugResetCounters();
        var peakCache = 0;
        final sw = Stopwatch()..start();
        for (var pass = 0; pass < passes; pass++) {
          for (var i = 0; i < doc.pageCount; i++) {
            await _renderPage(doc.page(i), scale);
            if (cache.bytes > peakCache) peakCache = cache.bytes;
          }
        }
        final elapsed = sw.elapsedMilliseconds;
        final lookups = cache.debugHits + cache.debugMisses;
        final hitRate = lookups == 0 ? 0.0 : cache.debugHits / lookups * 100;
        _line('  ${_pad('${mb}M', 8)}'
            '${_pad('${hitRate.toStringAsFixed(1)}%', 12)}'
            '${_pad('${cache.debugMisses}', 11)}'
            '${_pad('${(elapsed / (doc.pageCount * passes)).toStringAsFixed(1)}'
                ' ms/pg', 10)}'
            '${_pad(_mb(ProcessInfo.currentRss), 13)}'
            '${_mb(peakCache)}');
      }
      cache.clear();
      _line('');
    });
  }, timeout: const Timeout(Duration(minutes: 90)));
}

/// What the budget has to hold: the decoded footprint of every document in a
/// corpus. A budget only earns its RSS on documents whose whole working set
/// fits under it (see the sweep above - a budget that lands short of the
/// footprint pays for evictions and buys little), so the distribution of real
/// documents' footprints is what picks the number.
///
///   PDF_FOOTPRINT_DIR=../../corpus fvm flutter test \
///     test/benchmark_image_cache_budget_test.dart
void _footprintTest() {
  final dir = Platform.environment['PDF_FOOTPRINT_DIR'];
  final maxPages =
      int.tryParse(Platform.environment['PDF_FOOTPRINT_MAX_PAGES'] ?? '') ?? 40;

  testWidgets('decoded image footprint across a corpus', (tester) async {
    if (dir == null) {
      markTestSkipped('set PDF_FOOTPRINT_DIR');
      return;
    }
    await tester.runAsync(() async {
      await loadSystemFonts();
      final files = Directory(dir)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.pdf'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

      final cache = PdfImageCache.instance;
      final footprints = <String, int>{};
      for (final file in files) {
        PdfDocument doc;
        try {
          doc = PdfDocument.open(file.readAsBytesSync());
        } catch (_) {
          continue;
        }
        cache
          ..clear()
          ..maxBytes = 1 << 62;
        final limit =
            maxPages <= 0 ? doc.pageCount : math.min(doc.pageCount, maxPages);
        for (var i = 0; i < limit; i++) {
          try {
            // renderPicture runs the decodes; rasterizing adds nothing to the
            // footprint and would dominate the run.
            (await PdfPageRenderer.renderPicture(doc.page(i))).dispose();
          } catch (_) {}
        }
        footprints[file.uri.pathSegments.last] = cache.bytes;
      }
      cache
        ..clear()
        ..maxBytes = pdfDefaultImageCacheBytes();

      final sorted = footprints.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      _line('');
      _line('=== decoded image footprint (${sorted.length} documents, '
          'first $maxPages pages each) ===');
      for (final e in sorted.take(12)) {
        _line('  ${_pad(_mb(e.value), 10)}${e.key}');
      }
      _line('  ...');
      _line('');
      _line('  documents fitting a budget of:');
      for (final mb in const [16, 32, 64, 128, 256, 512]) {
        final fit =
            sorted.where((e) => e.value <= mb * 1024 * 1024).length;
        _line('    ${_pad('${mb}M', 8)}$fit/${sorted.length}  '
            '(${(fit / sorted.length * 100).toStringAsFixed(0)}%)');
      }
      _line('');
    });
  }, timeout: const Timeout(Duration(minutes: 90)));
}

Future<void> _renderPage(PdfPage page, double scale) async {
  final picture = await PdfPageRenderer.renderPicture(page);
  final image = await PdfPageRenderer.rasterize(
      picture, PdfPageRenderer.pageSize(page), scale);
  image.dispose();
  picture.dispose();
}

String _mb(int bytes) => '${(bytes / 1024 / 1024).toStringAsFixed(0)} MB';
String _pad(String s, int width) => s.padRight(width);
// ignore: avoid_print
void _line(String s) => print(s);
