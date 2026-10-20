// Generates a synthetic DeviceN-image-heavy PDF that reproduces the shape
// #282 optimised: a large image whose ColorSpace is a 3-colorant /DeviceN with
// a type-4 (PostScript) tint transform to /DeviceCMYK. Decoding the image runs
// the tint transform per sample, so before #282 (memoise the transform per
// distinct sample tuple) a page paid one PS evaluation per PIXEL; after, one
// per distinct tuple. The samples are coarse horizontal bands (few distinct
// tuples, millions of pixels), which is the print/CAD shape where the
// memoisation turns 23.7 s into 98 ms.
//
//   fvm dart run packages/pdf_cos/tool/gen_devicen_pdf.dart <out.pdf> [pages] [w] [h]
//
// Defaults: 8 pages, 1240x1650 (a few million pixels/page over ~70 band tuples).
import 'dart:io';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';

void main(List<String> args) {
  final outPath = args.isNotEmpty ? args[0] : 'perf_devicen.pdf';
  final pageCount = args.length > 1 ? int.parse(args[1]) : 8;
  final imgW = args.length > 2 ? int.parse(args[2]) : 1240;
  final imgH = args.length > 3 ? int.parse(args[3]) : 1650;

  const pageW = 612.0;
  const pageH = 792.0;

  final builder = CosDocumentBuilder();
  final zlib = ZLibCodec(level: 6);
  final samples = Uint8List(imgW * imgH * 3); // 3 colorants/pixel

  // Object numbers: 1 catalog, 2 pages tree, 3 tint fn, 4 colorspace array,
  // then per page i: content = 5+i*3, image = 5+i*3+1, page = 5+i*3+2.
  const catalogNum = 1;
  const treeNum = 2;
  const tintNum = 3;
  const csNum = 4;
  final treeRef = const CosReference(treeNum, 0);
  final csRef = const CosReference(csNum, 0);

  final pageRefs = [
    for (var i = 0; i < pageCount; i++) CosReference(5 + i * 3 + 2, 0),
  ];

  builder.add(CosDictionary({
    'Type': const CosName('Catalog'),
    'Pages': treeRef,
  })); // obj 1
  builder.add(CosDictionary({
    'Type': const CosName('Pages'),
    'Kids': CosArray(pageRefs),
    'Count': CosInteger(pageCount),
  })); // obj 2

  // obj 3: type-4 tint transform, 3 colorants (in [0,1]) -> DeviceCMYK. A
  // little per-sample math so the pre-memoisation cost is real.
  final ps = '{ '
      '3 copy pop pop 0.6 mul '          // C = c0*0.6
      'exch 0.3 mul exch '               // (stack juggling for M)
      '4 index 0.8 mul '                 // Y = c2*0.8
      '5 index 4 index add 0.5 mul '     // K = (c0+c1)*0.5
      '5 4 roll pop pop pop '            // drop the 3 inputs
      '}';
  final psBytes = Uint8List.fromList(ps.codeUnits);
  builder.add(CosStream(
    CosDictionary({
      'FunctionType': CosInteger(4),
      'Domain': CosArray([
        CosInteger(0), CosInteger(1), CosInteger(0), CosInteger(1),
        CosInteger(0), CosInteger(1),
      ]),
      'Range': CosArray([
        CosInteger(0), CosInteger(1), CosInteger(0), CosInteger(1),
        CosInteger(0), CosInteger(1), CosInteger(0), CosInteger(1),
      ]),
      'Length': CosInteger(psBytes.length),
    }),
    psBytes,
  )); // obj 3

  // obj 4: /DeviceN colorspace over 3 named colorants -> DeviceCMYK via obj 3.
  builder.add(CosArray([
    const CosName('DeviceN'),
    CosArray([const CosName('C0'), const CosName('C1'), const CosName('C2')]),
    const CosName('DeviceCMYK'),
    const CosReference(tintNum, 0),
  ])); // obj 4

  for (var i = 0; i < pageCount; i++) {
    final contentRef = CosReference(5 + i * 3, 0);
    final imageRef = CosReference(5 + i * 3 + 1, 0);

    final content = 'q\n$pageW 0 0 $pageH 0 0 cm\n/Im0 Do\nQ\n';
    final contentBytes =
        Uint8List.fromList(zlib.encode(Uint8List.fromList(content.codeUnits)));
    builder.add(CosStream(
      CosDictionary({
        'Length': CosInteger(contentBytes.length),
        'Filter': const CosName('FlateDecode'),
      }),
      contentBytes,
    )); // content

    // Coarse horizontal bands: constant 3-colorant tuple within a 24px band,
    // distinct per page, so ~70 distinct tuples cover millions of pixels.
    final phase = i * 37;
    var p = 0;
    for (var y = 0; y < imgH; y++) {
      final band = y ~/ 24;
      final c0 = (band + phase) & 0xFF;
      final c1 = (band * 2 + phase) & 0xFF;
      final c2 = (band * 3 + phase * 2) & 0xFF;
      for (var x = 0; x < imgW; x++) {
        samples[p++] = c0;
        samples[p++] = c1;
        samples[p++] = c2;
      }
    }
    final compressed = Uint8List.fromList(zlib.encode(samples));
    builder.add(CosStream(
      CosDictionary({
        'Type': const CosName('XObject'),
        'Subtype': const CosName('Image'),
        'Width': CosInteger(imgW),
        'Height': CosInteger(imgH),
        'ColorSpace': csRef,
        'BitsPerComponent': CosInteger(8),
        'Filter': const CosName('FlateDecode'),
        'Length': CosInteger(compressed.length),
      }),
      compressed,
    )); // image

    builder.add(CosDictionary({
      'Type': const CosName('Page'),
      'Parent': treeRef,
      'MediaBox': CosArray([
        CosInteger(0), CosInteger(0), CosReal(pageW), CosReal(pageH),
      ]),
      'Resources': CosDictionary({
        'XObject': CosDictionary({'Im0': imageRef}),
      }),
      'Contents': contentRef,
    })); // page
  }

  final bytes = builder.build(root: const CosReference(catalogNum, 0));
  File(outPath).writeAsBytesSync(bytes);
  stdout.writeln('wrote $outPath: ${bytes.length} bytes, $pageCount pages, '
      'DeviceN image ${imgW}x$imgH (3 colorants -> CMYK, type-4 tint)');
}
