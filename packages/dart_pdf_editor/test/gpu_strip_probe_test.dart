// Synthetic smoke test for the sparse-strip pipeline (gpu_strips.dart +
// pdf_strip.vert/frag): hand-builds the strip-generator SoA arrays for a
// 64x64 box whose 1px border ring has 50% coverage (127) and whose interior
// is full coverage - the middle strip rows use solid-flag strips (no alpha
// data) for the interior, so one image validates the whole contract:
// vertex layout, u16 xy packing, the solid flag, all four RGBA channel
// selects, multi-row atlas addressing (atlasWidth 64 forces 3 atlas rows),
// nearest-sample exactness, and src-over blending.
//
//   fvm flutter test --enable-impeller --enable-flutter-gpu \
//     test/gpu_strip_probe_test.dart
//
// Skips when the GPU context is unavailable (plain `flutter test`).
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/gpu.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_graphics/pdf_graphics.dart'
    show PdfColor, PdfFillRule, PdfLineTo, PdfMatrix, PdfMoveTo, PdfPath;
import 'package:pdf_graphics/raster.dart'
    show StripGenerator, premulRgba8, stripSolidSentinel;
import 'package:vector_math/vector_math.dart' as vm;

/// Builds the strip generator's SoA arrays by hand.
class _StripsBuilder {
  final xy = <int>[];
  final widthFlags = <int>[];
  final alphaOffset = <int>[];
  final color = <int>[];
  final alphas = <int>[];

  int get count => xy.length;

  /// One coverage strip at device px (x, y), one 4-byte column per entry in
  /// [columns] (column byte 0 = the strip's top pixel row).
  void alpha(int x, int y, int rgba, List<List<int>> columns) {
    xy.add(x | (y << 16));
    widthFlags.add(columns.length);
    alphaOffset.add(alphas.length ~/ 4);
    color.add(rgba);
    for (final col in columns) {
      assert(col.length == 4);
      alphas.addAll(col);
    }
  }

  /// One solid strip (coverage 1, consumes no alpha data).
  void solid(int x, int y, int width, int rgba) {
    xy.add(x | (y << 16));
    widthFlags.add(width);
    alphaOffset.add(stripSolidSentinel);
    color.add(rgba);
  }
}

void main() {
  testWidgets('strip pipeline renders exact coverage bytes', (tester) async {
    await tester.runAsync(() async {
      late final gpu.GpuContext context;
      try {
        context = gpu.gpuContext;
        // ignore: unnecessary_statements
        context.defaultColorFormat;
      } catch (e) {
        markTestSkipped('flutter_gpu unavailable in this tester: $e');
        return;
      }
      final pipelines = PdfGpuPipelines.instance(context);

      // Premultiplied opaque red: r | g<<8 | b<<16 | a<<24.
      const red = 0x000000FF | 0xFF000000;
      const box = 64, bx = 16, by = 16; // box offset inside the target
      const border = 127; // 50% coverage ring

      final strips = _StripsBuilder();
      // Top strip row: border across row 0, corners fully border.
      strips.alpha(bx, by, red, [
        for (var c = 0; c < box; c++)
          c == 0 || c == box - 1
              ? const [border, border, border, border]
              : const [border, 255, 255, 255],
      ]);
      // Middle rows: 1px border columns as alpha strips, interior solid.
      for (var row = 1; row < box ~/ 4 - 1; row++) {
        final y = by + row * 4;
        strips.alpha(bx, y, red, const [
          [border, border, border, border],
        ]);
        strips.solid(bx + 1, y, box - 2, red);
        strips.alpha(bx + box - 1, y, red, const [
          [border, border, border, border],
        ]);
      }
      // Bottom strip row: mirror of the top.
      strips.alpha(bx, by + box - 4, red, [
        for (var c = 0; c < box; c++)
          c == 0 || c == box - 1
              ? const [border, border, border, border]
              : const [255, 255, 255, border],
      ]);

      // atlasWidth 64 < 156 total columns -> texel indices span 3 atlas
      // rows, exercising the index -> x/y recovery in the fragment stage.
      final batch = StripBatch(context: context, pipelines: pipelines, atlasWidth: 64)
        ..setStrips(
          count: strips.count,
          xy: Uint32List.fromList(strips.xy),
          widthFlags: Uint32List.fromList(strips.widthFlags),
          alphaOffset: Uint32List.fromList(strips.alphaOffset),
          color: Uint32List.fromList(strips.color),
          alphas: Uint8List.fromList(strips.alphas),
        );

      const w = 96, h = 96; // aliased target, no depth/stencil/MSAA
      final target = context.createTexture(gpu.StorageMode.devicePrivate, w, h,
          format: context.defaultColorFormat);
      final commandBuffer = context.createCommandBuffer();
      final pass = commandBuffer.createRenderPass(gpu.RenderTarget.singleColor(
        gpu.ColorAttachment(
            texture: target, clearValue: vm.Vector4(0, 0, 0, 0)),
      ));
      final hostBuffer = context.createHostBuffer();
      batch.encode(pass, hostBuffer, widthPx: w, heightPx: h);
      commandBuffer.submit();

      final image = target.asImage();
      final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final bytes = data.buffer.asUint8List();

      int expected(int x, int y) {
        final lx = x - bx, ly = y - by;
        if (lx < 0 || ly < 0 || lx >= box || ly >= box) return 0;
        if (lx == 0 || ly == 0 || lx == box - 1 || ly == box - 1) {
          return border;
        }
        return 255;
      }

      var checked = 0;
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final i = (y * w + x) * 4;
          final want = expected(x, y);
          final r = bytes[i], g = bytes[i + 1], b = bytes[i + 2];
          final a = bytes[i + 3];
          if (want == border) {
            // 127/255 survives one float round-trip as 127 or 128.
            expect(r, inInclusiveRange(127, 128),
                reason: 'red at ($x,$y)');
            expect(a, inInclusiveRange(127, 128),
                reason: 'alpha at ($x,$y)');
          } else {
            expect(r, want, reason: 'red at ($x,$y)');
            expect(a, want, reason: 'alpha at ($x,$y)');
          }
          expect(g, 0, reason: 'green at ($x,$y)');
          expect(b, 0, reason: 'blue at ($x,$y)');
          checked++;
        }
      }
      expect(checked, w * h);

      // Spot-verify the interesting classes explicitly (exact bytes).
      int px(int x, int y, int c) => bytes[(y * w + x) * 4 + c];
      expect(px(bx - 1, by, 0), 0); // outside, left of the box
      expect(px(bx + box, by + box - 1, 3), 0); // outside, right
      expect(px(bx, by, 0), inInclusiveRange(127, 128)); // corner ring
      expect(px(bx + 30, by, 0), inInclusiveRange(127, 128)); // top border
      expect(px(bx + 1, by + 1, 0), 255); // interior from alpha texel 255
      expect(px(bx + 30, by + 30, 0), 255); // interior from solid strip
      expect(px(bx + 30, by + 30, 3), 255); // solid strip alpha
    });
  });

  testWidgets('StripGenerator star matches the MSAA stencil path',
      (tester) async {
    await tester.runAsync(() async {
      late final gpu.GpuContext context;
      try {
        context = gpu.gpuContext;
        // ignore: unnecessary_statements
        context.defaultColorFormat;
      } catch (e) {
        markTestSkipped('flutter_gpu unavailable in this tester: $e');
        return;
      }
      final pipelines = PdfGpuPipelines.instance(context);
      const w = 128, h = 128;

      // Classic self-intersecting 5-point star, even-odd (hollow core):
      // exercises the generator's winding machinery, not just boxes.
      final pts = <double>[];
      for (var i = 0; i < 5; i++) {
        final ang = -math.pi / 2 + i * 4 * math.pi / 5;
        pts.addAll([64 + 52 * math.cos(ang), 64 + 52 * math.sin(ang)]);
      }
      final star = PdfPath([
        PdfMoveTo(pts[0], pts[1]),
        for (var i = 1; i < 5; i++) PdfLineTo(pts[2 * i], pts[2 * i + 1]),
      ]);
      const color = PdfColor(0.2, 0.4, 0.8);

      Future<Uint8List> readback(gpu.Texture texture) async {
        final image = texture.asImage();
        final data =
            (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        return data.buffer.asUint8List();
      }

      // (a) CPU strips -> strip pipeline, aliased 1-sample target.
      final gen = StripGenerator()..begin(w, h);
      gen.fillPath(star, PdfMatrix.identity, PdfFillRule.evenOdd,
          premulRgba8(color, 1.0));
      final buf = gen.strips;
      final batch = StripBatch(context: context, pipelines: pipelines)
        ..setStrips(
          count: buf.length,
          xy: buf.xy,
          widthFlags: buf.widthFlags,
          alphaOffset: buf.alphaOffset,
          color: buf.color,
          alphas: buf.alphas,
          alphaTexels: buf.alphaColumns,
        );
      final stripTarget = context.createTexture(
          gpu.StorageMode.devicePrivate, w, h,
          format: context.defaultColorFormat);
      {
        final commandBuffer = context.createCommandBuffer();
        final pass =
            commandBuffer.createRenderPass(gpu.RenderTarget.singleColor(
          gpu.ColorAttachment(
              texture: stripTarget, clearValue: vm.Vector4(0, 0, 0, 0)),
        ));
        batch.encode(pass, context.createHostBuffer(),
            widthPx: w, heightPx: h);
        commandBuffer.submit();
      }
      final stripBytes = await readback(stripTarget);

      // (b) The existing even-odd route: GpuPdfDevice stencil-then-cover
      // into a 4x MSAA target (the AA quality reference).
      final resolve = context.createTexture(gpu.StorageMode.devicePrivate,
          w, h,
          format: context.defaultColorFormat);
      final msaaColor = context.createTexture(
          gpu.StorageMode.deviceTransient, w, h,
          format: context.defaultColorFormat, sampleCount: 4);
      final stencil = context.createTexture(
          gpu.StorageMode.deviceTransient, w, h,
          format: context.defaultStencilFormat, sampleCount: 4);
      {
        final commandBuffer = context.createCommandBuffer();
        final pass = commandBuffer.createRenderPass(gpu.RenderTarget(
          colorAttachments: [
            gpu.ColorAttachment(
              texture: msaaColor,
              resolveTexture: resolve,
              clearValue: vm.Vector4(0, 0, 0, 0),
              storeAction: gpu.StoreAction.multisampleResolve,
            ),
          ],
          depthStencilAttachment: gpu.DepthStencilAttachment(
            texture: stencil,
            stencilClearValue: 0,
          ),
        ));
        final device = GpuPdfDevice(
          context: context,
          pass: pass,
          hostBuffer: context.createHostBuffer(),
          pipelines: pipelines,
          pageToDevice: PdfMatrix.identity,
          widthPx: w,
          heightPx: h,
        );
        device.fillPath(star, color, PdfFillRule.evenOdd, 1.0);
        device.finish();
        commandBuffer.submit();
      }
      final msaaBytes = await readback(resolve);

      // Same shape, two AA mechanisms: interiors identical, edges within a
      // sample-position wobble. Mean channel diff must be edge-only small.
      var sum = 0;
      var maxInterior = 0;
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          for (var c = 0; c < 4; c++) {
            final i = (y * w + x) * 4 + c;
            final d = (stripBytes[i] - msaaBytes[i]).abs();
            sum += d;
            // Off-edge pixels (both fully in or fully out in both images)
            // must agree exactly.
            final s = stripBytes[i], m = msaaBytes[i];
            final extremeBoth = (s == 0 || s == 255) && (m == 0 || m == 255);
            if (extremeBoth && d > 0) maxInterior = math.max(maxInterior, d);
          }
        }
      }
      final mean = sum / (w * h * 4);
      expect(buf.length, greaterThan(0));
      expect(mean, lessThan(2.5),
          reason: 'strips vs MSAA mean channel diff should be edge-only');
      expect(maxInterior, 0,
          reason: 'fully-covered/empty pixels must match exactly');

      // Hollow core (even-odd) and solid arm spot checks against both.
      int at(Uint8List b, int x, int y, int c) => b[(y * w + x) * 4 + c];
      expect(at(stripBytes, 64, 64, 3), 0); // core is hollow
      expect(at(msaaBytes, 64, 64, 3), 0);
      expect(at(stripBytes, 64, 20, 3), 255); // top arm solid
      expect(at(msaaBytes, 64, 20, 3), 255);
    });
  });
}
