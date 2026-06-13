import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

import 'renderer.dart';

/// A rasterized page handed to a [PdfOcrEngine], with the geometry to map
/// pixel boxes back to PDF user space.
///
/// An OCR engine works in raster pixels (top-left origin, y down); the page
/// content lives in PDF user space (bottom-left origin, y up, possibly with
/// a non-zero crop box and a /Rotate). [userSpaceRect] converts between
/// them, undoing the rotation and crop the raster already baked in, so an
/// engine can return [PdfOcrSpan]s without doing any of that math itself.
class PdfOcrPageImage {
  PdfOcrPageImage({
    required this.image,
    required this.page,
    required this.pageIndex,
    required this.pixelRatio,
  });

  /// The page raster, rendered post-rotation at [pixelRatio] px per point.
  final ui.Image image;

  /// The source page, for crop box and rotation.
  final PdfPage page;

  /// The page's index in its document.
  final int pageIndex;

  /// Raster resolution: pixels per PDF point.
  final double pixelRatio;

  /// The raster's pixel width.
  int get width => image.width;

  /// The raster's pixel height.
  int get height => image.height;

  /// Maps a [pixels] rectangle (raster space: top-left origin, y down, the
  /// natural output of an image-based OCR engine) to a PDF user-space
  /// [PdfRect] suitable for [PdfOcrSpan.bounds].
  PdfRect userSpaceRect(Rect pixels) {
    final inverse = _pixelToUser;
    final corners = [
      (pixels.left, pixels.top),
      (pixels.right, pixels.top),
      (pixels.right, pixels.bottom),
      (pixels.left, pixels.bottom),
    ];
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final (px, py) in corners) {
      final x = inverse.transformX(px, py);
      final y = inverse.transformY(px, py);
      minX = math.min(minX, x);
      minY = math.min(minY, y);
      maxX = math.max(maxX, x);
      maxY = math.max(maxY, y);
    }
    return PdfRect(minX, minY, maxX, maxY);
  }

  /// Inverse of the user→pixel transform built from the same operations
  /// `PdfPageRenderer.renderPicture` applies, so it round-trips exactly.
  PdfMatrix get _pixelToUser =>
      _userToPixel.inverted() ?? PdfMatrix.identity;

  PdfMatrix get _userToPixel {
    final box = page.cropBox;
    final size = PdfPageRenderer.pageSize(page);
    // Innermost first: user → cropped → flipped → rotated → scaled.
    var m = PdfMatrix.translation(-box.left, -box.bottom)
        .concat(const PdfMatrix(1, 0, 0, -1, 0, 0))
        .concat(PdfMatrix.translation(0, box.height));
    switch (page.rotation) {
      case 90:
        m = m
            .concat(_rotation(math.pi / 2))
            .concat(PdfMatrix.translation(size.width, 0));
      case 180:
        m = m
            .concat(_rotation(math.pi))
            .concat(PdfMatrix.translation(size.width, size.height));
      case 270:
        m = m
            .concat(_rotation(-math.pi / 2))
            .concat(PdfMatrix.translation(0, size.height));
    }
    return m.concat(PdfMatrix.scaled(pixelRatio, pixelRatio));
  }

  static PdfMatrix _rotation(double theta) {
    final c = math.cos(theta), s = math.sin(theta);
    return PdfMatrix(c, s, -s, c, 0, 0);
  }
}

/// A pluggable OCR engine: given a rasterized page, returns recognized text
/// runs positioned in PDF user space.
///
/// **No engine ships in-tree.** OCR is a large native/cloud subsystem
/// (ML Kit, a Tesseract WASM build, Vision, a cloud API), so dart-pdf only
/// defines the seam. A host implements this; [PdfOcrEditing.applyOcr]
/// rasterizes the page, calls the engine, and writes the recognized runs as
/// an invisible, selectable, searchable text layer
/// (`PdfOcrEditing.injectTextLayer`).
///
/// Implementations typically run their recognizer over
/// [PdfOcrPageImage.image] and convert each word box from pixels to user
/// space with [PdfOcrPageImage.userSpaceRect].
abstract class PdfOcrEngine {
  /// Recognizes the text on [page]. Returns one [PdfOcrSpan] per word (or
  /// line) with its user-space bounds and confidence.
  Future<List<PdfOcrSpan>> recognize(PdfOcrPageImage page);
}

/// Running an [PdfOcrEngine] and writing its result onto a page.
extension PdfOcrApply on PdfEditor {
  /// Rasterizes page [pageIndex], runs [engine] over it, and injects the
  /// recognized text as a (by default invisible) selectable/searchable
  /// layer — turning a scanned, image-only page into one whose text can be
  /// selected, searched, copied, and extracted, without changing how it
  /// looks. Returns how many spans were written.
  ///
  /// [pixelRatio] is the OCR raster resolution (2 = 144 dpi; raise it for
  /// small type). [minConfidence] drops low-confidence spans; [visible]
  /// burns the text in instead of hiding it; [font] picks the layer font.
  /// See [PdfOcrEditing.injectTextLayer] for how spans are placed.
  Future<int> applyOcr(
    int pageIndex,
    PdfOcrEngine engine, {
    double pixelRatio = 2,
    PdfStandardFont font = PdfStandardFont.helvetica,
    double minConfidence = 0,
    bool visible = false,
  }) async {
    final page = document.page(pageIndex);
    final image =
        await PdfPageRenderer.renderImage(page, pixelRatio: pixelRatio);
    try {
      final spans = await engine.recognize(PdfOcrPageImage(
        image: image,
        page: page,
        pageIndex: pageIndex,
        pixelRatio: pixelRatio,
      ));
      return injectTextLayer(
        pageIndex,
        spans,
        font: font,
        minConfidence: minConfidence,
        visible: visible,
      );
    } finally {
      image.dispose();
    }
  }
}
