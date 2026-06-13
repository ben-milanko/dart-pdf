import 'dart:convert';
import 'dart:math' as math;

import 'package:pdf_cos/pdf_cos.dart';

import 'document.dart';
import 'measure.dart';
import 'rect.dart';

/// An entry in a page's /Annots array (§12.5).
///
/// Interactive subtypes get their own classes ([PdfLinkAnnotation],
/// [PdfWidgetAnnotation]); everything else (highlights, stamps, ink, ...)
/// parses as a plain [PdfAnnotation] until those kinds grow richer models.
class PdfAnnotation {
  PdfAnnotation._({
    required this.document,
    required this.dict,
    required this.subtype,
    required this.rect,
    required this.flags,
  });

  factory PdfAnnotation.fromDict(PdfDocument document, CosDictionary dict) {
    final cos = document.cos;
    final subtypeName = cos.resolve(dict['Subtype']);
    final subtype = subtypeName is CosName ? subtypeName.value : '';
    final rect = pdfRectFrom(cos, dict['Rect']) ?? const PdfRect(0, 0, 0, 0);
    final f = cos.resolve(dict['F']);
    final flags = f is CosInteger ? f.value : 0;

    switch (subtype) {
      case 'Link':
        return PdfLinkAnnotation._(
          document: document,
          dict: dict,
          rect: rect,
          flags: flags,
          action: PdfAction.parse(document, dict['A']) ??
              _destAsGoTo(document, dict['Dest']),
        );
      case 'Widget':
        return PdfWidgetAnnotation._parse(
            document: document, dict: dict, rect: rect, flags: flags);
      default:
        return PdfAnnotation._(
          document: document,
          dict: dict,
          subtype: subtype,
          rect: rect,
          flags: flags,
        );
    }
  }

  final PdfDocument document;

  /// The raw annotation dictionary, for entries not surfaced here yet.
  final CosDictionary dict;

  /// The /Subtype name without the slash ('Link', 'Widget', 'Highlight'...).
  final String subtype;

  /// Bounds in page space (PDF user space, y up).
  final PdfRect rect;

  /// The /F flag word (§12.5.3).
  final int flags;

  bool get isHidden => flags & 2 != 0;
  bool get isNoView => flags & 32 != 0;

  /// The ReadOnly flag (§12.5.3 bit 7): no interaction with the
  /// annotation at all.
  bool get isReadOnly => flags & 64 != 0;

  /// The Locked flag (§12.5.3 bit 8): the annotation may not be deleted
  /// and its properties (position, size) may not change — but its
  /// contents may, see [isLockedContents].
  bool get isLocked => flags & 128 != 0;

  /// The LockedContents flag (§12.5.3 bit 10): the annotation's contents
  /// may not change, though it can still move and resize.
  bool get isLockedContents => flags & 512 != 0;

  /// The /Contents text (note body, free-text body, tooltip), if any.
  String? get contents {
    final c = document.cos.resolve(dict['Contents']);
    return c is CosString ? c.text : null;
  }

  /// The author: /T, "the text label … by convention … the annotation's
  /// author" (§12.5.6.2). Meaningless on widgets, where /T is the form
  /// field's partial name instead.
  String? get author {
    final t = document.cos.resolve(dict['T']);
    return t is CosString ? t.text : null;
  }

  /// The annotation name: /NM, "a text string uniquely identifying it
  /// among all the annotations on its page" (§12.5.2).
  ///
  /// The editor stamps a generated UUID on every annotation it creates
  /// and preserves it through restyles and rewrites, which makes /NM the
  /// durable handle for syncing annotations across documents and devices
  /// — slots shift, names don't.
  String? get name {
    final nm = document.cos.resolve(dict['NM']);
    return nm is CosString ? nm.text : null;
  }

  /// The /C color as 0xRRGGBB, if present. Gray and CMYK component
  /// counts are converted; an empty array (explicit "no color") and
  /// malformed entries resolve to null.
  ///
  /// For free text /C is the *background* color per §12.5.6.6 (see
  /// [freeTextStyle], which disambiguates against legacy files where it
  /// held the text color).
  int? get color => _colorArray(dict['C']);

  /// The /IC interior (fill) color of shape annotations, as 0xRRGGBB.
  int? get interiorColor => _colorArray(dict['IC']);

  /// The /BS border-style width, or null when no /BS /W is present.
  double? get borderWidth {
    final bs = document.cos.resolve(dict['BS']);
    if (bs is! CosDictionary) return null;
    final w = document.cos.resolve(bs['W']);
    if (w is CosInteger) return w.value.toDouble();
    return w is CosReal ? w.value : null;
  }

  /// The /BS dash array, or null for solid or malformed borders.
  List<double>? get borderDash {
    final bs = document.cos.resolve(dict['BS']);
    if (bs is! CosDictionary) return null;
    final d = document.cos.resolve(bs['D']);
    if (d is! CosArray) return null;
    final values = <double>[];
    for (final item in d.items) {
      final n = _number(document.cos.resolve(item));
      if (n == null || n < 0) return null;
      values.add(n);
    }
    return values.any((value) => value > 0) ? values : null;
  }

  /// The endpoints of a /Line annotation, page space.
  ((double, double), (double, double))? get line {
    if (subtype != 'Line') return null;
    final l = document.cos.resolve(dict['L']);
    if (l is! CosArray || l.length < 4) return null;
    final x1 = _number(document.cos.resolve(l[0]));
    final y1 = _number(document.cos.resolve(l[1]));
    final x2 = _number(document.cos.resolve(l[2]));
    final y2 = _number(document.cos.resolve(l[3]));
    if (x1 == null || y1 == null || x2 == null || y2 == null) return null;
    return ((x1, y1), (x2, y2));
  }

  /// The vertices of a /PolyLine or /Polygon annotation, page space.
  List<(double, double)>? get vertices {
    if (subtype != 'PolyLine' && subtype != 'Polygon') return null;
    final raw = document.cos.resolve(dict['Vertices']);
    if (raw is! CosArray) return null;
    final points = <(double, double)>[];
    for (var i = 0; i + 1 < raw.items.length; i += 2) {
      final x = _number(document.cos.resolve(raw.items[i]));
      final y = _number(document.cos.resolve(raw.items[i + 1]));
      if (x == null || y == null) return null;
      points.add((x, y));
    }
    return points;
  }

  /// The /Measure dictionary (§12.9): the scale and unit formats a
  /// measurement annotation (Line/PolyLine/Polygon) carries. Null when
  /// the annotation has no /Measure.
  PdfMeasure? get measure => PdfMeasure.fromDict(document, dict['Measure']);

  /// The real-world measurement this annotation represents, formatted
  /// through its /Measure: a distance for /Line, a perimeter (the sum of
  /// the segment lengths) for /PolyLine, and a shoelace area for
  /// /Polygon. Null without a /Measure or for other subtypes.
  String? get measurementText {
    final m = measure;
    if (m == null) return null;
    switch (subtype) {
      case 'Line':
        final l = line;
        if (l == null) return null;
        final dx = l.$2.$1 - l.$1.$1;
        final dy = l.$2.$2 - l.$1.$2;
        return m.formatDistance(math.sqrt(dx * dx + dy * dy));
      case 'PolyLine':
        final v = vertices;
        if (v == null || v.length < 2) return null;
        var total = 0.0;
        for (var i = 0; i + 1 < v.length; i++) {
          final dx = v[i + 1].$1 - v[i].$1;
          final dy = v[i + 1].$2 - v[i].$2;
          total += math.sqrt(dx * dx + dy * dy);
        }
        return m.formatDistance(total);
      case 'Polygon':
        final v = vertices;
        if (v == null || v.length < 3) return null;
        return m.formatArea(pdfShoelaceArea(v));
      default:
        return null;
    }
  }

  static double? _number(CosObject? value) => switch (value) {
        CosInteger(:final value) => value.toDouble(),
        CosReal(:final value) => value,
        _ => null,
      };

  int? _colorArray(CosObject? raw) {
    final c = document.cos.resolve(raw);
    if (c is! CosArray) return null;
    final values = <double>[];
    for (final item in c.items) {
      final n = document.cos.resolve(item);
      if (n is CosInteger) {
        values.add(n.value.toDouble());
      } else if (n is CosReal) {
        values.add(n.value);
      } else {
        return null;
      }
    }
    if (values.length != 1 && values.length != 3 && values.length != 4) {
      return null;
    }
    final (r, g, b) = switch (values.length) {
      1 => (values[0], values[0], values[0]),
      3 => (values[0], values[1], values[2]),
      _ => (
          (1 - values[0]) * (1 - values[3]),
          (1 - values[1]) * (1 - values[3]),
          (1 - values[2]) * (1 - values[3]),
        ),
    };
    int byte(double v) => (v.clamp(0.0, 1.0) * 255).round();
    return (byte(r) << 16) | (byte(g) << 8) | byte(b);
  }

  /// The /DA default-appearance string (free text, widgets), if any.
  String? get defaultAppearance {
    final da = document.cos.resolve(dict['DA']);
    return da is CosString ? da.text : null;
  }

  /// The complete style of a free-text annotation, parsed from /DA, /C,
  /// and /BS — everything needed to regenerate its appearance at a new
  /// size. Null for other subtypes or when /DA has no usable `Tf`.
  ///
  /// Mapping: text color is /DA's `rg` (or `g`) operator; the background
  /// is /C (per §12.5.6.6 — but a /C that *equals* the text color is
  /// treated as a legacy text-color mirror, not a background); border
  /// width is /BS /W (0 when absent — the /Border default of 1 would
  /// conjure borders most viewers never drew); border color is /DA's
  /// `RG` operator, falling back to the text color when /BS declares a
  /// width without one.
  PdfFreeTextStyle? get freeTextStyle {
    if (subtype != 'FreeText') return null;
    final da = defaultAppearance;
    final tf =
        da == null ? null : RegExp(r'/(\S+)\s+([\d.]+)\s+Tf').firstMatch(da);
    final size = double.tryParse(tf?.group(2) ?? '');
    if (tf == null || size == null) return null;

    int? lastColor(String op) {
      final m = RegExp('([\\d.]+)\\s+([\\d.]+)\\s+([\\d.]+)\\s+$op\\b')
          .allMatches(da!)
          .lastOrNull;
      if (m == null) return null;
      int byte(String s) =>
          ((double.tryParse(s) ?? 0).clamp(0.0, 1.0) * 255).round();
      return (byte(m.group(1)!) << 16) |
          (byte(m.group(2)!) << 8) |
          byte(m.group(3)!);
    }

    int? gray() {
      final m = RegExp(r'([\d.]+)\s+g\b').allMatches(da!).lastOrNull;
      if (m == null) return null;
      final v =
          ((double.tryParse(m.group(1)!) ?? 0).clamp(0.0, 1.0) * 255).round();
      return (v << 16) | (v << 8) | v;
    }

    final text = lastColor('rg') ?? gray() ?? 0x000000;
    final background = color;
    final width = borderWidth ?? 0;
    return PdfFreeTextStyle(
      fontName: tf.group(1)!,
      fontSize: size,
      color: text,
      fillColor: background != null && background != text ? background : null,
      borderColor: lastColor('RG') ?? (width > 0 ? text : null),
      borderWidth: width,
    );
  }

  /// The /InkList strokes of an Ink annotation, page space: one list of
  /// (x, y) points per stroke. Null for other subtypes or without a
  /// usable /InkList. Odd trailing numbers in a stroke are dropped.
  List<List<(double, double)>>? get inkList {
    if (subtype != 'Ink') return null;
    final cos = document.cos;
    final raw = cos.resolve(dict['InkList']);
    if (raw is! CosArray) return null;
    final strokes = <List<(double, double)>>[];
    for (final item in raw.items) {
      final stroke = cos.resolve(item);
      if (stroke is! CosArray) return null;
      final points = <(double, double)>[];
      for (var i = 0; i + 1 < stroke.items.length; i += 2) {
        final x = _number(cos.resolve(stroke.items[i]));
        final y = _number(cos.resolve(stroke.items[i + 1]));
        if (x == null || y == null) return null;
        points.add((x, y));
      }
      strokes.add(points);
    }
    return strokes;
  }

  /// The action this annotation triggers when activated, if any.
  PdfAction? get action => null;

  /// The normal appearance stream (§12.5.5): /AP → /N, a Form XObject.
  ///
  /// When /N holds a subdictionary of states (checkboxes, radio buttons),
  /// the /AS entry selects one; without /AS a sole entry is used, anything
  /// more ambiguous resolves to null.
  CosStream? get normalAppearance {
    final cos = document.cos;
    final ap = cos.resolve(dict['AP']);
    if (ap is! CosDictionary) return null;
    var n = cos.resolve(ap['N']);
    if (n is CosDictionary) {
      final state = cos.resolve(dict['AS']);
      if (state is CosName) {
        n = cos.resolve(n[state.value]);
      } else if (n.entries.length == 1) {
        n = cos.resolve(n.entries.values.single);
      } else {
        return null;
      }
    }
    return n is CosStream ? n : null;
  }

  /// The constant alpha the normal appearance carries: the first /ca
  /// among its /Resources /ExtGState entries — where [PdfEditor]-authored
  /// annotations store their opacity (they deliberately write no dict
  /// /CA, which conforming viewers would apply *on top* of the alpha
  /// already baked into the appearance). 1.0 without one.
  double get appearanceOpacity {
    final cos = document.cos;
    final form = normalAppearance;
    if (form == null) return 1;
    final resources = cos.resolve(form.dictionary['Resources']);
    if (resources is! CosDictionary) return 1;
    final ext = cos.resolve(resources['ExtGState']);
    if (ext is! CosDictionary) return 1;
    for (final entry in ext.entries.values) {
      final gs = cos.resolve(entry);
      if (gs is! CosDictionary) continue;
      final ca = cos.resolve(gs['ca']);
      if (ca is CosInteger) return ca.value.toDouble().clamp(0.0, 1.0);
      if (ca is CosReal) return ca.value.clamp(0.0, 1.0);
    }
    return 1;
  }

  /// The page-space corners of the normal appearance's /BBox after its
  /// /Matrix and the §12.5.5 fit onto [rect], in BBox corner order:
  /// lower-left, lower-right, upper-right, upper-left.
  ///
  /// For an appearance whose matrix carries no rotation these are just
  /// [rect]'s corners; after [PdfEditor.rotateAnnotation] they trace the
  /// rotated artwork, so a viewer can draw selection chrome that hugs it
  /// instead of the axis-aligned /Rect bounds. Null without an
  /// appearance stream or a usable /BBox.
  List<(double x, double y)>? get appearanceQuad {
    final form = normalAppearance;
    if (form == null) return null;
    final cos = document.cos;
    final bbox = pdfRectFrom(cos, form.dictionary['BBox']);
    if (bbox == null) return null;
    var m = const <double>[1, 0, 0, 1, 0, 0];
    final raw = cos.resolve(form.dictionary['Matrix']);
    if (raw is CosArray && raw.length >= 6) {
      final values = <double>[];
      for (var i = 0; i < 6; i++) {
        final n = cos.resolve(raw[i]);
        values.add(n is CosInteger
            ? n.value.toDouble()
            : n is CosReal
                ? n.value
                : (i == 0 || i == 3 ? 1.0 : 0.0));
      }
      m = values;
    }
    final corners = [
      for (final (x, y) in [
        (bbox.left, bbox.bottom),
        (bbox.right, bbox.bottom),
        (bbox.right, bbox.top),
        (bbox.left, bbox.top),
      ])
        (m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5])
    ];
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final (x, y) in corners) {
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
    if (maxX - minX < 1e-9 || maxY - minY < 1e-9) return null;
    final sx = rect.width / (maxX - minX);
    final sy = rect.height / (maxY - minY);
    return [
      for (final (x, y) in corners)
        (rect.left + (x - minX) * sx, rect.bottom + (y - minY) * sy)
    ];
  }

  static PdfGoToAction? _destAsGoTo(PdfDocument document, CosObject? raw) {
    final destination = PdfDestination.parse(document, raw);
    return destination == null ? null : PdfGoToAction(destination);
  }
}

/// A free-text annotation's text and box styling, as recoverable from
/// its dictionary (see [PdfAnnotation.freeTextStyle]). Colors are
/// 0xRRGGBB.
class PdfFreeTextStyle {
  const PdfFreeTextStyle({
    required this.fontName,
    required this.fontSize,
    required this.color,
    this.fillColor,
    this.borderColor,
    this.borderWidth = 0,
  });

  /// The /DA font resource name (e.g. `Helv`), unresolved.
  final String fontName;
  final double fontSize;

  /// The text color.
  final int color;

  /// The box background, or null for a transparent box.
  final int? fillColor;

  /// The box border color, or null for no border.
  final int? borderColor;
  final double borderWidth;
}

/// A /Link annotation: a clickable region with an action (§12.5.6.5).
///
/// A bare /Dest entry (the pre-action way to express "go to page X")
/// surfaces as a [PdfGoToAction] so consumers handle one shape.
class PdfLinkAnnotation extends PdfAnnotation {
  PdfLinkAnnotation._({
    required super.document,
    required super.dict,
    required super.rect,
    required super.flags,
    required PdfAction? action,
  })  : _action = action,
        super._(subtype: 'Link');

  final PdfAction? _action;

  @override
  PdfAction? get action => _action;
}

/// A /Widget annotation: the visible incarnation of an AcroForm field
/// (§12.5.6.19). Push buttons carry actions; other field kinds will grow
/// value accessors when form filling lands.
class PdfWidgetAnnotation extends PdfAnnotation {
  PdfWidgetAnnotation._({
    required super.document,
    required super.dict,
    required super.rect,
    required super.flags,
    required PdfAction? action,
    required this.fieldType,
    required this.fieldName,
  })  : _action = action,
        super._(subtype: 'Widget');

  factory PdfWidgetAnnotation._parse({
    required PdfDocument document,
    required CosDictionary dict,
    required PdfRect rect,
    required int flags,
  }) {
    // /FT and /T live on the widget itself when field and widget are
    // merged, otherwise up the /Parent field chain; /T parts join into the
    // fully qualified field name (§12.7.4.2)
    final cos = document.cos;
    String? fieldType;
    final parts = <String>[];
    CosDictionary? node = dict;
    final visited = <CosDictionary>{};
    while (node != null && visited.add(node)) {
      final t = cos.resolve(node['T']);
      if (t is CosString) parts.insert(0, t.text);
      if (fieldType == null) {
        final ft = cos.resolve(node['FT']);
        if (ft is CosName) fieldType = ft.value;
      }
      final parent = cos.resolve(node['Parent']);
      node = parent is CosDictionary ? parent : null;
    }
    return PdfWidgetAnnotation._(
      document: document,
      dict: dict,
      rect: rect,
      flags: flags,
      action: PdfAction.parse(document, dict['A']),
      fieldType: fieldType,
      fieldName: parts.isEmpty ? null : parts.join('.'),
    );
  }

  final PdfAction? _action;

  /// The field type name without the slash ('Btn', 'Tx', 'Ch', 'Sig').
  final String? fieldType;

  /// Fully qualified field name (partial names joined with dots).
  final String? fieldName;

  /// The field's current value — /V resolved up the /Parent chain
  /// (§12.7.4.2): the text of text and choice fields, the on-state name
  /// of buttons ('Off' when unchecked), the first element of a
  /// multi-select choice value.
  String? get fieldValue {
    final cos = document.cos;
    CosDictionary? node = dict;
    final visited = <CosDictionary>{};
    while (node != null && visited.add(node)) {
      final v = cos.resolve(node['V']);
      if (v is CosString) return v.text;
      if (v is CosName) return v.value;
      if (v is CosArray && v.length > 0) {
        final first = cos.resolve(v[0]);
        if (first is CosString) return first.text;
      }
      final parent = cos.resolve(node['Parent']);
      node = parent is CosDictionary ? parent : null;
    }
    return null;
  }

  @override
  PdfAction? get action => _action;
}

/// An action dictionary (§12.6). Unrecognized types parse as
/// [PdfUnknownAction] with the raw dictionary attached, so apps can still
/// inspect /Launch, /GoToR, /SubmitForm, ... themselves.
sealed class PdfAction {
  const PdfAction();

  static PdfAction? parse(PdfDocument document, CosObject? raw) {
    final cos = document.cos;
    final dict = cos.resolve(raw);
    if (dict is! CosDictionary) return null;
    final s = cos.resolve(dict['S']);
    final type = s is CosName ? s.value : '';
    switch (type) {
      case 'URI':
        final uri = cos.resolve(dict['URI']);
        return uri is CosString ? PdfUriAction(uri.text) : null;
      case 'GoTo':
        final destination = PdfDestination.parse(document, dict['D']);
        return destination == null ? null : PdfGoToAction(destination);
      case 'Named':
        final name = cos.resolve(dict['N']);
        return name is CosName ? PdfNamedAction(name.value) : null;
      case 'JavaScript':
        final js = cos.resolve(dict['JS']);
        if (js is CosString) return PdfJavaScriptAction(js.text);
        if (js is CosStream) {
          return PdfJavaScriptAction(
              utf8.decode(cos.decodeStreamData(js), allowMalformed: true));
        }
        return null;
      default:
        return PdfUnknownAction(type, dict);
    }
  }
}

/// /URI: open a (possibly app-defined) URI. The conventional bridge for
/// "a button in the PDF drives the host app": author links with a custom
/// scheme and dispatch on it in the viewer's action callback.
class PdfUriAction extends PdfAction {
  const PdfUriAction(this.uri);
  final String uri;
}

/// /GoTo: jump to a destination in this document.
class PdfGoToAction extends PdfAction {
  const PdfGoToAction(this.destination);
  final PdfDestination destination;
}

/// /Named: a viewer-defined action (NextPage, PrevPage, FirstPage,
/// LastPage are the standard four).
class PdfNamedAction extends PdfAction {
  const PdfNamedAction(this.name);
  final String name;
}

/// /JavaScript: the script is surfaced verbatim — there is deliberately no
/// JS engine here. Apps that author their own PDFs can pattern-match the
/// source; everything else should be ignored.
class PdfJavaScriptAction extends PdfAction {
  const PdfJavaScriptAction(this.script);
  final String script;
}

/// Any /S type without a dedicated class yet.
class PdfUnknownAction extends PdfAction {
  const PdfUnknownAction(this.type, this.dict);
  final String type;
  final CosDictionary dict;
}

/// An explicit destination (§12.3.2.2): a target page plus how to fit it.
class PdfDestination {
  const PdfDestination({
    required this.pageIndex,
    required this.fit,
    required this.params,
  });

  /// Zero-based page index, already resolved from the page reference.
  final int pageIndex;

  /// The fit style name without the slash: XYZ, Fit, FitH, FitV, FitR,
  /// FitB, FitBH, or FitBV.
  final String fit;

  /// The numeric operands after the fit name; null entries were /null in
  /// the file (meaning "keep the current value").
  final List<double?> params;

  double? get left => switch (fit) {
        'XYZ' || 'FitV' || 'FitBV' => _param(0),
        'FitR' => _param(0),
        _ => null,
      };

  double? get top => switch (fit) {
        'XYZ' => _param(1),
        'FitH' || 'FitBH' => _param(0),
        'FitR' => _param(3),
        _ => null,
      };

  double? get zoom => fit == 'XYZ' ? _param(2) : null;

  double? _param(int i) => i < params.length ? params[i] : null;

  /// Parses any destination form: an explicit array, a name or string
  /// resolved through the catalog's /Dests dictionary or the /Names →
  /// /Dests name tree, or a dictionary wrapping the array under /D.
  static PdfDestination? parse(PdfDocument document, CosObject? raw) {
    final cos = document.cos;
    var value = cos.resolve(raw);
    if (value is CosName) {
      value = cos.resolve(_lookupNamed(document, value.value));
    }
    if (value is CosString) {
      value = cos.resolve(_lookupNamed(document, value.text));
    }
    if (value is CosDictionary) value = cos.resolve(value['D']);
    if (value is! CosArray || value.length == 0) return null;

    final pageObj = cos.resolve(value[0]);
    final int pageIndex;
    if (pageObj is CosDictionary) {
      pageIndex = document.pageIndexOf(pageObj);
    } else if (pageObj is CosInteger) {
      // remote destinations count pages instead of referencing them; some
      // broken in-document destinations do too
      pageIndex = pageObj.value;
    } else {
      return null;
    }
    if (pageIndex < 0) return null;

    var fit = 'Fit';
    if (value.length > 1) {
      final f = cos.resolve(value[1]);
      if (f is CosName) fit = f.value;
    }
    final params = <double?>[];
    for (var i = 2; i < value.length; i++) {
      final n = cos.resolve(value[i]);
      params.add(n is CosInteger
          ? n.value.toDouble()
          : n is CosReal
              ? n.value
              : null);
    }
    return PdfDestination(pageIndex: pageIndex, fit: fit, params: params);
  }

  static CosObject? _lookupNamed(PdfDocument document, String name) {
    final cos = document.cos;
    // PDF 1.1 kept named destinations in a plain catalog /Dests dictionary
    final dests = cos.resolve(document.catalog['Dests']);
    if (dests is CosDictionary && dests.containsKey(name)) {
      return dests[name];
    }
    final names = cos.resolve(document.catalog['Names']);
    if (names is CosDictionary) {
      final tree = cos.resolve(names['Dests']);
      if (tree is CosDictionary) {
        return _searchNameTree(cos, tree, name, <CosDictionary>{});
      }
    }
    return null;
  }

  /// Linear name-tree walk; /Limits-guided binary search is an
  /// optimization real-world files often get wrong, so stay lenient.
  static CosObject? _searchNameTree(CosDocument cos, CosDictionary node,
      String name, Set<CosDictionary> visited) {
    if (!visited.add(node)) return null;
    final entries = cos.resolve(node['Names']);
    if (entries is CosArray) {
      for (var i = 0; i + 1 < entries.length; i += 2) {
        final key = cos.resolve(entries[i]);
        if (key is CosString && key.text == name) return entries[i + 1];
      }
    }
    final kids = cos.resolve(node['Kids']);
    if (kids is CosArray) {
      for (final kid in kids.items) {
        final child = cos.resolve(kid);
        if (child is CosDictionary) {
          final found = _searchNameTree(cos, child, name, visited);
          if (found != null) return found;
        }
      }
    }
    return null;
  }
}
