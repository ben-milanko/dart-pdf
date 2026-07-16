import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:pdf_document/pdf_document.dart'
    show pdfInkCurveControls, pdfInkStrokeWidth;

/// A hand-drawn signature, stored device-side and stamped onto pages as
/// an Ink annotation ([PdfEditingController.placeSignature]).
///
/// Strokes are normalized to the drawing's bounding box (0–1, y down,
/// like the pad it was drawn on); [aspect] preserves its proportions.
/// Serializes to JSON so [PdfEditingPreferences] can persist it.
class PdfInkSignature {
  PdfInkSignature({
    required this.strokes,
    required this.pressures,
    required this.color,
    required this.aspect,
  }) : assert(strokes.length == pressures.length);

  /// Normalizes pad-space [strokes] (logical pixels, y down) to the
  /// drawing's bounding box. Returns null when nothing was drawn.
  static PdfInkSignature? fromPad(
    List<List<Offset>> strokes,
    List<List<double>?> pressures,
    Color color,
  ) {
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

  String encode() => jsonEncode({
        'color': color,
        'aspect': aspect,
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
      return PdfInkSignature(
        strokes: strokes,
        pressures: pressures,
        color: map['color'] as int,
        aspect: (map['aspect'] as num).toDouble(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Shows the signature pad dialog; resolves to the drawn signature, or
/// null on cancel.
Future<PdfInkSignature?> showPdfSignatureDialog(BuildContext context) =>
    showDialog<PdfInkSignature>(
      context: context,
      builder: (context) => const PdfSignatureDialog(),
    );

/// A dialog with a drawing pad for capturing a signature: draw with
/// mouse, finger, or stylus (pressure is recorded and rendered as
/// variable width, like the ink tool), pick an ink color, clear, done.
class PdfSignatureDialog extends StatefulWidget {
  const PdfSignatureDialog({super.key});

  @override
  State<PdfSignatureDialog> createState() => _PdfSignatureDialogState();
}

class _PdfSignatureDialogState extends State<PdfSignatureDialog> {
  static const _inks = [
    Color(0xFF000000),
    Color(0xFF1A3E8C),
    Color(0xFFB71C1C)
  ];

  final List<List<Offset>> _strokes = [];
  final List<List<double>?> _pressures = [];
  List<Offset>? _active;
  List<double>? _activePressures;
  double? _pointerPressure;
  Color _ink = _inks.first;

  bool get _isEmpty => _strokes.isEmpty && _active == null;

  /// 0–1 within the device's range; null when the device has none
  /// (mouse, finger) - same convention as the ink overlay.
  static double? _normalizedPressure(PointerEvent event) {
    if (event.pressureMax <= event.pressureMin) return null;
    return ((event.pressure - event.pressureMin) /
            (event.pressureMax - event.pressureMin))
        .clamp(0.0, 1.0);
  }

  void _panStart(DragStartDetails details) {
    final pressure = _pointerPressure;
    setState(() {
      _active = [details.localPosition];
      _activePressures = pressure == null ? null : [pressure];
    });
  }

  void _panUpdate(DragUpdateDetails details) {
    setState(() {
      _active!.add(details.localPosition);
      _activePressures?.add(_pointerPressure ?? _activePressures!.last);
    });
  }

  void _panEnd(DragEndDetails details) {
    final stroke = _active;
    if (stroke == null) return;
    setState(() {
      _strokes.add(stroke);
      _pressures.add(_activePressures);
      _active = null;
      _activePressures = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Signature'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 360,
            height: 180,
            decoration: BoxDecoration(
              // the pad is always paper-white, like the page the
              // signature will land on - only its border follows the theme
              color: Colors.white,
              border: Border.all(color: Theme.of(context).colorScheme.outline),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Listener(
                onPointerDown: (e) => _pointerPressure = _normalizedPressure(e),
                onPointerMove: (e) => _pointerPressure = _normalizedPressure(e),
                child: GestureDetector(
                  dragStartBehavior: DragStartBehavior.down,
                  onPanStart: _panStart,
                  onPanUpdate: _panUpdate,
                  onPanEnd: _panEnd,
                  child: CustomPaint(
                    key: const ValueKey('pdf-signature-pad'),
                    size: const Size(360, 180),
                    painter: _SignaturePadPainter(
                      strokes: [..._strokes, if (_active != null) _active!],
                      pressures: [
                        ..._pressures,
                        if (_active != null) _activePressures
                      ],
                      color: _ink,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            for (final ink in _inks)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InkWell(
                  onTap: () => setState(() => _ink = ink),
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: ink,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _ink == ink
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outline,
                        width: _ink == ink ? 3 : 1,
                      ),
                    ),
                  ),
                ),
              ),
            const Spacer(),
            TextButton(
              onPressed: _isEmpty
                  ? null
                  : () => setState(() {
                        _strokes.clear();
                        _pressures.clear();
                        _active = null;
                        _activePressures = null;
                      }),
              child: const Text('Clear'),
            ),
          ]),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isEmpty
              ? null
              : () => Navigator.of(context)
                  .pop(PdfInkSignature.fromPad(_strokes, _pressures, _ink)),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _SignaturePadPainter extends CustomPainter {
  _SignaturePadPainter({
    required this.strokes,
    required this.pressures,
    required this.color,
  });

  final List<List<Offset>> strokes;
  final List<List<double>?> pressures;
  final Color color;

  static const _baseWidth = 2.5;

  @override
  void paint(Canvas canvas, Size size) {
    final baseline = Paint()
      ..color = Colors.black12
      ..strokeWidth = 1;
    canvas.drawLine(Offset(16, size.height * 0.75),
        Offset(size.width - 16, size.height * 0.75), baseline);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _baseWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (var i = 0; i < strokes.length; i++) {
      final stroke = strokes[i];
      final pressure = i < pressures.length ? pressures[i] : null;
      if (stroke.isEmpty) continue;
      // same Catmull-Rom smoothing as the committed ink appearance
      final controls =
          pdfInkCurveControls([for (final p in stroke) (p.dx, p.dy)]);
      if (pressure == null) {
        final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
        for (var j = 0; j + 1 < stroke.length; j++) {
          final ((c1x, c1y), (c2x, c2y)) = controls[j];
          path.cubicTo(c1x, c1y, c2x, c2y, stroke[j + 1].dx, stroke[j + 1].dy);
        }
        canvas.drawPath(path, paint);
      } else {
        // same per-segment width mapping as the committed appearance
        final segment = Paint()
          ..color = color
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;
        if (stroke.length == 1) {
          canvas.drawCircle(
              stroke.single,
              pdfInkStrokeWidth(_baseWidth, pressure.first) / 2,
              Paint()..color = color);
          continue;
        }
        for (var j = 0; j + 1 < stroke.length; j++) {
          final avg = (pressure[j] + pressure[j + 1]) / 2;
          segment.strokeWidth = pdfInkStrokeWidth(_baseWidth, avg);
          final ((c1x, c1y), (c2x, c2y)) = controls[j];
          canvas.drawPath(
              Path()
                ..moveTo(stroke[j].dx, stroke[j].dy)
                ..cubicTo(
                    c1x, c1y, c2x, c2y, stroke[j + 1].dx, stroke[j + 1].dy),
              segment);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_SignaturePadPainter old) =>
      old.strokes != strokes || old.color != color;
}
