import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../dialog.dart';
import '../l10n/pdf_l10n.dart';
import 'annotation_presentation.dart';
import 'editing_controller.dart';
import 'editing_panel.dart';
import 'editing_stamps.dart';
import 'saved_annotation.dart';
import 'text_prompt.dart';

/// Opens the reusable annotation library.
///
/// Tapping an item arms it on the pointer for placement and leaves it on the
/// ordinary annotation clipboard, so Paste can also repeat it in this PDF or
/// another one.
/// The Custom stamps action keeps the specialized stamp designer alongside
/// the broader snapshot-based library.
Future<void> showPdfAnnotationLibrary(
  BuildContext context, {
  required PdfEditingController controller,
  required int pageIndex,
  PdfImagePicker? imagePicker,
  PdfStampExportCallback? onExportStamps,
  PdfStampImportCallback? onImportStamps,
}) =>
    showPdfDialog<void>(
      context: context,
      builder: (context) => PdfAnnotationLibraryDialog(
        controller: controller,
        pageIndex: pageIndex,
        imagePicker: imagePicker,
        onExportStamps: onExportStamps,
        onImportStamps: onImportStamps,
      ),
    );

/// A dockable, searchable library of reusable annotation snapshots.
///
/// Items are collected under user-defined groups. Tapping one arms it as a
/// cursor-following placement tool; the next page click drops it, and it stays
/// armed for repeat placement until Escape or another tool is selected.
class PdfAnnotationLibraryPanel extends StatefulWidget {
  const PdfAnnotationLibraryPanel({
    super.key,
    required this.controller,
    this.width = 300,
    this.dock = PdfPanelDock.right,
    this.resizable = true,
    this.minWidth = 220,
    this.maxWidth = 480,
    this.bottomSheet = false,
    this.onClose,
    this.imagePicker,
    this.onExportStamps,
    this.onImportStamps,
  });

  final PdfEditingController controller;
  final double width;
  final PdfPanelDock dock;
  final bool resizable;
  final double minWidth;
  final double maxWidth;
  final bool bottomSheet;
  final VoidCallback? onClose;
  final PdfImagePicker? imagePicker;
  final PdfStampExportCallback? onExportStamps;
  final PdfStampImportCallback? onImportStamps;

  @override
  State<PdfAnnotationLibraryPanel> createState() =>
      _PdfAnnotationLibraryPanelState();
}

enum _LibraryItemAction { rename, group, delete }

class _AnnotationGroupChoice {
  const _AnnotationGroupChoice.group(this.group) : create = false;
  const _AnnotationGroupChoice.create()
      : group = null,
        create = true;

  final String? group;
  final bool create;
}

class _PdfAnnotationLibraryPanelState extends State<PdfAnnotationLibraryPanel> {
  final TextEditingController _search = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode(debugLabel: 'annotation library');

  PdfEditingController get _controller => widget.controller;

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _rename(PdfSavedAnnotation annotation) async {
    final name = await showPdfTextPrompt(
      context,
      title: pdfL10n(context).annotationLibraryRenameTitle,
      initial: annotation.name,
      multiline: false,
    );
    if (name != null) _controller.renameSavedAnnotation(annotation, name);
  }

  Future<void> _renameGroup(String group) async {
    final name = await showPdfTextPrompt(
      context,
      title: pdfL10n(context).annotationLibraryRenameGroupTitle,
      initial: group,
      multiline: false,
    );
    if (name != null) _controller.renameSavedAnnotationGroup(group, name);
  }

  Future<void> _chooseGroup(PdfSavedAnnotation annotation) async {
    final choice = await showPdfDialog<_AnnotationGroupChoice>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(pdfL10n(context).annotationLibraryChooseGroup),
        children: [
          SimpleDialogOption(
            key: const ValueKey('pdf-annotation-library-group-ungrouped'),
            onPressed: () => Navigator.of(dialogContext).pop(
              const _AnnotationGroupChoice.group(null),
            ),
            child: Text(pdfL10n(context).annotationLibraryUngrouped),
          ),
          for (final group in _controller.savedAnnotationGroups)
            SimpleDialogOption(
              key: ValueKey('pdf-annotation-library-group-$group'),
              onPressed: () => Navigator.of(dialogContext).pop(
                _AnnotationGroupChoice.group(group),
              ),
              child: Text(group),
            ),
          const Divider(),
          SimpleDialogOption(
            key: const ValueKey('pdf-annotation-library-group-new'),
            onPressed: () => Navigator.of(dialogContext).pop(
              const _AnnotationGroupChoice.create(),
            ),
            child: Row(children: [
              const Icon(Icons.create_new_folder_outlined),
              const SizedBox(width: 12),
              Text(pdfL10n(context).annotationLibraryNewGroup),
            ]),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    var group = choice.group;
    if (choice.create) {
      group = await showPdfTextPrompt(
        context,
        title: pdfL10n(context).annotationLibraryGroupTitle,
        multiline: false,
      );
      if (group == null || !mounted) return;
    }
    _controller.groupSavedAnnotation(annotation, group);
  }

  Future<void> _itemAction(
      PdfSavedAnnotation annotation, _LibraryItemAction action) async {
    switch (action) {
      case _LibraryItemAction.rename:
        await _rename(annotation);
      case _LibraryItemAction.group:
        await _chooseGroup(annotation);
      case _LibraryItemAction.delete:
        _controller.removeSavedAnnotation(annotation);
    }
  }

  void _activate(PdfSavedAnnotation annotation) {
    if (!_controller.beginSavedAnnotationPlacement(annotation)) return;
    _focus.requestFocus();
    // A compact bottom sheet covers the page it asks the user to click. Close
    // it after arming; a docked desktop panel remains open for quick reuse.
    if (widget.bottomSheet) {
      _controller.preferences.showAnnotationLibraryPanel = false;
    }
  }

  Future<void> _stamps() => showPdfStampPicker(
        context,
        controller: _controller,
        imagePicker: widget.imagePicker,
        onExportStamps: widget.onExportStamps,
        onImportStamps: widget.onImportStamps,
      );

  bool _matches(PdfSavedAnnotation annotation, String query) {
    if (query.isEmpty) return true;
    return annotation.name.toLowerCase().contains(query) ||
        annotation.snapshot.subtype.toLowerCase().contains(query) ||
        (annotation.group?.toLowerCase().contains(query) ?? false);
  }

  Widget _groupHeader(String? group) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 4, 2),
      child: Row(children: [
        Icon(group == null ? Icons.folder_off_outlined : Icons.folder_outlined,
            size: 17, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            group ?? pdfL10n(context).annotationLibraryUngrouped,
            style: theme.textTheme.labelMedium
                ?.copyWith(color: theme.colorScheme.primary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (group != null) ...[
          IconButton(
            key: ValueKey('pdf-annotation-library-group-rename-$group'),
            icon: const Icon(Icons.edit_outlined, size: 17),
            tooltip: pdfL10n(context).rename,
            visualDensity: VisualDensity.compact,
            onPressed: () => _renameGroup(group),
          ),
          IconButton(
            key: ValueKey('pdf-annotation-library-group-delete-$group'),
            icon: const Icon(Icons.folder_delete_outlined, size: 17),
            tooltip: pdfL10n(context).annotationLibraryRemoveGroup,
            visualDensity: VisualDensity.compact,
            onPressed: () => _controller.removeSavedAnnotationGroup(group),
          ),
        ],
      ]),
    );
  }

  Widget _item(PdfSavedAnnotation annotation) {
    final active = _controller.activeSavedAnnotation?.id == annotation.id;
    return ListTile(
      key: ValueKey('pdf-annotation-library-item-${annotation.id}'),
      selected: active,
      leading: PdfSavedAnnotationPreview(annotation: annotation),
      title: Text(annotation.name, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        pdfAnnotationLabel(context, annotation.snapshot.subtype),
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => _activate(annotation),
      trailing: PopupMenuButton<_LibraryItemAction>(
        key: ValueKey('pdf-annotation-library-menu-${annotation.id}'),
        tooltip: pdfL10n(context).sidebarMore,
        onSelected: (action) => _itemAction(annotation, action),
        itemBuilder: (context) => [
          PopupMenuItem(
            value: _LibraryItemAction.rename,
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.edit_outlined),
              title: Text(pdfL10n(context).rename),
            ),
          ),
          PopupMenuItem(
            value: _LibraryItemAction.group,
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.drive_file_move_outline),
              title: Text(pdfL10n(context).annotationLibraryChooseGroup),
            ),
          ),
          PopupMenuItem(
            value: _LibraryItemAction.delete,
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.delete_outline),
              title: Text(pdfL10n(context).delete),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final preferences = _controller.preferences;
    return PdfSidebarPanelFrame(
      width: widget.width,
      minWidth: widget.minWidth,
      maxWidth: widget.maxWidth,
      persistedWidth: preferences.annotationLibraryPanelWidth,
      onPersistWidth: (width) =>
          preferences.annotationLibraryPanelWidth = width,
      dock: widget.dock,
      panel: PdfDockablePanel.annotationLibrary,
      resizable: widget.resizable,
      bottomSheet: widget.bottomSheet,
      gripKey: const ValueKey('pdf-annotation-library-resize-grip'),
      onClose: widget.onClose,
      builder: (context, geometry) {
        final moveHandle = geometry.moveHandle(
          key: const ValueKey('pdf-annotation-library-panel-move'),
        );
        final closeButton = geometry.closeButton(
          key: const ValueKey('pdf-annotation-library-panel-close'),
        );
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape):
                _controller.cancelSavedAnnotationPlacement,
          },
          child: Focus(
            focusNode: _focus,
            child: Material(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: ListenableBuilder(
                listenable: _controller,
                builder: (context, _) {
                  final query = _search.text.trim().toLowerCase();
                  final matches = [
                    for (final annotation in _controller.savedAnnotations)
                      if (_matches(annotation, query)) annotation,
                  ];
                  final groups = <String?, List<PdfSavedAnnotation>>{};
                  for (final annotation in matches) {
                    groups
                        .putIfAbsent(annotation.group, () => [])
                        .add(annotation);
                  }
                  final groupNames = groups.keys.toList()
                    ..sort((a, b) {
                      if (a == null) return 1;
                      if (b == null) return -1;
                      return a.toLowerCase().compareTo(b.toLowerCase());
                    });
                  return Column(children: [
                    Padding(
                      padding: EdgeInsetsDirectional.fromSTEB(
                        16 + geometry.contentStartInset,
                        4,
                        4 + geometry.contentEndInset,
                        0,
                      ),
                      child: Row(children: [
                        Expanded(
                          child: Text(
                            pdfL10n(context).annotationLibraryTitle,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        IconButton(
                          key: const ValueKey('pdf-annotation-library-stamps'),
                          onPressed: _stamps,
                          icon: const Icon(Icons.approval_outlined, size: 19),
                          tooltip:
                              pdfL10n(context).annotationLibraryCustomStamps,
                          visualDensity: VisualDensity.compact,
                        ),
                        if (moveHandle != null) moveHandle,
                        if (closeButton != null) closeButton,
                      ]),
                    ),
                    Padding(
                      padding: EdgeInsetsDirectional.fromSTEB(
                        12 + geometry.contentStartInset,
                        4,
                        12 + geometry.contentEndInset,
                        8,
                      ),
                      child: TextField(
                        key: const ValueKey('pdf-annotation-library-search'),
                        controller: _search,
                        decoration: InputDecoration(
                          hintText:
                              pdfL10n(context).annotationLibrarySearchHint,
                          prefixIcon: const Icon(Icons.search, size: 18),
                          isDense: true,
                          suffixIcon: query.isEmpty
                              ? null
                              : IconButton(
                                  key: const ValueKey(
                                      'pdf-annotation-library-search-clear'),
                                  onPressed: () => setState(_search.clear),
                                  icon: const Icon(Icons.close, size: 17),
                                  tooltip: pdfL10n(context).searchClearSearch,
                                ),
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    if (_controller.activeSavedAnnotation != null)
                      Material(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        child: Padding(
                          padding: EdgeInsetsDirectional.fromSTEB(
                            12 + geometry.contentStartInset,
                            6,
                            4 + geometry.contentEndInset,
                            6,
                          ),
                          child: Row(children: [
                            const Icon(Icons.ads_click, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                pdfL10n(context).annotationLibraryPlacementHint,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            IconButton(
                              key: const ValueKey(
                                  'pdf-annotation-library-placement-cancel'),
                              onPressed:
                                  _controller.cancelSavedAnnotationPlacement,
                              icon: const Icon(Icons.close, size: 18),
                              tooltip: pdfL10n(context).cancel,
                              visualDensity: VisualDensity.compact,
                            ),
                          ]),
                        ),
                      ),
                    Expanded(
                      child: matches.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  _controller.savedAnnotations.isEmpty
                                      ? pdfL10n(context).annotationLibraryEmpty
                                      : pdfL10n(context)
                                          .annotationLibraryNoMatches,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          : geometry.withScrollbar(
                              scroll: _scroll,
                              thumbKey: const ValueKey(
                                  'pdf-annotation-library-scrollbar-thumb'),
                              child: ScrollConfiguration(
                                behavior: ScrollConfiguration.of(context)
                                    .copyWith(scrollbars: false),
                                child: ListView(
                                  key: const ValueKey(
                                      'pdf-annotation-library-list'),
                                  controller: _scroll,
                                  padding: EdgeInsetsDirectional.only(
                                    end: geometry.scrollbarClearance,
                                    bottom: 12,
                                  ),
                                  children: [
                                    for (final group in groupNames) ...[
                                      _groupHeader(group),
                                      for (final annotation in groups[group]!)
                                        _item(annotation),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                    ),
                  ]);
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Legacy modal wrapper for hosts that have not adopted
/// [PdfAnnotationLibraryPanel]. The stock [PdfEditorView] uses the dockable
/// panel.
class PdfAnnotationLibraryDialog extends StatelessWidget {
  const PdfAnnotationLibraryDialog({
    super.key,
    required this.controller,
    required this.pageIndex,
    this.imagePicker,
    this.onExportStamps,
    this.onImportStamps,
  });

  final PdfEditingController controller;
  final int pageIndex;
  final PdfImagePicker? imagePicker;
  final PdfStampExportCallback? onExportStamps;
  final PdfStampImportCallback? onImportStamps;

  Future<void> _rename(
      BuildContext context, PdfSavedAnnotation annotation) async {
    final name = await showPdfTextPrompt(
      context,
      title: pdfL10n(context).annotationLibraryRenameTitle,
      initial: annotation.name,
      multiline: false,
    );
    if (name != null) controller.renameSavedAnnotation(annotation, name);
  }

  void _activate(BuildContext context, PdfSavedAnnotation annotation) {
    if (!controller.beginSavedAnnotationPlacement(annotation)) return;
    Navigator.of(context).pop();
  }

  Future<void> _stamps(BuildContext context) => showPdfStampPicker(
        context,
        controller: controller,
        imagePicker: imagePicker,
        onExportStamps: onExportStamps,
        onImportStamps: onImportStamps,
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(pdfL10n(context).annotationLibraryTitle),
      content: SizedBox(
        width: 380,
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final annotations = controller.savedAnnotations;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: annotations.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(pdfL10n(context).annotationLibraryEmpty),
                        )
                      : ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 360),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: annotations.length,
                            itemBuilder: (context, index) {
                              final annotation = annotations[index];
                              return ListTile(
                                key: ValueKey(
                                    'pdf-annotation-library-item-$index'),
                                leading: PdfSavedAnnotationPreview(
                                    annotation: annotation),
                                title: Text(annotation.name),
                                subtitle: Text(pdfAnnotationLabel(
                                    context, annotation.snapshot.subtype)),
                                onTap: () => _activate(context, annotation),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      key: ValueKey(
                                          'pdf-annotation-library-rename-$index'),
                                      icon: const Icon(Icons.edit_outlined),
                                      tooltip: pdfL10n(context).rename,
                                      onPressed: () =>
                                          _rename(context, annotation),
                                    ),
                                    IconButton(
                                      key: ValueKey(
                                          'pdf-annotation-library-delete-$index'),
                                      icon: const Icon(Icons.delete_outline),
                                      tooltip: pdfL10n(context).delete,
                                      onPressed: () => controller
                                          .removeSavedAnnotation(annotation),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                ),
                const SizedBox(height: 12),
                Text(
                  pdfL10n(context).annotationLibraryHelp,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton.icon(
          key: const ValueKey('pdf-annotation-library-stamps'),
          onPressed: () => _stamps(context),
          icon: const Icon(Icons.approval_outlined),
          label: Text(pdfL10n(context).annotationLibraryCustomStamps),
        ),
        PdfDialogSubmit(
            child: TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(pdfL10n(context).close),
        )),
      ],
    );
  }
}

/// Compact subtype preview used by the stock annotation library.
class PdfSavedAnnotationPreview extends StatelessWidget {
  const PdfSavedAnnotationPreview({
    super.key,
    required this.annotation,
  });

  final PdfSavedAnnotation annotation;

  @override
  Widget build(BuildContext context) {
    final icon = pdfAnnotationIcon(annotation.snapshot.subtype);
    final rect = annotation.snapshot.rect;
    return Container(
      width: 48,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Tooltip(
        message:
            '${rect.width.toStringAsFixed(0)} × ${rect.height.toStringAsFixed(0)} pt',
        child: Icon(icon,
            size: 23,
            color: Theme.of(context).colorScheme.onSecondaryContainer),
      ),
    );
  }
}
