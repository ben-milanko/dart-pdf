import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

/// Bounded, painter-order-preserving index for retained region replay.
///
/// Each entry is one independent paint operation plus a persistent snapshot
/// of the clips and blend mode active at that point in the command stream.
/// Transparency/soft-mask groups remain on the full-replay path: splitting a
/// group would change its isolated compositing semantics.
class PdfRegionReplayIndex {
  PdfRegionReplayIndex._({
    required this.supported,
    required this.units,
    required this.clipNodeCount,
    this.grid,
  });

  factory PdfRegionReplayIndex.build(
    List<PdfRenderCommand> commands, {
    required int maxCommands,
    int maxStateDepth = 128,
    bool buildGrid = false,
  }) {
    if (commands.length > maxCommands) {
      return PdfRegionReplayIndex._(
        supported: false,
        units: const [],
        clipNodeCount: 0,
      );
    }

    final units = <PdfRegionReplayUnit>[];
    final savedClips = <PdfRegionClipState?>[];
    PdfRegionClipState? clips;
    var blendMode = PdfBlendMode.normal;
    var clipNodes = 0;

    for (var i = 0; i < commands.length; i++) {
      final command = commands[i];
      switch (command) {
        case PdfSaveCommand():
          if (savedClips.length >= maxStateDepth) {
            return PdfRegionReplayIndex._(
              supported: false,
              units: const [],
              clipNodeCount: clipNodes,
            );
          }
          savedClips.add(clips);
        case PdfRestoreCommand():
          if (savedClips.isEmpty) {
            return PdfRegionReplayIndex._(
              supported: false,
              units: const [],
              clipNodeCount: clipNodes,
            );
          }
          clips = savedClips.removeLast();
        case PdfClipPathCommand(:final path):
          final bounds = pdfRenderPathBounds(path);
          clips = PdfRegionClipState(
            parent: clips,
            command: command,
            aggregateBounds: _clipIntersection(clips, bounds),
            empty: (clips?.empty ?? false) ||
                bounds == null ||
                (clips?.aggregateBounds != null &&
                    !_intersects(clips!.aggregateBounds!, bounds)),
          );
          clipNodes++;
        case PdfSetBlendModeCommand(:final mode):
          blendMode = mode;
        case PdfBeginGroupCommand() ||
              PdfEndGroupCommand() ||
              PdfBeginSoftMaskedCommand() ||
              PdfEndSoftMaskedCommand():
          return PdfRegionReplayIndex._(
            supported: false,
            units: const [],
            clipNodeCount: clipNodes,
          );
        default:
          if (clips?.empty ?? false) continue;
          var bounds = pdfRenderCommandBounds(command);
          if (bounds == null) continue;
          // Raster coverage and filtered image edges can extend just beyond
          // mathematical geometry. Two page points conservatively cover a
          // device pixel even below 1 px/pt while remaining highly selective.
          bounds = _inflate(bounds, 2);
          final clipBounds = clips?.aggregateBounds;
          if (clipBounds != null) {
            bounds = _intersection(bounds, clipBounds);
            if (bounds == null) continue;
          }
          units.add(PdfRegionReplayUnit(
            commandIndex: i,
            bounds: bounds,
            clips: clips,
            blendMode: blendMode,
          ));
      }
    }
    if (savedClips.isNotEmpty) {
      return PdfRegionReplayIndex._(
        supported: false,
        units: const [],
        clipNodeCount: clipNodes,
      );
    }
    final unitList = List<PdfRegionReplayUnit>.unmodifiable(units);
    return PdfRegionReplayIndex._(
      supported: true,
      units: unitList,
      clipNodeCount: clipNodes,
      grid: buildGrid ? PdfRegionReplayGrid.build(unitList) : null,
    );
  }

  final bool supported;
  final List<PdfRegionReplayUnit> units;
  final int clipNodeCount;

  /// Optional uniform-grid spatial index over [units]. Present only when
  /// [PdfRegionReplayIndex.build] was asked for one; it turns the per-region
  /// linear scan into an O(cells + candidates) lookup, which is what makes a
  /// multi-hundred-thousand-unit page (a dense CAD drawing) affordable to pan.
  final PdfRegionReplayGrid? grid;

  /// Conservative retained-index estimate. The command geometry itself is
  /// borrowed from the scene and is not counted twice.
  int get estimatedBytes =>
      units.length * 48 + clipNodeCount * 40 + (grid?.estimatedBytes ?? 0);

  /// Replays intersecting units in their original painter order. Uses the
  /// spatial [grid] when present (candidate units only), else a linear scan.
  int replay(
    PdfRect region,
    List<PdfRenderCommand> commands,
    PdfDevice device,
    Canvas canvas,
  ) {
    final grid = this.grid;
    if (grid != null) {
      return grid.replay(region, units, commands, device, canvas);
    }
    var replayed = 0;
    for (final unit in units) {
      if (!_intersects(unit.bounds, region)) continue;
      canvas.save();
      device.setBlendMode(unit.blendMode);
      unit.clips?.replay(device);
      replayCommands(
        commands,
        device,
        start: unit.commandIndex,
        end: unit.commandIndex + 1,
      );
      canvas.restore();
      replayed++;
    }
    return replayed;
  }
}

/// Uniform-grid spatial index over painter-ordered replay units.
///
/// Units are binned by the grid cells their bounds overlap; a query gathers
/// the candidate units from the cells the region touches, de-duplicates them
/// (a generation-stamped visited array, no per-query allocation of a Set),
/// and replays those that truly intersect in ascending unit order — which is
/// painter order, because [PdfRegionReplayIndex.build] emits units in painter
/// order. Units whose bounds span a large fraction of the grid (a page-wide
/// fill or a single giant polyline) are kept in a separate [_broad] list
/// scanned on every query instead of being smeared across every cell, so the
/// bin arrays stay compact.
class PdfRegionReplayGrid {
  PdfRegionReplayGrid._(
    this._cols,
    this._rows,
    this._originX,
    this._originY,
    this._cellW,
    this._cellH,
    this._cellStart,
    this._cellUnits,
    this._broad,
    this._visited,
  );

  /// Builds a grid sized so each cell holds a handful of units on average,
  /// capped at [maxCells] total. Returns null for a degenerate (empty or
  /// zero-area) unit set — callers then keep the linear path.
  static PdfRegionReplayGrid? build(
    List<PdfRegionReplayUnit> units, {
    int maxCells = 1 << 14, // 16384 cells
    double broadCellFraction = 0.25,
  }) {
    if (units.isEmpty) return null;
    var left = double.infinity, bottom = double.infinity;
    var right = -double.infinity, top = -double.infinity;
    for (final u in units) {
      if (u.bounds.left < left) left = u.bounds.left;
      if (u.bounds.bottom < bottom) bottom = u.bounds.bottom;
      if (u.bounds.right > right) right = u.bounds.right;
      if (u.bounds.top > top) top = u.bounds.top;
    }
    final w = right - left, h = top - bottom;
    if (!(w > 0) || !(h > 0)) return null;

    // Aim for ~2 units per cell, aspect-matched, capped at maxCells.
    final target = math.min(maxCells, math.max(1, units.length ~/ 2));
    final aspect = w / h;
    var cols = math.max(1, math.sqrt(target * aspect).round());
    var rows = math.max(1, (target / cols).round());
    cols = cols.clamp(1, maxCells);
    rows = rows.clamp(1, math.max(1, maxCells ~/ cols));
    final cellW = w / cols, cellH = h / rows;

    int colOf(double x) =>
        ((x - left) / cellW).floor().clamp(0, cols - 1);
    int rowOf(double y) =>
        ((y - bottom) / cellH).floor().clamp(0, rows - 1);

    // A unit is "broad" if it covers more than broadCellFraction of the grid
    // in either axis — smearing those across thousands of cells is the memory
    // trap the historical ceiling guarded against.
    final broadColSpan = (cols * broadCellFraction).ceil();
    final broadRowSpan = (rows * broadCellFraction).ceil();

    final nCells = cols * rows;
    final counts = Int32List(nCells);
    final broad = <int>[];
    for (var i = 0; i < units.length; i++) {
      final b = units[i].bounds;
      final c0 = colOf(b.left), c1 = colOf(b.right);
      final r0 = rowOf(b.bottom), r1 = rowOf(b.top);
      if ((c1 - c0 + 1) > broadColSpan || (r1 - r0 + 1) > broadRowSpan) {
        broad.add(i);
        continue;
      }
      for (var r = r0; r <= r1; r++) {
        final base = r * cols;
        for (var c = c0; c <= c1; c++) {
          counts[base + c]++;
        }
      }
    }
    // CSR layout: prefix-sum offsets, then fill.
    final cellStart = Int32List(nCells + 1);
    for (var i = 0; i < nCells; i++) {
      cellStart[i + 1] = cellStart[i] + counts[i];
    }
    final cellUnits = Int32List(cellStart[nCells]);
    final cursor = Int32List.fromList(cellStart.sublist(0, nCells));
    for (var i = 0; i < units.length; i++) {
      final b = units[i].bounds;
      final c0 = colOf(b.left), c1 = colOf(b.right);
      final r0 = rowOf(b.bottom), r1 = rowOf(b.top);
      if ((c1 - c0 + 1) > broadColSpan || (r1 - r0 + 1) > broadRowSpan) {
        continue;
      }
      for (var r = r0; r <= r1; r++) {
        final base = r * cols;
        for (var c = c0; c <= c1; c++) {
          cellUnits[cursor[base + c]++] = i;
        }
      }
    }
    return PdfRegionReplayGrid._(
      cols,
      rows,
      left,
      bottom,
      cellW,
      cellH,
      cellStart,
      cellUnits,
      Int32List.fromList(broad),
      Int32List(units.length),
    );
  }

  final int _cols, _rows;
  final double _originX, _originY, _cellW, _cellH;
  final Int32List _cellStart; // CSR offsets, length nCells+1
  final Int32List _cellUnits; // CSR payload: unit indices
  final Int32List _broad; // page-spanning units, always considered
  final Int32List _visited; // generation stamp per unit, dedupe across cells
  int _generation = 0;

  int get broadCount => _broad.length;
  int get estimatedBytes =>
      _cellStart.lengthInBytes +
      _cellUnits.lengthInBytes +
      _broad.lengthInBytes +
      _visited.lengthInBytes;

  int replay(
    PdfRect region,
    List<PdfRegionReplayUnit> units,
    List<PdfRenderCommand> commands,
    PdfDevice device,
    Canvas canvas,
  ) {
    final gen = ++_generation;
    // Gather candidate unit indices (deduped) from the touched cells + broad.
    final candidates = <int>[];
    final c0 = ((region.left - _originX) / _cellW).floor().clamp(0, _cols - 1);
    final c1 = ((region.right - _originX) / _cellW).floor().clamp(0, _cols - 1);
    final r0 = ((region.bottom - _originY) / _cellH).floor().clamp(0, _rows - 1);
    final r1 = ((region.top - _originY) / _cellH).floor().clamp(0, _rows - 1);
    for (var r = r0; r <= r1; r++) {
      final base = r * _cols;
      for (var c = c0; c <= c1; c++) {
        final cell = base + c;
        final end = _cellStart[cell + 1];
        for (var k = _cellStart[cell]; k < end; k++) {
          final idx = _cellUnits[k];
          if (_visited[idx] == gen) continue;
          _visited[idx] = gen;
          if (_intersects(units[idx].bounds, region)) candidates.add(idx);
        }
      }
    }
    for (final idx in _broad) {
      if (_visited[idx] == gen) continue;
      _visited[idx] = gen;
      if (_intersects(units[idx].bounds, region)) candidates.add(idx);
    }
    // Painter order = ascending unit index.
    candidates.sort();
    var replayed = 0;
    for (final idx in candidates) {
      final unit = units[idx];
      canvas.save();
      device.setBlendMode(unit.blendMode);
      unit.clips?.replay(device);
      replayCommands(
        commands,
        device,
        start: unit.commandIndex,
        end: unit.commandIndex + 1,
      );
      canvas.restore();
      replayed++;
    }
    return replayed;
  }
}

class PdfRegionReplayUnit {
  const PdfRegionReplayUnit({
    required this.commandIndex,
    required this.bounds,
    required this.clips,
    required this.blendMode,
  });

  final int commandIndex;
  final PdfRect bounds;
  final PdfRegionClipState? clips;
  final PdfBlendMode blendMode;
}

class PdfRegionClipState {
  const PdfRegionClipState({
    required this.parent,
    required this.command,
    required this.aggregateBounds,
    required this.empty,
  });

  final PdfRegionClipState? parent;
  final PdfClipPathCommand command;
  final PdfRect? aggregateBounds;
  final bool empty;

  void replay(PdfDevice device) {
    parent?.replay(device);
    device.clipPath(command.path, command.rule);
  }
}

PdfRect? pdfRenderCommandBounds(PdfRenderCommand command) {
  switch (command) {
    case PdfFillPathCommand(:final path) ||
          PdfFillPathGradientCommand(:final path):
      return pdfRenderPathBounds(path);
    case PdfStrokePathCommand(:final path, :final stroke):
      final bounds = pdfRenderPathBounds(path);
      if (bounds == null) return null;
      final joinScale = stroke.join == 0 ? math.max(1.0, stroke.miterLimit) : 1;
      final radius = math.max(.5, stroke.width.abs() * .5 * joinScale);
      return _inflate(bounds, radius);
    case PdfFillMeshCommand(:final mesh):
      if (mesh.vertices.isEmpty) return null;
      var left = mesh.vertices.first.x;
      var right = left;
      var bottom = mesh.vertices.first.y;
      var top = bottom;
      for (final vertex in mesh.vertices.skip(1)) {
        left = math.min(left, vertex.x);
        right = math.max(right, vertex.x);
        bottom = math.min(bottom, vertex.y);
        top = math.max(top, vertex.y);
      }
      return PdfRect(left, bottom, right, top);
    case PdfDrawTextCommand(:final run):
      var bounds = _textBounds(run);
      if (bounds == null) return null;
      if (run.strokeColor != null) {
        bounds = _inflate(bounds, math.max(.5, run.strokeWidth.abs() * .5));
      }
      return bounds;
    case PdfDrawImageCommand(:final request):
      return _matrixBounds(request.transform, 0, 0, 1, 1);
    case PdfSaveCommand() ||
          PdfRestoreCommand() ||
          PdfClipPathCommand() ||
          PdfSetBlendModeCommand() ||
          PdfBeginGroupCommand() ||
          PdfEndGroupCommand() ||
          PdfBeginSoftMaskedCommand() ||
          PdfEndSoftMaskedCommand():
      return null;
  }
}

PdfRect? _textBounds(PdfTextRun run) {
  if (run.invisible) return null;
  final glyphs = run.glyphs;
  if (glyphs != null) {
    PdfRect? out;
    for (final glyph in glyphs) {
      final outline = glyph.outline;
      if (outline == null) continue;
      final bounds = pdfRenderPathBounds(outline);
      if (bounds == null) continue;
      final mapped = _matrixBounds(
        run.transform,
        bounds.left + glyph.offset,
        bounds.bottom + glyph.offsetY,
        bounds.right + glyph.offset,
        bounds.top + glyph.offsetY,
      );
      out = out == null ? mapped : _union(out, mapped);
    }
    // CanvasPdfDevice deliberately draws no substitute when a real glyph list
    // exists but contains only blank/unavailable outlines.
    return out;
  }
  if (run.text.isEmpty) return null;
  // Deliberately wider than the extractor's conventional -.25..+.75 em:
  // platform substitute fonts can carry accents, descenders, and bearings
  // outside the nominal advance. A full em of horizontal and two em of
  // vertical headroom is conservative for the system-font fallback.
  return _matrixBounds(
    run.transform,
    math.min(-1, run.width - 1),
    -2,
    math.max(1, run.width + 1),
    2,
  );
}

PdfRect? pdfRenderPathBounds(PdfPath path) {
  double? left, right, bottom, top;
  void include(double x, double y) {
    left = left == null ? x : math.min(left!, x);
    right = right == null ? x : math.max(right!, x);
    bottom = bottom == null ? y : math.min(bottom!, y);
    top = top == null ? y : math.max(top!, y);
  }

  for (final segment in path.segments) {
    switch (segment) {
      case PdfMoveTo(:final x, :final y) || PdfLineTo(:final x, :final y):
        include(x, y);
      case PdfCubicTo(
          :final x1,
          :final y1,
          :final x2,
          :final y2,
          :final x3,
          :final y3
        ):
        // A cubic lies inside the convex hull of its endpoints/control points.
        include(x1, y1);
        include(x2, y2);
        include(x3, y3);
      case PdfClosePath():
        break;
    }
  }
  if (left == null) return null;
  return PdfRect(left!, bottom!, right!, top!);
}

PdfRect _matrixBounds(
  PdfMatrix matrix,
  double left,
  double bottom,
  double right,
  double top,
) {
  final points = <(double, double)>[
    (matrix.transformX(left, bottom), matrix.transformY(left, bottom)),
    (matrix.transformX(right, bottom), matrix.transformY(right, bottom)),
    (matrix.transformX(right, top), matrix.transformY(right, top)),
    (matrix.transformX(left, top), matrix.transformY(left, top)),
  ];
  return PdfRect(
    points.map((point) => point.$1).reduce(math.min),
    points.map((point) => point.$2).reduce(math.min),
    points.map((point) => point.$1).reduce(math.max),
    points.map((point) => point.$2).reduce(math.max),
  );
}

PdfRect _inflate(PdfRect rect, double amount) => PdfRect(
      rect.left - amount,
      rect.bottom - amount,
      rect.right + amount,
      rect.top + amount,
    );

PdfRect? _clipIntersection(PdfRegionClipState? parent, PdfRect? next) {
  if (parent?.empty ?? false) return null;
  if (next == null) return null;
  final existing = parent?.aggregateBounds;
  return existing == null ? next : _intersection(existing, next);
}

PdfRect? _intersection(PdfRect a, PdfRect b) {
  final left = math.max(a.left, b.left);
  final bottom = math.max(a.bottom, b.bottom);
  final right = math.min(a.right, b.right);
  final top = math.min(a.top, b.top);
  if (right < left || top < bottom) return null;
  return PdfRect(left, bottom, right, top);
}

PdfRect _union(PdfRect a, PdfRect b) => PdfRect(
      math.min(a.left, b.left),
      math.min(a.bottom, b.bottom),
      math.max(a.right, b.right),
      math.max(a.top, b.top),
    );

bool _intersects(PdfRect a, PdfRect b) =>
    a.right >= b.left &&
    a.left <= b.right &&
    a.top >= b.bottom &&
    a.bottom <= b.top;
