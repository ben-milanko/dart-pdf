part of 'editor.dart';

/// Structural page operations: reordering, removal, and merging pages in
/// from other documents. All of them rewrite the page tree as a single
/// flat /Pages node, materializing inherited attributes onto each leaf
/// first so nothing is lost when intermediate nodes drop out.
extension PdfPageOperations on PdfEditor {
  /// Moves the page at [from] so that it ends up at index [to].
  void movePage(int from, int to) {
    final count = document.pageCount;
    RangeError.checkValidIndex(from, null, 'from', count);
    RangeError.checkValidIndex(to, null, 'to', count);
    if (from == to) return;
    final order = [for (var i = 0; i < count; i++) i]
      ..removeAt(from)
      ..insert(to, from);
    reorderPages(order);
  }

  /// Rearranges all pages: entry i of [order] is the current index of the
  /// page that ends up at position i. [order] must be a permutation of
  /// every page index.
  void reorderPages(List<int> order) {
    final count = document.pageCount;
    if (order.length != count ||
        {...order}.length != count ||
        order.any((i) => i < 0 || i >= count)) {
      throw ArgumentError.value(
          order, 'order', 'must be a permutation of 0..${count - 1}');
    }
    final leaves = _materializedLeaves();
    _rebuildPageTree([for (final i in order) leaves[i]]);
  }

  /// Removes the page at [index].
  void removePage(int index) => removePages([index]);

  /// Removes the pages at [indices]; at least one page must remain. The
  /// page objects stay in the file (incremental updates never delete
  /// bytes) but drop out of the page tree.
  void removePages(Iterable<int> indices) {
    final count = document.pageCount;
    final doomed = {...indices};
    for (final i in doomed) {
      RangeError.checkValidIndex(i, null, 'indices', count);
    }
    if (doomed.isEmpty) return;
    if (doomed.length >= count) {
      throw ArgumentError('cannot remove every page of a document');
    }
    final leaves = _materializedLeaves();
    _rebuildPageTree(
        [for (var i = 0; i < count; i++) if (!doomed.contains(i)) leaves[i]]);
  }

  /// Rotates the pages at [indices] clockwise by [degrees] (a multiple of
  /// 90; negative turns counterclockwise), updating each page's /Rotate.
  /// The new rotation is the page's current display rotation plus
  /// [degrees], normalized to 0/90/180/270 and written explicitly onto the
  /// page dictionary (so it overrides any value inherited from an ancestor).
  void rotatePages(Iterable<int> indices, int degrees) {
    if (degrees % 90 != 0) {
      throw ArgumentError.value(
          degrees, 'degrees', 'must be a multiple of 90');
    }
    final count = document.pageCount;
    final targets = {...indices};
    for (final i in targets) {
      RangeError.checkValidIndex(i, null, 'indices', count);
    }
    if (targets.isEmpty || degrees % 360 == 0) return;
    for (final i in targets) {
      final page = document.page(i);
      final dict = page.dict;
      var next = (page.rotation + degrees) % 360;
      if (next < 0) next += 360;
      dict['Rotate'] = CosInteger(next);
      _updater.markChanged(dict);
    }
    document.invalidatePageCache();
  }

  /// Inserts a new blank page [at] the given index (default: appended at
  /// the end), sized [width] × [height] points (default: US Letter,
  /// 612 × 792). The page carries an empty /Resources dictionary and no
  /// content, ready for [PdfContentEditing.stampPage] or annotation
  /// authoring.
  void insertBlankPage({double? width, double? height, int? at}) {
    final w = width ?? 612;
    final h = height ?? 792;
    if (w <= 0 || h <= 0) {
      throw ArgumentError('page dimensions must be positive ($w × $h)');
    }
    final leaves = _materializedLeaves();
    final insertAt = at ?? leaves.length;
    RangeError.checkValueInInterval(insertAt, 0, leaves.length, 'at');
    final dict = CosDictionary({
      'Type': const CosName('Page'),
      'MediaBox': CosArray([CosReal(0), CosReal(0), CosReal(w), CosReal(h)]),
      'Resources': CosDictionary(),
    });
    final ref = _updater.addObject(dict);
    _rebuildPageTree(
        [...leaves]..insert(insertAt, _Leaf(ref, dict, isNew: true)));
  }

  /// Copies pages from [source] into this document — all of them, or the
  /// given [indices] (in that order) — inserting [at] the given position
  /// (default: appended at the end).
  ///
  /// Everything each page references is deep-copied: content streams,
  /// resources, fonts, images, annotations. Links between pages imported
  /// together keep working; destinations that point at source pages left
  /// behind become null (following them would drag the whole source
  /// document along).
  void appendPagesFrom(PdfDocument source, {List<int>? indices, int? at}) {
    if (identical(source.cos, document.cos)) {
      throw ArgumentError('source is this document; '
          'use movePage/reorderPages to rearrange within a file');
    }
    final picks =
        indices ?? [for (var i = 0; i < source.pageCount; i++) i];
    for (final i in picks) {
      RangeError.checkValidIndex(i, null, 'indices', source.pageCount);
    }
    if (picks.isEmpty) return;
    final leaves = _materializedLeaves();
    final insertAt = at ?? leaves.length;
    RangeError.checkValueInInterval(insertAt, 0, leaves.length, 'at');
    final importer = _PageImporter(source, _updater.addObject);
    final imported = importer.importPages(picks);
    _rebuildPageTree([...leaves]..insertAll(insertAt, imported));
  }

  /// Collects the current leaves in order, copying any attributes a page
  /// inherits from its ancestors onto the page itself — flattening is
  /// about to cut those ancestors out of the tree.
  List<_Leaf> _materializedLeaves() {
    final count = document.pageCount;
    return [
      for (var i = 0; i < count; i++) _materialize(document.page(i)),
    ];
  }

  _Leaf _materialize(PdfPage page) {
    final cos = document.cos;
    final dict = page.dict;
    final ref = cos.referenceTo(dict);
    if (ref == null) {
      throw StateError('page dictionary is not an indirect object');
    }
    var changed = false;
    if (!dict.containsKey('Resources')) {
      final resources = page.resources;
      dict['Resources'] = cos.referenceTo(resources) ?? resources;
      changed = true;
    }
    if (!dict.containsKey('MediaBox')) {
      dict['MediaBox'] = _rectArray(page.mediaBox);
      changed = true;
    }
    if (!dict.containsKey('CropBox') && page.cropBox != page.mediaBox) {
      dict['CropBox'] = _rectArray(page.cropBox);
      changed = true;
    }
    if (!dict.containsKey('Rotate') && page.rotation != 0) {
      dict['Rotate'] = CosInteger(page.rotation);
      changed = true;
    }
    return _Leaf(ref, dict, changed: changed);
  }

  /// Rewrites the root /Pages node as a flat tree over [leaves].
  void _rebuildPageTree(List<_Leaf> leaves) {
    final cos = document.cos;
    final rootRef = _pagesRootRef();
    final root = cos.resolve(rootRef) as CosDictionary;
    for (final leaf in leaves) {
      final parentChanged = leaf.dict['Parent'] != rootRef;
      if (parentChanged) leaf.dict['Parent'] = rootRef;
      if (leaf.isNew) continue; // already queued by addObject
      if (parentChanged || leaf.changed) _updater.markChanged(leaf.dict);
    }
    root['Kids'] = CosArray([for (final leaf in leaves) leaf.ref]);
    root['Count'] = CosInteger(leaves.length);
    _updater.markChanged(root);
    document.invalidatePageCache();
  }

  CosReference _pagesRootRef() {
    final ref = document.catalog['Pages'];
    if (ref is CosReference) return ref;
    // a direct /Pages dictionary (nonstandard): promote it to indirect so
    // leaves can point their /Parent at it
    final pages = document.cos.resolve(ref);
    if (pages is! CosDictionary) {
      throw StateError('catalog has no /Pages tree');
    }
    final newRef = _updater.addObject(pages);
    document.catalog['Pages'] = newRef;
    _updater.markChanged(document.catalog);
    return newRef;
  }
}

/// Building a new document from a subset of this one's pages.
extension PdfPageExtraction on PdfDocument {
  /// Builds a brand-new PDF containing only the pages at [indices], in
  /// that order, with everything they reference deep-copied across. The
  /// document information dictionary comes along; document-level state
  /// that lives outside the pages (outlines, the AcroForm field list,
  /// named destinations) does not. Extracting from an encrypted document
  /// produces unencrypted output.
  Uint8List extractPages(List<int> indices) {
    if (indices.isEmpty) {
      throw ArgumentError.value(indices, 'indices', 'select at least one page');
    }
    for (final i in indices) {
      RangeError.checkValidIndex(i, null, 'indices', pageCount);
    }
    final builder = CosDocumentBuilder();
    final pagesDict = CosDictionary({'Type': const CosName('Pages')});
    final pagesRef = builder.add(pagesDict);
    final importer = _PageImporter(this, builder.add);
    final leaves = importer.importPages(indices);
    for (final leaf in leaves) {
      leaf.dict['Parent'] = pagesRef;
    }
    pagesDict['Kids'] = CosArray([for (final leaf in leaves) leaf.ref]);
    pagesDict['Count'] = CosInteger(leaves.length);
    final catalogRef = builder.add(CosDictionary({
      'Type': const CosName('Catalog'),
      'Pages': pagesRef,
    }));
    CosReference? infoRef;
    final info = cos.resolve(cos.trailer['Info']);
    if (info is CosDictionary) {
      infoRef = builder.add(importer.copyValue(info));
    }
    final headerVersion = version;
    return builder.build(
      root: catalogRef,
      info: infoRef,
      version: RegExp(r'^\d+\.\d+$').hasMatch(headerVersion)
          ? headerVersion
          : '1.7',
    );
  }

  /// Builds a standalone PDF of pages [start] through [end] inclusive, in
  /// order — a convenience over [extractPages] for the common contiguous
  /// range. [end] must not be before [start].
  Uint8List extractPageRange(int start, int end) {
    if (end < start) {
      throw ArgumentError('end ($end) must not be before start ($start)');
    }
    return extractPages([for (var i = start; i <= end; i++) i]);
  }
}

/// A page leaf headed into a rebuilt flat tree.
class _Leaf {
  _Leaf(this.ref, this.dict, {this.changed = false, this.isNew = false});

  final CosReference ref;
  final CosDictionary dict;

  /// Attributes were materialized onto the dict, so it must be rewritten.
  final bool changed;

  /// Freshly imported — already queued for writing, [PdfEditor] must not
  /// call markChanged on it.
  final bool isNew;
}

/// Deep-copies page object graphs out of [source] into a destination
/// object sink (an incremental updater's addObject, or a
/// [CosDocumentBuilder]'s add), remapping references as it goes.
///
/// The source page tree is the copy boundary: a reference that escapes to
/// a /Pages node, or to a page that is not part of the import set, copies
/// as null instead of dragging the rest of the document along.
class _PageImporter {
  _PageImporter(this.source, this._add);

  final PdfDocument source;
  final CosReference Function(CosObject) _add;
  final Map<CosReference, CosObject> _mapped = {};

  List<_Leaf> importPages(List<int> indices) {
    final cos = source.cos;
    final pages = [for (final i in indices) source.page(i)];

    // pre-register every imported page so references between them — link
    // destinations, annotation /P entries — remap instead of dropping
    final leaves = <_Leaf>[];
    for (final page in pages) {
      final dest = CosDictionary();
      final ref = _add(dest);
      leaves.add(_Leaf(ref, dest, isNew: true));
      final srcRef = cos.referenceTo(page.dict);
      if (srcRef != null) _mapped[srcRef] = ref;
    }

    for (var i = 0; i < pages.length; i++) {
      final page = pages[i];
      final dest = leaves[i].dict;
      page.dict.entries.forEach((key, value) {
        if (key == 'Parent') return; // belongs to the source tree
        dest[key] = copyValue(value);
      });
      dest['Type'] = const CosName('Page');
      // materialize what the source page inherited from its ancestors
      if (!dest.containsKey('Resources')) {
        final resources = page.resources;
        final srcRef = cos.referenceTo(resources);
        dest['Resources'] =
            srcRef != null ? copyValue(srcRef) : copyValue(resources);
      }
      if (!dest.containsKey('MediaBox')) {
        dest['MediaBox'] = _rectArray(page.mediaBox);
      }
      if (!dest.containsKey('CropBox') && page.cropBox != page.mediaBox) {
        dest['CropBox'] = _rectArray(page.cropBox);
      }
      if (!dest.containsKey('Rotate') && page.rotation != 0) {
        dest['Rotate'] = CosInteger(page.rotation);
      }
    }
    return leaves;
  }

  /// Copies any object value. Direct containers copy structurally;
  /// references allocate (once) in the destination and remap.
  CosObject copyValue(CosObject value) {
    switch (value) {
      case CosReference ref:
        return _mapped[ref] ??= _copyTarget(ref);
      case CosStream stream: // direct streams are illegal, but tolerate
        return _copyStream(null, stream);
      case CosDictionary dict:
        final out = CosDictionary();
        dict.entries.forEach((key, item) => out[key] = copyValue(item));
        return out;
      case CosArray array:
        return CosArray([for (final item in array.items) copyValue(item)]);
      case CosString string:
        return CosString(Uint8List.fromList(string.bytes),
            isHex: string.isHex);
      default:
        return value; // names, numbers, booleans, null are immutable
    }
  }

  CosObject _copyTarget(CosReference ref) {
    final target = source.cos.resolve(ref);
    switch (target) {
      case CosDictionary dict when dict.typeName == 'Pages':
        return CosNull.instance; // never cross into the source page tree
      case CosDictionary dict when dict.typeName == 'Page':
        return CosNull.instance; // a page that was not selected for import
      case CosStream stream:
        return _copyStream(ref, stream);
      case CosDictionary dict:
        final out = CosDictionary();
        final outRef = _add(out);
        _mapped[ref] = outRef;
        dict.entries.forEach((key, item) => out[key] = copyValue(item));
        return outRef;
      case CosNull():
        return CosNull.instance;
      default:
        // an indirectly referenced scalar — inline it at the use site
        return copyValue(target);
    }
  }

  /// Copies a stream, registering its reference (when indirect) before
  /// the dictionary fills so self-referential entries remap instead of
  /// recursing. For unencrypted sources the raw (still encoded) payload
  /// is reused as-is; encrypted sources decrypt the payload without
  /// running the filters, so /Filter chains survive and the copy lands
  /// in the destination as plain bytes.
  CosObject _copyStream(CosReference? ref, CosStream stream) {
    final bytes = _payloadOf(stream);
    final out = CosStream(CosDictionary(), bytes);
    final outRef = ref != null ? _mapped[ref] = _add(out) : null;
    stream.dictionary.entries.forEach((key, item) {
      if (key == 'Length') return; // recomputed below
      out.dictionary[key] = copyValue(item);
    });
    out.dictionary['Length'] = CosInteger(bytes.length);
    return outRef ?? out;
  }

  Uint8List _payloadOf(CosStream stream) {
    final cos = source.cos;
    if (!cos.isEncrypted) return stream.rawBytes;
    final filter = cos.resolve(stream.dictionary['Filter']);
    final first = switch (filter) {
      CosName(:final value) => value,
      CosArray array when array.length > 0 =>
        switch (cos.resolve(array[0])) {
          CosName(:final value) => value,
          _ => null,
        },
      _ => null,
    };
    // stop before the first filter: decrypt only, keep the encoding
    return cos.decodeStreamData(stream, stopBeforeFilter: first);
  }
}

CosArray _rectArray(PdfRect rect) => CosArray([
      CosReal(rect.left),
      CosReal(rect.bottom),
      CosReal(rect.right),
      CosReal(rect.top),
    ]);
