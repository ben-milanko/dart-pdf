import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';

import 'content_writer.dart';
import 'image.dart';

/// A page size in PDF points (1 pt = 1/72 inch) for [PdfImageDocument].
///
/// Use one of the ISO/US constants, or construct an arbitrary size. The
/// [portrait]/[landscape] getters reorient without caring which way the
/// constant is defined.
class PdfPageSize {
  const PdfPageSize(this.width, this.height);

  /// Page width in points.
  final double width;

  /// Page height in points.
  final double height;

  /// ISO A3 (297 × 420 mm).
  static const a3 = PdfPageSize(841.89, 1190.55);

  /// ISO A4 (210 × 297 mm) - the common document size.
  static const a4 = PdfPageSize(595.28, 841.89);

  /// ISO A5 (148 × 210 mm).
  static const a5 = PdfPageSize(419.53, 595.28);

  /// US Letter (8.5 × 11 in).
  static const letter = PdfPageSize(612, 792);

  /// US Legal (8.5 × 14 in).
  static const legal = PdfPageSize(612, 1008);

  /// US Tabloid / Ledger (11 × 17 in).
  static const tabloid = PdfPageSize(792, 1224);

  /// This size in portrait orientation (height ≥ width).
  PdfPageSize get portrait =>
      height >= width ? this : PdfPageSize(height, width);

  /// This size in landscape orientation (width ≥ height).
  PdfPageSize get landscape =>
      width >= height ? this : PdfPageSize(height, width);

  @override
  String toString() => 'PdfPageSize($width, $height)';
}

/// How an image is scaled to fill its page when a fixed [PdfPageSize] is
/// chosen. Ignored when the page is sized to the image (the default).
enum PdfImageFit {
  /// Scale to fit entirely inside the content box, preserving aspect ratio.
  /// Leaves letterbox/pillarbox margins; nothing is cropped.
  contain,

  /// Scale to cover the whole content box, preserving aspect ratio. The
  /// overflow is clipped to the content box.
  cover,

  /// Stretch to exactly fill the content box, ignoring aspect ratio.
  fill,

  /// Draw at the image's natural size (its pixels at the chosen dpi), placed
  /// by the alignment and clipped to the content box.
  none,
}

/// Where the image sits inside the page's content box, as fractions of the
/// leftover space: `x` runs −1 (left) → 0 (centre) → 1 (right), `y` runs
/// −1 (bottom) → 0 (centre) → 1 (top). Only matters when the scaled image
/// is smaller than the content box ([PdfImageFit.contain] /
/// [PdfImageFit.none]); [PdfImageFit.cover] and [PdfImageFit.fill] leave no
/// slack.
class PdfImageAlign {
  const PdfImageAlign(this.x, this.y);

  /// Horizontal placement: −1 left, 0 centre, 1 right.
  final double x;

  /// Vertical placement: −1 bottom, 0 centre, 1 top.
  final double y;

  static const center = PdfImageAlign(0, 0);
  static const topLeft = PdfImageAlign(-1, 1);
  static const topCenter = PdfImageAlign(0, 1);
  static const topRight = PdfImageAlign(1, 1);
  static const centerLeft = PdfImageAlign(-1, 0);
  static const centerRight = PdfImageAlign(1, 0);
  static const bottomLeft = PdfImageAlign(-1, -1);
  static const bottomCenter = PdfImageAlign(0, -1);
  static const bottomRight = PdfImageAlign(1, -1);
}

/// Assembles a brand-new PDF from a list of raster images - one page per
/// image.
///
/// This is the pure-Dart half of "Office / image ingestion": turning a
/// stack of scanned pages, camera shots, or the frames of a multi-page
/// TIFF (split to PNG/JPEG by the host) into a single PDF. It is built on
/// [CosDocumentBuilder] and [PdfEmbeddableImage]; it lives in pdf_document
/// rather than on the builder itself because the builder (pdf_cos) knows
/// nothing about image embedding.
///
/// No `dart:io`, so it runs on the VM and the web alike. JPEGs pass
/// through verbatim (DCTDecode); PNGs are decoded and re-deflated, with
/// transparency split into a soft mask (see [PdfEmbeddableImage]).
///
/// By default each page is sized to its image (one image pixel = one point
/// at the default 72 dpi). Pass a [pageSize] to lay the images onto a fixed
/// page instead - A4, Letter, anything - with a [fit] and [align] (and an
/// optional [margin]).
class PdfImageDocument {
  PdfImageDocument._();

  /// Assembles a PDF from raw image [bytes], sniffing JPEG vs PNG per entry
  /// ([PdfEmbeddableImage.decode]). See [fromImages] for the placement
  /// parameters.
  static Uint8List fromImageBytes(
    Iterable<Uint8List> bytes, {
    double dpi = 72,
    PdfPageSize? pageSize,
    PdfImageFit fit = PdfImageFit.contain,
    PdfImageAlign align = PdfImageAlign.center,
    double margin = 0,
  }) =>
      fromImages(
        [for (final b in bytes) PdfEmbeddableImage.decode(b)],
        dpi: dpi,
        pageSize: pageSize,
        fit: fit,
        align: align,
        margin: margin,
      );

  /// Assembles a PDF from decoded [images], one per page in order.
  ///
  /// With no [pageSize], each page is sized so its image renders at [dpi]
  /// dots per inch: at the default 72 one pixel maps to one PDF point; 150
  /// or 300 shrink the page for a high-resolution scan. The image fills the
  /// page edge to edge.
  ///
  /// With a [pageSize], every page is that fixed size and the image is laid
  /// inside the content box (the page minus [margin] points on every side)
  /// according to [fit] and [align]. Under [PdfImageFit.none] the image
  /// keeps its natural [dpi] size; the other fits scale relative to the
  /// content box and ignore [dpi].
  static Uint8List fromImages(
    List<PdfEmbeddableImage> images, {
    double dpi = 72,
    PdfPageSize? pageSize,
    PdfImageFit fit = PdfImageFit.contain,
    PdfImageAlign align = PdfImageAlign.center,
    double margin = 0,
  }) {
    if (images.isEmpty) {
      throw ArgumentError.value(images, 'images', 'provide at least one image');
    }
    if (dpi <= 0) {
      throw ArgumentError.value(dpi, 'dpi', 'must be positive');
    }
    if (margin < 0) {
      throw ArgumentError.value(margin, 'margin', 'must not be negative');
    }

    final builder = CosDocumentBuilder();
    final pagesDict = CosDictionary({'Type': const CosName('Pages')});
    final pagesRef = builder.add(pagesDict);

    final scale = 72 / dpi;
    final kids = <CosReference>[];
    for (final image in images) {
      final naturalW = image.width * scale;
      final naturalH = image.height * scale;

      // toXObject registers the soft mask (if any) before returning the
      // image stream, so the mask is numbered first - both go to builder.
      final xobjectRef = builder.add(image.toXObject(builder.add));

      final double pageW;
      final double pageH;
      final _Placement place;
      if (pageSize == null) {
        // Page sized to the image; the image fills it edge to edge.
        pageW = naturalW;
        pageH = naturalH;
        place = _Placement(naturalW, naturalH, 0, 0, clip: false);
      } else {
        pageW = pageSize.width;
        pageH = pageSize.height;
        place = _fit(
          naturalW: naturalW,
          naturalH: naturalH,
          pageW: pageW,
          pageH: pageH,
          fit: fit,
          align: align,
          margin: margin,
        );
      }

      final writer = ContentWriter()..save();
      if (place.clip) {
        writer
          ..rect(margin, margin, pageW - 2 * margin, pageH - 2 * margin)
          ..clip();
      }
      writer
        ..concatMatrix(place.width, 0, 0, place.height, place.x, place.y)
        ..drawXObject('Im0')
        ..restore();
      final contentBytes = writer.takeBytes();
      final contentRef = builder.add(CosStream(
          CosDictionary({'Length': CosInteger(contentBytes.length)}),
          contentBytes));

      kids.add(builder.add(CosDictionary({
        'Type': const CosName('Page'),
        'Parent': pagesRef,
        'MediaBox': CosArray([
          const CosInteger(0),
          const CosInteger(0),
          CosReal(pageW),
          CosReal(pageH),
        ]),
        'Resources': CosDictionary({
          'XObject': CosDictionary({'Im0': xobjectRef}),
        }),
        'Contents': contentRef,
      })));
    }

    pagesDict['Kids'] = CosArray([...kids]);
    pagesDict['Count'] = CosInteger(kids.length);
    final catalogRef = builder.add(CosDictionary({
      'Type': const CosName('Catalog'),
      'Pages': pagesRef,
    }));
    return builder.build(root: catalogRef);
  }

  /// Computes the draw size and bottom-left origin (the `cm` operands) for
  /// an image of [naturalW]×[naturalH] points placed onto a [pageW]×[pageH]
  /// page under [fit]/[align], inside the content box inset by [margin].
  static _Placement _fit({
    required double naturalW,
    required double naturalH,
    required double pageW,
    required double pageH,
    required PdfImageFit fit,
    required PdfImageAlign align,
    required double margin,
  }) {
    final boxW = (pageW - 2 * margin).clamp(0.0, double.infinity);
    final boxH = (pageH - 2 * margin).clamp(0.0, double.infinity);

    double drawW;
    double drawH;
    switch (fit) {
      case PdfImageFit.fill:
        drawW = boxW;
        drawH = boxH;
      case PdfImageFit.none:
        drawW = naturalW;
        drawH = naturalH;
      case PdfImageFit.contain:
      case PdfImageFit.cover:
        final sx = naturalW > 0 ? boxW / naturalW : 1.0;
        final sy = naturalH > 0 ? boxH / naturalH : 1.0;
        final s = fit == PdfImageFit.contain
            ? (sx < sy ? sx : sy)
            : (sx > sy ? sx : sy);
        drawW = naturalW * s;
        drawH = naturalH * s;
    }

    // align.x −1→0 (left), 0→0.5 (centre), 1→1 (right); same for y with
    // −1 at the content-box bottom (PDF y-up).
    final ax = (align.x + 1) / 2;
    final ay = (align.y + 1) / 2;
    final x = margin + (boxW - drawW) * ax;
    final y = margin + (boxH - drawH) * ay;

    // Clip whenever the drawn image can spill past the content box (cover,
    // none, or a non-zero margin), so margins are honoured and overflow is
    // trimmed. Harmless when the image already fits.
    final clip = fit == PdfImageFit.cover ||
        fit == PdfImageFit.none ||
        margin > 0;
    return _Placement(drawW, drawH, x, y, clip: clip);
  }
}

/// The resolved geometry for drawing one image: its scaled size, its
/// bottom-left origin in page space, and whether to clip to the content box.
class _Placement {
  const _Placement(this.width, this.height, this.x, this.y,
      {required this.clip});

  final double width;
  final double height;
  final double x;
  final double y;
  final bool clip;
}
