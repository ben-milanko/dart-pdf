import 'dart:async' show FutureOr;
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/painting.dart' show Offset, Rect;
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_graphics/raster.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'backend_stats.dart';

/// Scene-retained flutter_gpu backend for final LoD tile textures.
///
/// The first tile lazily compiles supported retained commands into page-space
/// GPU buffers and uploads every decoded image once. Later tiles only query the
/// retained region index, bind those buffers with a page-to-tile transform and
/// submit a render pass. No PDF interpretation, path tessellation, image
/// decode, texture upload, or CPU pixel readback occurs per tile.
///
/// The exact subset includes a common isolated single-image soft-mask group:
/// content and mask stay as separate scene-lifetime textures and are combined
/// by the tile shader. Ordinary PDF clip paths are retained as exact stencil
/// masks (with rectangular clips additionally using the hardware scissor).
/// Other isolated groups, non-normal blend modes, complex clips *inside* the
/// special soft-mask-image shortcut, gradients, substituted/stroked text,
/// tiling cells, unsafe overprint, or missing image pixels reject the whole
/// scene.
/// dart_pdf_editor then permanently uses its Canvas session for that scene.
class FlutterGpuTileRasterBackend extends PdfTileRasterBackend {
  FlutterGpuTileRasterBackend({
    this.msaa = true,
    this.allowOverprintApproximation = false,
    this.maxTextureBytes = 256 << 20,
    this.maxGeometryBytes = 256 << 20,
    FlutterGpuTileBackendStats? stats,
  })  : stats = stats ?? FlutterGpuTileBackendStats(),
        _imageCache = _GpuImageCache(maxTextureBytes),
        _geometryPool = _GpuGeometryPool(maxGeometryBytes);

  /// Enables 4x offscreen MSAA where the Impeller context supports it.
  final bool msaa;

  /// Allows non-black overprint paints to use source-over.
  ///
  /// False by default: stable flutter_gpu cannot sample an offscreen target
  /// in a later darken pass reliably on every Impeller backend. Keep this for
  /// controlled benchmarking only; ordinary clients get the exact Canvas
  /// fallback instead.
  final bool allowOverprintApproximation;

  /// Byte budget for decoded image textures shared by every scene/session
  /// created from this backend instance. Cached and active scene leases both
  /// count; a scene that cannot fit after evicting unpinned LRU entries throws
  /// during its first tile and the viewer switches that session to Canvas.
  /// A non-positive value disables cross-scene texture reuse.
  final int maxTextureBytes;

  /// Hard ceiling for reusable scene geometry buffers.
  ///
  /// Stable flutter_gpu does not expose explicit DeviceBuffer disposal, so
  /// relying on native finalizers lets fast CAD navigation outrun collection.
  /// Buffers are therefore pooled in 16 MiB blocks, leased by compiled scenes,
  /// and reused only after the scene is disposed and every submitted command
  /// buffer has completed. A scene that cannot fit falls back to Canvas.
  final int maxGeometryBytes;

  final FlutterGpuTileBackendStats stats;
  final _GpuImageCache _imageCache;
  final _GpuGeometryPool _geometryPool;
  // Contexts belong to Flutter views and can disappear when a native window
  // closes. Keep only weak membership so diagnostics do not turn every view
  // ever opened into a process-lifetime root.
  final Expando<bool> _seenContexts = Expando<bool>('pdf-gpu-context');
  gpu.GpuContext? _lastContext;
  String? _lastSessionRejection;

  @override
  String? get lastSessionRejection => _lastSessionRejection;

  /// True when this build includes the native flutter_gpu implementation.
  ///
  /// The Impeller context is still acquired lazily by [createSession], so
  /// reading this does not move GPU initialization onto the document's first
  /// paint. A native build without a usable context declines the session and
  /// reports that runtime reason through [stats].
  bool get isPlatformSupported => true;

  /// Drops reusable texture ownership. Active compiled scenes retain the
  /// resources they are currently drawing.
  void clearImageCache() => _imageCache.clear(stats);

  @override
  String get debugLabel => 'flutter_gpu';

  @override
  bool get prefersDirectDecodedImageUploads => true;

  @override
  PdfTileRasterSession? createSession(PdfRetainedScene scene) {
    _lastSessionRejection = null;
    try {
      final context = gpu.gpuContext;
      if (_seenContexts[context] != true) {
        _seenContexts[context] = true;
        stats.contextsSeen++;
      }
      final previousContext = _lastContext;
      if (previousContext != null && !identical(previousContext, context)) {
        stats.contextSwitches++;
      }
      _lastContext = context;
      stats.lastContextIdentity = identityHashCode(context);
      final commandBuild = _buildGpuCommands(scene.commands);
      final commands = commandBuild.commands;
      if (commands == null) {
        _lastSessionRejection = commandBuild.rejection;
        stats.lastRejection = commandBuild.rejection;
        stats.lastTileRoute = 'canvas-fallback';
        stats.sessionsRejected++;
        return null;
      }
      final unitBuild = _buildGpuUnits(commands);
      final units = unitBuild.units;
      if (units == null) {
        _lastSessionRejection = unitBuild.rejection;
        stats.lastRejection = unitBuild.rejection;
        stats.lastTileRoute = 'canvas-fallback';
        stats.sessionsRejected++;
        return null;
      }
      final rejection = _unsupportedReason(
          scene, commands, units, allowOverprintApproximation);
      if (rejection != null) {
        _lastSessionRejection = rejection;
        stats.lastRejection = rejection;
        stats.lastTileRoute = 'canvas-fallback';
        stats.sessionsRejected++;
        return null;
      }
      if (allowOverprintApproximation && units.any((unit) => unit.darken)) {
        stats.overprintApproximationSessions++;
      }
      stats.sessionsCreated++;
      stats.lastTileRoute = 'flutter_gpu-session';
      stats.activeSessions++;
      stats.peakActiveSessions =
          math.max(stats.peakActiveSessions, stats.activeSessions);
      return _FlutterGpuTileSession(
        scene: scene,
        commands: commands,
        context: context,
        pipelines: _GpuPipelines.instance(context),
        units: units,
        msaa: msaa,
        stats: stats,
        imageCache: _imageCache,
        geometryPool: _geometryPool,
      );
    } catch (error) {
      _lastSessionRejection = 'initialization failed: $error';
      stats.lastRejection = _lastSessionRejection;
      stats.lastTileRoute = 'canvas-fallback';
      stats.sessionsRejected++;
      return null;
    }
  }

  static String? _unsupportedReason(
      PdfRetainedScene scene,
      List<PdfRenderCommand> commands,
      List<_GpuUnit> units,
      bool allowOverprintApproximation) {
    for (final unit in units) {
      if (unit.blendMode != PdfBlendMode.normal) {
        return 'blend mode ${unit.blendMode.name}';
      }
      final composite = unit.composite;
      if (composite != null) {
        if (scene.imageFor(composite.content) == null ||
            scene.imageFor(composite.mask) == null) {
          return 'missing soft-mask image pixels';
        }
        continue;
      }
      final command = commands[unit.commandIndex];
      final overprint = _unsafeOverprint(unit, command);
      if (overprint != null) return overprint;
      if (unit.darken && !allowOverprintApproximation) {
        return 'non-black overprint requires Canvas fallback';
      }
      switch (command) {
        case PdfFillPathCommand():
          break;
        case PdfStrokePathCommand(:final stroke):
          // A PDF hairline is device-scale-dependent, so it cannot be baked
          // into scene-lifetime geometry without changing semantics by LoD.
          if (stroke.width <= 0) return 'device-scale hairline';
        case PdfFillMeshCommand():
          break;
        case PdfDrawImageCommand(:final request):
          final image = scene.imageFor(request);
          if (image == null) return 'missing image pixels';
          // A platform-codec base keeps its /SMask as a companion GPU surface
          // that only CanvasPdfDevice knows how to compose (dstIn over the
          // base). This backend uploads one texture per image, so drawing it
          // here would paint the base opaque - the JPEG's masked-out area is
          // usually solid black, so a cut-out sticker renders as a black
          // rectangle (#675). Hand the scene to Canvas until the mask is
          // uploaded as its own texture.
          if (pdfGpuSoftMaskOf(image) != null) {
            return 'deferred image soft mask';
          }
        case PdfDrawTextCommand(:final run):
          if (run.invisible) continue;
          final textReasons = <String>[
            if (run.glyphs == null) 'missing glyph outlines',
            if (!run.fill) 'fill disabled',
            if (run.gradient != null) 'gradient fill',
            if (run.strokeColor != null) 'stroke',
          ];
          if (textReasons.isNotEmpty) {
            return 'unsupported text: ${textReasons.join(', ')}';
          }
        case PdfFillPathGradientCommand():
          return 'unsupported ${command.runtimeType}';
        default:
          return 'unsupported ${command.runtimeType}';
      }
    }
    final covered = <int>{
      for (final unit in units)
        if (unit.endCommandIndex > unit.commandIndex)
          for (var i = unit.commandIndex; i <= unit.endCommandIndex; i++) i,
    };
    for (var i = 0; i < commands.length; i++) {
      final command = commands[i];
      switch (command) {
        case PdfBeginGroupCommand() ||
              PdfEndGroupCommand() ||
              PdfBeginSoftMaskedCommand() ||
              PdfEndSoftMaskedCommand() ||
              PdfFillPathGradientCommand():
          if (covered.contains(i)) break;
          return 'unsafe ${command.runtimeType}';
        case PdfSetBlendModeCommand(:final mode):
          if (mode != PdfBlendMode.normal) return 'blend mode ${mode.name}';
        case PdfSetOverprintCommand(:final fill, :final stroke):
          // Paint units capture their active overprint state above. State
          // changes by themselves do not render anything.
          if (fill || stroke) break;
        default:
          break;
      }
    }
    return null;
  }

  static bool _isAxisAlignedRect(PdfPath path) {
    final subs = flattenPath(path, PdfMatrix.identity);
    if (subs.length != 1) return false;
    final p = subs.single.points;
    var n = p.length ~/ 2;
    if (n == 5 && p[0] == p[8] && p[1] == p[9]) n--;
    if (n != 4) return false;
    for (var i = 0; i < 4; i++) {
      final j = (i + 1) % 4;
      if (p[2 * i] != p[2 * j] && p[2 * i + 1] != p[2 * j + 1]) {
        return false;
      }
    }
    return true;
  }
}

class _GpuUnit {
  const _GpuUnit({
    required this.commandIndex,
    required this.endCommandIndex,
    required this.bounds,
    required this.clip,
    required this.blendMode,
    required this.fillOverprint,
    required this.strokeOverprint,
    required this.darken,
    this.composite,
  });

  final int commandIndex;
  final int endCommandIndex;
  final PdfRect bounds;
  final _GpuClipState clip;
  final PdfBlendMode blendMode;
  final bool fillOverprint;
  final bool strokeOverprint;
  final bool darken;
  final _SoftMaskImageSpec? composite;
}

/// One immutable graphics-state clip. Rectangles only narrow [scissor]; every
/// other path adds a persistent [node] that is rebuilt into the stencil when
/// the command stream changes clip state. Save/restore can therefore retain
/// and recover the exact intersection without copying paths.
class _GpuClipState {
  const _GpuClipState(this.scissor, this.node, {this.empty = false});

  final PdfRect? scissor;
  final _GpuClipNode? node;
  final bool empty;
}

class _GpuClipNode {
  const _GpuClipNode(this.path, this.rule, this.previous);

  final PdfPath path;
  final PdfFillRule rule;
  final _GpuClipNode? previous;
}

const _rootGpuClip = _GpuClipState(null, null);

class _GpuUnitBuild {
  const _GpuUnitBuild(this.units, this.rejection);
  final List<_GpuUnit>? units;
  final String? rejection;
}

class _CompositeCapture {
  _CompositeCapture(this.start, this.clip, this.blendMode, this.fillOverprint,
      this.strokeOverprint);
  final int start;
  final _GpuClipState clip;
  final PdfBlendMode blendMode;
  final bool fillOverprint;
  final bool strokeOverprint;
  var depth = 0;
  PdfRect? bounds;
}

class _SoftMaskImageSpec {
  const _SoftMaskImageSpec({
    required this.content,
    required this.mask,
    required this.groupAlpha,
    required this.contentClip,
    required this.maskClip,
    required this.luminosity,
    required this.backdropLuminance,
    required this.transferScale,
    required this.transferOffset,
  });

  final PdfImageRequest content;
  final PdfImageRequest mask;
  final double groupAlpha;
  final PdfRect? contentClip;
  final PdfRect? maskClip;
  final bool luminosity;
  final double backdropLuminance;
  final double transferScale;
  final double transferOffset;
}

class _GpuCommandBuild {
  const _GpuCommandBuild(this.commands, this.rejection);

  final List<PdfRenderCommand>? commands;
  final String? rejection;
}

/// Expands retained tiling cells once for the GPU scene.
///
/// Canvas can stamp a vector sub-picture for every repeat. flutter_gpu does
/// not expose a retained sub-pass transform, so keeping the nested command
/// would otherwise require rebuilding the cell for every tile. Flattening it
/// here preserves exact tile-major painter order while still compiling the
/// resulting page-space geometry only once. The hard cap keeps pathological
/// hatch grids on the existing Canvas sub-picture path instead of trading a
/// compact transcript for unbounded GPU geometry.
_GpuCommandBuild _buildGpuCommands(List<PdfRenderCommand> source) {
  const maxExpandedCommands = 1000000;
  var hasTiledCell = false;
  String? tiledRejection;

  int count(List<PdfRenderCommand> commands, Set<Object> active,
      {bool inTiledCell = false}) {
    if (!active.add(commands)) return maxExpandedCommands + 1;
    var total = 0;
    for (final command in commands) {
      if (command
          case PdfDrawTiledCellCommand(
            :final cellCommands,
            :final originsX,
          )) {
        hasTiledCell = true;
        final cellCount = count(cellCommands, active, inTiledCell: true);
        if (cellCount > maxExpandedCommands ||
            originsX.length > maxExpandedCommands ||
            (cellCount != 0 &&
                originsX.length > maxExpandedCommands ~/ cellCount)) {
          active.remove(commands);
          return maxExpandedCommands + 1;
        }
        total += cellCount * originsX.length;
      } else {
        if (inTiledCell &&
            command is PdfDrawImageCommand &&
            command.request.isStencil) {
          // Type 3 bitmap glyphs are retained as one-repeat tiling cells.
          // Linear texture sampling does not yet match Canvas closely enough
          // on the Ghent font grid, so do not let flattening accidentally
          // promote those pages into the exact GPU subset.
          tiledRejection ??= 'unsupported tiled stencil image';
        }
        total++;
      }
      if (total > maxExpandedCommands) {
        active.remove(commands);
        return total;
      }
    }
    active.remove(commands);
    return total;
  }

  final expandedCount = count(source, Set<Object>.identity());
  if (!hasTiledCell) return _GpuCommandBuild(source, null);
  if (tiledRejection != null) {
    return _GpuCommandBuild(null, tiledRejection);
  }
  if (expandedCount > maxExpandedCommands) {
    return const _GpuCommandBuild(
      null,
      'expanded tiling cells exceed GPU command cap',
    );
  }

  final expanded = <PdfRenderCommand>[];
  for (final command in source) {
    if (command
        case PdfDrawTiledCellCommand(
          :final cellCommands,
          :final originsX,
          :final originsY,
        )) {
      final recorder = RecordingPdfDevice();
      for (var i = 0; i < originsX.length; i++) {
        // TranslatingPdfDevice intentionally does not implement the native
        // tiled-cell capability. The generic replay path therefore expands
        // nested cells too and composes their origins into page-space.
        replayCommands(
          cellCommands,
          TranslatingPdfDevice(recorder, originsX[i], originsY[i]),
        );
      }
      expanded.addAll(recorder.commands);
    } else {
      expanded.add(command);
    }
  }
  if (expanded.length > maxExpandedCommands) {
    return const _GpuCommandBuild(
      null,
      'expanded tiling cells exceed GPU command cap',
    );
  }
  return _GpuCommandBuild(List.unmodifiable(expanded), null);
}

_GpuUnitBuild _buildGpuUnits(List<PdfRenderCommand> commands) {
  if (commands.length > 1000000) {
    return const _GpuUnitBuild(null, 'retained scene exceeds GPU index cap');
  }
  final units = <_GpuUnit>[];
  final saved = <(_GpuClipState, PdfBlendMode, bool, bool)>[];
  var clip = _rootGpuClip;
  var blend = PdfBlendMode.normal;
  var fillOverprint = false;
  var strokeOverprint = false;
  _CompositeCapture? composite;

  for (var i = 0; i < commands.length; i++) {
    final command = commands[i];
    switch (command) {
      case PdfSaveCommand():
        saved.add((clip, blend, fillOverprint, strokeOverprint));
      case PdfRestoreCommand():
        if (saved.isEmpty) {
          return const _GpuUnitBuild(null, 'unbalanced graphics state');
        }
        final state = saved.removeLast();
        clip = state.$1;
        blend = state.$2;
        fillOverprint = state.$3;
        strokeOverprint = state.$4;
      case PdfClipPathCommand(:final path, :final rule):
        clip = _pushGpuClip(clip, path, rule);
      case PdfSetBlendModeCommand(:final mode):
        blend = mode;
      case PdfSetOverprintCommand(:final fill, :final stroke):
        fillOverprint = fill;
        strokeOverprint = stroke;
      case PdfBeginGroupCommand() || PdfBeginSoftMaskedCommand():
        composite ??=
            _CompositeCapture(i, clip, blend, fillOverprint, strokeOverprint);
        composite.depth++;
      case PdfEndGroupCommand() || PdfEndSoftMaskedCommand():
        final capture = composite;
        if (capture == null || capture.depth <= 0) {
          return const _GpuUnitBuild(null, 'unbalanced composite group');
        }
        capture.depth--;
        if (capture.depth == 0) {
          final parsed = _parseSoftMaskImage(
            commands,
            capture.start,
            i,
            initialClip: capture.clip.scissor,
          );
          if (parsed.$1 == null) return _GpuUnitBuild(null, parsed.$2);
          final bounds = capture.bounds;
          if (bounds != null) {
            units.add(_GpuUnit(
              commandIndex: capture.start,
              endCommandIndex: i,
              bounds: _inflatePdf(bounds, 2),
              clip: _withGpuRectClip(capture.clip, parsed.$1!.contentClip),
              blendMode: capture.blendMode,
              fillOverprint: capture.fillOverprint,
              strokeOverprint: capture.strokeOverprint,
              darken: false,
              composite: parsed.$1,
            ));
          }
          composite = null;
        }
      default:
        final bounds = pdfRenderCommandBounds(command);
        if (bounds == null) continue;
        if (clip.empty) continue;
        final clipped = clip.scissor == null
            ? bounds
            : _pdfIntersection(clip.scissor, bounds);
        if (clipped == null) continue;
        if (composite != null) {
          composite.bounds = _pdfUnion(composite.bounds, clipped);
        } else {
          units.add(_GpuUnit(
            commandIndex: i,
            endCommandIndex: i,
            bounds: _inflatePdf(clipped, 2),
            clip: clip,
            blendMode: blend,
            fillOverprint: fillOverprint,
            strokeOverprint: strokeOverprint,
            darken:
                _commandNeedsDarken(command, fillOverprint, strokeOverprint),
          ));
        }
    }
  }
  if (saved.isNotEmpty) {
    return const _GpuUnitBuild(null, 'unbalanced graphics state');
  }
  if (composite != null) {
    return const _GpuUnitBuild(null, 'unterminated composite group');
  }
  return _GpuUnitBuild(List.unmodifiable(units), null);
}

_GpuClipState _pushGpuClip(
    _GpuClipState current, PdfPath path, PdfFillRule rule) {
  if (current.empty) return current;
  final bounds = pdfRenderPathBounds(path);
  if (bounds == null) {
    return _GpuClipState(current.scissor, current.node, empty: true);
  }
  final narrowed = current.scissor == null
      ? bounds
      : _pdfIntersection(current.scissor, bounds);
  if (narrowed == null) {
    return _GpuClipState(current.scissor, current.node, empty: true);
  }
  if (FlutterGpuTileRasterBackend._isAxisAlignedRect(path)) {
    return _GpuClipState(narrowed, current.node);
  }
  return _GpuClipState(
    narrowed,
    _GpuClipNode(path, rule, current.node),
  );
}

/// Adds a rectangle already discovered inside the single-image soft-mask
/// shortcut to the outer graphics-state clip. The outer arbitrary path stays
/// in [state.node] and is applied by the tile pass; the inner rectangle remains
/// a cheap exact scissor.
_GpuClipState _withGpuRectClip(_GpuClipState state, PdfRect? rect) {
  if (rect == null || state.empty) return state;
  final narrowed =
      state.scissor == null ? rect : _pdfIntersection(state.scissor, rect);
  return narrowed == null
      ? _GpuClipState(state.scissor, state.node, empty: true)
      : _GpuClipState(narrowed, state.node);
}

(_SoftMaskImageSpec?, String?) _parseSoftMaskImage(
  List<PdfRenderCommand> commands,
  int start,
  int end, {
  PdfRect? initialClip,
}) {
  if (commands[start]
      case PdfBeginGroupCommand(:final alpha, :final knockout)) {
    if (knockout) return (null, 'knockout soft-mask image group');
    if (commands[end] is! PdfEndGroupCommand) {
      return (null, 'unsupported composite nesting');
    }
    PdfDrawImageCommand? content;
    PdfEndSoftMaskedCommand? softEnd;
    var softDepth = 0;
    var softCount = 0;
    PdfRect? clip = initialClip;
    PdfRect? contentClip;
    final saved = <PdfRect?>[];
    for (var i = start + 1; i < end; i++) {
      final command = commands[i];
      switch (command) {
        case PdfSaveCommand():
          saved.add(clip);
        case PdfRestoreCommand():
          if (saved.isEmpty) return (null, 'unbalanced soft-mask image state');
          clip = saved.removeLast();
        case PdfClipPathCommand(:final path):
          if (!FlutterGpuTileRasterBackend._isAxisAlignedRect(path)) {
            return (null, 'non-rectangular soft-mask image clip');
          }
          clip = _pdfIntersection(clip, pdfRenderPathBounds(path));
        case PdfBeginSoftMaskedCommand():
          softDepth++;
          softCount++;
        case PdfEndSoftMaskedCommand():
          softDepth--;
          softEnd = command;
        case PdfDrawImageCommand():
          if (softDepth != 1 || content != null) {
            return (null, 'soft-mask group is not a single image');
          }
          content = command;
          contentClip = clip;
        case PdfSetBlendModeCommand(:final mode):
          if (mode != PdfBlendMode.normal) {
            return (null, 'soft-mask image blend mode ${mode.name}');
          }
        case PdfSetOverprintCommand():
          break;
        case PdfBeginGroupCommand() || PdfEndGroupCommand():
          return (null, 'nested image group');
        default:
          if (pdfRenderCommandBounds(command) != null) {
            return (null, 'soft-mask group contains ${command.runtimeType}');
          }
      }
    }
    if (softCount != 1 ||
        softDepth != 0 ||
        content == null ||
        softEnd == null) {
      return (null, 'unsupported soft-mask image group');
    }
    final maskState = _singleMaskImage(softEnd.maskCommands);
    if (maskState.$1 == null) return (null, maskState.$3);
    return (
      _SoftMaskImageSpec(
        content: content.request,
        mask: maskState.$1!.request,
        groupAlpha: alpha,
        contentClip: contentClip,
        maskClip: maskState.$2,
        luminosity: softEnd.luminosity,
        backdropLuminance: softEnd.backdropLuminance,
        transferScale: softEnd.transferScale,
        transferOffset: softEnd.transferOffset,
      ),
      null,
    );
  }
  return (null, 'unsupported composite ${commands[start].runtimeType}');
}

(PdfDrawImageCommand?, PdfRect?, String?) _singleMaskImage(
    List<PdfRenderCommand> commands) {
  PdfDrawImageCommand? image;
  PdfRect? clip;
  final saved = <PdfRect?>[];
  for (final command in commands) {
    switch (command) {
      case PdfSaveCommand():
        saved.add(clip);
      case PdfRestoreCommand():
        if (saved.isEmpty) return (null, null, 'unbalanced mask image state');
        clip = saved.removeLast();
      case PdfClipPathCommand(:final path):
        if (!FlutterGpuTileRasterBackend._isAxisAlignedRect(path)) {
          return (null, null, 'non-rectangular mask image clip');
        }
        clip = _pdfIntersection(clip, pdfRenderPathBounds(path));
      case PdfDrawImageCommand():
        if (image != null) return (null, null, 'mask contains multiple images');
        image = command;
      case PdfSetBlendModeCommand(:final mode):
        if (mode != PdfBlendMode.normal) {
          return (null, null, 'mask image blend mode ${mode.name}');
        }
      case PdfSetOverprintCommand():
        break;
      default:
        if (pdfRenderCommandBounds(command) != null) {
          return (null, null, 'mask contains ${command.runtimeType}');
        }
    }
  }
  if (saved.isNotEmpty) return (null, null, 'unbalanced mask image state');
  if (image == null) return (null, null, 'mask has no image');
  return (image, clip, null);
}

List<_GpuUnit> _selectGpuUnits(
    List<_GpuUnit> units, PdfMatrix pageToRaster, Rect rasterRegion) {
  final inverse = pageToRaster.inverted();
  if (inverse == null) return const [];
  final points = <(double, double)>[
    (rasterRegion.left, rasterRegion.top),
    (rasterRegion.right, rasterRegion.top),
    (rasterRegion.right, rasterRegion.bottom),
    (rasterRegion.left, rasterRegion.bottom),
  ];
  var left = double.infinity, bottom = double.infinity;
  var right = double.negativeInfinity, top = double.negativeInfinity;
  for (final (x, y) in points) {
    final px = inverse.transformX(x, y), py = inverse.transformY(x, y);
    if (px < left) left = px;
    if (px > right) right = px;
    if (py < bottom) bottom = py;
    if (py > top) top = py;
  }
  final page = PdfRect(left, bottom, right, top);
  return [
    for (final unit in units)
      if (_pdfIntersects(unit.bounds, page)) unit
  ];
}

PdfRect? _pdfIntersection(PdfRect? a, PdfRect? b) {
  if (a == null) return b;
  if (b == null) return a;
  final left = a.left > b.left ? a.left : b.left;
  final bottom = a.bottom > b.bottom ? a.bottom : b.bottom;
  final right = a.right < b.right ? a.right : b.right;
  final top = a.top < b.top ? a.top : b.top;
  return right > left && top > bottom
      ? PdfRect(left, bottom, right, top)
      : null;
}

PdfRect _pdfUnion(PdfRect? a, PdfRect b) => a == null
    ? b
    : PdfRect(
        a.left < b.left ? a.left : b.left,
        a.bottom < b.bottom ? a.bottom : b.bottom,
        a.right > b.right ? a.right : b.right,
        a.top > b.top ? a.top : b.top,
      );

PdfRect _inflatePdf(PdfRect r, double amount) => PdfRect(
      r.left - amount,
      r.bottom - amount,
      r.right + amount,
      r.top + amount,
    );

bool _pdfIntersects(PdfRect a, PdfRect b) =>
    a.left < b.right &&
    a.right > b.left &&
    a.bottom < b.top &&
    a.top > b.bottom;

String? _unsafeOverprint(_GpuUnit unit, PdfRenderCommand command) {
  switch (command) {
    case PdfFillMeshCommand():
      if (unit.fillOverprint) return 'mesh overprint';
    default:
      // Images do not use CanvasPdfDevice's overprint approximation; the
      // interpreter has already resolved any image-adjacent colorant work.
      break;
  }
  return null;
}

bool _commandNeedsDarken(
    PdfRenderCommand command, bool fillOverprint, bool strokeOverprint) {
  bool nonBlack(PdfColor color) =>
      color.red.abs() > 1e-7 ||
      color.green.abs() > 1e-7 ||
      color.blue.abs() > 1e-7;
  return switch (command) {
    PdfFillPathCommand(:final color) => fillOverprint && nonBlack(color),
    PdfStrokePathCommand(:final color) => strokeOverprint && nonBlack(color),
    PdfDrawTextCommand(:final run) =>
      (run.fill && fillOverprint && nonBlack(run.color)) ||
          (run.strokeColor != null &&
              strokeOverprint &&
              nonBlack(run.strokeColor!)),
    _ => false,
  };
}

class _FlutterGpuTileSession
    implements PdfTileRasterSession, PdfTileRasterScheduling {
  _FlutterGpuTileSession({
    required this.scene,
    required this.commands,
    required this.context,
    required this.pipelines,
    required this.units,
    required this.msaa,
    required this.stats,
    required this.imageCache,
    required this.geometryPool,
  });

  @override
  final PdfRetainedScene scene;
  final List<PdfRenderCommand> commands;

  // This backend already returns a final GPU texture for every raster call.
  // Slab splitting would queue another texture-to-texture copy per tile; those
  // copies are deferred by Impeller and have shown up as later 90ms raster
  // frames even though the synchronous split loop itself takes <1ms.
  @override
  bool get batchAdjacentTiles => false;

  // Keep the base/coarse tile visible and issue one new texture per repaint.
  // Completion ticks the store, naturally advancing the center-out queue.
  @override
  int get maxNewTilesPerPaint => 1;
  final gpu.GpuContext context;
  final Future<_GpuPipelines> pipelines;
  final List<_GpuUnit> units;
  final bool msaa;
  final FlutterGpuTileBackendStats stats;
  final _GpuImageCache imageCache;
  final _GpuGeometryPool geometryPool;

  Future<_CompiledScene>? _compiled;
  _CompiledScene? _ready;
  bool _disposed = false;
  bool _failureReported = false;

  Future<_CompiledScene> _compile() => _compiled ??= _CompiledScene.build(
        scene,
        commands,
        context,
        units,
        stats,
        imageCache,
        geometryPool,
      ).then((compiled) {
        if (_disposed) {
          compiled.dispose();
          throw StateError('flutter_gpu tile session disposed');
        }
        return _ready = compiled;
      }).whenComplete(scene.releaseDecodedImagePixels);

  @override
  Future<ui.Image> rasterizeRegion(
    Rect region, {
    required double pixelRatio,
    int? tracePage,
  }) async {
    if (_disposed) throw StateError('flutter_gpu tile session disposed');
    try {
      final compiled = await _compile();
      final gpuPipelines = await pipelines;
      if (_disposed) throw StateError('flutter_gpu tile session disposed');
      final issue = Stopwatch()..start();
      final selected = _selectGpuUnits(units, compiled.pageToRaster, region);
      stats.selectedCommands += selected.length;
      final image = compiled.render(
        selected,
        region: region,
        pixelRatio: pixelRatio,
        pipelines: gpuPipelines,
        useMsaa: msaa,
        tracePage: tracePage,
      );
      stats.tilesRendered++;
      stats.lastTileRoute = 'flutter_gpu';
      PdfPerfLog.log(
        'tile gpu issue page=${tracePage ?? '-'} '
        'region=${region.width.toStringAsFixed(0)}x'
        '${region.height.toStringAsFixed(0)}pt '
        'ratio=${pixelRatio.toStringAsFixed(2)} '
        'selected=${selected.length}/${units.length} '
        'img=${image.width}x${image.height} '
        'cpu=${(issue.elapsedMicroseconds / 1000).toStringAsFixed(1)}ms '
        'inFlight=${stats.inFlightSubmissions}',
      );
      return image;
    } catch (error) {
      if (!_failureReported && !_disposed) {
        _failureReported = true;
        stats.rasterFallbacks++;
        stats.lastRejection = 'rasterization failed: $error';
        stats.lastTileRoute = 'canvas-fallback';
      }
      rethrow;
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    scene.releaseDecodedImagePixels();
    _ready?.dispose();
    _ready = null;
    _compiled = null;
    stats.sessionsDisposed++;
    stats.activeSessions = math.max(0, stats.activeSessions - 1);
  }
}

class _CompiledScene {
  _CompiledScene({
    required this.context,
    required this.pageToRaster,
    required this.paper,
    required this.draws,
    required this.clipDraws,
    required this.stats,
    required this.imageCache,
    required this.textureLeases,
    required this.geometryPool,
    required this.geometryLeases,
  });

  static Future<_CompiledScene> build(
    PdfRetainedScene scene,
    List<PdfRenderCommand> commands,
    gpu.GpuContext context,
    List<_GpuUnit> units,
    FlutterGpuTileBackendStats stats,
    _GpuImageCache imageCache,
    _GpuGeometryPool geometryPool,
  ) async {
    final clock = Stopwatch()..start();
    final draws = <int, _GpuDraw>{};
    final clipDraws = Map<_GpuClipNode, _GpuClipDraw>.identity();
    final textureLeases = <_GpuImageTexture>[];
    final geometry = _GpuGeometryArena(context, stats, geometryPool);
    try {
      for (final unit in units) {
        for (_GpuClipNode? node = unit.clip.node;
            node != null;
            node = node.previous) {
          final clipNode = node;
          clipDraws.putIfAbsent(
              clipNode, () => _compileClip(geometry, clipNode));
        }
        final _GpuDraw? draw;
        if (unit.composite == null) {
          final pending = _compileCommand(
            context,
            geometry,
            scene,
            commands[unit.commandIndex],
            stats,
            imageCache,
            textureLeases,
          );
          draw = pending is Future<_GpuDraw?> ? await pending : pending;
        } else {
          draw = await _compileSoftMaskImage(
            context,
            geometry,
            scene,
            unit.composite!,
            stats,
            imageCache,
            textureLeases,
          );
        }
        if (draw != null) draws[unit.commandIndex] = draw;
      }
      final paper = _paperDraw(geometry, scene);
      geometry.finalize();
      final result = _CompiledScene(
        context: context,
        pageToRaster: PdfPageRenderer.pageToDeviceMatrix(
          scene.page,
          scene.pageSize,
          scene.page.cropBox,
          rotation: scene.plan.rotation,
          pixelRatio: 1,
        ),
        paper: paper,
        draws: draws,
        clipDraws: clipDraws,
        stats: stats,
        imageCache: imageCache,
        textureLeases: textureLeases,
        geometryPool: geometryPool,
        geometryLeases: geometry.leases,
      );
      stats
        ..scenesCompiled += 1
        ..clipPathsCompiled += clipDraws.length
        ..compileMicros += clock.elapsedMicroseconds;
      return result;
    } catch (_) {
      imageCache.releaseAll(textureLeases, stats);
      geometry.release();
      rethrow;
    }
  }

  final gpu.GpuContext context;
  final PdfMatrix pageToRaster;
  final _SolidDraw paper;
  final Map<int, _GpuDraw> draws;
  final Map<_GpuClipNode, _GpuClipDraw> clipDraws;
  final FlutterGpuTileBackendStats stats;
  final _GpuImageCache imageCache;
  final List<_GpuImageTexture> textureLeases;
  final _GpuGeometryPool geometryPool;
  final List<_GpuGeometryResource> geometryLeases;
  bool _disposed = false;
  bool _texturesReleased = false;
  bool _geometryReleased = false;
  int _inFlight = 0;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _releaseResourcesIfReady();
  }

  void _releaseResourcesIfReady() {
    if (!_disposed || _inFlight != 0) return;
    // The render pass references both the scene's geometry buffers and image
    // textures until its completion callback fires. A structural document
    // edit disposes the old page scene immediately; releasing the texture
    // leases here used to make them eviction-eligible while that scene's last
    // command buffer was still executing. Under Impeller/Metal the evicted
    // texture could then disappear underneath the submitted pass, producing
    // solid-colour rectangles or unrelated image fragments after page
    // insert/remove/reorder. Geometry already observed the completion fence;
    // image leases must share that exact lifetime.
    if (!_texturesReleased) {
      _texturesReleased = true;
      imageCache.releaseAll(textureLeases, stats);
    }
    if (!_geometryReleased) {
      _geometryReleased = true;
      geometryPool.releaseAll(geometryLeases, stats);
    }
  }

  void _completeSubmission(
    bool success,
    Stopwatch completion,
    int? tracePage,
    int width,
    int height,
    int selectedCommands,
  ) {
    if (_inFlight > 0) _inFlight--;
    stats.inFlightSubmissions = math.max(0, stats.inFlightSubmissions - 1);
    final elapsed = completion.elapsedMicroseconds;
    stats
      ..completedSubmissions += 1
      ..completionMicros += elapsed
      ..maxCompletionMicros = math.max(stats.maxCompletionMicros, elapsed);
    if (!success) stats.failedSubmissions++;
    PdfPerfLog.log(
      'tile gpu complete page=${tracePage ?? '-'} '
      'img=${width}x$height selected=$selectedCommands '
      'queue=${(elapsed / 1000).toStringAsFixed(1)}ms '
      'success=$success inFlight=${stats.inFlightSubmissions}',
    );
    _releaseResourcesIfReady();
  }

  ui.Image render(
    List<_GpuUnit> selected, {
    required Rect region,
    required double pixelRatio,
    required _GpuPipelines pipelines,
    required bool useMsaa,
    int? tracePage,
  }) {
    final width = (region.width * pixelRatio).ceil().clamp(1, 1 << 14);
    final height = (region.height * pixelRatio).ceil().clamp(1, 1 << 14);
    return _renderSimple(
      selected,
      region: region,
      pixelRatio: pixelRatio,
      pipelines: pipelines,
      useMsaa: useMsaa,
      width: width,
      height: height,
      tracePage: tracePage,
    );
  }

  ui.Image _renderSimple(
    List<_GpuUnit> selected, {
    required Rect region,
    required double pixelRatio,
    required _GpuPipelines pipelines,
    required bool useMsaa,
    required int width,
    required int height,
    int? tracePage,
  }) {
    final issue = Stopwatch()..start();
    final multisampled = useMsaa && context.doesSupportOffscreenMSAA;
    final resolve = context.createTexture(
      gpu.StorageMode.devicePrivate,
      width,
      height,
      format: context.defaultColorFormat,
    );
    final color = multisampled
        ? context.createTexture(
            gpu.StorageMode.deviceTransient,
            width,
            height,
            format: context.defaultColorFormat,
            sampleCount: 4,
          )
        : resolve;
    final stencil = context.createTexture(
      gpu.StorageMode.deviceTransient,
      width,
      height,
      format: context.defaultStencilFormat,
      sampleCount: multisampled ? 4 : 1,
    );
    final commandBuffer = context.createCommandBuffer();
    final pass = commandBuffer.createRenderPass(gpu.RenderTarget(
      colorAttachments: [
        gpu.ColorAttachment(
          texture: color,
          resolveTexture: multisampled ? resolve : null,
          clearValue: vm.Vector4(0, 0, 0, 0),
          storeAction: multisampled
              ? gpu.StoreAction.multisampleResolve
              : gpu.StoreAction.store,
        ),
      ],
      depthStencilAttachment: gpu.DepthStencilAttachment(
        texture: stencil,
        stencilClearValue: 0,
      ),
    ));
    pass
      ..setCullMode(gpu.CullMode.none)
      ..setWindingOrder(gpu.WindingOrder.counterClockwise)
      ..setPrimitiveType(gpu.PrimitiveType.triangle)
      ..setStencilReference(0)
      ..setColorBlendEnable(true);

    final transient = context.createHostBuffer();
    final transform = transient.emplace(
      _tileTransform(pageToRaster, region, pixelRatio, width, height),
    );
    final encoder = _GpuEncoder(
      pass: pass,
      pipelines: pipelines,
      transform: transform,
      pageToRaster: pageToRaster,
      region: region,
      pixelRatio: pixelRatio,
      width: width,
      height: height,
      clipDraws: clipDraws,
      stencilClear: paper.vertices,
    );
    encoder
      ..setClip(_rootGpuClip)
      ..solid(paper.vertices);
    for (final unit in selected) {
      final draw = draws[unit.commandIndex];
      if (draw == null) continue;
      encoder.setClip(unit.clip);
      draw.encode(encoder);
    }
    stats.clipMaskRebuilds += encoder.clipMaskRebuilds;
    final submit = Stopwatch()..start();
    final completion = Stopwatch()..start();
    _inFlight++;
    stats
      ..inFlightSubmissions += 1
      ..peakInFlightSubmissions = math.max(
        stats.peakInFlightSubmissions,
        stats.inFlightSubmissions,
      );
    try {
      commandBuffer.submit(
        completionCallback: (success) => _completeSubmission(
          success,
          completion,
          tracePage,
          width,
          height,
          selected.length,
        ),
      );
    } catch (_) {
      _inFlight--;
      stats
        ..inFlightSubmissions = math.max(0, stats.inFlightSubmissions - 1)
        ..failedSubmissions += 1;
      _releaseResourcesIfReady();
      rethrow;
    }
    stats
      ..submitMicros += submit.elapsedMicroseconds
      ..issueMicros += issue.elapsedMicroseconds;
    return resolve.asImage();
  }

  static ByteData _tileTransform(
    PdfMatrix pageToRaster,
    Rect region,
    double ratio,
    int width,
    int height,
  ) {
    final sx = 2 * ratio / width;
    final sy = 2 * ratio / height;
    final m = Float32List.fromList([
      sx * pageToRaster.a,
      -sy * pageToRaster.b,
      0,
      0,
      sx * pageToRaster.c,
      -sy * pageToRaster.d,
      0,
      0,
      0,
      0,
      1,
      0,
      sx * (pageToRaster.e - region.left) - 1,
      1 - sy * (pageToRaster.f - region.top),
      0,
      1,
    ]);
    return ByteData.sublistView(m);
  }
}

_GpuClipDraw _compileClip(_GpuGeometryArena geometry, _GpuClipNode node) {
  final subpaths = flattenPath(node.path, PdfMatrix.identity, tolerance: 0.01);
  final parts = _stencilGeometry(geometry, subpaths);
  if (parts == null) {
    throw StateError('empty non-rectangular clip');
  }
  return _GpuClipDraw(
    parts.$1,
    _coverGeometry(geometry, parts.$2, const [0, 0, 0, 0]),
    node.rule,
  );
}

_SolidDraw _paperDraw(_GpuGeometryArena geometry, PdfRetainedScene scene) {
  final box = scene.page.cropBox;
  final color = scene.plan.pageColor;
  final alpha = color.a;
  // PdfPageRenderer paints translucent paper over white first, so the page
  // stays opaque while the antialiased crop-box boundary retains fractional
  // coverage in ceil-sized edge tiles.
  final rgba = <double>[
    color.r * alpha + (1 - alpha),
    color.g * alpha + (1 - alpha),
    color.b * alpha + (1 - alpha),
    1,
  ];
  final vertices = FloatBuilder(36);
  for (final (x, y) in <(double, double)>[
    (box.left, box.bottom),
    (box.right, box.bottom),
    (box.right, box.top),
    (box.left, box.bottom),
    (box.right, box.top),
    (box.left, box.top),
  ]) {
    vertices.add6(x, y, rgba[0], rgba[1], rgba[2], rgba[3]);
  }
  return _SolidDraw(geometry.add(vertices.bytes, 6));
}

Future<_GpuDraw> _compileSoftMaskImage(
  gpu.GpuContext context,
  _GpuGeometryArena geometry,
  PdfRetainedScene scene,
  _SoftMaskImageSpec spec,
  FlutterGpuTileBackendStats stats,
  _GpuImageCache imageCache,
  List<_GpuImageTexture> textureLeases,
) async {
  final contentImage = scene.imageFor(spec.content)!;
  final maskImage = scene.imageFor(spec.mask)!;
  final contentResource =
      await imageCache.acquire(context, spec.content, contentImage, stats);
  textureLeases.add(contentResource);
  final maskResource =
      await imageCache.acquire(context, spec.mask, maskImage, stats);
  textureLeases.add(maskResource);
  final vertices = _imageVertices(spec.content.transform);
  final inverse = spec.mask.transform.inverted();
  if (inverse == null) throw StateError('singular soft-mask image transform');
  final contentAlpha = (spec.content.alpha * spec.groupAlpha).clamp(0.0, 1.0);
  final contentTint = spec.content.isStencil
      ? _premul(spec.content.stencilColor, contentAlpha)
      : <double>[0, 0, 0, contentAlpha];
  final maskTint = spec.mask.isStencil
      ? _premul(spec.mask.stencilColor, spec.mask.alpha)
      : <double>[0, 0, 0, spec.mask.alpha.clamp(0.0, 1.0)];
  final maskClip = spec.maskClip ??
      const PdfRect(-1000000000, -1000000000, 1000000000, 1000000000);
  final values = Float32List(36)
    ..setRange(0, 16, <double>[
      inverse.a,
      inverse.b,
      0,
      0,
      inverse.c,
      inverse.d,
      0,
      0,
      0,
      0,
      1,
      0,
      inverse.e,
      inverse.f,
      0,
      1,
    ])
    ..setRange(16, 20, contentTint)
    ..setRange(20, 24, maskTint)
    ..setRange(24, 28, <double>[
      spec.content.isStencil ? 1 : 0,
      spec.mask.isStencil ? 1 : 0,
      spec.luminosity ? 1 : 0,
      spec.luminosity ? spec.backdropLuminance : 0,
    ])
    ..setRange(28, 32, <double>[
      spec.transferScale,
      spec.transferOffset,
      0,
      0,
    ])
    ..setRange(32, 36, <double>[
      maskClip.left,
      maskClip.bottom,
      maskClip.right,
      maskClip.top,
    ]);
  return _SoftMaskDraw(
    geometry.add(vertices.bytes, vertices.length ~/ 4),
    contentResource.texture,
    maskResource.texture,
    gpu.BufferView(
      context.createDeviceBufferWithCopy(ByteData.sublistView(values)),
      offsetInBytes: 0,
      lengthInBytes: values.lengthInBytes,
    ),
  );
}

class _GpuImageTexture {
  _GpuImageTexture(this.texture, this.width, this.height);
  final gpu.Texture texture;
  final int width;
  final int height;
  int leases = 0;
  bool cacheable = true;
  int get bytes => width * height * 4;
}

class _GpuTextureKey {
  const _GpuTextureKey(this.context, this.content, this.width, this.height);
  final gpu.GpuContext context;
  final Object content;
  final int width;
  final int height;

  @override
  bool operator ==(Object other) =>
      other is _GpuTextureKey &&
      identical(other.context, context) &&
      other.content == content &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode =>
      Object.hash(identityHashCode(context), content, width, height);
}

class _GpuImageCache {
  _GpuImageCache(this.maxBytes);

  final int maxBytes;
  final LinkedHashMap<_GpuTextureKey, _GpuImageTexture> _entries =
      LinkedHashMap<_GpuTextureKey, _GpuImageTexture>();
  final Set<_GpuImageTexture> _detached = Set.identity();
  int _bytes = 0;

  Future<_GpuImageTexture> acquire(
    gpu.GpuContext context,
    PdfImageRequest request,
    ui.Image image,
    FlutterGpuTileBackendStats stats,
  ) async {
    final key = _GpuTextureKey(
        context, pdfImageContentKey(request), image.width, image.height);
    final hit = _entries.remove(key);
    if (hit != null) {
      _entries[key] = hit;
      hit.leases++;
      stats.textureCacheHits++;
      stats.activeTextureLeases++;
      stats.textureBytes = _bytes;
      return hit;
    }
    stats.textureCacheMisses++;
    final bytes = image.width * image.height * 4;
    if (maxBytes > 0 && !_makeRoom(bytes, stats)) {
      stats.textureBudgetFallbacks++;
      throw StateError('GPU texture budget exceeded: need $bytes bytes, '
          'have $_bytes/$maxBytes with active scenes pinned');
    }
    final uploaded = await _uploadImageTexture(
      context,
      image,
      stats,
      decoded: request.decoded,
    )
      ..leases = 1;
    _bytes += uploaded.bytes;
    if (maxBytes > 0) {
      _entries[key] = uploaded;
    } else {
      // A non-positive budget disables reuse but the live scene resource still
      // remains counted until its lease is released.
      uploaded.cacheable = false;
      _detached.add(uploaded);
    }
    stats.activeTextureLeases++;
    stats.textureBytes = _bytes;
    stats.peakTextureBytes = math.max(stats.peakTextureBytes, _bytes);
    return uploaded;
  }

  bool _makeRoom(int required, FlutterGpuTileBackendStats stats) {
    if (required > maxBytes) return false;
    while (_bytes + required > maxBytes) {
      _GpuTextureKey? victim;
      for (final entry in _entries.entries) {
        if (entry.value.leases == 0) {
          victim = entry.key;
          break;
        }
      }
      if (victim == null) return false;
      final evicted = _entries.remove(victim)!;
      evicted.cacheable = false;
      _bytes -= evicted.bytes;
      stats.textureEvictions++;
    }
    return true;
  }

  void releaseAll(
      List<_GpuImageTexture> resources, FlutterGpuTileBackendStats stats) {
    for (final resource in resources) {
      if (resource.leases <= 0) continue;
      resource.leases--;
      stats.activeTextureLeases = math.max(0, stats.activeTextureLeases - 1);
      if (resource.leases == 0 && !resource.cacheable) {
        if (_detached.remove(resource)) _bytes -= resource.bytes;
      }
    }
    resources.clear();
    stats.textureBytes = _bytes;
  }

  void clear(FlutterGpuTileBackendStats stats) {
    for (final resource in _entries.values) {
      resource.cacheable = false;
      if (resource.leases == 0) {
        _bytes -= resource.bytes;
      } else {
        _detached.add(resource);
      }
    }
    _entries.clear();
    stats.textureBytes = _bytes;
  }
}

FloatBuilder _imageVertices(PdfMatrix transform) {
  const corners = <double>[0, 0, 1, 0, 1, 1, 0, 1];
  const uv = <double>[0, 1, 1, 1, 1, 0, 0, 0];
  final vertices = FloatBuilder(24);
  for (final i in const [0, 1, 2, 0, 2, 3]) {
    final x = corners[2 * i], y = corners[2 * i + 1];
    vertices.add4(
      transform.transformX(x, y),
      transform.transformY(x, y),
      uv[2 * i],
      uv[2 * i + 1],
    );
  }
  return vertices;
}

Future<_GpuImageTexture> _uploadImageTexture(
    gpu.GpuContext context, ui.Image image, FlutterGpuTileBackendStats stats,
    {PdfDecodedPixels? decoded}) async {
  final ByteData bytes;
  if (decoded != null &&
      decoded.width == image.width &&
      decoded.height == image.height) {
    // Worker-recorded scenes already own premultiplied RGBA. Upload that
    // directly instead of round-tripping the ui.Image through GPU/CPU memory.
    bytes = ByteData.sublistView(decoded.rgba);
    stats.textureDirectUploads++;
  } else {
    final readback = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (readback == null) throw StateError('image readback failed');
    bytes = readback;
    stats.textureReadbacks++;
  }
  final texture = context.createTexture(
    gpu.StorageMode.hostVisible,
    image.width,
    image.height,
    format: gpu.PixelFormat.r8g8b8a8UNormInt,
  );
  texture.overwrite(bytes);
  stats.texturesUploaded++;
  return _GpuImageTexture(texture, image.width, image.height);
}

FutureOr<_GpuDraw?> _compileCommand(
  gpu.GpuContext context,
  _GpuGeometryArena geometry,
  PdfRetainedScene scene,
  PdfRenderCommand command,
  FlutterGpuTileBackendStats stats,
  _GpuImageCache imageCache,
  List<_GpuImageTexture> textureLeases,
) async {
  switch (command) {
    case PdfFillPathCommand(
        :final path,
        :final color,
        :final rule,
        :final alpha
      ):
      final subs = flattenPath(path, PdfMatrix.identity, tolerance: 0.01);
      return _stencilDraw(geometry, subs, color, alpha, rule, false);
    case PdfStrokePathCommand(
        :final path,
        :final color,
        :final stroke,
        :final alpha
      ):
      var subs = flattenPath(path, PdfMatrix.identity, tolerance: 0.01);
      if (stroke.dashArray.any((value) => value > 0)) {
        subs = dashSubpaths(subs, stroke.dashArray, stroke.dashPhase);
      }
      final contours = StrokeContours();
      strokeToContours(
        subs,
        width: stroke.width,
        cap: stroke.cap,
        join: stroke.join,
        miterLimit: stroke.miterLimit,
        out: contours,
      );
      final rings = <FlatSubpath>[];
      for (var i = 0; i < contours.ringCount; i++) {
        rings.add(FlatSubpath(
          Float64List.sublistView(
              contours.points.view, contours.ringStart(i), contours.ringEnd(i)),
          closed: true,
        ));
      }
      return _stencilDraw(
          geometry, rings, color, alpha, PdfFillRule.nonzero, true);
    case PdfDrawTextCommand(:final run):
      if (run.invisible) return null;
      final subs = <FlatSubpath>[];
      for (final glyph in run.glyphs!) {
        final outline = glyph.outline;
        if (outline == null) continue;
        final transform = PdfMatrix.translation(glyph.offset, glyph.offsetY)
            .concat(run.transform);
        for (final sub in FlattenedOutline.of(outline).subpaths) {
          final mapped = Float64List(sub.points.length);
          for (var i = 0; i < sub.points.length; i += 2) {
            mapped[i] = transform.transformX(sub.points[i], sub.points[i + 1]);
            mapped[i + 1] =
                transform.transformY(sub.points[i], sub.points[i + 1]);
          }
          subs.add(FlatSubpath(mapped, closed: sub.closed));
        }
      }
      return _stencilDraw(
          geometry, subs, run.color, 1, PdfFillRule.nonzero, false);
    case PdfFillMeshCommand(:final mesh, :final alpha):
      if (mesh.triangles.isEmpty) return null;
      final vertices = FloatBuilder(mesh.triangles.length * 6);
      for (final index in mesh.triangles) {
        final vertex = mesh.vertices[index];
        vertices.add6(
          vertex.x,
          vertex.y,
          vertex.color.red * alpha,
          vertex.color.green * alpha,
          vertex.color.blue * alpha,
          alpha,
        );
      }
      return _SolidDraw(geometry.add(vertices.bytes, vertices.length ~/ 6));
    case PdfDrawImageCommand(:final request):
      return _compileImageCommand(
        context,
        geometry,
        scene,
        request,
        stats,
        imageCache,
        textureLeases,
      );
    default:
      return null;
  }
}

Future<_GpuDraw> _compileImageCommand(
  gpu.GpuContext context,
  _GpuGeometryArena geometry,
  PdfRetainedScene scene,
  PdfImageRequest request,
  FlutterGpuTileBackendStats stats,
  _GpuImageCache imageCache,
  List<_GpuImageTexture> textureLeases,
) async {
  final image = scene.imageFor(request)!;
  final resource = await imageCache.acquire(context, request, image, stats);
  textureLeases.add(resource);
  final vertices = _imageVertices(request.transform);
  final tint = request.isStencil
      ? _premul(request.stencilColor, request.alpha)
      : <double>[0, 0, 0, request.alpha];
  final info = Float32List(8)
    ..setRange(0, 4, tint)
    ..[4] = request.isStencil ? 1 : 0;
  return _TextureDraw(
    geometry.add(vertices.bytes, 6),
    resource.texture,
    gpu.BufferView(
      context.createDeviceBufferWithCopy(ByteData.sublistView(info)),
      offsetInBytes: 0,
      lengthInBytes: info.lengthInBytes,
    ),
  );
}

_StencilDraw? _stencilDraw(
  _GpuGeometryArena geometry,
  List<FlatSubpath> subpaths,
  PdfColor color,
  double alpha,
  PdfFillRule rule,
  bool union,
) {
  if (alpha <= 0) return null;
  final parts = _stencilGeometry(geometry, subpaths);
  if (parts == null) return null;
  final fanBuffer = parts.$1;
  final a = alpha.clamp(0.0, 1.0);
  final rgba = _premul(color, a);
  return _StencilDraw(
    fanBuffer,
    _coverGeometry(geometry, parts.$2, rgba),
    rule,
    union,
  );
}

/// Compiles the shared fan + bounds cover used by both painted paths and clip
/// paths. The fan is intentionally the same winding/parity representation for
/// both, so clipping cannot disagree with a fill of the same PDF path.
(_GpuBuffer, FlatBounds)? _stencilGeometry(
    _GpuGeometryArena geometry, List<FlatSubpath> subpaths) {
  final bounds = FlatBounds.of(subpaths);
  if (bounds == null) return null;
  final fan = FloatBuilder(1024);
  for (final sub in subpaths) {
    final p = sub.points;
    var n = p.length ~/ 2;
    if (n > 2 && p[0] == p[2 * n - 2] && p[1] == p[2 * n - 1]) n--;
    if (n < 3) continue;
    for (var i = 1; i + 1 < n; i++) {
      fan
        ..add2(p[0], p[1])
        ..add2(p[2 * i], p[2 * i + 1])
        ..add2(p[2 * i + 2], p[2 * i + 3]);
    }
  }
  if (fan.isEmpty) return null;
  return (geometry.add(fan.bytes, fan.length ~/ 2), bounds);
}

_GpuBuffer _coverGeometry(
    _GpuGeometryArena geometry, FlatBounds bounds, List<double> rgba) {
  final cover = FloatBuilder(36);
  for (final (x, y) in <(double, double)>[
    (bounds.left, bounds.bottom),
    (bounds.right, bounds.bottom),
    (bounds.right, bounds.top),
    (bounds.left, bounds.bottom),
    (bounds.right, bounds.top),
    (bounds.left, bounds.top),
  ]) {
    cover.add6(x, y, rgba[0], rgba[1], rgba[2], rgba[3]);
  }
  return geometry.add(cover.bytes, 6);
}

List<double> _premul(PdfColor color, double alpha) => [
      color.red.clamp(0.0, 1.0) * alpha,
      color.green.clamp(0.0, 1.0) * alpha,
      color.blue.clamp(0.0, 1.0) * alpha,
      alpha,
    ];

class _GpuGeometryArena {
  _GpuGeometryArena(this.context, this.stats, this.pool);

  final gpu.GpuContext context;
  final FlutterGpuTileBackendStats stats;
  final _GpuGeometryPool pool;
  final List<_GpuGeometrySlice> _slices = [];
  final List<_GpuGeometryResource> _leases = [];
  var _pendingBytes = 0;
  var _finalized = false;

  List<_GpuGeometryResource> get leases => List.unmodifiable(_leases);

  _GpuBuffer add(ByteData bytes, int vertices) {
    if (_finalized) throw StateError('GPU geometry arena already finalized');
    if (_slices.isNotEmpty &&
        _pendingBytes + bytes.lengthInBytes > _GpuGeometryPool.chunkBytes) {
      _flush();
    }
    final result = _GpuBuffer(vertices);
    _slices.add(_GpuGeometrySlice(bytes, result));
    _pendingBytes += bytes.lengthInBytes;
    stats.geometryVertices += vertices;
    return result;
  }

  void finalize() {
    if (_finalized) return;
    _finalized = true;
    _flush();
  }

  void release() {
    pool.releaseAll(_leases, stats);
    _leases.clear();
  }

  void _flush() {
    if (_slices.isEmpty) return;
    final packed = Uint8List(_pendingBytes);
    var offset = 0;
    for (final slice in _slices) {
      final source = slice.bytes.buffer.asUint8List(
        slice.bytes.offsetInBytes,
        slice.bytes.lengthInBytes,
      );
      packed.setRange(offset, offset + source.length, source);
      slice.buffer._offsetInBytes = offset;
      offset += source.length;
    }
    final resource = pool.acquire(context, ByteData.sublistView(packed), stats);
    _leases.add(resource);
    for (final slice in _slices) {
      slice.buffer._view = gpu.BufferView(
        resource.buffer,
        offsetInBytes: slice.buffer._offsetInBytes,
        lengthInBytes: slice.bytes.lengthInBytes,
      );
    }
    _slices.clear();
    _pendingBytes = 0;
  }
}

class _GpuGeometryPool {
  _GpuGeometryPool(this.maxBytes);

  static const chunkBytes = 16 << 20;

  final int maxBytes;
  final List<_GpuGeometryResource> _resources = [];
  var _bytes = 0;

  _GpuGeometryResource acquire(
    gpu.GpuContext context,
    ByteData data,
    FlutterGpuTileBackendStats stats,
  ) {
    final capacity =
        ((data.lengthInBytes + chunkBytes - 1) ~/ chunkBytes) * chunkBytes;
    _GpuGeometryResource? resource;
    for (final candidate in _resources) {
      if (!identical(candidate.context, context) ||
          candidate.leased ||
          candidate.capacity < capacity) {
        continue;
      }
      if (resource == null || candidate.capacity < resource.capacity) {
        resource = candidate;
      }
    }
    if (resource == null) {
      if (capacity > maxBytes || _bytes + capacity > maxBytes) {
        stats.geometryBudgetFallbacks++;
        throw StateError(
          'GPU geometry budget exceeded: need $capacity bytes, '
          'have $_bytes/$maxBytes with active scenes pinned',
        );
      }
      resource = _GpuGeometryResource(
        context,
        context.createDeviceBuffer(gpu.StorageMode.hostVisible, capacity),
        capacity,
      );
      _resources.add(resource);
      _bytes += capacity;
      stats.geometryBuffers++;
    }
    if (!resource.buffer.overwrite(data)) {
      throw StateError('GPU geometry upload failed');
    }
    resource.buffer.flush(lengthInBytes: data.lengthInBytes);
    resource.leased = true;
    stats
      ..activeGeometryLeases = _resources.where((item) => item.leased).length
      ..geometryBytes = _bytes
      ..peakGeometryBytes = math.max(stats.peakGeometryBytes, _bytes);
    return resource;
  }

  void releaseAll(
    Iterable<_GpuGeometryResource> resources,
    FlutterGpuTileBackendStats stats,
  ) {
    for (final resource in resources) {
      resource.leased = false;
    }
    stats
      ..activeGeometryLeases = _resources.where((item) => item.leased).length
      ..geometryBytes = _bytes;
  }
}

class _GpuGeometryResource {
  _GpuGeometryResource(this.context, this.buffer, this.capacity);
  final gpu.GpuContext context;
  final gpu.DeviceBuffer buffer;
  final int capacity;
  bool leased = false;
}

class _GpuBuffer {
  _GpuBuffer(this.vertices);
  final int vertices;
  gpu.BufferView? _view;
  int _offsetInBytes = 0;
  gpu.BufferView get view =>
      _view ?? (throw StateError('GPU geometry arena not finalized'));
}

class _GpuGeometrySlice {
  const _GpuGeometrySlice(this.bytes, this.buffer);
  final ByteData bytes;
  final _GpuBuffer buffer;
}

sealed class _GpuDraw {
  void encode(_GpuEncoder encoder);
}

class _SolidDraw implements _GpuDraw {
  const _SolidDraw(this.vertices);
  final _GpuBuffer vertices;

  @override
  void encode(_GpuEncoder encoder) => encoder.solid(vertices);
}

class _StencilDraw implements _GpuDraw {
  const _StencilDraw(this.fan, this.cover, this.rule, this.union);
  final _GpuBuffer fan;
  final _GpuBuffer cover;
  final PdfFillRule rule;
  final bool union;

  @override
  void encode(_GpuEncoder encoder) =>
      encoder.stencil(fan, cover, rule: rule, union: union);
}

class _GpuClipDraw {
  const _GpuClipDraw(this.fan, this.cover, this.rule);

  final _GpuBuffer fan;
  final _GpuBuffer cover;
  final PdfFillRule rule;
}

class _TextureDraw implements _GpuDraw {
  const _TextureDraw(this.vertices, this.texture, this.info);
  final _GpuBuffer vertices;
  final gpu.Texture texture;
  final gpu.BufferView info;

  @override
  void encode(_GpuEncoder encoder) => encoder.texture(vertices, texture, info);
}

class _SoftMaskDraw implements _GpuDraw {
  const _SoftMaskDraw(
      this.vertices, this.contentTexture, this.maskTexture, this.info);
  final _GpuBuffer vertices;
  final gpu.Texture contentTexture;
  final gpu.Texture maskTexture;
  final gpu.BufferView info;

  @override
  void encode(_GpuEncoder encoder) =>
      encoder.softMask(vertices, contentTexture, maskTexture, info);
}

class _GpuEncoder {
  _GpuEncoder({
    required this.pass,
    required this.pipelines,
    required this.transform,
    required this.pageToRaster,
    required this.region,
    required this.pixelRatio,
    required this.width,
    required this.height,
    required this.clipDraws,
    required this.stencilClear,
  });

  final gpu.RenderPass pass;
  final _GpuPipelines pipelines;
  final gpu.BufferView transform;
  final PdfMatrix pageToRaster;
  final Rect region;
  final double pixelRatio;
  final int width;
  final int height;
  final Map<_GpuClipNode, _GpuClipDraw> clipDraws;
  final _GpuBuffer stencilClear;

  // The upper two stencil bits hold alternating clip intersections. The lower
  // six hold temporary winding/parity values for clip construction and normal
  // path fills. Alternating bits let an intersection be built without reading
  // and writing the same bit in one pass.
  static const _clipBitA = 0x80;
  static const _clipBitB = 0x40;
  static const _pathMask = 0x3f;
  static const _allStencilBits = 0xff;

  _GpuClipState? _clipState;
  int _activeClipBit = 0;
  int clipMaskRebuilds = 0;
  bool? _separateVertexCountApi;

  static final _srcOver = gpu.ColorBlendEquation(
    sourceColorBlendFactor: gpu.BlendFactor.one,
    destinationColorBlendFactor: gpu.BlendFactor.oneMinusSourceAlpha,
    sourceAlphaBlendFactor: gpu.BlendFactor.one,
    destinationAlphaBlendFactor: gpu.BlendFactor.oneMinusSourceAlpha,
  );
  static final _noWrite = gpu.ColorBlendEquation(
    sourceColorBlendFactor: gpu.BlendFactor.zero,
    destinationColorBlendFactor: gpu.BlendFactor.one,
    sourceAlphaBlendFactor: gpu.BlendFactor.zero,
    destinationAlphaBlendFactor: gpu.BlendFactor.one,
  );

  void setClip(_GpuClipState clip) {
    if (identical(_clipState, clip)) return;
    var target = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    final scissor = clip.scissor;
    if (scissor != null) {
      final points = <Offset>[
        Offset(pageToRaster.transformX(scissor.left, scissor.bottom),
            pageToRaster.transformY(scissor.left, scissor.bottom)),
        Offset(pageToRaster.transformX(scissor.right, scissor.bottom),
            pageToRaster.transformY(scissor.right, scissor.bottom)),
        Offset(pageToRaster.transformX(scissor.right, scissor.top),
            pageToRaster.transformY(scissor.right, scissor.top)),
        Offset(pageToRaster.transformX(scissor.left, scissor.top),
            pageToRaster.transformY(scissor.left, scissor.top)),
      ];
      final left = points.map((p) => p.dx).reduce((a, b) => a < b ? a : b);
      final right = points.map((p) => p.dx).reduce((a, b) => a > b ? a : b);
      final top = points.map((p) => p.dy).reduce((a, b) => a < b ? a : b);
      final bottom = points.map((p) => p.dy).reduce((a, b) => a > b ? a : b);
      target = Rect.fromLTRB(
        (left - region.left) * pixelRatio,
        (top - region.top) * pixelRatio,
        (right - region.left) * pixelRatio,
        (bottom - region.top) * pixelRatio,
      ).intersect(target);
    }
    pass.setScissor(gpu.Scissor(
      x: target.left.floor().clamp(0, width),
      y: target.top.floor().clamp(0, height),
      width: (target.right.ceil().clamp(0, width) -
              target.left.floor().clamp(0, width))
          .clamp(0, width),
      height: (target.bottom.ceil().clamp(0, height) -
              target.top.floor().clamp(0, height))
          .clamp(0, height),
    ));
    _clipState = clip;
    _activeClipBit = 0;
    final leaf = clip.node;
    if (leaf == null || clip.empty || target.isEmpty) return;
    clipMaskRebuilds++;

    // A restored clip can be broader than the state used by the preceding
    // draw. Rebuild from the persistent root rather than trying to preserve an
    // ancestor bit whose alternating slot may since have been reused.
    _clearStencil(_allStencilBits);
    final chain = <_GpuClipNode>[];
    for (_GpuClipNode? node = leaf; node != null; node = node.previous) {
      chain.add(node);
    }
    for (final node in chain.reversed) {
      final nextBit = _activeClipBit == _clipBitA ? _clipBitB : _clipBitA;
      _clearStencil(_pathMask | nextBit);
      final draw = clipDraws[node]!;
      _accumulateStencil(
        draw.fan,
        rule: draw.rule,
        union: false,
        requiredClipBit: _activeClipBit,
      );
      pass
        ..setStencilReference(nextBit)
        ..setColorBlendEquation(_noWrite)
        ..setStencilConfig(gpu.StencilConfig(
          compareFunction: gpu.CompareFunction.notEqual,
          depthStencilPassOperation: gpu.StencilOperation.setToReferenceValue,
          stencilFailureOperation: gpu.StencilOperation.keep,
          readMask: _pathMask,
          writeMask: nextBit,
        ))
        ..bindPipeline(pipelines.solid)
        ..bindUniform(pipelines.solidTransform, transform);
      _drawBuffer(draw.cover);
      // The lower bits are scratch. Clearing them here leaves the final clip
      // bit intact and makes the following PDF fill independent of how many
      // contours built this mask.
      _clearStencil(_pathMask);
      _activeClipBit = nextBit;
    }
  }

  void solid(_GpuBuffer vertices) {
    _defaultStencil();
    pass
      ..setColorBlendEquation(_srcOver)
      ..bindPipeline(pipelines.solid)
      ..bindUniform(pipelines.solidTransform, transform);
    _drawBuffer(vertices);
  }

  void stencil(_GpuBuffer fan, _GpuBuffer cover,
      {required PdfFillRule rule, required bool union}) {
    _accumulateStencil(fan,
        rule: rule, union: union, requiredClipBit: _activeClipBit);
    pass
      ..setStencilReference(0)
      ..setColorBlendEquation(_srcOver)
      ..setStencilConfig(gpu.StencilConfig(
        compareFunction: gpu.CompareFunction.notEqual,
        depthStencilPassOperation: gpu.StencilOperation.zero,
        stencilFailureOperation: gpu.StencilOperation.keep,
        readMask: _pathMask,
        writeMask: _pathMask,
      ))
      ..bindPipeline(pipelines.solid)
      ..bindUniform(pipelines.solidTransform, transform);
    _drawBuffer(cover);
  }

  void _accumulateStencil(
    _GpuBuffer fan, {
    required PdfFillRule rule,
    required bool union,
    required int requiredClipBit,
  }) {
    final compare = requiredClipBit == 0
        ? gpu.CompareFunction.always
        : gpu.CompareFunction.equal;
    gpu.StencilConfig config(gpu.StencilOperation operation) =>
        gpu.StencilConfig(
          compareFunction: compare,
          depthStencilPassOperation: operation,
          stencilFailureOperation: gpu.StencilOperation.keep,
          readMask: requiredClipBit == 0 ? 0 : requiredClipBit,
          writeMask: _pathMask,
        );
    pass
      ..setStencilReference(requiredClipBit)
      ..setColorBlendEquation(_noWrite)
      ..bindPipeline(pipelines.stencil)
      ..bindUniform(pipelines.stencilTransform, transform);
    if (union) {
      pass.setStencilConfig(config(gpu.StencilOperation.incrementWrap));
    } else if (rule == PdfFillRule.evenOdd) {
      pass.setStencilConfig(config(gpu.StencilOperation.invert));
    } else {
      pass
        ..setStencilConfig(
          config(gpu.StencilOperation.incrementWrap),
          targetFace: gpu.StencilFace.front,
        )
        ..setStencilConfig(
          config(gpu.StencilOperation.decrementWrap),
          targetFace: gpu.StencilFace.back,
        );
    }
    _drawBuffer(fan);
  }

  void _clearStencil(int mask) {
    if (mask == 0) return;
    pass
      ..setStencilReference(0)
      ..setColorBlendEquation(_noWrite)
      ..setStencilConfig(gpu.StencilConfig(
        compareFunction: gpu.CompareFunction.always,
        depthStencilPassOperation: gpu.StencilOperation.zero,
        readMask: 0,
        writeMask: mask,
      ))
      ..bindPipeline(pipelines.solid)
      ..bindUniform(pipelines.solidTransform, transform);
    _drawBuffer(stencilClear);
  }

  void texture(_GpuBuffer vertices, gpu.Texture texture, gpu.BufferView info) {
    _defaultStencil();
    pass
      ..setColorBlendEquation(_srcOver)
      ..bindPipeline(pipelines.texture)
      ..bindUniform(pipelines.textureTransform, transform)
      ..bindUniform(pipelines.textureInfo, info)
      ..bindTexture(
        pipelines.textureSampler,
        texture,
        sampler: gpu.SamplerOptions(
          minFilter: gpu.MinMagFilter.linear,
          magFilter: gpu.MinMagFilter.linear,
        ),
      );
    _drawBuffer(vertices);
    pass.clearBindings();
  }

  void softMask(_GpuBuffer vertices, gpu.Texture contentTexture,
      gpu.Texture maskTexture, gpu.BufferView info) {
    _defaultStencil();
    final sampler = gpu.SamplerOptions(
      minFilter: gpu.MinMagFilter.linear,
      magFilter: gpu.MinMagFilter.linear,
    );
    pass
      ..setColorBlendEquation(_srcOver)
      ..bindPipeline(pipelines.softMask)
      ..bindUniform(pipelines.softMaskTransform, transform)
      ..bindUniform(pipelines.softMaskInfo, info)
      ..bindTexture(pipelines.softMaskContentSampler, contentTexture,
          sampler: sampler)
      ..bindTexture(pipelines.softMaskMaskSampler, maskTexture,
          sampler: sampler);
    _drawBuffer(vertices);
    pass.clearBindings();
  }

  // flutter_gpu is experimental. Flutter 3.47 split vertex count out of
  // bindVertexBuffer and into draw; 3.44 uses the original pair. Keep this
  // package usable across both stable SDKs without exposing that churn to
  // callers. The one-time dynamic probe is cached for every render pass.
  void _drawBuffer(_GpuBuffer buffer) {
    final dynamic dynamicPass = pass;
    if (_separateVertexCountApi == true) {
      dynamicPass.bindVertexBuffer(buffer.view);
      dynamicPass.draw(buffer.vertices);
      return;
    }
    if (_separateVertexCountApi == false) {
      dynamicPass.bindVertexBuffer(buffer.view, buffer.vertices);
      dynamicPass.draw();
      return;
    }
    try {
      dynamicPass.bindVertexBuffer(buffer.view);
      _separateVertexCountApi = true;
      dynamicPass.draw(buffer.vertices);
    } on NoSuchMethodError {
      _separateVertexCountApi = false;
      dynamicPass.bindVertexBuffer(buffer.view, buffer.vertices);
      dynamicPass.draw();
    }
  }

  void _defaultStencil() {
    pass
      ..setStencilReference(_activeClipBit)
      ..setStencilConfig(gpu.StencilConfig(
        compareFunction: _activeClipBit == 0
            ? gpu.CompareFunction.always
            : gpu.CompareFunction.equal,
        depthStencilPassOperation: gpu.StencilOperation.keep,
        readMask: _activeClipBit == 0 ? 0 : _activeClipBit,
        writeMask: 0,
      ));
  }
}

class _GpuPipelines {
  _GpuPipelines._(gpu.GpuContext context, gpu.ShaderLibrary library)
      : stencil = context.createRenderPipeline(library['PdfTileStencilVertex']!,
            library['PdfTileStencilFragment']!),
        solid = context.createRenderPipeline(
            library['PdfTileSolidVertex']!, library['PdfTileSolidFragment']!),
        texture = context.createRenderPipeline(library['PdfTileTextureVertex']!,
            library['PdfTileTextureFragment']!),
        softMask = context.createRenderPipeline(
            library['PdfTileSoftMaskVertex']!,
            library['PdfTileSoftMaskFragment']!),
        stencilTransform =
            library['PdfTileStencilVertex']!.getUniformSlot('VertInfo'),
        solidTransform =
            library['PdfTileSolidVertex']!.getUniformSlot('VertInfo'),
        textureTransform =
            library['PdfTileTextureVertex']!.getUniformSlot('VertInfo'),
        textureInfo =
            library['PdfTileTextureFragment']!.getUniformSlot('FragInfo'),
        textureSampler =
            library['PdfTileTextureFragment']!.getUniformSlot('tex'),
        softMaskTransform =
            library['PdfTileSoftMaskVertex']!.getUniformSlot('VertInfo'),
        softMaskInfo =
            library['PdfTileSoftMaskFragment']!.getUniformSlot('MaskInfo'),
        softMaskContentSampler =
            library['PdfTileSoftMaskFragment']!.getUniformSlot('content_tex'),
        softMaskMaskSampler =
            library['PdfTileSoftMaskFragment']!.getUniformSlot('mask_tex');

  // Native multi-window builds can expose a distinct Impeller context per
  // Flutter view. Pipelines are context-owned; reusing the first window's
  // pipeline objects in another context produces undefined output rather than
  // a reliable submission error.
  // Expando gives this cache weak, identity-based context keys. A regular
  // static map would keep a closed Flutter window and all of its native
  // pipelines alive for the rest of the process.
  static final Expando<Future<_GpuPipelines>> _instances =
      Expando<Future<_GpuPipelines>>('pdf-gpu-pipelines');

  static Future<_GpuPipelines> instance(gpu.GpuContext context) {
    final existing = _instances[context];
    if (existing != null) return existing;
    return _instances[context] = _loadLibrary().then(
      (library) => _GpuPipelines._(context, library),
    );
  }

  static Future<gpu.ShaderLibrary> _loadLibrary() async {
    final failures = <String, Object>{};
    for (final asset in const [
      'packages/dart_pdf_editor_flutter_gpu/assets/shaders/pdf_tile_gpu.shaderbundle',
      'assets/shaders/pdf_tile_gpu.shaderbundle',
    ]) {
      try {
        // This was synchronous through Flutter 3.44 and returns a Future from
        // 3.47 onward. `await` deliberately accepts both call shapes.
        final library = await Future<gpu.ShaderLibrary?>.value(
          gpu.ShaderLibrary.fromAsset(asset),
        );
        if (library != null) return library;
      } catch (error) {
        // Package-prefixed in an app, bare while this package is the test root.
        // Keep the actual loader error: an incompatible shader bundle must not
        // be collapsed into the same terminal message as a missing asset.
        failures[asset] = error;
      }
    }
    final detail = failures.entries
        .map((entry) => '${entry.key}: ${entry.value}')
        .join('; ');
    throw StateError('pdf_tile_gpu.shaderbundle failed to load'
        '${detail.isEmpty ? '' : ': $detail'}');
  }

  final gpu.RenderPipeline stencil;
  final gpu.RenderPipeline solid;
  final gpu.RenderPipeline texture;
  final gpu.RenderPipeline softMask;
  final gpu.UniformSlot stencilTransform;
  final gpu.UniformSlot solidTransform;
  final gpu.UniformSlot textureTransform;
  final gpu.UniformSlot textureInfo;
  final gpu.UniformSlot textureSampler;
  final gpu.UniformSlot softMaskTransform;
  final gpu.UniformSlot softMaskInfo;
  final gpu.UniformSlot softMaskContentSampler;
  final gpu.UniformSlot softMaskMaskSampler;
}
