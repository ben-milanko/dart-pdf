// Experimental flutter_gpu implementation of PdfDevice.
//
// The interpreter's page-space callbacks are turned into GPU draws inside a
// single render pass: solid geometry (fills, strokes, meshes, glyph covers)
// batches into as few draw calls as possible; non-convex paths fill via
// stencil-then-cover; images and gradients draw as textured geometry.
//
// Known fidelity gaps (each counted in [unsupported]):
//  - substituted-font text (no embedded outlines) paints nothing
//  - non-normal blend modes composite as srcOver
//  - soft masks apply no mask (content paints unmasked)
//  - transparency groups reduce to an alpha multiplier; knockout ignored
//  - non-rectangular clips clip to their bounding box (scissor)
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:pdf_document/pdf_document.dart' show PdfRect;
import 'package:pdf_graphics/pdf_graphics.dart';

import '../image_decoder.dart' show pdfImageKey;
import 'gpu_geometry.dart';

/// The compiled pipelines + shaders for [GpuPdfDevice], built once per
/// process from the bundled shaderbundle asset.
class PdfGpuPipelines {
  PdfGpuPipelines._(gpu.GpuContext context, gpu.ShaderLibrary library)
      : stencil = context.createRenderPipeline(
            library['PdfStencilVertex']!, library['PdfStencilFragment']!),
        solid = context.createRenderPipeline(
            library['PdfSolidVertex']!, library['PdfSolidFragment']!),
        texture = context.createRenderPipeline(
            library['PdfTextureVertex']!, library['PdfTextureFragment']!),
        gradient = context.createRenderPipeline(
            library['PdfGradientVertex']!, library['PdfGradientFragment']!),
        textureFragInfo =
            library['PdfTextureFragment']!.getUniformSlot('FragInfo'),
        textureSampler = library['PdfTextureFragment']!.getUniformSlot('tex'),
        gradientInfo =
            library['PdfGradientFragment']!.getUniformSlot('GradInfo'),
        gradientLut = library['PdfGradientFragment']!.getUniformSlot('lut');

  static PdfGpuPipelines? _instance;

  /// Builds (or returns) the process-wide pipelines. [context] must be the
  /// default gpu context; the shader bundle loads from this package's assets.
  static PdfGpuPipelines instance(gpu.GpuContext context) {
    return _instance ??= PdfGpuPipelines._(context, _loadLibrary());
  }

  static gpu.ShaderLibrary _loadLibrary() {
    // Package-prefixed when hosted by an app; bare when this package is the
    // root (its own `flutter test`).
    try {
      return gpu.ShaderLibrary.fromAsset(
          'packages/dart_pdf_editor/assets/shaders/pdf_gpu.shaderbundle')!;
    } catch (_) {
      return gpu.ShaderLibrary.fromAsset(
          'assets/shaders/pdf_gpu.shaderbundle')!;
    }
  }

  final gpu.RenderPipeline stencil;
  final gpu.RenderPipeline solid;
  final gpu.RenderPipeline texture;
  final gpu.RenderPipeline gradient;
  final gpu.UniformSlot textureFragInfo;
  final gpu.UniformSlot textureSampler;
  final gpu.UniformSlot gradientInfo;
  final gpu.UniformSlot gradientLut;
}

/// Paints interpreter callbacks with flutter_gpu into an already-open
/// [gpu.RenderPass]. Call [finish] after interpretation to flush the last
/// batch; the caller submits the command buffer.
class GpuPdfDevice implements PdfDevice {
  GpuPdfDevice({
    required this.context,
    required this.pass,
    required this.hostBuffer,
    required this.pipelines,
    required this.pageToDevice,
    required this.widthPx,
    required this.heightPx,
    this.textures = const {},
  }) {
    _scissor = _Rect(0, 0, widthPx.toDouble(), heightPx.toDouble());
    pass
      ..setCullMode(gpu.CullMode.none)
      ..setWindingOrder(gpu.WindingOrder.counterClockwise)
      ..setPrimitiveType(gpu.PrimitiveType.triangle);
  }

  final gpu.GpuContext context;
  final gpu.RenderPass pass;
  final gpu.HostBuffer hostBuffer;
  final PdfGpuPipelines pipelines;

  /// Page space (PDF user space, y-up) -> device pixels (y-down), including
  /// page rotation and the raster scale.
  final PdfMatrix pageToDevice;
  final int widthPx;
  final int heightPx;

  /// Pre-uploaded image textures keyed by [pdfImageKey] (premultiplied RGBA).
  final Map<Object, gpu.Texture> textures;

  /// Approximated/skipped features and how often each was hit - honesty
  /// counters for the benchmark writeup.
  final Map<String, int> unsupported = {};

  void _count(String what) =>
      unsupported[what] = (unsupported[what] ?? 0) + 1;

  /// [gpu.HostBuffer.emplace] with a fallback: the SDK's bump allocator only
  /// opens a new block when the *start* offset passes the block end, so a
  /// write that merely crosses the boundary throws - give those writes their
  /// own device buffer instead.
  gpu.BufferView _emplace(ByteData data) {
    try {
      return hostBuffer.emplace(data);
    } on Exception {
      return gpu.BufferView(
        context.createDeviceBufferWithCopy(data),
        offsetInBytes: 0,
        lengthInBytes: data.lengthInBytes,
      );
    }
  }

  // ---- graphics state ------------------------------------------------------

  late _Rect _scissor;
  final _stateStack = <_Rect>[];
  final _groupAlpha = <double>[];
  double get _alphaScale =>
      _groupAlpha.isEmpty ? 1.0 : _groupAlpha.fold(1.0, (a, b) => a * b);

  // Batched solid triangles: NDC x, y + premultiplied r, g, b, a.
  final _solid = <double>[];
  // The scissor the current batch was started under; a change flushes.
  _Rect? _solidScissor;

  static final _gradientLuts = Expando<gpu.Texture>('pdfGradientLuts');

  double _ndcX(double x) => 2 * x / widthPx - 1;
  double _ndcY(double y) => 1 - 2 * y / heightPx;

  // ---- device interface ----------------------------------------------------

  @override
  void save() => _stateStack.add(_scissor);

  @override
  void restore() {
    if (_stateStack.isNotEmpty) _scissor = _stateStack.removeLast();
  }

  @override
  void setBlendMode(PdfBlendMode mode) {
    if (mode != PdfBlendMode.normal) _count('blend-${mode.name}');
  }

  @override
  void beginGroup(double alpha, {bool knockout = false}) {
    if (knockout) _count('knockout-group');
    if (alpha < 1) _count('group-alpha-approx');
    _groupAlpha.add(alpha.clamp(0, 1));
  }

  @override
  void endGroup() {
    if (_groupAlpha.isNotEmpty) _groupAlpha.removeLast();
  }

  @override
  void beginSoftMasked() {
    _count('soft-mask-skipped');
  }

  @override
  void endSoftMasked(
      {required bool luminosity,
      required PdfRect backdrop,
      required void Function() drawMask,
      double backdropLuminance = 0,
      double transferScale = 1,
      double transferOffset = 0}) {
    // The masked content painted unmasked; running drawMask here would paint
    // the mask's own geometry over the page, so it is intentionally skipped.
  }

  @override
  void clipPath(PdfPath path, PdfFillRule rule) {
    final subs = flattenPath(path, pageToDevice);
    final b = FlatBounds.of(subs);
    if (b == null) return;
    if (!_isAxisAlignedRect(subs, b)) _count('clip-approximated-by-bbox');
    _scissor = _scissor.intersect(_Rect(b.left, b.top, b.right, b.bottom));
  }

  /// Whether the flattened path is exactly one axis-aligned rectangle
  /// spanning [b] (the `re W n` idiom - scissor is then an exact clip).
  static bool _isAxisAlignedRect(List<FlatSubpath> subs, FlatBounds b) {
    if (subs.length != 1) return false;
    final p = subs[0].points;
    var n = p.length ~/ 2;
    if (n == 5 && p[0] == p[2 * n - 2] && p[1] == p[2 * n - 1]) n--;
    if (n != 4) return false;
    for (var i = 0; i < 4; i++) {
      final x = p[2 * i], y = p[2 * i + 1];
      final onX = (x - b.left).abs() < 1e-6 || (x - b.right).abs() < 1e-6;
      final onY = (y - b.top).abs() < 1e-6 || (y - b.bottom).abs() < 1e-6;
      if (!onX || !onY) return false;
    }
    return true;
  }

  @override
  void fillPath(PdfPath path, PdfColor color, PdfFillRule rule, double alpha) {
    final subs = flattenPath(path, pageToDevice);
    if (subs.isEmpty) return;
    final a = (alpha * _alphaScale).clamp(0.0, 1.0);
    if (a <= 0) return;
    if (isConvexPolygon(subs)) {
      _pushSolidFan(subs, color, a);
    } else {
      _stencilThenCover(subs, rule, union: false, cover: (bounds) {
        _coverSolid(bounds, color, a);
      });
    }
  }

  @override
  void fillPathGradient(
      PdfPath path, PdfFillRule rule, PdfGradient gradient, double alpha) {
    final subs = flattenPath(path, pageToDevice);
    if (subs.isEmpty) return;
    final a = (alpha * _alphaScale).clamp(0.0, 1.0);
    if (a <= 0) return;
    final deviceToGradient = _deviceToGradient(gradient);
    if (deviceToGradient == null) {
      // degenerate gradient space: fall back to the average color
      fillPath(path, gradient.averageColor, rule, alpha);
      return;
    }
    _stencilThenCover(subs, rule, union: false, cover: (bounds) {
      _coverGradient(bounds, gradient, deviceToGradient, a);
    });
  }

  @override
  void fillMesh(PdfMesh mesh, double alpha) {
    if (mesh.vertices.isEmpty || mesh.triangles.isEmpty) return;
    final a = (alpha * _alphaScale).clamp(0.0, 1.0);
    if (a <= 0) return;
    _ensureSolidBatch();
    for (final index in mesh.triangles) {
      final v = mesh.vertices[index];
      final dx = pageToDevice.transformX(v.x, v.y);
      final dy = pageToDevice.transformY(v.x, v.y);
      _solid
        ..add(_ndcX(dx))
        ..add(_ndcY(dy))
        ..add(v.color.red.clamp(0.0, 1.0) * a)
        ..add(v.color.green.clamp(0.0, 1.0) * a)
        ..add(v.color.blue.clamp(0.0, 1.0) * a)
        ..add(a);
    }
  }

  @override
  void strokePath(
      PdfPath path, PdfColor color, PdfStroke stroke, double alpha) {
    var subs = flattenPath(path, pageToDevice);
    if (subs.isEmpty) return;
    final scale = pageToDevice.scaleFactor;
    if (stroke.dashArray.any((d) => d > 0)) {
      subs = dashSubpaths(subs, [for (final d in stroke.dashArray) d * scale],
          stroke.dashPhase * scale);
    }
    final a = (alpha * _alphaScale).clamp(0.0, 1.0);
    if (a <= 0) return;
    final width = stroke.width * scale;
    final triangles = <double>[];
    appendStrokeTriangles(
        subs, width, stroke.cap, stroke.join, stroke.miterLimit, triangles);
    if (triangles.isEmpty) return;
    if (a >= 1) {
      // opaque: overlapping join geometry is invisible, batch directly
      _ensureSolidBatch();
      for (var i = 0; i < triangles.length; i += 2) {
        _solid
          ..add(_ndcX(triangles[i]))
          ..add(_ndcY(triangles[i + 1]))
          ..add(color.red.clamp(0.0, 1.0))
          ..add(color.green.clamp(0.0, 1.0))
          ..add(color.blue.clamp(0.0, 1.0))
          ..add(1.0);
      }
    } else {
      // translucent: stencil the union so overlaps don't double-blend
      _stencilTriangles(triangles, union: true);
      _coverSolid(_boundsOfTriangles(triangles), color, a);
    }
  }

  @override
  void drawText(PdfTextRun run) {
    if (run.invisible) return;
    if (run.glyphs == null) {
      _count('substituted-text-skipped');
      return;
    }
    final subs = <FlatSubpath>[];
    for (final glyph in run.glyphs!) {
      final outline = glyph.outline;
      if (outline == null) continue;
      final emToDevice = PdfMatrix.translation(glyph.offset, glyph.offsetY)
          .concat(run.transform)
          .concat(pageToDevice);
      subs.addAll(flattenPath(outline, emToDevice, tolerance: 0.1));
    }
    if (subs.isEmpty) return;
    final a = _alphaScale.clamp(0.0, 1.0);
    if (run.fill) {
      final gradient = run.gradient;
      final deviceToGradient =
          gradient == null ? null : _deviceToGradient(gradient);
      _stencilThenCover(subs, PdfFillRule.nonzero, union: false,
          cover: (bounds) {
        if (gradient != null && deviceToGradient != null) {
          _coverGradient(bounds, gradient, deviceToGradient, a);
        } else {
          _coverSolid(bounds, run.color, a);
        }
      });
    }
    if (run.strokeColor != null) {
      final triangles = <double>[];
      appendStrokeTriangles(
          subs,
          math.max(run.strokeWidth * pageToDevice.scaleFactor, 1.0),
          0,
          0,
          10,
          triangles);
      if (triangles.isNotEmpty) {
        _stencilTriangles(triangles, union: true);
        _coverSolid(_boundsOfTriangles(triangles), run.strokeColor!, a);
      }
    }
  }

  @override
  void drawImage(PdfImageRequest request) {
    final texture = textures[pdfImageKey(request)];
    if (texture == null) {
      _count('image-not-decoded');
      return;
    }
    _flushSolid();
    _applyScissor();
    _defaultStencil();

    final a = (request.alpha * _alphaScale).clamp(0.0, 1.0);
    // unit square (y-up) corners -> device -> NDC; uv is y-down
    final corners = <double>[0, 0, 1, 0, 1, 1, 0, 1];
    final ndc = List<double>.filled(8, 0);
    final uv = <double>[0, 1, 1, 1, 1, 0, 0, 0];
    for (var i = 0; i < 4; i++) {
      final x = corners[2 * i], y = corners[2 * i + 1];
      final px = request.transform.transformX(x, y);
      final py = request.transform.transformY(x, y);
      ndc[2 * i] = _ndcX(pageToDevice.transformX(px, py));
      ndc[2 * i + 1] = _ndcY(pageToDevice.transformY(px, py));
    }
    final verts = Float32List.fromList([
      for (final i in [0, 1, 2, 0, 2, 3]) ...[
        ndc[2 * i], ndc[2 * i + 1], uv[2 * i], uv[2 * i + 1],
      ],
    ]);

    final tint = request.isStencil
        ? _premul(request.stencilColor, a)
        : <double>[0, 0, 0, a];
    final info = Float32List(8)
      ..setRange(0, 4, tint)
      ..[4] = request.isStencil ? 1.0 : 0.0;

    pass
      ..bindPipeline(pipelines.texture)
      ..setColorBlendEnable(true)
      ..setColorBlendEquation(_srcOver)
      ..bindUniform(pipelines.textureFragInfo,
          _emplace(info.buffer.asByteData()))
      ..bindTexture(pipelines.textureSampler, texture,
          sampler: gpu.SamplerOptions(
              minFilter: gpu.MinMagFilter.linear,
              magFilter: gpu.MinMagFilter.linear))
      ..bindVertexBuffer(_emplace(verts.buffer.asByteData()), 6)
      ..draw();
    pass.clearBindings();
  }

  /// Flushes any pending batched geometry - call once after interpretation.
  void finish() => _flushSolid();

  // ---- internals -----------------------------------------------------------

  static final _srcOver = gpu.ColorBlendEquation(
    sourceColorBlendFactor: gpu.BlendFactor.one,
    destinationColorBlendFactor: gpu.BlendFactor.oneMinusSourceAlpha,
    sourceAlphaBlendFactor: gpu.BlendFactor.one,
    destinationAlphaBlendFactor: gpu.BlendFactor.oneMinusSourceAlpha,
  );

  // Color writes off: keep the destination untouched during stencil passes.
  static final _noColorWrite = gpu.ColorBlendEquation(
    sourceColorBlendFactor: gpu.BlendFactor.zero,
    destinationColorBlendFactor: gpu.BlendFactor.one,
    sourceAlphaBlendFactor: gpu.BlendFactor.zero,
    destinationAlphaBlendFactor: gpu.BlendFactor.one,
  );

  static List<double> _premul(PdfColor color, double alpha) => [
        color.red.clamp(0.0, 1.0) * alpha,
        color.green.clamp(0.0, 1.0) * alpha,
        color.blue.clamp(0.0, 1.0) * alpha,
        alpha,
      ];

  void _defaultStencil() {
    pass
      ..setStencilReference(0)
      ..setStencilConfig(gpu.StencilConfig(
        compareFunction: gpu.CompareFunction.always,
        depthStencilPassOperation: gpu.StencilOperation.keep,
      ));
  }

  void _applyScissor() {
    final s = _scissor;
    final x = s.left.floor().clamp(0, widthPx);
    final y = s.top.floor().clamp(0, heightPx);
    final r = s.right.ceil().clamp(0, widthPx);
    final b = s.bottom.ceil().clamp(0, heightPx);
    pass.setScissor(gpu.Scissor(
        x: x, y: y, width: math.max(r - x, 0), height: math.max(b - y, 0)));
  }

  void _ensureSolidBatch() {
    if (_solidScissor != null && !_solidScissor!.equals(_scissor)) {
      _flushSolid();
    }
    _solidScissor ??= _scissor;
  }

  void _pushSolidFan(List<FlatSubpath> subs, PdfColor color, double alpha) {
    _ensureSolidBatch();
    final fan = <double>[];
    appendFanTriangles(subs, fan);
    final c = _premul(color, alpha);
    for (var i = 0; i < fan.length; i += 2) {
      _solid
        ..add(_ndcX(fan[i]))
        ..add(_ndcY(fan[i + 1]))
        ..add(c[0])
        ..add(c[1])
        ..add(c[2])
        ..add(c[3]);
    }
  }

  void _flushSolid() {
    if (_solid.isEmpty) {
      _solidScissor = null;
      return;
    }
    final saved = _scissor;
    _scissor = _solidScissor ?? _scissor;
    _applyScissor();
    _scissor = saved;
    _defaultStencil();
    pass
      ..bindPipeline(pipelines.solid)
      ..setColorBlendEnable(true)
      ..setColorBlendEquation(_srcOver)
      ..bindVertexBuffer(
          hostBuffer
              .emplace(Float32List.fromList(_solid).buffer.asByteData()),
          _solid.length ~/ 6)
      ..draw();
    pass.clearBindings();
    _solid.clear();
    _solidScissor = null;
  }

  /// Stencil-then-cover fill: rasterize fan triangles into the stencil
  /// buffer ([union] counts coverage regardless of winding; otherwise
  /// nonzero/even-odd per [rule]), then run [cover] to paint every pixel
  /// with a non-zero stencil value, resetting the stencil to 0 behind it.
  void _stencilThenCover(List<FlatSubpath> subs, PdfFillRule rule,
      {required bool union, required void Function(FlatBounds) cover}) {
    final bounds = FlatBounds.of(subs);
    if (bounds == null) return;
    if (bounds.right <= _scissor.left ||
        bounds.left >= _scissor.right ||
        bounds.bottom <= _scissor.top ||
        bounds.top >= _scissor.bottom) {
      return; // fully clipped away
    }
    final fan = <double>[];
    appendFanTriangles(subs, fan);
    if (fan.isEmpty) return;
    _stencilRaw(fan, rule: rule, union: union);
    cover(bounds);
  }

  void _stencilTriangles(List<double> triangles, {required bool union}) {
    _stencilRaw(triangles, rule: PdfFillRule.nonzero, union: union);
  }

  void _stencilRaw(List<double> triangles,
      {required PdfFillRule rule, required bool union}) {
    _flushSolid();
    _applyScissor();
    final verts = Float32List(triangles.length);
    for (var i = 0; i < triangles.length; i += 2) {
      verts[i] = _ndcX(triangles[i]);
      verts[i + 1] = _ndcY(triangles[i + 1]);
    }
    pass
      ..bindPipeline(pipelines.stencil)
      ..setColorBlendEnable(true)
      ..setColorBlendEquation(_noColorWrite)
      ..setStencilReference(0);
    if (union) {
      // union coverage: any hit marks the pixel, winding irrelevant
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
            targetFace: gpu.StencilFace.front)
        ..setStencilConfig(
            gpu.StencilConfig(
              compareFunction: gpu.CompareFunction.always,
              depthStencilPassOperation: gpu.StencilOperation.decrementWrap,
            ),
            targetFace: gpu.StencilFace.back);
    }
    pass
      ..bindVertexBuffer(
          _emplace(verts.buffer.asByteData()), verts.length ~/ 2)
      ..draw();
    pass.clearBindings();
  }

  /// Stencil test for a cover draw: paint where the stencil is non-zero and
  /// zero it behind the draw, leaving the buffer clean for the next path.
  void _coverStencilConfig() {
    pass
      ..setStencilReference(0)
      ..setStencilConfig(gpu.StencilConfig(
        compareFunction: gpu.CompareFunction.notEqual,
        depthStencilPassOperation: gpu.StencilOperation.zero,
        stencilFailureOperation: gpu.StencilOperation.keep,
      ));
  }

  List<double> _coverQuad(FlatBounds b) {
    final l = _ndcX(b.left - 1), r = _ndcX(b.right + 1);
    final t = _ndcY(b.top - 1), bo = _ndcY(b.bottom + 1);
    return [l, t, r, t, r, bo, l, t, r, bo, l, bo];
  }

  void _coverSolid(FlatBounds? bounds, PdfColor color, double alpha) {
    if (bounds == null) return;
    _applyScissor();
    _coverStencilConfig();
    final c = _premul(color, alpha);
    final quad = _coverQuad(bounds);
    final verts = Float32List(6 * 6);
    for (var i = 0; i < 6; i++) {
      verts[i * 6] = quad[2 * i];
      verts[i * 6 + 1] = quad[2 * i + 1];
      verts[i * 6 + 2] = c[0];
      verts[i * 6 + 3] = c[1];
      verts[i * 6 + 4] = c[2];
      verts[i * 6 + 5] = c[3];
    }
    pass
      ..bindPipeline(pipelines.solid)
      ..setColorBlendEnable(true)
      ..setColorBlendEquation(_srcOver)
      ..bindVertexBuffer(
          _emplace(verts.buffer.asByteData()), 6)
      ..draw();
    pass.clearBindings();
    _defaultStencil();
  }

  /// Device px -> gradient space, or null when the gradient's transform is
  /// degenerate.
  PdfMatrix? _deviceToGradient(PdfGradient gradient) {
    final deviceToPage = pageToDevice.inverted();
    final pageToGradient = gradient.transform.inverted();
    if (deviceToPage == null || pageToGradient == null) return null;
    return deviceToPage.concat(pageToGradient);
  }

  void _coverGradient(FlatBounds? bounds, PdfGradient gradient,
      PdfMatrix deviceToGradient, double alpha) {
    if (bounds == null) return;
    _applyScissor();
    _coverStencilConfig();
    final quad = _coverQuad(bounds);
    // gradient-space coordinate per vertex (affine, so exact when
    // interpolated); recover device px from NDC to avoid re-deriving corners
    final verts = Float32List(6 * 4);
    for (var i = 0; i < 6; i++) {
      final dx = (quad[2 * i] + 1) * widthPx / 2;
      final dy = (1 - quad[2 * i + 1]) * heightPx / 2;
      verts[i * 4] = quad[2 * i];
      verts[i * 4 + 1] = quad[2 * i + 1];
      verts[i * 4 + 2] = deviceToGradient.transformX(dx, dy);
      verts[i * 4 + 3] = deviceToGradient.transformY(dx, dy);
    }
    final c = gradient.coords;
    final info = Float32List(12);
    if (gradient.isRadial) {
      info.setRange(0, 4, [c[0], c[1], c[3], c[4]]);
      info.setRange(4, 8, [c[2], c[5], 1, alpha]);
    } else {
      info.setRange(0, 4, [c[0], c[1], c[2], c[3]]);
      info.setRange(4, 8, [0, 0, 0, alpha]);
    }
    info[8] = gradient.extendStart ? 1 : 0;
    info[9] = gradient.extendEnd ? 1 : 0;

    pass
      ..bindPipeline(pipelines.gradient)
      ..setColorBlendEnable(true)
      ..setColorBlendEquation(_srcOver)
      ..bindUniform(
          pipelines.gradientInfo, _emplace(info.buffer.asByteData()))
      ..bindTexture(pipelines.gradientLut, _lutFor(gradient),
          sampler: gpu.SamplerOptions(
              minFilter: gpu.MinMagFilter.linear,
              magFilter: gpu.MinMagFilter.linear))
      ..bindVertexBuffer(_emplace(verts.buffer.asByteData()), 6)
      ..draw();
    pass.clearBindings();
    _defaultStencil();
  }

  /// 256x1 premultiplied color ramp for [gradient], cached on the gradient's
  /// own lifetime.
  gpu.Texture _lutFor(PdfGradient gradient) {
    final cached = _gradientLuts[gradient];
    if (cached != null) return cached;
    const n = 256;
    final data = Uint8List(n * 4);
    final stops = gradient.stops;
    final colors = gradient.colors;
    for (var i = 0; i < n; i++) {
      final t = i / (n - 1);
      var lo = 0;
      while (lo + 1 < stops.length && stops[lo + 1] < t) {
        lo++;
      }
      final hi = math.min(lo + 1, colors.length - 1);
      final span = stops[hi] - stops[lo];
      final f = span <= 0 ? 0.0 : ((t - stops[lo]) / span).clamp(0.0, 1.0);
      double lerp(double a, double b) => a + (b - a) * f;
      data[i * 4] =
          (lerp(colors[lo].red, colors[hi].red).clamp(0.0, 1.0) * 255).round();
      data[i * 4 + 1] =
          (lerp(colors[lo].green, colors[hi].green).clamp(0.0, 1.0) * 255)
              .round();
      data[i * 4 + 2] =
          (lerp(colors[lo].blue, colors[hi].blue).clamp(0.0, 1.0) * 255)
              .round();
      data[i * 4 + 3] = 255;
    }
    final texture = context.createTexture(gpu.StorageMode.hostVisible, n, 1,
        format: gpu.PixelFormat.r8g8b8a8UNormInt);
    texture.overwrite(data.buffer.asByteData());
    _gradientLuts[gradient] = texture;
    return texture;
  }

  static FlatBounds? _boundsOfTriangles(List<double> triangles) {
    if (triangles.isEmpty) return null;
    final b =
        FlatBounds(triangles[0], triangles[1], triangles[0], triangles[1]);
    for (var i = 2; i < triangles.length; i += 2) {
      if (triangles[i] < b.left) b.left = triangles[i];
      if (triangles[i] > b.right) b.right = triangles[i];
      if (triangles[i + 1] < b.top) b.top = triangles[i + 1];
      if (triangles[i + 1] > b.bottom) b.bottom = triangles[i + 1];
    }
    return b;
  }
}

class _Rect {
  const _Rect(this.left, this.top, this.right, this.bottom);

  final double left, top, right, bottom;

  _Rect intersect(_Rect other) => _Rect(
        math.max(left, other.left),
        math.max(top, other.top),
        math.min(right, other.right),
        math.min(bottom, other.bottom),
      );

  bool equals(_Rect other) =>
      left == other.left &&
      top == other.top &&
      right == other.right &&
      bottom == other.bottom;
}
