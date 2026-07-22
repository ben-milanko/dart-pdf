import 'dart:typed_data';

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

  /// Serializes the file: header, object bodies, a classic cross-reference
  /// table, and the trailer. [root] must reference the document catalog.
  Uint8List build({
    required CosReference root,
    CosReference? info,
    String version = '1.7',
  }) {
    final t0 = PdfPerf.begin();
    try {
      final built = _buildTimed(root: root, info: info, version: version);
      PdfPerf.add(PdfPerfCount.savedBytes, built.length);
      PdfPerf.add(PdfPerfCount.savedObjects, _objects.length);
      return built;
    } finally {
      PdfPerf.end(PdfPerfPhase.saveFull, t0);
    }
  }

  Uint8List _buildTimed({
    required CosReference root,
    CosReference? info,
    String version = '1.7',
  }) {
    final out = BytesBuilder(copy: false);
    _writeText(out, '%PDF-$version\n');
    // a comment with bytes ≥ 128 so transports treat the file as binary
    out.add(const [0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A]);

    final serializer = CosSerializer(out);
    final offsets = <int>[];
    for (var i = 0; i < _objects.length; i++) {
      offsets.add(out.length);
      serializer
          .writeIndirectObject(CosIndirectObject(i + 1, 0, _objects[i]));
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

  static void _writeText(BytesBuilder out, String text) =>
      out.add(text.codeUnits);
}
