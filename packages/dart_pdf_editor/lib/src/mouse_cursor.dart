import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:pdf_document/pdf_document.dart';

/// The platform-independent cursor glyphs used by the PDF chrome.
///
/// Flutter's [SystemMouseCursors] deliberately map to each platform's native
/// artwork. That is desirable for most apps, but it made the same PDF editing
/// affordance change shape (and occasionally disappear) between desktop and
/// web targets. These glyphs are painted by Flutter instead, while the native
/// cursor is hidden, so their geometry and hotspot are identical everywhere.
///
/// This type lives in `src/` and is shared package implementation rather than
/// public API.
enum PdfMouseCursorKind {
  basic,
  click,
  text,
  precise,
  move,
  grab,
  grabbing,
  resizeLeftRight,
  resizeUpDown,
  resizeUpLeftDownRight,
  resizeUpRightDownLeft,
  resizeColumn,
  resizeRow,
  rotate,
}

/// The cursor for a form field that the direct-fill layer actually handles.
/// A null result means the field has no pointer action and should let the page
/// surface underneath choose its cursor.
PdfMouseCursorKind? pdfFormFieldMouseCursor(
  PdfFormField field, {
  required bool canPickButtonImage,
}) {
  if (field.isReadOnly) return null;
  return switch (field.type) {
    PdfFieldType.text => PdfMouseCursorKind.text,
    PdfFieldType.checkBox ||
    PdfFieldType.radioGroup ||
    PdfFieldType.comboBox ||
    PdfFieldType.listBox =>
      PdfMouseCursorKind.click,
    PdfFieldType.pushButton =>
      canPickButtonImage ? PdfMouseCursorKind.click : null,
    PdfFieldType.signature || PdfFieldType.unknown => null,
  };
}

/// Paints one package-owned mouse cursor at its interaction [hotspot].
///
/// [scale] is local-space units per screen pixel. Page overlays pass the
/// inverse viewer zoom so cursors stay the same physical size while the PDF is
/// magnified; ordinary chrome leaves it at one.
void paintPdfMouseCursor(
  Canvas canvas,
  Offset hotspot,
  PdfMouseCursorKind kind, {
  double scale = 1,
}) {
  final s = scale.isFinite && scale > 0 ? scale : 1.0;
  canvas.save();
  canvas.translate(hotspot.dx, hotspot.dy);
  switch (kind) {
    case PdfMouseCursorKind.basic:
      _paintArrow(canvas, s);
    case PdfMouseCursorKind.click:
      _paintPointerHand(canvas, s);
    case PdfMouseCursorKind.text:
      _paintText(canvas, s);
    case PdfMouseCursorKind.precise:
      _paintCrosshair(canvas, s);
    case PdfMouseCursorKind.move:
      _paintMove(canvas, s);
    case PdfMouseCursorKind.grab:
      _paintHand(canvas, s, closed: false);
    case PdfMouseCursorKind.grabbing:
      _paintHand(canvas, s, closed: true);
    case PdfMouseCursorKind.resizeLeftRight:
      _paintResize(canvas, s, 0);
    case PdfMouseCursorKind.resizeUpDown:
      _paintResize(canvas, s, math.pi / 2);
    case PdfMouseCursorKind.resizeUpLeftDownRight:
      _paintResize(canvas, s, math.pi / 4);
    case PdfMouseCursorKind.resizeUpRightDownLeft:
      _paintResize(canvas, s, -math.pi / 4);
    case PdfMouseCursorKind.resizeColumn:
      _paintResize(canvas, s, 0, divider: true);
    case PdfMouseCursorKind.resizeRow:
      _paintResize(canvas, s, math.pi / 2, divider: true);
    case PdfMouseCursorKind.rotate:
      _paintRotate(canvas, s);
  }
  canvas.restore();
}

/// A mouse region that hides the native cursor and paints [kind] over its
/// child. It also follows pointer moves while a button is held, which
/// [MouseRegion.onHover] alone does not receive.
///
/// Page surfaces with an existing composite painter call
/// [paintPdfMouseCursor] directly. Standalone chrome such as panel grips and
/// scrollbars uses this widget.
class PdfMouseCursorRegion extends StatefulWidget {
  const PdfMouseCursorRegion({
    super.key,
    required this.kind,
    required this.child,
    this.scale = 1,
    this.onEnter,
    this.onHover,
    this.onExit,
  });

  final PdfMouseCursorKind? kind;
  final Widget child;
  final double scale;
  final void Function(PointerEnterEvent event)? onEnter;
  final void Function(PointerHoverEvent event)? onHover;
  final void Function(PointerExitEvent event)? onExit;

  @override
  State<PdfMouseCursorRegion> createState() => _PdfMouseCursorRegionState();
}

class _PdfMouseCursorRegionState extends State<PdfMouseCursorRegion> {
  Offset? _position;

  bool _tracks(PointerEvent event) =>
      event.kind == PointerDeviceKind.mouse ||
      event.kind == PointerDeviceKind.trackpad;

  void _setPosition(PointerEvent event) {
    if (!_tracks(event) || _position == event.localPosition) return;
    setState(() => _position = event.localPosition);
  }

  void _enter(PointerEnterEvent event) {
    if (_tracks(event)) setState(() => _position = event.localPosition);
    widget.onEnter?.call(event);
  }

  void _hover(PointerHoverEvent event) {
    _setPosition(event);
    widget.onHover?.call(event);
  }

  void _exit(PointerExitEvent event) {
    if (_position != null) setState(() => _position = null);
    widget.onExit?.call(event);
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.none,
        onEnter: _enter,
        onHover: _hover,
        onExit: _exit,
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _setPosition,
          onPointerMove: _setPosition,
          child: CustomPaint(
            foregroundPainter: PdfMouseCursorPainter(
              kind: widget.kind,
              position: _position,
              scale: widget.scale,
            ),
            child: widget.child,
          ),
        ),
      );
}

/// Foreground painter used by [PdfMouseCursorRegion] and the viewer's
/// transform-independent cursor layer.
class PdfMouseCursorPainter extends CustomPainter {
  const PdfMouseCursorPainter({
    required this.kind,
    required this.position,
    this.scale = 1,
  });

  final PdfMouseCursorKind? kind;
  final Offset? position;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final kind = this.kind;
    final position = this.position;
    if (kind != null && position != null) {
      paintPdfMouseCursor(canvas, position, kind, scale: scale);
    }
  }

  @override
  bool shouldRepaint(PdfMouseCursorPainter oldDelegate) =>
      oldDelegate.kind != kind ||
      oldDelegate.position != position ||
      oldDelegate.scale != scale;
}

Paint _outline(double s, {PaintingStyle style = PaintingStyle.stroke}) =>
    Paint()
      ..color = const Color(0xE6000000)
      ..style = style
      ..strokeWidth = 4 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

Paint _face(double s, {PaintingStyle style = PaintingStyle.stroke}) => Paint()
  ..color = const Color(0xFFFFFFFF)
  ..style = style
  ..strokeWidth = 2 * s
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

void _line(Canvas canvas, Offset a, Offset b, double s) {
  canvas.drawLine(a * s, b * s, _outline(s));
  canvas.drawLine(a * s, b * s, _face(s));
}

void _path(Canvas canvas, Path path, double s) {
  canvas.save();
  canvas.scale(s, s);
  canvas.drawPath(
    path.shift(const Offset(1, 1)),
    Paint()..color = const Color(0x40000000),
  );
  canvas.drawPath(path, _face(1, style: PaintingStyle.fill));
  canvas.drawPath(
    path,
    _outline(1)
      ..strokeWidth = 1.35
      ..style = PaintingStyle.stroke,
  );
  canvas.restore();
}

void _paintArrow(Canvas canvas, double s) {
  final path = Path()
    ..moveTo(0, 0)
    ..lineTo(1.3, 18.5)
    ..lineTo(5.7, 14.3)
    ..lineTo(9.1, 21.2)
    ..lineTo(13.2, 19.2)
    ..lineTo(9.7, 12.4)
    ..lineTo(15.7, 11.8)
    ..close();
  _path(canvas, path, s);
}

void _paintPointerHand(Canvas canvas, double s) {
  // The interaction hotspot is the raised index fingertip at (0, 0).
  final path = Path()
    ..moveTo(0, 0)
    ..cubicTo(-1.8, 0, -2.2, 1.5, -2.2, 3.1)
    ..lineTo(-2.2, 11.1)
    ..lineTo(-5.1, 8.6)
    ..cubicTo(-7.7, 6.4, -10.4, 9.3, -8.2, 11.7)
    ..lineTo(-1.5, 19.0)
    ..cubicTo(0.1, 20.7, 2.3, 21.6, 4.7, 21.6)
    ..lineTo(8.2, 21.6)
    ..cubicTo(11.6, 21.6, 14.2, 18.8, 14.2, 15.4)
    ..lineTo(14.2, 9.7)
    ..cubicTo(14.2, 7.0, 10.7, 6.4, 9.7, 8.7)
    ..cubicTo(9.2, 6.0, 5.6, 5.8, 4.7, 8.2)
    ..cubicTo(4.0, 5.6, 0.5, 5.6, -0.1, 8.1)
    ..lineTo(-0.1, 3.1)
    ..cubicTo(-0.1, 1.5, 1.8, 0, 0, 0)
    ..close();
  _path(canvas, path, s);
}

void _paintText(Canvas canvas, double s) {
  _line(canvas, const Offset(0, -9), const Offset(0, 9), s);
  _line(canvas, const Offset(-4, -9), const Offset(4, -9), s);
  _line(canvas, const Offset(-4, 9), const Offset(4, 9), s);
  _line(canvas, const Offset(-2.5, 0), const Offset(2.5, 0), s);
}

void _paintCrosshair(Canvas canvas, double s) {
  _line(canvas, const Offset(-10, 0), const Offset(-3, 0), s);
  _line(canvas, const Offset(3, 0), const Offset(10, 0), s);
  _line(canvas, const Offset(0, -10), const Offset(0, -3), s);
  _line(canvas, const Offset(0, 3), const Offset(0, 10), s);
  canvas.drawCircle(
    Offset.zero,
    1.2 * s,
    _outline(s, style: PaintingStyle.fill),
  );
  canvas.drawCircle(Offset.zero, 0.55 * s, _face(s, style: PaintingStyle.fill));
}

void _paintMove(Canvas canvas, double s) {
  for (var i = 0; i < 4; i++) {
    canvas.save();
    canvas.rotate(i * math.pi / 2);
    _line(canvas, const Offset(0, 1), const Offset(0, -9), s);
    _line(canvas, const Offset(0, -9), const Offset(-3.5, -5.5), s);
    _line(canvas, const Offset(0, -9), const Offset(3.5, -5.5), s);
    canvas.restore();
  }
  canvas.drawCircle(Offset.zero, 1.5 * s, _face(s, style: PaintingStyle.fill));
}

void _paintResize(
  Canvas canvas,
  double s,
  double rotation, {
  bool divider = false,
}) {
  canvas.save();
  canvas.rotate(rotation);
  _line(canvas, const Offset(-9, 0), const Offset(9, 0), s);
  _line(canvas, const Offset(-9, 0), const Offset(-5, -4), s);
  _line(canvas, const Offset(-9, 0), const Offset(-5, 4), s);
  _line(canvas, const Offset(9, 0), const Offset(5, -4), s);
  _line(canvas, const Offset(9, 0), const Offset(5, 4), s);
  if (divider) {
    _line(canvas, const Offset(0, -7), const Offset(0, 7), s);
  }
  canvas.restore();
}

void _paintHand(Canvas canvas, double s, {required bool closed}) {
  final path = closed ? _closedHandPath() : _openHandPath();
  _path(canvas, path, s);

  // A couple of restrained creases keep the silhouettes readable at their
  // real 20px size without turning the cursor into a tiny illustration.
  final detail = Paint()
    ..color = const Color(0xD9000000)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.05 * s
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final creases = closed
      ? (Path()
        ..moveTo(-4.1 * s, -1.7 * s)
        ..lineTo(-3.8 * s, 0.2 * s)
        ..moveTo(-0.8 * s, -2.5 * s)
        ..lineTo(-0.5 * s, 0.2 * s)
        ..moveTo(2.4 * s, -2.6 * s)
        ..lineTo(2.7 * s, 0.7 * s)
        ..moveTo(-5.4 * s, 1.1 * s)
        ..cubicTo(-1.8 * s, 0.2 * s, 2.0 * s, 1.3 * s, 4.5 * s, 3.7 * s))
      : (Path()
        ..moveTo(-1.0 * s, -5.0 * s)
        ..lineTo(-1.0 * s, 1.0 * s)
        ..moveTo(2.1 * s, -5.5 * s)
        ..lineTo(2.1 * s, 1.0 * s)
        ..moveTo(5.2 * s, -4.3 * s)
        ..lineTo(5.2 * s, 1.3 * s));
  canvas.drawPath(creases, detail);
}

Path _openHandPath() => Path()
  // Wrist and heel of the palm.
  ..moveTo(-5.0, 9.7)
  ..cubicTo(-7.5, 8.8, -8.6, 6.7, -8.1, 4.3)
  // The thumb opens diagonally to the left instead of reading as another
  // rounded side of the palm.
  ..lineTo(-10.1, 1.7)
  ..cubicTo(-11.7, -0.4, -9.5, -2.8, -7.4, -1.4)
  ..lineTo(-3.8, 1.0)
  // Index finger.
  ..lineTo(-3.8, -7.2)
  ..cubicTo(-3.8, -9.8, -0.8, -10.1, -0.8, -7.4)
  ..lineTo(-0.8, -5.2)
  // Middle finger, deliberately the tallest.
  ..lineTo(-0.8, -9.5)
  ..cubicTo(-0.8, -12.2, 2.2, -12.2, 2.2, -9.5)
  ..lineTo(2.2, -5.7)
  // Ring finger.
  ..lineTo(2.2, -8.4)
  ..cubicTo(2.2, -11.0, 5.2, -10.8, 5.2, -8.2)
  ..lineTo(5.2, -4.5)
  // Pinky and outside of the palm.
  ..lineTo(5.2, -6.7)
  ..cubicTo(5.2, -9.0, 8.1, -8.7, 8.1, -6.3)
  ..lineTo(8.1, 1.7)
  ..cubicTo(8.1, 5.9, 5.1, 9.5, 0.9, 10.2)
  ..cubicTo(-1.1, 10.6, -3.3, 10.5, -5.0, 9.7)
  ..close();

Path _closedHandPath() => Path()
  // Four compact, individually readable knuckles.
  ..moveTo(-7.9, -1.5)
  ..cubicTo(-8.0, -4.1, -5.1, -4.9, -3.7, -2.8)
  ..cubicTo(-3.6, -5.7, -0.6, -6.3, 0.6, -3.7)
  ..cubicTo(0.9, -6.5, 4.0, -6.5, 4.9, -3.8)
  ..cubicTo(5.5, -6.1, 8.3, -5.2, 8.1, -2.7)
  ..cubicTo(10.4, -2.5, 10.7, 0.4, 8.8, 1.8)
  // Curled thumb and tapered wrist.
  ..lineTo(5.3, 6.8)
  ..cubicTo(4.1, 9.1, 1.6, 10.3, -1.0, 9.9)
  ..lineTo(-4.8, 9.2)
  ..cubicTo(-7.3, 8.7, -8.9, 6.6, -8.9, 4.1)
  ..lineTo(-8.9, 0.1)
  ..cubicTo(-8.9, -0.9, -8.6, -1.5, -7.9, -1.9)
  ..close();

void _paintRotate(Canvas canvas, double s) {
  const start = -math.pi / 2;
  const sweep = 290 * math.pi / 180;
  final box = Rect.fromCircle(center: Offset.zero, radius: 9 * s);
  canvas.drawArc(box, start, sweep, false, _outline(s));
  canvas.drawArc(box, start, sweep, false, _face(s));
  final end = start + sweep;
  final tip = Offset(math.cos(end), math.sin(end)) * 9 * s;
  final tangent = end + math.pi / 2;
  for (final a in [tangent + 2.5, tangent - 2.5]) {
    final wing = tip + Offset(math.cos(a), math.sin(a)) * 4 * s;
    canvas.drawLine(tip, wing, _outline(s));
    canvas.drawLine(tip, wing, _face(s));
  }
}
