// One flushed batch of sparse strips, converted from the StripGenerator's
// SoA buffer into the exact upload shapes the shader path draws: quad
// vertices (positions in device pixels, texcoords addressing the alpha
// atlas, per-vertex ARGB colors) plus the batch's rgba8888 alpha atlas.
//
// Texcoord contract (mirrored by shaders/pdf_strips.frag): u interpolates
// the global alpha-texel index across the quad (fragment centers land at
// index + .5), v is the local strip row - [0,4) mixed, [4,8) solid.
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdf_graphics/raster.dart';

/// Alpha atlas width in texels (4 bytes each -> 4 KB rows).
const int stripAtlasWidth = 1024;

/// ui.Vertices indices are Uint16, so one draw holds at most
/// 65535 / 4 quads; batches chunk at this many strips per draw.
const int stripMaxQuadsPerDraw = 16000;

/// A flush batch: everything needed to draw its strips with one shader
/// paint - [chunks] drawVertices calls sharing one [atlas].
class StripBatch {
  StripBatch._(this.chunks, this.atlasPixels, this.atlasWidth,
      this.atlasHeight, this.stripCount);

  final List<ui.Vertices> chunks;
  final Uint8List atlasPixels; // rgba8888, atlasWidth * atlasHeight * 4
  final int atlasWidth;
  final int atlasHeight;
  final int stripCount;

  /// Decoded alpha atlas; set by [decodeAtlas], disposed by [dispose].
  ui.Image? atlas;

  /// Snapshots [strips] (the generator reuses its buffers, so all data is
  /// copied) into draw-ready form, or null when the buffer is empty.
  ///
  /// The per-strip color word is passed through to the vertex colors
  /// unchanged and must therefore be straight (non-premultiplied) ARGB -
  /// Skia premultiplies vertex colors before BlendMode.modulate multiplies
  /// them with the shader's coverage.
  static StripBatch? of(StripBuffer strips) {
    final n = strips.length;
    if (n == 0) return null;

    final chunks = <ui.Vertices>[];
    for (var start = 0; start < n; start += stripMaxQuadsPerDraw) {
      final count =
          (n - start) < stripMaxQuadsPerDraw ? (n - start) : stripMaxQuadsPerDraw;
      final positions = Float32List(count * 8);
      final texs = Float32List(count * 8);
      final colors = Int32List(count * 4);
      final indices = Uint16List(count * 6);
      for (var k = 0; k < count; k++) {
        final i = start + k;
        final xy = strips.xy[i];
        final x = (xy & 0xFFFF).toDouble();
        final y = (xy >> 16).toDouble();
        final wf = strips.widthFlags[i];
        final w = (wf & 0xFFFF).toDouble();
        final solid = wf & stripFlagSolid != 0;

        final p = k * 8;
        positions[p] = x;
        positions[p + 1] = y;
        positions[p + 2] = x + w;
        positions[p + 3] = y;
        positions[p + 4] = x;
        positions[p + 5] = y + 4;
        positions[p + 6] = x + w;
        positions[p + 7] = y + 4;

        // u: global texel index range; v: [0,4) mixed, [4,8) solid. Solid
        // quads keep u in [0,w) so the (ignored) sample stays in-atlas.
        final u0 = solid ? 0.0 : strips.alphaOffset[i].toDouble();
        final u1 = u0 + w;
        final v0 = solid ? 4.0 : 0.0;
        final v1 = v0 + 4;
        texs[p] = u0;
        texs[p + 1] = v0;
        texs[p + 2] = u1;
        texs[p + 3] = v0;
        texs[p + 4] = u0;
        texs[p + 5] = v1;
        texs[p + 6] = u1;
        texs[p + 7] = v1;

        final color = strips.color[i];
        final c = k * 4;
        colors[c] = color;
        colors[c + 1] = color;
        colors[c + 2] = color;
        colors[c + 3] = color;

        final vBase = k * 4;
        final ix = k * 6;
        indices[ix] = vBase;
        indices[ix + 1] = vBase + 1;
        indices[ix + 2] = vBase + 2;
        indices[ix + 3] = vBase + 1;
        indices[ix + 4] = vBase + 3;
        indices[ix + 5] = vBase + 2;
      }
      chunks.add(ui.Vertices.raw(ui.VertexMode.triangles, positions,
          textureCoordinates: texs, colors: colors, indices: indices));
    }

    // Alpha atlas: column texels row-major by global index, final row
    // zero-padded. Always at least one texel so solid-only batches still
    // have a valid sampler target.
    final cols = strips.alphaColumns;
    final rows = cols == 0 ? 1 : (cols + stripAtlasWidth - 1) ~/ stripAtlasWidth;
    final pixels = Uint8List(stripAtlasWidth * rows * 4);
    if (cols > 0) {
      pixels.setRange(0, cols * 4, strips.alphas);
    }
    return StripBatch._(chunks, pixels, stripAtlasWidth, rows, n);
  }

  /// Decodes [atlasPixels] into the GPU-sampled [atlas] image. rgba8888
  /// via decodeImageFromPixels is byte-exact (M0-verified); asynchronous,
  /// so the strip device defers all drawing to its finish() replay.
  Future<void> decodeAtlas() {
    final completer = Completer<void>();
    ui.decodeImageFromPixels(
        atlasPixels, atlasWidth, atlasHeight, ui.PixelFormat.rgba8888,
        (image) {
      atlas = image;
      completer.complete();
    });
    return completer.future;
  }

  void dispose() {
    atlas?.dispose();
    atlas = null;
    for (final v in chunks) {
      v.dispose();
    }
  }
}
