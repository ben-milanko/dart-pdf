// Page rasterization through the experimental flutter_gpu backend.
//
// Mirrors PdfPageRenderer.renderImage's structure (parse once, scan-collect
// images, decode async, then paint) but paints with [GpuPdfDevice] into an
// offscreen MSAA texture instead of recording a ui.Canvas picture, and
// returns the resolved texture as a ui.Image.
//
// Requires Impeller and the Flutter GPU manifest flag; under `flutter test`
// pass `--enable-impeller --enable-flutter-gpu`.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show Color, Size;
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../image_decoder.dart';
import '../renderer.dart' show PdfPageRenderer;
import 'gpu_device.dart';

/// Rasterizes PDF pages with flutter_gpu. Experimental - see [GpuPdfDevice]
/// for the fidelity gaps.
class PdfGpuPageRenderer {
  PdfGpuPageRenderer._();

  /// Uploaded page-image textures, keyed like the decoded-image cache
  /// ([pdfImageKey]) and bounded by entry count. Uploads are the GPU
  /// equivalent of the decode cache: repeated renders of the same document
  /// reuse the texture instead of re-reading the ui.Image pixels back.
  static final _textureCache = <Object, gpu.Texture>{};
  static const _textureCacheCap = 128;

  /// Counters accumulated by the last [renderImage] call - the fidelity
  /// honesty log (blend modes approximated, masks skipped, ...).
  static Map<String, int> lastUnsupported = const {};

  static void clearTextureCache() => _textureCache.clear();

  /// Renders [page] to a bitmap at [pixelRatio] (2 = 144 DPI), matching
  /// [PdfPageRenderer.renderImage]'s contract.
  static Future<ui.Image> renderImage(PdfPage page,
      {double pixelRatio = 1,
      Color pageColor = const Color(0xFFFFFFFF),
      bool annotations = true}) async {
    final context = gpu.gpuContext;
    final pipelines = PdfGpuPipelines.instance(context);
    final cos = page.document.cos;

    final pageOps = ContentStreamParser.parse(page.contentBytes());

    // Same two-walk shape as the canvas renderer: a scan-only pass finds the
    // images so their (async) decode can happen before the paint walk.
    final collector = ImageCollector();
    final collecting =
        PdfInterpreter(cos: cos, device: collector, scanImagesOnly: true)
          ..drawPageOperations(page, pageOps);
    if (annotations) collecting.drawAnnotations(page);
    final images = await decodeImages(cos, collector.streams,
        cache: PdfImageCache.instance);
    final textures = await _texturesFor(context, collector.streams, images);
    for (final image in images.values) {
      image.dispose();
    }

    final box = page.cropBox;
    final size = PdfPageRenderer.pageSize(page);
    final width = (size.width * pixelRatio).ceil().clamp(1, 1 << 14);
    final height = (size.height * pixelRatio).ceil().clamp(1, 1 << 14);

    final useMsaa = context.doesSupportOffscreenMSAA;
    final colorFormat = context.defaultColorFormat;
    final resolve = context.createTexture(
        gpu.StorageMode.devicePrivate, width, height,
        format: colorFormat);
    final color = useMsaa
        ? context.createTexture(gpu.StorageMode.deviceTransient, width, height,
            format: colorFormat, sampleCount: 4)
        : resolve;
    final stencil = context.createTexture(
        gpu.StorageMode.deviceTransient, width, height,
        format: context.defaultStencilFormat, sampleCount: useMsaa ? 4 : 1);

    // paper: PDF pages have no background of their own
    final clear = vm.Vector4(
      pageColor.r * pageColor.a,
      pageColor.g * pageColor.a,
      pageColor.b * pageColor.a,
      pageColor.a,
    );

    final commandBuffer = context.createCommandBuffer();
    final pass = commandBuffer.createRenderPass(gpu.RenderTarget(
      colorAttachments: [
        gpu.ColorAttachment(
          texture: color,
          resolveTexture: useMsaa ? resolve : null,
          clearValue: clear,
          storeAction: useMsaa
              ? gpu.StoreAction.multisampleResolve
              : gpu.StoreAction.store,
        ),
      ],
      depthStencilAttachment: gpu.DepthStencilAttachment(
        texture: stencil,
        stencilClearValue: 0,
      ),
    ));

    final hostBuffer = context.createHostBuffer();
    final device = GpuPdfDevice(
      context: context,
      pass: pass,
      hostBuffer: hostBuffer,
      pipelines: pipelines,
      pageToDevice: _pageToDevice(page, box, size, pixelRatio),
      widthPx: width,
      heightPx: height,
      textures: textures,
    );

    final painting = PdfInterpreter(cos: cos, device: device)
      ..drawPageOperations(page, pageOps);
    if (annotations) painting.drawAnnotations(page);
    device.finish();
    commandBuffer.submit();
    lastUnsupported = device.unsupported;

    return resolve.asImage();
  }

  /// Page space (y-up, crop-box origin) -> device pixels (y-down), mirroring
  /// the canvas renderer's _applyPageTransform + pixelRatio scale.
  static PdfMatrix _pageToDevice(
      PdfPage page, PdfRect box, Size size, double pixelRatio) {
    var m = const PdfMatrix(1, 0, 0, 1, 0, 0)
        .concat(PdfMatrix.translation(-box.left, -box.bottom))
        .concat(const PdfMatrix(1, 0, 0, -1, 0, 0))
        .concat(PdfMatrix.translation(0, box.height));
    m = switch (page.rotation) {
      90 => m.concat(PdfMatrix(0, 1, -1, 0, size.width, 0)),
      180 => m.concat(PdfMatrix(-1, 0, 0, -1, size.width, size.height)),
      270 => m.concat(PdfMatrix(0, -1, 1, 0, 0, size.height)),
      _ => m,
    };
    return m.concat(PdfMatrix.scaled(pixelRatio, pixelRatio));
  }

  /// Uploads decoded [images] as premultiplied RGBA textures, reusing the
  /// bounded cache across renders (keyed by content like the decode cache).
  static Future<Map<Object, gpu.Texture>> _texturesFor(
      gpu.GpuContext context,
      List<PdfImageRequest> requests,
      Map<Object, ui.Image> images) async {
    final out = <Object, gpu.Texture>{};
    for (final request in requests) {
      final key = pdfImageKey(request);
      if (out.containsKey(key)) continue;
      final cached = _textureCache[key];
      if (cached != null) {
        out[key] = cached;
        continue;
      }
      final image = images[key];
      if (image == null) continue;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) continue;
      final texture = context.createTexture(
          gpu.StorageMode.hostVisible, image.width, image.height,
          format: gpu.PixelFormat.r8g8b8a8UNormInt);
      texture.overwrite(data);
      out[key] = texture;
      _textureCache[key] = texture;
      if (_textureCache.length > _textureCacheCap) {
        _textureCache.remove(_textureCache.keys.first);
      }
    }
    return out;
  }
}

/// Convenience for tests: renders and reads back raw RGBA in one step.
Future<Uint8List> gpuRenderPageBytes(PdfPage page,
    {double pixelRatio = 1}) async {
  final image =
      await PdfGpuPageRenderer.renderImage(page, pixelRatio: pixelRatio);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}
