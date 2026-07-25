// The worker's resumable full-page record (#530) must produce exactly what the
// one-shot record produced. The render worker records a heavy page in bounded
// [PdfPageContentWalk.advance] chunks so a scroll that preempts it can requeue
// and *resume* the walk instead of re-interpreting the prefix. This pins the
// property the resume rides on: a walk suspended mid-page and resumed serializes
// to the same command buffer as a walk run to completion in one go.
//
// interpreter_test.dart already proves the chunked walk emits the same device
// calls as the unbounded one; this adds the serialization round-trip, which is
// the worker's actual output (the bytes the UI isolate deserializes).
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

/// A single-page PDF whose content stream is [opCount] stroked line segments -
/// enough operations to span many small advance chunks.
Uint8List _linesPdf(int opCount) {
  final content = StringBuffer('1 0 0 1 0 0 cm\n0 0 0 RG\n');
  for (var i = 0; i < opCount; i++) {
    final x = (i % 100).toDouble();
    final y = (i % 50).toDouble();
    content.write('${x.toStringAsFixed(1)} ${y.toStringAsFixed(1)} m '
        '${(x + 1).toStringAsFixed(1)} ${(y + 1).toStringAsFixed(1)} l S\n');
  }
  final stream = content.toString();
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R '
        '/Resources << >> >>',
    '<< /Length ${stream.length} >>\nstream\n$stream\nendstream',
  ];
  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = buffer.length;
  buffer.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer.write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
      'startxref\n$xref\n%%EOF');
  return Uint8List.fromList(buffer.toString().codeUnits);
}

/// Records page 0 in one unbounded walk - the pre-#530 shape.
Future<Uint8List?> _recordOneShot(Uint8List bytes) async {
  final doc = PdfDocument.open(bytes);
  final page = doc.page(0);
  final recorder = RecordingPdfDevice();
  final walk = PdfInterpreter(cos: doc.cos, device: recorder)
      .beginPageContent(page, page.contentBytes());
  await walk.advance(); // unbounded: runs to completion
  expect(walk.isComplete, isTrue);
  return serializeCommands(recorder.commands,
      cos: doc.cos, decodeImages: true, compactStateScopes: true);
}

/// Records page 0 the way `_recordResumablePage` does: bounded [chunk] advances
/// with the walk left suspended (not finished) between them, then resumed to
/// completion. Asserts the fixture actually spanned several chunks.
Future<Uint8List?> _recordResumed(Uint8List bytes, {required int chunk}) async {
  final doc = PdfDocument.open(bytes);
  final page = doc.page(0);
  final recorder = RecordingPdfDevice();
  final walk = PdfInterpreter(cos: doc.cos, device: recorder)
      .beginPageContent(page, page.contentBytes());
  var chunks = 0;
  while (!await walk.advance(operations: chunk)) {
    chunks++;
    expect(chunks, lessThan(100000), reason: 'walk did not terminate');
  }
  expect(chunks, greaterThan(1),
      reason: 'the fixture must span several chunks to exercise resume');
  expect(walk.isComplete, isTrue);
  return serializeCommands(recorder.commands,
      cos: doc.cos, decodeImages: true, compactStateScopes: true);
}

void main() {
  test('a resumed record serializes identically to a one-shot record',
      () async {
    final bytes = _linesPdf(500);
    final oneShot = await _recordOneShot(bytes);
    final resumed = await _recordResumed(bytes, chunk: 20);
    expect(oneShot, isNotNull);
    expect(resumed, isNotNull);
    expect(resumed, equals(oneShot),
        reason: 'suspending mid-walk and resuming must not change the bytes');
  });

  test('chunk size does not change the recorded bytes', () async {
    final bytes = _linesPdf(300);
    final small = await _recordResumed(bytes, chunk: 7);
    final large = await _recordResumed(bytes, chunk: 128);
    expect(small, isNotNull);
    expect(small, equals(large));
  });
}
