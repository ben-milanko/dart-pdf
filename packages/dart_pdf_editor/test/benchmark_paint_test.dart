// Hotspot probe for the PAINT pass (interpreter pass #2 into CanvasPdfDevice).
//
// The paint pass cost splits in two: the pdf_graphics interpreter WALK (parsing
// operands, building PdfPath/PdfMatrix, resolving colour, looking up glyph
// outlines) and the dart_pdf_editor device CALLBACKS (building Flutter Canvas
// ops). This probe wraps CanvasPdfDevice with a timing device that buckets each
// leaf callback by wall time + call count; the interpreter-walk overhead is the
// paint-pass total minus the summed callback time.
//
//   cd packages/dart_pdf_editor
//   PDF_BENCHMARK_DIR=../../corpus PDF_BENCHMARK_SCALE=2 PDF_BENCHMARK_MAX_PAGES=5 \
//     fvm flutter test test/benchmark_paint_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/image_decoder.dart';

import 'render_smoke_test.dart' show loadSystemFonts;

/// Wraps a real [PdfDevice], timing each leaf paint callback into a bucket.
///
/// Leaf ops (fill/stroke/clip/text/image/gradient/mesh/save/restore/blend) do
/// not re-enter the interpreter, so timing them is non-overlapping. The
/// bracketing ops (group/softmask) are counted but their inner content's time
/// lands in the leaf buckets; [softMaskUs] is the self time of endSoftMasked
/// minus the drawMask re-walk so nothing is double-counted.
class _TimingDevice implements PdfDevice {
  _TimingDevice(this.inner);
  final PdfDevice inner;

  final counts = <String, int>{};
  final micros = <String, int>{};
  final _sw = Stopwatch();

  // drawMask re-walks the mask content through this device; its leaf time is
  // already bucketed, so subtract it from the enclosing endSoftMasked self time.
  int _maskNestUs = 0;

  T _timed<T>(String bucket, T Function() body) {
    final start = _sw.elapsedMicroseconds;
    _sw.start();
    try {
      return body();
    } finally {
      final dt = _sw.elapsedMicroseconds - start;
      _sw.stop();
      counts[bucket] = (counts[bucket] ?? 0) + 1;
      micros[bucket] = (micros[bucket] ?? 0) + dt;
    }
  }

  @override
  void save() => _timed('save/restore', inner.save);
  @override
  void restore() => _timed('save/restore', inner.restore);
  @override
  void setBlendMode(PdfBlendMode m) => _timed('blend', () => inner.setBlendMode(m));
  @override
  void fillPath(PdfPath p, PdfColor c, PdfFillRule r, double a) =>
      _timed('fillPath', () => inner.fillPath(p, c, r, a));
  @override
  void fillPathGradient(PdfPath p, PdfFillRule r, PdfGradient g, double a) =>
      _timed('fillGradient', () => inner.fillPathGradient(p, r, g, a));
  @override
  void fillMesh(PdfMesh m, double a) => _timed('fillMesh', () => inner.fillMesh(m, a));
  @override
  void strokePath(PdfPath p, PdfColor c, PdfStroke s, double a) =>
      _timed('strokePath', () => inner.strokePath(p, c, s, a));
  @override
  void clipPath(PdfPath p, PdfFillRule r) =>
      _timed('clipPath', () => inner.clipPath(p, r));
  @override
  void drawText(PdfTextRun run) {
    final bucket = run.invisible
        ? 'text-invisible'
        : run.glyphs != null
            ? 'text-glyph'
            : 'text-substituted';
    _timed(bucket, () => inner.drawText(run));
  }
  @override
  void drawImage(PdfImageRequest req) =>
      _timed('drawImage', () => inner.drawImage(req));
  @override
  void beginGroup(double a, {bool knockout = false}) =>
      _timed('group', () => inner.beginGroup(a, knockout: knockout));
  @override
  void endGroup() => _timed('group', inner.endGroup);
  @override
  void beginSoftMasked() => _timed('softmask', inner.beginSoftMasked);
  @override
  void endSoftMasked({
    required bool luminosity,
    required PdfRect backdrop,
    required void Function() drawMask,
    double backdropLuminance = 0,
    double transferScale = 1,
    double transferOffset = 0,
  }) {
    final savedNest = _maskNestUs;
    _maskNestUs = 0;
    final start = _sw.elapsedMicroseconds;
    _sw.start();
    var inclusive = 0;
    try {
      inner.endSoftMasked(
        luminosity: luminosity,
        backdrop: backdrop,
        backdropLuminance: backdropLuminance,
        transferScale: transferScale,
        transferOffset: transferOffset,
        drawMask: () {
          // Pause the softmask timer across the re-walk: its leaf ops time
          // themselves, and the interpreter overhead between them belongs to
          // the walk, not to softmask compositing.
          final markStart = _sw.elapsedMicroseconds;
          _sw.stop();
          drawMask();
          _sw.start();
          _maskNestUs += _sw.elapsedMicroseconds - markStart;
        },
      );
    } finally {
      inclusive = _sw.elapsedMicroseconds - start;
      _sw.stop();
      counts['softmask'] = (counts['softmask'] ?? 0) + 1;
      micros['softmask'] = (micros['softmask'] ?? 0) + (inclusive - _maskNestUs);
      _maskNestUs = savedNest;
    }
  }

  int get totalUs => micros.values.fold(0, (s, v) => s + v);
}

void main() {
  final dir = Platform.environment['PDF_BENCHMARK_DIR'];
  final scale =
      double.tryParse(Platform.environment['PDF_BENCHMARK_SCALE'] ?? '') ?? 2.0;
  final maxPages =
      int.tryParse(Platform.environment['PDF_BENCHMARK_MAX_PAGES'] ?? '') ?? 5;

  testWidgets('paint pass hotspots', (tester) async {
    if (dir == null) {
      markTestSkipped('set PDF_BENCHMARK_DIR');
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

      var pages = 0;
      var paintUs = 0; // full paint-pass wall time (walk + callbacks)
      final counts = <String, int>{};
      final micros = <String, int>{};
      var warmed = false;

      for (final file in files) {
        PdfDocument doc;
        try {
          doc = PdfDocument.open(file.readAsBytesSync());
        } catch (_) {
          continue;
        }
        final limit = maxPages <= 0
            ? doc.pageCount
            : (doc.pageCount < maxPages ? doc.pageCount : maxPages);
        for (var i = 0; i < limit; i++) {
          try {
            final page = doc.page(i);
            final cos = page.document.cos;
            final size = PdfPageRenderer.pageSize(page);
            final box = page.cropBox;
            final pageOps = ContentStreamParser.parse(page.contentBytes());
            final collector = ImageCollector();
            PdfInterpreter(cos: cos, device: collector, scanImagesOnly: true)
              ..drawPageOperations(page, pageOps)
              ..drawAnnotations(page);
            final images = await decodeImages(cos, collector.streams,
                cache: PdfImageCache.instance);

            if (!warmed) {
              // Prime fonts/codepaths so the first dense page doesn't skew the
              // walk-overhead figure.
              final r0 = ui.PictureRecorder();
              final c0 = Canvas(r0);
              PdfInterpreter(
                  cos: cos, device: CanvasPdfDevice(c0, images: images))
                ..drawPageOperations(page, pageOps)
                ..drawAnnotations(page);
              r0.endRecording().dispose();
              warmed = true;
            }

            final recorder = ui.PictureRecorder();
            final canvas = Canvas(recorder);
            canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
            canvas.translate(0, box.height);
            canvas.scale(1, -1);
            canvas.translate(-box.left, -box.bottom);
            final device =
                _TimingDevice(CanvasPdfDevice(canvas, images: images));

            final sw = Stopwatch()..start();
            PdfInterpreter(cos: cos, device: device)
              ..drawPageOperations(page, pageOps)
              ..drawAnnotations(page);
            paintUs += sw.elapsedMicroseconds;
            recorder.endRecording().dispose();

            device.counts.forEach((k, v) => counts[k] = (counts[k] ?? 0) + v);
            device.micros.forEach((k, v) => micros[k] = (micros[k] ?? 0) + v);
            for (final im in images.values) {
              im.dispose();
            }
            pages++;
          } catch (_) {}
        }
      }

      final callbackUs = micros.values.fold(0, (s, v) => s + v);
      final walkUs = paintUs - callbackUs;
      String per(int us) => (us / 1000 / pages).toStringAsFixed(2);
      String pct(int us) => (us / paintUs * 100).toStringAsFixed(0);
      double perCall(String k) =>
          (counts[k] ?? 0) == 0 ? 0 : micros[k]! / counts[k]!;

      // ignore: avoid_print
      print('\n=== paint pass hotspots ($pages pages, scale $scale) ===');
      // ignore: avoid_print
      print('  paint-pass total:          ${per(paintUs)} ms/page');
      // ignore: avoid_print
      print('  interpreter walk overhead: ${per(walkUs)} ms/page  (${pct(walkUs)}%)');
      // ignore: avoid_print
      print('  device callbacks total:    ${per(callbackUs)} ms/page  (${pct(callbackUs)}%)');
      // ignore: avoid_print
      print('  --- device callbacks by category (ms/page, % of paint, calls/page, us/call) ---');
      final keys = micros.keys.toList()
        ..sort((a, b) => micros[b]!.compareTo(micros[a]!));
      for (final k in keys) {
        final callsPerPage = (counts[k]! / pages).toStringAsFixed(1);
        // ignore: avoid_print
        print('  ${k.padRight(14)} ${per(micros[k]!).padLeft(6)} '
            '${pct(micros[k]!).padLeft(4)}%  ${callsPerPage.padLeft(8)} calls  '
            '${perCall(k).toStringAsFixed(1).padLeft(7)} us/call');
      }
    });
  }, timeout: const Timeout(Duration(minutes: 60)));
}
