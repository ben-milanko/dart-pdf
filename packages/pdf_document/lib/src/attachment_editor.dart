part of 'editor.dart';

/// Authoring of embedded files (attachments): the document-level
/// `/Names → /EmbeddedFiles` name tree (§7.11.4) and `/FileAttachment`
/// annotations (§12.5.6.15). Each embedded file becomes a proper
/// `/EmbeddedFile` stream with `/Params` carrying its size and MD5
/// checksum, optionally Flate-compressed.
extension PdfAttachmentEditing on PdfEditor {
  /// Embeds [data] under [name] in the catalog's `/EmbeddedFiles` name tree,
  /// replacing any existing entry with the same name.
  ///
  /// [fileName] is the displayed file name (defaults to [name]),
  /// [description] fills `/Desc`, [mimeType] the stream `/Subtype` (e.g.
  /// `application/pdf`), and the dates fill `/Params`. With [compress] the
  /// payload is Flate-encoded. Returns the new filespec reference.
  CosReference addEmbeddedFile(
    String name,
    Uint8List data, {
    String? fileName,
    String? description,
    String? mimeType,
    DateTime? creationDate,
    DateTime? modificationDate,
    bool compress = true,
  }) {
    final specRef = _updater.addObject(_buildFilespec(
      fileName: fileName ?? name,
      data: data,
      description: description,
      mimeType: mimeType,
      creationDate: creationDate,
      modificationDate: modificationDate,
      compress: compress,
    ));
    final pairs = _embeddedFilePairs()..removeWhere((p) => p.$1 == name);
    pairs.add((name, specRef));
    _writeEmbeddedFilesTree(pairs);
    return specRef;
  }

  /// Removes the embedded file named [name] from the `/EmbeddedFiles` name
  /// tree. The stream becomes unreferenced (harmless in an incremental
  /// update). Returns whether an entry was removed.
  bool removeEmbeddedFile(String name) {
    final pairs = _embeddedFilePairs();
    final before = pairs.length;
    pairs.removeWhere((p) => p.$1 == name);
    if (pairs.length == before) return false;
    _writeEmbeddedFilesTree(pairs);
    return true;
  }

  /// Adds a `/FileAttachment` annotation on page [pageIndex] that carries
  /// [data] as an embedded file. [rect] is the icon's page-space rectangle,
  /// [iconName] the icon style (PushPin, Graph, Paperclip, Tag), and
  /// [description] the annotation `/Contents`. The file is *not* added to
  /// the document-level name tree (pass it to [addEmbeddedFile] for that).
  /// Returns the annotation reference.
  CosReference addFileAttachmentAnnotation(
    int pageIndex, {
    required String fileName,
    required Uint8List data,
    required PdfRect rect,
    String? description,
    String? mimeType,
    String iconName = 'PushPin',
    DateTime? creationDate,
    DateTime? modificationDate,
    bool compress = true,
  }) {
    final specRef = _updater.addObject(_buildFilespec(
      fileName: fileName,
      data: data,
      description: description,
      mimeType: mimeType,
      creationDate: creationDate,
      modificationDate: modificationDate,
      compress: compress,
    ));
    final annot = CosDictionary({
      'Type': const CosName('Annot'),
      'Subtype': const CosName('FileAttachment'),
      'FS': specRef,
      'Rect': _rectArray(rect),
      'Name': CosName(iconName),
      'F': const CosInteger(4), // Print
    });
    if (description != null) annot['Contents'] = CosString.fromText(description);
    final annotRef = _updater.addObject(annot);

    final page = document.page(pageIndex);
    final raw = page.dict['Annots'];
    final resolved = document.cos.resolve(raw);
    if (resolved is CosArray) {
      resolved.items.add(annotRef);
      if (raw is CosReference) {
        _updater.replaceObject(raw.objectNumber, resolved);
      } else {
        _updater.markChanged(page.dict);
      }
    } else {
      page.dict['Annots'] = CosArray([annotRef]);
      _updater.markChanged(page.dict);
    }
    return annotRef;
  }

  // --- internals -----------------------------------------------------------

  CosDictionary _buildFilespec({
    required String fileName,
    required Uint8List data,
    String? description,
    String? mimeType,
    DateTime? creationDate,
    DateTime? modificationDate,
    required bool compress,
  }) {
    final streamRef = _updater.addObject(_buildEmbeddedStream(
      data,
      mimeType: mimeType,
      creationDate: creationDate,
      modificationDate: modificationDate,
      compress: compress,
    ));
    final spec = CosDictionary({
      'Type': const CosName('Filespec'),
      'F': CosString.fromText(fileName),
      'UF': CosString.fromText(fileName),
      'EF': CosDictionary({'F': streamRef, 'UF': streamRef}),
    });
    if (description != null) spec['Desc'] = CosString.fromText(description);
    return spec;
  }

  CosStream _buildEmbeddedStream(
    Uint8List data, {
    String? mimeType,
    DateTime? creationDate,
    DateTime? modificationDate,
    required bool compress,
  }) {
    // /CheckSum is the MD5 of the uncompressed, unencrypted bytes (§7.11.3).
    final checksum = Uint8List.fromList(crypto.md5.convert(data).bytes);
    final params = CosDictionary({
      'Size': CosInteger(data.length),
      'CheckSum': CosString(checksum, isHex: true),
    });
    if (creationDate != null) {
      params['CreationDate'] = CosString.fromText(_formatPdfDate(creationDate));
    }
    if (modificationDate != null) {
      params['ModDate'] = CosString.fromText(_formatPdfDate(modificationDate));
    }
    final dict = CosDictionary({
      'Type': const CosName('EmbeddedFile'),
      'Params': params,
    });
    if (mimeType != null) dict['Subtype'] = CosName(mimeType);

    var payload = data;
    if (compress) {
      payload = Uint8List.fromList(const ZLibEncoder().encode(data));
      dict['Filter'] = const CosName('FlateDecode');
    }
    dict['Length'] = CosInteger(payload.length);
    return CosStream(dict, payload);
  }

  /// The existing `name → filespec` entries of the `/EmbeddedFiles` tree.
  List<(String, CosObject)> _embeddedFilePairs() {
    final cos = document.cos;
    final out = <(String, CosObject)>[];
    final names = cos.resolve(document.catalog['Names']);
    if (names is! CosDictionary) return out;
    final tree = cos.resolve(names['EmbeddedFiles']);
    if (tree is! CosDictionary) return out;
    void walk(CosDictionary node, Set<CosDictionary> seen) {
      if (!seen.add(node)) return;
      final entries = cos.resolve(node['Names']);
      if (entries is CosArray) {
        for (var i = 0; i + 1 < entries.length; i += 2) {
          final key = cos.resolve(entries[i]);
          if (key is CosString) out.add((key.text, entries[i + 1]));
        }
      }
      final kids = cos.resolve(node['Kids']);
      if (kids is CosArray) {
        for (final kid in kids.items) {
          final child = cos.resolve(kid);
          if (child is CosDictionary) walk(child, seen);
        }
      }
    }

    walk(tree, <CosDictionary>{});
    return out;
  }

  /// Rebuilds `/EmbeddedFiles` as a single flat, key-sorted name-tree node.
  void _writeEmbeddedFilesTree(List<(String, CosObject)> pairs) {
    final cos = document.cos;
    final namesRef = _ensureNamesDict();
    final namesDict = cos.resolve(namesRef) as CosDictionary;
    final treeRaw = namesDict['EmbeddedFiles'];

    if (pairs.isEmpty) {
      namesDict.entries.remove('EmbeddedFiles');
      _updater.replaceObject(namesRef.objectNumber, namesDict);
      return;
    }

    pairs.sort((a, b) => a.$1.compareTo(b.$1)); // name trees sort by key
    final namesArray = CosArray();
    for (final (key, value) in pairs) {
      namesArray.items
        ..add(CosString.fromText(key))
        ..add(value);
    }
    final node = CosDictionary({'Names': namesArray});

    if (treeRaw is CosReference) {
      _updater.replaceObject(treeRaw.objectNumber, node);
      cos.adoptObject(treeRaw, node); // so a later read sees the new node
    } else {
      final ref = _updater.addObject(node);
      namesDict['EmbeddedFiles'] = ref;
      _updater.replaceObject(namesRef.objectNumber, namesDict);
    }
  }

  /// The catalog's `/Names` dictionary reference, creating it when absent.
  CosReference _ensureNamesDict() {
    final cos = document.cos;
    final raw = document.catalog['Names'];
    final resolved = cos.resolve(raw);
    if (resolved is CosDictionary && raw is CosReference) return raw;
    final dict = resolved is CosDictionary
        ? CosDictionary({...resolved.entries})
        : CosDictionary();
    final ref = _updater.addObject(dict);
    document.catalog['Names'] = ref;
    _updater.markChanged(document.catalog);
    return ref;
  }
}

/// Formats a [DateTime] as a PDF date string `D:YYYYMMDDHHmmSSZ` (§7.9.4).
String _formatPdfDate(DateTime date) {
  final utc = date.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return 'D:${utc.year.toString().padLeft(4, '0')}${two(utc.month)}'
      '${two(utc.day)}${two(utc.hour)}${two(utc.minute)}${two(utc.second)}Z';
}
