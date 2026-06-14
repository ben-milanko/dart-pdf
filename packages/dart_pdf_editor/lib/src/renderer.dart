import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

import 'canvas_device.dart';
import 'image_decoder.dart';

/// Rasterizes PDF pages.
///
/// Two passes: first an [ImageCollector] walk finds image XObjects so they
/// can be decoded asynchronously, then the page is painted synchronously
/// onto a recorded canvas.
class PdfPageRenderer {
  PdfPageRenderer._();

  /// Renders [page] into a picture at 1 unit = 1 PDF point, cropped to the
  /// page's crop box and rotated per /Rotate.
  ///
  /// [pageColor] is the paper: the fill painted under the page content.
  /// PDF pages have no background of their own — white is only the
  /// convention — so any opaque color works (a viewer-level setting; the
  /// document is untouched).
  ///
  /// [annotations] false leaves the page's annotations (highlights, ink,
  /// stamps, form fields...) out of the render — the clean underlying
  /// page. Display-only, like [pageColor]; the document is untouched.
  ///
  /// [skipAnnotation] omits the annotations it matches while keeping the
  /// rest — the "lift" model behind a live drag/resize preview, so the
  /// page reads as the artwork minus the one being edited.
  static Future<ui.Picture> renderPicture(PdfPage page,
      {Color pageColor = const Color(0xFFFFFFFF),
      bool annotations = true,
      bool Function(PdfAnnotation)? skipAnnotation}) async {
    final cos = page.document.cos;

    // Parsing the content stream (and decompressing it) dominates rendering on
    // graphics-rich pages, and the page is interpreted twice here — once to
    // discover images to decode, once to paint. Parse it once and feed both.
    final pageOps = ContentStreamParser.parse(page.contentBytes());

    // Discover the images to decode with a scan-only interpretation: it walks
    // the same content (so it sees every image — including those drawn by
    // Type3 glyphs and tiling patterns) but skips the path/text/colour/shading
    // build work, so the collect walk is a fraction of the paint walk.
    final collector = ImageCollector();
    final collecting =
        PdfInterpreter(cos: cos, device: collector, scanImagesOnly: true)
          ..drawPageOperations(page, pageOps);
    if (annotations) collecting.drawAnnotations(page, skip: skipAnnotation);
    final images =
        await decodeImages(cos, collector.streams, cache: PdfImageCache.instance);

    final box = page.cropBox;
    final size = pageSize(page);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    _paintBackground(canvas, size, pageColor);
    _applyPageTransform(canvas, page, size, box);

    final painting = PdfInterpreter(
        cos: cos, device: CanvasPdfDevice(canvas, images: images))
      ..drawPageOperations(page, pageOps);
    if (annotations) painting.drawAnnotations(page, skip: skipAnnotation);
    final picture = recorder.endRecording();
    // The picture retains its own reference to every drawn image, so the
    // decode handles (clones from the cache, or fresh decodes) can be freed
    // now — the cache keeps the masters for the next render.
    for (final image in images.values) {
      image.dispose();
    }
    return picture;
  }

  /// Renders [page] like [renderPicture] but by first recording the page's
  /// interpreter callbacks into a portable [PdfRenderCommand] buffer (a
  /// [RecordingPdfDevice]) and then replaying that buffer onto the canvas via
  /// the unchanged [CanvasPdfDevice].
  ///
  /// The result is pixel-identical to [renderPicture] — the same canvas calls
  /// happen in the same order — but the interpretation (the dominant cost: the
  /// content-stream parse and walk) is now decoupled from the painting. This
  /// is the seam the background-isolate work splits across: the recording half
  /// is pure Dart and `dart:ui`-free, so it can move to a worker isolate, with
  /// only this replay (cheap) and image decoding staying on the UI thread.
  ///
  /// For now both halves run on the calling isolate; this method exists so the
  /// record/replay split can be exercised and proven equivalent before any
  /// isolate machinery is introduced.
  static Future<ui.Picture> renderPictureRecorded(PdfPage page,
      {Color pageColor = const Color(0xFFFFFFFF),
      bool annotations = true,
      bool Function(PdfAnnotation)? skipAnnotation}) async {
    final cos = page.document.cos;
    final pageOps = ContentStreamParser.parse(page.contentBytes());

    // Record the page into a flat command buffer. This single walk also
    // discovers every image (the recording device's drawImage calls), so the
    // separate scan-only collect pass [renderPicture] runs is unnecessary here.
    final recorder = RecordingPdfDevice();
    final recording = PdfInterpreter(cos: cos, device: recorder)
      ..drawPageOperations(page, pageOps);
    if (annotations) recording.drawAnnotations(page, skip: skipAnnotation);

    final images = await decodeImages(cos, recorder.imageRequests,
        cache: PdfImageCache.instance);

    final box = page.cropBox;
    final size = pageSize(page);
    final uiRecorder = ui.PictureRecorder();
    final canvas = Canvas(uiRecorder);

    _paintBackground(canvas, size, pageColor);
    _applyPageTransform(canvas, page, size, box);

    replayCommands(recorder.commands, CanvasPdfDevice(canvas, images: images));
    final picture = uiRecorder.endRecording();
    for (final image in images.values) {
      image.dispose();
    }
    return picture;
  }

  /// Paints the page paper under the content: an opaque white backing when
  /// [pageColor] is translucent (so a tint washes over white rather than the
  /// viewer canvas behind the page), then [pageColor]. A fully opaque colour
  /// makes the white backing a no-op, so it is free in the common case.
  static void _paintBackground(Canvas canvas, Size size, Color pageColor) {
    if (pageColor.a < 1.0) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = const Color(0xFFFFFFFF),
      );
    }
    canvas.drawRect(Offset.zero & size, Paint()..color = pageColor);
  }

  /// Sets the canvas up in PDF user space: /Rotate, then the y-flip and crop
  /// box origin, so interpreter output (page space, y-up) lands correctly.
  static void _applyPageTransform(
      Canvas canvas, PdfPage page, Size size, PdfRect box) {
    switch (page.rotation) {
      case 90:
        canvas.translate(size.width, 0);
        canvas.rotate(math.pi / 2);
      case 180:
        canvas.translate(size.width, size.height);
        canvas.rotate(math.pi);
      case 270:
        canvas.translate(0, size.height);
        canvas.rotate(-math.pi / 2);
    }
    // PDF user space is y-up with the crop box's own origin
    canvas.translate(0, box.height);
    canvas.scale(1, -1);
    canvas.translate(-box.left, -box.bottom);
  }

  /// Renders one annotation's appearance into a picture in the same page
  /// raster space as [renderPicture] (post-rotation, y down, 1 unit =
  /// 1 point) but with a transparent background — for live drag/resize
  /// previews. Null when the annotation has no appearance stream.
  static Future<ui.Picture?> renderAnnotationPicture(
      PdfPage page, PdfAnnotation annotation) async {
    if (annotation.normalAppearance == null) return null;
    final cos = page.document.cos;

    final collector = ImageCollector();
    PdfInterpreter(cos: cos, device: collector, scanImagesOnly: true)
        .drawAnnotation(page, annotation);
    final images =
        await decodeImages(cos, collector.streams, cache: PdfImageCache.instance);

    final box = page.cropBox;
    final size = pageSize(page);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    _applyPageTransform(canvas, page, size, box);

    PdfInterpreter(cos: cos, device: CanvasPdfDevice(canvas, images: images))
        .drawAnnotation(page, annotation);
    final picture = recorder.endRecording();
    for (final image in images.values) {
      image.dispose();
    }
    return picture;
  }

  /// Renders [page] to a bitmap. [pixelRatio] of 2 doubles the resolution.
  static Future<ui.Image> renderImage(PdfPage page,
      {double pixelRatio = 1,
      Color pageColor = const Color(0xFFFFFFFF),
      bool annotations = true}) async {
    final picture = await renderPicture(page,
        pageColor: pageColor, annotations: annotations);
    try {
      return await rasterize(picture, pageSize(page), pixelRatio);
    } finally {
      picture.dispose();
    }
  }

  /// Rasterizes an already-recorded page [picture] (sized [size] points) —
  /// re-rasterizing a cached picture at a new zoom skips re-interpreting
  /// the page entirely.
  static Future<ui.Image> rasterize(
      ui.Picture picture, Size size, double pixelRatio) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder)
      ..scale(pixelRatio)
      ..drawPicture(picture);
    final scaled = recorder.endRecording();
    try {
      return await scaled.toImage(
        (size.width * pixelRatio).ceil().clamp(1, 1 << 14),
        (size.height * pixelRatio).ceil().clamp(1, 1 << 14),
      );
    } finally {
      scaled.dispose();
    }
  }

  /// Rasterizes only [region] (in page points, y-down raster space) of a
  /// recorded page [picture] at [pixelRatio] — the deep-zoom detail patch.
  static Future<ui.Image> rasterizeRegion(
      ui.Picture picture, Rect region, double pixelRatio) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder)
      ..scale(pixelRatio)
      ..translate(-region.left, -region.top)
      ..drawPicture(picture);
    final scaled = recorder.endRecording();
    try {
      return await scaled.toImage(
        (region.width * pixelRatio).ceil().clamp(1, 1 << 14),
        (region.height * pixelRatio).ceil().clamp(1, 1 << 14),
      );
    } finally {
      scaled.dispose();
    }
  }

  /// Samples the rendered color of [page] at [point] — page raster space,
  /// i.e. post-rotation points with y down (view coordinates divided by
  /// the view scale). One-shot; for repeated samples (an eyedropper's
  /// live preview) build a [PdfPageColorSampler] once instead.
  static Future<ui.Color?> sampleColor(PdfPage page, ui.Offset point,
          {Color pageColor = const Color(0xFFFFFFFF),
          bool annotations = true}) async =>
      (await PdfPageColorSampler.of(page,
              pageColor: pageColor, annotations: annotations))
          .colorAt(point);

  /// Page size in points after applying /Rotate.
  static Size pageSize(PdfPage page) {
    final box = page.cropBox;
    final swap = page.rotation == 90 || page.rotation == 270;
    return swap ? Size(box.height, box.width) : Size(box.width, box.height);
  }
}

/// Pixel access to a page rendered once, for repeated color sampling —
/// the eyedropper's live preview follows the pointer, and re-rendering
/// per event would be far too slow.
///
/// Points are page raster space: post-rotation points with y down, the
/// view position divided by the view scale.
class PdfPageColorSampler {
  PdfPageColorSampler._(this._pixels, this._width, this._height);

  final ByteData _pixels;
  final int _width;
  final int _height;

  /// Renders and rasterizes [page] at 1 px per point. [pageColor] and
  /// [annotations] must match how the page is displayed, so samples
  /// read the color the user actually sees.
  static Future<PdfPageColorSampler> of(PdfPage page,
      {Color pageColor = const Color(0xFFFFFFFF),
      bool annotations = true}) async {
    final picture = await PdfPageRenderer.renderPicture(page,
        pageColor: pageColor, annotations: annotations);
    try {
      final image = await PdfPageRenderer.rasterize(
          picture, PdfPageRenderer.pageSize(page), 1);
      try {
        final data = await image.toByteData();
        if (data == null) {
          throw StateError('page raster yielded no pixels');
        }
        return PdfPageColorSampler._(data, image.width, image.height);
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  }

  /// The color at [point], averaged over a 3×3-point patch so
  /// anti-aliased strokes still read as their color. Null off the page.
  ui.Color? colorAt(ui.Offset point) {
    final cx = point.dx.round(), cy = point.dy.round();
    var r = 0, g = 0, b = 0, n = 0;
    for (var y = cy - 1; y <= cy + 1; y++) {
      for (var x = cx - 1; x <= cx + 1; x++) {
        if (x < 0 || y < 0 || x >= _width || y >= _height) continue;
        final i = (y * _width + x) * 4;
        if (_pixels.getUint8(i + 3) == 0) continue; // past the page edge
        r += _pixels.getUint8(i);
        g += _pixels.getUint8(i + 1);
        b += _pixels.getUint8(i + 2);
        n++;
      }
    }
    return n == 0 ? null : ui.Color.fromARGB(255, r ~/ n, g ~/ n, b ~/ n);
  }
}
