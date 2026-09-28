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
///
/// Entries are keyed by the source [PdfPath] alone (its equality is identity),
/// with one slot per fill rule, so a lookup hashes one object instead of a
/// `(path, rule)` record. [maxEntries] therefore counts source paths, and the
/// registry's hit counter includes a path found without its rule's slot.
class PdfCanvasPathCache {
  PdfCanvasPathCache({int maxWeight = 32 << 20, int maxEntries = 65536})
      : _paths = PdfBudgetedCache<PdfPath, _CanvasPaths>(
          maxWeight: maxWeight,
          maxEntries: maxEntries,
          weigher: (value) => value.weight,
          rejectOversize: true,
          clearsUnderMemoryPressure: true,
          debugLabel: 'canvas-paths',
        );

  final PdfBudgetedCache<PdfPath, _CanvasPaths> _paths;

  ui.Path pathFor(PdfPath source, PdfFillRule rule, ui.Path Function() build) {
    final evenOdd = rule == PdfFillRule.evenOdd;
    // Admission never evicts, so recency stays insertion order and a hit need
    // not relink the LRU list: lookup rather than take. The registry ceiling's
    // hard trim then drops the earliest-painted paths first, which is the
    // order a touch would leave after any full replay anyway.
    final cached = _paths.lookup(source);
    final hit = evenOdd ? cached?.evenOdd : cached?.nonZero;
    if (hit != null) return hit;
    final path = build();
    // Conservative estimate: a cubic needs six float32 coordinates and a
    // verb, plus per-path native/Dart/map overhead. Count is capped separately
    // because short paths also dominate some CAD exports.
    final weight = 192 + source.segmentCount * 32;
    if (weight > _paths.maxWeight - _paths.weight) return path;
    if (cached == null) {
      if (_paths.length < _paths.maxEntries!) {
        _paths.put(
            source,
            evenOdd
                ? _CanvasPaths(null, path, weight)
                : _CanvasPaths(path, null, weight));
      }
    } else {
      // A known path drawn under its other rule (a B* fill and its stroke)
      // adds weight but no entry. The re-put replaces the entry with both
      // slots; there is no disposer, so the first path stays live in it.
      final combined = cached.weight + weight;
      _paths.put(
          source,
          evenOdd
              ? _CanvasPaths(cached.nonZero, path, combined)
              : _CanvasPaths(path, cached.evenOdd, combined));
    }
    return path;
  }

  void dispose() => _paths.dispose();
}

class _CanvasPaths {
  const _CanvasPaths(this.nonZero, this.evenOdd, this.weight);
  final ui.Path? nonZero;
  final ui.Path? evenOdd;
  final int weight;
}
