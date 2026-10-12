import 'package:pdf_cos/pdf_cos.dart';

import 'annotation.dart';
import 'page.dart';

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

  /// The group containing [index], in page annotation order. An ungrouped
  /// annotation returns just its own slot; an invalid index returns no slots.
  List<int> slotsFor(int index) =>
      index < 0 || index >= _slots.length ? const [] : _slots[index];
}
