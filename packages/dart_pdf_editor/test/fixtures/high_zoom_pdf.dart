import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';

/// Browser-safe geometry for high-zoom tests. The general fixture package
/// also exports native CAD generators with 64-bit random-number arithmetic.
Uint8List buildHighZoomPagePdf() {
  final builder = CosDocumentBuilder();
  final pages = CosDictionary({'Type': const CosName('Pages')});
  final pagesRef = builder.add(pages);
  final font = builder.add(CosDictionary({
    'Type': const CosName('Font'),
    'Subtype': const CosName('Type1'),
    'BaseFont': const CosName('Helvetica'),
  }));
  final page = builder.add(CosDictionary({
    'Type': const CosName('Page'),
    'Parent': pagesRef,
    'MediaBox': CosArray([0, 0, 612, 792].map(CosInteger.new).toList()),
    'Resources': CosDictionary({
      'Font': CosDictionary({'F1': font}),
    }),
    'Contents': builder.add(CosStream(
      CosDictionary(),
      Uint8List.fromList('BT /F1 12 Tf 72 720 Td (High zoom) Tj ET'.codeUnits),
    )),
  }));
  pages['Kids'] = CosArray([page]);
  pages['Count'] = const CosInteger(1);
  return builder.build(
      root: builder.add(CosDictionary(
          {'Type': const CosName('Catalog'), 'Pages': pagesRef})));
}
