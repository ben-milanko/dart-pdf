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
import 'color.dart';
import 'colorants.dart';
import 'matrix.dart';
import 'path.dart';
import 'raster/colorant_raster.dart';

/// Resolves overprint against a colorant buffer for one page.
class PdfOverprintCompositor {
  PdfOverprintCompositor._(this._raster);

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
      {int maxDimension = 384}) {
    final w = right - left, h = top - bottom;
    if (!w.isFinite || !h.isFinite || w <= 0 || h <= 0) return null;
    final scale = maxDimension / (w > h ? w : h);
    final width = (w * scale).round().clamp(1, maxDimension);
    final height = (h * scale).round().clamp(1, maxDimension);
    // y is flipped so cell rows run top-down; nothing reads the buffer
    // geometrically, but matching raster convention keeps debugging sane.
    final matrix = PdfMatrix(scale, 0, 0, -scale, -left * scale, top * scale);
    return PdfOverprintCompositor._(PdfColorantRaster(
        width: width,
        height: height,
        mapping: ColorantPageMapping(matrix, scale)));
  }

  final PdfColorantRaster _raster;

  /// Palette entry 0 is bare paper, entry 1 the "colorants unknown" sentinel
  /// (images, gradients, transparency groups, translucent paint, colour spaces
  /// with no colorant reading). An overprint landing on unknown declines.
  static const int _paperIndex = 0;
  static const int _unknownIndex = 1;

  final List<PdfColorants> _paletteColorants = [
    PdfColorants.none,
    PdfColorants.none,
  ];
  final List<PdfColor> _paletteColor = <PdfColor>[
    const PdfColor(1, 1, 1),
    const PdfColor(1, 1, 1),
  ];
  final Map<_PaletteKey, int> _paletteIndex = {};

  /// CMYK equivalents of the spot colorants seen on the page, by name.
  final Map<String, List<double>> _spotEquivalents = {};

  /// Nesting depth of transparency groups and soft-mask captures. Their
  /// contents composite through a separate buffer, so the page's colorants
  /// are unknowable while one is open - draws inside still mark their
  /// coverage unknown, which is what makes a later overprint decline.
  int _suspended = 0;

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

  /// Distinct colorant vectors interned so far - test hook.
  int get debugPaletteLength => _paletteColorants.length;

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
    _raster.clipTo(_raster.fillSpans(path, evenOdd: rule == PdfFillRule.evenOdd));
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
  PdfColor? fill(PdfPath path, PdfFillRule rule, PdfColor color,
          PdfInkColorants? ink,
          {required bool overprint, required int mode, required bool opaque}) =>
      _resolve(
          () => _raster.fillSpans(path, evenOdd: rule == PdfFillRule.evenOdd),
          color,
          ink,
          overprint: overprint,
          mode: mode,
          opaque: opaque);

  /// Stroking counterpart of [fill]. [stroke] carries page-space geometry
  /// (the interpreter has already mapped the line width through the CTM).
  PdfColor? strokeShape(PdfPath path, PdfStroke stroke, PdfColor color,
          PdfInkColorants? ink,
          {required bool overprint, required int mode, required bool opaque}) =>
      _resolve(
          () => _raster.strokeSpans(path,
              width: stroke.width,
              cap: stroke.cap,
              join: stroke.join,
              miterLimit: stroke.miterLimit,
              dashArray: stroke.dashArray,
              dashPhase: stroke.dashPhase),
          color,
          ink,
          overprint: overprint,
          mode: mode,
          opaque: opaque);

  /// Marks the area a draw with no colorant reading covers - images, shading
  /// fills, meshes, tiling patterns - as unknown, so a later overprint over it
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
    _raster.paintFlat(_raster.boxSpans(left, bottom, right, top), _unknownIndex);
  }

  PdfColor? _resolve(ColorantSpans Function() rasterize, PdfColor color,
      PdfInkColorants? ink,
      {required bool overprint, required int mode, required bool opaque}) {
    if (_exhausted || _muted != 0) return null;
    _draws++;
    final spans = rasterize();
    if (spans.isEmpty) return null;
    final effective = overprint && opaque && _suspended == 0 && ink != null;
    if (!effective) {
      // A knockout replaces the backdrop's colorants with the ink's; anything
      // the buffer cannot model (translucency, an open group, a colour space
      // with no colorant reading) becomes unknown.
      if (!opaque || _suspended != 0 || ink == null) {
        _raster.paintFlat(spans, _unknownIndex);
      } else {
        _learnSpots(ink);
        _raster.paintFlat(spans, _intern(ink.colorants, color));
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
    for (final backdrop in backdrops) {
      final composite = ink.over(_paletteColorants[backdrop], mode);
      final rendered = _srgbFor(composite, backdrop, ink, color);
      results[backdrop] = _intern(composite, rendered);
      if (uniform == null) {
        uniform = rendered;
      } else if (uniform != rendered) {
        // The composite differs across the draw. The device paints one colour
        // per call, so hand it back to the approximation - and mark the area
        // unknown so the buffer keeps describing what is actually on screen.
        _raster.paintFlat(spans, _unknownIndex);
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
    return colorantsToSrgb(composite, _spotEquivalents);
  }
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
