import 'package:pdf_cos/pdf_cos.dart';

import 'annotation.dart';
import 'document.dart';
import 'form.dart';
import 'page.dart';
import 'rect.dart';
import 'struct_tree.dart';

/// The order a page asks keyboard focus to visit its annotations in - the
/// page's /Tabs entry (§12.5, Table 30).
enum PdfTabOrder {
  /// `/R`: row order - top to bottom, left to right within a row.
  row,

  /// `/C`: column order - left to right, top to bottom within a column.
  column,

  /// `/S`: structure order - the order the logical structure tree tags the
  /// widgets in (/OBJR entries, §14.7.4.3).
  structure,

  /// No /Tabs (or `/A`/`/W` from PDF 2.0, or a value we don't know): the
  /// order the widgets appear in the page's /Annots array.
  annotations;

  /// The order a /Tabs name selects; anything unrecognised is
  /// [annotations].
  static PdfTabOrder fromName(String? name) => switch (name) {
        'R' => row,
        'C' => column,
        'S' => structure,
        _ => annotations,
      };
}

/// Reads a page's /Tabs entry.
extension PdfPageTabOrder on PdfPage {
  /// The page's /Tabs order; [PdfTabOrder.annotations] when it has none.
  PdfTabOrder get tabOrder {
    final tabs = document.cos.resolve(dict['Tabs']);
    return PdfTabOrder.fromName(tabs is CosName ? tabs.value : null);
  }
}

/// One stop in a form's keyboard (Tab) traversal: a single widget of a
/// fillable field.
class PdfFormTabStop {
  const PdfFormTabStop({
    required this.pageIndex,
    required this.field,
    required this.widgetIndex,
    required this.widget,
  });

  final int pageIndex;

  /// The field the widget belongs to. Fields die with every revision, so
  /// hold on to [fieldName] rather than this across edits.
  final PdfFormField field;

  /// The widget's index within [field]'s widgets (a radio group has one
  /// stop per button).
  final int widgetIndex;

  /// The widget annotation itself.
  final PdfAnnotation widget;

  /// The field's fully qualified name - the handle that survives edits.
  String get fieldName => field.name;

  /// The widget's rectangle in page space.
  PdfRect get rect => widget.rect;

  @override
  String toString() => 'PdfFormTabStop(p$pageIndex $fieldName#$widgetIndex)';
}

/// The keyboard traversal order of a document's form: every fillable
/// widget, page by page, each page ordered by its /Tabs entry.
///
/// Stops are what a Tab key should land on: widgets that are visible
/// (neither /F hidden nor no-view) of fields a user can fill by keyboard -
/// text, check box, radio and choice fields that aren't read-only. Push
/// buttons and signature fields are skipped ([takesTabStop]).
class PdfFormTabOrder {
  PdfFormTabOrder(this.stops);

  /// Builds the order for [document]. Pass the already-resolved [form]
  /// when you have one, to avoid re-reading the /AcroForm tree.
  factory PdfFormTabOrder.of(PdfDocument document, {PdfAcroForm? form}) {
    form ??= PdfAcroForm.of(document);
    if (form == null) return PdfFormTabOrder(const []);
    // widget dictionary -> (field, widget index), by identity: the same
    // matching the form layer uses to pair page annotations with fields
    final owners = Map<CosDictionary, (PdfFormField, int)>.identity();
    for (final field in form.fields) {
      if (!takesTabStop(field)) continue;
      final widgets = field.widgets;
      for (var w = 0; w < widgets.length; w++) {
        owners[widgets[w]] = (field, w);
      }
    }
    if (owners.isEmpty) return PdfFormTabOrder(const []);
    Map<CosDictionary, int>? structureRanks;
    final stops = <PdfFormTabStop>[];
    for (var p = 0; p < document.pageCount; p++) {
      final page = document.page(p);
      final pageStops = <PdfFormTabStop>[];
      for (final annotation in page.annotations) {
        if (annotation.subtype != 'Widget' ||
            annotation.isHidden ||
            annotation.isNoView ||
            annotation.isReadOnly) {
          continue;
        }
        final owner = owners[annotation.dict];
        if (owner == null) continue;
        pageStops.add(PdfFormTabStop(
          pageIndex: p,
          field: owner.$1,
          widgetIndex: owner.$2,
          widget: annotation,
        ));
      }
      if (pageStops.isEmpty) continue;
      final order = page.tabOrder;
      if (order == PdfTabOrder.structure) {
        structureRanks ??= _structureRanks(document);
      }
      final ranks = structureRanks;
      stops.addAll(sortPage(
        pageStops,
        order,
        rectOf: (s) => s.rect,
        structureRank: ranks == null ? null : (s) => ranks[s.widget.dict],
      ));
    }
    return PdfFormTabOrder(stops);
  }

  /// Every stop, in traversal order.
  final List<PdfFormTabStop> stops;

  /// Whether Tab should stop at [field] at all: text, check box, radio and
  /// choice fields that aren't read-only.
  static bool takesTabStop(PdfFormField field) {
    if (field.isReadOnly) return false;
    return switch (field.type) {
      PdfFieldType.text ||
      PdfFieldType.checkBox ||
      PdfFieldType.radioGroup ||
      PdfFieldType.comboBox ||
      PdfFieldType.listBox =>
        true,
      PdfFieldType.pushButton ||
      PdfFieldType.signature ||
      PdfFieldType.unknown =>
        false,
    };
  }

  /// The index of the stop for [fieldName]'s widget [widgetIndex] on
  /// [pageIndex], or -1.
  int indexOf(int pageIndex, String fieldName, int widgetIndex) {
    for (var i = 0; i < stops.length; i++) {
      final s = stops[i];
      if (s.pageIndex == pageIndex &&
          s.widgetIndex == widgetIndex &&
          s.fieldName == fieldName) {
        return i;
      }
    }
    return -1;
  }

  /// The stop Tab (or Shift+Tab when [backward]) moves to from the given
  /// widget, wrapping around at either end of the document. When the
  /// starting widget isn't a stop (it was just made read-only, say, or no
  /// field is focused - [fieldName] null), the move starts from
  /// [pageIndex]: forward lands on that page's first stop or the next
  /// page's, backward on the last stop at or before it. Null when the form
  /// has no stops.
  PdfFormTabStop? step({
    required int pageIndex,
    String? fieldName,
    int widgetIndex = 0,
    bool backward = false,
  }) {
    if (stops.isEmpty) return null;
    final n = stops.length;
    final at =
        fieldName == null ? -1 : indexOf(pageIndex, fieldName, widgetIndex);
    if (at >= 0) return stops[((backward ? at - 1 : at + 1) % n + n) % n];
    if (backward) {
      for (var i = n - 1; i >= 0; i--) {
        if (stops[i].pageIndex <= pageIndex) return stops[i];
      }
      return stops.last;
    }
    for (final s in stops) {
      if (s.pageIndex >= pageIndex) return s;
    }
    return stops.first;
  }

  /// Orders one page's [items] (given in /Annots order) for [order].
  ///
  /// Row order groups items into rows top-down - an item joins the current
  /// row when its vertical centre falls within the row's first item's
  /// height - then reads each row left to right; column order is the same
  /// with the axes swapped. Structure order sorts by [structureRank] (an
  /// item without a rank keeps its /Annots position after the ranked
  /// ones); without a ranking it falls back to /Annots order. Sorting is
  /// stable, and page-space: /Rotate is not taken into account.
  static List<T> sortPage<T>(
    List<T> items,
    PdfTabOrder order, {
    required PdfRect Function(T) rectOf,
    int? Function(T)? structureRank,
  }) {
    if (items.length < 2) return List.of(items);
    final indexed = [for (var i = 0; i < items.length; i++) (i, items[i])];
    switch (order) {
      case PdfTabOrder.annotations:
        return List.of(items);
      case PdfTabOrder.structure:
        if (structureRank == null) return List.of(items);
        final ranked = [for (final e in indexed) (e, structureRank(e.$2))];
        ranked.sort((a, b) {
          final ra = a.$2, rb = b.$2;
          if (ra != null && rb != null && ra != rb) return ra.compareTo(rb);
          if ((ra == null) != (rb == null)) return ra == null ? 1 : -1;
          return a.$1.$1.compareTo(b.$1.$1);
        });
        return [for (final e in ranked) e.$1.$2];
      case PdfTabOrder.row:
        return _bands(
          indexed,
          rectOf,
          // across rows: higher top first (PDF y grows upward)
          major: (r) => -r.top,
          lo: (r) => r.bottom,
          hi: (r) => r.top,
          minor: (r) => r.left,
        );
      case PdfTabOrder.column:
        return _bands(
          indexed,
          rectOf,
          major: (r) => r.left,
          lo: (r) => r.left,
          hi: (r) => r.right,
          minor: (r) => -r.top,
        );
    }
  }

  /// Groups [items] into bands along one axis and orders each band along
  /// the other: sorted by [major], a band opens at an item and takes every
  /// following item whose centre on that axis ([lo]..[hi]) falls inside
  /// the opening item's span; each band then sorts by [minor].
  static List<T> _bands<T>(
    List<(int, T)> items,
    PdfRect Function(T) rectOf, {
    required double Function(PdfRect) major,
    required double Function(PdfRect) lo,
    required double Function(PdfRect) hi,
    required double Function(PdfRect) minor,
  }) {
    int byThenIndex(double a, double b, int ia, int ib) {
      final c = a.compareTo(b);
      return c != 0 ? c : ia.compareTo(ib);
    }

    final sorted = List.of(items)
      ..sort((a, b) =>
          byThenIndex(major(rectOf(a.$2)), major(rectOf(b.$2)), a.$1, b.$1));
    final out = <T>[];
    var i = 0;
    while (i < sorted.length) {
      final anchor = rectOf(sorted[i].$2);
      final low = lo(anchor), high = hi(anchor);
      final band = [sorted[i]];
      var j = i + 1;
      while (j < sorted.length) {
        final r = rectOf(sorted[j].$2);
        final centre = (lo(r) + hi(r)) / 2;
        if (centre < low || centre > high) break;
        band.add(sorted[j]);
        j++;
      }
      band.sort((a, b) =>
          byThenIndex(minor(rectOf(a.$2)), minor(rectOf(b.$2)), a.$1, b.$1));
      out.addAll([for (final e in band) e.$2]);
      i = j;
    }
    return out;
  }

  /// Each widget dictionary's position in the structure tree's reading
  /// order (the /OBJR entries, depth-first), keyed by identity.
  static Map<CosDictionary, int> _structureRanks(PdfDocument document) {
    final ranks = Map<CosDictionary, int>.identity();
    final tree = PdfStructTree.of(document);
    if (tree == null) return ranks;
    for (final element in tree.elementsInReadingOrder()) {
      for (final ref in element.objectReferences) {
        final object = ref.object;
        if (object is CosDictionary) {
          ranks.putIfAbsent(object, () => ranks.length);
        }
      }
    }
    return ranks;
  }
}
