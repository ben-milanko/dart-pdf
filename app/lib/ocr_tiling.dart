import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

/// Pure (web-free) geometry and parsing for the browser OCR path, so the
/// tiling, Florence-2 result parsing, and overlap de-duplication can be unit
/// tested on the Dart VM - `ocr_web.dart` itself imports `dart:js_interop`
/// and so can't be loaded by `flutter test`.
///
/// Florence-2 resizes every input image to a fixed 768x768 square before it
/// looks at it, so handing it a whole multi-thousand-pixel scan crushes the
/// text to a few unreadable pixels and the model hallucinates plausible
/// tokens. The fix is to split the page raster into overlapping tiles that are
/// already close to the model's input size, recognize each, then map the
/// per-tile boxes back into full-page pixel space and drop the duplicates the
/// overlaps produce ([ocrTiles] + [parseFlorenceSpans] + [mergeOcrSpans]).

/// One recognized text run in raster-pixel space (top-left origin, y down) -
/// the space tiles and an image-based OCR engine both work in, before the
/// page geometry maps it to PDF user space.
class OcrRawSpan {
  const OcrRawSpan({
    required this.text,
    required this.box,
    this.confidence = 1,
  });

  final String text;
  final Rect box;
  final double confidence;

  /// A copy translated by ([dx], [dy]) - used to lift a tile-local box into
  /// full-page pixel coordinates by its tile's origin.
  OcrRawSpan shifted(double dx, double dy) => OcrRawSpan(
        text: text,
        box: box.shift(Offset(dx, dy)),
        confidence: confidence,
      );
}

/// Splits a [width] x [height] raster into a grid of overlapping tiles, each at
/// most [tileSize] px on a side, with neighbours sharing about [overlap] px so
/// a word straddling a seam stays wholly inside at least one tile. Tiles are
/// clamped to the image bounds, so the right/bottom column may overlap its
/// neighbour by more than [overlap]; a raster already within [tileSize] yields
/// a single full-image tile.
///
/// The point is legibility: Florence-2 downsamples whatever it is given to
/// 768x768, so each tile should be small enough that that downsample leaves
/// the text readable. [tileSize] 1024 keeps small print legible while bounding
/// the page to a handful of model calls.
List<Rect> ocrTiles(
  int width,
  int height, {
  int tileSize = 1024,
  int overlap = 128,
}) {
  if (width <= 0 || height <= 0) return const [];
  final int size = math.max(1, tileSize);
  final int step = math.max(1, size - math.max(0, overlap));

  // Tile-start offsets along one axis: step by `step` until a tile would run
  // off the end, then place a final tile flush against the far edge so the
  // whole extent is covered (the last two tiles overlap by whatever is left).
  List<int> starts(int extent) {
    if (extent <= size) return const [0];
    final out = <int>[];
    for (var s = 0; s < extent; s += step) {
      if (s + size >= extent) {
        out.add(extent - size);
        break;
      }
      out.add(s);
    }
    return out;
  }

  final xs = starts(width);
  final ys = starts(height);
  final tiles = <Rect>[];
  for (final y in ys) {
    for (final x in xs) {
      final w = math.min(size, width - x);
      final h = math.min(size, height - y);
      tiles.add(Rect.fromLTWH(x.toDouble(), y.toDouble(), w.toDouble(), h.toDouble()));
    }
  }
  return tiles;
}

/// Parses a Florence-2 `<OCR_WITH_REGION>` (or plain `<OCR>`) result [payload]
/// - already JSON-decoded - into raster-pixel spans. Boxes come back in
/// whatever pixel space the model was given; for a tile that is tile-local, so
/// the caller offsets each span by the tile origin ([OcrRawSpan.shifted]).
///
/// When the model returns only plain text with no boxes, a single span covers
/// the whole [fallbackWidth] x [fallbackHeight] region (the tile, or the page).
List<OcrRawSpan> parseFlorenceSpans(
  Object? payload, {
  required int fallbackWidth,
  required int fallbackHeight,
}) {
  final map = _payload(payload);
  final labels = _listOfStrings(map['labels']) ??
      _listOfStrings(map['text']) ??
      _listOfStrings(map['texts']);
  final boxes = _listOfBoxes(map['quad_boxes']) ??
      _listOfBoxes(map['quadBoxes']) ??
      _listOfBoxes(map['bboxes']) ??
      _listOfBoxes(map['boxes']);

  if (labels != null && boxes != null) {
    final spans = <OcrRawSpan>[];
    final count = math.min(labels.length, boxes.length);
    for (var i = 0; i < count; i++) {
      final text = labels[i].trim();
      final rect = boxes[i];
      if (text.isEmpty || rect.width <= 0 || rect.height <= 0) continue;
      spans.add(OcrRawSpan(text: text, box: rect));
    }
    return spans;
  }

  final text = _plainText(map).trim();
  if (text.isEmpty) return const [];
  return [
    OcrRawSpan(
      text: text,
      box: Rect.fromLTWH(0, 0, fallbackWidth.toDouble(), fallbackHeight.toDouble()),
    ),
  ];
}

/// Collapses near-duplicate spans produced where tiles overlap: two spans whose
/// text matches (trimmed, case-insensitive) and whose boxes overlap by more
/// than [iouThreshold] keep only the higher-confidence one. O(n^2), which is
/// fine for the few-hundred spans a page yields.
List<OcrRawSpan> mergeOcrSpans(
  List<OcrRawSpan> spans, {
  double iouThreshold = 0.5,
}) {
  final kept = <OcrRawSpan>[];
  for (final span in spans) {
    final key = span.text.trim().toLowerCase();
    var merged = false;
    for (var i = 0; i < kept.length; i++) {
      final other = kept[i];
      if (other.text.trim().toLowerCase() != key) continue;
      if (_iou(span.box, other.box) <= iouThreshold) continue;
      if (span.confidence > other.confidence) kept[i] = span;
      merged = true;
      break;
    }
    if (!merged) kept.add(span);
  }
  return kept;
}

double _iou(Rect a, Rect b) {
  final left = math.max(a.left, b.left);
  final top = math.max(a.top, b.top);
  final right = math.min(a.right, b.right);
  final bottom = math.min(a.bottom, b.bottom);
  if (right <= left || bottom <= top) return 0;
  final inter = (right - left) * (bottom - top);
  final union = a.width * a.height + b.width * b.height - inter;
  return union > 0 ? inter / union : 0;
}

Map<String, Object?> _payload(Object? value) {
  if (value is Map) {
    final ocrWithRegion = value['<OCR_WITH_REGION>'];
    if (ocrWithRegion is Map) return ocrWithRegion.cast<String, Object?>();
    final ocr = value['<OCR>'];
    if (ocr is Map) return ocr.cast<String, Object?>();
    return value.cast<String, Object?>();
  }
  if (value is String) return {'text': value};
  return const {};
}

List<String>? _listOfStrings(Object? value) {
  if (value is String) return [value];
  if (value is! List) return null;
  return [
    for (final item in value)
      if (item != null) item.toString()
  ];
}

List<Rect>? _listOfBoxes(Object? value) {
  if (value is! List) return null;
  final rects = <Rect>[];
  for (final item in value) {
    final rect = _rect(item);
    if (rect != null) rects.add(rect);
  }
  return rects.isEmpty ? null : rects;
}

Rect? _rect(Object? value) {
  if (value is! List || value.length < 4) return null;
  final nums = [
    for (final v in value)
      if (v is num) v.toDouble()
  ];
  if (nums.length < 4) return null;
  if (nums.length >= 8) {
    // A quad (x0,y0,...,x3,y3): take its axis-aligned bounds.
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (var i = 0; i + 1 < nums.length; i += 2) {
      final x = nums[i], y = nums[i + 1];
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }
  return Rect.fromLTRB(nums[0], nums[1], nums[2], nums[3]);
}

String _plainText(Map<String, Object?> payload) {
  for (final key in const ['text', 'ocr', 'generated_text']) {
    final value = payload[key];
    if (value is String) return value;
  }
  return '';
}
