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

/// Where one GPU render's wall time went, plus the device's work counters -
/// the profiling story behind the benchmark numbers.
class PdfGpuRenderStats {
  double parseMs = 0;
  double collectMs = 0;
  double decodeMs = 0;
  double uploadMs = 0;

  /// The interpreter walk through [GpuPdfDevice] - all CPU tessellation and
  /// command encoding, but no GPU execution.
  double paintMs = 0;

  /// commandBuffer.submit + resolve-texture wrap. GPU execution overlaps the
  /// caller's readback, so the true GPU cost shows up in the caller's
  /// toByteData wait, not here.
  double submitMs = 0;

  Map<String, int> counters = const {};

  @override
  String toString() =>
      'parse=${parseMs.toStringAsFixed(1)} collect=${collectMs.toStringAsFixed(1)} '
      'decode=${decodeMs.toStringAsFixed(1)} upload=${uploadMs.toStringAsFixed(1)} '
      'paint=${paintMs.toStringAsFixed(1)} submit=${submitMs.toStringAsFixed(1)} '
      '$counters';
}

/// Rasterizes PDF pages with flutter_gpu. Experimental - see [GpuPdfDevice]
/// for the fidelity gaps.
class PdfGpuPageRenderer {
  PdfGpuPageRenderer._();

  /// Stats for the most recent [renderImage] call.
  static PdfGpuRenderStats lastStats = PdfGpuRenderStats();

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

  /// Cached per-page render attachments (MSAA color + stencil), reused while
  /// consecutive pages share a pixel size. The resolve texture is never
  /// cached - its ui.Image belongs to the caller.
  static _PageTargets? _cachedTargets;
  static gpu.HostBuffer? _hostBuffer;

  /// Renders [page] to a bitmap at [pixelRatio] (2 = 144 DPI), matching
  /// [PdfPageRenderer.renderImage]'s contract.
  /// Whether pages render into a 4x MSAA target (edge antialiasing, matching
  /// the canvas renderer's quality). Costs ~10ms/page of resolve at A3 sizes
  /// on this SDK - flutter_gpu's deviceTransient attachments are not
  /// memoryless, so the resolve round-trips real memory. Off = aliased
  /// edges, minimum fixed cost.
  static bool msaaEnabled = true;

  static Future<ui.Image> renderImage(PdfPage page,
      {double pixelRatio = 1,
      Color pageColor = const Color(0xFFFFFFFF),
      bool annotations = true}) async {
    final context = gpu.gpuContext;
    final pipelines = PdfGpuPipelines.instance(context);
    final cos = page.document.cos;

    final stats = PdfGpuRenderStats();
    final clock = Stopwatch()..start();
    double lap() {
      final ms = clock.elapsedMicroseconds / 1000;
      clock.reset();
      return ms;
    }

    final pageOps = ContentStreamParser.parse(page.contentBytes());
    stats.parseMs = lap();

    // Same two-walk shape as the canvas renderer: a scan-only pass finds the
    // images so their (async) decode can happen before the paint walk.
    final collector = ImageCollector();
    final collecting =
        PdfInterpreter(cos: cos, device: collector, scanImagesOnly: true)
          ..drawPageOperations(page, pageOps);
    if (annotations) collecting.drawAnnotations(page);
    stats.collectMs = lap();
    final images = await decodeImages(cos, collector.streams,
        cache: PdfImageCache.instance);
    stats.decodeMs = lap();
    final textures = await _texturesFor(context, collector.streams, images);
    for (final image in images.values) {
      image.dispose();
    }
    stats.uploadMs = lap();

    final box = page.cropBox;
    final size = PdfPageRenderer.pageSize(page);
    final width = (size.width * pixelRatio).ceil().clamp(1, 1 << 14);
    final height = (size.height * pixelRatio).ceil().clamp(1, 1 << 14);

    final useMsaa = msaaEnabled && context.doesSupportOffscreenMSAA;
    final colorFormat = context.defaultColorFormat;
    // The resolve texture is fresh per render (its ui.Image is handed to the
    // caller), but the MSAA color + stencil attachments are consumed inside
    // the pass, so they cache by size across renders - allocating the
    // 4-sample surfaces costs ~12ms/page at 2382x1684 (gpu_cost_matrix).
    final resolve = context.createTexture(
        gpu.StorageMode.devicePrivate, width, height,
        format: colorFormat);
    final gpu.Texture color;
    final gpu.Texture stencil;
    if (_cachedTargets == null ||
        _cachedTargets!.width != width ||
        _cachedTargets!.height != height ||
        _cachedTargets!.msaa != useMsaa) {
      _cachedTargets = _PageTargets(
        width: width,
        height: height,
        msaa: useMsaa,
        color: useMsaa
            ? context.createTexture(
                gpu.StorageMode.deviceTransient, width, height,
                format: colorFormat, sampleCount: 4)
            : null,
        stencil: context.createTexture(
            gpu.StorageMode.deviceTransient, width, height,
            format: context.defaultStencilFormat, sampleCount: useMsaa ? 4 : 1),
      );
    }
    color = _cachedTargets!.color ?? resolve;
    stencil = _cachedTargets!.stencil;

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

    // The host bump allocator cycles a 4-frame ring on reset(), so reusing
    // one across renders is safe with in-flight GPU work and skips the
    // per-page block allocations.
    final hostBuffer = (_hostBuffer ??= context.createHostBuffer())..reset();
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

    lap(); // exclude target/pass setup from the paint phase
    final painting = PdfInterpreter(cos: cos, device: device)
      ..drawPageOperations(page, pageOps);
    if (annotations) painting.drawAnnotations(page);
    device.finish();
    stats.paintMs = lap();
    commandBuffer.submit();
    lastUnsupported = device.unsupported;
    final image = resolve.asImage();
    stats.submitMs = lap();
    stats.counters = device.stats;
    lastStats = stats;
    return image;
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

class _PageTargets {
  _PageTargets({
    required this.width,
    required this.height,
    required this.msaa,
    required this.color,
    required this.stencil,
  });

  final int width;
  final int height;
  final bool msaa;
  final gpu.Texture? color; // null when MSAA is unsupported
  final gpu.Texture stencil;
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
