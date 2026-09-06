import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_cos/pdf_cos.dart';

import 'l10n/app_l10n.dart';
import 'l10n/app_localizations.dart';
import 'middle_ellipsis_text.dart';
import 'print_settings.dart';
import 'print_composer.dart';

/// The source document and options confirmed for this print job.
class PrintPreviewResult {
  const PrintPreviewResult({required this.document, required this.settings});

  final PdfDocument document;
  final PrintSettings settings;
}

/// Which pages a print job covers.
enum PrintPageRange { all, current, selected, custom }

/// Parses one-based comma-separated pages and inclusive ranges. Duplicate
/// pages are emitted once, in the order entered; invalid input returns null.
List<int>? parsePrintPageRange(String input, int pageCount) {
  final result = <int>{};
  for (final part in input.split(',')) {
    final match = RegExp(r'^\s*(\d+)\s*(?:-\s*(\d+)\s*)?$').firstMatch(part);
    if (match == null) return null;
    final first = int.tryParse(match[1]!);
    final last = int.tryParse(match[2] ?? match[1]!);
    if (first == null ||
        last == null ||
        first < 1 ||
        last < 1 ||
        first > pageCount ||
        last > pageCount) {
      return null;
    }
    final step = first <= last ? 1 : -1;
    for (var page = first;; page += step) {
      result.add(page - 1);
      if (page == last) break;
    }
  }
  return result.isEmpty ? null : result.toList();
}

/// Shows the same composed sheets that are sent to the system print dialog.
Future<PrintPreviewResult?> showPrintPreviewDialog(
  BuildContext context, {
  required PdfDocument document,
  required String title,
  int currentPage = 0,
  List<int> selectedPages = const [],
  Future<List<PdfDocument>> Function()? addFiles,
}) =>
    showPdfDialog<PrintPreviewResult>(
      context: context,
      useRootNavigator: true,
      builder: (_) => PrintPreviewDialog(
        document: document,
        title: title,
        currentPage: currentPage,
        selectedPages: selectedPages,
        addFiles: addFiles,
      ),
    );

/// Document-level print settings, with native printer controls in the next
/// dialog. Adding files creates a separate print document.
class PrintPreviewDialog extends StatefulWidget {
  const PrintPreviewDialog({
    super.key,
    required this.document,
    required this.title,
    this.currentPage = 0,
    this.selectedPages = const [],
    this.addFiles,
  });

  final PdfDocument document;
  final String title;
  final int currentPage;
  final List<int> selectedPages;
  final Future<List<PdfDocument>> Function()? addFiles;

  @override
  State<PrintPreviewDialog> createState() => _PrintPreviewDialogState();
}

class _PrintPreviewDialogState extends State<PrintPreviewDialog> {
  late PdfDocument _document = widget.document;
  late final int _currentPage = widget.currentPage.clamp(0, _pageCount - 1);
  late PrintSettings _settings = PrintSettings(pages: _allPages);
  final _rangeInput = TextEditingController();
  final _previewAnchor = GlobalKey();
  final _numbers = <String, TextEditingController>{};
  final _invalidNumbers = <String>{};
  PrintPageRange _range = PrintPageRange.all;
  int _previewSlot = 0;
  bool _rangeInvalid = false;
  bool _choosingRegion = false;
  bool _addingFiles = false;
  String? _error;
  (PdfDocument, PrintSettings, int)? _previewFor;
  PdfDocument? _previewDocument;

  int get _pageCount => _document.pageCount;
  List<int> get _allPages => List.generate(_pageCount, (i) => i);
  List<int> get _selectedPages => widget.selectedPages
      .where((page) => page >= 0 && page < _pageCount)
      .toSet()
      .toList()
    ..sort();
  bool get _marginMode =>
      _settings.scaling == PrintScaling.fitMargins ||
      _settings.scaling == PrintScaling.reduceMargins ||
      _settings.scaling == PrintScaling.multiple;

  @override
  void initState() {
    super.initState();
    _previewSlot = _currentPage;
    _rangeInput.text = '${_currentPage + 1}-$_pageCount';
  }

  @override
  void dispose() {
    _rangeInput.dispose();
    for (final controller in _numbers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  List<int> get _pages => switch (_range) {
        PrintPageRange.all => _allPages,
        PrintPageRange.current => [_currentPage],
        PrintPageRange.selected => _selectedPages,
        PrintPageRange.custom =>
          parsePrintPageRange(_rangeInput.text, _pageCount) ?? [],
      };

  void _change(PrintSettings settings) {
    setState(() {
      _settings = settings;
      _error = null;
      _clampPreview();
    });
  }

  void _setRange(PrintPageRange range) {
    setState(() {
      _range = range;
      _rangeInvalid = false;
      _error = null;
      _settings = _settings.copyWith(
          pages: _pages, clearRegion: range != PrintPageRange.current);
      _choosingRegion = false;
      if (range == PrintPageRange.current) _previewSlot = 0;
      _clampPreview();
    });
  }

  void _clampPreview() {
    final count = printSheetCount(_settings);
    _previewSlot = count == 0 ? 0 : _previewSlot.clamp(0, count - 1);
  }

  void _defaults() {
    setState(() {
      _range = PrintPageRange.all;
      _settings = PrintSettings(pages: _allPages);
      _previewSlot = _currentPage;
      _rangeInvalid = false;
      _choosingRegion = false;
      _error = null;
      _invalidNumbers.clear();
      for (final entry in _numbers.entries) {
        entry.value.text = switch (entry.key) {
          'copies' => '1',
          'scale' => '100',
          'margin' => '18',
          'offset-x' || 'offset-y' => '0',
          _ => '',
        };
      }
    });
  }

  Future<void> _addFiles() async {
    setState(() => _addingFiles = true);
    try {
      final incoming = await widget.addFiles!();
      if (!mounted || incoming.isEmpty) return;
      // Import into an empty document so the job owns its objects and keeps
      // each source's form resources, including encrypted sources already open.
      final builder = CosDocumentBuilder();
      final pages = builder.add(CosDictionary({
        'Type': const CosName('Pages'),
        'Count': const CosInteger(0),
        'Kids': CosArray([]),
      }));
      final catalog = builder.add(
          CosDictionary({'Type': const CosName('Catalog'), 'Pages': pages}));
      final editor = PdfEditor(PdfDocument.open(builder.build(root: catalog)));
      editor.appendPagesFrom(_document);
      for (final document in incoming) {
        editor.appendPagesFrom(document);
      }
      final merged = PdfDocument.open(editor.save());
      if (!mounted) return;
      setState(() {
        _document = merged;
        _settings = _settings.copyWith(pages: _pages);
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = appL10n(context).printOptionsAddFailed);
      }
    } finally {
      if (mounted) setState(() => _addingFiles = false);
    }
  }

  void _print() {
    if (_settings.pages.isEmpty || _invalidNumbers.isNotEmpty) {
      setState(() => _rangeInvalid = _settings.pages.isEmpty);
      return;
    }
    try {
      validatePrintSettings(_document, _settings);
    } catch (_) {
      setState(() => _error = appL10n(context).printOptionsInvalidLayout);
      return;
    }
    if (_sheet() == null) {
      setState(() => _error = appL10n(context).printOptionsInvalidLayout);
      return;
    }
    Navigator.of(context)
        .pop(PrintPreviewResult(document: _document, settings: _settings));
  }

  PdfDocument? _sheet() {
    if (_settings.pages.isEmpty) return null;
    final key = (_document, _settings, _previewSlot);
    if (_previewFor != key) {
      _previewFor = key;
      try {
        _previewDocument = PdfDocument.open(preparePrintDocument(
            _document, _settings,
            includeCopies: false, sheetIndex: _previewSlot));
      } catch (_) {
        _previewDocument = null;
      }
    }
    return _previewDocument;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = appL10n(context);
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final narrow = media.size.width < 800;
    final size = Size(
        (media.size.width - (narrow ? 24 : 48)).clamp(0, 1160),
        (media.size.height - media.viewInsets.bottom - (narrow ? 24 : 48))
            .clamp(0, 860));
    final options = _options(l10n);
    final preview = _preview(l10n);
    return Dialog(
      key: const ValueKey('print-preview-dialog'),
      insetPadding: EdgeInsets.all(narrow ? 12 : 24),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: size.width,
        height: size.height,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(children: [
              const Icon(Icons.print_outlined),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(l10n.printPreviewTitle,
                        style: theme.textTheme.titleLarge),
                    MiddleEllipsisText(widget.title,
                        hidePdfExtension: true,
                        style: theme.textTheme.bodySmall),
                  ])),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
              child: narrow
                  ? SingleChildScrollView(
                      key: const ValueKey('print-options-scroll'),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(height: 310, child: preview),
                            const Divider(height: 24),
                            options,
                          ]),
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                          SizedBox(
                              width: 360,
                              child: SingleChildScrollView(
                                  key: const ValueKey('print-options-scroll'),
                                  padding: const EdgeInsets.all(20),
                                  child: options)),
                          const VerticalDivider(width: 1),
                          Expanded(
                              child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: preview)),
                        ])),
          const Divider(height: 1),
          Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null ||
                      _rangeInvalid ||
                      _invalidNumbers.isNotEmpty)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                            _error ??
                                (_rangeInvalid
                                    ? l10n.printPreviewRangeError(_pageCount)
                                    : l10n.printOptionsInvalidNumber),
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.colorScheme.error))),
                  OverflowBar(
                      alignment: MainAxisAlignment.spaceBetween,
                      overflowAlignment: OverflowBarAlignment.end,
                      spacing: 8,
                      children: [
                        TextButton(
                            key: const ValueKey('print-options-defaults'),
                            onPressed: _defaults,
                            child: Text(l10n.printOptionsDefaults)),
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          TextButton(
                              key: const ValueKey('print-preview-cancel'),
                              onPressed: () => Navigator.of(context).pop(),
                              child: Text(l10n.cancel)),
                          const SizedBox(width: 8),
                          FilledButton(
                              key: const ValueKey('print-preview-print'),
                              onPressed: _addingFiles ? null : _print,
                              child: Text(l10n.printPreviewPrint)),
                        ]),
                      ]),
                ],
              )),
        ]),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 10),
          ...children,
        ]),
      );

  Widget _dropdown<T>(String key, String label, T value, Map<T, String> options,
          ValueChanged<T> changed) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: InputDecorator(
          decoration: InputDecoration(
              labelText: label,
              isDense: true,
              border: const OutlineInputBorder()),
          child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
            key: ValueKey('print-options-$key'),
            value: value,
            isExpanded: true,
            isDense: true,
            items: [
              for (final entry in options.entries)
                DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value, overflow: TextOverflow.ellipsis))
            ],
            onChanged: (value) {
              if (value != null) changed(value);
            },
          )),
        ),
      );

  Widget _check(
          String key, String label, bool value, ValueChanged<bool> changed,
          {bool enabled = true}) =>
      CheckboxListTile(
        key: ValueKey('print-options-$key'),
        value: value,
        title: Text(label),
        dense: true,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        onChanged: enabled ? (value) => changed(value!) : null,
      );

  Widget _number(
      String key, String label, double value, ValueChanged<double> changed,
      {double min = -100000, double max = 100000, bool integer = false}) {
    final controller = _numbers.putIfAbsent(
        key, () => TextEditingController(text: _format(value)));
    return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          key: ValueKey('print-options-$key'),
          controller: controller,
          keyboardType: TextInputType.numberWithOptions(
              decimal: !integer, signed: min < 0),
          decoration: InputDecoration(
              labelText: label,
              isDense: true,
              border: const OutlineInputBorder(),
              errorText: _invalidNumbers.contains(key)
                  ? appL10n(context).printOptionsInvalidValue
                  : null),
          onChanged: (text) {
            final number = double.tryParse(text);
            if (number == null ||
                !number.isFinite ||
                number < min ||
                number > max ||
                (integer && number != number.roundToDouble())) {
              setState(() => _invalidNumbers.add(key));
            } else {
              _invalidNumbers.remove(key);
              changed(number);
            }
          },
        ));
  }

  double _pageUnit(PdfPage page) {
    final value = _document.cos.resolve(page.dict['UserUnit']);
    final unit = switch (value) {
      CosInteger(:final value) => value.toDouble(),
      CosReal(:final value) => value,
      _ => 1.0
    };
    return unit.isFinite && unit > 0 ? unit : 1.0;
  }

  String _format(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);

  Widget _options(AppLocalizations l10n) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _section(l10n.printOptionsPrinter, [
          Text(l10n.printOptionsNativePrinter,
              style: Theme.of(context).textTheme.bodySmall),
        ]),
        _section(l10n.printOptionsPages, [
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final entry in {
              PrintPageRange.all: l10n.printPreviewAll,
              PrintPageRange.current: l10n.printPreviewCurrent,
              if (_selectedPages.isNotEmpty)
                PrintPageRange.selected: l10n.printOptionsSelected,
              PrintPageRange.custom: l10n.printPreviewRange,
            }.entries)
              ChoiceChip(
                  key: ValueKey('print-preview-${entry.key.name}'),
                  label: Text(entry.value),
                  selected: _range == entry.key,
                  onSelected: (_) => _setRange(entry.key)),
          ]),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('print-preview-range'),
            controller: _rangeInput,
            decoration: InputDecoration(
                labelText: l10n.printOptionsPageRange,
                hintText: '1, 3-5',
                isDense: true,
                border: const OutlineInputBorder()),
            onChanged: (_) => _setRange(PrintPageRange.custom),
          ),
          const SizedBox(height: 8),
          Text(l10n.printPreviewSelection(_settings.pages.length),
              style: Theme.of(context).textTheme.bodySmall),
          if (widget.addFiles != null)
            Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                    key: const ValueKey('print-options-add-files'),
                    onPressed: _addingFiles ? null : _addFiles,
                    icon: const Icon(Icons.note_add_outlined),
                    label: Text(l10n.printOptionsAddFiles))),
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(
                key: const ValueKey('print-options-window'),
                onPressed: () {
                  final choosing = !_choosingRegion;
                  _setRange(PrintPageRange.current);
                  setState(() => _choosingRegion = choosing);
                  if (choosing) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      final previewContext = _previewAnchor.currentContext;
                      if (mounted && previewContext != null) {
                        Scrollable.ensureVisible(previewContext,
                            duration: const Duration(milliseconds: 200));
                      }
                    });
                  }
                },
                icon: const Icon(Icons.crop),
                label: Text(l10n.printOptionsGetWindow)),
            if (_settings.region != null)
              TextButton(
                  key: const ValueKey('print-options-clear-window'),
                  onPressed: () =>
                      _change(_settings.copyWith(clearRegion: true)),
                  child: Text(l10n.printOptionsClearWindow)),
          ]),
          if (_settings.region case final region?)
            Text(
                l10n.printOptionsAreaSize(
                    _format(
                        region.width * _pageUnit(_document.page(_currentPage))),
                    _format(region.height *
                        _pageUnit(_document.page(_currentPage)))),
                style: Theme.of(context).textTheme.bodySmall),
        ]),
        _section(l10n.printOptionsPaper, [
          _dropdown(
              'paper',
              l10n.printOptionsPaperSize,
              _settings.paperSize,
              {
                PrintPaperSize.auto: l10n.printOptionsPageSize,
                for (final paper in PrintPaperSize.values
                    .where((p) => p != PrintPaperSize.auto))
                  paper: paper.name.toUpperCase(),
              },
              (value) => _change(_settings.copyWith(paperSize: value))),
          _dropdown(
              'orientation',
              l10n.printOptionsOrientation,
              _settings.orientation,
              {
                PrintOrientation.auto: l10n.printOptionsAuto,
                PrintOrientation.portrait: l10n.printOptionsPortrait,
                PrintOrientation.landscape: l10n.printOptionsLandscape,
              },
              (value) => _change(_settings.copyWith(orientation: value))),
        ]),
        _section(l10n.printOptionsCopies, [
          _number(
              'copies',
              l10n.printOptionsCopies,
              _settings.copies.toDouble(),
              (value) => _change(_settings.copyWith(copies: value.toInt())),
              min: 1,
              max: 999,
              integer: true),
          _check('collate', l10n.printOptionsCollate, _settings.collate,
              (value) => _change(_settings.copyWith(collate: value))),
          _check('reverse', l10n.printOptionsReverse, _settings.reverse,
              (value) => _change(_settings.copyWith(reverse: value))),
        ]),
        _section(l10n.printOptionsLayout, [
          _dropdown('scaling', l10n.printOptionsScaling, _settings.scaling, {
            PrintScaling.none: l10n.printOptionsScaleNone,
            PrintScaling.fitPaper: l10n.printOptionsFitPaper,
            PrintScaling.reducePaper: l10n.printOptionsReducePaper,
            PrintScaling.fitMargins: l10n.printOptionsFitMargins,
            PrintScaling.reduceMargins: l10n.printOptionsReduceMargins,
            PrintScaling.custom: l10n.printOptionsCustomScale,
            PrintScaling.multiple: l10n.printOptionsMultiple,
          }, (value) {
            if (_invalidNumbers.remove('scale')) {
              _numbers['scale']?.text = _format(_settings.customScale);
            }
            if (_invalidNumbers.remove('margin')) {
              _numbers['margin']?.text = _format(_settings.margin);
            }
            _change(_settings.copyWith(scaling: value));
          }),
          if (_settings.scaling == PrintScaling.custom)
            _number(
                'scale',
                l10n.printOptionsScalePercent,
                _settings.customScale,
                (value) => _change(_settings.copyWith(customScale: value)),
                min: 1,
                max: 1000),
          if (_marginMode)
            _number('margin', l10n.printOptionsMargin, _settings.margin,
                (value) => _change(_settings.copyWith(margin: value)),
                min: 0, max: 200),
          if (_settings.scaling == PrintScaling.multiple) ...[
            _dropdown(
                'pages-per-sheet',
                l10n.printOptionsPagesPerSheet,
                _settings.pagesPerSheet,
                {
                  for (final count in [2, 4, 6, 9, 16]) count: '$count'
                },
                (value) => _change(_settings.copyWith(pagesPerSheet: value))),
            _dropdown(
                'page-layout',
                l10n.printOptionsPageOrder,
                _settings.layout,
                {
                  PrintPageLayout.horizontal: l10n.printOptionsHorizontal,
                  PrintPageLayout.horizontalReverse:
                      l10n.printOptionsHorizontalReverse,
                  PrintPageLayout.vertical: l10n.printOptionsVertical,
                  PrintPageLayout.verticalReverse:
                      l10n.printOptionsVerticalReverse,
                },
                (value) => _change(_settings.copyWith(layout: value))),
            _check('border', l10n.printOptionsBorder, _settings.printBorder,
                (value) => _change(_settings.copyWith(printBorder: value))),
          ],
          _dropdown(
              'rotation',
              l10n.printOptionsRotation,
              _settings.rotation,
              {
                PrintRotation.auto: l10n.printOptionsAuto,
                PrintRotation.none: l10n.printOptionsNoRotation,
                PrintRotation.clockwise90: '90°',
                PrintRotation.halfTurn: '180°',
                PrintRotation.clockwise270: '270°',
              },
              (value) => _change(_settings.copyWith(rotation: value))),
          _check('center', l10n.printOptionsCenter, _settings.center,
              (value) => _change(_settings.copyWith(center: value))),
          Row(children: [
            Expanded(
                child: _number(
                    'offset-x',
                    l10n.printOptionsOffsetX,
                    _settings.offsetX,
                    (value) => _change(_settings.copyWith(offsetX: value)))),
            const SizedBox(width: 12),
            Expanded(
                child: _number(
                    'offset-y',
                    l10n.printOptionsOffsetY,
                    _settings.offsetY,
                    (value) => _change(_settings.copyWith(offsetY: value)))),
          ]),
        ]),
        _section(l10n.printOptionsContents, [
          _dropdown(
              'content',
              l10n.printOptionsContents,
              _settings.content,
              {
                PrintContent.documentAndMarkups:
                    l10n.printOptionsDocumentAndMarkups,
                PrintContent.documentOnly: l10n.printOptionsDocumentOnly,
                PrintContent.markupsOnly: l10n.printOptionsMarkupsOnly,
              },
              (value) => _change(_settings.copyWith(content: value))),
          _check('dim-page', l10n.printOptionsDimPage, _settings.dimPageContent,
              (value) => _change(_settings.copyWith(dimPageContent: value)),
              enabled: _settings.content != PrintContent.markupsOnly),
          _check(
              'dim-markups',
              l10n.printOptionsDimMarkups,
              _settings.dimMarkups,
              (value) => _change(_settings.copyWith(dimMarkups: value)),
              enabled: _settings.content != PrintContent.documentOnly),
          _check(
              'hyperlinks',
              l10n.printOptionsHyperlinks,
              _settings.printVisibleHyperlinks,
              (value) =>
                  _change(_settings.copyWith(printVisibleHyperlinks: value))),
        ]),
      ]);

  Widget _preview(AppLocalizations l10n) {
    final sheet = _choosingRegion ? _document : _sheet();
    final pageIndex = _choosingRegion ? _currentPage : 0;
    final count = printSheetCount(_settings);
    final orderedPages =
        _settings.reverse ? _settings.pages.reversed.toList() : _settings.pages;
    final sourceIndex = _settings.pages.isEmpty
        ? _currentPage
        : orderedPages[(_previewSlot *
                (_settings.scaling == PrintScaling.multiple
                    ? _settings.pagesPerSheet
                    : 1))
            .clamp(0, _settings.pages.length - 1)];
    final sourcePage = _document.page(sourceIndex);
    final unit = _pageUnit(sourcePage);
    final source = PdfPageRenderer.pageSize(sourcePage) * unit;
    final size =
        sheet == null ? null : PdfPageRenderer.pageSize(sheet.page(pageIndex));
    return Column(
        key: _previewAnchor,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_choosingRegion)
            Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(l10n.printOptionsWindowHint)),
          Expanded(
              child: ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: sheet == null
                          ? Center(
                              child: Text(_settings.pages.isEmpty
                                  ? l10n.printPreviewRangeError(_pageCount)
                                  : l10n.printPreviewUnavailable))
                          : _PagePreview(
                              document: sheet,
                              pageIndex: pageIndex,
                              margin: !_choosingRegion && _marginMode
                                  ? _settings.margin
                                  : 0,
                              region: _choosingRegion ? _settings.region : null,
                              onRegionSelected: !_choosingRegion
                                  ? null
                                  : (region) {
                                      setState(() {
                                        _settings =
                                            _settings.copyWith(region: region);
                                        _choosingRegion = false;
                                      });
                                    },
                            )))),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(
                key: const ValueKey('print-preview-previous'),
                icon: const Icon(Icons.chevron_left),
                tooltip: l10n.printPreviewPreviousPage,
                onPressed: !_choosingRegion && _previewSlot > 0
                    ? () => setState(() => _previewSlot--)
                    : null),
            Flexible(
                child: Text(_choosingRegion
                    ? l10n.printPreviewPageOf(_currentPage + 1, _pageCount)
                    : _settings.scaling == PrintScaling.multiple
                        ? l10n.printOptionsSheetOf(
                            count == 0 ? 0 : _previewSlot + 1, count)
                        : l10n.printPreviewPageOf(
                            sourceIndex + 1, _pageCount))),
            IconButton(
                key: const ValueKey('print-preview-next'),
                icon: const Icon(Icons.chevron_right),
                tooltip: l10n.printPreviewNextPage,
                onPressed: !_choosingRegion && _previewSlot < count - 1
                    ? () => setState(() => _previewSlot++)
                    : null),
          ]),
          Text(
              l10n.printOptionsSourceSize(
                  _format(source.width), _format(source.height)),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall),
          if (size != null && !_choosingRegion)
            Text(
                l10n.printOptionsSheetSize(
                    _format(size.width), _format(size.height)),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
          if (_marginMode && !_choosingRegion)
            Text(l10n.printOptionsMarginGuide,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
        ]);
  }
}

/// Fits the raster and its interactive crop area to exactly the same bounds.
class _PagePreview extends StatefulWidget {
  const _PagePreview(
      {required this.document,
      required this.pageIndex,
      this.margin = 0,
      this.region,
      this.onRegionSelected});
  final PdfDocument document;
  final int pageIndex;
  final double margin;
  final PdfRect? region;
  final ValueChanged<PdfRect>? onRegionSelected;

  @override
  State<_PagePreview> createState() => _PagePreviewState();
}

class _PagePreviewState extends State<_PagePreview> {
  ui.Image? _image;
  int _token = 0;
  (PdfDocument, int, int)? _rendered;
  bool _failed = false;
  Offset? _dragStart;
  Rect? _dragRect;

  @override
  void dispose() {
    _token++;
    _image?.dispose();
    super.dispose();
  }

  void _renderIfNeeded(double width, double ratio) {
    final bucket = (width / 32).ceil();
    final key = (widget.document, widget.pageIndex, bucket);
    if (_rendered == key) return;
    _rendered = key;
    final token = ++_token;
    final page = widget.document.page(widget.pageIndex);
    final size = PdfPageRenderer.pageSize(page);
    final pixelRatio = math.min(
        (bucket * 32 * ratio / math.max(1, size.width)).clamp(0.01, 4.0),
        math.min(4096 / math.max(size.width, size.height),
            math.sqrt(4000000 / math.max(1, size.width * size.height))));
    () async {
      try {
        final image =
            await PdfPageRenderer.renderImage(page, pixelRatio: pixelRatio);
        if (!mounted || token != _token) {
          image.dispose();
          return;
        }
        setState(() {
          _image?.dispose();
          _image = image;
          _failed = false;
        });
      } catch (_) {
        if (!mounted || token != _token) return;
        setState(() {
          _image?.dispose();
          _image = null;
          _failed = true;
        });
      }
    }();
  }

  @override
  Widget build(BuildContext context) {
    final pageSize =
        PdfPageRenderer.pageSize(widget.document.page(widget.pageIndex));
    final ratio = MediaQuery.of(context).devicePixelRatio;
    return LayoutBuilder(builder: (context, constraints) {
      final fit = applyBoxFit(BoxFit.contain, pageSize, constraints.biggest)
          .destination;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _renderIfNeeded(fit.width, ratio);
      });
      final image = _image;
      if (image == null) {
        return Center(
            child: _failed
                ? Text(appL10n(context).printPreviewUnavailable)
                : const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2)));
      }
      Offset clamp(Offset point) =>
          Offset(point.dx.clamp(0, fit.width), point.dy.clamp(0, fit.height));
      return Center(
          child: SizedBox(
              width: fit.width,
              height: fit.height,
              child: MouseRegion(
                cursor: widget.onRegionSelected == null
                    ? MouseCursor.defer
                    : SystemMouseCursors.precise,
                child: GestureDetector(
                  dragStartBehavior: DragStartBehavior.down,
                  behavior: HitTestBehavior.opaque,
                  onPanStart: widget.onRegionSelected == null
                      ? null
                      : (details) => setState(() {
                            _dragStart = clamp(details.localPosition);
                            _dragRect =
                                Rect.fromPoints(_dragStart!, _dragStart!);
                          }),
                  onPanUpdate: widget.onRegionSelected == null
                      ? null
                      : (details) => setState(() {
                            _dragRect = Rect.fromPoints(
                                _dragStart!, clamp(details.localPosition));
                          }),
                  onPanEnd: widget.onRegionSelected == null
                      ? null
                      : (_) {
                          final rect = _dragRect;
                          setState(() {
                            _dragStart = null;
                            _dragRect = null;
                          });
                          if (rect == null ||
                              rect.width < 3 ||
                              rect.height < 3) {
                            return;
                          }
                          widget.onRegionSelected!(PdfRect(
                              rect.left / fit.width * pageSize.width,
                              rect.top / fit.height * pageSize.height,
                              rect.right / fit.width * pageSize.width,
                              rect.bottom / fit.height * pageSize.height));
                        },
                  onPanCancel: widget.onRegionSelected == null
                      ? null
                      : () => setState(() {
                            _dragStart = null;
                            _dragRect = null;
                          }),
                  child: CustomPaint(
                      key: const ValueKey('print-preview-page'),
                      painter: _PagePreviewPainter(image, pageSize,
                          margin: widget.margin,
                          crop: _dragRect ??
                              (widget.region == null
                                  ? null
                                  : Rect.fromLTRB(
                                      widget.region!.left /
                                          pageSize.width *
                                          fit.width,
                                      widget.region!.bottom /
                                          pageSize.height *
                                          fit.height,
                                      widget.region!.right /
                                          pageSize.width *
                                          fit.width,
                                      widget.region!.top /
                                          pageSize.height *
                                          fit.height)))),
                ),
              )));
    });
  }
}

class _PagePreviewPainter extends CustomPainter {
  const _PagePreviewPainter(this.image, this.pageSize,
      {this.margin = 0, this.crop});
  final ui.Image image;
  final Size pageSize;
  final double margin;
  final Rect? crop;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Offset.zero & size,
        Paint()..filterQuality = FilterQuality.medium);
    if (margin > 0) {
      final inset = margin / pageSize.width * size.width;
      final rect = (Offset.zero & size).deflate(inset);
      if (!rect.isEmpty) {
        canvas.drawRect(
            rect,
            Paint()
              ..color = const Color(0xCCEF4444)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1);
      }
    }
    if (crop case final rect?) {
      final shade = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addRect(rect);
      canvas.drawPath(shade, Paint()..color = const Color(0x66000000));
      canvas.drawRect(
          rect,
          Paint()
            ..color = const Color(0xFF2196F3)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(_PagePreviewPainter old) =>
      !identical(old.image, image) ||
      old.pageSize != pageSize ||
      old.margin != margin ||
      old.crop != crop;
}
