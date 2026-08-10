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

/// Scene-retained flutter_gpu backend for LoD tile slabs.
///
/// The first tile lazily compiles supported retained commands into page-space
/// GPU buffers and uploads every decoded image once. Later tiles only query the
/// retained region index, bind those buffers with a page-to-tile transform and
/// submit a render pass. No PDF interpretation, path tessellation, image
/// decode, texture upload, or CPU pixel readback occurs per tile.
///
/// The exact subset includes a common isolated single-image soft-mask group:
/// content and mask stay as separate scene-lifetime textures and are combined
/// by the tile shader. Other isolated groups, non-normal blend modes,
/// non-rectangular clips, gradients, substituted/stroked text, tiling cells,
/// unsafe overprint, or missing image pixels reject the whole scene.
/// dart_pdf_editor then permanently uses its Canvas session for that scene.
class FlutterGpuTileRasterBackend extends PdfTileRasterBackend {
  FlutterGpuTileRasterBackend({
    this.msaa = true,
    this.allowOverprintApproximation = false,
    this.maxTextureBytes = 256 << 20,
    FlutterGpuTileBackendStats? stats,
  })  : stats = stats ?? FlutterGpuTileBackendStats(),
        _imageCache = _GpuImageCache(maxTextureBytes);

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

  final FlutterGpuTileBackendStats stats;
  final _GpuImageCache _imageCache;

  /// Drops reusable texture ownership. Active compiled scenes retain the
  /// resources they are currently drawing.
  void clearImageCache() => _imageCache.clear(stats);

  @override
  String get debugLabel => 'flutter_gpu';

  @override
  PdfTileRasterSession? createSession(PdfRetainedScene scene) {
    try {
      final context = gpu.gpuContext;
      final unitBuild = _buildGpuUnits(scene.commands);
      final units = unitBuild.units;
      if (units == null) {
        stats.lastRejection = unitBuild.rejection;
        stats.sessionsRejected++;
        return null;
      }
      final rejection =
          _unsupportedReason(scene, units, allowOverprintApproximation);
      if (rejection != null) {
        stats.lastRejection = rejection;
        stats.sessionsRejected++;
        return null;
      }
      if (allowOverprintApproximation && units.any((unit) => unit.darken)) {
        stats.overprintApproximationSessions++;
      }
      stats.sessionsCreated++;
      return _FlutterGpuTileSession(
        scene: scene,
        context: context,
        pipelines: _GpuPipelines.instance(context),
        units: units,
        msaa: msaa,
        stats: stats,
        imageCache: _imageCache,
      );
    } catch (error) {
      stats.lastRejection = 'initialization failed: $error';
      stats.sessionsRejected++;
      return null;
    }
  }

  static String? _unsupportedReason(PdfRetainedScene scene,
      List<_GpuUnit> units, bool allowOverprintApproximation) {
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
      final command = scene.commands[unit.commandIndex];
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
          if (scene.imageFor(request) == null) return 'missing image pixels';
        case PdfDrawTextCommand(:final run):
          if (run.invisible) continue;
          if (run.glyphs == null ||
              !run.fill ||
              run.gradient != null ||
              run.strokeColor != null) {
            return 'unsupported text rendering mode';
          }
        case PdfFillPathGradientCommand() || PdfDrawTiledCellCommand():
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
    for (var i = 0; i < scene.commands.length; i++) {
      final command = scene.commands[i];
      switch (command) {
        case PdfBeginGroupCommand() ||
              PdfEndGroupCommand() ||
              PdfBeginSoftMaskedCommand() ||
              PdfEndSoftMaskedCommand() ||
              PdfFillPathGradientCommand() ||
              PdfDrawTiledCellCommand():
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
  final PdfRect? clip;
  final PdfBlendMode blendMode;
  final bool fillOverprint;
  final bool strokeOverprint;
  final bool darken;
  final _SoftMaskImageSpec? composite;
}

class _GpuUnitBuild {
  const _GpuUnitBuild(this.units, this.rejection);
  final List<_GpuUnit>? units;
  final String? rejection;
}

class _CompositeCapture {
  _CompositeCapture(this.start, this.clip, this.blendMode, this.fillOverprint,
      this.strokeOverprint);
  final int start;
  final PdfRect? clip;
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

_GpuUnitBuild _buildGpuUnits(List<PdfRenderCommand> commands) {
  if (commands.length > 1000000) {
    return const _GpuUnitBuild(null, 'retained scene exceeds GPU index cap');
  }
  final units = <_GpuUnit>[];
  final saved = <(PdfRect?, PdfBlendMode, bool, bool)>[];
  PdfRect? clip;
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
      case PdfClipPathCommand(:final path):
        if (!FlutterGpuTileRasterBackend._isAxisAlignedRect(path)) {
          return const _GpuUnitBuild(null, 'non-rectangular clip');
        }
        final bounds = pdfRenderPathBounds(path);
        if (bounds == null) {
          return const _GpuUnitBuild(null, 'empty rectangular clip');
        }
        clip = _pdfIntersection(clip, bounds);
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
            initialClip: capture.clip,
          );
          if (parsed.$1 == null) return _GpuUnitBuild(null, parsed.$2);
          final bounds = capture.bounds;
          if (bounds != null) {
            units.add(_GpuUnit(
              commandIndex: capture.start,
              endCommandIndex: i,
              bounds: _inflatePdf(bounds, 2),
              clip: parsed.$1!.contentClip ?? capture.clip,
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
        final clipped = _pdfIntersection(clip, bounds);
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

class _FlutterGpuTileSession implements PdfTileRasterSession {
  _FlutterGpuTileSession({
    required this.scene,
    required this.context,
    required this.pipelines,
    required this.units,
    required this.msaa,
    required this.stats,
    required this.imageCache,
  });

  @override
  final PdfRetainedScene scene;
  final gpu.GpuContext context;
  final _GpuPipelines pipelines;
  final List<_GpuUnit> units;
  final bool msaa;
  final FlutterGpuTileBackendStats stats;
  final _GpuImageCache imageCache;

  Future<_CompiledScene>? _compiled;
  _CompiledScene? _ready;
  bool _disposed = false;

  Future<_CompiledScene> _compile() => _compiled ??= _CompiledScene.build(
        scene,
        context,
        units,
        stats,
        imageCache,
      ).then((compiled) {
        if (_disposed) {
          compiled.dispose();
          throw StateError('flutter_gpu tile session disposed');
        }
        return _ready = compiled;
      });

  @override
  Future<ui.Image> rasterizeRegion(
    Rect region, {
    required double pixelRatio,
    int? tracePage,
  }) async {
    if (_disposed) throw StateError('flutter_gpu tile session disposed');
    final compiled = await _compile();
    if (_disposed) throw StateError('flutter_gpu tile session disposed');
    final selected = _selectGpuUnits(units, compiled.pageToRaster, region);
    stats.selectedCommands += selected.length;
    final image = compiled.render(
      selected,
      region: region,
      pixelRatio: pixelRatio,
      pipelines: pipelines,
      useMsaa: msaa,
    );
    stats.tilesRendered++;
    return image;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _ready?.dispose();
    _ready = null;
    _compiled = null;
  }
}

class _CompiledScene {
  _CompiledScene({
    required this.context,
    required this.pageToRaster,
    required this.paper,
    required this.draws,
    required this.stats,
    required this.imageCache,
    required this.textureLeases,
  });

  static Future<_CompiledScene> build(
    PdfRetainedScene scene,
    gpu.GpuContext context,
    List<_GpuUnit> units,
    FlutterGpuTileBackendStats stats,
    _GpuImageCache imageCache,
  ) async {
    final clock = Stopwatch()..start();
    final draws = <int, _GpuDraw>{};
    final textureLeases = <_GpuImageTexture>[];
    try {
      for (final unit in units) {
        final draw = unit.composite == null
            ? await _compileCommand(
                context,
                scene,
                scene.commands[unit.commandIndex],
                stats,
                imageCache,
                textureLeases,
              )
            : await _compileSoftMaskImage(
                context,
                scene,
                unit.composite!,
                stats,
                imageCache,
                textureLeases,
              );
        if (draw != null) draws[unit.commandIndex] = draw;
      }
      final result = _CompiledScene(
        context: context,
        pageToRaster: PdfPageRenderer.pageToDeviceMatrix(
          scene.page,
          scene.pageSize,
          scene.page.cropBox,
          rotation: scene.plan.rotation,
          pixelRatio: 1,
        ),
        paper: _paperDraw(context, scene, stats),
        draws: draws,
        stats: stats,
        imageCache: imageCache,
        textureLeases: textureLeases,
      );
      stats
        ..scenesCompiled += 1
        ..compileMicros += clock.elapsedMicroseconds;
      return result;
    } catch (_) {
      imageCache.releaseAll(textureLeases, stats);
      rethrow;
    }
  }

  final gpu.GpuContext context;
  final PdfMatrix pageToRaster;
  final _SolidDraw paper;
  final Map<int, _GpuDraw> draws;
  final FlutterGpuTileBackendStats stats;
  final _GpuImageCache imageCache;
  final List<_GpuImageTexture> textureLeases;
  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    imageCache.releaseAll(textureLeases, stats);
  }

  ui.Image render(
    List<_GpuUnit> selected, {
    required Rect region,
    required double pixelRatio,
    required _GpuPipelines pipelines,
    required bool useMsaa,
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
  }) {
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
    );
    encoder
      ..setClip(null)
      ..solid(paper.vertices);
    for (final unit in selected) {
      final draw = draws[unit.commandIndex];
      if (draw == null) continue;
      encoder.setClip(unit.clip);
      draw.encode(encoder);
    }
    final submit = Stopwatch()..start();
    commandBuffer.submit();
    stats.submitMicros += submit.elapsedMicroseconds;
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

_SolidDraw _paperDraw(gpu.GpuContext context, PdfRetainedScene scene,
    FlutterGpuTileBackendStats stats) {
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
  return _SolidDraw(_upload(context, vertices.bytes, 6, stats));
}

Future<_GpuDraw> _compileSoftMaskImage(
  gpu.GpuContext context,
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
    _upload(context, vertices.bytes, vertices.length ~/ 4, stats),
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
  const _GpuTextureKey(this.content, this.width, this.height);
  final Object content;
  final int width;
  final int height;

  @override
  bool operator ==(Object other) =>
      other is _GpuTextureKey &&
      other.content == content &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(content, width, height);
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
    final key =
        _GpuTextureKey(pdfImageContentKey(request), image.width, image.height);
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

Future<_GpuDraw?> _compileCommand(
  gpu.GpuContext context,
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
      return _stencilDraw(context, subs, color, alpha, rule, false, stats);
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
          context, rings, color, alpha, PdfFillRule.nonzero, true, stats);
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
          context, subs, run.color, 1, PdfFillRule.nonzero, false, stats);
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
      return _SolidDraw(
          _upload(context, vertices.bytes, vertices.length ~/ 6, stats));
    case PdfDrawImageCommand(:final request):
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
        _upload(context, vertices.bytes, 6, stats),
        resource.texture,
        gpu.BufferView(
          context.createDeviceBufferWithCopy(ByteData.sublistView(info)),
          offsetInBytes: 0,
          lengthInBytes: info.lengthInBytes,
        ),
      );
    default:
      return null;
  }
}

_StencilDraw? _stencilDraw(
  gpu.GpuContext context,
  List<FlatSubpath> subpaths,
  PdfColor color,
  double alpha,
  PdfFillRule rule,
  bool union,
  FlutterGpuTileBackendStats stats,
) {
  final bounds = FlatBounds.of(subpaths);
  if (bounds == null || alpha <= 0) return null;
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
  final a = alpha.clamp(0.0, 1.0);
  final rgba = _premul(color, a);
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
  return _StencilDraw(
    _upload(context, fan.bytes, fan.length ~/ 2, stats),
    _upload(context, cover.bytes, 6, stats),
    rule,
    union,
  );
}

List<double> _premul(PdfColor color, double alpha) => [
      color.red.clamp(0.0, 1.0) * alpha,
      color.green.clamp(0.0, 1.0) * alpha,
      color.blue.clamp(0.0, 1.0) * alpha,
      alpha,
    ];

_GpuBuffer _upload(gpu.GpuContext context, ByteData bytes, int vertices,
    FlutterGpuTileBackendStats stats) {
  final buffer = context.createDeviceBufferWithCopy(bytes);
  stats
    ..geometryBuffers += 1
    ..geometryVertices += vertices;
  return _GpuBuffer(
    gpu.BufferView(
      buffer,
      offsetInBytes: 0,
      lengthInBytes: bytes.lengthInBytes,
    ),
    vertices,
  );
}

class _GpuBuffer {
  const _GpuBuffer(this.view, this.vertices);
  final gpu.BufferView view;
  final int vertices;
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
  });

  final gpu.RenderPass pass;
  final _GpuPipelines pipelines;
  final gpu.BufferView transform;
  final PdfMatrix pageToRaster;
  final Rect region;
  final double pixelRatio;
  final int width;
  final int height;

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

  void setClip(PdfRect? clip) {
    var target = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    if (clip != null) {
      final points = <Offset>[
        Offset(pageToRaster.transformX(clip.left, clip.bottom),
            pageToRaster.transformY(clip.left, clip.bottom)),
        Offset(pageToRaster.transformX(clip.right, clip.bottom),
            pageToRaster.transformY(clip.right, clip.bottom)),
        Offset(pageToRaster.transformX(clip.right, clip.top),
            pageToRaster.transformY(clip.right, clip.top)),
        Offset(pageToRaster.transformX(clip.left, clip.top),
            pageToRaster.transformY(clip.left, clip.top)),
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
  }

  void solid(_GpuBuffer vertices) {
    _defaultStencil();
    pass
      ..setColorBlendEquation(_srcOver)
      ..bindPipeline(pipelines.solid)
      ..bindUniform(pipelines.solidTransform, transform)
      ..bindVertexBuffer(vertices.view, vertices.vertices)
      ..draw();
  }

  void stencil(_GpuBuffer fan, _GpuBuffer cover,
      {required PdfFillRule rule, required bool union}) {
    pass
      ..setColorBlendEquation(_noWrite)
      ..bindPipeline(pipelines.stencil)
      ..bindUniform(pipelines.stencilTransform, transform);
    if (union) {
      pass.setStencilConfig(gpu.StencilConfig(
        compareFunction: gpu.CompareFunction.always,
        depthStencilPassOperation: gpu.StencilOperation.incrementWrap,
      ));
    } else if (rule == PdfFillRule.evenOdd) {
      pass.setStencilConfig(gpu.StencilConfig(
        compareFunction: gpu.CompareFunction.always,
        depthStencilPassOperation: gpu.StencilOperation.invert,
      ));
    } else {
      pass
        ..setStencilConfig(
          gpu.StencilConfig(
            compareFunction: gpu.CompareFunction.always,
            depthStencilPassOperation: gpu.StencilOperation.incrementWrap,
          ),
          targetFace: gpu.StencilFace.front,
        )
        ..setStencilConfig(
          gpu.StencilConfig(
            compareFunction: gpu.CompareFunction.always,
            depthStencilPassOperation: gpu.StencilOperation.decrementWrap,
          ),
          targetFace: gpu.StencilFace.back,
        );
    }
    pass
      ..bindVertexBuffer(fan.view, fan.vertices)
      ..draw()
      ..setColorBlendEquation(_srcOver)
      ..setStencilConfig(gpu.StencilConfig(
        compareFunction: gpu.CompareFunction.notEqual,
        depthStencilPassOperation: gpu.StencilOperation.zero,
        stencilFailureOperation: gpu.StencilOperation.keep,
      ))
      ..bindPipeline(pipelines.solid)
      ..bindUniform(pipelines.solidTransform, transform)
      ..bindVertexBuffer(cover.view, cover.vertices)
      ..draw();
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
      )
      ..bindVertexBuffer(vertices.view, vertices.vertices)
      ..draw();
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
          sampler: sampler)
      ..bindVertexBuffer(vertices.view, vertices.vertices)
      ..draw();
    pass.clearBindings();
  }

  void _defaultStencil() => pass.setStencilConfig(gpu.StencilConfig(
        compareFunction: gpu.CompareFunction.always,
        depthStencilPassOperation: gpu.StencilOperation.keep,
      ));
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

  static _GpuPipelines? _instance;

  static _GpuPipelines instance(gpu.GpuContext context) =>
      _instance ??= _GpuPipelines._(context, _loadLibrary());

  static gpu.ShaderLibrary _loadLibrary() {
    for (final asset in const [
      'packages/dart_pdf_editor_flutter_gpu/assets/shaders/pdf_tile_gpu.shaderbundle',
      'assets/shaders/pdf_tile_gpu.shaderbundle',
    ]) {
      try {
        final library = gpu.ShaderLibrary.fromAsset(asset);
        if (library != null) return library;
      } catch (_) {
        // Package-prefixed in an app, bare while this package is the test root.
      }
    }
    throw StateError('pdf_tile_gpu.shaderbundle asset not found');
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
