import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart';

import 'matrix.dart';
import 'text_extraction.dart';

/// Magic + version word at the head of an encoded [PdfPageText] blob.
/// Bump the low byte when the layout below changes; mismatched blobs
/// decode to null (a miss) rather than mis-parsing.
const int _textBlobMagic = 0x50545831; // 'PTX1'

/// Serializes [page] into a compact binary blob for the on-disk text
/// cache. The format is little-endian and self-describing enough to
/// reject foreign/old bytes ([pdfDecodePageText] returns null on any
/// mismatch). No external dependency — just `dart:typed_data`.
Uint8List pdfEncodePageText(PdfPageText page) {
  final out = _Writer();
  out.u32(_textBlobMagic);
  out.i32(page.pageIndex);
  out.str(page.text);
  out.u32(page.runs.length);
  for (final run in page.runs) {
    out.str(run.text);
    out.i32(run.startIndex);
    final t = run.transform;
    out
      ..f64(t.a)
      ..f64(t.b)
      ..f64(t.c)
      ..f64(t.d)
      ..f64(t.e)
      ..f64(t.f);
    out.f64(run.width);
    final b = run.bounds;
    out
      ..f64(b.left)
      ..f64(b.bottom)
      ..f64(b.right)
      ..f64(b.top);
  }
  return out.takeBytes();
}

/// Reverses [pdfEncodePageText], or returns null when [bytes] are absent,
/// truncated, corrupt, or from an incompatible format — every such case
/// is a cache miss the caller recomputes from.
PdfPageText? pdfDecodePageText(Uint8List bytes) {
  try {
    final r = _Reader(bytes);
    if (r.u32() != _textBlobMagic) return null;
    final pageIndex = r.i32();
    final text = r.str();
    final runCount = r.u32();
    final runs = <PdfExtractedRun>[];
    for (var i = 0; i < runCount; i++) {
      final runText = r.str();
      final startIndex = r.i32();
      final transform =
          PdfMatrix(r.f64(), r.f64(), r.f64(), r.f64(), r.f64(), r.f64());
      final width = r.f64();
      final bounds = PdfRect(r.f64(), r.f64(), r.f64(), r.f64());
      runs.add(PdfExtractedRun(
        text: runText,
        startIndex: startIndex,
        transform: transform,
        width: width,
        bounds: bounds,
      ));
    }
    return PdfPageText(pageIndex: pageIndex, text: text, runs: runs);
  } catch (_) {
    return null;
  }
}

/// A persistent cache of extracted page text, on top of a [PdfDiskCache].
///
/// Text extraction interprets the whole content stream (the same heavy
/// walk that rendering does), so search, selection, and the reading view
/// pay it again on every reopen of a document. This memoizes the result
/// keyed by document content + page index, so a previously-opened
/// document's text is read back from the store instead of recomputed.
///
/// Use a dedicated [PdfDiskCache] namespace (e.g. `'pdftext'`) so the
/// text blobs and any page rasters age out independently. Bump the disk
/// cache's `version` when the extraction logic changes meaningfully.
class PdfPageTextCache {
  PdfPageTextCache(this.cache);

  /// The byte store this cache persists into.
  final PdfDiskCache cache;

  String _key(String documentKey, int pageIndex) => '$documentKey/$pageIndex';

  /// Returns page [pageIndex]'s text for the document identified by
  /// [documentKey] (e.g. [pdfContentKey] of the bytes, or a file path),
  /// reading it from disk on a hit and falling back to [compute] —
  /// caching the result — on a miss.
  ///
  /// Best-effort: a store failure simply runs [compute].
  Future<PdfPageText> get(
    String documentKey,
    int pageIndex,
    FutureOr<PdfPageText> Function() compute,
  ) async {
    final key = _key(documentKey, pageIndex);
    final cached = await cache.read(key);
    if (cached != null) {
      final decoded = pdfDecodePageText(cached);
      if (decoded != null) return decoded;
    }
    final text = await compute();
    unawaited(cache.write(key, pdfEncodePageText(text)));
    return text;
  }
}

class _Writer {
  // copy: true — the scratch buffer is reused across calls, so the builder
  // must take its own copy of each slice rather than retain a live view.
  final BytesBuilder _builder = BytesBuilder(copy: true);
  final ByteData _scratch = ByteData(8);

  void u32(int value) {
    _scratch.setUint32(0, value & 0xffffffff, Endian.little);
    _builder.add(_scratch.buffer.asUint8List(0, 4));
  }

  void i32(int value) {
    _scratch.setInt32(0, value, Endian.little);
    _builder.add(_scratch.buffer.asUint8List(0, 4));
  }

  void f64(double value) {
    _scratch.setFloat64(0, value, Endian.little);
    _builder.add(_scratch.buffer.asUint8List(0, 8));
  }

  void str(String value) {
    final encoded = utf8.encode(value);
    u32(encoded.length);
    _builder.add(encoded);
  }

  Uint8List takeBytes() => _builder.toBytes();
}

class _Reader {
  _Reader(this._bytes) : _data = ByteData.sublistView(_bytes);

  final Uint8List _bytes;
  final ByteData _data;
  int _offset = 0;

  int u32() {
    final value = _data.getUint32(_offset, Endian.little);
    _offset += 4;
    return value;
  }

  int i32() {
    final value = _data.getInt32(_offset, Endian.little);
    _offset += 4;
    return value;
  }

  double f64() {
    final value = _data.getFloat64(_offset, Endian.little);
    _offset += 8;
    return value;
  }

  String str() {
    final length = u32();
    final value = utf8.decode(_bytes.sublist(_offset, _offset + length));
    _offset += length;
    return value;
  }
}
