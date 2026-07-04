// Diagnostic testing loop for the heavy-raster CAD jank work.
//
// It drives the EXACT code path a PdfRenderWorker runs off-thread
// (interpret -> serializeCommands(decodeImages:true, maxImagePixelRatio:r))
// on the test isolate, so the image-resolution cap and progressive
// vector-first pass can be measured against a real file without a browser.
//
// Skips unless a file is present. Defaults to the local CAD corpus copy:
//
//   cd packages/dart_pdf_editor
//   CAD_PDF=../../corpus/ly9-far-cad.pdf \
//     fvm flutter test test/cad_perf_probe_test.dart
//
// Knobs:
//   CAD_PDF     path to the PDF (default ../../corpus/ly9-far-cad.pdf)
//   CAD_PAGE    0-based page to deep-probe (default: heaviest found by scan)
//   CAD_RATIO   screen px per point for the cap (default 2.0; ~typical view)
//   CAD_SCAN    '0' to skip the per-page heavy-page scan (default on)
//   CAD_REGION  optional PDF-space decode region: left,bottom,right,top.
//               Defaults to the middle half of the target page.
//   CAD_PAN_ZOOM   public viewer zoom for the pan loop (default 1.0)
//   CAD_PAN_LOOPS  back-and-forth pan/zoom loop count (default 3)
//   CAD_PAN_STEPS  trackpad pan updates per loop (default 48)
//
// Reports, for the target page: native vs capped decoded megapixels, the
// shipped command-buffer size (the bytes the worker hands the UI thread),
// decode+serialize time, full render time, the progressive vector-first
// first-paint time, and a viewer pan/zoom timing summary. Asserts the cap
// actually shrinks an oversized underlay.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';

import 'render_smoke_test.dart' show loadSystemFonts;

void main() {
  final path =
      Platform.environment['CAD_PDF'] ?? '../../corpus/ly9-far-cad.pdf';
  final ratio = double.tryParse(Platform.environment['CAD_RATIO'] ?? '') ?? 2.0;
  final pageOverride = int.tryParse(Platform.environment['CAD_PAGE'] ?? '');
  final doScan = (Platform.environment['CAD_SCAN'] ?? '1') != '0';
  final panLoops =
      int.tryParse(Platform.environment['CAD_PAN_LOOPS'] ?? '') ?? 3;
  final panSteps =
      int.tryParse(Platform.environment['CAD_PAN_STEPS'] ?? '') ?? 48;
  final panZoom =
      double.tryParse(Platform.environment['CAD_PAN_ZOOM'] ?? '') ?? 1.0;

  testWidgets('CAD heavy-raster render probe', (tester) async {
    final file = File(path);
    if (!file.existsSync()) {
      markTestSkipped('set CAD_PDF to a real file (missing: $path)');
      return;
    }

    await tester.runAsync(() async {
      await loadSystemFonts();
      final bytes = file.readAsBytesSync();
      final doc = PdfDocument.open(bytes);
      _line('opened ${_mb(bytes.length)} - ${doc.pageCount} pages: $path');

      // --- Pass A: cheap scan (no decode) to find the heavy raster page. ---
      var target = pageOverride ?? 0;
      if (doScan && pageOverride == null) {
        final ranked = <_PageImages>[];
        for (var i = 0; i < doc.pageCount; i++) {
          final requests = _imageRequests(doc, i);
          if (requests.isEmpty) continue;
          var declaredMp = 0.0;
          var drawnMp = 0.0;
          for (final r in requests) {
            declaredMp += _declaredPixels(doc, r) / 1e6;
            final t = r.transform;
            // transform column lengths == drawn size in points; at `ratio`
            // px/pt that is the on-screen footprint the cap targets.
            final wPts = _len(t.a, t.b);
            final hPts = _len(t.c, t.d);
            drawnMp += (wPts * ratio) * (hPts * ratio) / 1e6;
          }
          ranked.add(_PageImages(i, requests.length, declaredMp, drawnMp));
        }
        ranked.sort((a, b) => b.declaredMp.compareTo(a.declaredMp));
        _line('--- heaviest pages by declared image megapixels ---');
        for (final p in ranked.take(12)) {
          _line('  page ${p.page}: ${p.count} img, '
              '${p.declaredMp.toStringAsFixed(1)} MP native, '
              '${p.drawnMp.toStringAsFixed(2)} MP on-screen @${ratio}x');
        }
        if (ranked.isNotEmpty) target = ranked.first.page;
        if (ranked.isEmpty) _line('  (no image draws found on any page)');
      }

      _line('--- deep probe: page $target @ ratio ${ratio}x ---');
      final page = doc.page(target);

      // Interpret once (the off-thread walk) -> raw command buffer.
      final interp = Stopwatch()..start();
      final commands = _interpret(doc, target);
      interp.stop();
      _line('interpret: ${interp.elapsedMilliseconds} ms, '
          '${commands.length} commands');

      // Native decode (cap off): what the worker shipped before the fix.
      final nativeSw = Stopwatch()..start();
      final nativeBuf =
          serializeCommands(commands, cos: doc.cos, decodeImages: true);
      nativeSw.stop();
      final nativeStats =
          PdfPageRenderer.decodedImageStats(deserializeCommands(nativeBuf!));
      _line('native  decode: ${nativeSw.elapsedMilliseconds} ms, '
          '${nativeStats.$1} img, ${_mpStr(nativeStats.$2)} MP, '
          'buffer ${_mb(nativeBuf.length)}');

      // Capped decode (the fix): cap to ~2x on-screen at `ratio`.
      final capSw = Stopwatch()..start();
      final capBuf = serializeCommands(commands,
          cos: doc.cos, decodeImages: true, maxImagePixelRatio: ratio);
      capSw.stop();
      final capCmds = deserializeCommands(capBuf!);
      final capStats = PdfPageRenderer.decodedImageStats(capCmds);
      _line('capped  decode: ${capSw.elapsedMilliseconds} ms, '
          '${capStats.$1} img, ${_mpStr(capStats.$2)} MP, '
          'buffer ${_mb(capBuf.length)}');

      final decodeRegion = _decodeRegion(page);
      final regionSw = Stopwatch()..start();
      final regionBuf = serializeCommands(commands,
          cos: doc.cos,
          decodeImages: true,
          maxImagePixelRatio: ratio,
          imageDecodeRegion: decodeRegion);
      regionSw.stop();
      final regionCmds = deserializeCommands(regionBuf!);
      final regionStats = PdfPageRenderer.decodedImageStats(regionCmds);
      final regionShare = capStats.$2 == 0 ? 1.0 : regionStats.$2 / capStats.$2;
      _line('region  decode: ${regionSw.elapsedMilliseconds} ms, '
          '${regionStats.$1} img, ${_mpStr(regionStats.$2)} MP, '
          'buffer ${_mb(regionBuf.length)}, '
          'region=$decodeRegion '
          '(${(regionShare * 100).toStringAsFixed(1)}% of capped pixels)');

      final shrink = nativeStats.$2 == 0 ? 1.0 : capStats.$2 / nativeStats.$2;
      _line('cap shrank decoded pixels to '
          '${(shrink * 100).toStringAsFixed(1)}% of native');

      // The cap's contract: decode no sharper than headroom(2x) the on-screen
      // footprint. When native pixels already sit at/under that, there is
      // nothing to cut (the page genuinely carries that much imagery at this
      // zoom) and a no-op is correct — so the meaningful invariant is the
      // contract, not a fixed reduction.
      final footprintPixels = _onScreenFootprintPixels(capCmds, ratio);
      _line('on-screen footprint @${ratio}x: '
          '${_mpStr(footprintPixels)} MP '
          '(cap ceiling ~${_mpStr(footprintPixels * 4)} MP w/ 2x headroom)');

      // Full render of the capped buffer (replay + raster).
      final renderRatio = _renderRatio(page, ratio);
      final size = PdfPageRenderer.pageSize(page);
      final renderSw = Stopwatch()..start();
      final picture = await PdfPageRenderer.pictureFromCommands(page, capCmds);
      final image = await PdfPageRenderer.rasterize(picture, size, renderRatio);
      await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      renderSw.stop();
      _line('full render (capped): ${renderSw.elapsedMilliseconds} ms '
          '-> ${image.width}x${image.height}');
      picture.dispose();
      image.dispose();

      // Progressive first paint: vector/text only, no image decode.
      final vecSw = Stopwatch()..start();
      final vecBuf = serializeCommands(commands, cos: doc.cos);
      final vecCmds = deserializeCommands(vecBuf!);
      final vecPic = await PdfPageRenderer.pictureFromCommands(page, vecCmds,
          includeImages: false);
      final vecImg = await PdfPageRenderer.rasterize(vecPic, size, renderRatio);
      await vecImg.toByteData(format: ui.ImageByteFormat.rawRgba);
      vecSw.stop();
      _line('progressive first paint (vector-only): '
          '${vecSw.elapsedMilliseconds} ms');
      vecPic.dispose();
      vecImg.dispose();

      // --- Assertions ---
      // 1. The cap never invents pixels.
      expect(capStats.$2, lessThanOrEqualTo(nativeStats.$2),
          reason: 'capped pixels must never exceed native');
      // 2. The cap honored its contract: each image decodes to no more than
      //    headroom^2 (= 4x) its on-screen footprint, with two slacks baked
      //    into cappedImagePixelSize — it leaves an image at native when a
      //    resample would save <10% (the 0.9 skip threshold, so per-image
      //    decoded can reach target/0.9) and ceil()s each edge. A no-op when
      //    native already sits under that ceiling is correct. A failure here
      //    means the cap math regressed or the worker bundle ships un-capped
      //    images.
      const headroomArea = 2.0 * 2.0;
      const skipSlack = 1 / 0.9;
      final perImageCeiling =
          (footprintPixels * headroomArea * skipSlack).round() +
              capStats.$1 * 16 +
              (1 << 20);
      // 3. The page-pixel budget bounds the TOTAL decoded pixels to
      //    ~budgetFactor (1.0) x the 16.78 MP page raster cap, regardless of
      //    overlap. Decoded pixels must sit under whichever ceiling binds.
      const pageBudget = (1.0 * (1 << 24)) + (4 << 20); // + downsample slop
      final ceiling =
          perImageCeiling < pageBudget ? perImageCeiling : pageBudget;
      expect(capStats.$2.toDouble(), lessThanOrEqualTo(ceiling.toDouble()),
          reason: 'capped pixels (${_mpStr(capStats.$2)} MP) exceed the '
              'binding cap ceiling (${(ceiling / 1e6).toStringAsFixed(1)} MP) '
              'for a ${_mpStr(footprintPixels)} MP footprint at ${ratio}x - '
              'per-image or page-budget cap regressed, or worker is stale');
    });
  }, timeout: const Timeout(Duration(minutes: 20)));

  testWidgets('CAD viewer pan/zoom loop', (tester) async {
    final file = File(path);
    if (!file.existsSync()) {
      markTestSkipped('set CAD_PDF to a real file (missing: $path)');
      return;
    }
    if (panLoops <= 0 || panSteps <= 0) {
      markTestSkipped('CAD_PAN_LOOPS and CAD_PAN_STEPS must be > 0');
      return;
    }

    final bytes = file.readAsBytesSync();
    final document = PdfDocument.open(bytes);
    final target = pageOverride ??
        (doScan ? _heaviestImagePage(document, ratio) : 0)
            .clamp(0, document.pageCount - 1)
            .toInt();
    final controller = PdfViewerController();
    final worker = startPdfRenderWorker(bytes, pageCount: document.pageCount);
    addTearDown(controller.dispose);
    addTearDown(worker.dispose);

    final timings = <FrameTiming>[];
    void onTimings(List<FrameTiming> batch) => timings.addAll(batch);
    SchedulerBinding.instance.addTimingsCallback(onTimings);
    addTearDown(
        () => SchedulerBinding.instance.removeTimingsCallback(onTimings));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 1200,
          height: 800,
          child: PdfViewer(
            document: document,
            controller: controller,
            initialFit: PdfViewerFit.width,
            renderWorker: worker,
            pagePreviews: true,
            previewWindow: 2,
          ),
        ),
      ),
    ));
    await tester.pump();
    await controller.jumpToPage(target);
    await tester.pump(const Duration(milliseconds: 100));
    controller.setZoom(panZoom);
    await tester.pump(const Duration(milliseconds: 250));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));

    timings.clear();
    final pumpUs = <(String, int)>[];
    final center = tester.getCenter(find.byType(PdfViewer));

    for (var loop = 0; loop < panLoops; loop++) {
      final pinch = await tester.createGesture(
          kind: PointerDeviceKind.trackpad, pointer: 500 + loop * 2);
      await pinch.panZoomStart(center);
      for (var i = 1; i <= panSteps ~/ 3; i++) {
        await _timedPump(tester, pumpUs, 'pinch $loop/$i', () async {
          await pinch.panZoomUpdate(center, scale: 1 + 0.004 * i);
        });
      }
      await pinch.panZoomEnd();

      final pan = await tester.createGesture(
          kind: PointerDeviceKind.trackpad, pointer: 501 + loop * 2);
      await pan.panZoomStart(center);
      for (var i = 1; i <= panSteps; i++) {
        final direction = loop.isEven ? -1.0 : 1.0;
        await _timedPump(tester, pumpUs, 'pan $loop/$i', () async {
          await pan.panZoomUpdate(center,
              pan: Offset(direction * 18 * i, -8.0 * i),
              timeStamp: Duration(milliseconds: 16 * i));
        });
        if (i % 12 == 0) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 1)));
        }
      }
      await pan.panZoomEnd(
          timeStamp: Duration(milliseconds: 16 * (panSteps + 1)));
      await tester.pump(const Duration(milliseconds: 16));
    }

    await tester.pump(const Duration(milliseconds: 16));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();

    _printPanSummary(
      target: target,
      loops: panLoops,
      steps: panSteps,
      zoom: panZoom,
      timings: timings,
      pumpUs: pumpUs,
    );
  }, timeout: const Timeout(Duration(minutes: 20)));
}

/// Interprets [pageIndex] to a raw command buffer (no decode), exactly as
/// the worker isolate's record path does.
List<PdfRenderCommand> _interpret(PdfDocument doc, int pageIndex) {
  final page = doc.page(pageIndex);
  final ops = ContentStreamParser.parse(page.contentBytes());
  final recorder = RecordingPdfDevice();
  final interpreter = PdfInterpreter(cos: doc.cos, device: recorder);
  interpreter.drawPageOperations(page, ops);
  interpreter.drawAnnotations(page);
  return recorder.commands;
}

/// Collects the image draw requests on a page without decoding.
List<PdfImageRequest> _imageRequests(PdfDocument doc, int pageIndex) {
  final requests = <PdfImageRequest>[];
  for (final c in _interpret(doc, pageIndex)) {
    _walk(c, requests);
  }
  return requests;
}

int _heaviestImagePage(PdfDocument doc, double ratio) {
  var bestPage = 0;
  var bestMp = -1.0;
  for (var i = 0; i < doc.pageCount; i++) {
    final requests = _imageRequests(doc, i);
    if (requests.isEmpty) continue;
    var declaredMp = 0.0;
    for (final r in requests) {
      declaredMp += _declaredPixels(doc, r) / 1e6;
    }
    if (declaredMp > bestMp) {
      bestMp = declaredMp;
      bestPage = i;
    }
  }
  return bestPage;
}

void _walk(PdfRenderCommand c, List<PdfImageRequest> out) {
  if (c is PdfDrawImageCommand) {
    out.add(c.request);
  } else if (c is PdfEndSoftMaskedCommand) {
    for (final m in c.maskCommands) {
      _walk(m, out);
    }
  }
}

/// Sum of every image's on-screen footprint in pixels at [ratio] px/pt
/// (drawn point size from the CTM column lengths). The cap targets
/// `headroom^2` times this.
int _onScreenFootprintPixels(List<PdfRenderCommand> commands, double ratio) {
  final requests = <PdfImageRequest>[];
  for (final c in commands) {
    _walk(c, requests);
  }
  var total = 0.0;
  for (final r in requests) {
    final t = r.transform;
    total += (_len(t.a, t.b) * ratio) * (_len(t.c, t.d) * ratio);
  }
  return total.round();
}

int _declaredPixels(PdfDocument doc, PdfImageRequest r) {
  final dict = r.stream.dictionary;
  final w = _intOf(doc.cos.resolve(dict['Width']));
  final h = _intOf(doc.cos.resolve(dict['Height']));
  return w * h;
}

int _intOf(CosObject? o) {
  if (o is CosInteger) return o.value;
  if (o is CosReal) return o.value.round();
  return 0;
}

double _len(double a, double b) => math.sqrt(a * a + b * b);

/// Mirrors PdfPageView._effectiveRatio's clamp (16.7 MP / 8192 px ceilings).
double _renderRatio(PdfPage page, double desired) {
  final size = PdfPageRenderer.pageSize(page);
  final w = size.width < 1 ? 1.0 : size.width;
  final h = size.height < 1 ? 1.0 : size.height;
  var r = desired;
  final byPixels = math.sqrt((1 << 24) / (w * h));
  if (byPixels < r) r = byPixels;
  final byDim = 8192.0 / (w > h ? w : h);
  if (byDim < r) r = byDim;
  return r < 0.05 ? 0.05 : r;
}

PdfRect _decodeRegion(PdfPage page) {
  final raw = Platform.environment['CAD_REGION'];
  if (raw != null && raw.trim().isNotEmpty) {
    final parts = raw.split(',').map((s) => double.tryParse(s.trim())).toList();
    if (parts.length == 4 && parts.every((v) => v != null)) {
      return PdfRect.normalized(parts[0]!, parts[1]!, parts[2]!, parts[3]!);
    }
  }
  final box = page.cropBox;
  return PdfRect(
    box.left + box.width * 0.25,
    box.bottom + box.height * 0.25,
    box.left + box.width * 0.75,
    box.bottom + box.height * 0.75,
  );
}

String _mpStr(int pixels) => (pixels / 1e6).toStringAsFixed(1);
String _mb(int bytes) => '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';

void _line(String s) {
  // ignore: avoid_print
  print('[cad-probe] $s');
}

Future<void> _timedPump(WidgetTester tester, List<(String, int)> pumpUs,
    String label, Future<void> Function() body) async {
  await body();
  final sw = Stopwatch()..start();
  await tester.pump(const Duration(milliseconds: 16));
  sw.stop();
  pumpUs.add((label, sw.elapsedMicroseconds));
}

void _printPanSummary({
  required int target,
  required int loops,
  required int steps,
  required double zoom,
  required List<FrameTiming> timings,
  required List<(String, int)> pumpUs,
}) {
  double ms(Duration d) => d.inMicroseconds / 1000.0;
  final build = [for (final t in timings) ms(t.buildDuration)];
  final raster = [for (final t in timings) ms(t.rasterDuration)];
  final total = [for (final t in timings) ms(t.totalSpan)];
  final pump = [for (final entry in pumpUs) entry.$2 / 1000.0];
  int over(List<double> values, double limit) =>
      values.where((v) => v > limit).length;
  _line('--- viewer pan/zoom loop: page $target, loops=$loops, '
      'steps=$steps, zoom=${zoom}x ---');
  if (timings.isEmpty) {
    _line('frame timings unavailable in this test backend');
  } else {
    _line('frames=${timings.length}, '
        'build>16ms=${over(build, 16)}, raster>16ms=${over(raster, 16)}, '
        'total>16ms=${over(total, 16)}');
    _line('frame build ${_dist(build)}; raster ${_dist(raster)}; '
        'total ${_dist(total)}');
  }
  _line('pump wall ${_dist(pump)} (${pump.length} interaction pumps)');
  final slowest = [...pumpUs]..sort((a, b) => b.$2.compareTo(a.$2));
  _line('slowest pumps: ${slowest.take(5).map((e) {
    return '${e.$1}=${(e.$2 / 1000.0).toStringAsFixed(1)}ms';
  }).join(', ')}');
}

String _dist(List<double> values) {
  if (values.isEmpty) return 'n/a';
  final sorted = [...values]..sort();
  double at(double q) => sorted[(q * (sorted.length - 1)).round()];
  return 'p50=${at(0.50).toStringAsFixed(1)}ms '
      'p95=${at(0.95).toStringAsFixed(1)}ms '
      'max=${sorted.last.toStringAsFixed(1)}ms';
}

class _PageImages {
  _PageImages(this.page, this.count, this.declaredMp, this.drawnMp);
  final int page;
  final int count;
  final double declaredMp;
  final double drawnMp;
}
