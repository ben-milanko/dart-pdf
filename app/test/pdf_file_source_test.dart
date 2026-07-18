// PdfFileByteSource reads a local file on demand for the progressive loader:
// ranged reads, clamped/short past EOF, progress, cancellation - and it opens
// a real document through PdfDocument.openSource. readSourceFully reassembles
// the complete contiguous buffer (with progress) for the background full read.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor_app/file_io.dart';
import 'package:dart_pdf_editor_app/pdf_file_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late File pdfFile;
  late Uint8List pdfBytes;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pdf_file_source_test');
    pdfBytes = PdfBlankDocument.create();
    pdfFile = File('${tmp.path}/blank.pdf');
    await pdfFile.writeAsBytes(pdfBytes, flush: true);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('length reports the file size', () async {
    final source = PdfFileByteSource(pdfFile.path);
    expect(await source.length, pdfBytes.length);
    await source.close();
  });

  test('readRange returns the requested slice', () async {
    final source = PdfFileByteSource(pdfFile.path);
    final head = await source.readRange(0, 5);
    expect(head, pdfBytes.sublist(0, 5));
    final mid = await source.readRange(10, 20);
    expect(mid, pdfBytes.sublist(10, 20));
    await source.close();
  });

  test('readRange clamps past the end and empties beyond it', () async {
    final source = PdfFileByteSource(pdfFile.path);
    final len = pdfBytes.length;
    // A window straddling EOF returns only the real bytes (a short read).
    final tail = await source.readRange(len - 4, len + 100);
    expect(tail, pdfBytes.sublist(len - 4));
    // Wholly past the end is empty; so is a degenerate range.
    expect(await source.readRange(len + 10, len + 20), isEmpty);
    expect(await source.readRange(30, 30), isEmpty);
    // A negative start is clamped to 0.
    expect(await source.readRange(-5, 3), pdfBytes.sublist(0, 3));
    await source.close();
  });

  test('reports cumulative progress across reads', () async {
    final seen = <int>[];
    final source = PdfFileByteSource(
      pdfFile.path,
      onProgress: (received, total) {
        expect(total, pdfBytes.length);
        seen.add(received);
      },
    );
    await source.readRange(0, 10);
    await source.readRange(10, 25);
    expect(seen, [10, 25]);
    await source.close();
  });

  test('a fired cancel token aborts reads', () async {
    final token = PdfCancelToken();
    final source = PdfFileByteSource(pdfFile.path, cancelToken: token);
    token.cancel();
    expect(source.readRange(0, 10), throwsA(isA<PdfHttpCancelledException>()));
    expect(source.length, throwsA(isA<PdfHttpCancelledException>()));
    await source.close();
  });

  test('concurrent reads on one handle stay consistent', () async {
    final source = PdfFileByteSource(pdfFile.path);
    final futures = [
      for (var i = 0; i < pdfBytes.length; i += 7)
        source.readRange(i, i + 7),
    ];
    final chunks = await Future.wait(futures);
    final rebuilt = BytesBuilder(copy: false);
    for (final c in chunks) {
      rebuilt.add(c);
    }
    expect(rebuilt.toBytes(), pdfBytes);
    await source.close();
  });

  test('readSourceFully reassembles the exact file with progress', () async {
    final source = PdfFileByteSource(pdfFile.path);
    var lastReceived = 0;
    int? lastTotal;
    final full = await readSourceFully(
      source,
      chunk: 16, // force many chunks over the small fixture
      onProgress: (received, total) {
        lastReceived = received;
        lastTotal = total;
      },
    );
    expect(full, pdfBytes);
    expect(lastReceived, pdfBytes.length);
    expect(lastTotal, pdfBytes.length);
    await source.close();
  });

  test('PdfDocument.openSource opens the file through the source', () async {
    final source = PdfFileByteSource(pdfFile.path);
    final doc = await PdfDocument.openSource(source);
    expect(doc.pageCount, 1);
    // The progressive loader assembles a full-length (sparse) buffer.
    expect(doc.cos.bytes.length, pdfBytes.length);
    await source.close();
  });
}
