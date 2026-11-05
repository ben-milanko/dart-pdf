part of 'editor.dart';

/// Applying (burning) redaction marks created by
/// [PdfAnnotationEditing.addRedaction].
///
/// True redaction per §12.5.6.23: covered text and images are *removed
/// from the file* - not merely painted over - then the /IC fill is drawn
/// into the page content and the /Redact annotations are deleted. The result
/// is irreversible: a viewer (or a byte search of the saved file, decoded
/// streams included) cannot recover what was under a redaction rect.
///
/// What a burn covers (#1255):
///  * **Page text** is split glyph by glyph: exact for simple single-byte
///    fonts (Type 3 included) and `/Identity-H` composite fonts. Other
///    composite (`/Type0`) encodings can't be split without parsing their
///    CMap, so a text-showing operation in one that touches a rect is
///    dropped whole. Invisible text (`3 Tr`, size 0) is removed like any
///    other.
///  * **Form XObjects** under a rect are burned recursively into a fresh
///    copy (their own text, images and nested forms), so the OCR text layer
///    or a stamp drawn through a form loses what the rect covers.
///  * **Images** fully under a rect are dropped; partially covered ones are
///    re-encoded with the covered pixels (and the matching /SMask or /Mask
///    pixels) cleared. An image whose samples can't be decoded (JPX, CMYK
///    JPEG, unknown colour space) is dropped whole. Inline images that touch
///    a rect are dropped whole.
///  * The page's resources stop naming what was dropped or replaced, and an
///    original nothing else draws is purged from the saved file.
///  * **Annotations** touching a rect are removed with their popups and
///    replies. A removed **form widget** takes its field (and the field's
///    value) out of the /AcroForm tree once it has no other widget, and any
///    XFA copy of the form data goes with it.
///  * Marked-content `/ActualText`, `/Alt` and `/E` around removed content
///    are stripped, as is the page's /Thumb thumbnail and /PieceInfo.
///  * **Hidden copies** of the removed text are scrubbed document-wide:
///    document info, XMP metadata, bookmarks, structure-tree alternate text
///    and attachments that contain it. With `removeHiddenInformation` (the
///    default) the burn also drops document metadata, attachments and
///    document JavaScript outright, since they can carry the redacted
///    content in a form no text match finds (a compressed attachment, an
///    unrelated copy in the title).
///
/// Not covered: content drawn through tiling patterns or Type 3 glyph
/// procedures is not split, and text on other pages is never touched.
extension PdfRedactionApply on PdfEditor {
  /// Burns every `/Redact` mark on [pageIndex] (or on every page when
  /// null) and returns the full edited file bytes. Same as
  /// [burnRedactions] with its defaults.
  Uint8List applyRedactions([int? pageIndex]) =>
      burnRedactions(pageIndex: pageIndex);

  /// Burns every `/Redact` mark on [pageIndex] (or on every page when
  /// null) and returns the full edited file bytes.
  ///
  /// Removes the covered glyphs/images from the content (see the
  /// [PdfRedactionApply] overview), paints the /IC fill, removes the /Redact
  /// annotations and every annotation touching a redaction region, and
  /// scrubs hidden copies of the removed text. With
  /// [removeHiddenInformation] it also drops document metadata (keeping
  /// only /Producer and the dates), embedded files and document JavaScript.
  ///
  /// Unlike every other editor operation, the burn is NOT written as an
  /// incremental update - an incremental save keeps the original bytes
  /// (and therefore the redacted glyphs) physically in the file, where a
  /// byte search would recover them. Instead the whole document is
  /// re-serialized fresh (a compaction), dropping the superseded content
  /// streams entirely. This makes the result irreversible at the cost of
  /// invalidating any existing digital signature (redaction changes the
  /// content, so signatures could not survive regardless).
  ///
  /// Throws [UnsupportedError] for encrypted documents (the compaction
  /// would mix plaintext strings with the file's ciphertext streams);
  /// decrypt the file before redacting.
  Uint8List burnRedactions({
    int? pageIndex,
    bool removeHiddenInformation = true,
  }) {
    final pages = pageIndex != null
        ? [pageIndex]
        : [for (var i = 0; i < document.pageCount; i++) i];
    if (document.cos.encryption != null &&
        pages.any((i) => _hasRedactionMarks(document.page(i)))) {
      throw UnsupportedError(
        'applyRedactions cannot compact an encrypted document; decrypt it '
        'before redacting',
      );
    }
    final session = _RedactionSession();
    for (final i in pages) {
      if (_applyRedactionsOnPage(i, session)) session.burnedPages.add(i);
    }
    // No marks anywhere: keep any other staged edits as an incremental save.
    if (session.burnedPages.isEmpty) return save();
    _scrubHiddenCopies(session, removeHiddenInformation);
    _purgeUndrawnXObjects(session);
    _markDestructive(pages);
    return _compactedSave(session.purged);
  }

  bool _hasRedactionMarks(PdfPage page) {
    final cos = document.cos;
    final annots = cos.resolve(page.dict['Annots']);
    if (annots is! CosArray) return false;
    for (final item in annots.items) {
      final d = cos.resolve(item);
      if (d is CosDictionary && _isSubtype(cos, d, 'Redact')) return true;
    }
    return false;
  }

  static bool _isSubtype(CosDocument cos, CosDictionary d, String subtype) {
    final s = cos.resolve(d['Subtype']);
    return s is CosName && s.value == subtype;
  }

  /// Re-serializes the document's current in-memory state into a fresh file
  /// with renumbered objects, dropping everything no longer reachable from
  /// the catalog (the redacted-away content streams and annotations). This
  /// is what makes redaction irreversible.
  ///
  /// [purged] object numbers are dropped even where still referenced: the
  /// reference is removed from its array or dictionary (and a structure
  /// tree /OBJR pointing at one goes with it). That is how a removed
  /// annotation's other referrers - the /AcroForm field tree, a popup's
  /// /Parent, a reply's /IRT, the structure tree - stop carrying it.
  Uint8List _compactedSave(Set<int> purged) {
    final cos = document.cos;
    if (cos.encryption != null) {
      throw UnsupportedError(
        'applyRedactions cannot compact an encrypted document; decrypt it '
        'before redacting',
      );
    }
    final rootRef = cos.trailer['Root'];
    if (rootRef is! CosReference) {
      throw StateError('document has no indirect /Root');
    }
    final infoRef = cos.trailer['Info'];

    final order = <int>[]; // old object numbers, in discovery order
    final newNumber = <int, int>{}; // old → new (1-based)
    final generation = <int, int>{};
    final queue = <int>[];

    bool deadObjr(CosDictionary d) {
      final type = d['Type'];
      final obj = d['Obj'];
      return type is CosName &&
          type.value == 'OBJR' &&
          obj is CosReference &&
          purged.contains(obj.objectNumber);
    }

    bool dead(CosObject value) {
      if (purged.isEmpty) return false;
      if (value is CosReference) {
        if (purged.contains(value.objectNumber)) return true;
        final resolved = cos.resolve(value);
        return resolved is CosDictionary && deadObjr(resolved);
      }
      return value is CosDictionary && deadObjr(value);
    }

    void discover(CosObject node) {
      if (node is! CosReference) return;
      if (newNumber.containsKey(node.objectNumber)) return;
      if (purged.contains(node.objectNumber)) return;
      newNumber[node.objectNumber] = order.length + 1;
      generation[node.objectNumber] = node.generation;
      order.add(node.objectNumber);
      queue.add(node.objectNumber);
    }

    void scan(CosObject node) {
      switch (node) {
        case CosArray():
          for (final item in node.items) {
            if (dead(item)) continue;
            item is CosReference ? discover(item) : scan(item);
          }
        case CosDictionary():
          node.entries.forEach((_, value) {
            if (dead(value)) return;
            value is CosReference ? discover(value) : scan(value);
          });
        case CosStream():
          scan(node.dictionary);
        default:
          break;
      }
    }

    discover(rootRef);
    if (infoRef is CosReference) discover(infoRef);
    var head = 0;
    while (head < queue.length) {
      final number = queue[head++];
      scan(cos.resolve(CosReference(number, generation[number]!)));
    }

    CosObject remap(CosObject node) {
      switch (node) {
        case CosReference():
          final n = newNumber[node.objectNumber];
          return n != null ? CosReference(n, 0) : CosNull.instance;
        case CosArray():
          return CosArray([
            for (final item in node.items)
              if (!dead(item)) remap(item),
          ]);
        case CosDictionary():
          final out = CosDictionary();
          node.entries.forEach((key, value) {
            if (!dead(value)) out[key] = remap(value);
          });
          return out;
        case CosStream():
          final dict = remap(node.dictionary) as CosDictionary
            ..['Length'] = CosInteger(node.rawBytes.length);
          return CosStream(dict, node.rawBytes);
        default:
          return node;
      }
    }

    final builder = CosDocumentBuilder();
    for (final number in order) {
      builder.add(
        remap(cos.resolve(CosReference(number, generation[number]!))),
      );
    }
    return builder.build(
      root: CosReference(newNumber[rootRef.objectNumber]!, 0),
      info: infoRef is CosReference
          ? CosReference(newNumber[infoRef.objectNumber]!, 0)
          : null,
    );
  }

  /// Burns the redactions on one page; returns whether any mark was found.
  bool _applyRedactionsOnPage(int pageIndex, _RedactionSession session) {
    final cos = document.cos;
    final page = document.page(pageIndex);
    final annotsRaw = page.dict['Annots'];
    final annots = cos.resolve(annotsRaw);
    if (annots is! CosArray) return false;

    final redactions = <_Redaction>[];
    for (final item in annots.items) {
      final d = cos.resolve(item);
      if (d is CosDictionary && _isSubtype(cos, d, 'Redact')) {
        redactions.addAll(_redactionsFrom(cos, d));
      }
    }
    if (redactions.isEmpty) return false;
    final regions = [for (final r in redactions) r.rect];

    // 1. Surgically remove covered content from the page's streams (and
    //    from the form XObjects and images it draws).
    final original = page.contentBytes();
    final burn = _RedactionBurn(
        cos, page.resources, regions, session, _updater.addObject);
    final burned = burn.run(original);
    final resources = burn.rebuiltResources();
    if (resources != null) {
      // the page's own copy: an inherited or shared dictionary may still
      // serve pages that draw the originals
      page.dict['Resources'] = resources;
    }
    // thumbnails and private application data show the page as it was
    page.dict.entries.remove('Thumb');
    page.dict.entries.remove('PieceInfo');
    _updater.markChanged(page.dict);

    // 2. Paint the fill (and any overlay text) over each region, on top.
    final fill = _redactionFillContent(page, redactions);

    final rebuilt = BytesBuilder(copy: false)
      ..add(latin1.encode('q\n'))
      ..add(burned)
      ..add(latin1.encode('\nQ\n'))
      ..add(fill);
    _setContent(pageIndex, page, rebuilt.takeBytes());

    // 3. Drop the /Redact annotations and every annotation touching a
    //    redaction region (it draws over the fill, and its /Contents or
    //    field value is what the rect is meant to hide), with the popups
    //    and replies that belong to them.
    final removed = _annotationsToRedact(annots, regions);
    final annotationsChanged = _PdfPageAnnotationList(this, pageIndex)
        .removeWhere((_, resolved) => removed.containsKey(resolved));
    for (final MapEntry(key: dict, value: item) in removed.entries) {
      final ref = item is CosReference ? item : cos.referenceTo(dict);
      if (ref != null) session.purged.add(ref.objectNumber);
      if (_isSubtype(cos, dict, 'Redact')) continue;
      session.addText(cos.resolve(dict['Contents']));
      if (_isSubtype(cos, dict, 'Widget')) _purgeWidgetField(dict, session);
    }
    if (annotationsChanged) _markAnnotations([pageIndex], visual: false);
    return true;
  }

  /// The annotations a burn removes, mapped to their /Annots entries:
  /// every /Redact, every annotation whose /Rect touches a region, and -
  /// transitively - popups (/Parent) and replies (/IRT) of removed ones.
  Map<CosDictionary, CosObject> _annotationsToRedact(
      CosArray annots, List<PdfRect> regions) {
    final cos = document.cos;
    final removed = Map<CosDictionary, CosObject>.identity();
    for (final item in annots.items) {
      final d = cos.resolve(item);
      if (d is! CosDictionary) continue;
      final r = pdfRectFrom(cos, d['Rect']);
      if (_isSubtype(cos, d, 'Redact') ||
          (r != null && _rectTouchesAny(r, regions))) {
        removed[d] = item;
      }
    }
    var grew = removed.isNotEmpty;
    while (grew) {
      grew = false;
      for (final item in annots.items) {
        final d = cos.resolve(item);
        if (d is! CosDictionary || removed.containsKey(d)) continue;
        final parent = cos.resolve(d['Parent']);
        final irt = cos.resolve(d['IRT']);
        if ((_isSubtype(cos, d, 'Popup') && removed.containsKey(parent)) ||
            removed.containsKey(irt)) {
          removed[d] = item;
          grew = true;
        }
      }
    }
    return removed;
  }

  /// Takes a removed widget's field out of the form: the widget's own
  /// field data (merged field), then every ancestor left with no other
  /// kid. A field that still has a widget elsewhere keeps its value - it is
  /// visible there, outside any redaction.
  void _purgeWidgetField(CosDictionary widget, _RedactionSession session) {
    final cos = document.cos;
    session
      ..formFieldsRemoved = true
      ..addText(cos.resolve(widget['V']));
    CosDictionary child = widget;
    var parent = cos.resolve(widget['Parent']);
    var guard = 0;
    while (parent is CosDictionary && guard++ < 64) {
      final kids = cos.resolve(parent['Kids']);
      if (kids is CosArray) {
        final others = kids.items.where((k) {
          if (k is CosReference && session.purged.contains(k.objectNumber)) {
            return false;
          }
          return !identical(cos.resolve(k), child);
        });
        if (others.isNotEmpty) return;
      }
      final ref = cos.referenceTo(parent);
      if (ref == null) return;
      session
        ..purged.add(ref.objectNumber)
        ..addText(cos.resolve(parent['V']));
      child = parent;
      parent = cos.resolve(parent['Parent']);
    }
  }

  /// Removes or scrubs the places outside page content that can repeat the
  /// redacted text: document info, XMP, bookmarks, structure-tree alternate
  /// text, attachments, XFA form data and document JavaScript.
  void _scrubHiddenCopies(
      _RedactionSession session, bool removeHiddenInformation) {
    final cos = document.cos;
    final scrubber = _RedactionScrubber.of(session.texts);

    final info = cos.resolve(cos.trailer['Info']);
    if (info is CosDictionary) {
      if (removeHiddenInformation) {
        info.entries.removeWhere((key, _) =>
            !const {'Producer', 'CreationDate', 'ModDate'}.contains(key));
      }
      if (scrubber != null) _scrubStrings(info, info.entries.keys, scrubber);
      _touch(info);
    }

    final catalog = cos.resolve(cos.trailer['Root']);
    if (catalog is! CosDictionary) return;
    final names = cos.resolve(catalog['Names']);
    if (removeHiddenInformation) {
      catalog.entries.remove('Metadata');
      catalog.entries.remove('PieceInfo');
      catalog.entries.remove('AA');
      final open = cos.resolve(catalog['OpenAction']);
      if (open is CosDictionary) {
        final s = cos.resolve(open['S']);
        if (s is CosName && s.value == 'JavaScript') {
          catalog.entries.remove('OpenAction');
        }
      }
      if (names is CosDictionary) {
        names.entries.remove('EmbeddedFiles');
        names.entries.remove('JavaScript');
        _touch(names);
      }
      for (final i in session.burnedPages) {
        document.page(i).dict.entries.remove('Metadata');
      }
    } else if (scrubber != null) {
      _scrubXmp(catalog, scrubber);
      for (final i in session.burnedPages) {
        _scrubXmp(document.page(i).dict, scrubber);
      }
      if (names is CosDictionary) {
        _filterNameTree(
            names['EmbeddedFiles'],
            (spec) => _attachmentMentions(spec, scrubber),
            Set<CosDictionary>.identity());
      }
    }

    // the XFA packet duplicates every field value
    final acroForm = cos.resolve(catalog['AcroForm']);
    if (acroForm is CosDictionary &&
        (session.formFieldsRemoved || removeHiddenInformation) &&
        acroForm.entries.remove('XFA') != null) {
      _touch(acroForm);
    }

    if (scrubber != null) {
      _scrubOutlines(catalog, scrubber);
      _scrubStructTree(catalog, scrubber);
    }
    _touch(catalog);
  }

  /// Marks a mutated object changed when it was loaded from the file.
  void _touch(CosObject object) {
    if (document.cos.referenceTo(object) != null) _updater.markChanged(object);
  }

  /// Replaces redacted text inside the string values of [dict] at [keys].
  void _scrubStrings(
      CosDictionary dict, Iterable<String> keys, _RedactionScrubber scrubber) {
    for (final key in keys.toList()) {
      final value = document.cos.resolve(dict[key]);
      if (value is! CosString) continue;
      final scrubbed = scrubber.scrub(_decodeTextString(value));
      if (scrubbed != null) dict[key] = CosString.fromText(scrubbed);
    }
  }

  /// Rewrites [owner]'s /Metadata XMP stream with redacted text replaced.
  void _scrubXmp(CosDictionary owner, _RedactionScrubber scrubber) {
    final cos = document.cos;
    final stream = cos.resolve(owner['Metadata']);
    if (stream is! CosStream) return;
    String xml;
    try {
      xml = utf8.decode(cos.decodeStreamData(stream), allowMalformed: true);
    } on Object {
      owner.entries.remove('Metadata'); // unreadable: can't vouch for it
      _touch(owner);
      return;
    }
    final scrubbed = scrubber.scrub(xml);
    if (scrubbed == null) return;
    final bytes = Uint8List.fromList(utf8.encode(scrubbed));
    owner['Metadata'] = _updater.addObject(CosStream(
      CosDictionary({
        'Type': const CosName('Metadata'),
        'Subtype': const CosName('XML'),
        'Length': CosInteger(bytes.length),
      }),
      bytes,
    ));
    _touch(owner);
  }

  /// Whether a file specification's name, description or embedded bytes
  /// contain redacted text.
  bool _attachmentMentions(CosObject spec, _RedactionScrubber scrubber) {
    final cos = document.cos;
    final d = cos.resolve(spec);
    if (d is! CosDictionary) return false;
    for (final key in const ['F', 'UF', 'Desc']) {
      final s = cos.resolve(d[key]);
      if (s is CosString && scrubber.matches(_decodeTextString(s))) return true;
    }
    final ef = cos.resolve(d['EF']);
    if (ef is CosDictionary) {
      for (final value in ef.entries.values) {
        final file = cos.resolve(value);
        if (file is! CosStream) continue;
        try {
          final bytes = cos.decodeStreamData(file);
          if (scrubber.matches(latin1.decode(bytes)) ||
              scrubber.matches(utf8.decode(bytes, allowMalformed: true))) {
            return true;
          }
        } on Object {
          return true; // undecodable: can't vouch for it
        }
      }
    }
    return false;
  }

  /// Drops the name-tree entries under [node] whose value [drop] accepts.
  void _filterNameTree(CosObject? node, bool Function(CosObject value) drop,
      Set<CosDictionary> visited) {
    final cos = document.cos;
    final n = cos.resolve(node);
    if (n is! CosDictionary || visited.length > 4096 || !visited.add(n)) {
      return;
    }
    final names = cos.resolve(n['Names']);
    if (names is CosArray) {
      final kept = <CosObject>[];
      for (var i = 0; i + 1 < names.items.length; i += 2) {
        if (drop(names.items[i + 1])) continue;
        kept
          ..add(names.items[i])
          ..add(names.items[i + 1]);
      }
      if (kept.length != names.items.length) {
        n['Names'] = CosArray(kept);
        _touch(n);
      }
    }
    final kids = cos.resolve(n['Kids']);
    if (kids is CosArray) {
      for (final kid in kids.items) {
        _filterNameTree(kid, drop, visited);
      }
    }
  }

  /// Replaces redacted text in bookmark titles, and drops a bookmark's
  /// link action when its URI carries it.
  void _scrubOutlines(CosDictionary catalog, _RedactionScrubber scrubber) {
    final cos = document.cos;
    final root = cos.resolve(catalog['Outlines']);
    if (root is! CosDictionary) return;
    final visited = Set<CosDictionary>.identity();
    final stack = <CosObject>[cos.resolve(root['First'])];
    while (stack.isNotEmpty && visited.length < 100000) {
      final item = stack.removeLast();
      if (item is! CosDictionary || !visited.add(item)) continue;
      final before = item['Title'];
      _scrubStrings(item, const ['Title'], scrubber);
      var changed = !identical(before, item['Title']);
      final action = cos.resolve(item['A']);
      if (action is CosDictionary) {
        final uri = cos.resolve(action['URI']);
        if (uri is CosString && scrubber.matches(latin1.decode(uri.bytes))) {
          item.entries.remove('A');
          changed = true;
        }
      }
      if (changed) _touch(item);
      stack
        ..add(cos.resolve(item['Next']))
        ..add(cos.resolve(item['First']));
    }
  }

  /// Replaces redacted text in structure elements' alternate descriptions,
  /// replacement text, expansions and titles.
  void _scrubStructTree(CosDictionary catalog, _RedactionScrubber scrubber) {
    final cos = document.cos;
    final root = cos.resolve(catalog['StructTreeRoot']);
    if (root is! CosDictionary) return;
    final visited = Set<CosDictionary>.identity();
    final stack = <CosObject>[cos.resolve(root['K'])];
    while (stack.isNotEmpty && visited.length < 500000) {
      final node = stack.removeLast();
      if (node is CosArray) {
        for (final kid in node.items) {
          stack.add(cos.resolve(kid));
        }
        continue;
      }
      if (node is! CosDictionary || !visited.add(node)) continue;
      final before = [for (final k in _structTextKeys) node[k]];
      _scrubStrings(node, _structTextKeys, scrubber);
      for (var i = 0; i < _structTextKeys.length; i++) {
        if (!identical(before[i], node[_structTextKeys[i]])) {
          _touch(node);
          break;
        }
      }
      stack.add(cos.resolve(node['K']));
    }
  }

  static const _structTextKeys = ['ActualText', 'Alt', 'E', 'T'];

  /// Purges the image/form XObjects a burn stopped drawing when nothing
  /// else in the document draws them either - a resource dictionary that
  /// merely still names one (an inherited /Resources, a sibling page
  /// sharing the dictionary) would otherwise keep it in the saved file.
  void _purgeUndrawnXObjects(_RedactionSession session) {
    if (session.retired.isEmpty) return;
    final drawn = _drawnXObjectNumbers();
    for (final number in session.retired) {
      if (!drawn.contains(number)) session.purged.add(number);
    }
  }

  /// Object numbers of every XObject a page, form, pattern, Type 3 glyph,
  /// soft mask or annotation appearance in the document actually draws.
  Set<int> _drawnXObjectNumbers() {
    final cos = document.cos;
    final drawn = <int>{};
    final walked = Set<CosObject>.identity();

    late final void Function(Uint8List, CosDictionary, int) walk;

    void walkStream(CosStream stream, CosDictionary fallback, int depth) {
      if (depth > 32 || !walked.add(stream)) return;
      final res = cos.resolve(stream.dictionary['Resources']);
      final Uint8List data;
      try {
        data = cos.decodeStreamData(stream);
      } on Object {
        return; // no viewer can draw it either
      }
      walk(data, res is CosDictionary ? res : fallback, depth);
    }

    void walkResources(CosDictionary resources, int depth) {
      final patterns = cos.resolve(resources['Pattern']);
      if (patterns is CosDictionary) {
        for (final p in patterns.entries.values) {
          final pattern = cos.resolve(p);
          if (pattern is CosStream) walkStream(pattern, resources, depth + 1);
        }
      }
      final states = cos.resolve(resources['ExtGState']);
      if (states is CosDictionary) {
        for (final s in states.entries.values) {
          final state = cos.resolve(s);
          if (state is! CosDictionary) continue;
          final mask = cos.resolve(state['SMask']);
          if (mask is! CosDictionary) continue;
          final group = cos.resolve(mask['G']);
          if (group is CosStream) walkStream(group, resources, depth + 1);
        }
      }
      final fonts = cos.resolve(resources['Font']);
      if (fonts is CosDictionary) {
        for (final f in fonts.entries.values) {
          final font = cos.resolve(f);
          if (font is! CosDictionary || !_isSubtype(cos, font, 'Type3')) {
            continue;
          }
          final fontRes = cos.resolve(font['Resources']);
          final procs = cos.resolve(font['CharProcs']);
          if (procs is! CosDictionary) continue;
          for (final proc in procs.entries.values) {
            final glyph = cos.resolve(proc);
            if (glyph is CosStream) {
              walkStream(glyph, fontRes is CosDictionary ? fontRes : resources,
                  depth + 1);
            }
          }
        }
      }
    }

    walk = (content, resources, depth) {
      if (depth > 32) return;
      final List<ContentOperation> ops;
      try {
        ops = ContentStreamParser.parse(content);
      } on Object {
        return;
      }
      final xobjects = cos.resolve(resources['XObject']);
      for (final op in ops) {
        if (op.operator != 'Do' || xobjects is! CosDictionary) continue;
        final name = op.operands.isEmpty ? null : op.operands.first;
        if (name is! CosName) continue;
        final entry = xobjects[name.value];
        if (entry is CosReference) drawn.add(entry.objectNumber);
        final x = cos.resolve(entry);
        if (x is CosStream && _isSubtype(cos, x.dictionary, 'Form')) {
          walkStream(x, resources, depth + 1);
        }
      }
      walkResources(resources, depth);
    };

    for (var i = 0; i < document.pageCount; i++) {
      final page = document.page(i);
      walk(page.contentBytes(), page.resources, 0);
      final annots = cos.resolve(page.dict['Annots']);
      if (annots is! CosArray) continue;
      for (final item in annots.items) {
        final annot = cos.resolve(item);
        if (annot is! CosDictionary) continue;
        final ap = cos.resolve(annot['AP']);
        if (ap is! CosDictionary) continue;
        for (final value in ap.entries.values) {
          final appearance = cos.resolve(value);
          if (appearance is CosStream) {
            walkStream(appearance, CosDictionary(), 1);
          } else if (appearance is CosDictionary) {
            for (final state in appearance.entries.values) {
              final s = cos.resolve(state);
              if (s is CosStream) walkStream(s, CosDictionary(), 1);
            }
          }
        }
      }
    }
    return drawn;
  }

  /// Reads the redaction regions of one `/Redact` dictionary: one rect per
  /// /QuadPoints group, falling back to /Rect.
  List<_Redaction> _redactionsFrom(CosDocument cos, CosDictionary dict) {
    final fillColor = _rgbFromArray(cos, dict['IC']) ?? 0x000000;
    String? overlayText;
    final ot = cos.resolve(dict['OverlayText']);
    if (ot is CosString) overlayText = _decodeTextString(ot);
    final da = cos.resolve(dict['DA']);
    final daText = da is CosString ? latin1.decode(da.bytes) : null;

    final rects = <PdfRect>[];
    final quads = cos.resolve(dict['QuadPoints']);
    if (quads is CosArray && quads.length >= 8) {
      final v = <double>[];
      for (final n in quads.items) {
        final r = cos.resolve(n);
        v.add(
          r is CosInteger
              ? r.value.toDouble()
              : r is CosReal
                  ? r.value
                  : 0,
        );
      }
      for (var i = 0; i + 7 < v.length; i += 8) {
        final xs = [v[i], v[i + 2], v[i + 4], v[i + 6]];
        final ys = [v[i + 1], v[i + 3], v[i + 5], v[i + 7]];
        rects.add(
          PdfRect(
            xs.reduce(math.min),
            ys.reduce(math.min),
            xs.reduce(math.max),
            ys.reduce(math.max),
          ),
        );
      }
    }
    if (rects.isEmpty) {
      final r = pdfRectFrom(cos, dict['Rect']);
      if (r != null) rects.add(r);
    }
    return [
      for (final r in rects) _Redaction(r, fillColor, overlayText, daText),
    ];
  }

  /// Content that paints each redaction's /IC fill and optional overlay
  /// text. Appended after the (burned) original content, so it covers the
  /// now-empty area opaquely.
  Uint8List _redactionFillContent(PdfPage page, List<_Redaction> redactions) {
    final out = BytesBuilder();
    var fontResource = '';
    for (final r in redactions) {
      final w = ContentWriter()
        ..save()
        ..fillColor(r.fillColor)
        ..rect(r.rect.left, r.rect.bottom, r.rect.width, r.rect.height)
        ..fill();
      if (r.overlayText != null && r.overlayText!.isNotEmpty) {
        if (fontResource.isEmpty) fontResource = _ensureHelvOnPage(page);
        final color = _overlayColorOf(r.daText, 0xFFFFFF);
        final size = _overlaySizeOf(r.daText, 12);
        final textWidth = measureHelvetica(r.overlayText!, size);
        final tx = r.rect.left + (r.rect.width - textWidth) / 2;
        final ty = r.rect.bottom + (r.rect.height - size) / 2 + size * 0.2;
        w
          ..beginText()
          ..font(fontResource, size)
          ..fillColor(color)
          ..textAt(math.max(tx, r.rect.left + 1), ty)
          ..showText(r.overlayText!)
          ..endText();
      }
      w.restore();
      out.add(w.takeBytes());
    }
    return out.takeBytes();
  }

  /// Ensures a base-14 Helvetica font (`/RHelv`) lives in the page's own
  /// /Font resources and returns its name, for overlay text.
  String _ensureHelvOnPage(PdfPage page) {
    final cos = document.cos;
    final resources = _materializeResources(page);
    final fontsRaw = resources['Font'];
    final fonts = cos.resolve(fontsRaw);
    final dict = fonts is CosDictionary && fontsRaw is! CosReference
        ? fonts
        : CosDictionary({if (fonts is CosDictionary) ...fonts.entries});
    resources['Font'] = dict;
    const name = 'RHelv';
    dict[name] = CosDictionary({
      'Type': const CosName('Font'),
      'Subtype': const CosName('Type1'),
      'BaseFont': const CosName('Helvetica'),
      'Encoding': const CosName('WinAnsiEncoding'),
    });
    return name;
  }

  /// The page's own /Resources, copied when inherited or shared by
  /// reference (mutating an ancestor's would bleed into sibling pages).
  CosDictionary _materializeResources(PdfPage page) {
    final cos = document.cos;
    final direct = page.dict['Resources'];
    final resolved = cos.resolve(direct);
    if (resolved is CosDictionary && direct is! CosReference) return resolved;
    final copy = CosDictionary({
      if (resolved is CosDictionary)
        ...resolved.entries
      else
        ...page.resources.entries,
    });
    page.dict['Resources'] = copy;
    _updater.markChanged(page.dict);
    return copy;
  }

  int? _rgbFromArray(CosDocument cos, CosObject? value) {
    final array = cos.resolve(value);
    if (array is! CosArray || array.length == 0) return null;
    double comp(int i) {
      final n = cos.resolve(array[i]);
      return n is CosInteger
          ? n.value.toDouble()
          : n is CosReal
              ? n.value
              : 0;
    }

    if (array.length >= 3) {
      return ((comp(0) * 255).round() << 16) |
          ((comp(1) * 255).round() << 8) |
          (comp(2) * 255).round();
    }
    final g = (comp(0) * 255).round();
    return (g << 16) | (g << 8) | g;
  }

  String _decodeTextString(CosString s) => _redactionTextOf(s);

  int _overlayColorOf(String? da, int fallback) {
    if (da == null) return fallback;
    final m = RegExp(r'([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+rg').firstMatch(da);
    if (m == null) return fallback;
    int c(int g) => ((double.tryParse(m.group(g)!) ?? 0) * 255).round() & 0xFF;
    return (c(1) << 16) | (c(2) << 8) | c(3);
  }

  double _overlaySizeOf(String? da, double fallback) {
    if (da == null) return fallback;
    final m = RegExp(r'/\S+\s+([\d.]+)\s+Tf').firstMatch(da);
    if (m == null) return fallback;
    final s = double.tryParse(m.group(1)!) ?? fallback;
    return s > 0 ? s : fallback;
  }

  /// True when [rect] overlaps one of [regions] (a zero-area rect counts
  /// when it lies inside one).
  static bool _rectTouchesAny(PdfRect rect, List<PdfRect> regions) {
    for (final region in regions) {
      if (rect.left <= region.right &&
          rect.right >= region.left &&
          rect.bottom <= region.top &&
          rect.top >= region.bottom &&
          (rect.left < region.right || rect.width == 0) &&
          (rect.right > region.left || rect.width == 0) &&
          (rect.bottom < region.top || rect.height == 0) &&
          (rect.top > region.bottom || rect.height == 0)) {
        return true;
      }
    }
    return false;
  }
}

/// A PDF text string (UTF-16BE with BOM, UTF-8 with BOM, else
/// PDFDocEncoding read as Latin-1) as Dart text.
String _redactionTextOf(CosString s) {
  final b = s.bytes;
  if (b.length >= 2 && b[0] == 0xFE && b[1] == 0xFF) {
    final out = StringBuffer();
    for (var i = 2; i + 1 < b.length; i += 2) {
      out.writeCharCode((b[i] << 8) | b[i + 1]);
    }
    return out.toString();
  }
  if (b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) {
    return utf8.decode(b.sublist(3), allowMalformed: true);
  }
  return latin1.decode(b);
}

/// State shared by every page (and nested form) of one burn.
class _RedactionSession {
  /// Object numbers dropped from the saved file even where still referenced.
  final Set<int> purged = {};

  /// XObjects some burn stopped drawing; purged unless drawn elsewhere.
  final Set<int> retired = {};

  /// The text that was removed, for scrubbing hidden copies of it.
  final List<String> texts = [];

  final List<int> burnedPages = [];
  bool formFieldsRemoved = false;

  void addText(CosObject value) {
    if (value is CosString) texts.add(_redactionTextOf(value));
  }
}

/// Finds and replaces the redacted text in strings outside page content.
///
/// Each removed span becomes a case-insensitive pattern in which runs of
/// whitespace are optional (so `123-45-6701` matches `123 - 45 - 6701` and
/// a value that lost its spaces). Each word of a span - a run of letters
/// and digits, keeping inner `-./@_+` so numbers, dates and addresses stay
/// whole - of four or more characters is also a pattern of its own, matched
/// on word boundaries: a box over "SSN 123-45-6701" must still scrub a
/// title holding only "123-45-6701". Hidden places lose a little too much
/// text rather than keep any. Shorter fragments are ignored so a redacted
/// digit or initial doesn't strip every occurrence of it.
class _RedactionScrubber {
  _RedactionScrubber._(this._pattern);

  final RegExp _pattern;

  static const replacement = '[redacted]';

  static final _word = RegExp(
      r'[\p{L}\p{N}](?:[\p{L}\p{N}\-./@_+]*[\p{L}\p{N}])?',
      unicode: true);

  static String _flexible(String text) => [
        for (final r in text.runes) RegExp.escape(String.fromCharCode(r)),
      ].join(r'\s*');

  static _RedactionScrubber? of(Iterable<String> texts) {
    final seen = <String>{};
    final sources = <(int, String)>[];
    void add(String key, int weight, String source) {
      if (seen.add(key)) sources.add((weight, source));
    }

    for (final text in texts) {
      final compact = text.replaceAll(RegExp(r'\s+'), '');
      if (compact.runes.length >= 3) {
        add('s:${compact.toLowerCase()}', compact.length, _flexible(compact));
      }
      for (final m in _word.allMatches(text)) {
        final word = m.group(0)!;
        if (word.runes.length < 4) continue;
        add('w:${word.toLowerCase()}', word.length,
            '(?<![\\p{L}\\p{N}])${_flexible(word)}(?![\\p{L}\\p{N}])');
      }
    }
    if (sources.isEmpty) return null;
    // longest first, so a span wins over one of its own words
    sources.sort((a, b) => b.$1.compareTo(a.$1));
    return _RedactionScrubber._(RegExp(sources.map((s) => s.$2).join('|'),
        caseSensitive: false, unicode: true));
  }

  bool matches(String text) => _pattern.hasMatch(text);

  /// [text] with every redacted span replaced, or null when none occurs.
  String? scrub(String text) {
    if (!_pattern.hasMatch(text)) return null;
    return text.replaceAll(_pattern, replacement);
  }
}

/// One redaction region with its fill style.
class _Redaction {
  _Redaction(this.rect, this.fillColor, this.overlayText, this.daText);

  final PdfRect rect;
  final int fillColor;
  final String? overlayText;
  final String? daText;
}

/// An open marked-content sequence whose property list carries text
/// (`/ActualText`, `/Alt`, `/E`) - stripped when content inside it is
/// redacted.
class _RedMarkedContent {
  _RedMarkedContent(this.part, this.op);

  /// Index of the BDC operator's own piece in [_RedactionBurn._parts].
  final int part;
  final ContentOperation op;
  bool stripped = false;
}

/// Walks a content stream and rewrites it with the glyphs, images and form
/// content that fall inside any redaction [regions] removed - the
/// content-stream surgery half of a redaction burn.
///
/// [_ctm] starts at the matrix the stream is drawn under (identity for a
/// page, the form matrix times the invoking CTM for a form XObject), so
/// region tests always happen in default user space.
class _RedactionBurn {
  _RedactionBurn(
    this._cos,
    this._resources,
    this._regions,
    this._session,
    this._addObject, {
    _RedMatrix ctm = _redIdentity,
    _RedactionBurn? parent,
  })  : _ctm = ctm,
        _parent = parent,
        _depth = parent == null ? 0 : parent._depth + 1 {
    if (parent != null) {
      _tfs = parent._tfs;
      _tc = parent._tc;
      _tw = parent._tw;
      _th = parent._th;
      _tl = parent._tl;
      _trise = parent._trise;
      _fontName = parent._fontName;
    }
  }

  final CosDocument _cos;
  final CosDictionary _resources;
  final List<PdfRect> _regions;
  final _RedactionSession _session;
  final CosReference Function(CosObject) _addObject;
  final _RedactionBurn? _parent;
  final int _depth;

  static const _maxFormDepth = 16;

  final Map<String, _RedFont?> _fontCache = {};

  /// Whether anything was removed from this stream (or a form it draws).
  bool changed = false;

  // XObject bookkeeping for [rebuiltResources]
  final Set<String> _used = {};
  final Map<String, CosObject> _retired = {};
  final Map<String, CosObject> _added = {};

  // output: pieces, so a BDC already written can still be stripped
  final List<Uint8List> _parts = [];
  final BytesBuilder _out = BytesBuilder();
  final List<_RedMarkedContent?> _marked = [];

  // the text removed since the last kept glyph or text positioning
  final StringBuffer _span = StringBuffer();

  // graphics state
  _RedMatrix _ctm;
  final List<_RedGraphicsState> _gsStack = [];

  // text state (the q/Q-saved parameters live in _RedGraphicsState)
  _RedMatrix _tm = _redIdentity;
  _RedMatrix _tlm = _redIdentity;
  double _tfs = 0;
  double _tc = 0;
  double _tw = 0;
  double _th = 1;
  double _tl = 0;
  double _trise = 0;
  String? _fontName;

  Uint8List run(Uint8List content) {
    final ops = ContentStreamParser.parse(content);
    for (final op in ops) {
      _handle(op);
    }
    _flushSpan();
    _parts.add(_out.takeBytes());
    final all = BytesBuilder(copy: false);
    for (final part in _parts) {
      all.add(part);
    }
    return all.takeBytes();
  }

  /// The resource dictionary the rewritten stream needs, or null when the
  /// original serves unchanged: dropped/replaced XObjects no longer drawn
  /// are gone, and replacements are added under fresh names.
  CosDictionary? rebuiltResources() {
    if (_added.isEmpty && _retired.isEmpty) return null;
    final x = _cos.resolve(_resources['XObject']);
    final xobjects = CosDictionary({if (x is CosDictionary) ...x.entries});
    for (final name in _retired.keys) {
      if (!_used.contains(name)) xobjects.entries.remove(name);
    }
    xobjects.entries.addAll(_added);
    return CosDictionary({..._resources.entries, 'XObject': xobjects});
  }

  double _n(CosObject o) => switch (o) {
        CosInteger(:final value) => value.toDouble(),
        CosReal(:final value) => value,
        _ => 0,
      };

  void _handle(ContentOperation op) {
    final operands = op.operands;
    switch (op.operator) {
      case 'q':
        _gsStack.add(
          _RedGraphicsState(_ctm, _tfs, _tc, _tw, _th, _tl, _trise, _fontName),
        );
      case 'Q':
        if (_gsStack.isNotEmpty) {
          final s = _gsStack.removeLast();
          _ctm = s.ctm;
          _tfs = s.tfs;
          _tc = s.tc;
          _tw = s.tw;
          _th = s.th;
          _tl = s.tl;
          _trise = s.trise;
          _fontName = s.fontName;
        }
      case 'cm':
        if (operands.length >= 6) {
          _ctm = _redMul((
            _n(operands[0]),
            _n(operands[1]),
            _n(operands[2]),
            _n(operands[3]),
            _n(operands[4]),
            _n(operands[5]),
          ), _ctm);
        }
      case 'BT':
        _flushSpan();
        _tm = _redIdentity;
        _tlm = _redIdentity;
      case 'ET':
        _flushSpan();
      case 'Tf':
        if (operands.length >= 2) {
          _fontName =
              operands[0] is CosName ? (operands[0] as CosName).value : null;
          _tfs = _n(operands[1]);
        }
      case 'Tc':
        if (operands.isNotEmpty) _tc = _n(operands[0]);
      case 'Tw':
        if (operands.isNotEmpty) _tw = _n(operands[0]);
      case 'Tz':
        if (operands.isNotEmpty) _th = _n(operands[0]) / 100;
      case 'TL':
        if (operands.isNotEmpty) _tl = _n(operands[0]);
      case 'Ts':
        if (operands.isNotEmpty) _trise = _n(operands[0]);
      case 'Td':
        _flushSpan();
        if (operands.length >= 2) {
          _tlm = _redMul((1, 0, 0, 1, _n(operands[0]), _n(operands[1])), _tlm);
          _tm = _tlm;
        }
      case 'TD':
        _flushSpan();
        if (operands.length >= 2) {
          _tl = -_n(operands[1]);
          _tlm = _redMul((1, 0, 0, 1, _n(operands[0]), _n(operands[1])), _tlm);
          _tm = _tlm;
        }
      case 'Tm':
        _flushSpan();
        if (operands.length >= 6) {
          _tm = (
            _n(operands[0]),
            _n(operands[1]),
            _n(operands[2]),
            _n(operands[3]),
            _n(operands[4]),
            _n(operands[5]),
          );
          _tlm = _tm;
        }
      case 'T*':
        _flushSpan();
        _tlm = _redMul((1, 0, 0, 1, 0, -_tl), _tlm);
        _tm = _tlm;
      case 'Tj' || 'TJ':
        _showText(op);
        return;
      case "'":
        _flushSpan();
        _tlm = _redMul((1, 0, 0, 1, 0, -_tl), _tlm);
        _tm = _tlm;
        _showText(op, prefix: 'T*\n');
        return;
      case '"':
        _flushSpan();
        if (operands.length >= 3) {
          _tw = _n(operands[0]);
          _tc = _n(operands[1]);
        }
        _tlm = _redMul((1, 0, 0, 1, 0, -_tl), _tlm);
        _tm = _tlm;
        _showText(
          op,
          prefix: '${ContentWriter.fmt(_tw)} Tw '
              '${ContentWriter.fmt(_tc)} Tc T*\n',
        );
        return;
      case 'Do':
        _handleDo(op);
        return;
      case 'BI':
        // an inline image touching a region goes whole: they are small, and
        // splitting their samples would need the abbreviated-name decoding
        if (_rectIntersectsAny(_unitSquareBounds(_ctm))) {
          _removed();
          return;
        }
      case 'BMC':
        _marked.add(null);
      case 'BDC':
        final props = operands.length >= 2 ? operands[1] : null;
        if (props is CosDictionary && _markedTextKeys.any(props.containsKey)) {
          _parts.add(_out.takeBytes());
          _marked.add(_RedMarkedContent(_parts.length, op));
          final piece = BytesBuilder();
          ContentStreamSerializer.writeOperation(op, piece);
          _parts.add(piece.takeBytes());
          return;
        }
        _marked.add(null);
      case 'EMC':
        if (_marked.isNotEmpty) _marked.removeLast();
    }
    _writeOp(op);
  }

  static const _markedTextKeys = ['ActualText', 'Alt', 'E'];

  /// Records that content was removed here: strips the replacement and
  /// alternate text of every enclosing marked-content sequence, which
  /// would otherwise still spell out what was removed.
  void _removed() {
    changed = true;
    for (final frame in _marked) {
      if (frame == null || frame.stripped) continue;
      frame.stripped = true;
      final props = frame.op.operands[1] as CosDictionary;
      final stripped = CosDictionary({...props.entries});
      for (final key in _markedTextKeys) {
        stripped.entries.remove(key);
      }
      final piece = BytesBuilder();
      ContentStreamSerializer.writeOperation(
          ContentOperation('BDC', [frame.op.operands[0], stripped]), piece);
      _parts[frame.part] = piece.takeBytes();
    }
  }

  void _flushSpan() {
    if (_span.isEmpty) return;
    _session.texts.add(_span.toString());
    _span.clear();
  }

  void _handleDo(ContentOperation op) {
    final name = op.operands.isNotEmpty && op.operands.first is CosName
        ? (op.operands.first as CosName).value
        : null;
    final xobjects = _cos.resolve(_resources['XObject']);
    final entry =
        name != null && xobjects is CosDictionary ? xobjects[name] : null;
    final xobject = _cos.resolve(entry);
    if (name == null || entry == null || xobject is! CosStream) {
      _writeOp(op);
      return;
    }

    final isForm = _isForm(xobject);
    final drawCtm = isForm ? _redMul(_formMatrix(xobject), _ctm) : _ctm;
    PdfRect? bounds;
    if (isForm) {
      final bbox = pdfRectFrom(_cos, xobject.dictionary['BBox']);
      if (bbox != null) {
        bounds = _hullBounds([
          _redApply(drawCtm, bbox.left, bbox.bottom),
          _redApply(drawCtm, bbox.right, bbox.bottom),
          _redApply(drawCtm, bbox.left, bbox.top),
          _redApply(drawCtm, bbox.right, bbox.top),
        ]);
      }
    } else {
      bounds = _unitSquareBounds(_ctm);
    }
    // a form without a /BBox has no known extent: burn it to find out
    if (bounds != null && !_rectIntersectsAny(bounds)) {
      _keepDo(op, name);
      return;
    }
    if (bounds != null && _boundsFullyCovered(bounds)) {
      _retire(name, entry);
      _removed();
      return; // drop
    }

    final CosStream? replacement;
    if (isForm) {
      final (formChanged, burned) = _burnForm(xobject, drawCtm);
      if (!formChanged) {
        _keepDo(op, name);
        return;
      }
      replacement = burned;
    } else {
      final redacted = _redactImage(xobject, _ctm);
      if (identical(redacted, xobject)) {
        _keepDo(op, name);
        return;
      }
      replacement = redacted;
    }
    _retire(name, entry);
    _removed();
    if (replacement == null) return; // couldn't be rewritten: dropped whole
    final fresh = _freshName(xobjects is CosDictionary ? xobjects : null);
    _added[fresh] = _addObject(replacement);
    _used.add(fresh);
    _writeOp(ContentOperation('Do', [CosName(fresh)]));
  }

  void _keepDo(ContentOperation op, String name) {
    _used.add(name);
    _writeOp(op);
  }

  void _retire(String name, CosObject entry) {
    _retired[name] = entry;
    if (entry is CosReference) _session.retired.add(entry.objectNumber);
  }

  String _freshName(CosDictionary? existing) {
    var i = _added.length;
    while (true) {
      final name = 'RdX${++i}';
      if (existing?.containsKey(name) != true && !_added.containsKey(name)) {
        return name;
      }
    }
  }

  bool _isForm(CosStream xobject) {
    final subtype = _cos.resolve(xobject.dictionary['Subtype']);
    return subtype is CosName && subtype.value == 'Form';
  }

  _RedMatrix _formMatrix(CosStream form) {
    final m = _cos.resolve(form.dictionary['Matrix']);
    if (m is! CosArray || m.length < 6) return _redIdentity;
    double at(int i) => _n(_cos.resolve(m[i]));
    return (at(0), at(1), at(2), at(3), at(4), at(5));
  }

  /// Burns a form XObject drawn under [drawCtm] into a fresh copy. Returns
  /// `(false, _)` when nothing in it was covered, `(true, null)` when it
  /// must be dropped whole (undecodable, or nested too deep to follow).
  (bool, CosStream?) _burnForm(CosStream form, _RedMatrix drawCtm) {
    if (_depth >= _maxFormDepth) return (true, null);
    final Uint8List content;
    try {
      content = _cos.decodeStreamData(form);
    } on Object {
      return (true, null);
    }
    final ownResources = _cos.resolve(form.dictionary['Resources']);
    final nested = _RedactionBurn(
      _cos,
      ownResources is CosDictionary ? ownResources : _resources,
      _regions,
      _session,
      _addObject,
      ctm: drawCtm,
      parent: this,
    );
    final Uint8List burned;
    try {
      burned = nested.run(content);
    } on Object {
      return (true, null);
    }
    if (!nested.changed) return (false, null);
    final dict = CosDictionary({...form.dictionary.entries});
    for (final key in _rewrittenStreamKeys) {
      dict.entries.remove(key);
    }
    final resources = nested.rebuiltResources();
    if (resources != null) dict['Resources'] = resources;
    dict['Length'] = CosInteger(burned.length);
    return (true, CosStream(dict, burned));
  }

  /// Stream keys a rewritten copy must not carry over: the old encoding,
  /// and private data describing the original.
  static const _rewrittenStreamKeys = [
    'Filter',
    'DecodeParms',
    'DP',
    'Length',
    'DL',
    'F',
    'FFilter',
    'FDecodeParms',
    'Metadata',
    'PieceInfo',
  ];

  /// [image] drawn under [ctm] with the pixels under any region cleared,
  /// re-encoded with Flate. Returns [image] itself when no pixel is under a
  /// region, and null when the samples can't be decoded or rewritten -
  /// the caller then drops the image whole (removing too much beats
  /// leaking).
  CosStream? _redactImage(CosStream image, _RedMatrix ctm) {
    try {
      return _redactImageSamples(image, ctm);
    } on Object {
      return null;
    }
  }

  CosStream? _redactImageSamples(CosStream image, _RedMatrix ctm) {
    final dict = image.dictionary;
    final width = _int(dict['Width']);
    final height = _int(dict['Height']);
    if (width <= 0 || height <= 0 || width * height > 200000000) return null;

    // the pixel box each region covers (rows from the top)
    final inverse = _redInvert(ctm);
    if (inverse == null) return null;
    final boxes = <(int, int, int, int)>[];
    for (final region in _regions) {
      final corners = [
        _redApply(inverse, region.left, region.bottom),
        _redApply(inverse, region.right, region.bottom),
        _redApply(inverse, region.left, region.top),
        _redApply(inverse, region.right, region.top),
      ];
      final hull = _hullBounds(corners)!;
      final x0 = (hull.left * width).floor().clamp(0, width);
      final x1 = (hull.right * width).ceil().clamp(0, width);
      final y0 = ((1 - hull.top) * height).floor().clamp(0, height);
      final y1 = ((1 - hull.bottom) * height).ceil().clamp(0, height);
      if (x0 < x1 && y0 < y1) boxes.add((x0, y0, x1, y1));
    }
    if (boxes.isEmpty) return image;

    final isMask = _cos.resolve(dict['ImageMask']) is CosBoolean &&
        (_cos.resolve(dict['ImageMask']) as CosBoolean).value;
    final components = isMask ? 1 : _componentCount(dict['ColorSpace']);
    if (components == null) return null;
    var bits = isMask ? 1 : _int(dict['BitsPerComponent'], fallback: 8);
    if (!const {1, 2, 4, 8, 16}.contains(bits)) return null;

    final filters = _filterNames(dict['Filter']);
    final Uint8List samples;
    if (filters.contains('JPXDecode')) {
      return null;
    } else if (filters.isNotEmpty && filters.last == 'DCTDecode') {
      final decoded = _decodeJpegSamples(image, width, height, components);
      if (decoded == null) return null;
      samples = decoded;
      bits = 8;
    } else if (filters.contains('JBIG2Decode')) {
      if (filters.last != 'JBIG2Decode') return null;
      final params = _filterParams(dict, filters.length - 1);
      final globalsStream =
          params == null ? null : _cos.resolve(params['JBIG2Globals']);
      final decoded = Jbig2Decoder.decode(
        data: _cos.decodeStreamData(image, stopBeforeFilter: 'JBIG2Decode'),
        globals: globalsStream is CosStream
            ? _cos.decodeStreamData(globalsStream)
            : null,
        width: width,
        height: height,
      );
      if (decoded == null) return null;
      samples = decoded;
    } else {
      samples = _cos.decodeStreamData(image);
    }

    final rowBytes = (width * components * bits + 7) >> 3;
    if (samples.length < rowBytes * height) return null;
    // a copy: decoded bytes may be the document's cached decode
    final data = Uint8List.fromList(
        Uint8List.sublistView(samples, 0, rowBytes * height));
    final bitsPerPixel = components * bits;
    for (final (x0, y0, x1, y1) in boxes) {
      for (var y = y0; y < y1; y++) {
        _clearBits(data, y * rowBytes, x0 * bitsPerPixel, x1 * bitsPerPixel);
      }
    }

    final out = CosDictionary({...dict.entries});
    for (final key in _rewrittenStreamKeys) {
      out.entries.remove(key);
    }
    if (!isMask) out['BitsPerComponent'] = CosInteger(bits);
    // the soft mask and stencil mask carry the same picture's shape
    for (final key in const ['SMask', 'Mask']) {
      final mask = _cos.resolve(dict[key]);
      if (mask is! CosStream) continue;
      final redacted = _redactImageSamples(mask, ctm);
      if (redacted == null) return null;
      if (!identical(redacted, mask)) out[key] = _addObject(redacted);
    }
    final payload =
        Uint8List.fromList(const ZLibEncoder().encodeBytes(data, level: 6));
    out['Filter'] = const CosName('FlateDecode');
    out['Length'] = CosInteger(payload.length);
    return CosStream(out, payload);
  }

  /// The 8-bit samples of a DCT-encoded [image], or null when the JPEG's
  /// shape disagrees with the dictionary or can't be reproduced as plain
  /// samples (CMYK/YCCK, EXIF rotation, explicit /ColorTransform).
  Uint8List? _decodeJpegSamples(
      CosStream image, int width, int height, int components) {
    if (components != 1 && components != 3) return null;
    final filters = _filterNames(image.dictionary['Filter']);
    if (_filterParams(image.dictionary, filters.length - 1) != null) {
      return null;
    }
    final bytes = _cos.decodeStreamData(image, stopBeforeFilter: 'DCTDecode');
    final decoder = imaging.JpegDecoder();
    final info = decoder.startDecode(bytes);
    if (info == null ||
        info.width != width ||
        info.height != height ||
        decoder.info!.numComponents != components) {
      return null;
    }
    final orientation = imaging.decodeJpgExif(bytes)?.imageIfd.orientation;
    if (orientation != null && orientation != 1) return null;
    final pixels = decoder.decodeFrame(0);
    if (pixels == null) return null;
    return pixels.getBytes(
        order: components == 1
            ? imaging.ChannelOrder.red
            : imaging.ChannelOrder.rgb);
  }

  /// Clears bits [startBit, endBit) of the row starting at [rowStart].
  static void _clearBits(
      Uint8List data, int rowStart, int startBit, int endBit) {
    var b = startBit;
    while (b < endBit) {
      if (b & 7 == 0 && b + 8 <= endBit) {
        data[rowStart + (b >> 3)] = 0;
        b += 8;
      } else {
        data[rowStart + (b >> 3)] &= ~(0x80 >> (b & 7)) & 0xFF;
        b++;
      }
    }
  }

  int? _componentCount(CosObject? colorSpace) {
    final cs = _cos.resolve(colorSpace);
    String? family;
    if (cs is CosName) family = cs.value;
    if (cs is CosArray && cs.length > 0) {
      final head = _cos.resolve(cs[0]);
      if (head is CosName) family = head.value;
    }
    switch (family) {
      case 'DeviceGray' || 'G' || 'CalGray' || 'Indexed' || 'I' || 'Separation':
        return 1;
      case 'DeviceRGB' || 'RGB' || 'CalRGB' || 'Lab':
        return 3;
      case 'DeviceCMYK' || 'CMYK':
        return 4;
      case 'ICCBased':
        final stream =
            cs is CosArray && cs.length > 1 ? _cos.resolve(cs[1]) : null;
        if (stream is! CosStream) return null;
        final n = _int(stream.dictionary['N']);
        return n > 0 ? n : null;
      case 'DeviceN':
        final names =
            cs is CosArray && cs.length > 1 ? _cos.resolve(cs[1]) : null;
        return names is CosArray && names.length > 0 ? names.length : null;
    }
    return null;
  }

  List<String> _filterNames(CosObject? filter) {
    final f = _cos.resolve(filter);
    if (f is CosName) return [f.value];
    if (f is CosArray) {
      return [
        for (final item in f.items)
          if (_cos.resolve(item) case CosName(:final value)) value,
      ];
    }
    return const [];
  }

  CosDictionary? _filterParams(CosDictionary dict, int index) {
    final p = _cos.resolve(dict['DecodeParms'] ?? dict['DP']);
    if (p is CosDictionary) return index == 0 ? p : null;
    if (p is CosArray && index < p.length) {
      final r = _cos.resolve(p[index]);
      return r is CosDictionary ? r : null;
    }
    return null;
  }

  int _int(CosObject? value, {int fallback = 0}) {
    final v = _cos.resolve(value);
    if (v is CosInteger) return v.value;
    if (v is CosReal) return v.value.round();
    return fallback;
  }

  void _showText(ContentOperation op, {String prefix = ''}) {
    // Pull the (string | adjustment) elements out of the operator.
    final elements = <Object>[]; // CosString or double (TJ adjustment)
    if (op.operator == 'TJ' && op.operands.isNotEmpty) {
      final array = op.operands.first;
      if (array is CosArray) {
        for (final item in array.items) {
          if (item is CosString) {
            elements.add(item);
          } else if (item is CosInteger || item is CosReal) {
            elements.add(_n(item));
          }
        }
      }
    } else if (op.operator == '"' && op.operands.length >= 3) {
      if (op.operands[2] is CosString) elements.add(op.operands[2]);
    } else if (op.operands.isNotEmpty && op.operands.first is CosString) {
      elements.add(op.operands.first);
    }

    final font = _font(_fontName);
    final codeLength = font != null && font.isComposite ? 2 : 1;

    // Removes the whole operator, keeping the line state it would set.
    void dropWhole() {
      _removed();
      for (final element in elements) {
        if (element is! CosString) continue;
        final bytes = element.bytes;
        for (var i = 0; i + codeLength <= bytes.length; i += codeLength) {
          final code =
              codeLength == 2 ? (bytes[i] << 8) | bytes[i + 1] : bytes[i];
          _span.write(font?.textOf(code) ?? '');
        }
      }
      _flushSpan();
      if (prefix.isNotEmpty) _out.add(latin1.encode(prefix));
    }

    // Composite fonts whose code length we can't know without the CMap:
    // don't try to split - drop the whole op if it touches a region, else
    // keep verbatim. Identity-H (two-byte codes) splits per glyph below.
    if (font != null && font.isComposite && !font.isIdentityH) {
      final bounds = _compositeBounds(elements, font);
      if (bounds != null && _rectIntersectsAny(bounds)) {
        _advanceComposite(elements, font); // keep Tm in sync
        dropWhole();
        return;
      }
      _advanceComposite(elements, font);
      _writeOp(op);
      return;
    }
    if (_tfs == 0 || _th == 0) {
      // no measurable size: every glyph sits on the current point. Still
      // extractable text (an invisible layer), so a point inside a region
      // takes the operator.
      if (_glyphCovered(0)) {
        dropWhole();
        return;
      }
      _writeOp(op);
      return;
    }

    // Walk glyph by glyph, building a TJ array with covered glyphs removed
    // and replaced by a numeric gap so survivors keep their position.
    final rebuilt = <Object>[]; // CosString | double
    final current = BytesBuilder();
    var currentHex = false;
    var redactedAny = false;
    double pendingGap = 0; // accumulated removed advance (text-space points)

    void flushString() {
      if (current.length > 0) {
        rebuilt.add(CosString(current.takeBytes(), isHex: currentHex));
      }
    }

    void flushGap() {
      if (pendingGap != 0) {
        // displacement = -num/1000 * tfs * th  ⇒  num = -gap*1000/(tfs*th)
        rebuilt.add(-pendingGap * 1000 / (_tfs * _th));
        pendingGap = 0;
      }
    }

    for (final element in elements) {
      if (element is double) {
        // existing TJ adjustment: advances the cursor, carry it through
        final disp = -element / 1000 * _tfs * _th;
        if (current.length > 0) {
          flushString();
        }
        // fold into the gap stream so spacing survives either way; both are
        // forward advances, so a kern keeps its direction when re-emitted
        pendingGap += disp;
        _tm = _redMul((1, 0, 0, 1, disp, 0), _tm);
        continue;
      }
      final string = element as CosString;
      final bytes = string.bytes;
      for (var i = 0; i + codeLength <= bytes.length; i += codeLength) {
        final code =
            codeLength == 2 ? (bytes[i] << 8) | bytes[i + 1] : bytes[i];
        final w0 = font?.widthOf(code) ?? 500; // glyph units
        final glyphWidth = w0 / 1000 * _tfs * _th;
        // word spacing applies to the single-byte code 32 only (§9.3.3)
        final wordSpace = codeLength == 1 && code == 32 ? _tw : 0;
        final advance = (w0 / 1000 * _tfs + _tc + wordSpace) * _th;

        final covered = _glyphCovered(glyphWidth);
        if (covered) {
          redactedAny = true;
          flushString();
          pendingGap += advance;
          _span.write(font?.textOf(code) ?? '');
        } else {
          _flushSpan();
          flushGap();
          if (current.length > 0 && currentHex != string.isHex) {
            flushString();
          }
          currentHex = string.isHex;
          current.add(Uint8List.sublistView(bytes, i, i + codeLength));
        }
        _tm = _redMul((1, 0, 0, 1, advance, 0), _tm);
      }
    }

    if (!redactedAny) {
      // nothing covered: re-emit the original operator unchanged (it moves
      // to the next line itself, so no prefix).
      _writeOp(op);
      return;
    }
    _removed();
    if (prefix.isNotEmpty) _out.add(latin1.encode(prefix));
    flushString();
    flushGap();

    if (rebuilt.isEmpty) {
      // everything was removed: emit nothing (but Tm already advanced).
      return;
    }
    _out.add(latin1.encode('['));
    for (final piece in rebuilt) {
      if (piece is CosString) {
        _out.add(CosSerializer.serialize(piece));
      } else {
        _out.add(latin1.encode(ContentWriter.fmt(piece as double)));
      }
      _out.addByte(0x20);
    }
    _out.add(latin1.encode('] TJ\n'));
  }

  /// True when the glyph occupying [glyphWidth] text-space points from the
  /// current text position lies under a redaction region.
  ///
  /// The test runs along the glyph's body - a line through it at
  /// [_glyphBodyHeight] of the font size above the baseline - rather than
  /// its full em box. The em box (descent to a full em up) overhangs the
  /// visible glyph by a good fraction of a line, so on ordinary leading a
  /// box drawn over one line reached into the line below and took glyphs
  /// that were never under it (#1162). Along the line the glyph must be
  /// covered by more than [_minCoveredFraction] of its advance, so a
  /// neighbour that only grazes a box edge (selection rounding) stays.
  bool _glyphCovered(double glyphWidth) {
    final m = _redMul(_tm, _ctm);
    final y = _trise + _glyphBodyHeight * _tfs;
    final (x0, y0) = _redApply(m, 0, y);
    final (x1, y1) = _redApply(m, glyphWidth, y);
    for (final region in _regions) {
      // a zero-advance glyph is a point: 1 when inside, 0 when not
      if (_coveredFraction(x0, y0, x1, y1, region) > _minCoveredFraction) {
        return true;
      }
    }
    return false;
  }

  /// Where a glyph's body sits, as a fraction of the font size above the
  /// baseline: mid x-height to mid cap-height for Latin text.
  static const double _glyphBodyHeight = 0.3;

  /// How much of a glyph's advance a region must cover to remove it.
  static const double _minCoveredFraction = 0.1;

  /// The fraction (0..1) of the segment (x0,y0)-(x1,y1) inside [r]
  /// (Liang-Barsky clipping).
  static double _coveredFraction(
      double x0, double y0, double x1, double y1, PdfRect r) {
    final dx = x1 - x0, dy = y1 - y0;
    var t0 = 0.0, t1 = 1.0;
    for (final (p, q) in [
      (-dx, x0 - r.left),
      (dx, r.right - x0),
      (-dy, y0 - r.bottom),
      (dy, r.top - y0),
    ]) {
      if (p == 0) {
        if (q < 0) return 0; // parallel to this edge and outside it
        continue;
      }
      final t = q / p;
      if (p < 0) {
        if (t > t1) return 0;
        if (t > t0) t0 = t;
      } else {
        if (t < t0) return 0;
        if (t < t1) t1 = t;
      }
    }
    return t1 - t0;
  }

  /// Conservative bounds of a composite run we can't split: along the
  /// glyph bodies for horizontal writing, plus a column straight down the
  /// run's length for a vertical (`-V`) CMap.
  PdfRect? _compositeBounds(List<Object> elements, _RedFont font) {
    var minX = double.infinity,
        minY = double.infinity,
        maxX = -double.infinity,
        maxY = -double.infinity;
    var cursor = 0.0;
    final m = _redMul(_tm, _ctm);
    void include((double, double) p) {
      final (x, y) = p;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }

    for (final element in elements) {
      if (element is double) {
        cursor += -element / 1000 * _tfs * _th;
        continue;
      }
      final string = element as CosString;
      final glyphs = string.bytes.length ~/ 2;
      for (var i = 0; i < glyphs; i++) {
        final gw = font.defaultWidth / 1000 * _tfs * _th;
        // along the glyph body, as [_glyphCovered] tests it
        final body = _trise + _glyphBodyHeight * _tfs;
        include(_redApply(m, cursor, body));
        include(_redApply(m, cursor + gw, body));
        cursor += gw + _tc * _th;
      }
    }
    if (minX > maxX) return null;
    if (font.isVertical) {
      // vertical glyphs hang below the origin, centred on it
      include(_redApply(m, -_tfs, _tfs));
      include(_redApply(m, _tfs, -cursor - _tfs));
    }
    return PdfRect(minX, minY, maxX, maxY);
  }

  void _advanceComposite(List<Object> elements, _RedFont font) {
    var advance = 0.0;
    for (final element in elements) {
      if (element is double) {
        advance += -element / 1000 * _tfs * _th;
        continue;
      }
      final string = element as CosString;
      final glyphs = string.bytes.length ~/ 2;
      advance += glyphs * (font.defaultWidth / 1000 * _tfs + _tc) * _th;
    }
    _tm = _redMul((1, 0, 0, 1, advance, 0), _tm);
  }

  _RedFont? _font(String? name) {
    if (name == null) return null;
    return _fontCache.putIfAbsent(name, () {
      final fonts = _cos.resolve(_resources['Font']);
      final font = fonts is CosDictionary ? _cos.resolve(fonts[name]) : null;
      // a form showing text in the font its invoker set
      if (font is! CosDictionary) return _parent?._font(name);
      return _RedFont.from(_cos, font);
    });
  }

  bool _rectIntersectsAny(PdfRect rect) {
    for (final region in _regions) {
      if (rect.left < region.right &&
          rect.right > region.left &&
          rect.bottom < region.top &&
          rect.top > region.bottom) {
        return true;
      }
    }
    return false;
  }

  bool _boundsFullyCovered(PdfRect rect) {
    for (final region in _regions) {
      if (rect.left >= region.left &&
          rect.right <= region.right &&
          rect.bottom >= region.bottom &&
          rect.top <= region.top) {
        return true;
      }
    }
    return false;
  }

  PdfRect _unitSquareBounds(_RedMatrix ctm) => _hullBounds([
        _redApply(ctm, 0, 0),
        _redApply(ctm, 1, 0),
        _redApply(ctm, 0, 1),
        _redApply(ctm, 1, 1),
      ])!;

  /// Re-serializes [op] verbatim (mirrors [PdfPageElements.serialize]).
  void _writeOp(ContentOperation op) {
    ContentStreamSerializer.writeOperation(op, _out);
  }
}

/// The glyph metrics (and text) a redaction burn needs from one font.
class _RedFont {
  _RedFont._(
    this.isComposite,
    this._firstChar,
    this._widths,
    this._fallback,
    this.defaultWidth,
    this._text, {
    this.isIdentityH = false,
    this.isVertical = false,
    this.widthScale = 1,
    Map<int, double>? cidWidths,
  }) : _cidWidths = cidWidths;

  final bool isComposite;

  /// A composite font with the `/Identity-H` CMap: every code is two bytes
  /// and is its own CID, so /W widths apply to it directly.
  final bool isIdentityH;

  /// A composite font with a vertical (`-V`) CMap.
  final bool isVertical;
  final Map<int, double>? _cidWidths; // composite /W, by CID
  final int _firstChar;
  final List<double>? _widths; // glyph units (1000/em), simple fonts
  final List<int> _fallback; // base-14 table for missing widths
  final double defaultWidth; // composite /DW or simple miss default

  /// /Widths units to thousandths of text space: 1 except for Type 3
  /// fonts, whose widths are in glyph space (`/FontMatrix`).
  final double widthScale;
  final String Function(int code) _text;

  /// The Unicode text [code] stands for, best effort ('' when unknown).
  String textOf(int code) {
    try {
      return _text(code);
    } on Object {
      return '';
    }
  }

  static _RedFont from(CosDocument cos, CosDictionary font) {
    final subtype = cos.resolve(font['Subtype']);
    final isType0 = subtype is CosName && subtype.value == 'Type0';
    final baseFont = cos.resolve(font['BaseFont']);
    final baseName = baseFont is CosName ? baseFont.value : '';
    final fallback = _fallbackTable(baseName);

    if (isType0) {
      var dw = 1000.0;
      var widths = <int, double>{};
      final descendants = cos.resolve(font['DescendantFonts']);
      if (descendants is CosArray && descendants.length > 0) {
        final d = cos.resolve(descendants.items.first);
        if (d is CosDictionary) {
          dw = cidDefaultWidth(cos, d);
          widths = parseCidWidths(cos, d);
        }
      }
      final encoding = cos.resolve(font['Encoding']);
      final encodingName = encoding is CosName ? encoding.value : '';
      Map<int, String> toUnicode;
      try {
        toUnicode = Type0Font.decode(cos, font).codeToText;
      } on Object {
        toUnicode = const {};
      }
      return _RedFont._(
        true,
        0,
        null,
        fallback,
        dw,
        (code) => toUnicode[code] ?? '',
        isIdentityH: encodingName == 'Identity-H',
        isVertical: encodingName.endsWith('-V'),
        cidWidths: widths,
      );
    }

    var scale = 1.0;
    if (subtype is CosName && subtype.value == 'Type3') {
      final matrix = cos.resolve(font['FontMatrix']);
      if (matrix is CosArray && matrix.length > 0) {
        final a = switch (cos.resolve(matrix[0])) {
          CosInteger(:final value) => value.toDouble(),
          CosReal(:final value) => value,
          _ => 0.001,
        };
        if (a != 0) scale = a.abs() * 1000;
      }
    }
    final firstCharObj = cos.resolve(font['FirstChar']);
    final firstChar = firstCharObj is CosInteger ? firstCharObj.value : 0;
    final widthsObj = cos.resolve(font['Widths']);
    List<double>? widths;
    if (widthsObj is CosArray) {
      widths = [
        for (final w in widthsObj.items)
          switch (cos.resolve(w)) {
            CosInteger(:final value) => value.toDouble(),
            CosReal(:final value) => value,
            _ => 0.0,
          },
      ];
    }
    String Function(int) text;
    try {
      text = SimpleFont.decode(cos, font).textFor;
    } on Object {
      text =
          (code) => code >= 32 && code < 127 ? String.fromCharCode(code) : '';
    }
    return _RedFont._(false, firstChar, widths, fallback, 500, text,
        widthScale: scale);
  }

  static List<int> _fallbackTable(String baseFont) {
    final n = baseFont.toLowerCase();
    if (n.contains('times') || n.contains('serif')) return timesRomanWidths;
    if (n.contains('bold')) return helveticaBoldWidths;
    return helveticaWidths;
  }

  /// Advance width of [code] in glyph units (1000/em).
  double widthOf(int code) {
    final cidWidths = _cidWidths;
    if (cidWidths != null) return cidWidths[code] ?? defaultWidth;
    final widths = _widths;
    if (widths != null) {
      final i = code - _firstChar;
      if (i >= 0 && i < widths.length) {
        final w = widths[i];
        if (w > 0) return w * widthScale;
      }
    }
    if (code >= 32 && code <= 126) return _fallback[code - 32].toDouble();
    return defaultWidth;
  }
}

class _RedGraphicsState {
  _RedGraphicsState(
    this.ctm,
    this.tfs,
    this.tc,
    this.tw,
    this.th,
    this.tl,
    this.trise,
    this.fontName,
  );

  final _RedMatrix ctm;
  final double tfs;
  final double tc;
  final double tw;
  final double th;
  final double tl;
  final double trise;
  final String? fontName;
}

typedef _RedMatrix = (double, double, double, double, double, double);

const _RedMatrix _redIdentity = (1, 0, 0, 1, 0, 0);

_RedMatrix _redMul(_RedMatrix m, _RedMatrix n) => (
      m.$1 * n.$1 + m.$2 * n.$3,
      m.$1 * n.$2 + m.$2 * n.$4,
      m.$3 * n.$1 + m.$4 * n.$3,
      m.$3 * n.$2 + m.$4 * n.$4,
      m.$5 * n.$1 + m.$6 * n.$3 + n.$5,
      m.$5 * n.$2 + m.$6 * n.$4 + n.$6,
    );

(double, double) _redApply(_RedMatrix m, double x, double y) =>
    (m.$1 * x + m.$3 * y + m.$5, m.$2 * x + m.$4 * y + m.$6);

_RedMatrix? _redInvert(_RedMatrix m) {
  final det = m.$1 * m.$4 - m.$2 * m.$3;
  if (det == 0 || !det.isFinite) return null;
  final a = m.$4 / det, b = -m.$2 / det, c = -m.$3 / det, d = m.$1 / det;
  return (a, b, c, d, -(m.$5 * a + m.$6 * c), -(m.$5 * b + m.$6 * d));
}

PdfRect? _hullBounds(List<(double, double)> points) {
  if (points.isEmpty) return null;
  var minX = points.first.$1, maxX = points.first.$1;
  var minY = points.first.$2, maxY = points.first.$2;
  for (final (x, y) in points) {
    if (x < minX) minX = x;
    if (x > maxX) maxX = x;
    if (y < minY) minY = y;
    if (y > maxY) maxY = y;
  }
  return PdfRect(minX, minY, maxX, maxY);
}
