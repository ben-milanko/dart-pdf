// A host's own dock panel for PdfEditorView.extraPanels: an id, how it is
// labelled in the panel switch, where it docks first, and how to build its
// body. Widgets-layer types only; the editor supplies the frame.

import 'package:flutter/widgets.dart';

import 'editing_panel.dart' show PdfSidebarPanelGeometry;
import 'models/panel_dock.dart';

/// Builds a host panel's content inside the frame the editor gives it - a
/// resizable column or strip on its dock, or a bottom sheet on a compact
/// layout ([PdfSidebarPanelGeometry.bottomSheet]). Use [geometry] the way
/// the stock panels do: [PdfSidebarPanelGeometry.moveHandle] and
/// [PdfSidebarPanelGeometry.closeButton] for a header row (both null in a
/// sheet, whose own chrome has the title and close button), and the
/// content insets for the resize grip.
typedef PdfEditorPanelBuilder = Widget Function(
    BuildContext context, PdfSidebarPanelGeometry geometry);

/// A host's own panel, shown by `PdfEditorView(extraPanels: [...])` beside
/// the stock ones: a toggle in the panel switch (and the compact Controls
/// sheet), a frame on its dock with a resize grip and a move handle that
/// redocks it to another edge, and a bottom sheet on compact layouts. Its
/// dock, width and - unless [open] is given - whether it is open persist in
/// `PdfEditingPreferences`, keyed by [id].
///
/// ```dart
/// PdfEditorView(
///   bytes: bytes,
///   extraPanels: [
///     PdfEditorPanel(
///       id: 'comments',
///       icon: Icons.forum_outlined,
///       label: 'Comments',
///       builder: (context, geometry) => Column(children: [
///         Row(children: [
///           if (geometry.moveHandle() case final handle?) handle,
///           const Expanded(child: Text('Comments')),
///           if (geometry.closeButton() case final close?) close,
///         ]),
///         const Expanded(child: MyComments()),
///       ]),
///     ),
///   ],
/// )
/// ```
///
/// A host panel docks on its own: it does not join a stock panel's tab
/// group. Like the Pages and Bookmarks panels it stays available in the
/// reflow view and steps aside only for the full-area page grid.
@immutable
class PdfEditorPanel {
  const PdfEditorPanel({
    required this.id,
    required this.icon,
    required this.label,
    required this.builder,
    this.defaultDock = PdfPanelDock.right,
    this.width = 300,
    this.minWidth = 200,
    this.maxWidth = 560,
    this.open,
    this.showInPanelSwitch = true,
  });

  /// Identifies the panel in the persisted preferences and in its keys
  /// (`pdf-shell-panel-<id>-toggle`, `...-docked`, `...-sheet`). Unique
  /// among a view's extra panels, and stable across runs.
  final String id;

  /// The panel switch glyph, also shown on the drag chip.
  final IconData icon;

  /// The panel's name: the panel switch tooltip, the Controls sheet row,
  /// the sheet title and the drag chip. Localize it.
  final String label;

  /// Builds the panel's content in the editor's frame.
  final PdfEditorPanelBuilder builder;

  /// Where the panel docks until the user moves it.
  final PdfPanelDock defaultDock;

  /// The panel's extent across its dock (the column width, or the strip
  /// height on the top/bottom docks), and the range the grip resizes it in.
  final double width;
  final double minWidth;
  final double maxWidth;

  /// Whether the panel is open, when the host keeps that state itself (a
  /// keyboard shortcut of its own, a menu): the panel follows it and the
  /// panel switch and close button write it. Null keeps it in the
  /// preferences, persisted like the stock panels' visibility.
  final ValueNotifier<bool>? open;

  /// Whether the panel has a toggle in the panel switch and the compact
  /// Controls sheet. Off for a panel the host opens some other way ([open]).
  final bool showInPanelSwitch;

  @override
  bool operator ==(Object other) =>
      other is PdfEditorPanel &&
      other.id == id &&
      other.icon == icon &&
      other.label == label &&
      other.builder == builder &&
      other.defaultDock == defaultDock &&
      other.width == width &&
      other.minWidth == minWidth &&
      other.maxWidth == maxWidth &&
      other.open == open &&
      other.showInPanelSwitch == showInPanelSwitch;

  @override
  int get hashCode => Object.hash(id, icon, label, builder, defaultDock, width,
      minWidth, maxWidth, open, showInPanelSwitch);
}
