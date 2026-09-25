import 'dart:typed_data';

import '../objects.dart';
import 'filters.dart';

/// FlateDecode: zlib/deflate, optionally followed by a PNG/TIFF predictor.
///
/// The zlib layer is [inflateZlib], which ignores bytes after the stream on
/// every platform, as native zlib and pdf.js do.
class FlateFilter extends CosFilter {
  const FlateFilter();

  @override
  Uint8List decode(Uint8List data, CosDictionary? params) =>
      applyPredictor(inflateZlib(data), params);
}
