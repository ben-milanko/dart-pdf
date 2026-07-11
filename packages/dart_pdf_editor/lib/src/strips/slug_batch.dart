// dart:ui upload wrapper for pdf_graphics' worker-transferable Slug batches.
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdf_graphics/raster.dart';

export 'package:pdf_graphics/raster.dart'
    show
        SlugBatchBuilder,
        SlugBatchData,
        SlugChunkData,
        SlugGlyphData,
        slugAtlasWidth;

class SlugBatch {
  SlugBatch.fromData(SlugBatchData data)
      : chunks = [
          for (final chunk in data.chunks)
            ui.Vertices.raw(ui.VertexMode.triangles, chunk.positions,
                textureCoordinates: chunk.textureCoordinates,
                colors: chunk.colors,
                indices: chunk.indices),
        ],
        atlasPixels = data.atlasPixels,
        atlasWidth = data.atlasWidth,
        atlasHeight = data.atlasHeight,
        quadCount = data.quadCount,
        cellHeight = data.cellHeight;

  final List<ui.Vertices> chunks;
  final Uint8List atlasPixels;
  final int atlasWidth;
  final int atlasHeight;
  final int quadCount;
  final double cellHeight;
  ui.Image? atlas;

  Future<void> decodeAtlas() {
    final completer = Completer<void>();
    ui.decodeImageFromPixels(
        atlasPixels, atlasWidth, atlasHeight, ui.PixelFormat.rgba8888, (image) {
      atlas = image;
      completer.complete();
    });
    return completer.future;
  }

  void dispose() {
    atlas?.dispose();
    atlas = null;
    for (final vertices in chunks) {
      vertices.dispose();
    }
  }
}
