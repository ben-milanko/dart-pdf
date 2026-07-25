import 'dart:convert';
import 'dart:math' as math;

import 'package:pdf_cos/pdf_cos.dart';

import 'content_writer.dart';
import 'document.dart';
import 'measure.dart';
import 'rect.dart';
import 'takeoff.dart';

part 'annotation_behavior.dart';

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

  /// PDF-semantic editing capabilities and authoritative style for this
  /// annotation.
  ///
  /// The descriptor is lazy and cached for the lifetime of this parsed
  /// annotation. A saved editor revision produces new [PdfAnnotation]
  /// instances, so hot UI paths can reuse the derived facts without stale
  /// cross-revision state or repeated appearance-stream parsing.
  late final PdfAnnotationBehavior behavior = PdfAnnotationBehavior._(this);

  bool get isHidden => flags & 2 != 0;
  bool get isNoView => flags & 32 != 0;

  /// The Print flag (§12.5.3 bit 3): the annotation is printed when the
  /// page is printed. When clear, the annotation shows on screen but is
  /// omitted from print output.
  bool get isPrint => flags & 4 != 0;

  /// The ReadOnly flag (§12.5.3 bit 7): no interaction with the
  /// annotation at all.
  bool get isReadOnly => flags & 64 != 0;

  /// The Locked flag (§12.5.3 bit 8): the annotation may not be deleted
  /// and its properties (position, size) may not change - but its
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
  /// - slots shift, names don't.
  String? get name {
    final nm = document.cos.resolve(dict['NM']);
    return nm is CosString ? nm.text : null;
  }

  /// The /Name appearance/icon name (§12.5.6.x): the named icon a /Text
  /// or /Stamp annotation draws (e.g. `Comment`, `Approved`, `Check`).
  /// Distinct from [name], which reads /NM.
  String? get iconName {
    final n = document.cos.resolve(dict['Name']);
    return n is CosName ? n.value : null;
  }

  /// Whether this is a count check-mark: a /Stamp whose /Name is `Check`,
  /// placed by the editor's count tool. The editing UI tallies these
  /// Bluebeam-style.
  bool get isCheckMark => subtype == 'Stamp' && iconName == 'Check';

  /// App-defined workflow type for a custom stamp annotation, e.g.
  /// `Approval`, `Audit`, or `Tested`.
  ///
  /// The editor writes this private metadata when a custom stamp with a type
  /// is placed. It stays in the annotation dictionary so tap handlers,
  /// annotation sync, and reopened documents can classify placed stamps
  /// without relying on their visible caption.
  String? get stampType {
    final value = document.cos.resolve(dict['DartPdfStampType']);
    return value is CosString ? value.text : null;
  }

  /// Whether this /Stamp is a placed raster picture (PdfEditor.addImageStamp)
  /// rather than a drawn text or template stamp.
  ///
  /// The editor writes this private marker when it embeds an image as a
  /// stamp. It stays in the dictionary across saves, copies, and reopens so
  /// the restyle path knows it can re-bake the appearance's alpha over the
  /// same picture - and does not mistake a template stamp that merely
  /// contains an image component for a bare image.
  bool get isImageStamp {
    if (subtype != 'Stamp') return false;
    final value = document.cos.resolve(dict['DartPdfImageStamp']);
    return value is CosBoolean && value.value;
  }

  /// The cropped sub-region of an image stamp's source picture that its
  /// appearance draws, in normalized image coordinates (origin bottom-left,
  /// `[0,0,1,1]` is the whole image). Null when this is not an image stamp
  /// or the whole picture is shown (no crop applied).
  ///
  /// The editor writes this private marker when an image stamp is cropped
  /// ([PdfAnnotationEditing.cropImageStamp]) so the crop survives saves,
  /// copies, and reopens, and is re-baked whenever the appearance is
  /// regenerated (opacity restyle). Absent on an uncropped picture.
  PdfRect? get imageStampCrop {
    if (!isImageStamp) return null;
    final value = document.cos.resolve(dict['DartPdfImageCrop']);
    if (value is! CosArray || value.length < 4) return null;
    final crop = pdfRectFrom(document.cos, value);
    if (crop == null) return null;
    // A degenerate or full-image marker reads as "no crop".
    if (crop.width <= 0 || crop.height <= 0) return null;
    if (crop.left <= 0 &&
        crop.bottom <= 0 &&
        crop.right >= 1 &&
        crop.top >= 1) {
      return null;
    }
    return crop;
  }

  /// App-defined labels attached to a custom stamp annotation.
  ///
  /// These are stored as private annotation metadata beside [stampType].
  List<String> get stampTags {
    final value = document.cos.resolve(dict['DartPdfStampTags']);
    if (value is! CosArray) return const [];
    final tags = <String>[];
    for (final item in value.items) {
      final tag = document.cos.resolve(item);
      if (tag is CosString && tag.text.trim().isNotEmpty) {
        tags.add(tag.text);
      }
    }
    return List.unmodifiable(tags);
  }

  /// The /NM of the annotation this one is in reply to (§12.5.6.x): /IRT
  /// is an indirect reference to the parent markup annotation, which this
  /// resolves to its [name]. Null when the annotation is not a reply (or
  /// the parent carries no /NM). Used to assemble comment threads
  /// ([PdfCommentThread]) and to relink replies across documents on sync.
  String? get inReplyTo {
    final irt = document.cos.resolve(dict['IRT']);
    if (irt is! CosDictionary) return null;
    final nm = document.cos.resolve(irt['NM']);
    return nm is CosString ? nm.text : null;
  }

  /// The /RT reply type (§12.5.6.x): `R` (a reply in a thread, the default
  /// when /IRT is present) or `Group` (this annotation is grouped with the
  /// /IRT one, sharing its properties). Null when absent.
  String? get replyType {
    final rt = document.cos.resolve(dict['RT']);
    return rt is CosName ? rt.value : null;
  }

  /// The review/marked /State (§12.5.6.2): `Accepted`, `Rejected`,
  /// `Cancelled`, `Completed`, `None` (the Review model) or `Marked` /
  /// `Unmarked` (the Marked model). Carried by a dedicated reply
  /// annotation, never on the comment it annotates.
  String? get reviewState {
    final s = document.cos.resolve(dict['State']);
    return s is CosString ? s.text : null;
  }

  /// The /StateModel naming which family [reviewState] belongs to -
  /// `Review` or `Marked` (§12.5.6.2). Its presence is what marks an
  /// annotation as a *state* annotation rather than a content reply.
  String? get stateModel {
    final s = document.cos.resolve(dict['StateModel']);
    return s is CosString ? s.text : null;
  }

  /// The /Subj short subject/heading of a markup annotation (§12.5.6.2).
  String? get subject {
    final s = document.cos.resolve(dict['Subj']);
    return s is CosString ? s.text : null;
  }

  /// The /CreationDate parsed from its PDF date string (§7.9.4), if any.
  DateTime? get creationDate =>
      _parsePdfDate(document.cos.resolve(dict['CreationDate']) is CosString
          ? (document.cos.resolve(dict['CreationDate']) as CosString).text
          : null);

  /// The /M modification date parsed from its PDF date string, if any.
  DateTime? get modificationDate {
    final m = document.cos.resolve(dict['M']);
    return m is CosString ? _parsePdfDate(m.text) : null;
  }

  /// Whether this is a *state* annotation (§12.5.6.2): a reply that records
  /// a review/marked state ([reviewState] + [stateModel]) rather than text.
  /// Such annotations carry the thread's status, not page graphics, so the
  /// renderer treats them like popups and does not paint them.
  bool get isStateAnnotation => stateModel != null;

  /// Whether this is a thread reply (§12.5.6.x): it carries /IRT and its
  /// /RT is `R` (or absent, which defaults to a reply). Group annotations
  /// (/RT `Group`) are not replies. Replies are thread content, shown by a
  /// viewer in the comment pane, not painted as a second icon on the page.
  bool get isReply {
    if (dict['IRT'] == null) return false;
    final rt = replyType;
    return rt == null || rt == 'R';
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

  /// The corner radius (page points) of a /Square annotation's rounded
  /// rectangle, from the /Border array's first entry (§12.5.4
  /// `[hCornerRadius vCornerRadius width]`); 0 for square corners or when
  /// /Border is absent or malformed.
  double get cornerRadius {
    final border = document.cos.resolve(dict['Border']);
    if (border is! CosArray || border.length < 3) return 0;
    final r = _number(document.cos.resolve(border[0]));
    return r != null && r > 0 ? r : 0;
  }

  /// Whether the annotation asks conforming viewers to render its border as
  /// a cloudy border effect (`/BE << /S /Cloudy ... >>`).
  bool get hasCloudyBorder {
    final be = document.cos.resolve(dict['BE']);
    if (be is! CosDictionary) return false;
    final style = document.cos.resolve(be['S']);
    return style is CosName && style.value == 'Cloudy';
  }

  /// The cloud scallop scale carried on `/BE /I` (§12.5.4) - the border
  /// effect intensity, which the editor also uses as a puff-size multiplier
  /// so a cloud's scallop size survives a restyle or reshape independently
  /// of its stroke width. Defaults to 1 when absent or not cloudy.
  double get cloudBorderScale {
    final be = document.cos.resolve(dict['BE']);
    if (be is! CosDictionary) return 1;
    final intensity = _number(document.cos.resolve(be['I']));
    return intensity == null || intensity <= 0 ? 1 : intensity;
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

  /// True when this is a FreeText callout (§12.5.6.19): a text box joined
  /// to a point on the page by a leader line (/CL) that ends in an arrow.
  bool get isCallout {
    if (subtype != 'FreeText') return false;
    final it = document.cos.resolve(dict['IT']);
    return it is CosName && it.value == 'FreeTextCallout';
  }

  /// The callout leader-line points (/CL, §12.5.6.19) in page space - the
  /// first point is the arrow tip on the page, the last touches the text
  /// box. Null when this is not a callout or carries no usable /CL.
  List<(double, double)>? get calloutLine {
    if (!isCallout) return null;
    final raw = document.cos.resolve(dict['CL']);
    if (raw is! CosArray || raw.items.length < 4) return null;
    final points = <(double, double)>[];
    for (var i = 0; i + 1 < raw.items.length; i += 2) {
      final x = _number(document.cos.resolve(raw.items[i]));
      final y = _number(document.cos.resolve(raw.items[i + 1]));
      if (x == null || y == null) return null;
      points.add((x, y));
    }
    return points;
  }

  /// The text-box sub-rect of a callout (§12.5.6.19): [rect] inset by /RD,
  /// distinct from /Rect which also encloses the leader line and arrowhead.
  /// Null when this is not a callout.
  PdfRect? get calloutBox {
    if (!isCallout) return null;
    final rd = document.cos.resolve(dict['RD']);
    double d(int i) {
      if (rd is! CosArray || rd.items.length <= i) return 0;
      return _number(document.cos.resolve(rd.items[i])) ?? 0;
    }

    final r = rect;
    return PdfRect(
        r.left + d(0), r.bottom + d(3), r.right - d(2), r.top - d(1));
  }

  /// The /Measure dictionary (§12.9): the scale and unit formats a
  /// measurement annotation (Line/PolyLine/Polygon) carries. Null when
  /// the annotation has no /Measure.
  PdfMeasure? get measure => PdfMeasure.fromDict(document, dict['Measure']);

  /// The takeoff metadata (/Takeoff) carried by a count/volume/angle/arc/
  /// slope/area-cutout measurement, or null for a plain annotation. See
  /// [PdfTakeoffData].
  PdfTakeoffData? get takeoff => PdfTakeoffData.read(this);

  /// The measurement kind this annotation represents: the explicit
  /// /Takeoff /K when present, else inferred from the subtype (Line →
  /// distance, PolyLine → perimeter, Polygon → area). Null when the
  /// annotation isn't a measurement.
  PdfMeasurementKind? get measurementKind {
    final t = takeoff;
    if (t != null) return t.kind;
    // the Bluebeam-style count tool drops /Stamp check-marks (no /Measure);
    // surface them as count measurements so a takeoff total tallies them.
    if (isCheckMark) return PdfMeasurementKind.count;
    if (measure == null) return null;
    return switch (subtype) {
      'Line' => PdfMeasurementKind.distance,
      'PolyLine' => PdfMeasurementKind.perimeter,
      'Polygon' => PdfMeasurementKind.area,
      _ => null,
    };
  }

  /// The vertices a measurement reads its geometry from: a /Line's two
  /// endpoints, a /PolyLine or /Polygon's [vertices], or a single-point
  /// marker (a count) at the /Rect centre.
  List<(double, double)>? get _measurementPoints {
    final l = line;
    if (l != null) return [l.$1, l.$2];
    final v = vertices;
    if (v != null) return v;
    if (measurementKind == PdfMeasurementKind.count) {
      return [((rect.left + rect.right) / 2, (rect.bottom + rect.top) / 2)];
    }
    return null;
  }

  /// The fully computed takeoff measurement - kind, real-world value, unit,
  /// formatted text - or null when the annotation isn't a measurement (no
  /// /Measure and not a count marker).
  PdfMeasurementResult? get measurementResult {
    final kind = measurementKind;
    if (kind == null) return null;
    final m = measure;
    final t = takeoff;
    final pts = _measurementPoints;

    switch (kind) {
      case PdfMeasurementKind.count:
        return PdfMeasurementResult(
            kind: kind, value: 1, unit: '', text: '1', count: 1);
      case PdfMeasurementKind.distance:
        if (m == null || pts == null || pts.length < 2) return null;
        final len = pdfPolylineLength(pts);
        return PdfMeasurementResult(
            kind: kind,
            value: m.realDistance(len),
            unit: m.distance.first.unit,
            text: m.formatDistance(len));
      case PdfMeasurementKind.perimeter:
        if (m == null || pts == null || pts.length < 2) return null;
        final len = pdfPolylineLength(pts);
        return PdfMeasurementResult(
            kind: kind,
            value: m.realDistance(len),
            unit: m.distance.first.unit,
            text: m.formatDistance(len));
      case PdfMeasurementKind.arc:
        if (m == null || pts == null || pts.length < 3) return null;
        final metrics = pdfArcMetrics(pts[0], pts[1], pts[2]);
        final len = metrics?.length ?? pdfPolylineLength(pts);
        return PdfMeasurementResult(
            kind: kind,
            value: m.realDistance(len),
            unit: m.distance.first.unit,
            text: m.formatDistance(len));
      case PdfMeasurementKind.area:
        if (m == null || pts == null || pts.length < 3) return null;
        final pointArea = pdfShoelaceArea(pts);
        return PdfMeasurementResult(
            kind: kind,
            value: m.realArea(pointArea),
            unit: m.area.first.unit,
            text: m.formatArea(pointArea));
      case PdfMeasurementKind.areaCutout:
        if (m == null || pts == null || pts.length < 3) return null;
        final pointArea = pdfNetPolygonArea(pts, t?.holes ?? const []);
        return PdfMeasurementResult(
            kind: kind,
            value: m.realArea(pointArea),
            unit: m.area.first.unit,
            text: m.formatArea(pointArea));
      case PdfMeasurementKind.volume:
        if (m == null || pts == null || pts.length < 3) return null;
        final depth = t?.depth ?? 0;
        final pointArea = pdfShoelaceArea(pts);
        return PdfMeasurementResult(
            kind: kind,
            value: m.realArea(pointArea) * depth,
            unit: (m.volume?.first ?? m.area.first).unit,
            text: m.formatVolume(pointArea, depth));
      case PdfMeasurementKind.angle:
        if (pts == null || pts.length < 3) return null;
        final deg = pdfMeasurementAngle(pts);
        return PdfMeasurementResult(
            kind: kind,
            value: deg,
            unit: '°',
            text: m?.formatAngle(deg) ??
                const PdfNumberFormat(unit: '°', precision: 10).format(deg));
      case PdfMeasurementKind.slope:
        if (pts == null || pts.length < 2) return null;
        final deg = pdfSlopeDegrees(pts.first, pts.last);
        return PdfMeasurementResult(
            kind: kind,
            value: deg,
            unit: '°',
            text: m?.formatAngle(deg) ??
                const PdfNumberFormat(unit: '°', precision: 10).format(deg));
    }
  }

  /// The real-world measurement this annotation represents, formatted
  /// through its /Measure: a distance for /Line, a perimeter (the sum of
  /// the segment lengths) for /PolyLine, and a shoelace area for
  /// /Polygon - plus the takeoff kinds (count/volume/angle/arc/slope/net
  /// area) when a /Takeoff is present. Null without a /Measure or for
  /// other subtypes.
  String? get measurementText => measurementResult?.text;

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

  /// The free-text rich-content string (§12.7.3.4 `/RC`) - the XHTML that
  /// records per-run styling the flat /DA can't, written by
  /// `PdfEditor.addFreeTextRich`. Null when absent (plain free text or a
  /// non-free-text annotation). Parse it with
  /// `PdfEditor.parseFreeTextRichContent`.
  String? get richContent {
    if (subtype != 'FreeText') return null;
    final rc = document.cos.resolve(dict['RC']);
    return rc is CosString ? rc.text : null;
  }

  /// The complete style of a free-text annotation, parsed from /DA, /C,
  /// and /BS - everything needed to regenerate its appearance at a new
  /// size. Null for other subtypes or when /DA has no usable `Tf`.
  ///
  /// Mapping: text color is /DA's `rg` (or `g`) operator; the background
  /// is /C (per §12.5.6.6 - but a /C that *equals* the text color is
  /// treated as a legacy text-color mirror, not a background); border
  /// width is /BS /W (0 when absent - the /Border default of 1 would
  /// conjure borders most viewers never drew); border color is /DA's
  /// `RG` operator, falling back to the text color when /BS declares a
  /// width without one.
  PdfFreeTextStyle? get freeTextStyle {
    if (subtype != 'FreeText') return null;
    final da = defaultAppearance;
    final tf = da == null ? null : _daTfRe.firstMatch(da);
    final size = double.tryParse(tf?.group(2) ?? '');
    if (tf == null || size == null) return null;

    int? lastColor(String op) {
      final m = (op == 'RG' ? _daUpperRgRe : _daRgRe).allMatches(da!).lastOrNull;
      if (m == null) return null;
      int byte(String s) =>
          ((double.tryParse(s) ?? 0).clamp(0.0, 1.0) * 255).round();
      return (byte(m.group(1)!) << 16) |
          (byte(m.group(2)!) << 8) |
          byte(m.group(3)!);
    }

    int? gray() {
      final m = _daGrayRe.allMatches(da!).lastOrNull;
      if (m == null) return null;
      final v =
          ((double.tryParse(m.group(1)!) ?? 0).clamp(0.0, 1.0) * 255).round();
      return (v << 16) | (v << 8) | v;
    }

    final text = lastColor('rg') ?? gray() ?? 0x000000;
    final background = color;
    final width = borderWidth ?? 0;
    final q = document.cos.resolve(dict['Q']);
    final cos = document.cos;
    double? number(String key) {
      final v = cos.resolve(dict[key]);
      if (v is CosInteger) return v.value.toDouble();
      if (v is CosReal) return v.value;
      return null;
    }

    final underlineFlag = cos.resolve(dict[kPdfFreeTextUnderlineKey]);
    return PdfFreeTextStyle(
      fontName: tf.group(1)!,
      fontSize: size,
      color: text,
      fillColor: background != null && background != text ? background : null,
      borderColor: lastColor('RG') ?? (width > 0 ? text : null),
      borderWidth: width,
      alignment: PdfTextAlign.fromQuadding(q is CosInteger ? q.value : null),
      lineSpacing:
          number(kPdfFreeTextLineSpacingKey) ?? kPdfFreeTextDefaultLineSpacing,
      charSpacing: number(kPdfFreeTextCharSpacingKey) ?? 0,
      horizontalScale:
          number(kPdfFreeTextHScaleKey) ?? kPdfFreeTextDefaultHorizontalScale,
      underline: underlineFlag is CosBoolean && underlineFlag.value,
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
  /// among its /Resources /ExtGState entries - where [PdfEditor]-authored
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

// /DA parsing patterns, compiled once (these getters run per sidebar tile).
final RegExp _daTfRe = RegExp(r'/(\S+)\s+([\d.]+)\s+Tf');
final RegExp _daRgRe = RegExp(r'([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+rg\b');
final RegExp _daUpperRgRe = RegExp(r'([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+RG\b');
final RegExp _daGrayRe = RegExp(r'([\d.]+)\s+g\b');
final RegExp _pdfDateRe = RegExp(
    r"D:(\d{4})(\d{2})?(\d{2})?(\d{2})?(\d{2})?(\d{2})?(?:([+\-Z])(\d{2})?'?(\d{2})?)?");

/// Parses a PDF date string (§7.9.4, `D:YYYYMMDDHHmmSSOHH'mm'`) to a
/// [DateTime] in UTC, leniently: every field past the year is optional and
/// a missing or malformed string returns null. Shared by the annotation
/// timestamp getters; the same shape is produced by [pdfFormatDate].
DateTime? _parsePdfDate(String? value) {
  if (value == null) return null;
  final match = _pdfDateRe.firstMatch(value);
  if (match == null) return null;
  int part(int i, [int fallback = 0]) =>
      match.group(i) == null ? fallback : int.parse(match.group(i)!);
  var time =
      DateTime.utc(part(1), part(2, 1), part(3, 1), part(4), part(5), part(6));
  if (match.group(7) == '+' || match.group(7) == '-') {
    final offset = Duration(hours: part(8), minutes: part(9));
    time = match.group(7) == '+' ? time.subtract(offset) : time.add(offset);
  }
  return time;
}

/// Formats [time] as a PDF date string (§7.9.4) in UTC - the form the
/// comment editor stamps on /CreationDate and /M, round-tripping through
/// [_parsePdfDate] and parsing in other readers (Acrobat).
String pdfFormatDate(DateTime time) {
  final t = time.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return "D:${t.year.toString().padLeft(4, '0')}${two(t.month)}${two(t.day)}"
      "${two(t.hour)}${two(t.minute)}${two(t.second)}Z00'00'";
}

/// Dictionary keys where free-text styling that /DA and /Q cannot express
/// is persisted (line height, character spacing, horizontal glyph scaling,
/// whole-box underline). Non-standard PDF keys, written and read back only
/// by this package so a resize/edit can regenerate the same appearance.
const String kPdfFreeTextLineSpacingKey = 'LineSpacing';
const String kPdfFreeTextCharSpacingKey = 'CharSpacing';
const String kPdfFreeTextHScaleKey = 'HScale';
const String kPdfFreeTextUnderlineKey = 'TextUnderline';

/// The default free-text line-height multiplier (baseline-to-baseline
/// distance is `fontSize * lineSpacing`).
const double kPdfFreeTextDefaultLineSpacing = 1.2;

/// The default free-text horizontal glyph scaling, as a percentage.
const double kPdfFreeTextDefaultHorizontalScale = 100.0;

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
    this.alignment = PdfTextAlign.left,
    this.lineSpacing = kPdfFreeTextDefaultLineSpacing,
    this.charSpacing = 0,
    this.horizontalScale = kPdfFreeTextDefaultHorizontalScale,
    this.underline = false,
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

  /// How the lines are aligned inside the box (the /Q quadding). Defaults
  /// to [PdfTextAlign.left] when the annotation carries no /Q.
  final PdfTextAlign alignment;

  /// The line-height multiplier (baseline-to-baseline distance is
  /// `fontSize * lineSpacing`). Defaults to [kPdfFreeTextDefaultLineSpacing].
  final double lineSpacing;

  /// Extra spacing added after each glyph, in points (the Tc value).
  final double charSpacing;

  /// Horizontal glyph scaling as a percentage - 100 is the font's natural
  /// width (the Tz value).
  final double horizontalScale;

  /// Whether the whole box is drawn underlined.
  final bool underline;
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

  /// The field's current value - /V resolved up the /Parent chain
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

/// /JavaScript: the script is surfaced verbatim - there is deliberately no
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
