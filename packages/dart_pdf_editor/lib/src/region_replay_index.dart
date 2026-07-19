import 'dart:math' as math;

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
  });

  factory PdfRegionReplayIndex.build(
    List<PdfRenderCommand> commands, {
    required int maxCommands,
    int maxStateDepth = 128,
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
    return PdfRegionReplayIndex._(
      supported: true,
      units: List.unmodifiable(units),
      clipNodeCount: clipNodes,
    );
  }

  final bool supported;
  final List<PdfRegionReplayUnit> units;
  final int clipNodeCount;

  /// Conservative retained-index estimate. The command geometry itself is
  /// borrowed from the scene and is not counted twice.
  int get estimatedBytes => units.length * 48 + clipNodeCount * 40;

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

  /// Replays intersecting units in their original painter order.
  int replay(
    PdfRect region,
    List<PdfRenderCommand> commands,
    PdfDevice device,
    Canvas canvas,
  ) {
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

bool _intersects(PdfRect a, PdfRect b) => pdfRenderRectsIntersect(a, b);

/// Closed-interval rectangle overlap in page space, shared by the region index
/// and the X-strip banded transcript.
bool pdfRenderRectsIntersect(PdfRect a, PdfRect b) =>
    a.right >= b.left &&
    a.left <= b.right &&
    a.top >= b.bottom &&
    a.bottom <= b.top;
