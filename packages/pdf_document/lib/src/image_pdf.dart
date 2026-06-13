import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';

import 'content_writer.dart';
import 'image.dart';

/// Assembles a brand-new PDF from a list of raster images — one page per
/// image, each image filling its page.
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
class PdfImageDocument {
  PdfImageDocument._();

  /// Assembles a PDF from raw image [bytes], sniffing JPEG vs PNG per entry
  /// ([PdfEmbeddableImage.decode]). See [fromImages] for [dpi].
  static Uint8List fromImageBytes(Iterable<Uint8List> bytes, {double dpi = 72}) =>
      fromImages(
        [for (final b in bytes) PdfEmbeddableImage.decode(b)],
        dpi: dpi,
      );

  /// Assembles a PDF from decoded [images], one per page in order.
  ///
  /// Each page is sized so the image renders at [dpi] dots per inch: at the
  /// default 72 one pixel maps to one PDF point; 150 or 300 shrink the page
  /// for a high-resolution scan. The image fills the page edge to edge.
  static Uint8List fromImages(List<PdfEmbeddableImage> images,
      {double dpi = 72}) {
    if (images.isEmpty) {
      throw ArgumentError.value(images, 'images', 'provide at least one image');
    }
    if (dpi <= 0) {
      throw ArgumentError.value(dpi, 'dpi', 'must be positive');
    }

    final builder = CosDocumentBuilder();
    final pagesDict = CosDictionary({'Type': const CosName('Pages')});
    final pagesRef = builder.add(pagesDict);

    final scale = 72 / dpi;
    final kids = <CosReference>[];
    for (final image in images) {
      final w = image.width * scale;
      final h = image.height * scale;
      // toXObject registers the soft mask (if any) before returning the
      // image stream, so the mask is numbered first — both go to builder.
      final xobjectRef = builder.add(image.toXObject(builder.add));

      final content = 'q ${ContentWriter.fmt(w)} 0 0 ${ContentWriter.fmt(h)} '
          '0 0 cm /Im0 Do Q\n';
      final contentBytes = Uint8List.fromList(latin1.encode(content));
      final contentRef = builder.add(CosStream(
          CosDictionary({'Length': CosInteger(contentBytes.length)}),
          contentBytes));

      kids.add(builder.add(CosDictionary({
        'Type': const CosName('Page'),
        'Parent': pagesRef,
        'MediaBox': CosArray([
          const CosInteger(0),
          const CosInteger(0),
          CosReal(w),
          CosReal(h),
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
}
