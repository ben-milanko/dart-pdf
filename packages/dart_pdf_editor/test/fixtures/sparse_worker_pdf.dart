import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';

/// Real objects deliberately sit inside the declared holes: losing the map
/// makes them render, so the regression needs neither a large file nor a timer.
({Uint8List bytes, List<int> ranges}) sparseWorkerPdf() {
  final editor = PdfEditor(PdfDocument.open(_threePages()))
    // Stamps have no synthesized fallback when their appearance is unfetched.
    ..addStamp(0, const PdfRect(20, 20, 120, 120), 'FETCHED');
  final bytes = editor.save();
  final whole = PdfDocument.open(bytes);
  final appearance = whole.page(0).annotations.single.normalAppearance!;
  final refs = [
    whole.page(1).dict['Contents'] as CosReference,
    whole.cos.referenceTo(appearance)!,
  ];
  final text = latin1.decode(bytes);
  final holes = refs.map((ref) {
    final start = text.indexOf('${ref.objectNumber} ${ref.generation} obj');
    if (start < 0) throw StateError('fixture object header missing');
    final end = text.indexOf('endobj', start) + 'endobj'.length;
    return (start, end);
  }).toList()
    ..sort((a, b) => a.$1.compareTo(b.$1));
  return (
    bytes: bytes,
    ranges: [
      0,
      for (final hole in holes) ...[hole.$1, hole.$2],
      bytes.length
    ],
  );
}

// Keep the fixture browser-safe; the general fixture package exports native
// performance generators whose 64-bit integer literals cannot compile to JS.
Uint8List _threePages() {
  final builder = CosDocumentBuilder();
  final pages = CosDictionary({
    'Type': CosName('Pages'),
    'Count': CosInteger(3),
  });
  final pagesRef = builder.add(pages);
  final font = builder.add(CosDictionary({
    'Type': CosName('Font'),
    'Subtype': CosName('Type1'),
    'BaseFont': CosName('Helvetica'),
  }));
  pages['Kids'] = CosArray([
    for (var i = 0; i < 3; i++)
      builder.add(CosDictionary({
        'Type': CosName('Page'),
        'Parent': pagesRef,
        'MediaBox': CosArray([0, 0, 612, 792].map(CosInteger.new).toList()),
        'Resources': CosDictionary({
          'Font': CosDictionary({'F1': font})
        }),
        'Contents': builder.add(CosStream(
          CosDictionary(),
          Uint8List.fromList(
              ascii.encode('BT /F1 24 Tf 72 720 Td (Page ${i + 1}) Tj ET')),
        )),
      })),
  ]);
  return builder.build(
      root: builder.add(CosDictionary({
    'Type': CosName('Catalog'),
    'Pages': pagesRef,
  })));
}
