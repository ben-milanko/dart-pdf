part of 'editor.dart';

extension PdfAnnotationGrouping on PdfEditor {
  /// Applies one page-space transform to an annotation set, including its
  /// appearances and point geometry. Text and strokes scale with the artwork.
  /// Validates the complete set before changing any member.
  bool transformAnnotations(
      int pageIndex, Iterable<PdfAnnotation> annotations, PdfMatrix transform) {
    if (transform.toList().any((n) => !n.isFinite) ||
        transform.inverted() == null) {
      return false;
    }
    final page = document.page(pageIndex);
    final specs = <({
      PdfAnnotation a,
      CosStream form,
      PdfRect bbox,
      PdfMatrix matrix,
      PdfRect? box,
      Uint8List bytes
    })>[];
    final seen = Set<CosDictionary>.identity();
    for (final a in annotations) {
      if (!seen.add(a.dict)) continue;
      if (!page.annotations.any((p) => identical(p.dict, a.dict))) return false;
      final form = a.normalAppearance;
      final bbox = form == null
          ? null
          : pdfRectFrom(document.cos, form.dictionary['BBox']);
      final baked = form == null ? null : _bakedFormMatrix(form, a.rect);
      if (form == null ||
          bbox == null ||
          baked == null ||
          a.rect.width <= 0 ||
          a.rect.height <= 0) {
        return false;
      }
      final matrix = baked.concat(transform);
      if (matrix.toList().any((n) => !n.isFinite) ||
          !a.rect.width.isFinite ||
          !a.rect.height.isFinite) {
        return false;
      }
      try {
        PdfRect? box;
        if (a.isCallout) {
          final local = CosDictionary({...a.dict.entries})
            ..['Rect'] = _rectArray(bbox)
            ..entries.remove(kPdfCalloutRDFrameKey);
          local['RD'] =
              a.dict[kPdfCalloutLocalRDKey] ?? a.dict['RD'] ?? CosNull.instance;
          final inverse = baked.inverted();
          if (inverse == null) return false;
          if (_mapPointPairs(a.dict['CL'], inverse.apply) case final line?) {
            local['CL'] = line;
          }
          box = PdfAnnotation.fromDict(document, local).calloutBox;
        }
        specs.add((
          a: a,
          form: form,
          bbox: bbox,
          matrix: matrix,
          box: box,
          bytes: document.cos.decodeStreamData(form)
        ));
      } catch (_) {
        return false;
      }
    }
    if (specs.isEmpty) return false;
    for (final spec in specs) {
      // Detach the appearance: foreign annotations can share the same /AP.
      // Decoding also makes a newly numbered stream safe in encrypted PDFs.
      final bytes = spec.bytes;
      final fd = CosDictionary({...spec.form.dictionary.entries})
        ..entries.remove('Filter')
        ..entries.remove('DecodeParms')
        ..['Length'] = CosInteger(bytes.length)
        ..['Matrix'] =
            CosArray([for (final n in spec.matrix.toList()) CosReal(n)]);
      final ref = _updater.addObject(CosStream(fd, bytes));
      final oldAp = document.cos.resolve(spec.a.dict['AP']) as CosDictionary;
      final ap = CosDictionary({...oldAp.entries});
      final normal = document.cos.resolve(oldAp['N']);
      ap['N'] = normal is CosDictionary
          ? CosDictionary({
              for (final entry in normal.entries.entries)
                entry.key:
                    identical(document.cos.resolve(entry.value), spec.form)
                        ? ref
                        : entry.value
            })
          : ref;
      final dict = spec.a.dict;
      dict['AP'] = ap;
      dict['Rect'] = _rectArray(boundsUnderMatrix(spec.matrix, spec.bbox));
      dict[kPdfAppearanceFrameKey] = const CosBoolean(true);
      if (spec.box case final box?) {
        dict[kPdfCalloutRDFrameKey] = const CosBoolean(true);
        dict[kPdfCalloutLocalRDKey] = _rdArray(spec.bbox, box);
        dict['RD'] = _rdArray(boundsUnderMatrix(spec.matrix, spec.bbox),
            boundsUnderMatrix(spec.matrix, box));
      }
      for (final key in const ['QuadPoints', 'L', 'Vertices', 'CL']) {
        final points = _mapPointPairs(dict[key], transform.apply);
        if (points != null) dict[key] = points;
      }
      for (final key in const ['InkList', kPdfCalloutLeadersKey]) {
        final nested = document.cos.resolve(dict[key]);
        if (nested is CosArray) {
          dict[key] = CosArray([
            for (final stroke in nested.items)
              _mapPointPairs(stroke, transform.apply) ?? stroke
          ]);
        }
      }
      _markAnnotationChanged(pageIndex, dict);
    }
    return true;
  }

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
