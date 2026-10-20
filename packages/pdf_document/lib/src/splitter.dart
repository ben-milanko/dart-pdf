import 'dart:typed_data';

import 'document.dart';
import 'editor.dart';

/// An inclusive, zero-based page range for one output PDF.
///
/// For example, `PdfPageRange(0, 2)` selects pages 1–3. Bounds are checked
/// against the source document when extracting; reversed ranges are rejected.
class PdfPageRange {
  const PdfPageRange(this.start, this.end);

  final int start;
  final int end;

  void _validate(int pageCount) {
    RangeError.checkValidIndex(start, null, 'start', pageCount);
    RangeError.checkValidIndex(end, null, 'end', pageCount);
    if (end < start) {
      throw ArgumentError('end ($end) must not be before start ($start)');
    }
  }
}

/// Splits PDF bytes into standalone PDFs without file-system dependencies.
///
/// Each range produces one output, in the supplied order. Overlapping and
/// repeated ranges are allowed; they produce independent documents. The source
/// is opened once and all ranges are validated before any output is generated.
///
/// ```dart
/// final parts = PdfSplitter.split(bytes, const [
///   PdfPageRange(0, 2), // pages 1–3 in the first PDF
///   PdfPageRange(6, 6), // page 7 in the second PDF
///   PdfPageRange(9, 11), // pages 10–12 in the third PDF
/// ]);
/// final firstThree = PdfSplitter.splitRange(bytes, 0, 2);
/// final fromInput = PdfSplitter.splitExpression(bytes, '1-3, 7, 10-12');
/// ```
///
/// Extraction deep-copies page annotations and reachable resources, remaps
/// destinations between retained pages within each output, and retains the
/// document information dictionary. Outlines/bookmarks, the AcroForm field
/// list, and named destinations are omitted. Copied widgets are therefore not
/// registered in an AcroForm. Shared resources remain shared within an output
/// where possible; separate outputs own their copies. Encrypted sources require
/// their password and produce **unencrypted** outputs. The source is unchanged.
abstract final class PdfSplitter {
  /// Returns one PDF per zero-based, inclusive range in [ranges].
  ///
  /// An empty list or reversed range throws [ArgumentError]; a page outside
  /// the document throws [RangeError]. Opening errors propagate to the caller.
  static List<Uint8List> split(
    Uint8List bytes,
    List<PdfPageRange> ranges, {
    String password = '',
  }) =>
      PdfDocument.open(bytes, password: password).extractPageRanges(ranges);

  /// Returns a single PDF of pages [start] through [end], zero-based/inclusive.
  static Uint8List splitRange(
    Uint8List bytes,
    int start,
    int end, {
    String password = '',
  }) =>
      split(bytes, [PdfPageRange(start, end)], password: password).single;

  /// Opens [bytes] once and produces one PDF per comma-separated range.
  ///
  /// Unlike [split], [expression] uses one-based page numbers, as described
  /// by [parseRanges]. Invalid input throws [FormatException].
  static List<Uint8List> splitExpression(
    Uint8List bytes,
    String expression, {
    String password = '',
  }) {
    final document = PdfDocument.open(bytes, password: password);
    return document.extractPageRanges(
      parseRanges(expression, pageCount: document.pageCount),
    );
  }

  /// Parses one-based, inclusive ranges such as `1-3, 7, 10-12`.
  ///
  /// Each comma starts another output. Whitespace around numbers and separators
  /// is ignored. Order, overlaps, and repeated ranges are preserved. Empty
  /// input/items, non-integers, reversed ranges, and pages outside 1..[pageCount]
  /// throw [FormatException]. The returned ranges use zero-based indices.
  static List<PdfPageRange> parseRanges(
    String expression, {
    required int pageCount,
  }) {
    RangeError.checkNotNegative(pageCount, 'pageCount');
    final result = <PdfPageRange>[];
    for (final item in expression.split(',')) {
      final match =
          RegExp(r'^\s*([0-9]+)\s*(?:-\s*([0-9]+)\s*)?$').firstMatch(item);
      final start = match == null ? null : int.tryParse(match[1]!);
      final end = match == null ? null : int.tryParse(match[2] ?? match[1]!);
      if (start == null ||
          end == null ||
          start < 1 ||
          end < start ||
          end > pageCount) {
        throw FormatException(
          'Use pages 1–$pageCount, separated by commas, with ascending ranges '
          '(for example 1-3, 7, 10-12).',
          expression,
        );
      }
      result.add(PdfPageRange(start - 1, end - 1));
    }
    return result;
  }
}

/// Batch extraction from an already-open document.
extension PdfBatchPageExtraction on PdfDocument {
  /// Returns one standalone PDF per range. See [PdfSplitter] for semantics.
  ///
  /// All ranges are checked before extraction; the document is unchanged.
  List<Uint8List> extractPageRanges(List<PdfPageRange> ranges) {
    if (ranges.isEmpty) {
      throw ArgumentError.value(ranges, 'ranges', 'select at least one range');
    }
    for (final range in ranges) {
      range._validate(pageCount);
    }
    return [
      for (final range in ranges) extractPageRange(range.start, range.end),
    ];
  }
}
