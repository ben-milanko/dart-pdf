import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';

import '../l10n/pdf_l10n.dart';
import '../scrollbar.dart';

/// Which side of the viewer a sidebar panel's resize grip belongs to. Its
/// grip rides the opposite (inner) edge - the one facing the viewer. Kept
/// as the horizontal-only orientation the grip and the comparison navigator
/// still speak; new placement code uses [PdfPanelDock].
enum PdfSidebarSide { left, right }

/// Which edge of the content area a dockable panel is attached to.
///
/// Left/right docks lay the panel out as a fixed-width column beside the
/// viewer; top/bottom docks lay it out as a fixed-height strip spanning the
/// content width, above or below the viewer. The user drags a panel's move
/// handle onto another edge to redock it, and the shell persists the choice.
enum PdfPanelDock {
  left,
  right,
  top,
  bottom;

  /// Left/right docks are vertical columns sized by their width; top/bottom
  /// docks are horizontal strips sized by their height.
  bool get isHorizontal =>
      this == PdfPanelDock.left || this == PdfPanelDock.right;

  /// The horizontal orientation the resize grip speaks, for the left/right
  /// docks. Meaningless for the vertical docks (which use a vertical grip).
  PdfSidebarSide get gripSide =>
      this == PdfPanelDock.left ? PdfSidebarSide.left : PdfSidebarSide.right;
}

/// The panels a shell can rearrange between docks. Doubles as the payload
/// dragged from a move handle onto a drop zone and the identity a shell maps
/// to the panel's persisted [PdfPanelDock].
enum PdfDockablePanel {
  thumbnails(Icons.grid_view),
  search(Icons.manage_search),
  bookmarks(Icons.bookmarks_outlined),
  annotations(Icons.list_alt),
  properties(Icons.tune);

  const PdfDockablePanel(this.icon);

  /// The panel's glyph, shown on the drag feedback chip.
  final IconData icon;

  /// A localized, human-readable name shown on the drag feedback chip and
  /// panel headers. Reuses the shell's panel names so the same words are
  /// translated once.
  String label(BuildContext context) {
    final l = pdfL10n(context);
    return switch (this) {
      PdfDockablePanel.thumbnails => l.shellPanelPages,
      PdfDockablePanel.search => l.shellPanelSearchResults,
      PdfDockablePanel.bookmarks => l.shellPanelBookmarks,
      PdfDockablePanel.annotations => l.shellPanelAnnotations,
      PdfDockablePanel.properties => l.shellPanelProperties,
    };
  }
}

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

/// Ambient wiring that lets a docked panel's move handle drive the shell's
/// drag-to-redock affordance. [PdfShellPanelLayout] provides it around the
/// panels; a panel's [PdfSidebarPanelGeometry.moveHandle] reads it. Absent
/// when a shell wires no redocking - then panels render no move handle.
class PdfPanelDragScope extends InheritedWidget {
  const PdfPanelDragScope({
    super.key,
    required this.onDragStarted,
    required this.onDragEnded,
    required super.child,
  });

  /// A panel's move handle picked up a drag - the shell reveals its drop
  /// zones.
  final VoidCallback onDragStarted;

  /// The drag ended (dropped or cancelled) - the shell hides its drop zones.
  final VoidCallback onDragEnded;

  static PdfPanelDragScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PdfPanelDragScope>();

  @override
  bool updateShouldNotify(PdfPanelDragScope oldWidget) => false;
}

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
        tooltip: pdfL10n(context).close,
        visualDensity: VisualDensity.compact,
        onPressed: onPressed,
      );
}

/// The grab handle a docked panel shows in its header: drag it onto another
/// edge's drop zone to redock the panel. Renders nothing when no
/// [PdfPanelDragScope] is in scope (the shell wires no redocking).
class PdfSidebarMoveHandle extends StatelessWidget {
  const PdfSidebarMoveHandle({
    super.key,
    required this.panel,
  });

  /// The panel this handle moves - the drag payload a drop zone receives.
  final PdfDockablePanel panel;

  @override
  Widget build(BuildContext context) {
    final scope = PdfPanelDragScope.maybeOf(context);
    if (scope == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final handle = MouseRegion(
      cursor: SystemMouseCursors.move,
      child: Tooltip(
        message: pdfL10n(context).panelDragToMovePanel,
        child: Icon(Icons.drag_indicator,
            size: 18, color: scheme.onSurfaceVariant),
      ),
    );
    return Draggable<PdfDockablePanel>(
      data: panel,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: scope.onDragStarted,
      onDragEnd: (_) => scope.onDragEnded(),
      onDraggableCanceled: (_, __) => scope.onDragEnded(),
      feedback: PdfPanelDragFeedback(panel: panel),
      // keep the handle in place under the moving feedback chip
      childWhenDragging: Opacity(opacity: 0.3, child: handle),
      child: handle,
    );
  }
}

/// The chip that follows the pointer while a panel is being redocked or
/// dragged onto another panel to form a tab group.
class PdfPanelDragFeedback extends StatelessWidget {
  const PdfPanelDragFeedback({super.key, required this.panel});

  final PdfDockablePanel panel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(panel.icon, size: 18, color: scheme.onPrimaryContainer),
          const SizedBox(width: 8),
          Text(panel.label(context),
              style: TextStyle(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }
}

/// The draggable divider on a sidebar's inner edge: an invisible 8px
/// hit strip with a hairline down the middle that thickens and tints on
/// hover and while dragging. Reports width deltas already signed toward
/// growth, whichever side the panel is docked on. Used by the left/right
/// docks and by the comparison navigator.
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

  /// The grip's hit-test thickness.
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

/// The vertical counterpart of [PdfSidebarResizeGrip], for the top/bottom
/// docks: an 8px horizontal hit strip whose hairline thickens on hover and
/// drag. Reports height deltas already signed toward growth.
class _PdfSidebarVerticalResizeGrip extends StatefulWidget {
  const _PdfSidebarVerticalResizeGrip({
    super.key,
    required this.top,
    required this.onHeightDelta,
    required this.onResizeEnd,
  });

  /// Whether the panel is docked at the top (grip rides its bottom edge and
  /// dragging down grows it) rather than the bottom.
  final bool top;

  final ValueChanged<double> onHeightDelta;
  final VoidCallback onResizeEnd;

  @override
  State<_PdfSidebarVerticalResizeGrip> createState() =>
      _PdfSidebarVerticalResizeGripState();
}

class _PdfSidebarVerticalResizeGripState
    extends State<_PdfSidebarVerticalResizeGrip> {
  bool _hovered = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = _hovered || _dragging;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: (_) => setState(() => _dragging = true),
        onVerticalDragUpdate: (details) => widget
            .onHeightDelta(widget.top ? details.delta.dy : -details.delta.dy),
        onVerticalDragEnd: (_) {
          setState(() => _dragging = false);
          widget.onResizeEnd();
        },
        onVerticalDragCancel: () {
          setState(() => _dragging = false);
          widget.onResizeEnd();
        },
        child: SizedBox(
          height: PdfSidebarResizeGrip.width,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              height: active ? 3 : 1,
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
    required this.dock,
    required this.bottomSheet,
    required this.showGrip,
    required this.gripOnLeft,
    required this.onClose,
    required this.panel,
  });

  /// The panel's fixed extent along its dock's cross axis - the column
  /// width for left/right docks, the strip height for top/bottom docks.
  final double width;

  /// Which edge the panel is docked on.
  final PdfPanelDock dock;

  final bool bottomSheet;
  final bool showGrip;
  final bool gripOnLeft;
  final VoidCallback? onClose;

  /// The panel's identity, for the move handle's drag payload. Null when
  /// the panel is not registered as dockable.
  final PdfDockablePanel? panel;

  bool get gripOnRight => showGrip && !gripOnLeft && dock.isHorizontal;
  bool get scrollbarSharesGripEdge => gripOnRight;
  double get scrollbarInset =>
      scrollbarSharesGripEdge ? PdfSidebarResizeGrip.width : 0;
  double get scrollbarClearance => PdfScrollbar.hitExtent + scrollbarInset;
  double get contentStartInset =>
      gripOnLeft && dock.isHorizontal ? PdfSidebarResizeGrip.width : 0;
  double get contentEndInset => gripOnRight ? PdfSidebarResizeGrip.width : 0;

  /// The docked close button; bottom sheets supply their own sheet chrome.
  Widget? closeButton({Key? key}) => bottomSheet || onClose == null
      ? null
      : PdfSidebarCloseButton(key: key, onPressed: onClose!);

  /// The move (drag-to-redock) handle; null unless the panel is dockable
  /// and docked (bottom sheets carry no handle). Renders nothing further
  /// when no [PdfPanelDragScope] is in scope.
  Widget? moveHandle({Key? key}) => bottomSheet || panel == null
      ? null
      : PdfSidebarMoveHandle(key: key, panel: panel!);

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
/// Owns drag extent, clamping, one-shot persistence, grip placement, dock
/// insets, close policy, and scrollbar geometry. Panel-specific data, lists,
/// and controllers remain inside [builder].
///
/// [width]/[minWidth]/[maxWidth] size the panel along its dock's cross axis:
/// the column width for the left/right docks, the strip height for the
/// top/bottom docks.
class PdfSidebarPanelFrame extends StatefulWidget {
  const PdfSidebarPanelFrame({
    super.key,
    required this.builder,
    required this.width,
    required this.minWidth,
    required this.maxWidth,
    required this.dock,
    required this.resizable,
    required this.bottomSheet,
    required this.gripKey,
    this.panel,
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

  /// Which edge the panel docks on - decides column-vs-strip layout and the
  /// grip orientation.
  final PdfPanelDock dock;

  /// The panel's identity, enabling the move (drag-to-redock) handle when a
  /// [PdfPanelDragScope] is in scope. Null keeps the panel non-draggable.
  final PdfDockablePanel? panel;

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
    final horizontal = widget.dock.isHorizontal;
    final geometry = PdfSidebarPanelGeometry._(
      width: _width,
      dock: widget.dock,
      bottomSheet: widget.bottomSheet,
      showGrip: showGrip,
      gripOnLeft: showGrip && widget.dock == PdfPanelDock.right,
      onClose: widget.onClose,
      panel: widget.panel,
    );
    final content = widget.builder(context, geometry);
    if (widget.bottomSheet) return content;
    if (horizontal) {
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
                side: widget.dock.gripSide,
                onWidthDelta: _resize,
                onResizeEnd: _endResize,
              ),
            ),
        ]),
      );
    }
    // top/bottom dock: a fixed-height strip; the grip rides the inner edge.
    final atTop = widget.dock == PdfPanelDock.top;
    return SizedBox(
      height: geometry.width,
      child: Stack(children: [
        Positioned.fill(child: content),
        if (showGrip)
          Positioned(
            left: 0,
            right: 0,
            top: atTop ? null : 0,
            bottom: atTop ? 0 : null,
            child: _PdfSidebarVerticalResizeGrip(
              key: widget.gripKey,
              top: atTop,
              onHeightDelta: _resize,
              onResizeEnd: _endResize,
            ),
          ),
      ]),
    );
  }
}
