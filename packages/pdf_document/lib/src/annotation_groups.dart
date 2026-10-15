import 'dart:math' as math;

import 'package:pdf_cos/pdf_cos.dart';

import 'annotation.dart';
import 'page.dart';
import 'matrix_geometry.dart';

/// Private group-frame orientation in page space, in radians. Stored on each
/// member so deleting the leader or copying a group retains its orientation.
const kPdfAnnotationGroupRotationKey = 'DartPdfGroupRotation';

/// Whether an annotation can belong to a page markup group. Comment replies
/// and review states keep their own /IRT relationships.
bool pdfCanGroupAnnotation(PdfAnnotation annotation) =>
    annotation.behavior.selectable &&
    !annotation.isReply &&
    !annotation.isStateAnnotation;

/// Page-local markup groups recorded with /RT /Group and an /IRT reference.
///
/// Resolves by dictionary identity, so foreign groups need no /NM names.
/// Chained and cyclic links form one group; dangling links are ignored.
class PdfAnnotationGroups {
  PdfAnnotationGroups.ofPage(PdfPage page) {
    final annotations = page.annotations;
    _annotations = annotations;
    final indices = Map<CosDictionary, int>.identity();
    final parents = List.generate(annotations.length, (i) => i);
    for (var i = 0; i < annotations.length; i++) {
      if (pdfCanGroupAnnotation(annotations[i])) {
        indices[annotations[i].dict] = i;
      }
    }
    int root(int i) {
      while (parents[i] != i) {
        parents[i] = parents[parents[i]];
        i = parents[i];
      }
      return i;
    }

    for (final entry in indices.entries) {
      final annotation = annotations[entry.value];
      if (annotation.replyType != 'Group') continue;
      final parent = page.document.cos.resolve(annotation.dict['IRT']);
      final parentIndex = parent is CosDictionary ? indices[parent] : null;
      if (parentIndex != null) parents[root(entry.value)] = root(parentIndex);
    }
    final groups = <int, List<int>>{};
    for (var i = 0; i < annotations.length; i++) {
      (groups[root(i)] ??= []).add(i);
    }
    final immutable = {
      for (final entry in groups.entries)
        entry.key: List<int>.unmodifiable(entry.value),
    };
    _slots = [
      for (var i = 0; i < annotations.length; i++) immutable[root(i)]!,
    ];
  }

  late final List<List<int>> _slots;
  late final List<PdfAnnotation> _annotations;

  /// The group containing [index], in page annotation order. An ungrouped
  /// annotation returns just its own slot; an invalid index returns no slots.
  List<int> slotsFor(int index) =>
      index < 0 || index >= _slots.length ? const [] : _slots[index];

  /// The group's saved frame angle. Foreign groups start square to the page.
  double rotationFor(int index) {
    final slots = slotsFor(index);
    if (slots.length < 2) return 0;
    final a = _annotations[slots.first];
    final value =
        a.document.cos.resolve(a.dict[kPdfAnnotationGroupRotationKey]);
    final angle = switch (value) {
      CosInteger(:final value) => value.toDouble(),
      CosReal(:final value) => value,
      _ => 0.0,
    };
    return angle.isFinite ? angle : 0;
  }

  /// Oriented artwork bounds, in ll/lr/ur/ul corner order. Measuring in the
  /// group's own frame keeps its dimensions constant through rotation rather
  /// than repeatedly enclosing the members' expanded page-aligned /Rects.
  /// Returns null for an ungrouped annotation.
  List<(double, double)>? selectionQuadFor(int index) {
    final slots = slotsFor(index);
    if (slots.length < 2) return null;
    final angle = rotationFor(index);
    final c = math.cos(angle), s = math.sin(angle);
    final local = boundsOfPoints([
      for (final slot in slots)
        for (final (x, y) in _annotations[slot].appearanceQuad ??
            [
              (_annotations[slot].rect.left, _annotations[slot].rect.bottom),
              (_annotations[slot].rect.right, _annotations[slot].rect.bottom),
              (_annotations[slot].rect.right, _annotations[slot].rect.top),
              (_annotations[slot].rect.left, _annotations[slot].rect.top),
            ])
          (c * x + s * y, -s * x + c * y),
    ])!;
    return [
      for (final (x, y) in [
        (local.left, local.bottom),
        (local.right, local.bottom),
        (local.right, local.top),
        (local.left, local.top),
      ])
        (c * x - s * y, s * x + c * y),
    ];
  }
}
