// Headless signature models: the data the editing controller and preferences
// carry, kept apart from the Material signature pad and library dialogs in
// editing_signature.dart (which re-exports these), so the controller's import
// closure stays free of flutter/material. See tool/check_design_imports.dart.

import 'dart:convert';
import 'dart:ui' show Color, Offset;

import 'package:flutter/widgets.dart' show BuildContext;

/// A hand-drawn signature, stored device-side and stamped onto pages as
/// an Ink annotation ([PdfEditingController.placeSignature]).
///
/// Strokes are normalized to the drawing's bounding box (0–1, y down,
/// like the pad it was drawn on); [aspect] preserves its proportions and
/// [strokeWidth] the pen it was drawn with.
/// Serializes to JSON so [PdfEditingPreferences] can persist it.
class PdfInkSignature {
  PdfInkSignature({
    required this.strokes,
    required this.pressures,
    required this.color,
    required this.aspect,
    this.strokeWidth = defaultStrokeWidth,
  }) : assert(strokes.length == pressures.length);

  /// The point width a signature is laid out at by default - see
  /// [PdfEditingController.placeSignature]'s `width`.
  ///
  /// [strokeWidth] is quoted at this size; every consumer scales the pen
  /// with the size it actually draws the signature at ([strokeWidthFor]),
  /// so a signature stamped small keeps its proportions.
  static const referenceWidth = 160.0;

  /// The pen a signature carries when it doesn't name one - what
  /// [PdfEditingController.placeSignature] used to hard-code (`width / 60`)
  /// before the pad had a thickness control, so signatures drawn by an
  /// older build still stamp exactly as they did.
  static const defaultStrokeWidth = referenceWidth / 60;

  /// The pen width slider's range in the pad, in points - the same range
  /// the toolbar's stroke-width slider offers.
  static const minStrokeWidth = 0.5;
  static const maxStrokeWidth = 12.0;

  /// Normalizes pad-space [strokes] (logical pixels, y down) to the
  /// drawing's bounding box. Returns null when nothing was drawn.
  /// [strokeWidth] is the pen the pad drew with, in points at
  /// [referenceWidth].
  static PdfInkSignature? fromPad(
    List<List<Offset>> strokes,
    List<List<double>?> pressures,
    Color color, {
    double strokeWidth = defaultStrokeWidth,
  }) {
    final points = strokes.expand((s) => s);
    if (points.isEmpty) return null;
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final p in points) {
      if (p.dx < minX) minX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy > maxY) maxY = p.dy;
    }
    // a dot or a perfectly straight line still needs a finite box
    final width = (maxX - minX).clamp(1.0, double.infinity);
    final height = (maxY - minY).clamp(1.0, double.infinity);
    return PdfInkSignature(
      strokes: [
        for (final stroke in strokes)
          [
            for (final p in stroke)
              ((p.dx - minX) / width, (p.dy - minY) / height)
          ]
      ],
      pressures: [for (final p in pressures) p?.toList()],
      color: color.toARGB32() & 0xFFFFFF,
      aspect: width / height,
      strokeWidth: strokeWidth,
    );
  }

  /// Normalized points per stroke: 0–1 within the bounding box, y down.
  final List<List<(double, double)>> strokes;

  /// Per-point pressures paralleling [strokes]; null entries are strokes
  /// drawn without pressure (mouse, finger).
  final List<List<double>?> pressures;

  /// RGB ink color.
  final int color;

  /// Bounding-box width / height.
  final double aspect;

  /// Pen width in points, quoted at [referenceWidth]. Scale it with
  /// [strokeWidthFor] to draw the signature at any other size.
  final double strokeWidth;

  /// The pen width to draw this signature with when it is laid out
  /// [width] wide - points for a page, pixels for a raster; only the
  /// ratio to [referenceWidth] matters.
  double strokeWidthFor(double width) => strokeWidth * width / referenceWidth;

  String encode() => jsonEncode({
        'color': color,
        'aspect': aspect,
        'strokeWidth': strokeWidth,
        'strokes': [
          for (final stroke in strokes)
            [
              for (final (x, y) in stroke) ...[x, y]
            ]
        ],
        'pressures': pressures,
      });

  /// Parses [encode]'s output; null for anything malformed.
  static PdfInkSignature? decode(String json) {
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      final strokes = [
        for (final flat in map['strokes'] as List)
          [
            for (var i = 0; i + 1 < (flat as List).length; i += 2)
              ((flat[i] as num).toDouble(), (flat[i + 1] as num).toDouble())
          ]
      ];
      final pressures = [
        for (final p in map['pressures'] as List)
          p == null ? null : [for (final v in p as List) (v as num).toDouble()]
      ];
      if (strokes.length != pressures.length) return null;
      // written since the pad grew a thickness control; anything older (or
      // nonsensical) falls back to the pen those signatures were stamped with
      final width = (map['strokeWidth'] as num?)?.toDouble();
      return PdfInkSignature(
        strokes: strokes,
        pressures: pressures,
        color: map['color'] as int,
        aspect: (map['aspect'] as num).toDouble(),
        strokeWidth: width != null && width.isFinite && width > 0
            ? width
            : defaultStrokeWidth,
      );
    } catch (_) {
      return null;
    }
  }
}

/// A named signature in the device-side signature library.
///
/// [id] remains stable when the entry is renamed or redrawn, which lets the
/// active choice survive both operations and app restarts.
class PdfSavedSignature {
  const PdfSavedSignature({
    required this.id,
    required this.name,
    required this.signature,
  });

  factory PdfSavedSignature.create({
    required String name,
    required PdfInkSignature signature,
  }) =>
      PdfSavedSignature(
        id: _nextSignatureId(),
        name: name,
        signature: signature,
      );

  final String id;
  final String name;
  final PdfInkSignature signature;

  PdfSavedSignature copyWith({String? name, PdfInkSignature? signature}) =>
      PdfSavedSignature(
        id: id,
        name: name ?? this.name,
        signature: signature ?? this.signature,
      );

  String encode() => jsonEncode({
        'v': 1,
        'id': id,
        'name': name,
        'signature': jsonDecode(signature.encode()),
      });

  static PdfSavedSignature? decode(String source) {
    try {
      final map = jsonDecode(source);
      if (map is! Map<String, dynamic> || map['v'] != 1) return null;
      final id = map['id'];
      final name = map['name'];
      final signature = map['signature'];
      if (id is! String ||
          id.isEmpty ||
          name is! String ||
          name.trim().isEmpty ||
          signature is! Map) {
        return null;
      }
      final decoded = PdfInkSignature.decode(jsonEncode(signature));
      if (decoded == null) return null;
      return PdfSavedSignature(id: id, name: name, signature: decoded);
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is PdfSavedSignature && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

int _signatureIdCounter = 0;

String _nextSignatureId() {
  final micros = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final sequence = (_signatureIdCounter++).toRadixString(36);
  return 'signature-$micros-$sequence';
}

/// Opens a full colour picker over the signature pad, seeded with the
/// pad's current ink; resolves to the chosen colour or null when
/// dismissed. The stock chrome wires this to `pickEditingColor` so the
/// pad's picker offers the same recents and document colours as every
/// other colour in the editor.
typedef PdfSignatureColorPicker = Future<Color?> Function(
    BuildContext context, Color initial);

/// What a [PdfTrackpadSignatureEvent] reports.
enum PdfTrackpadSignaturePhase {
  /// A finger landed on the trackpad: the pen goes down.
  down,

  /// The drawing finger moved.
  move,

  /// The drawing finger lifted: the pen comes up.
  up,

  /// The user ended the capture (the host's "press any key" gesture).
  finish,
}

/// One sample from a [PdfTrackpadSignatureCapture]. [x] and [y] place the
/// drawing finger on the trackpad surface, 0–1 across its width and height
/// with y down; they are meaningless for [PdfTrackpadSignaturePhase.finish].
class PdfTrackpadSignatureEvent {
  const PdfTrackpadSignatureEvent(this.phase, {this.x = 0, this.y = 0});

  final PdfTrackpadSignaturePhase phase;
  final double x;
  final double y;

  @override
  String toString() => 'PdfTrackpadSignatureEvent($phase, $x, $y)';
}

/// Draws a signature with a finger on the trackpad, the way Preview does:
/// the trackpad surface maps absolutely onto the signature pad, a finger
/// down is the pen down, and a key press ends the capture.
///
/// Absolute finger positions are a native affordance (AppKit's indirect
/// `NSTouch`es, Windows Precision Touchpad HID reports, Android's captured
/// `SOURCE_TOUCHPAD` events) that Flutter's pointer events don't carry, so
/// the host supplies the capture: listening to [capture] starts it (the host
/// grabs the trackpad and parks the cursor), cancelling the subscription or
/// the stream closing ends it. The pad itself ends the capture on any key
/// press or when the app loses focus, and ignores clicks while it runs (a
/// tap-to-click while dotting an "i" must not press a button), so a host
/// only has to stream touches. The DartPDF app installs its implementation
/// as [platform] at startup; with no capture installed, or when
/// [isAvailable] reports no trackpad, the pad simply doesn't offer the mode.
abstract class PdfTrackpadSignatureCapture {
  /// The capture [showPdfSignatureDialog] offers when it isn't handed one.
  static PdfTrackpadSignatureCapture? platform;

  /// Whether a trackpad is attached right now; asked each time the pad
  /// opens. Defaults to true.
  Future<bool> isAvailable() async => true;

  /// Starts a capture on listen; see the class docs.
  Stream<PdfTrackpadSignatureEvent> capture();
}
