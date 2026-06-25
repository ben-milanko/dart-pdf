// A tiny CLI that assembles a PDF from one or more JPEG/PNG images — the
// pure-Dart image→PDF pipeline ([PdfImageDocument]).
//
// Usage:
//   dart run example/image_to_pdf.dart out.pdf scan1.jpg scan2.png ...
//
// Options (before the output path):
//   --a4 | --letter      lay each image onto a fixed page (default: page
//                        sized to the image)
//   --dpi=N              image resolution (default 72; raise for scans)
//   --fit=contain|cover|fill|none   fit within the fixed page (default
//                        contain)
//   --margin=N          points of margin around the image on a fixed page
//
// `dart:io` here is fine — this is an example/CLI, not library code. The
// library half ([PdfImageDocument]) stays pure Dart and web-safe.
import 'dart:io';

import 'package:pdf_document/pdf_document.dart';

void main(List<String> args) {
  PdfPageSize? pageSize;
  var dpi = 72.0;
  var fit = PdfImageFit.contain;
  var margin = 0.0;
  final positional = <String>[];

  for (final arg in args) {
    switch (arg) {
      case '--a4':
        pageSize = PdfPageSize.a4;
      case '--letter':
        pageSize = PdfPageSize.letter;
      case _ when arg.startsWith('--dpi='):
        dpi = double.parse(arg.substring('--dpi='.length));
      case _ when arg.startsWith('--margin='):
        margin = double.parse(arg.substring('--margin='.length));
      case _ when arg.startsWith('--fit='):
        fit = PdfImageFit.values.byName(arg.substring('--fit='.length));
      case _ when arg.startsWith('--'):
        stderr.writeln('unknown option: $arg');
        exit(64);
      default:
        positional.add(arg);
    }
  }

  if (positional.length < 2) {
    stderr.writeln('usage: dart run example/image_to_pdf.dart '
        '[--a4|--letter] [--dpi=N] [--fit=contain|cover|fill|none] '
        '[--margin=N] out.pdf image1 [image2 ...]');
    exit(64);
  }

  final outPath = positional.first;
  final imagePaths = positional.skip(1);
  final images = [
    for (final path in imagePaths) File(path).readAsBytesSync(),
  ];

  final pdf = PdfImageDocument.fromImageBytes(
    images,
    dpi: dpi,
    pageSize: pageSize,
    fit: fit,
    margin: margin,
  );

  File(outPath).writeAsBytesSync(pdf);
  stdout.writeln('wrote $outPath (${images.length} page'
      '${images.length == 1 ? '' : 's'}, ${pdf.length} bytes)');
}
