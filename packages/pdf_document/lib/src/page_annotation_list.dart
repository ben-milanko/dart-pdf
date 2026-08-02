part of 'editor.dart';

/// Internal mutation module for a page's `/Annots` array.
///
/// The array may be direct, indirect, absent, or malformed. Callers should not
/// have to remember which object owns the bytes after appending, filtering, or
/// reordering annotations.
class _PdfPageAnnotationList {
  _PdfPageAnnotationList(this._editor, this.pageIndex);

  final PdfEditor _editor;
  final int pageIndex;

  PdfDocument get _document => _editor.document;
  CosDocument get _cos => _document.cos;
  CosIncrementalUpdater get _updater => _editor._updater;
  PdfPage get _page => _document.page(pageIndex);

  CosObject? get _raw => _page.dict['Annots'];

  CosArray? get _array {
    final resolved = _cos.resolve(_raw);
    return resolved is CosArray ? resolved : null;
  }

  /// Appends [item], creating `/Annots` when it is absent or malformed.
  void append(CosObject item) {
    final items = [...?_array?.items, item];
    _replaceItems(items);
  }

  /// Removes array entries matching [test]. Returns whether the page changed.
  bool removeWhere(bool Function(CosObject item, CosObject? resolved) test,
      {bool removeIfEmpty = false}) {
    final array = _array;
    if (array == null) return false;
    final kept = <CosObject>[];
    var changed = false;
    for (final item in array.items) {
      if (test(item, _cos.resolve(item))) {
        changed = true;
      } else {
        kept.add(item);
      }
    }
    if (!changed) return false;
    _replaceItems(kept, removeIfEmpty: removeIfEmpty);
    return true;
  }

  /// Moves entries resolving to one of [targets] to the front/back of
  /// `/Annots`, preserving their relative order.
  bool reorderResolvedDictionaries(Set<CosDictionary> targets,
      {required bool toFront}) {
    if (targets.isEmpty) return false;
    final array = _array;
    if (array == null) return false;
    final moved = <CosObject>[];
    final rest = <CosObject>[];
    for (final item in array.items) {
      final resolved = _cos.resolve(item);
      (resolved is CosDictionary && targets.contains(resolved) ? moved : rest)
          .add(item);
    }
    if (moved.isEmpty) return false;
    final reordered = toFront ? [...rest, ...moved] : [...moved, ...rest];
    var same = reordered.length == array.items.length;
    for (var i = 0; i < array.items.length && same; i++) {
      same = identical(array.items[i], reordered[i]);
    }
    if (same) return false;
    _replaceItems(reordered);
    return true;
  }

  /// Stages the object that owns [dict]'s serialized bytes.
  ///
  /// If [dict] is indirect, the annotation itself owns the bytes. Otherwise
  /// the containing `/Annots` array or page owns them.
  void markOwnerChangedFor(CosDictionary dict) {
    final ref = _cos.referenceTo(dict);
    if (ref != null) {
      _updater.replaceObject(ref.objectNumber, dict);
      return;
    }
    final raw = _raw;
    final array = _array;
    if (raw is CosReference && array != null) {
      _updater.replaceObject(raw.objectNumber, CosArray([...array.items]));
    } else {
      _updater.markChanged(_page.dict);
    }
  }

  void _replaceItems(List<CosObject> items, {bool removeIfEmpty = false}) {
    final page = _page;
    final raw = _raw;
    if (items.isEmpty && removeIfEmpty) {
      if (page.dict.entries.remove('Annots') != null) {
        _updater.markChanged(page.dict);
      }
      return;
    }

    final next = CosArray(items);
    if (raw is CosReference && _cos.resolve(raw) is CosArray) {
      _updater.replaceObject(raw.objectNumber, next);
      // A single editor transaction can remove and then re-add an annotation
      // (for example when a FreeText property change regenerates its
      // appearance). Make the replacement visible to that transaction's
      // next `/Annots` read; otherwise resolve(raw) returns the original
      // cached array and the append resurrects the removed annotation.
      _cos.adoptObject(raw, next);
    } else {
      page.dict['Annots'] = next;
      _updater.markChanged(page.dict);
    }
  }
}
