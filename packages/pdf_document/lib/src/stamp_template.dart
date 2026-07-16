import 'dart:convert';
import 'dart:typed_data';

import 'content_writer.dart';

/// Editable vector template for a reusable rubber stamp.
///
/// Coordinates are in template space with the origin at the top-left and y
/// growing downward. When a template is placed on a PDF page, it is scaled into
/// the stamp annotation's visual rectangle and compiled into a single /Stamp
/// appearance.
class PdfStampTemplate {
  const PdfStampTemplate({
    required this.width,
    required this.height,
    required this.components,
  });

  /// Builds the legacy text-stamp look as editable parts: a border box and a
  /// centered caption. This is the starting point for the stamp editor.
  factory PdfStampTemplate.text(String text, int color) => PdfStampTemplate(
        width: 240,
        height: 96,
        components: [
          PdfStampTemplateComponent.rectangle(
            x: 6,
            y: 16,
            width: 228,
            height: 64,
            color: color,
            strokeWidth: 2,
            radius: 8,
          ),
          PdfStampTemplateComponent.text(
            x: 20,
            y: 30,
            width: 200,
            height: 36,
            text: text,
            color: color,
            fontSize: 26,
            font: PdfStandardFont.helveticaBold,
          ),
        ],
      );

  final double width;
  final double height;
  final List<PdfStampTemplateComponent> components;

  bool get isValid => width > 0 && height > 0 && components.isNotEmpty;

  /// Returns a copy with all text-component `{{field}}` placeholders resolved
  /// from [values]. Field names are matched case-insensitively after trimming.
  ///
  /// Unknown placeholders stay in the text, which makes missing app data
  /// visible instead of silently producing an incomplete stamp.
  PdfStampTemplate resolveText(Map<String, String> values) {
    if (values.isEmpty) return this;
    var changed = false;
    final resolved = [
      for (final component in components)
        if (component.type == PdfStampTemplateComponentType.text)
          () {
            final text = pdfResolveStampTemplateText(component.text, values);
            if (text != component.text) changed = true;
            return component.copyWith(text: text);
          }()
        else
          component,
    ];
    if (!changed) return this;
    return PdfStampTemplate(
      width: width,
      height: height,
      components: List.unmodifiable(resolved),
    );
  }

  Map<String, Object?> toJson() => {
        'w': width,
        'h': height,
        'components': [for (final c in components) c.toJson()],
      };

  static PdfStampTemplate? fromJson(Object? value) {
    if (value is! Map) return null;
    final width = _num(value['w']);
    final height = _num(value['h']);
    final rawComponents = value['components'];
    if (width == null ||
        height == null ||
        width <= 0 ||
        height <= 0 ||
        rawComponents is! List) {
      return null;
    }
    final components = [
      for (final item in rawComponents)
        if (PdfStampTemplateComponent.fromJson(item) case final component?)
          component,
    ];
    if (components.isEmpty) return null;
    return PdfStampTemplate(
      width: width,
      height: height,
      components: List.unmodifiable(components),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PdfStampTemplate &&
      other.width == width &&
      other.height == height &&
      _listEquals(other.components, components);

  @override
  int get hashCode => Object.hash(width, height, Object.hashAll(components));
}

enum PdfStampTemplateComponentType {
  text,
  rectangle,
  ellipse,
  image,
  signature;

  static PdfStampTemplateComponentType? fromName(Object? value) {
    if (value is! String) return null;
    for (final type in values) {
      if (type.name == value) return type;
    }
    return null;
  }
}

class PdfStampTemplateComponent {
  const PdfStampTemplateComponent({
    required this.type,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.text = '',
    required this.color,
    this.fillColor,
    this.strokeWidth = 2,
    this.radius = 0,
    this.fontSize,
    this.font = PdfStandardFont.helveticaBold,
    this.imageBytes,
    this.strokes = const [],
    this.pressures = const [],
  });

  factory PdfStampTemplateComponent.text({
    required double x,
    required double y,
    required double width,
    required double height,
    required String text,
    required int color,
    double? fontSize,
    PdfStandardFont font = PdfStandardFont.helveticaBold,
  }) =>
      PdfStampTemplateComponent(
        type: PdfStampTemplateComponentType.text,
        x: x,
        y: y,
        width: width,
        height: height,
        text: text,
        color: color,
        fontSize: fontSize,
        font: font,
      );

  factory PdfStampTemplateComponent.rectangle({
    required double x,
    required double y,
    required double width,
    required double height,
    required int color,
    int? fillColor,
    double strokeWidth = 2,
    double radius = 0,
  }) =>
      PdfStampTemplateComponent(
        type: PdfStampTemplateComponentType.rectangle,
        x: x,
        y: y,
        width: width,
        height: height,
        color: color,
        fillColor: fillColor,
        strokeWidth: strokeWidth,
        radius: radius,
      );

  factory PdfStampTemplateComponent.ellipse({
    required double x,
    required double y,
    required double width,
    required double height,
    required int color,
    int? fillColor,
    double strokeWidth = 2,
  }) =>
      PdfStampTemplateComponent(
        type: PdfStampTemplateComponentType.ellipse,
        x: x,
        y: y,
        width: width,
        height: height,
        color: color,
        fillColor: fillColor,
        strokeWidth: strokeWidth,
      );

  factory PdfStampTemplateComponent.image({
    required double x,
    required double y,
    required double width,
    required double height,
    required Uint8List imageBytes,
  }) =>
      PdfStampTemplateComponent(
        type: PdfStampTemplateComponentType.image,
        x: x,
        y: y,
        width: width,
        height: height,
        color: 0,
        imageBytes: Uint8List.fromList(imageBytes),
      );

  factory PdfStampTemplateComponent.signature({
    required double x,
    required double y,
    required double width,
    required double height,
    required List<List<(double, double)>> strokes,
    List<List<double>?> pressures = const [],
    required int color,
    double strokeWidth = 2,
  }) {
    _validateSignatureStrokes(strokes, pressures);
    return PdfStampTemplateComponent(
      type: PdfStampTemplateComponentType.signature,
      x: x,
      y: y,
      width: width,
      height: height,
      color: color,
      strokeWidth: strokeWidth,
      strokes: _copyStrokes(strokes),
      pressures: pressures.isEmpty
          ? [for (final _ in strokes) null]
          : _copyPressures(pressures),
    );
  }

  final PdfStampTemplateComponentType type;
  final double x;
  final double y;
  final double width;
  final double height;
  final String text;
  final int color;
  final int? fillColor;
  final double strokeWidth;
  final double radius;
  final double? fontSize;
  final PdfStandardFont font;
  final Uint8List? imageBytes;
  final List<List<(double, double)>> strokes;
  final List<List<double>?> pressures;

  PdfStampTemplateComponent copyWith({
    PdfStampTemplateComponentType? type,
    double? x,
    double? y,
    double? width,
    double? height,
    String? text,
    int? color,
    Object? fillColor = _keep,
    double? strokeWidth,
    double? radius,
    Object? fontSize = _keep,
    PdfStandardFont? font,
    Object? imageBytes = _keep,
    Object? strokes = _keep,
    Object? pressures = _keep,
  }) =>
      PdfStampTemplateComponent(
        type: type ?? this.type,
        x: x ?? this.x,
        y: y ?? this.y,
        width: width ?? this.width,
        height: height ?? this.height,
        text: text ?? this.text,
        color: color ?? this.color,
        fillColor: fillColor == _keep ? this.fillColor : fillColor as int?,
        strokeWidth: strokeWidth ?? this.strokeWidth,
        radius: radius ?? this.radius,
        fontSize: fontSize == _keep ? this.fontSize : fontSize as double?,
        font: font ?? this.font,
        imageBytes: imageBytes == _keep
            ? this.imageBytes
            : imageBytes == null
                ? null
                : Uint8List.fromList(imageBytes as Uint8List),
        strokes: strokes == _keep
            ? this.strokes
            : _copyStrokes(strokes as List<List<(double, double)>>),
        pressures: pressures == _keep
            ? this.pressures
            : _copyPressures(pressures as List<List<double>?>),
      );

  Map<String, Object?> toJson() => {
        'type': type.name,
        'x': x,
        'y': y,
        'w': width,
        'h': height,
        if (text.isNotEmpty) 'text': text,
        'color': color,
        if (fillColor != null) 'fill': fillColor,
        'stroke': strokeWidth,
        if (radius != 0) 'radius': radius,
        if (fontSize != null) 'fontSize': fontSize,
        if (font != PdfStandardFont.helveticaBold) 'font': font.name,
        if (imageBytes != null) 'image': base64Encode(imageBytes!),
        if (strokes.isNotEmpty) 'strokes': _strokesToJson(strokes),
        if (pressures.isNotEmpty) 'pressures': _pressuresToJson(pressures),
      };

  static PdfStampTemplateComponent? fromJson(Object? value) {
    if (value is! Map) return null;
    final type = PdfStampTemplateComponentType.fromName(value['type']);
    final x = _num(value['x']);
    final y = _num(value['y']);
    final width = _num(value['w']);
    final height = _num(value['h']);
    final color = value['color'];
    if (type == null ||
        x == null ||
        y == null ||
        width == null ||
        height == null ||
        width <= 0 ||
        height <= 0 ||
        (color is! int && type != PdfStampTemplateComponentType.image)) {
      return null;
    }
    final fill = value['fill'];
    final stroke = _num(value['stroke']) ?? 2;
    final radius = _num(value['radius']) ?? 0;
    final fontSize = _num(value['fontSize']);
    final font = value['font'] is String
        ? PdfStandardFont.values.asNameMap()[value['font']] ??
            PdfStandardFont.helveticaBold
        : PdfStandardFont.helveticaBold;
    Uint8List? imageBytes;
    if (value['image'] is String) {
      try {
        imageBytes = base64Decode(value['image'] as String);
      } catch (_) {
        return null;
      }
    }
    if (type == PdfStampTemplateComponentType.image && imageBytes == null) {
      return null;
    }
    final strokes = _strokesFromJson(value['strokes']);
    if (type == PdfStampTemplateComponentType.signature &&
        (strokes == null || strokes.isEmpty)) {
      return null;
    }
    final pressures = _pressuresFromJson(value['pressures'], strokes);
    if (type == PdfStampTemplateComponentType.signature && pressures == null) {
      return null;
    }
    return PdfStampTemplateComponent(
      type: type,
      x: x,
      y: y,
      width: width,
      height: height,
      text: value['text'] is String ? value['text'] as String : '',
      color: color is int ? color : 0,
      fillColor: fill is int ? fill : null,
      strokeWidth: stroke,
      radius: radius,
      fontSize: fontSize,
      font: font,
      imageBytes: imageBytes,
      strokes: strokes ?? const [],
      pressures: pressures ?? const [],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PdfStampTemplateComponent &&
      other.type == type &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height &&
      other.text == text &&
      other.color == color &&
      other.fillColor == fillColor &&
      other.strokeWidth == strokeWidth &&
      other.radius == radius &&
      other.fontSize == fontSize &&
      other.font == font &&
      _byteListEquals(other.imageBytes, imageBytes) &&
      _strokesEqual(other.strokes, strokes) &&
      _pressuresEqual(other.pressures, pressures);

  @override
  int get hashCode => Object.hash(
      type,
      x,
      y,
      width,
      height,
      text,
      color,
      fillColor,
      strokeWidth,
      radius,
      fontSize,
      font,
      imageBytes == null ? null : Object.hashAll(imageBytes!),
      Object.hashAll(strokes.map((stroke) => Object.hashAll(stroke))),
      Object.hashAll(pressures.map(
          (pressure) => pressure == null ? null : Object.hashAll(pressure))));
}

const _keep = Object();

double? _num(Object? value) => switch (value) {
      int v => v.toDouble(),
      double v => v,
      _ => null,
    };

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _byteListEquals(Uint8List? a, Uint8List? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

List<List<(double, double)>> _copyStrokes(
        List<List<(double, double)>> strokes) =>
    [
      for (final stroke in strokes) [for (final (x, y) in stroke) (x, y)]
    ];

List<List<double>?> _copyPressures(List<List<double>?> pressures) => [
      for (final pressure in pressures) pressure == null ? null : [...pressure]
    ];

void _validateSignatureStrokes(
    List<List<(double, double)>> strokes, List<List<double>?> pressures) {
  if (strokes.isEmpty || strokes.any((stroke) => stroke.isEmpty)) {
    throw ArgumentError.value(strokes, 'strokes', 'must be non-empty');
  }
  if (pressures.isEmpty) return;
  if (pressures.length != strokes.length) {
    throw ArgumentError.value(
        pressures, 'pressures', 'must parallel strokes point for point');
  }
  for (var i = 0; i < strokes.length; i++) {
    final pressure = pressures[i];
    if (pressure != null && pressure.length != strokes[i].length) {
      throw ArgumentError.value(
          pressures, 'pressures', 'must parallel strokes point for point');
    }
  }
}

List<Object> _strokesToJson(List<List<(double, double)>> strokes) => [
      for (final stroke in strokes)
        [
          for (final (x, y) in stroke) ...[x, y]
        ]
    ];

List<Object?> _pressuresToJson(List<List<double>?> pressures) => [
      for (final pressure in pressures) pressure == null ? null : [...pressure]
    ];

List<List<(double, double)>>? _strokesFromJson(Object? value) {
  if (value is! List) return null;
  final strokes = <List<(double, double)>>[];
  for (final rawStroke in value) {
    if (rawStroke is! List || rawStroke.isEmpty || rawStroke.length.isOdd) {
      return null;
    }
    final stroke = <(double, double)>[];
    for (var i = 0; i + 1 < rawStroke.length; i += 2) {
      final x = _num(rawStroke[i]);
      final y = _num(rawStroke[i + 1]);
      if (x == null || y == null) return null;
      stroke.add((x, y));
    }
    strokes.add(stroke);
  }
  return strokes;
}

List<List<double>?>? _pressuresFromJson(
    Object? value, List<List<(double, double)>>? strokes) {
  if (value == null) {
    return strokes == null ? const [] : [for (final _ in strokes) null];
  }
  if (value is! List || strokes == null || value.length != strokes.length) {
    return null;
  }
  final pressures = <List<double>?>[];
  for (var i = 0; i < value.length; i++) {
    final rawPressure = value[i];
    if (rawPressure == null) {
      pressures.add(null);
      continue;
    }
    if (rawPressure is! List || rawPressure.length != strokes[i].length) {
      return null;
    }
    final pressure = <double>[];
    for (final raw in rawPressure) {
      final p = _num(raw);
      if (p == null) return null;
      pressure.add(p);
    }
    pressures.add(pressure);
  }
  return pressures;
}

bool _strokesEqual(
    List<List<(double, double)>> a, List<List<(double, double)>> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].length != b[i].length) return false;
    for (var j = 0; j < a[i].length; j++) {
      if (a[i][j] != b[i][j]) return false;
    }
  }
  return true;
}

bool _pressuresEqual(List<List<double>?> a, List<List<double>?> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    final pa = a[i], pb = b[i];
    if (pa == null || pb == null) {
      if (pa != pb) return false;
      continue;
    }
    if (pa.length != pb.length) return false;
    for (var j = 0; j < pa.length; j++) {
      if (pa[j] != pb[j]) return false;
    }
  }
  return true;
}

/// Resolves `{{field}}` placeholders in stamp text from [values].
///
/// Field names are matched case-insensitively after trimming, so
/// `{{ Date }}` and `{{date}}` address the same value. Unknown placeholders
/// are preserved.
String pdfResolveStampTemplateText(String text, Map<String, String> values) {
  if (values.isEmpty || !text.contains('{{')) return text;
  final normalized = <String, String>{
    for (final entry in values.entries)
      if (entry.key.trim().isNotEmpty)
        entry.key.trim().toLowerCase(): entry.value,
  };
  if (normalized.isEmpty) return text;
  return text.replaceAllMapped(RegExp(r'\{\{\s*([^{}]+?)\s*\}\}'), (match) {
    final key = match.group(1)!.trim().toLowerCase();
    return normalized[key] ?? match.group(0)!;
  });
}
