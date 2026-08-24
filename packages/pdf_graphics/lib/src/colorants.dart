// Device colorants (PDF 32000-1 §8.6.7) — the ink-space value type overprint
// is defined in terms of.
//
// Overprint is subtractive: painting with overprint enabled writes only the
// device colorants the source colour space *specifies* and leaves every other
// colorant of the backdrop untouched (instead of knocking it out). Reproducing
// that needs the colorants themselves, not the sRGB the rest of the renderer
// works in - a DeviceCMYK green and a spot green can be the same pixels and
// still overprint differently, which is exactly what the RGB `darken`
// approximation could not separate (issue #502).
//
// The model here is a virtual separations device: the four process colorants
// plus one channel per named spot colorant encountered on the page. It is pure
// Dart with no rendering dependency, so the composite rules are unit-testable
// on their own.
import 'dart:typed_data';

import 'color.dart';

/// Bit per process colorant in [PdfInkColorants.processMask].
const int kColorantCyan = 1;
const int kColorantMagenta = 2;
const int kColorantYellow = 4;
const int kColorantBlack = 8;
const int kColorantProcessAll =
    kColorantCyan | kColorantMagenta | kColorantYellow | kColorantBlack;

/// A device colorant vector: the four process tints plus a sorted list of
/// named spot colorants and their tints. All tints are 0..1, where 0 is "no
/// ink" - so [none] (all zero) is bare paper.
///
/// Values are compared exactly: they come from the same content-stream
/// operands and tint transforms every time a colour is selected, so equal
/// colours produce equal vectors, which is what lets the compositor recognise
/// "this overprint left the backdrop unchanged" and reuse the backdrop's own
/// sRGB rather than round-tripping through a CMYK conversion.
class PdfColorants {
  PdfColorants(this.c, this.m, this.y, this.k,
      {this.spots = const [], List<double> tints = const []})
      : tints = tints is Float64List ? tints : Float64List.fromList(tints);

  /// Bare paper: no colorant anywhere.
  static final PdfColorants none = PdfColorants(0, 0, 0, 0);

  final double c;
  final double m;
  final double y;
  final double k;

  /// Spot colorant names, sorted and unique; empty for pure process colours.
  final List<String> spots;

  /// Tints parallel to [spots].
  final Float64List tints;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PdfColorants) return false;
    if (other.c != c || other.m != m || other.y != y || other.k != k) {
      return false;
    }
    if (other.spots.length != spots.length) return false;
    for (var i = 0; i < spots.length; i++) {
      if (other.spots[i] != spots[i] || other.tints[i] != tints[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode {
    var h = Object.hash(c, m, y, k);
    for (var i = 0; i < spots.length; i++) {
      h = Object.hash(h, spots[i], tints[i]);
    }
    return h;
  }

  @override
  String toString() {
    final b = StringBuffer('PdfColorants($c, $m, $y, $k');
    for (var i = 0; i < spots.length; i++) {
      b.write(', ${spots[i]}=${tints[i]}');
    }
    return (b..write(')')).toString();
  }
}

/// Per-pixel colorant backdrop for an overprinting image.
///
/// The page colorant buffer normally resolves a vector or image against one
/// uniform backdrop. GWG's DeviceN support patches deliberately put different
/// process/spot vectors underneath one indexed image, so the image must read
/// the backdrop at every source pixel. Entries are palette-indexed to keep the
/// map compact and value-comparable across the renderer's collect and paint
/// walks; palette entry 0 means the backdrop is unknown.
class PdfColorantBackdropMap {
  PdfColorantBackdropMap({
    required this.width,
    required this.height,
    required this.indices,
    required this.colorants,
    required this.colors,
  }) : _hashCode = _hash(width, height, indices, colorants, colors);

  final int width;
  final int height;
  final Uint16List indices;

  /// Entry 0 is always null (unknown); all later entries are real vectors.
  final List<PdfColorants?> colorants;

  /// Display colours parallel to [colorants]. Entry 0 is arbitrary.
  final List<PdfColor> colors;

  final int _hashCode;

  ({PdfColorants colorants, PdfColor color})? at(int x, int y) {
    if (x < 0 || y < 0 || x >= width || y >= height) return null;
    final index = indices[y * width + x];
    if (index == 0 || index >= colorants.length || index >= colors.length) {
      return null;
    }
    final value = colorants[index];
    return value == null ? null : (colorants: value, color: colors[index]);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PdfColorantBackdropMap ||
        other.width != width ||
        other.height != height ||
        other._hashCode != _hashCode ||
        other.indices.length != indices.length ||
        other.colorants.length != colorants.length ||
        other.colors.length != colors.length) {
      return false;
    }
    for (var i = 0; i < indices.length; i++) {
      if (other.indices[i] != indices[i]) return false;
    }
    for (var i = 0; i < colorants.length; i++) {
      if (other.colorants[i] != colorants[i] || other.colors[i] != colors[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => _hashCode;

  static int _hash(int width, int height, Uint16List indices,
      List<PdfColorants?> colorants, List<PdfColor> colors) {
    var hash = Object.hash(width, height);
    for (final value in colorants) {
      hash = Object.hash(hash, value);
    }
    for (final color in colors) {
      hash = Object.hash(hash, color);
    }
    // Sample every entry into the rolling hash. The maps are bounded by the
    // image-overprint pixel cap and are constructed only for a non-uniform
    // backdrop, so this cost is paid beside an unavoidable per-pixel build.
    for (final index in indices) {
      hash = Object.hash(hash, index);
    }
    return hash;
  }
}

/// A paint's colorants together with the overprint semantics of the colour
/// space it came from - everything [over] needs to decide which of the
/// device's colorants this ink writes.
class PdfInkColorants {
  PdfInkColorants({
    required this.colorants,
    required this.processMask,
    required this.overprintModeApplies,
    this.writesAll = false,
    this.spotEquivalents = const [],
  });

  /// The four process colorants, as DeviceCMYK writes them: all four are
  /// specified, and the overprint-mode-1 zero rule applies (§8.6.7.3).
  PdfInkColorants.deviceCmyk(double c, double m, double y, double k)
      : colorants = PdfColorants(c, m, y, k),
        processMask = kColorantProcessAll,
        overprintModeApplies = true,
        writesAll = false,
        spotEquivalents = const [];

  /// DeviceGray, which §8.6.7 writes as the process colorants
  /// (0, 0, 0, 1 - [level]) - so a neutral grey knocks a process backdrop out
  /// to grey rather than merely darkening it. The overprint-mode-1 zero rule
  /// is DeviceCMYK's alone, which is why 50% grey over CMYK grades the same
  /// under both modes.
  PdfInkColorants.deviceGray(double level)
      : colorants = PdfColorants(0, 0, 0, 1 - level),
        processMask = kColorantProcessAll,
        overprintModeApplies = false,
        writesAll = false,
        spotEquivalents = const [];

  /// The tints this ink carries.
  final PdfColorants colorants;

  /// Which process colorants the source space specifies (a mask of
  /// [kColorantCyan] &c). DeviceCMYK and DeviceGray specify all four -
  /// DeviceGray as (0, 0, 0, 1 - gray), which is why a neutral grey knocks a
  /// process backdrop out to grey rather than merely darkening it. A
  /// Separation/DeviceN space specifies only the process colorants it names.
  final int processMask;

  /// Whether the overprint-mode-1 rule (§8.6.7.3: a component of 0.0 is not
  /// written, so it cannot erase the backdrop) applies to this space.
  ///
  /// True for DeviceCMYK alone. Deliberately false for DeviceGray - OPM has no
  /// effect there, so 50% grey knocks a DeviceCMYK backdrop out to grey under
  /// either mode (GWG030's patches e and k grade exactly that) - and false for
  /// Separation/DeviceN, whose named colorants are written whatever their tint
  /// (GWG190's patch c grades that one).
  final bool overprintModeApplies;

  /// Separation `/All` (§8.6.6.4): the tint is applied to every colorant the
  /// device has, including spot colorants only the backdrop carries.
  final bool writesAll;

  /// CMYK equivalent (four components) of each spot in [colorants]`.spots` at
  /// full tint, parallel to that list. Lets a composite vector that names a
  /// spot no single paint produced still convert to sRGB.
  final List<List<double>> spotEquivalents;

  /// Whether painting this ink writes no colorant at all (`/None`).
  bool get writesNothing =>
      !writesAll && processMask == 0 && colorants.spots.isEmpty;

  /// The colorant vector left behind by painting this ink, with overprint
  /// enabled under overprint mode [mode], over the backdrop [backdrop].
  ///
  /// Colorants this ink writes take its tint; every other colorant keeps the
  /// backdrop's. That single rule is the whole of overprint - the RGB
  /// approximations only ever existed because the backdrop's colorants were
  /// not known.
  PdfColorants over(PdfColorants backdrop, int mode) {
    if (writesAll) {
      final tint = colorants.k;
      return PdfColorants(tint, tint, tint, tint,
          spots: backdrop.spots,
          tints: Float64List(backdrop.spots.length)
            ..fillRange(0, backdrop.spots.length, tint));
    }
    var mask = processMask;
    final suppressZero = overprintModeApplies && mode == 1;
    if (suppressZero) {
      if (colorants.c == 0) mask &= ~kColorantCyan;
      if (colorants.m == 0) mask &= ~kColorantMagenta;
      if (colorants.y == 0) mask &= ~kColorantYellow;
      if (colorants.k == 0) mask &= ~kColorantBlack;
    }
    final rc = (mask & kColorantCyan) != 0 ? colorants.c : backdrop.c;
    final rm = (mask & kColorantMagenta) != 0 ? colorants.m : backdrop.m;
    final ry = (mask & kColorantYellow) != 0 ? colorants.y : backdrop.y;
    final rk = (mask & kColorantBlack) != 0 ? colorants.k : backdrop.k;
    if (colorants.spots.isEmpty && backdrop.spots.isEmpty) {
      return PdfColorants(rc, rm, ry, rk);
    }
    // Merge the two sorted name lists; the ink's tint wins for a spot it
    // writes, the backdrop's survives everywhere else.
    final names = <String>[];
    final values = <double>[];
    var i = 0, j = 0;
    while (i < backdrop.spots.length || j < colorants.spots.length) {
      final takeBackdrop = j >= colorants.spots.length ||
          (i < backdrop.spots.length &&
              backdrop.spots[i].compareTo(colorants.spots[j]) < 0);
      final takeInk = i >= backdrop.spots.length ||
          (j < colorants.spots.length &&
              colorants.spots[j].compareTo(backdrop.spots[i]) < 0);
      if (takeBackdrop && !takeInk) {
        names.add(backdrop.spots[i]);
        values.add(backdrop.tints[i]);
        i++;
      } else if (takeInk && !takeBackdrop) {
        final t = colorants.tints[j];
        if (!(suppressZero && t == 0)) {
          names.add(colorants.spots[j]);
          values.add(t);
        }
        j++;
      } else {
        final t = colorants.tints[j];
        names.add(backdrop.spots[i]);
        values.add(suppressZero && t == 0 ? backdrop.tints[i] : t);
        i++;
        j++;
      }
    }
    return PdfColorants(rc, rm, ry, rk, spots: names, tints: values);
  }
}

/// Converts a colorant vector back to sRGB for display.
///
/// Spot colorants contribute through their CMYK equivalents (looked up in
/// [spotEquivalents] by name, scaled by tint); overlapping inks accumulate
/// additively per process channel and clamp at full ink, the usual
/// separations-preview model. Only reached for a colorant combination that no
/// single paint produced - the compositor reuses the backdrop's or the ink's
/// own sRGB when the composite equals one of them, so the common cases keep
/// their exact rendered colour.
PdfColor colorantsToSrgb(
  PdfColorants v,
  Map<String, List<double>> spotEquivalents, {
  PdfColor Function(double c, double m, double y, double k)? cmykToSrgb,
}) {
  var c = v.c, m = v.m, y = v.y, k = v.k;
  for (var i = 0; i < v.spots.length; i++) {
    final equivalent = spotEquivalents[v.spots[i]];
    if (equivalent == null || equivalent.length < 4) continue;
    final t = v.tints[i];
    c += equivalent[0] * t;
    m += equivalent[1] * t;
    y += equivalent[2] * t;
    k += equivalent[3] * t;
  }
  final cyan = c.clamp(0.0, 1.0).toDouble();
  final magenta = m.clamp(0.0, 1.0).toDouble();
  final yellow = y.clamp(0.0, 1.0).toDouble();
  final black = k.clamp(0.0, 1.0).toDouble();
  return cmykToSrgb?.call(cyan, magenta, yellow, black) ??
      PdfColor.cmyk(cyan, magenta, yellow, black);
}
