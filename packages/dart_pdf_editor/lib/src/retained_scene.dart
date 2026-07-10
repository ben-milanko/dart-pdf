/// Record a page once, replay it at any scale without re-interpreting the
/// content stream or re-decoding its images.
///
/// The classic zoom path caches a [ui.Picture] and re-rasterizes it on every
/// settle ([PdfPageRenderer.rasterize] - a `drawPicture` + `toImage`). A
/// nested `drawPicture` re-raster is measurably slower under Impeller than
/// rasterizing a freshly recorded flat picture of the same draws (~4-6x on
/// image-heavy pages), and the cached picture is a black box that cannot be
/// re-fed through a painting device. [PdfRetainedScene] keeps the page one
/// level higher - as the interpreter's own [PdfRenderCommand] transcript plus
/// the decoded [ui.Image]s it needs - so a zoom rebuilds a flat picture at
/// the new scale from retained data alone. Nothing is parsed and no codec
/// runs after [record] returns.
library;

import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

import 'canvas_device.dart';
import 'image_decoder.dart';
import 'renderer.dart';
import 'strips/strip_device.dart';

/// A page retained as a replayable scene: the recorded interpreter command
/// buffer plus its decoded images, both produced exactly once in [record].
///
/// [replay] is synchronous - it only re-issues canvas calls - which is the
/// point: the interpret (content-stream parse + walk) and the image decodes,
/// the two costs a zoom must never pay again, happened up front. The scene
/// owns its decoded images; dispose it with [dispose] when the page leaves
/// the cache window (outstanding pictures keep painting - `ui.Image.dispose`
/// on a picture-referenced image is safe, the picture holds its own ref).
class PdfRetainedScene {
  PdfRetainedScene._(this.page, this.plan, this.commands, this._images);

  /// The page this scene replays. Must stay open (the scene borrows nothing
  /// from it after [record], but callers naturally keep both together).
  final PdfPage page;

  /// The display inputs the scene was recorded under (paper color,
  /// annotations, rotation). A different plan needs a new recording -
  /// annotations are baked into [commands].
  final PdfPageRenderPlan plan;

  /// The interpreter's transcript of the page, in paint order.
  final List<PdfRenderCommand> commands;

  /// Decoded images keyed by [pdfImageKey], owned by this scene.
  final Map<Object, ui.Image> _images;

  bool _disposed = false;

  /// Page size in points after the plan's rotation - the raster size at
  /// pixelRatio 1.
  Size get pageSize => plan.pageSize(page);

  /// Interprets [page] once into a retained scene: one recording walk (which
  /// also discovers every image the page draws, including inside soft-mask
  /// groups) followed by one decode pass. This is the only step that touches
  /// the content stream or an image codec.
  ///
  /// Decodes share [PdfImageCache.instance] like every other render path, so
  /// recording a page the viewer already showed is decode-free.
  static Future<PdfRetainedScene> record(
    PdfPage page, {
    PdfPageRenderPlan plan = const PdfPageRenderPlan(),
    bool Function(PdfAnnotation)? skipAnnotation,
  }) async {
    final cos = page.document.cos;
    final pageOps = ContentStreamParser.parse(page.contentBytes());
    final recorder = RecordingPdfDevice();
    final recording = PdfInterpreter(cos: cos, device: recorder)
      ..drawPageOperations(page, pageOps);
    if (plan.annotations) recording.drawAnnotations(page, skip: skipAnnotation);
    final images = await decodeImages(cos, recorder.imageRequests,
        cache: PdfImageCache.instance);
    return PdfRetainedScene._(page, plan, recorder.commands, images);
  }

  /// Builds a scene from an already-recorded [commands] buffer (e.g. one a
  /// [PdfRenderWorker] shipped back), decoding its images once. The buffer
  /// must have been recorded for [page] under [plan].
  static Future<PdfRetainedScene> fromCommands(
    PdfPage page,
    List<PdfRenderCommand> commands, {
    PdfPageRenderPlan plan = const PdfPageRenderPlan(),
  }) async {
    final requests = <PdfImageRequest>[];
    PdfPageRenderer.collectImageRequests(commands, requests);
    final images = await decodeImages(page.document.cos, requests,
        cache: PdfImageCache.instance);
    return PdfRetainedScene._(page, plan, commands, images);
  }

  /// Replays the retained commands into a fresh picture with [pixelRatio]
  /// baked into the canvas transform, so `picture.toImage(width * ratio,
  /// height * ratio)` rasterizes it 1:1. Synchronous: no interpretation, no
  /// decoding - only canvas calls.
  ///
  /// Unlike re-rasterizing a cached picture, the replay re-issues every draw
  /// into a flat picture at the new transform - which Impeller rasterizes
  /// significantly faster than a nested `drawPicture` at a new scale. The
  /// output is pixel-identical to the cached-picture path (asserted
  /// byte-for-byte in retained_scene_test.dart).
  ui.Picture replay({required double pixelRatio}) {
    assert(!_disposed, 'replay after dispose');
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(pixelRatio);
    _replayOnto(canvas);
    return recorder.endRecording();
  }

  /// Region variant of [replay]: only [region] (page points, y-down raster
  /// space - the same space [PdfPageRenderer.rasterizeRegion] takes) lands at
  /// the picture origin, at [pixelRatio]. The deep-zoom detail patch replays
  /// through this without re-interpreting.
  ui.Picture replayRegion(Rect region, {required double pixelRatio}) {
    assert(!_disposed, 'replay after dispose');
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(pixelRatio)
      ..translate(-region.left, -region.top);
    _replayOnto(canvas);
    return recorder.endRecording();
  }

  /// Convenience: [replay] + `toImage` at the exact raster size, clamped to
  /// the engine's texture limit like [PdfPageRenderer.rasterize].
  Future<ui.Image> rasterize({required double pixelRatio}) async {
    final picture = replay(pixelRatio: pixelRatio);
    try {
      final size = pageSize;
      return await picture.toImage(
        (size.width * pixelRatio).ceil().clamp(1, 1 << 14),
        (size.height * pixelRatio).ceil().clamp(1, 1 << 14),
      );
    } finally {
      picture.dispose();
    }
  }

  /// Convenience: [replayRegion] + `toImage`, mirror of
  /// [PdfPageRenderer.rasterizeRegion].
  Future<ui.Image> rasterizeRegion(Rect region,
      {required double pixelRatio}) async {
    final picture = replayRegion(region, pixelRatio: pixelRatio);
    try {
      return await picture.toImage(
        (region.width * pixelRatio).ceil().clamp(1, 1 << 14),
        (region.height * pixelRatio).ceil().clamp(1, 1 << 14),
      );
    } finally {
      picture.dispose();
    }
  }

  void _replayOnto(Canvas canvas) {
    PdfPageRenderer.preparePageCanvas(canvas, page, plan);
    replayCommands(commands, CanvasPdfDevice(canvas, images: _images));
  }

  /// Replays the retained commands through a [StripPdfDevice] instead of
  /// [CanvasPdfDevice]: fills/strokes/outline glyphs are re-binned into
  /// sparse strips at [pixelRatio] and drawn as shader-carrying
  /// `drawVertices` batches; everything the strip device can't express
  /// delegates to the canvas in painter's order. Async because the device's
  /// alpha-atlas upload awaits `decodeImageFromPixels` inside `finish()`.
  ///
  /// The resulting picture is only valid at the recorded [pixelRatio]
  /// (strip quads are device-pixel-aligned) - every zoom step is a fresh
  /// re-bin. Still zero re-interpretation and zero image re-decoding: the
  /// walk is a command replay and the image map is the scene's own.
  ///
  /// Batching telemetry accumulates on [StripPdfDevice.totalFlushes] /
  /// `totalStripQuads` / `totalAtlasTexels`; call
  /// [StripPdfDevice.resetStats] around a step to read per-step deltas.
  Future<ui.Picture> replayStrips({required double pixelRatio}) async {
    assert(!_disposed, 'replay after dispose');
    final size = pageSize;
    final width = (size.width * pixelRatio).ceil().clamp(1, 1 << 14);
    final height = (size.height * pixelRatio).ceil().clamp(1, 1 << 14);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(pixelRatio);
    PdfPageRenderer.preparePageCanvas(canvas, page, plan);
    final device = StripPdfDevice(
      canvas,
      pageToDevice: PdfPageRenderer.pageToDeviceMatrix(
          page, size, page.cropBox,
          rotation: plan.rotation, pixelRatio: pixelRatio),
      deviceWidth: width,
      deviceHeight: height,
      pixelRatio: pixelRatio,
      images: _images,
    );
    try {
      replayCommands(commands, device);
      await device.finish(); // must precede endRecording
      return recorder.endRecording();
    } finally {
      device.dispose();
    }
  }

  /// Region variant of [replayStrips]: only [region] (page points, y-down
  /// raster space, like [replayRegion]) lands at the picture origin, at
  /// [pixelRatio]. The strip viewport is the region raster, so offscreen
  /// geometry is clipped during binning rather than drawn.
  Future<ui.Picture> replayRegionStrips(Rect region,
      {required double pixelRatio}) async {
    assert(!_disposed, 'replay after dispose');
    final width = (region.width * pixelRatio).ceil().clamp(1, 1 << 14);
    final height = (region.height * pixelRatio).ceil().clamp(1, 1 << 14);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(pixelRatio)
      ..translate(-region.left, -region.top);
    PdfPageRenderer.preparePageCanvas(canvas, page, plan);
    final device = StripPdfDevice(
      canvas,
      pageToDevice: PdfPageRenderer.pageToDeviceMatrix(
              page, pageSize, page.cropBox,
              rotation: plan.rotation, pixelRatio: pixelRatio)
          .concat(PdfMatrix.translation(
              -region.left * pixelRatio, -region.top * pixelRatio)),
      deviceWidth: width,
      deviceHeight: height,
      pixelRatio: pixelRatio,
      images: _images,
    );
    try {
      replayCommands(commands, device);
      await device.finish(); // must precede endRecording
      return recorder.endRecording();
    } finally {
      device.dispose();
    }
  }

  /// Convenience: [replayStrips] + `toImage`, the strip-router counterpart
  /// of [rasterize].
  Future<ui.Image> rasterizeStrips({required double pixelRatio}) async {
    final picture = await replayStrips(pixelRatio: pixelRatio);
    try {
      final size = pageSize;
      return await picture.toImage(
        (size.width * pixelRatio).ceil().clamp(1, 1 << 14),
        (size.height * pixelRatio).ceil().clamp(1, 1 << 14),
      );
    } finally {
      picture.dispose();
    }
  }

  /// Convenience: [replayRegionStrips] + `toImage`, the strip-router
  /// counterpart of [rasterizeRegion].
  Future<ui.Image> rasterizeRegionStrips(Rect region,
      {required double pixelRatio}) async {
    final picture = await replayRegionStrips(region, pixelRatio: pixelRatio);
    try {
      return await picture.toImage(
        (region.width * pixelRatio).ceil().clamp(1, 1 << 14),
        (region.height * pixelRatio).ceil().clamp(1, 1 << 14),
      );
    } finally {
      picture.dispose();
    }
  }

  /// Releases the scene's decoded images. Pictures already returned by
  /// [replay] keep painting (they hold their own image refs); further
  /// replays are an error.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final image in _images.values) {
      image.dispose();
    }
  }
}
