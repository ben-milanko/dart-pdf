part of 'editor.dart';

/// Combines complete PDFs without a file-system or Flutter dependency.
class PdfMerger {
  PdfMerger._();

  /// Concatenates [pdfs] in order. At least one input is required.
  ///
  /// ```dart
  /// final merged = PdfMerger.merge([coverBytes, reportBytes, appendixBytes]);
  /// final document = PdfDocument.open(merged);
  /// print(document.pageCount);
  /// ```
  ///
  /// [passwords], when supplied, must contain one password per input (use an
  /// empty string for unprotected inputs). Wrong passwords throw
  /// [CosPasswordException]. The first PDF remains the base: its encryption,
  /// metadata, catalog viewing settings (including /PageMode), and original
  /// bytes are retained. Later inputs are decrypted during import and saved
  /// under the base's encryption. This never removes the base's password.
  ///
  /// Pages, their resources and annotations, AcroForm fields, named
  /// destinations, and outlines are imported. Colliding root field names and
  /// named destinations gain `_2`, `_3`, ... suffixes. Internal links resolve
  /// in their source namespace before remapping, so duplicate destination
  /// names do not redirect links into a different input. Other catalog data
  /// from later inputs (such as attachments, XFA, and document JavaScript)
  /// is not merged. Source signatures do not certify the merged document.
  static Uint8List merge(List<Uint8List> pdfs, {List<String>? passwords}) {
    if (pdfs.isEmpty) {
      throw ArgumentError.value(pdfs, 'pdfs', 'provide at least one PDF');
    }
    if (passwords != null && passwords.length != pdfs.length) {
      throw ArgumentError.value(
          passwords, 'passwords', 'provide one password per PDF');
    }
    final documents = [
      for (var i = 0; i < pdfs.length; i++)
        PdfDocument.open(pdfs[i], password: passwords?[i] ?? ''),
    ];
    final editor = PdfEditor(documents.first);
    for (final source in documents.skip(1)) {
      editor.appendPagesFrom(source);
    }
    return Uint8List.fromList(editor.hasChanges ? editor.save() : pdfs.first);
  }
}

extension on PdfEditor {
  void _mergeImportedDocumentData(_PageImporter importer,
      {required bool intoEmpty}) {
    _mergeFormFields(importer);
    _mergeNamedDestinations(importer);
    _mergeOptionalContent(importer);
    final source = importer.source;
    final intents = source.catalog['OutputIntents'];
    if (intoEmpty && intents != null) {
      document.catalog['OutputIntents'] = importer.copyValue(intents);
      _updater.markChanged(document.catalog);
    }
    final outlines = source.cos.resolve(source.catalog['Outlines']);
    if (outlines is CosDictionary && outlines.containsKey('First')) {
      final root = _ensureOutlineRoot();
      final imported =
          _importOutlineChildren(importer, outlines, <CosDictionary>{});
      _relinkOutlineChildren(root, [..._outlineChildren(root), ...imported]);
      _recountOutline(root);
    }
  }

  /// Each input's default layer state belongs to that document's group
  /// namespace. Make it explicit before combining the groups, and restrict
  /// automatic usage applications to the groups they originally governed.
  /// Otherwise an imported BaseState OFF turns on under the destination's
  /// ON default, or an /AS entry with no /OCGs starts affecting other inputs.
  void _mergeOptionalContent(_PageImporter importer) {
    final source = importer.source.cos;
    final incoming = source.resolve(importer.source.catalog['OCProperties']);
    if (incoming is! CosDictionary) return;
    final cos = document.cos;
    final previous = cos.resolve(document.catalog['OCProperties']);
    final groups = <CosObject>[];
    final on = <CosObject>[];
    final off = <CosObject>[];
    final applications = <CosObject>[];

    void append(CosDocument owner, CosDictionary properties,
        CosObject Function(CosObject) copy) {
      final defaults = owner.resolve(properties['D']);
      final config = defaults is CosDictionary ? defaults : CosDictionary();
      final states = Map<CosDictionary, (CosObject, bool)>.identity();

      List<CosObject> items(CosObject? raw) {
        final value = owner.resolve(raw);
        return value is CosArray ? value.items : const [];
      }

      void register(Iterable<CosObject> values, bool visible) {
        for (final value in values) {
          final group = owner.resolve(value);
          if (group is CosDictionary) states[group] = (value, visible);
        }
      }

      register(items(properties['OCGs']),
          owner.resolve(config['BaseState']) != const CosName('OFF'));
      register(items(config['ON']), true);
      register(items(config['OFF']), false);
      for (final (value, visible) in states.values) {
        final mapped = copy(value);
        groups.add(mapped);
        (visible ? on : off).add(mapped);
      }
      for (final item in items(config['AS'])) {
        final application = owner.resolve(item);
        if (application is! CosDictionary) continue;
        final targets = items(application['OCGs']);
        applications.add(CosDictionary({
          for (final entry in application.entries.entries)
            if (entry.key != 'OCGs') entry.key: copy(entry.value),
          // Missing or empty means all groups in this input, not all groups
          // in the eventual merged document (§8.11.4.5).
          'OCGs': CosArray([
            for (final group in targets.isEmpty
                ? states.values.map((entry) => entry.$1)
                : targets)
              copy(group),
          ]),
        }));
      }
    }

    if (previous is CosDictionary) append(cos, previous, (value) => value);
    append(source, incoming, importer.copyValue);
    final oldDefaults =
        previous is CosDictionary ? cos.resolve(previous['D']) : null;
    document.catalog['OCProperties'] = CosDictionary({
      if (previous is CosDictionary) ...previous.entries,
      'OCGs': CosArray(groups),
      'D': CosDictionary({
        if (oldDefaults is CosDictionary) ...oldDefaults.entries,
        'BaseState': const CosName('OFF'),
        'ON': CosArray(on),
        'OFF': CosArray(off),
        if (applications.isNotEmpty) 'AS': CosArray(applications),
      }),
    });
    _updater.markChanged(document.catalog);
  }

  void _mergeFormFields(_PageImporter importer) {
    if (importer._formRoots.isEmpty) return;
    final cos = document.cos;
    final source = importer.source.cos;
    final sourceForm = source.resolve(importer.source.catalog['AcroForm']);
    final previous = cos.resolve(document.catalog['AcroForm']);
    // Reassign the catalog entry: /AcroForm and its /Fields or /DR may all
    // have been indirect. Mutating a resolved array would not stage its owner.
    final form = CosDictionary({
      if (previous is CosDictionary) ...previous.entries,
    });
    if (sourceForm is CosDictionary &&
        source.resolve(sourceForm['NeedAppearances']) ==
            const CosBoolean(true)) {
      form['NeedAppearances'] = const CosBoolean(true);
    }
    final fields = cos.resolve(form['Fields']);
    final roots = <CosObject>[if (fields is CosArray) ...fields.items];
    final used = <String>{};
    for (final root in roots) {
      final dict = cos.resolve(root);
      final name = dict is CosDictionary ? cos.resolve(dict['T']) : null;
      if (name is CosString) used.add(name.text);
    }

    final renames = <String, Map<String, String>>{};
    final oldResources = cos.resolve(form['DR']);
    final resources = CosDictionary({
      if (oldResources is CosDictionary) ...oldResources.entries,
    });
    final sourceResources =
        sourceForm is CosDictionary ? source.resolve(sourceForm['DR']) : null;
    if (sourceResources is CosDictionary) {
      for (final entry in sourceResources.entries.entries) {
        final incoming = source.resolve(entry.value);
        final existing = cos.resolve(resources[entry.key]);
        if (incoming is! CosDictionary) continue;
        final category = CosDictionary({
          if (existing is CosDictionary) ...existing.entries,
        });
        final names = category.entries.keys.toSet();
        final mapping = renames[entry.key] = {};
        for (final resource in incoming.entries.entries) {
          final name = _uniqueImportName(resource.key, names);
          mapping[resource.key] = name;
          category[name] = importer.copyValue(resource.value);
        }
        resources[entry.key] = category;
      }
    }
    if (resources.entries.isNotEmpty) form['DR'] = resources;

    for (final root in importer._formRoots) {
      final original = source.referenceTo(root) ?? root;
      final copied = importer.copyValue(original);
      final dict = importer._dictionaries[root]!;
      final name = source.resolve(root['T']);
      dict['T'] = CosString.fromText(
          _uniqueImportName(name is CosString ? name.text : 'Imported', used));
      dict.entries.remove('Parent');
      // Form-level defaults belonged to the source. Materialize them on its
      // roots so the destination's /DA and /Q cannot change imported fields.
      if (sourceForm is CosDictionary) {
        for (final key in ['DA', 'Q']) {
          if (!dict.containsKey(key) && sourceForm.containsKey(key)) {
            dict[key] = importer.copyValue(sourceForm[key]!);
          }
        }
      }
      roots.add(copied is CosReference ? copied : _updater.addObject(dict));
    }
    for (final node in importer._formNodes) {
      final dict = importer._dictionaries[node];
      if (dict == null) continue;
      final da = cos.resolve(dict['DA']);
      if (da is CosString) dict['DA'] = _remapDefaultAppearance(da, renames);
    }
    final calculationOrder =
        sourceForm is CosDictionary ? source.resolve(sourceForm['CO']) : null;
    if (calculationOrder is CosArray) {
      final previousOrder = cos.resolve(form['CO']);
      form['CO'] = CosArray([
        if (previousOrder is CosArray) ...previousOrder.items,
        for (final field in calculationOrder.items)
          if (importer._formNodes.contains(source.resolve(field)))
            importer.copyValue(field),
      ]);
    }
    form['Fields'] = CosArray(roots);
    document.catalog['AcroForm'] = form;
    _updater.markChanged(document.catalog);
  }

  void _mergeNamedDestinations(_PageImporter importer) {
    final incoming = _namedDestinations(importer.source);
    if (incoming.isEmpty) return;
    final existing = _namedDestinations(document);
    final used = existing.keys.toSet();
    for (final entry in incoming.entries) {
      final dest = importer.copyDestination(entry.value);
      if (dest is! CosArray || dest[0] is CosNull) continue;
      existing[_uniqueImportName(entry.key, used)] = dest;
    }
    final keys = existing.keys.toList()
      ..sort((a, b) {
        final aa = CosString.fromText(a).bytes;
        final bb = CosString.fromText(b).bytes;
        for (var i = 0; i < math.min(aa.length, bb.length); i++) {
          if (aa[i] != bb[i]) return aa[i].compareTo(bb[i]);
        }
        return aa.length.compareTo(bb.length);
      });
    final oldNames = document.cos.resolve(document.catalog['Names']);
    document.catalog['Names'] = CosDictionary({
      if (oldNames is CosDictionary) ...oldNames.entries,
      'Dests': CosDictionary({
        'Names': CosArray([
          for (final key in keys) ...[CosString.fromText(key), existing[key]!],
        ]),
      }),
    });
    _updater.markChanged(document.catalog);
  }

  List<CosReference> _importOutlineChildren(
      _PageImporter importer, CosDictionary parent, Set<CosDictionary> seen) {
    final cos = importer.source.cos;
    final out = <CosReference>[];
    var node = cos.resolve(parent['First']);
    while (node is CosDictionary && seen.add(node)) {
      final dict = CosDictionary();
      for (final key in ['Title', 'C', 'F', 'A', 'Dest']) {
        final value = node[key];
        if (value != null) {
          dict[key] = key == 'Dest'
              ? importer.copyDestination(value)
              : importer.copyValue(value);
        }
      }
      final ref = _updater.addObject(dict);
      final count = cos.resolve(node['Count']);
      _outlineOpenOverride[ref.objectNumber] =
          count is! CosInteger || count.value >= 0;
      final children = _importOutlineChildren(importer, node, seen);
      _relinkOutlineChildren(ref, children);
      out.add(ref);
      node = cos.resolve(node['Next']);
    }
    return out;
  }
}

String _uniqueImportName(String requested, Set<String> used) {
  var name = requested;
  for (var suffix = 2; !used.add(name); suffix++) {
    name = '${requested}_$suffix';
  }
  return name;
}

Map<String, CosObject> _namedDestinations(PdfDocument document) {
  final cos = document.cos;
  final legacy = cos.resolve(document.catalog['Dests']);
  final result = <String, CosObject>{
    if (legacy is CosDictionary) ...legacy.entries,
  };
  final seen = <CosDictionary>{};
  void walk(CosObject? value) {
    final node = cos.resolve(value);
    if (node is! CosDictionary || !seen.add(node)) return;
    final names = cos.resolve(node['Names']);
    if (names is CosArray) {
      for (var i = 0; i + 1 < names.length; i += 2) {
        final name = cos.resolve(names[i]);
        if (name is CosString) {
          result.putIfAbsent(name.text, () => names[i + 1]);
        }
      }
    }
    final kids = cos.resolve(node['Kids']);
    if (kids is CosArray) {
      for (final kid in kids.items) {
        walk(kid);
      }
    }
  }

  final names = cos.resolve(document.catalog['Names']);
  if (names is CosDictionary) walk(names['Dests']);
  return result;
}

CosString _remapDefaultAppearance(
    CosString da, Map<String, Map<String, String>> renames) {
  final operations = ContentStreamParser.parse(da.bytes);
  for (final op in operations) {
    final category = switch (op.operator) {
      'Tf' => 'Font',
      'gs' => 'ExtGState',
      'CS' || 'cs' => 'ColorSpace',
      'SCN' || 'scn' => 'Pattern',
      _ => null,
    };
    final mapping = renames[category];
    if (mapping == null) continue;
    for (var i = 0; i < op.operands.length; i++) {
      final value = op.operands[i];
      if (value is CosName && mapping.containsKey(value.value)) {
        op.operands[i] = CosName(mapping[value.value]!);
      }
    }
  }
  return CosString(ContentStreamSerializer.serialize(operations));
}
