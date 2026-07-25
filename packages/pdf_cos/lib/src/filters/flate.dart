import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../objects.dart';
import 'filters.dart';

/// FlateDecode: zlib/deflate, optionally followed by a PNG/TIFF predictor.
class FlateFilter extends CosFilter {
  const FlateFilter();

  @override
  Uint8List decode(Uint8List data, CosDictionary? params) {
    // decodeBytes already returns a Uint8List; copying it again would double
    // the allocation for every inflated stream in the document (#533).
    final inflated = const ZLibDecoder().decodeBytes(data);
    return applyPredictor(inflated, params);
  }
}
