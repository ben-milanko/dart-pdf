import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf_document/pdf_document.dart';
import '../l10n/pdf_l10n.dart';
import '../editing/editing_color_picker.dart';
import '../editing/editing_font_controls.dart';
import '../font_substitution.dart';
import 'material_host.dart';

class PdfTableEditorDialog extends StatefulWidget {
  const PdfTableEditorDialog({super.key, this.initial, this.onCopyCells});
  final Future<void> Function(String)? onCopyCells;
  final PdfTableData? initial;
  @override
  State<PdfTableEditorDialog> createState() => _PdfTableEditorDialogState();
}

class _PdfTableEditorDialogState extends State<PdfTableEditorDialog> {
  late List<List<String>> _cells;
  late List<double> _widths;
  late List<double> _heights;
  late bool _header;
  late double _fontSize;
  late PdfStandardFont _font;
  late int _textColor, _backgroundColor, _headerColor, _borderColor;
  late double _borderWidth;
  late bool _gridLines;
  bool _styling = false;
  final Map<(int, int), TextEditingController> _fields = {};
  final Map<(int, int), FocusNode> _focus = {};
  final _horizontalScroll = ScrollController();
  final _verticalScroll = ScrollController();
  int _row = 0, _column = 0, _anchorRow = 0, _anchorColumn = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial ??
        PdfTableData(List.generate(3, (_) => List.filled(3, '')));
    _cells = [
      for (final row in initial.cells) [...row]
    ];
    _widths = [...initial.columnWidths];
    _heights = [...initial.rowHeights];
    _header = initial.headerRow;
    _fontSize = initial.fontSize;
    _font = initial.font;
    _textColor = initial.textColor;
    _backgroundColor = initial.backgroundColor;
    _headerColor = initial.headerColor;
    _borderColor = initial.borderColor;
    _borderWidth = initial.borderWidth;
    _gridLines = initial.gridLines;
  }

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    for (final node in _focus.values) {
      node.dispose();
    }
    _horizontalScroll.dispose();
    _verticalScroll.dispose();
    super.dispose();
  }

  void _readDraftCells() {
    for (final entry in _fields.entries) {
      final (r, c) = entry.key;
      if (r < _cells.length && c < _widths.length) {
        _cells[r][c] = entry.value.text;
      }
    }
  }

  PdfTableData get _value {
    // The text controllers also hold any in-flight IME composition. Read them
    // at submit/copy time rather than relying only on onChanged ordering.
    _readDraftCells();
    return PdfTableData(_cells,
        columnWidths: _widths,
        rowHeights: _heights,
        fontSize: _fontSize,
        headerRow: _header,
        textColor: _textColor,
        borderColor: _borderColor,
        headerColor: _headerColor,
        backgroundColor: _backgroundColor,
        font: _font,
        gridLines: _gridLines,
        borderWidth: _borderWidth);
  }

  Widget _styles() {
    final labels = pdfL10n(context);
    Widget color(
            String key, String label, int value, void Function(int) update) =>
        TextButton.icon(
            key: ValueKey('pdf-table-$key-color'),
            icon: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                    color: Color(0xFF000000 | value),
                    border: Border.all(
                        color: Theme.of(context).colorScheme.outline))),
            label: Text(label),
            onPressed: () async {
              final picked = await showPdfColorPicker(context,
                  initial: Color(0xFF000000 | value));
              if (mounted && picked != null) {
                setState(() => update(picked.toARGB32() & 0xFFFFFF));
              }
            });
    return SingleChildScrollView(
        key: const ValueKey('pdf-table-style-panel'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(labels.tableStyleHint),
          const SizedBox(height: 12),
          Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(labels.propFont),
                PdfDropdown<PdfStandardFontFamily>(
                    key: const ValueKey('pdf-table-font'),
                    value: _font.family,
                    items: [
                      for (final family in PdfStandardFontFamily.values)
                        PdfDropdownItem(
                            value: family,
                            label: switch (family) {
                              PdfStandardFontFamily.sans => 'Helvetica',
                              PdfStandardFontFamily.serif => 'Times',
                              PdfStandardFontFamily.mono => 'Courier',
                            })
                    ],
                    onChanged: (family) {
                      setState(() => _font = PdfStandardFont.styled(family,
                          bold: _font.isBold, italic: _font.isItalic));
                    }),
                FontStyleToggles(
                    font: _font,
                    keyPrefix: 'pdf-table-font',
                    onChanged: (font) => setState(() => _font = font)),
              ]),
          Wrap(spacing: 8, children: [
            color('background', labels.tableBackgroundColor, _backgroundColor,
                (value) => _backgroundColor = value),
            color('header', labels.tableHeaderColor, _headerColor,
                (value) => _headerColor = value),
            color('text', labels.tableTextColor, _textColor,
                (value) => _textColor = value),
          ]),
          SwitchListTile.adaptive(
              key: const ValueKey('pdf-table-grid-lines'),
              contentPadding: EdgeInsets.zero,
              title: Text(labels.tableGridLines),
              value: _gridLines,
              onChanged: (value) => setState(() => _gridLines = value)),
          Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                color('grid', labels.tableGridColor, _borderColor,
                    (value) => _borderColor = value),
                SizedBox(
                    width: 140,
                    child: TextFormField(
                        key: const ValueKey('pdf-table-grid-width'),
                        initialValue: _borderWidth.toString(),
                        contextMenuBuilder: pdfTextContextMenu,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                            labelText: labels.tableGridWidth, suffixText: 'pt'),
                        onChanged: (text) {
                          final width = double.tryParse(text);
                          if (width != null &&
                              width.isFinite &&
                              width > 0 &&
                              width <= 20) {
                            setState(() => _borderWidth = width);
                          }
                        })),
              ]),
        ]));
  }

  void _resetFields() {
    // EditableText may still be attached until the next build. Reset values
    // in place instead of disposing its controller during a paste or resize.
    for (final e in _fields.entries) {
      final (r, c) = e.key;
      if (r < _cells.length && c < _widths.length) e.value.text = _cells[r][c];
    }
  }

  void _select(int r, int c, {bool extend = false}) => setState(() {
        if (!extend) {
          _anchorRow = r;
          _anchorColumn = c;
        }
        _row = r;
        _column = c;
      });

  void _focusCell(int r, int c, {bool extend = false}) {
    _select(r, c, extend: extend);
    final field = _fields[(r, c)]!;
    field.selection =
        TextSelection(baseOffset: 0, extentOffset: field.text.length);
    final node = _focus[(r, c)]!;
    node.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && node.context != null) {
        Scrollable.ensureVisible(node.context!,
            duration: const Duration(milliseconds: 100), alignment: .5);
      }
    });
  }

  KeyEventResult _cellKey(int r, int c, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final field = _fields[(r, c)]!;
    if (!field.value.composing.isCollapsed) return KeyEventResult.ignored;
    var row = r, column = c;
    if (key == LogicalKeyboardKey.tab) {
      final index = r * _widths.length + c + (keyboard.isShiftPressed ? -1 : 1);
      if (index < 0 || index >= _cells.length * _widths.length) {
        return KeyEventResult
            .ignored; // leave the grid, never trap keyboard focus
      }
      row = index ~/ _widths.length;
      column = index % _widths.length;
    } else {
      final selection = field.selection;
      if (!selection.isValid) return KeyEventResult.ignored;
      final all = selection.start == 0 && selection.end == field.text.length;
      // Newly focused cells select their contents, so arrows navigate the grid.
      // After a click/typing, retain ordinary caret movement inside the text;
      // crossing its first/last line or start/end moves to the adjacent cell.
      if (key == LogicalKeyboardKey.arrowLeft &&
          (all || selection.isCollapsed && selection.start == 0)) {
        column--;
      } else if (key == LogicalKeyboardKey.arrowRight &&
          (all ||
              selection.isCollapsed && selection.end == field.text.length)) {
        column++;
      } else if (key == LogicalKeyboardKey.arrowUp &&
          (all ||
              selection.isCollapsed && _atVerticalEdge(r, c, above: true))) {
        row--;
      } else if (key == LogicalKeyboardKey.arrowDown &&
          (all ||
              selection.isCollapsed && _atVerticalEdge(r, c, above: false))) {
        row++;
      } else {
        return KeyEventResult.ignored;
      }
      if (row < 0 ||
          row >= _cells.length ||
          column < 0 ||
          column >= _widths.length) {
        return KeyEventResult.ignored;
      }
    }
    _focusCell(row, column,
        extend: key != LogicalKeyboardKey.tab && keyboard.isShiftPressed);
    return KeyEventResult.handled;
  }

  bool _atVerticalEdge(int r, int c, {required bool above}) {
    final field = _fields[(r, c)]!;
    final editable = _focus[(r, c)]!
        .context
        ?.findAncestorStateOfType<EditableTextState>()
        ?.renderEditable;
    if (editable == null) {
      return above
          ? field.selection.start == 0
          : field.selection.end == field.text.length;
    }
    final caret = editable.getLocalRectForCaret(field.selection.extent);
    final edge = editable.getLocalRectForCaret(
        TextPosition(offset: above ? 0 : field.text.length));
    return (caret.top - edge.top).abs() < .5;
  }

  String _columnLabel(int column) {
    var label = '';
    for (var n = column + 1; n > 0; n = (n - 1) ~/ 26) {
      label = String.fromCharCode(65 + (n - 1) % 26) + label;
    }
    return label;
  }

  Widget _grid() => LayoutBuilder(builder: (context, constraints) {
        final colors = Theme.of(context).colorScheme;
        final scale = math.max(
            1.5,
            (constraints.maxWidth - 44) /
                _widths.fold<double>(0, (a, b) => a + b));
        final widths = [
          for (final width in _widths) math.max(96.0, width * scale)
        ];
        final columns = <int, TableColumnWidth>{
          0: const FixedColumnWidth(44),
          for (var c = 0; c < widths.length; c++)
            c + 1: FixedColumnWidth(widths[c]),
        };
        Widget heading(String label) => Container(
            padding: const EdgeInsets.all(8),
            alignment: Alignment.center,
            color: colors.surfaceContainerHighest,
            child: Text(label));
        Widget cell(int r, int c) {
          final selected = r >= math.min(_row, _anchorRow) &&
              r <= math.max(_row, _anchorRow) &&
              c >= math.min(_column, _anchorColumn) &&
              c <= math.max(_column, _anchorColumn);
          final node = _focus.putIfAbsent((r, c), () => FocusNode());
          return Container(
              key: ValueKey('pdf-table-grid-cell-$r-$c'),
              constraints: BoxConstraints(minHeight: math.max(40, _heights[r])),
              color: Color(0xFF000000 |
                  (r == 0 && _header ? _headerColor : _backgroundColor)),
              // Keep this decoration wrapper even when unselected: inserting
              // it on focus would remount EditableText during text input.
              foregroundDecoration: BoxDecoration(
                  border: Border.all(
                      color: selected ? colors.primary : Colors.transparent,
                      width: 2)),
              child: Focus(
                  skipTraversal: true,
                  canRequestFocus: false,
                  onFocusChange: (focused) {
                    if (focused && (_row != r || _column != c)) {
                      _select(r, c,
                          extend: HardwareKeyboard.instance.isShiftPressed);
                    }
                  },
                  onKeyEvent: (_, event) => _cellKey(r, c, event),
                  child: TextField(
                      key: ValueKey('pdf-table-cell-$r-$c'),
                      focusNode: node,
                      controller: _fields.putIfAbsent((r, c),
                          () => TextEditingController(text: _cells[r][c])),
                      contextMenuBuilder: pdfTextContextMenu,
                      onTap: () => _select(r, c,
                          extend: HardwareKeyboard.instance.isShiftPressed),
                      onChanged: (text) => setState(() => _cells[r][c] = text),
                      minLines: 1,
                      maxLines: null,
                      scrollPhysics: const NeverScrollableScrollPhysics(),
                      textAlignVertical: TextAlignVertical.top,
                      style: TextStyle(
                          fontSize: _fontSize,
                          fontFamily: pdfBundledSubstituteFor(_font.baseFont)
                              .packageFamily,
                          fontFamilyFallback: [
                            pdfBundledSubstituteFor(_font.baseFont).family,
                            ...pdfBundledSubstituteFor(_font.baseFont)
                                .systemFallbacks
                          ],
                          fontWeight: _font.isBold
                              ? FontWeight.bold
                              : FontWeight.normal,
                          fontStyle: _font.isItalic
                              ? FontStyle.italic
                              : FontStyle.normal,
                          color: Color(0xFF000000 | _textColor)),
                      decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.all(8),
                          hintText: '${_columnLabel(c)}${r + 1}'))));
        }

        return FocusTraversalGroup(
            policy: WidgetOrderTraversalPolicy(),
            child: Scrollbar(
                controller: _horizontalScroll,
                thumbVisibility: true,
                notificationPredicate: (notification) =>
                    notification.depth == 0,
                child: SingleChildScrollView(
                    controller: _horizontalScroll,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                        width: 44 + widths.fold<double>(0, (a, b) => a + b),
                        child: Column(children: [
                          Table(columnWidths: columns, children: [
                            TableRow(children: [
                              heading(''),
                              for (var c = 0; c < _widths.length; c++)
                                heading(_columnLabel(c)),
                            ])
                          ]),
                          Expanded(
                              child: Scrollbar(
                                  controller: _verticalScroll,
                                  thumbVisibility: true,
                                  child: SingleChildScrollView(
                                      controller: _verticalScroll,
                                      child: Table(
                                          key: const ValueKey('pdf-table-grid'),
                                          columnWidths: columns,
                                          defaultVerticalAlignment:
                                              TableCellVerticalAlignment
                                                  .intrinsicHeight,
                                          border: _gridLines
                                              ? TableBorder.all(
                                                  color: Color(0xFF000000 |
                                                      _borderColor),
                                                  width: _borderWidth)
                                              : null,
                                          children: [
                                            for (var r = 0;
                                                r < _cells.length;
                                                r++)
                                              TableRow(children: [
                                                heading('${r + 1}'),
                                                for (var c = 0;
                                                    c < _widths.length;
                                                    c++)
                                                  cell(r, c),
                                              ]),
                                          ]))))
                        ])))));
      });

  Future<void> _copy() async {
    try {
      final text = _value.toTsv(
          firstRow: math.min(_row, _anchorRow),
          lastRow: math.max(_row, _anchorRow),
          firstColumn: math.min(_column, _anchorColumn),
          lastColumn: math.max(_column, _anchorColumn));
      final copy = widget.onCopyCells;
      if (copy != null) {
        await copy(text);
      } else {
        await Clipboard.setData(ClipboardData(text: text));
      }
    } on FormatException {
      if (mounted) {
        setState(() => _error = pdfL10n(context).tableClipboardError);
      }
    }
  }

  Future<void> _paste() async {
    _readDraftCells();
    final targetRow = math.min(_row, _anchorRow);
    final targetColumn = math.min(_column, _anchorColumn);
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted || clipboard?.text == null) return;
    try {
      final incoming = PdfTableData.fromTsv(clipboard!.text!);
      final emptyNewTable = widget.initial == null &&
          targetRow == 0 &&
          targetColumn == 0 &&
          _cells.every((row) => row.every((value) => value.isEmpty));
      final rows = emptyNewTable
          ? incoming.rowCount
          : math.max(_cells.length, targetRow + incoming.rowCount);
      final cols = emptyNewTable
          ? incoming.columnCount
          : math.max(_widths.length, targetColumn + incoming.columnCount);
      if (rows > PdfTableData.maxRows ||
          cols > PdfTableData.maxColumns ||
          rows * cols > PdfTableData.maxCells) {
        throw const FormatException('Table is too large');
      }
      final updated = List.generate(
          rows,
          (r) => List.generate(
              cols,
              (c) =>
                  r < _cells.length && c < _widths.length ? _cells[r][c] : ''));
      for (var r = 0; r < incoming.rowCount; r++) {
        for (var c = 0; c < incoming.columnCount; c++) {
          updated[targetRow + r][targetColumn + c] = incoming.cells[r][c];
        }
      }
      // Validate before mutating any draft, including the total byte budget.
      PdfTableData(updated);
      setState(() {
        _cells = updated;
        _widths =
            List.generate(cols, (c) => c < _widths.length ? _widths[c] : 100.0);
        _heights = List.generate(
            rows, (r) => r < _heights.length ? _heights[r] : 28.0);
        _anchorRow = targetRow;
        _anchorColumn = targetColumn;
        _row = targetRow + incoming.rowCount - 1;
        _column = targetColumn + incoming.columnCount - 1;
        _error = null;
        _resetFields();
      });
    } on FormatException {
      setState(() => _error = pdfL10n(context).tableClipboardError);
    }
  }

  void _resize({int rows = 0, int columns = 0}) => setState(() {
        _readDraftCells();
        if (rows > 0) {
          _cells.insert(
              _row + 1, List.filled(_widths.length, '', growable: true));
          _heights.insert(_row + 1, 28);
        }
        if (rows < 0) {
          _cells.removeAt(_row);
          _heights.removeAt(_row);
        }
        if (columns > 0) {
          for (final r in _cells) {
            r.insert(_column + 1, '');
          }
          _widths.insert(_column + 1, 100);
        }
        if (columns < 0) {
          for (final r in _cells) {
            r.removeAt(_column);
          }
          _widths.removeAt(_column);
        }
        _row = _row.clamp(0, _cells.length - 1);
        _column = _column.clamp(0, _widths.length - 1);
        _anchorRow = _row;
        _anchorColumn = _column;
        _resetFields();
      });
  void _confirm() {
    try {
      Navigator.of(context).pop(_value);
    } on FormatException {
      setState(() => _error = pdfL10n(context).tableClipboardError);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = pdfL10n(context);
    Widget number(String label, double value, void Function(double) update) =>
        SizedBox(
            width: 116,
            child: TextFormField(
                contextMenuBuilder: pdfTextContextMenu,
                key: ValueKey('$label-$_row-$_column'),
                initialValue: value.toStringAsFixed(0),
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: label),
                onChanged: (text) {
                  final n = double.tryParse(text);
                  if (n != null && n.isFinite && n >= 4 && n <= 2000) {
                    setState(() => update(n));
                  }
                }));
    return AlertDialog(
        key: const ValueKey('pdf-table-editor'),
        title: Text(widget.initial == null ? l10n.table : l10n.tableEdit),
        content: SizedBox(
            width: 740,
            height: 480,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    IconButton(
                        key: const ValueKey('pdf-table-style'),
                        tooltip: l10n.tableStyle,
                        isSelected: _styling,
                        icon: const Icon(Icons.tune),
                        onPressed: () => setState(() => _styling = !_styling)),
                    Text('${l10n.tableRows}: ${_cells.length}'),
                    IconButton(
                        key: const ValueKey('pdf-table-add-row'),
                        tooltip: '${l10n.tableRows} +',
                        icon: const Icon(Icons.add),
                        onPressed: _cells.length < PdfTableData.maxRows &&
                                (_cells.length + 1) * _widths.length <=
                                    PdfTableData.maxCells
                            ? () => _resize(rows: 1)
                            : null),
                    IconButton(
                        tooltip: '${l10n.tableRows} −',
                        icon: const Icon(Icons.remove),
                        onPressed:
                            _cells.length > 1 ? () => _resize(rows: -1) : null),
                    Text('${l10n.tableColumns}: ${_widths.length}'),
                    IconButton(
                        key: const ValueKey('pdf-table-add-column'),
                        tooltip: '${l10n.tableColumns} +',
                        icon: const Icon(Icons.add),
                        onPressed: _widths.length < PdfTableData.maxColumns &&
                                _cells.length * (_widths.length + 1) <=
                                    PdfTableData.maxCells
                            ? () => _resize(columns: 1)
                            : null),
                    IconButton(
                        tooltip: '${l10n.tableColumns} −',
                        icon: const Icon(Icons.remove),
                        onPressed: _widths.length > 1
                            ? () => _resize(columns: -1)
                            : null),
                    TextButton.icon(
                        key: const ValueKey('pdf-table-select-all'),
                        onPressed: () => setState(() {
                              _anchorRow = 0;
                              _anchorColumn = 0;
                              _row = _cells.length - 1;
                              _column = _widths.length - 1;
                            }),
                        icon: const Icon(Icons.select_all),
                        label: Text(l10n.viewerSelectAll)),
                    TextButton.icon(
                        key: const ValueKey('pdf-table-copy'),
                        onPressed: _copy,
                        icon: const Icon(Icons.copy),
                        label: Text(l10n.copy)),
                    TextButton.icon(
                        key: const ValueKey('pdf-table-paste'),
                        onPressed: _paste,
                        icon: const Icon(Icons.paste),
                        label: Text(l10n.paste)),
                  ]),
              Text(l10n.tableSelectionHint,
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              Expanded(child: _styling ? _styles() : _grid()),
              const SizedBox(height: 8),
              SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Wrap(
                      spacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilterChip(
                            label: Text(l10n.tableHeaderRow),
                            selected: _header,
                            onSelected: (value) =>
                                setState(() => _header = value)),
                        number(l10n.tableColumnWidth, _widths[_column],
                            (v) => _widths[_column] = v),
                        number(l10n.tableRowHeight, _heights[_row],
                            (v) => _heights[_row] = v),
                        number(l10n.tbFontSize, _fontSize,
                            (v) => _fontSize = v.clamp(4, 144)),
                      ])),
              if (_error != null)
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
            ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.cancel)),
          FilledButton(
              key: const ValueKey('pdf-table-apply'),
              onPressed: _confirm,
              child: Text(l10n.apply))
        ]);
  }
}
