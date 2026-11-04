part of 'editor.dart';

// FDF (§12.7.8) reading and writing for [PdfFormData]. An FDF file is PDF
// object syntax under an `%FDF-1.2` header whose trailer /Root is a catalog
// holding one /FDF dictionary: /Fields (a field tree of /T + /V), /Annots
// (annotation dictionaries with a /Page index), /F (the target PDF) and
// /ID (its file identifiers).

final Uint8List _fdfMagic = ascii.encode('%FDF');
final Uint8List _pdfMagic = ascii.encode('%PDF');

PdfFormData _readFdf(Uint8List bytes) {
  // Same object syntax as PDF; only the header word differs. Swapping it
  // for the PDF one in a copy keeps every byte offset where the xref put
  // it, so the PDF reader (and its xref recovery, which the many FDFs
  // written without a cross-reference table need) applies unchanged.
  final copy = Uint8List.fromList(bytes);
  final limit = math.min(copy.length - 4, 1024);
  for (var i = 0; i <= limit; i++) {
    if (copy[i] == 0x25 &&
        copy[i + 1] == 0x46 &&
        copy[i + 2] == 0x44 &&
        copy[i + 3] == 0x46) {
      copy.setAll(i, _pdfMagic);
      break;
    }
  }
  final CosDocument cos;
  try {
    cos = CosDocument.open(copy);
  } on CosParseException catch (e) {
    throw FormatException('malformed FDF: ${e.message}');
  }
  final root = cos.resolve(cos.trailer['Root']);
  final fdf = root is CosDictionary ? cos.resolve(root['FDF']) : null;
  if (fdf is! CosDictionary) {
    throw const FormatException('not FDF: the catalog has no /FDF dictionary');
  }

  final fields = <PdfFormDataField>[];
  void walk(CosObject? node, String prefix, Set<CosDictionary> seen) {
    final dict = cos.resolve(node);
    if (dict is! CosDictionary || !seen.add(dict)) return;
    final t = cos.resolve(dict['T']);
    final partial = t is CosString ? t.text : null;
    final name = partial == null
        ? prefix
        : prefix.isEmpty
            ? partial
            : '$prefix.$partial';
    if (dict.entries.containsKey('V') && name.isNotEmpty) {
      final v = cos.resolve(dict['V']);
      final (values, isState) = _fdfValues(cos, v);
      fields.add(PdfFormDataField(name, values, isState: isState));
    }
    final kids = cos.resolve(dict['Kids']);
    if (kids is CosArray) {
      for (final kid in kids.items) {
        walk(kid, name, seen);
      }
    }
  }

  final roots = cos.resolve(fdf['Fields']);
  if (roots is CosArray) {
    final seen = Set<CosDictionary>.identity();
    for (final node in roots.items) {
      walk(node, '', seen);
    }
  }

  final annotations = <PdfExchangeAnnotation>[];
  final annots = cos.resolve(fdf['Annots']);
  if (annots is CosArray) {
    final dicts = <CosDictionary>[
      for (final item in annots.items)
        if (cos.resolve(item) case final CosDictionary d) d,
    ];
    // names first, so a reply can name a parent the producer left unnamed
    final names = Map<CosDictionary, String>.identity();
    for (final dict in dicts) {
      final nm = cos.resolve(dict['NM']);
      names[dict] = nm is CosString ? nm.text : _generateAnnotationName();
    }
    final copier = _SnapshotCopier(cos);
    for (final dict in dicts) {
      final subtype = cos.resolve(dict['Subtype']);
      if (subtype is! CosName || _exchangeSkipped.contains(subtype.value)) {
        continue;
      }
      final out = CosDictionary();
      dict.entries.forEach((key, value) {
        if (_exchangeDropped.contains(key)) return;
        out[key] = copier.copy(value);
      });
      out['NM'] = CosString.fromText(names[dict]!);
      final page = cos.resolve(dict['Page']);
      final parent = cos.resolve(dict['IRT']);
      annotations.add(PdfExchangeAnnotation._(
        page is CosInteger ? page.value : 0,
        out,
        inReplyTo: parent is CosDictionary
            ? names[parent] ??
                switch (cos.resolve(parent['NM'])) {
                  CosString string => string.text,
                  _ => null,
                }
            : null,
      ));
    }
  }

  final f = cos.resolve(fdf['F']);
  final target = switch (f) {
    CosString string => string.text,
    CosDictionary spec => switch (cos.resolve(spec['UF'] ?? spec['F'])) {
        CosString string => string.text,
        _ => null,
      },
    _ => null,
  };
  return PdfFormData(
    fields: fields,
    annotations: annotations,
    targetFile: target,
    documentIds: PdfFormData._idsFrom(cos, fdf['ID']),
  );
}

/// A /V value as strings: text strings decoded, names (button states) by
/// value, arrays (multi-select) entry by entry.
(List<String>, bool) _fdfValues(CosDocument cos, CosObject? v) {
  switch (v) {
    case CosString string:
      return ([string.text], false);
    case CosName(:final value):
      return ([value], true);
    case CosArray(:final items):
      var isState = false;
      final out = <String>[];
      for (final item in items) {
        switch (cos.resolve(item)) {
          case CosString string:
            out.add(string.text);
          case CosName(:final value):
            out.add(value);
            isState = true;
          default:
        }
      }
      return (out, isState);
    case CosStream stream:
      // rich text values (/RV-style streams) carry their text decoded
      return (
        [utf8.decode(cos.decodeStreamData(stream), allowMalformed: true)],
        false
      );
    default:
      return (const [], false);
  }
}

Uint8List _writeFdf(PdfFormData data) {
  final builder = CosDocumentBuilder();
  final fdf = CosDictionary();

  if (data.fields.isNotEmpty) {
    fdf['Fields'] = _fdfFieldTree(data.fields);
  }

  if (data.annotations.isNotEmpty) {
    final refs = <String, CosReference>{};
    final dicts = <(PdfExchangeAnnotation, CosDictionary)>[];
    final listed = <CosObject>[];
    for (final annotation in data.annotations) {
      final dict = _copyDetached(annotation._dict) as CosDictionary;
      dict['Page'] = CosInteger(annotation.pageIndex);
      if (dict['Type'] is! CosName) dict['Type'] = const CosName('Annot');
      _hoistInto(builder, dict);
      final ref = builder.add(dict);
      listed.add(ref);
      final name = annotation.name;
      if (name != null) refs[name] = ref;
      dicts.add((annotation, dict));
    }
    for (final (annotation, dict) in dicts) {
      final parent = annotation.inReplyTo;
      final ref = parent == null ? null : refs[parent];
      if (ref == null) continue;
      dict['IRT'] = ref;
      if (dict['RT'] is! CosName) dict['RT'] = const CosName('R');
    }
    fdf['Annots'] = CosArray(listed);
  }

  final target = data.targetFile;
  if (target != null) fdf['F'] = CosString.fromText(target);
  final ids = data.documentIds;
  if (ids != null && ids.length == 2) {
    fdf['ID'] = CosArray([
      for (final id in ids) CosString(Uint8List.fromList(id), isHex: true),
    ]);
  }

  final root = builder.add(CosDictionary({'FDF': fdf}));
  final bytes = builder.build(root: root, version: '1.2');
  bytes.setAll(0, _fdfMagic);
  return bytes;
}

/// Turns fully qualified names into the nested /T + /Kids tree FDF stores
/// (`a.b` and `a.c` share a parent `a`), each terminal node with its /V.
CosArray _fdfFieldTree(List<PdfFormDataField> fields) {
  final roots = <String, CosDictionary>{};
  final kidsOf = Map<CosDictionary, Map<String, CosDictionary>>.identity();

  CosDictionary node(Map<String, CosDictionary> level, String partial) =>
      level.putIfAbsent(
          partial, () => CosDictionary({'T': CosString.fromText(partial)}));

  for (final field in fields) {
    final parts = field.name.split('.');
    var level = roots;
    late CosDictionary dict;
    for (var i = 0; i < parts.length; i++) {
      dict = node(level, parts[i]);
      if (i < parts.length - 1) {
        level = kidsOf.putIfAbsent(dict, () => {});
      }
    }
    final values = field.values;
    CosObject one(String v) =>
        field.isState ? CosName(v) : CosString.fromText(v);
    if (values.length == 1) {
      dict['V'] = one(values.single);
    } else if (values.length > 1) {
      dict['V'] = CosArray([for (final v in values) one(v)]);
    }
  }

  CosArray emit(Map<String, CosDictionary> level) => CosArray([
        for (final dict in level.values)
          () {
            final kids = kidsOf[dict];
            if (kids != null) dict['Kids'] = emit(kids);
            return dict;
          }(),
      ]);

  return emit(roots);
}

/// Registers every inline stream under [node] with [builder] as its own
/// indirect object (children first), as §7.3.8 requires of streams.
void _hoistInto(CosDocumentBuilder builder, CosObject node) {
  switch (node) {
    case CosStream stream:
      _hoistInto(builder, stream.dictionary);
    case CosDictionary dict:
      for (final key in dict.entries.keys.toList()) {
        final value = dict.entries[key]!;
        _hoistInto(builder, value);
        if (value is CosStream) dict[key] = builder.add(value);
      }
    case CosArray array:
      for (var i = 0; i < array.items.length; i++) {
        final value = array.items[i];
        _hoistInto(builder, value);
        if (value is CosStream) array.items[i] = builder.add(value);
      }
    default:
  }
}
