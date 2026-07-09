// Sparse-strip rendering for the experimental flutter_gpu backend
// (vello_hybrid-style): the CPU rasterizes path coverage into 4px-tall
// strips, the GPU draws each strip as one alpha-blended quad whose fragments
// scale the per-vertex premultiplied color by a coverage byte sampled from
// an RGBA8 alpha atlas. AA quality at aliased cost - no stencil-then-cover,
// no MSAA resolve.
//
// This file owns only the GPU side: [StripBatch] accepts the strip
// generator's raw SoA arrays (a [StripBuffer] from
// package:pdf_graphics/raster.dart, or hand-built in tests), builds the
// vertex buffer + alpha atlas, and issues one draw. GpuPdfDevice routes
// fills through it when [GpuPdfDevice.strips] is set.
//
// SoA layout contract (the shared core's StripBuffer layout):
//  - xy:          Uint32List, per strip `x | (y << 16)` - unsigned 16-bit
//                 device-pixel coordinates of the strip's top-left corner.
//  - widthFlags:  Uint32List, low 16 bits = strip width in px (generator
//                 flags in the high bits are ignored here).
//  - alphaOffset: Uint32List, index (in texels == coverage columns) of the
//                 strip's first column in [alphas]; [stripSolidSentinel]
//                 marks a solid strip (coverage 1, no alpha data).
//  - color:       Uint32List, premultiplied RGBA8 packed little-endian:
//                 `r | g << 8 | b << 16 | a << 24`.
//  - alphas:      Uint8List, column-major coverage - 4 consecutive bytes are
//                 one 1x4 px column (byte 0 = the strip's top row), uploaded
//                 verbatim as one RGBA8888 texel.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:pdf_graphics/raster.dart' show stripSolidSentinel;

import 'gpu_device.dart' show PdfGpuPipelines;

/// Builds and draws one batch of coverage strips: a shared vertex buffer
/// (two triangles per strip) plus one alpha-atlas texture, drawn with the
/// `strip` pipeline in a single alpha-blended call - painter's order within
/// the buffer, no depth/stencil/MSAA involvement.
///
/// Reusable: [setStrips] grows the vertex scratch monotonically and
/// allocates a fresh atlas texture per call (atlas contents differ every
/// batch; pooling can come with the device wiring if allocation shows up).
class StripBatch {
  StripBatch({
    required this.context,
    required this.pipelines,
    this.atlasWidth = 1024,
  }) : assert(atlasWidth > 0);

  final gpu.GpuContext context;
  final PdfGpuPipelines pipelines;

  /// Alpha-atlas row width in texels. Texel index i lives at atlas
  /// (i % atlasWidth, i ~/ atlasWidth).
  final int atlasWidth;

  // x, y, texelIndex, yFlags, r, g, b, a
  static const int _floatsPerVertex = 8;
  static const int _floatsPerStrip = 6 * _floatsPerVertex;

  Float32List _vertices = Float32List(0);
  int _vertexFloats = 0;
  int _strips = 0;
  gpu.Texture? _atlas;
  int _atlasHeight = 0;

  /// Number of strips staged by the last [setStrips].
  int get stripCount => _strips;

  /// Stages [count] strips from the generator's SoA arrays: builds the
  /// interleaved vertex data and uploads the alpha atlas.
  /// [alphaTexels] bounds the live prefix of [alphas] (in texels); by
  /// default the whole list is uploaded.
  void setStrips({
    required int count,
    required Uint32List xy,
    required Uint32List widthFlags,
    required Uint32List alphaOffset,
    required Uint32List color,
    required Uint8List alphas,
    int? alphaTexels,
  }) {
    _strips = count;
    final floats = count * _floatsPerStrip;
    if (_vertices.length < floats) {
      _vertices = Float32List(math.max(floats, _vertices.length * 2));
    }
    _vertexFloats = floats;
    final v = _vertices;
    var o = 0;
    for (var i = 0; i < count; i++) {
      final p = xy[i];
      final x0 = (p & 0xFFFF).toDouble();
      final y0 = ((p >> 16) & 0xFFFF).toDouble();
      final w = (widthFlags[i] & 0xFFFF).toDouble();
      final x1 = x0 + w;
      final y1 = y0 + 4.0;
      final off = alphaOffset[i];
      final solid = off == stripSolidSentinel;
      // Solid strips never fetch, but keep the interpolated index in-range
      // so the (still executed) sample stays defined.
      final t0 = solid ? 0.0 : off.toDouble();
      final t1 = t0 + w;
      final yTop = solid ? 4.0 : 0.0;
      final yBot = yTop + 4.0;
      final c = color[i];
      final r = (c & 0xFF) / 255.0;
      final g = ((c >> 8) & 0xFF) / 255.0;
      final b = ((c >> 16) & 0xFF) / 255.0;
      final a = ((c >> 24) & 0xFF) / 255.0;
      // Two CCW triangles: (x0,y0)(x1,y0)(x1,y1) + (x0,y0)(x1,y1)(x0,y1).
      // Straight-line writes (hot path: tens of thousands of strips/page).
      v[o] = x0; v[o + 1] = y0; v[o + 2] = t0; v[o + 3] = yTop;
      v[o + 4] = r; v[o + 5] = g; v[o + 6] = b; v[o + 7] = a;
      v[o + 8] = x1; v[o + 9] = y0; v[o + 10] = t1; v[o + 11] = yTop;
      v[o + 12] = r; v[o + 13] = g; v[o + 14] = b; v[o + 15] = a;
      v[o + 16] = x1; v[o + 17] = y1; v[o + 18] = t1; v[o + 19] = yBot;
      v[o + 20] = r; v[o + 21] = g; v[o + 22] = b; v[o + 23] = a;
      v[o + 24] = x0; v[o + 25] = y0; v[o + 26] = t0; v[o + 27] = yTop;
      v[o + 28] = r; v[o + 29] = g; v[o + 30] = b; v[o + 31] = a;
      v[o + 32] = x1; v[o + 33] = y1; v[o + 34] = t1; v[o + 35] = yBot;
      v[o + 36] = r; v[o + 37] = g; v[o + 38] = b; v[o + 39] = a;
      v[o + 40] = x0; v[o + 41] = y1; v[o + 42] = t0; v[o + 43] = yBot;
      v[o + 44] = r; v[o + 45] = g; v[o + 46] = b; v[o + 47] = a;
      o += _floatsPerStrip;
    }

    final texels = alphaTexels ?? alphas.length ~/ 4;
    _atlasHeight = math.max(1, (texels + atlasWidth - 1) ~/ atlasWidth);
    final rowBytes = atlasWidth * 4;
    final padded = Uint8List(rowBytes * _atlasHeight);
    padded.setRange(0, texels * 4, alphas);
    final atlas = context.createTexture(
        gpu.StorageMode.hostVisible, atlasWidth, _atlasHeight,
        format: gpu.PixelFormat.r8g8b8a8UNormInt);
    atlas.overwrite(ByteData.sublistView(padded));
    _atlas = atlas;
  }

  /// Encodes the staged strips as ONE draw into [pass]. The caller owns the
  /// pass; this sets the strip pipeline, src-over blending, and its own
  /// bindings, so a state-tracking caller (GpuPdfDevice) must invalidate its
  /// cached pipeline/blend state afterwards.
  void encode(gpu.RenderPass pass, gpu.HostBuffer hostBuffer,
      {required int widthPx, required int heightPx}) {
    if (_strips == 0) return;
    final atlas = _atlas;
    if (atlas == null) return;

    // 16-byte-padded uniform blocks, matching the other FragInfo uploads.
    final vertInfo = Float32List(4)
      ..[0] = widthPx.toDouble()
      ..[1] = heightPx.toDouble();
    final fragInfo = Float32List(4)
      ..[0] = atlasWidth.toDouble()
      ..[1] = _atlasHeight.toDouble();

    pass
      ..bindPipeline(pipelines.strip)
      ..setColorBlendEnable(true)
      ..setColorBlendEquation(gpu.ColorBlendEquation(
        sourceColorBlendFactor: gpu.BlendFactor.one,
        destinationColorBlendFactor: gpu.BlendFactor.oneMinusSourceAlpha,
        sourceAlphaBlendFactor: gpu.BlendFactor.one,
        destinationAlphaBlendFactor: gpu.BlendFactor.oneMinusSourceAlpha,
      ))
      ..bindUniform(pipelines.stripVertInfo,
          _emplace(hostBuffer, vertInfo.buffer.asByteData()))
      ..bindUniform(pipelines.stripFragInfo,
          _emplace(hostBuffer, fragInfo.buffer.asByteData()))
      ..bindTexture(pipelines.stripSampler, atlas,
          sampler: gpu.SamplerOptions(
              minFilter: gpu.MinMagFilter.nearest,
              magFilter: gpu.MinMagFilter.nearest,
              mipFilter: gpu.MipFilter.nearest,
              widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
              heightAddressMode: gpu.SamplerAddressMode.clampToEdge))
      ..bindVertexBuffer(
          _emplace(hostBuffer,
              ByteData.sublistView(_vertices, 0, _vertexFloats)),
          _strips * 6)
      ..draw();
    pass.clearBindings();
  }

  /// [gpu.HostBuffer.emplace] with the SDK 1MB-block-boundary fallback
  /// (same trap as GpuPdfDevice._emplace): a write that crosses a block
  /// boundary throws, so it gets its own device buffer instead.
  gpu.BufferView _emplace(gpu.HostBuffer hostBuffer, ByteData data) {
    try {
      return hostBuffer.emplace(data);
    } on Exception {
      return gpu.BufferView(
        context.createDeviceBufferWithCopy(data),
        offsetInBytes: 0,
        lengthInBytes: data.lengthInBytes,
      );
    }
  }
}
