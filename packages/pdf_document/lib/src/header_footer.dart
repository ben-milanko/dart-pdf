part of 'editor.dart';

/// A repeating header or footer: up to three text slots (left, centre,
/// right) drawn in Helvetica. Each slot is a template that may contain the
/// dynamic tokens `{page}` (1-based page number), `{pages}` (page count),
/// `{label}` (the logical page label when the document carries
/// `/PageLabels`, else the page number), and `{date}` (the stamp date as
/// `YYYY-MM-DD`).
class PdfHeaderFooter {
  const PdfHeaderFooter({
    this.left,
    this.center,
    this.right,
    this.size = 9,
    this.color = 0x000000,
    this.bold = false,
    this.margin = 36,
  });

  /// Left-aligned slot template, or null to leave it empty.
  final String? left;

  /// Centred slot template.
  final String? center;

  /// Right-aligned slot template.
  final String? right;

  /// Font size in points.
  final double size;

  /// Text colour, `0xRRGGBB`.
  final int color;

  /// Whether to use Helvetica-Bold.
  final bool bold;

  /// Distance in points from the page edge: the left/right slots sit this
  /// far in from the crop-box sides, and the baseline this far from the
  /// top (header) or bottom (footer) edge.
  final double margin;

  bool get _isEmpty =>
      (left == null || left!.isEmpty) &&
      (center == null || center!.isEmpty) &&
      (right == null || right!.isEmpty);
}

/// Stamps repeating headers and footers across a page range, building on
/// [PdfContentEditing.stampPage].
extension PdfHeaderFooterEditing on PdfEditor {
  /// Draws [header] at the top and/or [footer] at the bottom of every page
  /// from [fromPage] to [toPage] inclusive (defaults: the whole document).
  /// [date] is the value for the `{date}` token (defaults to now).
  void stampHeaderFooter({
    PdfHeaderFooter? header,
    PdfHeaderFooter? footer,
    int fromPage = 0,
    int? toPage,
    DateTime? date,
  }) {
    if (header == null && footer == null) return;
    final last = (toPage ?? document.pageCount - 1)
        .clamp(0, document.pageCount - 1);
    final first = fromPage.clamp(0, document.pageCount - 1);
    final when = date ?? DateTime.now();
    final pageCount = document.pageCount;
    final labels = PdfPageLabels.of(document);

    for (var i = first; i <= last; i++) {
      final hasHeader = header != null && !header._isEmpty;
      final hasFooter = footer != null && !footer._isEmpty;
      if (!hasHeader && !hasFooter) continue;
      stampPage(i, (stamp) {
        final box = stamp.page.cropBox;
        if (hasHeader) {
          _drawSlots(stamp, header, box,
              y: box.top - header.margin - header.size * 0.8,
              pageIndex: i,
              pageCount: pageCount,
              labels: labels,
              date: when);
        }
        if (hasFooter) {
          _drawSlots(stamp, footer, box,
              y: box.bottom + footer.margin,
              pageIndex: i,
              pageCount: pageCount,
              labels: labels,
              date: when);
        }
      });
    }
  }

  void _drawSlots(
    PdfStamp stamp,
    PdfHeaderFooter hf,
    PdfRect box, {
    required double y,
    required int pageIndex,
    required int pageCount,
    required PdfPageLabels labels,
    required DateTime date,
  }) {
    void slot(String? template, _SlotAlign align) {
      if (template == null || template.isEmpty) return;
      final text = _expandHeaderTokens(
          template, pageIndex, pageCount, labels, date);
      if (text.isEmpty) return;
      final width = stamp.measureText(text, size: hf.size, bold: hf.bold);
      final double x;
      switch (align) {
        case _SlotAlign.left:
          x = box.left + hf.margin;
        case _SlotAlign.center:
          x = box.left + (box.width - width) / 2;
        case _SlotAlign.right:
          x = box.right - hf.margin - width;
      }
      stamp.text(text,
          x: x, y: y, size: hf.size, color: hf.color, bold: hf.bold);
    }

    slot(hf.left, _SlotAlign.left);
    slot(hf.center, _SlotAlign.center);
    slot(hf.right, _SlotAlign.right);
  }

  String _expandHeaderTokens(String template, int pageIndex, int pageCount,
      PdfPageLabels labels, DateTime date) {
    final label = labels.isEmpty ? '${pageIndex + 1}' : labels.labelFor(pageIndex);
    String two(int v) => v.toString().padLeft(2, '0');
    final dateText = '${date.year.toString().padLeft(4, '0')}-'
        '${two(date.month)}-${two(date.day)}';
    return template
        .replaceAll('{page}', '${pageIndex + 1}')
        .replaceAll('{pages}', '$pageCount')
        .replaceAll('{label}', label)
        .replaceAll('{date}', dateText);
  }
}

enum _SlotAlign { left, center, right }
