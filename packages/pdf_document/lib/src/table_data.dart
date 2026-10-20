import 'dart:convert';

/// Editable cell values and simple layout, stored alongside a standard vector
/// PDF appearance. Excel clipboard exchange uses quoted tab-separated text;
/// formulas are literal strings here, not executable spreadsheet programs.
class PdfTableData {
  PdfTableData(
    List<List<String>> cells, {
    List<double>? columnWidths,
    List<double>? rowHeights,
    this.fontSize = 11,
    this.headerRow = true,
    this.textColor = 0x000000,
    this.borderColor = 0x808080,
    this.headerColor = 0xE8EEF8,
  })  : cells =
            List.unmodifiable(cells.map((r) => List<String>.unmodifiable(r))),
        columnWidths = List.unmodifiable(columnWidths ??
            List.filled(cells.isEmpty ? 0 : cells.first.length, 100.0)),
        rowHeights =
            List.unmodifiable(rowHeights ?? List.filled(cells.length, 28.0)) {
    if (cells.isEmpty ||
        cells.first.isEmpty ||
        cells.length > maxRows ||
        cells.first.length > maxColumns ||
        cells.length * cells.first.length > maxCells ||
        cells.any((r) => r.length != cells.first.length) ||
        this.columnWidths.length != cells.first.length ||
        this.rowHeights.length != cells.length ||
        [...this.columnWidths, ...this.rowHeights, fontSize]
            .any((n) => !n.isFinite || n <= 0) ||
        fontSize > 144 ||
        !width.isFinite ||
        !height.isFinite ||
        [textColor, borderColor, headerColor]
            .any((c) => c < 0 || c > 0xFFFFFF)) {
      throw const FormatException('Invalid table size or layout');
    }
    if (utf8.encode(jsonEncode(toJson())).length > maxMetadataBytes) {
      throw const FormatException('Table is too large');
    }
  }

  static const maxRows = 500;
  static const maxColumns = 100;
  static const maxCells = 20000;
  static const maxMetadataBytes = 2 * 1024 * 1024;
  final List<List<String>> cells;
  final List<double> columnWidths;
  final List<double> rowHeights;
  final double fontSize;
  final bool headerRow;
  final int textColor;
  final int borderColor;
  final int headerColor;
  int get rowCount => cells.length;
  int get columnCount => cells.first.length;
  double get width => columnWidths.fold(0, (a, b) => a + b);
  double get height => rowHeights.fold(0, (a, b) => a + b);

  Map<String, Object> toJson() => {
        'version': 1,
        'cells': cells,
        'columns': columnWidths,
        'rows': rowHeights,
        'fontSize': fontSize,
        'headerRow': headerRow,
        'textColor': textColor,
        'borderColor': borderColor,
        'headerColor': headerColor,
      };

  static PdfTableData? decode(String encoded) {
    if (encoded.length > maxMetadataBytes) return null;
    try {
      final m = jsonDecode(encoded) as Map<String, dynamic>;
      if (m['version'] != 1) return null;
      return PdfTableData([
        for (final row in m['cells'] as List) (row as List).cast<String>(),
      ],
          columnWidths: [
            for (final n in m['columns'] as List) (n as num).toDouble()
          ],
          rowHeights: [
            for (final n in m['rows'] as List) (n as num).toDouble()
          ],
          fontSize: (m['fontSize'] as num).toDouble(),
          headerRow: m['headerRow'] as bool,
          textColor: m['textColor'] as int,
          borderColor: m['borderColor'] as int,
          headerColor: m['headerColor'] as int);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    } on RangeError {
      return null;
    }
  }

  String toTsv(
      {int firstRow = 0, int firstColumn = 0, int? lastRow, int? lastColumn}) {
    String quote(String value) => RegExp('[\t\r\n"]').hasMatch(value)
        ? '"${value.replaceAll('"', '""')}"'
        : value;
    return [
      for (var r = firstRow; r <= (lastRow ?? rowCount - 1); r++)
        [
          for (var c = firstColumn; c <= (lastColumn ?? columnCount - 1); c++)
            quote(cells[r][c])
        ].join('\t'),
    ].join('\r\n');
  }

  /// Handles Excel's quoted multiline cells, doubled quotes, CRLF/LF rows,
  /// empty cells, trailing empty columns and ragged ranges. A final row
  /// terminator is not an extra blank row.
  factory PdfTableData.fromTsv(String text) {
    if (text.length > maxMetadataBytes) {
      throw const FormatException('Table is too large');
    }
    final rows = <List<String>>[];
    var row = <String>[];
    var field = StringBuffer();
    var quoted = false;
    var start = true;
    void endField() {
      row.add(field.toString());
      field = StringBuffer();
      start = true;
    }

    void endRow() {
      endField();
      rows.add(row);
      row = [];
      if (rows.length > maxRows) {
        throw const FormatException('Too many table rows');
      }
    }

    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (quoted) {
        if (ch == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            quoted = false;
          }
        } else {
          field.write(ch);
        }
      } else if (ch == '"' && start) {
        quoted = true;
        start = false;
      } else if (ch == '\t') {
        endField();
        if (row.length >= maxColumns) {
          throw const FormatException('Too many table columns');
        }
      } else if (ch == '\r' || ch == '\n') {
        if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        endRow();
      } else {
        field.write(ch);
        start = false;
      }
    }
    if (quoted) throw const FormatException('Unclosed quoted table cell');
    if (field.isNotEmpty ||
        row.isNotEmpty ||
        rows.isEmpty ||
        (!text.endsWith('\r') && !text.endsWith('\n'))) {
      endRow();
    }
    final columns = rows.fold<int>(1, (n, r) => r.length > n ? r.length : n);
    return PdfTableData([
      for (final r in rows) [...r, ...List.filled(columns - r.length, '')]
    ]);
  }
}
