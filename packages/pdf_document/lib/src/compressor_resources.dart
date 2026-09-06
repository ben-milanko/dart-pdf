import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pdf_cos/pdf_cos.dart';

import 'document.dart';

class PdfResourceOptimizationStats {
  const PdfResourceOptimizationStats(this.resourcesRemoved, this.warnings);
  final int resourcesRemoved;
  final List<String> warnings;
}

const _categories = {
  'Font',
  'XObject',
  'ColorSpace',
  'ExtGState',
  'Pattern',
  'Shading',
  'Properties',
};

/// Conservative resource-name liveness. Names are unioned across all consumers
/// before modifying any dictionary: inherited/shared resources, annotation
/// states, Type 3 glyphs and resource-less forms cannot lose a dependency just
/// because it is used on another page. This can retain some unused aliases.
/// AcroForm default resources are kept for subsequent field editing.
PdfResourceOptimizationStats prunePdfResources(PdfDocument document) {
  final cos = document.cos;
  final graph = _reachable(cos);
  final used = <String>{'DefaultGray', 'DefaultRGB', 'DefaultCMYK'};
  final resources = <CosDictionary>{};
  final protected = <CosDictionary>{};
  final parsed = <CosStream>{};

  void names(CosObject value) {
    switch (value) {
      case CosName(:final value):
        used.add(value);
      case CosArray(:final items):
        items.forEach(names);
      case CosDictionary(:final entries):
        entries.values.forEach(names);
      default:
        break;
    }
  }

  void content(Uint8List bytes) {
    final cursor = ContentStreamParser.cursor(bytes);
    ContentOperation? op;
    while ((op = cursor.nextOperation()) != null) {
      if (op!.numberOperands == null) op.operands.forEach(names);
    }
  }

  void stream(CosObject? value) {
    final resolved = cos.resolve(value);
    if (resolved is CosStream && parsed.add(resolved)) {
      content(cos.decodeStreamData(resolved));
    }
  }

  void appearances(CosObject? value, Set<CosObject> visited) {
    final resolved = cos.resolve(value);
    if (!visited.add(resolved)) return;
    if (resolved is CosStream) {
      stream(resolved);
    } else if (resolved is CosDictionary) {
      for (final value in resolved.entries.values) {
        appearances(value, visited);
      }
    }
  }

  try {
    for (final object in graph) {
      // Resource aliases can occur in non-content dictionaries too (an
      // image's named /ColorSpace, or a Pattern's colour-space operands).
      if (object is CosName) used.add(object.value);
      final dict = switch (object) {
        CosStream(:final dictionary) => dictionary,
        CosDictionary() => object,
        _ => null,
      };
      if (dict == null) continue;
      final dr = cos.resolve(dict['DR']);
      if (dr is CosDictionary) protected.add(dr);
      final res = cos.resolve(dict['Resources']);
      if (res is CosDictionary) {
        resources.add(res);
        final known = dict.typeName == 'Page' ||
            dict.typeName == 'Pages' ||
            dict['Subtype'] == const CosName('Form') ||
            dict['Subtype'] == const CosName('Type3') ||
            dict['PatternType'] == const CosInteger(1);
        if (!known) protected.add(res);
      }
      final da = cos.resolve(dict['DA']);
      if (da is CosString) content(da.bytes);
      if (dict.containsKey('AP')) appearances(dict['AP'], <CosObject>{});
      final chars = cos.resolve(dict['CharProcs']);
      if (chars is CosDictionary) chars.entries.values.forEach(stream);
      if (object is CosStream &&
          (dict['Subtype'] == const CosName('Form') ||
              dict['PatternType'] == const CosInteger(1))) {
        stream(object);
      }
      if (dict['Subtype'] == const CosName('PS')) {
        return const PdfResourceOptimizationStats(
            0, ['Resources used by PostScript XObjects were preserved.']);
      }
    }
    for (var i = 0; i < document.pageCount; i++) {
      final page = document.page(i);
      resources.add(page.resources);
      final contents = cos.resolve(page.dict['Contents']);
      final chunks = contents is CosArray ? contents.items : [contents];
      final bytes = BytesBuilder(copy: false);
      for (final chunk in chunks) {
        final source = cos.resolve(chunk);
        if (source is CosNull) continue;
        if (source is! CosStream) {
          throw const FormatException('Invalid page content stream');
        }
        // Do not use page.contentBytes: its lenient decode-failure skip
        // would make a resource used by a broken stream appear dead.
        bytes.add(cos.decodeStreamData(source));
        bytes.addByte(10);
      }
      content(bytes.takeBytes());
    }
  } on Object {
    return const PdfResourceOptimizationStats(0, [
      'Unused-resource cleanup was skipped because some content could not '
          'be analysed safely.',
    ]);
  }

  var removed = 0;
  for (final res in resources.difference(protected)) {
    for (final category in _categories) {
      final entries = cos.resolve(res[category]);
      if (entries is! CosDictionary) continue;
      final kept = <String, CosObject>{};
      for (final entry in entries.entries.entries) {
        if (used.contains(entry.key)) {
          kept[entry.key] = entry.value;
        } else {
          removed++;
        }
      }
      // Reassign rather than mutating a shared/indirect category dictionary.
      if (kept.length != entries.entries.length) {
        res[category] = CosDictionary(kept);
      }
    }
  }
  return PdfResourceOptimizationStats(removed, const []);
}

/// Coalesces exactly equivalent image, embedded-font and ICC stream objects.
/// Fingerprints include ALL dictionary semantics (except stored /Length),
/// recursively resolved references and the complete encoded payload. Different
/// masks, colour profiles, decode arrays or font subtype never compare equal.
int deduplicatePdfResources(PdfDocument document) {
  final cos = document.cos;
  final graph = _reachable(cos);
  final candidates = <CosStream>{};
  for (final object in graph) {
    if (object is CosStream &&
        object.dictionary['Subtype'] == const CosName('Image')) {
      candidates.add(object);
    }
    if (object is CosDictionary) {
      for (final key in const ['FontFile', 'FontFile2', 'FontFile3']) {
        final file = cos.resolve(object[key]);
        if (file is CosStream) candidates.add(file);
      }
    }
    if (object is CosArray &&
        object.length >= 2 &&
        cos.resolve(object[0]) == const CosName('ICCBased')) {
      final profile = cos.resolve(object[1]);
      if (profile is CosStream) candidates.add(profile);
    }
  }
  final seen = <String, CosReference>{};
  final remap = <CosReference, CosReference>{};
  for (final stream in candidates) {
    final ref = cos.referenceTo(stream);
    if (ref == null ||
        stream.dictionary.containsKey('StructParent') ||
        stream.dictionary.containsKey('StructParents')) {
      continue;
    }
    final fingerprint = _fingerprint(cos, stream, <CosObject>{});
    if (fingerprint == null) continue;
    final key = sha256.convert(utf8.encode(fingerprint)).toString();
    final existing = seen[key];
    if (existing == null) {
      seen[key] = ref;
    } else {
      remap[ref] = existing;
    }
  }
  if (remap.isEmpty) return 0;
  for (final object in graph) {
    if (object is CosArray) {
      for (var i = 0; i < object.length; i++) {
        object.items[i] = remap[object[i]] ?? object[i];
      }
    } else if (object is CosDictionary) {
      for (final key in object.entries.keys.toList()) {
        object[key] = remap[object[key]] ?? object[key]!;
      }
    }
  }
  return remap.length;
}

String? _fingerprint(CosDocument cos, CosObject source, Set<CosObject> active,
    [int depth = 0]) {
  if (depth > 64) return null;
  final object = cos.resolve(source);
  if (!active.add(object)) return null;
  try {
    if (object is CosStream || object is CosDictionary) {
      final dict =
          object is CosStream ? object.dictionary : object as CosDictionary;
      // Equal dictionaries need not identify the same visibility/structure
      // node: one OCG can be on while an otherwise identical OCG is off.
      if (const ['OC', 'StructParent', 'StructParents'].any(dict.containsKey)) {
        return null;
      }
      final keys = dict.entries.keys
          .where((k) => object is! CosStream || k != 'Length')
          .toList()
        ..sort();
      final parts = <String>[];
      for (final key in keys) {
        final value = _fingerprint(cos, dict[key]!, active, depth + 1);
        if (value == null) return null;
        parts.add('${jsonEncode(key)}:$value');
      }
      final payload =
          object is CosStream ? ':${sha256.convert(object.rawBytes)}' : '';
      return '{${parts.join(',')}}$payload';
    }
    if (object is CosArray) {
      final values = <String>[];
      for (final item in object.items) {
        final value = _fingerprint(cos, item, active, depth + 1);
        if (value == null) return null;
        values.add(value);
      }
      return '[${values.join(',')}]';
    }
    return switch (object) {
      CosString(:final bytes) => 's:${base64Encode(bytes)}',
      CosName(:final value) => 'n:${jsonEncode(value)}',
      CosInteger(:final value) => 'v:$value',
      CosReal(:final value) => 'v:${CosSerializer.formatRealExact(value)}',
      _ => object.toString(),
    };
  } finally {
    active.remove(object);
  }
}

List<CosObject> _reachable(CosDocument cos) {
  final found = <CosObject>[];
  final visited = Set<CosObject>.identity();
  final stack = <CosObject>[cos.catalog, cos.resolve(cos.trailer['Info'])];
  while (stack.isNotEmpty) {
    final object = cos.resolve(stack.removeLast());
    if (!visited.add(object)) continue;
    found.add(object);
    switch (object) {
      case CosStream(:final dictionary):
        stack.add(dictionary);
      case CosDictionary(:final entries):
        stack.addAll(entries.values);
      case CosArray(:final items):
        stack.addAll(items);
      default:
        break;
    }
  }
  return found;
}
