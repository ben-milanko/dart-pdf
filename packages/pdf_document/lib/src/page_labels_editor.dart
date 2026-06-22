part of 'editor.dart';

/// Authoring of the `/PageLabels` number tree (§12.4.2): a flat, key-sorted
/// `/Nums` array mapping the first page of each range to its label
/// dictionary.
extension PdfPageLabelEditing on PdfEditor {
  /// Sets (or replaces) the label range that begins at zero-based
  /// [fromPageIndex]. [style] is the numbering style, [prefix] is prepended
  /// to every label, and [start] is the first value in the range.
  void setPageLabel(
    int fromPageIndex, {
    PdfPageLabelStyle style = PdfPageLabelStyle.decimal,
    String prefix = '',
    int start = 1,
  }) {
    if (fromPageIndex < 0) {
      throw ArgumentError.value(fromPageIndex, 'fromPageIndex', 'is negative');
    }
    final ranges = PdfPageLabels.of(document).ranges.toList()
      ..removeWhere((r) => r.startPage == fromPageIndex)
      ..add(PdfPageLabelRange(
          startPage: fromPageIndex,
          style: style,
          prefix: prefix,
          start: start));
    setPageLabels(ranges);
  }

  /// Removes the label range that begins at [fromPageIndex]. Returns whether
  /// one was removed.
  bool removePageLabelRange(int fromPageIndex) {
    final ranges = PdfPageLabels.of(document).ranges.toList();
    final before = ranges.length;
    ranges.removeWhere((r) => r.startPage == fromPageIndex);
    if (ranges.length == before) return false;
    setPageLabels(ranges);
    return true;
  }

  /// Removes the whole `/PageLabels` tree.
  void clearPageLabels() {
    final cos = document.cos;
    if (cos.resolve(document.catalog['PageLabels']) is! CosDictionary) return;
    document.catalog.entries.remove('PageLabels');
    _updater.markChanged(document.catalog);
  }

  /// Replaces the entire page-label tree with [ranges]. A range starting at
  /// page 0 is required by the spec for a well-formed tree; this stays
  /// lenient and writes whatever it is given (sorted by start page). An
  /// empty list clears the tree.
  void setPageLabels(List<PdfPageLabelRange> ranges) {
    if (ranges.isEmpty) {
      clearPageLabels();
      return;
    }
    final sorted = ranges.toList()
      ..sort((a, b) => a.startPage.compareTo(b.startPage));
    final nums = CosArray();
    for (final range in sorted) {
      final dict = CosDictionary();
      final styleName = range.style.styleName;
      if (styleName != null) dict['S'] = CosName(styleName);
      if (range.prefix.isNotEmpty) {
        dict['P'] = CosString.fromText(range.prefix);
      }
      if (range.start != 1) dict['St'] = CosInteger(range.start);
      nums.items
        ..add(CosInteger(range.startPage))
        ..add(dict);
    }
    final tree = CosDictionary({'Nums': nums});

    final cos = document.cos;
    final raw = document.catalog['PageLabels'];
    if (raw is CosReference) {
      _updater.replaceObject(raw.objectNumber, tree);
      cos.adoptObject(raw, tree);
    } else {
      document.catalog['PageLabels'] = _updater.addObject(tree);
      _updater.markChanged(document.catalog);
    }
  }
}
