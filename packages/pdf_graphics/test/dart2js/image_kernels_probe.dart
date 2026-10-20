// Compiled (never run) by test/image_kernels_dart2js_test.dart: reaches the
// masked-image kernels through the entry points the web render worker calls,
// with inputs dart2js cannot see through, so they compile as they do there.
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

void main(List<String> args) {
  final cos = CosDocument.open(Uint8List(args.length));
  final image = cos.resolve(CosReference(args.length, 0));
  if (image is! CosStream) return;
  final n = args.length + 1;
  // Whole-image downscale (the worker's record) and a deep-zoom slice.
  print(decodePdfImage(cos, image, targetWidth: n, targetHeight: n)?.width);
  print(decodePdfImage(cos, image,
          region: PdfImageRegion(0, 0, n, n), targetWidth: 1, targetHeight: 1)
      ?.width);
  print(tryAssignedSampleSum(cos, image));
}

/// The shape the kernels must not take - samples assigned inside a `try` and
/// read in a loop. The test checks this still compiles to interceptor calls,
/// so a pass over the kernels means their reads are native, not that the
/// check stopped seeing the pattern.
int tryAssignedSampleSum(CosDocument cos, CosStream stream) {
  final Uint8List data;
  try {
    data = cos.decodeStreamData(stream);
  } on Exception {
    return 0;
  }
  var sum = 0;
  for (var i = 0; i < data.length; i++) {
    sum += data[i];
  }
  return sum;
}
