/// EXPERIMENTAL (Track C, retained-scene zoom): record a page once, replay
/// it at any scale without re-interpreting the content stream or re-decoding
/// its images.
///
/// Today's zoom path caches a [ui.Picture] and re-rasterizes it on every
/// settle ([PdfPageRenderer.rasterize] - a `drawPicture` + `toImage`). That
/// picture is a black box: it cannot be re-fed through a different painting
/// device, so the upcoming strip/shader replay targets have nothing to bin.
/// [PdfRetainedScene] keeps the page one level higher - as the interpreter's
/// own [PdfRenderCommand] transcript plus the decoded [ui.Image]s it needs -
/// so a zoom can rebuild a picture (or later, a strip buffer) at the new
/// transform from retained data alone. Nothing is parsed and no codec runs
/// after [record] returns.
///
/// Not exported from the main barrel; import `package:dart_pdf_editor/strips.dart`.
library;

import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

import '../canvas_device.dart';
import '../image_decoder.dart';
import '../renderer.dart';

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
    final device = RecordingPdfDevice();
    replayCommands(commands, device); // re-walk to collect image requests
    final images = await decodeImages(page.document.cos, device.imageRequests,
        cache: PdfImageCache.instance);
    return PdfRetainedScene._(page, plan, commands, images);
  }

  /// Replays the retained commands into a fresh picture with [pixelRatio]
  /// baked into the canvas transform, so `picture.toImage(width * ratio,
  /// height * ratio)` rasterizes it 1:1. Synchronous: no interpretation, no
  /// decoding - only canvas calls.
  ///
  /// Unlike re-rasterizing a cached picture, the replay re-issues every draw
  /// at the new transform, which is exactly the seam a strip/shader device
  /// needs (it must re-bin geometry per scale); for [CanvasPdfDevice] the
  /// output is pixel-identical to the cached-picture path.
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
