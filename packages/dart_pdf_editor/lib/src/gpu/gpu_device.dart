// Experimental flutter_gpu implementation of PdfDevice.
//
// The interpreter's page-space callbacks are turned into GPU draws inside a
// single render pass. Two deferred batches keep the draw count down (each
// draw costs ~12us of GPU-timeline time regardless of size, measured in
// gpu_cost_matrix_test.dart):
//  - solid geometry (convex fills, opaque strokes, meshes) accumulates into
//    one vertex buffer per state run;
//  - consecutive same-color text runs merge into a single stencil-then-cover
//    pair instead of one per show-text operator.
// At most one batch is open at a time, so paint order is preserved.
// Non-convex paths fill via stencil-then-cover; images and gradients draw
// as textured geometry. Redundant pass-state calls (scissor, stencil
// config, blend) are elided.
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
      ..setPrimitiveType(gpu.PrimitiveType.triangle)
      ..setStencilReference(0)
      ..setColorBlendEnable(true);
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

  /// Work counters for profiling: draw calls, stencil passes, vertex volume.
  final Map<String, int> stats = {};

  void _tally(String what, [int n = 1]) =>
      stats[what] = (stats[what] ?? 0) + n;

  static final _timer = Stopwatch();
  bool _timed(String what, bool Function() f) {
    _timer
      ..reset()
      ..start();
    final result = f();
    _tally(what, _timer.elapsedMicroseconds);
    return result;
  }

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
  final _solid = FloatBuilder(4096);
  // The scissor the current batch was started under; a change flushes.
  _Rect? _solidScissor;

  // Batched stencil fills: device-space fan triangles for consecutive
  // same-color nonzero fills (text runs and non-convex paths), covered in
  // one stencil-then-cover pair at flush. Overlaps between merged fills
  // paint once instead of blending twice - invisible for the opaque common
  // case, a small deviation for translucent overlapping same-color art.
  final _text = DoubleBuilder(4096);
  FlatBounds? _textBounds;
  double _textR = 0, _textG = 0, _textB = 0, _textA = 0;
  _Rect? _textScissor;
  bool _textOpen = false;
  // Sum of member bbox areas: the flush-on-spread heuristic keeps the
  // cover quad (union bbox) from ballooning past the painted content.
  double _textCoverage = 0;

  // scratch for per-path fan/stroke triangles (reused across calls)
  final _scratch = DoubleBuilder(4096);

  static final _gradientLuts = Expando<gpu.Texture>('pdfGradientLuts');

  // Applied pass state, for elision of redundant FFI setters.
  int _appliedScissorX = -1, _appliedScissorY = -1;
  int _appliedScissorW = -1, _appliedScissorH = -1;
  int _stencilState = -1; // 0 default, 1 nonzero, 2 evenodd, 3 union, 4 cover
  int _blendState = -1; // 0 srcOver, 1 no color write
  gpu.RenderPipeline? _boundPipeline;

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
    // Shape instancing: CAD exports repeat identical small shapes
    // (converted-text glyphs, symbols) at hundreds of offsets. Key the
    // triangulation by the shape's translation-invariant form and replay
    // it instead of re-classifying and re-clipping.
    final key = _ShapeKey.of(subs, rule);
    if (key != null) {
      final cached = _shapeCache[key];
      if (cached != null) {
        _tally('fill-shape-cache');
        _emitShape(cached, key.anchorX, key.anchorY, color, a);
        return;
      }
      final solidStart = _solid.length;
      final flushes = _solidFlushes;
      _fillPathClassified(subs, color, rule, a);
      if (_solidFlushes == flushes && _solid.length > solidStart) {
        _tally('shape-capture');
        _cacheShape(key, solidStart);
      } else {
        _tally('shape-capture-miss');
      }
      return;
    }
    _tally('shape-key-null');
    _fillPathClassified(subs, color, rule, a);
  }

  int _solidFlushes = 0;

  /// Shape-instancing cache: translation-invariant quantized outline ->
  /// NDC-relative solid triangles. Shared across pages (device coords for
  /// same-size pages line up); FIFO-capped.
  static final _shapeCache = <_ShapeKey, Float64List>{};
  static const _shapeCacheCap = 4096;

  void _cacheShape(_ShapeKey key, int solidStart) {
    final ax = _ndcX(key.anchorX), ay = _ndcY(key.anchorY);
    final deltas = Float64List((_solid.length - solidStart) ~/ 6 * 2);
    var w = 0;
    for (var i = solidStart; i < _solid.length; i += 6) {
      deltas[w++] = _solid[i] - ax;
      deltas[w++] = _solid[i + 1] - ay;
    }
    if (_shapeCache.length >= _shapeCacheCap) {
      _shapeCache.remove(_shapeCache.keys.first);
    }
    _shapeCache[key] = deltas;
  }

  void _emitShape(Float64List deltas, double anchorX, double anchorY,
      PdfColor color, double a) {
    _ensureSolidBatch();
    final ax = _ndcX(anchorX), ay = _ndcY(anchorY);
    final r = color.red.clamp(0.0, 1.0) * a;
    final g = color.green.clamp(0.0, 1.0) * a;
    final b = color.blue.clamp(0.0, 1.0) * a;
    for (var i = 0; i < deltas.length; i += 2) {
      _solid.add6(ax + deltas[i], ay + deltas[i + 1], r, g, b, a);
    }
  }

  void _fillPathClassified(
      List<FlatSubpath> subs, PdfColor color, PdfFillRule rule, double a) {
    if (isConvexPolygon(subs)) {
      _tally('fill-convex');
      _pushSolidFan(subs, color, a);
    } else if (subs.length == 1 && _pushEarClipped(subs[0], color, a)) {
      // small simple polygon (CAD hatches, arrowheads): exact triangles into
      // the solid batch - no stencil pass, no hull overdraw, no cover.
      // For a simple polygon nonzero and even-odd fill identically.
      _tally('fill-earclip');
    } else if (subs.length == 1) {
      _tally('earclip-fail-${subs[0].pointCount <= 160 ? "shape" : "size"}');
      _fillStencilFallback(subs, color, rule, a);
    } else if (_timed('islands-us', () => _independentIslands(subs, rule))) {
      // independent islands (hatch strips, edge-split quads, dash-like
      // fills): route each subpath through the fast paths alone. Winding
      // and parity only interact where interiors overlap, so
      // interior-disjoint subpaths fill independently under both rules.
      // Checked before rings: this is the cheap, dominant CAD case.
      _tally('fill-islands');
      for (final sub in subs) {
        final single = [sub];
        if (isConvexPolygon(single)) {
          _pushSolidFan(single, color, a);
        } else if (!_pushEarClipped(sub, color, a)) {
          _fillStencilFallback(single, color, rule, a);
        }
      }
    } else if (_timed('rings-us', () => _pushRings(subs, color, a))) {
      // outer+hole rings (rectangle borders, outlined thick strokes in CAD
      // exports): bridged hole-aware ear clip into the solid batch
      _tally('fill-rings');
    } else if (rule == PdfFillRule.nonzero) {
      // winding counts add across merged nonzero fills, so same-color
      // non-convex fills coalesce exactly like text runs
      _tally('fill-stencil-batched');
      _appendStencilFill(
          subs,
          color.red.clamp(0.0, 1.0) * a,
          color.green.clamp(0.0, 1.0) * a,
          color.blue.clamp(0.0, 1.0) * a,
          a);
    } else {
      // even-odd inverts, which would cancel across overlapping merged
      // paths - fill immediately
      _tally('fill-stencil');
      _flushText();
      _stencilThenCover(subs, rule, union: false, cover: (bounds) {
        _coverSolid(bounds, color, a);
      });
    }
  }

  /// Recognizes outer+hole ring structures (each hole's bbox nested in
  /// exactly one outer) and fills them with bridged hole-aware ear clipping
  /// straight into the solid batch. Handles both fill rules: for a one-deep
  /// nesting tree the nonzero (opposite-winding) and even-odd results agree
  /// with cutting the holes out. Returns false - appending nothing - when
  /// the structure is deeper, ambiguous, or the clipping fails.
  bool _pushRings(List<FlatSubpath> subs, PdfColor color, double alpha) {
    if (subs.length > 48) return false;
    const eps = 1.0; // device px slack: thin diagonal rings tie on extents
    final areas = <double>[];
    final boxes = <FlatBounds>[];
    var totalPts = 0;
    for (final sub in subs) {
      totalPts += sub.pointCount;
      areas.add(signedArea2(sub.points));
      boxes.add(FlatBounds.of([sub])!);
    }
    // Small rings only: CAD border/outline pairs are 4-12 points per ring.
    // Big curvy rings usually fail the bridge/clip after O(n^2) work, and
    // one stencil pair paints them faster than the attempt costs.
    if (totalPts > 120) return false;

    double boxArea(FlatBounds b) => (b.right - b.left) * (b.bottom - b.top);
    bool contains(FlatBounds a, FlatBounds b) =>
        a.left - eps <= b.left &&
        a.right + eps >= b.right &&
        a.top - eps <= b.top &&
        a.bottom + eps >= b.bottom;

    // parent = smallest strictly-larger bbox containing this one
    final parent = List<int>.filled(subs.length, -1);
    for (var i = 0; i < subs.length; i++) {
      if (areas[i].abs() < 1e-9) continue; // degenerate sliver: ignore
      var best = -1;
      var bestArea = double.infinity;
      for (var j = 0; j < subs.length; j++) {
        if (j == i || areas[j].abs() < 1e-9) continue;
        final ja = boxArea(boxes[j]);
        if (ja <= boxArea(boxes[i]) + 1e-6) continue;
        if (contains(boxes[j], boxes[i]) && ja < bestArea) {
          best = j;
          bestArea = ja;
        }
      }
      parent[i] = best;
    }
    final holesFor = <int, List<Float64List>>{};
    final tops = <int>[];
    var holeCount = 0;
    for (var i = 0; i < subs.length; i++) {
      if (areas[i].abs() < 1e-9) continue;
      final p = parent[i];
      if (p == -1) {
        tops.add(i);
      } else if (parent[p] == -1) {
        (holesFor[p] ??= []).add(subs[i].points);
        holeCount++;
      } else {
        _tally('rings-fail-depth');
        return false; // deeper nesting (island in hole): stencil handles it
      }
    }
    if (holeCount == 0 || tops.isEmpty) {
      _tally('rings-fail-noholes');
      return false;
    }
    // an unassigned opposite-winding sub overlapping a top-level would
    // cancel under nonzero - the tree can't represent that, so bail
    for (var i = 0; i < tops.length; i++) {
      for (var j = i + 1; j < tops.length; j++) {
        final a = tops[i], b = tops[j];
        if (areas[a].sign == areas[b].sign) continue;
        final apart = boxes[a].right < boxes[b].left ||
            boxes[b].right < boxes[a].left ||
            boxes[a].bottom < boxes[b].top ||
            boxes[b].bottom < boxes[a].top;
        if (!apart) {
          _tally('rings-fail-cancel-risk');
          return false;
        }
      }
    }

    final tris = DoubleBuilder(512);
    for (final t in tops) {
      final holes = holesFor[t];
      final ok = holes == null
          ? earClipPolygon(subs[t].points, tris)
          : earClipWithHoles(subs[t].points, holes, tris);
      if (!ok) {
        _tally('rings-fail-clip');
        return false;
      }
    }
    _ensureSolidBatch();
    final v = tris.view;
    final r = color.red.clamp(0.0, 1.0) * alpha;
    final g = color.green.clamp(0.0, 1.0) * alpha;
    final b = color.blue.clamp(0.0, 1.0) * alpha;
    for (var i = 0; i < v.length; i += 2) {
      _solid.add6(_ndcX(v[i]), _ndcY(v[i + 1]), r, g, b, alpha);
    }
    return true;
  }

  /// Whether the subpaths can fill independently: winding (nonzero) and
  /// parity (even-odd) only interact where interiors overlap, so subpaths
  /// with pairwise-disjoint interiors are just islands. Under nonzero,
  /// same-winding overlaps are additionally fine (they union). Pairs whose
  /// bounding boxes overlap resolve with an exact separating-axis test when
  /// both are convex; anything unresolved falls back to the stencil.
  static bool _independentIslands(List<FlatSubpath> subs, PdfFillRule rule) {
    if (subs.length > 64) return false; // O(k^2) guard
    final signs = <double>[];
    final boxes = <FlatBounds>[];
    for (final sub in subs) {
      signs.add(signedArea2(sub.points).sign);
      boxes.add(FlatBounds.of([sub])!);
    }
    List<bool>? convex;
    for (var i = 0; i < subs.length; i++) {
      if (signs[i] == 0) continue;
      for (var j = i + 1; j < subs.length; j++) {
        if (signs[j] == 0) continue;
        // nonzero: same-direction subpaths union - overlap is harmless
        if (rule == PdfFillRule.nonzero && signs[i] == signs[j]) continue;
        final a = boxes[i], b = boxes[j];
        final apart = a.right < b.left ||
            b.right < a.left ||
            a.bottom < b.top ||
            b.bottom < a.top;
        if (apart) continue;
        // bbox overlap: prove the interiors disjoint or give up
        if (subs[i].pointCount > 16 || subs[j].pointCount > 16) return false;
        convex ??= [
          for (final sub in subs)
            sub.pointCount <= 16 && isConvexPolygon([sub]),
        ];
        if (!convex[i] || !convex[j]) return false;
        if (!convexInteriorsDisjoint(subs[i].points, subs[j].points)) {
          return false;
        }
      }
    }
    return true;
  }

  /// Routes a fill that failed the fast paths: same-color stencil batch for
  /// nonzero, immediate stencil-then-cover for even-odd.
  void _fillStencilFallback(
      List<FlatSubpath> subs, PdfColor color, PdfFillRule rule, double a) {
    if (rule == PdfFillRule.nonzero) {
      _appendStencilFill(
          subs,
          color.red.clamp(0.0, 1.0) * a,
          color.green.clamp(0.0, 1.0) * a,
          color.blue.clamp(0.0, 1.0) * a,
          a);
    } else {
      _flushText();
      _stencilThenCover(subs, rule, union: false, cover: (bounds) {
        _coverSolid(bounds, color, a);
      });
    }
  }

  /// Opens (or re-targets) the same-color stencil batch, flushing the
  /// pending one when the premultiplied color or clip changed.
  void _openStencilBatch(double r, double g, double b, double a) {
    if (_textOpen &&
        (r != _textR ||
            g != _textG ||
            b != _textB ||
            a != _textA ||
            !_textScissor!.equals(_scissor))) {
      _flushText();
    }
    _flushSolid(); // only one deferred batch open at a time
    if (!_textOpen) {
      _textOpen = true;
      _textR = r;
      _textG = g;
      _textB = b;
      _textA = a;
      _textScissor = _scissor;
      _textBounds = null;
    }
  }

  void _growTextBounds(double x, double y) {
    final b = _textBounds;
    if (b == null) {
      _textBounds = FlatBounds(x, y, x, y);
    } else {
      b.include(x, y);
    }
  }

  /// Admits one element (bbox [l],[t],[r],[b]) into the stencil batch,
  /// flushing first when merging it would spread the cover quad to more
  /// than ~3x the accumulated content area. The cover pass rasterizes the
  /// union bbox at MSAA rate, so a batch spanning distant page corners
  /// costs far more fill than the draw calls it saves.
  void _admitToBatch(double l, double t, double r, double b, double red,
      double green, double blue, double alpha) {
    final elemArea = math.max((r - l) * (b - t), 1.0);
    final bounds = _textBounds;
    if (_textOpen && bounds != null) {
      final unionW = math.max(bounds.right, r) - math.min(bounds.left, l);
      final unionH = math.max(bounds.bottom, b) - math.min(bounds.top, t);
      if (unionW * unionH > 3 * (_textCoverage + elemArea) + 4096) {
        _flushText();
      }
    }
    _openStencilBatch(red, green, blue, alpha);
    _growTextBounds(l, t);
    _growTextBounds(r, b);
    _textCoverage += elemArea;
  }

  /// Adds a nonzero fill to the pending same-color stencil batch, flushing
  /// first when the color or clip changed.
  void _appendStencilFill(
      List<FlatSubpath> subs, double r, double g, double b, double a) {
    final bounds = FlatBounds.of(subs);
    if (bounds == null) return;
    _admitToBatch(
        bounds.left, bounds.top, bounds.right, bounds.bottom, r, g, b, a);
    appendFanTriangles(subs, _text);
  }

  /// Appends a filled text run using cached em-space glyph triangles: each
  /// distinct outline triangulates once per tolerance bucket, then every
  /// occurrence is a 6-multiply affine per vertex. Exactly-triangulated
  /// glyphs (the common case) go straight into the solid batch - no
  /// stencil, no cover; fan-form glyphs go through the stencil batch in a
  /// second pass so the two deferred batches don't ping-pong.
  void _appendGlyphRun(
      PdfTextRun run, PdfMatrix m, double scale, double alpha) {
    final red = run.color.red.clamp(0.0, 1.0) * alpha;
    final green = run.color.green.clamp(0.0, 1.0) * alpha;
    final blue = run.color.blue.clamp(0.0, 1.0) * alpha;
    final emTol = 0.2 / scale;
    var sawFan = false;
    _ensureSolidBatch();
    for (final glyph in run.glyphs!) {
      final outline = glyph.outline;
      if (outline == null) continue;
      final fan = _glyphFanFor(outline, emTol);
      if (fan.tris.isEmpty) continue;
      if (!fan.exact) {
        sawFan = true;
        continue;
      }
      // (p + offset)·M = p·A + offset·M  (A = linear part of M)
      final tx = m.transformX(glyph.offset, glyph.offsetY);
      final ty = m.transformY(glyph.offset, glyph.offsetY);
      final tris = fan.tris;
      for (var i = 0; i + 5 < tris.length; i += 6) {
        _solid
          ..add6(_ndcX(tris[i] * m.a + tris[i + 1] * m.c + tx),
              _ndcY(tris[i] * m.b + tris[i + 1] * m.d + ty), red, green, blue,
              alpha)
          ..add6(_ndcX(tris[i + 2] * m.a + tris[i + 3] * m.c + tx),
              _ndcY(tris[i + 2] * m.b + tris[i + 3] * m.d + ty), red, green,
              blue, alpha)
          ..add6(_ndcX(tris[i + 4] * m.a + tris[i + 5] * m.c + tx),
              _ndcY(tris[i + 4] * m.b + tris[i + 5] * m.d + ty), red, green,
              blue, alpha);
      }
    }
    if (!sawFan) return;
    for (final glyph in run.glyphs!) {
      final outline = glyph.outline;
      if (outline == null) continue;
      final fan = _glyphFanFor(outline, emTol);
      if (fan.exact || fan.tris.isEmpty) continue;
      final tx = m.transformX(glyph.offset, glyph.offsetY);
      final ty = m.transformY(glyph.offset, glyph.offsetY);
      final c0x = fan.left * m.a + fan.top * m.c + tx;
      final c0y = fan.left * m.b + fan.top * m.d + ty;
      final c1x = fan.right * m.a + fan.top * m.c + tx;
      final c1y = fan.right * m.b + fan.top * m.d + ty;
      final c2x = fan.left * m.a + fan.bottom * m.c + tx;
      final c2y = fan.left * m.b + fan.bottom * m.d + ty;
      final c3x = fan.right * m.a + fan.bottom * m.c + tx;
      final c3y = fan.right * m.b + fan.bottom * m.d + ty;
      final l = math.min(math.min(c0x, c1x), math.min(c2x, c3x));
      final r = math.max(math.max(c0x, c1x), math.max(c2x, c3x));
      final t = math.min(math.min(c0y, c1y), math.min(c2y, c3y));
      final b = math.max(math.max(c0y, c1y), math.max(c2y, c3y));
      _admitToBatch(l, t, r, b, red, green, blue, alpha);
      final tris = fan.tris;
      for (var i = 0; i < tris.length; i += 2) {
        final x = tris[i], y = tris[i + 1];
        _text.add2(x * m.a + y * m.c + tx, x * m.b + y * m.d + ty);
      }
    }
  }

  static final _glyphFans = Expando<_GlyphFan>('pdfGpuGlyphFans');

  /// Em-space triangles for [outline], cached on the outline object.
  /// Rebuilt when the requested tolerance leaves the cached bucket (finer
  /// is accepted down to 8x - extra vertices are cheap, reflattening isn't).
  ///
  /// Preferred form is an exact triangulation (ear clip, holes bridged via
  /// a bbox nesting tree) - those triangles go straight into the solid
  /// batch with no stencil or cover pass. Outlines that defeat the clipper
  /// (self-intersections, deep nesting) fall back to fan triangles for the
  /// stencil path.
  _GlyphFan _glyphFanFor(PdfPath outline, double emTol) {
    final cached = _glyphFans[outline];
    if (cached != null &&
        cached.tolerance <= emTol * 1.01 &&
        cached.tolerance >= emTol / 8) {
      _tally('glyph-cache-hit');
      return cached;
    }
    _tally('glyph-flatten');
    final subs = flattenPath(outline, PdfMatrix.identity, tolerance: emTol);
    final b = FlatBounds.of(subs);
    final tris = DoubleBuilder(128);
    final exact = b != null && _clipGlyphExact(subs, tris);
    if (!exact) {
      tris.clear();
      appendFanTriangles(subs, tris);
    }
    final fan = _GlyphFan(
      emTol,
      Float64List.fromList(tris.view),
      b?.left ?? 0,
      b?.top ?? 0,
      b?.right ?? 0,
      b?.bottom ?? 0,
      exact: exact,
    );
    _glyphFans[outline] = fan;
    _tally(exact ? 'glyph-exact' : 'glyph-fan');
    return fan;
  }

  /// Exact em-space triangulation of a glyph: outer contours matched with
  /// their holes by bbox nesting (letters with counters like o/a/e/4),
  /// each clipped independently. False when the structure is deeper than
  /// outer+hole or any clip fails.
  static bool _clipGlyphExact(List<FlatSubpath> subs, DoubleBuilder out) {
    if (subs.isEmpty) return false;
    if (subs.length == 1) return earClipPolygon(subs[0].points, out);
    final boxes = <FlatBounds>[];
    var totalPts = 0;
    for (final sub in subs) {
      totalPts += sub.pointCount;
      boxes.add(FlatBounds.of([sub])!);
    }
    if (subs.length > 8 || totalPts > 200) return false;
    double boxArea(FlatBounds b) => (b.right - b.left) * (b.bottom - b.top);
    // em-space outlines are ~unit scale; tie slack accordingly
    const eps = 1e-4;
    final parent = List<int>.filled(subs.length, -1);
    for (var i = 0; i < subs.length; i++) {
      var best = -1;
      var bestArea = double.infinity;
      for (var j = 0; j < subs.length; j++) {
        if (j == i || boxArea(boxes[j]) <= boxArea(boxes[i])) continue;
        if (boxes[j].left - eps <= boxes[i].left &&
            boxes[j].right + eps >= boxes[i].right &&
            boxes[j].top - eps <= boxes[i].top &&
            boxes[j].bottom + eps >= boxes[i].bottom &&
            boxArea(boxes[j]) < bestArea) {
          best = j;
          bestArea = boxArea(boxes[j]);
        }
      }
      parent[i] = best;
    }
    final holesFor = <int, List<Float64List>>{};
    final tops = <int>[];
    for (var i = 0; i < subs.length; i++) {
      final p = parent[i];
      if (p == -1) {
        tops.add(i);
      } else if (parent[p] == -1) {
        (holesFor[p] ??= []).add(subs[i].points);
      } else {
        return false; // island in a counter (rare): stencil handles it
      }
    }
    for (final t in tops) {
      final holes = holesFor[t];
      final ok = holes == null
          ? earClipPolygon(subs[t].points, out)
          : earClipWithHoles(subs[t].points, holes, out);
      if (!ok) return false;
    }
    return true;
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
    _flushText();
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
      _solid.add6(
          _ndcX(dx),
          _ndcY(dy),
          v.color.red.clamp(0.0, 1.0) * a,
          v.color.green.clamp(0.0, 1.0) * a,
          v.color.blue.clamp(0.0, 1.0) * a,
          a);
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
    final triangles = _scratch..clear();
    appendStrokeTriangles(
        subs, width, stroke.cap, stroke.join, stroke.miterLimit, triangles);
    if (triangles.isEmpty) return;
    if (a >= 1) {
      // opaque: overlapping join geometry is invisible, batch directly
      _ensureSolidBatch();
      final t = triangles.view;
      final r = color.red.clamp(0.0, 1.0);
      final g = color.green.clamp(0.0, 1.0);
      final b = color.blue.clamp(0.0, 1.0);
      for (var i = 0; i < t.length; i += 2) {
        _solid.add6(_ndcX(t[i]), _ndcY(t[i + 1]), r, g, b, 1.0);
      }
    } else {
      // translucent: stencil the union so overlaps don't double-blend
      _flushText();
      final t = triangles.view;
      _stencilRaw(t, rule: PdfFillRule.nonzero, union: true);
      _coverSolid(_boundsOfTriangles(t), color, a);
    }
  }

  @override
  void drawText(PdfTextRun run) {
    if (run.invisible) return;
    _tally('text-runs');
    if (run.glyphs == null) {
      _count('substituted-text-skipped');
      return;
    }
    final a = _alphaScale.clamp(0.0, 1.0);

    if (run.fill && run.gradient == null && run.strokeColor == null) {
      // The batched common case: cached em-space glyph triangles, one affine
      // per run, merged into the pending same-color batch.
      final runToDevice = run.transform.concat(pageToDevice);
      final scale = runToDevice.scaleFactor;
      if (scale > 0 && scale.isFinite) {
        _appendGlyphRun(run, runToDevice, scale, a);
        return;
      }
    }

    final subs = <FlatSubpath>[];
    for (final glyph in run.glyphs!) {
      final outline = glyph.outline;
      if (outline == null) continue;
      final emToDevice = PdfMatrix.translation(glyph.offset, glyph.offsetY)
          .concat(run.transform)
          .concat(pageToDevice);
      subs.addAll(flattenPath(outline, emToDevice, tolerance: 0.2));
    }
    if (subs.isEmpty) return;

    // gradient fills / stroked text: immediate stencil-then-cover
    _flushText();
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
      final triangles = _scratch..clear();
      appendStrokeTriangles(
          subs,
          math.max(run.strokeWidth * pageToDevice.scaleFactor, 1.0),
          0,
          0,
          10,
          triangles);
      if (!triangles.isEmpty) {
        final t = triangles.view;
        _stencilRaw(t, rule: PdfFillRule.nonzero, union: true);
        _coverSolid(_boundsOfTriangles(t), run.strokeColor!, a);
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
    _flushText();
    _flushSolid();
    _applyScissor(_scissor);
    _setStencilState(_stencilDefault);

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

    _bindPipeline(pipelines.texture);
    _setBlendState(_blendSrcOver);
    pass
      ..bindUniform(pipelines.textureFragInfo,
          _emplace(info.buffer.asByteData()))
      ..bindTexture(pipelines.textureSampler, texture,
          sampler: gpu.SamplerOptions(
              minFilter: gpu.MinMagFilter.linear,
              magFilter: gpu.MinMagFilter.linear))
      ..bindVertexBuffer(_emplace(verts.buffer.asByteData()), 6)
      ..draw();
    _tally('draw-image');
    pass.clearBindings();
    _boundPipeline = null;
  }

  /// Flushes any pending batched geometry - call once after interpretation.
  void finish() {
    _flushText();
    _flushSolid();
  }

  // ---- pass-state elision ---------------------------------------------------

  static const _blendSrcOver = 0;
  static const _blendNoWrite = 1;
  static const _stencilDefault = 0;
  static const _stencilNonzero = 1;
  static const _stencilEvenOdd = 2;
  static const _stencilUnion = 3;
  static const _stencilCover = 4;

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

  void _bindPipeline(gpu.RenderPipeline pipeline) {
    if (identical(_boundPipeline, pipeline)) return;
    pass.bindPipeline(pipeline);
    _boundPipeline = pipeline;
  }

  void _setBlendState(int state) {
    if (_blendState == state) return;
    pass.setColorBlendEquation(
        state == _blendSrcOver ? _srcOver : _noColorWrite);
    _blendState = state;
  }

  void _setStencilState(int state) {
    if (_stencilState == state) return;
    switch (state) {
      case _stencilDefault:
        pass.setStencilConfig(gpu.StencilConfig(
          compareFunction: gpu.CompareFunction.always,
          depthStencilPassOperation: gpu.StencilOperation.keep,
        ));
      case _stencilNonzero:
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
      case _stencilEvenOdd:
        pass.setStencilConfig(gpu.StencilConfig(
          compareFunction: gpu.CompareFunction.always,
          depthStencilPassOperation: gpu.StencilOperation.invert,
        ));
      case _stencilUnion:
        // union coverage: any hit marks the pixel, winding irrelevant
        pass.setStencilConfig(gpu.StencilConfig(
          compareFunction: gpu.CompareFunction.always,
          depthStencilPassOperation: gpu.StencilOperation.incrementWrap,
        ));
      case _stencilCover:
        // paint where non-zero, zeroing behind the draw so the buffer is
        // clean for the next path without an explicit clear
        pass.setStencilConfig(gpu.StencilConfig(
          compareFunction: gpu.CompareFunction.notEqual,
          depthStencilPassOperation: gpu.StencilOperation.zero,
          stencilFailureOperation: gpu.StencilOperation.keep,
        ));
    }
    _stencilState = state;
  }

  void _applyScissor(_Rect s) {
    final x = s.left.floor().clamp(0, widthPx);
    final y = s.top.floor().clamp(0, heightPx);
    final r = s.right.ceil().clamp(0, widthPx);
    final b = s.bottom.ceil().clamp(0, heightPx);
    final w = math.max(r - x, 0), h = math.max(b - y, 0);
    if (x == _appliedScissorX &&
        y == _appliedScissorY &&
        w == _appliedScissorW &&
        h == _appliedScissorH) {
      return;
    }
    pass.setScissor(gpu.Scissor(x: x, y: y, width: w, height: h));
    _appliedScissorX = x;
    _appliedScissorY = y;
    _appliedScissorW = w;
    _appliedScissorH = h;
  }

  // ---- batches ---------------------------------------------------------------

  static List<double> _premul(PdfColor color, double alpha) => [
        color.red.clamp(0.0, 1.0) * alpha,
        color.green.clamp(0.0, 1.0) * alpha,
        color.blue.clamp(0.0, 1.0) * alpha,
        alpha,
      ];

  void _ensureSolidBatch() {
    _flushText();
    if (_solidScissor != null && !_solidScissor!.equals(_scissor)) {
      _flushSolid();
    }
    _solidScissor ??= _scissor;
  }

  /// Ear-clips a single-subpath polygon straight into the solid batch.
  /// False when it doesn't qualify (big/self-intersecting/degenerate).
  bool _pushEarClipped(FlatSubpath sub, PdfColor color, double alpha) {
    final tris = _scratch..clear();
    if (!earClipPolygon(sub.points, tris)) return false;
    _ensureSolidBatch();
    final t = tris.view;
    final r = color.red.clamp(0.0, 1.0) * alpha;
    final g = color.green.clamp(0.0, 1.0) * alpha;
    final b = color.blue.clamp(0.0, 1.0) * alpha;
    for (var i = 0; i < t.length; i += 2) {
      _solid.add6(_ndcX(t[i]), _ndcY(t[i + 1]), r, g, b, alpha);
    }
    return true;
  }

  void _pushSolidFan(List<FlatSubpath> subs, PdfColor color, double alpha) {
    _ensureSolidBatch();
    final fan = _scratch..clear();
    appendFanTriangles(subs, fan);
    final t = fan.view;
    final r = color.red.clamp(0.0, 1.0) * alpha;
    final g = color.green.clamp(0.0, 1.0) * alpha;
    final b = color.blue.clamp(0.0, 1.0) * alpha;
    for (var i = 0; i < t.length; i += 2) {
      _solid.add6(_ndcX(t[i]), _ndcY(t[i + 1]), r, g, b, alpha);
    }
  }

  void _flushSolid() {
    _solidFlushes++; // invalidates any in-progress shape-cache capture
    if (_solid.isEmpty) {
      _solidScissor = null;
      return;
    }
    _applyScissor(_solidScissor ?? _scissor);
    _setStencilState(_stencilDefault);
    _bindPipeline(pipelines.solid);
    _setBlendState(_blendSrcOver);
    pass
      ..bindVertexBuffer(_emplace(_solid.bytes), _solid.length ~/ 6)
      ..draw();
    _tally('draw-solid-batch');
    _tally('verts-solid', _solid.length ~/ 6);
    _solid.clear();
    _solidScissor = null;
  }

  /// Flushes the pending coalesced text runs as one stencil+cover pair.
  void _flushText() {
    if (!_textOpen) return;
    _textOpen = false;
    _textCoverage = 0;
    final bounds = _textBounds;
    _textBounds = null;
    if (bounds == null || _text.isEmpty) {
      _text.clear();
      return;
    }
    final scissor = _textScissor ?? _scissor;
    _stencilRaw(_text.view,
        rule: PdfFillRule.nonzero, union: false, scissor: scissor);
    _coverSolidPremul(bounds, _textR, _textG, _textB, _textA,
        scissor: scissor);
    _text.clear();
    _tally('text-batches');
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
    final fan = _scratch..clear();
    appendFanTriangles(subs, fan);
    if (fan.isEmpty) return;
    _stencilRaw(fan.view, rule: rule, union: union);
    cover(bounds);
  }

  void _stencilRaw(Float64List triangles,
      {required PdfFillRule rule, required bool union, _Rect? scissor}) {
    _flushSolid();
    _applyScissor(scissor ?? _scissor);
    final verts = Float32List(triangles.length);
    for (var i = 0; i < triangles.length; i += 2) {
      verts[i] = _ndcX(triangles[i]);
      verts[i + 1] = _ndcY(triangles[i + 1]);
    }
    _bindPipeline(pipelines.stencil);
    _setBlendState(_blendNoWrite);
    _setStencilState(union
        ? _stencilUnion
        : rule == PdfFillRule.evenOdd
            ? _stencilEvenOdd
            : _stencilNonzero);
    pass
      ..bindVertexBuffer(
          _emplace(verts.buffer.asByteData()), verts.length ~/ 2)
      ..draw();
    _tally('draw-stencil');
    _tally('verts-stencil', verts.length ~/ 2);
  }

  List<double> _coverQuad(FlatBounds b) {
    final l = _ndcX(b.left - 1), r = _ndcX(b.right + 1);
    final t = _ndcY(b.top - 1), bo = _ndcY(b.bottom + 1);
    return [l, t, r, t, r, bo, l, t, r, bo, l, bo];
  }

  void _coverSolid(FlatBounds? bounds, PdfColor color, double alpha) {
    if (bounds == null) return;
    _coverSolidPremul(
        bounds,
        color.red.clamp(0.0, 1.0) * alpha,
        color.green.clamp(0.0, 1.0) * alpha,
        color.blue.clamp(0.0, 1.0) * alpha,
        alpha);
  }

  void _coverSolidPremul(
      FlatBounds bounds, double r, double g, double b, double a,
      {_Rect? scissor}) {
    _applyScissor(scissor ?? _scissor);
    _setStencilState(_stencilCover);
    final quad = _coverQuad(bounds);
    final verts = Float32List(6 * 6);
    for (var i = 0; i < 6; i++) {
      verts[i * 6] = quad[2 * i];
      verts[i * 6 + 1] = quad[2 * i + 1];
      verts[i * 6 + 2] = r;
      verts[i * 6 + 3] = g;
      verts[i * 6 + 4] = b;
      verts[i * 6 + 5] = a;
    }
    _bindPipeline(pipelines.solid);
    _setBlendState(_blendSrcOver);
    pass
      ..bindVertexBuffer(_emplace(verts.buffer.asByteData()), 6)
      ..draw();
    _tally('draw-cover');
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
    _applyScissor(_scissor);
    _setStencilState(_stencilCover);
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

    _bindPipeline(pipelines.gradient);
    _setBlendState(_blendSrcOver);
    pass
      ..bindUniform(
          pipelines.gradientInfo, _emplace(info.buffer.asByteData()))
      ..bindTexture(pipelines.gradientLut, _lutFor(gradient),
          sampler: gpu.SamplerOptions(
              minFilter: gpu.MinMagFilter.linear,
              magFilter: gpu.MinMagFilter.linear))
      ..bindVertexBuffer(_emplace(verts.buffer.asByteData()), 6)
      ..draw();
    _tally('draw-cover-gradient');
    pass.clearBindings();
    _boundPipeline = null;
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

  static FlatBounds? _boundsOfTriangles(Float64List triangles) {
    if (triangles.isEmpty) return null;
    final b =
        FlatBounds(triangles[0], triangles[1], triangles[0], triangles[1]);
    for (var i = 2; i < triangles.length; i += 2) {
      b.include(triangles[i], triangles[i + 1]);
    }
    return b;
  }
}

/// Translation-invariant identity of a small filled shape: fill rule,
/// subpath structure, and outline points quantized to 1/64 px relative to
/// the first point. Two fills with equal keys are the same shape at
/// different offsets (within subpixel), so one triangulation serves both.
class _ShapeKey {
  _ShapeKey._(this.rule, this.counts, this.deltas, this.anchorX, this.anchorY)
      : hashCode = _hash(rule, counts, deltas);

  /// Null when the path is too large to be a plausible repeated symbol.
  static _ShapeKey? of(List<FlatSubpath> subs, PdfFillRule rule) {
    if (subs.length > 16) return null;
    var total = 0;
    for (final sub in subs) {
      total += sub.pointCount; // fills close implicitly; closed-ness moot
    }
    if (total > 200) return null;
    final anchorX = subs[0].points[0], anchorY = subs[0].points[1];
    final counts = Int32List(subs.length);
    final deltas = Int32List(total * 2);
    var w = 0;
    for (var s = 0; s < subs.length; s++) {
      final pts = subs[s].points;
      counts[s] = pts.length ~/ 2;
      for (var i = 0; i < pts.length; i += 2) {
        final qx = ((pts[i] - anchorX) * 64).roundToDouble();
        final qy = ((pts[i + 1] - anchorY) * 64).roundToDouble();
        if (qx.abs() > 2e9 || qy.abs() > 2e9) return null;
        deltas[w++] = qx.toInt();
        deltas[w++] = qy.toInt();
      }
    }
    return _ShapeKey._(rule, counts, deltas, anchorX, anchorY);
  }

  final PdfFillRule rule;
  final Int32List counts;
  final Int32List deltas;
  final double anchorX, anchorY;

  @override
  final int hashCode;

  static int _hash(PdfFillRule rule, Int32List counts, Int32List deltas) {
    var h = 0xcbf29ce484222325 ^ rule.index;
    for (final c in counts) {
      h = (h ^ c) * 0x100000001b3;
    }
    for (final d in deltas) {
      h = (h ^ (d & 0xffffffff)) * 0x100000001b3;
    }
    return h;
  }

  @override
  bool operator ==(Object other) {
    if (other is! _ShapeKey ||
        other.hashCode != hashCode ||
        other.rule != rule ||
        other.counts.length != counts.length ||
        other.deltas.length != deltas.length) {
      return false;
    }
    for (var i = 0; i < counts.length; i++) {
      if (other.counts[i] != counts[i]) return false;
    }
    for (var i = 0; i < deltas.length; i++) {
      if (other.deltas[i] != deltas[i]) return false;
    }
    return true;
  }
}

/// Cached em-space tessellation of one glyph outline: fan triangles plus
/// their bounds, valid for tolerances within the cached bucket.
class _GlyphFan {
  const _GlyphFan(this.tolerance, this.tris, this.left, this.top, this.right,
      this.bottom,
      {required this.exact});

  final double tolerance;
  final Float64List tris;
  final double left, top, right, bottom;

  /// True when [tris] is an exact triangulation (solid batch, no stencil);
  /// false when it is fan triangles for the stencil path.
  final bool exact;
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
