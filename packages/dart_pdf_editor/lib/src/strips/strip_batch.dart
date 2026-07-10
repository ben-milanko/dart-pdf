// One flushed batch of sparse strips, wrapped from the portable
// [StripBatchData] arrays (built in pdf_graphics, possibly on a worker
// isolate) into the engine objects the shader path draws: `ui.Vertices.raw`
// per chunk plus the decoded rgba8888 alpha atlas. This side does NOTHING
// but engine-object creation - the array-building loop lives with the
// binning core so worker-side plans ship draw-ready data.
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdf_graphics/raster.dart';

export 'package:pdf_graphics/raster.dart'
    show
        StripBatchData,
        StripChunkData,
        stripAtlasWidth,
        stripMaxAlphaColumnsPerDraw,
        stripMaxQuadsPerDraw;

/// A flush batch: everything needed to draw its strips with one shader
/// paint - [chunks] drawVertices calls sharing one [atlas].
class StripBatch {
  /// Wraps portable batch [data] in engine vertex objects. The atlas image
  /// is decoded separately ([decodeAtlas]) because `decodeImageFromPixels`
  /// is asynchronous.
  StripBatch.fromData(StripBatchData data)
      : chunks = [
          for (final chunk in data.chunks)
            ui.Vertices.raw(ui.VertexMode.triangles, chunk.positions,
                textureCoordinates: chunk.textureCoordinates,
                colors: chunk.colors,
                indices: chunk.indices),
        ],
        chunkAlphaBases = [
          for (final chunk in data.chunks) chunk.alphaBase,
        ],
        atlasPixels = data.atlasPixels,
        atlasWidth = data.atlasWidth,
        atlasHeight = data.atlasHeight,
        stripCount = data.stripCount;

  final List<ui.Vertices> chunks;

  /// Per-chunk texcoord origin (global alpha-texel index), fed to the
  /// shader's uBase - see [StripChunkData.alphaBase].
  final List<int> chunkAlphaBases;
  final Uint8List atlasPixels; // rgba8888, atlasWidth * atlasHeight * 4
  final int atlasWidth;
  final int atlasHeight;
  final int stripCount;

  /// Decoded alpha atlas; set by [decodeAtlas], disposed by [dispose].
  ui.Image? atlas;

  /// Snapshots [strips] (the generator reuses its buffers, so all data is
  /// copied) into draw-ready form, or null when the buffer is empty.
  static StripBatch? of(StripBuffer strips) {
    final data = StripBatchData.of(strips, 0);
    return data == null ? null : StripBatch.fromData(data);
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
