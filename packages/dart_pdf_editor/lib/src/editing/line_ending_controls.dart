import 'package:flutter/material.dart';
import 'package:pdf_document/pdf_document.dart';

/// A short human label for a [PdfLineEnding], for menus and tooltips.
String pdfLineEndingLabel(PdfLineEnding ending) => switch (ending) {
      PdfLineEnding.none => 'None',
      PdfLineEnding.square => 'Square',
      PdfLineEnding.circle => 'Circle',
      PdfLineEnding.diamond => 'Diamond',
      PdfLineEnding.openArrow => 'Open arrow',
      PdfLineEnding.closedArrow => 'Closed arrow',
      PdfLineEnding.butt => 'Butt',
      PdfLineEnding.rOpenArrow => 'Open arrow (rev.)',
      PdfLineEnding.rClosedArrow => 'Closed arrow (rev.)',
      PdfLineEnding.slash => 'Slash',
    };

/// A dropdown for choosing a /Line or /PolyLine ending ([PdfLineEnding]),
/// each option previewed with a tiny icon of the shape on a short segment.
///
/// [atEnd] orients the preview so a start picker draws its ending on the
/// left and an end picker on the right. Shared by the editing toolbar and
/// the annotation properties panel so both read the same way.
class PdfLineEndingDropdown extends StatelessWidget {
  const PdfLineEndingDropdown({
    super.key,
    required this.value,
    required this.atEnd,
    required this.onChanged,
    this.dropdownKey,
    this.isExpanded = true,
    this.underline,
  });

  final PdfLineEnding value;

  /// Whether this dropdown decorates the line's end (preview on the right)
  /// rather than its start (preview on the left).
  final bool atEnd;

  final ValueChanged<PdfLineEnding> onChanged;

  /// Key for the inner [DropdownButton] (for tests to target).
  final Key? dropdownKey;

  final bool isExpanded;

  /// Replaces the dropdown's default underline; null keeps it.
  final Widget? underline;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    return DropdownButton<PdfLineEnding>(
      key: dropdownKey,
      isExpanded: isExpanded,
      isDense: true,
      value: value,
      underline: underline,
      items: [
        for (final ending in PdfLineEnding.values)
          DropdownMenuItem(
            value: ending,
            child: Row(children: [
              SizedBox(
                width: 36,
                height: 14,
                child: CustomPaint(
                  painter:
                      PdfLineEndingPainter(ending, atEnd: atEnd, color: color),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(pdfLineEndingLabel(ending),
                    overflow: TextOverflow.ellipsis),
              ),
            ]),
          ),
      ],
      onChanged: (ending) {
        if (ending != null) onChanged(ending);
      },
    );
  }
}

/// Draws a short segment with [ending] rendered at one end — the preview
/// icon for the line-ending dropdown. Purely indicative geometry (not the
/// exact appearance the editor generates), oriented so [atEnd] puts the
/// ending on the right.
class PdfLineEndingPainter extends CustomPainter {
  const PdfLineEndingPainter(this.ending,
      {required this.atEnd, required this.color});

  final PdfLineEnding ending;
  final bool atEnd;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final cy = size.height / 2;
    // the tip is the end the shape decorates; the line runs to the far side
    final tipX = atEnd ? size.width - 2.0 : 2.0;
    final farX = atEnd ? 2.0 : size.width - 2.0;
    // unit vector from tip back along the line, and the perpendicular
    final ux = farX > tipX ? 1.0 : -1.0;
    final tip = Offset(tipX, cy);
    canvas.drawLine(Offset(farX, cy), tip, stroke);
    const s = 6.0; // characteristic size in preview px
    Offset at(double along, double across) =>
        Offset(tip.dx + ux * along, cy + across);
    switch (ending) {
      case PdfLineEnding.none:
        break;
      case PdfLineEnding.closedArrow:
      case PdfLineEnding.openArrow:
        final path = Path()
          ..moveTo(at(s, -s * 0.4).dx, at(s, -s * 0.4).dy)
          ..lineTo(tip.dx, tip.dy)
          ..lineTo(at(s, s * 0.4).dx, at(s, s * 0.4).dy);
        if (ending == PdfLineEnding.closedArrow) {
          path.close();
          canvas.drawPath(path, fill);
        } else {
          canvas.drawPath(path, stroke);
        }
      case PdfLineEnding.rClosedArrow:
      case PdfLineEnding.rOpenArrow:
        final path = Path()
          ..moveTo(at(0, -s * 0.4).dx, at(0, -s * 0.4).dy)
          ..lineTo(at(s, 0).dx, at(s, 0).dy)
          ..lineTo(at(0, s * 0.4).dx, at(0, s * 0.4).dy);
        if (ending == PdfLineEnding.rClosedArrow) {
          path.close();
          canvas.drawPath(path, fill);
        } else {
          canvas.drawPath(path, stroke);
        }
      case PdfLineEnding.diamond:
        final path = Path()
          ..moveTo(at(s * 0.5, 0).dx, at(s * 0.5, 0).dy)
          ..lineTo(at(0, -s * 0.5).dx, at(0, -s * 0.5).dy)
          ..lineTo(at(-s * 0.5, 0).dx, at(-s * 0.5, 0).dy)
          ..lineTo(at(0, s * 0.5).dx, at(0, s * 0.5).dy)
          ..close();
        canvas.drawPath(path, fill);
      case PdfLineEnding.square:
        canvas.drawRect(
            Rect.fromCenter(center: tip, width: s, height: s), fill);
      case PdfLineEnding.circle:
        canvas.drawCircle(tip, s * 0.5, fill);
      case PdfLineEnding.butt:
        canvas.drawLine(at(0, -s * 0.5), at(0, s * 0.5), stroke);
      case PdfLineEnding.slash:
        canvas.drawLine(Offset(tip.dx - s * 0.3, cy + s * 0.5),
            Offset(tip.dx + s * 0.3, cy - s * 0.5), stroke);
    }
  }

  @override
  bool shouldRepaint(PdfLineEndingPainter old) =>
      old.ending != ending || old.atEnd != atEnd || old.color != color;
}
