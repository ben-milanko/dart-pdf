/// Helpers for the display-only annotation subtype filter
/// (`PdfEditingPreferences.hiddenAnnotationSubtypes` →
/// `PdfViewer.hiddenAnnotationSubtypes` → `PdfPageRenderPlan`). Pure Dart so
/// the render workers can share them.
library;

import 'package:pdf_document/pdf_document.dart' show PdfPage;
import 'package:pdf_graphics/pdf_graphics.dart' show PdfInterpreter;

/// Whether [a] and [b] hide the same annotation subtypes.
bool sameHiddenAnnotationSubtypes(Set<String> a, Set<String> b) =>
    identical(a, b) || (a.length == b.length && a.containsAll(b));

/// An order-independent hash for a hidden-subtype set.
int hiddenAnnotationSubtypesHash(Set<String> subtypes) =>
    subtypes.isEmpty ? 0 : Object.hashAllUnordered(subtypes);

/// A stable string form of a hidden-subtype set, for string cache keys:
/// empty for none, otherwise the sorted names joined by `,`.
String hiddenAnnotationSubtypesKey(Set<String> subtypes) {
  if (subtypes.isEmpty) return '';
  return (subtypes.toList()..sort()).join(',');
}

/// What a recording draws of a page's annotations: none of them, or all but
/// the [hiddenSubtypes]. This is the render workers' internal form of a
/// request's `annotations` + `hiddenAnnotationSubtypes` pair; it has value
/// equality so it can key the workers' record caches, and [toWire]/[fromWire]
/// carry it across the isolate or Web Worker boundary as plain data.
final class PdfAnnotationLayerSpec {
  PdfAnnotationLayerSpec(this.draw, [Set<String> hiddenSubtypes = const {}])
      : hiddenSubtypes = draw ? hiddenSubtypes : const {};

  /// No annotations at all.
  static final none = PdfAnnotationLayerSpec(false);

  /// Every (displayable) annotation.
  static final all = PdfAnnotationLayerSpec(true);

  /// Whether annotations are drawn.
  final bool draw;

  /// The /Subtype names left out while [draw] is true.
  final Set<String> hiddenSubtypes;

  /// Draws [page]'s annotations through [interpreter] per this spec.
  void drawOn(PdfInterpreter interpreter, PdfPage page) {
    if (draw) interpreter.drawAnnotations(page, skipSubtypes: hiddenSubtypes);
  }

  /// Plain-data form: null for none, else the sorted hidden subtype names.
  List<String>? toWire() => draw ? (hiddenSubtypes.toList()..sort()) : null;

  /// Inverse of [toWire]. Also accepts a bare bool (the pre-filter wire form).
  static PdfAnnotationLayerSpec fromWire(Object? wire) {
    if (wire == null || wire == false) return none;
    if (wire == true) return all;
    final names = (wire as List).cast<String>();
    return names.isEmpty ? all : PdfAnnotationLayerSpec(true, names.toSet());
  }

  @override
  bool operator ==(Object other) =>
      other is PdfAnnotationLayerSpec &&
      draw == other.draw &&
      sameHiddenAnnotationSubtypes(hiddenSubtypes, other.hiddenSubtypes);

  @override
  int get hashCode =>
      Object.hash(draw, hiddenAnnotationSubtypesHash(hiddenSubtypes));

  @override
  String toString() => !draw
      ? 'annotations: none'
      : hiddenSubtypes.isEmpty
          ? 'annotations: all'
          : 'annotations: hiding ${hiddenAnnotationSubtypesKey(hiddenSubtypes)}';
}
