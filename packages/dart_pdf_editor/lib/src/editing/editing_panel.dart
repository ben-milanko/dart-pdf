import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';

import '../scrollbar.dart';

/// Which side of the viewer a sidebar panel is docked on. Its resize
/// grip rides the opposite (inner) edge - the one facing the viewer.
enum PdfSidebarSide { left, right }

/// Whether panel row controls should be revealed by mouse hover.
///
/// Desktop targets have reliable hover and benefit from quieter panels.
/// Touch-first targets keep controls visible so the actions stay discoverable.
bool pdfPanelControlsRevealOnHover() => switch (defaultTargetPlatform) {
      TargetPlatform.linux ||
      TargetPlatform.macOS ||
      TargetPlatform.windows =>
        true,
      TargetPlatform.android ||
      TargetPlatform.fuchsia ||
      TargetPlatform.iOS =>
        false,
    };

/// A compact close (×) button for a docked sidebar panel's header - the
/// desktop counterpart of the bottom sheet's close button (which the
/// sheet chrome supplies on its own). A panel renders this in its header
/// only when the host wires an `onClose` and the panel is docked, not a
/// sheet.
class PdfSidebarCloseButton extends StatelessWidget {
  const PdfSidebarCloseButton({
    super.key,
    required this.onPressed,
  });

  /// Dismisses the panel - the shells turn its visibility preference off.
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

  /// The drag ended - time to persist the new width.
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

/// Geometry and shared chrome supplied to a sidebar panel's content builder.
class PdfSidebarPanelGeometry {
  const PdfSidebarPanelGeometry._({
    required this.width,
    required this.bottomSheet,
    required this.showGrip,
    required this.gripOnLeft,
    required this.onClose,
  });

  final double width;
  final bool bottomSheet;
  final bool showGrip;
  final bool gripOnLeft;
  final VoidCallback? onClose;

  bool get gripOnRight => showGrip && !gripOnLeft;
  bool get scrollbarSharesGripEdge => gripOnRight;
  double get scrollbarInset =>
      scrollbarSharesGripEdge ? PdfSidebarResizeGrip.width : 0;
  double get scrollbarClearance => PdfScrollbar.hitExtent + scrollbarInset;
  double get contentStartInset => gripOnLeft ? PdfSidebarResizeGrip.width : 0;
  double get contentEndInset => gripOnRight ? PdfSidebarResizeGrip.width : 0;

  /// The docked close button; bottom sheets supply their own sheet chrome.
  Widget? closeButton({Key? key}) => bottomSheet || onClose == null
      ? null
      : PdfSidebarCloseButton(key: key, onPressed: onClose!);

  /// Places the package scrollbar at the shared dock-aware inset.
  Widget withScrollbar({
    required Widget child,
    required ScrollController scroll,
    required Key thumbKey,
  }) =>
      Stack(children: [
        child,
        Positioned(
          top: 0,
          bottom: 0,
          right: scrollbarInset,
          child: PdfScrollbar(scroll: scroll, thumbKey: thumbKey),
        ),
      ]);
}

typedef PdfSidebarPanelContentBuilder = Widget Function(
  BuildContext context,
  PdfSidebarPanelGeometry geometry,
);

/// Shared docked/bottom-sheet frame for sidebar panels.
///
/// Owns drag width, clamping, one-shot persistence, grip placement, dock
/// insets, close policy, and scrollbar geometry. Panel-specific data, lists,
/// and controllers remain inside [builder].
class PdfSidebarPanelFrame extends StatefulWidget {
  const PdfSidebarPanelFrame({
    super.key,
    required this.builder,
    required this.width,
    required this.minWidth,
    required this.maxWidth,
    required this.side,
    required this.resizable,
    required this.bottomSheet,
    required this.gripKey,
    this.persistedWidth,
    this.onPersistWidth,
    this.onClose,
  });

  final PdfSidebarPanelContentBuilder builder;
  final double width;
  final double minWidth;
  final double maxWidth;
  final double? persistedWidth;
  final ValueChanged<double>? onPersistWidth;
  final PdfSidebarSide side;
  final bool resizable;
  final bool bottomSheet;
  final Key gripKey;
  final VoidCallback? onClose;

  @override
  State<PdfSidebarPanelFrame> createState() => _PdfSidebarPanelFrameState();
}

class _PdfSidebarPanelFrameState extends State<PdfSidebarPanelFrame> {
  double? _dragWidth;
  double? _settledWidth;

  double get _width =>
      (_dragWidth ?? _settledWidth ?? widget.persistedWidth ?? widget.width)
          .clamp(widget.minWidth, widget.maxWidth)
          .toDouble();

  @override
  void didUpdateWidget(PdfSidebarPanelFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.persistedWidth != widget.persistedWidth) {
      _settledWidth = null;
    }
  }

  void _resize(double delta) => setState(() {
        _dragWidth =
            (_width + delta).clamp(widget.minWidth, widget.maxWidth).toDouble();
      });

  void _endResize() {
    final width = _dragWidth;
    if (width == null) return;
    final persist = widget.onPersistWidth;
    if (persist == null) return; // the search panel keeps an unpersisted drag
    persist(width); // exactly one preference write per completed drag
    setState(() {
      _settledWidth = width;
      _dragWidth = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final showGrip = widget.resizable && !widget.bottomSheet;
    final geometry = PdfSidebarPanelGeometry._(
      width: _width,
      bottomSheet: widget.bottomSheet,
      showGrip: showGrip,
      gripOnLeft: showGrip && widget.side == PdfSidebarSide.right,
      onClose: widget.onClose,
    );
    final content = widget.builder(context, geometry);
    if (widget.bottomSheet) return content;
    return SizedBox(
      width: geometry.width,
      child: Stack(children: [
        Positioned.fill(child: content),
        if (showGrip)
          Positioned(
            top: 0,
            bottom: 0,
            left: geometry.gripOnLeft ? 0 : null,
            right: geometry.gripOnRight ? 0 : null,
            child: PdfSidebarResizeGrip(
              key: widget.gripKey,
              side: widget.side,
              onWidthDelta: _resize,
              onResizeEnd: _endResize,
            ),
          ),
      ]),
    );
  }
}
