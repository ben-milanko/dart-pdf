// One flushed batch of sparse strips in engine-free form: the exact upload
// shapes a `drawVertices` shader path needs (quad positions in device
// pixels, texcoords addressing the alpha atlas, per-vertex ARGB colors,
// triangle indices) plus the batch's rgba8888 alpha atlas bytes. Pure Dart -
// the dart_pdf_editor side wraps these arrays in `ui.Vertices.raw` and
// `decodeImageFromPixels` without touching the data again, and a worker
// isolate can build/ship them without dart:ui.
//
// Texcoord contract (mirrored by shaders/pdf_strips.frag): u interpolates
// the global alpha-texel index across the quad (fragment centers land at
// index + .5), v is the local strip row - [0,4) mixed, [4,8) solid.
import 'dart:typed_data';

import 'strip_generator.dart';

/// Alpha atlas width in texels (4 bytes each -> 4 KB rows).
const int stripAtlasWidth = 1024;

/// `ui.Vertices` indices are Uint16, so one draw holds at most
/// 65535 / 4 quads; batches chunk at this many strips per draw.
const int stripMaxQuadsPerDraw = 16000;

/// Maximum alpha-texel span (u texcoord range) of one draw's strips.
///
/// Impeller does not pass drawVertices texcoords to the fragment shader as
/// raw varyings the way Skia does: it renders the paint's shader into a
/// snapshot texture covering the texcoord BOUNDS and samples that, so a
/// batch whose global alpha indices ran to ~500k texels (a dense CAD sheet)
/// asked for a 500k x 8 snapshot - over the 16384 max texture size - and
/// drew NOTHING (silent blank strips on exactly the pages the router
/// targets). Chunks therefore also split by alpha span, with texcoords
/// REBASED to each chunk's first alpha texel ([StripChunkData.alphaBase],
/// added back by the shader's uBase uniform), keeping every snapshot within
/// 8192 x 8. A single strip wider than the cap still draws alone (its span
/// is bounded by the 16384 viewport clamp, inside the texture limit).
const int stripMaxAlphaColumnsPerDraw = 8192;

/// One `drawVertices`-sized slice of a [StripBatchData]: raw vertex arrays
/// for up to [stripMaxQuadsPerDraw] strip quads.
class StripChunkData {
  StripChunkData(this.alphaBase, this.positions, this.textureCoordinates,
      this.colors, this.indices);

  /// Global alpha-texel index of this chunk's texcoord origin: the shader
  /// computes the atlas index as `uBase + u` so per-chunk u stays within
  /// [stripMaxAlphaColumnsPerDraw] (see that constant for why).
  final int alphaBase;

  /// Quad corner positions in device pixels, 8 floats per strip.
  final Float32List positions;

  /// Texcoords per the atlas contract above, 8 floats per strip.
  final Float32List textureCoordinates;

  /// Straight (non-premultiplied) ARGB per vertex, 4 ints per strip.
  final Int32List colors;

  /// Two triangles per quad, 6 indices per strip.
  final Uint16List indices;
}

/// A flush batch in portable form: everything needed to draw its strips
/// with one shader paint - [chunks] draw calls sharing one alpha atlas -
/// tagged with the [flushOrdinal] of the flush point that emitted it.
class StripBatchData {
  StripBatchData._(this.flushOrdinal, this.chunks, this.atlasPixels,
      this.atlasWidth, this.atlasHeight, this.stripCount);

  /// Test/codec seam: builds a batch from already-materialized arrays.
  StripBatchData.raw(this.flushOrdinal, this.chunks, this.atlasPixels,
      this.atlasWidth, this.atlasHeight, this.stripCount);

  /// Which flush point (0-based, counting every flush point including empty
  /// ones) of the binning walk emitted this batch. A headless binner and a
  /// live device replaying the same command list produce the same ordinals -
  /// the parity invariant precomputed strip plans ride on.
  final int flushOrdinal;

  final List<StripChunkData> chunks;
  final Uint8List atlasPixels; // rgba8888, atlasWidth * atlasHeight * 4
  final int atlasWidth;
  final int atlasHeight;
  final int stripCount;

  /// Snapshots [strips] (the generator reuses its buffers, so all data is
  /// copied) into draw-ready form, or null when the buffer is empty.
  ///
  /// The per-strip color word is passed through to the vertex colors
  /// unchanged and must therefore be straight (non-premultiplied) ARGB -
  /// Skia premultiplies vertex colors before BlendMode.modulate multiplies
  /// them with the shader's coverage.
  static StripBatchData? of(StripBuffer strips, int flushOrdinal) {
    final n = strips.length;
    if (n == 0) return null;

    final chunks = <StripChunkData>[];
    var start = 0;
    while (start < n) {
      // Chunk end: capped by quad count (Uint16 indices) and by the alpha
      // span of the chunk's MIXED strips (Impeller snapshot limit; alpha
      // offsets are appended monotonically, so a streaming scan suffices).
      // Solid strips carry constant u = 0 (their sample is ignored) and
      // never widen the span.
      var base = -1;
      var end = start;
      while (end < n && end - start < stripMaxQuadsPerDraw) {
        final wf = strips.widthFlags[end];
        if (wf & stripFlagSolid == 0) {
          final off = strips.alphaOffset[end];
          final w = wf & 0xFFFF;
          if (base < 0) base = off;
          if (off + w - base > stripMaxAlphaColumnsPerDraw && end > start) {
            break;
          }
        }
        end++;
      }
      if (end == start) end = start + 1; // lone over-wide strip: own chunk
      if (base < 0) base = 0; // solid-only chunk

      final count = end - start;
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

        // u: chunk-relative texel index range (the shader adds the chunk's
        // alphaBase back); v: [0,4) mixed, [4,8) solid. Solid quads carry
        // constant u = 0 - the sample is ignored (cov = 1) and the atlas
        // always has a texel 0, so the dead fetch stays in-atlas without
        // widening the chunk's texcoord bounds.
        final u0 = solid ? 0.0 : (strips.alphaOffset[i] - base).toDouble();
        final u1 = solid ? 0.0 : u0 + w;
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
      chunks.add(StripChunkData(base, positions, texs, colors, indices));
      start = end;
    }

    // Alpha atlas: column texels row-major by global index, final row
    // zero-padded. Always at least one texel so solid-only batches still
    // have a valid sampler target.
    final cols = strips.alphaColumns;
    final rows =
        cols == 0 ? 1 : (cols + stripAtlasWidth - 1) ~/ stripAtlasWidth;
    final pixels = Uint8List(stripAtlasWidth * rows * 4);
    if (cols > 0) {
      pixels.setRange(0, cols * 4, strips.alphas);
    }
    return StripBatchData._(
        flushOrdinal, chunks, pixels, stripAtlasWidth, rows, n);
  }
}
