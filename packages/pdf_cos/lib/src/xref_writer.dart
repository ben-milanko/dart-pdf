import 'dart:typed_data';

import 'objects.dart';
import 'serializer.dart';

/// Writes the file-tail framing shared by the from-scratch [CosDocumentBuilder]
/// and the incremental [CosIncrementalUpdater]: the classic cross-reference
/// table (entry encoding plus consecutive-run subsections), the `trailer`
/// dictionary, and the `startxref`/`%%EOF` epilogue.
///
/// From-scratch output is just the incremental case with an empty prefix, a
/// free-list head, and no `/Prev` - so both writers emit the same bytes here.
class CosXrefTableWriter {
  CosXrefTableWriter(this._out) : _serializer = CosSerializer(_out);

  final BytesBuilder _out;
  final CosSerializer _serializer;

  /// Groups sorted object numbers into runs of consecutive numbers, one
  /// cross-reference subsection each. Shared with the xref-stream writer.
  static List<List<int>> runsOf(List<int> sorted) {
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

  /// Writes `xref` and one subsection per consecutive run of [offsets]. Each
  /// in-use entry is encoded as `NNNNNNNNNN GGGGG n ` (byte offset padded to
  /// ten digits, generation from [generationOf] padded to five). When
  /// [includeFreeHead] is set the object-0 free-list head
  /// (`0000000000 65535 f `) leads the table - required for a from-scratch
  /// file, omitted for an incremental update whose object 0 is already on file.
  void writeTable(
    Map<int, int> offsets,
    int Function(int) generationOf, {
    bool includeFreeHead = false,
  }) {
    final numbers = offsets.keys.toList()..sort();
    if (includeFreeHead) numbers.insert(0, 0);
    _writeText('xref\n');
    for (final run in runsOf(numbers)) {
      _writeText('${run.first} ${run.length}\n');
      for (final number in run) {
        if (includeFreeHead && number == 0) {
          _writeText('0000000000 65535 f \n');
        } else {
          final offset = offsets[number]!.toString().padLeft(10, '0');
          final generation = generationOf(number).toString().padLeft(5, '0');
          _writeText('$offset $generation n \n');
        }
      }
    }
  }

  /// Writes `trailer` followed by the [trailer] dictionary and a newline. Kept
  /// separate from [writeTable] so the builder can hash the emitted table bytes
  /// into `/ID` before the trailer is composed.
  void writeTrailer(CosDictionary trailer) {
    _writeText('trailer\n');
    _serializer.writeObject(trailer);
    _writeText('\n');
  }

  /// Writes the `startxref`/`%%EOF` epilogue pointing at [xrefOffset] (the
  /// cross-reference offset relative to the `%PDF-` header).
  void writeEpilogue(int xrefOffset) {
    _writeText('startxref\n$xrefOffset\n%%EOF\n');
  }

  void _writeText(String text) => _out.add(text.codeUnits);
}
