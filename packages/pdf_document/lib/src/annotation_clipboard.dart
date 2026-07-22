part of 'editor.dart';

/// A self-contained copy of one annotation: its dictionary with every
/// referenced object - appearance streams included - resolved and copied
/// inline, detached from the document it came from.
///
/// Snapshots survive edits, undo, and even closing the source document,
/// which makes them the clipboard payload for copy/paste of annotations,
/// including across documents. Capture with [capture], paste with
/// [PdfAnnotationClipboard.pasteAnnotation].
class PdfAnnotationSnapshot {
  PdfAnnotationSnapshot._(
    this._dict,
    this.subtype,
    this.rect, {
    this.inReplyTo,
    this.sourceRotation = 0,
  });

  /// Fully detached: no [CosReference]s, streams held inline. Pastes
  /// re-copy it ([_materialize]), so one snapshot can paste many times
  /// without the copies sharing mutable structure.
  final CosDictionary _dict;

  /// The /Subtype name ('Square', 'Ink', 'FreeText', ...).
  final String subtype;

  /// The source /Rect in its page's space - paste offsets are relative
  /// to this.
  final PdfRect rect;

  /// For a reply ([PdfAnnotation.isReply]) captured with `keepName`, the
  /// /NM of the annotation it replies to. /IRT itself is an indirect
  /// reference that cannot travel in a detached snapshot, so the link
  /// rides as the parent's name and is relinked on
  /// [PdfAnnotationClipboard.pasteAnnotation] (and so [upsertAnnotation])
  /// by finding the parent in the receiving document. Null for non-replies
  /// and clipboard captures (which mint a fresh, parentless annotation).
  final String? inReplyTo;

  /// The clockwise /Rotate (0/90/180/270) of the page the annotation was
  /// captured from. An oriented appearance (FreeText and the like) is
  /// authored to read upright *after* the renderer applies its page's
  /// display rotation, so a copy pasted onto a page whose /Rotate differs
  /// would render spun. [PdfAnnotationClipboard.pasteAnnotation] uses this
  /// to counter-rotate by the source→destination delta. 0 (the default)
  /// means "captured from an unrotated page", which is also the safe
  /// fallback for payloads that predate this field.
  final int sourceRotation;

  /// Entries that don't travel: the page link (/P), reply threads and
  /// popups (whose /Parent points back into the source document),
  /// struct-tree and optional-content wiring. /NM drops too unless
  /// [capture] is told to keep it.
  static const _dropped = {
    'P', 'Popup', 'Parent', 'IRT', 'RT', 'NM', 'StructParent', 'OC', //
  };

  /// Captures [annotation] from [document] as a detached snapshot.
  ///
  /// Popups belong to their parent annotation, and links and form
  /// widgets are interactive objects whose targets (destinations, the
  /// AcroForm field tree) cannot travel with a copy - those return null.
  ///
  /// [keepName] keeps the /NM unique identifier in the snapshot. The
  /// clipboard leaves it false - a pasted copy is a new annotation and
  /// mints its own name. Sync payloads set it true: the name *is* the
  /// identity the snapshot travels under (see
  /// [PdfAnnotationSyncEditing.upsertAnnotation]).
  ///
  /// [sourcePageRotation] is the /Rotate of the page [annotation] lives on
  /// (read it from [PdfPage.rotation], which resolves inheritance); it is
  /// recorded as [sourceRotation] so a paste onto a differently rotated
  /// page can re-orient the appearance. Leave it 0 for unrotated pages.
  static PdfAnnotationSnapshot? capture(
    PdfDocument document,
    PdfAnnotation annotation, {
    bool keepName = false,
    int sourcePageRotation = 0,
  }) {
    if (const {'Popup', 'Widget', 'Link'}.contains(annotation.subtype)) {
      return null;
    }
    final copier = _SnapshotCopier(document);
    final out = CosDictionary();
    annotation.dict.entries.forEach((key, value) {
      // /NM and /RT travel only for sync (keepName): a reply needs its
      // reply-type, and the /IRT link rides separately as [inReplyTo]
      if (_dropped.contains(key) &&
          !(keepName && (key == 'NM' || key == 'RT'))) {
        return;
      }
      out[key] = copier.copy(value);
    });
    return PdfAnnotationSnapshot._(
      out,
      annotation.subtype,
      annotation.rect,
      inReplyTo: keepName ? annotation.inReplyTo : null,
      sourceRotation: _normalizeRotation(sourcePageRotation),
    );
  }

  /// Clamps any /Rotate to the {0, 90, 180, 270} the PDF spec allows.
  static int _normalizeRotation(int rotation) {
    final r = rotation % 360;
    final positive = r < 0 ? r + 360 : r;
    return positive - positive % 90;
  }

  /// The /NM identity captured with `keepName: true`, if any.
  String? get name {
    final nm = _dict['NM'];
    return nm is CosString ? nm.text : null;
  }

  /// Encodes the snapshot as plain JSON-compatible data - appearance
  /// streams travel as base64 - so it can live in a database or cross
  /// the wire and come back through [fromJson] rendering byte-identically.
  Map<String, dynamic> toJson() => {
        'v': 1,
        'subtype': subtype,
        'rect': [rect.left, rect.bottom, rect.right, rect.top],
        if (inReplyTo != null) 'irt': inReplyTo,
        // additive and omitted when 0, so unrotated-page payloads (the
        // common case) stay byte-identical to pre-field ones
        if (sourceRotation != 0) 'rot': sourceRotation,
        'dict': _encodeCos(_dict),
      };

  /// Decodes a [toJson] payload. Throws [FormatException] on malformed
  /// or version-incompatible data.
  static PdfAnnotationSnapshot fromJson(Map<String, dynamic> json) {
    if (json['v'] != 1) {
      throw FormatException('unsupported snapshot version: ${json['v']}');
    }
    final subtype = json['subtype'];
    final rect = json['rect'];
    final irt = json['irt'];
    final rot = json['rot'];
    final dict = _decodeCos(json['dict']);
    if (subtype is! String ||
        rect is! List ||
        rect.length != 4 ||
        rect.any((v) => v is! num) ||
        (irt != null && irt is! String) ||
        (rot != null && rot is! int) ||
        dict is! CosDictionary) {
      throw const FormatException('malformed annotation snapshot');
    }
    return PdfAnnotationSnapshot._(
      dict,
      subtype,
      PdfRect(
        (rect[0] as num).toDouble(),
        (rect[1] as num).toDouble(),
        (rect[2] as num).toDouble(),
        (rect[3] as num).toDouble(),
      ),
      inReplyTo: irt as String?,
      sourceRotation: rot == null ? 0 : _normalizeRotation(rot as int),
    );
  }

  CosDictionary _materialize() => _copyDetached(_dict) as CosDictionary;
}

/// JSON encoding of a detached COS tree. Dictionaries and streams share
/// the `d` tag (a stream adds `b`, its raw bytes); names tag `n`,
/// strings `s` (base64 of the exact bytes, `h` marking hex strings);
/// numbers, booleans, null, and arrays map natively.
Object? _encodeCos(CosObject value) {
  switch (value) {
    case CosStream stream:
      return {
        'd': {
          for (final e in stream.dictionary.entries.entries)
            e.key: _encodeCos(e.value),
        },
        'b': base64Encode(stream.rawBytes),
      };
    case CosDictionary dict:
      return {
        'd': {for (final e in dict.entries.entries) e.key: _encodeCos(e.value)},
      };
    case CosArray array:
      return [for (final item in array.items) _encodeCos(item)];
    case CosName name:
      return {'n': name.value};
    case CosString string:
      return {'s': base64Encode(string.bytes), if (string.isHex) 'h': true};
    case CosInteger(:final value):
      return value;
    case CosReal(:final value):
      return value;
    case CosBoolean(:final value):
      return value;
    default:
      return null; // CosNull (references can't survive capture)
  }
}

CosObject _decodeCos(Object? value) {
  switch (value) {
    case null:
      return CosNull.instance;
    case bool b:
      return CosBoolean(b);
    case int i:
      return CosInteger(i);
    case num n:
      return CosReal(n.toDouble());
    case List list:
      return CosArray([for (final item in list) _decodeCos(item)]);
    case Map map when map.containsKey('n'):
      return CosName(map['n'] as String);
    case Map map when map.containsKey('s'):
      return CosString(
        base64Decode(map['s'] as String),
        isHex: map['h'] == true,
      );
    case Map map when map.containsKey('d'):
      final dict = CosDictionary();
      (map['d'] as Map).forEach((key, item) {
        dict[key as String] = _decodeCos(item);
      });
      final bytes = map['b'];
      return bytes is String ? CosStream(dict, base64Decode(bytes)) : dict;
    default:
      throw FormatException('malformed snapshot node: $value');
  }
}

/// Pure structural copy of an already-detached tree (no references to
/// resolve - [PdfAnnotationSnapshot] guarantees none survive capture).
CosObject _copyDetached(CosObject value) {
  switch (value) {
    case CosStream stream:
      return CosStream(
        _copyDetached(stream.dictionary) as CosDictionary,
        Uint8List.fromList(stream.rawBytes),
      );
    case CosDictionary dict:
      final out = CosDictionary();
      dict.entries.forEach((key, item) => out[key] = _copyDetached(item));
      return out;
    case CosArray array:
      return CosArray([for (final item in array.items) _copyDetached(item)]);
    case CosString string:
      return CosString(Uint8List.fromList(string.bytes), isHex: string.isHex);
    default:
      return value; // names, numbers, booleans, null are immutable
  }
}

/// Deep-copies an annotation's object graph out of [source] into fully
/// direct (inline) structures: references resolve and copy in place,
/// shared targets duplicate, reference cycles break to null. Page-tree
/// dictionaries copy as null so a stray /P-like entry can't drag the
/// whole document along.
class _SnapshotCopier {
  _SnapshotCopier(this.source);

  final PdfDocument source;
  final Set<CosReference> _visiting = {};

  CosObject copy(CosObject value) {
    switch (value) {
      case CosReference ref:
        if (!_visiting.add(ref)) return CosNull.instance; // cycle
        final out = copy(source.cos.resolve(ref));
        _visiting.remove(ref);
        return out;
      case CosStream stream:
        final bytes = _payloadOf(stream);
        final out = CosStream(CosDictionary(), bytes);
        stream.dictionary.entries.forEach((key, item) {
          if (key == 'Length') return; // recomputed below
          out.dictionary[key] = copy(item);
        });
        out.dictionary['Length'] = CosInteger(bytes.length);
        return out;
      case CosDictionary dict:
        if (dict.typeName == 'Page' || dict.typeName == 'Pages') {
          return CosNull.instance; // never cross into the page tree
        }
        final out = CosDictionary();
        dict.entries.forEach((key, item) => out[key] = copy(item));
        return out;
      case CosArray array:
        return CosArray([for (final item in array.items) copy(item)]);
      case CosString string:
        return CosString(Uint8List.fromList(string.bytes), isHex: string.isHex);
      default:
        return value;
    }
  }

  /// Stream payload as plain (decrypted) bytes with the /Filter chain
  /// intact - same approach as page imports: stop the decode before the
  /// first filter so only the encryption comes off.
  Uint8List _payloadOf(CosStream stream) {
    final cos = source.cos;
    if (!cos.isEncrypted) return stream.rawBytes;
    final filter = cos.resolve(stream.dictionary['Filter']);
    final first = switch (filter) {
      CosName(:final value) => value,
      CosArray array when array.length > 0 => switch (cos.resolve(array[0])) {
          CosName(:final value) => value,
          _ => null,
        },
      _ => null,
    };
    return cos.decodeStreamData(stream, stopBeforeFilter: first);
  }
}

/// Pasting captured annotations ([PdfAnnotationSnapshot]) into a page.
extension PdfAnnotationClipboard on PdfEditor {
  /// Pastes [snapshot] onto page [pageIndex], its geometry shifted by
  /// ([dx], [dy]) page units.
  ///
  /// Each call materializes an independent copy - pasting twice yields
  /// two annotations. Streams (the appearance) become fresh indirect
  /// objects per §7.3.8, and the annotation appends to the page's
  /// /Annots, so it paints on top (§12.5.2).
  void pasteAnnotation(
    int pageIndex,
    PdfAnnotationSnapshot snapshot, {
    double dx = 0,
    double dy = 0,
  }) {
    final dict = snapshot._materialize();
    // pasted copies are new annotations and get a fresh identity; a
    // sync snapshot captured with keepName pastes under its own /NM
    if (dict['NM'] is! CosString) {
      dict['NM'] = CosString.fromText(_generateAnnotationName());
    }
    final rect = snapshot.rect;
    dict['Rect'] = _rectArray(
      PdfRect(rect.left + dx, rect.bottom + dy, rect.right + dx, rect.top + dy),
    );
    for (final key in const ['QuadPoints', 'L', 'Vertices', 'CL']) {
      final shifted = _shiftPoints(dict[key], dx, dy);
      if (shifted != null) dict[key] = shifted;
    }
    final ink = dict['InkList'];
    if (ink is CosArray) {
      dict['InkList'] = CosArray([
        for (final stroke in ink.items) _shiftPoints(stroke, dx, dy) ?? stroke,
      ]);
    }
    _reorientPastedAppearance(dict, pageIndex, snapshot.sourceRotation);
    // re-establish a reply's /IRT link by the parent's /NM: the reference
    // could not travel detached, so it arrives as snapshot.inReplyTo and is
    // resolved against the receiving document (orphaned when the parent
    // isn't present, which keeps a stray reply valid rather than dangling)
    final irtName = snapshot.inReplyTo;
    if (irtName != null) {
      final parent = _findByName(irtName, pageIndex: pageIndex);
      final ref =
          parent == null ? null : document.cos.referenceTo(parent.$2.dict);
      if (ref != null) {
        dict['IRT'] = ref;
        if (dict['RT'] is! CosName) dict['RT'] = const CosName('R');
      }
    }
    _hoistStreams(dict);

    final annotRef = _updater.addObject(dict);
    _linkAnnotation(
      pageIndex,
      annotRef,
      visual: !const {'Popup'}.contains(snapshot.subtype),
    );
  }

  /// Counter-rotates a pasted annotation's appearance when the destination
  /// page's /Rotate differs from the page it was captured on
  /// ([PdfAnnotationSnapshot.sourceRotation]), so oriented artwork
  /// (FreeText and the like) reads upright instead of spun by the page's
  /// display rotation.
  ///
  /// The renderer maps an appearance through the page's rotation just like
  /// the rest of the page, so a copy authored for a page rotated by
  /// `sourceRotation` needs `dstRotation - sourceRotation` degrees folded
  /// into its /Matrix to stay upright at `dstRotation` - the same
  /// centre-preserving fold [PdfAnnotationEditing.rotateAnnotation]
  /// applies. A no-op when the rotations match (the overwhelming common
  /// case) or the appearance can't be re-oriented (no single-stream /N,
  /// missing or degenerate BBox/Rect). Called before [_hoistStreams] while
  /// the appearance is still inline in [dict].
  void _reorientPastedAppearance(
    CosDictionary dict,
    int pageIndex,
    int sourceRotation,
  ) {
    final delta = PdfAnnotationEditing._normalizePageRotation(
        document.page(pageIndex).rotation - sourceRotation);
    if (delta == 0) return;
    final ap = document.cos.resolve(dict['AP']);
    if (ap is! CosDictionary) return;
    final form = document.cos.resolve(ap['N']);
    if (form is! CosStream) return; // multi-state /N (widgets) never paste here
    final rect = pdfRectFrom(document.cos, dict['Rect']);
    if (rect == null || rect.width <= 0 || rect.height <= 0) return;
    _foldRotationInto(dict, form, rect, delta.toDouble());
  }

  /// Replaces every inline [CosStream] in the tree with a reference to a
  /// freshly staged indirect object (children first, so a stream nested
  /// in another stream's /Resources hoists too).
  void _hoistStreams(CosObject node) {
    switch (node) {
      case CosDictionary dict:
        for (final key in dict.entries.keys.toList()) {
          final value = dict.entries[key]!;
          if (value is CosStream) {
            _hoistStreams(value.dictionary);
            dict[key] = _updater.addObject(value);
          } else {
            _hoistStreams(value);
          }
        }
      case CosArray array:
        for (var i = 0; i < array.items.length; i++) {
          final value = array.items[i];
          if (value is CosStream) {
            _hoistStreams(value.dictionary);
            array.items[i] = _updater.addObject(value);
          } else {
            _hoistStreams(value);
          }
        }
      default:
        break;
    }
  }
}
