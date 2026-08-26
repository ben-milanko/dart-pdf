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
import 'system_text_outliner_native.dart';
import 'text_outliner.dart';

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
/// The exact subset includes retained soft masks, bounded transparency and
/// knockout groups, every PDF blend mode through destination-sampling passes,
/// and decoded images whose `/SMask` stays as a companion GPU surface.
/// Ordinary PDF clip paths remain exact stencil masks (with rectangular clips
/// additionally using the hardware scissor). Unsupported transparency forms,
/// complex clips *inside* special soft-mask shortcuts, non-nested radial
/// gradients, unresolved substituted text, unsafe overprint, or missing image
/// pixels reject the whole scene. Zero-width PDF hairlines are expanded at
/// tile submission time so they remain exactly one device pixel at every LoD.
/// dart_pdf_editor then permanently uses its Canvas session for that scene.
class FlutterGpuTileRasterBackend extends PdfTileRasterBackend
    implements PdfTileRasterRetryBackend {
  FlutterGpuTileRasterBackend({
    this.msaa = true,
    this.allowOverprintApproximation = false,
    this.overprintRetryMaxDimension = 512,
    this.maxTextureBytes = 256 << 20,
    this.maxGeometryBytes = 256 << 20,
    this.enableProactiveWarmUp,
    this.analyticText = true,
    FlutterGpuTextOutliner? textOutliner,
    this.systemTextOutlines = false,
    FlutterGpuTileBackendStats? stats,
  })  : assert(overprintRetryMaxDimension == null ||
            overprintRetryMaxDimension > 0),
        stats = stats ?? FlutterGpuTileBackendStats(),
        textOutliner = textOutliner ??
            (systemTextOutlines
                ? FlutterGpuSystemTextOutliner.tryCreate()
                : null),
        _imageCache = _GpuImageCache(maxTextureBytes),
        _geometryPool = _GpuGeometryPool(maxGeometryBytes);

  /// Enables 4x MSAA on the final tile target where Impeller supports it.
  /// Intermediate transparency-group targets stay single-sample and are
  /// sampled through that final pass.
  final bool msaa;

  /// Allows non-black overprint paints to use source-over.
  ///
  /// False by default because source-over does not preserve untouched process
  /// channels as PDF overprint requires. Keep this for controlled benchmarking
  /// only; ordinary clients get the exact Canvas fallback instead.
  final bool allowOverprintApproximation;

  /// Long-side colorant-grid size for one exact retry after the default scene
  /// is rejected specifically for unresolved non-black overprint.
  ///
  /// Null disables the retry. It is lazy—the ordinary 384-cell page walk and
  /// every already-accepted scene are unchanged—and a retry that remains
  /// unsupported is handed back to the viewer's exact Canvas fallback.
  final int? overprintRetryMaxDimension;

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
  /// Buffers are therefore pooled in power-of-two size classes from 64 KiB to
  /// the arena's 16 MiB chunk size, leased by compiled scenes, and reused only
  /// after the scene is disposed and every submitted command buffer has
  /// completed. A scene that cannot fit falls back to Canvas.
  final int maxGeometryBytes;

  /// Whether the viewer should prepare GPU pipelines and live scenes at idle.
  ///
  /// Null (the default) enables proactive work on desktop and leaves mobile
  /// on-demand. Mobile Impeller contexts can reserve substantial additional
  /// memory even for a page that later falls back to Canvas; validated hosts
  /// can opt in explicitly.
  final bool? enableProactiveWarmUp;

  /// Evaluates ordinary filled glyph outlines directly from a retained curve
  /// atlas instead of tessellating every glyph into page-space stencil fans.
  ///
  /// Unsupported glyphs and gradient or soft-masked text keep the exact
  /// stencil path. The atlas is independent of tile scale, so later LoD tiles
  /// reuse both its outline streams and the six-vertex glyph quads. Native
  /// substitution scenes with fewer than 32 outlined glyph placements keep
  /// the cheaper retained stencil path because atlas setup cannot amortize.
  final bool analyticText;

  /// Optional exact vector outlines for unembedded/substituted text.
  ///
  /// Null preserves the conservative Canvas fallback. Set
  /// `systemTextOutlines: true` to probe the native fonts Canvas normally
  /// selects, or pass a host outliner built from the exact registered bytes.
  final FlutterGpuTextOutliner? textOutliner;

  /// Whether the backend was asked to probe the current platform's native
  /// substitution faces when no explicit [textOutliner] was supplied.
  final bool systemTextOutlines;

  final FlutterGpuTileBackendStats stats;
  final _GpuImageCache _imageCache;
  final _GpuGeometryPool _geometryPool;
  // Contexts belong to Flutter views and can disappear when a native window
  // closes. Keep only weak membership so diagnostics do not turn every view
  // ever opened into a process-lifetime root.
  final Expando<bool> _seenContexts = Expando<bool>('pdf-gpu-context');
  gpu.GpuContext? _lastContext;
  String? _lastSessionRejection;

  // Flutter GPU does not expose its active Impeller backend directly. This
  // capability is documented as true on Metal/Vulkan and false on GLES. The
  // current GLES implementation can terminate the process while loading or
  // submitting this package's shader pipelines, which cannot be caught in
  // Dart. Decline it before creating a pipeline future so the exact Canvas
  // fallback remains available.
  static bool _supportsContext(gpu.GpuContext context) =>
      context.doesSupportFramebufferRenderMipmap;
  static const _unsupportedContextReason =
      'OpenGLES flutter_gpu contexts require Canvas fallback';

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

  /// Compiles the common tile pipelines with a one-pixel GPU submission.
  ///
  /// The driver otherwise compiles the stencil, solid, and texture pipelines
  /// on the first deep-zoom tile, which can leave the coarse page visible for
  /// hundreds of milliseconds. Page-specific glyph, soft-mask, and advanced-
  /// blend variants are compiled by the later scene warm-up instead of making
  /// every document pay for them. This is safe to call repeatedly: work is
  /// shared per Impeller context and MSAA mode, including between backend
  /// instances.
  @override
  Future<void> warmUp() async {
    final clock = Stopwatch()..start();
    stats.warmUpRequests++;
    try {
      final context = gpu.gpuContext;
      if (!_supportsContext(context)) {
        stats.warmUpCompletions++;
        PdfPerfLog.log(
          'tile gpu pipeline warm skipped reason=opengles-context',
        );
        return;
      }
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
      if (!_supportsContext(context)) {
        _lastSessionRejection = _unsupportedContextReason;
        stats.lastRejection = _unsupportedContextReason;
        stats.lastTileRoute = 'canvas-fallback';
        stats.sessionsRejected++;
        return null;
      }
      final outlinedCommands = textOutliner == null
          ? scene.commands
          : _outlineGpuTextCommands(scene.commands, textOutliner!);
      final usesHostOutlines = !identical(outlinedCommands, scene.commands);
      final commandBuild = _buildGpuCommands(outlinedCommands);
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
        analyticText: analyticText,
        analyticTextMinimumGlyphs:
            systemTextOutlines && usesHostOutlines ? 32 : 1,
      );
    } catch (error) {
      _lastSessionRejection = 'initialization failed: $error';
      stats.lastRejection = _lastSessionRejection;
      stats.lastTileRoute = 'canvas-fallback';
      stats.sessionsRejected++;
      return null;
    }
  }

  @override
  Future<PdfTileRasterSession?>? retrySession(PdfRetainedScene scene) {
    final maxDimension = overprintRetryMaxDimension;
    if (maxDimension == null ||
        _lastSessionRejection !=
            'non-black overprint requires Canvas fallback' ||
        !scene.canRerecordWithOverprint) {
      return null;
    }
    stats
      ..overprintRetryRequests += 1
      ..lastTileRoute = 'flutter_gpu-overprint-retry';
    return Future<PdfTileRasterSession?>.microtask(() async {
      final clock = Stopwatch()..start();
      PdfRetainedScene? retried;
      try {
        final retry = scene.rerecordWithOverprintMaxDimension(maxDimension);
        if (retry == null) {
          stats.overprintRetryFallbacks++;
          return null;
        }
        retried = await retry;
        final session = createSession(retried);
        if (session == null) {
          stats.overprintRetryFallbacks++;
          retried.dispose();
          return null;
        }
        stats.overprintRetrySuccesses++;
        return _RetriedSceneTileRasterSession(session, retried);
      } catch (error) {
        retried?.dispose();
        stats
          ..overprintRetryFallbacks += 1
          ..lastRejection = 'overprint retry failed: $error'
          ..lastTileRoute = 'canvas-fallback';
        return null;
      } finally {
        stats.overprintRetryMicros += clock.elapsedMicroseconds;
      }
    });
  }

  static String? _unsupportedReason(
      PdfRetainedScene scene,
      List<PdfRenderCommand> commands,
      List<_GpuUnit> units,
      bool allowOverprintApproximation) {
    final hasAdvancedBlend =
        units.any((unit) => !_isFixedFunctionBlendMode(unit.blendMode));
    if (hasAdvancedBlend &&
        units.any((unit) => unit.composite is _KnockoutSoftMaskFillSpec)) {
      return 'advanced blend with knockout soft mask';
    }
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
          case _SoftMaskStrokeSpec():
            if (scene.imageFor(composite.mask) == null) {
              return 'missing soft-mask image pixels';
            }
          case _SoftMaskVectorFillSpec():
            break;
          case _SoftMaskGradientFillSpec():
            break;
          case _SoftMaskGradientStrokeSpec():
            break;
          case _SoftMaskTextSpec():
            if (scene.imageFor(composite.mask) == null) {
              return 'missing soft-mask image pixels';
            }
            final reason = _unsupportedTextReason(composite.content.run);
            if (reason != null) return reason;
          case _SoftMaskGradientTextSpec():
            final reason = _unsupportedTextReason(composite.content.run);
            if (reason != null) return reason;
          case _SoftMaskGroupSpec():
            final reason = _unsupportedNestedSoftMaskReason(
              scene,
              composite.content,
            );
            if (reason != null) return reason;
          case _GroupFillSpec():
            break;
          case _GroupStrokeSpec():
            break;
          case _GroupTextSpec():
            final reason = _unsupportedTextReason(composite.content.run);
            if (reason != null) return reason;
          case _GroupPaintSpec():
            for (final command in composite.commands) {
              switch (command) {
                case PdfDrawTextCommand(:final run):
                  final reason = _unsupportedTextReason(run);
                  if (reason != null) return reason;
                case PdfDrawImageCommand(:final request):
                  if (scene.imageFor(request) == null &&
                      !scene.imageDecodingAttempted) {
                    return 'missing transparency-group image pixels';
                  }
                case PdfFillPathGradientCommand(:final gradient, :final alpha):
                  final reason = _gradientUnsupportedReason(gradient, alpha);
                  if (reason != null) return reason;
                default:
                  break;
              }
            }
            break;
          case _KnockoutSoftMaskFillSpec():
            break;
          case _FlattenSoftMaskSpec():
            break;
          case _FlattenGroupSpec():
            break;
          case _EmptyGroupSpec():
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
          if (image == null && !scene.imageDecodingAttempted) {
            return 'missing image pixels';
          }
        case PdfDrawTextCommand(:final run):
          if (run.invisible) continue;
          final reason = _unsupportedTextReason(run);
          if (reason != null) return reason;
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

  static String? _unsupportedNestedSoftMaskReason(
    PdfRetainedScene scene,
    _GpuCompositeSpec composite,
  ) {
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
      case _SoftMaskStrokeSpec():
        if (scene.imageFor(composite.mask) == null) {
          return 'missing soft-mask image pixels';
        }
      case _SoftMaskVectorFillSpec() ||
            _SoftMaskGradientFillSpec() ||
            _SoftMaskGradientStrokeSpec():
        break;
      case _SoftMaskTextSpec():
        if (scene.imageFor(composite.mask) == null) {
          return 'missing soft-mask image pixels';
        }
        return _unsupportedTextReason(composite.content.run);
      case _SoftMaskGradientTextSpec():
        return _unsupportedTextReason(composite.content.run);
      default:
        return 'unsupported nested soft-mask group';
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

  static bool _isFixedFunctionBlendMode(PdfBlendMode mode) =>
      mode == PdfBlendMode.normal ||
      mode == PdfBlendMode.multiply ||
      mode == PdfBlendMode.screen;

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
    this.minimumPositiveStrokeWidth,
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
  final double? minimumPositiveStrokeWidth;
  final _GpuCompositeSpec? composite;
}

/// A conservative page-space capsule for one positive-width, single-segment
/// stroke. It lets the advanced-blend scheduler prove that diagonal strokes
/// are disjoint even when their axis-aligned bounds overlap heavily.
class _StraightStrokeFootprint {
  const _StraightStrokeFootprint(
    this.x0,
    this.y0,
    this.x1,
    this.y1,
    this.radius,
  );

  final double x0;
  final double y0;
  final double x1;
  final double y1;
  final double radius;
}

_StraightStrokeFootprint? _straightStrokeFootprint(
    PdfStrokePathCommand command) {
  final width = command.stroke.width;
  if (!width.isFinite || width <= 0) return null;
  final subpaths = flattenPath(command.path, PdfMatrix.identity);
  if (subpaths.length != 1) return null;
  final subpath = subpaths.single;
  if (subpath.closed || subpath.pointCount != 2) return null;
  final points = subpath.points;
  if (!points.every((value) => value.isFinite)) return null;
  final halfWidth = width / 2;
  // A circle of sqrt(2) * halfWidth encloses a projecting-square cap.
  final radius = command.stroke.cap == 2 ? halfWidth * math.sqrt2 : halfWidth;
  return _StraightStrokeFootprint(
    points[0],
    points[1],
    points[2],
    points[3],
    radius,
  );
}

double _pointSegmentDistanceSquared(
  double px,
  double py,
  double x0,
  double y0,
  double x1,
  double y1,
) {
  final dx = x1 - x0, dy = y1 - y0;
  final lengthSquared = dx * dx + dy * dy;
  if (lengthSquared <= 1e-24) {
    final ex = px - x0, ey = py - y0;
    return ex * ex + ey * ey;
  }
  final t = (((px - x0) * dx + (py - y0) * dy) / lengthSquared).clamp(0.0, 1.0);
  final ex = px - (x0 + t * dx), ey = py - (y0 + t * dy);
  return ex * ex + ey * ey;
}

double _segmentDistanceSquared(
    _StraightStrokeFootprint a, _StraightStrokeFootprint b) {
  double cross(
          double ax, double ay, double bx, double by, double cx, double cy) =>
      (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
  final ab0 = cross(a.x0, a.y0, a.x1, a.y1, b.x0, b.y0);
  final ab1 = cross(a.x0, a.y0, a.x1, a.y1, b.x1, b.y1);
  final ba0 = cross(b.x0, b.y0, b.x1, b.y1, a.x0, a.y0);
  final ba1 = cross(b.x0, b.y0, b.x1, b.y1, a.x1, a.y1);
  if (((ab0 <= 0 && ab1 >= 0) || (ab0 >= 0 && ab1 <= 0)) &&
      ((ba0 <= 0 && ba1 >= 0) || (ba0 >= 0 && ba1 <= 0))) {
    return 0;
  }
  return math.min(
    math.min(
      _pointSegmentDistanceSquared(a.x0, a.y0, b.x0, b.y0, b.x1, b.y1),
      _pointSegmentDistanceSquared(a.x1, a.y1, b.x0, b.y0, b.x1, b.y1),
    ),
    math.min(
      _pointSegmentDistanceSquared(b.x0, b.y0, a.x0, a.y0, a.x1, a.y1),
      _pointSegmentDistanceSquared(b.x1, b.y1, a.x0, a.y0, a.x1, a.y1),
    ),
  );
}

bool _straightStrokesAreRasterDisjoint(
  _StraightStrokeFootprint a,
  _StraightStrokeFootprint b,
  double deviceScale,
) {
  // Two shapes cannot contribute samples to the same resolved pixel when the
  // page-space gap between them is wider than that pixel's diagonal. This is
  // the condition needed to blend their shared transparent source exactly
  // once; using the diagonal remains conservative for every MSAA pattern.
  final minimumDistance = a.radius + b.radius + math.sqrt2 / deviceScale;
  return _segmentDistanceSquared(a, b) > minimumDistance * minimumDistance;
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

  // A one-source soft-mask layer is transparent outside its content clip, so
  // constraining the resolved composite with the same stencil is equivalent
  // to clipping that source inside Canvas' temporary layer.
  List<_GpuPathClip> get contentPathClips => const [];
}

typedef _GpuPathClip = ({PdfPath path, PdfFillRule rule});

class _GroupFillSpec extends _GpuCompositeSpec {
  const _GroupFillSpec({
    required this.content,
    required this.groupAlpha,
    required this.contentClip,
    this.contentPathClips = const [],
  });

  final PdfFillPathCommand content;
  final double groupAlpha;
  @override
  final PdfRect? contentClip;
  @override
  final List<_GpuPathClip> contentPathClips;
}

class _GroupStrokeSpec extends _GpuCompositeSpec {
  const _GroupStrokeSpec({
    required this.content,
    required this.groupAlpha,
    required this.contentClip,
    this.contentPathClips = const [],
  });

  final PdfStrokePathCommand content;
  final double groupAlpha;
  @override
  final PdfRect? contentClip;
  @override
  final List<_GpuPathClip> contentPathClips;
}

class _GroupTextSpec extends _GpuCompositeSpec {
  const _GroupTextSpec({
    required this.content,
    required this.groupAlpha,
    required this.contentClip,
    this.contentPathClips = const [],
  });

  final PdfDrawTextCommand content;
  final double groupAlpha;
  @override
  final PdfRect? contentClip;
  @override
  final List<_GpuPathClip> contentPathClips;
}

class _GroupPaintSpec extends _GpuCompositeSpec {
  const _GroupPaintSpec({
    required this.commands,
    required this.paintClips,
    required this.paintBlends,
    required this.contentClip,
    this.contentPathClips = const [],
    this.paintAlphaScales = const {},
    this.groupAlpha = 1,
    this.offscreen = false,
    this.knockout = false,
    this.backdropColor,
  });

  final List<PdfRenderCommand> commands;
  final List<PdfRect?> paintClips;
  final List<PdfBlendMode> paintBlends;
  final Map<int, double> paintAlphaScales;
  final double groupAlpha;
  final bool offscreen;
  final bool knockout;
  final PdfColor? backdropColor;
  @override
  final PdfRect? contentClip;
  @override
  final List<_GpuPathClip> contentPathClips;
}

class _KnockoutSoftMaskFillSpec extends _GpuCompositeSpec {
  const _KnockoutSoftMaskFillSpec({
    required this.base,
    required this.baseClip,
    required this.masked,
    required this.groupAlpha,
  });

  final PdfFillPathCommand base;
  final PdfRect? baseClip;
  final _SoftMaskVectorFillSpec masked;
  final double groupAlpha;

  @override
  PdfRect? get contentClip => null;
}

class _FlattenSoftMaskSpec extends _GpuCompositeSpec {
  const _FlattenSoftMaskSpec(this.paints);

  final List<_FlattenSoftMaskPaint> paints;

  @override
  PdfRect? get contentClip => null;
}

class _FlattenSoftMaskPaint {
  const _FlattenSoftMaskPaint({
    required this.commandIndex,
    required this.endCommandIndex,
    required this.bounds,
    required this.clip,
    required this.blendMode,
    this.composite,
    this.pathClip,
  });

  final int commandIndex;
  final int endCommandIndex;
  final PdfRect bounds;
  final PdfRect clip;
  final PdfBlendMode blendMode;
  final _GpuCompositeSpec? composite;
  final PdfPath? pathClip;
}

class _FlattenGroupSpec extends _GpuCompositeSpec {
  const _FlattenGroupSpec(this.paints);

  final List<({int commandIndex, PdfRect? clip, List<_GpuPathClip> pathClips})>
      paints;

  @override
  PdfRect? get contentClip => null;
}

class _EmptyGroupSpec extends _GpuCompositeSpec {
  const _EmptyGroupSpec(this.bounds);

  final PdfRect bounds;

  @override
  PdfRect? get contentClip => null;
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
    this.contentPathClips = const [],
  });

  final PdfImageRequest content;
  final PdfImageRequest mask;
  final double groupAlpha;
  @override
  final PdfRect? contentClip;
  @override
  final List<_GpuPathClip> contentPathClips;
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
    this.contentPathClips = const [],
  });

  final PdfFillPathCommand content;
  final PdfImageRequest mask;
  @override
  final PdfRect? contentClip;
  @override
  final List<_GpuPathClip> contentPathClips;
  final PdfRect? maskClip;
  final bool luminosity;
  final double backdropLuminance;
  final double transferScale;
  final double transferOffset;
}

class _SoftMaskStrokeSpec extends _GpuCompositeSpec {
  const _SoftMaskStrokeSpec({
    required this.content,
    required this.mask,
    required this.contentClip,
    required this.maskClip,
    required this.luminosity,
    required this.backdropLuminance,
    required this.transferScale,
    required this.transferOffset,
    this.contentPathClips = const [],
  });

  final PdfStrokePathCommand content;
  final PdfImageRequest mask;
  @override
  final PdfRect? contentClip;
  @override
  final List<_GpuPathClip> contentPathClips;
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
    this.contentPathClips = const [],
  });

  final PdfFillPathCommand content;
  final List<_VectorMaskFill> maskFills;
  @override
  final PdfRect? contentClip;
  @override
  final List<_GpuPathClip> contentPathClips;
  final bool luminosity;
  final double backdropLuminance;
  final double transferScale;
  final double transferOffset;
}

class _SoftMaskGradientFillSpec extends _GpuCompositeSpec {
  const _SoftMaskGradientFillSpec({
    required this.content,
    required this.mask,
    required this.contentClip,
    required this.luminosity,
    this.contentPathClips = const [],
  });

  final PdfFillPathCommand content;
  final PdfFillPathGradientCommand mask;
  @override
  final PdfRect? contentClip;
  @override
  final List<_GpuPathClip> contentPathClips;
  final bool luminosity;
}

class _SoftMaskGradientStrokeSpec extends _GpuCompositeSpec {
  const _SoftMaskGradientStrokeSpec({
    required this.content,
    required this.mask,
    required this.contentClip,
    required this.luminosity,
    this.contentPathClips = const [],
  });

  final PdfStrokePathCommand content;
  final PdfFillPathGradientCommand mask;
  @override
  final PdfRect? contentClip;
  @override
  final List<_GpuPathClip> contentPathClips;
  final bool luminosity;
}

class _SoftMaskTextSpec extends _GpuCompositeSpec {
  const _SoftMaskTextSpec({
    required this.content,
    required this.mask,
    required this.contentClip,
    required this.maskClip,
    required this.luminosity,
    required this.backdropLuminance,
    required this.transferScale,
    required this.transferOffset,
    this.contentPathClips = const [],
  });

  final PdfDrawTextCommand content;
  final PdfImageRequest mask;
  @override
  final PdfRect? contentClip;
  @override
  final List<_GpuPathClip> contentPathClips;
  final PdfRect? maskClip;
  final bool luminosity;
  final double backdropLuminance;
  final double transferScale;
  final double transferOffset;
}

class _SoftMaskGradientTextSpec extends _GpuCompositeSpec {
  const _SoftMaskGradientTextSpec({
    required this.content,
    required this.mask,
    required this.contentClip,
    required this.luminosity,
    this.contentPathClips = const [],
  });

  final PdfDrawTextCommand content;
  final PdfFillPathGradientCommand mask;
  @override
  final PdfRect? contentClip;
  @override
  final List<_GpuPathClip> contentPathClips;
  final bool luminosity;
}

/// One already-masked source that must be composited through its enclosing
/// transparency-group alpha after the mask has resolved.
class _SoftMaskGroupSpec extends _GpuCompositeSpec {
  const _SoftMaskGroupSpec(this.content, this.groupAlpha);

  final _GpuCompositeSpec content;
  final double groupAlpha;

  @override
  PdfRect? get contentClip => content.contentClip;

  @override
  List<_GpuPathClip> get contentPathClips => content.contentPathClips;
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

/// Resolves host-supplied substitute outlines before tiled cells expand.
///
/// Keeping the rewrite above [_buildGpuCommands] means a repeated Type3/pattern
/// cell resolves each text run once, then [TranslatingPdfDevice] shares the
/// resulting glyph paths across every translated occurrence. Soft-mask tapes
/// are nested command lists and must follow the same rule.
List<PdfRenderCommand> _outlineGpuTextCommands(
  List<PdfRenderCommand> source,
  FlutterGpuTextOutliner outliner,
) {
  List<PdfRenderCommand>? rewritten;
  for (var i = 0; i < source.length; i++) {
    final command = source[i];
    final PdfRenderCommand replacement;
    switch (command) {
      case PdfDrawTextCommand(:final run) when run.glyphs == null:
        final outlined = _tryOutlineGpuText(outliner, run);
        replacement = outlined == null || identical(outlined, run)
            ? command
            : PdfDrawTextCommand(outlined);
      case PdfEndSoftMaskedCommand():
        final mask = _outlineGpuTextCommands(command.maskCommands, outliner);
        replacement = identical(mask, command.maskCommands)
            ? command
            : PdfEndSoftMaskedCommand(
                luminosity: command.luminosity,
                backdrop: command.backdrop,
                maskCommands: mask,
                backdropLuminance: command.backdropLuminance,
                transferScale: command.transferScale,
                transferOffset: command.transferOffset,
              );
      case PdfDrawTiledCellCommand():
        final cell = _outlineGpuTextCommands(command.cellCommands, outliner);
        replacement = identical(cell, command.cellCommands)
            ? command
            : PdfDrawTiledCellCommand(
                cell,
                command.originsX,
                command.originsY,
              );
      default:
        replacement = command;
    }
    if (!identical(replacement, command)) {
      rewritten ??= List<PdfRenderCommand>.of(source);
      rewritten[i] = replacement;
    }
  }
  return rewritten == null ? source : List.unmodifiable(rewritten);
}

PdfTextRun? _tryOutlineGpuText(
  FlutterGpuTextOutliner outliner,
  PdfTextRun run,
) {
  try {
    return outliner.outline(run);
  } on Object {
    // A host resolver must never turn the exact Canvas fallback into a scene
    // creation failure. Leaving the original run in place makes the ordinary
    // unsupported-text audit reject it conservatively.
    return null;
  }
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
  source = _dropInvisibleGroups(source);
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

/// Removes transparency groups whose alpha is zero or whose declared
/// device-space bounds have no area.
///
/// A form group is clipped to its BBox before any content paints. A collapsed
/// BBox therefore contributes no samples regardless of nested commands,
/// blend modes, masks, or overprint state; group alpha zero has the same
/// result after compositing. Dropping the balanced transcript is exact and
/// avoids rejecting an otherwise GPU-safe page for unreachable content.
List<PdfRenderCommand> _dropInvisibleGroups(List<PdfRenderCommand> commands) {
  List<PdfRenderCommand>? rewritten;
  for (var index = 0; index < commands.length; index++) {
    final command = commands[index];
    if (command case PdfBeginGroupCommand(:final alpha, :final bounds)
        when alpha <= 0 ||
            (bounds != null &&
                (bounds.right <= bounds.left || bounds.top <= bounds.bottom))) {
      var depth = 1;
      var end = index + 1;
      for (; end < commands.length && depth > 0; end++) {
        switch (commands[end]) {
          case PdfBeginGroupCommand():
            depth++;
          case PdfEndGroupCommand():
            depth--;
          default:
            break;
        }
      }
      if (depth == 0) {
        rewritten ??= List<PdfRenderCommand>.of(commands.take(index));
        index = end - 1;
        continue;
      }
    }
    rewritten?.add(command);
  }
  return rewritten == null ? commands : List.unmodifiable(rewritten);
}

double? _minimumPositiveStrokeWidth(
  List<PdfRenderCommand> commands,
  int start,
  int end,
) {
  double? minimum;
  for (var index = start; index <= end; index++) {
    final width = switch (commands[index]) {
      PdfStrokePathCommand(:final stroke) when stroke.width > 0 => stroke.width,
      PdfDrawTextCommand(:final run)
          when run.strokeColor != null && run.strokeWidth > 0 =>
        run.strokeWidth,
      _ => null,
    };
    if (width != null && (minimum == null || width < minimum)) {
      minimum = width;
    }
  }
  return minimum;
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
          final spec = parsed.$1!;
          if (spec is _FlattenSoftMaskSpec) {
            for (final paint in spec.paints) {
              var paintClip = _withGpuRectClip(capture.clip, paint.clip);
              final pathClip = paint.pathClip;
              if (pathClip != null) {
                paintClip = _pushGpuClip(
                  paintClip,
                  pathClip,
                  PdfFillRule.nonzero,
                );
              }
              units.add(_GpuUnit(
                commandIndex: paint.commandIndex,
                endCommandIndex: paint.endCommandIndex,
                bounds: _inflatePdf(paint.bounds, 2),
                clip: paintClip,
                blendMode: paint.blendMode,
                fillOverprint: false,
                strokeOverprint: false,
                darken: false,
                minimumPositiveStrokeWidth: _minimumPositiveStrokeWidth(
                  commands,
                  paint.commandIndex,
                  paint.endCommandIndex,
                ),
                composite: paint.composite,
              ));
            }
            final bounds = capture.bounds;
            if (bounds != null) {
              // Covers the outer Begin/End pair for the unsupported-command
              // audit. Its paints compile above in their original order;
              // this structural marker intentionally emits no draw.
              units.add(_GpuUnit(
                commandIndex: capture.start,
                endCommandIndex: i,
                bounds: _inflatePdf(bounds, 2),
                clip: capture.clip,
                blendMode: PdfBlendMode.normal,
                fillOverprint: false,
                strokeOverprint: false,
                darken: false,
                composite: spec,
              ));
            }
          } else if (spec is _FlattenGroupSpec) {
            for (final paint in spec.paints) {
              final paintCommand = commands[paint.commandIndex];
              var paintClip = _withGpuRectClip(capture.clip, paint.clip);
              for (final pathClip in paint.pathClips) {
                paintClip = _pushGpuClip(
                  paintClip,
                  pathClip.path,
                  pathClip.rule,
                );
              }
              final paintBounds = pdfRenderCommandBounds(paintCommand);
              final clipped = paintBounds == null || paintClip.empty
                  ? null
                  : paintClip.scissor == null
                      ? paintBounds
                      : _pdfIntersection(paintClip.scissor, paintBounds);
              if (clipped == null) continue;
              units.add(_GpuUnit(
                commandIndex: paint.commandIndex,
                endCommandIndex: paint.commandIndex,
                bounds: _inflatePdf(clipped, 2),
                clip: paintClip,
                blendMode: capture.blendMode,
                fillOverprint: false,
                strokeOverprint: false,
                darken: false,
                hairline: paintCommand is PdfStrokePathCommand &&
                    paintCommand.stroke.width <= 0,
                minimumPositiveStrokeWidth: _minimumPositiveStrokeWidth(
                  commands,
                  paint.commandIndex,
                  paint.commandIndex,
                ),
              ));
            }
            final groupBounds = capture.bounds;
            if (groupBounds != null) {
              // Keep the structural Begin/End pair covered for the final
              // unsupported-command audit. The real paints above retain
              // their own command indices and clips; this marker compiles to
              // no draw.
              units.add(_GpuUnit(
                commandIndex: capture.start,
                endCommandIndex: i,
                bounds: _inflatePdf(groupBounds, 2),
                clip: capture.clip,
                blendMode: PdfBlendMode.normal,
                fillOverprint: false,
                strokeOverprint: false,
                darken: false,
                composite: spec,
              ));
            }
          } else {
            final bounds =
                spec is _EmptyGroupSpec ? spec.bounds : capture.bounds;
            if (bounds != null) {
              var compositeClip =
                  _withGpuRectClip(capture.clip, spec.contentClip);
              // An offscreen multi-paint group must apply its arbitrary clip
              // to each source paint before the group alpha is resolved.
              // Moving that clip to the completed texture can accumulate
              // different antialias coverage where translucent paints
              // overlap. [_CompiledScene] retains these path clips as
              // per-paint stencil states instead.
              if (spec is! _GroupPaintSpec || !spec.offscreen) {
                for (final pathClip in spec.contentPathClips) {
                  compositeClip = _pushGpuClip(
                    compositeClip,
                    pathClip.path,
                    pathClip.rule,
                  );
                }
              }
              units.add(_GpuUnit(
                commandIndex: capture.start,
                endCommandIndex: i,
                bounds: _inflatePdf(bounds, 2),
                clip: compositeClip,
                blendMode: capture.blendMode,
                fillOverprint: capture.fillOverprint,
                strokeOverprint: capture.strokeOverprint,
                darken: false,
                minimumPositiveStrokeWidth:
                    _minimumPositiveStrokeWidth(commands, capture.start, i),
                composite: spec,
              ));
            }
          }
          clip = capture.clip;
          blend = capture.blendMode;
          fillOverprint = capture.fillOverprint;
          strokeOverprint = capture.strokeOverprint;
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
            minimumPositiveStrokeWidth:
                _minimumPositiveStrokeWidth(commands, i, i),
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
      case PdfBeginGroupCommand(
        :final alpha,
        :final knockout,
        :final isolated,
        bounds: final groupBounds,
        :final backdropColor,
      )) {
    if (commands[end] is! PdfEndGroupCommand) {
      return (null, 'unsupported composite nesting');
    }
    if (isolated && knockout && backdropColor == null) {
      final knockoutFill = _parseKnockoutSoftMaskFill(
        commands,
        start,
        end,
        groupAlpha: alpha,
        initialClip: initialClip,
        initialFillOverprint: initialFillOverprint,
        initialStrokeOverprint: initialStrokeOverprint,
        initialBlend: initialBlend,
      );
      if (knockoutFill != null) return (knockoutFill, null);
    }
    final singleSoftMask = _parseSingleSoftMaskGroup(
      commands,
      start,
      end,
      groupAlpha: alpha,
      backdropColor: backdropColor,
      initialClip: initialClip,
      initialFillOverprint: initialFillOverprint,
      initialStrokeOverprint: initialStrokeOverprint,
      initialBlend: initialBlend,
    );
    if (singleSoftMask != null) return (singleSoftMask, null);
    // Knockout only changes how multiple sibling elements interact inside a
    // group. A one-element group is therefore identical either way. The
    // multi-paint path below is deliberately narrower: alpha-one, normal
    // source-over, non-knockout groups whose isolation layer is an identity.
    PdfDrawImageCommand? content;
    final paints = <(int?, PdfRenderCommand, PdfRect?, PdfBlendMode, bool)>[];
    final paintPathClips = <List<_GpuPathClip>>[];
    final paintAlphaScales = <int, double>{};
    PdfEndSoftMaskedCommand? softEnd;
    var softDepth = 0;
    var softCount = 0;
    PdfRect? clip = initialClip;
    PdfRect? contentClip;
    var pathClips = const <_GpuPathClip>[];
    var contentPathClips = const <_GpuPathClip>[];
    var emptyClipOnly = false;
    PdfRect? emptyClipBounds;
    var skippedEmptyPaint = false;
    var fillOverprint = initialFillOverprint;
    var strokeOverprint = initialStrokeOverprint;
    var blend = initialBlend;
    var invisibleGroupDepth = 0;
    final saved =
        <(PdfRect?, List<_GpuPathClip>, bool, bool, bool, PdfBlendMode)>[];
    for (var i = start + 1; i < end; i++) {
      final command = commands[i];
      if (invisibleGroupDepth != 0) {
        if (command is PdfBeginGroupCommand) invisibleGroupDepth++;
        if (command is PdfEndGroupCommand) invisibleGroupDepth--;
        continue;
      }
      if (command case PdfBeginGroupCommand(alpha: final groupAlpha)
          when groupAlpha <= 0) {
        invisibleGroupDepth = 1;
        continue;
      }
      switch (command) {
        case PdfSaveCommand():
          saved.add((
            clip,
            pathClips,
            emptyClipOnly,
            fillOverprint,
            strokeOverprint,
            blend,
          ));
        case PdfRestoreCommand():
          if (saved.isEmpty) return (null, 'unbalanced soft-mask image state');
          final restored = saved.removeLast();
          clip = restored.$1;
          pathClips = restored.$2;
          emptyClipOnly = restored.$3;
          fillOverprint = restored.$4;
          strokeOverprint = restored.$5;
          blend = restored.$6;
        case PdfClipPathCommand(:final path, :final rule):
          final pathBounds = pdfRenderPathBounds(path);
          final narrowed = _pdfIntersection(clip, pathBounds);
          final degenerate = pathBounds != null &&
              (pathBounds.right <= pathBounds.left ||
                  pathBounds.top <= pathBounds.bottom);
          if (degenerate ||
              (clip != null && pathBounds != null && narrowed == null)) {
            emptyClipOnly = true;
            clip = pathBounds;
            emptyClipBounds ??= pathBounds;
            break;
          }
          clip = narrowed;
          if (!FlutterGpuTileRasterBackend._isAxisAlignedRect(path)) {
            pathClips = List.unmodifiable([
              ...pathClips,
              (path: path, rule: rule),
            ]);
          }
        case PdfBeginSoftMaskedCommand():
          softDepth++;
          softCount++;
        case PdfEndSoftMaskedCommand():
          softDepth--;
          softEnd = command;
        case PdfDrawImageCommand():
          if (emptyClipOnly) {
            skippedEmptyPaint = true;
            break;
          }
          if (softDepth == 0 && content == null) {
            paints.add((i, command, clip, blend, false));
            paintPathClips.add(pathClips);
            contentClip = clip;
            break;
          }
          if (softDepth != 1 || content != null || paints.isNotEmpty) {
            return (null, 'soft-mask group is not a single image');
          }
          content = command;
          contentClip = clip;
          contentPathClips = pathClips;
        case PdfFillPathCommand():
          if (emptyClipOnly) {
            skippedEmptyPaint = true;
            break;
          }
          if (softDepth != 0 || content != null) {
            return (null, 'soft-mask group contains PdfFillPathCommand');
          }
          paints.add((i, command, clip, blend, fillOverprint));
          paintPathClips.add(pathClips);
          contentClip = clip;
        case PdfFillPathGradientCommand() || PdfFillMeshCommand():
          if (emptyClipOnly) {
            skippedEmptyPaint = true;
            break;
          }
          if (softDepth != 0 || content != null) {
            return (
              null,
              'soft-mask group contains ${command.runtimeType}',
            );
          }
          paints.add((i, command, clip, blend, fillOverprint));
          paintPathClips.add(pathClips);
          contentClip = clip;
        case PdfStrokePathCommand():
          if (emptyClipOnly) {
            skippedEmptyPaint = true;
            break;
          }
          if (softDepth != 0 || content != null) {
            return (null, 'soft-mask group contains PdfStrokePathCommand');
          }
          paints.add((i, command, clip, blend, strokeOverprint));
          paintPathClips.add(pathClips);
          contentClip = clip;
        case PdfDrawTextCommand(:final run):
          if (emptyClipOnly) {
            skippedEmptyPaint = true;
            break;
          }
          if (softDepth != 0 || content != null) {
            return (null, 'soft-mask group contains PdfDrawTextCommand');
          }
          paints.add((
            i,
            command,
            clip,
            blend,
            (run.fill && fillOverprint) ||
                (run.strokeColor != null && strokeOverprint),
          ));
          paintPathClips.add(pathClips);
          contentClip = clip;
        case PdfSetBlendModeCommand(:final mode):
          // A one-element group may use any internal blend: with a transparent
          // group backdrop every PDF blend function reduces to the source.
          // The multi-paint identity path validates Normal below.
          blend = mode;
        case PdfSetOverprintCommand(:final fill, :final stroke):
          fillOverprint = fill;
          strokeOverprint = stroke;
        case PdfBeginGroupCommand(:final backdropColor):
          if (blend != PdfBlendMode.normal ||
              fillOverprint ||
              strokeOverprint ||
              backdropColor != null) {
            return (null, 'nested image group');
          }
          final nestedEnd = _matchingGroupEnd(commands, i, end);
          if (nestedEnd == null) return (null, 'nested image group');
          final nested = _parseComposite(
            commands,
            i,
            nestedEnd,
            initialClip: clip,
            initialFillOverprint: false,
            initialStrokeOverprint: false,
            initialBlend: PdfBlendMode.normal,
          );
          final nestedSpec = nested.$1;
          switch (nestedSpec) {
            case _FlattenGroupSpec(paints: final nestedPaints):
              for (final nestedPaint in nestedPaints) {
                paints.add((
                  nestedPaint.commandIndex,
                  commands[nestedPaint.commandIndex],
                  nestedPaint.clip,
                  PdfBlendMode.normal,
                  false,
                ));
                paintPathClips.add(nestedPaint.pathClips);
              }
            case _GroupFillSpec(:final content, :final groupAlpha):
              paints.add((
                null,
                PdfFillPathCommand(
                  content.path,
                  content.color,
                  content.rule,
                  (content.alpha * groupAlpha).clamp(0.0, 1.0),
                ),
                nestedSpec.contentClip,
                PdfBlendMode.normal,
                false,
              ));
              paintPathClips.add(nestedSpec.contentPathClips);
            case _GroupStrokeSpec(:final content, :final groupAlpha):
              paints.add((
                null,
                PdfStrokePathCommand(
                  content.path,
                  content.color,
                  content.stroke,
                  (content.alpha * groupAlpha).clamp(0.0, 1.0),
                ),
                nestedSpec.contentClip,
                PdfBlendMode.normal,
                false,
              ));
              paintPathClips.add(nestedSpec.contentPathClips);
            case _GroupPaintSpec(
                  :final commands,
                  :final paintClips,
                  :final paintBlends,
                )
                when nestedSpec.groupAlpha == 1 &&
                    !nestedSpec.knockout &&
                    paintBlends.every((mode) => mode == PdfBlendMode.normal):
              for (var nestedIndex = 0;
                  nestedIndex < commands.length;
                  nestedIndex++) {
                paints.add((
                  null,
                  commands[nestedIndex],
                  paintClips[nestedIndex],
                  paintBlends[nestedIndex],
                  false,
                ));
                final nestedAlphaScale =
                    nestedSpec.paintAlphaScales[nestedIndex];
                if (nestedAlphaScale != null) {
                  paintAlphaScales[paints.length - 1] = nestedAlphaScale;
                }
                paintPathClips.add(nestedSpec.contentPathClips);
              }
            case _GroupPaintSpec(
                  commands: [PdfDrawImageCommand(:final request)],
                  paintClips: [final nestedClip],
                  paintBlends: [PdfBlendMode.normal],
                )
                when !nestedSpec.knockout && nestedSpec.backdropColor == null:
              // A single image over a transparent group backdrop can absorb
              // the group's alpha exactly: scaling the premultiplied source
              // before its parent composition is identical to sampling the
              // completed one-paint group with that alpha. This keeps common
              // nested image forms on the retained route without inventing a
              // second nested offscreen pass.
              paints.add((
                null,
                PdfDrawImageCommand(request),
                nestedClip,
                PdfBlendMode.normal,
                false,
              ));
              paintAlphaScales[paints.length - 1] =
                  (nestedSpec.paintAlphaScales[0] ?? 1) * nestedSpec.groupAlpha;
              paintPathClips.add(nestedSpec.contentPathClips);
            default:
              return (null, nested.$2 ?? 'nested image group');
          }
          i = nestedEnd;
        case PdfEndGroupCommand():
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
    if (invisibleGroupDepth != 0) {
      return (null, 'unbalanced invisible transparency group');
    }
    if ((emptyClipOnly || skippedEmptyPaint) &&
        softDepth == 0 &&
        paints.isEmpty &&
        content == null) {
      return (_EmptyGroupSpec(emptyClipBounds ?? clip!), null);
    }
    if (softCount == 0 && softDepth == 0 && paints.length == 1) {
      final paint = paints.single;
      final paintPaths = paintPathClips.single;
      final overprintReason = _compositeOverprintReason(paint.$2, paint.$5);
      if (overprintReason != null) return (null, overprintReason);
      if (backdropColor != null) {
        final canRenderSeededKnockout = !isolated &&
            knockout &&
            alpha == 1 &&
            initialBlend == PdfBlendMode.normal &&
            groupBounds != null &&
            paint.$4 == PdfBlendMode.normal &&
            switch (paint.$2) {
              PdfFillPathCommand(:final alpha) => alpha == 1,
              PdfStrokePathCommand(:final alpha) => alpha == 1,
              _ => false,
            };
        if (canRenderSeededKnockout) {
          return (
            _GroupPaintSpec(
              commands: [paint.$2],
              paintClips: [paint.$3],
              paintBlends: [paint.$4],
              contentClip: groupBounds,
              contentPathClips: paintPaths,
              offscreen: true,
              knockout: true,
              backdropColor: backdropColor,
            ),
            null,
          );
        }
        return (null, 'non-identity single-paint transparency group');
      }
      return switch (paint.$2) {
        PdfFillPathCommand content => (
            _GroupFillSpec(
              content: content,
              groupAlpha: alpha,
              contentClip: paint.$3,
              contentPathClips: paintPaths,
            ),
            null,
          ),
        PdfStrokePathCommand content => (
            _GroupStrokeSpec(
              content: content,
              groupAlpha: alpha,
              contentClip: paint.$3,
              contentPathClips: paintPaths,
            ),
            null,
          ),
        PdfDrawTextCommand content => (
            _GroupTextSpec(
              content: content,
              groupAlpha: alpha,
              contentClip: paint.$3,
              contentPathClips: paintPaths,
            ),
            null,
          ),
        PdfDrawImageCommand content => (
            _GroupPaintSpec(
              commands: [content],
              paintClips: [paint.$3],
              paintBlends: const [PdfBlendMode.normal],
              paintAlphaScales: Map.unmodifiable(paintAlphaScales),
              contentClip: paint.$3,
              contentPathClips: paintPaths,
              groupAlpha: alpha,
              offscreen: alpha != 1,
            ),
            null,
          ),
        PdfFillPathGradientCommand content => (
            _GroupPaintSpec(
              commands: [content],
              paintClips: [paint.$3],
              paintBlends: const [PdfBlendMode.normal],
              contentClip: paint.$3,
              contentPathClips: paintPaths,
              groupAlpha: alpha,
              offscreen: alpha != 1,
            ),
            null,
          ),
        PdfFillMeshCommand content => (
            _GroupPaintSpec(
              commands: [content],
              paintClips: [paint.$3],
              paintBlends: const [PdfBlendMode.normal],
              contentClip: paint.$3,
              contentPathClips: paintPaths,
              groupAlpha: alpha,
              offscreen: alpha != 1,
            ),
            null,
          ),
        _ => (null, 'unsupported transparency-group paint'),
      };
    }
    if (softCount == 0 && softDepth == 0 && paints.length > 1) {
      final commonPathClips = paintPathClips.first;
      final commonPaintPathClip = paintPathClips.every(
        (clips) => _samePathClipStack(clips, commonPathClips),
      );
      final commonClip = paints.first.$3;
      final normalPaints = paints.every((paint) =>
          paint.$4 == PdfBlendMode.normal &&
          _compositeOverprintReason(paint.$2, paint.$5) == null);
      final fixedFunctionPaints = paints.every((paint) =>
          FlutterGpuTileRasterBackend._isFixedFunctionBlendMode(paint.$4) &&
          _compositeOverprintReason(paint.$2, paint.$5) == null);
      final commonPaintClip =
          paints.every((paint) => _samePdfRect(paint.$3, commonClip));
      final disjointOuterBlend = initialBlend != PdfBlendMode.normal &&
          _areDisjointFills([
            for (final paint in paints)
              (paint.$2, paint.$3, paint.$4, paint.$5),
          ]);
      final canFlatten = alpha == 1 &&
          !knockout &&
          backdropColor == null &&
          normalPaints &&
          (initialBlend == PdfBlendMode.normal || disjointOuterBlend);
      final canRenderKnockout = isolated &&
          knockout &&
          backdropColor == null &&
          normalPaints &&
          paints.every((paint) => paint.$2 is PdfFillPathCommand);
      final canRenderSeededKnockout = !isolated &&
          knockout &&
          alpha == 1 &&
          initialBlend == PdfBlendMode.normal &&
          groupBounds != null &&
          backdropColor != null &&
          normalPaints &&
          paints.every((paint) => switch (paint.$2) {
                PdfFillPathCommand(:final alpha) => alpha == 1,
                PdfStrokePathCommand(:final alpha) => alpha == 1,
                _ => false,
              });
      final canRenderOffscreen = (isolated &&
              !knockout &&
              backdropColor == null &&
              fixedFunctionPaints) ||
          canRenderKnockout ||
          canRenderSeededKnockout;
      if (canFlatten &&
          paints.every((paint) => paint.$1 != null) &&
          (!commonPaintClip || !commonPaintPathClip)) {
        return (
          _FlattenGroupSpec(List.unmodifiable([
            for (var index = 0; index < paints.length; index++)
              (
                commandIndex: paints[index].$1!,
                clip: paints[index].$3,
                pathClips: paintPathClips[index],
              ),
          ])),
          null,
        );
      }
      if (!commonPaintPathClip) {
        return (null, 'non-rectangular multi-paint transparency group clip');
      }
      // A shared path clip can stay active across a flattened draw sequence,
      // which applies the same retained stencil to every paint. Do not move it
      // to the resolved texture of an offscreen group: repeated translucent
      // paints can accumulate different edge coverage from one final mask.
      if (commonPathClips.isNotEmpty &&
          (!canFlatten || !commonPaintClip) &&
          !canRenderOffscreen) {
        return (null, 'non-rectangular multi-paint transparency group clip');
      }
      if (!canFlatten && !canRenderOffscreen) {
        for (final paint in paints) {
          final reason = _compositeOverprintReason(paint.$2, paint.$5);
          if (reason != null) return (null, reason);
        }
        return (null, 'non-identity multi-paint transparency group');
      }
      // Synthesized paints from a nested group no longer have source command
      // indices, so they cannot use [_FlattenGroupSpec]'s per-command clips.
      // Retaining those clips in an offscreen pass is exact only for an
      // isolated group; an unisolated group must keep seeing the page
      // backdrop between paints.
      if (canFlatten && !commonPaintClip && !canRenderOffscreen) {
        return (null, 'nested group has distinct paint clips');
      }
      return (
        _GroupPaintSpec(
          commands: List.unmodifiable([for (final paint in paints) paint.$2]),
          paintClips: List.unmodifiable([for (final paint in paints) paint.$3]),
          paintBlends:
              List.unmodifiable([for (final paint in paints) paint.$4]),
          paintAlphaScales: Map.unmodifiable(paintAlphaScales),
          contentClip: canRenderSeededKnockout
              ? groupBounds
              : canFlatten && commonPaintClip
                  ? commonClip
                  : null,
          contentPathClips: commonPathClips,
          groupAlpha: alpha,
          offscreen: !canFlatten || !commonPaintClip,
          knockout: canRenderKnockout || canRenderSeededKnockout,
          backdropColor: canRenderSeededKnockout ? backdropColor : null,
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
    final mask = maskState.image;
    if (mask == null) return (null, maskState.rejection);
    final maskPathClips = maskState.pathClips;
    if (maskPathClips.isNotEmpty &&
        !_softMaskOutsideIsZero(
          luminosity: softEnd.luminosity,
          backdropLuminance: softEnd.backdropLuminance,
          transferScale: softEnd.transferScale,
          transferOffset: softEnd.transferOffset,
        )) {
      return (null, 'non-zero soft-mask backdrop outside path clip');
    }
    return (
      _SoftMaskImageSpec(
        content: content.request,
        mask: mask.request,
        groupAlpha: alpha,
        contentClip: contentClip,
        contentPathClips: List.unmodifiable([
          ...contentPathClips,
          ...maskPathClips,
        ]),
        maskClip: maskState.clip,
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
    final flattened = _parseOpaqueVectorMaskStack(
      commands,
      start,
      end,
      endCommand,
      initialClip: initialClip,
      initialFillOverprint: initialFillOverprint,
      initialStrokeOverprint: initialStrokeOverprint,
      initialBlend: initialBlend,
    );
    if (flattened != null) return (flattened, null);
    final textStack = _parseOpaqueTextMaskStack(
      commands,
      start,
      end,
      endCommand,
      initialClip: initialClip,
      initialFillOverprint: initialFillOverprint,
      initialStrokeOverprint: initialStrokeOverprint,
      initialBlend: initialBlend,
    );
    if (textStack != null) return (textStack, null);
    final maskCommands = endCommand.maskCommands;
    final luminosity = endCommand.luminosity;
    final backdropLuminance = endCommand.backdropLuminance;
    final transferScale = endCommand.transferScale;
    final transferOffset = endCommand.transferOffset;
    PdfRenderCommand? content;
    PdfRect? clip = initialClip;
    PdfRect? contentClip;
    var pathClips = const <_GpuPathClip>[];
    var contentPathClips = const <_GpuPathClip>[];
    final saved = <(PdfRect?, List<_GpuPathClip>)>[];
    for (var i = start + 1; i < end; i++) {
      final command = commands[i];
      switch (command) {
        case PdfSaveCommand():
          saved.add((clip, pathClips));
        case PdfRestoreCommand():
          if (saved.isEmpty) return (null, 'unbalanced soft-mask fill state');
          final restored = saved.removeLast();
          clip = restored.$1;
          pathClips = restored.$2;
        case PdfClipPathCommand(:final path, :final rule):
          clip = _pdfIntersection(clip, pdfRenderPathBounds(path));
          if (!FlutterGpuTileRasterBackend._isAxisAlignedRect(path)) {
            pathClips = List.unmodifiable([
              ...pathClips,
              (path: path, rule: rule),
            ]);
          }
        case PdfFillPathCommand() ||
              PdfStrokePathCommand() ||
              PdfDrawTextCommand():
          if (content != null) {
            return (null, 'soft-mask group has multiple paints');
          }
          content = command;
          contentClip = clip;
          contentPathClips = pathClips;
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
    final mask = maskState.image;
    if (mask == null) {
      final gradientState = _singleMaskGradient(maskCommands);
      final gradient = gradientState.$1;
      if (gradient != null &&
          !gradient.gradient.isRadial &&
          backdropLuminance == 0 &&
          transferScale == 1 &&
          transferOffset == 0 &&
          _gradientUnsupportedReason(gradient.gradient, gradient.alpha) ==
              null) {
        final contentBounds = _pdfIntersection(
          contentClip,
          pdfRenderCommandBounds(content),
        );
        final maskBounds = gradientState.$2;
        if (contentBounds != null &&
            maskBounds != null &&
            _pdfContains(maskBounds, contentBounds)) {
          return switch (content) {
            PdfFillPathCommand fill => (
                _SoftMaskGradientFillSpec(
                  content: fill,
                  mask: gradient,
                  contentClip: contentClip,
                  contentPathClips: contentPathClips,
                  luminosity: luminosity,
                ),
                null,
              ),
            PdfStrokePathCommand stroke when stroke.stroke.width > 0 => (
                _SoftMaskGradientStrokeSpec(
                  content: stroke,
                  mask: gradient,
                  contentClip: contentClip,
                  contentPathClips: contentPathClips,
                  luminosity: luminosity,
                ),
                null,
              ),
            PdfStrokePathCommand() => (
                null,
                'gradient soft-mask hairline requires Canvas fallback',
              ),
            PdfDrawTextCommand text => (
                _SoftMaskGradientTextSpec(
                  content: text,
                  mask: gradient,
                  contentClip: contentClip,
                  contentPathClips: contentPathClips,
                  luminosity: luminosity,
                ),
                null,
              ),
            _ => (null, 'unsupported gradient soft-mask content'),
          };
        }
      }
      final vectorMask = _vectorMaskFills(maskCommands);
      final maskFills = vectorMask.$1;
      if (maskFills == null) {
        return (null, vectorMask.$2 ?? maskState.rejection);
      }
      if (![backdropLuminance, transferScale, transferOffset]
          .every((value) => value.isFinite)) {
        return (null, 'invalid vector soft-mask transfer');
      }
      if (content is! PdfFillPathCommand) {
        return (null, 'unsupported vector soft-mask text');
      }
      return (
        _SoftMaskVectorFillSpec(
          content: content,
          maskFills: maskFills,
          contentClip: contentClip,
          contentPathClips: contentPathClips,
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
    final maskPathClips = maskState.pathClips;
    if (maskPathClips.isNotEmpty &&
        !_softMaskOutsideIsZero(
          luminosity: luminosity,
          backdropLuminance: backdropLuminance,
          transferScale: transferScale,
          transferOffset: transferOffset,
        )) {
      return (null, 'non-zero soft-mask backdrop outside path clip');
    }
    final compositePathClips = List<_GpuPathClip>.unmodifiable([
      ...contentPathClips,
      ...maskPathClips,
    ]);
    return switch (content) {
      PdfFillPathCommand fill => (
          _SoftMaskFillSpec(
            content: fill,
            mask: mask.request,
            contentClip: contentClip,
            contentPathClips: compositePathClips,
            maskClip: maskState.clip,
            luminosity: luminosity,
            backdropLuminance: backdropLuminance,
            transferScale: transferScale,
            transferOffset: transferOffset,
          ),
          null,
        ),
      PdfStrokePathCommand stroke when stroke.stroke.width > 0 => (
          _SoftMaskStrokeSpec(
            content: stroke,
            mask: mask.request,
            contentClip: contentClip,
            contentPathClips: compositePathClips,
            maskClip: maskState.clip,
            luminosity: luminosity,
            backdropLuminance: backdropLuminance,
            transferScale: transferScale,
            transferOffset: transferOffset,
          ),
          null,
        ),
      PdfStrokePathCommand() => (
          null,
          'image soft-mask hairline requires Canvas fallback'
        ),
      PdfDrawTextCommand text => (
          _SoftMaskTextSpec(
            content: text,
            mask: mask.request,
            contentClip: contentClip,
            contentPathClips: compositePathClips,
            maskClip: maskState.clip,
            luminosity: luminosity,
            backdropLuminance: backdropLuminance,
            transferScale: transferScale,
            transferOffset: transferOffset,
          ),
          null,
        ),
      _ => (null, 'unsupported image soft-mask content'),
    };
  }
  return (null, 'unsupported composite ${commands[start].runtimeType}');
}

/// Retains a one-element soft-masked transparency group as one bounded layer.
///
/// The soft mask first resolves the source shape inside a transparent group;
/// only then does the enclosing group alpha apply to that completed source.
/// Keeping those stages separate mirrors Canvas' saveLayer ordering and avoids
/// edge-coverage differences from folding the alpha into the masked paint.
/// State-only commands may surround the element; additional paints, explicit
/// backdrops, and non-Normal internal blends stay on Canvas.
_GpuCompositeSpec? _parseSingleSoftMaskGroup(
  List<PdfRenderCommand> commands,
  int start,
  int end, {
  required double groupAlpha,
  required PdfColor? backdropColor,
  required PdfRect? initialClip,
  required bool initialFillOverprint,
  required bool initialStrokeOverprint,
  required PdfBlendMode initialBlend,
}) {
  if (backdropColor != null || !groupAlpha.isFinite) return null;
  var clip = initialClip;
  var blend = initialBlend;
  var fillOverprint = initialFillOverprint;
  var strokeOverprint = initialStrokeOverprint;
  final saved = <(PdfRect?, PdfBlendMode, bool, bool)>[];
  _GpuCompositeSpec? nested;

  int? nestedEnd(int nestedStart) {
    var depth = 1;
    for (var index = nestedStart + 1; index < end; index++) {
      switch (commands[index]) {
        case PdfBeginSoftMaskedCommand():
          depth++;
        case PdfEndSoftMaskedCommand():
          depth--;
          if (depth == 0) return index;
        case PdfBeginGroupCommand() || PdfEndGroupCommand():
          return null;
        default:
          break;
      }
    }
    return null;
  }

  for (var index = start + 1; index < end; index++) {
    final command = commands[index];
    switch (command) {
      case PdfSaveCommand():
        saved.add((clip, blend, fillOverprint, strokeOverprint));
      case PdfRestoreCommand():
        if (saved.isEmpty) return null;
        final restored = saved.removeLast();
        clip = restored.$1;
        blend = restored.$2;
        fillOverprint = restored.$3;
        strokeOverprint = restored.$4;
      case PdfClipPathCommand(:final path):
        if (!FlutterGpuTileRasterBackend._isAxisAlignedRect(path)) return null;
        clip = _pdfIntersection(clip, pdfRenderPathBounds(path));
        if (clip == null) return null;
      case PdfSetBlendModeCommand(:final mode):
        blend = mode;
      case PdfSetOverprintCommand(:final fill, :final stroke):
        fillOverprint = fill;
        strokeOverprint = stroke;
      case PdfBeginSoftMaskedCommand():
        if (nested != null ||
            blend != PdfBlendMode.normal ||
            fillOverprint ||
            strokeOverprint) {
          return null;
        }
        final stop = nestedEnd(index);
        if (stop == null) return null;
        for (var scan = index + 1; scan < stop; scan++) {
          if (commands[scan]
              case PdfSetOverprintCommand(:final fill, :final stroke)
              when fill || stroke) {
            // Canvas' RGB overprint fallback is destination-dependent inside
            // the transparent soft-mask capture. Do not treat it as a plain
            // one-source layer; keep the exact Canvas route.
            return null;
          }
        }
        final parsed = _parseComposite(
          commands,
          index,
          stop,
          initialClip: clip,
          initialFillOverprint: fillOverprint,
          initialStrokeOverprint: strokeOverprint,
          initialBlend: blend,
        ).$1;
        if (parsed == null) return null;
        nested = _SoftMaskGroupSpec(
          parsed,
          groupAlpha.clamp(0.0, 1.0).toDouble(),
        );
        index = stop;
      case PdfBeginGroupCommand() ||
            PdfEndGroupCommand() ||
            PdfEndSoftMaskedCommand():
        return null;
      default:
        if (pdfRenderCommandBounds(command) != null) return null;
    }
  }
  return saved.isEmpty ? nested : null;
}

/// Recognizes the exact isolated-knockout shape emitted by PDF.js's
/// `knockout_smask.pdf`: one ordinary base fill followed by one
/// vector-soft-masked fill. The masked source remains one captured object (its
/// mask is not applied to sibling paints), then the completed transparent
/// group applies its alpha and outer blend once.
_KnockoutSoftMaskFillSpec? _parseKnockoutSoftMaskFill(
  List<PdfRenderCommand> commands,
  int start,
  int end, {
  required double groupAlpha,
  required PdfRect? initialClip,
  required bool initialFillOverprint,
  required bool initialStrokeOverprint,
  required PdfBlendMode initialBlend,
}) {
  var clip = initialClip;
  var blend = initialBlend;
  var fillOverprint = initialFillOverprint;
  var strokeOverprint = initialStrokeOverprint;
  final saved = <(PdfRect?, PdfBlendMode, bool, bool)>[];
  PdfFillPathCommand? base;
  PdfRect? baseClip;
  _SoftMaskVectorFillSpec? masked;

  int? nestedEnd(int nestedStart) {
    var depth = 1;
    for (var index = nestedStart + 1; index < end; index++) {
      switch (commands[index]) {
        case PdfBeginSoftMaskedCommand():
          depth++;
        case PdfEndSoftMaskedCommand():
          depth--;
          if (depth == 0) return index;
        case PdfBeginGroupCommand() || PdfEndGroupCommand():
          return null;
        default:
          break;
      }
    }
    return null;
  }

  for (var index = start + 1; index < end; index++) {
    final command = commands[index];
    switch (command) {
      case PdfSaveCommand():
        saved.add((clip, blend, fillOverprint, strokeOverprint));
      case PdfRestoreCommand():
        if (saved.isEmpty) return null;
        final restored = saved.removeLast();
        clip = restored.$1;
        blend = restored.$2;
        fillOverprint = restored.$3;
        strokeOverprint = restored.$4;
      case PdfClipPathCommand(:final path):
        if (!FlutterGpuTileRasterBackend._isAxisAlignedRect(path)) return null;
        clip = _pdfIntersection(clip, pdfRenderPathBounds(path));
        if (clip == null) return null;
      case PdfSetBlendModeCommand(:final mode):
        blend = mode;
      case PdfSetOverprintCommand(:final fill, :final stroke):
        fillOverprint = fill;
        strokeOverprint = stroke;
      case PdfFillPathCommand():
        if (base != null ||
            masked != null ||
            blend != PdfBlendMode.normal ||
            fillOverprint) {
          return null;
        }
        base = command;
        baseClip = clip;
      case PdfBeginSoftMaskedCommand():
        if (base == null || masked != null) return null;
        final nestedStop = nestedEnd(index);
        if (nestedStop == null) return null;
        final parsed = _parseComposite(
          commands,
          index,
          nestedStop,
          initialClip: clip,
          initialFillOverprint: fillOverprint,
          initialStrokeOverprint: strokeOverprint,
          initialBlend: blend,
        ).$1;
        if (parsed is! _SoftMaskVectorFillSpec ||
            parsed.contentPathClips.isNotEmpty) {
          return null;
        }
        masked = parsed;
        index = nestedStop;
      case PdfBeginGroupCommand() ||
            PdfEndGroupCommand() ||
            PdfEndSoftMaskedCommand():
        return null;
      default:
        if (pdfRenderCommandBounds(command) != null) return null;
    }
  }
  if (saved.isNotEmpty || base == null || masked == null) return null;
  return _KnockoutSoftMaskFillSpec(
    base: base,
    baseClip: baseClip,
    masked: masked,
    groupAlpha: groupAlpha,
  );
}

/// Whether a multi-paint group can apply its outer blend per paint without
/// changing the result.
///
/// Disjoint fills never contribute to the same destination sample, so
/// compositing their transparent group once is identical to compositing each
/// fill directly. The two-point padding is deliberately conservative around
/// antialiased path edges; overlapping, touching, stroked, or unbounded paints
/// stay on the exact Canvas layer path.
bool _areDisjointFills(
  List<(PdfRenderCommand, PdfRect?, PdfBlendMode, bool)> paints,
) {
  final bounds = <PdfRect>[];
  for (final paint in paints) {
    if (paint.$1 is! PdfFillPathCommand) return false;
    final commandBounds = pdfRenderCommandBounds(paint.$1);
    final clipped = _pdfIntersection(commandBounds, paint.$2);
    if (clipped == null) return false;
    final padded = _inflatePdf(clipped, 2);
    if (bounds.any((other) => _pdfIntersection(other, padded) != null)) {
      return false;
    }
    bounds.add(padded);
  }
  return true;
}

int? _matchingGroupEnd(
  List<PdfRenderCommand> commands,
  int start,
  int outerEnd,
) {
  var depth = 1;
  for (var index = start + 1; index < outerEnd; index++) {
    switch (commands[index]) {
      case PdfBeginGroupCommand():
        depth++;
      case PdfEndGroupCommand():
        depth--;
        if (depth == 0) return index;
      default:
        break;
    }
  }
  return null;
}

/// Flattens one narrow nested-mask shape without allocating an offscreen
/// group: an opaque Normal base covering a binary white vector mask, followed
/// by image-masked fills blended onto that base. Because the base is opaque,
/// each nested blend sees exactly the same backdrop whether it is evaluated
/// inside the isolated source layer or directly after the base. The outer
/// mask then reduces to a retained path stencil (a rectangle stays a cheap
/// scissor).
///
/// Every condition below is part of that proof. General nested masks, partial
/// bases, non-binary masks, and non-Normal outer composites continue through
/// the existing conservative Canvas fallback.
_FlattenSoftMaskSpec? _parseOpaqueVectorMaskStack(
  List<PdfRenderCommand> commands,
  int start,
  int end,
  PdfEndSoftMaskedCommand outerEnd, {
  required PdfRect? initialClip,
  required bool initialFillOverprint,
  required bool initialStrokeOverprint,
  required PdfBlendMode initialBlend,
}) {
  if (initialBlend != PdfBlendMode.normal ||
      outerEnd.backdropLuminance != 0 ||
      outerEnd.transferScale != 1 ||
      outerEnd.transferOffset != 0) {
    return null;
  }
  final maskState = _singleMaskPath(outerEnd.maskCommands);
  final mask = maskState.$1;
  if (mask == null) return null;
  final maskIsOpaque = mask.alpha == 1 &&
      (!outerEnd.luminosity ||
          (mask.color.red == 1 &&
              mask.color.green == 1 &&
              mask.color.blue == 1));
  if (!maskIsOpaque) return null;
  final maskBounds = pdfRenderCommandBounds(mask);
  var visibleMask = _pdfIntersection(initialClip, maskState.$2);
  visibleMask = _pdfIntersection(visibleMask, maskBounds);
  if (visibleMask == null) return null;
  final rectangularMask =
      FlutterGpuTileRasterBackend._isAxisAlignedRect(mask.path);
  if (!rectangularMask && mask.rule != PdfFillRule.nonzero) return null;
  final pathClip = rectangularMask ? null : mask.path;

  var clip = initialClip;
  var blend = initialBlend;
  var fillOverprint = initialFillOverprint;
  var strokeOverprint = initialStrokeOverprint;
  final saved = <(PdfRect?, PdfBlendMode, bool, bool)>[];
  final paints = <_FlattenSoftMaskPaint>[];
  var hasOpaqueBase = false;
  var nestedMasks = 0;

  int? nestedEnd(int nestedStart) {
    var depth = 1;
    for (var i = nestedStart + 1; i < end; i++) {
      switch (commands[i]) {
        case PdfBeginSoftMaskedCommand():
          depth++;
        case PdfEndSoftMaskedCommand():
          depth--;
          if (depth == 0) return i;
        case PdfBeginGroupCommand() || PdfEndGroupCommand():
          return null;
        default:
          break;
      }
    }
    return null;
  }

  for (var i = start + 1; i < end; i++) {
    final command = commands[i];
    switch (command) {
      case PdfSaveCommand():
        saved.add((clip, blend, fillOverprint, strokeOverprint));
      case PdfRestoreCommand():
        if (saved.isEmpty) return null;
        final restored = saved.removeLast();
        clip = restored.$1;
        blend = restored.$2;
        fillOverprint = restored.$3;
        strokeOverprint = restored.$4;
      case PdfClipPathCommand(:final path):
        if (!FlutterGpuTileRasterBackend._isAxisAlignedRect(path)) return null;
        clip = _pdfIntersection(clip, pdfRenderPathBounds(path));
        if (clip == null) return null;
      case PdfSetBlendModeCommand(:final mode):
        blend = mode;
      case PdfSetOverprintCommand(:final fill, :final stroke):
        fillOverprint = fill;
        strokeOverprint = stroke;
      case PdfFillPathCommand(:final path, :final rule, :final alpha):
        if (hasOpaqueBase || alpha != 1 || blend != PdfBlendMode.normal) {
          return null;
        }
        final bounds = _pdfIntersection(clip, pdfRenderPathBounds(path));
        final matchingMask = rectangularMask
            ? bounds != null && _pdfContains(bounds, visibleMask)
            : rule == mask.rule && _samePathGeometry(path, mask.path);
        if (bounds == null || !matchingMask) {
          return null;
        }
        hasOpaqueBase = true;
        paints.add(_FlattenSoftMaskPaint(
          commandIndex: i,
          endCommandIndex: i,
          bounds: visibleMask,
          clip: visibleMask,
          blendMode: PdfBlendMode.normal,
          pathClip: pathClip,
        ));
      case PdfBeginSoftMaskedCommand():
        if (!hasOpaqueBase) return null;
        final nestedStop = nestedEnd(i);
        if (nestedStop == null ||
            commands[nestedStop] is! PdfEndSoftMaskedCommand) {
          return null;
        }
        final parsed = _parseComposite(
          commands,
          i,
          nestedStop,
          initialClip: clip,
          initialFillOverprint: fillOverprint,
          initialStrokeOverprint: strokeOverprint,
          initialBlend: blend,
        ).$1;
        if (parsed is! _SoftMaskFillSpec ||
            parsed.contentPathClips.isNotEmpty) {
          return null;
        }
        final contentBounds = pdfRenderCommandBounds(parsed.content);
        final contentClip = _pdfIntersection(clip, parsed.contentClip);
        final paintClip = _pdfIntersection(visibleMask, contentClip);
        final bounds = _pdfIntersection(paintClip, contentBounds);
        if (bounds != null) {
          paints.add(_FlattenSoftMaskPaint(
            commandIndex: i,
            endCommandIndex: nestedStop,
            bounds: bounds,
            clip: paintClip!,
            blendMode: blend,
            composite: parsed,
            pathClip: pathClip,
          ));
        }
        nestedMasks++;
        // CanvasPdfDevice restores the blend captured by beginSoftMasked
        // after compositing the nested layer. State-only commands inside the
        // layer therefore do not leak into the next sibling.
        i = nestedStop;
      case PdfBeginGroupCommand() || PdfEndGroupCommand():
        return null;
      default:
        if (pdfRenderCommandBounds(command) != null) return null;
    }
  }
  if (saved.isNotEmpty || !hasOpaqueBase || nestedMasks == 0) return null;
  return _FlattenSoftMaskSpec(List.unmodifiable(paints));
}

/// Text inner-shadow/glow effects in the GWG suite use the same exact shape
/// as the vector stack above: an opaque text base, one image-masked fill, then
/// an opaque white copy of the same text as the outer luminosity mask. The
/// common text outline is an exact retained stencil, so no offscreen group or
/// rasterized glyph mask is needed.
_FlattenSoftMaskSpec? _parseOpaqueTextMaskStack(
  List<PdfRenderCommand> commands,
  int start,
  int end,
  PdfEndSoftMaskedCommand outerEnd, {
  required PdfRect? initialClip,
  required bool initialFillOverprint,
  required bool initialStrokeOverprint,
  required PdfBlendMode initialBlend,
}) {
  if (!outerEnd.luminosity ||
      initialBlend != PdfBlendMode.normal ||
      outerEnd.backdropLuminance != 0 ||
      outerEnd.transferScale != 1 ||
      outerEnd.transferOffset != 0) {
    return null;
  }
  final maskState = _singleMaskText(outerEnd.maskCommands);
  final mask = maskState.$1;
  if (mask == null ||
      mask.run.color.red != 1 ||
      mask.run.color.green != 1 ||
      mask.run.color.blue != 1 ||
      mask.run.fillAlpha != 1 ||
      _unsupportedTextReason(mask.run) != null) {
    return null;
  }
  final maskPath = _textPath(mask.run);
  final maskBounds = pdfRenderCommandBounds(mask);
  var visibleMask = _pdfIntersection(initialClip, maskState.$2);
  visibleMask = _pdfIntersection(visibleMask, maskBounds);
  if (maskPath == null || visibleMask == null) return null;

  var clip = initialClip;
  var blend = initialBlend;
  var fillOverprint = initialFillOverprint;
  var strokeOverprint = initialStrokeOverprint;
  final saved = <(PdfRect?, PdfBlendMode, bool, bool)>[];
  final paints = <_FlattenSoftMaskPaint>[];
  PdfDrawTextCommand? base;
  var nestedMasks = 0;

  int? nestedEnd(int nestedStart) {
    var depth = 1;
    for (var i = nestedStart + 1; i < end; i++) {
      switch (commands[i]) {
        case PdfBeginSoftMaskedCommand():
          depth++;
        case PdfEndSoftMaskedCommand():
          depth--;
          if (depth == 0) return i;
        case PdfBeginGroupCommand() || PdfEndGroupCommand():
          return null;
        default:
          break;
      }
    }
    return null;
  }

  for (var i = start + 1; i < end; i++) {
    final command = commands[i];
    switch (command) {
      case PdfSaveCommand():
        saved.add((clip, blend, fillOverprint, strokeOverprint));
      case PdfRestoreCommand():
        if (saved.isEmpty) return null;
        final restored = saved.removeLast();
        clip = restored.$1;
        blend = restored.$2;
        fillOverprint = restored.$3;
        strokeOverprint = restored.$4;
      case PdfClipPathCommand(:final path):
        if (!FlutterGpuTileRasterBackend._isAxisAlignedRect(path)) return null;
        clip = _pdfIntersection(clip, pdfRenderPathBounds(path));
        if (clip == null) return null;
      case PdfSetBlendModeCommand(:final mode):
        blend = mode;
      case PdfSetOverprintCommand(:final fill, :final stroke):
        fillOverprint = fill;
        strokeOverprint = stroke;
      case PdfDrawTextCommand():
        if (base != null ||
            blend != PdfBlendMode.normal ||
            command.run.fillAlpha != 1 ||
            _unsupportedTextReason(command.run) != null ||
            !_sameTextGeometry(command, mask)) {
          return null;
        }
        final bounds = _pdfIntersection(
          _pdfIntersection(clip, visibleMask),
          pdfRenderCommandBounds(command),
        );
        if (bounds == null) return null;
        base = command;
        paints.add(_FlattenSoftMaskPaint(
          commandIndex: i,
          endCommandIndex: i,
          bounds: bounds,
          clip: visibleMask,
          blendMode: PdfBlendMode.normal,
          pathClip: maskPath,
        ));
      case PdfBeginSoftMaskedCommand():
        if (base == null) return null;
        final nestedStop = nestedEnd(i);
        if (nestedStop == null ||
            commands[nestedStop] is! PdfEndSoftMaskedCommand) {
          return null;
        }
        final parsed = _parseComposite(
          commands,
          i,
          nestedStop,
          initialClip: clip,
          initialFillOverprint: fillOverprint,
          initialStrokeOverprint: strokeOverprint,
          initialBlend: blend,
        ).$1;
        if (parsed is! _SoftMaskFillSpec ||
            parsed.contentPathClips.isNotEmpty) {
          return null;
        }
        final bounds = _pdfIntersection(
          _pdfIntersection(
            _pdfIntersection(clip, parsed.contentClip),
            visibleMask,
          ),
          pdfRenderCommandBounds(parsed.content),
        );
        if (bounds != null) {
          paints.add(_FlattenSoftMaskPaint(
            commandIndex: i,
            endCommandIndex: nestedStop,
            bounds: bounds,
            clip: visibleMask,
            blendMode: blend,
            composite: parsed,
            pathClip: maskPath,
          ));
        }
        nestedMasks++;
        i = nestedStop;
      case PdfBeginGroupCommand() || PdfEndGroupCommand():
        return null;
      default:
        if (pdfRenderCommandBounds(command) != null) return null;
    }
  }
  if (saved.isNotEmpty || base == null || nestedMasks != 1) return null;
  return _FlattenSoftMaskSpec(List.unmodifiable(paints));
}

bool _sameTextGeometry(PdfDrawTextCommand a, PdfDrawTextCommand b) {
  final left = _textSubpaths(a.run), right = _textSubpaths(b.run);
  return left != null && right != null && _sameSubpaths(left, right);
}

bool _samePathGeometry(PdfPath a, PdfPath b) => _sameSubpaths(
      flattenPath(a, PdfMatrix.identity, tolerance: 0.01),
      flattenPath(b, PdfMatrix.identity, tolerance: 0.01),
    );

bool _sameSubpaths(List<FlatSubpath> left, List<FlatSubpath> right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    final l = left[i], r = right[i];
    if (l.closed != r.closed || l.points.length != r.points.length) {
      return false;
    }
    for (var j = 0; j < l.points.length; j++) {
      if ((l.points[j] - r.points[j]).abs() > 0.001) return false;
    }
  }
  return true;
}

PdfPath? _textPath(PdfTextRun run) {
  final glyphs = run.glyphs;
  if (glyphs == null) return null;
  final segments = <PdfPathSegment>[];
  for (final glyph in glyphs) {
    final outline = glyph.outline;
    if (outline == null) continue;
    final transform = PdfMatrix.translation(glyph.offset, glyph.offsetY)
        .concat(run.transform);
    final cursor = outline.cursor();
    while (cursor.moveNext()) {
      segments.add(switch (cursor.verb) {
        PdfPathVerb.moveTo => PdfMoveTo(
            transform.transformX(cursor.x1, cursor.y1),
            transform.transformY(cursor.x1, cursor.y1),
          ),
        PdfPathVerb.lineTo => PdfLineTo(
            transform.transformX(cursor.x1, cursor.y1),
            transform.transformY(cursor.x1, cursor.y1),
          ),
        PdfPathVerb.cubicTo => PdfCubicTo(
            transform.transformX(cursor.x1, cursor.y1),
            transform.transformY(cursor.x1, cursor.y1),
            transform.transformX(cursor.x2, cursor.y2),
            transform.transformY(cursor.x2, cursor.y2),
            transform.transformX(cursor.x3, cursor.y3),
            transform.transformY(cursor.x3, cursor.y3),
          ),
        PdfPathVerb.close => const PdfClosePath(),
      });
    }
  }
  return segments.isEmpty ? null : PdfPath(List.unmodifiable(segments));
}

// Adjacent form transforms in real PDFs can serialize the same intended edge
// a few millionths of a point apart. The retained stencil still uses the
// original geometry; this tolerance only recognizes coincident coverage.
bool _pdfContains(PdfRect outer, PdfRect inner) =>
    outer.left <= inner.left + 0.001 &&
    outer.bottom <= inner.bottom + 0.001 &&
    outer.right + 0.001 >= inner.right &&
    outer.top + 0.001 >= inner.top;

typedef _SingleMaskImageState = ({
  PdfDrawImageCommand? image,
  PdfRect? clip,
  List<_GpuPathClip> pathClips,
  String? rejection,
});

_SingleMaskImageState _rejectedMaskImage(String rejection) => (
      image: null,
      clip: null,
      pathClips: const [],
      rejection: rejection,
    );

_SingleMaskImageState _singleMaskImage(List<PdfRenderCommand> commands) {
  PdfDrawImageCommand? image;
  PdfRect? imageClip;
  var pathClips = const <_GpuPathClip>[];
  var imagePathClips = const <_GpuPathClip>[];
  PdfRect? clip;
  var blend = PdfBlendMode.normal;
  final saved = <(PdfRect?, List<_GpuPathClip>, PdfBlendMode)>[];
  for (final command in commands) {
    switch (command) {
      case PdfSaveCommand():
        saved.add((clip, pathClips, blend));
      case PdfRestoreCommand():
        if (saved.isEmpty) {
          return _rejectedMaskImage('unbalanced mask image state');
        }
        final restored = saved.removeLast();
        clip = restored.$1;
        pathClips = restored.$2;
        blend = restored.$3;
      case PdfClipPathCommand(:final path, :final rule):
        clip = _pdfIntersection(clip, pdfRenderPathBounds(path));
        if (!FlutterGpuTileRasterBackend._isAxisAlignedRect(path)) {
          pathClips = List.unmodifiable([
            ...pathClips,
            (path: path, rule: rule),
          ]);
        }
      case PdfDrawImageCommand():
        if (image != null) {
          return _rejectedMaskImage('mask contains multiple images');
        }
        if (blend != PdfBlendMode.normal) {
          return _rejectedMaskImage('mask image blend mode ${blend.name}');
        }
        image = command;
        imageClip = clip;
        imagePathClips = pathClips;
      case PdfSetBlendModeCommand(:final mode):
        blend = mode;
      case PdfSetOverprintCommand():
        break;
      default:
        if (pdfRenderCommandBounds(command) != null) {
          return _rejectedMaskImage(
            'mask contains ${command.runtimeType}',
          );
        }
    }
  }
  if (saved.isNotEmpty) {
    return _rejectedMaskImage('unbalanced mask image state');
  }
  if (image == null) {
    return _rejectedMaskImage('mask has no image');
  }
  return (
    image: image,
    clip: imageClip,
    pathClips: imagePathClips,
    rejection: null,
  );
}

bool _softMaskOutsideIsZero({
  required bool luminosity,
  required double backdropLuminance,
  required double transferScale,
  required double transferOffset,
}) {
  if (![backdropLuminance, transferScale, transferOffset]
      .every((value) => value.isFinite)) {
    return false;
  }
  final outside = luminosity ? backdropLuminance : 0.0;
  return outside * transferScale + transferOffset <= 0;
}

(PdfFillPathGradientCommand?, PdfRect?, String?) _singleMaskGradient(
    List<PdfRenderCommand> commands) {
  PdfFillPathGradientCommand? gradient;
  PdfRect? clip;
  PdfRect? bounds;
  var blend = PdfBlendMode.normal;
  final saved = <(PdfRect?, PdfBlendMode)>[];
  for (final command in commands) {
    switch (command) {
      case PdfSaveCommand():
        saved.add((clip, blend));
      case PdfRestoreCommand():
        if (saved.isEmpty) {
          return (null, null, 'unbalanced mask gradient state');
        }
        final restored = saved.removeLast();
        clip = restored.$1;
        blend = restored.$2;
      case PdfClipPathCommand(:final path):
        if (!FlutterGpuTileRasterBackend._isAxisAlignedRect(path)) {
          return (null, null, 'non-rectangular mask gradient clip');
        }
        clip = _pdfIntersection(clip, pdfRenderPathBounds(path));
      case PdfFillPathGradientCommand(:final path):
        if (gradient != null) {
          return (null, null, 'mask contains multiple gradients');
        }
        if (blend != PdfBlendMode.normal) {
          return (null, null, 'mask gradient blend mode ${blend.name}');
        }
        if (!FlutterGpuTileRasterBackend._isAxisAlignedRect(path)) {
          return (null, null, 'non-rectangular mask gradient fill');
        }
        gradient = command;
        bounds = _pdfIntersection(clip, pdfRenderPathBounds(path));
      case PdfSetBlendModeCommand(:final mode):
        blend = mode;
      case PdfSetOverprintCommand():
        // A single mask element has no prior colorants to preserve.
        break;
      default:
        if (pdfRenderCommandBounds(command) != null) {
          return (null, null, 'mask contains ${command.runtimeType}');
        }
    }
  }
  if (saved.isNotEmpty) {
    return (null, null, 'unbalanced mask gradient state');
  }
  if (gradient == null || bounds == null) {
    return (null, null, 'mask has no gradient');
  }
  return (gradient, bounds, null);
}

(PdfDrawTextCommand?, PdfRect?, String?) _singleMaskText(
    List<PdfRenderCommand> commands) {
  PdfDrawTextCommand? text;
  PdfRect? textClip;
  PdfRect? clip;
  var blend = PdfBlendMode.normal;
  final saved = <(PdfRect?, PdfBlendMode)>[];
  for (final command in commands) {
    switch (command) {
      case PdfSaveCommand():
        saved.add((clip, blend));
      case PdfRestoreCommand():
        if (saved.isEmpty) return (null, null, 'unbalanced mask text state');
        final restored = saved.removeLast();
        clip = restored.$1;
        blend = restored.$2;
      case PdfClipPathCommand(:final path):
        if (!FlutterGpuTileRasterBackend._isAxisAlignedRect(path)) {
          return (null, null, 'non-rectangular mask text clip');
        }
        clip = _pdfIntersection(clip, pdfRenderPathBounds(path));
      case PdfDrawTextCommand():
        if (text != null) return (null, null, 'mask contains multiple texts');
        if (blend != PdfBlendMode.normal) {
          return (null, null, 'mask text blend mode ${blend.name}');
        }
        text = command;
        textClip = clip;
      case PdfSetBlendModeCommand(:final mode):
        blend = mode;
      case PdfSetOverprintCommand():
        // A single mask element has no prior colorants to preserve.
        break;
      default:
        if (pdfRenderCommandBounds(command) != null) {
          return (null, null, 'mask contains ${command.runtimeType}');
        }
    }
  }
  if (saved.isNotEmpty) return (null, null, 'unbalanced mask text state');
  if (text == null) return (null, null, 'mask has no text');
  return (text, textClip, null);
}

(PdfFillPathCommand?, PdfRect?, String?) _singleMaskPath(
    List<PdfRenderCommand> commands) {
  PdfFillPathCommand? fill;
  PdfRect? fillClip;
  PdfRect? clip;
  var blend = PdfBlendMode.normal;
  final saved = <(PdfRect?, PdfBlendMode)>[];
  for (final command in commands) {
    switch (command) {
      case PdfSaveCommand():
        saved.add((clip, blend));
      case PdfRestoreCommand():
        if (saved.isEmpty) return (null, null, 'unbalanced mask path state');
        final restored = saved.removeLast();
        clip = restored.$1;
        blend = restored.$2;
      case PdfClipPathCommand(:final path):
        if (!FlutterGpuTileRasterBackend._isAxisAlignedRect(path)) {
          return (null, null, 'non-rectangular mask path clip');
        }
        clip = _pdfIntersection(clip, pdfRenderPathBounds(path));
      case PdfFillPathCommand():
        if (fill != null) return (null, null, 'mask contains multiple paths');
        if (blend != PdfBlendMode.normal) {
          return (null, null, 'mask path blend mode ${blend.name}');
        }
        fill = command;
        fillClip = clip;
      case PdfSetBlendModeCommand(:final mode):
        blend = mode;
      case PdfSetOverprintCommand():
        // A single mask element has no prior colorants to preserve.
        break;
      default:
        if (pdfRenderCommandBounds(command) != null) {
          return (null, null, 'mask contains ${command.runtimeType}');
        }
    }
  }
  if (saved.isNotEmpty) return (null, null, 'unbalanced mask path state');
  if (fill == null) return (null, null, 'mask has no path');
  return (fill, fillClip, null);
}

(List<_VectorMaskFill>?, String?) _vectorMaskFills(
    List<PdfRenderCommand> commands) {
  const maxFills = 32;
  final fills = <_VectorMaskFill>[];
  PdfRect? clip;
  var clipEmpty = false;
  var fillOverprint = false;
  var strokeOverprint = false;
  var overprintedFills = 0;
  final saved = <(PdfRect?, bool, bool, bool)>[];
  for (final command in commands) {
    switch (command) {
      case PdfSaveCommand():
        saved.add((clip, clipEmpty, fillOverprint, strokeOverprint));
      case PdfRestoreCommand():
        if (saved.isEmpty) return (null, 'unbalanced vector mask state');
        final restored = saved.removeLast();
        clip = restored.$1;
        clipEmpty = restored.$2;
        fillOverprint = restored.$3;
        strokeOverprint = restored.$4;
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
        if (fillOverprint) overprintedFills++;
        if (fills.length > maxFills) {
          return (null, 'vector mask fill count exceeds GPU cap');
        }
      case PdfSetBlendModeCommand(:final mode):
        if (mode != PdfBlendMode.normal) {
          return (null, 'vector mask blend mode ${mode.name}');
        }
      case PdfSetOverprintCommand(:final fill, :final stroke):
        fillOverprint = fill;
        strokeOverprint = stroke;
      default:
        if (pdfRenderCommandBounds(command) != null) {
          return (null, 'vector mask contains ${command.runtimeType}');
        }
    }
  }
  if (saved.isNotEmpty) return (null, 'unbalanced vector mask state');
  if (fills.isEmpty) return (null, 'vector mask has no fills');
  // Overprint has nothing to preserve for the only painted element in a
  // fresh mask group. With multiple fills it can change their interaction,
  // so that shape remains on Canvas.
  if (overprintedFills > 0 && fills.length > 1) {
    return (null, 'multi-fill vector mask overprint');
  }
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

bool _samePathClipStack(
  List<_GpuPathClip> a,
  List<_GpuPathClip> b,
) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (!identical(a[index].path, b[index].path) ||
        a[index].rule != b[index].rule) {
      return false;
    }
  }
  return true;
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

Rect _rasterAlignedRegion(
  PdfRect bounds,
  PdfMatrix pageToRaster,
  Rect tileRegion,
  double pixelRatio,
) {
  final points = <(double, double)>[
    (bounds.left, bounds.bottom),
    (bounds.right, bounds.bottom),
    (bounds.right, bounds.top),
    (bounds.left, bounds.top),
  ];
  var left = double.infinity, top = double.infinity;
  var right = double.negativeInfinity, bottom = double.negativeInfinity;
  for (final (x, y) in points) {
    final rx = pageToRaster.transformX(x, y);
    final ry = pageToRaster.transformY(x, y);
    if (rx < left) left = rx;
    if (rx > right) right = rx;
    if (ry < top) top = ry;
    if (ry > bottom) bottom = ry;
  }
  left = math.max(
    tileRegion.left,
    tileRegion.left +
        (((left - tileRegion.left) * pixelRatio).floor() / pixelRatio),
  );
  top = math.max(
    tileRegion.top,
    tileRegion.top +
        (((top - tileRegion.top) * pixelRatio).floor() / pixelRatio),
  );
  right = math.min(
    tileRegion.right,
    tileRegion.left +
        (((right - tileRegion.left) * pixelRatio).ceil() / pixelRatio),
  );
  bottom = math.min(
    tileRegion.bottom,
    tileRegion.top +
        (((bottom - tileRegion.top) * pixelRatio).ceil() / pixelRatio),
  );
  return Rect.fromLTRB(left, top, right, bottom);
}

bool _pdfIntersects(PdfRect a, PdfRect b) =>
    a.left < b.right &&
    a.right > b.left &&
    a.bottom < b.top &&
    a.top > b.bottom;

String? _compositeOverprintReason(
  PdfRenderCommand command,
  bool overprint,
) {
  if (!overprint) return null;
  return switch (command) {
    PdfFillMeshCommand() => 'mesh overprint',
    PdfFillPathGradientCommand() => 'gradient overprint',
    PdfDrawTextCommand(:final run) when run.gradient != null =>
      'gradient text overprint',
    _ when _commandNeedsDarken(command, true, true) =>
      'non-black overprint requires Canvas fallback',
    _ => null,
  };
}

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

String? _unsupportedTextReason(PdfTextRun run) {
  if (run.invisible) return null;
  final gradientReason = !run.fill || run.gradient == null
      ? null
      : _gradientUnsupportedReason(run.gradient!, run.fillAlpha);
  final reasons = <String>[
    if (run.glyphs == null) 'missing glyph outlines',
    if (gradientReason != null) gradientReason,
  ];
  return reasons.isEmpty ? null : 'unsupported text: ${reasons.join(', ')}';
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

/// Couples a successful denser re-recording to the GPU session built from it.
/// The original retained scene remains owned by the viewer for its base image
/// and ready Canvas fallback; this wrapper owns only the retry transcript.
class _RetriedSceneTileRasterSession
    implements
        PdfTileRasterSession,
        PdfTileRasterScheduling,
        PdfTileRasterWarmUp {
  _RetriedSceneTileRasterSession(this._session, this.scene) {
    assert(identical(_session.scene, scene));
  }

  final PdfTileRasterSession _session;

  @override
  final PdfRetainedScene scene;

  @override
  bool get batchAdjacentTiles => _session is PdfTileRasterScheduling
      ? (_session as PdfTileRasterScheduling).batchAdjacentTiles
      : true;

  @override
  int? get maxNewTilesPerPaint => _session is PdfTileRasterScheduling
      ? (_session as PdfTileRasterScheduling).maxNewTilesPerPaint
      : null;

  @override
  Future<void> warmUp() async {
    if (_session is PdfTileRasterWarmUp) {
      await (_session as PdfTileRasterWarmUp).warmUp();
    }
  }

  @override
  Future<ui.Image> rasterizeRegion(
    Rect region, {
    required double pixelRatio,
    int? tracePage,
  }) =>
      _session.rasterizeRegion(
        region,
        pixelRatio: pixelRatio,
        tracePage: tracePage,
      );

  @override
  void dispose() {
    try {
      _session.dispose();
    } finally {
      scene.dispose();
    }
  }
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
    required this.analyticText,
    required this.analyticTextMinimumGlyphs,
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
  final bool analyticText;
  final int analyticTextMinimumGlyphs;

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
        analyticText: analyticText,
        analyticTextMinimumGlyphs: analyticTextMinimumGlyphs,
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
      final coverageQuantum =
          msaa && context.doesSupportOffscreenMSAA ? 0.25 : 1.0;
      final deviceScale = _pageDeviceScale(compiled.pageToRaster, pixelRatio);
      var undersampledUnits = 0;
      double? narrowest;
      for (final unit in selected) {
        final width = unit.minimumPositiveStrokeWidth;
        if (width != null && width * deviceScale < coverageQuantum) {
          undersampledUnits++;
          if (narrowest == null || width < narrowest) narrowest = width;
        }
      }
      // Four-sample MSAA can represent coverage only in quarter-pixel
      // increments. Isolated thinner strokes stay within the established
      // Canvas parity tolerance, but dense CAD drawings accumulate hundreds
      // of missed strokes into material blank regions. Retire the accelerated
      // session before issuing a knowingly incomplete tile; the viewer serves
      // this request and all later LoDs from its exact Canvas fallback session.
      if (undersampledUnits >= 128) {
        final resolvedWidth = narrowest! * deviceScale;
        stats.subpixelStrokeFallbacks++;
        throw StateError(
          '$undersampledUnits paint units contain positive-width strokes that '
          'resolve as narrowly as ${resolvedWidth.toStringAsFixed(3)} device '
          'pixels, below the ${coverageQuantum.toStringAsFixed(2)} '
          'flutter_gpu coverage quantum',
        );
      }
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
    required this.straightStrokes,
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
      {required bool analyticText,
      required int analyticTextMinimumGlyphs,
      required bool mipmapImages}) async {
    final clock = Stopwatch()..start();
    final draws = <int, _GpuDraw>{};
    final straightStrokes = <int, _StraightStrokeFootprint>{};
    final clipDraws = Map<_GpuClipNode, _GpuClipDraw>.identity();
    final textureLeases = <_GpuImageTexture>[];
    final geometry = _GpuGeometryArena(context, stats, geometryPool);
    final pageToRaster = PdfPageRenderer.pageToDeviceMatrix(
      scene.page,
      scene.pageSize,
      scene.page.cropBox,
      rotation: scene.plan.rotation,
      pixelRatio: 1,
    );
    try {
      _GpuGlyphAtlas? glyphAtlas;
      if (analyticText) {
        try {
          glyphAtlas = _GpuGlyphAtlas.build(
            context,
            commands,
            units,
            stats,
            minimumGlyphs: analyticTextMinimumGlyphs,
          );
        } catch (_) {
          // This is a retained-geometry optimization, never a new reason for
          // an otherwise supported page to abandon the exact GPU route.
          stats.analyticAtlasFallbacks++;
        }
      }
      for (final unit in units) {
        final command = commands[unit.commandIndex];
        List<_GpuClipState>? offscreenPaintClips;
        if (unit.composite
            case _GroupPaintSpec(
              offscreen: true,
              :final contentPathClips,
              :final paintClips,
            ) when contentPathClips.isNotEmpty) {
          var commonState = unit.clip;
          for (final pathClip in contentPathClips) {
            commonState = _pushGpuClip(
              commonState,
              pathClip.path,
              pathClip.rule,
            );
          }
          offscreenPaintClips = [
            for (final paintClip in paintClips)
              _withGpuRectClip(commonState, paintClip),
          ];
          for (_GpuClipNode? node = commonState.node;
              node != null;
              node = node.previous) {
            final clipNode = node;
            clipDraws.putIfAbsent(
              clipNode,
              () => _compileClip(geometry, clipNode),
            );
          }
        }
        if (unit.composite == null && command is PdfStrokePathCommand) {
          final footprint = _straightStrokeFootprint(command);
          if (footprint != null) {
            straightStrokes[unit.commandIndex] = footprint;
          }
        }
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
            command,
            stats,
            imageCache,
            textureLeases,
            glyphAtlas,
            pageToRaster,
            mipmapImages: mipmapImages,
          );
          draw = pending is Future<_GpuDraw?> ? await pending : pending;
        } else {
          draw = switch (unit.composite!) {
            _GroupFillSpec spec => _compileGroupFill(geometry, spec),
            _GroupStrokeSpec spec => _compileGroupStroke(geometry, spec),
            _GroupTextSpec spec => _compileGroupText(geometry, spec),
            _GroupPaintSpec spec => await _compileGroupPaint(
                context,
                geometry,
                scene,
                spec,
                stats,
                imageCache,
                textureLeases,
                glyphAtlas,
                pageToRaster,
                paintClipStates: offscreenPaintClips,
                mipmapImages: mipmapImages,
              ),
            _KnockoutSoftMaskFillSpec spec =>
              _compileKnockoutSoftMaskFill(geometry, spec),
            _FlattenSoftMaskSpec() => null,
            _FlattenGroupSpec() => null,
            _EmptyGroupSpec() => null,
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
            _SoftMaskStrokeSpec spec => await _compileSoftMaskStroke(
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
            _SoftMaskGradientFillSpec spec =>
              _compileSoftMaskGradientFill(geometry, spec),
            _SoftMaskGradientStrokeSpec spec =>
              _compileSoftMaskGradientStroke(geometry, spec),
            _SoftMaskTextSpec spec => await _compileSoftMaskText(
                context,
                geometry,
                scene,
                spec,
                stats,
                imageCache,
                textureLeases,
                mipmapImages: mipmapImages,
              ),
            _SoftMaskGradientTextSpec spec =>
              _compileSoftMaskGradientText(geometry, spec),
            _SoftMaskGroupSpec spec => await _compileSoftMaskGroup(
                context,
                geometry,
                scene,
                spec,
                stats,
                imageCache,
                textureLeases,
                mipmapImages: mipmapImages,
              ),
          };
        }
        if (draw != null) draws[unit.commandIndex] = draw;
      }
      final paper = _paperDraw(geometry, scene, pageToRaster);
      geometry.finalize();
      final result = _CompiledScene(
        context: context,
        pageToRaster: pageToRaster,
        paper: paper,
        draws: draws,
        straightStrokes: straightStrokes,
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
  final _PaperDraw paper;
  final Map<int, _GpuDraw> draws;
  final Map<int, _StraightStrokeFootprint> straightStrokes;
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
    if (selected.isEmpty && _canClearPaper(region, pixelRatio)) {
      return _renderPaperOnly(
        width: width,
        height: height,
        tracePage: tracePage,
      );
    }
    if (selected.any((unit) =>
        !FlutterGpuTileRasterBackend._isFixedFunctionBlendMode(
            unit.blendMode))) {
      return _renderAdvanced(
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

  ui.Image _renderPaperOnly({
    required int width,
    required int height,
    int? tracePage,
  }) {
    final issue = Stopwatch()..start();
    final texture = context.createTexture(
      gpu.StorageMode.devicePrivate,
      width,
      height,
      format: context.defaultColorFormat,
    );
    final commandBuffer = context.createCommandBuffer();
    final pass = commandBuffer.createRenderPass(
      gpu.RenderTarget.singleColor(gpu.ColorAttachment(
        texture: texture,
        clearValue: paper.clearColor,
      )),
    );
    final retained = <Object>[texture, commandBuffer, pass];
    final submit = Stopwatch()..start();
    final completion = Stopwatch()..start();
    _inFlight++;
    stats
      ..paperClearTiles += 1
      ..paperOnlyTiles += 1
      ..inFlightSubmissions += 1
      ..peakInFlightSubmissions = math.max(
        stats.peakInFlightSubmissions,
        stats.inFlightSubmissions,
      );
    try {
      commandBuffer.submit(completionCallback: (success) {
        retained.length;
        _completeSubmission(
          success,
          completion,
          tracePage,
          width,
          height,
          0,
        );
      });
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
    return texture.asImage();
  }

  PdfRect _rasterFootprintBounds(
    _GpuUnit unit,
    _GpuDraw? draw,
    double pixelRatio,
  ) {
    final hairlinePadding = math.max(
      0.0,
      0.5 / _pageDeviceScale(pageToRaster, pixelRatio) - 2,
    );
    final extraPadding = draw is _OffscreenGroupDraw
        ? math.max(draw.extraPadding, hairlinePadding)
        : unit.hairline
            ? hairlinePadding
            : 0.0;
    return extraPadding == 0
        ? unit.bounds
        : _inflatePdf(unit.bounds, extraPadding);
  }

  bool _canClearPaper(Rect region, double pixelRatio) {
    // A render-pass clear cannot reproduce the paper quad's antialiased crop
    // edge. Keep one device pixel between the tile and every transformed page
    // edge so the clear is used only where the quad has constant full coverage.
    final margin = 1 / pixelRatio;
    final bounds = paper.rasterBounds;
    return region.left >= bounds.left + margin &&
        region.top >= bounds.top + margin &&
        region.right <= bounds.right - margin &&
        region.bottom <= bounds.bottom - margin;
  }

  ({
    Map<int, (gpu.Texture, Rect)> textures,
    List<gpu.Texture> retained,
  }) _renderOffscreenGroups(
    List<_GpuUnit> selected, {
    required Rect region,
    required double pixelRatio,
    required _GpuPipelines pipelines,
    required int width,
    required int height,
    required _GpuTransientArena transient,
    int maxBytes = 256 << 20,
  }) {
    Rect groupRegionFor(_GpuUnit unit, _OffscreenGroupDraw draw) {
      final bounds = _rasterFootprintBounds(unit, draw, pixelRatio);
      return _rasterAlignedRegion(
        bounds,
        pageToRaster,
        region,
        pixelRatio,
      );
    }

    final groupPlans = <(_GpuUnit, _OffscreenGroupDraw, Rect, int, int, int)>[];
    var offscreenBytes = 0;
    for (final unit in selected) {
      final draw = draws[unit.commandIndex];
      if (draw is! _OffscreenGroupDraw) continue;
      final groupRegion = groupRegionFor(unit, draw);
      final groupWidth =
          (groupRegion.width * pixelRatio).ceil().clamp(1, width);
      final groupHeight =
          (groupRegion.height * pixelRatio).ceil().clamp(1, height);
      // The resolved RGBA + stencil pair is about 8 B/px. The intermediate
      // stays single-sample: it is sampled through the final page pass, and a
      // second 4x color+stencil raster plus resolve makes visual settle slower
      // than Canvas for ordinary groups. Bound all live intermediates so a
      // pathological page falls back instead of multiplying a deep-zoom tile
      // into an OOM.
      final estimatedBytes = groupWidth * groupHeight * 8;
      offscreenBytes += estimatedBytes;
      if (offscreenBytes > maxBytes) {
        stats.offscreenGroupBudgetFallbacks++;
        throw StateError('offscreen group tiles exceed the route budget');
      }
      groupPlans.add((
        unit,
        draw,
        groupRegion,
        groupWidth,
        groupHeight,
        estimatedBytes,
      ));
    }

    final groupTextures = <int, (gpu.Texture, Rect)>{};
    final retainedGroupTextures = <gpu.Texture>[];
    for (final plan in groupPlans) {
      final (unit, draw, groupRegion, groupWidth, groupHeight, estimatedBytes) =
          plan;
      final groupResolve = context.createTexture(
        gpu.StorageMode.devicePrivate,
        groupWidth,
        groupHeight,
        format: context.defaultColorFormat,
      );
      final groupStencil = context.createTexture(
        gpu.StorageMode.deviceTransient,
        groupWidth,
        groupHeight,
        format: context.defaultStencilFormat,
        sampleCount: 1,
      );
      final groupAttachments = <gpu.Texture>[groupResolve, groupStencil];
      retainedGroupTextures.addAll(groupAttachments);
      final groupCommandBuffer = context.createCommandBuffer();
      final backdropColor = draw.backdropColor;
      final groupPass = groupCommandBuffer.createRenderPass(gpu.RenderTarget(
        colorAttachments: [
          gpu.ColorAttachment(
            texture: groupResolve,
            clearValue: backdropColor == null
                ? vm.Vector4.zero()
                : vm.Vector4(
                    backdropColor.red,
                    backdropColor.green,
                    backdropColor.blue,
                    1,
                  ),
          ),
        ],
        depthStencilAttachment: gpu.DepthStencilAttachment(
          texture: groupStencil,
          stencilClearValue: 0,
        ),
      ))
        ..setCullMode(gpu.CullMode.none)
        ..setWindingOrder(gpu.WindingOrder.counterClockwise)
        ..setPrimitiveType(gpu.PrimitiveType.triangle)
        ..setStencilReference(0)
        ..setColorBlendEnable(true);
      final groupEncoder = _GpuEncoder(
        pass: groupPass,
        pipelines: pipelines,
        transform: transient.emplace(_tileTransform(
          pageToRaster,
          groupRegion,
          pixelRatio,
          groupWidth,
          groupHeight,
        )),
        pageToRaster: pageToRaster,
        region: groupRegion,
        pixelRatio: pixelRatio,
        width: groupWidth,
        height: groupHeight,
        clipDraws: clipDraws,
        stencilClear: paper.vertices,
        emplaceTransient: transient.emplace,
      );
      for (final paint in draw.paints) {
        groupEncoder.setClip(
          paint.$5 ?? _withGpuRectClip(unit.clip, paint.$2),
        );
        if (paint.$4) {
          groupEncoder.setSourceBlend();
        } else {
          groupEncoder.setBlendMode(paint.$3);
        }
        paint.$1.encode(groupEncoder);
      }
      stats.clipMaskRebuilds += groupEncoder.clipMaskRebuilds;
      final groupResources = <Object>[
        ...groupAttachments,
        groupPass,
        transient,
      ];
      transient.flush();
      groupCommandBuffer.submit(completionCallback: (_) {
        // The page completion owns the textures on the success path. This
        // independent capture also fences every submitted group resource if a
        // later allocation or the final page submission throws.
        groupResources.length;
      });
      stats
        ..offscreenGroupPasses += 1
        ..offscreenGroupAllocatedBytes += estimatedBytes;
      groupTextures[unit.commandIndex] = (groupResolve, groupRegion);
    }
    stats.peakOffscreenGroupBytes =
        math.max(stats.peakOffscreenGroupBytes, offscreenBytes);
    return (textures: groupTextures, retained: retainedGroupTextures);
  }

  ui.Image _renderAdvanced(
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
    PdfRect? advancedBounds;
    for (final unit in selected) {
      if (!FlutterGpuTileRasterBackend._isFixedFunctionBlendMode(
          unit.blendMode)) {
        advancedBounds = _pdfUnion(
          advancedBounds,
          _rasterFootprintBounds(
            unit,
            draws[unit.commandIndex],
            pixelRatio,
          ),
        );
      }
    }
    final candidateSourceRegion = _rasterAlignedRegion(
      advancedBounds!,
      pageToRaster,
      region,
      pixelRatio,
    );
    final candidateSourceWidth =
        (candidateSourceRegion.width * pixelRatio).ceil().clamp(1, width);
    final candidateSourceHeight =
        (candidateSourceRegion.height * pixelRatio).ceil().clamp(1, height);
    final tilePixels = width * height;
    final candidateSourcePixels = candidateSourceWidth * candidateSourceHeight;
    // A cropped source needs its own color/stencil attachments while page
    // ping-pong keeps reusing the full-tile pair. Use it only when the bounded
    // source is at most half the tile, so both allocation and clear/raster
    // work are lower even after those extra attachments are counted.
    final cropSource = candidateSourcePixels * 2 <= tilePixels &&
        (candidateSourceWidth < width || candidateSourceHeight < height);
    final sourceRegion = cropSource ? candidateSourceRegion : region;
    final sourceWidth = cropSource ? candidateSourceWidth : width;
    final sourceHeight = cropSource ? candidateSourceHeight : height;
    final sourcePixels = sourceWidth * sourceHeight;
    // Two page ping-pong targets plus their shared color/stencil attachments
    // are conservatively 32 B/px with 4x MSAA (12 B/px without it). A cropped
    // source carries its own resolve/color/stencil set at 24 B/px (8 B/px
    // without MSAA). The full-source path keeps the historical shared
    // attachment estimate. Reject before allocating so Canvas can recover
    // from an unusual deep-zoom tile without a multi-gigabyte GPU allocation.
    final estimatedBytes = cropSource
        ? tilePixels * (multisampled ? 32 : 12) +
            sourcePixels * (multisampled ? 24 : 8)
        : tilePixels * (multisampled ? 48 : 16);
    if (estimatedBytes > (256 << 20)) {
      stats.advancedBlendBudgetFallbacks++;
      throw StateError('advanced blend tiles exceed 256 MiB');
    }
    stats
      ..advancedBlendCroppedSources += cropSource ? 1 : 0
      ..advancedBlendAllocatedBytes += estimatedBytes
      ..peakAdvancedBlendBytes =
          math.max(stats.peakAdvancedBlendBytes, estimatedBytes);
    gpu.Texture texture(int textureWidth, int textureHeight) =>
        context.createTexture(
          gpu.StorageMode.devicePrivate,
          textureWidth,
          textureHeight,
          format: context.defaultColorFormat,
        );

    final pageA = texture(width, height);
    final pageB = texture(width, height);
    final source = texture(sourceWidth, sourceHeight);
    final color = multisampled
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
    final sourceColor = cropSource && multisampled
        ? context.createTexture(
            gpu.StorageMode.deviceTransient,
            sourceWidth,
            sourceHeight,
            format: context.defaultColorFormat,
            sampleCount: 4,
          )
        : color;
    final sourceStencil = cropSource
        ? context.createTexture(
            gpu.StorageMode.deviceTransient,
            sourceWidth,
            sourceHeight,
            format: context.defaultStencilFormat,
            sampleCount: multisampled ? 4 : 1,
          )
        : stencil;
    final transient = _GpuTransientArena(context, stats);
    final groups = _renderOffscreenGroups(
      selected,
      region: region,
      pixelRatio: pixelRatio,
      pipelines: pipelines,
      width: width,
      height: height,
      transient: transient,
      // Keep page ping-pong and every simultaneously live group attachment
      // inside one route-wide budget rather than allowing two independent
      // 256 MiB pools.
      maxBytes: (256 << 20) - estimatedBytes,
    );
    final commandBuffers = <gpu.CommandBuffer>[];
    final retained = <Object>[
      pageA,
      pageB,
      source,
      if (color != null) color,
      stencil,
      if (cropSource && sourceColor != null) sourceColor,
      if (cropSource) sourceStencil,
      transient,
      ...groups.retained,
      commandBuffers,
    ];

    gpu.RenderPass createPaintPass(
      gpu.CommandBuffer commandBuffer,
      gpu.Texture resolve,
      gpu.Texture? targetColor,
      gpu.Texture targetStencil, {
      vm.Vector4? clearValue,
    }) {
      final target = targetColor ?? resolve;
      final pass = commandBuffer.createRenderPass(gpu.RenderTarget(
        colorAttachments: [
          gpu.ColorAttachment(
            texture: target,
            resolveTexture: multisampled ? resolve : null,
            clearValue: clearValue ?? vm.Vector4.zero(),
            storeAction: multisampled
                ? gpu.StoreAction.multisampleResolve
                : gpu.StoreAction.store,
          ),
        ],
        depthStencilAttachment: gpu.DepthStencilAttachment(
          texture: targetStencil,
          stencilClearValue: 0,
        ),
      ));
      return pass
        ..setCullMode(gpu.CullMode.none)
        ..setWindingOrder(gpu.WindingOrder.counterClockwise)
        ..setPrimitiveType(gpu.PrimitiveType.triangle)
        ..setStencilReference(0)
        ..setColorBlendEnable(true);
    }

    _GpuEncoder encoderFor(
      gpu.RenderPass pass, {
      required Rect targetRegion,
      required int targetWidth,
      required int targetHeight,
    }) =>
        _GpuEncoder(
          pass: pass,
          pipelines: pipelines,
          transform: transient.emplace(_tileTransform(
            pageToRaster,
            targetRegion,
            pixelRatio,
            targetWidth,
            targetHeight,
          )),
          pageToRaster: pageToRaster,
          region: targetRegion,
          pixelRatio: pixelRatio,
          width: targetWidth,
          height: targetHeight,
          clipDraws: clipDraws,
          stencilClear: paper.vertices,
          emplaceTransient: transient.emplace,
        );

    gpu.Texture? current;
    gpu.Texture alternate() => identical(current, pageA) ? pageB : pageA;

    void paintSegment(List<_GpuUnit> segment) {
      final target = alternate();
      final commandBuffer = context.createCommandBuffer();
      final clearPaper = current == null && _canClearPaper(region, pixelRatio);
      if (clearPaper) stats.paperClearTiles++;
      final encoder = encoderFor(
        createPaintPass(
          commandBuffer,
          target,
          color,
          stencil,
          clearValue: clearPaper ? paper.clearColor : null,
        ),
        targetRegion: region,
        targetWidth: width,
        targetHeight: height,
      );
      if (current == null) {
        if (!clearPaper) {
          encoder
            ..setClip(_rootGpuClip)
            ..setSourceBlend()
            ..solid(paper.vertices);
        }
      } else {
        encoder
          ..setClip(_rootGpuClip)
          ..setSourceBlend()
          ..tileTexture(current!, region, 1);
      }
      for (final unit in segment) {
        final draw = draws[unit.commandIndex];
        if (draw == null) continue;
        if (draw is _OffscreenGroupDraw) {
          final group = groups.textures[unit.commandIndex]!;
          encoder
            ..setClip(unit.clip)
            ..setBlendMode(unit.blendMode)
            ..tileTexture(group.$1, group.$2, draw.alpha);
          continue;
        }
        encoder
          ..setClip(unit.clip)
          ..setBlendMode(unit.blendMode);
        draw.encode(encoder);
      }
      stats.clipMaskRebuilds += encoder.clipMaskRebuilds;
      commandBuffers.add(commandBuffer);
      retained.add(encoder.pass);
      current = target;
    }

    void paintSources(List<_GpuUnit> units) {
      final sourceCommandBuffer = context.createCommandBuffer();
      final sourceEncoder = encoderFor(
        createPaintPass(
          sourceCommandBuffer,
          source,
          sourceColor,
          sourceStencil,
        ),
        targetRegion: sourceRegion,
        targetWidth: sourceWidth,
        targetHeight: sourceHeight,
      );
      for (final unit in units) {
        final draw = draws[unit.commandIndex];
        if (draw == null) continue;
        if (draw is _OffscreenGroupDraw) {
          final group = groups.textures[unit.commandIndex]!;
          sourceEncoder
            ..setClip(unit.clip)
            ..setBlendMode(PdfBlendMode.normal)
            ..tileTexture(group.$1, group.$2, draw.alpha);
          continue;
        }
        sourceEncoder
          ..setClip(unit.clip)
          ..setBlendMode(PdfBlendMode.normal);
        draw.encode(sourceEncoder);
      }
      stats.clipMaskRebuilds += sourceEncoder.clipMaskRebuilds;
      commandBuffers.add(sourceCommandBuffer);
      retained.add(sourceEncoder.pass);
    }

    void blendSources(List<(_GpuUnit, PdfRect?)> units) {
      final target = alternate();
      final blendCommandBuffer = context.createCommandBuffer();
      // Preserve the untouched destination with a native texture copy. The
      // old full-tile textured draw spent fragment work rewriting every pixel
      // before the bounded advanced-blend shader could touch its small dirty
      // region. A blit is byte-exact and leaves the render pass free to load
      // the copied target and shade only those conservative command bounds.
      blendCommandBuffer.copyTextureToTexture(
        gpu.TextureRegion(current!),
        gpu.TextureDestinationRegion(target),
      );
      final blendPass = blendCommandBuffer.createRenderPass(
        gpu.RenderTarget.singleColor(gpu.ColorAttachment(
          texture: target,
          loadAction: gpu.LoadAction.load,
        )),
      )
        ..setCullMode(gpu.CullMode.none)
        ..setWindingOrder(gpu.WindingOrder.counterClockwise)
        ..setPrimitiveType(gpu.PrimitiveType.triangle)
        ..setColorBlendEnable(false);
      final blendEncoder = encoderFor(
        blendPass,
        targetRegion: region,
        targetWidth: width,
        targetHeight: height,
      );
      for (final (unit, bounds) in units) {
        blendEncoder.advancedBlend(
          current!,
          source,
          sourceRegion,
          unit.blendMode,
          bounds,
        );
      }
      commandBuffers.add(blendCommandBuffer);
      retained.add(blendPass);
      current = target;
      stats
        ..advancedBlendPasses += 1
        ..advancedBlendBlits += 1;
    }

    bool overlaps(PdfRect a, PdfRect b) =>
        a.left < b.right &&
        a.right > b.left &&
        a.bottom < b.top &&
        a.top > b.bottom;

    final deviceScale = _pageDeviceScale(pageToRaster, pixelRatio);
    bool rasterDisjoint(_GpuUnit a, _GpuUnit b) {
      if (!overlaps(a.bounds, b.bounds)) return true;
      final aStroke = straightStrokes[a.commandIndex];
      final bStroke = straightStrokes[b.commandIndex];
      return aStroke != null &&
          bStroke != null &&
          _straightStrokesAreRasterDisjoint(
            aStroke,
            bStroke,
            deviceScale,
          );
    }

    final advanced = <(int, _GpuUnit, PdfRect)>[];
    for (var i = 0; i < selected.length; i++) {
      final unit = selected[i];
      if (!FlutterGpuTileRasterBackend._isFixedFunctionBlendMode(
          unit.blendMode)) {
        advanced.add((i, unit, unit.bounds));
      }
    }
    var batchable =
        advanced.length > 1 && advanced.every((item) => !item.$2.hairline);
    for (var i = 0; batchable && i < advanced.length; i++) {
      for (var j = i + 1; j < advanced.length; j++) {
        if (overlaps(advanced[i].$3, advanced[j].$3)) {
          batchable = false;
          break;
        }
      }
      for (var j = advanced[i].$1 + 1; batchable && j < selected.length; j++) {
        final later = selected[j];
        if (FlutterGpuTileRasterBackend._isFixedFunctionBlendMode(
                later.blendMode) &&
            overlaps(advanced[i].$3, later.bounds)) {
          batchable = false;
        }
      }
    }

    if (batchable) {
      paintSegment([
        for (final unit in selected)
          if (FlutterGpuTileRasterBackend._isFixedFunctionBlendMode(
              unit.blendMode))
            unit,
      ]);
      final units = [for (final item in advanced) item.$2];
      paintSources(units);
      blendSources([
        for (final item in advanced) (item.$2, item.$3),
      ]);
    } else {
      var index = 0;
      while (index < selected.length) {
        final start = index;
        while (index < selected.length &&
            FlutterGpuTileRasterBackend._isFixedFunctionBlendMode(
                selected[index].blendMode)) {
          index++;
        }
        if (start != index || current == null) {
          paintSegment(selected.sublist(start, index));
        }
        if (index < selected.length) {
          final first = selected[index];
          final firstFootprint = straightStrokes[first.commandIndex];
          var batchEnd = index + 1;
          if (firstFootprint != null) {
            while (batchEnd < selected.length) {
              final candidate = selected[batchEnd];
              if (FlutterGpuTileRasterBackend._isFixedFunctionBlendMode(
                      candidate.blendMode) ||
                  candidate.blendMode != first.blendMode ||
                  straightStrokes[candidate.commandIndex] == null) {
                break;
              }
              var disjoint = true;
              for (var previous = index; previous < batchEnd; previous++) {
                if (!rasterDisjoint(selected[previous], candidate)) {
                  disjoint = false;
                  break;
                }
              }
              if (!disjoint) break;
              batchEnd++;
            }
          }
          final sources = selected.sublist(index, batchEnd);
          paintSources(sources);
          if (sources.length == 1) {
            blendSources([(first, first.bounds)]);
          } else {
            var blendBounds = first.bounds;
            for (final source in sources.skip(1)) {
              blendBounds = _pdfUnion(blendBounds, source.bounds);
            }
            // No resolved source pixel contains coverage from two strokes.
            // Their common blend can therefore run exactly once over the
            // union, including the transparent gaps between them.
            blendSources([(first, blendBounds)]);
          }
          index = batchEnd;
        }
      }
    }

    final submit = Stopwatch()..start();
    final completion = Stopwatch()..start();
    _inFlight++;
    stats
      ..inFlightSubmissions += 1
      ..peakInFlightSubmissions = math.max(
        stats.peakInFlightSubmissions,
        stats.inFlightSubmissions,
      );
    transient.flush();
    try {
      for (var i = 0; i < commandBuffers.length; i++) {
        final last = i == commandBuffers.length - 1;
        commandBuffers[i].submit(completionCallback: (success) {
          retained.length;
          if (last) {
            _completeSubmission(
              success,
              completion,
              tracePage,
              width,
              height,
              selected.length,
            );
          }
        });
      }
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
    return current!.asImage();
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
    final transient = _GpuTransientArena(context, stats);

    gpu.RenderPass createPass(
      gpu.CommandBuffer commandBuffer,
      gpu.Texture target,
      gpu.Texture stencilTarget, {
      gpu.Texture? resolveTarget,
      vm.Vector4? clearValue,
    }) {
      final pass = commandBuffer.createRenderPass(gpu.RenderTarget(
        colorAttachments: [
          gpu.ColorAttachment(
            texture: target,
            resolveTexture: resolveTarget,
            clearValue: clearValue ?? vm.Vector4.zero(),
            storeAction: resolveTarget == null
                ? gpu.StoreAction.store
                : gpu.StoreAction.multisampleResolve,
          ),
        ],
        depthStencilAttachment: gpu.DepthStencilAttachment(
          texture: stencilTarget,
          stencilClearValue: 0,
        ),
      ));
      return pass
        ..setCullMode(gpu.CullMode.none)
        ..setWindingOrder(gpu.WindingOrder.counterClockwise)
        ..setPrimitiveType(gpu.PrimitiveType.triangle)
        ..setStencilReference(0)
        ..setColorBlendEnable(true);
    }

    _GpuEncoder encoderFor(
      gpu.RenderPass pass, {
      required Rect targetRegion,
      required int targetWidth,
      required int targetHeight,
    }) =>
        _GpuEncoder(
          pass: pass,
          pipelines: pipelines,
          transform: transient.emplace(_tileTransform(
            pageToRaster,
            targetRegion,
            pixelRatio,
            targetWidth,
            targetHeight,
          )),
          pageToRaster: pageToRaster,
          region: targetRegion,
          pixelRatio: pixelRatio,
          width: targetWidth,
          height: targetHeight,
          clipDraws: clipDraws,
          stencilClear: paper.vertices,
          emplaceTransient: transient.emplace,
        );

    final groups = _renderOffscreenGroups(
      selected,
      region: region,
      pixelRatio: pixelRatio,
      pipelines: pipelines,
      width: width,
      height: height,
      transient: transient,
    );
    final groupTextures = groups.textures;
    final retainedGroupTextures = groups.retained;

    final commandBuffer = context.createCommandBuffer();
    final clearPaper = _canClearPaper(region, pixelRatio);
    if (clearPaper) stats.paperClearTiles++;
    final pass = createPass(
      commandBuffer,
      color,
      stencil,
      resolveTarget: multisampled ? resolve : null,
      clearValue: clearPaper ? paper.clearColor : null,
    );
    final encoder = encoderFor(
      pass,
      targetRegion: region,
      targetWidth: width,
      targetHeight: height,
    );
    if (!clearPaper) {
      encoder
        ..setClip(_rootGpuClip)
        ..solid(paper.vertices);
    }
    for (final unit in selected) {
      final draw = draws[unit.commandIndex];
      if (draw == null) continue;
      encoder
        ..setClip(unit.clip)
        ..setBlendMode(unit.blendMode);
      if (draw is _OffscreenGroupDraw) {
        final group = groupTextures[unit.commandIndex]!;
        encoder.tileTexture(group.$1, group.$2, draw.alpha);
      } else {
        draw.encode(encoder);
      }
    }
    stats.clipMaskRebuilds += encoder.clipMaskRebuilds;
    transient.flush();
    final retained = <Object>[
      resolve,
      color,
      stencil,
      transient,
      ...retainedGroupTextures,
      commandBuffer,
      pass,
    ];
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
        completionCallback: (success) {
          // Keep every intermediate attachment alive until the command buffer
          // has finished sampling it into the page target.
          retained.length;
          _completeSubmission(
            success,
            completion,
            tracePage,
            width,
            height,
            selected.length,
          );
        },
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

_PaperDraw _paperDraw(
  _GpuGeometryArena geometry,
  PdfRetainedScene scene,
  PdfMatrix pageToRaster,
) {
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
  final corners = <(double, double)>[
    (box.left, box.bottom),
    (box.right, box.bottom),
    (box.right, box.top),
    (box.left, box.top),
  ];
  var left = double.infinity, top = double.infinity;
  var right = double.negativeInfinity, bottom = double.negativeInfinity;
  for (final (x, y) in corners) {
    final rx = pageToRaster.transformX(x, y);
    final ry = pageToRaster.transformY(x, y);
    if (rx < left) left = rx;
    if (rx > right) right = rx;
    if (ry < top) top = ry;
    if (ry > bottom) bottom = ry;
  }
  return _PaperDraw(
    geometry.add(vertices.bytes, 6),
    vm.Vector4(rgba[0], rgba[1], rgba[2], rgba[3]),
    Rect.fromLTRB(left, top, right, bottom),
  );
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

_GpuDraw? _compileGroupText(_GpuGeometryArena geometry, _GroupTextSpec spec) =>
    _compileGroupTextRun(
      geometry,
      spec.content.run,
      alphaScale: spec.groupAlpha,
    );

_GpuDraw? _compileGroupTextRun(
  _GpuGeometryArena geometry,
  PdfTextRun run, {
  double alphaScale = 1,
}) {
  if (run.invisible) return null;
  final subpaths = _textSubpaths(run)!;
  final gradient = run.gradient;
  final fill = !run.fill
      ? null
      : gradient != null
          ? _compileGradientSubpaths(
              geometry,
              subpaths,
              PdfFillRule.nonzero,
              gradient,
              (run.fillAlpha * alphaScale).clamp(0.0, 1.0),
            )
          : _stencilDraw(
              geometry,
              subpaths,
              run.color,
              (run.fillAlpha * alphaScale).clamp(0.0, 1.0),
              PdfFillRule.nonzero,
              false,
            );
  final strokeColor = run.strokeColor;
  final stroke = strokeColor == null
      ? null
      : _compileStrokeSubpaths(
          geometry,
          subpaths,
          strokeColor,
          PdfStroke(width: run.strokeWidth, miterLimit: 4),
          (run.strokeAlpha * alphaScale).clamp(0.0, 1.0),
        );
  return switch ((fill, stroke)) {
    (null, null) => null,
    (final _GpuDraw draw, null) || (null, final _GpuDraw draw) => draw,
    (final _GpuDraw fill, final _GpuDraw stroke) =>
      _SequenceDraw([fill, stroke]),
  };
}

Future<_GpuDraw?> _compileGroupPaint(
  gpu.GpuContext context,
  _GpuGeometryArena geometry,
  PdfRetainedScene scene,
  _GroupPaintSpec spec,
  FlutterGpuTileBackendStats stats,
  _GpuImageCache imageCache,
  List<_GpuImageTexture> textureLeases,
  _GpuGlyphAtlas? glyphAtlas,
  PdfMatrix pageToRaster, {
  List<_GpuClipState>? paintClipStates,
  required bool mipmapImages,
}) async {
  final draws = <(_GpuDraw, PdfRect?, PdfBlendMode, bool, _GpuClipState?)>[];
  var paintPadding = 2.0;
  for (var index = 0; index < spec.commands.length; index++) {
    final command = spec.commands[index];
    if (command case PdfStrokePathCommand(:final stroke)
        when stroke.width > 0) {
      final joinScale = stroke.join == 0 ? stroke.miterLimit : 1.0;
      paintPadding = math.max(
        paintPadding,
        stroke.width * joinScale / 2 + 2,
      );
    }
    final alphaScale = spec.paintAlphaScales[index] ?? 1;
    final _GpuDraw? draw;
    if (command case PdfDrawImageCommand(:final request) when alphaScale != 1) {
      draw = await _compileImageCommand(
        context,
        geometry,
        scene,
        request,
        stats,
        imageCache,
        textureLeases,
        alphaScale: alphaScale,
        mipmapImages: mipmapImages,
      );
    } else {
      draw = await _compileCommand(
        context,
        geometry,
        scene,
        command,
        stats,
        imageCache,
        textureLeases,
        glyphAtlas,
        pageToRaster,
        mipmapImages: mipmapImages,
      );
    }
    if (draw != null) {
      draws.add((
        draw,
        spec.paintClips[index],
        spec.paintBlends[index],
        spec.knockout && index > 0,
        paintClipStates?[index],
      ));
    }
  }
  if (draws.isEmpty) return null;
  return spec.offscreen
      ? _OffscreenGroupDraw(
          List.unmodifiable(draws),
          spec.groupAlpha,
          math.max(0, paintPadding - 2),
          backdropColor: spec.backdropColor,
        )
      : _SequenceDraw(List.unmodifiable([for (final draw in draws) draw.$1]));
}

_GpuDraw? _compileKnockoutSoftMaskFill(
  _GpuGeometryArena geometry,
  _KnockoutSoftMaskFillSpec spec,
) {
  final base = spec.base;
  final baseDraw = _stencilDraw(
    geometry,
    flattenPath(base.path, PdfMatrix.identity, tolerance: 0.01),
    base.color,
    base.alpha,
    base.rule,
    false,
  );
  final maskedDraw = _compileSoftMaskVectorFill(geometry, spec.masked);
  final paints = <(_GpuDraw, PdfRect?, PdfBlendMode, bool, _GpuClipState?)>[
    if (baseDraw != null)
      (baseDraw, spec.baseClip, PdfBlendMode.normal, false, null),
    if (maskedDraw != null)
      (
        maskedDraw,
        spec.masked.contentClip,
        PdfBlendMode.normal,
        false,
        null,
      ),
  ];
  if (paints.isEmpty) return null;
  return _OffscreenGroupDraw(
    paints,
    spec.groupAlpha,
    0,
  );
}

Future<_GpuDraw?> _compileSoftMaskGroup(
  gpu.GpuContext context,
  _GpuGeometryArena geometry,
  PdfRetainedScene scene,
  _SoftMaskGroupSpec spec,
  FlutterGpuTileBackendStats stats,
  _GpuImageCache imageCache,
  List<_GpuImageTexture> textureLeases, {
  required bool mipmapImages,
}) async {
  final content = spec.content;
  final _GpuDraw? draw;
  switch (content) {
    case _SoftMaskImageSpec():
      draw = await _compileSoftMaskImage(
        context,
        geometry,
        scene,
        content,
        stats,
        imageCache,
        textureLeases,
        mipmapImages: mipmapImages,
      );
    case _SoftMaskFillSpec():
      draw = await _compileSoftMaskFill(
        context,
        geometry,
        scene,
        content,
        stats,
        imageCache,
        textureLeases,
        mipmapImages: mipmapImages,
      );
    case _SoftMaskStrokeSpec():
      draw = await _compileSoftMaskStroke(
        context,
        geometry,
        scene,
        content,
        stats,
        imageCache,
        textureLeases,
        mipmapImages: mipmapImages,
      );
    case _SoftMaskVectorFillSpec():
      draw = _compileSoftMaskVectorFill(geometry, content);
    case _SoftMaskGradientFillSpec():
      draw = _compileSoftMaskGradientFill(geometry, content);
    case _SoftMaskGradientStrokeSpec():
      draw = _compileSoftMaskGradientStroke(geometry, content);
    case _SoftMaskTextSpec():
      draw = await _compileSoftMaskText(
        context,
        geometry,
        scene,
        content,
        stats,
        imageCache,
        textureLeases,
        mipmapImages: mipmapImages,
      );
    case _SoftMaskGradientTextSpec():
      draw = _compileSoftMaskGradientText(geometry, content);
    default:
      return null;
  }
  if (draw == null) return null;
  return _OffscreenGroupDraw(
    [(draw, null, PdfBlendMode.normal, false, null)],
    spec.groupAlpha,
    0,
  );
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

Future<_GpuDraw> _compileSoftMaskStroke(
    gpu.GpuContext context,
    _GpuGeometryArena geometry,
    PdfRetainedScene scene,
    _SoftMaskStrokeSpec spec,
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
  final source = flattenPath(
    spec.content.path,
    PdfMatrix.identity,
    tolerance: 0.01,
  );
  final subpaths = _prepareStrokeSubpaths(source, spec.content.stroke);
  final stencil = _stencilGeometry(
    geometry,
    _strokeRings(subpaths, spec.content.stroke),
  );
  if (stencil == null) throw StateError('empty soft-mask stroke path');
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
    PdfFillRule.nonzero,
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

Future<_GpuDraw> _compileSoftMaskText(
    gpu.GpuContext context,
    _GpuGeometryArena geometry,
    PdfRetainedScene scene,
    _SoftMaskTextSpec spec,
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
  final subpaths = _textSubpaths(spec.content.run)!;
  final stencil = _stencilGeometry(geometry, subpaths);
  if (stencil == null) throw StateError('empty soft-mask text outline');
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
    PdfFillRule.nonzero,
    maskResource.texture,
    _softMaskInfo(
      context,
      maskTransform: spec.mask.transform,
      contentTint: _premul(spec.content.run.color, spec.content.run.fillAlpha),
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

_GpuDraw? _compileSoftMaskGradientFill(
  _GpuGeometryArena geometry,
  _SoftMaskGradientFillSpec spec,
) {
  final subpaths = flattenPath(
    spec.content.path,
    PdfMatrix.identity,
    tolerance: 0.01,
  );
  final maskAlpha = spec.mask.alpha.clamp(0.0, 1.0);
  return _compileGradientSubpaths(
    geometry,
    subpaths,
    spec.content.rule,
    spec.mask.gradient,
    1,
    vertexColor: (maskColor) {
      final mask = spec.luminosity
          ? (0.2126 * maskColor.red +
                  0.7152 * maskColor.green +
                  0.0722 * maskColor.blue) *
              maskAlpha
          : maskAlpha;
      return _premul(
        spec.content.color,
        (spec.content.alpha * mask).clamp(0.0, 1.0),
      );
    },
  );
}

_GpuDraw? _compileSoftMaskGradientStroke(
  _GpuGeometryArena geometry,
  _SoftMaskGradientStrokeSpec spec,
) {
  final source = flattenPath(
    spec.content.path,
    PdfMatrix.identity,
    tolerance: 0.01,
  );
  final subpaths = _prepareStrokeSubpaths(source, spec.content.stroke);
  final maskAlpha = spec.mask.alpha.clamp(0.0, 1.0);
  return _compileGradientSubpaths(
    geometry,
    _strokeRings(subpaths, spec.content.stroke),
    PdfFillRule.nonzero,
    spec.mask.gradient,
    1,
    vertexColor: (maskColor) {
      final mask = spec.luminosity
          ? (0.2126 * maskColor.red +
                  0.7152 * maskColor.green +
                  0.0722 * maskColor.blue) *
              maskAlpha
          : maskAlpha;
      return _premul(
        spec.content.color,
        (spec.content.alpha * mask).clamp(0.0, 1.0),
      );
    },
  );
}

_GpuDraw? _compileSoftMaskGradientText(
  _GpuGeometryArena geometry,
  _SoftMaskGradientTextSpec spec,
) {
  final maskAlpha = spec.mask.alpha.clamp(0.0, 1.0);
  return _compileGradientSubpaths(
    geometry,
    _textSubpaths(spec.content.run)!,
    PdfFillRule.nonzero,
    spec.mask.gradient,
    1,
    vertexColor: (maskColor) {
      final mask = spec.luminosity
          ? (0.2126 * maskColor.red +
                  0.7152 * maskColor.green +
                  0.0722 * maskColor.blue) *
              maskAlpha
          : maskAlpha;
      return _premul(
        spec.content.run.color,
        (spec.content.run.fillAlpha * mask).clamp(0.0, 1.0),
      );
    },
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
      pathBounds.top,
      pathBounds.right,
      pathBounds.bottom,
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

class _GpuGlyphAtlas {
  _GpuGlyphAtlas(this.texture, this.info, this.slots);

  static _GpuGlyphAtlas? build(
    gpu.GpuContext context,
    List<PdfRenderCommand> commands,
    List<_GpuUnit> units,
    FlutterGpuTileBackendStats stats, {
    required int minimumGlyphs,
  }) {
    var candidateGlyphs = 0;
    for (final unit in units) {
      if (unit.composite != null) continue;
      final command = commands[unit.commandIndex];
      if (command case PdfDrawTextCommand(:final run)
          when !run.invisible && run.fill && run.gradient == null) {
        candidateGlyphs += (run.glyphs ?? const <PdfGlyphPlacement>[])
            .where((glyph) => glyph.outline != null)
            .length;
      }
    }
    if (candidateGlyphs < minimumGlyphs) {
      if (candidateGlyphs > 0) stats.analyticSparseAtlasSkips++;
      return null;
    }
    final slots = Map<PdfPath, int>.identity();
    final data = <SlugGlyphData>[];
    for (final unit in units) {
      if (unit.composite != null) continue;
      final command = commands[unit.commandIndex];
      if (command case PdfDrawTextCommand(:final run)
          when !run.invisible && run.fill && run.gradient == null) {
        for (final glyph in run.glyphs ?? const <PdfGlyphPlacement>[]) {
          final outline = glyph.outline;
          if (outline == null || slots.containsKey(outline)) continue;
          final glyphData = SlugGlyphData.of(outline);
          if (glyphData.overflow ||
              glyphData.maxX - glyphData.minX <= 1e-9 ||
              glyphData.maxY - glyphData.minY <= 1e-9) {
            continue;
          }
          slots[outline] = data.length;
          data.add(glyphData);
        }
      }
    }
    if (data.isEmpty) return null;

    var texels = data.length * 4;
    final bases = Uint32List(data.length);
    for (var i = 0; i < data.length; i++) {
      bases[i] = texels;
      texels += data[i].texelCount;
    }
    final height = math.max(1, (texels + slugAtlasWidth - 1) ~/ slugAtlasWidth);
    if (height > 4096) {
      stats.analyticAtlasFallbacks++;
      return null;
    }
    final pixels = Uint8List(slugAtlasWidth * height * 4);
    final pairs = ByteData.sublistView(pixels);
    void put(int texel, int low, int high) {
      pairs
        ..setUint16(texel * 4, low, Endian.little)
        ..setUint16(texel * 4 + 2, high, Endian.little);
    }

    for (var i = 0; i < data.length; i++) {
      final glyph = data[i];
      final base = bases[i];
      put(i * 4, base & 0xffff, base >> 16);
      put(i * 4 + 1, emToFixed(glyph.minY),
          emToFixed((glyph.maxY - glyph.minY) / glyph.bandCount));
      put(i * 4 + 2, emToFixed(glyph.minX),
          emToFixed((glyph.maxX - glyph.minX) / glyph.bandCount));
      put(i * 4 + 3, 0, 0);
      pixels.setRange(
        base * 4,
        base * 4 + glyph.stream!.length,
        glyph.stream!,
      );
    }

    final texture = context.createTexture(
      gpu.StorageMode.hostVisible,
      slugAtlasWidth,
      height,
      format: gpu.PixelFormat.r8g8b8a8UNormInt,
    );
    texture.overwrite(ByteData.sublistView(pixels));
    final dimensions = Float32List.fromList(
      <double>[slugAtlasWidth.toDouble(), height.toDouble()],
    );
    final info = gpu.BufferView(
      context.createDeviceBufferWithCopy(ByteData.sublistView(dimensions)),
      offsetInBytes: 0,
      lengthInBytes: dimensions.lengthInBytes,
    );
    stats
      ..analyticGlyphSlots += data.length
      ..analyticAtlasBytes += pixels.length;
    return _GpuGlyphAtlas(texture, info, slots);
  }

  final gpu.Texture texture;
  final gpu.BufferView info;
  final Map<PdfPath, int> slots;
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
  if (decoded == null && mipLevelCount == 1) {
    try {
      final texture = gpu.Texture.fromImage(context, image);
      stats
        ..textureImports += 1
        ..texturesUploaded += 1;
      return _GpuImageTexture(
        texture,
        texture.width,
        texture.height,
        texture.getBaseMipLevelSizeInBytes(),
      );
    } on Exception {
      // CPU-backed or cross-context images cannot be wrapped. Preserve the
      // established readback/upload path for those uncommon inputs.
    }
  }
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
  final alpha = (command.alpha * alphaScale).clamp(0.0, 1.0);
  final subpaths =
      flattenPath(command.path, PdfMatrix.identity, tolerance: 0.01);
  return _compileStrokeSubpaths(
    geometry,
    subpaths,
    command.color,
    command.stroke,
    alpha,
  );
}

_GpuDraw? _compileStrokeSubpaths(
  _GpuGeometryArena geometry,
  List<FlatSubpath> source,
  PdfColor color,
  PdfStroke stroke,
  double alpha,
) {
  final subpaths = _prepareStrokeSubpaths(source, stroke);
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
  return _stencilDraw(
    geometry,
    _strokeRings(subpaths, stroke),
    color,
    alpha,
    PdfFillRule.nonzero,
    true,
  );
}

List<FlatSubpath> _prepareStrokeSubpaths(
        List<FlatSubpath> source, PdfStroke stroke) =>
    stroke.dashArray.any((value) => value > 0)
        ? dashSubpaths(source, stroke.dashArray, stroke.dashPhase)
        : source;

List<FlatSubpath> _strokeRings(List<FlatSubpath> subpaths, PdfStroke stroke) {
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
  return rings;
}

List<FlatSubpath>? _textSubpaths(PdfTextRun run) {
  final glyphs = run.glyphs;
  if (glyphs == null) return null;
  final subpaths = <FlatSubpath>[];
  for (final glyph in glyphs) {
    final outline = glyph.outline;
    if (outline == null) continue;
    final transform = PdfMatrix.translation(glyph.offset, glyph.offsetY)
        .concat(run.transform);
    for (final sub in FlattenedOutline.of(outline).subpaths) {
      final mapped = Float64List(sub.points.length);
      for (var i = 0; i < sub.points.length; i += 2) {
        mapped[i] = transform.transformX(sub.points[i], sub.points[i + 1]);
        mapped[i + 1] = transform.transformY(sub.points[i], sub.points[i + 1]);
      }
      subpaths.add(FlatSubpath(mapped, closed: sub.closed));
    }
  }
  return subpaths;
}

_AnalyticTextDraw? _compileAnalyticText(
  _GpuGeometryArena geometry,
  PdfTextRun run,
  _GpuGlyphAtlas atlas,
  PdfMatrix pageToRaster,
  FlutterGpuTileBackendStats stats,
) {
  final glyphs = run.glyphs!;
  for (final glyph in glyphs) {
    final outline = glyph.outline;
    if (outline != null && !atlas.slots.containsKey(outline)) return null;
  }
  final rgba = _premul(run.color, run.fillAlpha);
  final vertices = FloatBuilder(math.max(54, glyphs.length * 54));
  final deviceTransform = run.transform.concat(pageToRaster);
  final scaleX = math.sqrt(deviceTransform.a * deviceTransform.a +
      deviceTransform.b * deviceTransform.b);
  final scaleY = math.sqrt(deviceTransform.c * deviceTransform.c +
      deviceTransform.d * deviceTransform.d);
  if (!scaleX.isFinite ||
      !scaleY.isFinite ||
      scaleX <= 1e-9 ||
      scaleY <= 1e-9) {
    return null;
  }
  // Covers at least one AA pixel at the backend's normal final-tile LoD and
  // half a pixel down to a 1/3-scale corpus raster without making large text
  // quads pay a fixed em-space overdraw margin.
  final paddingX = 1.5 / scaleX;
  final paddingY = 1.5 / scaleY;
  var quads = 0;
  for (final glyph in glyphs) {
    final outline = glyph.outline;
    if (outline == null) continue;
    final data = SlugGlyphData.of(outline);
    final slot = atlas.slots[outline]!;
    final left = data.minX - paddingX;
    final right = data.maxX + paddingX;
    final bottom = data.minY - paddingY;
    final top = data.maxY + paddingY;
    final transform = PdfMatrix.translation(glyph.offset, glyph.offsetY)
        .concat(run.transform);
    for (final (x, y) in <(double, double)>[
      (left, bottom),
      (right, bottom),
      (right, top),
      (left, bottom),
      (right, top),
      (left, top),
    ]) {
      vertices.add9(
        transform.transformX(x, y),
        transform.transformY(x, y),
        x,
        y,
        slot.toDouble(),
        rgba[0],
        rgba[1],
        rgba[2],
        rgba[3],
      );
    }
    quads++;
  }
  if (vertices.isEmpty) return null;
  stats
    ..analyticTextRuns += 1
    ..analyticGlyphQuads += quads;
  return _AnalyticTextDraw(
    geometry.add(vertices.bytes, vertices.length ~/ 9),
    atlas,
  );
}

FutureOr<_GpuDraw?> _compileCommand(
    gpu.GpuContext context,
    _GpuGeometryArena geometry,
    PdfRetainedScene scene,
    PdfRenderCommand command,
    FlutterGpuTileBackendStats stats,
    _GpuImageCache imageCache,
    List<_GpuImageTexture> textureLeases,
    _GpuGlyphAtlas? glyphAtlas,
    PdfMatrix pageToRaster,
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
      List<FlatSubpath>? flattened;
      List<FlatSubpath> outlines() => flattened ??= _textSubpaths(run)!;
      _GpuDraw? fill;
      if (run.fill) {
        if (glyphAtlas != null && run.gradient == null) {
          fill = _compileAnalyticText(
            geometry,
            run,
            glyphAtlas,
            pageToRaster,
            stats,
          );
          if (fill == null &&
              run.glyphs!.any((glyph) => glyph.outline != null)) {
            stats.analyticTextFallbackRuns++;
          }
        }
        if (fill == null) {
          final gradient = run.gradient;
          fill = gradient != null
              ? _compileGradientSubpaths(
                  geometry,
                  outlines(),
                  PdfFillRule.nonzero,
                  gradient,
                  run.fillAlpha,
                )
              : _stencilDraw(
                  geometry,
                  outlines(),
                  run.color,
                  run.fillAlpha,
                  PdfFillRule.nonzero,
                  false,
                );
        }
      }
      final strokeColor = run.strokeColor;
      final stroke = strokeColor == null
          ? null
          : _compileStrokeSubpaths(
              geometry,
              outlines(),
              strokeColor,
              PdfStroke(width: run.strokeWidth, miterLimit: 4),
              run.strokeAlpha.clamp(0.0, 1.0),
            );
      return switch ((fill, stroke)) {
        (null, null) => null,
        (final _GpuDraw draw, null) || (null, final _GpuDraw draw) => draw,
        (final _GpuDraw fill, final _GpuDraw stroke) =>
          _SequenceDraw([fill, stroke]),
      };
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

Future<_GpuDraw?> _compileImageCommand(
  gpu.GpuContext context,
  _GpuGeometryArena geometry,
  PdfRetainedScene scene,
  PdfImageRequest request,
  FlutterGpuTileBackendStats stats,
  _GpuImageCache imageCache,
  List<_GpuImageTexture> textureLeases, {
  double alphaScale = 1,
  required bool mipmapImages,
}) async {
  final image = scene.imageFor(request);
  if (image == null) return null;
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
  final alpha = (request.alpha * alphaScale).clamp(0.0, 1.0);
  final tint = request.isStencil
      ? _premul(request.stencilColor, alpha)
      : <double>[0, 0, 0, alpha];
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
  double alpha, {
  List<double> Function(PdfColor color)? vertexColor,
}) {
  if (alpha <= 0) return null;
  if (gradient.isRadial) {
    if (vertexColor != null) return null;
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
      final color = gradient.colors.last;
      return vertexColor?.call(color) ?? _premul(color, commandAlpha);
    }
    final lower = upper - 1;
    final lo = gradient.stops[lower], hi = gradient.stops[upper];
    final mix = hi <= lo ? 1.0 : ((sample - lo) / (hi - lo)).clamp(0.0, 1.0);
    final a = gradient.colors[lower], b = gradient.colors[upper];
    final color = PdfColor(
      a.red + (b.red - a.red) * mix,
      a.green + (b.green - a.green) * mix,
      a.blue + (b.blue - a.blue) * mix,
    );
    return vertexColor?.call(color) ?? _premul(color, commandAlpha);
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

/// Single-submission bump arena for transient uniforms and dynamic vertices.
///
/// Flutter 3.47's HostBuffer reserves four 1,024,000-byte frame blocks even
/// though the tile renderer creates a fresh allocator for every submission.
/// Its rollover check also ignores the incoming emplacement length, so a
/// dense sequence of individually small CAD hairlines can cross the active
/// block boundary and fail the upload. This arena owns only the buffers used
/// by one tile, tests the complete aligned range before every write, and is
/// retained until the command-buffer completion fence fires.
class _GpuTransientArena {
  _GpuTransientArena(this.context, [this.stats]);

  static const _firstBlockBytes = 64 << 10;
  static const _secondBlockBytes = 256 << 10;
  static const _maximumBlockBytes = 1 << 20;

  final gpu.GpuContext context;
  final FlutterGpuTileBackendStats? stats;
  final List<_GpuTransientBlock> _blocks = [];
  _GpuTransientBlock? _active;
  var _allocatedBytes = 0;
  var _nextBlockBytes = _secondBlockBytes;

  gpu.BufferView emplace(ByteData bytes) {
    final length = bytes.lengthInBytes;
    if (length <= 0) {
      throw ArgumentError.value(length, 'bytes.lengthInBytes');
    }
    final alignment = math.max(1, context.minimumUniformByteAlignment);
    var block = _active;
    var offset = block == null ? 0 : _align(block.usedBytes, alignment);
    if (block == null || offset + length > block.capacity) {
      final minimum = _align(length, alignment);
      final first = _blocks.isEmpty;
      final base = first ? _firstBlockBytes : _nextBlockBytes;
      final capacity = math.max(base, minimum);
      block = _GpuTransientBlock(
        context.createDeviceBuffer(gpu.StorageMode.hostVisible, capacity),
        capacity,
      );
      _blocks.add(block);
      _active = block;
      _allocatedBytes += capacity;
      if (!first) {
        _nextBlockBytes = math.min(
          _maximumBlockBytes,
          math.max(_nextBlockBytes * 2, capacity),
        );
      }
      stats
        ?..transientBuffers += 1
        ..transientAllocatedBytes += capacity
        ..peakTransientTileBytes = math.max(
          stats!.peakTransientTileBytes,
          _allocatedBytes,
        );
      offset = 0;
    }
    if (!block.buffer.overwrite(bytes, destinationOffsetInBytes: offset)) {
      throw StateError(
        'GPU transient upload failed: offset=$offset length=$length '
        'capacity=${block.capacity}',
      );
    }
    block.usedBytes = offset + length;
    stats?.transientEmplacedBytes += length;
    return gpu.BufferView(
      block.buffer,
      offsetInBytes: offset,
      lengthInBytes: length,
    );
  }

  void flush() {
    for (final block in _blocks) {
      if (block.flushedBytes == block.usedBytes) continue;
      block.buffer.flush(
        offsetInBytes: block.flushedBytes,
        lengthInBytes: block.usedBytes - block.flushedBytes,
      );
      block.flushedBytes = block.usedBytes;
    }
  }

  static int _align(int value, int alignment) =>
      ((value + alignment - 1) ~/ alignment) * alignment;
}

class _GpuTransientBlock {
  _GpuTransientBlock(this.buffer, this.capacity);

  final gpu.DeviceBuffer buffer;
  final int capacity;
  var usedBytes = 0;
  var flushedBytes = 0;
}

class _GpuGeometryPool {
  _GpuGeometryPool(this.maxBytes);

  static const minimumBytes = 64 << 10;
  static const chunkBytes = 16 << 20;

  final int maxBytes;
  final List<_GpuGeometryResource> _resources = [];
  var _bytes = 0;

  _GpuGeometryResource acquire(
    gpu.GpuContext context,
    ByteData data,
    FlutterGpuTileBackendStats stats,
  ) {
    final capacity = _capacityFor(data.lengthInBytes);
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

  static int _capacityFor(int bytes) {
    var capacity = minimumBytes;
    while (capacity < bytes && capacity < chunkBytes) {
      capacity <<= 1;
    }
    if (capacity >= bytes) return capacity;
    return ((bytes + chunkBytes - 1) ~/ chunkBytes) * chunkBytes;
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

/// A retained group whose overlapping paints must first render onto a bounded
/// tile-sized attachment. [_CompiledScene] encodes [paints]
/// into that attachment, then samples the completed texture once into the
/// page pass with [alpha] and the unit's outer blend mode.
class _OffscreenGroupDraw implements _GpuDraw {
  const _OffscreenGroupDraw(
    this.paints,
    this.alpha,
    this.extraPadding, {
    this.backdropColor,
  });

  /// The third field preserves the paint's internal blend. The fourth selects
  /// shape-limited source replacement for knockout
  /// siblings. Retained path stencils emit fragments only inside the painted
  /// shape; masked texture quads keep source-over so transparent pixels beyond
  /// their source shape cannot erase earlier siblings. The fifth optionally
  /// carries a precompiled per-paint clip for offscreen groups whose shared
  /// arbitrary path must be applied before the group is resolved.
  final List<(_GpuDraw, PdfRect?, PdfBlendMode, bool, _GpuClipState?)> paints;
  final double alpha;
  final double extraPadding;
  final PdfColor? backdropColor;

  @override
  void encode(_GpuEncoder encoder) =>
      throw StateError('offscreen group requires a separate render pass');
}

class _SolidDraw implements _GpuDraw {
  const _SolidDraw(this.vertices);
  final _GpuBuffer vertices;

  @override
  void encode(_GpuEncoder encoder) => encoder.solid(vertices);
}

class _PaperDraw extends _SolidDraw {
  const _PaperDraw(super.vertices, this.clearColor, this.rasterBounds);

  final vm.Vector4 clearColor;
  final Rect rasterBounds;
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

class _AnalyticTextDraw implements _GpuDraw {
  const _AnalyticTextDraw(this.vertices, this.atlas);

  final _GpuBuffer vertices;
  final _GpuGlyphAtlas atlas;

  @override
  void encode(_GpuEncoder encoder) => encoder.glyphs(vertices, atlas);
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
  static final _source = gpu.ColorBlendEquation(
    sourceColorBlendFactor: gpu.BlendFactor.one,
    destinationColorBlendFactor: gpu.BlendFactor.zero,
    sourceAlphaBlendFactor: gpu.BlendFactor.one,
    destinationAlphaBlendFactor: gpu.BlendFactor.zero,
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

  void setSourceBlend() => _paintBlend = _source;

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

  /// Samples a tile-sized offscreen group back into the same raster region.
  /// The texture was produced at this pass's exact dimensions, so nearest
  /// sampling is a one-to-one texel copy; [alpha] and [_paintBlend] apply to
  /// the completed group once, as required by PDF transparency semantics.
  void tileTexture(gpu.Texture texture, Rect textureRegion, double alpha) {
    final vertices = _tileTextureVertices(textureRegion);
    final info = Float32List(8)..[3] = alpha.clamp(0.0, 1.0);
    _defaultStencil();
    pass
      ..setColorBlendEquation(_paintBlend)
      ..bindPipeline(pipelines.texture)
      ..bindUniform(pipelines.textureTransform, transform)
      ..bindUniform(
          pipelines.textureInfo, emplaceTransient(ByteData.sublistView(info)))
      ..bindTexture(
        pipelines.textureSampler,
        texture,
        sampler: gpu.SamplerOptions(
          minFilter: gpu.MinMagFilter.nearest,
          magFilter: gpu.MinMagFilter.nearest,
        ),
      );
    _drawView(emplaceTransient(vertices.bytes), 6);
    pass.clearBindings();
  }

  /// Combines one premultiplied source tile with its existing backdrop using
  /// the PDF blend equations. This runs in a separate pass because Flutter GPU
  /// deliberately forbids sampling the color attachment being written.
  void copyTile(gpu.Texture texture) {
    final vertices = _tileTextureVertices(region);
    final info = Float32List(8)..[3] = 1;
    pass
      ..setScissor(gpu.Scissor(x: 0, y: 0, width: width, height: height))
      ..bindPipeline(pipelines.texture)
      ..bindUniform(pipelines.textureTransform, transform)
      ..bindUniform(
          pipelines.textureInfo, emplaceTransient(ByteData.sublistView(info)))
      ..bindTexture(
        pipelines.textureSampler,
        texture,
        sampler: gpu.SamplerOptions(
          minFilter: gpu.MinMagFilter.nearest,
          magFilter: gpu.MinMagFilter.nearest,
        ),
      );
    _drawView(emplaceTransient(vertices.bytes), 6);
    pass.clearBindings();
  }

  void advancedBlend(
    gpu.Texture backdrop,
    gpu.Texture source,
    Rect sourceRegion,
    PdfBlendMode mode,
    PdfRect? bounds,
  ) {
    final vertices = _tileTextureVertices(region);
    final info = Float32List(8)
      ..[0] = mode.index.toDouble()
      ..[4] = (sourceRegion.left - region.left) / region.width
      ..[5] = (sourceRegion.top - region.top) / region.height
      ..[6] = sourceRegion.width / region.width
      ..[7] = sourceRegion.height / region.height;
    pass
      ..setScissor(bounds == null
          ? gpu.Scissor(x: 0, y: 0, width: width, height: height)
          : _scissorForPdfRect(bounds))
      ..bindPipeline(pipelines.blend)
      ..bindUniform(pipelines.blendTransform, transform)
      ..bindUniform(
          pipelines.blendInfo, emplaceTransient(ByteData.sublistView(info)))
      ..bindTexture(
        pipelines.blendBackdropSampler,
        backdrop,
        sampler: gpu.SamplerOptions(
          minFilter: gpu.MinMagFilter.nearest,
          magFilter: gpu.MinMagFilter.nearest,
        ),
      )
      ..bindTexture(
        pipelines.blendSourceSampler,
        source,
        sampler: gpu.SamplerOptions(
          minFilter: gpu.MinMagFilter.nearest,
          magFilter: gpu.MinMagFilter.nearest,
        ),
      );
    _drawView(emplaceTransient(vertices.bytes), 6);
    pass.clearBindings();
  }

  gpu.Scissor _scissorForPdfRect(PdfRect rect) {
    final points = <Offset>[
      Offset(pageToRaster.transformX(rect.left, rect.bottom),
          pageToRaster.transformY(rect.left, rect.bottom)),
      Offset(pageToRaster.transformX(rect.right, rect.bottom),
          pageToRaster.transformY(rect.right, rect.bottom)),
      Offset(pageToRaster.transformX(rect.right, rect.top),
          pageToRaster.transformY(rect.right, rect.top)),
      Offset(pageToRaster.transformX(rect.left, rect.top),
          pageToRaster.transformY(rect.left, rect.top)),
    ];
    final left = points.map((point) => point.dx).reduce(math.min);
    final right = points.map((point) => point.dx).reduce(math.max);
    final top = points.map((point) => point.dy).reduce(math.min);
    final bottom = points.map((point) => point.dy).reduce(math.max);
    final x0 = ((left - region.left) * pixelRatio).floor().clamp(0, width);
    final x1 = ((right - region.left) * pixelRatio).ceil().clamp(0, width);
    final y0 = ((top - region.top) * pixelRatio).floor().clamp(0, height);
    final y1 = ((bottom - region.top) * pixelRatio).ceil().clamp(0, height);
    return gpu.Scissor(
      x: x0,
      y: y0,
      width: math.max(0, x1 - x0),
      height: math.max(0, y1 - y0),
    );
  }

  FloatBuilder _tileTextureVertices(Rect textureRegion) {
    final inverse = pageToRaster.inverted();
    if (inverse == null) throw StateError('singular page-to-raster transform');
    final left = textureRegion.left, right = textureRegion.right;
    final top = textureRegion.top, bottom = textureRegion.bottom;
    final bl = (
      inverse.transformX(left, bottom),
      inverse.transformY(left, bottom),
    );
    final br = (
      inverse.transformX(right, bottom),
      inverse.transformY(right, bottom),
    );
    final tl = (
      inverse.transformX(left, top),
      inverse.transformY(left, top),
    );
    return _imageVertices(PdfMatrix(
      br.$1 - bl.$1,
      br.$2 - bl.$2,
      tl.$1 - bl.$1,
      tl.$2 - bl.$2,
      bl.$1,
      bl.$2,
    ));
  }

  void glyphs(_GpuBuffer vertices, _GpuGlyphAtlas atlas) {
    _defaultStencil();
    pass
      ..setColorBlendEquation(_paintBlend)
      ..bindPipeline(pipelines.glyph)
      ..bindUniform(pipelines.glyphTransform, transform)
      ..bindUniform(pipelines.glyphInfo, atlas.info)
      ..bindTexture(
        pipelines.glyphSampler,
        atlas.texture,
        sampler: gpu.SamplerOptions(
          minFilter: gpu.MinMagFilter.nearest,
          magFilter: gpu.MinMagFilter.nearest,
          mipFilter: gpu.MipFilter.nearest,
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
        blend = context.createRenderPipeline(
            library['PdfTileTextureVertex']!, library['PdfTileBlendFragment']!),
        glyph = context.createRenderPipeline(
            library['PdfTileGlyphVertex']!, library['PdfTileGlyphFragment']!),
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
        blendTransform =
            library['PdfTileTextureVertex']!.getUniformSlot('VertInfo'),
        blendInfo =
            library['PdfTileBlendFragment']!.getUniformSlot('BlendInfo'),
        blendBackdropSampler =
            library['PdfTileBlendFragment']!.getUniformSlot('backdrop_tex'),
        blendSourceSampler =
            library['PdfTileBlendFragment']!.getUniformSlot('source_tex'),
        glyphTransform =
            library['PdfTileGlyphVertex']!.getUniformSlot('VertInfo'),
        glyphInfo =
            library['PdfTileGlyphFragment']!.getUniformSlot('GlyphInfo'),
        glyphSampler =
            library['PdfTileGlyphFragment']!.getUniformSlot('glyph_atlas'),
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

    final transient = _GpuTransientArena(context);
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
    transient.flush();
    try {
      void complete(bool success) {
        resources.length;
        if (completer.isCompleted) return;
        if (success) {
          completer.complete();
        } else {
          completer.completeError(StateError('GPU pipeline warm-up failed'));
        }
      }

      commandBuffer.submit(completionCallback: complete);
    } catch (error, stack) {
      if (!completer.isCompleted) completer.completeError(error, stack);
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
  final gpu.RenderPipeline blend;
  final gpu.RenderPipeline glyph;
  final gpu.RenderPipeline softMask;
  final gpu.UniformSlot stencilTransform;
  final gpu.UniformSlot solidTransform;
  final gpu.UniformSlot textureTransform;
  final gpu.UniformSlot textureInfo;
  final gpu.UniformSlot textureSampler;
  final gpu.UniformSlot blendTransform;
  final gpu.UniformSlot blendInfo;
  final gpu.UniformSlot blendBackdropSampler;
  final gpu.UniformSlot blendSourceSampler;
  final gpu.UniformSlot glyphTransform;
  final gpu.UniformSlot glyphInfo;
  final gpu.UniformSlot glyphSampler;
  final gpu.UniformSlot softMaskTransform;
  final gpu.UniformSlot softMaskInfo;
  final gpu.UniformSlot softMaskContentSampler;
  final gpu.UniformSlot softMaskMaskSampler;
}
