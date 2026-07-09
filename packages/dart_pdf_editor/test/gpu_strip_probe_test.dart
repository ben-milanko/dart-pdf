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
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/gpu.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';
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
    alphaOffset.add(stripSolidOffset);
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
          xy: Int32List.fromList(strips.xy),
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
}
