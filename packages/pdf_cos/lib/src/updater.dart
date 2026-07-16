import 'dart:typed_data';

import 'crypto/standard_security_handler.dart';
import 'document.dart';
import 'objects.dart';
import 'serializer.dart';
import 'xref.dart';

/// Writes changes to a document as an incremental update: the original bytes
/// are preserved verbatim and changed objects plus a new cross-reference
/// section are appended (§7.5.6). This keeps existing digital signatures
/// valid and makes every edit reversible.
///
/// Encrypted documents re-encrypt on write: queued objects hold plaintext
/// (strings decrypt at load; editors build plaintext streams), so each one
/// is serialized as an encrypted copy under its own object key. Stream
/// payloads still carrying the file's original ciphertext are written
/// verbatim.
class CosIncrementalUpdater {
  CosIncrementalUpdater(this.document) {
    var next = document.declaredSize;
    if (next < 1) next = 1;
    // distrust /Size: some writers get it wrong
    for (final number in document.objectNumbers) {
      if (number >= next) next = number + 1;
    }
    _nextObjectNumber = next;
  }

  final CosDocument document;

  final Map<int, CosObject> _changed = {};
  final Map<String, CosObject> _trailerOverrides = {};
  late int _nextObjectNumber;

  bool get hasChanges => _changed.isNotEmpty || _trailerOverrides.isNotEmpty;

  /// Queues a replacement for an existing object number.
  void replaceObject(int objectNumber, CosObject object) {
    _changed[objectNumber] = object;
  }

  /// Allocates a fresh object number for [object] and returns its reference.
  /// The object is also adopted into the document's cache, so references to
  /// it resolve immediately - edits can build on each other before [save].
  CosReference addObject(CosObject object) {
    final number = _nextObjectNumber++;
    _changed[number] = object;
    final ref = CosReference(number, 0);
    document.adoptObject(ref, object);
    return ref;
  }

  /// Marks an object that was loaded (and then mutated in place) as changed,
  /// so its current state is written with the update.
  CosReference markChanged(CosObject object) {
    final ref = document.referenceTo(object);
    if (ref == null) {
      throw ArgumentError(
          'object was not loaded from this document; use addObject');
    }
    _changed[ref.objectNumber] = object;
    return ref;
  }

  /// Overrides a trailer entry in the update, e.g. a new /Info reference.
  void setTrailerEntry(String key, CosObject value) {
    _trailerOverrides[key] = value;
  }

  /// Returns the full bytes of the updated file: original + appended update.
  Uint8List save() {
    final out = BytesBuilder(copy: false)..add(document.bytes);
    final last = document.bytes.isEmpty ? 0x0A : document.bytes.last;
    if (last != 0x0A && last != 0x0D) out.addByte(0x0A);

    // xref offsets are relative to the %PDF- header, which may not be byte 0
    final shift = document.headerOffset;
    final offsets = <int, int>{};
    final serializer = CosSerializer(out);

    final handler = document.encryption;
    final changedNumbers = _changed.keys.toList()..sort();
    for (final number in changedNumbers) {
      offsets[number] = out.length - shift;
      var object = _changed[number]!;
      if (handler != null && number != document.encryptObjectNumber) {
        object = _encryptedCopy(object, number, _generationOf(number), handler);
      }
      serializer.writeIndirectObject(
          CosIndirectObject(number, _generationOf(number), object));
    }

    // a file whose newest xref is a stream must be updated with a stream;
    // a classic-table file is updated with a classic table (§7.5.8.4)
    final xrefOffset = out.length - shift;
    if (document.trailer.typeName == 'XRef') {
      _writeXrefStream(serializer, offsets, xrefOffset);
    } else {
      _writeXrefTable(out, offsets);
    }
    _writeText(out, 'startxref\n$xrefOffset\n%%EOF\n');
    return out.takeBytes();
  }

  /// Deep-copies [object] with strings and stream payloads encrypted under
  /// the (number, generation) object key. The live object stays plaintext
  /// so later edits in the same session keep working. Cross-reference
  /// streams and exempt /Metadata stay plain (§7.5.8.2); payloads still
  /// holding the file's ciphertext pass through untouched.
  CosObject _encryptedCopy(CosObject object, int number, int generation,
      StandardSecurityHandler handler) {
    CosObject copy(CosObject value) {
      switch (value) {
        case CosString():
          return CosString(
              handler.encryptString(value.bytes, number, generation),
              isHex: value.isHex);
        case CosArray():
          return CosArray([for (final item in value.items) copy(item)]);
        case CosStream():
          final dict = copy(value.dictionary) as CosDictionary;
          if (document.streamKeepsFileBytes(value)) {
            return CosStream(dict, value.rawBytes);
          }
          final type = dict['Type'];
          final exempt = type is CosName &&
              (type.value == 'XRef' ||
                  type.value == 'Metadata' && !handler.encryptMetadata);
          if (exempt) return CosStream(dict, value.rawBytes);
          final cipher =
              handler.encryptStream(value.rawBytes, number, generation);
          dict['Length'] = CosInteger(cipher.length);
          return CosStream(dict, cipher);
        case CosDictionary():
          final out = CosDictionary();
          value.entries.forEach((key, v) => out[key] = copy(v));
          return out;
        default:
          return value;
      }
    }

    return copy(object);
  }

  int _generationOf(int objectNumber) {
    final entry = document.xrefEntry(objectNumber);
    return entry != null && entry.type == CosXrefEntryType.inUse
        ? entry.generation
        : 0;
  }

  CosDictionary _buildTrailer() {
    final trailer = CosDictionary();
    trailer['Size'] = CosInteger(_nextObjectNumber);
    trailer['Prev'] = CosInteger(document.startXref);
    for (final key in const ['Root', 'Info', 'Encrypt', 'ID']) {
      final value = document.trailer[key];
      if (value != null) trailer[key] = value;
    }
    _trailerOverrides.forEach((key, value) => trailer[key] = value);
    return trailer;
  }

  /// Groups sorted object numbers into runs of consecutive numbers.
  static List<List<int>> _runsOf(List<int> sorted) {
    final runs = <List<int>>[];
    for (final number in sorted) {
      if (runs.isEmpty || runs.last.last != number - 1) {
        runs.add([number]);
      } else {
        runs.last.add(number);
      }
    }
    return runs;
  }

  void _writeXrefTable(BytesBuilder out, Map<int, int> offsets) {
    _writeText(out, 'xref\n');
    for (final run in _runsOf(offsets.keys.toList()..sort())) {
      _writeText(out, '${run.first} ${run.length}\n');
      for (final number in run) {
        final offset = offsets[number]!.toString().padLeft(10, '0');
        final generation = _generationOf(number).toString().padLeft(5, '0');
        _writeText(out, '$offset $generation n \n');
      }
    }
    _writeText(out, 'trailer\n');
    CosSerializer(out).writeObject(_buildTrailer());
    _writeText(out, '\n');
  }

  void _writeXrefStream(
      CosSerializer serializer, Map<int, int> offsets, int xrefOffset) {
    // the cross-reference stream is itself an object and lists itself
    final streamNumber = _nextObjectNumber++;
    offsets[streamNumber] = xrefOffset;

    final sorted = offsets.keys.toList()..sort();
    final runs = _runsOf(sorted);
    final data = BytesBuilder();
    for (final number in sorted) {
      final offset = offsets[number]!;
      data
        ..addByte(1) // type 1: in use
        ..addByte((offset >> 24) & 0xFF)
        ..addByte((offset >> 16) & 0xFF)
        ..addByte((offset >> 8) & 0xFF)
        ..addByte(offset & 0xFF)
        ..addByte((_generationOf(number) >> 8) & 0xFF)
        ..addByte(_generationOf(number) & 0xFF);
    }
    final payload = data.takeBytes();

    final dict = _buildTrailer();
    dict['Type'] = const CosName('XRef');
    dict['W'] = CosArray(
        [const CosInteger(1), const CosInteger(4), const CosInteger(2)]);
    dict['Index'] = CosArray([
      for (final run in runs) ...[
        CosInteger(run.first),
        CosInteger(run.length),
      ],
    ]);
    dict['Length'] = CosInteger(payload.length);

    serializer.writeIndirectObject(
        CosIndirectObject(streamNumber, 0, CosStream(dict, payload)));
  }

  static void _writeText(BytesBuilder out, String text) =>
      out.add(text.codeUnits);
}
