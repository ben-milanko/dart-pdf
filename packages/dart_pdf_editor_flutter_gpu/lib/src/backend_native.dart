import 'dart:async' show Completer, FutureOr;
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
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
/// submit a render pass. No PDF interpretation, image decode, texture upload,
/// or CPU pixel readback occurs per tile. Fixed-width paths are tessellated
/// once; zero-width hairlines alone expand their retained polyline for the
/// current device scale.
///
/// The exact subset includes a common isolated single-image soft-mask group
/// and decoded images whose `/SMask` stayed as a companion GPU surface:
/// content and mask stay as separate scene-lifetime textures and are combined
/// by the tile shader. Ordinary PDF clip paths are retained as exact stencil
/// masks (with rectangular clips additionally using the hardware scissor).
/// Destination-dependent PDF blend modes use ordered shader-readable tile
/// passes; Multiply and Screen keep their cheaper fixed-function equations.
/// Other isolated groups, complex clips *inside* the special soft-mask
/// shortcuts, non-nested radial gradients, substituted/stroked text, unsafe
/// overprint, or missing image pixels reject the whole scene. Zero-width PDF
/// hairlines are expanded at tile submission time so they remain exactly one
/// device pixel at every level of detail. dart_pdf_editor then permanently
/// uses its Canvas session for that scene.
class FlutterGpuTileRasterBackend extends PdfTileRasterBackend {
  FlutterGpuTileRasterBackend({
    this.msaa = true,
    this.allowOverprintApproximation = false,
    this.maxTextureBytes = 256 << 20,
    this.maxGeometryBytes = 256 << 20,
    this.enableProactiveWarmUp,
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

  /// Whether the viewer should prepare GPU pipelines and live scenes at idle.
  ///
  /// Null (the default) enables proactive work on desktop and leaves mobile
  /// on-demand. Mobile Impeller contexts can reserve substantial additional
  /// memory even for a page that later falls back to Canvas; validated hosts
  /// can opt in explicitly.
  final bool? enableProactiveWarmUp;

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

  bool get _proactiveWarmUpEnabled =>
      enableProactiveWarmUp ??
      switch (defaultTargetPlatform) {
        TargetPlatform.macOS ||
        TargetPlatform.windows ||
        TargetPlatform.linux =>
          true,
        _ => false,
      };

  @override
  bool get supportsWarmUp => _proactiveWarmUpEnabled;

  @override
  bool get supportsSessionWarmUp => _proactiveWarmUpEnabled;

  /// Drops reusable texture ownership. Active compiled scenes retain the
  /// resources they are currently drawing.
  void clearImageCache() => _imageCache.clear(stats);

  /// Compiles this view's tile pipelines with a one-pixel GPU submission.
  ///
  /// The driver otherwise compiles the pipelines on the first deep-zoom tile,
  /// which can leave the coarse page visible for hundreds of milliseconds.
  /// This is safe to call repeatedly: work is shared per Impeller context and
  /// MSAA mode, including between backend instances.
  @override
  Future<void> warmUp() async {
    final clock = Stopwatch()..start();
    stats.warmUpRequests++;
    try {
      final context = gpu.gpuContext;
      final pipelines = await _GpuPipelines.instance(context);
      final submitted = await pipelines.warmUp(
        context,
        useMsaa: msaa && context.doesSupportOffscreenMSAA,
      );
      if (submitted) stats.warmUpSubmissions++;
      stats.warmUpCompletions++;
    } catch (error) {
      stats
        ..warmUpFailures += 1
        ..lastWarmUpError = error.toString();
      rethrow;
    } finally {
      stats.warmUpMicros += clock.elapsedMicroseconds;
    }
  }

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
        mipmapImages: commandBuild.mipmapImages,
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
      if (!_isGpuBlendMode(unit.blendMode)) {
        return 'blend mode ${unit.blendMode.name}';
      }
      final composite = unit.composite;
      if (composite != null) {
        switch (composite) {
          case _SoftMaskImageSpec():
            if (scene.imageFor(composite.content) == null ||
                scene.imageFor(composite.mask) == null) {
              return 'missing soft-mask image pixels';
            }
          case _SoftMaskFillSpec():
            if (scene.imageFor(composite.mask) == null) {
              return 'missing soft-mask image pixels';
            }
          case _SoftMaskVectorFillSpec():
            break;
          case _GroupFillSpec():
            break;
          case _GroupStrokeSpec():
            break;
          case _GroupPaintSpec():
            break;
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
        case PdfStrokePathCommand():
          break;
        case PdfFillMeshCommand():
          break;
        case PdfDrawImageCommand(:final request):
          final image = scene.imageFor(request);
          if (image == null) return 'missing image pixels';
        case PdfDrawTextCommand(:final run):
          if (run.invisible) continue;
          final gradientReason = run.gradient == null
              ? null
              : _gradientUnsupportedReason(run.gradient!, run.fillAlpha);
          final textReasons = <String>[
            if (run.glyphs == null) 'missing glyph outlines',
            if (!run.fill) 'fill disabled',
            if (gradientReason != null) gradientReason,
            if (run.strokeColor != null) 'stroke',
          ];
          if (textReasons.isNotEmpty) {
            return 'unsupported text: ${textReasons.join(', ')}';
          }
        case PdfFillPathGradientCommand():
          final reason =
              _gradientUnsupportedReason(command.gradient, command.alpha);
          if (reason != null) return reason;
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
              PdfEndSoftMaskedCommand():
          if (covered.contains(i)) break;
          return 'unsafe ${command.runtimeType}';
        case PdfSetBlendModeCommand(:final mode):
          if (!_isGpuBlendMode(mode)) return 'blend mode ${mode.name}';
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

  static bool _isGpuBlendMode(PdfBlendMode mode) => switch (mode) {
        PdfBlendMode.normal ||
        PdfBlendMode.multiply ||
        PdfBlendMode.screen ||
        PdfBlendMode.overlay ||
        PdfBlendMode.darken ||
        PdfBlendMode.lighten ||
        PdfBlendMode.colorDodge ||
        PdfBlendMode.colorBurn ||
        PdfBlendMode.hardLight ||
        PdfBlendMode.softLight ||
        PdfBlendMode.difference ||
        PdfBlendMode.exclusion ||
        PdfBlendMode.hue ||
        PdfBlendMode.saturation ||
        PdfBlendMode.color ||
        PdfBlendMode.luminosity =>
          true,
      };

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
    this.hairline = false,
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
  final bool hairline;
  final _GpuCompositeSpec? composite;
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

sealed class _GpuCompositeSpec {
  const _GpuCompositeSpec();
  PdfRect? get contentClip;
}

class _GroupFillSpec extends _GpuCompositeSpec {
  const _GroupFillSpec({
    required this.content,
    required this.groupAlpha,
    required this.contentClip,
  });

  final PdfFillPathCommand content;
  final double groupAlpha;
  @override
  final PdfRect? contentClip;
}

class _GroupStrokeSpec extends _GpuCompositeSpec {
  const _GroupStrokeSpec({
    required this.content,
    required this.groupAlpha,
    required this.contentClip,
  });

  final PdfStrokePathCommand content;
  final double groupAlpha;
  @override
  final PdfRect? contentClip;
}

class _GroupPaintSpec extends _GpuCompositeSpec {
  const _GroupPaintSpec({
    required this.commands,
    required this.contentClip,
  });

  final List<PdfRenderCommand> commands;
  @override
  final PdfRect? contentClip;
}

class _SoftMaskImageSpec extends _GpuCompositeSpec {
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
  @override
  final PdfRect? contentClip;
  final PdfRect? maskClip;
  final bool luminosity;
  final double backdropLuminance;
  final double transferScale;
  final double transferOffset;
}

class _SoftMaskFillSpec extends _GpuCompositeSpec {
  const _SoftMaskFillSpec({
    required this.content,
    required this.mask,
    required this.contentClip,
    required this.maskClip,
    required this.luminosity,
    required this.backdropLuminance,
    required this.transferScale,
    required this.transferOffset,
  });

  final PdfFillPathCommand content;
  final PdfImageRequest mask;
  @override
  final PdfRect? contentClip;
  final PdfRect? maskClip;
  final bool luminosity;
  final double backdropLuminance;
  final double transferScale;
  final double transferOffset;
}

class _SoftMaskVectorFillSpec extends _GpuCompositeSpec {
  const _SoftMaskVectorFillSpec({
    required this.content,
    required this.maskFills,
    required this.contentClip,
    required this.luminosity,
    required this.backdropLuminance,
    required this.transferScale,
    required this.transferOffset,
  });

  final PdfFillPathCommand content;
  final List<_VectorMaskFill> maskFills;
  @override
  final PdfRect? contentClip;
  final bool luminosity;
  final double backdropLuminance;
  final double transferScale;
  final double transferOffset;
}

class _VectorMaskFill {
  const _VectorMaskFill(this.rect, this.color, this.alpha);

  final PdfRect rect;
  final PdfColor color;
  final double alpha;
}

class _GpuCommandBuild {
  const _GpuCommandBuild(
    this.commands,
    this.rejection, {
    required this.mipmapImages,
  });

  final List<PdfRenderCommand>? commands;
  final String? rejection;
  final bool mipmapImages;
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
  var mipmapImages = false;

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
          // Canvas uses FilterQuality.medium for every image on the page.
          // Once a retained bitmap-font cell needs minification, match that
          // sampling mode for the whole GPU scene; mixing base-only and
          // mipmapped images on the same Ghent page is measurably less exact.
          mipmapImages = true;
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
  if (!hasTiledCell) {
    return _GpuCommandBuild(source, null, mipmapImages: false);
  }
  if (expandedCount > maxExpandedCommands) {
    return const _GpuCommandBuild(
      null,
      'expanded tiling cells exceed GPU command cap',
      mipmapImages: false,
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
      mipmapImages: false,
    );
  }
  return _GpuCommandBuild(
    List.unmodifiable(expanded),
    null,
    mipmapImages: mipmapImages,
  );
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
          final parsed = _parseComposite(
            commands,
            capture.start,
            i,
            initialClip: capture.clip.scissor,
            initialFillOverprint: capture.fillOverprint,
            initialStrokeOverprint: capture.strokeOverprint,
            initialBlend: capture.blendMode,
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
            hairline:
                command is PdfStrokePathCommand && command.stroke.width <= 0,
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

(_GpuCompositeSpec?, String?) _parseComposite(
  List<PdfRenderCommand> commands,
  int start,
  int end, {
  PdfRect? initialClip,
  bool initialFillOverprint = false,
  bool initialStrokeOverprint = false,
  PdfBlendMode initialBlend = PdfBlendMode.normal,
}) {
  if (commands[start]
      case PdfBeginGroupCommand(:final alpha, :final knockout)) {
    if (commands[end] is! PdfEndGroupCommand) {
      return (null, 'unsupported composite nesting');
    }
    // Knockout only changes how multiple sibling elements interact inside a
    // group. A one-element group is therefore identical either way. The
    // multi-paint path below is deliberately narrower: alpha-one, normal
    // source-over, non-knockout groups whose isolation layer is an identity.
    PdfDrawImageCommand? content;
    final paints = <(PdfRenderCommand, PdfRect?, PdfBlendMode, bool)>[];
    PdfEndSoftMaskedCommand? softEnd;
    var softDepth = 0;
    var softCount = 0;
    PdfRect? clip = initialClip;
    PdfRect? contentClip;
    var fillOverprint = initialFillOverprint;
    var strokeOverprint = initialStrokeOverprint;
    var blend = initialBlend;
    final saved = <(PdfRect?, bool, bool, PdfBlendMode)>[];
    for (var i = start + 1; i < end; i++) {
      final command = commands[i];
      switch (command) {
        case PdfSaveCommand():
          saved.add((clip, fillOverprint, strokeOverprint, blend));
        case PdfRestoreCommand():
          if (saved.isEmpty) return (null, 'unbalanced soft-mask image state');
          final restored = saved.removeLast();
          clip = restored.$1;
          fillOverprint = restored.$2;
          strokeOverprint = restored.$3;
          blend = restored.$4;
        case PdfClipPathCommand(:final path):
          if (!FlutterGpuTileRasterBackend._isAxisAlignedRect(path)) {
            return (null, 'non-rectangular soft-mask image clip');
          }
          final pathBounds = pdfRenderPathBounds(path);
          final narrowed = _pdfIntersection(clip, pathBounds);
          if (clip != null && pathBounds != null && narrowed == null) {
            return (null, 'empty transparency group clip');
          }
          clip = narrowed;
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
        case PdfFillPathCommand():
          if (softDepth != 0 || content != null) {
            return (null, 'soft-mask group contains PdfFillPathCommand');
          }
          paints.add((command, clip, blend, fillOverprint));
          contentClip = clip;
        case PdfStrokePathCommand():
          if (softDepth != 0 || content != null) {
            return (null, 'soft-mask group contains PdfStrokePathCommand');
          }
          paints.add((command, clip, blend, strokeOverprint));
          contentClip = clip;
        case PdfSetBlendModeCommand(:final mode):
          // A one-element group may use any internal blend: with a transparent
          // group backdrop every PDF blend function reduces to the source.
          // The multi-paint identity path validates Normal below.
          blend = mode;
        case PdfSetOverprintCommand(:final fill, :final stroke):
          fillOverprint = fill;
          strokeOverprint = stroke;
        case PdfBeginGroupCommand() || PdfEndGroupCommand():
          return (null, 'nested image group');
        default:
          if (pdfRenderCommandBounds(command) != null) {
            return (null, 'soft-mask group contains ${command.runtimeType}');
          }
      }
    }
    if (saved.isNotEmpty) {
      return (null, 'unbalanced transparency group state');
    }
    if (softCount == 0 && softDepth == 0 && paints.length == 1) {
      final paint = paints.single;
      if (paint.$4) {
        return (
          null,
          paint.$1 is PdfStrokePathCommand
              ? 'transparency-group stroke overprint'
              : 'transparency-group fill overprint',
        );
      }
      return switch (paint.$1) {
        PdfFillPathCommand content => (
            _GroupFillSpec(
              content: content,
              groupAlpha: alpha,
              contentClip: paint.$2,
            ),
            null,
          ),
        PdfStrokePathCommand content => (
            _GroupStrokeSpec(
              content: content,
              groupAlpha: alpha,
              contentClip: paint.$2,
            ),
            null,
          ),
        _ => (null, 'unsupported transparency-group paint'),
      };
    }
    if (softCount == 0 && softDepth == 0 && paints.length > 1) {
      final commonClip = paints.first.$2;
      if (alpha != 1 ||
          knockout ||
          initialBlend != PdfBlendMode.normal ||
          paints.any((paint) =>
              paint.$3 != PdfBlendMode.normal ||
              paint.$4 ||
              !_samePdfRect(paint.$2, commonClip))) {
        return (null, 'non-identity multi-paint transparency group');
      }
      return (
        _GroupPaintSpec(
          commands: List.unmodifiable([for (final paint in paints) paint.$1]),
          contentClip: commonClip,
        ),
        null,
      );
    }
    if (softCount != 1 ||
        softDepth != 0 ||
        paints.isNotEmpty ||
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
  final endCommand = commands[end];
  if (commands[start] is PdfBeginSoftMaskedCommand &&
      endCommand is PdfEndSoftMaskedCommand) {
    final maskCommands = endCommand.maskCommands;
    final luminosity = endCommand.luminosity;
    final backdropLuminance = endCommand.backdropLuminance;
    final transferScale = endCommand.transferScale;
    final transferOffset = endCommand.transferOffset;
    PdfFillPathCommand? content;
    PdfRect? clip = initialClip;
    PdfRect? contentClip;
    final saved = <PdfRect?>[];
    for (var i = start + 1; i < end; i++) {
      final command = commands[i];
      switch (command) {
        case PdfSaveCommand():
          saved.add(clip);
        case PdfRestoreCommand():
          if (saved.isEmpty) return (null, 'unbalanced soft-mask fill state');
          clip = saved.removeLast();
        case PdfClipPathCommand(:final path):
          if (!FlutterGpuTileRasterBackend._isAxisAlignedRect(path)) {
            return (null, 'non-rectangular soft-mask fill clip');
          }
          clip = _pdfIntersection(clip, pdfRenderPathBounds(path));
        case PdfFillPathCommand():
          if (content != null) {
            return (null, 'soft-mask group has multiple vector fills');
          }
          content = command;
          contentClip = clip;
        case PdfSetBlendModeCommand():
          // This shortcut accepts exactly one painted element in the isolated
          // soft-mask capture. Every PDF blend function reduces to the source
          // when the backdrop alpha is zero, so the active blend mode cannot
          // affect that element's captured pixels. The completed masked layer
          // is then composited normally, matching CanvasPdfDevice's two-layer
          // beginSoftMasked/endSoftMasked sequence.
          break;
        case PdfSetOverprintCommand():
          // Like blend modes above, overprint has no backdrop colorants to
          // preserve inside this isolated, initially transparent capture.
          // With one painted fill it therefore reduces to the same source.
          break;
        default:
          if (pdfRenderCommandBounds(command) != null) {
            return (null, 'soft-mask fill contains ${command.runtimeType}');
          }
      }
    }
    if (saved.isNotEmpty || content == null) {
      return (null, 'unsupported soft-mask fill group');
    }
    final maskState = _singleMaskImage(maskCommands);
    final mask = maskState.$1;
    if (mask == null) {
      final vectorMask = _vectorMaskFills(maskCommands);
      final maskFills = vectorMask.$1;
      if (maskFills == null) return (null, vectorMask.$2 ?? maskState.$3);
      if (![backdropLuminance, transferScale, transferOffset]
          .every((value) => value.isFinite)) {
        return (null, 'invalid vector soft-mask transfer');
      }
      return (
        _SoftMaskVectorFillSpec(
          content: content,
          maskFills: maskFills,
          contentClip: contentClip,
          luminosity: luminosity,
          backdropLuminance: backdropLuminance,
          transferScale: transferScale,
          transferOffset: transferOffset,
        ),
        null,
      );
    }
    if (mask.request.isStencil) {
      return (null, 'stencil soft-mask fill image');
    }
    final maskDictionary = mask.request.stream.dictionary;
    if (maskDictionary['SMask'] != null || maskDictionary['Mask'] != null) {
      return (null, 'transparent soft-mask fill image');
    }
    return (
      _SoftMaskFillSpec(
        content: content,
        mask: mask.request,
        contentClip: contentClip,
        maskClip: maskState.$2,
        luminosity: luminosity,
        backdropLuminance: backdropLuminance,
        transferScale: transferScale,
        transferOffset: transferOffset,
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

(List<_VectorMaskFill>?, String?) _vectorMaskFills(
    List<PdfRenderCommand> commands) {
  const maxFills = 32;
  final fills = <_VectorMaskFill>[];
  PdfRect? clip;
  var clipEmpty = false;
  final saved = <(PdfRect?, bool)>[];
  for (final command in commands) {
    switch (command) {
      case PdfSaveCommand():
        saved.add((clip, clipEmpty));
      case PdfRestoreCommand():
        if (saved.isEmpty) return (null, 'unbalanced vector mask state');
        final restored = saved.removeLast();
        clip = restored.$1;
        clipEmpty = restored.$2;
      case PdfClipPathCommand(:final path):
        if (!FlutterGpuTileRasterBackend._isAxisAlignedRect(path)) {
          return (null, 'non-rectangular vector mask clip');
        }
        if (clipEmpty) continue;
        final narrowed = _pdfIntersection(clip, pdfRenderPathBounds(path));
        if (narrowed == null) {
          clipEmpty = true;
        } else {
          clip = narrowed;
        }
      case PdfFillPathCommand(
          :final path,
          :final color,
          :final alpha,
        ):
        if (!FlutterGpuTileRasterBackend._isAxisAlignedRect(path)) {
          return (null, 'non-rectangular vector mask fill');
        }
        if (clipEmpty) continue;
        final rect = _pdfIntersection(clip, pdfRenderPathBounds(path));
        if (rect != null) fills.add(_VectorMaskFill(rect, color, alpha));
        if (fills.length > maxFills) {
          return (null, 'vector mask fill count exceeds GPU cap');
        }
      case PdfSetBlendModeCommand(:final mode):
        if (mode != PdfBlendMode.normal) {
          return (null, 'vector mask blend mode ${mode.name}');
        }
      case PdfSetOverprintCommand(:final fill, :final stroke):
        if (fill || stroke) return (null, 'vector mask overprint');
      default:
        if (pdfRenderCommandBounds(command) != null) {
          return (null, 'vector mask contains ${command.runtimeType}');
        }
    }
  }
  if (saved.isNotEmpty) return (null, 'unbalanced vector mask state');
  if (fills.isEmpty) return (null, 'vector mask has no fills');
  return (List.unmodifiable(fills), null);
}

List<_GpuUnit> _selectGpuUnits(List<_GpuUnit> units, PdfMatrix pageToRaster,
    Rect rasterRegion, double pixelRatio) {
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
  final scale = _pageDeviceScale(pageToRaster, pixelRatio);
  // Unit bounds already carry a 2pt safety pad. At very low LoD a one-pixel
  // hairline can be wider than that in page space, so expand its query bounds
  // by the remainder. This keeps a line just outside a tile from being
  // incorrectly culled when its device footprint still reaches the tile.
  final hairlinePadding = math.max(0.0, 0.5 / scale - 2);
  return [
    for (final unit in units)
      if (_pdfIntersects(
          unit.hairline && hairlinePadding > 0
              ? _inflatePdf(unit.bounds, hairlinePadding)
              : unit.bounds,
          page))
        unit
  ];
}

double _pageDeviceScale(PdfMatrix pageToRaster, double pixelRatio) {
  final determinant =
      pageToRaster.a * pageToRaster.d - pageToRaster.b * pageToRaster.c;
  return math.max(1e-12, math.sqrt(determinant.abs()) * pixelRatio);
}

bool _usesDestinationBlend(PdfBlendMode mode) =>
    mode != PdfBlendMode.normal &&
    mode != PdfBlendMode.multiply &&
    mode != PdfBlendMode.screen;

ByteData _destinationBlendVertices() => ByteData.sublistView(
      Float32List.fromList(const [
        -1, -1, 0, 1, //
        1, -1, 1, 1, //
        1, 1, 1, 0, //
        -1, -1, 0, 1, //
        1, 1, 1, 0, //
        -1, 1, 0, 0, //
      ]),
    );

ByteData _destinationBlendInfo(PdfBlendMode? mode) => ByteData.sublistView(
      Float32List.fromList([
        mode?.index.toDouble() ?? -1,
        0,
        0,
        0,
      ]),
    );

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

bool _samePdfRect(PdfRect? a, PdfRect? b) =>
    identical(a, b) ||
    (a != null &&
        b != null &&
        a.left == b.left &&
        a.bottom == b.bottom &&
        a.right == b.right &&
        a.top == b.top);

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
    case PdfFillPathGradientCommand():
      if (unit.fillOverprint) return 'gradient overprint';
    case PdfDrawTextCommand(:final run):
      if (unit.fillOverprint && run.gradient != null) {
        return 'gradient text overprint';
      }
    default:
      // Images do not use CanvasPdfDevice's overprint approximation; the
      // interpreter has already resolved any image-adjacent colorant work.
      break;
  }
  return null;
}

String? _gradientUnsupportedReason(PdfGradient gradient, double alpha) {
  if (gradient.colors.length < 2 ||
      gradient.colors.length != gradient.stops.length ||
      gradient.transform.inverted() == null ||
      !alpha.isFinite ||
      ![
        gradient.transform.a,
        gradient.transform.b,
        gradient.transform.c,
        gradient.transform.d,
        gradient.transform.e,
        gradient.transform.f,
      ].every((value) => value.isFinite)) {
    return 'invalid axial gradient';
  }
  if (gradient.isRadial) {
    if (gradient.coords.length < 6) return 'invalid radial gradient';
    final x0 = gradient.coords[0], y0 = gradient.coords[1];
    final r0 = gradient.coords[2];
    final x1 = gradient.coords[3], y1 = gradient.coords[4];
    final r1 = gradient.coords[5];
    final dx = x1 - x0, dy = y1 - y0, dr = r1 - r0;
    final centerDistance = math.sqrt(dx * dx + dy * dy);
    if (![x0, y0, r0, x1, y1, r1].every((value) => value.isFinite) ||
        r0 < 0 ||
        r1 < 0 ||
        dr.abs() <= 1e-9 ||
        centerDistance > dr.abs() + 1e-6) {
      return 'unsupported non-nested radial gradient';
    }
  } else if (gradient.coords.length < 4) {
    return 'invalid axial gradient';
  }
  if (gradient.isRadial) return null;
  final dx = gradient.coords[2] - gradient.coords[0];
  final dy = gradient.coords[3] - gradient.coords[1];
  if (!dx.isFinite || !dy.isFinite || dx * dx + dy * dy <= 1e-12) {
    return 'invalid axial gradient';
  }
  var previous = double.negativeInfinity;
  for (final stop in gradient.stops) {
    if (!stop.isFinite || stop <= previous) return 'invalid axial gradient';
    previous = stop;
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
    implements
        PdfTileRasterSession,
        PdfTileRasterScheduling,
        PdfTileRasterWarmUp {
  _FlutterGpuTileSession({
    required this.scene,
    required this.commands,
    required this.mipmapImages,
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
  final bool mipmapImages;

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
  Future<void>? _prewarm;
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
        mipmapImages: mipmapImages,
      ).then((compiled) {
        if (_disposed) {
          compiled.dispose();
          throw StateError('flutter_gpu tile session disposed');
        }
        return _ready = compiled;
      }).whenComplete(scene.releaseDecodedImagePixels);

  @override
  Future<void> warmUp() => _prewarm ??= _warmUpScene();

  Future<void> _warmUpScene() async {
    if (_disposed) return;
    final clock = Stopwatch()..start();
    stats.sceneWarmUpRequests++;
    ui.Image? image;
    try {
      final compiled = await _compile();
      final gpuPipelines = await pipelines;
      await gpuPipelines.warmUp(
        context,
        useMsaa: msaa && context.doesSupportOffscreenMSAA,
      );
      if (_disposed) throw StateError('flutter_gpu tile session disposed');
      final size = scene.pageSize;
      final ratio = 1 / math.max(1.0, math.max(size.width, size.height));
      image = compiled.render(
        units,
        region: Offset.zero & size,
        pixelRatio: ratio,
        pipelines: gpuPipelines,
        useMsaa: msaa,
      );
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bytes == null) throw StateError('GPU scene warm-up readback failed');
      stats.sceneWarmUpCompletions++;
      PdfPerfLog.log(
        'tile gpu scene warm commands=${units.length} '
        'elapsed=${clock.elapsedMilliseconds}ms',
      );
    } catch (error) {
      // A page leaving the cache while this optional idle pass is in flight is
      // ordinary cancellation, not a backend failure or a reason to report a
      // Canvas fallback for a scene that no longer has an owner.
      if (_disposed) {
        stats.sceneWarmUpCancellations++;
        return;
      }
      stats
        ..sceneWarmUpFailures += 1
        ..lastSceneWarmUpError = error.toString();
      rethrow;
    } finally {
      image?.dispose();
      stats.sceneWarmUpMicros += clock.elapsedMicroseconds;
    }
  }

  @override
  Future<ui.Image> rasterizeRegion(
    Rect region, {
    required double pixelRatio,
    int? tracePage,
  }) async {
    if (_disposed) throw StateError('flutter_gpu tile session disposed');
    try {
      final prewarm = _prewarm;
      if (prewarm != null) await prewarm;
      final compiled = await _compile();
      final gpuPipelines = await pipelines;
      if (_disposed) throw StateError('flutter_gpu tile session disposed');
      final issue = Stopwatch()..start();
      final selected =
          _selectGpuUnits(units, compiled.pageToRaster, region, pixelRatio);
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
      {required bool mipmapImages}) async {
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
            mipmapImages: mipmapImages,
          );
          draw = pending is Future<_GpuDraw?> ? await pending : pending;
        } else {
          draw = switch (unit.composite!) {
            _GroupFillSpec spec => _compileGroupFill(geometry, spec),
            _GroupStrokeSpec spec => _compileGroupStroke(geometry, spec),
            _GroupPaintSpec spec => _compileGroupPaint(geometry, spec),
            _SoftMaskImageSpec spec => await _compileSoftMaskImage(
                context,
                geometry,
                scene,
                spec,
                stats,
                imageCache,
                textureLeases,
                mipmapImages: mipmapImages,
              ),
            _SoftMaskFillSpec spec => await _compileSoftMaskFill(
                context,
                geometry,
                scene,
                spec,
                stats,
                imageCache,
                textureLeases,
                mipmapImages: mipmapImages,
              ),
            _SoftMaskVectorFillSpec spec =>
              _compileSoftMaskVectorFill(geometry, spec),
          };
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
    if (selected.any((unit) => _usesDestinationBlend(unit.blendMode))) {
      return _renderDestinationBlends(
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
      emplaceTransient: transient.emplace,
    );
    encoder
      ..setClip(_rootGpuClip)
      ..solid(paper.vertices);
    for (final unit in selected) {
      final draw = draws[unit.commandIndex];
      if (draw == null) continue;
      encoder
        ..setClip(unit.clip)
        ..setBlendMode(unit.blendMode);
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

  ui.Image _renderDestinationBlends(
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
    // Keep every write-then-sample dependency in a separately submitted
    // command buffer. Stable Flutter 3.47 Metal can segfault when a later
    // render pass samples a texture written by an earlier pass in the same
    // command buffer; ordered queue submissions preserve the dependency
    // without a CPU fence.
    final multisampled = useMsaa && context.doesSupportOffscreenMSAA;
    final targets = <gpu.Texture>[
      for (var i = 0; i < 2; i++)
        context.createTexture(
          gpu.StorageMode.devicePrivate,
          width,
          height,
          format: context.defaultColorFormat,
          enableRenderTargetUsage: true,
          enableShaderReadUsage: true,
        ),
    ];
    final source = context.createTexture(
      gpu.StorageMode.devicePrivate,
      width,
      height,
      format: context.defaultColorFormat,
      enableRenderTargetUsage: true,
      enableShaderReadUsage: true,
    );
    final msaaColor = multisampled
        ? context.createTexture(
            gpu.StorageMode.deviceTransient,
            width,
            height,
            format: context.defaultColorFormat,
            sampleCount: 4,
          )
        : null;
    final stencil = context.createTexture(
      gpu.StorageMode.deviceTransient,
      width,
      height,
      format: context.defaultStencilFormat,
      sampleCount: multisampled ? 4 : 1,
    );
    final resident = <Object>[
      ...targets,
      source,
      if (msaaColor != null) msaaColor,
      stencil,
    ];

    void submit(
      gpu.CommandBuffer commandBuffer,
      gpu.RenderPass pass,
      gpu.HostBuffer transient,
      int commandCount,
    ) {
      final submitClock = Stopwatch()..start();
      final completion = Stopwatch()..start();
      final resources = <Object>[
        ...resident,
        commandBuffer,
        pass,
        transient,
      ];
      _inFlight++;
      stats
        ..inFlightSubmissions += 1
        ..peakInFlightSubmissions = math.max(
          stats.peakInFlightSubmissions,
          stats.inFlightSubmissions,
        );
      try {
        commandBuffer.submit(completionCallback: (success) {
          if (resources.isEmpty) return;
          _completeSubmission(
            success,
            completion,
            tracePage,
            width,
            height,
            commandCount,
          );
        });
      } catch (_) {
        _inFlight--;
        stats
          ..inFlightSubmissions = math.max(0, stats.inFlightSubmissions - 1)
          ..failedSubmissions += 1;
        _releaseResourcesIfReady();
        rethrow;
      } finally {
        stats.submitMicros += submitClock.elapsedMicroseconds;
      }
    }

    gpu.RenderPass drawPass(
      gpu.CommandBuffer commandBuffer,
      gpu.Texture target,
    ) {
      return commandBuffer.createRenderPass(gpu.RenderTarget(
        colorAttachments: [
          gpu.ColorAttachment(
            texture: multisampled ? msaaColor! : target,
            resolveTexture: multisampled ? target : null,
            loadAction: gpu.LoadAction.clear,
            clearValue: vm.Vector4.zero(),
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
    }

    void renderUnits(
      List<_GpuUnit> units,
      gpu.Texture target, {
      required bool includePaper,
      gpu.Texture? copyFrom,
    }) {
      final commandBuffer = context.createCommandBuffer();
      final pass = drawPass(commandBuffer, target);
      pass
        ..setCullMode(gpu.CullMode.none)
        ..setWindingOrder(gpu.WindingOrder.counterClockwise)
        ..setPrimitiveType(gpu.PrimitiveType.triangle)
        ..setStencilReference(0)
        ..setColorBlendEnable(true);
      final transient = context.createHostBuffer();
      if (copyFrom != null) {
        // Do not replace this draw with copyTextureToTexture followed by an
        // attachment load. On Flutter 3.47 Metal, a shader-readable offscreen
        // target is not preserved by that load sequence (including without
        // MSAA), which blanks the accumulated tile. Copying through this pass
        // is the stable path and also seeds every MSAA sample exactly once.
        _encodeDestinationBlend(
          pass,
          pipelines,
          transient,
          destination: copyFrom,
          source: source,
        );
        pass.setColorBlendEnable(true);
      }
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
        emplaceTransient: transient.emplace,
      );
      if (includePaper) {
        encoder
          ..setClip(_rootGpuClip)
          ..solid(paper.vertices);
      }
      for (final unit in units) {
        final draw = draws[unit.commandIndex];
        if (draw == null) continue;
        encoder
          ..setClip(unit.clip)
          ..setBlendMode(unit.blendMode);
        draw.encode(encoder);
      }
      stats.clipMaskRebuilds += encoder.clipMaskRebuilds;
      submit(commandBuffer, pass, transient, units.length);
    }

    void renderSource(_GpuUnit unit) {
      final commandBuffer = context.createCommandBuffer();
      final pass = drawPass(commandBuffer, source);
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
        emplaceTransient: transient.emplace,
      );
      final draw = draws[unit.commandIndex];
      if (draw != null) {
        encoder
          ..setClip(unit.clip)
          ..setBlendMode(PdfBlendMode.normal);
        draw.encode(encoder);
      }
      stats.clipMaskRebuilds += encoder.clipMaskRebuilds;
      submit(commandBuffer, pass, transient, 1);
    }

    void composite(
      gpu.Texture destination,
      gpu.Texture output,
      PdfBlendMode mode,
    ) {
      final commandBuffer = context.createCommandBuffer();
      final pass = commandBuffer.createRenderPass(
        gpu.RenderTarget.singleColor(gpu.ColorAttachment(
          texture: output,
          clearValue: vm.Vector4.zero(),
          storeAction: gpu.StoreAction.store,
        )),
      );
      pass
        ..setCullMode(gpu.CullMode.none)
        ..setWindingOrder(gpu.WindingOrder.counterClockwise)
        ..setPrimitiveType(gpu.PrimitiveType.triangle)
        ..setColorBlendEnable(false);
      final transient = context.createHostBuffer();
      _encodeDestinationBlend(
        pass,
        pipelines,
        transient,
        destination: destination,
        source: source,
        mode: mode,
      );
      submit(commandBuffer, pass, transient, 1);
    }

    var current = 0;
    var initialized = false;
    final ordinary = <_GpuUnit>[];
    void flushOrdinary() {
      if (initialized && ordinary.isEmpty) return;
      if (!initialized) {
        renderUnits(
          ordinary,
          targets[current],
          includePaper: true,
        );
        initialized = true;
      } else {
        final next = 1 - current;
        renderUnits(
          ordinary,
          targets[next],
          includePaper: false,
          copyFrom: targets[current],
        );
        current = next;
      }
      ordinary.clear();
    }

    for (final unit in selected) {
      if (!_usesDestinationBlend(unit.blendMode)) {
        ordinary.add(unit);
        continue;
      }
      flushOrdinary();
      renderSource(unit);
      final next = 1 - current;
      composite(targets[current], targets[next], unit.blendMode);
      current = next;
    }
    flushOrdinary();
    stats.issueMicros += issue.elapsedMicroseconds;
    return targets[current].asImage();
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

void _encodeDestinationBlend(
  gpu.RenderPass pass,
  _GpuPipelines pipelines,
  gpu.HostBuffer transient, {
  required gpu.Texture destination,
  required gpu.Texture source,
  PdfBlendMode? mode,
}) {
  final vertices = transient.emplace(_destinationBlendVertices());
  final info = transient.emplace(_destinationBlendInfo(mode));
  final sampler = gpu.SamplerOptions(
    minFilter: gpu.MinMagFilter.nearest,
    magFilter: gpu.MinMagFilter.nearest,
  );
  pass
    ..setColorBlendEnable(false)
    ..bindPipeline(pipelines.destinationBlend)
    ..bindUniform(pipelines.destinationBlendInfo, info)
    ..bindTexture(
      pipelines.destinationBlendDestination,
      destination,
      sampler: sampler,
    )
    ..bindTexture(
      pipelines.destinationBlendSource,
      source,
      sampler: sampler,
    );
  final dynamic dynamicPass = pass;
  try {
    dynamicPass.bindVertexBuffer(vertices);
    dynamicPass.draw(6);
  } on NoSuchMethodError {
    dynamicPass.bindVertexBuffer(vertices, 6);
    dynamicPass.draw();
  }
  pass.clearBindings();
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
    {required bool mipmapImages}) async {
  final contentImage = scene.imageFor(spec.content)!;
  final maskImage = scene.imageFor(spec.mask)!;
  final contentResource = await imageCache.acquire(
    context,
    spec.content,
    contentImage,
    stats,
    mipmapped: mipmapImages,
  );
  textureLeases.add(contentResource);
  final maskResource = await imageCache.acquire(
    context,
    spec.mask,
    maskImage,
    stats,
    mipmapped: mipmapImages,
  );
  textureLeases.add(maskResource);
  final vertices = _imageVertices(spec.content.transform);
  final contentAlpha = (spec.content.alpha * spec.groupAlpha).clamp(0.0, 1.0);
  final contentTint = spec.content.isStencil
      ? _premul(spec.content.stencilColor, contentAlpha)
      : <double>[0, 0, 0, contentAlpha];
  final maskTint = spec.mask.isStencil
      ? _premul(spec.mask.stencilColor, spec.mask.alpha)
      : <double>[0, 0, 0, spec.mask.alpha.clamp(0.0, 1.0)];
  final info = _softMaskInfo(
    context,
    maskTransform: spec.mask.transform,
    contentTint: contentTint,
    maskTint: maskTint,
    contentStencil: spec.content.isStencil,
    maskStencil: spec.mask.isStencil,
    luminosity: spec.luminosity,
    backdropLuminance: spec.backdropLuminance,
    transferScale: spec.transferScale,
    transferOffset: spec.transferOffset,
    maskClip: spec.maskClip,
  );
  return _SoftMaskDraw(
    geometry.add(vertices.bytes, vertices.length ~/ 4),
    contentResource.texture,
    maskResource.texture,
    info,
  );
}

_GpuDraw? _compileGroupFill(_GpuGeometryArena geometry, _GroupFillSpec spec) {
  final content = spec.content;
  final subpaths = flattenPath(
    content.path,
    PdfMatrix.identity,
    tolerance: 0.01,
  );
  return _stencilDraw(
    geometry,
    subpaths,
    content.color,
    (content.alpha * spec.groupAlpha).clamp(0.0, 1.0),
    content.rule,
    false,
  );
}

_GpuDraw? _compileGroupStroke(
        _GpuGeometryArena geometry, _GroupStrokeSpec spec) =>
    _compileStroke(
      geometry,
      spec.content,
      alphaScale: spec.groupAlpha,
    );

_GpuDraw? _compileGroupPaint(_GpuGeometryArena geometry, _GroupPaintSpec spec) {
  final draws = <_GpuDraw>[];
  for (final command in spec.commands) {
    final draw = switch (command) {
      PdfFillPathCommand(
        :final path,
        :final color,
        :final rule,
        :final alpha,
      ) =>
        _stencilDraw(
          geometry,
          flattenPath(path, PdfMatrix.identity, tolerance: 0.01),
          color,
          alpha,
          rule,
          false,
        ),
      PdfStrokePathCommand() => _compileStroke(geometry, command),
      _ => null,
    };
    if (draw != null) draws.add(draw);
  }
  return draws.isEmpty ? null : _SequenceDraw(List.unmodifiable(draws));
}

Future<_GpuDraw> _compileSoftMaskFill(
    gpu.GpuContext context,
    _GpuGeometryArena geometry,
    PdfRetainedScene scene,
    _SoftMaskFillSpec spec,
    FlutterGpuTileBackendStats stats,
    _GpuImageCache imageCache,
    List<_GpuImageTexture> textureLeases,
    {required bool mipmapImages}) async {
  final maskImage = scene.imageFor(spec.mask)!;
  final maskResource = await imageCache.acquire(
    context,
    spec.mask,
    maskImage,
    stats,
    mipmapped: mipmapImages,
  );
  textureLeases.add(maskResource);
  final subpaths = flattenPath(
    spec.content.path,
    PdfMatrix.identity,
    tolerance: 0.01,
  );
  final stencil = _stencilGeometry(geometry, subpaths);
  if (stencil == null) throw StateError('empty soft-mask fill path');
  final bounds = stencil.$2;
  final cover = _imageVertices(PdfMatrix(
    bounds.right - bounds.left,
    0,
    0,
    bounds.top - bounds.bottom,
    bounds.left,
    bounds.bottom,
  ));
  return _SoftMaskFillDraw(
    stencil.$1,
    geometry.add(cover.bytes, cover.length ~/ 4),
    spec.content.rule,
    maskResource.texture,
    _softMaskInfo(
      context,
      maskTransform: spec.mask.transform,
      contentTint: _premul(spec.content.color, spec.content.alpha),
      maskTint: <double>[0, 0, 0, spec.mask.alpha.clamp(0.0, 1.0)],
      contentStencil: true,
      maskStencil: false,
      luminosity: spec.luminosity,
      backdropLuminance: spec.backdropLuminance,
      transferScale: spec.transferScale,
      transferOffset: spec.transferOffset,
      maskClip: spec.maskClip,
    ),
  );
}

_GpuDraw? _compileSoftMaskVectorFill(
    _GpuGeometryArena geometry, _SoftMaskVectorFillSpec spec) {
  final subpaths = flattenPath(
    spec.content.path,
    PdfMatrix.identity,
    tolerance: 0.01,
  );
  final stencil = _stencilGeometry(geometry, subpaths);
  if (stencil == null) return null;
  final pathBounds = stencil.$2;
  final bounds = _pdfIntersection(
    PdfRect(
      pathBounds.left,
      pathBounds.bottom,
      pathBounds.right,
      pathBounds.top,
    ),
    spec.contentClip,
  );
  if (bounds == null) return null;

  final xs = <double>{bounds.left, bounds.right};
  final ys = <double>{bounds.bottom, bounds.top};
  for (final fill in spec.maskFills) {
    final rect = _pdfIntersection(bounds, fill.rect);
    if (rect == null) continue;
    xs
      ..add(rect.left)
      ..add(rect.right);
    ys
      ..add(rect.bottom)
      ..add(rect.top);
  }
  final orderedX = xs.toList()..sort();
  final orderedY = ys.toList()..sort();
  final cells = (orderedX.length - 1) * (orderedY.length - 1);
  final cover = FloatBuilder(math.max(36, cells * 36));
  for (var yi = 0; yi + 1 < orderedY.length; yi++) {
    final bottom = orderedY[yi], top = orderedY[yi + 1];
    if (top <= bottom) continue;
    for (var xi = 0; xi + 1 < orderedX.length; xi++) {
      final left = orderedX[xi], right = orderedX[xi + 1];
      if (right <= left) continue;
      final mask = _vectorMaskValue(
        spec,
        (left + right) / 2,
        (bottom + top) / 2,
      );
      final color = _premul(
        spec.content.color,
        (spec.content.alpha * mask).clamp(0.0, 1.0),
      );
      for (final (x, y) in <(double, double)>[
        (left, bottom),
        (right, bottom),
        (right, top),
        (left, bottom),
        (right, top),
        (left, top),
      ]) {
        cover.add6(x, y, color[0], color[1], color[2], color[3]);
      }
    }
  }
  return _StencilDraw(
    stencil.$1,
    geometry.add(cover.bytes, cover.length ~/ 6),
    spec.content.rule,
    false,
  );
}

double _vectorMaskValue(_SoftMaskVectorFillSpec spec, double x, double y) {
  var alpha = spec.luminosity ? 1.0 : 0.0;
  var red = spec.luminosity ? spec.backdropLuminance : 0.0;
  var green = red, blue = red;
  for (final fill in spec.maskFills) {
    final rect = fill.rect;
    if (x < rect.left || x > rect.right || y < rect.bottom || y > rect.top) {
      continue;
    }
    final sourceAlpha = fill.alpha.clamp(0.0, 1.0);
    final inverse = 1 - sourceAlpha;
    red = fill.color.red * sourceAlpha + red * inverse;
    green = fill.color.green * sourceAlpha + green * inverse;
    blue = fill.color.blue * sourceAlpha + blue * inverse;
    alpha = sourceAlpha + alpha * inverse;
  }
  final value =
      spec.luminosity ? 0.2126 * red + 0.7152 * green + 0.0722 * blue : alpha;
  return (value * spec.transferScale + spec.transferOffset).clamp(0.0, 1.0);
}

gpu.BufferView _softMaskInfo(
  gpu.GpuContext context, {
  required PdfMatrix maskTransform,
  required List<double> contentTint,
  required List<double> maskTint,
  required bool contentStencil,
  required bool maskStencil,
  required bool luminosity,
  required double backdropLuminance,
  required double transferScale,
  required double transferOffset,
  PdfRect? maskClip,
}) {
  final inverse = maskTransform.inverted();
  if (inverse == null) throw StateError('singular soft-mask image transform');
  final clip = maskClip ??
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
      contentStencil ? 1 : 0,
      maskStencil ? 1 : 0,
      luminosity ? 1 : 0,
      luminosity ? backdropLuminance : 0,
    ])
    ..setRange(28, 32, <double>[
      transferScale,
      transferOffset,
      0,
      0,
    ])
    ..setRange(32, 36, <double>[
      clip.left,
      clip.bottom,
      clip.right,
      clip.top,
    ]);
  return gpu.BufferView(
    context.createDeviceBufferWithCopy(ByteData.sublistView(values)),
    offsetInBytes: 0,
    lengthInBytes: values.lengthInBytes,
  );
}

class _GpuImageTexture {
  _GpuImageTexture(this.texture, this.width, this.height, this.bytes);
  final gpu.Texture texture;
  final int width;
  final int height;
  final int bytes;
  int leases = 0;
  bool cacheable = true;
}

enum _GpuTexturePlane { deferredSoftMask }

class _GpuTextureKey {
  const _GpuTextureKey(
    this.context,
    this.content,
    this.width,
    this.height,
    this.mipmapped,
  );
  final gpu.GpuContext context;
  final Object content;
  final int width;
  final int height;
  final bool mipmapped;

  @override
  bool operator ==(Object other) =>
      other is _GpuTextureKey &&
      identical(other.context, context) &&
      other.content == content &&
      other.width == width &&
      other.height == height &&
      other.mipmapped == mipmapped;

  @override
  int get hashCode => Object.hash(
        identityHashCode(context),
        content,
        width,
        height,
        mipmapped,
      );
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
          {required bool mipmapped}) =>
      acquireSurface(
        context,
        pdfImageContentKey(request),
        image,
        stats,
        decoded: request.decoded,
        mipmapped: mipmapped,
      );

  Future<_GpuImageTexture> acquireSurface(gpu.GpuContext context,
      Object content, ui.Image image, FlutterGpuTileBackendStats stats,
      {PdfDecodedPixels? decoded, required bool mipmapped}) async {
    final key = _GpuTextureKey(
      context,
      content,
      image.width,
      image.height,
      mipmapped,
    );
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
    final mipLevelCount =
        mipmapped ? gpu.Texture.fullMipCount(image.width, image.height) : 1;
    final bytes = _textureBytes(image.width, image.height, mipLevelCount);
    if (maxBytes > 0 && !_makeRoom(bytes, stats)) {
      stats.textureBudgetFallbacks++;
      throw StateError('GPU texture budget exceeded: need $bytes bytes, '
          'have $_bytes/$maxBytes with active scenes pinned');
    }
    final uploaded = await _uploadImageTexture(
      context,
      image,
      stats,
      decoded: decoded,
      mipLevelCount: mipLevelCount,
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
    {PdfDecodedPixels? decoded, required int mipLevelCount}) async {
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
    mipLevelCount: mipLevelCount,
  );
  texture.overwrite(bytes);
  var width = image.width;
  var height = image.height;
  var level =
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  for (var mip = 1; mip < mipLevelCount; mip++) {
    level = _downsampleRgba(level, width, height);
    width = math.max(1, width ~/ 2);
    height = math.max(1, height ~/ 2);
    texture.overwrite(ByteData.sublistView(level), mipLevel: mip);
  }
  stats.texturesUploaded++;
  return _GpuImageTexture(
    texture,
    image.width,
    image.height,
    _textureBytes(image.width, image.height, mipLevelCount),
  );
}

int _textureBytes(int width, int height, int mipLevelCount) {
  var bytes = 0;
  for (var mip = 0; mip < mipLevelCount; mip++) {
    bytes += width * height * 4;
    width = math.max(1, width ~/ 2);
    height = math.max(1, height ~/ 2);
  }
  return bytes;
}

Uint8List _downsampleRgba(Uint8List source, int width, int height) {
  final nextWidth = math.max(1, width ~/ 2);
  final nextHeight = math.max(1, height ~/ 2);
  return downsamplePdfDecodedPixels(
    PdfDecodedPixels(source, width, height),
    nextWidth,
    nextHeight,
  ).rgba;
}

_GpuDraw? _compileStroke(
  _GpuGeometryArena geometry,
  PdfStrokePathCommand command, {
  double alphaScale = 1,
}) {
  final path = command.path;
  final color = command.color;
  final stroke = command.stroke;
  final alpha = (command.alpha * alphaScale).clamp(0.0, 1.0);
  var subpaths = flattenPath(path, PdfMatrix.identity, tolerance: 0.01);
  if (stroke.dashArray.any((value) => value > 0)) {
    subpaths = dashSubpaths(subpaths, stroke.dashArray, stroke.dashPhase);
  }
  if (stroke.width <= 0) {
    return alpha <= 0
        ? null
        : _HairlineDraw(
            List.unmodifiable(subpaths),
            color,
            stroke,
            alpha,
          );
  }
  final contours = StrokeContours();
  strokeToContours(
    subpaths,
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
  return _stencilDraw(geometry, rings, color, alpha, PdfFillRule.nonzero, true);
}

FutureOr<_GpuDraw?> _compileCommand(
    gpu.GpuContext context,
    _GpuGeometryArena geometry,
    PdfRetainedScene scene,
    PdfRenderCommand command,
    FlutterGpuTileBackendStats stats,
    _GpuImageCache imageCache,
    List<_GpuImageTexture> textureLeases,
    {required bool mipmapImages}) async {
  switch (command) {
    case PdfFillPathCommand(
        :final path,
        :final color,
        :final rule,
        :final alpha
      ):
      final subs = flattenPath(path, PdfMatrix.identity, tolerance: 0.01);
      return _stencilDraw(geometry, subs, color, alpha, rule, false);
    case PdfFillPathGradientCommand(
        :final path,
        :final rule,
        :final gradient,
        :final alpha,
      ):
      return _compileGradient(
        geometry,
        path,
        rule,
        gradient,
        alpha,
      );
    case PdfStrokePathCommand():
      return _compileStroke(geometry, command);
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
      final gradient = run.gradient;
      if (gradient != null) {
        return _compileGradientSubpaths(
          geometry,
          subs,
          PdfFillRule.nonzero,
          gradient,
          run.fillAlpha,
        );
      }
      return _stencilDraw(
          geometry, subs, run.color, run.fillAlpha, PdfFillRule.nonzero, false);
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
        mipmapImages: mipmapImages,
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
    {required bool mipmapImages}) async {
  final image = scene.imageFor(request)!;
  final maskImage = pdfGpuSoftMaskOf(image);
  final resource = await imageCache.acquire(
    context,
    request,
    image,
    stats,
    mipmapped: mipmapImages,
  );
  textureLeases.add(resource);
  final vertices = _imageVertices(request.transform);
  final tint = request.isStencil
      ? _premul(request.stencilColor, request.alpha)
      : <double>[0, 0, 0, request.alpha];
  if (maskImage != null) {
    final maskResource = await imageCache.acquireSurface(
      context,
      (pdfImageContentKey(request), _GpuTexturePlane.deferredSoftMask),
      maskImage,
      stats,
      mipmapped: mipmapImages,
    );
    textureLeases.add(maskResource);
    // Platform-codec `/SMask` companions are opaque grayscale surfaces. The
    // PDF alpha is their gray sample (Canvas applies red-to-alpha), so the
    // luminosity branch of the existing soft-mask shader is the exact match.
    return _SoftMaskDraw(
      geometry.add(vertices.bytes, 6),
      resource.texture,
      maskResource.texture,
      _softMaskInfo(
        context,
        maskTransform: request.transform,
        contentTint: tint,
        maskTint: const [0, 0, 0, 1],
        contentStencil: request.isStencil,
        maskStencil: false,
        luminosity: true,
        backdropLuminance: 0,
        transferScale: 1,
        transferOffset: 0,
      ),
    );
  }
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

_GradientDraw? _compileGradient(
  _GpuGeometryArena geometry,
  PdfPath path,
  PdfFillRule rule,
  PdfGradient gradient,
  double alpha,
) {
  if (alpha <= 0 || _gradientUnsupportedReason(gradient, alpha) != null) {
    return null;
  }
  final subpaths = flattenPath(path, PdfMatrix.identity, tolerance: 0.01);
  return _compileGradientSubpaths(
    geometry,
    subpaths,
    rule,
    gradient,
    alpha,
  );
}

_GradientDraw? _compileGradientSubpaths(
  _GpuGeometryArena geometry,
  List<FlatSubpath> subpaths,
  PdfFillRule rule,
  PdfGradient gradient,
  double alpha,
) {
  if (alpha <= 0) return null;
  if (gradient.isRadial) {
    return _compileRadialGradientSubpaths(
      geometry,
      subpaths,
      rule,
      gradient,
      alpha,
    );
  }
  final stencil = _stencilGeometry(geometry, subpaths);
  if (stencil == null) return null;
  final bounds = stencil.$2;
  final inverse = gradient.transform.inverted()!;
  final x0 = gradient.coords[0], y0 = gradient.coords[1];
  final dx = gradient.coords[2] - x0, dy = gradient.coords[3] - y0;
  final length2 = dx * dx + dy * dy;
  final nx = -dy, ny = dx;
  var minT = double.infinity, maxT = double.negativeInfinity;
  var minU = double.infinity, maxU = double.negativeInfinity;
  for (final (px, py) in <(double, double)>[
    (bounds.left, bounds.bottom),
    (bounds.right, bounds.bottom),
    (bounds.right, bounds.top),
    (bounds.left, bounds.top),
  ]) {
    final x = inverse.transformX(px, py), y = inverse.transformY(px, py);
    final gx = x - x0, gy = y - y0;
    final t = (gx * dx + gy * dy) / length2;
    final u = (gx * nx + gy * ny) / length2;
    minT = math.min(minT, t);
    maxT = math.max(maxT, t);
    minU = math.min(minU, u);
    maxU = math.max(maxU, u);
  }
  if (![minT, maxT, minU, maxU].every((value) => value.isFinite) ||
      minT >= maxT ||
      minU >= maxU) {
    return null;
  }

  final cuts = <double>{minT, maxT};
  for (final stop in <double>[0, ...gradient.stops, 1]) {
    if (stop > minT && stop < maxT) cuts.add(stop);
  }
  final ordered = cuts.toList()..sort();
  final vertices = FloatBuilder(math.max(36, (ordered.length - 1) * 36));
  final commandAlpha = alpha.clamp(0.0, 1.0);

  List<double> colorAt(double t) {
    final sample = t.clamp(0.0, 1.0);
    var upper = 1;
    while (upper < gradient.stops.length && gradient.stops[upper] < sample) {
      upper++;
    }
    if (upper >= gradient.stops.length) {
      return _premul(gradient.colors.last, commandAlpha);
    }
    final lower = upper - 1;
    final lo = gradient.stops[lower], hi = gradient.stops[upper];
    final mix = hi <= lo ? 1.0 : ((sample - lo) / (hi - lo)).clamp(0.0, 1.0);
    final a = gradient.colors[lower], b = gradient.colors[upper];
    return _premul(
      PdfColor(
        a.red + (b.red - a.red) * mix,
        a.green + (b.green - a.green) * mix,
        a.blue + (b.blue - a.blue) * mix,
      ),
      commandAlpha,
    );
  }

  (double, double) point(double t, double u) {
    final x = x0 + dx * t + nx * u;
    final y = y0 + dy * t + ny * u;
    return (
      gradient.transform.transformX(x, y),
      gradient.transform.transformY(x, y),
    );
  }

  for (var i = 0; i + 1 < ordered.length; i++) {
    final a = ordered[i], b = ordered[i + 1];
    if (b - a <= 1e-12) continue;
    final outsideStart = b <= 0;
    final outsideEnd = a >= 1;
    final ca = outsideStart && !gradient.extendStart ||
            outsideEnd && !gradient.extendEnd
        ? const <double>[0, 0, 0, 0]
        : colorAt(a);
    final cb = outsideStart && !gradient.extendStart ||
            outsideEnd && !gradient.extendEnd
        ? const <double>[0, 0, 0, 0]
        : colorAt(b);
    final p00 = point(a, minU), p01 = point(a, maxU);
    final p10 = point(b, minU), p11 = point(b, maxU);
    for (final (point, color) in <((double, double), List<double>)>[
      (p00, ca),
      (p10, cb),
      (p11, cb),
      (p00, ca),
      (p11, cb),
      (p01, ca),
    ]) {
      vertices.add6(
        point.$1,
        point.$2,
        color[0],
        color[1],
        color[2],
        color[3],
      );
    }
  }
  if (vertices.isEmpty) return null;
  return _GradientDraw(
    stencil.$1,
    geometry.add(vertices.bytes, vertices.length ~/ 6),
    rule,
  );
}

_GradientDraw? _compileRadialGradientSubpaths(
  _GpuGeometryArena geometry,
  List<FlatSubpath> subpaths,
  PdfFillRule rule,
  PdfGradient gradient,
  double alpha,
) {
  final stencil = _stencilGeometry(geometry, subpaths);
  if (stencil == null) return null;
  final bounds = stencil.$2;
  final inverse = gradient.transform.inverted()!;
  final x0 = gradient.coords[0], y0 = gradient.coords[1];
  final r0 = gradient.coords[2];
  final x1 = gradient.coords[3], y1 = gradient.coords[4];
  final r1 = gradient.coords[5];
  final dx = x1 - x0, dy = y1 - y0, dr = r1 - r0;

  // Bound the extended, growing side by the fill path. The extra radii and
  // centre travel are deliberately conservative; the path stencil discards
  // the excess, while a too-small outer ring would leave a clipped corner
  // transparent when /Extend asks for the terminal colour.
  var reach = (math.sqrt(dx * dx + dy * dy) + r0 + r1) * 4 + 1;
  for (final (px, py) in <(double, double)>[
    (bounds.left, bounds.bottom),
    (bounds.right, bounds.bottom),
    (bounds.right, bounds.top),
    (bounds.left, bounds.top),
  ]) {
    final x = inverse.transformX(px, py), y = inverse.transformY(px, py);
    final d0 = math.sqrt((x - x0) * (x - x0) + (y - y0) * (y - y0));
    final d1 = math.sqrt((x - x1) * (x - x1) + (y - y1) * (y - y1));
    reach = math.max(reach, math.max(d0, d1) + r0 + r1);
  }
  if (!reach.isFinite) return null;

  final double tLo;
  final double tHi;
  if (dr > 0) {
    tLo = gradient.extendStart ? -r0 / dr : 0;
    tHi = gradient.extendEnd ? (reach - r0) / dr : 1;
  } else {
    tLo = gradient.extendStart ? (reach - r0) / dr : 0;
    tHi = gradient.extendEnd ? -r0 / dr : 1;
  }
  if (!tLo.isFinite || !tHi.isFinite || tLo >= tHi) return null;

  final cuts = <double>{tLo, tHi};
  for (final stop in <double>[0, ...gradient.stops, 1]) {
    if (stop > tLo && stop < tHi) cuts.add(stop);
  }
  final ordered = cuts.toList()..sort();
  const angular = 96;
  final vertices =
      FloatBuilder(math.max(angular * 36, (ordered.length - 1) * angular * 36));
  final commandAlpha = alpha.clamp(0.0, 1.0);

  List<double> colorAt(double t) {
    final sample = t.clamp(0.0, 1.0);
    var upper = 1;
    while (upper < gradient.stops.length && gradient.stops[upper] < sample) {
      upper++;
    }
    if (upper >= gradient.stops.length) {
      return _premul(gradient.colors.last, commandAlpha);
    }
    final lower = upper - 1;
    final lo = gradient.stops[lower], hi = gradient.stops[upper];
    final mix = ((sample - lo) / (hi - lo)).clamp(0.0, 1.0);
    final a = gradient.colors[lower], b = gradient.colors[upper];
    return _premul(
      PdfColor(
        a.red + (b.red - a.red) * mix,
        a.green + (b.green - a.green) * mix,
        a.blue + (b.blue - a.blue) * mix,
      ),
      commandAlpha,
    );
  }

  (double, double) point(double t, int step) {
    final angle = 2 * math.pi * step / angular;
    final radius = math.max(0.0, r0 + dr * t);
    final x = x0 + dx * t + radius * math.cos(angle);
    final y = y0 + dy * t + radius * math.sin(angle);
    return (
      gradient.transform.transformX(x, y),
      gradient.transform.transformY(x, y),
    );
  }

  for (var i = 0; i + 1 < ordered.length; i++) {
    final a = ordered[i], b = ordered[i + 1];
    if (b - a <= 1e-12) continue;
    final ca = colorAt(a), cb = colorAt(b);
    for (var j = 0; j < angular; j++) {
      final p00 = point(a, j), p01 = point(a, j + 1);
      final p10 = point(b, j), p11 = point(b, j + 1);
      for (final (point, color) in <((double, double), List<double>)>[
        (p00, ca),
        (p10, cb),
        (p11, cb),
        (p00, ca),
        (p11, cb),
        (p01, ca),
      ]) {
        vertices.add6(
          point.$1,
          point.$2,
          color[0],
          color[1],
          color[2],
          color[3],
        );
      }
    }
  }
  if (vertices.isEmpty) return null;
  return _GradientDraw(
    stencil.$1,
    geometry.add(vertices.bytes, vertices.length ~/ 6),
    rule,
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

class _SequenceDraw implements _GpuDraw {
  const _SequenceDraw(this.draws);
  final List<_GpuDraw> draws;

  @override
  void encode(_GpuEncoder encoder) {
    for (final draw in draws) {
      draw.encode(encoder);
    }
  }
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

/// A PDF zero-width stroke. Its source polyline is retained with the scene,
/// but its contour is expanded for the current tile LoD because the PDF
/// definition is one device pixel rather than a fixed page-space width.
class _HairlineDraw implements _GpuDraw {
  const _HairlineDraw(this.subpaths, this.color, this.stroke, this.alpha);

  final List<FlatSubpath> subpaths;
  final PdfColor color;
  final PdfStroke stroke;
  final double alpha;

  @override
  void encode(_GpuEncoder encoder) =>
      encoder.hairline(subpaths, color, stroke, alpha);
}

class _GradientDraw implements _GpuDraw {
  const _GradientDraw(this.fan, this.mesh, this.rule);

  final _GpuBuffer fan;
  final _GpuBuffer mesh;
  final PdfFillRule rule;

  @override
  void encode(_GpuEncoder encoder) => encoder.gradient(fan, mesh, rule);
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

class _SoftMaskFillDraw implements _GpuDraw {
  const _SoftMaskFillDraw(
      this.fan, this.cover, this.rule, this.maskTexture, this.info);
  final _GpuBuffer fan;
  final _GpuBuffer cover;
  final PdfFillRule rule;
  final gpu.Texture maskTexture;
  final gpu.BufferView info;

  @override
  void encode(_GpuEncoder encoder) =>
      encoder.softMaskFill(fan, cover, rule, maskTexture, info);
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
    required this.emplaceTransient,
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
  final gpu.BufferView Function(ByteData) emplaceTransient;

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
  gpu.ColorBlendEquation _paintBlend = _srcOver;

  static final _srcOver = gpu.ColorBlendEquation(
    sourceColorBlendFactor: gpu.BlendFactor.one,
    destinationColorBlendFactor: gpu.BlendFactor.oneMinusSourceAlpha,
    sourceAlphaBlendFactor: gpu.BlendFactor.one,
    destinationAlphaBlendFactor: gpu.BlendFactor.oneMinusSourceAlpha,
  );
  // The page paper makes the destination beneath every supported primitive
  // opaque. Under that invariant PDF Multiply and Screen each reduce to one
  // exact fixed-function equation, with no destination-texture readback.
  static final _multiply = gpu.ColorBlendEquation(
    sourceColorBlendFactor: gpu.BlendFactor.destinationColor,
    destinationColorBlendFactor: gpu.BlendFactor.oneMinusSourceAlpha,
    sourceAlphaBlendFactor: gpu.BlendFactor.one,
    destinationAlphaBlendFactor: gpu.BlendFactor.oneMinusSourceAlpha,
  );
  static final _screen = gpu.ColorBlendEquation(
    sourceColorBlendFactor: gpu.BlendFactor.oneMinusDestinationColor,
    destinationColorBlendFactor: gpu.BlendFactor.one,
    sourceAlphaBlendFactor: gpu.BlendFactor.one,
    destinationAlphaBlendFactor: gpu.BlendFactor.oneMinusSourceAlpha,
  );
  static final _noWrite = gpu.ColorBlendEquation(
    sourceColorBlendFactor: gpu.BlendFactor.zero,
    destinationColorBlendFactor: gpu.BlendFactor.one,
    sourceAlphaBlendFactor: gpu.BlendFactor.zero,
    destinationAlphaBlendFactor: gpu.BlendFactor.one,
  );

  void setBlendMode(PdfBlendMode mode) {
    _paintBlend = switch (mode) {
      PdfBlendMode.multiply => _multiply,
      PdfBlendMode.screen => _screen,
      _ => _srcOver,
    };
  }

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
      ..setColorBlendEquation(_paintBlend)
      ..bindPipeline(pipelines.solid)
      ..bindUniform(pipelines.solidTransform, transform);
    _drawBuffer(vertices);
  }

  void stencil(_GpuBuffer fan, _GpuBuffer cover,
      {required PdfFillRule rule, required bool union}) {
    _accumulateStencil(fan,
        rule: rule, union: union, requiredClipBit: _activeClipBit);
    _paintStencilCover(cover.view, cover.vertices);
  }

  void hairline(List<FlatSubpath> subpaths, PdfColor color, PdfStroke stroke,
      double alpha) {
    final contours = StrokeContours();
    strokeToContours(
      subpaths,
      width: 1 / _pageDeviceScale(pageToRaster, pixelRatio),
      cap: stroke.cap,
      join: stroke.join,
      miterLimit: stroke.miterLimit,
      out: contours,
    );
    final rings = <FlatSubpath>[
      for (var i = 0; i < contours.ringCount; i++)
        FlatSubpath(
          Float64List.sublistView(
            contours.points.view,
            contours.ringStart(i),
            contours.ringEnd(i),
          ),
          closed: true,
        ),
    ];
    final bounds = FlatBounds.of(rings);
    if (bounds == null) return;
    final fan = FloatBuilder(1024);
    for (final sub in rings) {
      final points = sub.points;
      final count = points.length ~/ 2;
      for (var i = 1; i + 1 < count; i++) {
        fan
          ..add2(points[0], points[1])
          ..add2(points[2 * i], points[2 * i + 1])
          ..add2(points[2 * i + 2], points[2 * i + 3]);
      }
    }
    if (fan.isEmpty) return;
    final rgba = _premul(color, alpha);
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
    _accumulateStencilView(
      emplaceTransient(fan.bytes),
      fan.length ~/ 2,
      rule: PdfFillRule.nonzero,
      union: true,
      requiredClipBit: _activeClipBit,
    );
    _paintStencilCover(emplaceTransient(cover.bytes), 6);
  }

  void _paintStencilCover(gpu.BufferView cover, int vertices) {
    pass
      ..setStencilReference(0)
      ..setColorBlendEquation(_paintBlend)
      ..setStencilConfig(gpu.StencilConfig(
        compareFunction: gpu.CompareFunction.notEqual,
        depthStencilPassOperation: gpu.StencilOperation.zero,
        stencilFailureOperation: gpu.StencilOperation.keep,
        readMask: _pathMask,
        writeMask: _pathMask,
      ))
      ..bindPipeline(pipelines.solid)
      ..bindUniform(pipelines.solidTransform, transform);
    _drawView(cover, vertices);
  }

  void gradient(_GpuBuffer fan, _GpuBuffer mesh, PdfFillRule rule) {
    _accumulateStencil(
      fan,
      rule: rule,
      union: false,
      requiredClipBit: _activeClipBit,
    );
    pass
      ..setStencilReference(0)
      ..setColorBlendEquation(_paintBlend)
      ..setStencilConfig(gpu.StencilConfig(
        compareFunction: gpu.CompareFunction.notEqual,
        depthStencilPassOperation: gpu.StencilOperation.zero,
        stencilFailureOperation: gpu.StencilOperation.keep,
        readMask: _pathMask,
        writeMask: _pathMask,
      ))
      ..bindPipeline(pipelines.solid)
      ..bindUniform(pipelines.solidTransform, transform);
    _drawBuffer(mesh);
    // The gradient mesh conservatively covers the path bounds, but clearing
    // the scratch bits explicitly keeps a malformed transform or degenerate
    // interval from leaking winding state into the next draw.
    _clearStencil(_pathMask);
  }

  void _accumulateStencil(
    _GpuBuffer fan, {
    required PdfFillRule rule,
    required bool union,
    required int requiredClipBit,
  }) =>
      _accumulateStencilView(
        fan.view,
        fan.vertices,
        rule: rule,
        union: union,
        requiredClipBit: requiredClipBit,
      );

  void _accumulateStencilView(
    gpu.BufferView fan,
    int vertices, {
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
    _drawView(fan, vertices);
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
      ..setColorBlendEquation(_paintBlend)
      ..bindPipeline(pipelines.texture)
      ..bindUniform(pipelines.textureTransform, transform)
      ..bindUniform(pipelines.textureInfo, info)
      ..bindTexture(
        pipelines.textureSampler,
        texture,
        sampler: gpu.SamplerOptions(
          minFilter: gpu.MinMagFilter.linear,
          magFilter: gpu.MinMagFilter.linear,
          mipFilter: gpu.MipFilter.linear,
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
      mipFilter: gpu.MipFilter.linear,
    );
    pass
      ..setColorBlendEquation(_paintBlend)
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

  void softMaskFill(_GpuBuffer fan, _GpuBuffer cover, PdfFillRule rule,
      gpu.Texture maskTexture, gpu.BufferView info) {
    _accumulateStencil(
      fan,
      rule: rule,
      union: false,
      requiredClipBit: _activeClipBit,
    );
    final sampler = gpu.SamplerOptions(
      minFilter: gpu.MinMagFilter.linear,
      magFilter: gpu.MinMagFilter.linear,
      mipFilter: gpu.MipFilter.linear,
    );
    pass
      ..setStencilReference(0)
      ..setColorBlendEquation(_paintBlend)
      ..setStencilConfig(gpu.StencilConfig(
        compareFunction: gpu.CompareFunction.notEqual,
        depthStencilPassOperation: gpu.StencilOperation.zero,
        stencilFailureOperation: gpu.StencilOperation.keep,
        readMask: _pathMask,
        writeMask: _pathMask,
      ))
      ..bindPipeline(pipelines.softMask)
      ..bindUniform(pipelines.softMaskTransform, transform)
      ..bindUniform(pipelines.softMaskInfo, info)
      // The normal grayscale mask texture has opaque alpha. Binding it as the
      // content sample too lets contentStencil supply the solid fill color,
      // while the second lookup still evaluates the PDF mask luminance/alpha.
      ..bindTexture(pipelines.softMaskContentSampler, maskTexture,
          sampler: sampler)
      ..bindTexture(pipelines.softMaskMaskSampler, maskTexture,
          sampler: sampler);
    _drawBuffer(cover);
    pass.clearBindings();
    _clearStencil(_pathMask);
  }

  // flutter_gpu is experimental. Flutter 3.47 split vertex count out of
  // bindVertexBuffer and into draw; 3.44 uses the original pair. Keep this
  // package usable across both stable SDKs without exposing that churn to
  // callers. The one-time dynamic probe is cached for every render pass.
  void _drawBuffer(_GpuBuffer buffer) {
    _drawView(buffer.view, buffer.vertices);
  }

  void _drawView(gpu.BufferView view, int vertices) {
    final dynamic dynamicPass = pass;
    if (_separateVertexCountApi == true) {
      dynamicPass.bindVertexBuffer(view);
      dynamicPass.draw(vertices);
      return;
    }
    if (_separateVertexCountApi == false) {
      dynamicPass.bindVertexBuffer(view, vertices);
      dynamicPass.draw();
      return;
    }
    try {
      dynamicPass.bindVertexBuffer(view);
      _separateVertexCountApi = true;
      dynamicPass.draw(vertices);
    } on NoSuchMethodError {
      _separateVertexCountApi = false;
      dynamicPass.bindVertexBuffer(view, vertices);
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
        destinationBlend = context.createRenderPipeline(
            library['PdfTileDestinationBlendVertex']!,
            library['PdfTileDestinationBlendFragment']!),
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
            library['PdfTileSoftMaskFragment']!.getUniformSlot('mask_tex'),
        destinationBlendInfo = library['PdfTileDestinationBlendFragment']!
            .getUniformSlot('BlendInfo'),
        destinationBlendDestination =
            library['PdfTileDestinationBlendFragment']!
                .getUniformSlot('destination_tex'),
        destinationBlendSource = library['PdfTileDestinationBlendFragment']!
            .getUniformSlot('source_tex');

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

  final Map<bool, Future<void>> _warmUps = {};

  Future<bool> warmUp(gpu.GpuContext context, {required bool useMsaa}) async {
    final existing = _warmUps[useMsaa];
    if (existing != null) {
      await existing;
      return false;
    }
    final future = _submitWarmUp(context, useMsaa: useMsaa);
    _warmUps[useMsaa] = future;
    try {
      await future;
      return true;
    } catch (_) {
      if (identical(_warmUps[useMsaa], future)) _warmUps.remove(useMsaa);
      rethrow;
    }
  }

  Future<void> _submitWarmUp(
    gpu.GpuContext context, {
    required bool useMsaa,
  }) {
    final resolve = context.createTexture(
      gpu.StorageMode.devicePrivate,
      1,
      1,
      format: context.defaultColorFormat,
    );
    final color = useMsaa
        ? context.createTexture(
            gpu.StorageMode.deviceTransient,
            1,
            1,
            format: context.defaultColorFormat,
            sampleCount: 4,
          )
        : resolve;
    final stencilTexture = context.createTexture(
      gpu.StorageMode.deviceTransient,
      1,
      1,
      format: context.defaultStencilFormat,
      sampleCount: useMsaa ? 4 : 1,
    );
    final sample = context.createTexture(
      gpu.StorageMode.hostVisible,
      1,
      1,
      format: gpu.PixelFormat.r8g8b8a8UNormInt,
    );
    sample.overwrite(ByteData.sublistView(Uint8List.fromList(
      const [255, 255, 255, 255],
    )));

    final transient = context.createHostBuffer();
    final transform =
        transient.emplace(ByteData.sublistView(Float32List.fromList(
      const [
        1,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        1,
      ],
    )));
    final stencilVertices = transient.emplace(ByteData.sublistView(
      Float32List.fromList(const [-1, -1, 3, -1, -1, 3]),
    ));
    final solidVertices = transient.emplace(ByteData.sublistView(
      Float32List.fromList(const [
        -1,
        -1,
        1,
        1,
        1,
        1,
        3,
        -1,
        1,
        1,
        1,
        1,
        -1,
        3,
        1,
        1,
        1,
        1,
      ]),
    ));
    final textureVertices = transient.emplace(ByteData.sublistView(
      Float32List.fromList(const [
        -1,
        -1,
        0,
        0,
        3,
        -1,
        1,
        0,
        -1,
        3,
        0,
        1,
      ]),
    ));
    final textureInfo = transient.emplace(ByteData.sublistView(
      Float32List.fromList(const [1, 1, 1, 1, 0, 0, 0, 0]),
    ));
    final softMaskInfo = Float32List(36)
      ..setRange(0, 16, const [
        1,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        1,
      ])
      ..setRange(16, 20, const [1, 1, 1, 1])
      ..setRange(20, 24, const [1, 1, 1, 1])
      ..setRange(24, 28, const [0, 0, 0, 1])
      ..setRange(28, 32, const [1, 0, 0, 0])
      ..setRange(32, 36, const [-1, -1, 1, 1]);
    final softMaskUniform =
        transient.emplace(ByteData.sublistView(softMaskInfo));
    final destinationBlendUniform = transient.emplace(
      _destinationBlendInfo(PdfBlendMode.colorBurn),
    );

    final commandBuffer = context.createCommandBuffer();
    final pass = commandBuffer.createRenderPass(gpu.RenderTarget(
      colorAttachments: [
        gpu.ColorAttachment(
          texture: color,
          resolveTexture: useMsaa ? resolve : null,
          clearValue: vm.Vector4.zero(),
          storeAction: useMsaa
              ? gpu.StoreAction.multisampleResolve
              : gpu.StoreAction.store,
        ),
      ],
      depthStencilAttachment: gpu.DepthStencilAttachment(
        texture: stencilTexture,
        stencilClearValue: 0,
      ),
    ));
    pass
      ..setCullMode(gpu.CullMode.none)
      ..setWindingOrder(gpu.WindingOrder.counterClockwise)
      ..setPrimitiveType(gpu.PrimitiveType.triangle)
      ..setColorBlendEnable(true)
      ..setStencilReference(0)
      ..setColorBlendEquation(_GpuEncoder._noWrite)
      ..setStencilConfig(
          gpu.StencilConfig(
            compareFunction: gpu.CompareFunction.always,
            depthStencilPassOperation: gpu.StencilOperation.incrementWrap,
            readMask: 0,
            writeMask: _GpuEncoder._pathMask,
          ),
          targetFace: gpu.StencilFace.front)
      ..setStencilConfig(
          gpu.StencilConfig(
            compareFunction: gpu.CompareFunction.always,
            depthStencilPassOperation: gpu.StencilOperation.decrementWrap,
            readMask: 0,
            writeMask: _GpuEncoder._pathMask,
          ),
          targetFace: gpu.StencilFace.back)
      ..bindPipeline(stencil)
      ..bindUniform(stencilTransform, transform);
    _warmUpDraw(pass, stencilVertices, 3);
    pass
      ..setStencilConfig(gpu.StencilConfig(
        compareFunction: gpu.CompareFunction.notEqual,
        depthStencilPassOperation: gpu.StencilOperation.zero,
        readMask: _GpuEncoder._pathMask,
        writeMask: _GpuEncoder._pathMask,
      ))
      ..bindPipeline(solid)
      ..bindUniform(solidTransform, transform)
      ..setColorBlendEquation(_GpuEncoder._srcOver);
    _warmUpDraw(pass, solidVertices, 3);
    pass
      ..setColorBlendEquation(_GpuEncoder._srcOver)
      ..setStencilConfig(gpu.StencilConfig(
        compareFunction: gpu.CompareFunction.always,
        depthStencilPassOperation: gpu.StencilOperation.keep,
        readMask: 0,
        writeMask: 0,
      ));
    _warmUpDraw(pass, solidVertices, 3);
    pass
      ..bindPipeline(texture)
      ..bindUniform(textureTransform, transform)
      ..bindUniform(this.textureInfo, textureInfo)
      ..bindTexture(textureSampler, sample);
    _warmUpDraw(pass, textureVertices, 3);
    pass
      ..clearBindings()
      ..bindPipeline(softMask)
      ..bindUniform(softMaskTransform, transform)
      ..bindUniform(this.softMaskInfo, softMaskUniform)
      ..bindTexture(softMaskContentSampler, sample)
      ..bindTexture(softMaskMaskSampler, sample);
    _warmUpDraw(pass, textureVertices, 3);
    pass
      ..clearBindings()
      ..bindPipeline(destinationBlend)
      ..bindUniform(destinationBlendInfo, destinationBlendUniform)
      ..bindTexture(destinationBlendDestination, sample)
      ..bindTexture(destinationBlendSource, sample);
    _warmUpDraw(pass, textureVertices, 3);
    pass.clearBindings();

    final completer = Completer<void>();
    // Keep every command-buffer resource strongly reachable until Impeller's
    // completion fence fires. The callback itself is the lifetime owner.
    final resources = <Object>[
      resolve,
      color,
      stencilTexture,
      sample,
      transient,
      commandBuffer,
      pass,
    ];
    try {
      commandBuffer.submit(completionCallback: (success) {
        if (resources.isEmpty) return;
        if (success) {
          completer.complete();
        } else {
          completer.completeError(StateError('GPU pipeline warm-up failed'));
        }
      });
    } catch (error, stack) {
      completer.completeError(error, stack);
    }
    return completer.future;
  }

  static void _warmUpDraw(
    gpu.RenderPass pass,
    gpu.BufferView vertices,
    int count,
  ) {
    final dynamic dynamicPass = pass;
    try {
      dynamicPass.bindVertexBuffer(vertices);
      dynamicPass.draw(count);
    } on NoSuchMethodError {
      dynamicPass.bindVertexBuffer(vertices, count);
      dynamicPass.draw();
    }
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
  final gpu.RenderPipeline destinationBlend;
  final gpu.UniformSlot stencilTransform;
  final gpu.UniformSlot solidTransform;
  final gpu.UniformSlot textureTransform;
  final gpu.UniformSlot textureInfo;
  final gpu.UniformSlot textureSampler;
  final gpu.UniformSlot softMaskTransform;
  final gpu.UniformSlot softMaskInfo;
  final gpu.UniformSlot softMaskContentSampler;
  final gpu.UniformSlot softMaskMaskSampler;
  final gpu.UniformSlot destinationBlendInfo;
  final gpu.UniformSlot destinationBlendDestination;
  final gpu.UniformSlot destinationBlendSource;
}
