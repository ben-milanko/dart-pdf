import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';

import 'image_pdf.dart';

/// Builds a new PDF containing one or more empty pages.
///
/// The pages have an empty resource dictionary and no content stream, ready
/// for annotation authoring, content stamping, or page insertion through
/// `PdfEditor`. The output is a standalone, unencrypted PDF.
class PdfBlankDocument {
  PdfBlankDocument._();

  /// Creates [pageCount] blank pages of [pageSize].
  ///
  /// The default is US Letter. Use [PdfPageSize.portrait] or
  /// [PdfPageSize.landscape] to choose the orientation explicitly.
  static Uint8List create({
    PdfPageSize pageSize = PdfPageSize.letter,
    int pageCount = 1,
  }) {
    if (!pageSize.width.isFinite ||
        !pageSize.height.isFinite ||
        pageSize.width <= 0 ||
        pageSize.height <= 0) {
      throw ArgumentError.value(
        pageSize,
        'pageSize',
        'dimensions must be finite and positive',
      );
    }
    if (pageCount < 1) {
      throw ArgumentError.value(pageCount, 'pageCount', 'must be positive');
    }

    final builder = CosDocumentBuilder();
    final pages = CosDictionary({'Type': const CosName('Pages')});
    final pagesRef = builder.add(pages);
    final kids = <CosReference>[];
    for (var i = 0; i < pageCount; i++) {
      kids.add(builder.add(CosDictionary({
        'Type': const CosName('Page'),
        'Parent': pagesRef,
        'MediaBox': CosArray([
          const CosInteger(0),
          const CosInteger(0),
          CosReal(pageSize.width),
          CosReal(pageSize.height),
        ]),
        'Resources': CosDictionary(),
      })));
    }
    pages['Kids'] = CosArray(kids);
    pages['Count'] = CosInteger(pageCount);
    final catalogRef = builder.add(CosDictionary({
      'Type': const CosName('Catalog'),
      'Pages': pagesRef,
    }));
    return builder.build(root: catalogRef);
  }
}
