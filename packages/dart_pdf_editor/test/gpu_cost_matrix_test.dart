// Synthetic cost matrix for flutter_gpu render passes: isolates the fixed
// per-pass cost (MSAA, size) from per-draw and per-state-change costs, timed
// as submit -> asImage -> toByteData (the realized-raster fence).
//
//   fvm flutter test --enable-impeller --enable-flutter-gpu \
//     test/gpu_cost_matrix_test.dart
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'gpu_probe_test.dart' show loadPdfShaderBundle;

void main() {
  testWidgets('gpu cost matrix', (tester) async {
    await tester.runAsync(() async {
      late final gpu.GpuContext context;
      try {
        context = gpu.gpuContext;
        // ignore: unnecessary_statements
        context.defaultColorFormat;
      } catch (e) {
        markTestSkipped('flutter_gpu unavailable: $e');
        return;
      }
      final library = loadPdfShaderBundle();
      final solid = context.createRenderPipeline(
          library['PdfSolidVertex']!, library['PdfSolidFragment']!);
      final stencil = context.createRenderPipeline(
          library['PdfStencilVertex']!, library['PdfStencilFragment']!);

      gpu.Texture? cachedColor, cachedStencil;

      Future<double> run(String label,
          {required int w,
          required int h,
          required bool msaa,
          int solidDraws = 0,
          int stencilPairs = 0,
          int trisPerDraw = 1,
          bool reuseTargets = false,
          int samples = 4,
          gpu.StorageMode msaaStorage = gpu.StorageMode.deviceTransient,
          bool dontCareLoad = false}) async {
        var bestMs = double.infinity;
        for (var pass = 0; pass < 3; pass++) {
          final resolve = context.createTexture(
              gpu.StorageMode.devicePrivate, w, h,
              format: context.defaultColorFormat);
          final gpu.Texture color;
          final gpu.Texture stencilTex;
          if (reuseTargets && msaa) {
            cachedColor ??= context.createTexture(msaaStorage, w, h,
                format: context.defaultColorFormat, sampleCount: samples);
            cachedStencil ??= context.createTexture(msaaStorage, w, h,
                format: context.defaultStencilFormat, sampleCount: samples);
            color = cachedColor!;
            stencilTex = cachedStencil!;
          } else {
            color = msaa
                ? context.createTexture(msaaStorage, w, h,
                    format: context.defaultColorFormat, sampleCount: samples)
                : resolve;
            stencilTex = context.createTexture(
                gpu.StorageMode.deviceTransient, w, h,
                format: context.defaultStencilFormat,
                sampleCount: msaa ? samples : 1);
          }
          final commandBuffer = context.createCommandBuffer();
          final rp = commandBuffer.createRenderPass(gpu.RenderTarget(
            colorAttachments: [
              gpu.ColorAttachment(
                texture: color,
                resolveTexture: msaa ? resolve : null,
                loadAction: dontCareLoad
                    ? gpu.LoadAction.dontCare
                    : gpu.LoadAction.clear,
                clearValue: vm.Vector4(1, 1, 1, 1),
                storeAction: msaa
                    ? gpu.StoreAction.multisampleResolve
                    : gpu.StoreAction.store,
              ),
            ],
            depthStencilAttachment: gpu.DepthStencilAttachment(
                texture: stencilTex, stencilClearValue: 0),
          ));
          rp
            ..setCullMode(gpu.CullMode.none)
            ..setPrimitiveType(gpu.PrimitiveType.triangle);
          final hostBuffer = context.createHostBuffer();

          // tiny triangles near the origin; per-vertex: x,y,r,g,b,a
          final solidVerts = Float32List.fromList(List.generate(
              trisPerDraw * 3 * 6,
              (i) => switch (i % 6) {
                    0 => -1 + (i % 100) * 0.001,
                    1 => 1 - (i % 100) * 0.001,
                    2 => 0.5,
                    3 => 0.5,
                    4 => 0.5,
                    _ => 1.0,
                  }));
          final stencilVerts = Float32List.fromList(List.generate(
              trisPerDraw * 3 * 2,
              (i) => (i % 2 == 0 ? -1 : 1) + (i % 50) * 0.001));

          if (dontCareLoad) {
            // background as one oversized fullscreen triangle instead of a
            // load-action clear
            final quad = Float32List.fromList([
              -1, -1, 1, 1, 1, 1, //
              3, -1, 1, 1, 1, 1, //
              -1, 3, 1, 1, 1, 1,
            ]);
            rp
              ..bindPipeline(solid)
              ..setColorBlendEnable(true)
              ..bindVertexBuffer(
                  hostBuffer.emplace(quad.buffer.asByteData()), 3)
              ..draw();
          }
          for (var i = 0; i < solidDraws; i++) {
            rp
              ..bindPipeline(solid)
              ..setColorBlendEnable(true)
              ..bindVertexBuffer(
                  hostBuffer.emplace(solidVerts.buffer.asByteData()),
                  trisPerDraw * 3)
              ..draw();
          }
          for (var i = 0; i < stencilPairs; i++) {
            rp
              ..bindPipeline(stencil)
              ..setStencilConfig(gpu.StencilConfig(
                compareFunction: gpu.CompareFunction.always,
                depthStencilPassOperation: gpu.StencilOperation.invert,
              ))
              ..bindVertexBuffer(
                  hostBuffer.emplace(stencilVerts.buffer.asByteData()),
                  trisPerDraw * 3)
              ..draw()
              ..bindPipeline(solid)
              ..setStencilConfig(gpu.StencilConfig(
                compareFunction: gpu.CompareFunction.notEqual,
                depthStencilPassOperation: gpu.StencilOperation.zero,
              ))
              ..bindVertexBuffer(
                  hostBuffer.emplace(solidVerts.buffer.asByteData()),
                  trisPerDraw * 3)
              ..draw();
          }

          final sw = Stopwatch()..start();
          commandBuffer.submit();
          final image = resolve.asImage();
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
          final ms = sw.elapsedMicroseconds / 1000;
          image.dispose();
          if (ms < bestMs) bestMs = ms;
        }
        // ignore: avoid_print
        print('$label: ${bestMs.toStringAsFixed(1)}ms');
        return bestMs;
      }

      await run('A  2382x1684 msaa4, 0 draws', w: 2382, h: 1684, msaa: true);
      await run('B  2382x1684 msaa4, 2000 stencil+cover pairs',
          w: 2382, h: 1684, msaa: true, stencilPairs: 2000);
      await run('C  2382x1684 no-msaa, 0 draws',
          w: 2382, h: 1684, msaa: false);
      await run('D  1191x842 msaa4, 0 draws', w: 1191, h: 842, msaa: true);
      await run('E  2382x1684 msaa4, 2000 solid draws (no state churn)',
          w: 2382, h: 1684, msaa: true, solidDraws: 2000);
      await run('F  2382x1684 msaa4, 200 stencil+cover pairs',
          w: 2382, h: 1684, msaa: true, stencilPairs: 200);
      await run('G  2382x1684 msaa4, 1 solid draw of 6000 tris',
          w: 2382, h: 1684, msaa: true, solidDraws: 1, trisPerDraw: 6000);
      await run('H  2382x1684 msaa4, 0 draws, reused msaa+stencil',
          w: 2382, h: 1684, msaa: true, reuseTargets: true);
      await run('I  2382x1684 msaa4, 2000 solid draws, reused targets',
          w: 2382, h: 1684, msaa: true, solidDraws: 2000, reuseTargets: true);
      // Probing the residual ~10ms: is it the clear, the storage mode, or
      // the resolve itself?
      await run('J  msaa4 reused, dontCare load + fullscreen quad',
          w: 2382, h: 1684, msaa: true, reuseTargets: true,
          dontCareLoad: true);
      cachedColor = cachedStencil = null;
      try {
        await run('K  msaa2 reused', w: 2382, h: 1684, msaa: true,
            reuseTargets: true, samples: 2);
      } catch (e) {
        // ignore: avoid_print
        print('K  msaa2: unsupported ($e)');
      }
      cachedColor = cachedStencil = null;
      try {
        await run('L  msaa4 devicePrivate reused', w: 2382, h: 1684,
            msaa: true, reuseTargets: true,
            msaaStorage: gpu.StorageMode.devicePrivate);
      } catch (e) {
        // ignore: avoid_print
        print('L  devicePrivate msaa: unsupported ($e)');
      }
      cachedColor = cachedStencil = null;
      // M: how much is the readback machinery itself? Same as C but half res.
      await run('M  1191x842 no-msaa, 0 draws', w: 1191, h: 842, msaa: false);
    });
  }, timeout: const Timeout(Duration(minutes: 10)));
}
