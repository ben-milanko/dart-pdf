part of 'editor.dart';

extension PdfAnnotationGrouping on PdfEditor {
  /// Groups page markups using the standard /RT /Group and /IRT entries.
  /// Existing groups touched by [annotations] are merged in full. Appearances,
  /// geometry, annotation names, and page paint order are preserved.
  bool groupAnnotations(int pageIndex, Iterable<PdfAnnotation> annotations) {
    final page = document.page(pageIndex);
    final groups = PdfAnnotationGroups.ofPage(page);
    final slots = _annotationGroupTargets(page, groups, annotations);
    if (slots.length < 2) return false;
    final existing = groups.slotsFor(slots.first);
    if (existing.length == slots.length && slots.every(existing.contains)) {
      return false;
    }
    final targets = [for (final slot in slots) page.annotations[slot]];
    _writeAnnotationGroupMembers(pageIndex, targets);
    return true;
  }

  void _writeAnnotationGroupMembers(
      int pageIndex, List<PdfAnnotation> targets) {
    if (targets.isEmpty) return;
    final parent = targets.first;
    final parentRef = targets.length > 1
        ? _PdfPageAnnotationList(this, pageIndex).makeIndirect(parent.dict)
        : null;
    for (final annotation in targets) {
      if (targets.length > 1 && annotation.name == null) {
        annotation.dict['NM'] = CosString.fromText(_generateAnnotationName());
      }
      if (identical(annotation.dict, parent.dict)) {
        annotation.dict.entries
          ..remove('IRT')
          ..remove('RT');
      } else {
        annotation.dict['IRT'] = parentRef!;
        annotation.dict['RT'] = const CosName('Group');
      }
      _markAnnotationChanged(pageIndex, annotation.dict, visual: false);
    }
  }

  /// Re-parent surviving group members when a removed member was their
  /// leader (or an intermediate link in a foreign chained group).
  void _repairAnnotationGroupsForRemoval(
      int pageIndex, Set<CosDictionary> removed) {
    final page = document.page(pageIndex);
    final annotations = page.annotations;
    if (!annotations.any((a) =>
        !removed.contains(a.dict) &&
        a.replyType == 'Group' &&
        removed.contains(document.cos.resolve(a.dict['IRT'])))) {
      return;
    }
    final groups = PdfAnnotationGroups.ofPage(page);
    final visited = <int>{};
    for (var i = 0; i < annotations.length; i++) {
      if (!removed.contains(annotations[i].dict)) continue;
      final slots = groups.slotsFor(i);
      if (slots.length < 2 || !visited.add(slots.first)) continue;
      final survivors = [
        for (final slot in slots)
          if (!removed.contains(annotations[slot].dict)) annotations[slot],
      ];
      _writeAnnotationGroupMembers(pageIndex, survivors);
    }
  }

  /// Dissolves each group touched by [annotations], retaining every markup.
  /// Comment reply links and review states are left intact.
  bool ungroupAnnotations(int pageIndex, Iterable<PdfAnnotation> annotations) {
    final page = document.page(pageIndex);
    final groups = PdfAnnotationGroups.ofPage(page);
    final slots = _annotationGroupTargets(page, groups, annotations);
    var changed = false;
    for (final slot in slots) {
      final annotation = page.annotations[slot];
      if (annotation.replyType != 'Group') continue;
      annotation.dict.entries
        ..remove('IRT')
        ..remove('RT');
      _markAnnotationChanged(pageIndex, annotation.dict, visual: false);
      changed = true;
    }
    return changed;
  }

  List<int> _annotationGroupTargets(PdfPage page, PdfAnnotationGroups groups,
      Iterable<PdfAnnotation> annotations) {
    final slots = <int>{};
    for (final annotation in annotations) {
      final index = page.annotations
          .indexWhere((a) => identical(a.dict, annotation.dict));
      if (index < 0 || !pdfCanGroupAnnotation(annotation)) {
        throw ArgumentError('group members must be markups on the same page');
      }
      slots.addAll(groups.slotsFor(index));
    }
    return slots.toList()..sort();
  }
}
