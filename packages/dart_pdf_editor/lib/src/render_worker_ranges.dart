import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';

/// Captures metadata before a worker copies/transfers the source bytes.
List<int>? renderWorkerPopulatedRanges(Uint8List bytes,
    [List<int>? populatedRanges]) {
  final ranges = populatedRanges ?? cosSparseBufferRanges[bytes];
  return ranges == null ? null : List<int>.unmodifiable(ranges);
}

/// Keeps the shared prefix's holes and marks the appended revision populated.
/// An undo has no append; clipping also drops ranges beyond its shorter EOF.
List<int>? renderWorkerRevisionRanges(
    List<int>? ranges, int baseLength, int newLength) {
  if (ranges == null) return null;
  final result = <int>[];
  for (var i = 0; i < ranges.length; i += 2) {
    if (ranges[i] >= baseLength) break;
    result.addAll([ranges[i], math.min(ranges[i + 1], baseLength)]);
  }
  if (newLength > baseLength) {
    if (result.isNotEmpty && result.last == baseLength) {
      result[result.length - 1] = newLength;
    } else {
      result.addAll([baseLength, newLength]);
    }
  }
  return List<int>.unmodifiable(result);
}
