// The dock and panel identities the shell persists, kept apart from the
// Material panel chrome in editing_panel.dart (which re-exports them) so the
// preferences - and through them the editing controller - can name them
// without importing flutter/material. See tool/check_design_imports.dart.

import 'package:flutter/widgets.dart' show BuildContext, IconData;

import '../../l10n/pdf_l10n.dart';

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
  // Material Icons glyphs as plain const IconData (the same values as
  // Icons.grid_view, Icons.manage_search, Icons.bookmarks_outlined,
  // Icons.list_alt, Icons.tune and Icons.collections_bookmark_outlined, so
  // they compare equal to them) - the enum is data, and data stays on the
  // widgets layer.
  thumbnails(IconData(0xe2ea, fontFamily: 'MaterialIcons')),
  search(IconData(0xe3c7, fontFamily: 'MaterialIcons')),
  bookmarks(IconData(0xeee5, fontFamily: 'MaterialIcons')),
  annotations(
      IconData(0xe385, fontFamily: 'MaterialIcons', matchTextDirection: true)),
  properties(IconData(0xe683, fontFamily: 'MaterialIcons')),
  annotationLibrary(IconData(0xef69, fontFamily: 'MaterialIcons'));

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
      PdfDockablePanel.annotationLibrary => l.annotationLibraryTitle,
    };
  }
}
