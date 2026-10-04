// Opt-in accuracy benchmark for the browser (Florence-2) OCR path, in two
// halves around a real browser run:
//
//   1. export: render the page exactly as the web job does and cut it with
//      the app's own ocrTiles, writing each tile as a PNG plus a manifest;
//   2. tool/ocr_florence_run.mjs: run those tiles through the
//      __dartPdfOcrRecognize bridge lifted verbatim from web/index.html in
//      headless Chromium, writing the raw Florence outputs;
//   3. score: feed them through the app's own parseFlorenceSpans +
//      mergeOcrSpans + userSpaceRect and score against the truth.
//
// Skipped unless PDF_OCR_FLORENCE_DIR is set. See
// doc/dev-log/2026-10-04-ocr-accuracy-benchmark.md for the full recipe.
//
// Knobs: PDF_OCR_PIXEL_RATIO (default 2) and PDF_OCR_TILE (default
// ocrTiles' own); PDF_OCR_REAL_PDF + PDF_OCR_REAL_TRUTH score a real page
// instead of the synthetic sheet.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor_app/ocr_tiling.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main() {
  final env = Platform.environment;
  final dir = env['PDF_OCR_FLORENCE_DIR'];
  final skip = dir == null ? 'set PDF_OCR_FLORENCE_DIR to run' : null;
  final pixelRatio = double.tryParse(env['PDF_OCR_PIXEL_RATIO'] ?? '') ?? 2;
  final tileSize = int.tryParse(env['PDF_OCR_TILE'] ?? '');

  (PdfDocument, List<OcrTruthLabel>) source() {
    final real = env['PDF_OCR_REAL_PDF'];
    if (real != null) {
      return (
        PdfDocument.open(File(real).readAsBytesSync()),
        [
          for (final e
              in jsonDecode(File(env['PDF_OCR_REAL_TRUTH']!).readAsStringSync())
                  as List)
            OcrTruthLabel.fromJson(e as Map<String, Object?>),
        ],
      );
    }
    final sheet = buildOcrDrawingSheet(
        File('../packages/pdf_document/test/fonts/LiberationSans-Regular.ttf')
            .readAsBytesSync());
    return (PdfDocument.open(sheet.bytes), sheet.labels);
  }

  Future<PdfOcrPageImage> raster(PdfDocument doc) =>
      const PdfRendererOcrRasterizer()
          .rasterize(doc.page(0), pageIndex: 0, pixelRatio: pixelRatio);

  List<Rect> tilesOf(PdfOcrPageImage page) => tileSize == null
      ? ocrTiles(page.width, page.height)
      : ocrTiles(page.width, page.height, tileSize: tileSize);

  test('export tiles', () async {
    final (doc, _) = source();
    final page = await raster(doc);
    final out = Directory(dir!)..createSync(recursive: true);
    final tiles = tilesOf(page);
    final manifest = <Map<String, Object>>[];
    for (var i = 0; i < tiles.length; i++) {
      // Crop on the raster thread the way the web engine's _encodeTilePng does.
      final src = tiles[i];
      final w = src.width.round(), h = src.height.round();
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawImageRect(page.image, src,
          Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), ui.Paint());
      final picture = recorder.endRecording();
      final tile = await picture.toImage(w, h);
      picture.dispose();
      final png = await tile.toByteData(format: ui.ImageByteFormat.png);
      tile.dispose();
      final name = 'tile_$i.png';
      File('${out.path}/$name').writeAsBytesSync(png!.buffer.asUint8List());
      manifest.add({'file': name, 'left': src.left, 'top': src.top});
    }
    File('${out.path}/manifest.json').writeAsStringSync(jsonEncode(manifest));
    page.dispose();
    // ignore: avoid_print
    print('exported ${tiles.length} tiles of ${page.width}x${page.height}');
  }, skip: skip ?? (env['PDF_OCR_PHASE'] == 'score' ? 'scoring' : null));

  test('score Florence results', () async {
    final (doc, truth) = source();
    final page = await raster(doc);
    final results = jsonDecode(File('$dir/results.json').readAsStringSync())
        as List<Object?>;
    final raw = <OcrRawSpan>[];
    for (final r in results.cast<Map<String, Object?>>()) {
      final tile = (r['tile']! as Map).cast<String, Object?>();
      final spans = parseFlorenceSpans(
        r['result'],
        fallbackWidth: (r['width']! as num).round(),
        fallbackHeight: (r['height']! as num).round(),
      );
      for (final s in spans) {
        raw.add(s.shifted((tile['left']! as num).toDouble(),
            (tile['top']! as num).toDouble()));
      }
    }
    final spans = [
      for (final s in mergeOcrSpans(raw))
        if (page.userSpaceRect(s.box) case final b)
          (
            text: s.text,
            left: b.left,
            bottom: b.bottom,
            right: b.right,
            top: b.top,
          ),
    ];
    page.dispose();
    final score = scoreOcrAccuracy(truth, spans);
    // ignore: avoid_print
    print('florence @${pixelRatio}x tile ${tileSize ?? 'default'}: $score '
        '(${spans.length} spans)\n  misreads: ${score.misreads.take(25).map((m) => '${m.$1}->"${m.$2}"').join('  ')}');
  }, skip: skip ?? (env['PDF_OCR_PHASE'] == 'score' ? null : 'exporting'));
}
