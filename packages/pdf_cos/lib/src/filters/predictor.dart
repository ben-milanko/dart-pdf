import 'dart:typed_data';

import '../exceptions.dart';
import '../objects.dart';

int _intParam(CosDictionary? params, String key, int fallback) {
  final v = params?[key];
  return v is CosInteger ? v.value : fallback;
}

/// Reverses the /Predictor transform described by a filter's /DecodeParms
/// (ISO 32000-1 §7.4.4.4). Returns [data] unchanged when no predictor is set.
Uint8List applyPredictor(Uint8List data, CosDictionary? params) {
  final predictor = _intParam(params, 'Predictor', 1);
  if (predictor <= 1) return data;

  final colors = _intParam(params, 'Colors', 1);
  final bitsPerComponent = _intParam(params, 'BitsPerComponent', 8);
  final columns = _intParam(params, 'Columns', 1);
  final bytesPerPixel = (colors * bitsPerComponent + 7) ~/ 8;
  final bytesPerRow = (colors * bitsPerComponent * columns + 7) ~/ 8;

  if (predictor == 2) {
    if (bitsPerComponent != 8 && bitsPerComponent != 16) {
      throw CosParseException(
          'TIFF predictor with $bitsPerComponent bits per component '
          'is not supported yet');
    }
    if (bitsPerComponent == 8) {
      for (var row = 0; row + bytesPerRow <= data.length; row += bytesPerRow) {
        for (var i = bytesPerPixel; i < bytesPerRow; i++) {
          data[row + i] =
              (data[row + i] + data[row + i - bytesPerPixel]) & 0xFF;
        }
      }
    } else {
      // Predictor 2 differences *samples*, not bytes. A 16-bit PDF sample is
      // big-endian, so reconstruct each component modulo 65536 from the same
      // component in the pixel immediately to its left. Byte-wise addition
      // loses carries and is the reason every 16-bit Ghent image used to be
      // rejected (or would have decoded into vertical colour bands).
      final view = ByteData.sublistView(data);
      for (var row = 0; row + bytesPerRow <= data.length; row += bytesPerRow) {
        for (var i = bytesPerPixel; i < bytesPerRow; i += 2) {
          final delta = view.getUint16(row + i);
          final left = view.getUint16(row + i - bytesPerPixel);
          view.setUint16(row + i, (delta + left) & 0xFFFF);
        }
      }
    }
    return data;
  }

  // PNG predictors (10..15): every row is prefixed with a filter-type byte.
  // The filter type is constant across a row, so dispatch once per row into a
  // specialised loop rather than branching per byte. Filter 0 (None) is a
  // straight copy.
  final rowCount = data.length ~/ (bytesPerRow + 1);
  final out = Uint8List(rowCount * bytesPerRow);
  final prior = Uint8List(bytesPerRow);
  var inPos = 0;
  var outPos = 0;
  final bpp = bytesPerPixel;
  for (var r = 0; r < rowCount; r++) {
    final filter = data[inPos++];
    switch (filter) {
      case 0: // None
        out.setRange(outPos, outPos + bytesPerRow, data, inPos);
      case 1: // Sub
        for (var i = 0; i < bpp; i++) {
          out[outPos + i] = data[inPos + i] & 0xFF;
        }
        for (var i = bpp; i < bytesPerRow; i++) {
          out[outPos + i] = (data[inPos + i] + out[outPos + i - bpp]) & 0xFF;
        }
      case 2: // Up
        for (var i = 0; i < bytesPerRow; i++) {
          out[outPos + i] = (data[inPos + i] + prior[i]) & 0xFF;
        }
      case 3: // Average
        for (var i = 0; i < bytesPerRow; i++) {
          final left = i >= bpp ? out[outPos + i - bpp] : 0;
          out[outPos + i] = (data[inPos + i] + ((left + prior[i]) >> 1)) & 0xFF;
        }
      case 4: // Paeth
        for (var i = 0; i < bytesPerRow; i++) {
          final left = i >= bpp ? out[outPos + i - bpp] : 0;
          final upLeft = i >= bpp ? prior[i - bpp] : 0;
          out[outPos + i] =
              (data[inPos + i] + _paeth(left, prior[i], upLeft)) & 0xFF;
        }
      default:
        throw CosParseException('invalid PNG predictor filter byte $filter');
    }
    inPos += bytesPerRow;
    prior.setRange(0, bytesPerRow, out, outPos);
    outPos += bytesPerRow;
  }
  return out;
}

int _paeth(int a, int b, int c) {
  final p = a + b - c;
  final pa = (p - a).abs();
  final pb = (p - b).abs();
  final pc = (p - c).abs();
  if (pa <= pb && pa <= pc) return a;
  if (pb <= pc) return b;
  return c;
}
