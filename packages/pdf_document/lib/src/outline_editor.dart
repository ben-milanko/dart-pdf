part of 'editor.dart';

/// Authoring of the document outline (bookmarks): the `/Outlines` tree
/// (§12.3.3). Every mutation keeps the First/Last/Next/Prev/Parent linkage
/// and the `/Count` invariants consistent, and stages only the objects it
/// touches so [PdfEditor.save] appends them as one incremental update.
///
/// Items are referred to by their object [CosReference], which
/// [addOutlineItem] returns.
extension PdfOutlineEditing on PdfEditor {
  /// Adds an outline item titled [title].
  ///
  /// [destination] (or, as a shortcut, [pageIndex] for a fit-the-page
  /// target) is where the item navigates. [parent] is the item to nest
  /// under; null adds a top-level item. [index] is the position among the
  /// new parent's children (null appends to the end, 0 prepends). [color]
  /// is `0xRRGGBB`, [bold]/[italic] set the text style, and [open] controls
  /// whether the item starts expanded once it has children.
  ///
  /// Returns the new item's reference, usable as [parent] for further nesting
  /// and with the other mutators.
  CosReference addOutlineItem(
    String title, {
    PdfExplicitDestination? destination,
    int? pageIndex,
    CosReference? parent,
    int? index,
    int? color,
    bool bold = false,
    bool italic = false,
    bool open = true,
  }) {
    final rootRef = _ensureOutlineRoot();
    final parentRef = parent ?? rootRef;
    // resolve early so a bad parent throws before anything is staged
    _outlineDict(parentRef);

    final item = CosDictionary({'Title': CosString.fromText(title)});
    final dest = destination ??
        (pageIndex != null ? PdfExplicitDestination.fit(pageIndex) : null);
    if (dest != null) item['Dest'] = _outlineDestArray(dest);
    if (color != null) item['C'] = _rgbArray(color);
    final flags = (italic ? 1 : 0) | (bold ? 2 : 0);
    if (flags != 0) item['F'] = CosInteger(flags);
    item['Parent'] = parentRef;
    final itemRef = _updater.addObject(item);
    _outlineOpenOverride[itemRef.objectNumber] = open;

    final siblings = _outlineChildren(parentRef);
    final at = index == null ? siblings.length : index.clamp(0, siblings.length);
    siblings.insert(at, itemRef);
    _relinkOutlineChildren(parentRef, siblings);
    _recountOutline(rootRef);
    return itemRef;
  }

  /// Removes [item] and its whole subtree from the outline. The detached
  /// objects become unreferenced in the file (harmless in an incremental
  /// update).
  void removeOutlineItem(CosReference item) {
    final dict = _outlineDict(item);
    final parentRef = _outlineParentRef(dict) ?? _ensureOutlineRoot();
    final siblings = _outlineChildren(parentRef)
      ..removeWhere((r) => r == item);
    _relinkOutlineChildren(parentRef, siblings);
    _recountOutline(_ensureOutlineRoot());
  }

  /// Moves [item] (and its subtree) under [parent] (null = top level) at
  /// [index] among the destination's children (null appends). Throws if
  /// [parent] is [item] itself or one of its descendants.
  void moveOutlineItem(CosReference item,
      {CosReference? parent, int? index}) {
    final rootRef = _ensureOutlineRoot();
    final dict = _outlineDict(item);
    final newParentRef = parent ?? rootRef;
    if (newParentRef == item || _outlineIsDescendant(newParentRef, item)) {
      throw ArgumentError('cannot move an outline item under itself');
    }
    final oldParentRef = _outlineParentRef(dict) ?? rootRef;

    if (oldParentRef == newParentRef) {
      final siblings = _outlineChildren(oldParentRef)
        ..removeWhere((r) => r == item);
      final at = index == null ? siblings.length : index.clamp(0, siblings.length);
      siblings.insert(at, item);
      _relinkOutlineChildren(newParentRef, siblings);
    } else {
      final old = _outlineChildren(oldParentRef)..removeWhere((r) => r == item);
      _relinkOutlineChildren(oldParentRef, old);
      final siblings = _outlineChildren(newParentRef);
      final at = index == null ? siblings.length : index.clamp(0, siblings.length);
      siblings.insert(at, item);
      _relinkOutlineChildren(newParentRef, siblings);
    }
    _recountOutline(rootRef);
  }

  /// Replaces [item]'s title.
  void setOutlineTitle(CosReference item, String title) {
    final dict = _outlineDict(item);
    dict['Title'] = CosString.fromText(title);
    _stageOutline(item, dict);
  }

  /// Points [item] at [destination].
  void setOutlineDestination(
      CosReference item, PdfExplicitDestination destination) {
    final dict = _outlineDict(item);
    dict['Dest'] = _outlineDestArray(destination);
    dict.entries.remove('A'); // an explicit /Dest supersedes a /GoTo action
    _stageOutline(item, dict);
  }

  /// Restyles [item]. A null argument leaves that property unchanged;
  /// [color] is `0xRRGGBB` (pass a negative value to clear it). Changing
  /// [open] recomputes the `/Count` signs.
  void setOutlineStyle(
    CosReference item, {
    int? color,
    bool? bold,
    bool? italic,
    bool? open,
  }) {
    final dict = _outlineDict(item);
    if (color != null) {
      if (color < 0) {
        dict.entries.remove('C');
      } else {
        dict['C'] = _rgbArray(color);
      }
    }
    if (bold != null || italic != null) {
      final current = dict['F'];
      var flags = current is CosInteger ? current.value : 0;
      if (italic != null) flags = italic ? flags | 1 : flags & ~1;
      if (bold != null) flags = bold ? flags | 2 : flags & ~2;
      if (flags == 0) {
        dict.entries.remove('F');
      } else {
        dict['F'] = CosInteger(flags);
      }
    }
    _stageOutline(item, dict);
    if (open != null) {
      _outlineOpenOverride[item.objectNumber] = open;
      _recountOutline(_ensureOutlineRoot());
    }
  }

  // --- internals -----------------------------------------------------------

  /// The catalog's outline root reference, creating and linking `/Outlines`
  /// when absent.
  CosReference _ensureOutlineRoot() {
    final cos = document.cos;
    final raw = document.catalog['Outlines'];
    final resolved = cos.resolve(raw);
    if (resolved is CosDictionary) {
      if (raw is CosReference) return raw;
      final ref = _updater.addObject(resolved);
      document.catalog['Outlines'] = ref;
      _updater.markChanged(document.catalog);
      return ref;
    }
    final root = CosDictionary({
      'Type': const CosName('Outlines'),
      'Count': const CosInteger(0),
    });
    final ref = _updater.addObject(root);
    document.catalog['Outlines'] = ref;
    _updater.markChanged(document.catalog);
    return ref;
  }

  CosDictionary _outlineDict(CosReference ref) {
    final d = document.cos.resolve(ref);
    if (d is! CosDictionary) {
      throw ArgumentError.value(ref, 'item', 'is not an outline item');
    }
    return d;
  }

  CosReference? _outlineParentRef(CosDictionary dict) {
    final p = dict['Parent'];
    return p is CosReference ? p : null;
  }

  List<CosReference> _outlineChildren(CosReference parentRef) {
    final dict = _outlineDict(parentRef);
    final out = <CosReference>[];
    final seen = <int>{};
    var cur = dict['First'];
    while (cur is CosReference && seen.add(cur.objectNumber)) {
      out.add(cur);
      final c = document.cos.resolve(cur);
      cur = c is CosDictionary ? c['Next'] : null;
    }
    return out;
  }

  bool _outlineIsDescendant(CosReference candidate, CosReference ancestor) {
    var cur = candidate;
    final seen = <int>{};
    while (seen.add(cur.objectNumber)) {
      final parent = _outlineParentRef(_outlineDict(cur));
      if (parent == null) return false;
      if (parent == ancestor) return true;
      cur = parent;
    }
    return false;
  }

  /// Rewrites a parent's First/Last and every child's Prev/Next/Parent from
  /// the ordered [children] list, staging all of them.
  void _relinkOutlineChildren(
      CosReference parentRef, List<CosReference> children) {
    final parent = _outlineDict(parentRef);
    if (children.isEmpty) {
      parent.entries.remove('First');
      parent.entries.remove('Last');
    } else {
      parent['First'] = children.first;
      parent['Last'] = children.last;
    }
    _stageOutline(parentRef, parent);
    for (var i = 0; i < children.length; i++) {
      final d = _outlineDict(children[i]);
      d['Parent'] = parentRef;
      if (i == 0) {
        d.entries.remove('Prev');
      } else {
        d['Prev'] = children[i - 1];
      }
      if (i == children.length - 1) {
        d.entries.remove('Next');
      } else {
        d['Next'] = children[i + 1];
      }
      _stageOutline(children[i], d);
    }
  }

  /// Recomputes `/Count` on every node so it equals the number of visible
  /// descendants, negated for closed items (§12.3.3).
  void _recountOutline(CosReference rootRef) {
    int visible(CosReference nodeRef) {
      final dict = _outlineDict(nodeRef);
      final kids = _outlineChildren(nodeRef);
      if (kids.isEmpty) {
        dict.entries.remove('Count');
        _stageOutline(nodeRef, dict);
        return 0;
      }
      var total = 0;
      for (final kid in kids) {
        final sub = visible(kid);
        total += 1 + (_outlineIsOpen(kid) ? sub : 0);
      }
      dict['Count'] = CosInteger(_outlineIsOpen(nodeRef) ? total : -total);
      _stageOutline(nodeRef, dict);
      return total;
    }

    final root = _outlineDict(rootRef);
    var total = 0;
    for (final kid in _outlineChildren(rootRef)) {
      final sub = visible(kid);
      total += 1 + (_outlineIsOpen(kid) ? sub : 0);
    }
    root['Count'] = CosInteger(total); // the root is always shown expanded
    _stageOutline(rootRef, root);
  }

  bool _outlineIsOpen(CosReference ref) {
    final override = _outlineOpenOverride[ref.objectNumber];
    if (override != null) return override;
    final c = _outlineDict(ref)['Count'];
    if (c is CosInteger) return c.value >= 0;
    return true;
  }

  void _stageOutline(CosReference ref, CosDictionary dict) =>
      _updater.replaceObject(ref.objectNumber, dict);

  CosArray _outlineDestArray(PdfExplicitDestination dest) =>
      dest.toCosArray(_pageReference(dest.pageIndex));

  CosReference _pageReference(int index) {
    final page = document.page(index);
    final ref = document.cos.referenceTo(page.dict);
    if (ref == null) {
      throw StateError('page $index has no object reference');
    }
    return ref;
  }

  CosArray _rgbArray(int color) => CosArray([
        CosReal(((color >> 16) & 0xFF) / 255),
        CosReal(((color >> 8) & 0xFF) / 255),
        CosReal((color & 0xFF) / 255),
      ]);
}
