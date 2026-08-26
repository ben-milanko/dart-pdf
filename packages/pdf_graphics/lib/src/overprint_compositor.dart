// The CMYK/spot colorant buffer that makes overprint faithful (issue #502).
//
// Overprint (§8.6.7) is subtractive: an overprinting paint writes only the
// device colorants its colour space specifies and leaves the rest of the
// backdrop's colorants alone. In sRGB that is not merely hard, it is
// under-determined - a DeviceCMYK green and a spot green can be the identical
// pixels yet overprint to different results, which is exactly why the
// `BlendMode.darken` approximation hit a ceiling (see
// doc/dev-log/2026-07-23-overprint-rgb-ceiling.md).
//
// This resolves overprint one layer *above* the painting device, where the
// colour spaces are still known:
//
//   1. every draw records the colorants it leaves behind into a page-sized
//      colorant raster ([PdfColorantRaster]), interned into a palette;
//   2. an overprinting draw reads the backdrop colorants under its own
//      coverage, composites in ink space ([PdfInkColorants.over]) and
//      converts the result back to sRGB;
//   3. when that result is one colour across the whole draw, the interpreter
//      paints it as an ordinary opaque fill and tells the device *not* to
//      apply its RGB approximation. Otherwise the compositor declines and the
//      device's `darken` stand-in still applies.
//
// Converting back to sRGB prefers an exact answer over a round trip: if the
// composite equals the backdrop's colorants the backdrop's own rendered colour
// is reused, and if it equals the ink's the ink's is - so "the overprint
// changed nothing here" and "the ink knocked the backdrop out" both land on
// pixels the renderer already produces elsewhere. Only a genuinely new
// combination goes through [colorantsToSrgb].
//
// Everything here is pure Dart and sits in pdf_graphics, so the VM, the render
// worker and the web all get the same result, and the strip and canvas devices
// agree by construction (they receive the already-resolved colour).
import 'dart:math' as math;
import 'dart:typed_data';

import 'color.dart';
import 'color_context.dart';
import 'colorants.dart';
import 'device.dart';
import 'matrix.dart';
import 'path.dart';
import 'raster/colorant_raster.dart';
import 'shading.dart';

class PdfOverprintRegion {
  const PdfOverprintRegion(this.path, this.color);

  final PdfPath path;
  final PdfColor color;
}

/// Resolves overprint against a colorant buffer for one page.
class PdfOverprintCompositor {
  PdfOverprintCompositor._(this._raster, this._colorContext);

  /// Builds a compositor covering the page box `[left, bottom, right, top]`
  /// in PDF user space, or null when the box is degenerate.
  ///
  /// [maxDimension] caps the buffer's longer side. The buffer never reaches a
  /// screen: it only has to keep neighbouring painted regions apart, and it
  /// pays per covered cell on *every* draw of every page that declares
  /// overprint - which on print-oriented content is most of them, since `/op`
  /// is routinely set defensively. 384 puts an A4 page at ~0.5 cells per point.
  ///
  /// Resolution is not the sensitivity it looks like: [PdfColorantRaster]
  /// selects a backdrop by *area share*, not by eroding a fixed number of
  /// cells, so a coarser grid does not start losing small shapes. GWG030 grades
  /// identically from 256 up.
  static PdfOverprintCompositor? forPageBox(
      double left, double bottom, double right, double top,
      {int maxDimension = 384, PdfColorContext? colorContext}) {
    final w = right - left, h = top - bottom;
    if (!w.isFinite || !h.isFinite || w <= 0 || h <= 0) return null;
    final scale = maxDimension / (w > h ? w : h);
    final width = (w * scale).round().clamp(1, maxDimension);
    final height = (h * scale).round().clamp(1, maxDimension);
    // y is flipped so cell rows run top-down; nothing reads the buffer
    // geometrically, but matching raster convention keeps debugging sane.
    final matrix = PdfMatrix(scale, 0, 0, -scale, -left * scale, top * scale);
    return PdfOverprintCompositor._(
        PdfColorantRaster(
            width: width,
            height: height,
            mapping: ColorantPageMapping(matrix, scale)),
        colorContext);
  }

  final PdfColorantRaster _raster;
  final PdfColorContext? _colorContext;

  /// Palette entry 0 is bare paper, entry 1 the "colorants unknown" sentinel
  /// (images, gradients, transparency groups, translucent paint, colour spaces
  /// with no colorant reading). An overprint landing on unknown declines.
  static const int _paperIndex = 0;
  static const int _unknownIndex = 1;
  static const int _transparentIndex = 2;

  final List<PdfColorants> _paletteColorants = [
    PdfColorants.none,
    PdfColorants.none,
    PdfColorants.none,
  ];
  final List<PdfColor> _paletteColor = <PdfColor>[
    const PdfColor(1, 1, 1),
    const PdfColor(1, 1, 1),
    const PdfColor(1, 1, 1),
  ];
  final Map<_PaletteKey, int> _paletteIndex = {};

  /// CMYK equivalents of the spot colorants seen on the page, by name.
  final Map<String, List<double>> _spotEquivalents = {};

  /// The spot equivalents learned so far, for a caller that has to convert a
  /// composite vector back to sRGB itself (image overprint builds its
  /// substitute raster outside the buffer - see `image_colorants.dart`).
  Map<String, List<double>> get spotEquivalents => _spotEquivalents;

  /// Display colour of one uniform known backdrop under [path], or null when
  /// the region is clipped out, varies, or contains content whose colorants
  /// are unknown. Used to seed non-isolated transparency groups.
  PdfColor? uniformBackdrop(PdfPath path) {
    final spans = _raster.fillSpans(path, evenOdd: false);
    final backdrops = _raster.backdropUnder(spans, bleedFraction: 0);
    if (backdrops == null ||
        backdrops.length != 1 ||
        backdrops.first == _unknownIndex) {
      return null;
    }
    return _paletteColor[backdrops.first];
  }

  /// Nesting depth of transparency groups and soft-mask captures. Their
  /// contents composite through a separate buffer, so the page's colorants
  /// are unknowable while one is open - draws inside still mark their
  /// coverage unknown, which is what makes a later overprint decline.
  int _suspended = 0;

  final List<_TransparencyContext> _groups = [];

  /// Opens a transparency-group colorant surface.
  ///
  /// Returns true when an opaque non-Normal group blend will be resolved here
  /// in its declared transparency blending space. In that case the painting
  /// device must not apply the same blend mode a second time.
  bool beginTransparencyGroup({
    required PdfBlendMode blendMode,
    required bool isolated,
    required bool knockout,
    required bool opaque,
  }) {
    final enclosing = _groups.isEmpty ? null : _groups.last;
    Uint16List? accumulated;
    if (enclosing != null && enclosing.knockout) {
      accumulated = Uint16List.fromList(_raster.cells);
      _raster.cells.setAll(0, enclosing.initialCells);
    }
    final external = Uint16List.fromList(_raster.cells);
    if (isolated) {
      _raster.cells.fillRange(0, _raster.cells.length, _transparentIndex);
    }
    final initial = Uint16List.fromList(_raster.cells);
    _groups.add(_TransparencyContext(
      blendMode: blendMode,
      isolated: isolated,
      knockout: knockout,
      opaque: opaque,
      externalCells: external,
      initialCells: initial,
      accumulatedCells: accumulated,
      touched: Uint8List(_raster.cells.length),
    ));
    return opaque && blendMode != PdfBlendMode.normal;
  }

  void endTransparencyGroup() {
    if (_groups.isEmpty) return;
    final group = _groups.removeLast();
    var result = Uint16List.fromList(_raster.cells);
    if (group.isolated) {
      final composed = group.externalCells;
      for (var i = 0; i < composed.length; i++) {
        if (group.touched[i] != 0) composed[i] = result[i];
      }
      result = composed;
    }
    final accumulated = group.accumulatedCells;
    if (accumulated != null) {
      for (var i = 0; i < accumulated.length; i++) {
        if (group.touched[i] != 0) accumulated[i] = result[i];
      }
      result = accumulated;
    }
    _raster.cells.setAll(0, result);
    if (_groups.isNotEmpty) {
      final parent = _groups.last;
      for (var i = 0; i < parent.touched.length; i++) {
        if (group.touched[i] != 0) parent.touched[i] = 1;
      }
    }
  }

  /// Nesting depth of soft-mask *form* execution. A mask group's content never
  /// puts colorants on the page - it only becomes an alpha channel for what
  /// follows - so the buffer must not record it at all, which also keeps a
  /// page of image soft masks from paying to rasterize content that can never
  /// be a backdrop. (Content painted *through* an active mask is a different
  /// thing, and is handled by [_resolve]'s opacity test.)
  int _muted = 0;

  /// Draws rasterized so far, against [_maxDraws]. A page with hundreds of
  /// thousands of paths that also happens to set /op would otherwise pay for
  /// a buffer update per path; past the cap the compositor stops resolving
  /// (the device keeps its approximation) instead of slowing the render down.
  int _draws = 0;
  static const int _maxDraws = 20000;
  bool get _exhausted => _draws >= _maxDraws;

  /// Pushes the clip, mirroring `q` (and every nested-content bracket the
  /// interpreter saves the device across: form XObjects, tiling-pattern cells,
  /// Type3 CharProcs, soft-mask forms, appearance streams). A `W n` inside one
  /// of those need not be closed by a `Q`, so without the bracket the narrowed
  /// clip would leak out and the buffer would stop recording colorants for
  /// everything drawn after it.
  void save() => _raster.save();

  void restore() => _raster.restore();

  void beginIsolated() => _suspended++;

  void endIsolated() {
    if (_suspended > 0) _suspended--;
  }

  /// Brackets a soft-mask form's own content; see [_muted].
  void beginMaskCapture() => _muted++;

  void endMaskCapture() {
    if (_muted > 0) _muted--;
  }

  void clipPath(PdfPath path, PdfFillRule rule) {
    if (_exhausted || _muted != 0) return;
    _draws++;
    _raster
        .clipTo(_raster.fillSpans(path, evenOdd: rule == PdfFillRule.evenOdd));
  }

  /// Records the spot colorants an ink introduces so a composite vector that
  /// mixes them can still be converted back to sRGB.
  void _learnSpots(PdfInkColorants ink) {
    final names = ink.colorants.spots;
    for (var i = 0; i < names.length && i < ink.spotEquivalents.length; i++) {
      _spotEquivalents.putIfAbsent(names[i], () => ink.spotEquivalents[i]);
    }
  }

  int _intern(PdfColorants colorants, PdfColor color) {
    final key = _PaletteKey(colorants, color);
    final hit = _paletteIndex[key];
    if (hit != null) return hit;
    // Uint16 cells: past 65535 distinct (colorants, colour) pairs give up and
    // record "unknown" rather than aliasing onto an unrelated entry.
    if (_paletteColorants.length >= 0xFFFF) return _unknownIndex;
    final index = _paletteColorants.length;
    _paletteColorants.add(colorants);
    _paletteColor.add(color);
    _paletteIndex[key] = index;
    return index;
  }

  /// Resolves a fill. Returns the colour to paint when the overprint composite
  /// is a single colour across the draw, or null to leave the device's own
  /// handling (its RGB approximation, or plain painting when not overprinting)
  /// in charge.
  PdfColor? fill(
      PdfPath path, PdfFillRule rule, PdfColor color, PdfInkColorants? ink,
      {PdfInkColorants? blendInk,
      required bool overprint,
      required int mode,
      required bool opaque}) {
    _skipPaint = false;
    _spatialPaint = null;
    return _resolve(
        () => _raster.fillSpans(path, evenOdd: rule == PdfFillRule.evenOdd),
        color,
        ink,
        blendInk: blendInk,
        overprint: overprint,
        mode: mode,
        opaque: opaque);
  }

  bool _skipPaint = false;
  List<PdfOverprintRegion>? _spatialPaint;
  List<PdfOverprintRegion>? _gradientSpatialPaint;
  PdfGradient? _gradientSubstitute;

  /// Whether the last [fill] was an exact overprint identity and therefore
  /// must not be sent to an RGB painting device at all.
  ///
  /// Repainting an identity with the source's alternate RGB is observably
  /// wrong: GWG080 places a full-tint spot X over a gradient that already has
  /// that same plate. On press nothing changes; an RGB darken approximation
  /// reveals the X. This one-shot signal lets the interpreter omit it.
  bool takeSkipPaint() {
    final value = _skipPaint;
    _skipPaint = false;
    return value;
  }

  /// Exact precomposited regions produced by the last [fill], when its result
  /// varied with the backdrop and therefore could not be one solid colour.
  List<PdfOverprintRegion>? takeSpatialPaint() {
    final value = _spatialPaint;
    _spatialPaint = null;
    return value;
  }

  /// Composite-only overlays for the last [gradient]. The caller first paints
  /// the smooth source gradient as a knockout, then paints these regions where
  /// overprint preserved colorants from the backdrop.
  List<PdfOverprintRegion>? takeGradientSpatialPaint() {
    final value = _gradientSpatialPaint;
    _gradientSpatialPaint = null;
    return value;
  }

  /// Smooth precomposited gradient produced when the backdrop under the last
  /// shading was one known colorant vector.
  ///
  /// Painting this directly is both more faithful and cleaner than replaying
  /// cell-sized correction regions: the original vector clip supplies the
  /// exact antialiased edge while every sampled stop carries the subtractive
  /// ink result. Spatial correction remains necessary only when the backdrop
  /// itself varies (the GWG080/081 check patterns).
  PdfGradient? takeGradientSubstitute() {
    final value = _gradientSubstitute;
    _gradientSubstitute = null;
    return value;
  }

  /// Stroking counterpart of [fill]. [stroke] carries page-space geometry
  /// (the interpreter has already mapped the line width through the CTM).
  PdfColor? strokeShape(
      PdfPath path, PdfStroke stroke, PdfColor color, PdfInkColorants? ink,
      {PdfInkColorants? blendInk,
      required bool overprint,
      required int mode,
      required bool opaque}) {
    _skipPaint = false;
    _spatialPaint = null;
    return _resolve(
        () => _raster.strokeSpans(path,
            width: stroke.width,
            cap: stroke.cap,
            join: stroke.join,
            miterLimit: stroke.miterLimit,
            dashArray: stroke.dashArray,
            dashPhase: stroke.dashPhase),
        color,
        ink,
        blendInk: blendInk,
        overprint: overprint,
        mode: mode,
        opaque: opaque);
  }

  /// Records an axial or radial shading in device-colorant space.
  ///
  /// Unlike a path fill, a shading can change ink at every point. Sampling it
  /// at the colorant raster's cell centres preserves those separations for
  /// later overprint without turning this internal plate buffer into a display
  /// raster. Returns false when the gradient has no device-colorant reading.
  bool gradient(
    PdfPath path,
    PdfGradient gradient, {
    required bool overprint,
    required int mode,
    required bool opaque,
  }) {
    _gradientSpatialPaint = null;
    _gradientSubstitute = null;
    if (_exhausted || _muted != 0) return false;
    final inkAt = gradient.inkAt;
    final inverse = gradient.transform.inverted();
    if (inkAt == null || inverse == null) {
      markUnknownPath(path, PdfFillRule.nonzero);
      return false;
    }
    _draws++;
    final spans = _raster.fillSpans(path, evenOdd: false);
    if (spans.isEmpty) return true;
    final effective = overprint && opaque && _suspended == 0;
    final uniformBackdrop = effective
        ? _raster.backdropUnder(spans, limit: 1, bleedFraction: 0)
        : null;
    final uniformBackdropIndex = uniformBackdrop != null &&
            uniformBackdrop.length == 1 &&
            uniformBackdrop.first != _unknownIndex
        ? uniformBackdrop.first
        : null;
    if (uniformBackdropIndex != null) {
      final colors = <PdfColor>[];
      var complete = true;
      for (var i = 0; i < gradient.stops.length; i++) {
        final parameter = gradient.stops[i];
        final source = inkAt(parameter);
        if (source == null) {
          complete = false;
          break;
        }
        _learnSpots(source);
        final composite =
            source.over(_paletteColorants[uniformBackdropIndex], mode);
        colors.add(_srgbFor(composite, uniformBackdropIndex, source,
            gradient.colorAt(parameter)));
      }
      if (complete && colors.length == gradient.colors.length) {
        _gradientSubstitute = PdfGradient(
          isRadial: gradient.isRadial,
          coords: gradient.coords,
          colors: colors,
          stops: gradient.stops,
          transform: gradient.transform,
          extendStart: gradient.extendStart,
          extendEnd: gradient.extendEnd,
          inkAt: gradient.inkAt,
        );
      }
    }
    _raster.paintSampled(spans, (pageX, pageY, backdrop) {
      final gx = inverse.transformX(pageX, pageY);
      final gy = inverse.transformY(pageX, pageY);
      final parameter = _gradientParameter(gradient, gx, gy);
      if (parameter == null) return backdrop;
      final ink = inkAt(parameter);
      if (ink == null) return _unknownIndex;
      _learnSpots(ink);
      if (!opaque || _suspended != 0) return _unknownIndex;
      final composite = effective
          ? (backdrop == _unknownIndex
              ? null
              : ink.over(_paletteColorants[backdrop], mode))
          : ink.colorants;
      if (composite == null) return _unknownIndex;
      final color = effective
          ? _srgbFor(composite, backdrop, ink, gradient.colorAt(parameter))
          : gradient.colorAt(parameter);
      return _intern(composite, color);
    });
    if (effective && _gradientSubstitute == null) {
      final regions =
          _raster.sampledResultRegions(spans, (pageX, pageY, current) {
        if (current == _unknownIndex) return null;
        final gx = inverse.transformX(pageX, pageY);
        final gy = inverse.transformY(pageX, pageY);
        final parameter = _gradientParameter(gradient, gx, gy);
        if (parameter == null) return null;
        final source = inkAt(parameter);
        if (source == null || _paletteColorants[current] == source.colorants) {
          return null;
        }
        return current;
      });
      _gradientSpatialPaint = [
        for (final entry in regions.entries)
          PdfOverprintRegion(entry.value, _paletteColor[entry.key]),
      ];
    }
    return true;
  }

  static double? _gradientParameter(PdfGradient gradient, double x, double y) {
    final c = gradient.coords;
    double? finish(double value) {
      if (value < 0) return gradient.extendStart ? 0 : null;
      if (value > 1) return gradient.extendEnd ? 1 : null;
      return value;
    }

    if (!gradient.isRadial && c.length >= 4) {
      final dx = c[2] - c[0], dy = c[3] - c[1];
      final d2 = dx * dx + dy * dy;
      if (d2 == 0) return finish(0);
      return finish(((x - c[0]) * dx + (y - c[1]) * dy) / d2);
    }
    if (gradient.isRadial && c.length >= 6) {
      final px = x - c[0], py = y - c[1];
      final dx = c[3] - c[0], dy = c[4] - c[1];
      final dr = c[5] - c[2];
      final a = dx * dx + dy * dy - dr * dr;
      final b = -2 * (px * dx + py * dy + c[2] * dr);
      final d = px * px + py * py - c[2] * c[2];
      const epsilon = 1e-12;
      final roots = <double>[];
      if (a.abs() < epsilon) {
        if (b.abs() >= epsilon) roots.add(-d / b);
      } else {
        final discriminant = b * b - 4 * a * d;
        if (discriminant >= 0) {
          final root = math.sqrt(discriminant);
          roots
            ..add((-b - root) / (2 * a))
            ..add((-b + root) / (2 * a));
        }
      }
      if (roots.isEmpty) return null;
      roots.sort();
      return finish(roots.last);
    }
    return null;
  }

  /// Resolves an image draw covering [path] (the image's unit square mapped
  /// through its transform), and records what it leaves behind (issue #604).
  ///
  /// [ink] is the image's colorant reading when every sample carries the same
  /// colorants, [color] the sRGB it renders as; [hasColorants] says whether the
  /// raster has a colorant reading *at all* (false for a DeviceRGB/ICC raster,
  /// an encoding whose samples cannot be read, or a stencil - see
  /// `pdfImageColorants`).
  ///
  /// When the image overprints onto a single known backdrop, [resolve] builds
  /// the ordinary uniform substitute. When several colorant vectors sit under
  /// the same image, [resolveSpatial] receives their per-source-pixel map. The
  /// latter is what the GWG DeviceN support patches grade: a check and an X
  /// are painted under one indexed image and only exact spatial overprint
  /// leaves the check visible.
  T? image<T>(
    PdfPath path, {
    required PdfMatrix transform,
    required int width,
    required int height,
    required PdfInkColorants? ink,
    required PdfColor color,
    required bool hasColorants,
    required bool overprint,
    required int mode,
    required bool opaque,
    required T? Function(PdfColorants backdrop, PdfColor backdropColor) resolve,
    required T? Function(PdfColorantBackdropMap backdrop) resolveSpatial,
  }) {
    if (_exhausted || _muted != 0) return null;
    _draws++;
    final spans = _raster.fillSpans(path, evenOdd: false);
    if (spans.isEmpty) return null;
    final paintable = opaque && _suspended == 0;
    if (!overprint || !paintable || !hasColorants) {
      _recordImage(spans, paintable ? ink : null, color);
      return null;
    }
    // A small colorant region under a large image is not boundary bleed: the
    // GWG DeviceN checks occupy only a few percent of the image by design.
    // Keep every underlying vector here and let the spatial resolver sample
    // it per source pixel. Vector-on-vector resolution retains the normal 4%
    // edge tolerance below.
    final backdrops = _raster.backdropUnder(spans, limit: 32, bleedFraction: 0);
    if (backdrops == null) {
      _raster.paintFlat(spans, _unknownIndex);
      return null;
    }
    if (backdrops.length != 1 || backdrops.contains(_unknownIndex)) {
      final spatial = _spatialBackdrop(transform, width, height);
      final resolved = spatial == null ? null : resolveSpatial(spatial);
      // A varying raster generally leaves a varying composite. Until a later
      // draw needs another spatial read, the honest compact representation is
      // unknown; the displayed substitute itself is exact.
      _raster.paintFlat(spans, _unknownIndex);
      return resolved;
    }
    final backdrop = backdrops.first;
    final resolved =
        resolve(_paletteColorants[backdrop], _paletteColor[backdrop]);
    if (resolved == null) {
      // Either the backdrop is bare paper (overprinting onto no colorant is
      // the identity, so the source raster already *is* the composite) or no
      // substitute could be built. Recording the image's own colorants is
      // right in the first case and the honest "unknown" in the second, which
      // is what [_recordImage] does with a null ink.
      _recordImage(spans,
          _paletteColorants[backdrop] == PdfColorants.none ? ink : null, color);
      return null;
    }
    if (ink == null) {
      // A varying raster leaves a varying composite behind; the buffer stores
      // one vector per cell, so it can only say "unknown" here.
      _raster.paintFlat(spans, _unknownIndex);
      return resolved;
    }
    _learnSpots(ink);
    final composite = ink.over(_paletteColorants[backdrop], mode);
    _raster.paintFlat(
        spans, _intern(composite, _srgbFor(composite, backdrop, ink, color)));
    return resolved;
  }

  /// Samples the current colorant raster at each source-image pixel centre.
  /// Image row 0 is the top row, while PDF image space is y-up, hence `1-v`.
  PdfColorantBackdropMap? _spatialBackdrop(
      PdfMatrix transform, int width, int height) {
    if (width <= 0 || height <= 0 || width * height > (4 << 20)) return null;
    final indices = Uint16List(width * height);
    final colorants = <PdfColorants?>[null];
    final colors = <PdfColor>[const PdfColor(1, 1, 1)];
    final local = <_PaletteKey, int>{};
    var offset = 0;
    for (var y = 0; y < height; y++) {
      final v = 1 - (y + 0.5) / height;
      for (var x = 0; x < width; x++) {
        final u = (x + 0.5) / width;
        final pageX = transform.transformX(u, v);
        final pageY = transform.transformY(u, v);
        // Outside the active clip this substitute pixel will never reach the
        // canvas; use paper as a harmless stable value. An actual unknown cell
        // inside the clip remains entry 0 and makes the builder decline.
        final pageIndex = _raster.paletteAtPage(pageX, pageY) ?? _paperIndex;
        if (pageIndex == _unknownIndex) {
          indices[offset++] = 0;
          continue;
        }
        final key =
            _PaletteKey(_paletteColorants[pageIndex], _paletteColor[pageIndex]);
        var index = local[key];
        if (index == null) {
          if (colorants.length >= 0xffff) return null;
          index = colorants.length;
          local[key] = index;
          colorants.add(key.colorants);
          colors.add(key.color);
        }
        indices[offset++] = index;
      }
    }
    return PdfColorantBackdropMap(
      width: width,
      height: height,
      indices: indices,
      colorants: colorants,
      colors: colors,
    );
  }

  /// Resolves a stencil (/ImageMask) draw covering [path], the quad of its
  /// unit square.
  ///
  /// A stencil carries no colour of its own: it paints the *fill* colour
  /// through its own alpha (§8.9.6.2), so the ink is ordinary vector ink with
  /// an ordinary colorant reading. What the buffer cannot model is its
  /// **coverage** - the mask, not the quad. So resolving is allowed only when
  /// the backdrop is a single vector across the whole quad, where every pixel
  /// the mask does paint composites to the same colour and painting that colour
  /// through the mask is exact.
  ///
  /// The quad is recorded as unknown either way: the backdrop survives wherever
  /// the mask is clear, so the stencil is not a backdrop of its own.
  PdfColor? stencil(PdfPath path, PdfColor color, PdfInkColorants? ink,
      {required bool overprint, required int mode, required bool opaque}) {
    if (_exhausted || _muted != 0) return null;
    _draws++;
    final spans = _raster.fillSpans(path, evenOdd: false);
    if (spans.isEmpty) return null;
    if (!overprint ||
        !opaque ||
        _suspended != 0 ||
        ink == null ||
        ink.writesNothing) {
      _raster.paintFlat(spans, _unknownIndex);
      return null;
    }
    final backdrops = _raster.backdropUnder(spans);
    if (backdrops == null ||
        backdrops.length != 1 ||
        backdrops.first == _unknownIndex) {
      _raster.paintFlat(spans, _unknownIndex);
      return null;
    }
    final backdrop = backdrops.first;
    _learnSpots(ink);
    final composite = ink.over(_paletteColorants[backdrop], mode);
    final resolved = _srgbFor(composite, backdrop, ink, color);
    _raster.paintFlat(spans, _unknownIndex);
    return resolved;
  }

  /// Records an image's own coverage: its colorants when the raster carries one
  /// vector throughout and paints opaquely, else unknown.
  void _recordImage(ColorantSpans spans, PdfInkColorants? ink, PdfColor color) {
    if (ink == null) {
      _raster.paintFlat(spans, _unknownIndex);
      return;
    }
    _learnSpots(ink);
    _raster.paintFlat(spans, _intern(ink.colorants, color));
  }

  /// Marks the area a draw with no colorant reading covers - shading fills,
  /// meshes, tiling patterns - as unknown, so a later overprint over it
  /// declines instead of compositing against a stale backdrop.
  void markUnknownPath(PdfPath path, PdfFillRule rule) {
    if (_exhausted || _muted != 0) return;
    _draws++;
    _raster.paintFlat(
        _raster.fillSpans(path, evenOdd: rule == PdfFillRule.evenOdd),
        _unknownIndex);
  }

  /// [markUnknownPath] for a page-space box (text runs without outlines,
  /// images).
  void markUnknownBox(double left, double bottom, double right, double top) {
    if (_exhausted || _muted != 0) return;
    _draws++;
    _raster.paintFlat(
        _raster.boxSpans(left, bottom, right, top), _unknownIndex);
  }

  PdfColor? _resolve(
      ColorantSpans Function() rasterize, PdfColor color, PdfInkColorants? ink,
      {PdfInkColorants? blendInk,
      required bool overprint,
      required int mode,
      required bool opaque}) {
    if (_exhausted || _muted != 0) return null;
    _draws++;
    final spans = rasterize();
    if (spans.isEmpty) return null;
    if (_groups.isNotEmpty) {
      _raster.markCovered(spans, _groups.last.touched);
      final group = _groups.last;
      final groupInk = blendInk ?? ink;
      if (group.opaque &&
          opaque &&
          groupInk != null &&
          group.blendMode != PdfBlendMode.normal) {
        return _resolveGroupBlend(spans, color, groupInk, group.blendMode);
      }
      if (groupInk != null) ink = groupInk;
    }
    final effective = overprint && opaque && _suspended == 0 && ink != null;
    if (!effective) {
      final recordedInk = ink ?? blendInk;
      // A knockout replaces the backdrop's colorants with the ink's; anything
      // the buffer cannot model (translucency, an open group, a colour space
      // with no colorant reading) becomes unknown.
      if (!opaque || _suspended != 0 || recordedInk == null) {
        _raster.paintFlat(spans, _unknownIndex);
      } else {
        _learnSpots(recordedInk);
        _raster.paintFlat(spans, _intern(recordedInk.colorants, color));
      }
      return null;
    }
    if (ink.writesNothing) {
      // Separation /None paints no colorant at all (§8.6.6.4).
      return null;
    }
    final backdrops = _raster.backdropUnder(spans);
    if (backdrops == null || backdrops.contains(_unknownIndex)) {
      _raster.paintFlat(spans, _unknownIndex);
      return null;
    }
    _learnSpots(ink);
    final results = <int, int>{};
    PdfColor? uniform;
    var identity = true;
    for (final backdrop in backdrops) {
      final composite = ink.over(_paletteColorants[backdrop], mode);
      if (composite != _paletteColorants[backdrop]) identity = false;
      final rendered = _srgbFor(composite, backdrop, ink, color);
      results[backdrop] = _intern(composite, rendered);
      if (uniform == null) {
        uniform = rendered;
      } else if (uniform != rendered) {
        // The composite differs across the draw. The device paints one colour
        // per call, so it still needs its RGB fallback for this immediate
        // primitive; the separations result is nevertheless exact per cell.
        // Preserve it in the plate buffer so a later overprinting image or
        // vector can resolve against the PDF's actual colorants instead of
        // inheriting the display approximation. GWG080/081 deliberately rely
        // on this chain: a spot check overlays a CMYK X, then a DeviceN image
        // overwrites selected plates and must see both underlying vectors.
        int resultFor(int backdrop) => results[backdrop] ?? _unknownIndex;
        final regions = _raster.resultRegions(spans, resultFor);
        _spatialPaint = [
          for (final entry in regions.entries)
            if (entry.key != _unknownIndex)
              PdfOverprintRegion(entry.value, _paletteColor[entry.key]),
        ];
        _raster.paint(spans, resultFor);
        _skipPaint = identity;
        return null;
      }
    }
    _raster.paint(spans, (backdrop) => results[backdrop] ?? _unknownIndex);
    return uniform;
  }

  /// sRGB for a composite colorant vector.
  ///
  /// Reuses an existing rendered colour whenever the composite reproduces one:
  /// unchanged backdrop keeps the backdrop's pixels (so an overprint that
  /// writes nothing new is invisible, which is what the GWG "over spot"
  /// patches grade), and a full knockout to the ink's own colorants keeps the
  /// ink's (the "over CMYK" patches). Everything else converts through the
  /// separations model.
  PdfColor _srgbFor(PdfColorants composite, int backdrop, PdfInkColorants ink,
      PdfColor inkColor) {
    if (composite == _paletteColorants[backdrop]) {
      return backdrop == _paperIndex
          ? _paletteColor[_paperIndex]
          : _paletteColor[backdrop];
    }
    if (composite == ink.colorants) return inkColor;
    return colorantsToSrgb(
      composite,
      _spotEquivalents,
      cmykToSrgb: _colorContext?.deviceCmyk,
    );
  }

  PdfColor? _resolveGroupBlend(ColorantSpans spans, PdfColor sourceColor,
      PdfInkColorants source, PdfBlendMode mode) {
    _learnSpots(source);
    final backdrops = _raster.backdropUnder(spans, bleedFraction: 0);
    if (backdrops == null || backdrops.contains(_unknownIndex)) {
      _raster.paintFlat(spans, _unknownIndex);
      return null;
    }
    final results = <int, int>{};
    PdfColor? uniform;
    for (final backdrop in backdrops) {
      final PdfColorants composite;
      final PdfColor rendered;
      if (backdrop == _transparentIndex) {
        composite = source.colorants;
        rendered = sourceColor;
      } else {
        composite = _blendColorants(
            _paletteColorants[backdrop], source.colorants, mode);
        rendered = composite == _paletteColorants[backdrop]
            ? _paletteColor[backdrop]
            : composite == source.colorants
                ? sourceColor
                : colorantsToSrgb(composite, _spotEquivalents,
                    cmykToSrgb: _colorContext?.deviceCmyk);
      }
      final index = _intern(composite, rendered);
      results[backdrop] = index;
      uniform ??= rendered;
      if (uniform != rendered) {
        final regions = _raster.resultRegions(
            spans, (value) => results[value] ?? _unknownIndex);
        _spatialPaint = [
          for (final entry in regions.entries)
            if (entry.key != _unknownIndex)
              PdfOverprintRegion(entry.value, _paletteColor[entry.key]),
        ];
        _raster.paint(spans, (value) => results[value] ?? _unknownIndex);
        return null;
      }
    }
    _raster.paint(spans, (value) => results[value] ?? _unknownIndex);
    return uniform;
  }

  static PdfColorants _blendColorants(
      PdfColorants backdrop, PdfColorants source, PdfBlendMode mode) {
    double component(double backdropInk, double sourceInk) {
      final cb = 1 - backdropInk;
      final cs = 1 - sourceInk;
      final blended = switch (mode) {
        PdfBlendMode.normal => cs,
        PdfBlendMode.multiply => cb * cs,
        PdfBlendMode.screen => cb + cs - cb * cs,
        PdfBlendMode.overlay =>
          cb <= 0.5 ? 2 * cb * cs : 1 - 2 * (1 - cb) * (1 - cs),
        PdfBlendMode.darken => math.min(cb, cs),
        PdfBlendMode.lighten => math.max(cb, cs),
        PdfBlendMode.colorDodge => cs >= 1 ? 1 : math.min(1, cb / (1 - cs)),
        PdfBlendMode.colorBurn => cs <= 0 ? 0 : 1 - math.min(1, (1 - cb) / cs),
        PdfBlendMode.hardLight =>
          cs <= 0.5 ? 2 * cb * cs : 1 - 2 * (1 - cb) * (1 - cs),
        PdfBlendMode.softLight => _softLight(cb, cs),
        PdfBlendMode.difference => (cb - cs).abs(),
        PdfBlendMode.exclusion => cb + cs - 2 * cb * cs,
        // The nonseparable modes are resolved below as a three-component
        // colour operation; K still follows the source for their CMYK group.
        PdfBlendMode.hue ||
        PdfBlendMode.saturation ||
        PdfBlendMode.color ||
        PdfBlendMode.luminosity =>
          cs,
      };
      return (1 - blended).clamp(0.0, 1.0).toDouble();
    }

    if (mode == PdfBlendMode.hue ||
        mode == PdfBlendMode.saturation ||
        mode == PdfBlendMode.color ||
        mode == PdfBlendMode.luminosity) {
      final cb = [1 - backdrop.c, 1 - backdrop.m, 1 - backdrop.y];
      final cs = [1 - source.c, 1 - source.m, 1 - source.y];
      final rgb = switch (mode) {
        PdfBlendMode.hue => _setLum(_setSat(cs, _sat(cb)), _lum(cb)),
        PdfBlendMode.saturation => _setLum(_setSat(cb, _sat(cs)), _lum(cb)),
        PdfBlendMode.color => _setLum(cs, _lum(cb)),
        PdfBlendMode.luminosity => _setLum(cb, _lum(cs)),
        _ => cs,
      };
      // In a subtractive blending space the nonseparable operation uses the
      // complements of C/M/Y. The black component follows the backdrop for
      // Hue/Saturation/Color and the source for Luminosity (PDF blend-mode
      // addendum; this is also what keeps a neutral source over a K-only
      // backdrop neutral instead of exposing GWG160's fail marker).
      final black = mode == PdfBlendMode.luminosity ? source.k : backdrop.k;
      return PdfColorants(1 - rgb[0], 1 - rgb[1], 1 - rgb[2], black);
    }
    return PdfColorants(
      component(backdrop.c, source.c),
      component(backdrop.m, source.m),
      component(backdrop.y, source.y),
      component(backdrop.k, source.k),
    );
  }

  static double _softLight(double cb, double cs) {
    if (cs <= 0.5) return cb - (1 - 2 * cs) * cb * (1 - cb);
    final d = cb <= 0.25 ? ((16 * cb - 12) * cb + 4) * cb : math.sqrt(cb);
    return cb + (2 * cs - 1) * (d - cb);
  }

  static double _lum(List<double> c) => 0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2];

  static double _sat(List<double> c) => c.reduce(math.max) - c.reduce(math.min);

  static List<double> _clipColor(List<double> c) {
    final l = _lum(c), n = c.reduce(math.min), x = c.reduce(math.max);
    final result = [...c];
    if (n < 0) {
      for (var i = 0; i < result.length; i++) {
        result[i] = l + (result[i] - l) * l / (l - n);
      }
    }
    if (x > 1) {
      for (var i = 0; i < result.length; i++) {
        result[i] = l + (result[i] - l) * (1 - l) / (x - l);
      }
    }
    return result;
  }

  static List<double> _setLum(List<double> c, double l) {
    final delta = l - _lum(c);
    return _clipColor([for (final value in c) value + delta]);
  }

  static List<double> _setSat(List<double> c, double s) {
    final order = [0, 1, 2]..sort((a, b) => c[a].compareTo(c[b]));
    final result = [0.0, 0.0, 0.0];
    final lo = order[0], mid = order[1], hi = order[2];
    if (c[hi] > c[lo]) {
      result[mid] = (c[mid] - c[lo]) * s / (c[hi] - c[lo]);
      result[hi] = s;
    }
    result[lo] = 0;
    return result;
  }
}

class _TransparencyContext {
  _TransparencyContext({
    required this.blendMode,
    required this.isolated,
    required this.knockout,
    required this.opaque,
    required this.externalCells,
    required this.initialCells,
    required this.accumulatedCells,
    required this.touched,
  });

  final PdfBlendMode blendMode;
  final bool isolated;
  final bool knockout;
  final bool opaque;
  final Uint16List externalCells;
  final Uint16List initialCells;
  final Uint16List? accumulatedCells;
  final Uint8List touched;
}

class _PaletteKey {
  _PaletteKey(this.colorants, this.color);

  final PdfColorants colorants;
  final PdfColor color;

  @override
  bool operator ==(Object other) =>
      other is _PaletteKey &&
      other.colorants == colorants &&
      other.color == color;

  @override
  int get hashCode => Object.hash(colorants, color);
}
