import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:pdf_cos/pdf_cos.dart';

import 'compressor_font_program.dart';
import 'document.dart';

/// Results of the conservative, glyph-ID-preserving font optimization pass.
class PdfFontOptimizationStats {
  const PdfFontOptimizationStats({
    this.fontsSubset = 0,
    this.bytesSaved = 0,
    this.warnings = const [],
  });

  final int fontsSubset;
  final int bytesSaved;
  final List<String> warnings;
}

/// Subsets supported embedded composite fonts in [document]'s cached COS
/// graph. The caller must serialize the graph, rather than copying its original
/// object bytes, to persist the replacements.
///
/// Glyph IDs, widths, encodings and Unicode maps stay unchanged. Every text
/// string in page content, appearances, forms, tiling patterns and Type 3
/// charprocs contributes to a conservative union of character codes. Using the
/// union deliberately retains some extra glyphs: inherited text state and
/// shared resource names cannot cause a glyph to be accidentally discarded.
/// Fonts accessible to interactive form fields are retained in full.
PdfFontOptimizationStats subsetPdfFonts(PdfDocument document) {
  final scan = _FontScan(document);
  try {
    scan.collect();
  } on Object {
    return const PdfFontOptimizationStats(warnings: [
      'Font subsetting was skipped because some document content could not '
          'be inspected safely.',
    ]);
  }
  final warnings = <String>{};
  var fontsSubset = 0;
  var bytesSaved = 0;
  for (final entry in scan.programs.entries) {
    final stream = entry.key;
    final consumers = entry.value;
    if (scan.protectedPrograms.contains(stream)) {
      warnings.add('Fonts used by editable form fields were retained in full.');
      continue;
    }
    if (consumers.any((font) => font == null)) {
      warnings.add('Simple fonts, Type 1 fonts and fonts with custom CMaps '
          'were retained because their glyph usage is not unambiguous.');
      continue;
    }
    // A font stream aliased as an attachment or another non-font object must
    // remain byte-identical for that other consumer.
    if (scan.nonFontAliases.contains(stream) ||
        (scan.streamParents[stream]?.any((parent) =>
                parent.$2 != 'FontFile2' && parent.$2 != 'FontFile3') ??
            false)) {
      warnings.add('A font program shared with another object was retained.');
      continue;
    }
    try {
      final decoded = Uint8List.fromList(document.cos.decodeStreamData(stream));
      final program = PdfSubsetFontProgram.parse(decoded);
      final glyphs = <int>{0};
      for (final font in consumers.nonNulls) {
        final mapping = document.cos.resolve(font['CIDToGIDMap']);
        if (mapping is CosStream) {
          final bytes = document.cos.decodeStreamData(mapping);
          if (bytes.length.isOdd) {
            throw const FormatException('Odd CIDToGIDMap length');
          }
          for (final code in scan.codes) {
            if (code * 2 + 1 < bytes.length) {
              glyphs.add((bytes[code * 2] << 8) | bytes[code * 2 + 1]);
            }
          }
        } else if (mapping is CosNull ||
            mapping is CosName && mapping.value == 'Identity') {
          for (final code in scan.codes) {
            glyphs.add(program.glyphForCid(code));
          }
        } else {
          throw const FormatException('Unsupported CIDToGIDMap');
        }
      }
      final subset = program.subset(glyphs);
      if (subset == null) continue;
      final compressed = Uint8List.fromList(ZLibEncoder().encode(subset));
      if (compressed.length >= stream.rawBytes.length) continue;
      final dictionary = CosDictionary(Map.of(stream.dictionary.entries))
        ..['Filter'] = const CosName('FlateDecode')
        ..['Length'] = CosInteger(compressed.length);
      dictionary.entries.remove('DecodeParms');
      if (dictionary.containsKey('Length1')) {
        dictionary['Length1'] = CosInteger(subset.length);
      }
      final replacement = CosStream(dictionary, compressed);
      final ref = document.cos.referenceTo(stream);
      if (ref != null) document.cos.adoptObject(ref, replacement);
      // Update direct aliases as well; reference aliases resolve through the
      // freshly adopted object above.
      for (final parent in scan.streamParents[stream] ?? const []) {
        if (identical(parent.$1[parent.$2], stream)) {
          parent.$1[parent.$2] = replacement;
        }
      }
      scan.renameSubset(consumers.nonNulls.toSet(), subset);
      fontsSubset++;
      bytesSaved += stream.rawBytes.length - compressed.length;
    } on Object catch (error) {
      warnings.add('An embedded font was retained: '
          '${error is FormatException ? error.message : 'unsupported or malformed font program'}.');
    }
  }
  return PdfFontOptimizationStats(
    fontsSubset: fontsSubset,
    bytesSaved: bytesSaved,
    warnings: warnings.toList(),
  );
}

class _FontScan {
  _FontScan(this.document);

  final PdfDocument document;
  CosDocument get cos => document.cos;
  final codes = <int>{};
  final programs = Map<CosStream, List<CosDictionary?>>.identity();
  final streamParents =
      Map<CosStream, List<(CosDictionary, String)>>.identity();
  final protectedPrograms = Set<CosStream>.identity();
  final nonFontAliases = Set<CosStream>.identity();
  final _dictionaries = Set<CosDictionary>.identity();
  final _streams = Set<CosStream>.identity();
  final _content = Set<CosStream>.identity();
  final _pages = Set<CosDictionary>.identity();

  void renameSubset(Set<CosDictionary> hosts, Uint8List bytes) {
    final tag = String.fromCharCodes(
        sha256.convert(bytes).bytes.take(6).map((value) => 65 + value % 26));
    void rename(CosDictionary dictionary, String key) {
      final original = _name(dictionary[key]);
      if (original == null) return;
      final name = original.replaceFirst(RegExp(r'^[A-Z]{6}\+'), '');
      dictionary[key] = CosName('$tag+$name');
    }

    for (final host in hosts) {
      rename(host, 'BaseFont');
      final descriptor = cos.resolve(host['FontDescriptor']);
      if (descriptor is CosDictionary) rename(descriptor, 'FontName');
    }
    for (final dictionary in _dictionaries) {
      final descendants = cos.resolve(dictionary['DescendantFonts']);
      if (descendants is CosArray &&
          descendants.items.any((item) => hosts.contains(cos.resolve(item)))) {
        rename(dictionary, 'BaseFont');
      }
    }
  }

  void collect() {
    _pages.addAll(document.pages.map((page) => page.dict));
    _walk(cos.trailer, (object) {
      if (object is CosStream) {
        _streams.add(object);
        if (_name(object.dictionary['Subtype']) == 'Form' ||
            _integer(object.dictionary['PatternType']) == 1) {
          _content.add(object);
        }
      }
      if (object is CosArray) {
        for (final item in object.items) {
          final value = cos.resolve(item);
          if (value is CosStream) nonFontAliases.add(value);
        }
      }
      if (object is! CosDictionary) return;
      _dictionaries.add(object);
      for (final entry in object.entries.entries) {
        final value = cos.resolve(entry.value);
        if (value is CosStream) {
          streamParents.putIfAbsent(value, () => []).add((object, entry.key));
        }
      }
      if (_name(object['Type']) == 'Page' || _pages.contains(object)) {
        final contents = cos.resolve(object['Contents']);
        if (contents is CosStream) _content.add(contents);
        if (contents is CosArray) {
          // Stream arrays are one logical byte stream. Join before parsing so
          // an operand or even a string split over streams remains visible.
          final bytes = BytesBuilder();
          for (final item in contents.items) {
            final stream = cos.resolve(item);
            if (stream is! CosStream) continue;
            _content.add(stream);
            bytes.add(cos.decodeStreamData(stream));
            bytes.addByte(10);
          }
          _collectCodes(bytes.takeBytes());
        }
      }
      for (final key in ['AP', 'CharProcs']) {
        final value = object[key];
        if (value != null) {
          _walk(value, (child) {
            if (child is CosStream) _content.add(child);
          }, stopAtStream: true);
        }
      }
    });

    final root = cos.resolve(cos.trailer['Root']);
    if (root is CosDictionary && root['AcroForm'] != null) {
      _walk(root['AcroForm']!, (object) {
        if (object is CosDictionary) {
          for (final key in ['FontFile', 'FontFile2', 'FontFile3']) {
            final stream = cos.resolve(object[key]);
            if (stream is CosStream) protectedPrograms.add(stream);
          }
        }
      }, skipBacklinks: true);
    }

    final descendants = Set<CosDictionary>.identity();
    for (final dictionary in _dictionaries) {
      final raw = cos.resolve(dictionary['DescendantFonts']);
      if (raw is! CosArray) continue;
      for (final value in raw.items) {
        final child = cos.resolve(value);
        if (child is CosDictionary) descendants.add(child);
      }
    }
    for (final dictionary in _dictionaries) {
      if (descendants.contains(dictionary)) continue;
      var host = dictionary;
      final raw = cos.resolve(dictionary['DescendantFonts']);
      if (raw is CosArray && raw.items.length != 1) {
        // Readers recover malformed multi-descendant fonts differently. Every
        // listed program is therefore an unsupported consumer, including a
        // program shared by an otherwise eligible, differently encoded font.
        for (final value in raw.items) {
          final child = cos.resolve(value);
          if (child is! CosDictionary) continue;
          final descriptor = cos.resolve(child['FontDescriptor']);
          if (descriptor is! CosDictionary) continue;
          for (final key in ['FontFile', 'FontFile2', 'FontFile3']) {
            final stream = cos.resolve(descriptor[key]);
            if (stream is CosStream) {
              programs.putIfAbsent(stream, () => []).add(null);
            }
          }
        }
        continue;
      }
      if (raw is CosArray && raw.items.length == 1) {
        final child = cos.resolve(raw.items.single);
        if (child is CosDictionary) host = child;
      }
      final descriptor = cos.resolve(host['FontDescriptor']);
      if (descriptor is! CosDictionary) continue;
      final encoding = _name(dictionary['Encoding']);
      final subtype = _name(host['Subtype']);
      final supported = _name(dictionary['Subtype']) == 'Type0' &&
          (encoding == 'Identity-H' || encoding == 'Identity-V') &&
          (subtype == 'CIDFontType2' || subtype == 'CIDFontType0');
      for (final key in ['FontFile', 'FontFile2', 'FontFile3']) {
        final stream = cos.resolve(descriptor[key]);
        if (stream is CosStream) {
          programs.putIfAbsent(stream, () => []).add(supported ? host : null);
        }
      }
    }
    for (final stream in _content) {
      _collectCodes(Uint8List.fromList(cos.decodeStreamData(stream)));
    }
    // PostScript and external stream files may paint text without exposing
    // PDF show-text operators to the scanner. Retain fonts in those documents.
    if (_streams.any((stream) =>
        _name(stream.dictionary['Subtype']) == 'PS' ||
        stream.dictionary.containsKey('F'))) {
      throw const FormatException('External or PostScript content');
    }
  }

  void _collectCodes(Uint8List bytes) {
    void text(CosObject value) {
      if (value is CosString) {
        for (var i = 0; i + 1 < value.bytes.length; i += 2) {
          codes.add((value.bytes[i] << 8) | value.bytes[i + 1]);
        }
        if (value.bytes.length.isOdd) codes.add(value.bytes.last);
      } else if (value is CosArray) {
        for (final child in value.items) {
          text(child);
        }
      }
    }

    final cursor = ContentStreamParser.cursor(bytes);
    ContentOperation? operation;
    while ((operation = cursor.nextOperation()) != null) {
      if (const {'Tj', 'TJ', "'", '"'}.contains(operation!.operator)) {
        for (final operand in operation.operands) {
          text(operand);
        }
      }
    }
  }

  void _walk(CosObject start, void Function(CosObject) visit,
      {bool stopAtStream = false, bool skipBacklinks = false}) {
    final seen = Set<CosObject>.identity();
    final pending = <CosObject>[start];
    while (pending.isNotEmpty) {
      final object = cos.resolve(pending.removeLast());
      if (!seen.add(object)) continue;
      // Resource aliases are arbitrary names: /P and /Parent may themselves
      // name a font in /DR /Font. Stop at actual page objects instead of
      // treating those key spellings as structural backlinks everywhere.
      if (skipBacklinks &&
          object is CosDictionary &&
          (_pages.contains(object) ||
              _name(object['Type']) == 'Page' ||
              _name(object['Type']) == 'Pages')) {
        continue;
      }
      if (seen.length > 1000000) {
        throw const FormatException('Document object limit');
      }
      visit(object);
      if (object is CosStream) {
        if (!stopAtStream) pending.add(object.dictionary);
      } else if (object is CosDictionary) {
        for (final entry in object.entries.entries) {
          pending.add(entry.value);
        }
      } else if (object is CosArray) {
        pending.addAll(object.items);
      }
    }
  }

  String? _name(CosObject? object) {
    final resolved = cos.resolve(object);
    return resolved is CosName ? resolved.value : null;
  }

  int? _integer(CosObject? object) {
    final resolved = cos.resolve(object);
    return resolved is CosInteger ? resolved.value : null;
  }
}
