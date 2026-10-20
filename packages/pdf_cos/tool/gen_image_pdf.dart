// Generates a synthetic image-heavy multi-page PDF for the web memory perf
// harness (issue #283). Each page draws one full-page RGB image XObject; the
// images differ per page so the decoded-image cache can't dedup them, giving a
// per-page decoded-RGBA footprint like a scanned/photo document.
//
//   fvm dart run packages/pdf_cos/tool/gen_image_pdf.dart <out.pdf> [pages] [w] [h]
//
// Defaults: 62 pages, 1240x1650 px images (~8.2 MB decoded RGBA each), so the
// whole document decodes to ~500 MB of RGBA - the shape issue #283 measured.
import 'dart:io';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';

void main(List<String> args) {
  final outPath = args.isNotEmpty ? args[0] : 'perf_images.pdf';
  final pageCount = args.length > 1 ? int.parse(args[1]) : 62;
  final imgW = args.length > 2 ? int.parse(args[2]) : 1240;
  final imgH = args.length > 3 ? int.parse(args[3]) : 1650;
  // Vector rectangles drawn per page on top of the image, so each page's
  // retained scene / ui.Picture carries print/CAD-like weight.
  final richOps = args.length > 4 ? int.parse(args[4]) : 4000;

  const pageW = 612.0; // US Letter, points
  const pageH = 792.0;

  final builder = CosDocumentBuilder();
  final zlib = ZLibCodec(level: 6);
  // Reused across pages: every page overwrites all imgW*imgH*3 bytes, so one
  // buffer avoids reallocating ~imgW*imgH*3 bytes per page.
  final rgb = Uint8List(imgW * imgH * 3);

  // Object numbers are assigned in registration order starting at 1:
  //   1 = catalog, 2 = pages tree, then per page i (0-based), three objects
  //   in this add() order: content = 3+i*3, image = 3+i*3+1, page = 3+i*3+2.
  const catalogNum = 1;
  const treeNum = 2;
  final treeRef = const CosReference(treeNum, 0);

  final pageRefs = [
    for (var i = 0; i < pageCount; i++) CosReference(3 + i * 3 + 2, 0),
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

  for (var i = 0; i < pageCount; i++) {
    final contentRef = CosReference(3 + i * 3, 0);
    final imageRef = CosReference(3 + i * 3 + 1, 0);

    // 1) content stream (obj 3+i*3): the full-page image plus a few thousand
    // vector ops, so each page's retained scene / ui.Picture carries real
    // weight (like a print/CAD page), not a single Do. A small LCG seeded by
    // the page index places the shapes so every page differs.
    final sb = StringBuffer('q\n$pageW 0 0 $pageH 0 0 cm\n/Im0 Do\nQ\n');
    var seed = (i + 1) * 2654435761 & 0x7fffffff;
    int next() {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      return seed;
    }

    for (var k = 0; k < richOps; k++) {
      final x = (next() % 1000000) / 1000000 * pageW;
      final y = (next() % 1000000) / 1000000 * pageH;
      final w = (next() % 40) + 4;
      final h = (next() % 40) + 4;
      final r = (next() % 256) / 255;
      final g = (next() % 256) / 255;
      final b = (next() % 256) / 255;
      sb.write('${r.toStringAsFixed(3)} ${g.toStringAsFixed(3)} '
          '${b.toStringAsFixed(3)} rg\n'
          '${x.toStringAsFixed(2)} ${y.toStringAsFixed(2)} $w $h re\nf\n');
    }
    final contentRaw = Uint8List.fromList(sb.toString().codeUnits);
    final contentBytes = Uint8List.fromList(zlib.encode(contentRaw));
    builder.add(CosStream(
      CosDictionary({
        'Length': CosInteger(contentBytes.length),
        'Filter': const CosName('FlateDecode'),
      }),
      contentBytes,
    ));

    // 2) image xobject (obj 3+i*3+1): distinct pixels per page so the
    // decoded-image cache can't dedup, but HIGHLY compressible (coarse
    // horizontal bands, constant within each band and across a row) so the
    // file stays small - the decode still expands to the full RGBA footprint.
    // This matches the real doc's shape (24 MB file, 436 MB decoded RGBA):
    // it's the decoded size, not the file size, that drives the tab memory.
    final phase = i * 37;
    var p = 0;
    for (var y = 0; y < imgH; y++) {
      final band = (y ~/ 24);
      final r = (band + phase) & 0xFF;
      final g = (band * 2 + phase * 2) & 0xFF;
      final b = (band * 3 + phase * 3) & 0xFF;
      for (var x = 0; x < imgW; x++) {
        rgb[p++] = r;
        rgb[p++] = g;
        rgb[p++] = b;
      }
    }
    final compressed = Uint8List.fromList(zlib.encode(rgb));
    builder.add(CosStream(
      CosDictionary({
        'Type': const CosName('XObject'),
        'Subtype': const CosName('Image'),
        'Width': CosInteger(imgW),
        'Height': CosInteger(imgH),
        'ColorSpace': const CosName('DeviceRGB'),
        'BitsPerComponent': CosInteger(8),
        'Filter': const CosName('FlateDecode'),
        'Length': CosInteger(compressed.length),
      }),
      compressed,
    ));

    // 3) page dict (obj 3+i*3+2)
    builder.add(CosDictionary({
      'Type': const CosName('Page'),
      'Parent': treeRef,
      'MediaBox': CosArray([
        CosInteger(0),
        CosInteger(0),
        CosReal(pageW),
        CosReal(pageH),
      ]),
      'Resources': CosDictionary({
        'XObject': CosDictionary({'Im0': imageRef}),
      }),
      'Contents': contentRef,
    }));
  }

  final bytes = builder.build(root: const CosReference(catalogNum, 0));
  File(outPath).writeAsBytesSync(bytes);
  stdout.writeln('wrote $outPath: ${bytes.length} bytes, $pageCount pages, '
      'image ${imgW}x$imgH (~${(imgW * imgH * 4 / 1e6).toStringAsFixed(1)} MB '
      'RGBA/page, ~${(imgW * imgH * 4 * pageCount / 1e6).toStringAsFixed(0)} MB total)');
}
