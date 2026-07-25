import 'package:pdf_cos/pdf_cos.dart';

import 'calibrated_color.dart';
import 'color.dart';
import 'colorants.dart';
import 'function.dart';
import 'icc.dart';

/// A PDF colour space (§8.6) resolved to what rendering needs: how many
/// components a colour carries, and how those components become sRGB.
///
/// This is the single source of truth for the knowledge "given a COS
/// colour-space object, how many channels does it have and how do N
/// component values convert to sRGB". The interpreter (`sc`/`scn`), axial
/// and radial shadings, mesh shadings, and image decoding all resolve their
/// colour spaces through [parse] rather than each re-deriving the
/// family/channel/conversion logic. The device families, the CIE-based
/// calibrated spaces ([PdfCalibratedColorSpace]), ICC profiles
/// ([IccProfile]), Indexed palettes, and Separation/DeviceN tint transforms
/// are all folded into one interface here.
abstract class PdfColorSpace {
  const PdfColorSpace();

  /// The default DeviceGray space - the initial fill/stroke space (§8.6.3)
  /// and a safe fallback for anything unresolved.
  static const PdfColorSpace deviceGray = _DeviceColorSpace('DeviceGray', 1);

  /// Nominal component count of the space. Pattern spaces report 0.
  int get channels;

  /// The space's family name (`DeviceGray`/`DeviceRGB`/`DeviceCMYK`/
  /// `Indexed`/`Separation`/`DeviceN`/`ICCBased`/`CalGray`/`CalRGB`/`Lab`/
  /// `Pattern`).
  String get family;

  /// The parsed ICC profile backing an ICCBased space, when supported;
  /// null for every other family (and for an ICCBased space whose profile
  /// could not be parsed, where the device fallback applies).
  IccProfile? get iccProfile => null;

  /// Converts [values] - nominally one per [channels], in the space's own
  /// component ranges - to sRGB. Lenient on a length mismatch: device
  /// families read what they can and treat the rest as zero.
  PdfColor toSrgb(List<double> values);

  /// Converts raw 8-bit samples (0–255), as stored in image data or an
  /// Indexed palette entry, to sRGB through the space's default component
  /// decode (§8.6.5). The default decode is [0, 1] per component; Lab
  /// overrides it with its L*/a*/b* ranges.
  PdfColor toSrgbFromSamples(List<int> samples) =>
      toSrgb([for (final s in samples) s / 255]);

  /// The device colorants painting [values] in this space writes, with the
  /// overprint semantics of the space (§8.6.7) - or null when the space has no
  /// colorant reading, in which case overprint cannot be resolved and the
  /// painting device's approximation stands.
  ///
  /// Implemented for the spaces overprint is defined over: DeviceGray and
  /// DeviceCMYK (process colorants) and Separation/DeviceN (the colorants they
  /// name). DeviceRGB, ICCBased, Lab/CalRGB/CalGray, Indexed and Pattern
  /// return null: an RGB-ish colour has no colorant decomposition, and
  /// inventing one would knock backdrops out that a real separations device
  /// leaves alone.
  PdfInkColorants? inkColorants(List<double> values) => null;

  /// Resolves a colour-space object. [object] may be a device or
  /// abbreviation name, a `Pattern` name, an array space (`[/ICCBased …]`,
  /// `[/Indexed …]`, `[/Separation …]`, `[/DeviceN …]`, `[/CalRGB …]`, …),
  /// or - when [resources] is given - a name keying the resource
  /// dictionary's `/ColorSpace` sub-dictionary (as `cs`/`CS` operands do).
  /// Always returns a space; unrecognised shapes fall back to a device
  /// family.
  ///
  /// [iccCache] optionally memoises parsed ICC profiles by their profile
  /// stream, so a colour space selected repeatedly (a `cs`/`CS` in a tight
  /// `q`/`Q` loop) parses its profile only once.
  static PdfColorSpace parse(CosDocument cos, CosObject? object,
      {CosDictionary? resources, Map<CosStream, IccProfile?>? iccCache}) {
    final resolved = cos.resolve(object);
    if (resolved is CosName) {
      final device = _deviceForName(resolved.value);
      if (device != null) return device;
      if (resolved.value == 'Pattern') return const _PatternColorSpace();
      if (resources != null) {
        final spaces = cos.resolve(resources['ColorSpace']);
        if (spaces is CosDictionary && spaces.containsKey(resolved.value)) {
          return parse(cos, spaces[resolved.value],
              resources: resources, iccCache: iccCache);
        }
      }
      // Unknown named space: assume RGB, the historical default.
      return const _DeviceColorSpace('DeviceRGB', 3);
    }
    if (resolved is CosArray && resolved.length > 0) {
      // Doc-level parse cache (#534, PDFium's CPDF_DocPageData shape): a
      // `cs`/`CS` operator re-selects the same colour space object on every
      // occurrence, every render, every zoom bucket - and a Separation /
      // DeviceN space re-reads its tint sample stream each time. Parsed
      // spaces are immutable, and keying by the resolved array's identity
      // makes invalidation free: an edit builds new COS objects, so a stale
      // entry is simply never looked up again (the same argument as the
      // decoded-stream cache). An Expando ties each entry's lifetime to its
      // document's objects.
      final hit = _parsed[resolved];
      if (hit != null) return hit;
      final space = _parseArray(cos, resolved, resources, iccCache);
      _parsed[resolved] = space;
      return space;
    }
    // Unresolved / malformed: a single-component gray keeps something visible.
    return const _DeviceColorSpace('DeviceGray', 1);
  }

  static final Expando<PdfColorSpace> _parsed = Expando();

  static PdfColorSpace _parseArray(CosDocument cos, CosArray resolved,
      CosDictionary? resources, Map<CosStream, IccProfile?>? iccCache) {
    {
      final family = cos.resolve(resolved[0]);
      if (family is CosName) {
        switch (family.value) {
          case 'ICCBased':
            return _parseIcc(cos, resolved, iccCache);
          case 'Indexed' || 'I':
            return _IndexedColorSpace.parse(cos, resolved, resources, iccCache) ??
                const _DeviceColorSpace('DeviceRGB', 3);
          case 'Separation':
            return _TintColorSpace.parse(cos, resolved, resources, iccCache) ??
                const _DeviceColorSpace('DeviceGray', 1);
          case 'DeviceN':
            return _TintColorSpace.parseDeviceN(
                    cos, resolved, resources, iccCache) ??
                const _DeviceColorSpace('DeviceRGB', 3);
          case 'CalGray' || 'CalRGB' || 'Lab':
            final cal = PdfCalibratedColorSpace.parse(cos, resolved);
            if (cal != null) return _CalibratedColorSpace(family.value, cal);
            return _DeviceColorSpace(
                family.value == 'CalGray' ? 'DeviceGray' : 'DeviceRGB',
                family.value == 'CalGray' ? 1 : 3);
          case 'Pattern':
            return const _PatternColorSpace();
          default:
            final device = _deviceForName(family.value);
            if (device != null) return device;
        }
      }
    }
    // Unresolved / malformed: a single-component gray keeps something visible.
    return const _DeviceColorSpace('DeviceGray', 1);
  }

  static PdfColorSpace _parseIcc(CosDocument cos, CosArray space,
      Map<CosStream, IccProfile?>? iccCache) {
    // ICCBased carries its own component count in the profile stream's /N;
    // the device family it degrades to is chosen from that count.
    var channels = 3;
    IccProfile? profile;
    if (space.length > 1) {
      final stream = cos.resolve(space[1]);
      if (stream is CosStream) {
        final n = cos.resolve(stream.dictionary['N']);
        if (n is CosInteger) channels = n.value;
        profile = iccCache != null
            ? iccCache.putIfAbsent(stream, () => _parseProfile(cos, stream))
            : _parseProfile(cos, stream);
      }
    }
    return _IccColorSpace(profile, channels);
  }

  static IccProfile? _parseProfile(CosDocument cos, CosStream stream) {
    try {
      return IccProfile.parse(cos.decodeStreamData(stream));
    } on Exception {
      return null;
    }
  }

  /// The device space for a colour-space name or its inline-image
  /// abbreviation, or null when the name is not a device family.
  static _DeviceColorSpace? _deviceForName(String name) => switch (name) {
        'DeviceGray' || 'G' => const _DeviceColorSpace('DeviceGray', 1),
        'DeviceRGB' || 'RGB' => const _DeviceColorSpace('DeviceRGB', 3),
        'DeviceCMYK' || 'CMYK' => const _DeviceColorSpace('DeviceCMYK', 4),
        _ => null,
      };
}

/// DeviceGray/RGB/CMYK - components map straight through [colorFromComponents].
/// Also the fallback for anything unrecognised.
class _DeviceColorSpace extends PdfColorSpace {
  const _DeviceColorSpace(this.family, this.channels);

  @override
  final String family;

  @override
  final int channels;

  @override
  PdfColor toSrgb(List<double> values) => colorFromComponents(values, channels);

  @override
  PdfInkColorants? inkColorants(List<double> values) {
    double at(int i) =>
        i < values.length ? values[i].clamp(0.0, 1.0).toDouble() : 0.0;
    return switch (family) {
      'DeviceCMYK' => PdfInkColorants.deviceCmyk(at(0), at(1), at(2), at(3)),
      'DeviceGray' => PdfInkColorants.deviceGray(at(0)),
      _ => null,
    };
  }
}

/// The Pattern space: colours come from the pattern, not from components.
class _PatternColorSpace extends PdfColorSpace {
  const _PatternColorSpace();

  @override
  String get family => 'Pattern';

  @override
  int get channels => 0;

  @override
  PdfColor toSrgb(List<double> values) => PdfColor.black;
}

/// CalGray/CalRGB/Lab, delegating to the CIE machinery in
/// [PdfCalibratedColorSpace].
class _CalibratedColorSpace extends PdfColorSpace {
  const _CalibratedColorSpace(this.family, this._calibrated);

  @override
  final String family;

  final PdfCalibratedColorSpace _calibrated;

  @override
  int get channels => _calibrated.components;

  @override
  PdfColor toSrgb(List<double> values) => _calibrated.toSrgb(values);

  @override
  PdfColor toSrgbFromSamples(List<int> samples) =>
      _calibrated.toSrgbFromSamples(samples);
}

/// An ICCBased space. Converts through the parsed [profile] when its channel
/// count matches; otherwise (or when the profile could not be parsed) falls
/// back to the device family the profile's /N implies.
class _IccColorSpace extends PdfColorSpace {
  const _IccColorSpace(this._profile, this.channels);

  final IccProfile? _profile;

  @override
  final int channels;

  @override
  String get family => 'ICCBased';

  @override
  IccProfile? get iccProfile => _profile;

  @override
  PdfColor toSrgb(List<double> values) {
    final profile = _profile;
    if (profile != null && values.length == profile.channels) {
      // sRGB-equivalent: components pass through unmanaged (#531).
      if (profile.isSrgb) return colorFromComponents(values, channels);
      return profile.toSrgb(values);
    }
    return colorFromComponents(values, channels);
  }
}

/// An `[/Indexed base hival lookup]` palette space (§8.6.6.3). A single index
/// component selects a colour from the base space's lookup table.
class _IndexedColorSpace extends PdfColorSpace {
  _IndexedColorSpace(this._base, this._hival, this._table);

  final PdfColorSpace _base;
  final int _hival;
  final List<int> _table;

  @override
  String get family => 'Indexed';

  @override
  int get channels => 1;

  @override
  PdfColor toSrgb(List<double> values) {
    var index = (values.isEmpty ? 0.0 : values[0]).round();
    if (index < 0) index = 0;
    if (index > _hival) index = _hival;
    final n = _base.channels;
    final offset = index * n;
    if (n <= 0 || offset + n > _table.length) return PdfColor.black;
    return _base.toSrgbFromSamples(
        [for (var i = 0; i < n; i++) _table[offset + i]]);
  }

  static _IndexedColorSpace? parse(CosDocument cos, CosArray space,
      CosDictionary? resources, Map<CosStream, IccProfile?>? iccCache) {
    if (space.length < 4) return null;
    final base = PdfColorSpace.parse(cos, space[1],
        resources: resources, iccCache: iccCache);
    final hivalObj = cos.resolve(space[2]);
    final hival = switch (hivalObj) {
      CosInteger(:final value) => value,
      CosReal(:final value) => value.round(),
      _ => -1,
    };
    if (hival < 0) return null;
    final lookupObj = cos.resolve(space[3]);
    final List<int> table;
    if (lookupObj is CosString) {
      table = lookupObj.bytes;
    } else if (lookupObj is CosStream) {
      try {
        table = cos.decodeStreamData(lookupObj);
      } on Exception {
        return null;
      }
    } else {
      return null;
    }
    return _IndexedColorSpace(base, hival, table);
  }
}

/// A Separation or DeviceN space: colorant values run through a tint
/// transform ([function]) into the [alternate] space (§8.6.6.4).
class _TintColorSpace extends PdfColorSpace {
  _TintColorSpace(
      this.family, this.colorantNames, this._function, this._alternate);

  @override
  final String family;

  /// The colorant each component names (§8.6.6.4). A Separation has one.
  final List<String> colorantNames;

  @override
  int get channels => colorantNames.length;

  final PdfFunction _function;
  final PdfColorSpace _alternate;

  @override
  PdfColor toSrgb(List<double> values) =>
      _alternate.toSrgb(_function.evaluateAt(values));

  @override
  PdfInkColorants? inkColorants(List<double> values) {
    double at(int i) =>
        i < values.length ? values[i].clamp(0.0, 1.0).toDouble() : 0.0;
    var c = 0.0, m = 0.0, y = 0.0, k = 0.0;
    var mask = 0;
    final spots = <String>[];
    final tints = <double>[];
    final equivalents = <List<double>>[];
    for (var i = 0; i < colorantNames.length; i++) {
      final tint = at(i);
      switch (colorantNames[i]) {
        case 'All':
          // Every colorant on the device takes the tint (§8.6.6.4). Modelled
          // as an all-writing ink; [PdfInkColorants.over] carries the tint to
          // whatever spots the backdrop holds.
          return PdfInkColorants(
            colorants: PdfColorants(tint, tint, tint, tint),
            processMask: kColorantProcessAll,
            overprintModeApplies: false,
            writesAll: true,
          );
        case 'None':
          continue;
        case 'Cyan':
          c = tint;
          mask |= kColorantCyan;
        case 'Magenta':
          m = tint;
          mask |= kColorantMagenta;
        case 'Yellow':
          y = tint;
          mask |= kColorantYellow;
        case 'Black':
          k = tint;
          mask |= kColorantBlack;
        default:
          spots.add(colorantNames[i]);
          tints.add(tint);
          equivalents.add(_spotEquivalent(i));
      }
    }
    // [PdfColorants] keeps spot names sorted so two vectors naming the same
    // colorants compare equal whatever order the space listed them in.
    final order = [for (var i = 0; i < spots.length; i++) i]
      ..sort((a, b) => spots[a].compareTo(spots[b]));
    return PdfInkColorants(
      colorants: PdfColorants(c, m, y, k,
          spots: [for (final i in order) spots[i]],
          tints: [for (final i in order) tints[i]]),
      processMask: mask,
      // §8.6.7.3 scopes the overprint-mode-1 zero rule to DeviceCMYK. Applying
      // it to a Separation/DeviceN space instead is precisely the failure
      // GWG190's patch c grades ("X means the colour space might have been
      // converted to DeviceCMYK upfront (OPM 1)"): its DeviceN 100C/0Y/0K over
      // CMYK black must knock the black out to solid cyan under either mode.
      overprintModeApplies: false,
      spotEquivalents: [for (final i in order) equivalents[i]],
    );
  }

  /// The CMYK a full tint of colorant [index] alone renders as - what a
  /// composite vector naming this spot converts through when no single paint
  /// produced it. Evaluated through the space's own tint transform, so a
  /// DeviceN's per-colorant appearance comes from the document, not a guess.
  List<double> _spotEquivalent(int index) {
    final cached = _spotEquivalents[index];
    if (cached != null) return cached;
    final probe = List<double>.filled(colorantNames.length, 0)..[index] = 1;
    List<double> cmyk;
    try {
      final alternate = _function.evaluateAt(probe);
      cmyk = _alternate.family == 'DeviceCMYK' && alternate.length >= 4
          ? [
              for (var i = 0; i < 4; i++) alternate[i].clamp(0.0, 1.0).toDouble()
            ]
          : _cmykFromSrgb(_alternate.toSrgb(alternate));
    } on Exception {
      cmyk = const [0, 0, 0, 1];
    }
    return _spotEquivalents[index] = cmyk;
  }

  final Map<int, List<double>> _spotEquivalents = {};

  /// Naive sRGB → CMYK for an alternate space that is not DeviceCMYK. Only
  /// feeds the fallback conversion of a colorant combination no paint
  /// produced, never a colour the renderer shows directly.
  static List<double> _cmykFromSrgb(PdfColor color) {
    final k = 1 - [color.red, color.green, color.blue].reduce((a, b) => a > b ? a : b);
    if (k >= 1) return const [0, 0, 0, 1];
    return [
      (1 - color.red - k) / (1 - k),
      (1 - color.green - k) / (1 - k),
      (1 - color.blue - k) / (1 - k),
      k,
    ];
  }

  /// `[/Separation name alternate tint]`.
  static _TintColorSpace? parse(CosDocument cos, CosArray space,
      CosDictionary? resources, Map<CosStream, IccProfile?>? iccCache) {
    if (space.length < 4) return null;
    final function = PdfFunction.parse(cos, space[3]);
    if (function == null) return null;
    final alternate = PdfColorSpace.parse(cos, space[2],
        resources: resources, iccCache: iccCache);
    final name = cos.resolve(space[1]);
    return _TintColorSpace('Separation',
        [name is CosName ? name.value : ''], function, alternate);
  }

  /// `[/DeviceN names alternate tint attributes]`; the colorant count is the
  /// length of the `names` array.
  static _TintColorSpace? parseDeviceN(CosDocument cos, CosArray space,
      CosDictionary? resources, Map<CosStream, IccProfile?>? iccCache) {
    if (space.length < 4) return null;
    final names = cos.resolve(space[1]);
    if (names is! CosArray || names.length == 0) return null;
    final function = PdfFunction.parse(cos, space[3]);
    if (function == null) return null;
    final alternate = PdfColorSpace.parse(cos, space[2],
        resources: resources, iccCache: iccCache);
    return _TintColorSpace(
        'DeviceN',
        [
          for (final item in names.items)
            switch (cos.resolve(item)) {
              CosName(:final value) => value,
              _ => '',
            },
        ],
        function,
        alternate);
  }
}
