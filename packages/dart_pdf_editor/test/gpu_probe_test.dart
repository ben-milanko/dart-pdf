// Feasibility probe for the flutter_gpu experiment: checks that the headless
// `flutter test` engine can hand out an Impeller GPU context, allocate a
// texture, run an empty (clear-only) render pass, and read the pixels back.
//
//   fvm flutter test --enable-impeller test/gpu_probe_test.dart
//
// Skips (with a message) when the context is unavailable, so it is safe in a
// normal non-Impeller test run.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

gpu.ShaderLibrary loadPdfShaderBundle() {
  try {
    return gpu.ShaderLibrary.fromAsset(
        'packages/dart_pdf_editor/assets/shaders/pdf_gpu.shaderbundle')!;
  } catch (_) {
    return gpu.ShaderLibrary.fromAsset('assets/shaders/pdf_gpu.shaderbundle')!;
  }
}

void main() {
  testWidgets('flutter_gpu clear + readback works in the tester', (tester) async {
    await tester.runAsync(() async {
      late final gpu.GpuContext context;
      try {
        context = gpu.gpuContext;
        // touching a property forces the lazy native init
        // ignore: unnecessary_statements
        context.defaultColorFormat;
      } catch (e) {
        markTestSkipped('flutter_gpu unavailable in this tester: $e');
        return;
      }
      // ignore: avoid_print
      print('gpu ok: color=${context.defaultColorFormat} '
          'stencil=${context.defaultStencilFormat} '
          'ds=${context.defaultDepthStencilFormat} '
          'msaa=${context.doesSupportOffscreenMSAA}');

      final texture = context.createTexture(gpu.StorageMode.devicePrivate, 4, 4,
          format: context.defaultColorFormat);
      final commandBuffer = context.createCommandBuffer();
      final renderTarget = gpu.RenderTarget.singleColor(
        gpu.ColorAttachment(
          texture: texture,
          clearValue: vm.Vector4(0, 0.5, 1, 1),
        ),
      );
      commandBuffer.createRenderPass(renderTarget);
      commandBuffer.submit();

      final image = texture.asImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      expect(data, isNotNull);
      final b = data!.buffer.asUint8List();
      // ignore: avoid_print
      print('pixel0 rgba: ${b[0]} ${b[1]} ${b[2]} ${b[3]}');
      expect(b[2], greaterThan(200)); // blue-ish clear made it back
    });
  });

  testWidgets('shader bundle draws a solid quad with correct orientation',
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
      final library = loadPdfShaderBundle();
      final vert = library['PdfSolidVertex']!;
      final frag = library['PdfSolidFragment']!;
      final pipeline = context.createRenderPipeline(vert, frag);

      const w = 8, h = 8;
      final texture = context.createTexture(gpu.StorageMode.devicePrivate, w, h,
          format: context.defaultColorFormat);
      final commandBuffer = context.createCommandBuffer();
      final pass = commandBuffer.createRenderPass(gpu.RenderTarget.singleColor(
        gpu.ColorAttachment(
            texture: texture, clearValue: vm.Vector4(0, 0, 0, 0)),
      ));

      // Two triangles covering the TOP-LEFT quadrant in our intended device
      // space (y-down pixels -> NDC y-up flip done CPU-side). Red, opaque,
      // premultiplied. Device px (0..4, 0..4) => NDC x in [-1,0], y in [0,1].
      final v = Float32List.fromList([
        // x, y, r, g, b, a
        -1, 1, 1, 0, 0, 1,
        0, 1, 1, 0, 0, 1,
        0, 0, 1, 0, 0, 1,
        -1, 1, 1, 0, 0, 1,
        0, 0, 1, 0, 0, 1,
        -1, 0, 1, 0, 0, 1,
      ]);
      final hostBuffer = context.createHostBuffer();
      pass
        ..bindPipeline(pipeline)
        ..bindVertexBuffer(hostBuffer.emplace(v.buffer.asByteData()), 6)
        ..draw();
      commandBuffer.submit();

      final image = texture.asImage();
      final data =
          (await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!;
      final bytes = data.buffer.asUint8List();
      int px(int x, int y, int c) => bytes[(y * w + x) * 4 + c];
      // ignore: avoid_print
      print('topleft=${px(1, 1, 0)},${px(1, 1, 3)} '
          'bottomleft=${px(1, 6, 0)},${px(1, 6, 3)} '
          'topright=${px(6, 1, 0)},${px(6, 1, 3)}');
      expect(px(1, 1, 0), greaterThan(200)); // top-left red
      expect(px(6, 6, 3), equals(0)); // bottom-right untouched
    });
  });
}
