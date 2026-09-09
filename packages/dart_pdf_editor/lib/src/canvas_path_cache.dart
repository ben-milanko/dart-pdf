import 'dart:ui' as ui;

import 'package:pdf_graphics/pdf_graphics.dart';

import 'budgeted_cache.dart';

/// Native geometry owned by one immutable retained command transcript.
///
/// Building a dense sheet's hundreds of thousands of path verbs again at each
/// zoom stalls the UI isolate. These paths contain page-space geometry only;
/// transforms, paints, dashes, and clipping still run in their original order.
/// Never mutate either the source geometry or a returned path while retained.
/// Once full, the cache preserves its admitted subset: cycling an immutable
/// transcript larger than an LRU would otherwise evict every path before its
/// next use. Memory-pressure eviction reopens admission as space becomes free.
class PdfCanvasPathCache {
  PdfCanvasPathCache({int maxWeight = 32 << 20, int maxEntries = 65536})
      : _paths = PdfBudgetedCache<(PdfPath, PdfFillRule), _CanvasPath>(
          maxWeight: maxWeight,
          maxEntries: maxEntries,
          weigher: (value) => value.weight,
          rejectOversize: true,
          clearsUnderMemoryPressure: true,
          debugLabel: 'canvas-paths',
        );

  final PdfBudgetedCache<(PdfPath, PdfFillRule), _CanvasPath> _paths;

  ui.Path pathFor(PdfPath source, PdfFillRule rule, ui.Path Function() build) {
    final key = (source, rule);
    final cached = _paths.take(key);
    if (cached != null) return cached.path;
    final path = build();
    // Conservative estimate: a cubic needs six float32 coordinates and a
    // verb, plus per-path native/Dart/map overhead. Count is capped separately
    // because short paths also dominate some CAD exports.
    final weight = 192 + source.segmentCount * 32;
    if (_paths.length < _paths.maxEntries! &&
        weight <= _paths.maxWeight - _paths.weight) {
      _paths.put(key, _CanvasPath(path, weight));
    }
    return path;
  }

  void dispose() => _paths.dispose();
}

class _CanvasPath {
  const _CanvasPath(this.path, this.weight);
  final ui.Path path;
  final int weight;
}
