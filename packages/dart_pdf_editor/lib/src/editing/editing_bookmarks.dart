import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf_document/pdf_document.dart';

import '../l10n/pdf_l10n.dart';
import '../pdf_viewer.dart';
import 'editing_controller.dart';
import 'editing_panel.dart';

/// Dockable PDF outline/bookmarks panel.
///
/// Reads and writes the document's real `/Outlines` tree. In reader mode
/// ([editable] false) it is navigation-only; in editor mode it can create,
/// edit and delete bookmark items.
class PdfBookmarkSidebar extends StatefulWidget {
  const PdfBookmarkSidebar({
    super.key,
    required this.controller,
    required this.viewerController,
    this.editable = true,
    this.dock = PdfPanelDock.left,
    this.bottomSheet = false,
    this.width = 260,
    this.minWidth = 200,
    this.maxWidth = 420,
    this.resizable = true,
    this.onClose,
  });

  final PdfEditingController controller;
  final PdfViewerController viewerController;
  final bool editable;
  final PdfPanelDock dock;
  final bool bottomSheet;
  final double width;
  final double minWidth;
  final double maxWidth;
  final bool resizable;
  final VoidCallback? onClose;

  @override
  State<PdfBookmarkSidebar> createState() => _PdfBookmarkSidebarState();
}

class _PdfBookmarkSidebarState extends State<PdfBookmarkSidebar> {
  final ScrollController _scroll = ScrollController();
  final Map<String, bool> _expanded = {};
  String? _hoveredPath;

  PdfEditingController get controller => widget.controller;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  String _keyFor(List<int> path) => path.join('.');

  bool _expandedFor(List<int> path, PdfOutlineItem item) {
    final key = _keyFor(path);
    return _expanded.putIfAbsent(key, () => item.open);
  }

  void _setHover(String pathKey, bool hovering) {
    if (!pdfPanelControlsRevealOnHover()) return;
    final next =
        hovering ? pathKey : (_hoveredPath == pathKey ? null : _hoveredPath);
    if (next == _hoveredPath) return;
    setState(() => _hoveredPath = next);
  }

  List<_BookmarkRow> _rows(List<PdfOutlineItem> items,
      {List<int> prefix = const [], int depth = 0}) {
    final out = <_BookmarkRow>[];
    for (var i = 0; i < items.length; i++) {
      final path = [...prefix, i];
      final item = items[i];
      out.add(_BookmarkRow(item: item, path: path, depth: depth));
      if (item.children.isNotEmpty && _expandedFor(path, item)) {
        out.addAll(_rows(item.children, prefix: path, depth: depth + 1));
      }
    }
    return out;
  }

  Future<void> _addBookmark(BuildContext context,
      {List<int>? parentPath}) async {
    final page = widget.viewerController.currentPage
        .clamp(0, controller.document.pageCount - 1)
        .toInt();
    final result = await _showBookmarkDialog(
      context,
      pageCount: controller.document.pageCount,
      initialTitle: pdfL10n(context).bookmarkPageLabel(page + 1),
      initialPageIndex: page,
      initialOpen: true,
      editing: false,
    );
    if (result == null) return;
    controller.addBookmark(result.title,
        pageIndex: result.pageIndex, parentPath: parentPath, open: result.open);
  }

  Future<void> _editBookmark(BuildContext context, _BookmarkRow row) async {
    final destination = row.item.destination;
    final page = (destination?.pageIndex ?? widget.viewerController.currentPage)
        .clamp(0, controller.document.pageCount - 1)
        .toInt();
    final result = await _showBookmarkDialog(
      context,
      pageCount: controller.document.pageCount,
      initialTitle: row.item.title,
      initialPageIndex: page,
      initialOpen: row.item.open,
      editing: true,
    );
    if (result == null) return;
    controller.editBookmark(row.path,
        title: result.title, pageIndex: result.pageIndex, open: result.open);
  }

  void _deleteBookmark(_BookmarkRow row) {
    controller.deleteBookmark(row.path);
  }

  void _activate(PdfOutlineItem item) {
    final destination = item.destination;
    if (destination == null) return;
    widget.viewerController.showDestination(destination);
  }

  Widget _header(
    BuildContext context, {
    required PdfSidebarPanelGeometry geometry,
  }) {
    final closeButton = geometry.closeButton(
      key: const ValueKey('pdf-bookmark-panel-close'),
    );
    final moveHandle = geometry.moveHandle(
      key: const ValueKey('pdf-bookmark-panel-move'),
    );
    final showTitle = !widget.bottomSheet;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          showTitle ? 16 : 8, 4, geometry.contentEndInset + 4, 0),
      child: Row(children: [
        if (showTitle)
          Expanded(
            child: Text(pdfL10n(context).bookmarkTitle,
                style: Theme.of(context).textTheme.titleSmall,
                overflow: TextOverflow.ellipsis),
          )
        else
          const Spacer(),
        if (widget.editable)
          IconButton(
            key: const ValueKey('pdf-bookmark-add'),
            tooltip: pdfL10n(context).bookmarkAdd,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add),
            onPressed: () => _addBookmark(context),
          ),
        if (moveHandle != null) moveHandle,
        if (closeButton != null) closeButton,
      ]),
    );
  }

  Widget _empty(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bookmarks_outlined,
                size: 34, color: scheme.onSurfaceVariant),
            const SizedBox(height: 10),
            Text(pdfL10n(context).bookmarkEmpty,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            if (widget.editable) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const ValueKey('pdf-bookmark-empty-add'),
                onPressed: () => _addBookmark(context),
                icon: const Icon(Icons.add),
                label: Text(pdfL10n(context).bookmarkAdd),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, _BookmarkRow row) {
    final item = row.item;
    final pathKey = _keyFor(row.path);
    final hasChildren = item.children.isNotEmpty;
    final expanded = hasChildren && _expandedFor(row.path, item);
    final destination = item.destination;
    final color = item.color;
    final textColor = color == null
        ? null
        : Color.fromARGB(
            255,
            (color[0].clamp(0.0, 1.0) * 255).round(),
            (color[1].clamp(0.0, 1.0) * 255).round(),
            (color[2].clamp(0.0, 1.0) * 255).round(),
          );
    final scheme = Theme.of(context).colorScheme;
    final pageLabel = destination == null
        ? pdfL10n(context).bookmarkNoDestination
        : pdfL10n(context).bookmarkPageLabel(destination.pageIndex + 1);
    final actionsVisible =
        !pdfPanelControlsRevealOnHover() || _hoveredPath == pathKey;
    final titleStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: textColor,
          fontWeight: item.bold ? FontWeight.w700 : FontWeight.w400,
          fontStyle: item.italic ? FontStyle.italic : FontStyle.normal,
        );

    return MouseRegion(
      onEnter: (_) => _setHover(pathKey, true),
      onExit: (_) => _setHover(pathKey, false),
      child: InkWell(
        key: ValueKey('pdf-bookmark-tile-$pathKey'),
        onTap: destination == null ? null : () => _activate(item),
        child: Padding(
          padding: EdgeInsets.only(left: 6 + row.depth * 16.0, right: 4),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 46),
            child: Row(children: [
              SizedBox(
                width: 28,
                child: hasChildren
                    ? IconButton(
                        key: ValueKey('pdf-bookmark-toggle-$pathKey'),
                        tooltip: expanded
                            ? pdfL10n(context).bookmarkCollapse
                            : pdfL10n(context).bookmarkExpand,
                        constraints: const BoxConstraints.tightFor(
                            width: 28, height: 28),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        iconSize: 18,
                        icon: Icon(
                            expanded ? Icons.expand_more : Icons.chevron_right),
                        onPressed: () {
                          setState(() => _expanded[pathKey] = !expanded);
                        },
                      )
                    : const SizedBox.shrink(),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          item.title.isEmpty
                              ? pdfL10n(context).bookmarkUntitled
                              : item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: titleStyle),
                      const SizedBox(height: 2),
                      Text(pageLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
              if (widget.editable)
                Visibility(
                  visible: actionsVisible,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      key: ValueKey('pdf-bookmark-add-child-$pathKey'),
                      tooltip: pdfL10n(context).bookmarkAddChild,
                      icon:
                          const Icon(Icons.subdirectory_arrow_right, size: 19),
                      onPressed: () =>
                          _addBookmark(context, parentPath: row.path),
                    ),
                    IconButton(
                      key: ValueKey('pdf-bookmark-edit-$pathKey'),
                      tooltip: pdfL10n(context).bookmarkEdit,
                      icon: const Icon(Icons.edit_outlined, size: 19),
                      onPressed: () => _editBookmark(context, row),
                    ),
                    IconButton(
                      key: ValueKey('pdf-bookmark-delete-$pathKey'),
                      tooltip: pdfL10n(context).bookmarkDelete,
                      icon: const Icon(Icons.delete_outline, size: 19),
                      onPressed: () => _deleteBookmark(row),
                    ),
                  ]),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _content(
    BuildContext context, {
    required PdfSidebarPanelGeometry geometry,
  }) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final rows = _rows(controller.outline.items);
        final showHeader =
            widget.editable || (!widget.bottomSheet && widget.onClose != null);
        return Column(children: [
          if (showHeader) _header(context, geometry: geometry),
          Expanded(
            child: rows.isEmpty
                ? _empty(context)
                : ListView.builder(
                    key: const ValueKey('pdf-bookmark-list'),
                    controller: _scroll,
                    padding: EdgeInsets.only(
                        bottom: 12,
                        right: widget.bottomSheet
                            ? 0
                            : geometry.showGrip
                                ? PdfSidebarResizeGrip.width
                                : 0),
                    itemCount: rows.length,
                    itemBuilder: (context, index) =>
                        _tile(context, rows[index]),
                  ),
          ),
        ]);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PdfSidebarPanelFrame(
      width: widget.width,
      minWidth: widget.minWidth,
      maxWidth: widget.maxWidth,
      persistedWidth: controller.preferences.bookmarkSidebarWidth,
      onPersistWidth: (width) =>
          controller.preferences.bookmarkSidebarWidth = width,
      dock: widget.dock,
      panel: PdfDockablePanel.bookmarks,
      resizable: widget.resizable,
      bottomSheet: widget.bottomSheet,
      gripKey: const ValueKey('pdf-bookmark-resize-grip'),
      onClose: widget.onClose,
      builder: (context, geometry) => Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: _content(context, geometry: geometry),
      ),
    );
  }
}

class _BookmarkRow {
  const _BookmarkRow({
    required this.item,
    required this.path,
    required this.depth,
  });

  final PdfOutlineItem item;
  final List<int> path;
  final int depth;
}

class _BookmarkEditResult {
  const _BookmarkEditResult({
    required this.title,
    required this.pageIndex,
    required this.open,
  });

  final String title;
  final int pageIndex;
  final bool open;
}

Future<_BookmarkEditResult?> _showBookmarkDialog(
  BuildContext context, {
  required int pageCount,
  required String initialTitle,
  required int initialPageIndex,
  required bool initialOpen,
  required bool editing,
}) =>
    showDialog<_BookmarkEditResult>(
      context: context,
      builder: (context) => _BookmarkDialog(
        pageCount: pageCount,
        initialTitle: initialTitle,
        initialPageIndex: initialPageIndex,
        initialOpen: initialOpen,
        editing: editing,
      ),
    );

class _BookmarkDialog extends StatefulWidget {
  const _BookmarkDialog({
    required this.pageCount,
    required this.initialTitle,
    required this.initialPageIndex,
    required this.initialOpen,
    required this.editing,
  });

  final int pageCount;
  final String initialTitle;
  final int initialPageIndex;
  final bool initialOpen;
  final bool editing;

  @override
  State<_BookmarkDialog> createState() => _BookmarkDialogState();
}

class _BookmarkDialogState extends State<_BookmarkDialog> {
  late final TextEditingController _title =
      TextEditingController(text: widget.initialTitle);
  late final TextEditingController _page =
      TextEditingController(text: '${widget.initialPageIndex + 1}');
  late bool _open = widget.initialOpen;

  @override
  void dispose() {
    _title.dispose();
    _page.dispose();
    super.dispose();
  }

  void _save() {
    final text = _title.text.trim();
    final parsed = int.tryParse(_page.text.trim());
    if (text.isEmpty || parsed == null) return;
    final pageIndex = (parsed - 1).clamp(0, widget.pageCount - 1).toInt();
    Navigator.of(context).pop(
      _BookmarkEditResult(title: text, pageIndex: pageIndex, open: _open),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.editing
            ? pdfL10n(context).bookmarkEdit
            : pdfL10n(context).bookmarkAdd),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const ValueKey('pdf-bookmark-title'),
                controller: _title,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: pdfL10n(context).bookmarkTitleLabel,
                  border: const OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('pdf-bookmark-page'),
                controller: _page,
                decoration: InputDecoration(
                  labelText: pdfL10n(context).bookmarkPageFieldLabel,
                  helperText: pdfL10n(context).bookmarkPageRangeHint(widget.pageCount),
                  border: const OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
              CheckboxListTile(
                key: const ValueKey('pdf-bookmark-open'),
                contentPadding: EdgeInsets.zero,
                title: Text(pdfL10n(context).bookmarkExpandedByDefault),
                value: _open,
                onChanged: (value) => setState(() => _open = value ?? _open),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(pdfL10n(context).cancel),
          ),
          FilledButton(
            key: const ValueKey('pdf-bookmark-save'),
            onPressed: _save,
            child: Text(pdfL10n(context).save),
          ),
        ],
      );
}
