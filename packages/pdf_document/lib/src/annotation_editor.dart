part of 'editor.dart';

/// The drawn width of an ink segment at normalized [pressure] (0–1) for a
/// base [strokeWidth]: 0.4× when barely touching up to 1.6× at full
/// pressure, the base width at 0.5. Shared by [PdfAnnotationEditing.addInk]
/// appearances and live stroke previews so they look identical.
double pdfInkStrokeWidth(double strokeWidth, double pressure) =>
    strokeWidth * (0.4 + 1.2 * pressure.clamp(0.0, 1.0));

/// Cubic Bézier control points that smooth a captured polyline into a
/// Catmull-Rom spline through its points: `result[i]` is the `(c1, c2)`
/// pair for the segment `points[i] → points[i+1]`. Pointer events sample
/// a stroke once per frame, so a fast stroke leaves long straight
/// segments with visible corners; the spline rounds them while still
/// passing through every sample. Shared by [PdfAnnotationEditing.addInk]
/// appearances and the live stroke previews so committed ink matches
/// what was drawn.
List<((double, double), (double, double))> pdfInkCurveControls(
    List<(double, double)> points) {
  return [
    for (var i = 0; i < points.length - 1; i++)
      () {
        // neighbors clamp to the endpoints, the standard open-spline rule
        final (x0, y0) = points[i == 0 ? 0 : i - 1];
        final (x1, y1) = points[i];
        final (x2, y2) = points[i + 1];
        final (x3, y3) = points[math.min(i + 2, points.length - 1)];
        return (
          (x1 + (x2 - x0) / 6, y1 + (y2 - y0) / 6),
          (x2 - (x3 - x1) / 6, y2 - (y3 - y1) / 6),
        );
      }(),
  ];
}

/// The kind of measurement [PdfAnnotationEditing.addMeasurement] creates:
/// a /Line distance, a /PolyLine perimeter (sum of segment lengths), or a
/// /Polygon area (shoelace).
enum PdfMeasurementKind { distance, perimeter, area }

/// One styled run inside a rich free-text annotation.
///
/// A normal FreeText annotation has one `/DA` default appearance. Runs let
/// this package generate an appearance stream with several fonts, sizes, or
/// text colors inside the same annotation while keeping `/Contents` as the
/// plain concatenated text.
class PdfFreeTextRun {
  const PdfFreeTextRun(
    this.text, {
    this.font = PdfStandardFont.helvetica,
    this.fontSize = 12,
    this.color = 0x000000,
  });

  final String text;
  final PdfTextFont font;
  final double fontSize;
  final int color;
}

class _RichTextPiece {
  const _RichTextPiece(this.text, this.style);

  final String text;
  final PdfFreeTextRun style;

  bool sameStyle(PdfFreeTextRun other) =>
      style.font.resourceName == other.font.resourceName &&
      style.fontSize == other.fontSize &&
      style.color == other.color;
}

class _RichTextLine {
  const _RichTextLine(this.runs, this.width);

  final List<_RichTextPiece> runs;
  final double width;
}

/// Line ending styles (§12.5.6.7, Table 176) drawn at a /Line or
/// /PolyLine endpoint by [PdfEditor.addLine] / [PdfEditor.addPolyLine].
///
/// [pdfName] is the /LE name written to (and read back from) the
/// dictionary. The geometry of each shape is produced by the appearance
/// generator: closed shapes ([square], [circle], [diamond],
/// [closedArrow], [rClosedArrow]) are filled, the rest stroked; the
/// `r*` variants point the opposite way along the line.
enum PdfLineEnding {
  none('None'),
  square('Square'),
  circle('Circle'),
  diamond('Diamond'),
  openArrow('OpenArrow'),
  closedArrow('ClosedArrow'),
  butt('Butt'),
  rOpenArrow('ROpenArrow'),
  rClosedArrow('RClosedArrow'),
  slash('Slash');

  const PdfLineEnding(this.pdfName);

  final String pdfName;

  /// The matching ending for a /LE name, or [none] when unknown.
  static PdfLineEnding fromName(String name) => values.firstWhere(
        (ending) => ending.pdfName == name,
        orElse: () => none,
      );
}

/// The start/end line endings recorded on [annotation]'s /LE entry, or
/// null when it is not a /Line or /PolyLine. Each defaults to
/// [PdfLineEnding.none] when absent or unrecognized. Lets UI read the
/// current endings without an editor instance (mirrors
/// [pdfCanRestyleAnnotation]).
(PdfLineEnding, PdfLineEnding)? pdfLineEndings(PdfAnnotation annotation) {
  if (annotation.subtype != 'Line' && annotation.subtype != 'PolyLine') {
    return null;
  }
  final le = annotation.document.cos.resolve(annotation.dict['LE']);
  PdfLineEnding read(int index) {
    if (le is! CosArray || le.length <= index) return PdfLineEnding.none;
    final name = annotation.document.cos.resolve(le[index]);
    if (name is! CosName) return PdfLineEnding.none;
    return PdfLineEnding.fromName(name.value);
  }

  return (read(0), read(1));
}

/// Slices ink [strokes] with one stamp of a circular eraser swept from
/// [from] to [to] (a capsule of [radius]): every part of a stroke's
/// centerline within [radius] of that segment is removed, splitting
/// strokes where the eraser crosses them. [pressures] (the [PdfEditor]
/// addInk convention — one optional list per stroke) travel with their
/// points, interpolated at the cut boundaries. Returns the surviving
/// strokes, or null when the eraser touched nothing. Shared by
/// [PdfAnnotationEditing.sliceInk] and the editing overlay's live
/// preview so the preview matches the commit exactly.
({List<List<(double, double)>> strokes, List<List<double>?>? pressures})?
    pdfSliceInkStrokes(
  List<List<(double, double)>> strokes,
  List<List<double>?>? pressures,
  (double, double) from,
  (double, double) to,
  double radius,
) {
  // ends of a cut shorter than this are invisible crumbs — drop them
  const minFragment = 0.05;
  const epsT = 1e-6;
  final boundsLeft = math.min(from.$1, to.$1) - radius;
  final boundsRight = math.max(from.$1, to.$1) + radius;
  final boundsBottom = math.min(from.$2, to.$2) - radius;
  final boundsTop = math.max(from.$2, to.$2) + radius;

  var changed = false;
  final outStrokes = <List<(double, double)>>[];
  final outPressures = <List<double>?>[];
  void emit(List<(double, double)> stroke, List<double>? pressure) {
    outStrokes.add(stroke);
    outPressures.add(pressure);
  }

  for (var s = 0; s < strokes.length; s++) {
    final stroke = strokes[s];
    final pressure = pressures?[s];
    if (stroke.length == 1) {
      // a bare dot: gone if the eraser reaches it
      final (x, y) = stroke.single;
      if (_distanceToSegment(x, y, from, to) <= radius) {
        changed = true;
      } else {
        emit(stroke, pressure);
      }
      continue;
    }
    // at most one erased t-interval per segment (a capsule is convex)
    List<(double, double)?>? intervals;
    for (var i = 0; i + 1 < stroke.length; i++) {
      final interval = _capsuleInterval(
          stroke[i], stroke[i + 1], from, to, radius,
          boundsLeft: boundsLeft,
          boundsRight: boundsRight,
          boundsBottom: boundsBottom,
          boundsTop: boundsTop);
      if (interval == null) continue;
      (intervals ??= List.filled(stroke.length - 1, null))[i] = interval;
    }
    if (intervals == null) {
      emit(stroke, pressure);
      continue;
    }
    changed = true;
    var run = <(double, double)>[];
    var runP = pressure == null ? null : <double>[];
    void endRun() {
      if (run.length >= 2) {
        var length = 0.0;
        for (var i = 0; i + 1 < run.length; i++) {
          final dx = run[i + 1].$1 - run[i].$1;
          final dy = run[i + 1].$2 - run[i].$2;
          length += math.sqrt(dx * dx + dy * dy);
        }
        if (length > minFragment) emit(run, runP);
      }
      run = [];
      runP = pressure == null ? null : <double>[];
    }

    (double, double) pointAt(int i, double t) => (
          stroke[i].$1 + (stroke[i + 1].$1 - stroke[i].$1) * t,
          stroke[i].$2 + (stroke[i + 1].$2 - stroke[i].$2) * t,
        );
    double pressureAt(int i, double t) =>
        pressure![i] + (pressure[i + 1] - pressure[i]) * t;

    final first = intervals[0];
    if (first == null || first.$1 > epsT) {
      run.add(stroke[0]);
      runP?.add(pressure![0]);
    }
    for (var i = 0; i + 1 < stroke.length; i++) {
      final interval = intervals[i];
      if (interval == null) {
        run.add(stroke[i + 1]);
        runP?.add(pressure![i + 1]);
        continue;
      }
      var (a, b) = interval;
      if (a < epsT) a = 0;
      if (b > 1 - epsT) b = 1;
      if (a > 0) {
        run.add(pointAt(i, a));
        runP?.add(pressureAt(i, a));
      }
      endRun();
      if (b < 1) {
        run.add(pointAt(i, b));
        runP?.add(pressureAt(i, b));
        run.add(stroke[i + 1]);
        runP?.add(pressure![i + 1]);
      }
    }
    endRun();
  }
  if (!changed) return null;
  return (
    strokes: outStrokes,
    pressures: pressures == null ? null : outPressures,
  );
}

/// The t-interval of the segment [a]–[b] that lies within [radius] of
/// the spine [c]–[d], or null when they don't overlap (or only touch
/// tangentially). The capsule is convex, so the inside parameters form
/// one interval; the distance along the segment is convex in t, found
/// by ternary search and refined by bisection.
(double, double)? _capsuleInterval(
  (double, double) a,
  (double, double) b,
  (double, double) c,
  (double, double) d,
  double radius, {
  required double boundsLeft,
  required double boundsRight,
  required double boundsBottom,
  required double boundsTop,
}) {
  if (math.max(a.$1, b.$1) < boundsLeft ||
      math.min(a.$1, b.$1) > boundsRight ||
      math.max(a.$2, b.$2) < boundsBottom ||
      math.min(a.$2, b.$2) > boundsTop) {
    return null;
  }
  double f(double t) => _distanceToSegment(
      a.$1 + (b.$1 - a.$1) * t, a.$2 + (b.$2 - a.$2) * t, c, d);
  final f0 = f(0), f1 = f(1);
  var lo = 0.0, hi = 1.0;
  for (var i = 0; i < 60; i++) {
    final m1 = lo + (hi - lo) / 3;
    final m2 = hi - (hi - lo) / 3;
    if (f(m1) <= f(m2)) {
      hi = m2;
    } else {
      lo = m1;
    }
  }
  final tMin = (lo + hi) / 2;
  if (math.min(f(tMin), math.min(f0, f1)) > radius) return null;
  double crossing(double inside, double outside) {
    for (var i = 0; i < 48; i++) {
      final mid = (inside + outside) / 2;
      if (f(mid) <= radius) {
        inside = mid;
      } else {
        outside = mid;
      }
    }
    return inside;
  }

  final t0 = f0 <= radius ? 0.0 : crossing(tMin, 0);
  final t1 = f1 <= radius ? 1.0 : crossing(tMin, 1);
  if (t1 - t0 < 1e-6) return null;
  return (t0, t1);
}

/// Distance from ([x], [y]) to the segment [a]–[b].
double _distanceToSegment(
    double x, double y, (double, double) a, (double, double) b) {
  final (ax, ay) = a;
  final (bx, by) = b;
  final dx = bx - ax, dy = by - ay;
  final lengthSquared = dx * dx + dy * dy;
  var px = ax, py = ay;
  if (lengthSquared > 0) {
    final t = (((x - ax) * dx + (y - ay) * dy) / lengthSquared).clamp(0.0, 1.0);
    px = ax + t * dx;
    py = ay + t * dy;
  }
  final ex = x - px, ey = y - py;
  return math.sqrt(ex * ex + ey * ey);
}

/// Whether [PdfAnnotationEditing.restyleAnnotation] can faithfully
/// regenerate [annotation]'s appearance — the gate UI style controls
/// should check before offering to restyle a selection.
///
/// True for the subtypes the editor authors (shapes, ink, free text,
/// line-family annotations, the four text markups, notes, stamps) when the dictionary carries
/// enough style to rebuild the artwork: shapes must not be cloudy
/// (/BE) or dashed (/BS /D), lines need /L or /Vertices, free text needs a standard-font /DA, ink
/// needs a usable /InkList, markups need axis-aligned /QuadPoints,
/// stamps need their caption in /Contents.
bool pdfCanRestyleAnnotation(PdfAnnotation annotation) {
  switch (annotation.subtype) {
    case 'Square' || 'Circle':
      if (annotation.normalAppearance == null) return false;
      // cloudy borders (/BE) still can't regenerate; dashed ones now do
      return annotation.dict['BE'] == null;
    case 'Line':
      return annotation.normalAppearance != null && annotation.line != null;
    case 'PolyLine':
      return annotation.normalAppearance != null &&
          (annotation.vertices?.length ?? 0) >= 2;
    case 'Polygon':
      return annotation.normalAppearance != null &&
          (annotation.vertices?.length ?? 0) >= 3;
    case 'FreeText':
      if (annotation.normalAppearance == null) return false;
      final style = annotation.freeTextStyle;
      return style != null &&
          PdfStandardFont.tryFromName(style.fontName) != null;
    case 'Ink':
      return annotation.inkList?.isNotEmpty ?? false;
    case 'Highlight' || 'Underline' || 'StrikeOut' || 'Squiggly':
      return _axisAlignedQuads(annotation) != null;
    case 'Text':
      return annotation.normalAppearance != null;
    case 'Stamp':
      return annotation.normalAppearance != null &&
          (annotation.contents?.isNotEmpty ?? false);
    default:
      return false;
  }
}

/// The /QuadPoints as one axis-aligned rect per quad, or null when they
/// are absent, malformed, or rotated (every corner must sit on the
/// quad's own bounds) — regenerating a markup repaints axis-aligned
/// rects, so rotated quads can't restyle faithfully.
List<PdfRect>? _axisAlignedQuads(PdfAnnotation annotation) {
  final cos = annotation.document.cos;
  final raw = cos.resolve(annotation.dict['QuadPoints']);
  if (raw is! CosArray || raw.length == 0 || raw.length % 8 != 0) return null;
  final values = <double>[];
  for (var i = 0; i < raw.length; i++) {
    final n = cos.resolve(raw[i]);
    if (n is CosInteger) {
      values.add(n.value.toDouble());
    } else if (n is CosReal) {
      values.add(n.value);
    } else {
      return null;
    }
  }
  const eps = 0.01;
  final quads = <PdfRect>[];
  for (var q = 0; q + 7 < values.length; q += 8) {
    final xs = [values[q], values[q + 2], values[q + 4], values[q + 6]];
    final ys = [values[q + 1], values[q + 3], values[q + 5], values[q + 7]];
    final minX = xs.reduce(math.min), maxX = xs.reduce(math.max);
    final minY = ys.reduce(math.min), maxY = ys.reduce(math.max);
    for (final x in xs) {
      if ((x - minX).abs() > eps && (x - maxX).abs() > eps) return null;
    }
    for (final y in ys) {
      if ((y - minY).abs() > eps && (y - maxY).abs() > eps) return null;
    }
    quads.add(PdfRect(minX, minY, maxX, maxY));
  }
  return quads;
}

/// A random version-4 UUID for an annotation's /NM. Random.secure() where
/// the platform provides it, falling back to a time-seeded generator
/// (identity needs uniqueness, not unpredictability).
String _generateAnnotationName() {
  math.Random random;
  try {
    random = math.Random.secure();
  } on UnsupportedError {
    random = math.Random(DateTime.now().microsecondsSinceEpoch);
  }
  final b = Uint8List(16);
  for (var i = 0; i < 16; i++) {
    b[i] = random.nextInt(256);
  }
  b[6] = (b[6] & 0x0F) | 0x40; // version 4
  b[8] = (b[8] & 0x3F) | 0x80; // RFC 4122 variant
  final hex =
      [for (final byte in b) byte.toRadixString(16).padLeft(2, '0')].join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Annotation authoring (§12.5): each method creates an annotation with a
/// generated appearance stream (/AP → /N), so the result displays the same
/// in this renderer and in other viewers.
///
/// Colors are `0xRRGGBB` ints; coordinates are PDF user space (origin at
/// the page's bottom-left, y up). Annotations are staged on the editor and
/// written by [PdfEditor.save].
///
/// Every creator takes an optional `name` — the /NM unique identifier
/// (§12.5.2, see [PdfAnnotation.name]). Omitted, a UUID is generated;
/// pass a name only to preserve identity through a rewrite or when
/// replaying a synced annotation.
extension PdfAnnotationEditing on PdfEditor {
  /// Adds a text-markup highlight over [quads] (one rect per marked word,
  /// line, or column slice).
  ///
  /// The appearance paints the quads in [color] with Multiply blending, the
  /// conventional highlighter look that keeps text underneath readable.
  void addHighlight(
    int pageIndex,
    List<PdfRect> quads, {
    int color = 0xFFD100,
    double opacity = 1,
    String? contents,
    String? author,
    String? name,
  }) =>
      _addTextMarkup('Highlight', pageIndex, quads, color, opacity, contents,
          author, name);

  /// Adds an underline beneath each quad in [quads].
  void addUnderline(int pageIndex, List<PdfRect> quads,
          {int color = 0x10A010,
          double opacity = 1,
          String? contents,
          String? author,
          String? name}) =>
      _addTextMarkup('Underline', pageIndex, quads, color, opacity, contents,
          author, name);

  /// Adds a strike-out through each quad in [quads].
  void addStrikeOut(int pageIndex, List<PdfRect> quads,
          {int color = 0xD02020,
          double opacity = 1,
          String? contents,
          String? author,
          String? name}) =>
      _addTextMarkup('StrikeOut', pageIndex, quads, color, opacity, contents,
          author, name);

  /// Adds a squiggly (jagged) underline beneath each quad in [quads].
  void addSquiggly(int pageIndex, List<PdfRect> quads,
          {int color = 0xD02020,
          double opacity = 1,
          String? contents,
          String? author,
          String? name}) =>
      _addTextMarkup(
          'Squiggly', pageIndex, quads, color, opacity, contents, author, name);

  void _addTextMarkup(
      String subtype,
      int pageIndex,
      List<PdfRect> quads,
      int color,
      double opacity,
      String? contents,
      String? author,
      String? name) {
    final rect = _boundsOf(quads);
    final (w, gs) = _markupContent(subtype, quads, color, opacity);
    _addAnnotation(
      pageIndex,
      _markupDict(subtype, rect, color, contents, author)
        ..['QuadPoints'] = _quadPoints(quads),
      _form(rect, w, resources: _resources(extGState: gs)),
      name: name,
    );
  }

  /// The text-markup appearance for [quads]: the content and the alpha
  /// ExtGState (always present for highlights, whose Multiply blending
  /// rides the same GS0). Shared by the markup creators and
  /// [restyleAnnotation] so a restyled markup re-renders exactly like a
  /// fresh one.
  (ContentWriter, CosDictionary?) _markupContent(
      String subtype, List<PdfRect> quads, int color, double opacity) {
    switch (subtype) {
      case 'Highlight':
        final w = ContentWriter()
          ..extGState('GS0')
          ..fillColor(color);
        for (final q in quads) {
          w.rect(q.left, q.bottom, q.width, q.height);
        }
        w.fill();
        return (w, _alphaState(opacity, multiply: true));
      case 'Squiggly':
        final w = ContentWriter()..strokeColor(color);
        final gs = _alphaState(opacity);
        if (gs != null) w.extGState('GS0');
        for (final q in quads) {
          final amplitude = q.height * 0.1;
          final period = q.height * 0.3;
          w.lineWidth((q.height * 0.05).clamp(0.5, 2.0));
          w.moveTo(q.left, q.bottom + amplitude);
          var up = true;
          for (var x = q.left + period / 2; x < q.right; x += period / 2) {
            w.lineTo(x, q.bottom + (up ? amplitude * 2 : 0));
            up = !up;
          }
          w.stroke();
        }
        return (w, gs);
      default: // 'Underline' || 'StrikeOut'
        final atHeight = subtype == 'Underline' ? 0.08 : 0.45;
        final w = ContentWriter();
        final gs = _alphaState(opacity);
        if (gs != null) w.extGState('GS0');
        w.strokeColor(color);
        for (final q in quads) {
          final y = q.bottom + q.height * atHeight;
          w
            ..lineWidth((q.height * 0.06).clamp(0.5, 3.0))
            ..moveTo(q.left, y)
            ..lineTo(q.right, y)
            ..stroke();
        }
        return (w, gs);
    }
  }

  /// Marks one or more regions for redaction (§12.5.6.23) by creating a
  /// `/Redact` annotation over [quads] (one rect per region). This is the
  /// MARK phase only — nothing is removed yet; call
  /// [PdfRedactionApply.applyRedactions] to BURN the marks irreversibly.
  ///
  /// [fillColor] (default black) is the colour the redacted area is painted
  /// on apply and is stored in /IC. [overlayText] is optional text drawn
  /// over the filled area on apply (/OverlayText), in [overlayTextColor] at
  /// [overlayFontSize].
  ///
  /// The marked-but-unapplied appearance is a translucent fill so the
  /// content underneath stays visible while reviewing; the editor draws a
  /// hatched preview on top.
  void addRedaction(
    int pageIndex,
    List<PdfRect> quads, {
    int fillColor = 0x000000,
    String? overlayText,
    int overlayTextColor = 0xFFFFFF,
    double overlayFontSize = 12,
    String? contents,
    String? author,
    String? name,
  }) {
    final rect = _boundsOf(quads);
    final gs = _alphaState(0.4);
    final w = ContentWriter();
    if (gs != null) w.extGState('GS0');
    w.fillColor(fillColor);
    for (final q in quads) {
      w.rect(q.left, q.bottom, q.width, q.height);
    }
    w.fill();

    final dict = _markupDict('Redact', rect, fillColor, contents, author)
      ..['QuadPoints'] = _quadPoints(quads)
      ..['IC'] = CosArray([
        for (final c in ContentWriter.rgbComponents(fillColor)) CosReal(c),
      ]);
    if (overlayText != null) {
      dict['OverlayText'] = CosString.fromText(overlayText);
      dict['Repeat'] = const CosBoolean(false);
      final rgb = ContentWriter.rgbComponents(overlayTextColor);
      dict['DA'] = CosString(Uint8List.fromList(
          latin1.encode('/Helv ${ContentWriter.fmt(overlayFontSize)} Tf '
              '${ContentWriter.fmt(rgb[0])} ${ContentWriter.fmt(rgb[1])} '
              '${ContentWriter.fmt(rgb[2])} rg')));
    }
    _addAnnotation(
      pageIndex,
      dict,
      _form(rect, w, resources: _resources(extGState: gs)),
      name: name,
    );
  }

  /// Adds a freehand ink annotation. Each stroke is a polyline of
  /// `(x, y)` points in page space.
  ///
  /// [pressures] optionally gives one normalized pressure (0–1) per point
  /// of the corresponding stroke (a null entry leaves that stroke at the
  /// uniform [strokeWidth]). Pressured strokes render with a varying
  /// width — [pdfInkStrokeWidth] per segment — the natural look for
  /// stylus (Apple Pencil) drawings. The /InkList always stores the
  /// centerline points; the variable width lives in the appearance
  /// stream, which conforming viewers prefer.
  void addInk(
    int pageIndex,
    List<List<(double, double)>> strokes, {
    int color = 0xD02020,
    double strokeWidth = 2,
    double opacity = 1,
    List<List<double>?>? pressures,
    String? contents,
    String? author,
    String? name,
  }) {
    if (strokes.isEmpty || strokes.any((s) => s.isEmpty)) {
      throw ArgumentError.value(strokes, 'strokes', 'must be non-empty');
    }
    if (pressures != null &&
        (pressures.length != strokes.length ||
            [
              for (var i = 0; i < strokes.length; i++)
                if (pressures[i] != null &&
                    pressures[i]!.length != strokes[i].length)
                  i
            ].isNotEmpty)) {
      throw ArgumentError.value(
          pressures, 'pressures', 'must parallel strokes point for point');
    }
    final (rect, w, gs) =
        _inkAppearance(strokes, pressures, color, strokeWidth, opacity);

    _addAnnotation(
      pageIndex,
      _markupDict('Ink', rect, color, contents, author)
        ..['BS'] = _borderStyle(strokeWidth)
        ..['InkList'] = _inkListArray(strokes),
      _form(rect, w, resources: _resources(extGState: gs)),
      name: name,
    );
  }

  /// The generated Ink appearance for [strokes]: the padded rect (the
  /// Bézier control hull plus half the widest pen width), the content,
  /// and the alpha ExtGState when [opacity] < 1. Shared by [addInk] and
  /// [sliceInk] so sliced ink re-renders exactly as it was drawn.
  (PdfRect, ContentWriter, CosDictionary?) _inkAppearance(
    List<List<(double, double)>> strokes,
    List<List<double>?>? pressures,
    int color,
    double strokeWidth,
    double opacity,
  ) {
    var maxWidth = strokeWidth;
    if (pressures != null) {
      for (final list in pressures) {
        for (final p in list ?? const <double>[]) {
          final width = pdfInkStrokeWidth(strokeWidth, p);
          if (width > maxWidth) maxWidth = width;
        }
      }
    }
    final controls = [
      for (final stroke in strokes) pdfInkCurveControls(stroke),
    ];
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    // a Bézier stays inside its control points' hull, so including the
    // controls makes the rect cover any spline overshoot past the samples
    for (var s = 0; s < strokes.length; s++) {
      for (final (x, y)
          in strokes[s].followedBy(controls[s].expand((c) => [c.$1, c.$2]))) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
    final pad = maxWidth / 2 + 1;
    final rect = PdfRect(minX - pad, minY - pad, maxX + pad, maxY + pad);

    final w = ContentWriter();
    final gs = _alphaState(opacity);
    if (gs != null) w.extGState('GS0');
    w
      ..strokeColor(color)
      ..lineWidth(strokeWidth)
      ..roundLines();
    for (var s = 0; s < strokes.length; s++) {
      final stroke = strokes[s];
      final pressure = pressures?[s];
      final (x0, y0) = stroke.first;
      if (pressure == null) {
        w.moveTo(x0, y0);
        if (stroke.length == 1) {
          // a dot: zero-length segment with round caps paints a circle
          w.lineTo(x0, y0);
        }
        for (var i = 0; i < stroke.length - 1; i++) {
          final ((c1x, c1y), (c2x, c2y)) = controls[s][i];
          final (x, y) = stroke[i + 1];
          w.curveTo(c1x, c1y, c2x, c2y, x, y);
        }
        w.stroke();
        continue;
      }
      if (stroke.length == 1) {
        w
          ..lineWidth(pdfInkStrokeWidth(strokeWidth, pressure.first))
          ..moveTo(x0, y0)
          ..lineTo(x0, y0)
          ..stroke();
        continue;
      }
      // one stroked spline segment per point pair, each at its own width;
      // the round caps and joins hide the seams
      for (var i = 0; i < stroke.length - 1; i++) {
        final (xa, ya) = stroke[i];
        final ((c1x, c1y), (c2x, c2y)) = controls[s][i];
        final (xb, yb) = stroke[i + 1];
        w
          ..lineWidth(pdfInkStrokeWidth(
              strokeWidth, (pressure[i] + pressure[i + 1]) / 2))
          ..moveTo(xa, ya)
          ..curveTo(c1x, c1y, c2x, c2y, xb, yb)
          ..stroke();
      }
    }
    return (rect, w, gs);
  }

  CosArray _inkListArray(List<List<(double, double)>> strokes) => CosArray([
        for (final stroke in strokes)
          CosArray([
            for (final (x, y) in stroke) ...[CosReal(x), CosReal(y)],
          ]),
      ]);

  /// Erases the parts of an Ink [annotation] within [radius] page units
  /// of the eraser's swept [path] — the PSPDFKit-style circle eraser.
  /// Strokes split where the circle crosses them; /InkList, /Rect, and
  /// the appearance are rewritten in place (same object numbers), so
  /// the annotation keeps its identity, author, and contents. When the
  /// appearance is one we generated with pressure-variable widths, the
  /// pressures are recovered from its per-segment `w` operators and
  /// survive the cut. An annotation whose strokes are erased entirely
  /// is removed.
  ///
  /// Returns whether anything changed; false for non-Ink annotations
  /// and ones without a usable /InkList (those can only be deleted
  /// whole).
  bool sliceInk(int pageIndex, PdfAnnotation annotation,
      List<(double, double)> path, double radius) {
    if (annotation.subtype != 'Ink' || path.isEmpty || radius <= 0) {
      return false;
    }
    var strokes = annotation.inkList;
    if (strokes == null || strokes.isEmpty) return false;
    final form = annotation.normalAppearance;
    final strokeWidth = annotation.borderWidth ?? 1;
    var pressures =
        form == null ? null : _recoverInkPressures(form, strokes, strokeWidth);
    final capsules = path.length == 1
        ? [(path[0], path[0])]
        : [for (var i = 0; i + 1 < path.length; i++) (path[i], path[i + 1])];
    var changed = false;
    for (final (from, to) in capsules) {
      final sliced = pdfSliceInkStrokes(strokes!, pressures, from, to, radius);
      if (sliced == null) continue;
      strokes = sliced.strokes;
      pressures = sliced.pressures;
      changed = true;
      if (strokes.isEmpty) break;
    }
    if (!changed) return false;
    if (strokes!.isEmpty) {
      removeAnnotation(pageIndex, annotation);
      return true;
    }
    final opacity = form == null ? 1.0 : _appearanceOpacity(form);
    final color = annotation.color ?? 0x000000;
    final (rect, w, gs) =
        _inkAppearance(strokes, pressures, color, strokeWidth, opacity);
    final dict = annotation.dict;
    dict['Rect'] = _rectArray(rect);
    dict['InkList'] = _inkListArray(strokes);
    if (form != null) {
      _replaceAppearance(dict, form, rect, w,
          resources: _resources(extGState: gs));
    } else {
      dict['AP'] = CosDictionary({
        'N': _updater
            .addObject(_form(rect, w, resources: _resources(extGState: gs))),
      });
    }
    _markAnnotationChanged(pageIndex, dict);
    return true;
  }

  /// Per-point pressures recovered from an Ink appearance this editor
  /// generated: pressured strokes carry one `w` per drawn segment (see
  /// [_inkAppearance]), so inverting [pdfInkStrokeWidth] gives segment
  /// pressures, averaged back onto the points. Returns null — uniform
  /// width — whenever the stream doesn't match that exact shape
  /// (foreign appearances, plain uniform ink).
  List<List<double>?>? _recoverInkPressures(CosStream form,
      List<List<(double, double)>> strokes, double strokeWidth) {
    if (strokeWidth <= 0) return null;
    final List<ContentOperation> ops;
    try {
      ops = ContentStreamParser.parse(document.cos.decodeStreamData(form));
    } catch (_) {
      return null;
    }
    // anything beyond stroked paths and line state means the appearance
    // isn't one of ours — don't guess
    const allowed = {
      'q', 'Q', 'gs', 'cm', 'w', 'J', 'j', 'M', 'd', //
      'RG', 'rg', 'S', 's', 'n', 'm', 'l', 'c', 'v', 'y',
    };
    var width = 1.0;
    final widths = <double>[];
    for (final op in ops) {
      if (!allowed.contains(op.operator)) return null;
      switch (op.operator) {
        case 'w':
          if (op.operands.length != 1) return null;
          final value = op.operands.single;
          width = switch (value) {
            CosInteger(:final value) => value.toDouble(),
            CosReal(:final value) => value,
            _ => double.nan,
          };
          if (width.isNaN) return null;
        case 'l' || 'c' || 'v' || 'y':
          widths.add(width);
      }
    }
    var total = 0;
    for (final stroke in strokes) {
      total += math.max(1, stroke.length - 1);
    }
    if (widths.length != total) return null;
    var k = 0;
    var anyPressure = false;
    final result = <List<double>?>[];
    for (final stroke in strokes) {
      final segments = math.max(1, stroke.length - 1);
      final ws = widths.sublist(k, k + segments);
      k += segments;
      if (ws.every((w) => (w - strokeWidth).abs() < 1e-3)) {
        result.add(null);
        continue;
      }
      anyPressure = true;
      final perSegment = [
        for (final w in ws) ((w / strokeWidth - 0.4) / 1.2).clamp(0.0, 1.0),
      ];
      if (stroke.length == 1) {
        result.add([perSegment.single]);
        continue;
      }
      result.add([
        perSegment.first,
        for (var i = 1; i + 1 < stroke.length; i++)
          (perSegment[i - 1] + perSegment[i]) / 2,
        perSegment.last,
      ]);
    }
    return anyPressure ? result : null;
  }

  /// Adds a rectangle annotation. At least one of [strokeColor] and
  /// [fillColor] must be given.
  void addSquare(
    int pageIndex,
    PdfRect rect, {
    int? strokeColor = 0xD02020,
    double strokeWidth = 2,
    int? fillColor,
    double opacity = 1,
    List<double>? dashPattern,
    String? contents,
    String? author,
    String? name,
  }) =>
      _addShape('Square', pageIndex, rect, strokeColor, strokeWidth, fillColor,
          opacity, contents, author, name, dashPattern);

  /// Adds an ellipse annotation inscribed in [rect]. At least one of
  /// [strokeColor] and [fillColor] must be given.
  void addCircle(
    int pageIndex,
    PdfRect rect, {
    int? strokeColor = 0xD02020,
    double strokeWidth = 2,
    int? fillColor,
    double opacity = 1,
    List<double>? dashPattern,
    String? contents,
    String? author,
    String? name,
  }) =>
      _addShape('Circle', pageIndex, rect, strokeColor, strokeWidth, fillColor,
          opacity, contents, author, name, dashPattern);

  /// Adds a straight /Line annotation from [start] to [end]. Set
  /// [endEnding] to [PdfLineEnding.closedArrow] for a standard arrow.
  void addLine(
    int pageIndex,
    (double, double) start,
    (double, double) end, {
    int strokeColor = 0xD02020,
    double strokeWidth = 2,
    double opacity = 1,
    List<double>? dashPattern,
    PdfLineEnding startEnding = PdfLineEnding.none,
    PdfLineEnding endEnding = PdfLineEnding.none,
    String? contents,
    String? author,
    String? name,
  }) {
    if (start == end) {
      throw ArgumentError.value(end, 'end', 'must differ from start');
    }
    final dashed = dashPattern != null && dashPattern.isNotEmpty;
    final points = [start, end];
    final endingPoints = <(double, double)>[
      ..._endingExtent(startEnding, start, end, strokeWidth),
      ..._endingExtent(endEnding, end, start, strokeWidth),
    ];
    final rect = _pointBounds(
        [...points, ...endingPoints], strokeWidth + (dashed ? strokeWidth : 0));
    final gs = _alphaState(opacity);
    final w = _lineContent(points,
        strokeColor: strokeColor,
        strokeWidth: strokeWidth,
        dashPattern: dashPattern,
        closed: false,
        fillColor: null,
        startEnding: startEnding,
        endEnding: endEnding,
        hasAlpha: gs != null);
    final dict = _markupDict('Line', rect, strokeColor, contents, author)
      ..['L'] = CosArray([
        CosReal(start.$1),
        CosReal(start.$2),
        CosReal(end.$1),
        CosReal(end.$2),
      ])
      ..['LE'] = CosArray([
        CosName(startEnding.pdfName),
        CosName(endEnding.pdfName),
      ])
      ..['BS'] = _borderStyle(strokeWidth, dashPattern: dashPattern);
    _addAnnotation(
        pageIndex, dict, _form(rect, w, resources: _resources(extGState: gs)),
        name: name);
  }

  /// Adds a /PolyLine annotation through [vertices]. Per §12.5.6.7 a
  /// /PolyLine may carry /LE endings on its first and last vertex —
  /// [startEnding] is drawn at `vertices.first` (pointing back toward
  /// `vertices[1]`), [endEnding] at `vertices.last`.
  void addPolyLine(
    int pageIndex,
    List<(double, double)> vertices, {
    int strokeColor = 0xD02020,
    double strokeWidth = 2,
    double opacity = 1,
    List<double>? dashPattern,
    PdfLineEnding startEnding = PdfLineEnding.none,
    PdfLineEnding endEnding = PdfLineEnding.none,
    String? contents,
    String? author,
    String? name,
  }) {
    if (vertices.length < 2) {
      throw ArgumentError.value(vertices, 'vertices', 'must have 2+ points');
    }
    final endingPoints = <(double, double)>[
      ..._endingExtent(startEnding, vertices.first, vertices[1], strokeWidth),
      ..._endingExtent(
          endEnding, vertices.last, vertices[vertices.length - 2], strokeWidth),
    ];
    final rect = _pointBounds([...vertices, ...endingPoints], strokeWidth);
    final gs = _alphaState(opacity);
    final w = _lineContent(vertices,
        strokeColor: strokeColor,
        strokeWidth: strokeWidth,
        dashPattern: dashPattern,
        closed: false,
        fillColor: null,
        startEnding: startEnding,
        endEnding: endEnding,
        hasAlpha: gs != null);
    final dict = _markupDict('PolyLine', rect, strokeColor, contents, author)
      ..['Vertices'] = _pointArray(vertices)
      ..['LE'] = CosArray([
        CosName(startEnding.pdfName),
        CosName(endEnding.pdfName),
      ])
      ..['BS'] = _borderStyle(strokeWidth, dashPattern: dashPattern);
    _addAnnotation(
        pageIndex, dict, _form(rect, w, resources: _resources(extGState: gs)),
        name: name);
  }

  /// Adds a /Polygon annotation through [vertices].
  void addPolygon(
    int pageIndex,
    List<(double, double)> vertices, {
    int strokeColor = 0xD02020,
    double strokeWidth = 2,
    int? fillColor,
    double opacity = 1,
    List<double>? dashPattern,
    String? contents,
    String? author,
    String? name,
  }) {
    if (vertices.length < 3) {
      throw ArgumentError.value(vertices, 'vertices', 'must have 3+ points');
    }
    final rect = _pointBounds(vertices, strokeWidth);
    final gs = _alphaState(opacity);
    final w = _lineContent(vertices,
        strokeColor: strokeColor,
        strokeWidth: strokeWidth,
        dashPattern: dashPattern,
        closed: true,
        fillColor: fillColor,
        hasAlpha: gs != null);
    final dict = _markupDict('Polygon', rect, strokeColor, contents, author)
      ..['Vertices'] = _pointArray(vertices)
      ..['BS'] = _borderStyle(strokeWidth, dashPattern: dashPattern);
    if (fillColor != null) dict['IC'] = _colorComponents(fillColor);
    _addAnnotation(
        pageIndex, dict, _form(rect, w, resources: _resources(extGState: gs)),
        name: name);
  }

  /// The document-default measurement scale, or null until
  /// [setMeasurementScale] is called.
  PdfMeasure? get measurementScale => _defaultMeasure;

  /// Sets the document-default measurement scale (§12.9) used by
  /// [addMeasurement] when no per-annotation override is given.
  ///
  /// [pageUnitsPerPoint] converts a PDF point to a "page unit" (e.g. an
  /// inch printed at 72 dpi is `1 / 72`), and [realUnitsPerPageUnit] is
  /// the drawing's scale (`20` for `1 in = 20 ft`). Their product is the
  /// real-world units per point baked into the /Measure /X array; values
  /// display in [realUnitLabel] (and [areaUnitLabel] for areas, defaulting
  /// to `realUnitLabel²`).
  PdfMeasure setMeasurementScale(
    double pageUnitsPerPoint,
    String realUnitLabel,
    double realUnitsPerPageUnit, {
    String? areaUnitLabel,
    int precision = 100,
    String? ratioLabel,
  }) {
    final measure = PdfMeasure.scale(
      unitsPerPoint: pageUnitsPerPoint * realUnitsPerPageUnit,
      unitLabel: realUnitLabel,
      areaUnitLabel: areaUnitLabel,
      precision: precision,
      ratioLabel: ratioLabel,
    );
    _defaultMeasure = measure;
    return measure;
  }

  /// Adds a measurement annotation: a /Line ([PdfMeasurementKind.distance]),
  /// /PolyLine ([PdfMeasurementKind.perimeter]), or /Polygon
  /// ([PdfMeasurementKind.area]) carrying a /Measure dictionary (§12.9).
  ///
  /// The measured value (distance = `|segment| × scaleFactor`, perimeter =
  /// `Σ segments × scaleFactor`, area = `shoelace × scaleFactor²`) is
  /// formatted through [measure] (or the document default set by
  /// [setMeasurementScale]), stamped into /Contents, and drawn as a
  /// caption at the segment midpoint / polygon centroid. Throws a
  /// [StateError] when no scale is available.
  void addMeasurement(
    int pageIndex,
    PdfMeasurementKind kind,
    List<(double, double)> points, {
    PdfMeasure? measure,
    int strokeColor = 0xD02020,
    double strokeWidth = 2,
    int? fillColor,
    double opacity = 1,
    List<double>? dashPattern,
    int? captionColor,
    String? author,
    String? name,
  }) {
    final m = measure ?? _defaultMeasure;
    if (m == null) {
      throw StateError('no measurement scale set — call setMeasurementScale '
          'or pass a measure');
    }
    final minPoints = kind == PdfMeasurementKind.distance ? 2 : 3;
    if (points.length <
        (kind == PdfMeasurementKind.perimeter ? 2 : minPoints)) {
      throw ArgumentError.value(points, 'points',
          'needs ${kind == PdfMeasurementKind.area ? 3 : 2}+ points');
    }

    final closed = kind == PdfMeasurementKind.area;
    final (caption, anchor) = _measurementCaption(kind, points, m);

    // the geometry appearance, then the caption text drawn over its anchor
    final gs = _alphaState(opacity);
    final content = _lineContent(points,
        strokeColor: strokeColor,
        strokeWidth: strokeWidth,
        dashPattern: dashPattern,
        closed: closed,
        fillColor: closed ? fillColor : null,
        hasAlpha: gs != null);

    const captionSize = 10.0;
    final labelColor = captionColor ?? strokeColor;
    final textWidth = measureHelvetica(caption, captionSize);
    const padX = 3.0, padY = 2.0;
    final boxLeft = anchor.$1 - textWidth / 2 - padX;
    final boxBottom = anchor.$2 - captionSize / 2 - padY;
    final boxWidth = textWidth + 2 * padX;
    final boxHeight = captionSize + 2 * padY;
    content
      ..fillColor(0xFFFFFF)
      ..rect(boxLeft, boxBottom, boxWidth, boxHeight)
      ..fill()
      ..beginText()
      ..font('Helv', captionSize)
      ..fillColor(labelColor)
      ..textAt(anchor.$1 - textWidth / 2,
          anchor.$2 - captionSize * 0.36) // rough cap-height centering
      ..showText(caption)
      ..endText();

    // the rect must cover both the geometry and the caption box
    final geomRect = _pointBounds(points, strokeWidth);
    final rect = PdfRect(
      math.min(geomRect.left, boxLeft),
      math.min(geomRect.bottom, boxBottom),
      math.max(geomRect.right, boxLeft + boxWidth),
      math.max(geomRect.top, boxBottom + boxHeight),
    );

    final subtype = switch (kind) {
      PdfMeasurementKind.distance => 'Line',
      PdfMeasurementKind.perimeter => 'PolyLine',
      PdfMeasurementKind.area => 'Polygon',
    };
    final intent = switch (kind) {
      PdfMeasurementKind.distance => 'LineDimension',
      PdfMeasurementKind.perimeter => 'PolyLineDimension',
      PdfMeasurementKind.area => 'PolygonDimension',
    };
    final dict = _markupDict(subtype, rect, strokeColor, caption, author)
      ..['BS'] = _borderStyle(strokeWidth, dashPattern: dashPattern)
      ..['IT'] = CosName(intent)
      ..['Measure'] = m.toCosDictionary();
    if (kind == PdfMeasurementKind.distance) {
      dict['L'] = CosArray([
        CosReal(points.first.$1),
        CosReal(points.first.$2),
        CosReal(points.last.$1),
        CosReal(points.last.$2),
      ]);
      dict['LE'] = CosArray([const CosName('None'), const CosName('None')]);
    } else {
      dict['Vertices'] = _pointArray(points);
    }
    if (closed && fillColor != null) dict['IC'] = _colorComponents(fillColor);

    _addAnnotation(
      pageIndex,
      dict,
      _form(rect, content,
          resources: _resources(extGState: gs, font: _helvetica())),
      name: name,
    );
  }

  /// The caption string and its page-space anchor (segment midpoint for a
  /// distance, the path/polygon centroid otherwise) for a measurement.
  (String, (double, double)) _measurementCaption(
      PdfMeasurementKind kind, List<(double, double)> points, PdfMeasure m) {
    switch (kind) {
      case PdfMeasurementKind.distance:
        final a = points.first, b = points.last;
        final dx = b.$1 - a.$1, dy = b.$2 - a.$2;
        final caption = m.formatDistance(math.sqrt(dx * dx + dy * dy));
        return (caption, ((a.$1 + b.$1) / 2, (a.$2 + b.$2) / 2));
      case PdfMeasurementKind.perimeter:
        var total = 0.0;
        for (var i = 0; i + 1 < points.length; i++) {
          final dx = points[i + 1].$1 - points[i].$1;
          final dy = points[i + 1].$2 - points[i].$2;
          total += math.sqrt(dx * dx + dy * dy);
        }
        return (m.formatDistance(total), _centroid(points));
      case PdfMeasurementKind.area:
        final caption = m.formatArea(pdfShoelaceArea(points));
        return (caption, _centroid(points));
    }
  }

  (double, double) _centroid(List<(double, double)> points) {
    var sx = 0.0, sy = 0.0;
    for (final (x, y) in points) {
      sx += x;
      sy += y;
    }
    return (sx / points.length, sy / points.length);
  }

  /// Adds a free-text annotation: [text] rendered directly on the page in
  /// [font] (12pt Helvetica by default), wrapped to fit [rect] and
  /// clipped to it.
  ///
  /// The style round-trips through the dictionary so the appearance can
  /// be regenerated (resize, text edits): text color and [borderColor]
  /// live in /DA (`rg` / `RG`), [fillColor] is /C (the free-text
  /// background per §12.5.6.6), [borderWidth] is /BS /W.
  void addFreeText(
    int pageIndex,
    PdfRect rect,
    String text, {
    double fontSize = 12,
    PdfTextFont font = PdfStandardFont.helvetica,
    PdfTextDirection textDirection = PdfTextDirection.auto,
    int color = 0x000000,
    int? fillColor,
    int? borderColor,
    double borderWidth = 1,
    String? author,
    String? name,
  }) {
    // The font accumulates which glyphs the appearance shows (so an
    // embedded font's /W and /ToUnicode cover exactly them); start fresh.
    if (font is PdfEmbeddedFont) font.resetUsage();
    final w = _freeTextContent(rect, text,
        fontSize: fontSize,
        font: font,
        textDirection: textDirection,
        color: color,
        fillColor: fillColor,
        borderColor: borderColor,
        borderWidth: borderWidth);

    String rgb(int c) =>
        ContentWriter.rgbComponents(c).map(ContentWriter.fmt).join(' ');
    final da = '${rgb(color)} rg '
        '${borderColor != null ? '${rgb(borderColor)} RG ' : ''}'
        '/${font.resourceName} ${ContentWriter.fmt(fontSize)} Tf';
    final dict = _markupDict('FreeText', rect, fillColor ?? color, text, author)
      ..['DA'] = CosString.fromText(da)
      ..['Q'] = CosInteger(
          textDirection.resolve(text) == PdfTextDirection.rtl ? 2 : 0);
    if (borderColor != null && borderWidth > 0) {
      dict['BS'] = _borderStyle(borderWidth);
    }
    final fontResource = font is PdfEmbeddedFont
        ? font.buildResource(_updater.addObject)
        : _standardFont(font as PdfStandardFont);
    _addAnnotation(
      pageIndex,
      dict,
      _form(rect, w, resources: _resources(font: fontResource)),
      name: name,
    );
  }

  /// Adds a rich free-text annotation whose appearance can switch font,
  /// size, and text color between [runs].
  ///
  /// `/Contents` remains the plain concatenation of the run text so comment
  /// lists, sync payloads, and search-friendly metadata still see ordinary
  /// text. `/DA` records the first run as the fallback style for other
  /// viewers; the generated `/AP /N` appearance carries the per-run styling.
  void addFreeTextRich(
    int pageIndex,
    PdfRect rect,
    List<PdfFreeTextRun> runs, {
    PdfTextDirection textDirection = PdfTextDirection.auto,
    int? fillColor,
    int? borderColor,
    double borderWidth = 1,
    String? author,
    String? name,
  }) {
    final nonEmpty = [
      for (final run in runs)
        if (run.text.isNotEmpty) run
    ];
    if (nonEmpty.isEmpty) return;
    final text = nonEmpty.map((run) => run.text).join();
    for (final font in _richFonts(nonEmpty)) {
      if (font is PdfEmbeddedFont) font.resetUsage();
    }
    final w = _freeTextRichContent(rect, nonEmpty,
        textDirection: textDirection,
        fillColor: fillColor,
        borderColor: borderColor,
        borderWidth: borderWidth);

    final first = nonEmpty.first;
    String rgb(int c) =>
        ContentWriter.rgbComponents(c).map(ContentWriter.fmt).join(' ');
    final da = '${rgb(first.color)} rg '
        '${borderColor != null ? '${rgb(borderColor)} RG ' : ''}'
        '/${first.font.resourceName} ${ContentWriter.fmt(first.fontSize)} Tf';
    final dict =
        _markupDict('FreeText', rect, fillColor ?? first.color, text, author)
          ..['DA'] = CosString.fromText(da)
          ..['Q'] = CosInteger(
              textDirection.resolve(text) == PdfTextDirection.rtl ? 2 : 0);
    if (borderColor != null && borderWidth > 0) {
      dict['BS'] = _borderStyle(borderWidth);
    }
    _addAnnotation(
      pageIndex,
      dict,
      _form(rect, w, resources: _resources(font: _richFontResources(nonEmpty))),
      name: name,
    );
  }

  /// The free-text appearance content: optional background fill and
  /// border, then [text] wrapped into [rect] and clipped to it.
  ContentWriter _freeTextContent(
    PdfRect rect,
    String text, {
    required double fontSize,
    required PdfTextFont font,
    required PdfTextDirection textDirection,
    required int color,
    required int? fillColor,
    required int? borderColor,
    required double borderWidth,
  }) {
    const pad = 3.0;
    final w = ContentWriter();
    if (fillColor != null) {
      w
        ..fillColor(fillColor)
        ..rect(rect.left, rect.bottom, rect.width, rect.height)
        ..fill();
    }
    if (borderColor != null && borderWidth > 0) {
      w
        ..strokeColor(borderColor)
        ..lineWidth(borderWidth)
        ..rect(rect.left + borderWidth / 2, rect.bottom + borderWidth / 2,
            rect.width - borderWidth, rect.height - borderWidth)
        ..stroke();
    }
    w
      ..save()
      ..rect(rect.left, rect.bottom, rect.width, rect.height)
      ..clip()
      ..beginText()
      ..font(font.resourceName, fontSize)
      ..leading(fontSize * 1.2)
      ..fillColor(color);
    // first baseline sits one ascent below the top padding
    final firstY = rect.top - pad - fontSize * font.ascent / 1000;
    final lines = _wrap(text, fontSize, rect.width - 2 * pad, font: font);
    final resolvedDirection = textDirection.resolve(text);
    var prevX = 0.0;
    var prevY = 0.0;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final width = font.measure(line, fontSize);
      final x = resolvedDirection == PdfTextDirection.rtl
          ? rect.right - pad - width
          : rect.left + pad;
      final y = firstY - i * fontSize * 1.2;
      w.textAt(x - prevX, y - prevY);
      final visual = pdfVisualText(line, resolvedDirection);
      if (font is PdfEmbeddedFont) {
        w.showGlyphHex(font.encodeHex(visual));
      } else {
        w.showText(visual);
      }
      prevX = x;
      prevY = y;
    }
    w
      ..endText()
      ..restore();
    return w;
  }

  ContentWriter _freeTextRichContent(
    PdfRect rect,
    List<PdfFreeTextRun> runs, {
    required PdfTextDirection textDirection,
    required int? fillColor,
    required int? borderColor,
    required double borderWidth,
  }) {
    const pad = 3.0;
    final w = ContentWriter();
    if (fillColor != null) {
      w
        ..fillColor(fillColor)
        ..rect(rect.left, rect.bottom, rect.width, rect.height)
        ..fill();
    }
    if (borderColor != null && borderWidth > 0) {
      w
        ..strokeColor(borderColor)
        ..lineWidth(borderWidth)
        ..rect(rect.left + borderWidth / 2, rect.bottom + borderWidth / 2,
            rect.width - borderWidth, rect.height - borderWidth)
        ..stroke();
    }
    final plain = runs.map((run) => run.text).join();
    final resolvedDirection = textDirection.resolve(plain);
    final lines = _wrapRich(runs, rect.width - 2 * pad);
    var top = rect.top - pad;
    var prevX = 0.0;
    var prevY = 0.0;
    w
      ..save()
      ..rect(rect.left, rect.bottom, rect.width, rect.height)
      ..clip()
      ..beginText();
    for (final line in lines) {
      if (line.runs.isEmpty) {
        top -= 12 * 1.2;
        continue;
      }
      final ascent = line.runs.fold<double>(
          0,
          (max, run) =>
              math.max(max, run.style.fontSize * run.style.font.ascent / 1000));
      final lineHeight = line.runs.fold<double>(
          0, (max, run) => math.max(max, run.style.fontSize * 1.2));
      var x = resolvedDirection == PdfTextDirection.rtl
          ? rect.right - pad - line.width
          : rect.left + pad;
      final y = top - ascent;
      final drawRuns = resolvedDirection == PdfTextDirection.rtl
          ? line.runs.reversed
          : line.runs;
      for (final run in drawRuns) {
        final style = run.style;
        final visual = pdfVisualText(run.text, resolvedDirection);
        final width = style.font.measure(visual, style.fontSize);
        w
          ..font(style.font.resourceName, style.fontSize)
          ..fillColor(style.color)
          ..textAt(x - prevX, y - prevY);
        if (style.font is PdfEmbeddedFont) {
          w.showGlyphHex((style.font as PdfEmbeddedFont).encodeHex(visual));
        } else {
          w.showText(visual);
        }
        prevX = x;
        prevY = y;
        x += width;
      }
      top -= lineHeight;
    }
    w
      ..endText()
      ..restore();
    return w;
  }

  Iterable<PdfTextFont> _richFonts(List<PdfFreeTextRun> runs) sync* {
    final seen = <String>{};
    for (final run in runs) {
      if (seen.add(run.font.resourceName)) yield run.font;
    }
  }

  CosDictionary _richFontResources(List<PdfFreeTextRun> runs) {
    final dict = CosDictionary();
    for (final font in _richFonts(runs)) {
      final resource = font is PdfEmbeddedFont
          ? font.buildResource(_updater.addObject)
          : _standardFont(font as PdfStandardFont);
      dict.entries.addAll(resource.entries);
    }
    return dict;
  }

  List<_RichTextLine> _wrapRich(List<PdfFreeTextRun> runs, double maxWidth) {
    final lines = <_RichTextLine>[];
    var current = <_RichTextPiece>[];
    var width = 0.0;

    void flushLine() {
      lines.add(_RichTextLine(current, width));
      current = <_RichTextPiece>[];
      width = 0;
    }

    void addText(PdfFreeTextRun style, String text) {
      if (text.isEmpty) return;
      if (current.isNotEmpty && current.last.sameStyle(style)) {
        current[current.length - 1] =
            _RichTextPiece(current.last.text + text, current.last.style);
      } else {
        current.add(_RichTextPiece(text, style));
      }
      width += style.font.measure(text, style.fontSize);
    }

    for (final run in runs) {
      for (final rune in run.text.runes) {
        if (rune == 0x0A) {
          flushLine();
          continue;
        }
        final text = String.fromCharCode(rune);
        final w = run.font.measure(text, run.fontSize);
        if (width > 0 && width + w > maxWidth) flushLine();
        addText(run, text);
      }
    }
    if (current.isNotEmpty || lines.isEmpty) flushLine();
    return lines;
  }

  /// Adds a sticky-note (/Text) annotation with its top-left corner at
  /// ([x], [y]). Viewers show [contents] in a popup when it is opened.
  void addNote(
    int pageIndex,
    double x,
    double y,
    String contents, {
    int color = 0xFFD100,
    String? author,
    String? name,
  }) {
    const size = 20.0;
    final rect = PdfRect(x, y - size, x + size, y);
    _addAnnotation(
      pageIndex,
      _markupDict('Text', rect, color, contents, author)
        ..['Name'] = const CosName('Comment'),
      _form(rect, _noteContent(rect, color)),
      name: name,
    );
  }

  /// The sticky-note sheet appearance, drawn inside [rect]. Shared by
  /// [addNote] and [restyleAnnotation].
  ContentWriter _noteContent(PdfRect rect, int color) {
    final x = rect.left, y = rect.top;
    final size = rect.height;
    final w = ContentWriter()
      // note sheet
      ..fillColor(color)
      ..strokeColor(0x404040)
      ..lineWidth(1)
      ..roundedRect(x + 1, y - size + 1, size - 2, size - 2, 2)
      ..fillAndStroke()
      // text lines on the sheet
      ..strokeColor(0x606060)
      ..lineWidth(1);
    for (var i = 0; i < 3; i++) {
      final lineY = y - 6 - i * 4;
      w
        ..moveTo(x + 4, lineY)
        ..lineTo(x + size - 4, lineY)
        ..stroke();
    }
    return w;
  }

  /// Adds a rubber-stamp annotation: [text] centered in bold inside a
  /// rounded border, sized to fit [rect].
  void addStamp(
    int pageIndex,
    PdfRect rect,
    String text, {
    int color = 0xC03030,
    double opacity = 1,
    String? author,
    String? name,
  }) {
    final (w, gs) = _stampContent(rect, text, color, opacity);
    _addAnnotation(
      pageIndex,
      _markupDict('Stamp', rect, color, text, author),
      _form(rect, w,
          resources: _resources(
              extGState: gs, font: _helvetica(bold: true, name: 'HelvB'))),
      name: name,
    );
  }

  /// The rubber-stamp appearance: [text] centered in bold inside a
  /// rounded border, sized to fit [rect]. Shared by [addStamp] and
  /// [restyleAnnotation].
  (ContentWriter, CosDictionary?) _stampContent(
      PdfRect rect, String text, int color, double opacity) {
    const borderWidth = 2.0;
    const pad = 6.0;
    var fontSize = (rect.height - 2 * pad) * 0.72;
    final available = rect.width - 2 * pad;
    final atUnit = measureHelvetica(text, 1, bold: true);
    if (atUnit > 0 && atUnit * fontSize > available) {
      fontSize = available / atUnit;
    }
    final textWidth = atUnit * fontSize;

    final w = ContentWriter();
    final gs = _alphaState(opacity);
    if (gs != null) w.extGState('GS0');
    w
      ..strokeColor(color)
      ..lineWidth(borderWidth)
      ..roundedRect(rect.left + borderWidth / 2, rect.bottom + borderWidth / 2,
          rect.width - borderWidth, rect.height - borderWidth, 4)
      ..stroke()
      ..beginText()
      ..font('HelvB', fontSize)
      ..fillColor(color)
      ..textAt(rect.left + (rect.width - textWidth) / 2,
          rect.bottom + (rect.height - fontSize * 0.718) / 2)
      ..showText(text)
      ..endText();
    return (w, gs);
  }

  /// Adds a count check-mark: a checkmark drawn inside [rect], modelled as
  /// a /Stamp with /Name /Check so the editing UI can tally them
  /// Bluebeam-style (see [PdfAnnotation.isCheckMark]). Being a stamp, it
  /// inherits select/move/resize/rotate/delete from the annotation
  /// machinery for free.
  void addCheckMark(
    int pageIndex,
    PdfRect rect, {
    int color = 0x2E7D32,
    double opacity = 1,
    String? author,
    String? name,
  }) {
    final (w, gs) = _checkMarkContent(rect, color, opacity);
    _addAnnotation(
      pageIndex,
      _markupDict('Stamp', rect, color, null, author)
        ..['Name'] = const CosName('Check'),
      _form(rect, w, resources: gs == null ? null : _resources(extGState: gs)),
      name: name,
    );
  }

  /// The check-mark appearance: a tick stroked inside [rect], centered in
  /// its largest square so it stays proportional whatever the rect aspect.
  (ContentWriter, CosDictionary?) _checkMarkContent(
      PdfRect rect, int color, double opacity) {
    final gs = _alphaState(opacity);
    final w = ContentWriter();
    if (gs != null) w.extGState('GS0');
    final s = math.min(rect.width, rect.height);
    final ox = rect.left + (rect.width - s) / 2;
    final oy = rect.bottom + (rect.height - s) / 2;
    w
      ..strokeColor(color)
      ..lineWidth(s * 0.16)
      ..roundLines()
      ..moveTo(ox + s * 0.18, oy + s * 0.50)
      ..lineTo(ox + s * 0.42, oy + s * 0.26)
      ..lineTo(ox + s * 0.82, oy + s * 0.74)
      ..stroke();
    return (w, gs);
  }

  /// Inserts [image] (a decoded PNG or JPEG) as a /Stamp annotation whose
  /// appearance draws it scaled to fill [rect].
  ///
  /// Modelled as a stamp so it inherits select/move/resize/rotate/delete
  /// from the annotation machinery for free. It carries no /Contents, so
  /// [pdfCanRestyleAnnotation] returns false — the restyle path would
  /// regenerate a /Stamp as a *text* stamp and destroy the picture.
  /// Resize stretches the appearance (the §12.5.5 BBox→Rect fit scales the
  /// form matrix, so the image scales with the box) and rotate bakes the
  /// matrix, exactly like any other stamp.
  void addImageStamp(
    int pageIndex,
    PdfRect rect,
    PdfEmbeddableImage image, {
    double opacity = 1,
    String? author,
    String? name,
  }) {
    final imageRef = _updater
        .addObject(image.toXObject((smask) => _updater.addObject(smask)));
    final w = ContentWriter();
    final gs = _alphaState(opacity);
    if (gs != null) w.extGState('GS0');
    // a unit image (1×1 at the origin) mapped onto the rect in page space —
    // the form's BBox is the rect, so the §12.5.5 fit is the identity
    w
      ..save()
      ..concatMatrix(rect.width, 0, 0, rect.height, rect.left, rect.bottom)
      ..drawXObject('Img0')
      ..restore();
    _addAnnotation(
      pageIndex,
      _markupDict('Stamp', rect, 0xC03030, null, author),
      _form(rect, w,
          resources: _resources(
              extGState: gs, xObject: CosDictionary({'Img0': imageRef}))),
      name: name,
    );
  }

  /// Removes [annotation] from the page, along with its popup, if any.
  void removeAnnotation(int pageIndex, PdfAnnotation annotation) {
    removeAnnotations(pageIndex, [annotation]);
  }

  /// Removes [annotations] from the page, along with their popups, if any.
  ///
  /// This is equivalent to calling [removeAnnotation] for every annotation,
  /// but scans and rewrites the page's /Annots array once. Use it for
  /// multi-select deletes so large annotation sets do not pay an O(n × m)
  /// identity scan plus one staged replacement per removed item.
  void removeAnnotations(int pageIndex, Iterable<PdfAnnotation> annotations) {
    final cos = document.cos;
    final page = document.page(pageIndex);
    final raw = page.dict['Annots'];
    final array = cos.resolve(raw);
    if (array is! CosArray) return;
    final targets = Set<CosDictionary>.identity();
    for (final annotation in annotations) {
      targets.add(annotation.dict);
      final popup = cos.resolve(annotation.dict['Popup']);
      if (popup is CosDictionary) targets.add(popup);
    }
    if (targets.isEmpty) return;
    final before = array.items.length;
    array.items.removeWhere((item) {
      final resolved = cos.resolve(item);
      return resolved is CosDictionary && targets.contains(resolved);
    });
    if (array.items.length == before) return;
    if (raw is CosReference) {
      _updater.replaceObject(raw.objectNumber, array);
    } else {
      _updater.markChanged(page.dict);
    }
  }

  /// Moves [annotations] to the end of the page's /Annots array,
  /// preserving their relative order. Later entries paint on top
  /// (§12.5.2's painter's model), so this brings them to the front.
  void bringAnnotationsToFront(
          int pageIndex, Iterable<PdfAnnotation> annotations) =>
      _reorderAnnotations(pageIndex, annotations, toFront: true);

  /// Moves [annotations] to the start of the page's /Annots array,
  /// preserving their relative order — behind everything else.
  void sendAnnotationsToBack(
          int pageIndex, Iterable<PdfAnnotation> annotations) =>
      _reorderAnnotations(pageIndex, annotations, toFront: false);

  void _reorderAnnotations(int pageIndex, Iterable<PdfAnnotation> annotations,
      {required bool toFront}) {
    final cos = document.cos;
    final page = document.page(pageIndex);
    final raw = page.dict['Annots'];
    final array = cos.resolve(raw);
    if (array is! CosArray) return;
    final targets = Set<CosDictionary>.identity()
      ..addAll([for (final annotation in annotations) annotation.dict]);
    final moved = <CosObject>[];
    final rest = <CosObject>[];
    for (final item in array.items) {
      final resolved = cos.resolve(item);
      (resolved is CosDictionary && targets.contains(resolved) ? moved : rest)
          .add(item);
    }
    if (moved.isEmpty) return;
    final reordered = toFront ? [...rest, ...moved] : [...moved, ...rest];
    var same = true;
    for (var i = 0; i < array.items.length && same; i++) {
      same = identical(array.items[i], reordered[i]);
    }
    if (same) return;
    array.items
      ..clear()
      ..addAll(reordered);
    if (raw is CosReference) {
      _updater.replaceObject(raw.objectNumber, array);
    } else {
      _updater.markChanged(page.dict);
    }
  }

  /// Translates [annotation] by ([dx], [dy]) in page space.
  ///
  /// Shifts /Rect and the absolute-coordinate entries that travel with it
  /// (/QuadPoints, /InkList, /L, /Vertices, /CL). The appearance stream
  /// needs no rewrite: viewers map its BBox onto the new /Rect (§12.5.5).
  void moveAnnotation(
      int pageIndex, PdfAnnotation annotation, double dx, double dy) {
    final dict = annotation.dict;
    final rect = annotation.rect;
    dict['Rect'] = _rectArray(PdfRect(
      rect.left + dx,
      rect.bottom + dy,
      rect.right + dx,
      rect.top + dy,
    ));
    for (final key in const ['QuadPoints', 'L', 'Vertices', 'CL']) {
      final shifted = _shiftPoints(dict[key], dx, dy);
      if (shifted != null) dict[key] = shifted;
    }
    final ink = document.cos.resolve(dict['InkList']);
    if (ink is CosArray) {
      dict['InkList'] = CosArray([
        for (final stroke in ink.items) _shiftPoints(stroke, dx, dy) ?? stroke,
      ]);
    }
    _markAnnotationChanged(pageIndex, dict);
  }

  /// Replaces a Line, PolyLine, or Polygon annotation's defining points
  /// and regenerates its appearance. Existing color, width, dash, fill,
  /// opacity, and line-ending style are preserved.
  void reshapeLineAnnotation(
      int pageIndex, PdfAnnotation annotation, List<(double, double)> points) {
    final subtype = annotation.subtype;
    if (subtype == 'Line' && points.length != 2) {
      throw ArgumentError.value(points, 'points', 'Line needs 2 points');
    }
    if (subtype == 'PolyLine' && points.length < 2) {
      throw ArgumentError.value(points, 'points', 'PolyLine needs 2+ points');
    }
    if (subtype == 'Polygon' && points.length < 3) {
      throw ArgumentError.value(points, 'points', 'Polygon needs 3+ points');
    }
    if (subtype != 'Line' && subtype != 'PolyLine' && subtype != 'Polygon') {
      throw ArgumentError.value(subtype, 'subtype', 'not a line annotation');
    }
    final stroke = annotation.color;
    final width = annotation.borderWidth ?? 1;
    if (stroke == null || width <= 0) return;
    final dashed = annotation.borderDash != null;
    final fill = subtype == 'Polygon' ? annotation.interiorColor : null;
    final endings = _lineEndings(annotation);
    final endingPoints = subtype == 'Polygon'
        ? const <(double, double)>[]
        : <(double, double)>[
            ..._endingExtent(endings.$1, points.first, points[1], width),
            ..._endingExtent(
                endings.$2, points.last, points[points.length - 2], width),
          ];
    final rect = _pointBounds(
        [...points, ...endingPoints], width + (dashed ? width : 0));
    final form = annotation.normalAppearance;
    final gs = _alphaState(form == null ? 1 : _appearanceOpacity(form));
    final w = _lineContent(points,
        strokeColor: stroke,
        strokeWidth: width,
        dashPattern: annotation.borderDash,
        closed: subtype == 'Polygon',
        fillColor: fill,
        startEnding: endings.$1,
        endEnding: endings.$2,
        hasAlpha: gs != null);
    final dict = annotation.dict;
    dict['Rect'] = _rectArray(rect);
    if (subtype == 'Line') {
      dict['L'] = CosArray([
        CosReal(points[0].$1),
        CosReal(points[0].$2),
        CosReal(points[1].$1),
        CosReal(points[1].$2),
      ]);
    } else {
      dict['Vertices'] = _pointArray(points);
    }
    if (form != null) {
      _replaceAppearance(dict, form, rect, w,
          resources: _resources(extGState: gs));
    } else {
      dict['AP'] = CosDictionary({
        'N': _updater
            .addObject(_form(rect, w, resources: _resources(extGState: gs))),
      });
    }
    _markAnnotationChanged(pageIndex, dict);
  }

  /// Sets the /LE line endings of a /Line or /PolyLine in place, keeping
  /// the annotation's object number and /Annots slot. The appearance,
  /// /Rect, and BBox regenerate from the current geometry with the new
  /// endings; pass null for an axis to leave it unchanged. A no-op (and
  /// returns false) for any other subtype, or when nothing changes.
  bool setLineEndings(
    int pageIndex,
    PdfAnnotation annotation, {
    PdfLineEnding? startEnding,
    PdfLineEnding? endEnding,
  }) {
    final subtype = annotation.subtype;
    if (subtype != 'Line' && subtype != 'PolyLine') return false;
    final current = _lineEndings(annotation);
    final start = startEnding ?? current.$1;
    final end = endEnding ?? current.$2;
    if (start == current.$1 && end == current.$2) return false;
    final List<(double, double)> points;
    if (subtype == 'Line') {
      final line = annotation.line;
      if (line == null) return false;
      points = [line.$1, line.$2];
    } else {
      final vertices = annotation.vertices;
      if (vertices == null || vertices.length < 2) return false;
      points = vertices;
    }
    annotation.dict['LE'] = CosArray([
      CosName(start.pdfName),
      CosName(end.pdfName),
    ]);
    // re-wrap: the dict's /LE just changed under the caller's instance, and
    // reshape reads the endings back through a fresh parse
    reshapeLineAnnotation(
        pageIndex, PdfAnnotation.fromDict(document, annotation.dict), points);
    return true;
  }

  /// Sets [annotation]'s /Contents text in place.
  ///
  /// Metadata only: the appearance is untouched, so for subtypes whose
  /// contents *are* the displayed text (free text, stamps, notes) this
  /// changes the tooltip/comment without redrawing — rewriting what's
  /// painted is the controller's text-edit path. An empty string removes
  /// the entry.
  void setAnnotationContents(
      int pageIndex, PdfAnnotation annotation, String contents) {
    final dict = annotation.dict;
    if (contents.isEmpty) {
      dict.entries.remove('Contents');
    } else {
      dict['Contents'] = CosString.fromText(contents);
    }
    _markAnnotationChanged(pageIndex, dict);
  }

  /// Sets [annotation]'s author (/T, §12.5.6.2) in place; null or empty
  /// removes it. Refused for form widgets, where /T is the field's
  /// partial name, not an author.
  void setAnnotationAuthor(
      int pageIndex, PdfAnnotation annotation, String? author) {
    if (annotation.subtype == 'Widget') {
      throw ArgumentError('on widgets /T is the field name, not an author');
    }
    final dict = annotation.dict;
    if (author == null || author.isEmpty) {
      dict.entries.remove('T');
    } else {
      dict['T'] = CosString.fromText(author);
    }
    _markAnnotationChanged(pageIndex, dict);
  }

  /// Sets [annotation]'s /NM unique name in place; null or empty removes
  /// it. The name is sync identity ([PdfAnnotation.name]) — rewrites that
  /// remove + re-add an annotation use this to carry it across.
  void setAnnotationName(
      int pageIndex, PdfAnnotation annotation, String? name) {
    final dict = annotation.dict;
    if (name == null || name.isEmpty) {
      dict.entries.remove('NM');
    } else {
      dict['NM'] = CosString.fromText(name);
    }
    _markAnnotationChanged(pageIndex, dict);
  }

  /// Sets [annotation]'s /F flag word (§12.5.3) in place — the way to
  /// lock an annotation in the saved file: bit 8 (`flags | 128`,
  /// [PdfAnnotation.isLocked]) refuses move/resize/delete, bit 7
  /// (`flags | 64`, [PdfAnnotation.isReadOnly]) refuses all interaction.
  /// Conforming viewers honor the same bits. The appearance is
  /// untouched; remember that bit 1 (hidden) and bit 3 (print) change
  /// what renders.
  void setAnnotationFlags(int pageIndex, PdfAnnotation annotation, int flags) {
    annotation.dict['F'] = CosInteger(flags);
    _markAnnotationChanged(pageIndex, annotation.dict);
  }

  /// Stamps a generated /NM on every annotation in the document that
  /// lacks one, so a pre-existing (or foreign) file can join name-keyed
  /// sync — call once before listening to a change feed. Popups, links,
  /// and form widgets are skipped: they can't be captured as
  /// [PdfAnnotationSnapshot]s, so names would buy them nothing. Returns
  /// how many annotations were named.
  int nameAnnotations() {
    var named = 0;
    for (var pageIndex = 0; pageIndex < document.pageCount; pageIndex++) {
      for (final annotation in document.page(pageIndex).annotations) {
        if (const {'Popup', 'Widget', 'Link'}.contains(annotation.subtype)) {
          continue;
        }
        if (annotation.name != null) continue;
        setAnnotationName(pageIndex, annotation, _generateAnnotationName());
        named++;
      }
    }
    return named;
  }

  /// Resizes [annotation] so its /Rect becomes [to].
  ///
  /// Squares, circles, and free text get their appearance *regenerated*
  /// at the new size — stroke width and font size stay what they were,
  /// the way desktop editors behave — whenever the dictionary carries
  /// enough style to do it faithfully (see
  /// [_regenerateResizedAppearance]). Everything else (ink, stamps,
  /// foreign artwork) keeps the §12.5.5 stretch: viewers fit the
  /// existing appearance's BBox onto the new /Rect.
  ///
  /// Either way, the absolute-coordinate entries that travel with the
  /// rect (/QuadPoints, /InkList, /L, /Vertices, /CL) are mapped through
  /// the old-rect → new-rect affine, so the annotation's geometry stays
  /// consistent for viewers that regenerate appearances.
  ///
  /// [flipX]/[flipY] mirror the annotation horizontally/vertically — what
  /// a drag that pulls a resize handle *past* the opposite edge produces.
  /// For a §12.5.5-stretched appearance the mirror is baked into the form
  /// /Matrix (about the BBox center, which leaves the BBox→/Rect fit
  /// untouched) and the point arrays reflect about the /Rect center to
  /// match; regenerated appearances (shapes, free text, lines) ignore the
  /// flip — a mirrored rectangle or readable-text box looks the same.
  void resizeAnnotation(int pageIndex, PdfAnnotation annotation, PdfRect to,
      {bool flipX = false, bool flipY = false}) {
    final from = annotation.rect;
    if (from.width <= 0 ||
        from.height <= 0 ||
        to.width <= 0 ||
        to.height <= 0) {
      throw ArgumentError('resizeAnnotation needs non-degenerate rects');
    }
    final regenerated = _regenerateResizedAppearance(annotation, to);
    if (!regenerated && (flipX || flipY)) {
      final form = annotation.normalAppearance;
      if (form != null) _flipFormArtwork(form, flipX: flipX, flipY: flipY);
    }
    final dict = annotation.dict;
    dict['Rect'] = _rectArray(to);
    final sx = to.width / from.width;
    final sy = to.height / from.height;
    double mapX(double x) {
      final t = (x - from.left) * sx;
      return flipX ? to.right - t : to.left + t;
    }

    double mapY(double y) {
      final t = (y - from.bottom) * sy;
      return flipY ? to.top - t : to.bottom + t;
    }

    for (final key in const ['QuadPoints', 'L', 'Vertices', 'CL']) {
      final scaled = _mapPoints(dict[key], mapX, mapY);
      if (scaled != null) dict[key] = scaled;
    }
    final ink = document.cos.resolve(dict['InkList']);
    if (ink is CosArray) {
      dict['InkList'] = CosArray([
        for (final stroke in ink.items)
          _mapPoints(stroke, mapX, mapY) ?? stroke,
      ]);
    }
    _markAnnotationChanged(pageIndex, dict);
  }

  /// Mirrors [form]'s artwork in place by premultiplying a reflection
  /// about the BBox center into its /Matrix. The reflection maps the BBox
  /// onto itself, so a conforming viewer's §12.5.5 BBox→/Rect fit lands
  /// exactly where it did — only the interior is flipped.
  void _flipFormArtwork(CosStream form,
      {required bool flipX, required bool flipY}) {
    final bbox = pdfRectFrom(document.cos, form.dictionary['BBox']);
    if (bbox == null) return;
    final cx = (bbox.left + bbox.right) / 2;
    final cy = (bbox.bottom + bbox.top) / 2;
    final reflect = <double>[
      flipX ? -1.0 : 1.0,
      0.0,
      0.0,
      flipY ? -1.0 : 1.0,
      flipX ? 2 * cx : 0.0,
      flipY ? 2 * cy : 0.0,
    ];
    final matrix = _mulAffine(reflect, _formMatrix(form));
    form.dictionary['Matrix'] = CosArray([for (final v in matrix) CosReal(v)]);
    final formRef = document.cos.referenceTo(form);
    if (formRef != null) _updater.replaceObject(formRef.objectNumber, form);
  }

  /// Rotates [annotation] by [degrees] counterclockwise about the center
  /// of its /Rect.
  ///
  /// The rotation is folded into the appearance stream's /Matrix — with
  /// the current BBox→Rect fit baked in first, so artwork whose BBox
  /// aspect differs from /Rect rotates without shearing — and /Rect
  /// becomes the bounding box of the rotated annotation, same center.
  /// Every viewer that implements the §12.5.5 fit then renders the
  /// artwork rotated. The absolute-coordinate entries that travel with
  /// the rect (/QuadPoints, /InkList, /L, /Vertices, /CL) rotate too, so
  /// viewers that regenerate appearances stay consistent.
  void rotateAnnotation(
      int pageIndex, PdfAnnotation annotation, double degrees) {
    final form = annotation.normalAppearance;
    if (form == null) {
      throw StateError('rotateAnnotation needs an appearance stream');
    }
    final rect = annotation.rect;
    if (rect.width <= 0 || rect.height <= 0) {
      throw ArgumentError('rotateAnnotation needs a non-degenerate rect');
    }
    final cos = document.cos;
    final bbox = pdfRectFrom(cos, form.dictionary['BBox']);
    if (bbox == null) return; // no BBox: §12.5.5 has nothing to map
    // the current BBox→Rect fit (the same bounds walk as the renderer)
    final baked = _bakedFormMatrix(form, rect);
    if (baked == null) return;

    final theta = degrees * math.pi / 180;
    final cosT = math.cos(theta), sinT = math.sin(theta);
    final cx = (rect.left + rect.right) / 2;
    final cy = (rect.bottom + rect.top) / 2;
    final rotation = [
      cosT,
      sinT,
      -sinT,
      cosT,
      cx - (cx * cosT - cy * sinT),
      cy - (cx * sinT + cy * cosT),
    ];
    final matrix = _mulAffine(baked, rotation);
    form.dictionary['Matrix'] = CosArray([for (final v in matrix) CosReal(v)]);

    // /Rect: the BBox corners' bounds under the new matrix. The matrix
    // carries the whole rotation history, so this stays the tightest box
    // around the rotated artwork — two 45° turns land exactly where one
    // 90° turn does, instead of compounding loose bounding boxes.
    annotation.dict['Rect'] = _rectArray(_bboxBounds(bbox, matrix));

    (double, double) rotate(double x, double y) => (
          cx + (x - cx) * cosT - (y - cy) * sinT,
          cy + (x - cx) * sinT + (y - cy) * cosT,
        );
    for (final key in const ['QuadPoints', 'L', 'Vertices', 'CL']) {
      final rotated = _mapPointPairs(annotation.dict[key], rotate);
      if (rotated != null) annotation.dict[key] = rotated;
    }
    final ink = cos.resolve(annotation.dict['InkList']);
    if (ink is CosArray) {
      annotation.dict['InkList'] = CosArray([
        for (final stroke in ink.items)
          _mapPointPairs(stroke, rotate) ?? stroke,
      ]);
    }

    final formRef = cos.referenceTo(form);
    if (formRef != null) _updater.replaceObject(formRef.objectNumber, form);
    _markAnnotationChanged(pageIndex, annotation.dict);
  }

  /// Resizes a possibly-rotated annotation in its own (unrotated) frame.
  ///
  /// [localTo] is the new axis-aligned box *before* the annotation's
  /// resting rotation: the committed annotation occupies [localTo]
  /// rotated about [localTo]'s center by the angle its appearance
  /// already carries. A page-axis /Rect stretch would shear rotated
  /// artwork; this never does. For an unrotated annotation it is
  /// exactly [resizeAnnotation].
  ///
  /// Square/Circle/FreeText regenerate their appearance at [localTo]
  /// (constant stroke width / font size) and re-rotate; every other
  /// subtype scales along its local axes inside the appearance /Matrix.
  ///
  /// [flipX]/[flipY] mirror the artwork along the local axes — a handle
  /// dragged past the opposite edge of the rotated box. For the stretch
  /// path the mirror folds into the local scale (a negative factor), so
  /// the /Rect and point arrays stay consistent with the appearance.
  void resizeAnnotationLocal(
      int pageIndex, PdfAnnotation annotation, PdfRect localTo,
      {bool flipX = false, bool flipY = false}) {
    final quad = annotation.appearanceQuad;
    final theta = quad == null ? 0.0 : _quadRotation(quad);
    if (theta == 0) {
      resizeAnnotation(pageIndex, annotation, localTo,
          flipX: flipX, flipY: flipY);
      return;
    }
    if (localTo.width <= 0 || localTo.height <= 0) {
      throw ArgumentError('resizeAnnotationLocal needs a non-degenerate rect');
    }
    // the resting local box: the quad's edge lengths about its center
    final (llx, lly) = quad![0];
    final (lrx, lry) = quad[1];
    final (urx, ury) = quad[2];
    final (ulx, uly) = quad[3];
    final cx = (llx + urx) / 2, cy = (lly + ury) / 2;
    final fromW =
        math.sqrt((lrx - llx) * (lrx - llx) + (lry - lly) * (lry - lly));
    final fromH =
        math.sqrt((ulx - llx) * (ulx - llx) + (uly - lly) * (uly - lly));
    if (fromW < 1e-9 || fromH < 1e-9) {
      resizeAnnotation(pageIndex, annotation, localTo,
          flipX: flipX, flipY: flipY);
      return;
    }

    if (_regenerateResizedAppearance(annotation, localTo)) {
      // a fresh, unrotated appearance at the local box — re-applying the
      // resting angle is then plain rotation (which also sets /Rect).
      // PdfAnnotation parses /Rect once, so rotate a re-wrapped view of
      // the dict instead of the stale [annotation]
      annotation.dict['Rect'] = _rectArray(localTo);
      rotateAnnotation(
          pageIndex,
          PdfAnnotation.fromDict(document, annotation.dict),
          theta * 180 / math.pi);
      return;
    }

    final form = annotation.normalAppearance;
    final baked = form == null ? null : _bakedFormMatrix(form, annotation.rect);
    if (form == null || baked == null) {
      // nothing can be rotated without a matrix-carrying appearance;
      // degrade to a page-space resize of the bounds
      resizeAnnotation(pageIndex, annotation, localTo,
          flipX: flipX, flipY: flipY);
      return;
    }
    final dict = annotation.dict;
    // a flip is a negative scale along the local axis — it commutes with
    // the scale and folds straight in, mirroring both the appearance
    // /Matrix and the mapped point arrays about the local center
    final sx = (localTo.width / fromW) * (flipX ? -1 : 1);
    final sy = (localTo.height / fromH) * (flipY ? -1 : 1);
    final tcx = (localTo.left + localTo.right) / 2;
    final tcy = (localTo.bottom + localTo.top) / 2;
    final cosT = math.cos(theta), sinT = math.sin(theta);
    // page-space affine: into the local frame about the old center,
    // scale, back out, recenter — T(-c) · R(-θ) · S · R(θ) · T(c')
    final local = _mulAffine(
      _mulAffine(
        _mulAffine([1, 0, 0, 1, -cx, -cy], [cosT, -sinT, sinT, cosT, 0, 0]),
        [sx, 0, 0, sy, 0, 0],
      ),
      _mulAffine([cosT, sinT, -sinT, cosT, 0, 0], [1, 0, 0, 1, tcx, tcy]),
    );
    final matrix = _mulAffine(baked, local);
    form.dictionary['Matrix'] = CosArray([for (final v in matrix) CosReal(v)]);
    final bbox = pdfRectFrom(document.cos, form.dictionary['BBox']);
    if (bbox != null) dict['Rect'] = _rectArray(_bboxBounds(bbox, matrix));

    (double, double) map(double x, double y) => (
          local[0] * x + local[2] * y + local[4],
          local[1] * x + local[3] * y + local[5],
        );
    for (final key in const ['QuadPoints', 'L', 'Vertices', 'CL']) {
      final mapped = _mapPointPairs(dict[key], map);
      if (mapped != null) dict[key] = mapped;
    }
    final ink = document.cos.resolve(dict['InkList']);
    if (ink is CosArray) {
      dict['InkList'] = CosArray([
        for (final stroke in ink.items) _mapPointPairs(stroke, map) ?? stroke,
      ]);
    }
    final formRef = document.cos.referenceTo(form);
    if (formRef != null) _updater.replaceObject(formRef.objectNumber, form);
    _markAnnotationChanged(pageIndex, dict);
  }

  /// The page-space rotation of [quad]'s bottom edge, radians CCW;
  /// numeric noise within ~0.3° reads as unrotated.
  static double _quadRotation(List<(double, double)> quad) {
    final dx = quad[1].$1 - quad[0].$1;
    final dy = quad[1].$2 - quad[0].$2;
    if (dx == 0 && dy == 0) return 0;
    final angle = math.atan2(dy, dx);
    return angle.abs() < 0.005 ? 0 : angle;
  }

  /// Regenerates the appearance of a Square, Circle, FreeText, Line,
  /// PolyLine, or Polygon at
  /// [to] from the style its dictionary carries, replacing the /AP /N
  /// stream. Returns false — leaving the caller on the §12.5.5 stretch
  /// path — for other subtypes and for styles it can't reproduce
  /// faithfully: cloudy (/BE) shape borders, free text whose /DA doesn't
  /// name a standard font.
  ///
  /// [opacity], when given, replaces the alpha the old appearance
  /// carried — [restyleAnnotation]'s opacity path.
  bool _regenerateResizedAppearance(PdfAnnotation annotation, PdfRect to,
      {double? opacity}) {
    final form = annotation.normalAppearance;
    if (form == null) return false;
    final dict = annotation.dict;
    switch (annotation.subtype) {
      case 'Square' || 'Circle':
        if (dict['BE'] != null) return false; // cloudy borders still stretch
        final width = annotation.borderWidth ?? 1;
        final stroke = width > 0 ? annotation.color : null;
        final fill = annotation.interiorColor;
        if (stroke == null && fill == null) return false;
        final gs = _alphaState(opacity ?? _appearanceOpacity(form));
        final w = _shapeContent(annotation.subtype, to, stroke, width, fill,
            dashPattern: annotation.borderDash, hasAlpha: gs != null);
        _replaceAppearance(dict, form, to, w,
            resources: _resources(extGState: gs));
        return true;
      case 'FreeText':
        final style = annotation.freeTextStyle;
        if (style == null) return false;
        final font = PdfStandardFont.tryFromName(style.fontName);
        if (font == null) return false;
        final w = _freeTextContent(to, annotation.contents ?? '',
            fontSize: style.fontSize,
            font: font,
            textDirection: _annotationTextDirection(annotation),
            color: style.color,
            fillColor: style.fillColor,
            borderColor: style.borderColor,
            borderWidth: style.borderWidth);
        _replaceAppearance(dict, form, to, w,
            resources: _resources(font: _standardFont(font)));
        return true;
      case 'Line':
        final line = annotation.line;
        if (line == null) return false;
        final from = annotation.rect;
        final sx = to.width / from.width;
        final sy = to.height / from.height;
        (double, double) map((double, double) p) => (
              to.left + (p.$1 - from.left) * sx,
              to.bottom + (p.$2 - from.bottom) * sy,
            );
        return _regenerateLineLikeAppearance(annotation, to,
            points: [map(line.$1), map(line.$2)], opacity: opacity);
      case 'PolyLine' || 'Polygon':
        final vertices = annotation.vertices;
        if (vertices == null || vertices.isEmpty) return false;
        final from = annotation.rect;
        final sx = to.width / from.width;
        final sy = to.height / from.height;
        final mapped = [
          for (final (x, y) in vertices)
            (to.left + (x - from.left) * sx, to.bottom + (y - from.bottom) * sy)
        ];
        return _regenerateLineLikeAppearance(annotation, to,
            points: mapped, opacity: opacity);
      default:
        return false;
    }
  }

  bool _regenerateLineLikeAppearance(PdfAnnotation annotation, PdfRect rect,
      {required List<(double, double)> points, double? opacity}) {
    final form = annotation.normalAppearance;
    if (form == null) return false;
    final width = annotation.borderWidth ?? 1;
    final stroke = annotation.color;
    if (stroke == null || width <= 0) return false;
    final fill =
        annotation.subtype == 'Polygon' ? annotation.interiorColor : null;
    final endings = _lineEndings(annotation);
    final gs = _alphaState(opacity ?? _appearanceOpacity(form));
    final w = _lineContent(points,
        strokeColor: stroke,
        strokeWidth: width,
        dashPattern: annotation.borderDash,
        closed: annotation.subtype == 'Polygon',
        fillColor: fill,
        startEnding: endings.$1,
        endEnding: endings.$2,
        hasAlpha: gs != null);
    _replaceAppearance(annotation.dict, form, rect, w,
        resources: _resources(extGState: gs));
    return true;
  }

  /// The endings recorded on [annotation]'s /LE entry — both
  /// [PdfLineEnding.none] for subtypes that carry no endings
  /// (/Polygon is closed; /PolyLine endings apply to its first and last
  /// vertex per §12.5.6.7).
  (PdfLineEnding, PdfLineEnding) _lineEndings(PdfAnnotation annotation) =>
      pdfLineEndings(annotation) ?? (PdfLineEnding.none, PdfLineEnding.none);

  /// Restyles [annotation] in place: new colors, stroke width, or
  /// opacity at its current geometry, with the appearance regenerated —
  /// same object numbers and /Annots slot, so selection, z-order,
  /// author, and contents all survive (unlike a remove + re-add).
  ///
  /// What each parameter means per subtype:
  ///
  /// * [color] — the stroke color of shapes and ink, the markup tint,
  ///   the note/stamp color, and the *text* color of free text.
  /// * [fillColor] — the interior of shapes (/IC) and the background of
  ///   free text (/C); the single-field record distinguishes "set to
  ///   this" — including `(null,)`, clearing the fill — from an omitted
  ///   parameter. Ignored elsewhere.
  /// * [strokeWidth] — shapes and ink. Ignored elsewhere (markup line
  ///   weights derive from the text size; free-text borders restyle
  ///   through the text-style path).
  /// * [opacity] — shapes, ink, markups, stamps. Free text and notes
  ///   stay opaque, as authored.
  ///
  /// Rotation survives: a rotated appearance regenerates in its local
  /// frame and re-rotates, exactly like [resizeAnnotationLocal].
  /// Returns false when nothing applies — gate UI with
  /// [pdfCanRestyleAnnotation].
  bool restyleAnnotation(
    int pageIndex,
    PdfAnnotation annotation, {
    int? color,
    (int?,)? fillColor,
    double? strokeWidth,
    double? opacity,
    (List<double>?,)? dashPattern,
  }) {
    if (color == null &&
        fillColor == null &&
        strokeWidth == null &&
        opacity == null &&
        dashPattern == null) {
      return false;
    }
    if (!pdfCanRestyleAnnotation(annotation)) return false;
    final dict = annotation.dict;
    switch (annotation.subtype) {
      case 'Ink':
        final form = annotation.normalAppearance;
        final strokes = annotation.inkList!;
        final oldWidth = annotation.borderWidth ?? 1;
        final pressures =
            form == null ? null : _recoverInkPressures(form, strokes, oldWidth);
        final newColor = color ?? annotation.color ?? 0x000000;
        final newWidth = strokeWidth ?? oldWidth;
        final newOpacity =
            opacity ?? (form == null ? 1.0 : _appearanceOpacity(form));
        final (rect, w, gs) =
            _inkAppearance(strokes, pressures, newColor, newWidth, newOpacity);
        dict['Rect'] = _rectArray(rect);
        dict['C'] = _colorComponents(newColor);
        dict['BS'] = _borderStyle(newWidth);
        if (form != null) {
          _replaceAppearance(dict, form, rect, w,
              resources: _resources(extGState: gs));
        } else {
          dict['AP'] = CosDictionary({
            'N': _updater.addObject(
                _form(rect, w, resources: _resources(extGState: gs))),
          });
        }
        _markAnnotationChanged(pageIndex, dict);
        return true;
      case 'Highlight' || 'Underline' || 'StrikeOut' || 'Squiggly':
        final quads = _axisAlignedQuads(annotation)!;
        final form = annotation.normalAppearance;
        final newColor = color ?? annotation.color ?? 0xFFD100;
        final newOpacity =
            opacity ?? (form == null ? 1.0 : _appearanceOpacity(form));
        final rect = _boundsOf(quads);
        final (w, gs) =
            _markupContent(annotation.subtype, quads, newColor, newOpacity);
        dict['C'] = _colorComponents(newColor);
        dict['Rect'] = _rectArray(rect);
        if (form != null) {
          _replaceAppearance(dict, form, rect, w,
              resources: _resources(extGState: gs));
        } else {
          dict['AP'] = CosDictionary({
            'N': _updater.addObject(
                _form(rect, w, resources: _resources(extGState: gs))),
          });
        }
        _markAnnotationChanged(pageIndex, dict);
        return true;
      case 'Square' || 'Circle':
        final width = strokeWidth ?? annotation.borderWidth ?? 1;
        final stroke = color ?? annotation.color;
        final fill =
            fillColor != null ? fillColor.$1 : annotation.interiorColor;
        if ((stroke == null || width <= 0) && fill == null) return false;
        if (stroke != null) dict['C'] = _colorComponents(stroke);
        final dash =
            dashPattern != null ? dashPattern.$1 : annotation.borderDash;
        dict['BS'] = _borderStyle(width, dashPattern: dash);
        if (fill != null) {
          dict['IC'] = _colorComponents(fill);
        } else {
          dict.entries.remove('IC');
        }
        return _restyleRegenerate(pageIndex, dict, opacity: opacity);
      case 'Line' || 'PolyLine' || 'Polygon':
        final width = strokeWidth ?? annotation.borderWidth ?? 1;
        final stroke = color ?? annotation.color;
        if (stroke == null || width <= 0) return false;
        final dash =
            dashPattern != null ? dashPattern.$1 : annotation.borderDash;
        dict['C'] = _colorComponents(stroke);
        dict['BS'] = _borderStyle(width, dashPattern: dash);
        if (annotation.subtype == 'Polygon') {
          final fill =
              fillColor != null ? fillColor.$1 : annotation.interiorColor;
          if (fill != null) {
            dict['IC'] = _colorComponents(fill);
          } else {
            dict.entries.remove('IC');
          }
        }
        return _restyleRegenerate(pageIndex, dict, opacity: opacity);
      case 'FreeText':
        final style = annotation.freeTextStyle!;
        final font = PdfStandardFont.tryFromName(style.fontName)!;
        final textColor = color ?? style.color;
        final fill = fillColor != null ? fillColor.$1 : style.fillColor;
        final border = style.borderColor != null && style.borderWidth > 0
            ? style.borderColor
            : null;
        String rgb(int c) =>
            ContentWriter.rgbComponents(c).map(ContentWriter.fmt).join(' ');
        dict['DA'] = CosString.fromText('${rgb(textColor)} rg '
            '${border != null ? '${rgb(border)} RG ' : ''}'
            '/${font.resourceName} ${ContentWriter.fmt(style.fontSize)} Tf');
        // /C is the background — or mirrors the text color when there is
        // none, the legacy form freeTextStyle reads back as "no fill"
        dict['C'] = _colorComponents(fill ?? textColor);
        return _restyleRegenerate(pageIndex, dict);
      case 'Text':
        dict['C'] = _colorComponents(color ?? annotation.color ?? 0xFFD100);
        return _restyleRegenerate(pageIndex, dict);
      case 'Stamp':
        dict['C'] = _colorComponents(color ?? annotation.color ?? 0xC03030);
        return _restyleRegenerate(pageIndex, dict, opacity: opacity);
    }
    return false;
  }

  /// Regenerates an annotation's appearance after its dictionary style
  /// changed, preserving any rotation the appearance matrix carries:
  /// unrotated annotations regenerate at their /Rect; rotated ones
  /// regenerate in their local frame and re-rotate (the
  /// [resizeAnnotationLocal] shape, at the same size).
  bool _restyleRegenerate(int pageIndex, CosDictionary dict,
      {double? opacity}) {
    // re-wrap: /Rect and style entries are parsed at construction or
    // lazily, and the dict just changed under the caller's instance
    final annotation = PdfAnnotation.fromDict(document, dict);
    final quad = annotation.appearanceQuad;
    final theta = quad == null ? 0.0 : _quadRotation(quad);
    if (theta == 0) {
      if (!_regenerateStyledAppearance(annotation, annotation.rect,
          opacity: opacity)) {
        return false;
      }
      _markAnnotationChanged(pageIndex, dict);
      return true;
    }
    final (llx, lly) = quad![0];
    final (lrx, lry) = quad[1];
    final (urx, ury) = quad[2];
    final (ulx, uly) = quad[3];
    final cx = (llx + urx) / 2, cy = (lly + ury) / 2;
    final w = math.sqrt((lrx - llx) * (lrx - llx) + (lry - lly) * (lry - lly));
    final h = math.sqrt((ulx - llx) * (ulx - llx) + (uly - lly) * (uly - lly));
    if (w < 1e-9 || h < 1e-9) return false;
    final local = PdfRect(cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2);
    if (!_regenerateStyledAppearance(annotation, local, opacity: opacity)) {
      return false;
    }
    dict['Rect'] = _rectArray(local);
    rotateAnnotation(pageIndex, PdfAnnotation.fromDict(document, dict),
        theta * 180 / math.pi);
    return true;
  }

  /// [_regenerateResizedAppearance] widened to the restyle-only
  /// subtypes (stamps, notes), which regenerate at their current size
  /// but never resize this way.
  bool _regenerateStyledAppearance(PdfAnnotation annotation, PdfRect to,
      {double? opacity}) {
    switch (annotation.subtype) {
      case 'Square' ||
            'Circle' ||
            'FreeText' ||
            'Line' ||
            'PolyLine' ||
            'Polygon':
        return _regenerateResizedAppearance(annotation, to, opacity: opacity);
      case 'Stamp':
        final form = annotation.normalAppearance;
        if (form == null) return false;
        final color = annotation.color ?? 0xC03030;
        final (w, gs) = _stampContent(to, annotation.contents ?? '', color,
            opacity ?? _appearanceOpacity(form));
        _replaceAppearance(annotation.dict, form, to, w,
            resources: _resources(
                extGState: gs, font: _helvetica(bold: true, name: 'HelvB')));
        return true;
      case 'Text':
        final form = annotation.normalAppearance;
        if (form == null) return false;
        final color = annotation.color ?? 0xFFD100;
        _replaceAppearance(annotation.dict, form, to, _noteContent(to, color));
        return true;
      default:
        return false;
    }
  }

  CosArray _colorComponents(int color) => CosArray([
        for (final c in ContentWriter.rgbComponents(color)) CosReal(c),
      ]);

  /// The constant alpha an appearance we generated carries: the first
  /// /ca found in its /Resources /ExtGState entries, else opaque. (The
  /// dictionary deliberately has no /CA — viewers would apply it *on
  /// top* of the alpha already baked into the appearance.)
  double _appearanceOpacity(CosStream form) {
    final cos = document.cos;
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

  /// Replaces [oldForm] (the annotation's /AP /N) with a fresh form of
  /// BBox [bbox] and content [w] — keeping the same object number when
  /// the stream is indirect, so existing references stay valid, and
  /// adopting the new object into the document cache so later edits in
  /// the same apply resolve it.
  void _replaceAppearance(
      CosDictionary annot, CosStream oldForm, PdfRect bbox, ContentWriter w,
      {CosDictionary? resources}) {
    final form = _form(bbox, w, resources: resources);
    final cos = document.cos;
    final ref = cos.referenceTo(oldForm);
    if (ref != null) {
      _updater.replaceObject(ref.objectNumber, form);
      cos.adoptObject(ref, form);
    } else {
      final ap = cos.resolve(annot['AP']);
      if (ap is CosDictionary) ap['N'] = _updater.addObject(form);
    }
  }

  /// [form]'s /Matrix with the §12.5.5 BBox→Rect fit baked in: the
  /// explicit affine mapping BBox space onto [rect] exactly as a
  /// conforming viewer would. Null when the BBox is missing or its
  /// transformed bounds are degenerate.
  List<double>? _bakedFormMatrix(CosStream form, PdfRect rect) {
    final bbox = pdfRectFrom(document.cos, form.dictionary['BBox']);
    if (bbox == null) return null;
    final m = _formMatrix(form);
    final bounds = _bboxBounds(bbox, m);
    if (bounds.width < 1e-9 || bounds.height < 1e-9) return null;
    final sx = rect.width / bounds.width;
    final sy = rect.height / bounds.height;
    return _mulAffine(m, [
      sx,
      0,
      0,
      sy,
      rect.left - bounds.left * sx,
      rect.bottom - bounds.bottom * sy
    ]);
  }

  /// The bounds of [bbox]'s corners under the affine [m].
  PdfRect _bboxBounds(PdfRect bbox, List<double> m) {
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final (x, y) in [
      (bbox.left, bbox.bottom),
      (bbox.right, bbox.bottom),
      (bbox.right, bbox.top),
      (bbox.left, bbox.top),
    ]) {
      final tx = m[0] * x + m[2] * y + m[4];
      final ty = m[1] * x + m[3] * y + m[5];
      minX = math.min(minX, tx);
      maxX = math.max(maxX, tx);
      minY = math.min(minY, ty);
      maxY = math.max(maxY, ty);
    }
    return PdfRect(minX, minY, maxX, maxY);
  }

  /// `first`, then `second` — the affine product in PDF's row-vector
  /// convention, both as `[a b c d e f]`.
  static List<double> _mulAffine(List<double> first, List<double> second) => [
        first[0] * second[0] + first[1] * second[2],
        first[0] * second[1] + first[1] * second[3],
        first[2] * second[0] + first[3] * second[2],
        first[2] * second[1] + first[3] * second[3],
        first[4] * second[0] + first[5] * second[2] + second[4],
        first[4] * second[1] + first[5] * second[3] + second[5],
      ];

  /// An x y x y ... array translated by (dx, dy), or null if [raw] is not
  /// a numeric array.
  CosArray? _shiftPoints(CosObject? raw, double dx, double dy) =>
      _mapPoints(raw, (x) => x + dx, (y) => y + dy);

  /// An x y x y ... array with each coordinate mapped, or null if [raw]
  /// is not a numeric array.
  CosArray? _mapPoints(CosObject? raw, double Function(double) mapX,
          double Function(double) mapY) =>
      _mapPointPairs(raw, (x, y) => (mapX(x), mapY(y)));

  /// An x y x y ... array with each point mapped jointly (rotation needs
  /// both coordinates), or null if [raw] is not a numeric array.
  CosArray? _mapPointPairs(
      CosObject? raw, (double, double) Function(double x, double y) map) {
    final cos = document.cos;
    final array = cos.resolve(raw);
    if (array is! CosArray) return null;
    final values = <double>[];
    for (var i = 0; i < array.length; i++) {
      final n = cos.resolve(array[i]);
      if (n is CosInteger) {
        values.add(n.value.toDouble());
      } else if (n is CosReal) {
        values.add(n.value);
      } else {
        return null;
      }
    }
    final mapped = <CosObject>[];
    for (var i = 0; i + 1 < values.length; i += 2) {
      final (x, y) = map(values[i], values[i + 1]);
      mapped
        ..add(CosReal(x))
        ..add(CosReal(y));
    }
    return CosArray(mapped);
  }

  /// Stages whatever object owns [dict]'s bytes: the annotation itself
  /// when indirect, otherwise its containing /Annots array or page.
  void _markAnnotationChanged(int pageIndex, CosDictionary dict) {
    final cos = document.cos;
    final ref = cos.referenceTo(dict);
    if (ref != null) {
      _updater.replaceObject(ref.objectNumber, dict);
      return;
    }
    final page = document.page(pageIndex);
    final raw = page.dict['Annots'];
    final array = cos.resolve(raw);
    if (raw is CosReference && array is CosArray) {
      _updater.replaceObject(raw.objectNumber, array);
    } else {
      _updater.markChanged(page.dict);
    }
  }

  /// Bakes the page's annotation appearances into its content streams and
  /// removes those annotations, making them permanent, non-interactive
  /// page graphics.
  ///
  /// Annotations without a paintable appearance — hidden or no-view ones,
  /// popups, and any without /AP — are left in place untouched.
  void flattenAnnotations(int pageIndex) =>
      _flattenAnnotations(pageIndex, (_) => true);

  /// [flattenAnnotations] restricted to annotations matching [select]
  /// (used by [PdfFormAdmin.flattenForm] to take widgets only).
  void _flattenAnnotations(int pageIndex, bool Function(PdfAnnotation) select) {
    final cos = document.cos;
    final page = document.page(pageIndex);

    // copy-on-write resources: the page's dict may be shared between
    // pages (inherited), so additions go into clones
    final ownResources = cos.resolve(page.dict['Resources']);
    final resources = CosDictionary({
      ...(ownResources is CosDictionary ? ownResources : page.resources)
          .entries,
    });
    final existingXObjects = cos.resolve(resources['XObject']);
    final xObjects = CosDictionary({
      if (existingXObjects is CosDictionary) ...existingXObjects.entries,
    });

    final w = ContentWriter()
      // restore the state the prefix stream saved before the original
      // content ran, so annotations paint over a clean slate
      ..restore();
    final flattened = <CosDictionary>{};
    var index = 0;
    for (final annot in page.annotations) {
      if (!select(annot)) continue;
      if (annot.isHidden || annot.isNoView || annot.subtype == 'Popup') {
        continue;
      }
      final form = annot.normalAppearance;
      if (form == null) continue;
      final rect = annot.rect;
      final bbox = pdfRectFrom(cos, form.dictionary['BBox']);
      if (bbox == null || rect.width <= 0 || rect.height <= 0) continue;

      // §12.5.5 algorithm: transform the BBox corners by the form /Matrix,
      // then scale/translate the resulting bounds onto /Rect. The /Matrix
      // itself is applied by the Do operator, so only the fit goes in cm.
      final m = _formMatrix(form);
      var minX = double.infinity, minY = double.infinity;
      var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
      for (final (x, y) in [
        (bbox.left, bbox.bottom),
        (bbox.right, bbox.bottom),
        (bbox.right, bbox.top),
        (bbox.left, bbox.top),
      ]) {
        final tx = m[0] * x + m[2] * y + m[4];
        final ty = m[1] * x + m[3] * y + m[5];
        if (tx < minX) minX = tx;
        if (tx > maxX) maxX = tx;
        if (ty < minY) minY = ty;
        if (ty > maxY) maxY = ty;
      }
      final sx = maxX - minX > 1e-9 ? rect.width / (maxX - minX) : 1.0;
      final sy = maxY - minY > 1e-9 ? rect.height / (maxY - minY) : 1.0;

      var name = 'FlatAnnot$index';
      while (xObjects.containsKey(name)) {
        name = 'FlatAnnot${++index}';
      }
      index++;
      xObjects[name] = cos.referenceTo(form) ?? _updater.addObject(form);
      w
        ..save()
        ..concatMatrix(
            sx, 0, 0, sy, rect.left - minX * sx, rect.bottom - minY * sy)
        ..drawXObject(name)
        ..restore();
      flattened.add(annot.dict);
    }
    if (flattened.isEmpty) return;

    resources['XObject'] = xObjects;
    page.dict['Resources'] = resources;

    // sandwich the original content between q and Q so its leftover
    // graphics state cannot leak into the appearance drawing
    final rawContents = page.dict['Contents'];
    final resolvedContents = cos.resolve(rawContents);
    final items = <CosObject>[_updater.addObject(_rawStream('q\n'))];
    if (resolvedContents is CosArray) {
      items.addAll(resolvedContents.items);
    } else if (resolvedContents is CosStream) {
      items.add(rawContents is CosReference
          ? rawContents
          : _updater.addObject(resolvedContents));
    }
    final suffix = w.takeBytes();
    items.add(_updater.addObject(CosStream(
        CosDictionary({'Length': CosInteger(suffix.length)}), suffix)));
    page.dict['Contents'] = CosArray(items);

    final annotsArray = cos.resolve(page.dict['Annots']);
    if (annotsArray is CosArray) {
      final remaining = [
        for (final item in annotsArray.items)
          if (!flattened.contains(cos.resolve(item))) item,
      ];
      if (remaining.isEmpty) {
        page.dict.entries.remove('Annots');
      } else {
        page.dict['Annots'] = CosArray(remaining);
      }
    }
    _updater.markChanged(page.dict);
  }

  // ---------------------------------------------------------------------
  // shared machinery

  List<double> _formMatrix(CosStream form) {
    final raw = document.cos.resolve(form.dictionary['Matrix']);
    if (raw is CosArray && raw.length >= 6) {
      final values = <double>[];
      for (var i = 0; i < 6; i++) {
        final n = document.cos.resolve(raw[i]);
        values.add(n is CosInteger
            ? n.value.toDouble()
            : n is CosReal
                ? n.value
                : (i == 0 || i == 3 ? 1.0 : 0.0));
      }
      return values;
    }
    return const [1, 0, 0, 1, 0, 0];
  }

  CosStream _rawStream(String text) {
    final bytes = Uint8List.fromList(text.codeUnits);
    return CosStream(
        CosDictionary({'Length': CosInteger(bytes.length)}), bytes);
  }

  void _addShape(
    String subtype,
    int pageIndex,
    PdfRect rect,
    int? strokeColor,
    double strokeWidth,
    int? fillColor,
    double opacity,
    String? contents,
    String? author,
    String? name,
    List<double>? dashPattern,
  ) {
    if (strokeColor == null && fillColor == null) {
      throw ArgumentError('strokeColor and fillColor are both null');
    }
    final stroking = strokeColor != null && strokeWidth > 0;
    final dash = stroking ? dashPattern : null;
    final gs = _alphaState(opacity);
    final w = _shapeContent(subtype, rect, strokeColor, strokeWidth, fillColor,
        dashPattern: dash, hasAlpha: gs != null);

    final dict = _markupDict(
        subtype, rect, strokeColor ?? fillColor!, contents, author)
      ..['BS'] = _borderStyle(stroking ? strokeWidth : 0, dashPattern: dash);
    if (fillColor != null) {
      dict['IC'] = CosArray([
        for (final c in ContentWriter.rgbComponents(fillColor)) CosReal(c),
      ]);
    }
    _addAnnotation(
        pageIndex, dict, _form(rect, w, resources: _resources(extGState: gs)),
        name: name);
  }

  /// The shape appearance content: a rectangle or inscribed ellipse,
  /// stroked inside [rect] so the line never spills past the /Rect.
  ContentWriter _shapeContent(String subtype, PdfRect rect, int? strokeColor,
      double strokeWidth, int? fillColor,
      {List<double>? dashPattern, required bool hasAlpha}) {
    final stroking = strokeColor != null && strokeWidth > 0;
    final inset = stroking ? strokeWidth / 2 : 0.0;
    final w = ContentWriter();
    if (hasAlpha) w.extGState('GS0');
    if (fillColor != null) w.fillColor(fillColor);
    if (stroking) {
      w
        ..strokeColor(strokeColor)
        ..lineWidth(strokeWidth);
      if (dashPattern != null && dashPattern.isNotEmpty) w.dash(dashPattern);
    }
    if (subtype == 'Square') {
      w.rect(rect.left + inset, rect.bottom + inset, rect.width - 2 * inset,
          rect.height - 2 * inset);
    } else {
      w.ellipse((rect.left + rect.right) / 2, (rect.bottom + rect.top) / 2,
          rect.width / 2 - inset, rect.height / 2 - inset);
    }
    if (fillColor != null && stroking) {
      w.fillAndStroke();
    } else if (fillColor != null) {
      w.fill();
    } else {
      w.stroke();
    }
    return w;
  }

  ContentWriter _lineContent(
    List<(double, double)> points, {
    required int strokeColor,
    required double strokeWidth,
    required List<double>? dashPattern,
    required bool closed,
    required int? fillColor,
    PdfLineEnding startEnding = PdfLineEnding.none,
    PdfLineEnding endEnding = PdfLineEnding.none,
    required bool hasAlpha,
  }) {
    final dashed = dashPattern != null && dashPattern.isNotEmpty;
    final w = ContentWriter();
    if (hasAlpha) w.extGState('GS0');
    if (fillColor != null) w.fillColor(fillColor);
    w
      ..strokeColor(strokeColor)
      ..lineWidth(strokeWidth)
      ..lineCap(0)
      ..lineJoin(1);
    if (dashed) w.dash(dashPattern);
    w.moveTo(points.first.$1, points.first.$2);
    for (final (x, y) in points.skip(1)) {
      w.lineTo(x, y);
    }
    if (closed) w.closePath();
    if (closed && fillColor != null) {
      w.fillAndStroke();
    } else {
      w.stroke();
    }
    if (dashed) w.dash(const []);
    if (points.length >= 2) {
      _drawEnding(
          w, startEnding, points.first, points[1], strokeColor, strokeWidth);
      _drawEnding(w, endEnding, points.last, points[points.length - 2],
          strokeColor, strokeWidth);
    }
    return w;
  }

  /// One line-ending shape (§12.5.6.7, Table 176) at endpoint [tip], with
  /// the line arriving from [from]. The shape is oriented along the
  /// segment: `u` points from the tip back into the line body, `p` is the
  /// left-hand perpendicular. Closed shapes are returned with
  /// `filled: true`; [PdfLineEnding.circle] additionally sets `isCircle`
  /// (the [vertices] are then its four cardinal extent points, used for
  /// bounds, and [radius]/[center] drive the Bézier draw).
  ///
  /// `r*` variants reverse the arrow direction (apex points into the line
  /// instead of out of it). Returns null for [PdfLineEnding.none].
  ({
    List<(double, double)> vertices,
    bool closed,
    bool filled,
    bool isCircle,
    (double, double) center,
    double radius,
  })? _endingPath(PdfLineEnding kind, (double, double) tip,
      (double, double) from, double strokeWidth) {
    if (kind == PdfLineEnding.none) return null;
    final dx = from.$1 - tip.$1;
    final dy = from.$2 - tip.$2;
    final len = math.sqrt(dx * dx + dy * dy);
    final ux = len < 1e-9 ? 1.0 : dx / len;
    final uy = len < 1e-9 ? 0.0 : dy / len;
    final px = -uy, py = ux;
    final s = math.max(10.0, strokeWidth * 5);
    (double, double) at(double along, double across) =>
        (tip.$1 + ux * along + px * across, tip.$2 + uy * along + py * across);
    switch (kind) {
      case PdfLineEnding.closedArrow:
      case PdfLineEnding.openArrow:
        final hw = s * 0.38;
        return (
          // barb, apex (tip), barb — closed for the filled arrow
          vertices: [at(s, hw), tip, at(s, -hw)],
          closed: kind == PdfLineEnding.closedArrow,
          filled: kind == PdfLineEnding.closedArrow,
          isCircle: false,
          center: tip,
          radius: 0,
        );
      case PdfLineEnding.rClosedArrow:
      case PdfLineEnding.rOpenArrow:
        final hw = s * 0.38;
        return (
          // reversed: apex points into the line, barbs sit on the endpoint
          vertices: [at(0, hw), at(s, 0), at(0, -hw)],
          closed: kind == PdfLineEnding.rClosedArrow,
          filled: kind == PdfLineEnding.rClosedArrow,
          isCircle: false,
          center: tip,
          radius: 0,
        );
      case PdfLineEnding.diamond:
        final r = s * 0.45;
        return (
          vertices: [at(r, 0), at(0, r), at(-r, 0), at(0, -r)],
          closed: true,
          filled: true,
          isCircle: false,
          center: tip,
          radius: 0,
        );
      case PdfLineEnding.square:
        final h = s * 0.35;
        return (
          vertices: [at(h, h), at(h, -h), at(-h, -h), at(-h, h)],
          closed: true,
          filled: true,
          isCircle: false,
          center: tip,
          radius: 0,
        );
      case PdfLineEnding.circle:
        final r = s * 0.4;
        return (
          vertices: [
            (tip.$1 + r, tip.$2),
            (tip.$1, tip.$2 + r),
            (tip.$1 - r, tip.$2),
            (tip.$1, tip.$2 - r)
          ],
          closed: true,
          filled: true,
          isCircle: true,
          center: tip,
          radius: r,
        );
      case PdfLineEnding.butt:
        final h = s * 0.45;
        return (
          vertices: [at(0, h), at(0, -h)],
          closed: false,
          filled: false,
          isCircle: false,
          center: tip,
          radius: 0,
        );
      case PdfLineEnding.slash:
        // a short line ~30° clockwise from perpendicular (60° from the
        // line itself): rotate the line direction u by 60° CCW
        final h = s * 0.5;
        const c = 0.5, sn = 0.8660254037844387; // cos 60°, sin 60°
        final sx = ux * c - uy * sn, sy = ux * sn + uy * c;
        return (
          vertices: [
            (tip.$1 + sx * h, tip.$2 + sy * h),
            (tip.$1 - sx * h, tip.$2 - sy * h),
          ],
          closed: false,
          filled: false,
          isCircle: false,
          center: tip,
          radius: 0,
        );
      case PdfLineEnding.none:
        return null;
    }
  }

  void _drawEnding(ContentWriter w, PdfLineEnding kind, (double, double) tip,
      (double, double) from, int color, double strokeWidth) {
    final shape = _endingPath(kind, tip, from, strokeWidth);
    if (shape == null) return;
    if (shape.isCircle) {
      _drawCircle(w, shape.center, shape.radius);
      w
        ..fillColor(color)
        ..fill();
      return;
    }
    w.moveTo(shape.vertices.first.$1, shape.vertices.first.$2);
    for (final (x, y) in shape.vertices.skip(1)) {
      w.lineTo(x, y);
    }
    if (shape.filled) {
      w
        ..closePath()
        ..fillColor(color)
        ..fill();
    } else {
      if (shape.closed) w.closePath();
      w
        ..strokeColor(color)
        ..lineWidth(strokeWidth)
        ..lineCap(0)
        ..stroke();
    }
  }

  /// Appends a circle of [radius] about [center] as four cubic Béziers.
  void _drawCircle(ContentWriter w, (double, double) center, double radius) {
    const k = 0.5522847498307936; // 4/3·(√2−1)
    final cx = center.$1, cy = center.$2, r = radius, kr = k * radius;
    w
      ..moveTo(cx + r, cy)
      ..curveTo(cx + r, cy + kr, cx + kr, cy + r, cx, cy + r)
      ..curveTo(cx - kr, cy + r, cx - r, cy + kr, cx - r, cy)
      ..curveTo(cx - r, cy - kr, cx - kr, cy - r, cx, cy - r)
      ..curveTo(cx + kr, cy - r, cx + r, cy - kr, cx + r, cy);
  }

  /// The extreme points an ending [kind] reaches at [tip] (line arriving
  /// from [from]) — fed into [_pointBounds] so the appearance /Rect and
  /// BBox cover the ending, not just the line.
  List<(double, double)> _endingExtent(PdfLineEnding kind, (double, double) tip,
      (double, double) from, double strokeWidth) {
    final shape = _endingPath(kind, tip, from, strokeWidth);
    if (shape == null) return const [];
    return [tip, ...shape.vertices];
  }

  PdfRect _pointBounds(List<(double, double)> points, double pad) {
    if (points.isEmpty) {
      throw ArgumentError.value(points, 'points', 'must be non-empty');
    }
    var left = points.first.$1;
    var right = points.first.$1;
    var bottom = points.first.$2;
    var top = points.first.$2;
    for (final (x, y) in points.skip(1)) {
      if (x < left) left = x;
      if (x > right) right = x;
      if (y < bottom) bottom = y;
      if (y > top) top = y;
    }
    final inset = math.max(1.0, pad / 2 + 1);
    return PdfRect(left - inset, bottom - inset, right + inset, top + inset);
  }

  /// The common annotation dictionary: /C carries [color], /F sets Print
  /// so the annotation survives printing and flattening.
  CosDictionary _markupDict(String subtype, PdfRect rect, int color,
      String? contents, String? author) {
    final dict = CosDictionary({
      'Type': const CosName('Annot'),
      'Subtype': CosName(subtype),
      'Rect': _rectArray(rect),
      'F': const CosInteger(4),
      'C': CosArray([
        for (final c in ContentWriter.rgbComponents(color)) CosReal(c),
      ]),
    });
    if (contents != null) dict['Contents'] = CosString.fromText(contents);
    if (author != null) dict['T'] = CosString.fromText(author);
    return dict;
  }

  /// Wraps the annotation content in a Form XObject whose BBox is the
  /// annotation rect in page coordinates — the §12.5.5 algorithm then maps
  /// it onto /Rect as the identity.
  CosStream _form(PdfRect bbox, ContentWriter content,
      {CosDictionary? resources}) {
    final bytes = content.takeBytes();
    final dict = CosDictionary({
      'Type': const CosName('XObject'),
      'Subtype': const CosName('Form'),
      'BBox': _rectArray(bbox),
      'Length': CosInteger(bytes.length),
    });
    if (resources != null) dict['Resources'] = resources;
    return CosStream(dict, bytes);
  }

  /// Stages [annot] (with its appearance [form]) and links it into the
  /// page's /Annots array.
  ///
  /// Every created annotation gets an /NM (§12.5.2): [name] when given,
  /// else a generated UUID — the durable identity that survives slot
  /// shifts and revisions (see [PdfAnnotation.name]).
  void _addAnnotation(int pageIndex, CosDictionary annot, CosStream form,
      {String? name}) {
    if (!annot.entries.containsKey('NM')) {
      annot['NM'] = CosString.fromText(name ?? _generateAnnotationName());
    }
    annot['AP'] = CosDictionary({'N': _updater.addObject(form)});
    final page = document.page(pageIndex);
    final annotRef = _updater.addObject(annot);

    final raw = page.dict['Annots'];
    final resolved = document.cos.resolve(raw);
    if (resolved is CosArray) {
      resolved.items.add(annotRef);
      if (raw is CosReference) {
        _updater.replaceObject(raw.objectNumber, resolved);
      } else {
        _updater.markChanged(page.dict);
      }
    } else {
      page.dict['Annots'] = CosArray([annotRef]);
      _updater.markChanged(page.dict);
    }
  }

  CosDictionary? _alphaState(double opacity, {bool multiply = false}) {
    if (opacity >= 1 && !multiply) return null;
    final dict = CosDictionary({
      'Type': const CosName('ExtGState'),
      'CA': CosReal(opacity),
      'ca': CosReal(opacity),
    });
    if (multiply) dict['BM'] = const CosName('Multiply');
    return dict;
  }

  CosDictionary? _resources(
      {CosDictionary? extGState, CosDictionary? font, CosDictionary? xObject}) {
    if (extGState == null && font == null && xObject == null) return null;
    final dict = CosDictionary();
    if (extGState != null) {
      dict['ExtGState'] = CosDictionary({'GS0': extGState});
    }
    if (font != null) dict['Font'] = font;
    if (xObject != null) dict['XObject'] = xObject;
    return dict;
  }

  /// A non-embedded base-14 Helvetica font with explicit /Widths, so both
  /// this renderer's substitution and other viewers space text correctly.
  CosDictionary _helvetica({bool bold = false, String name = 'Helv'}) =>
      _fontResource(name, bold ? 'Helvetica-Bold' : 'Helvetica',
          bold ? helveticaBoldWidths : helveticaWidths);

  /// Same, for any of the standard text fonts.
  CosDictionary _standardFont(PdfStandardFont font) =>
      _fontResource(font.resourceName, font.baseFont, font.widths);

  CosDictionary _fontResource(String name, String baseFont, List<int> widths) =>
      CosDictionary({
        name: CosDictionary({
          'Type': const CosName('Font'),
          'Subtype': const CosName('Type1'),
          'BaseFont': CosName(baseFont),
          'Encoding': const CosName('WinAnsiEncoding'),
          'FirstChar': const CosInteger(32),
          'LastChar': const CosInteger(126),
          'Widths': CosArray([for (final w in widths) CosInteger(w)]),
        }),
      });

  CosDictionary _borderStyle(double width, {List<double>? dashPattern}) {
    final dashed = dashPattern != null && dashPattern.isNotEmpty;
    final dict = CosDictionary({
      'Type': const CosName('Border'),
      'W': CosReal(width),
      'S': CosName(dashed ? 'D' : 'S'),
    });
    if (dashed) {
      dict['D'] = CosArray([for (final value in dashPattern) CosReal(value)]);
    }
    return dict;
  }

  CosArray _rectArray(PdfRect rect) => CosArray([
        CosReal(rect.left),
        CosReal(rect.bottom),
        CosReal(rect.right),
        CosReal(rect.top),
      ]);

  CosArray _pointArray(List<(double, double)> points) => CosArray([
        for (final (x, y) in points) ...[CosReal(x), CosReal(y)],
      ]);

  /// QuadPoints in the order real-world writers use (upper-left,
  /// upper-right, lower-left, lower-right per quad).
  CosArray _quadPoints(List<PdfRect> quads) => CosArray([
        for (final q in quads) ...[
          CosReal(q.left), CosReal(q.top), //
          CosReal(q.right), CosReal(q.top),
          CosReal(q.left), CosReal(q.bottom),
          CosReal(q.right), CosReal(q.bottom),
        ],
      ]);

  PdfRect _boundsOf(List<PdfRect> quads) {
    if (quads.isEmpty) {
      throw ArgumentError.value(quads, 'quads', 'must be non-empty');
    }
    var rect = quads.first;
    for (final q in quads.skip(1)) {
      rect = PdfRect(
        rect.left < q.left ? rect.left : q.left,
        rect.bottom < q.bottom ? rect.bottom : q.bottom,
        rect.right > q.right ? rect.right : q.right,
        rect.top > q.top ? rect.top : q.top,
      );
    }
    return rect;
  }

  /// Greedy word wrap with [font]'s metrics; a single word longer than
  /// [maxWidth] overflows (and is clipped by the appearance).
  List<String> _wrap(String text, double fontSize, double maxWidth,
      {PdfTextFont font = PdfStandardFont.helvetica}) {
    final lines = <String>[];
    for (final paragraph in text.split('\n')) {
      var line = '';
      for (final word in paragraph.split(' ')) {
        final candidate = line.isEmpty ? word : '$line $word';
        if (line.isNotEmpty && font.measure(candidate, fontSize) > maxWidth) {
          lines.add(line);
          line = word;
        } else {
          line = candidate;
        }
      }
      lines.add(line);
    }
    return lines;
  }

  PdfTextDirection _annotationTextDirection(PdfAnnotation annotation) {
    final q = document.cos.resolve(annotation.dict['Q']);
    if (q is CosInteger && q.value == 2) return PdfTextDirection.rtl;
    return PdfTextDirection.auto;
  }
}
