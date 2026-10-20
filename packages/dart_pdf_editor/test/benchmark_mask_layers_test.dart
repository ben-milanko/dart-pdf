// Local masked-graphics diagnosis. No PDF or raster is checked into the repo.
// PDF_PATH=/path/to/drawing.pdf PDF_MASK_BENCHMARK_OUT=/tmp/mask-phases.json \
//   fvm flutter test --no-pub test/benchmark_mask_layers_test.dart
// Optional: PDF_MASK_SCALES=30,60,100, PDF_MASK_SCENARIOS=middle-right,
// PDF_MASK_TRIALS=7, PDF_MASK_PNG_DIR=/tmp/mask-phases.
// Only the explicit output clip is expected to preserve pixels. Image and
// layer ablations deliberately change the rendering; their costs are not
// additive estimates of production phases (raster optimizers can elide work).
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/canvas_path_cache.dart';
import 'package:dart_pdf_editor/src/image_decoder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart' show PdfPage;
import 'package:pdf_graphics/pdf_graphics.dart';

import 'render_smoke_test.dart' show loadSystemFonts;

const _locations = {
  'upper-right': ui.Offset(400 / 421, 18 / 269),
  'middle-right': ui.Offset(405 / 421, 84 / 269),
  'lower-right': ui.Offset(345 / 421, 169 / 269),
  'bottom-right': ui.Offset(345 / 421, 214 / 269),
};

enum _Variant { stock, outputClip, flatImages, noLayers, elideOpaqueGroups }

void main() {
  testWidgets('masked image scaling and layer phase diagnostics',
      (tester) async {
    final env = Platform.environment;
    final path = env['PDF_PATH'];
    if (path == null) {
      markTestSkipped('set PDF_PATH');
      return;
    }
    await tester.runAsync(() async {
      await loadSystemFonts();
      final scales = (env['PDF_MASK_SCALES'] ?? '30,60,100')
          .split(',')
          .map(double.parse)
          .toList();
      final scenarios =
          (env['PDF_MASK_SCENARIOS'] ?? 'middle-right').split(',');
      final trials = int.parse(env['PDF_MASK_TRIALS'] ?? '7');
      final pngDir = env['PDF_MASK_PNG_DIR'];
      if (pngDir != null) Directory(pngDir).createSync(recursive: true);
      const width = 2560, height = 1600, dpr = 2.0;
      final bytes = File(path).readAsBytesSync();
      final pageIndex = int.parse(env['PDF_PAGE'] ?? '0');
      final page = PdfDocument.open(bytes).page(pageIndex);
      final worker = PdfRenderWorker.start(bytes);
      final paths = PdfCanvasPathCache();
      try {
        final commands = (await worker.record(pageIndex,
            imagePixelRatio: scales.reduce(math.max) * dpr))!;
        final scene = await PdfRetainedScene.fromCommands(page, commands,
            maxImagePixelRatio: scales.reduce(math.max) * dpr);
        try {
          final requests = <PdfImageRequest>[];
          PdfPageRenderer.collectImageRequests(commands, requests);
          final images = <Object, ui.Image>{
            for (final request in requests)
              if (scene.imageFor(request) case final image?)
                pdfImageKey(request): image,
          };
          final results = <Object>[];
          var clipChanged = 0;
          for (final name in scenarios) {
            final location = _locations[name]!;
            for (final zoom in scales) {
              final ratio = zoom * dpr;
              final rw = width / ratio, rh = height / ratio;
              final region = ui.Rect.fromLTWH(
                  (scene.pageSize.width * location.dx - rw / 2)
                      .clamp(0.0, math.max(0.0, scene.pageSize.width - rw)),
                  (scene.pageSize.height * location.dy - rh / 2)
                      .clamp(0.0, math.max(0.0, scene.pageSize.height - rh)),
                  rw,
                  rh);
              final units = scene.selectRegion(region)!;
              final selected = <PdfRenderCommand>[];
              for (final unit in units) {
                selected.add(const PdfSaveCommand());
                selected.add(PdfSetBlendModeCommand(unit.blendMode));
                unit.clips?.appendCommands(selected);
                selected.addAll(
                    commands.getRange(unit.commandIndex, unit.endCommandIndex));
                selected.add(const PdfRestoreCommand());
              }
              final variants = {
                for (final variant in _Variant.values)
                  variant: _transform(selected, variant),
              };
              final times = {
                for (final v in _Variant.values) v: <List<double>>[]
              };
              final differences = {for (final v in _Variant.values) v: (0, 0)};
              Uint8List? oracle;
              for (var trial = 0; trial <= trials; trial++) {
                // Rotate the order each trial: every variant sees warm and
                // cold neighbours without always following the stock run.
                final order = [
                  for (var n = 0; n < _Variant.values.length; n++)
                    _Variant.values[(n + trial) % _Variant.values.length],
                ];
                for (final variant in order) {
                  final clock = Stopwatch()..start();
                  final picture = _picture(scene, variants[variant]!, images,
                      paths, region, ratio, width, height,
                      clip: variant == _Variant.outputClip);
                  final replayMs = clock.elapsedMicroseconds / 1000;
                  clock.reset();
                  final image = await picture.toImage(width, height);
                  final rasterMs = clock.elapsedMicroseconds / 1000;
                  try {
                    clock.reset();
                    final data = (await image.toByteData(
                        format: ui.ImageByteFormat.rawRgba))!;
                    final pixels = data.buffer
                        .asUint8List(data.offsetInBytes, data.lengthInBytes);
                    final readbackMs = clock.elapsedMicroseconds / 1000;
                    if (trial == 0 && variant == _Variant.stock) {
                      oracle = pixels;
                    }
                    final difference = _diff(oracle!, pixels);
                    final previous = differences[variant]!;
                    differences[variant] = (
                      math.max(previous.$1, difference.$1),
                      math.max(previous.$2, difference.$2)
                    );
                    if (trial > 0) {
                      times[variant]!.add([replayMs, rasterMs, readbackMs]);
                    }
                    if (trial == 0 && pngDir != null) {
                      final png = (await image.toByteData(
                          format: ui.ImageByteFormat.png))!;
                      File('$pngDir/$name-${zoom.toInt()}x-${variant.name}.png')
                          .writeAsBytesSync(png.buffer.asUint8List(
                              png.offsetInBytes, png.lengthInBytes));
                    }
                  } finally {
                    image.dispose();
                    picture.dispose();
                  }
                }
              }
              clipChanged += differences[_Variant.outputClip]!.$1;
              results.add({
                'scenario': name,
                'viewPercent': zoom * 100,
                'regionPoints': [
                  region.left,
                  region.top,
                  region.width,
                  region.height
                ],
                'selectedCommands': selected.length,
                'structure': _structure(selected, images, page),
                'variants': {
                  for (final v in _Variant.values)
                    v.name: {
                      'productionEquivalentCandidate':
                          v == _Variant.stock || v == _Variant.outputClip,
                      'medianReplayMs': _median(times[v]!.map((s) => s[0])),
                      'medianRasterMs': _median(times[v]!.map((s) => s[1])),
                      'medianReadbackMs': _median(times[v]!.map((s) => s[2])),
                      'medianReplayAndRasterMs':
                          _median(times[v]!.map((s) => s[0] + s[1])),
                      'medianReplayRasterReadbackMs':
                          _median(times[v]!.map((s) => s[0] + s[1] + s[2])),
                      'maxChangedPixels': differences[v]!.$1,
                      'maxChannelDifference': differences[v]!.$2,
                      'samples': times[v],
                    },
                },
              });
              // ignore: avoid_print
              print('$name ${zoom}x: ${[
                for (final v in _Variant.values)
                  '${v.name}=${_median(times[v]!.map((s) => s[1])).toStringAsFixed(2)}ms/${differences[v]!.$1}px'
              ]}');
            }
          }
          final result = const JsonEncoder.withIndent('  ').convert({
            'note':
                'Flat-image/layer ablations intentionally change pixels; costs are not additive phase estimates.',
            'readbackCaution':
                'Impeller toImage may precede GPU completion. Readback waits for completion and adds transfer cost; the inclusive total is not viewer frame latency.',
            'imagePixels': [width, height],
            'dpr': dpr,
            'warmupTrials': 1,
            'measuredTrials': trials,
            'results': results,
          });
          final out = env['PDF_MASK_BENCHMARK_OUT'];
          if (out != null) File(out).writeAsStringSync(result);
          expect(clipChanged, 0,
              reason: 'a physical output clip must preserve every pixel');
        } finally {
          scene.dispose();
        }
      } finally {
        paths.dispose();
        worker.dispose();
      }
    });
  }, timeout: const Timeout(Duration(minutes: 10)));
}

ui.Picture _picture(
    PdfRetainedScene scene,
    List<PdfRenderCommand> commands,
    Map<Object, ui.Image> images,
    PdfCanvasPathCache paths,
    ui.Rect region,
    double ratio,
    int width,
    int height,
    {required bool clip}) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  // Clip physical output pixels before transformation; clipping the logical
  // ROI instead loses the rounded fringe of non-integral raster dimensions.
  if (clip) {
    canvas.clipRect(ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        doAntiAlias: false);
  }
  canvas.scale(ratio);
  canvas.translate(-region.left, -region.top);
  PdfPageRenderer.preparePageCanvas(canvas, scene.page, scene.plan);
  replayCommands(
      commands, CanvasPdfDevice(canvas, images: images, pathCache: paths));
  return recorder.endRecording();
}

List<PdfRenderCommand> _transform(
    List<PdfRenderCommand> commands, _Variant variant) {
  final out = <PdfRenderCommand>[];
  final groupElided = <bool>[];
  for (final command in commands) {
    if (command is PdfDrawImageCommand && variant == _Variant.flatImages) {
      final m = command.request.transform;
      final corners = [
        m.apply(0, 0),
        m.apply(1, 0),
        m.apply(1, 1),
        m.apply(0, 1)
      ];
      out.add(PdfFillPathCommand(
          PdfPath([
            PdfMoveTo(corners.first.$1, corners.first.$2),
            for (final p in corners.skip(1)) PdfLineTo(p.$1, p.$2),
            const PdfClosePath(),
          ]),
          const PdfColor(1, 1, 1),
          PdfFillRule.nonzero,
          command.request.alpha));
    } else if (command is PdfBeginGroupCommand) {
      final elide = variant == _Variant.noLayers ||
          (variant == _Variant.elideOpaqueGroups &&
              command.alpha == 1 &&
              command.isolated &&
              !command.knockout);
      groupElided.add(elide);
      out.add(elide ? const PdfSaveCommand() : command);
    } else if (command is PdfEndGroupCommand) {
      out.add(groupElided.removeLast() ? const PdfRestoreCommand() : command);
    } else if (command is PdfBeginSoftMaskedCommand &&
        variant == _Variant.noLayers) {
      out.add(const PdfSaveCommand());
    } else if (command is PdfEndSoftMaskedCommand) {
      final mask = _transform(command.maskCommands, variant);
      if (variant == _Variant.noLayers) {
        out.addAll(mask);
        out.add(const PdfRestoreCommand());
      } else {
        out.add(PdfEndSoftMaskedCommand(
            luminosity: command.luminosity,
            backdrop: command.backdrop,
            maskCommands: mask,
            backdropLuminance: command.backdropLuminance,
            transferScale: command.transferScale,
            transferOffset: command.transferOffset));
      }
    } else if (command is PdfDrawTiledCellCommand) {
      out.add(PdfDrawTiledCellCommand(_transform(command.cellCommands, variant),
          command.originsX, command.originsY));
    } else {
      out.add(command);
    }
  }
  return out;
}

Map<String, Object> _structure(List<PdfRenderCommand> commands,
    Map<Object, ui.Image> images, PdfPage page) {
  final counts = <String, int>{};
  final draws = <Object>[];
  void visit(List<PdfRenderCommand> list, String prefix) {
    for (var i = 0; i < list.length; i++) {
      final c = list[i], path = '$prefix$i';
      counts.update(c.runtimeType.toString(), (n) => n + 1, ifAbsent: () => 1);
      if (c is PdfDrawImageCommand) {
        final r = c.request, image = images[pdfImageKey(r)];
        final source = r.sourceReference == null
            ? r.stream
            : page.document.cos.resolve(r.sourceReference);
        final dict =
            source is CosStream ? source.dictionary : r.stream.dictionary;
        draws.add({
          'path': path,
          'imagePixels': image == null ? null : [image.width, image.height],
          'nativeWidth': dict['Width'].toString(),
          'nativeHeight': dict['Height'].toString(),
          'transform': r.transform.toList(),
          'alpha': r.alpha,
          'stencil': r.isStencil,
          'luminosityImage': r.isLuminosityMask,
          'companionMask': image != null && pdfGpuSoftMaskOf(image) != null
        });
      } else if (c is PdfBeginGroupCommand) {
        draws.add({
          'path': path,
          'groupAlpha': c.alpha,
          'isolated': c.isolated,
          'knockout': c.knockout,
          'bounds': c.bounds.toString(),
          'backdropColor': c.backdropColor.toString()
        });
      } else if (c is PdfSetBlendModeCommand) {
        draws.add({'path': path, 'blend': c.mode.name});
      } else if (c is PdfEndSoftMaskedCommand) {
        draws.add({
          'path': path,
          'luminosity': c.luminosity,
          'backdrop': c.backdrop.toString(),
          'backdropLuminance': c.backdropLuminance,
          'transfer': [c.transferScale, c.transferOffset],
          'maskCommands': c.maskCommands.length
        });
        visit(c.maskCommands, '$path.mask.');
      } else if (c is PdfDrawTiledCellCommand) {
        draws.add({
          'path': path,
          'cellCommands': c.cellCommands.length,
          'instances': c.originsX.length
        });
        visit(c.cellCommands, '$path.cell.');
      }
    }
  }

  visit(commands, '');
  return {'counts': counts, 'details': draws};
}

double _median(Iterable<double> values) {
  final sorted = values.toList()..sort();
  return sorted[sorted.length ~/ 2];
}

(int, int) _diff(Uint8List a, Uint8List b) {
  var pixels = 0, maxDifference = 0;
  for (var i = 0; i < a.length; i += 4) {
    var changed = false;
    for (var c = 0; c < 4; c++) {
      final delta = (a[i + c] - b[i + c]).abs();
      changed |= delta != 0;
      maxDifference = math.max(maxDifference, delta);
    }
    if (changed) pixels++;
  }
  return (pixels, maxDifference);
}
