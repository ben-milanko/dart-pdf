import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

import '../pdf_viewer.dart';
import '../scrollbar.dart';
import 'editing_controller.dart';
import 'editing_panel.dart';
import 'editing_preferences.dart';

/// A panel listing every annotation in the document, grouped by page,
/// each tile showing its author (/T) when the annotation carries one.
/// Form-field tiles show the field's kind, fully qualified name, and
/// current value; link tiles show the text under the link and where it
/// goes (the URI, or the target page).
///
/// Tapping a tile zooms the viewer to the annotation, selects it
/// (arming the select tool), and pulses an attention flash around it on
/// the page; the trailing button deletes it. A long press starts
/// multi-select: checkboxes replace the icons, tapping toggles, and the
/// header's delete removes everything checked as one undo step. The
/// list rebuilds on every revision, so it always reflects the current
/// state — including undo and redo.
///
/// The inner edge is draggable ([resizable]); the chosen width persists
/// via [PdfEditingPreferences.annotationSidebarWidth].
///
/// Place it beside the viewer, typically in a [Row]:
///
/// ```dart
/// Row(children: [
///   Expanded(child: PdfViewer(...)),
///   PdfAnnotationSidebar(
///     controller: editing,
///     viewerController: viewerController,
///   ),
/// ])
/// ```
class PdfAnnotationSidebar extends StatefulWidget {
  const PdfAnnotationSidebar({
    super.key,
    required this.controller,
    required this.viewerController,
    this.width = 280,
    this.side = PdfSidebarSide.right,
    this.resizable = true,
    this.minWidth = 200,
    this.maxWidth = 480,
    this.bottomSheet = false,
  });

  final PdfEditingController controller;

  /// The viewer to navigate when a tile is tapped.
  final PdfViewerController viewerController;

  /// The default width — a user-dragged width, persisted in
  /// [PdfEditingPreferences.annotationSidebarWidth], wins over it.
  final double width;

  /// Which side of the viewer the panel sits on; the resize grip rides
  /// the opposite (inner) edge.
  final PdfSidebarSide side;

  /// Whether the inner edge can be dragged to resize the panel.
  final bool resizable;

  /// Clamps for the dragged width.
  final double minWidth;
  final double maxWidth;

  /// Lays the panel out to fill its parent (full width, no side resize
  /// grip) for hosting inside a bottom sheet on a small screen, rather
  /// than as a fixed-width docked column.
  final bool bottomSheet;

  @override
  State<PdfAnnotationSidebar> createState() => _PdfAnnotationSidebarState();
}

class _PdfAnnotationSidebarState extends State<PdfAnnotationSidebar> {
  /// Links and form fields are listed but not selectable (the select
  /// tool refuses them too); popups belong to their parent annotation
  /// and are not listed at all.
  static const _unlisted = {'Popup'};
  static const _unselectable = {'Link', 'Widget'};

  /// Checked tiles in multi-select mode, as (page, /Annots slot).
  final Set<(int, int)> _checked = {};
  bool _selecting = false;

  final ScrollController _scroll = ScrollController();

  /// The filter text; tiles whose title or subtitle don't contain it
  /// (case-insensitive) are hidden. Survives revisions — a search isn't
  /// invalidated by an edit.
  final TextEditingController _search = TextEditingController();

  /// The document revision the selection state belongs to. Any edit,
  /// undo, or redo can shift /Annots slots, so a new revision drops it.
  PdfDocument? _builtFor;

  /// Extracted page text for link tiles ("the text under the link"),
  /// per page, for the current revision only — extraction interprets
  /// the page, so it runs once per page that actually lists a link and
  /// the cache dies with [_builtFor]. Null entries are failed or
  /// text-free extractions.
  final Map<int, PdfPageText?> _pageTexts = {};

  /// The panel width while a resize drag is in flight, overriding the
  /// preference until the drag ends and persists it.
  double? _dragWidth;

  PdfEditingPreferences get _preferences => widget.controller.preferences;

  double get _width =>
      (_dragWidth ?? _preferences.annotationSidebarWidth ?? widget.width)
          .clamp(widget.minWidth, widget.maxWidth);

  @override
  void initState() {
    super.initState();
    _preferences.addListener(_onPreferences);
  }

  @override
  void didUpdateWidget(PdfAnnotationSidebar old) {
    super.didUpdateWidget(old);
    if (!identical(old.controller.preferences, _preferences)) {
      old.controller.preferences.removeListener(_onPreferences);
      _preferences.addListener(_onPreferences);
    }
  }

  @override
  void dispose() {
    _preferences.removeListener(_onPreferences);
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onPreferences() {
    if (mounted) setState(() {});
  }

  void _onResizeDelta(double delta) => setState(() {
        _dragWidth = (_width + delta).clamp(widget.minWidth, widget.maxWidth);
      });

  void _onResizeEnd() {
    if (_dragWidth == null) return;
    _preferences.annotationSidebarWidth = _dragWidth;
    setState(() => _dragWidth = null);
  }

  static IconData _icon(String subtype) => switch (subtype) {
        'Highlight' => Icons.border_color,
        'Underline' => Icons.format_underlined,
        'StrikeOut' => Icons.format_strikethrough,
        'Squiggly' => Icons.gesture,
        'Ink' => Icons.draw,
        'Square' => Icons.rectangle_outlined,
        'Circle' => Icons.circle_outlined,
        'FreeText' => Icons.text_fields,
        'Text' => Icons.sticky_note_2_outlined,
        'Stamp' => Icons.approval,
        'Link' => Icons.link,
        'Widget' => Icons.input,
        'FileAttachment' => Icons.attach_file,
        _ => Icons.bookmark_border,
      };

  static String _label(String subtype) => switch (subtype) {
        'StrikeOut' => 'Strike-out',
        'FreeText' => 'Text box',
        'Text' => 'Note',
        'Widget' => 'Form field',
        _ => subtype,
      };

  /// A finer title for form fields, from the inherited /FT.
  static String _fieldLabel(String? fieldType) => switch (fieldType) {
        'Tx' => 'Text field',
        'Btn' => 'Button field',
        'Ch' => 'Choice field',
        'Sig' => 'Signature field',
        _ => 'Form field',
      };

  /// Where an action leads, for a link tile's subtitle.
  static String? _actionLabel(PdfAction? action) => switch (action) {
        PdfUriAction(:final uri) => uri,
        PdfGoToAction(:final destination) =>
          'Page ${destination.pageIndex + 1}',
        PdfNamedAction(:final name) => name,
        PdfJavaScriptAction() => 'JavaScript',
        PdfUnknownAction(:final type) => type.isEmpty ? null : type,
        null => null,
      };

  PdfPageText? _pageText(int page) {
    if (_pageTexts.containsKey(page)) return _pageTexts[page];
    PdfPageText? text;
    try {
      text = PdfTextExtractor.extract(widget.controller.document, page);
    } catch (_) {
      // a page that won't interpret still lists its annotations
    }
    return _pageTexts[page] = text;
  }

  /// The tile subtitle: author — contents for markup, name — value for
  /// form fields, link text — target for links.
  String _detail(int pageIndex, PdfAnnotation annotation) {
    if (annotation is PdfWidgetAnnotation) {
      final value = annotation.fieldValue;
      return [
        if (annotation.fieldName != null && annotation.fieldName!.isNotEmpty)
          annotation.fieldName!,
        if (value != null && value.isNotEmpty) value,
      ].join(' — ');
    }
    if (annotation.subtype == 'Link') {
      final text = _pageText(pageIndex)?.textIn(annotation.rect);
      return [
        if (text != null && text.isNotEmpty) text,
        if (_actionLabel(annotation.action) case final target?) target,
      ].join(' — ');
    }
    // on widgets /T is the field name, not an author — handled above
    final author = annotation.author;
    final contents = annotation.contents;
    return [
      if (author != null && author.isNotEmpty) author,
      if (contents != null && contents.isNotEmpty) contents,
    ].join(' — ');
  }

  void _toggle((int, int) slot) => setState(() {
        if (!_checked.add(slot)) _checked.remove(slot);
      });

  /// The tile's title, as shown — what the search matches besides the
  /// subtitle.
  String _title(PdfAnnotation annotation) => annotation is PdfWidgetAnnotation
      ? _fieldLabel(annotation.fieldType)
      : _label(annotation.subtype);

  bool _matches(String query, int pageIndex, PdfAnnotation annotation) {
    if (query.isEmpty) return true;
    return _title(annotation).toLowerCase().contains(query) ||
        _detail(pageIndex, annotation).toLowerCase().contains(query);
  }

  Widget _searchField(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: TextField(
        key: const ValueKey('pdf-annotation-search'),
        controller: _search,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: 'Search annotations',
          isDense: true,
          prefixIcon: const Icon(Icons.search, size: 18),
          suffixIcon: _search.text.isEmpty
              ? null
              : IconButton(
                  key: const ValueKey('pdf-annotation-search-clear'),
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Clear search',
                  onPressed: () => setState(_search.clear),
                ),
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, int pageIndex, int index,
      PdfAnnotation annotation) {
    final slot = (pageIndex, index);
    final selectable = !_unselectable.contains(annotation.subtype);
    final detail = _detail(pageIndex, annotation);
    return ListTile(
      dense: true,
      leading: _selecting
          ? Checkbox(
              value: _checked.contains(slot),
              onChanged: selectable ? (_) => _toggle(slot) : null,
            )
          : Icon(_icon(annotation.subtype), size: 20),
      title: Text(_title(annotation)),
      subtitle: detail.isEmpty
          ? null
          : Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis),
      // viewer multi-selection shows here too
      selected: !_selecting &&
          widget.controller.isAnnotationSelected(pageIndex, index),
      onTap: _selecting
          ? (selectable ? () => _toggle(slot) : null)
          : () {
              unawaited(
                  widget.viewerController.showRect(pageIndex, annotation.rect));
              if (selectable) {
                widget.controller.selectAnnotation(pageIndex, index);
              }
              // pulse it on the page so the eye lands right
              widget.controller.flashAnnotation(pageIndex, index);
            },
      onLongPress: selectable && !_selecting
          ? () => setState(() {
                _selecting = true;
                _checked.add(slot);
              })
          : null,
      trailing: _selecting || !selectable
          ? null
          : IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              tooltip: 'Delete',
              onPressed: () =>
                  widget.controller.deleteAnnotation(pageIndex, index),
            ),
    );
  }

  Widget _selectionHeader(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.close, size: 20),
          tooltip: 'Cancel selection',
          onPressed: () => setState(() {
            _selecting = false;
            _checked.clear();
          }),
        ),
        Text('${_checked.length} selected',
            style: Theme.of(context).textTheme.labelLarge),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.delete_outline, size: 20),
          tooltip: 'Delete selected',
          onPressed: _checked.isEmpty
              ? null
              : () => widget.controller.deleteAnnotations(_checked.toList()),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    // a bottom sheet supplies its own width and resize affordance, so the
    // panel drops the side resize grip and fills its parent
    final showGrip = widget.resizable && !widget.bottomSheet;
    final onLeftEdge = !widget.bottomSheet && widget.side == PdfSidebarSide.left;
    final content = Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: ListenableBuilder(
              listenable: widget.controller,
              builder: (context, _) {
                final document = widget.controller.document;
                if (!identical(document, _builtFor)) {
                  // already rebuilding — adjust the state in place
                  _builtFor = document;
                  _checked.clear();
                  _selecting = false;
                  _pageTexts.clear();
                }
                final query = _search.text.trim().toLowerCase();
                final children = <Widget>[];
                var listed = 0;
                for (var page = 0; page < document.pageCount; page++) {
                  final annotations =
                      widget.controller.pageAt(page).annotations;
                  final tiles = <Widget>[];
                  for (var i = 0; i < annotations.length; i++) {
                    final annotation = annotations[i];
                    if (_unlisted.contains(annotation.subtype)) continue;
                    listed++;
                    if (!_matches(query, page, annotation)) continue;
                    tiles.add(_tile(context, page, i, annotation));
                  }
                  if (tiles.isNotEmpty) {
                    children
                      ..add(Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text('Page ${page + 1}',
                            style: Theme.of(context).textTheme.labelLarge),
                      ))
                      ..addAll(tiles);
                  }
                }
                // the viewer-style scrollbar replaces the implicit
                // desktop bar; it wraps only the list, so the
                // multi-select header above stays clear of it. Stepped
                // off the resize grip when the grip rides the same
                // (right) edge.
                // keep the list clear of the overlay scrollbar's zone so
                // the bar never covers a tile's trailing button
                final barClearance = PdfScrollbar.hitExtent +
                    (showGrip && onLeftEdge ? PdfSidebarResizeGrip.width : 0);
                final list = children.isEmpty
                    ? Center(
                        child: Text(listed > 0 && query.isNotEmpty
                            ? 'No matching annotations'
                            : 'No annotations'))
                    : Stack(children: [
                        ScrollConfiguration(
                          behavior: ScrollConfiguration.of(context)
                              .copyWith(scrollbars: false),
                          child: ListView(
                              controller: _scroll,
                              padding: EdgeInsets.only(right: barClearance),
                              children: children),
                        ),
                        Positioned(
                          top: 0,
                          bottom: 0,
                          right: showGrip && onLeftEdge
                              ? PdfSidebarResizeGrip.width
                              : 0,
                          child: PdfScrollbar(
                            scroll: _scroll,
                            thumbKey: const ValueKey(
                                'pdf-annotation-scrollbar-thumb'),
                          ),
                        ),
                      ]);
                // one shape for both modes, with the list keyed: the
                // header appearing must not move the list to a new
                // element (the controller would sit attached to two
                // scroll views for a frame)
                return Column(children: [
                  _searchField(context),
                  if (_selecting) _selectionHeader(context),
                  Expanded(
                    key: const ValueKey('pdf-annotation-list'),
                    child: list,
                  ),
                ]);
              },
            ),
          );
    if (widget.bottomSheet) return content;
    return SizedBox(
      width: _width,
      child: Stack(children: [
        Positioned.fill(child: content),
        if (showGrip)
          Positioned(
            top: 0,
            bottom: 0,
            left: widget.side == PdfSidebarSide.right ? 0 : null,
            right: widget.side == PdfSidebarSide.left ? 0 : null,
            child: PdfSidebarResizeGrip(
              key: const ValueKey('pdf-annotation-resize-grip'),
              side: widget.side,
              onWidthDelta: _onResizeDelta,
              onResizeEnd: _onResizeEnd,
            ),
          ),
      ]),
    );
  }
}
