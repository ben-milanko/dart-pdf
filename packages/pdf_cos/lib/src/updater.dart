import 'dart:typed_data';

import 'document.dart';
import 'objects.dart';
import 'perf/perf.dart';
import 'serializer.dart';
import 'xref.dart';
import 'xref_writer.dart';

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
  ///
  /// Prefer [saveTail] in a session that keeps revisions as prefixes of one
  /// growing buffer: this has to materialise the whole file again per call,
  /// so an N-revision session copies O(file x N) bytes and `file` itself
  /// grows with every revision.
  Uint8List save() {
    final tail = saveTail();
    return (BytesBuilder(copy: false)
          ..add(document.bytes)
          ..add(tail))
        .takeBytes();
  }

  /// Returns **only the bytes to append** to [CosDocument.bytes] to form the
  /// updated file - the incremental update section and nothing else.
  ///
  /// `save()` concatenates the whole original file with this tail on every
  /// call. A caller that already holds the base bytes in a buffer it controls
  /// (the editor keeps every revision as a length into one buffer) can append
  /// this instead and pay only the tail, turning a per-revision O(file) copy
  /// into an amortised append.
  ///
  /// The returned bytes are position-dependent: they are only valid appended
  /// directly to this document's bytes, because the cross-reference offsets
  /// inside them are computed against that base length.
  Uint8List saveTail() {
    final t0 = PdfPerf.begin();
    try {
      final tail = _saveTailTimed();
      PdfPerf.add(PdfPerfCount.savedBytes, tail.length);
      PdfPerf.add(PdfPerfCount.savedObjects, _changed.length);
      return tail;
    } finally {
      PdfPerf.end(PdfPerfPhase.saveIncremental, t0);
    }
  }

  Uint8List _saveTailTimed() {
    // The tail is built on its own, so every offset written into it has to be
    // biased by the base file it will be appended to. `base` counts only the
    // bytes NOT in this builder - the separator below goes into `out`, so it
    // is already carried by `out.length` and must not be counted twice.
    final out = BytesBuilder(copy: false);
    final base = document.bytes.length;
    final last = document.bytes.isEmpty ? 0x0A : document.bytes.last;
    if (last != 0x0A && last != 0x0D) out.addByte(0x0A);

    // xref offsets are relative to the %PDF- header, which may not be byte 0.
    // Folding `base` in here keeps every `out.length - shift` below reading
    // exactly as it did when the whole file was in the builder.
    final shift = document.headerOffset - base;
    final offsets = <int, int>{};
    final serializer = CosSerializer(out);

    final handler = document.encryption;
    final changedNumbers = _changed.keys.toList()..sort();
    for (final number in changedNumbers) {
      offsets[number] = out.length - shift;
      var object = _changed[number]!;
      if (handler != null && number != document.encryptObjectNumber) {
        final tEncrypt = PdfPerf.begin();
        object = handler.encryptObjectGraph(
          object,
          number,
          _generationOf(number),
          resolve: document.resolve,
          keepsFileCiphertext: (stream) => stream.sourceRef != null,
        );
        PdfPerf.end(PdfPerfPhase.encryptGraph, tEncrypt);
      }
      serializer.writeIndirectObject(
          CosIndirectObject(number, _generationOf(number), object));
    }

    // a file whose newest xref is a stream must be updated with a stream;
    // a classic-table file is updated with a classic table (§7.5.8.4)
    final xrefOffset = out.length - shift;
    final tail = CosXrefTableWriter(out);
    if (document.trailer.typeName == 'XRef') {
      _writeXrefStream(serializer, offsets, xrefOffset);
    } else {
      tail
        ..writeTable(offsets, _generationOf)
        ..writeTrailer(_buildTrailer());
    }
    tail.writeEpilogue(xrefOffset);
    return out.takeBytes();
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

  void _writeXrefStream(
      CosSerializer serializer, Map<int, int> offsets, int xrefOffset) {
    // the cross-reference stream is itself an object and lists itself
    final streamNumber = _nextObjectNumber++;
    offsets[streamNumber] = xrefOffset;

    final sorted = offsets.keys.toList()..sort();
    final runs = CosXrefTableWriter.runsOf(sorted);
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
}
