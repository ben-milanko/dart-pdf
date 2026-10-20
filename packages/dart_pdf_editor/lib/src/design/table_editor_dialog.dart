import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf_document/pdf_document.dart';
import '../l10n/pdf_l10n.dart';
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
  final Map<(int, int), TextEditingController> _fields = {};
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
  }

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
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
        textColor: widget.initial?.textColor ?? 0,
        borderColor: widget.initial?.borderColor ?? 0x808080,
        headerColor: widget.initial?.headerColor ?? 0xE8EEF8);
  }

  void _resetFields() {
    // EditableText may still be attached until the next build. Reset values
    // in place instead of disposing its controller during a paste or resize.
    for (final e in _fields.entries) {
      final (r, c) = e.key;
      if (r < _cells.length && c < _widths.length) e.value.text = _cells[r][c];
    }
  }

  void _select(int r, int c) => setState(() {
        if (!HardwareKeyboard.instance.isShiftPressed) {
          _anchorRow = r;
          _anchorColumn = c;
        }
        _row = r;
        _column = c;
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
              Expanded(
                  child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                          width: 48 + _widths.length * 132,
                          child: ListView.builder(
                              itemCount: _cells.length,
                              itemBuilder: (context, r) => Row(children: [
                                    SizedBox(
                                        width: 48, child: Text('${r + 1}')),
                                    for (var c = 0; c < _widths.length; c++)
                                      Container(
                                          width: 132,
                                          padding: const EdgeInsets.all(2),
                                          color: r >= math.min(_row, _anchorRow) &&
                                                  r <=
                                                      math.max(
                                                          _row, _anchorRow) &&
                                                  c >=
                                                      math.min(_column,
                                                          _anchorColumn) &&
                                                  c <=
                                                      math.max(
                                                          _column, _anchorColumn)
                                              ? Theme.of(context)
                                                  .colorScheme
                                                  .secondaryContainer
                                              : Colors.transparent,
                                          child: Focus(
                                              onFocusChange: (focused) {
                                                if (focused) _select(r, c);
                                              },
                                              child: TextField(
                                                  contextMenuBuilder:
                                                      pdfTextContextMenu,
                                                  key: ValueKey(
                                                      'pdf-table-cell-$r-$c'),
                                                  controller: _fields.putIfAbsent(
                                                      (r, c),
                                                      () =>
                                                          TextEditingController(text: _cells[r][c])),
                                                  onTap: () => _select(r, c),
                                                  onChanged: (text) => _cells[r][c] = text,
                                                  minLines: 1,
                                                  maxLines: 3,
                                                  decoration: InputDecoration(isDense: true, border: const OutlineInputBorder(), labelText: '${r + 1}:${c + 1}')))),
                                  ]))))),
              const SizedBox(height: 8),
              Wrap(
                  spacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilterChip(
                        label: Text(l10n.tableHeaderRow),
                        selected: _header,
                        onSelected: (value) => setState(() => _header = value)),
                    number(l10n.tableColumnWidth, _widths[_column],
                        (v) => _widths[_column] = v),
                    number(l10n.tableRowHeight, _heights[_row],
                        (v) => _heights[_row] = v),
                    number(l10n.tbFontSize, _fontSize,
                        (v) => _fontSize = v.clamp(4, 144)),
                  ]),
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
