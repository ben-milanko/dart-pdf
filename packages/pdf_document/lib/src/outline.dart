import 'package:pdf_cos/pdf_cos.dart';

import 'annotation.dart';
import 'document.dart';

/// An explicit destination to author (§12.3.2.2): a page plus a view fit.
///
/// Reading destinations is [PdfDestination]; this is the write-side value
/// that [PdfOutlineEditing] and friends turn into a `[page /Fit ...]` array.
/// The page is named by zero-based index and resolved to its object
/// reference when the array is built.
class PdfExplicitDestination {
  const PdfExplicitDestination._(this.pageIndex, this.fit, this.params);

  /// Fit the whole page in the window (`/Fit`).
  const PdfExplicitDestination.fit(int pageIndex)
      : this._(pageIndex, 'Fit', const []);

  /// Position the page so [top] is at the top of the window, fit to width
  /// (`/FitH`). A null [top] keeps the current vertical position.
  PdfExplicitDestination.fitH(int pageIndex, {double? top})
      : this._(pageIndex, 'FitH', [top]);

  /// Position [left] at the left of the window, fit to height (`/FitV`).
  PdfExplicitDestination.fitV(int pageIndex, {double? left})
      : this._(pageIndex, 'FitV', [left]);

  /// Position ([left], [top]) at the upper-left corner with magnification
  /// [zoom] (`/XYZ`). Any null operand keeps that current value; a zero or
  /// null [zoom] keeps the current zoom.
  PdfExplicitDestination.xyz(int pageIndex,
      {double? left, double? top, double? zoom})
      : this._(pageIndex, 'XYZ', [left, top, zoom]);

  /// Fit the rectangle ([left], [bottom], [right], [top]) in the window
  /// (`/FitR`).
  PdfExplicitDestination.fitR(int pageIndex,
      {required double left,
      required double bottom,
      required double right,
      required double top})
      : this._(pageIndex, 'FitR', [left, bottom, right, top]);

  /// Zero-based page index the destination points at.
  final int pageIndex;

  /// The fit name without the slash (Fit, FitH, FitV, FitR, XYZ, ...).
  final String fit;

  /// Numeric operands after the fit name; null entries serialize as `null`
  /// ("keep the current value").
  final List<double?> params;

  /// Builds the explicit destination array given the page's reference.
  CosArray toCosArray(CosReference pageRef) => CosArray([
        pageRef,
        CosName(fit),
        for (final p in params)
          p == null ? CosNull.instance : CosReal(p),
      ]);
}

/// A read-only view of the document outline (bookmarks) tree.
///
/// Authoring is [PdfOutlineEditing] on [PdfEditor]; this resolves the
/// `/Outlines` tree into nested [PdfOutlineItem]s for display and for
/// round-trip assertions.
class PdfOutline {
  const PdfOutline(this.items);

  /// Top-level outline items, in document order.
  final List<PdfOutlineItem> items;

  bool get isEmpty => items.isEmpty;

  /// The root `/Count` (number of visible items at all levels), or 0 when
  /// there is no outline.
  static int rootCount(PdfDocument document) {
    final root = document.cos.resolve(document.catalog['Outlines']);
    if (root is! CosDictionary) return 0;
    final c = document.cos.resolve(root['Count']);
    return c is CosInteger ? c.value : 0;
  }

  /// Reads the document's outline tree. Returns an empty outline when the
  /// catalog has no `/Outlines`.
  static PdfOutline of(PdfDocument document) {
    final cos = document.cos;
    final root = cos.resolve(document.catalog['Outlines']);
    if (root is! CosDictionary) return const PdfOutline([]);
    return PdfOutline(_childrenOf(document, root, <CosDictionary>{}));
  }

  static List<PdfOutlineItem> _childrenOf(
      PdfDocument document, CosDictionary node, Set<CosDictionary> seen) {
    final cos = document.cos;
    final out = <PdfOutlineItem>[];
    var cur = cos.resolve(node['First']);
    while (cur is CosDictionary && seen.add(cur)) {
      out.add(PdfOutlineItem._(
        title: _text(cos, cur['Title']),
        destination: _destinationOf(document, cur),
        open: _isOpen(cos, cur),
        bold: _flag(cos, cur, 2),
        italic: _flag(cos, cur, 1),
        color: _color(cos, cur),
        children: _childrenOf(document, cur, seen),
      ));
      cur = cos.resolve(cur['Next']);
    }
    return out;
  }

  static PdfDestination? _destinationOf(
      PdfDocument document, CosDictionary item) {
    if (item.containsKey('Dest')) {
      return PdfDestination.parse(document, item['Dest']);
    }
    final action = document.cos.resolve(item['A']);
    if (action is CosDictionary) {
      final s = document.cos.resolve(action['S']);
      if (s is CosName && s.value == 'GoTo') {
        return PdfDestination.parse(document, action['D']);
      }
    }
    return null;
  }

  static String _text(CosDocument cos, CosObject? value) {
    final v = cos.resolve(value);
    return v is CosString ? v.text : '';
  }

  static bool _isOpen(CosDocument cos, CosDictionary item) {
    final c = cos.resolve(item['Count']);
    // closed items carry a negative /Count; childless ones carry none and
    // are conventionally treated as open.
    return c is! CosInteger || c.value >= 0;
  }

  static bool _flag(CosDocument cos, CosDictionary item, int bit) {
    final f = cos.resolve(item['F']);
    return f is CosInteger && (f.value & bit) != 0;
  }

  static List<double>? _color(CosDocument cos, CosDictionary item) {
    final c = cos.resolve(item['C']);
    if (c is! CosArray || c.length < 3) return null;
    final out = <double>[];
    for (var i = 0; i < 3; i++) {
      final n = cos.resolve(c[i]);
      out.add(n is CosInteger
          ? n.value.toDouble()
          : n is CosReal
              ? n.value
              : 0);
    }
    return out;
  }
}

/// A single outline (bookmark) entry.
class PdfOutlineItem {
  const PdfOutlineItem._({
    required this.title,
    required this.destination,
    required this.open,
    required this.bold,
    required this.italic,
    required this.color,
    required this.children,
  });

  /// The displayed title.
  final String title;

  /// Where activating the item navigates, or null when it has no
  /// destination or action this reader understands.
  final PdfDestination? destination;

  /// Whether the item is expanded (its children are shown).
  final bool open;

  final bool bold;
  final bool italic;

  /// The item's text color as `[r, g, b]` (0–1), or null for the default.
  final List<double>? color;

  /// Nested child items, in document order.
  final List<PdfOutlineItem> children;
}
