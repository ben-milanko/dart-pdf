import 'dart:async';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:pdf_document/pdf_document.dart';

import 'design/editor_presenter.dart';
import 'design/material_host.dart';
import 'dialog.dart';
import 'editing/editing_controller.dart';
import 'l10n/pdf_l10n.dart';

/// A PDF the host read for "Insert pages": its display [name] and [bytes].
@immutable
class PdfInsertFile {
  const PdfInsertFile(this.name, this.bytes);

  final String name;
  final Uint8List bytes;
}

/// Asks the host for PDFs to insert (an empty list = cancelled). Needs the
/// host for file I/O, like the single-file `onPickPdfToInsert`.
typedef PdfPickInsertFiles = Future<List<PdfInsertFile>> Function();

/// Which side of the [PdfInsertAnchor] page the inserted pages go.
enum PdfInsertSide { before, after }

/// The page the [PdfInsertSide] is relative to.
enum PdfInsertAnchor { firstPage, lastPage, page }

/// What the insert-pages dialog settled on - pass it to
/// [PdfInsertPagesPlan.applyTo] (or the fields to
/// [PdfEditingController.insertPages]).
@immutable
class PdfInsertPagesPlan {
  const PdfInsertPagesPlan({
    required this.sources,
    required this.at,
    this.interleave,
    this.bookmarks = true,
  });

  /// The documents to insert from, in order, with their page choices.
  final List<PdfPageInsertSource> sources;

  /// The page index the first inserted page lands at.
  final int at;

  /// How to weave the pages in; null inserts one block.
  final PdfPageInterleave? interleave;

  /// Whether each source's own bookmarks come along.
  final bool bookmarks;

  /// Commits the plan as one edit; returns the inserted pages' indices.
  List<int> applyTo(PdfEditingController controller) =>
      controller.insertPages(sources,
          at: at, interleave: interleave, bookmarks: bookmarks);
}

/// The insertion index for [side] of [anchor] in a [pageCount]-page
/// document; [page] (one-based) is used for [PdfInsertAnchor.page].
int pdfInsertIndex({
  required int pageCount,
  required PdfInsertSide side,
  required PdfInsertAnchor anchor,
  int page = 1,
}) {
  final target = switch (anchor) {
    PdfInsertAnchor.firstPage => 0,
    PdfInsertAnchor.lastPage => pageCount - 1,
    PdfInsertAnchor.page => (page - 1).clamp(0, pageCount - 1),
  };
  final at = side == PdfInsertSide.before ? target : target + 1;
  return at.clamp(0, pageCount).toInt();
}

/// The Bluebeam-style "Insert pages" dialog: several PDFs (each with its own
/// page range, odd/even filter and reverse toggle, reorderable), the
/// placement (before/after the first, last or a given page), interleaving,
/// and bookmark handling. [pickFiles] backs "Add files…"; [initialFiles]
/// start the list. [currentPage] (zero-based) seeds the placement as "after
/// the current page". Returns null when cancelled.
Future<PdfInsertPagesPlan?> showPdfInsertPagesDialog(
  BuildContext context, {
  required int pageCount,
  required PdfPickInsertFiles pickFiles,
  List<PdfInsertFile> initialFiles = const [],
  int currentPage = 0,
}) {
  return pdfPresentDialog<PdfInsertPagesPlan>(
    context,
    builder: (_) => _InsertPagesDialog(
      pageCount: pageCount,
      pickFiles: pickFiles,
      initialFiles: initialFiles,
      currentPage: currentPage,
    ),
  );
}

/// Picks files (unless [initialFiles] are given), shows
/// [showPdfInsertPagesDialog], and commits the result to [controller] as
/// one undoable edit. Returns how many files contributed pages and the
/// inserted pages' indices, or null when the user cancelled or nothing was
/// inserted.
Future<({int files, List<int> pages})?> pdfInsertPagesInteractively(
  BuildContext context, {
  required PdfEditingController controller,
  required PdfPickInsertFiles pickFiles,
  List<PdfInsertFile> initialFiles = const [],
  int currentPage = 0,
}) async {
  var files = initialFiles;
  if (files.isEmpty) {
    files = await pickFiles();
    if (files.isEmpty || !context.mounted) return null;
  }
  final document = controller.document;
  final plan = await showPdfInsertPagesDialog(
    context,
    pageCount: document.pageCount,
    pickFiles: pickFiles,
    initialFiles: files,
    currentPage: currentPage,
  );
  // the document may have moved on while the dialog was up
  if (plan == null || !identical(controller.document, document)) return null;
  final pages = plan.applyTo(controller);
  if (pages.isEmpty) return null;
  return (
    files: plan.sources.where((s) => s.indices?.isNotEmpty ?? true).length,
    pages: pages,
  );
}

class _Entry {
  _Entry(this.file, this.document);

  final PdfInsertFile file;
  final PdfDocument document;
  final ranges = TextEditingController();
  PdfPageSubset subset = PdfPageSubset.all;
  bool reverse = false;

  int get pageCount => document.pageCount;

  /// The picked pages, or null when the range expression is invalid.
  List<int>? get picks {
    try {
      return PdfPageInsertSource.select(pageCount,
          ranges: ranges.text, subset: subset, reverse: reverse);
    } on FormatException {
      return null;
    }
  }

  String get title {
    final name = file.name;
    return name.toLowerCase().endsWith('.pdf')
        ? name.substring(0, name.length - 4)
        : name;
  }
}

class _InsertPagesDialog extends StatefulWidget {
  const _InsertPagesDialog({
    required this.pageCount,
    required this.pickFiles,
    required this.initialFiles,
    required this.currentPage,
  });

  final int pageCount;
  final PdfPickInsertFiles pickFiles;
  final List<PdfInsertFile> initialFiles;
  final int currentPage;

  @override
  State<_InsertPagesDialog> createState() => _InsertPagesDialogState();
}

class _InsertPagesDialogState extends State<_InsertPagesDialog> {
  final _entries = <_Entry>[];
  final _failed = <String>[];
  var _side = PdfInsertSide.after;
  var _anchor = PdfInsertAnchor.page;
  late final _page = TextEditingController(
      text: '${(widget.currentPage + 1).clamp(1, widget.pageCount)}');
  var _interleave = false;
  final _existingRun = TextEditingController(text: '1');
  final _insertedRun = TextEditingController(text: '1');
  var _bookmarks = true;
  var _bookmarkFiles = false;
  var _picking = false;

  @override
  void initState() {
    super.initState();
    _add(widget.initialFiles);
  }

  @override
  void dispose() {
    for (final entry in _entries) {
      entry.ranges.dispose();
    }
    _page.dispose();
    _existingRun.dispose();
    _insertedRun.dispose();
    super.dispose();
  }

  /// Opens each file up front, so its page count is known and a file that
  /// can't be read is reported instead of failing the whole insert.
  void _add(List<PdfInsertFile> files) {
    _failed.clear();
    for (final file in files) {
      try {
        final document = PdfDocument.open(file.bytes);
        if (document.pageCount == 0) throw const FormatException('no pages');
        _entries.add(_Entry(file, document));
      } catch (_) {
        _failed.add(file.name);
      }
    }
  }

  Future<void> _pickMore() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final files = await widget.pickFiles();
      if (!mounted) return;
      setState(() => _add(files));
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _move(int index, int delta) {
    setState(() {
      final entry = _entries.removeAt(index);
      _entries.insert(index + delta, entry);
    });
  }

  void _remove(int index) {
    setState(() => _entries.removeAt(index).ranges.dispose());
  }

  void _sortByName() {
    setState(() => _entries.sort((a, b) =>
        a.file.name.toLowerCase().compareTo(b.file.name.toLowerCase())));
  }

  int? get _pageNumber {
    final n = int.tryParse(_page.text.trim());
    return n == null || n < 1 || n > widget.pageCount ? null : n;
  }

  static int? _run(TextEditingController c) {
    final n = int.tryParse(c.text.trim());
    return n == null || n < 1 ? null : n;
  }

  /// Total pages the plan inserts, or null while any input is invalid.
  int? get _insertedCount {
    var total = 0;
    for (final entry in _entries) {
      final picks = entry.picks;
      if (picks == null) return null;
      total += picks.length;
    }
    return total;
  }

  bool get _valid =>
      (_insertedCount ?? 0) > 0 &&
      (_anchor != PdfInsertAnchor.page || _pageNumber != null) &&
      (!_interleave ||
          (_run(_existingRun) != null && _run(_insertedRun) != null));

  void _submit() {
    if (!_valid) return;
    final at = pdfInsertIndex(
      pageCount: widget.pageCount,
      side: _side,
      anchor: _anchor,
      page: _pageNumber ?? 1,
    );
    Navigator.of(context).pop(PdfInsertPagesPlan(
      sources: [
        for (final entry in _entries)
          PdfPageInsertSource(
            entry.document,
            indices: entry.picks,
            bookmarkTitle: _bookmarkFiles ? entry.title : null,
          ),
      ],
      at: at,
      interleave: _interleave
          ? PdfPageInterleave(
              existing: _run(_existingRun)!, inserted: _run(_insertedRun)!)
          : null,
      bookmarks: _bookmarks,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = pdfL10n(context);
    final theme = Theme.of(context);
    final inserted = _insertedCount;
    final sectionStyle = theme.textTheme.titleSmall;
    return AlertDialog(
      key: const ValueKey('pdf-insert-pages-dialog'),
      title: Text(l10n.insertPagesTitle),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(builder: (context, constraints) {
                final narrow = constraints.maxWidth < _narrowWidth;
                final canSort = _entries.length > 1;
                return Row(children: [
                  Expanded(
                      child: Text(l10n.insertPagesFiles, style: sectionStyle)),
                  if (narrow)
                    IconButton(
                      key: const ValueKey('pdf-insert-pages-sort'),
                      tooltip: l10n.insertPagesSortByName,
                      onPressed: canSort ? _sortByName : null,
                      icon: const Icon(Icons.sort_by_alpha, size: 20),
                    )
                  else
                    TextButton.icon(
                      key: const ValueKey('pdf-insert-pages-sort'),
                      onPressed: canSort ? _sortByName : null,
                      icon: const Icon(Icons.sort_by_alpha, size: 18),
                      label: Text(l10n.insertPagesSortByName),
                    ),
                  const SizedBox(width: 4),
                  FilledButton.tonalIcon(
                    key: const ValueKey('pdf-insert-pages-add'),
                    onPressed: _picking ? null : () => unawaited(_pickMore()),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(l10n.insertPagesAddFiles),
                  ),
                ]);
              }),
              const SizedBox(height: 8),
              if (_entries.isEmpty)
                _EmptyFiles(message: l10n.insertPagesNoFiles),
              for (var i = 0; i < _entries.length; i++)
                _EntryTile(
                  key: ObjectKey(_entries[i]),
                  index: i,
                  entry: _entries[i],
                  canMoveUp: i > 0,
                  canMoveDown: i < _entries.length - 1,
                  onMove: (delta) => _move(i, delta),
                  onRemove: () => _remove(i),
                  onChanged: () => setState(() {}),
                ),
              if (_failed.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline,
                          size: 18, color: theme.colorScheme.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.insertPagesOpenFailed(_failed.join(', ')),
                          key: const ValueKey('pdf-insert-pages-failed'),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.error),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 20),
              Text(l10n.insertPagesPlacement, style: sectionStyle),
              const SizedBox(height: 12),
              LayoutBuilder(builder: (context, constraints) {
                final side = PdfDropdown<PdfInsertSide>(
                  key: const ValueKey('pdf-insert-pages-side'),
                  value: _side,
                  isExpanded: true,
                  decoration: _fieldDecoration(),
                  items: [
                    PdfDropdownItem(
                        key: const ValueKey('pdf-insert-pages-side-before'),
                        value: PdfInsertSide.before,
                        label: l10n.insertPagesBefore,
                        child: _FieldText(l10n.insertPagesBefore)),
                    PdfDropdownItem(
                        key: const ValueKey('pdf-insert-pages-side-after'),
                        value: PdfInsertSide.after,
                        label: l10n.insertPagesAfter,
                        child: _FieldText(l10n.insertPagesAfter)),
                  ],
                  onChanged: (v) => setState(() => _side = v),
                );
                final anchor = PdfDropdown<PdfInsertAnchor>(
                  key: const ValueKey('pdf-insert-pages-anchor'),
                  value: _anchor,
                  isExpanded: true,
                  decoration: _fieldDecoration(),
                  items: [
                    PdfDropdownItem(
                        key: const ValueKey('pdf-insert-pages-anchor-first'),
                        value: PdfInsertAnchor.firstPage,
                        label: l10n.insertPagesFirstPage),
                    PdfDropdownItem(
                        key: const ValueKey('pdf-insert-pages-anchor-last'),
                        value: PdfInsertAnchor.lastPage,
                        label: l10n.insertPagesLastPage,
                        child: _FieldText(l10n.insertPagesLastPage)),
                    PdfDropdownItem(
                        key: const ValueKey('pdf-insert-pages-anchor-page'),
                        value: PdfInsertAnchor.page,
                        label: l10n.insertPagesPage,
                        child: _FieldText(l10n.insertPagesPage)),
                  ],
                  onChanged: (v) => setState(() => _anchor = v),
                );
                // Kept in the layout (not removed) when another anchor is
                // picked, so the row doesn't reflow under the pointer.
                final page = TextField(
                  key: const ValueKey('pdf-insert-pages-page'),
                  controller: _page,
                  enabled: _anchor == PdfInsertAnchor.page,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _submit(),
                  decoration: _fieldDecoration(
                    label: l10n.insertPagesPageNumber,
                    suffix: l10n.insertPagesOfCount(widget.pageCount),
                    error:
                        _anchor == PdfInsertAnchor.page && _pageNumber == null
                            ? l10n.insertPagesPageInvalid(widget.pageCount)
                            : null,
                  ),
                  contextMenuBuilder: pdfTextContextMenu,
                );
                if (constraints.maxWidth < _narrowWidth) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Expanded(child: side),
                        const SizedBox(width: 12),
                        Expanded(child: anchor),
                      ]),
                      const SizedBox(height: 16),
                      page,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: side),
                    const SizedBox(width: 12),
                    Expanded(child: anchor),
                    const SizedBox(width: 12),
                    Expanded(child: page),
                  ],
                );
              }),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 8),
              _OptionTile(
                key: const ValueKey('pdf-insert-pages-interleave'),
                value: _interleave,
                onChanged: (v) => setState(() => _interleave = v),
                title: l10n.insertPagesInterleave,
                subtitle: l10n.insertPagesInterleaveHelp,
              ),
              if (_interleave)
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(56, 12, 0, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _RunField(
                          key: const ValueKey('pdf-insert-pages-run-inserted'),
                          controller: _insertedRun,
                          label: l10n.insertPagesRunInserted,
                          onChanged: () => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _RunField(
                          key: const ValueKey('pdf-insert-pages-run-existing'),
                          controller: _existingRun,
                          label: l10n.insertPagesRunExisting,
                          onChanged: () => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                ),
              _OptionTile(
                key: const ValueKey('pdf-insert-pages-bookmarks'),
                value: _bookmarks,
                onChanged: (v) => setState(() => _bookmarks = v),
                title: l10n.insertPagesIncludeBookmarks,
              ),
              _OptionTile(
                key: const ValueKey('pdf-insert-pages-bookmark-files'),
                value: _bookmarkFiles,
                onChanged: (v) => setState(() => _bookmarkFiles = v),
                title: l10n.insertPagesBookmarkFiles,
              ),
              if (inserted != null && inserted > 0) ...[
                const SizedBox(height: 12),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    child: Row(children: [
                      Icon(Icons.info_outline,
                          size: 18,
                          color: theme.colorScheme.onSecondaryContainer),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          l10n.insertPagesSummary(
                              inserted, widget.pageCount + inserted),
                          key: const ValueKey('pdf-insert-pages-summary'),
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSecondaryContainer),
                        ),
                      ),
                    ]),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('pdf-insert-pages-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        PdfDialogSubmit.action(
            onSubmit: _valid ? _submit : null,
            child: FilledButton(
              key: const ValueKey('pdf-insert-pages-confirm'),
              onPressed: _valid ? _submit : null,
              child: Text(l10n.insertPagesConfirm),
            )),
      ],
    );
  }
}

/// Below this content width the dialog's field rows stack instead of
/// squeezing three controls side by side.
const double _narrowWidth = 440;

/// The one look every field in the dialog shares - outlined, dense, label
/// always floated - so text fields and drop-downs line up on one baseline.
InputDecoration _fieldDecoration({
  String? label,
  String? hint,
  String? suffix,
  String? error,
}) =>
    InputDecoration(
      isDense: true,
      border: const OutlineInputBorder(),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      floatingLabelBehavior: FloatingLabelBehavior.always,
      labelText: label,
      hintText: hint,
      suffixText: suffix,
      errorText: error,
      errorMaxLines: 2,
    );

class _EmptyFiles extends StatelessWidget {
  const _EmptyFiles({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Column(children: [
          Icon(Icons.picture_as_pdf_outlined,
              size: 28, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ]),
      ),
    );
  }
}

/// A checkbox row whose whole width toggles it, with the title on the
/// checkbox's line and an optional explanation below.
class _OptionTile extends StatelessWidget {
  const _OptionTile({
    super.key,
    required this.value,
    required this.onChanged,
    required this.title,
    this.subtitle,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(value: value, onChanged: (v) => onChanged(v ?? false)),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                // centre the title on the checkbox's 40px tap target
                padding: const EdgeInsets.only(top: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.bodyLarge),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One source file: name and page count, ordering controls, and its page
/// choice (range, odd/even, reverse).
class _EntryTile extends StatelessWidget {
  const _EntryTile({
    super.key,
    required this.index,
    required this.entry,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onMove,
    required this.onRemove,
    required this.onChanged,
  });

  final int index;
  final _Entry entry;
  final bool canMoveUp;
  final bool canMoveDown;
  final ValueChanged<int> onMove;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = pdfL10n(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final invalid = entry.picks == null;
    return Container(
      key: ValueKey('pdf-insert-pages-file-$index'),
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 4, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.picture_as_pdf_outlined,
                  size: 20, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall),
                  Text(l10n.insertPagesFilePageCount(entry.pageCount),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            IconButton(
              key: ValueKey('pdf-insert-pages-up-$index'),
              tooltip: l10n.insertPagesMoveUp,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.arrow_upward, size: 18),
              onPressed: canMoveUp ? () => onMove(-1) : null,
            ),
            IconButton(
              key: ValueKey('pdf-insert-pages-down-$index'),
              tooltip: l10n.insertPagesMoveDown,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.arrow_downward, size: 18),
              onPressed: canMoveDown ? () => onMove(1) : null,
            ),
            IconButton(
              key: ValueKey('pdf-insert-pages-remove-$index'),
              tooltip: l10n.insertPagesRemoveFile,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 18),
              onPressed: onRemove,
            ),
          ]),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: LayoutBuilder(builder: (context, constraints) {
              final range = TextField(
                key: ValueKey('pdf-insert-pages-range-$index'),
                controller: entry.ranges,
                onChanged: (_) => onChanged(),
                decoration: _fieldDecoration(
                  label: l10n.insertPagesRange,
                  hint: l10n.insertPagesRangeHint,
                  error: invalid
                      ? l10n.insertPagesRangeInvalid(entry.pageCount)
                      : null,
                ),
                contextMenuBuilder: pdfTextContextMenu,
              );
              final subset = PdfDropdown<PdfPageSubset>(
                key: ValueKey('pdf-insert-pages-subset-$index'),
                value: entry.subset,
                isExpanded: true,
                decoration: _fieldDecoration(),
                items: [
                  PdfDropdownItem(
                      key: ValueKey('pdf-insert-pages-subset-$index-all'),
                      value: PdfPageSubset.all,
                      label: l10n.insertPagesSubsetAll,
                      child: _FieldText(l10n.insertPagesSubsetAll)),
                  PdfDropdownItem(
                      key: ValueKey('pdf-insert-pages-subset-$index-odd'),
                      value: PdfPageSubset.odd,
                      label: l10n.insertPagesSubsetOdd,
                      child: _FieldText(l10n.insertPagesSubsetOdd)),
                  PdfDropdownItem(
                      key: ValueKey('pdf-insert-pages-subset-$index-even'),
                      value: PdfPageSubset.even,
                      label: l10n.insertPagesSubsetEven,
                      child: _FieldText(l10n.insertPagesSubsetEven)),
                ],
                onChanged: (v) {
                  entry.subset = v;
                  onChanged();
                },
              );
              final reverse = _ToggleField(
                key: ValueKey('pdf-insert-pages-reverse-$index'),
                icon: Icons.swap_vert,
                label: l10n.insertPagesReverse,
                selected: entry.reverse,
                onChanged: (v) {
                  entry.reverse = v;
                  onChanged();
                },
              );
              if (constraints.maxWidth < _narrowWidth) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    range,
                    const SizedBox(height: 12),
                    Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: subset),
                          const SizedBox(width: 12),
                          Expanded(child: reverse),
                        ]),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: range),
                  const SizedBox(width: 12),
                  Expanded(flex: 3, child: subset),
                  const SizedBox(width: 12),
                  reverse,
                ],
              );
            }),
          ),
        ],
      ),
    );
  }
}

/// A drop-down value in the same type as the text fields beside it.
class _FieldText extends StatelessWidget {
  const _FieldText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodyLarge);
}

/// An on/off control drawn as an outlined field, so it sits on the same row
/// height and border as the text fields and drop-downs it lines up with.
class _ToggleField extends StatelessWidget {
  const _ToggleField({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground =
        selected ? scheme.onSecondaryContainer : scheme.onSurface;
    return Semantics(
      toggled: selected,
      child: Material(
        color: selected ? scheme.secondaryContainer : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(
              color: selected ? scheme.secondaryContainer : scheme.outline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onChanged(!selected),
          child: SizedBox(
            height: 48,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(selected ? Icons.check : icon,
                    size: 18, color: foreground),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge
                          ?.copyWith(color: foreground)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _RunField extends StatelessWidget {
  const _RunField({
    super.key,
    required this.controller,
    required this.label,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final n = int.tryParse(controller.text.trim());
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      onChanged: (_) => onChanged(),
      decoration: _fieldDecoration(
        label: label,
        error: n == null || n < 1 ? '≥ 1' : null,
      ),
      contextMenuBuilder: pdfTextContextMenu,
    );
  }
}
