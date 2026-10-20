import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' show md5;

import 'objects.dart';
import 'perf/perf.dart';
import 'serializer.dart';
import 'xref_writer.dart';

/// Assembles a brand-new PDF file from scratch - the counterpart of
/// [CosIncrementalUpdater] for output that does not extend an existing
/// byte stream (extracted page ranges, merged documents, generated files).
///
/// Objects are numbered in registration order starting at 1. A container
/// may be registered while still empty and filled in afterwards - nothing
/// is serialized until [build] - which is how callers close reference
/// cycles (a page referencing its parent tree node, say).
class CosDocumentBuilder {
  final List<CosObject> _objects = [];

  /// Registers [object] and returns the reference it will be written under.
  CosReference add(CosObject object) {
    _objects.add(object);
    return CosReference(_objects.length, 0);
  }

  /// Serializes the file: header, object bodies, a cross-reference section,
  /// and the trailer. [root] must reference the document catalog.
  ///
  /// With [objectStreams] the non-stream objects are packed into compressed
  /// object streams and the cross-reference is written as a PDF 1.5 xref
  /// stream (§7.5.7-7.5.8) - much smaller for object-heavy documents.
  /// [deflateLevel] (0-9) sets the object-stream and xref-stream compression
  /// level; it is ignored for the classic table.
  /// [preserveRealPrecision] retains all parsed double precision, including
  /// font matrices, when this builder is used for a lossless graph rewrite.
  Uint8List build({
    required CosReference root,
    CosReference? info,
    String version = '1.7',
    bool objectStreams = false,
    int deflateLevel = 6,
    bool preserveRealPrecision = false,
  }) {
    final t0 = PdfPerf.begin();
    try {
      final built = objectStreams
          ? _buildCompressed(
              root: root,
              info: info,
              version: version,
              level: deflateLevel,
              preserveRealPrecision: preserveRealPrecision)
          : _buildClassic(
              root: root,
              info: info,
              version: version,
              preserveRealPrecision: preserveRealPrecision);
      PdfPerf.add(PdfPerfCount.savedBytes, built.length);
      PdfPerf.add(PdfPerfCount.savedObjects, _objects.length);
      return built;
    } finally {
      PdfPerf.end(PdfPerfPhase.saveFull, t0);
    }
  }

  Uint8List _buildClassic({
    required CosReference root,
    CosReference? info,
    String version = '1.7',
    required bool preserveRealPrecision,
  }) {
    final out = BytesBuilder(copy: false);
    _writeHeader(out, version);

    final serializer =
        CosSerializer(out, preserveRealPrecision: preserveRealPrecision);
    final offsets = <int>[];
    for (var i = 0; i < _objects.length; i++) {
      offsets.add(out.length);
      serializer.writeIndirectObject(CosIndirectObject(i + 1, 0, _objects[i]));
    }

    final tail = CosXrefTableWriter(out);
    final xrefOffset = out.length;
    tail.writeTable(
      {for (var i = 0; i < offsets.length; i++) i + 1: offsets[i]},
      (_) => 0,
      includeFreeHead: true,
    );

    // both /ID halves may be identical for a freshly created file (§14.4)
    final id = Uint8List.fromList(md5.convert(out.toBytes()).bytes);
    final trailer = CosDictionary({
      'Size': CosInteger(_objects.length + 1),
      'Root': root,
      if (info != null) 'Info': info,
      'ID': CosArray([
        CosString(id, isHex: true),
        CosString(id, isHex: true),
      ]),
    });
    tail.writeTrailer(trailer);
    tail.writeEpilogue(xrefOffset);
    return out.takeBytes();
  }

  /// Object-stream + xref-stream output (PDF 1.5). Streams and the
  /// cross-reference stream itself stay as top-level indirect objects
  /// (type-1 xref entries); every other object is packed into a compressed
  /// `/ObjStm` and addressed by a type-2 entry. Object numbers 1..N keep
  /// their registration identity; the object streams and the xref stream
  /// take the numbers above N.
  Uint8List _buildCompressed({
    required CosReference root,
    CosReference? info,
    required String version,
    required int level,
    required bool preserveRealPrecision,
  }) {
    // Object streams need a 1.5-era header even if the caller asked lower.
    final out = BytesBuilder(copy: false);
    _writeHeader(out, _atLeast15(version));
    final serializer =
        CosSerializer(out, preserveRealPrecision: preserveRealPrecision);

    final n = _objects.length;
    final offsets = <int, int>{}; // type-1: object number -> byte offset
    final compressed = <int, List<int>>{}; // type-2: number -> [objStm, index]

    // Everything that is not a stream packs into object streams.
    final packable = <int>[
      for (var i = 0; i < n; i++)
        if (_objects[i] is! CosStream) i + 1,
    ];

    var nextNumber = n + 1;
    // Keep each object stream to a bounded member count so the per-stream
    // header stays small and a corrupt one costs little.
    const perStream = 128;
    for (var start = 0; start < packable.length; start += perStream) {
      final members =
          packable.sublist(start, math.min(start + perStream, packable.length));
      final streamNumber = nextNumber++;

      final bodies = BytesBuilder();
      final bodyOffsets = <int>[];
      for (final number in members) {
        bodyOffsets.add(bodies.length);
        bodies.add(CosSerializer.serialize(_objects[number - 1],
            preserveRealPrecision: preserveRealPrecision));
        bodies.addByte(0x0A); // whitespace separator between bodies
      }
      final headerText = StringBuffer();
      for (var j = 0; j < members.length; j++) {
        headerText.write('${members[j]} ${bodyOffsets[j]} ');
      }
      final headerBytes = Uint8List.fromList(headerText.toString().codeUnits);
      final first = headerBytes.length;
      final plain = (BytesBuilder(copy: false)
            ..add(headerBytes)
            ..add(bodies.takeBytes()))
          .takeBytes();
      final payload = Uint8List.fromList(
          const ZLibEncoder().encodeBytes(plain, level: level));

      for (var j = 0; j < members.length; j++) {
        compressed[members[j]] = [streamNumber, j];
      }
      offsets[streamNumber] = out.length;
      serializer.writeIndirectObject(CosIndirectObject(
        streamNumber,
        0,
        CosStream(
          CosDictionary({
            'Type': const CosName('ObjStm'),
            'N': CosInteger(members.length),
            'First': CosInteger(first),
            'Filter': const CosName('FlateDecode'),
            'Length': CosInteger(payload.length),
          }),
          payload,
        ),
      ));
    }

    // Stream objects stay uncompressed and top-level.
    for (var i = 0; i < n; i++) {
      if (_objects[i] is CosStream) {
        offsets[i + 1] = out.length;
        serializer
            .writeIndirectObject(CosIndirectObject(i + 1, 0, _objects[i]));
      }
    }

    // The cross-reference stream lists itself, so it takes the next number
    // and its own offset is known before it is written.
    final xrefNumber = nextNumber++;
    final xrefOffset = out.length;
    offsets[xrefNumber] = xrefOffset;
    final size = nextNumber; // one past the highest number (object 0..xref)

    final id = Uint8List.fromList(md5.convert(out.toBytes()).bytes);
    final data = BytesBuilder();
    for (var number = 0; number < size; number++) {
      if (number == 0) {
        _xrefEntry(data, 0, 0, 0xFFFF); // free-list head
      } else if (compressed.containsKey(number)) {
        final loc = compressed[number]!;
        _xrefEntry(data, 2, loc[0], loc[1]);
      } else {
        _xrefEntry(data, 1, offsets[number]!, 0);
      }
    }
    final xrefPayload = Uint8List.fromList(
        const ZLibEncoder().encodeBytes(data.takeBytes(), level: level));

    serializer.writeIndirectObject(CosIndirectObject(
      xrefNumber,
      0,
      CosStream(
        CosDictionary({
          'Type': const CosName('XRef'),
          'Size': CosInteger(size),
          'Root': root,
          if (info != null) 'Info': info,
          'W': CosArray(const [
            CosInteger(1),
            CosInteger(4),
            CosInteger(2),
          ]),
          'Index': CosArray([const CosInteger(0), CosInteger(size)]),
          'Filter': const CosName('FlateDecode'),
          'Length': CosInteger(xrefPayload.length),
          'ID': CosArray([
            CosString(id, isHex: true),
            CosString(id, isHex: true),
          ]),
        }),
        xrefPayload,
      ),
    ));

    _writeText(out, 'startxref\n$xrefOffset\n%%EOF\n');
    return out.takeBytes();
  }

  /// Writes one `W [1 4 2]` cross-reference-stream entry: a one-byte type,
  /// a four-byte second field, and a two-byte third field, all big-endian.
  static void _xrefEntry(BytesBuilder out, int type, int field2, int field3) {
    out
      ..addByte(type)
      ..addByte((field2 >> 24) & 0xFF)
      ..addByte((field2 >> 16) & 0xFF)
      ..addByte((field2 >> 8) & 0xFF)
      ..addByte(field2 & 0xFF)
      ..addByte((field3 >> 8) & 0xFF)
      ..addByte(field3 & 0xFF);
  }

  static String _atLeast15(String version) {
    final match = RegExp(r'^(\d+)\.(\d+)$').firstMatch(version);
    if (match == null) return '1.7';
    final major = int.parse(match.group(1)!);
    final minor = int.parse(match.group(2)!);
    if (major > 1 || (major == 1 && minor >= 5)) return version;
    return '1.5';
  }

  static void _writeHeader(BytesBuilder out, String version) {
    _writeText(out, '%PDF-$version\n');
    // a comment with bytes ≥ 128 so transports treat the file as binary
    out.add(const [0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A]);
  }

  static void _writeText(BytesBuilder out, String text) =>
      out.add(text.codeUnits);
}
