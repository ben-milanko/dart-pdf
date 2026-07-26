part of 'annotation.dart';

/// How resizing an annotation updates its appearance.
enum PdfAnnotationResizeBehavior {
  /// The subtype is not supported by the editor's resize operation.
  none,

  /// Scale the existing appearance and coordinate arrays.
  stretch,

  /// Rebuild a shape at the new bounds, preserving stroke width and fill.
  regenerateShape,

  /// Re-wrap free text at the new width, preserving its font size.
  reflowText,

  /// Rebuild line-family geometry and its optional measurement caption.
  regenerateLine,
}

/// The annotation style values that editing controls should display.
///
/// Values are resolved once by [PdfAnnotationBehavior]. In particular,
/// [opacity] may require decoding the normal appearance stream, and free-text
/// colors come from /DA rather than the annotation's generic /C entry.
class PdfAnnotationStyle {
  const PdfAnnotationStyle({
    required this.color,
    required this.fillColor,
    required this.borderColor,
    required this.strokeWidth,
    required this.opacity,
    required this.freeText,
  });

  /// Primary tint: text color for FreeText, stroke/tint for other subtypes.
  final int? color;

  /// Interior/background color, or null when absent or unsupported.
  final int? fillColor;

  /// FreeText border color. Other subtypes use [color] for their stroke.
  final int? borderColor;

  /// /BS /W when present.
  final double? strokeWidth;

  /// Alpha baked into the normal appearance, defaulting to 1.
  final double opacity;

  /// Parsed FreeText /DA and box style, when usable.
  final PdfFreeTextStyle? freeText;
}

/// One authoritative view of PDF-semantic annotation behavior.
///
/// Material labels, icons, and tool presentation deliberately stay in the
/// Flutter package. This descriptor owns only facts derived from the PDF
/// subtype and dictionary: editing gates, style sources, and whether a resize
/// can regenerate an equivalent appearance.
class PdfAnnotationBehavior {
  PdfAnnotationBehavior._(this.annotation);

  final PdfAnnotation annotation;

  String get subtype => annotation.subtype;

  /// Whether the general annotation selection tool may select this subtype.
  /// Links and widgets have their own interaction paths; popups belong to
  /// their parent annotation.
  bool get selectable => switch (subtype) {
        'Popup' || 'Link' || 'Widget' => false,
        _ => true,
      };

  /// Whether the editor knows how to keep this subtype's geometry coherent
  /// when /Rect changes.
  bool get resizable => switch (subtype) {
        'Square' ||
        'Circle' ||
        'FreeText' ||
        'Stamp' ||
        'Ink' ||
        'Line' ||
        'PolyLine' ||
        'Polygon' =>
          true,
        _ => false,
      };

  /// Whether rotation can ride this annotation's normal appearance matrix.
  late final bool rotatable = resizable && annotation.normalAppearance != null;

  /// Whether the editing controller can rewrite the annotation's text.
  bool get textEditable => switch (subtype) {
        'FreeText' || 'Stamp' || 'Text' => true,
        _ => false,
      };

  /// A line, polyline, or polygon whose defining points are independently
  /// editable by the overlay.
  bool get lineFamily => switch (subtype) {
        'Line' || 'PolyLine' || 'Polygon' => true,
        _ => false,
      };

  /// Whether the restyle API's fill argument applies to this subtype.
  bool get supportsFill => switch (subtype) {
        'Square' || 'Circle' || 'Polygon' || 'FreeText' => true,
        _ => false,
      };

  /// Whether a stroke-width control applies to this subtype.
  bool get supportsStrokeWidth => switch (subtype) {
        'Square' ||
        'Circle' ||
        'Line' ||
        'PolyLine' ||
        'Polygon' ||
        'Ink' =>
          true,
        _ => false,
      };

  /// Whether /BS /D is an editable line style for this subtype.
  bool get supportsLineStyle => switch (subtype) {
        'Square' || 'Circle' || 'Line' || 'PolyLine' || 'Polygon' => true,
        _ => false,
      };

  /// Whether line-ending controls apply to this subtype.
  bool get supportsLineEndings => subtype == 'Line' || subtype == 'PolyLine';

  /// Whether the editor can faithfully rebuild this subtype with a new alpha.
  bool get supportsOpacity => switch (subtype) {
        'Square' ||
        'Circle' ||
        'Line' ||
        'PolyLine' ||
        'Polygon' ||
        'Ink' ||
        'Highlight' ||
        'Underline' ||
        'StrikeOut' ||
        'Squiggly' ||
        'Stamp' =>
          true,
        _ => false,
      };

  /// Whether a stroke/tint colour control applies. False for image stamps -
  /// a pasted picture has no colour a /C would tint, so the swatch is hidden
  /// while opacity stays editable.
  bool get supportsColor => canRestyle && !isImageStamp;

  /// Whether this /Stamp is a placed raster picture (see
  /// [PdfAnnotation.isImageStamp]) rather than a drawn text or template
  /// stamp, so the restyle path re-bakes only its alpha over the same image.
  bool get isImageStamp => annotation.isImageStamp;

  late final PdfFreeTextStyle? _freeTextStyle =
      subtype == 'FreeText' ? annotation.freeTextStyle : null;

  late final PdfStandardFont? standardTextFont = _freeTextStyle == null
      ? null
      : PdfStandardFont.tryFromName(_freeTextStyle.fontName);

  /// Whether the box's /DA font resolves to an embedded (Type0-with-program)
  /// face in its appearance resources. Cheap COS inspection - enough to know
  /// a resize can re-wrap the box without parsing the whole font program
  /// (the editor recovers the actual font for that). Lets embedded/bundled
  /// free-text boxes reflow on resize instead of stretching their glyphs.
  late final bool hasEmbeddedTextFont = _hasEmbeddedTextFont();

  bool _hasEmbeddedTextFont() {
    if (subtype != 'FreeText') return false;
    final cos = annotation.document.cos;
    final form = annotation.normalAppearance;
    if (form == null) return false;
    final res = cos.resolve(form.dictionary['Resources']);
    if (res is! CosDictionary) return false;
    final fonts = cos.resolve(res['Font']);
    if (fonts is! CosDictionary) return false;
    final name =
        _daTfRe.firstMatch(annotation.defaultAppearance ?? '')?.group(1);
    final dict = name != null ? cos.resolve(fonts[name]) : null;
    if (dict is! CosDictionary) return false;
    final sub = cos.resolve(dict['Subtype']);
    if (sub is! CosName || sub.value != 'Type0') return false;
    final desc = cos.resolve(dict['DescendantFonts']);
    if (desc is! CosArray || desc.items.isEmpty) return false;
    final cid = cos.resolve(desc.items.first);
    if (cid is! CosDictionary) return false;
    final fd = cos.resolve(cid['FontDescriptor']);
    if (fd is! CosDictionary) return false;
    return cos.resolve(fd['FontFile2']) is CosStream ||
        cos.resolve(fd['FontFile3']) is CosStream;
  }

  late final List<PdfRect>? markupQuads = _readAxisAlignedQuads();

  /// Whether the editor has enough well-formed source data to regenerate an
  /// equivalent appearance for an in-place restyle.
  late final bool canRestyle = switch (subtype) {
    'Square' ||
    'Circle' =>
      annotation.normalAppearance != null && annotation.dict['BE'] == null,
    'Line' => annotation.normalAppearance != null && annotation.line != null,
    'PolyLine' => annotation.normalAppearance != null &&
        (annotation.vertices?.length ?? 0) >= 2,
    'Polygon' => annotation.normalAppearance != null &&
        (annotation.vertices?.length ?? 0) >= 3,
    'FreeText' =>
      annotation.normalAppearance != null && standardTextFont != null,
    'Ink' => annotation.inkList?.isNotEmpty ?? false,
    'Highlight' ||
    'Underline' ||
    'StrikeOut' ||
    'Squiggly' =>
      markupQuads != null,
    'Text' => annotation.normalAppearance != null,
    // A text check-mark stamp restyles by redrawing from its /Contents; an
    // image stamp restyles by re-baking its alpha over the same picture.
    'Stamp' => annotation.normalAppearance != null &&
        ((annotation.contents?.isNotEmpty ?? false) || isImageStamp),
    _ => false,
  };

  /// Appearance strategy used by both the document editor and live preview.
  late final PdfAnnotationResizeBehavior resizeBehavior = _resizeBehavior();

  /// Authoritative style values for UI controls and mutation defaults.
  late final PdfAnnotationStyle style = PdfAnnotationStyle(
    color: subtype == 'FreeText'
        ? _freeTextStyle?.color ?? annotation.color
        : annotation.color,
    fillColor: subtype == 'FreeText'
        ? _freeTextStyle?.fillColor
        : supportsFill
            ? annotation.interiorColor
            : null,
    borderColor: _freeTextStyle?.borderColor,
    strokeWidth: annotation.borderWidth,
    opacity: annotation.appearanceOpacity,
    freeText: _freeTextStyle,
  );

  PdfAnnotationResizeBehavior _resizeBehavior() {
    if (!resizable) return PdfAnnotationResizeBehavior.none;
    final form = annotation.normalAppearance;
    if (form == null) return PdfAnnotationResizeBehavior.stretch;
    switch (subtype) {
      case 'Square' || 'Circle':
        if (annotation.dict['BE'] != null) {
          return PdfAnnotationResizeBehavior.stretch;
        }
        final width = annotation.borderWidth ?? 1;
        final stroke = width > 0 ? annotation.color : null;
        if (stroke == null && annotation.interiorColor == null) {
          return PdfAnnotationResizeBehavior.stretch;
        }
        return PdfAnnotationResizeBehavior.regenerateShape;
      case 'FreeText':
        return standardTextFont == null && !hasEmbeddedTextFont
            ? PdfAnnotationResizeBehavior.stretch
            : PdfAnnotationResizeBehavior.reflowText;
      case 'Line':
        return annotation.line == null
            ? PdfAnnotationResizeBehavior.stretch
            : PdfAnnotationResizeBehavior.regenerateLine;
      case 'PolyLine' || 'Polygon':
        return (annotation.vertices?.isEmpty ?? true)
            ? PdfAnnotationResizeBehavior.stretch
            : PdfAnnotationResizeBehavior.regenerateLine;
      default:
        return PdfAnnotationResizeBehavior.stretch;
    }
  }

  List<PdfRect>? _readAxisAlignedQuads() {
    if (subtype != 'Highlight' &&
        subtype != 'Underline' &&
        subtype != 'StrikeOut' &&
        subtype != 'Squiggly') {
      return null;
    }
    final cos = annotation.document.cos;
    final raw = cos.resolve(annotation.dict['QuadPoints']);
    if (raw is! CosArray || raw.length == 0 || raw.length % 8 != 0) {
      return null;
    }
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
    final quads = <PdfRect>[];
    for (var i = 0; i < values.length; i += 8) {
      final xs = [values[i], values[i + 2], values[i + 4], values[i + 6]];
      final ys = [values[i + 1], values[i + 3], values[i + 5], values[i + 7]];
      final left = xs.reduce(math.min);
      final right = xs.reduce(math.max);
      final bottom = ys.reduce(math.min);
      final top = ys.reduce(math.max);
      // Preserve the editor's historical tolerance for real-world PDF
      // coordinate noise while rejecting genuinely rotated quads.
      const epsilon = 0.01;
      for (var p = 0; p < 4; p++) {
        final x = xs[p], y = ys[p];
        if (!((x - left).abs() <= epsilon || (x - right).abs() <= epsilon) ||
            !((y - bottom).abs() <= epsilon || (y - top).abs() <= epsilon)) {
          return null;
        }
      }
      quads.add(PdfRect(left, bottom, right, top));
    }
    return List.unmodifiable(quads);
  }
}
