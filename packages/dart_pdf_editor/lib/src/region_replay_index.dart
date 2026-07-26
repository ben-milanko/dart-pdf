import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

/// Serialized-index format version. Producer and consumer are the same build,
/// shipped together, so a mismatch is a programming error (asserted on read).
const int _regionIndexFormatVersion = 1;

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

  /// Page-space X span [min, max] covered by the indexed paint units, or null
  /// when nothing is drawable. This is the axis an X-strip band decomposition
  /// partitions (extreme-aspect CAD sheets pan along it).
  (double, double)? get xExtent {
    if (units.isEmpty) return null;
    var min = units.first.bounds.left;
    var max = units.first.bounds.right;
    for (final unit in units.skip(1)) {
      if (unit.bounds.left < min) min = unit.bounds.left;
      if (unit.bounds.right > max) max = unit.bounds.right;
    }
    return (min, max);
  }

  /// Per-band unit distribution across [bands] equal-width X strips over
  /// [xExtent]. Each unit is counted once, by the band its horizontal centre
  /// falls in - so the counts sum to [units].length and expose how unevenly
  /// paint work spreads along the pan axis (the CAD probe's densest 3 of 10
  /// strips carried ~54% of the units). Diagnostic only; the retention model
  /// in [PdfBandedTranscript] assigns a spanning unit to every band it
  /// overlaps, not just its centre band.
  List<int> unitBandHistogram(int bands) {
    final counts = List<int>.filled(bands < 1 ? 0 : bands, 0);
    if (bands < 1 || units.isEmpty) return counts;
    final extent = xExtent;
    if (extent == null) return counts;
    final (min, max) = extent;
    final span = max - min;
    for (final unit in units) {
      final centre = (unit.bounds.left + unit.bounds.right) / 2;
      var band = span <= 0 ? 0 : ((centre - min) / span * bands).floor();
      if (band < 0) band = 0;
      if (band >= bands) band = bands - 1;
      counts[band]++;
    }
    return counts;
  }

  /// Replays intersecting units in their original painter order. Uses the
  /// spatial [grid] when present (candidate units only), else a linear scan.
  ///
  /// Save/restore route through [device] (which forwards to its canvas) rather
  /// than a `dart:ui` [Canvas] directly, so this whole file stays Flutter-free
  /// and the render worker isolate can build and serialize the index.
  int replay(
    PdfRect region,
    List<PdfRenderCommand> commands,
    PdfDevice device,
  ) {
    final grid = this.grid;
    if (grid != null) {
      return grid.replay(region, units, commands, device);
    }
    var replayed = 0;
    for (final unit in units) {
      if (!_intersects(unit.bounds, region)) continue;
      device.save();
      device.setBlendMode(unit.blendMode);
      unit.clips?.replay(device);
      replayCommands(
        commands,
        device,
        start: unit.commandIndex,
        end: unit.commandIndex + 1,
      );
      device.restore();
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
      device.save();
      device.setBlendMode(unit.blendMode);
      unit.clips?.replay(device);
      replayCommands(
        commands,
        device,
        start: unit.commandIndex,
        end: unit.commandIndex + 1,
      );
      device.restore();
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
    case PdfDrawTiledCellCommand(
        :final cellCommands,
        :final originsX,
        :final originsY
      ):
      // Conservative: the cell's painted bounds (clip commands inside the
      // cell contribute nothing, so overrunning content is included - safe
      // for culling) swept across the origin extent. One rect for the whole
      // repeat lattice; a hatch fill is genuinely region-spanning.
      PdfRect? cell;
      for (final c in cellCommands) {
        final b = pdfRenderCommandBounds(c);
        if (b != null) cell = cell == null ? b : _union(cell, b);
      }
      if (cell == null || originsX.isEmpty) return null;
      var minX = originsX[0], maxX = originsX[0];
      var minY = originsY[0], maxY = originsY[0];
      for (var t = 1; t < originsX.length; t++) {
        minX = math.min(minX, originsX[t]);
        maxX = math.max(maxX, originsX[t]);
        minY = math.min(minY, originsY[t]);
        maxY = math.max(maxY, originsY[t]);
      }
      return PdfRect(cell.left + minX, cell.bottom + minY, cell.right + maxX,
          cell.top + maxY);
    case PdfSaveCommand() ||
          PdfRestoreCommand() ||
          PdfClipPathCommand() ||
          PdfSetBlendModeCommand() ||
          PdfSetOverprintCommand() ||
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

bool _intersects(PdfRect a, PdfRect b) => pdfRenderRectsIntersect(a, b);

/// Closed-interval rectangle overlap in page space, shared by the region index
/// and the X-strip banded transcript.
bool pdfRenderRectsIntersect(PdfRect a, PdfRect b) =>
    a.right >= b.left &&
    a.left <= b.right &&
    a.top >= b.bottom &&
    a.bottom <= b.top;

// --- isolate-boundary (de)serialization ---
//
// The grid arrays (`_cellStart`, `_cellUnits`, `_broad`) and the per-unit
// bounds/commandIndex/blendMode are trivially sendable typed data. The only
// live object graph is the clip-state tree: each [PdfRegionClipState] holds a
// [PdfClipPathCommand] (a [PdfPath] + rule) plus a parent pointer, aggregate
// bounds and an empty flag. The paths ride the existing [serializeCommands]
// codec (float32 path coordinates, exactly what the scene transcript already
// carries), and the tree structure is flattened to parent-index references.
//
// This lets a render worker build the whole index off the UI isolate — the
// ~210ms grid build on a dense CAD page is pure command-bounds arithmetic — and
// ship it back as one [Uint8List]. Reconstructed, the index replays
// byte-identically to one built in the UI isolate (the codec truncation is
// idempotent and the unit order — painter order — is preserved).

/// Serializes [index] to a portable byte buffer, or returns null when it holds
/// content the codec declines (a clip path that fails to serialize — never in
/// practice, clip paths carry no images). An unsupported index (a
/// transparency/soft-mask group spanned the page, or the build hit its bounds)
/// serializes to a tiny "unsupported" marker so the consumer learns the worker
/// examined the page and it is not region-cullable.
Uint8List? serializeRegionReplayIndex(PdfRegionReplayIndex index) {
  final w = _IdxWriter();
  w.u8(_regionIndexFormatVersion);
  w.boolean(index.supported);
  w.u32(index.clipNodeCount);
  if (!index.supported) return w.takeBytes();

  // Flatten the clip-state forest reachable from the units into a list ordered
  // so every parent precedes its children (register the parent first), which
  // lets the reader rebuild each node once its parent already exists.
  final nodeIndex = <PdfRegionClipState, int>{};
  final ordered = <PdfRegionClipState>[];
  int register(PdfRegionClipState? node) {
    if (node == null) return -1;
    final existing = nodeIndex[node];
    if (existing != null) return existing;
    register(node.parent); // parent gets a smaller index
    final id = ordered.length;
    nodeIndex[node] = id;
    ordered.add(node);
    return id;
  }

  final unitClipIndices = Int32List(index.units.length);
  for (var i = 0; i < index.units.length; i++) {
    unitClipIndices[i] = register(index.units[i].clips);
  }

  w.u32(ordered.length);
  for (final node in ordered) {
    w.i32(node.parent == null ? -1 : nodeIndex[node.parent]!);
    _idxWriteOptRect(w, node.aggregateBounds);
    w.boolean(node.empty);
  }
  // The clip PATH commands ride the shared command codec (float32 coordinates).
  final clipCommands = <PdfRenderCommand>[for (final n in ordered) n.command];
  final clipBytes = serializeCommands(clipCommands);
  if (clipBytes == null) return null; // clip paths never carry images
  w.bytes(clipBytes);

  w.u32(index.units.length);
  for (var i = 0; i < index.units.length; i++) {
    final unit = index.units[i];
    w.u32(unit.commandIndex);
    _idxWriteRect(w, unit.bounds);
    w.i32(unitClipIndices[i]);
    w.u8(unit.blendMode.index);
  }

  final grid = index.grid;
  w.boolean(grid != null);
  if (grid != null) {
    w.i32(grid._cols);
    w.i32(grid._rows);
    w.f64(grid._originX);
    w.f64(grid._originY);
    w.f64(grid._cellW);
    w.f64(grid._cellH);
    w.i32List(grid._cellStart);
    w.i32List(grid._cellUnits);
    w.i32List(grid._broad);
  }
  return w.takeBytes();
}

/// Reconstructs a [PdfRegionReplayIndex] written by
/// [serializeRegionReplayIndex]. Throws on a malformed buffer; callers wrap the
/// call and fall back to an in-isolate build on any failure.
PdfRegionReplayIndex deserializeRegionReplayIndex(Uint8List bytes) {
  final r = _IdxReader(bytes);
  final version = r.u8();
  assert(version == _regionIndexFormatVersion,
      'region index format version mismatch');
  final supported = r.boolean();
  final clipNodeCount = r.u32();
  if (!supported) {
    return PdfRegionReplayIndex._(
      supported: false,
      units: const [],
      clipNodeCount: clipNodeCount,
    );
  }

  final nodeCount = r.u32();
  final parents = Int32List(nodeCount);
  final nodeBounds = List<PdfRect?>.filled(nodeCount, null);
  final nodeEmpty = List<bool>.filled(nodeCount, false);
  for (var i = 0; i < nodeCount; i++) {
    parents[i] = r.i32();
    nodeBounds[i] = _idxReadOptRect(r);
    nodeEmpty[i] = r.boolean();
  }
  final clipCommands = deserializeCommands(r.bytes());
  final nodes = List<PdfRegionClipState?>.filled(nodeCount, null);
  for (var i = 0; i < nodeCount; i++) {
    nodes[i] = PdfRegionClipState(
      parent: parents[i] < 0 ? null : nodes[parents[i]],
      command: clipCommands[i] as PdfClipPathCommand,
      aggregateBounds: nodeBounds[i],
      empty: nodeEmpty[i],
    );
  }

  final unitCount = r.u32();
  final units = List<PdfRegionReplayUnit>.generate(unitCount, (_) {
    final commandIndex = r.u32();
    final bounds = _idxReadRect(r);
    final clipIndex = r.i32();
    final blendMode = PdfBlendMode.values[r.u8()];
    return PdfRegionReplayUnit(
      commandIndex: commandIndex,
      bounds: bounds,
      clips: clipIndex < 0 ? null : nodes[clipIndex],
      blendMode: blendMode,
    );
  }, growable: false);

  PdfRegionReplayGrid? grid;
  if (r.boolean()) {
    final cols = r.i32();
    final rows = r.i32();
    final originX = r.f64();
    final originY = r.f64();
    final cellW = r.f64();
    final cellH = r.f64();
    final cellStart = r.i32List();
    final cellUnits = r.i32List();
    final broad = r.i32List();
    grid = PdfRegionReplayGrid._(
      cols,
      rows,
      originX,
      originY,
      cellW,
      cellH,
      cellStart,
      cellUnits,
      broad,
      Int32List(unitCount),
    );
  }

  return PdfRegionReplayIndex._(
    supported: true,
    units: List<PdfRegionReplayUnit>.unmodifiable(units),
    clipNodeCount: clipNodeCount,
    grid: grid,
  );
}

void _idxWriteRect(_IdxWriter w, PdfRect rect) {
  w.f64(rect.left);
  w.f64(rect.bottom);
  w.f64(rect.right);
  w.f64(rect.top);
}

PdfRect _idxReadRect(_IdxReader r) => PdfRect(r.f64(), r.f64(), r.f64(), r.f64());

void _idxWriteOptRect(_IdxWriter w, PdfRect? rect) {
  w.boolean(rect != null);
  if (rect != null) _idxWriteRect(w, rect);
}

PdfRect? _idxReadOptRect(_IdxReader r) => r.boolean() ? _idxReadRect(r) : null;

/// A minimal big-endian byte writer for the region index. Mirrors the
/// render-command codec's writer (grow one backing buffer, write scalars into a
/// [ByteData] view at a running offset) so the two behave identically on the
/// web, where 64-bit ints are encoded as float64.
class _IdxWriter {
  Uint8List _buf = Uint8List(1 << 12);
  late ByteData _view = ByteData.view(_buf.buffer);
  int _len = 0;

  void _ensure(int extra) {
    final need = _len + extra;
    if (need <= _buf.length) return;
    var cap = _buf.length * 2;
    while (cap < need) {
      cap *= 2;
    }
    final grown = Uint8List(cap)..setRange(0, _len, _buf);
    _buf = grown;
    _view = ByteData.view(grown.buffer);
  }

  void u8(int v) {
    _ensure(1);
    _buf[_len++] = v & 0xff;
  }

  void boolean(bool v) => u8(v ? 1 : 0);

  void u32(int v) {
    _ensure(4);
    _view.setUint32(_len, v);
    _len += 4;
  }

  void i32(int v) {
    _ensure(4);
    _view.setInt32(_len, v);
    _len += 4;
  }

  void f64(double v) {
    _ensure(8);
    _view.setFloat64(_len, v);
    _len += 8;
  }

  void bytes(Uint8List xs) {
    u32(xs.length);
    _ensure(xs.length);
    _buf.setRange(_len, _len + xs.length, xs);
    _len += xs.length;
  }

  void i32List(Int32List xs) {
    u32(xs.length);
    _ensure(xs.length * 4);
    for (final x in xs) {
      _view.setInt32(_len, x);
      _len += 4;
    }
  }

  Uint8List takeBytes() =>
      Uint8List.fromList(Uint8List.sublistView(_buf, 0, _len));
}

class _IdxReader {
  _IdxReader(this._bytes) : _data = ByteData.sublistView(_bytes);

  final Uint8List _bytes;
  final ByteData _data;
  int _o = 0;

  int u8() => _data.getUint8(_o++);

  bool boolean() => u8() == 1;

  int u32() {
    final v = _data.getUint32(_o);
    _o += 4;
    return v;
  }

  int i32() {
    final v = _data.getInt32(_o);
    _o += 4;
    return v;
  }

  double f64() {
    final v = _data.getFloat64(_o);
    _o += 8;
    return v;
  }

  Uint8List bytes() {
    final n = u32();
    final out = Uint8List.fromList(Uint8List.sublistView(_bytes, _o, _o + n));
    _o += n;
    return out;
  }

  Int32List i32List() {
    final n = u32();
    final out = Int32List(n);
    for (var i = 0; i < n; i++) {
      out[i] = _data.getInt32(_o);
      _o += 4;
    }
    return out;
  }
}
