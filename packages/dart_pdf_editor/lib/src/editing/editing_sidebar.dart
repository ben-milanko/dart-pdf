import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HardwareKeyboard;
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

import '../l10n/pdf_l10n.dart';
import '../pdf_viewer.dart';
import 'annotation_presentation.dart';
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
/// the page. On mouse hover a row reveals its trailing actions: a "more"
/// (⋮) menu carrying Reply / Resolve for a markup annotation's comment
/// thread, and a delete button.
///
/// Rows are multi-selectable: ⌘/Ctrl-click toggles a row in or out of
/// the selection and shift-click extends a range from the last click,
/// mirroring the viewer's own selection. A long press starts a
/// touch-friendly checkbox multi-select: checkboxes replace the icons,
/// tapping toggles, and the header's delete removes everything checked as
/// one undo step. The list rebuilds on every revision, so it always
/// reflects the current state - including undo and redo.
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
    this.dock = PdfPanelDock.right,
    this.resizable = true,
    this.minWidth = 200,
    this.maxWidth = 480,
    this.bottomSheet = false,
    this.onClose,
  });

  final PdfEditingController controller;

  /// The viewer to navigate when a tile is tapped.
  final PdfViewerController viewerController;

  /// The default width - a user-dragged width, persisted in
  /// [PdfEditingPreferences.annotationSidebarWidth], wins over it.
  final double width;

  /// Which edge of the viewer the panel docks on; the resize grip rides
  /// the opposite (inner) edge.
  final PdfPanelDock dock;

  /// Whether the inner edge can be dragged to resize the panel.
  final bool resizable;

  /// Clamps for the dragged width.
  final double minWidth;
  final double maxWidth;

  /// Lays the panel out to fill its parent (full width, no side resize
  /// grip) for hosting inside a bottom sheet on a small screen, rather
  /// than as a fixed-width docked column.
  final bool bottomSheet;

  /// Closes the docked panel - the host turns its visibility preference
  /// off. When given (and not a [bottomSheet]) a close (×) button appears
  /// beside the filter field. Null leaves the panel with no close button
  /// (a bottom sheet supplies its own).
  final VoidCallback? onClose;

  @override
  State<PdfAnnotationSidebar> createState() => _PdfAnnotationSidebarState();
}

class _PdfAnnotationSidebarState extends State<PdfAnnotationSidebar> {
  /// Links and form fields are listed but not selectable (the select
  /// tool refuses them too); popups belong to their parent annotation
  /// and are not listed at all.
  static const _unlisted = {'Popup'};

  /// Checked tiles in multi-select mode, as (page, /Annots slot).
  final Set<(int, int)> _checked = {};
  (int, int)? _hoveredSlot;
  bool _selecting = false;

  /// The slot a shift-click range extends from - set on a plain or
  /// ⌘/Ctrl-click. Cleared with the selection on every revision (slots
  /// shift under edits).
  (int, int)? _anchor;

  final ScrollController _scroll = ScrollController();

  /// The filter text; tiles whose title or subtitle don't contain it
  /// (case-insensitive) are hidden. Survives revisions - a search isn't
  /// invalidated by an edit.
  final TextEditingController _search = TextEditingController();

  /// The /NM of the root annotation whose inline reply field is open, if
  /// any. Cleared on every revision (a sent reply revises the document and
  /// closes the field).
  String? _replyingTo;

  /// The text being typed into the open reply field.
  final TextEditingController _reply = TextEditingController();

  /// The document revision the selection state belongs to. Any edit,
  /// undo, or redo can shift /Annots slots, so a new revision drops it.
  int? _builtForRevision;

  /// Extracted page text for link tiles ("the text under the link"),
  /// per page, for the current revision only - extraction interprets
  /// the page, so it runs once per page that actually lists a link and
  /// the cache dies with the built-for revision. Null entries are failed or
  /// text-free extractions.
  final Map<int, PdfPageText?> _pageTexts = {};

  PdfEditingPreferences get _preferences => widget.controller.preferences;

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
    _reply.dispose();
    super.dispose();
  }

  void _onPreferences() {
    if (mounted) setState(() {});
  }

  void _setHover((int, int) slot, bool hovering) {
    if (!pdfPanelControlsRevealOnHover()) return;
    final next = hovering ? slot : (_hoveredSlot == slot ? null : _hoveredSlot);
    if (next == _hoveredSlot) return;
    setState(() => _hoveredSlot = next);
  }

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

  /// The tile subtitle: author - contents for markup, name - value for
  /// form fields, link text - target for links.
  String _detail(int pageIndex, PdfAnnotation annotation) {
    if (annotation is PdfWidgetAnnotation) {
      final value = annotation.fieldValue;
      return [
        if (annotation.fieldName != null && annotation.fieldName!.isNotEmpty)
          annotation.fieldName!,
        if (value != null && value.isNotEmpty) value,
      ].join(' - ');
    }
    if (annotation.subtype == 'Link') {
      final text = _pageText(pageIndex)?.textIn(annotation.rect);
      return [
        if (text != null && text.isNotEmpty) text,
        if (_actionLabel(annotation.action) case final target?) target,
      ].join(' - ');
    }
    // on widgets /T is the field name, not an author - handled above
    final author = annotation.author;
    final contents = annotation.contents;
    return [
      if (author != null && author.isNotEmpty) author,
      if (contents != null && contents.isNotEmpty) contents,
    ].join(' - ');
  }

  void _toggle((int, int) slot) => setState(() {
        if (!_checked.add(slot)) _checked.remove(slot);
      });

  /// The tile's title, as shown - what the search matches besides the
  /// subtitle.
  String _title(PdfAnnotation annotation) => annotation is PdfWidgetAnnotation
      ? _fieldLabel(annotation.fieldType)
      : annotation.isCallout
          ? 'Callout'
          : pdfAnnotationLabel(annotation.subtype);

  bool _matches(String query, int pageIndex, PdfAnnotation annotation) {
    if (query.isEmpty) return true;
    return _title(annotation).toLowerCase().contains(query) ||
        _detail(pageIndex, annotation).toLowerCase().contains(query);
  }

  Widget _searchField(
    BuildContext context,
    PdfSidebarPanelGeometry geometry,
  ) {
    // the docked panel's close button rides the right of the filter row;
    // a bottom sheet supplies its own in its sheet chrome
    final closeButton = geometry.closeButton(
      key: const ValueKey('pdf-annotation-panel-close'),
    );
    final moveHandle = geometry.moveHandle(
      key: const ValueKey('pdf-annotation-panel-move'),
    );
    final trailing = <Widget>[
      if (moveHandle != null) moveHandle,
      if (closeButton != null) closeButton,
    ];
    final field = TextField(
      key: const ValueKey('pdf-annotation-search'),
      controller: _search,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: pdfL10n(context).sidebarSearchHint,
        isDense: true,
        prefixIcon: const Icon(Icons.search, size: 18),
        suffixIcon: _search.text.isEmpty
            ? null
            : IconButton(
                key: const ValueKey('pdf-annotation-search-clear'),
                icon: const Icon(Icons.close, size: 18),
                tooltip: pdfL10n(context).sidebarClearSearch,
                onPressed: () => setState(_search.clear),
              ),
        border: const OutlineInputBorder(),
      ),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 8, trailing.isNotEmpty ? 4 : 12, 4),
      child: trailing.isNotEmpty
          ? Row(children: [
              Expanded(child: field),
              ...trailing,
            ])
          : field,
    );
  }

  Widget _tile(
      BuildContext context,
      int pageIndex,
      int index,
      PdfAnnotation annotation,
      PdfCommentThread? thread,
      List<(int, int)> ordered) {
    final slot = (pageIndex, index);
    final editable = annotation.behavior.selectable &&
        widget.controller.isAnnotationEditable(annotation);
    // a markup annotation hosts a comment thread; reply / resolve act on
    // it even when the annotation itself is locked (they add new
    // annotations rather than editing the locked one)
    final hostsThread = annotation.behavior.selectable;
    final detail = _detail(pageIndex, annotation);
    final actionsVisible =
        !pdfPanelControlsRevealOnHover() || _hoveredSlot == slot;
    return MouseRegion(
      onEnter: (_) => _setHover(slot, true),
      onExit: (_) => _setHover(slot, false),
      child: ListTile(
        dense: true,
        leading: _selecting
            ? Checkbox(
                value: _checked.contains(slot),
                onChanged: editable ? (_) => _toggle(slot) : null,
              )
            : Icon(
                annotation.isCallout
                    ? Icons.chat_bubble_outline
                    : pdfAnnotationIcon(annotation.subtype),
                size: 20),
        title: Text(_title(annotation)),
        subtitle: detail.isEmpty
            ? null
            : Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis),
        // viewer multi-selection shows here too
        selected: !_selecting &&
            widget.controller.isAnnotationSelected(pageIndex, index),
        onTap: _selecting
            ? (editable ? () => _toggle(slot) : null)
            : () => _onTileTap(pageIndex, index, annotation, editable, ordered),
        onLongPress: editable && !_selecting
            ? () => setState(() {
                  _selecting = true;
                  _checked.add(slot);
                })
            : null,
        trailing: _selecting
            ? null
            : _rowActions(context, pageIndex, index, annotation, thread,
                editable, hostsThread, actionsVisible),
      ),
    );
  }

  /// The trailing hover actions for a row: a "more" (⋮) menu with the
  /// thread's Reply / Resolve for a markup annotation, then delete for an
  /// editable one. Null when the row exposes neither.
  Widget? _rowActions(
    BuildContext context,
    int pageIndex,
    int index,
    PdfAnnotation annotation,
    PdfCommentThread? thread,
    bool editable,
    bool hostsThread,
    bool actionsVisible,
  ) {
    // A signed signature field is deletable even though its widget isn't a
    // normally selectable annotation (undo restores it).
    final signature = _signatureFor(annotation);
    // The lock toggle rides every markup row and stays visible even when
    // the rest of the actions hover-reveal, so a locked annotation reads
    // as locked at a glance and can always be unlocked from here (the only
    // reachable path, since a locked annotation can't be selected).
    final lockButton =
        widget.controller.isAnnotationLockManageable(annotation)
            ? IconButton(
                key: ValueKey('pdf-annotation-lock-$pageIndex-$index'),
                icon: Icon(
                    annotation.isLocked
                        ? Icons.lock
                        : Icons.lock_open_outlined,
                    size: 20),
                tooltip: annotation.isLocked
                    ? pdfL10n(context).sidebarUnlockAnnotation
                    : pdfL10n(context).sidebarLockAnnotation,
                onPressed: () =>
                    widget.controller.toggleAnnotationLock(pageIndex, index),
              )
            : null;
    final hoverActions = <Widget>[
      if (hostsThread)
        _threadMenu(context, pageIndex, index, annotation, thread),
      if (signature != null)
        IconButton(
          key: ValueKey('pdf-signature-delete-$pageIndex-$index'),
          icon: const Icon(Icons.delete_outline, size: 20),
          tooltip: pdfL10n(context).sidebarDeleteSignature,
          onPressed: () =>
              unawaited(_confirmRemoveSignature(context, signature)),
        )
      else if (editable)
        IconButton(
          key: ValueKey('pdf-annotation-delete-$pageIndex-$index'),
          icon: const Icon(Icons.delete_outline, size: 20),
          tooltip: pdfL10n(context).delete,
          onPressed: () => widget.controller.deleteAnnotation(pageIndex, index),
        ),
    ];
    if (lockButton == null && hoverActions.isEmpty) return null;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (lockButton != null) lockButton,
      if (hoverActions.isNotEmpty)
        Visibility(
          visible: actionsVisible,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: Row(mainAxisSize: MainAxisSize.min, children: hoverActions),
        ),
    ]);
  }

  /// The signed [PdfSignature] this tile's widget belongs to, or null when the
  /// tile isn't a signed signature field.
  PdfSignature? _signatureFor(PdfAnnotation annotation) {
    if (annotation is! PdfWidgetAnnotation ||
        annotation.fieldType != 'Sig' ||
        annotation.fieldName == null) {
      return null;
    }
    for (final signature in widget.controller.signatures) {
      if (signature.field.name == annotation.fieldName) return signature;
    }
    return null;
  }

  Future<void> _confirmRemoveSignature(
      BuildContext context, PdfSignature signature) async {
    final name = signature.signerName;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(pdfL10n(context).sidebarRemoveSignatureTitle),
        content: Text(name == null || name.isEmpty
            ? pdfL10n(context).sidebarRemoveSignatureBody
            : pdfL10n(context).sidebarRemoveSignatureBodyNamed(name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(pdfL10n(context).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(pdfL10n(context).remove),
          ),
        ],
      ),
    );
    if (confirmed == true) widget.controller.removeSignature(signature);
  }

  /// The per-row "more" menu holding a markup annotation's thread actions:
  /// Reply (opens the inline reply field) and Resolve / Reopen.
  Widget _threadMenu(BuildContext context, int pageIndex, int index,
      PdfAnnotation annotation, PdfCommentThread? thread) {
    final nm = annotation.name;
    final resolved = thread?.isResolved ?? false;
    return PopupMenuButton<_ThreadAction>(
      key: ValueKey('pdf-annotation-more-$pageIndex-$index'),
      icon: const Icon(Icons.more_vert, size: 20),
      tooltip: pdfL10n(context).sidebarMore,
      onSelected: (action) {
        switch (action) {
          case _ThreadAction.reply:
            setState(() {
              _replyingTo = nm;
              _reply.text = '';
            });
          case _ThreadAction.resolve:
            resolved
                ? widget.controller.reopenThread(pageIndex, annotation)
                : widget.controller.resolveThread(pageIndex, annotation);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          key: const ValueKey('pdf-reply-button'),
          value: _ThreadAction.reply,
          // a reply is matched to its root by /NM; without one there's
          // no field to open
          enabled: nm != null,
          child: Text(pdfL10n(context).sidebarReply),
        ),
        PopupMenuItem(
          key: const ValueKey('pdf-resolve-button'),
          value: _ThreadAction.resolve,
          child: Text(
              resolved ? pdfL10n(context).sidebarReopen : pdfL10n(context).sidebarResolve),
        ),
      ],
    );
  }

  /// A plain / ⌘-Ctrl / shift click on a row (outside checkbox mode).
  /// Plain click navigates the viewer to the annotation, selects it, and
  /// flashes it. ⌘/Ctrl-click toggles it in the selection; shift-click
  /// selects the range from the [_anchor] to it. Both modifier gestures
  /// leave the viewport put.
  void _onTileTap(int pageIndex, int index, PdfAnnotation annotation,
      bool editable, List<(int, int)> ordered) {
    final slot = (pageIndex, index);
    final keys = HardwareKeyboard.instance;
    final toggle = keys.isControlPressed || keys.isMetaPressed;
    final range = keys.isShiftPressed;

    if (editable && range && _anchor != null) {
      final from = ordered.indexOf(_anchor!);
      final to = ordered.indexOf(slot);
      if (from != -1 && to != -1) {
        final lo = from < to ? from : to;
        final hi = from < to ? to : from;
        widget.controller.selectAnnotationSlots(ordered.sublist(lo, hi + 1));
        return;
      }
    }
    if (editable && toggle) {
      widget.controller.toggleAnnotationSelection(pageIndex, index);
      _anchor = slot;
      return;
    }
    // plain click: frame it, select it, and pulse it on the page so the
    // eye lands right
    unawaited(widget.viewerController.showRect(pageIndex, annotation.rect));
    if (editable) {
      widget.controller.selectAnnotation(pageIndex, index);
      _anchor = slot;
    }
    widget.controller.flashAnnotation(pageIndex, index);
  }

  /// A short local-time stamp for a comment, or '' when undated.
  static String _formatTime(DateTime? t) {
    if (t == null) return '';
    final l = t.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} '
        '${two(l.hour)}:${two(l.minute)}';
  }

  /// The label and accent color for a review state chip, or null when the
  /// state is `None` (an open/unresolved thread shows no chip).
  static (String, Color)? _stateChip(PdfReviewState state, ColorScheme cs) =>
      switch (state) {
        PdfReviewState.completed => ('Resolved', Colors.green),
        PdfReviewState.accepted => ('Accepted', Colors.green),
        PdfReviewState.rejected => ('Rejected', Colors.red),
        PdfReviewState.cancelled => ('Cancelled', Colors.orange),
        PdfReviewState.marked => ('Marked', Colors.blue),
        PdfReviewState.unmarked => ('Unmarked', cs.outline),
        PdfReviewState.none => null,
      };

  /// Each comment in [root]'s reply tree with its depth (root = 0), in
  /// document/pre-order.
  static List<(PdfComment, int)> _flattenWithDepth(PdfComment root) {
    final out = <(PdfComment, int)>[];
    void walk(PdfComment comment, int depth) {
      out.add((comment, depth));
      for (final reply in comment.replies) {
        walk(reply, depth + 1);
      }
    }

    walk(root, 0);
    return out;
  }

  /// The inline thread under a root markup tile: a review-state chip, the
  /// reply tree (indented), and - when open - the reply field. Reply and
  /// Resolve are triggered from the row's "more" menu ([_threadMenu]).
  List<Widget> _threadSection(BuildContext context, int page,
      PdfAnnotation root, PdfCommentThread? thread) {
    if (_selecting) return const []; // chrome stays clear during multi-select
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final widgets = <Widget>[];

    // current review state chip
    final entry = thread?.state;
    if (entry != null) {
      final chip = _stateChip(entry.state, cs);
      if (chip != null) {
        widgets.add(Padding(
          padding: const EdgeInsets.fromLTRB(56, 0, 12, 2),
          child: Row(children: [
            _Pill(label: chip.$1, color: chip.$2),
            if (entry.author != null && entry.author!.isNotEmpty)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text(pdfL10n(context).sidebarByAuthor(entry.author!),
                      style: textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis),
                ),
              ),
          ]),
        ));
      }
    }

    // the reply tree (skip the root itself, which is the tile above)
    if (thread != null) {
      for (final (comment, depth) in _flattenWithDepth(thread.root)) {
        if (depth == 0) continue;
        widgets.add(_replyTile(context, comment, depth));
      }
    }

    // the open reply field, when the row's "more" > Reply was chosen
    final nm = root.name;
    final replying = nm != null && _replyingTo == nm;
    if (replying) {
      widgets.add(Padding(
        padding: const EdgeInsets.fromLTRB(56, 2, 12, 8),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            key: const ValueKey('pdf-reply-field'),
            controller: _reply,
            autofocus: true,
            minLines: 1,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: pdfL10n(context).sidebarWriteReplyHint,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _sendReply(page, root),
          ),
          Wrap(alignment: WrapAlignment.end, spacing: 4, children: [
            TextButton(
              onPressed: () => setState(() => _replyingTo = null),
              child: Text(pdfL10n(context).cancel),
            ),
            FilledButton(
              key: const ValueKey('pdf-reply-send'),
              onPressed: () => _sendReply(page, root),
              child: Text(pdfL10n(context).sidebarReply),
            ),
          ]),
        ]),
      ));
    }
    return widgets;
  }

  void _sendReply(int page, PdfAnnotation root) {
    final text = _reply.text.trim();
    if (text.isEmpty) {
      setState(() => _replyingTo = null);
      return;
    }
    // the revision that follows clears _replyingTo via the build reset
    widget.controller.replyToAnnotation(page, root, text);
  }

  /// One reply in a thread, indented by [depth], showing author, text, and
  /// a timestamp.
  Widget _replyTile(BuildContext context, PdfComment comment, int depth) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final time = _formatTime(comment.createdAt);
    final header = [
      if (comment.author != null && comment.author!.isNotEmpty) comment.author!,
      if (time.isNotEmpty) time,
    ].join(' • ');
    return Padding(
      padding: EdgeInsets.fromLTRB(56.0 + (depth - 1) * 14, 0, 12, 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(color: cs.outlineVariant, width: 2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (header.isNotEmpty)
            Text(header,
                style:
                    textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
          Text(comment.text, style: textTheme.bodySmall),
        ]),
      ),
    );
  }

  Widget _selectionHeader(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.close, size: 20),
          tooltip: pdfL10n(context).sidebarCancelSelection,
          onPressed: () => setState(() {
            _selecting = false;
            _checked.clear();
          }),
        ),
        Text(pdfL10n(context).sidebarSelectedCount(_checked.length),
            style: Theme.of(context).textTheme.labelLarge),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.delete_outline, size: 20),
          tooltip: pdfL10n(context).sidebarDeleteSelected,
          onPressed: _checked.isEmpty
              ? null
              : () => widget.controller.deleteAnnotations(_checked.toList()),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PdfSidebarPanelFrame(
      width: widget.width,
      minWidth: widget.minWidth,
      maxWidth: widget.maxWidth,
      persistedWidth: _preferences.annotationSidebarWidth,
      onPersistWidth: (width) => _preferences.annotationSidebarWidth = width,
      dock: widget.dock,
      panel: PdfDockablePanel.annotations,
      resizable: widget.resizable,
      bottomSheet: widget.bottomSheet,
      gripKey: const ValueKey('pdf-annotation-resize-grip'),
      onClose: widget.onClose,
      builder: (context, geometry) => Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) {
            final document = widget.controller.document;
            final revisionId = widget.controller.revisionId;
            if (revisionId != _builtForRevision) {
              // already rebuilding - adjust the state in place
              _builtForRevision = revisionId;
              _checked.clear();
              _hoveredSlot = null;
              _selecting = false;
              _anchor = null;
              _pageTexts.clear();
              // a revision closes any open reply field (the sent reply
              // is what produced the new revision)
              _replyingTo = null;
            }
            final query = _search.text.trim().toLowerCase();
            final children = <Widget>[];
            // every displayed, selectable slot in display order - the axis
            // a shift-click range runs along. Filled as tiles are built and
            // captured by each row's tap handler (complete by tap time).
            final ordered = <(int, int)>[];
            var listed = 0;
            for (var page = 0; page < document.pageCount; page++) {
              final annotations = widget.controller.pageAt(page).annotations;
              // map each thread to its root's dictionary so a tile can
              // render its replies and state inline
              final threadByDict = {
                for (final thread in widget.controller.commentThreads(page))
                  thread.root.annotation.dict: thread,
              };
              final tiles = <Widget>[];
              for (var i = 0; i < annotations.length; i++) {
                final annotation = annotations[i];
                if (_unlisted.contains(annotation.subtype)) continue;
                // replies and review-state annotations are thread
                // content - shown nested under their root, not as their
                // own top-level rows
                if (annotation.isReply || annotation.isStateAnnotation) {
                  continue;
                }
                listed++;
                if (!_matches(query, page, annotation)) continue;
                final thread = threadByDict[annotation.dict];
                if (annotation.behavior.selectable &&
                    widget.controller.isAnnotationEditable(annotation)) {
                  ordered.add((page, i));
                }
                tiles.add(_tile(context, page, i, annotation, thread, ordered));
                // a markup annotation hosts a comment thread
                if (annotation.behavior.selectable) {
                  tiles.addAll(
                      _threadSection(context, page, annotation, thread));
                }
              }
              if (tiles.isNotEmpty) {
                children
                  ..add(Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(pdfL10n(context).sidebarPageHeader(page + 1),
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
            final list = children.isEmpty
                ? Center(
                    child: Text(listed > 0 && query.isNotEmpty
                        ? pdfL10n(context).sidebarNoMatchingAnnotations
                        : pdfL10n(context).sidebarNoAnnotations))
                : geometry.withScrollbar(
                    scroll: _scroll,
                    thumbKey: const ValueKey('pdf-annotation-scrollbar-thumb'),
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context)
                          .copyWith(scrollbars: false),
                      child: ListView(
                          controller: _scroll,
                          padding: EdgeInsets.only(
                              right: geometry.scrollbarClearance),
                          children: children),
                    ),
                  );
            // one shape for both modes, with the list keyed: the
            // header appearing must not move the list to a new
            // element (the controller would sit attached to two
            // scroll views for a frame)
            return Column(children: [
              _searchField(context, geometry),
              if (_selecting) _selectionHeader(context),
              Expanded(
                key: const ValueKey('pdf-annotation-list'),
                child: list,
              ),
            ]);
          },
        ),
      ),
    );
  }
}

/// The actions a markup row's "more" menu offers on its comment thread.
enum _ThreadAction { reply, resolve }

/// A small rounded status chip used for a thread's review state.
class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(label,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: color, fontWeight: FontWeight.w600)),
    );
  }
}
