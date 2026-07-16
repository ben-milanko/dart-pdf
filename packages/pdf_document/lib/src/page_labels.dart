import 'package:pdf_cos/pdf_cos.dart';

import 'document.dart';

/// Numbering style of a page-label range (§12.4.2).
enum PdfPageLabelStyle {
  /// Decimal arabic numerals (1, 2, 3, ...), `/S /D`.
  decimal,

  /// Uppercase roman numerals (I, II, III, ...), `/S /R`.
  romanUpper,

  /// Lowercase roman numerals (i, ii, iii, ...), `/S /r`.
  romanLower,

  /// Uppercase letters (A, B, ..., Z, AA, ...), `/S /A`.
  alphaUpper,

  /// Lowercase letters (a, b, ..., z, aa, ...), `/S /a`.
  alphaLower,

  /// No numeric portion - the prefix alone labels every page in the range.
  none;

  /// The `/S` name, or null for [none].
  String? get styleName => switch (this) {
        PdfPageLabelStyle.decimal => 'D',
        PdfPageLabelStyle.romanUpper => 'R',
        PdfPageLabelStyle.romanLower => 'r',
        PdfPageLabelStyle.alphaUpper => 'A',
        PdfPageLabelStyle.alphaLower => 'a',
        PdfPageLabelStyle.none => null,
      };

  static PdfPageLabelStyle fromName(String? name) => switch (name) {
        'D' => PdfPageLabelStyle.decimal,
        'R' => PdfPageLabelStyle.romanUpper,
        'r' => PdfPageLabelStyle.romanLower,
        'A' => PdfPageLabelStyle.alphaUpper,
        'a' => PdfPageLabelStyle.alphaLower,
        _ => PdfPageLabelStyle.none,
      };
}

/// One range of the page-label number tree: from [startPage] (inclusive,
/// zero-based) until the next range begins.
class PdfPageLabelRange {
  const PdfPageLabelRange({
    required this.startPage,
    this.style = PdfPageLabelStyle.decimal,
    this.prefix = '',
    this.start = 1,
  });

  /// Zero-based index of the first page this range labels.
  final int startPage;

  /// Numbering style.
  final PdfPageLabelStyle style;

  /// Label prefix (`/P`), prepended to every number in the range.
  final String prefix;

  /// The numeric value of the first page in the range (`/St`, default 1).
  final int start;

  /// Formats the label for the [offset]-th page within this range
  /// (0 = [startPage]).
  String labelAt(int offset) {
    final n = start + offset;
    return '$prefix${_format(style, n)}';
  }

  static String _format(PdfPageLabelStyle style, int n) {
    switch (style) {
      case PdfPageLabelStyle.none:
        return '';
      case PdfPageLabelStyle.decimal:
        return '$n';
      case PdfPageLabelStyle.romanUpper:
        return _roman(n);
      case PdfPageLabelStyle.romanLower:
        return _roman(n).toLowerCase();
      case PdfPageLabelStyle.alphaUpper:
        return _alpha(n, 0x41);
      case PdfPageLabelStyle.alphaLower:
        return _alpha(n, 0x61);
    }
  }

  /// A to Z, then AA to ZZ, then AAA to ZZZ, ... (§12.4.2).
  static String _alpha(int n, int base) {
    if (n <= 0) return '';
    final index = (n - 1) % 26;
    final repeat = (n - 1) ~/ 26 + 1;
    return String.fromCharCode(base + index) * repeat;
  }

  static String _roman(int n) {
    if (n <= 0 || n >= 4000) return '$n';
    const values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1];
    const symbols = [
      'M', 'CM', 'D', 'CD', 'C', 'XC', 'L', 'XL', 'X', 'IX', 'V', 'IV', 'I',
    ];
    final out = StringBuffer();
    var value = n;
    for (var i = 0; i < values.length; i++) {
      while (value >= values[i]) {
        out.write(symbols[i]);
        value -= values[i];
      }
    }
    return out.toString();
  }
}

/// Reads the `/PageLabels` number tree and computes logical page labels.
///
/// Authoring is [PdfPageLabelEditing] on `PdfEditor`.
class PdfPageLabels {
  const PdfPageLabels(this.ranges);

  /// Ranges sorted by [PdfPageLabelRange.startPage] ascending.
  final List<PdfPageLabelRange> ranges;

  bool get isEmpty => ranges.isEmpty;

  /// The logical label for zero-based [pageIndex]. Falls back to the
  /// 1-based physical number when no range covers the page (including when
  /// the document has no labels).
  String labelFor(int pageIndex) {
    PdfPageLabelRange? match;
    for (final range in ranges) {
      if (range.startPage <= pageIndex) {
        match = range;
      } else {
        break;
      }
    }
    if (match == null) return '${pageIndex + 1}';
    return match.labelAt(pageIndex - match.startPage);
  }

  static PdfPageLabels of(PdfDocument document) {
    final cos = document.cos;
    final tree = cos.resolve(document.catalog['PageLabels']);
    if (tree is! CosDictionary) return const PdfPageLabels([]);
    final pairs = <(int, CosDictionary)>[];
    _walk(cos, tree, pairs, <CosDictionary>{});
    pairs.sort((a, b) => a.$1.compareTo(b.$1));
    final ranges = <PdfPageLabelRange>[];
    for (final (start, dict) in pairs) {
      final s = cos.resolve(dict['S']);
      final p = cos.resolve(dict['P']);
      final st = cos.resolve(dict['St']);
      ranges.add(PdfPageLabelRange(
        startPage: start,
        style: PdfPageLabelStyle.fromName(s is CosName ? s.value : null),
        prefix: p is CosString ? p.text : '',
        start: st is CosInteger && st.value > 0 ? st.value : 1,
      ));
    }
    return PdfPageLabels(ranges);
  }

  static void _walk(CosDocument cos, CosDictionary node,
      List<(int, CosDictionary)> out, Set<CosDictionary> visited) {
    if (!visited.add(node)) return;
    final nums = cos.resolve(node['Nums']);
    if (nums is CosArray) {
      for (var i = 0; i + 1 < nums.length; i += 2) {
        final key = cos.resolve(nums[i]);
        final value = cos.resolve(nums[i + 1]);
        if (key is CosInteger && value is CosDictionary && key.value >= 0) {
          out.add((key.value, value));
        }
      }
    }
    final kids = cos.resolve(node['Kids']);
    if (kids is CosArray) {
      for (final kid in kids.items) {
        final child = cos.resolve(kid);
        if (child is CosDictionary) _walk(cos, child, out, visited);
      }
    }
  }
}
