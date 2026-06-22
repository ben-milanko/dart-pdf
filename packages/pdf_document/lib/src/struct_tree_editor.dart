part of 'editor.dart';

/// Authoring and auto-tagging for the logical structure tree (§14.7) — the
/// write half of Tagged PDF — plus PDF/A conversion. Grouped in one extension
/// because PDF/A conversion reuses the XMP/metadata helpers below (Dart
/// extension members are not callable across separate extensions).
extension PdfTaggingAndArchival on PdfEditor {
  /// Marks the document tagged and writes a structure tree from [roots].
  ///
  /// Each [PdfStructSpec] becomes a /StructElem with its /S type, /Alt,
  /// /ActualText, /Lang and /T, tagging the marked content (its [PdfStructSpec.mcids]
  /// on page [PdfStructSpec.pageIndex]) and objects ([PdfStructSpec.objects],
  /// written as /OBJR) it lists. The marked content must already carry those
  /// /MCID values — [autoTag] writes both together; callers using this
  /// directly are responsible for emitting matching `/Tag <</MCID n>> BDC … EMC`.
  ///
  /// Also sets catalog /MarkInfo << /Marked true >>, document [lang] (when
  /// given), and — when [displayDocTitle] — /ViewerPreferences
  /// << /DisplayDocTitle true >> (required by PDF/UA so the title bar shows
  /// the document /Title rather than the file name). [roleMap] maps any custom
  /// structure types onto standard ones.
  void writeStructTree(
    List<PdfStructSpec> roots, {
    String? lang,
    bool displayDocTitle = true,
    Map<String, String> roleMap = const {},
  }) {
    final cos = document.cos;

    // Per page: the structure element owning each MCID, for the parent tree.
    final perPage = <int, Map<int, CosReference>>{};
    // Object StructParent key -> owning element; allocated after page keys.
    final objectOwners = <CosReference, CosReference>{};

    // Allocate a parent-tree key per page that actually carries content. The
    // page's own /StructParents uses that key; the entry is an MCID-indexed
    // array. Object keys come after, one per /OBJR target.
    final pagesWithContent = <int>{};
    void collectPages(PdfStructSpec spec) {
      if (spec.mcids.isNotEmpty) pagesWithContent.add(spec.pageIndex);
      for (final c in spec.children) {
        collectPages(c);
      }
    }

    for (final r in roots) {
      collectPages(r);
    }
    final sortedPages = pagesWithContent.toList()..sort();
    final pageKey = <int, int>{};
    var nextKey = 0;
    for (final p in sortedPages) {
      pageKey[p] = nextKey++;
    }

    CosReference rootRef = _updater.addObject(CosDictionary());

    CosReference buildElement(PdfStructSpec spec, CosReference parent) {
      final dict = CosDictionary({
        'Type': CosName('StructElem'),
        'S': CosName(spec.type),
        'P': parent,
      });
      final ref = _updater.addObject(dict);

      final pageRef = _pageReference(spec.pageIndex);
      if (pageRef != null && (spec.mcids.isNotEmpty || spec.objects.isNotEmpty)) {
        dict['Pg'] = pageRef;
      }
      if (spec.alt != null) dict['Alt'] = CosString.fromText(spec.alt!);
      if (spec.actualText != null) {
        dict['ActualText'] = CosString.fromText(spec.actualText!);
      }
      if (spec.lang != null) dict['Lang'] = CosString.fromText(spec.lang!);
      if (spec.title != null) dict['T'] = CosString.fromText(spec.title!);

      // /K, in reading order: this element's own marked content and object
      // references first, then child elements.
      final kids = <CosObject>[];
      final pageMap = perPage.putIfAbsent(spec.pageIndex, () => {});
      for (final mcid in spec.mcids) {
        kids.add(CosInteger(mcid));
        pageMap[mcid] = ref;
      }
      for (final obj in spec.objects) {
        final objr = CosDictionary({'Type': CosName('OBJR'), 'Obj': obj});
        if (pageRef != null) objr['Pg'] = pageRef;
        kids.add(objr);
        objectOwners[obj] = ref;
      }
      for (final child in spec.children) {
        kids.add(buildElement(child, ref));
      }
      dict['K'] = kids.length == 1 && spec.objects.isEmpty && spec.mcids.isEmpty
          ? kids.first
          : CosArray(kids);
      return ref;
    }

    final rootKids = [for (final r in roots) buildElement(r, rootRef)];

    // Assign a parent-tree key to each tagged object and stamp /StructParent.
    final objectKey = <CosReference, int>{};
    for (final obj in objectOwners.keys) {
      final key = nextKey++;
      objectKey[obj] = key;
      final resolved = cos.resolve(obj);
      if (resolved is CosDictionary) {
        resolved['StructParent'] = CosInteger(key);
        _updater.markChanged(resolved);
      }
    }

    // Build the /ParentTree number tree (/Nums sorted by key).
    final nums = <CosObject>[];
    for (final p in sortedPages) {
      final map = perPage[p] ?? const {};
      final maxMcid =
          map.keys.isEmpty ? -1 : map.keys.reduce((a, b) => a > b ? a : b);
      final arr = <CosObject>[
        for (var i = 0; i <= maxMcid; i++) map[i] ?? CosNull.instance,
      ];
      nums
        ..add(CosInteger(pageKey[p]!))
        ..add(CosArray(arr));
      // Stamp the page's /StructParents key.
      final pageDict = document.page(p).dict;
      pageDict['StructParents'] = CosInteger(pageKey[p]!);
      _updater.markChanged(pageDict);
    }
    final sortedObjects = objectKey.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    for (final e in sortedObjects) {
      nums
        ..add(CosInteger(e.value))
        ..add(objectOwners[e.key]!);
    }
    final parentTreeRef =
        _updater.addObject(CosDictionary({'Nums': CosArray(nums)}));

    // Fill the structure tree root.
    final rootDict = cos.resolve(rootRef) as CosDictionary;
    rootDict['Type'] = CosName('StructTreeRoot');
    rootDict['K'] =
        rootKids.length == 1 ? rootKids.first : CosArray([...rootKids]);
    rootDict['ParentTree'] = parentTreeRef;
    rootDict['ParentTreeNextKey'] = CosInteger(nextKey);
    if (roleMap.isNotEmpty) {
      rootDict['RoleMap'] = CosDictionary({
        for (final e in roleMap.entries) e.key: CosName(e.value),
      });
    }
    _updater.markChanged(rootDict);

    // Catalog wiring.
    final catalog = document.catalog;
    catalog['StructTreeRoot'] = rootRef;
    catalog['MarkInfo'] = CosDictionary({'Marked': const CosBoolean(true)});
    if (lang != null) catalog['Lang'] = CosString.fromText(lang);
    if (displayDocTitle) {
      final vp = cos.resolve(catalog['ViewerPreferences']);
      final vpDict = vp is CosDictionary ? vp : CosDictionary();
      vpDict['DisplayDocTitle'] = const CosBoolean(true);
      catalog['ViewerPreferences'] = vpDict;
    }
    _updater.markChanged(catalog);
  }

  /// Heuristically tags an untagged document: infers reading order and block
  /// roles from positioned text, wraps the content in marked content with
  /// /MCID, marks non-text painting as /Artifact, and writes a matching
  /// structure tree. Returns the number of structure elements created.
  ///
  /// This is intentionally approximate — PDFs carry no reading order. Text is
  /// grouped into visual lines and paragraphs; a line markedly larger than
  /// the page median becomes a heading (/H1 or /H2), a run of bullet/number
  /// lines becomes a list (/L → /LI → /LBody), everything else a paragraph
  /// (/P). Images, shadings and path fills become artifacts. The result is
  /// structurally valid Tagged PDF; semantic accuracy depends on the source.
  ///
  /// [title] sets the document /Title (PDF/UA wants a title shown via
  /// /DisplayDocTitle); [lang] the document language (default 'en-US'). When
  /// [writeUaMetadata] is true (the default) an XMP packet declaring
  /// pdfuaid:part = 1 and dc:title is written, so the result is a complete
  /// PDF/UA-1 candidate that the validator accepts.
  int autoTag(
      {String? title, String lang = 'en-US', bool writeUaMetadata = true}) {
    if (title != null) setInfo(title: title);
    final roots = <PdfStructSpec>[];
    for (var i = 0; i < document.pageCount; i++) {
      roots.addAll(_autoTagPage(i));
    }
    final documentRoot = PdfStructSpec('Document');
    documentRoot.children.addAll(roots);
    writeStructTree([documentRoot], lang: lang);
    if (writeUaMetadata) {
      setXmpMetadata(
          title: title ?? document.info['Title'], pdfUaPart: 1);
    }
    var count = 1;
    void countNode(PdfStructSpec s) {
      count++;
      s.children.forEach(countNode);
    }

    roots.forEach(countNode);
    return count;
  }

  /// Attaches an XMP metadata packet as the catalog /Metadata stream, building
  /// it from the given identification fields (see [buildXmpPacket]). Used for
  /// the PDF/UA ([pdfUaPart]) and PDF/A ([pdfaPart]/[pdfaConformance])
  /// identification schemas. Falls back to the document /Info for
  /// title/author/producer when those are not given.
  void setXmpMetadata({
    String? title,
    String? author,
    String? producer,
    String? creatorTool,
    int? pdfaPart,
    String? pdfaConformance,
    int? pdfUaPart,
  }) {
    final info = document.info;
    final packet = buildXmpPacket(
      title: title ?? info['Title'],
      author: author ?? info['Author'],
      producer: producer ?? info['Producer'],
      creatorTool: creatorTool ?? info['Creator'],
      pdfaPart: pdfaPart,
      pdfaConformance: pdfaConformance,
      pdfUaPart: pdfUaPart,
    );
    setMetadataStream(packet);
  }

  /// Sets the catalog /Metadata to a /Type /Metadata /Subtype /XML stream
  /// holding [xml] (a complete XMP packet). The stream is left uncompressed
  /// (PDF/A requires the document-level metadata stream to be unfiltered).
  void setMetadataStream(Uint8List xml) {
    final stream = CosStream(
      CosDictionary({
        'Type': CosName('Metadata'),
        'Subtype': CosName('XML'),
        'Length': CosInteger(xml.length),
      }),
      xml,
    );
    document.catalog['Metadata'] = _updater.addObject(stream);
    _updater.markChanged(document.catalog);
  }

  /// Converts the document toward PDF/A-[part]b (part 1, 2, or 3) by adding the
  /// structural requirements that do not need the content rewritten: an
  /// OutputIntent referencing the [iccProfile] ([iccComponents] = 1 gray,
  /// 3 RGB, 4 CMYK), XMP metadata carrying the pdfaid identification, a
  /// trailer /ID, and a catalog /Version cap. It refuses an encrypted document
  /// (PDF/A forbids encryption and the content cannot be re-emitted here).
  ///
  /// It does NOT embed missing fonts or rewrite colour — run [validatePdfA]
  /// afterward to see what remains. A document whose fonts are already
  /// embedded and whose colour is device-independent (or covered by the
  /// OutputIntent) becomes conformant. [title]/[creator] populate the
  /// metadata and document info.
  void convertToPdfA({
    required Uint8List iccProfile,
    int iccComponents = 3,
    String outputConditionIdentifier = 'Custom',
    String outputCondition = '',
    int part = 2,
    String level = 'B',
    String? title,
    String? creator,
  }) {
    if (document.cos.isEncrypted) {
      throw StateError(
          'cannot convert an encrypted document to PDF/A: re-save it '
          'without encryption first');
    }
    if (title != null) setInfo(title: title);

    // Cap the version (a catalog /Version name overrides the header, §7.5.5).
    document.catalog['Version'] = CosName(part == 1 ? '1.4' : '1.7');

    // OutputIntent + ICC DestOutputProfile.
    final iccRef = _updater.addObject(CosStream(
      CosDictionary({
        'N': CosInteger(iccComponents),
        'Length': CosInteger(iccProfile.length),
      }),
      iccProfile,
    ));
    final intent = CosDictionary({
      'Type': CosName('OutputIntent'),
      'S': CosName('GTS_PDFA1'),
      'OutputConditionIdentifier':
          CosString.fromText(outputConditionIdentifier),
      'Info': CosString.fromText(
          outputCondition.isEmpty ? outputConditionIdentifier : outputCondition),
      'DestOutputProfile': iccRef,
    });
    if (outputCondition.isNotEmpty) {
      intent['OutputCondition'] = CosString.fromText(outputCondition);
    }
    final existing = document.cos.resolve(document.catalog['OutputIntents']);
    final intents = <CosObject>[
      if (existing is CosArray) ...existing.items,
      _updater.addObject(intent),
    ];
    document.catalog['OutputIntents'] = CosArray(intents);

    // XMP identification metadata.
    setXmpMetadata(
      title: title,
      creatorTool: creator,
      pdfaPart: part,
      pdfaConformance: level.toUpperCase(),
    );

    _updater.markChanged(document.catalog);

    // Ensure a trailer /ID (required by PDF/A); derive it deterministically
    // from the current bytes so re-runs are stable.
    final existingId = document.cos.resolve(document.cos.trailer['ID']);
    if (existingId is! CosArray || existingId.length < 2) {
      final digest = crypto.md5.convert(document.cos.bytes).bytes;
      final id = CosString(Uint8List.fromList(digest), isHex: true);
      _updater.setTrailerEntry('ID', CosArray([id, id]));
    }
  }

  /// Tags page [pageIndex]'s content and returns the structure specs for it.
  List<PdfStructSpec> _autoTagPage(int pageIndex) {
    final page = document.page(pageIndex);
    final ops = ContentStreamParser.parse(page.contentBytes());
    final shows = <_ShowOp>[];
    _scanShows(ops, shows);
    if (shows.isEmpty) {
      // Nothing to tag as text; still wrap painting as artifacts so the page
      // has no untagged real content.
      _rewriteTagged(page, ops, const {}, const {});
      return const [];
    }

    // Assign one MCID per show op, in content order, so the parent-tree array
    // is naturally indexed.
    final mcidByOp = <int, int>{};
    var nextMcid = 0;
    for (final s in shows) {
      mcidByOp[s.opIndex] = nextMcid;
      s.mcid = nextMcid;
      nextMcid++;
    }

    // Tag of each MCID's marked content = its block's role, computed below.
    final tagByOp = <int, String>{};
    final blocks = _groupBlocks(shows);
    final specs = <PdfStructSpec>[];
    var pendingList = <_Block>[];

    void flushList() {
      if (pendingList.isEmpty) return;
      final list = PdfStructSpec('L', pageIndex: pageIndex);
      for (final b in pendingList) {
        final li = PdfStructSpec('LI', pageIndex: pageIndex);
        final body = PdfStructSpec('LBody',
            pageIndex: pageIndex, mcids: [for (final s in b.shows) s.mcid]);
        for (final s in b.shows) {
          tagByOp[s.opIndex] = 'LBody';
        }
        li.children.add(body);
        list.children.add(li);
      }
      specs.add(list);
      pendingList = [];
    }

    for (final b in blocks) {
      if (b.role == _Role.listItem) {
        pendingList.add(b);
        continue;
      }
      flushList();
      final type = switch (b.role) {
        _Role.heading1 => 'H1',
        _Role.heading2 => 'H2',
        _ => 'P',
      };
      for (final s in b.shows) {
        tagByOp[s.opIndex] = type;
      }
      specs.add(PdfStructSpec(type,
          pageIndex: pageIndex, mcids: [for (final s in b.shows) s.mcid]));
    }
    flushList();

    _rewriteTagged(page, ops, mcidByOp, tagByOp);
    return specs;
  }

  /// Re-serialises [ops] for [page], wrapping each tagged show op in
  /// `/Tag <</MCID n>> BDC … EMC` and each non-text painting op in
  /// `/Artifact BMC … EMC`, then replaces the page content.
  void _rewriteTagged(PdfPage page, List<ContentOperation> ops,
      Map<int, int> mcidByOp, Map<int, String> tagByOp) {
    final out = BytesBuilder();
    for (var i = 0; i < ops.length; i++) {
      final op = ops[i];
      final mcid = mcidByOp[i];
      if (mcid != null) {
        final tag = tagByOp[i] ?? 'P';
        out.add(latin1.encode('/$tag <</MCID $mcid>> BDC\n'));
        _writeContentOp(op, out);
        out.add(latin1.encode('EMC\n'));
      } else if (_isArtifactOp(op.operator)) {
        out.add(latin1.encode('/Artifact BMC\n'));
        _writeContentOp(op, out);
        out.add(latin1.encode('EMC\n'));
      } else {
        _writeContentOp(op, out);
      }
    }
    final bytes = out.takeBytes();
    page.dict['Contents'] = _updater.addObject(
        CosStream(CosDictionary({'Length': CosInteger(bytes.length)}), bytes));
    _wrappedPages.remove(page.dict);
    _updater.markChanged(page.dict);
  }

  /// Re-serialises one content operator (handling BI inline images), the same
  /// shape the redaction writer uses. Kept local because that one is private
  /// to its own extension.
  static void _writeContentOp(ContentOperation op, BytesBuilder out) {
    if (op.operator == 'BI' && op.operands.length >= 2) {
      out.add(latin1.encode('BI'));
      final dict = op.operands[0];
      if (dict is CosDictionary) {
        dict.entries.forEach((key, value) {
          out
            ..add(latin1.encode(' /$key '))
            ..add(CosSerializer.serialize(value));
        });
      }
      out.add(latin1.encode(' ID\n'));
      final data = op.operands[1];
      if (data is CosString) out.add(data.bytes);
      out.add(latin1.encode('\nEI\n'));
      return;
    }
    for (final operand in op.operands) {
      out
        ..add(CosSerializer.serialize(operand))
        ..addByte(0x20);
    }
    out.add(latin1.encode('${op.operator}\n'));
  }

  /// Painting operators whose output is not tagged text — wrapped as
  /// artifacts so the page carries no untagged real content. State-only
  /// operators (q/Q/cm/gs/colour) are left alone to keep q/Q nesting intact.
  static bool _isArtifactOp(String op) => const {
        'S', 's', 'f', 'F', 'f*', 'B', 'B*', 'b', 'b*', // path painting
        'sh', // shading
        'Do', // XObject (image or form)
        'BI', // inline image
      }.contains(op);

  /// The indirect reference of page [index]'s dictionary, or null.
  CosReference? _pageReference(int index) {
    if (index < 0 || index >= document.pageCount) return null;
    return document.cos.referenceTo(document.page(index).dict);
  }

  /// Collects every show-text operator with its baseline position and size by
  /// a light text-positioning pass (§9.4). Affine math is inline to avoid a
  /// dependency on the rendering layer.
  void _scanShows(List<ContentOperation> ops, List<_ShowOp> out) {
    var ctm = _stIdentity;
    final ctmStack = <List<double>>[];
    var tm = _stIdentity, tlm = _stIdentity;
    var fontSize = 0.0, leading = 0.0, hScale = 1.0;
    for (var i = 0; i < ops.length; i++) {
      final op = ops[i];
      final o = op.operands;
      switch (op.operator) {
        case 'q':
          ctmStack.add(ctm);
        case 'Q':
          if (ctmStack.isNotEmpty) ctm = ctmStack.removeLast();
        case 'cm':
          if (o.length >= 6) ctm = _stMul(_stMatrixOf(o), ctm);
        case 'BT':
          tm = tlm = _stIdentity;
        case 'Tf':
          if (o.length >= 2) fontSize = _stNum(o[1]);
        case 'TL':
          if (o.isNotEmpty) leading = _stNum(o[0]);
        case 'Tz':
          if (o.isNotEmpty) hScale = _stNum(o[0]) / 100.0;
        case 'Td':
          if (o.length >= 2) {
            tlm = _stMul([1, 0, 0, 1, _stNum(o[0]), _stNum(o[1])], tlm);
            tm = tlm;
          }
        case 'TD':
          if (o.length >= 2) {
            leading = -_stNum(o[1]);
            tlm = _stMul([1, 0, 0, 1, _stNum(o[0]), _stNum(o[1])], tlm);
            tm = tlm;
          }
        case 'Tm':
          if (o.length >= 6) tm = tlm = _stMatrixOf(o);
        case 'T*':
          tlm = _stMul([1, 0, 0, 1, 0, -leading], tlm);
          tm = tlm;
        case 'Tj':
          _emitShow(out, i, o.isNotEmpty ? o[0] : null, tm, ctm, fontSize, hScale);
        case 'TJ':
          _emitShow(out, i, o.isNotEmpty ? o[0] : null, tm, ctm, fontSize, hScale);
        case "'":
          tlm = _stMul([1, 0, 0, 1, 0, -leading], tlm);
          tm = tlm;
          _emitShow(out, i, o.isNotEmpty ? o[0] : null, tm, ctm, fontSize, hScale);
        case '"':
          tlm = _stMul([1, 0, 0, 1, 0, -leading], tlm);
          tm = tlm;
          _emitShow(out, i, o.length >= 3 ? o[2] : null, tm, ctm, fontSize,
              hScale);
      }
    }
  }

  void _emitShow(List<_ShowOp> out, int opIndex, CosObject? operand,
      List<double> tm, List<double> ctm, double fontSize, double hScale) {
    final m = _stMul(tm, ctm);
    final x = m[4], y = m[5];
    final det = (m[0] * m[3] - m[1] * m[2]).abs();
    final size = fontSize * (det <= 0 ? 1 : math.sqrt(det));
    out.add(_ShowOp(
        opIndex: opIndex, x: x, y: y, size: size, text: _showOperandText(operand)));
  }

  /// Best-effort text of a show operand for list-marker detection. Bytes are
  /// decoded as Latin-1 (covers the base-14 / WinAnsi case); good enough to
  /// spot a leading bullet or number — a miss only loses list grouping.
  String _showOperandText(CosObject? operand) {
    if (operand is CosString) return latin1.decode(operand.bytes, allowInvalid: true);
    if (operand is CosArray) {
      final b = StringBuffer();
      for (final item in operand.items) {
        if (item is CosString) {
          b.write(latin1.decode(item.bytes, allowInvalid: true));
        }
      }
      return b.toString();
    }
    return '';
  }

  /// Groups show ops into visual lines then paragraph blocks, classifying
  /// each block's role by relative size and list markers.
  List<_Block> _groupBlocks(List<_ShowOp> shows) {
    if (shows.isEmpty) return const [];
    final sizes = [for (final s in shows) s.size]..sort();
    final median = sizes[sizes.length ~/ 2];

    // Lines: same baseline within half the (median) text size.
    final byTop = [...shows]..sort((a, b) => b.y.compareTo(a.y));
    final lines = <List<_ShowOp>>[];
    for (final s in byTop) {
      if (lines.isNotEmpty &&
          (lines.last.first.y - s.y).abs() <= 0.5 * math.max(s.size, 1)) {
        lines.last.add(s);
      } else {
        lines.add([s]);
      }
    }
    for (final line in lines) {
      line.sort((a, b) => a.x.compareTo(b.x));
    }

    // Blocks: split lines on a vertical gap larger than ~1.6× line height, a
    // size change, or a list marker boundary.
    final blocks = <_Block>[];
    List<_ShowOp>? currentShows;
    double? lastY;
    double? lastSize;
    bool? lastBullet;
    for (final line in lines) {
      final lineSize = line.map((s) => s.size).reduce(math.max);
      final bullet = _bulletPrefix(line.first.text);
      final gap = lastY == null ? 0.0 : (lastY - line.first.y).abs();
      final breakBlock = currentShows == null ||
          bullet != (lastBullet ?? false) ||
          (lastSize != null && (lineSize - lastSize).abs() > 0.25 * lastSize) ||
          gap > 1.8 * math.max(lineSize, 1);
      if (breakBlock) {
        if (currentShows != null) {
          blocks.add(_makeBlock(currentShows, median));
        }
        currentShows = [...line];
      } else {
        currentShows.addAll(line);
      }
      lastY = line.last.y;
      lastSize = lineSize;
      lastBullet = bullet;
    }
    if (currentShows != null) blocks.add(_makeBlock(currentShows, median));
    return blocks;
  }

  _Block _makeBlock(List<_ShowOp> shows, double median) {
    final size = shows.map((s) => s.size).reduce(math.max);
    final _Role role;
    if (_bulletPrefix(shows.first.text)) {
      role = _Role.listItem;
    } else if (size >= 1.7 * median) {
      role = _Role.heading1;
    } else if (size >= 1.2 * median) {
      role = _Role.heading2;
    } else {
      role = _Role.paragraph;
    }
    return _Block(shows, role);
  }

  /// Whether [text] starts with a list marker (bullet glyph, dash, or a
  /// number/letter followed by '.' or ')').
  static bool _bulletPrefix(String text) {
    final t = text.trimLeft();
    if (t.isEmpty) return false;
    final first = t.codeUnitAt(0);
    const bullets = {0x2022, 0x2023, 0x25E6, 0x00B7, 0x0095, 0x2043, 0x2219};
    if (bullets.contains(first)) return true;
    if (t.startsWith('- ') || t.startsWith('* ') || t.startsWith('• ')) {
      return true;
    }
    return RegExp(r'^(\d{1,3}|[a-zA-Z])[.)]\s').hasMatch(t);
  }

  static const List<double> _stIdentity = [1, 0, 0, 1, 0, 0];

  static List<double> _stMatrixOf(List<CosObject> o) =>
      [_stNum(o[0]), _stNum(o[1]), _stNum(o[2]), _stNum(o[3]), _stNum(o[4]), _stNum(o[5])];

  /// a·b in PDF row-vector convention (a applied first).
  static List<double> _stMul(List<double> a, List<double> b) => [
        a[0] * b[0] + a[1] * b[2],
        a[0] * b[1] + a[1] * b[3],
        a[2] * b[0] + a[3] * b[2],
        a[2] * b[1] + a[3] * b[3],
        a[4] * b[0] + a[5] * b[2] + b[4],
        a[4] * b[1] + a[5] * b[3] + b[5],
      ];

  static double _stNum(CosObject o) => switch (o) {
        CosInteger(:final value) => value.toDouble(),
        CosReal(:final value) => value,
        _ => 0,
      };
}

enum _Role { paragraph, heading1, heading2, listItem }

class _ShowOp {
  _ShowOp(
      {required this.opIndex,
      required this.x,
      required this.y,
      required this.size,
      required this.text});
  final int opIndex;
  final double x;
  final double y;
  final double size;
  final String text;
  int mcid = -1;
}

class _Block {
  _Block(this.shows, this.role);
  final List<_ShowOp> shows;
  final _Role role;
}
