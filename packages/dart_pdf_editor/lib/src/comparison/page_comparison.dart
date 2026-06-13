import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/painting.dart';
import 'package:pdf_document/pdf_document.dart';

import '../page_geometry.dart';
import '../renderer.dart';

/// How a diff map colors its pixels.
enum PdfDiffStyle {
  /// Differing pixels solid red, matching pixels keep the first image.
  /// Used by the Ghent baseline-failure dump (red marks over the render).
  redOverImage,

  /// Differing pixels red on an otherwise white field — the changes alone,
  /// easy to spot. Used by the PDF.js comparison gallery.
  redOnWhite,

  /// Before/after semantics for document comparison: content only in the
  /// "before" page is red (removed), content only in the "after" page is
  /// green (added), content that changed in place is amber, and unchanged
  /// content is dimmed toward white so the changes stand out.
  beforeAfter,
}

/// Default per-channel difference treated as identical, matching the
/// Ghent/PDF.js harnesses.
const int kPdfDiffChannelTolerance = 8;

/// The pixel-level result of comparing two equal-size RGBA rasters.
class PdfPixelDiff {
  PdfPixelDiff({
    required this.width,
    required this.height,
    required this.differingPixels,
    required this.totalPixels,
    required Uint8List diffMap,
    required Uint8List changedMask,
  })  : _diffMap = diffMap,
        _changedMask = changedMask;

  final int width;
  final int height;
  final int differingPixels;
  final int totalPixels;

  /// RGBA pixels of the colored diff (see [PdfDiffStyle]); 4 bytes/pixel.
  final Uint8List _diffMap;

  /// One byte per pixel: 1 where the pixel differs, 0 elsewhere.
  final Uint8List _changedMask;

  double get differenceFraction =>
      totalPixels == 0 ? 0 : differingPixels / totalPixels;

  bool get hasChanges => differingPixels > 0;

  /// The raw RGBA bytes of the colored diff, for tests that assert the
  /// palette without a Flutter image binding.
  @visibleForTesting
  Uint8List get debugDiffMap => _diffMap;

  /// Decodes the colored diff into an image. The caller disposes it.
  Future<ui.Image> toImage() => _imageFromRgba(_diffMap, width, height);

  /// Bounding boxes (raster-pixel coordinates) of clusters of changed
  /// pixels, top-to-bottom — the navigation stops a diff viewer steps
  /// through. Coarse-grid clustered, so a handful of boxes cover a page.
  List<Rect> changeRegions({int cellSize = 24}) =>
      _clusterRegions(_changedMask, width, height, cellSize);
}

/// Compares rendered PDF pages and builds diff images.
///
/// Factors the pixel comparison the Ghent and PDF.js render tests use
/// (per-channel tolerance + differing-pixel fraction + a colored diff map)
/// into one place so the comparison feature and those suites share it.
class PdfPageComparison {
  PdfPageComparison._();

  /// Compares two equal-size RGBA buffers (4 bytes/pixel, straight alpha).
  ///
  /// A pixel differs when the largest absolute per-channel difference over
  /// R, G, B exceeds [channelTolerance].
  static PdfPixelDiff comparePixels(
    Uint8List before,
    Uint8List after, {
    required int width,
    required int height,
    int channelTolerance = kPdfDiffChannelTolerance,
    PdfDiffStyle style = PdfDiffStyle.beforeAfter,
  }) {
    assert(before.length == after.length);
    final n = before.length;
    final diffMap = Uint8List(n);
    final changed = Uint8List(n ~/ 4);
    var differing = 0;
    for (var i = 0, p = 0; i < n; i += 4, p++) {
      var maxDiff = 0;
      for (var c = 0; c < 3; c++) {
        final d = (before[i + c] - after[i + c]).abs();
        if (d > maxDiff) maxDiff = d;
      }
      final differs = maxDiff > channelTolerance;
      if (differs) {
        differing++;
        changed[p] = 1;
      }
      switch (style) {
        case PdfDiffStyle.redOverImage:
          diffMap[i] = differs ? 255 : before[i];
          diffMap[i + 1] = differs ? 0 : before[i + 1];
          diffMap[i + 2] = differs ? 0 : before[i + 2];
        case PdfDiffStyle.redOnWhite:
          diffMap[i] = 255;
          diffMap[i + 1] = differs ? 0 : 255;
          diffMap[i + 2] = differs ? 0 : 255;
        case PdfDiffStyle.beforeAfter:
          if (!differs) {
            // ghost the unchanged content: blend ~80% toward white
            diffMap[i] = _dim(after[i]);
            diffMap[i + 1] = _dim(after[i + 1]);
            diffMap[i + 2] = _dim(after[i + 2]);
          } else {
            final beforeInk = _isInk(before, i);
            final afterInk = _isInk(after, i);
            int r, g, b;
            if (beforeInk && !afterInk) {
              (r, g, b) = (0xE5, 0x39, 0x35); // removed — red
            } else if (afterInk && !beforeInk) {
              (r, g, b) = (0x2E, 0x7D, 0x32); // added — green
            } else {
              (r, g, b) = (0xF5, 0x7C, 0x00); // changed — amber
            }
            diffMap[i] = r;
            diffMap[i + 1] = g;
            diffMap[i + 2] = b;
          }
      }
      diffMap[i + 3] = 255;
    }
    return PdfPixelDiff(
      width: width,
      height: height,
      differingPixels: differing,
      totalPixels: n ~/ 4,
      diffMap: diffMap,
      changedMask: changed,
    );
  }

  /// Compares two already-rendered page images. They need not be the same
  /// size — each is padded (top-left) onto a shared canvas the size of the
  /// larger, with the extra area treated as page background, so inserted or
  /// removed content near an edge still registers.
  static Future<PdfPixelDiff> compareImages(
    ui.Image before,
    ui.Image after, {
    int channelTolerance = kPdfDiffChannelTolerance,
    PdfDiffStyle style = PdfDiffStyle.beforeAfter,
    Color background = const Color(0xFFFFFFFF),
  }) async {
    final width = math.max(before.width, after.width);
    final height = math.max(before.height, after.height);
    final a = await _paddedPixels(before, width, height, background);
    final b = await _paddedPixels(after, width, height, background);
    return comparePixels(a, b,
        width: width,
        height: height,
        channelTolerance: channelTolerance,
        style: style);
  }

  /// Renders both pages at [pixelRatio] (matched scale) and compares them.
  static Future<PdfPageDiff> comparePages(
    PdfPage? before,
    PdfPage? after, {
    double pixelRatio = 1.5,
    int channelTolerance = kPdfDiffChannelTolerance,
    PdfDiffStyle style = PdfDiffStyle.beforeAfter,
    Color pageColor = const Color(0xFFFFFFFF),
  }) async {
    // An inserted or removed page compares against a blank of the other's
    // size, so the whole page reads as added/removed.
    final beforeImage = before == null
        ? null
        : await PdfPageRenderer.renderImage(before,
            pixelRatio: pixelRatio, pageColor: pageColor);
    final afterImage = after == null
        ? null
        : await PdfPageRenderer.renderImage(after,
            pixelRatio: pixelRatio, pageColor: pageColor);
    try {
      final width = math.max(
          beforeImage?.width ?? afterImage?.width ?? 1,
          afterImage?.width ?? beforeImage?.width ?? 1);
      final height = math.max(
          beforeImage?.height ?? afterImage?.height ?? 1,
          afterImage?.height ?? beforeImage?.height ?? 1);
      final a = await _paddedPixels(beforeImage, width, height, pageColor);
      final b = await _paddedPixels(afterImage, width, height, pageColor);
      final pixels = comparePixels(a, b,
          width: width,
          height: height,
          channelTolerance: channelTolerance,
          style: style);

      final regionsPixels = pixels.changeRegions();
      return PdfPageDiff(
        pixels: pixels,
        pixelRatio: pixelRatio,
        regionsBefore: before == null
            ? const []
            : _toPageRects(regionsPixels, before, pixelRatio),
        regionsAfter: after == null
            ? const []
            : _toPageRects(regionsPixels, after, pixelRatio),
      );
    } finally {
      beforeImage?.dispose();
      afterImage?.dispose();
    }
  }
}

/// A page-pair comparison: the pixel diff plus the changed regions in each
/// page's own PDF coordinate space, ready for `showRect` navigation.
class PdfPageDiff {
  const PdfPageDiff({
    required this.pixels,
    required this.pixelRatio,
    required this.regionsBefore,
    required this.regionsAfter,
  });

  final PdfPixelDiff pixels;
  final double pixelRatio;

  /// Changed regions on the before page, PDF page space.
  final List<PdfRect> regionsBefore;

  /// Changed regions on the after page, PDF page space.
  final List<PdfRect> regionsAfter;

  double get differenceFraction => pixels.differenceFraction;
  bool get hasChanges => pixels.hasChanges;
}

int _dim(int v) => 204 + (v * 51 ~/ 255);

bool _isInk(Uint8List px, int i) =>
    px[i] < 250 || px[i + 1] < 250 || px[i + 2] < 250;

/// Reads [image] into an RGBA buffer of [width]×[height], background-filled
/// and the image copied into the top-left. When the image already matches
/// the size this is a straight read.
Future<Uint8List> _paddedPixels(
    ui.Image? image, int width, int height, Color background) async {
  final out = Uint8List(width * height * 4);
  // fill with the opaque background
  final br = (background.r * 255).round();
  final bg = (background.g * 255).round();
  final bb = (background.b * 255).round();
  for (var i = 0; i < out.length; i += 4) {
    out[i] = br;
    out[i + 1] = bg;
    out[i + 2] = bb;
    out[i + 3] = 255;
  }
  if (image == null) return out;
  final data =
      await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
  if (data == null) return out;
  final src = data.buffer.asUint8List();
  if (image.width == width && image.height == height) return src;
  for (var y = 0; y < image.height && y < height; y++) {
    final srcRow = y * image.width * 4;
    final dstRow = y * width * 4;
    final rowBytes = math.min(image.width, width) * 4;
    out.setRange(dstRow, dstRow + rowBytes, src, srcRow);
  }
  return out;
}

Future<ui.Image> _imageFromRgba(Uint8List rgba, int width, int height) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
  final descriptor = ui.ImageDescriptor.raw(buffer,
      width: width, height: height, pixelFormat: ui.PixelFormat.rgba8888);
  final codec = await descriptor.instantiateCodec();
  return (await codec.getNextFrame()).image;
}

List<PdfRect> _toPageRects(List<Rect> pixelRects, PdfPage page, double ratio) {
  final size = PdfPageRenderer.pageSize(page);
  final geometry = PdfPageGeometry(
      cropBox: page.cropBox, rotation: page.rotation, viewSize: size);
  final maxX = size.width * ratio;
  final maxY = size.height * ratio;
  final out = <PdfRect>[];
  for (final r in pixelRects) {
    final clamped = Rect.fromLTRB(
      r.left.clamp(0.0, maxX),
      r.top.clamp(0.0, maxY),
      r.right.clamp(0.0, maxX),
      r.bottom.clamp(0.0, maxY),
    );
    if (clamped.width <= 0 || clamped.height <= 0) continue;
    // raster pixels → raster points (the geometry's view space at scale 1)
    final viewRect = Rect.fromLTRB(clamped.left / ratio, clamped.top / ratio,
        clamped.right / ratio, clamped.bottom / ratio);
    out.add(geometry.toPageRect(viewRect));
  }
  return out;
}

/// Coarse connected-component clustering of the changed-pixel mask: bins
/// pixels into [cellSize] cells, unions 4-connected occupied cells, and
/// returns each component's bounding box in raster pixels.
List<Rect> _clusterRegions(
    Uint8List changed, int width, int height, int cellSize) {
  if (width == 0 || height == 0) return const [];
  final gw = (width + cellSize - 1) ~/ cellSize;
  final gh = (height + cellSize - 1) ~/ cellSize;
  final occ = List<bool>.filled(gw * gh, false);
  for (var y = 0; y < height; y++) {
    final row = y * width;
    final cy = (y ~/ cellSize) * gw;
    for (var x = 0; x < width; x++) {
      if (changed[row + x] != 0) occ[cy + x ~/ cellSize] = true;
    }
  }
  final parent = List<int>.generate(gw * gh, (i) => i);
  int find(int a) {
    while (parent[a] != a) {
      parent[a] = parent[parent[a]];
      a = parent[a];
    }
    return a;
  }

  void union(int a, int b) {
    final ra = find(a), rb = find(b);
    if (ra != rb) parent[ra] = rb;
  }

  for (var gy = 0; gy < gh; gy++) {
    for (var gx = 0; gx < gw; gx++) {
      final c = gy * gw + gx;
      if (!occ[c]) continue;
      if (gx + 1 < gw && occ[c + 1]) union(c, c + 1);
      if (gy + 1 < gh && occ[c + gw]) union(c, c + gw);
    }
  }
  final boxes = <int, List<int>>{}; // root -> [minGx, minGy, maxGx, maxGy]
  for (var gy = 0; gy < gh; gy++) {
    for (var gx = 0; gx < gw; gx++) {
      final c = gy * gw + gx;
      if (!occ[c]) continue;
      final r = find(c);
      final b = boxes[r];
      if (b == null) {
        boxes[r] = [gx, gy, gx, gy];
      } else {
        b[0] = math.min(b[0], gx);
        b[1] = math.min(b[1], gy);
        b[2] = math.max(b[2], gx);
        b[3] = math.max(b[3], gy);
      }
    }
  }
  final rects = <Rect>[
    for (final b in boxes.values)
      Rect.fromLTRB(
        (b[0] * cellSize).toDouble(),
        (b[1] * cellSize).toDouble(),
        math.min(width, (b[2] + 1) * cellSize).toDouble(),
        math.min(height, (b[3] + 1) * cellSize).toDouble(),
      )
  ];
  rects.sort((a, b) {
    final c = a.top.compareTo(b.top);
    return c != 0 ? c : a.left.compareTo(b.left);
  });
  return rects;
}
