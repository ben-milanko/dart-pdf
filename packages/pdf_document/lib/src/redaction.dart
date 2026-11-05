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
    final substitutes = _retireOriginals(session);
    _markDestructive(pages);
    return _compactedSave(
      session.purged,
      substitutes: substitutes,
      stripHidden: removeHiddenInformation,
      scrubber: _RedactionScrubber.of(session.texts),
    );
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
  /// References to a [substitutes] key point at its value instead: every
  /// remaining use of a redacted original - another page, an invisible
  /// draw, a pattern - gets the redacted copy.
  ///
  /// With [stripHidden], hidden information goes wherever it sits: every
  /// /AF, /Metadata, /PieceInfo and /Thumb entry, every embedded file
  /// (/EF, /RF) and every JavaScript action. With a [scrubber], every
  /// string left in the file has the redacted text replaced - document
  /// info, bookmarks, comments, field values, page labels, name-tree keys,
  /// structure text, wherever a copy sits.
  Uint8List _compactedSave(
    Set<int> purged, {
    Map<int, CosReference> substitutes = const {},
    bool stripHidden = false,
    _RedactionScrubber? scrubber,
  }) {
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

    /// Where a reference really points after substitution, or null when
    /// the object is purged.
    CosReference? target(CosReference ref) {
      var current = ref;
      var guard = 0;
      while (substitutes.containsKey(current.objectNumber) && guard++ < 64) {
        current = substitutes[current.objectNumber]!;
      }
      return purged.contains(current.objectNumber) ? null : current;
    }

    bool deadObjr(CosDictionary d) {
      final type = d['Type'];
      final obj = d['Obj'];
      return type is CosName &&
          type.value == 'OBJR' &&
          obj is CosReference &&
          target(obj) == null;
    }

    bool hiddenAction(CosDictionary d) {
      if (!stripHidden) return false;
      final s = d['S'];
      return d.containsKey('JS') || (s is CosName && s.value == 'JavaScript');
    }

    bool dead(CosObject value) {
      if (value is CosReference) {
        if (target(value) == null) return true;
        final resolved = cos.resolve(target(value));
        return resolved is CosDictionary &&
            (deadObjr(resolved) || hiddenAction(resolved));
      }
      return value is CosDictionary && (deadObjr(value) || hiddenAction(value));
    }

    const hiddenKeys = {'AF', 'Metadata', 'PieceInfo', 'Thumb', 'EF', 'RF'};
    bool keep(String key) => !stripHidden || !hiddenKeys.contains(key);

    void discover(CosObject node) {
      if (node is! CosReference) return;
      final t = target(node);
      if (t == null || newNumber.containsKey(t.objectNumber)) return;
      newNumber[t.objectNumber] = order.length + 1;
      generation[t.objectNumber] = t.generation;
      order.add(t.objectNumber);
      queue.add(t.objectNumber);
    }

    void scan(CosObject node) {
      switch (node) {
        case CosArray():
          for (final item in node.items) {
            if (dead(item)) continue;
            item is CosReference ? discover(item) : scan(item);
          }
        case CosDictionary():
          node.entries.forEach((key, value) {
            if (!keep(key) || dead(value)) return;
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
          final t = target(node);
          final n = t == null ? null : newNumber[t.objectNumber];
          return n != null ? CosReference(n, 0) : CosNull.instance;
        case CosArray():
          return CosArray([
            for (final item in node.items)
              if (!dead(item)) remap(item),
          ]);
        case CosDictionary():
          final out = CosDictionary();
          node.entries.forEach((key, value) {
            if (keep(key) && !dead(value)) out[key] = remap(value);
          });
          return out;
        case CosStream():
          final dict = remap(node.dictionary) as CosDictionary
            ..['Length'] = CosInteger(node.rawBytes.length);
          return CosStream(dict, node.rawBytes);
        case CosString():
          if (scrubber == null) return node;
          final scrubbed = scrubber.scrub(_redactionTextOf(node));
          return scrubbed == null ? node : CosString.fromText(scrubbed);
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
    final info = infoRef is CosReference ? target(infoRef) : null;
    return builder.build(
      root: CosReference(newNumber[rootRef.objectNumber]!, 0),
      info: info != null && newNumber.containsKey(info.objectNumber)
          ? CosReference(newNumber[info.objectNumber]!, 0)
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
    //    from the form XObjects, images, patterns and soft masks it draws).
    final original = page.contentBytes();
    final structParents = cos.resolve(page.dict['StructParents']);
    final burn = _RedactionBurn(
      cos,
      page.resources,
      regions,
      session,
      _updater.addObject,
      structParents: structParents is CosInteger ? structParents.value : null,
    );
    final burned = burn.run(original);
    final resources = burn.rebuiltResources();
    if (resources != null) {
      // the page's own copy: an inherited or shared dictionary may still
      // serve pages that draw the originals
      page.dict['Resources'] = resources;
    }
    // the original content streams go unless another page shows them
    final contents = page.dict['Contents'];
    if (contents is CosReference) {
      session.oldContents.add(contents.objectNumber);
    }
    final contentArray = cos.resolve(contents);
    if (contentArray is CosArray) {
      for (final item in contentArray.items) {
        if (item is CosReference) session.oldContents.add(item.objectNumber);
      }
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
    //    field value is what the rect is meant to hide), with the popups,
    //    popup owners and replies that belong to them.
    final removed = _annotationsToRedact(annots, regions);
    final annotationsChanged = _PdfPageAnnotationList(this, pageIndex)
        .removeWhere((_, resolved) => removed.containsKey(resolved));
    for (final MapEntry(key: dict, value: item) in removed.entries) {
      _purgeAnnotation(dict, item, session);
    }
    if (annotationsChanged) _markAnnotations([pageIndex], visual: false);
    return true;
  }

  /// Purges a removed annotation from the file and records what it said.
  void _purgeAnnotation(
      CosDictionary dict, CosObject? item, _RedactionSession session) {
    final cos = document.cos;
    final ref = item is CosReference ? item : cos.referenceTo(dict);
    if (ref != null) session.purged.add(ref.objectNumber);
    if (_isSubtype(cos, dict, 'Redact')) return;
    session.addText(cos.resolve(dict['Contents']));
    final sp = cos.resolve(dict['StructParent']);
    if (sp is CosInteger) session.removedStructParents.add(sp.value);
    if (_isSubtype(cos, dict, 'Widget')) _purgeWidgetField(dict, session);
  }

  /// The annotations a burn removes, mapped to their /Annots entries:
  /// every /Redact, every annotation whose /Rect touches a region, and -
  /// transitively - popups (/Parent) and replies (/IRT) of removed ones,
  /// and the annotation whose open popup a region covers (the popup shows
  /// its /Contents).
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
        final popup = cos.resolve(d['Popup']);
        if ((_isSubtype(cos, d, 'Popup') && removed.containsKey(parent)) ||
            removed.containsKey(irt) ||
            removed.containsKey(popup)) {
          removed[d] = item;
          grew = true;
        }
      }
    }
    // a removed popup's owner listed on another page (or nowhere)
    for (final d in removed.keys.toList()) {
      if (!_isSubtype(cos, d, 'Popup')) continue;
      final parent = cos.resolve(d['Parent']);
      if (parent is CosDictionary && !removed.containsKey(parent)) {
        removed[parent] = d['Parent'] ?? CosNull.instance;
      }
    }
    return removed;
  }

  /// Takes a removed widget's field out of the form: the widget's own
  /// field data (merged field), then every ancestor left with no other
  /// *shown* widget, with everything under it. A field still shown by a
  /// widget elsewhere keeps its value - it is visible there, outside any
  /// redaction - but hidden, zero-size or unplaced siblings don't count:
  /// the box covered the only place the value appeared.
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
          final kid = cos.resolve(k);
          return !identical(kid, child) &&
              kid is CosDictionary &&
              _fieldShown(kid, session, 0);
        });
        if (others.isNotEmpty) return;
      }
      final ref = cos.referenceTo(parent);
      if (ref == null) return;
      _purgeFieldTree(parent, session, 0);
      child = parent;
      parent = cos.resolve(parent['Parent']);
    }
  }

  /// Whether [node] (a field or widget) is shown by some widget: listed on
  /// a page, not hidden, and with an area.
  bool _fieldShown(CosDictionary node, _RedactionSession session, int depth) {
    final cos = document.cos;
    if (depth > 32) return true;
    final kids = cos.resolve(node['Kids']);
    if (kids is CosArray) {
      return kids.items.any((k) {
        if (k is CosReference && session.purged.contains(k.objectNumber)) {
          return false;
        }
        final kid = cos.resolve(k);
        return kid is CosDictionary && _fieldShown(kid, session, depth + 1);
      });
    }
    final flags = cos.resolve(node['F']);
    if (flags is CosInteger && flags.value & (2 | 32) != 0) return false;
    final r = pdfRectFrom(cos, node['Rect']);
    if (r == null || r.width <= 0 || r.height <= 0) return false;
    // a widget off its page's crop box is nowhere a reader sees it
    final pageBox = session.listedAnnotations(document)[node];
    return pageBox != null && _rectTouchesAny(r, [pageBox]);
  }

  /// Purges [node] and every field and widget under it, recording values.
  void _purgeFieldTree(
      CosDictionary node, _RedactionSession session, int depth) {
    final cos = document.cos;
    if (depth > 32) return;
    final ref = cos.referenceTo(node);
    if (ref != null && !session.purged.add(ref.objectNumber) && depth > 0) {
      return;
    }
    session.addText(cos.resolve(node['V']));
    final sp = cos.resolve(node['StructParent']);
    if (sp is CosInteger) session.removedStructParents.add(sp.value);
    final kids = cos.resolve(node['Kids']);
    if (kids is CosArray) {
      for (final k in kids.items) {
        final kid = cos.resolve(k);
        if (kid is CosDictionary) _purgeFieldTree(kid, session, depth + 1);
      }
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
        document.page(i).dict.entries
          ..remove('Metadata')
          ..remove('AA');
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

    _stripStructTextOfRemoved(catalog, session);
    // named destinations spelled with the redacted text
    final dests = cos.resolve(catalog['Dests']);
    if (scrubber != null && dests is CosDictionary) {
      final before = dests.entries.length;
      dests.entries.removeWhere((key, _) => scrubber.matches(key));
      if (dests.entries.length != before) _touch(dests);
    }
    if (scrubber != null) {
      _scrubOutlines(catalog, scrubber);
      _scrubStructTree(catalog, scrubber);
    }
    _touch(catalog);
  }

  /// Strips /ActualText, /Alt and /E from the structure elements that own
  /// removed content (by /MCID through the /ParentTree, or an annotation's
  /// /StructParent), and from their ancestors, whose text spans it. These
  /// describe the content in words no glyph match finds - an image's alt
  /// text, replacement text for glyphs without /ToUnicode.
  void _stripStructTextOfRemoved(
      CosDictionary catalog, _RedactionSession session) {
    if (session.removedMcids.isEmpty && session.removedStructParents.isEmpty) {
      return;
    }
    final cos = document.cos;
    final root = cos.resolve(catalog['StructTreeRoot']);
    if (root is! CosDictionary) return;
    final parentTree = cos.resolve(root['ParentTree']);
    if (parentTree is! CosDictionary) return;
    final elements = Set<CosDictionary>.identity();
    session.removedMcids.forEach((key, mcids) {
      final entry = cos.resolve(_numberTreeLookup(parentTree, key, 0));
      if (entry is! CosArray) return;
      for (final mcid in mcids) {
        if (mcid < 0 || mcid >= entry.length) continue;
        final e = cos.resolve(entry[mcid]);
        if (e is CosDictionary) elements.add(e);
      }
    });
    for (final key in session.removedStructParents) {
      final e = cos.resolve(_numberTreeLookup(parentTree, key, 0));
      if (e is CosDictionary) elements.add(e);
    }
    final stripped = Set<CosDictionary>.identity();
    for (var e in elements) {
      var guard = 0;
      CosObject node = e;
      while (node is CosDictionary &&
          guard++ < 256 &&
          node.typeName != 'StructTreeRoot' &&
          stripped.add(node)) {
        var changed = false;
        for (final key in _PdfRedactionText.markedKeys) {
          changed = node.entries.remove(key) != null || changed;
        }
        if (changed) _touch(node);
        node = cos.resolve(node['P']);
      }
    }
  }

  /// The value under [key] in a number tree.
  CosObject? _numberTreeLookup(CosDictionary node, int key, int depth) {
    final cos = document.cos;
    if (depth > 32) return null;
    final nums = cos.resolve(node['Nums']);
    if (nums is CosArray) {
      for (var i = 0; i + 1 < nums.length; i += 2) {
        final k = cos.resolve(nums[i]);
        if (k is CosInteger && k.value == key) return nums[i + 1];
      }
    }
    final kids = cos.resolve(node['Kids']);
    if (kids is CosArray) {
      for (final kid in kids.items) {
        final k = cos.resolve(kid);
        if (k is! CosDictionary) continue;
        final found = _numberTreeLookup(k, key, depth + 1);
        if (found != null) return found;
      }
    }
    return null;
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

  /// Decides the fate of every resource a burn retired (XObjects,
  /// patterns, shadings, graphics states, property lists, soft-mask
  /// groups): one redacted copy replaces the original *everywhere* in the
  /// file; with none, or several differing copies, the original is purged.
  /// Any other use - a sibling page, an off-page or clipped draw, a hidden
  /// annotation's appearance - would otherwise keep the original's covered
  /// content in the file. Replaced content streams are purged unless a page
  /// still shows them.
  Map<int, CosReference> _retireOriginals(_RedactionSession session) {
    final cos = document.cos;
    final substitutes = <int, CosReference>{};
    for (final number in session.retired) {
      final copies = session.replacements[number];
      if (copies != null && copies.length == 1) {
        substitutes[number] = copies.single;
      } else {
        session.purged.add(number);
      }
    }
    if (session.oldContents.isNotEmpty) {
      final shown = <int>{};
      for (var i = 0; i < document.pageCount; i++) {
        final contents = document.page(i).dict['Contents'];
        if (contents is CosReference) shown.add(contents.objectNumber);
        final array = cos.resolve(contents);
        if (array is CosArray) {
          for (final item in array.items) {
            if (item is CosReference) shown.add(item.objectNumber);
          }
        }
      }
      for (final number in session.oldContents) {
        if (!shown.contains(number)) session.purged.add(number);
      }
    }
    return substitutes;
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

  /// Resources some burn stopped using; purged unless used elsewhere.
  final Set<int> retired = {};

  /// Content streams replaced by a burn; purged unless a page shows them.
  final Set<int> oldContents = {};

  /// The text that was removed, for scrubbing hidden copies of it.
  final List<String> texts = [];

  /// /MCIDs of removed content, by the /StructParents key they number under.
  final Map<int, Set<int>> removedMcids = {};

  /// /StructParent keys of removed annotations and fields.
  final Set<int> removedStructParents = {};

  final List<int> burnedPages = [];
  bool formFieldsRemoved = false;

  /// Form XObject burns so far, bounded so a hostile file of forms drawing
  /// forms can't make the burn run for ever.
  int formBurns = 0;
  static const maxFormBurns = 20000;

  /// Redacted copies made of each retired resource, by object number.
  final Map<int, List<CosReference>> replacements = {};

  Map<CosDictionary, PdfRect>? _listed;

  /// Every annotation dictionary listed in some page's /Annots, with that
  /// page's crop box.
  Map<CosDictionary, PdfRect> listedAnnotations(PdfDocument document) {
    final listed = _listed;
    if (listed != null) return listed;
    final cos = document.cos;
    final out = Map<CosDictionary, PdfRect>.identity();
    for (var i = 0; i < document.pageCount; i++) {
      final page = document.page(i);
      final annots = cos.resolve(page.dict['Annots']);
      if (annots is! CosArray) continue;
      for (final item in annots.items) {
        final d = cos.resolve(item);
        if (d is CosDictionary) out[d] = page.cropBox;
      }
    }
    return _listed = out;
  }

  void addText(CosObject value) {
    if (value is CosString) texts.add(_redactionTextOf(value));
  }
}

/// Text keys of marked-content property lists and structure elements.
abstract final class _PdfRedactionText {
  static const markedKeys = ['ActualText', 'Alt', 'E'];
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
