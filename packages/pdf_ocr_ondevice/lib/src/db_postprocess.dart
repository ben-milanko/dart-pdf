import 'dart:typed_data';

import 'package:flutter/painting.dart';

/// A text region found by detection, as an axis-aligned box in the original
/// image's pixel space (top-left origin, y down) with the mean detector
/// probability over its pixels.
class DetectedBox {
  const DetectedBox({required this.rect, required this.score});

  final Rect rect;
  final double score;
}

/// Extracts text boxes from a DB-style detection probability map.
///
/// [probMap] is a row-major `width` x `height` map of values in `[0, 1]`
/// (the detector's per-pixel text probability). The map is binarized at
/// [threshold]; each 4-connected blob becomes one axis-aligned box, dropped
/// if its mean probability is below [boxScoreThreshold] or it is smaller than
/// [minSize] on either side. Boxes are dilated by [unclipRatio] (DB shrinks
/// text regions during training, so detections are tightened; expanding
/// recovers the full glyph extent) and finally scaled by [scaleX]/[scaleY]
/// back into the original image's pixels.
///
/// This uses axis-aligned bounding boxes rather than rotated min-area rects:
/// the OCR layer this feeds (`PdfEditor.injectTextLayer`) places horizontal
/// runs, and axis-aligned boxes keep the post-process pure-Dart and robust.
List<DetectedBox> extractDetectionBoxes(
  Float32List probMap,
  int width,
  int height, {
  double threshold = 0.3,
  double boxScoreThreshold = 0.5,
  double unclipRatio = 1.6,
  int minSize = 3,
  double scaleX = 1.0,
  double scaleY = 1.0,
}) {
  final visited = Uint8List(width * height);
  final boxes = <DetectedBox>[];
  final stack = <int>[];

  for (var start = 0; start < probMap.length; start++) {
    if (visited[start] != 0 || probMap[start] < threshold) continue;
    // Flood-fill this connected component.
    var minX = width, minY = height, maxX = -1, maxY = -1;
    var sum = 0.0;
    var count = 0;
    stack.add(start);
    visited[start] = 1;
    while (stack.isNotEmpty) {
      final idx = stack.removeLast();
      final x = idx % width;
      final y = idx ~/ width;
      sum += probMap[idx];
      count++;
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
      // 4-neighbours.
      if (x > 0) _push(stack, visited, probMap, idx - 1, threshold);
      if (x < width - 1) _push(stack, visited, probMap, idx + 1, threshold);
      if (y > 0) _push(stack, visited, probMap, idx - width, threshold);
      if (y < height - 1) {
        _push(stack, visited, probMap, idx + width, threshold);
      }
    }

    final boxW = maxX - minX + 1;
    final boxH = maxY - minY + 1;
    if (boxW < minSize || boxH < minSize) continue;
    final score = sum / count;
    if (score < boxScoreThreshold) continue;

    // Unclip: grow the box about its centre.
    final cx = (minX + maxX + 1) / 2;
    final cy = (minY + maxY + 1) / 2;
    final halfW = boxW / 2 * unclipRatio;
    final halfH = boxH / 2 * unclipRatio;
    final rect = Rect.fromLTRB(
      ((cx - halfW) * scaleX).clamp(0.0, width * scaleX),
      ((cy - halfH) * scaleY).clamp(0.0, height * scaleY),
      ((cx + halfW) * scaleX).clamp(0.0, width * scaleX),
      ((cy + halfH) * scaleY).clamp(0.0, height * scaleY),
    );
    boxes.add(DetectedBox(rect: rect, score: score));
  }

  // Top-to-bottom, then left-to-right — a reasonable reading order for the
  // (independent) runs an OCR text layer holds.
  boxes.sort((a, b) {
    final dy = a.rect.top.compareTo(b.rect.top);
    return dy != 0 ? dy : a.rect.left.compareTo(b.rect.left);
  });
  return boxes;
}

void _push(List<int> stack, Uint8List visited, Float32List map, int idx,
    double threshold) {
  if (visited[idx] == 0 && map[idx] >= threshold) {
    visited[idx] = 1;
    stack.add(idx);
  }
}
