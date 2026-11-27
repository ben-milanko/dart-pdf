import 'package:flutter/widgets.dart';

/// An entry the host app adds to the page-thumbnail context menu (the
/// right-click menu on a strip or grid tile), alongside the built-in rotate,
/// duplicate, insert, export and delete actions.
///
/// Built per right-click by a [PdfPageMenuActionsBuilder], so the label and
/// [enabled] state can reflect the page that was clicked.
@immutable
class PdfPageMenuAction {
  const PdfPageMenuAction({
    required this.label,
    required this.onSelected,
    this.icon,
    this.enabled = true,
    this.key,
  });

  /// The row's text, e.g. "Copy link to page 3".
  final String label;

  /// Runs after the menu closes when the row is picked.
  final VoidCallback onSelected;

  /// The row's leading icon. Without one the row keeps the icon column's
  /// indent, so its text lines up with the built-in entries.
  final IconData? icon;

  /// A disabled row is shown dimmed and cannot be picked.
  final bool enabled;

  /// A stable identifier for the row, applied as its `ValueKey` so tests and
  /// automation can find it (the built-in rows use `pdf-thumbnail-menu-*`).
  final String? key;
}

/// Builds the host's extra page-thumbnail menu entries for one right-click.
///
/// [pageIndex] is the 0-based page that was right-clicked. [selectedPages]
/// are the pages the built-in actions act on: the strip's selection when the
/// clicked page belongs to it, otherwise just [pageIndex]; it always contains
/// [pageIndex]. Return an empty list to add nothing for this click.
///
/// The entries appear after the built-in insert entries and before Export,
/// in the order returned.
typedef PdfPageMenuActionsBuilder = List<PdfPageMenuAction> Function(
  BuildContext context,
  int pageIndex,
  List<int> selectedPages,
);

/// Signature for `PdfEditorView.pageThumbnailOverlayBuilder` (also on
/// `PdfReader`, `PdfThumbnailSidebar` and `PdfThumbnailView`): returns
/// widgets stacked over the thumbnail of [pageIndex], in the strip and the
/// grid alike - page status badges, review marks, counts. Wrap each in a
/// `Positioned` to place it; unpositioned widgets fill the thumbnail.
///
/// Called whenever the tile builds, so the overlays should listen to their
/// own state (a `ListenableBuilder`, an `Observer`) rather than rely on the
/// strip to rebuild them. Avoid `Tooltip` here: a Tooltip is an
/// OverlayPortal, and the strip's tiles live in a ReorderableListView whose
/// items can be reactivated mid-layout - use a `Semantics` label instead.
typedef PdfPageThumbnailOverlayBuilder = List<Widget> Function(
  BuildContext context,
  int pageIndex,
);
