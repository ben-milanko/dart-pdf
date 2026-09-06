// The paint-pass text caches must (a) memoize substituted-font layouts so
// repeated (text, font, colour) runs reuse one laid-out painter, and (b) never
// change a pixel - a warm (cache-hot) render is byte-identical to a cold one,
// for both substituted text and embedded-font glyph outlines.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';

Future<Uint8List> _raster(PdfPage page) async {
  final image = await PdfPageRenderer.renderImage(page, pixelRatio: 2);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return Uint8List.fromList(data!.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}

Future<Uint8List> _rasterOutlineBatch({
  required bool batched,
  bool overlapping = false,
}) async {
  final previous = CanvasPdfDevice.batchEmbeddedTextOutlines;
  CanvasPdfDevice.batchEmbeddedTextOutlines = batched;
  try {
    const outline = PdfPath([
      PdfMoveTo(0, 0),
      PdfLineTo(0.8, 0),
      PdfLineTo(0.6, 1),
      PdfLineTo(0.2, 1),
      PdfClosePath(),
    ]);
    PdfDrawTextCommand run(double x, PdfColor color) => PdfDrawTextCommand(
          PdfTextRun(
            text: 'A',
            transform: PdfMatrix(36, 0, 0, 36, x, 45),
            color: color,
            width: 0.8,
            glyphs: const [
              PdfGlyphPlacement(offset: 0, outline: outline),
            ],
          ),
        );
    final commands = <PdfRenderCommand>[
      run(8, PdfColor.black),
      run(overlapping ? 8 : 48, PdfColor.black),
      run(88, const PdfColor(0.8, 0.1, 0.1)),
      run(128, PdfColor.black),
    ];
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)
      ..drawColor(const Color(0xFFFFFFFF), BlendMode.src);
    replayCommands(commands, CanvasPdfDevice(canvas));
    final picture = recorder.endRecording();
    final image = await picture.toImage(172, 64);
    picture.dispose();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return Uint8List.fromList(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  } finally {
    CanvasPdfDevice.batchEmbeddedTextOutlines = previous;
  }
}

const _copiedArabicLine =
    '\u2067اﻟﺣﻣد لله رب اﻟﻌﺎﻟﻣﯾن) 2 (اﻟرﺣﻣن اﻟرﺣﯾم) 3 (ﻣﺎﻟك ﯾوم\u2069';

bool _dejavuLoaded = false;

Future<void> _loadBundledDejavu() async {
  if (_dejavuLoaded) return;
  _dejavuLoaded = true;
  // DejaVu now ships in dart_pdf_editor_assets, which this package's test asset
  // bundle can't reach; read the moved file and register it under the family
  // name the default fallback list expects.
  final bytes = File('../dart_pdf_editor_assets/assets/fonts/DejaVuSans.ttf')
      .readAsBytesSync();
  final loader = FontLoader('packages/dart_pdf_editor_assets/DejaVu Sans')
    ..addFont(Future.value(ByteData.sublistView(bytes)));
  await loader.load();
}

Future<Uint8List> _rasterSubstitutedArabic({
  required bool throughDevice,
  List<String>? fallbacks,
  String fontFamily = 'Helvetica',
}) async {
  const renderSize = 100.0;
  const runWidth = _copiedArabicLine.length * 0.5;
  const transform = PdfMatrix(20, 0, 0, 20, 20, 80);
  final style = TextStyle(
    color: const Color(0xFFFF0000),
    fontSize: renderSize,
    fontFamily: fontFamily,
    fontFamilyFallback: fallbacks ?? CanvasPdfDevice.debugDefaultFontFallbacks,
    letterSpacing: 0,
    height: 1,
  );
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)
    ..drawColor(const Color(0xFFFFFFFF), BlendMode.src);

  if (throughDevice) {
    CanvasPdfDevice(canvas).drawText(const PdfTextRun(
      text: _copiedArabicLine,
      transform: transform,
      color: PdfColor(1, 0, 0),
      width: runWidth,
      fontName: 'Helvetica',
      fontSize: 20,
    ));
  } else {
    final painter = TextPainter(
      text: TextSpan(text: _copiedArabicLine, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final baseline =
        painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    final scaleX = runWidth * renderSize / painter.width;
    canvas
      ..save()
      ..transform(Float64List.fromList(const [
        20, 0, 0, 0, //
        0, 20, 0, 0, //
        0, 0, 1, 0, //
        20, 80, 0, 1,
      ]))
      ..scale(scaleX / renderSize, -1 / renderSize);
    painter.paint(canvas, Offset(0, -baseline));
    canvas.restore();
  }

  final image = await recorder.endRecording().toImage(1400, 160);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return Uint8List.fromList(data!.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}

void main() {
  testWidgets('substituted-text layouts cache and repeated runs reuse them',
      (tester) async {
    await tester.runAsync(() async {
      CanvasPdfDevice.clearTextLayoutCache();
      final page = PdfDocument.open(buildClassicPdf()).page(0);

      // A Latin run is now painted per character at the PDF's own offsets
      // (#649), so its shaping is memoized in the glyph cache rather than the
      // run cache - an alphabet's worth of entries, shared by every run that
      // uses those characters.
      await _raster(page);
      final afterFirst = CanvasPdfDevice.debugGlyphLayoutCacheLength;
      expect(afterFirst, greaterThan(0),
          reason: 'standard-font runs should be cached');

      // Re-rendering the same page hits the cache for every character - no new
      // entries appear.
      await _raster(page);
      expect(CanvasPdfDevice.debugGlyphLayoutCacheLength, afterFirst,
          reason: 'a re-render is all cache hits, no new layouts');
    });
  });

  testWidgets('a run that keeps whole-run shaping caches as a run',
      (tester) async {
    await tester.runAsync(() async {
      // Arabic needs joining and reordering, so it is not placeable per
      // character (#649) and stays on whole-run shaping - and on the run cache.
      CanvasPdfDevice.clearTextLayoutCache();
      await _rasterSubstitutedArabic(throughDevice: true);
      expect(CanvasPdfDevice.debugTextLayoutCacheLength, greaterThan(0));
    });
  });

  testWidgets('clearTextLayoutCache empties both caches', (tester) async {
    await tester.runAsync(() async {
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      await _raster(page);
      await _rasterSubstitutedArabic(throughDevice: true);
      expect(CanvasPdfDevice.debugTextLayoutCacheLength, greaterThan(0));
      expect(CanvasPdfDevice.debugGlyphLayoutCacheLength, greaterThan(0));
      CanvasPdfDevice.clearTextLayoutCache();
      expect(CanvasPdfDevice.debugTextLayoutCacheLength, 0);
      expect(CanvasPdfDevice.debugGlyphLayoutCacheLength, 0);
    });
  });

  testWidgets('a warm render is byte-identical (substituted text)',
      (tester) async {
    await tester.runAsync(() async {
      CanvasPdfDevice.clearTextLayoutCache();
      final page = PdfDocument.open(buildClassicPdf()).page(0);
      final cold = await _raster(page); // populates the layout cache
      final warm = await _raster(page); // serves it from cache
      expect(warm, equals(cold));
    });
  });

  testWidgets('a warm render is byte-identical (embedded glyph outlines)',
      (tester) async {
    await tester.runAsync(() async {
      // Real TrueType outlines exercise the glyph-path cache (keyed by outline
      // identity); the second render reuses the cached em-space ui.Paths.
      final page = PdfDocument.open(buildEmbeddedFontPdf()).page(0);
      final cold = await _raster(page);
      final warm = await _raster(page);
      expect(warm, equals(cold));
    });
  });

  testWidgets('batched embedded outlines are raster-equivalent',
      (tester) async {
    await tester.runAsync(() async {
      final individual = await _rasterOutlineBatch(batched: false);
      final batched = await _rasterOutlineBatch(batched: true);
      var maxDifference = 0;
      var outOfToleranceChannels = 0;
      for (var i = 0; i < individual.length; i++) {
        final difference = (individual[i] - batched[i]).abs();
        if (difference > maxDifference) maxDifference = difference;
        if (difference > 8) outOfToleranceChannels++;
      }
      // Skia may quantize an edge a few channel values differently when the
      // same contours arrive in one path instead of several draw calls. This
      // stays within the renderer corpus' channel tolerance (8) and is limited
      // to a minute fraction of antialiased edge pixels.
      expect(maxDifference, lessThanOrEqualTo(8));
      expect(outOfToleranceChannels, 0);
    });
  });

  testWidgets('overlapping embedded outlines keep separate paint coverage',
      (tester) async {
    await tester.runAsync(() async {
      final individual =
          await _rasterOutlineBatch(batched: false, overlapping: true);
      final batched =
          await _rasterOutlineBatch(batched: true, overlapping: true);
      expect(batched, individual,
          reason: 'overlapping runs must flush instead of changing winding or '
              'alpha coverage inside one combined path');
    });
  });

  testWidgets(
      'substituted text renders copied Arabic presentation forms through the bundled fallback',
      (tester) async {
    await tester.runAsync(() async {
      await _loadBundledDejavu();
      CanvasPdfDevice.clearTextLayoutCache();

      expect(
        CanvasPdfDevice.debugDefaultFontFallbacks,
        contains('packages/dart_pdf_editor_assets/DejaVu Sans'),
      );
      final expected = await _rasterSubstitutedArabic(throughDevice: false);
      final missing = await _rasterSubstitutedArabic(
        throughDevice: false,
        fallbacks: const ['Ahem'],
        fontFamily: 'Ahem',
      );
      final actual = await _rasterSubstitutedArabic(throughDevice: true);

      expect(expected, isNot(equals(missing)),
          reason: 'the bundled font must replace missing-glyph boxes');
      expect(actual, equals(expected));
    });
  });
}
