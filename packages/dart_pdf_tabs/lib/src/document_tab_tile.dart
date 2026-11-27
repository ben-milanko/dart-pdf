import 'package:material_ui/material_ui.dart';

import 'document_tabs_labels.dart';
import 'middle_ellipsis_text.dart';

/// A grid tile's part in a [DocumentTabsOverview]'s multi-select: whether
/// the grid is selecting at all, whether this tile is checked, and how to
/// flip it (which also starts selecting, from a long-press).
typedef DocumentTabTileSelection = ({
  bool selecting,
  bool checked,
  VoidCallback toggle,
});

/// One tab in a [DocumentTabsOverview]: a preview over the tab's title, with
/// a close button - or, while the overview is selecting, a checkbox.
class DocumentTabTile extends StatelessWidget {
  const DocumentTabTile({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    required this.onClose,
    this.preview,
    this.isDirty = false,
    this.selection,
    this.onContextMenu,
    this.labels = const DocumentTabsLabels(),
    this.hidePdfExtension = true,
  });

  /// The tab's title; empty shows [DocumentTabsLabels.untitled].
  final String title;

  /// What fills the tile above the title, typically a first-page thumbnail.
  /// A document icon stands in when null.
  final Widget? preview;

  /// Whether the tab has unsaved changes (a dot before its title).
  final bool isDirty;

  /// Whether this is the active tab.
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onClose;

  /// The overview's multi-select: while it is selecting a tap checks the tile
  /// instead of switching to it and a checkbox stands in for the close
  /// button; a long-press starts selecting with this tile checked.
  final DocumentTabTileSelection? selection;

  /// Opens the tab's context menu at the given global position (right-click
  /// on desktop, long-press on touch when the tile is not selectable). Null
  /// disables the affordance.
  final void Function(Offset globalPosition)? onContextMenu;

  final DocumentTabsLabels labels;

  /// Whether the title hides a trailing `.pdf` (see [MiddleEllipsisText]).
  final bool hidePdfExtension;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selection = this.selection;
    final selecting = selection?.selecting ?? false;
    final checked = selection?.checked ?? false;
    final highlighted = selecting ? checked : selected;
    final onContextMenu = this.onContextMenu;
    return Material(
      key: const ValueKey('mobile-tab-tile'),
      color: selected ? scheme.secondaryContainer : scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: highlighted ? scheme.primary : scheme.outlineVariant,
          width: highlighted ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: selecting ? selection!.toggle : onTap,
        onSecondaryTapUp: onContextMenu == null || selecting
            ? null
            : (details) => onContextMenu(details.globalPosition),
        // A long-press starts (or extends) a multi-select, the touch
        // convention; without one it opens the context menu instead.
        onLongPress: selection != null
            ? selection.toggle
            : onContextMenu == null
                ? null
                : () {
                    // InkWell's long-press carries no position, so anchor the
                    // menu at the tile's centre.
                    final box = context.findRenderObject() as RenderBox?;
                    if (box == null || !box.hasSize) return;
                    onContextMenu(
                        box.localToGlobal(box.size.center(Offset.zero)));
                  },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                child: preview ??
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.description_outlined,
                          size: 40,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(10, 0, 4, 6),
              child: Row(
                children: [
                  if (isDirty)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 6),
                      child: Icon(Icons.circle, size: 8, color: scheme.primary),
                    ),
                  Expanded(
                    child: MiddleEllipsisText(
                      title.isEmpty ? labels.untitled : title,
                      hidePdfExtension: hidePdfExtension && title.isNotEmpty,
                      style: TextStyle(
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.normal,
                        color: selected
                            ? scheme.onSecondaryContainer
                            : scheme.onSurface,
                      ),
                    ),
                  ),
                  if (selecting)
                    SizedBox.square(
                      dimension: 32,
                      child: Checkbox(
                        key: const ValueKey('mobile-tab-tile-checkbox'),
                        value: checked,
                        visualDensity: VisualDensity.compact,
                        onChanged: (_) => selection!.toggle(),
                      ),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: labels.closeTab,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints.tightFor(width: 32, height: 32),
                      onPressed: onClose,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
