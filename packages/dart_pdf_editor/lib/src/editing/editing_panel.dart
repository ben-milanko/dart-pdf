import 'package:flutter/material.dart';

/// Which side of the viewer a sidebar panel is docked on. Its resize
/// grip rides the opposite (inner) edge — the one facing the viewer.
enum PdfSidebarSide { left, right }

/// A compact close (×) button for a docked sidebar panel's header — the
/// desktop counterpart of the bottom sheet's close button (which the
/// sheet chrome supplies on its own). A panel renders this in its header
/// only when the host wires an `onClose` and the panel is docked, not a
/// sheet.
class PdfSidebarCloseButton extends StatelessWidget {
  const PdfSidebarCloseButton({
    super.key,
    required this.onPressed,
  });

  /// Dismisses the panel — the shells turn its visibility preference off.
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
        icon: const Icon(Icons.close, size: 18),
        tooltip: 'Close',
        visualDensity: VisualDensity.compact,
        onPressed: onPressed,
      );
}

/// The draggable divider on a sidebar's inner edge: an invisible 8px
/// hit strip with a hairline down the middle that thickens and tints on
/// hover and while dragging. Reports width deltas already signed toward
/// growth, whichever side the panel is docked on.
class PdfSidebarResizeGrip extends StatefulWidget {
  const PdfSidebarResizeGrip({
    super.key,
    required this.side,
    required this.onWidthDelta,
    required this.onResizeEnd,
  });

  /// The side of the viewer the panel is docked on; the grip itself is
  /// laid out on the opposite edge by the panel.
  final PdfSidebarSide side;

  /// A drag movement, in logical pixels, positive when the drag makes
  /// the panel wider.
  final ValueChanged<double> onWidthDelta;

  /// The drag ended — time to persist the new width.
  final VoidCallback onResizeEnd;

  /// The grip's hit-test width.
  static const double width = 8;

  @override
  State<PdfSidebarResizeGrip> createState() => _PdfSidebarResizeGripState();
}

class _PdfSidebarResizeGripState extends State<PdfSidebarResizeGrip> {
  bool _hovered = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = _hovered || _dragging;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => setState(() => _dragging = true),
        onHorizontalDragUpdate: (details) => widget.onWidthDelta(
            widget.side == PdfSidebarSide.left
                ? details.delta.dx
                : -details.delta.dx),
        onHorizontalDragEnd: (_) {
          setState(() => _dragging = false);
          widget.onResizeEnd();
        },
        onHorizontalDragCancel: () {
          setState(() => _dragging = false);
          widget.onResizeEnd();
        },
        child: SizedBox(
          width: PdfSidebarResizeGrip.width,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: active ? 3 : 1,
              color: active ? scheme.primary : scheme.outlineVariant,
            ),
          ),
        ),
      ),
    );
  }
}
