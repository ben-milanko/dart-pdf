// Runs on the VM and under dart2js (`dart test -p node`, as CI does): the
// render worker walks content with this fast path on the web too, and dart2js
// numbers differ from the VM's (an integral double is an int, `-0` is `-0.0`),
// so the fast path's parity with the materialized walk is checked on both.
// Keep this file free of `dart:io`, of int literals past 2^53 and of
// pdf_test_fixtures (whose generators are not dart2js-safe).
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:test/test.dart';

const _isWeb = identical(0, 0.0);

void main() {
  final document = PdfDocument.open(_onePagePdf());
  final page = document.page(0);

  // The cursor walk runs number-only operators straight from the cursor's
  // operand buffer by their packed operator code; parse()/drawPageOperations
  // materializes every operation and dispatches on its String. Random
  // streams - braces, junk keywords, arrays and dictionaries, true/false/
  // null, ints past 2^53, signed zeros, `.5`/`5.`, operand-count mismatches,
  // the odd malformed number - must record identically both ways, sync and
  // through the resumable walk in small chunks (the worker's shape).
  test('seeded fuzz: the cursor fast path matches the materialized walk',
      () async {
    final random = math.Random(20260927);
    const cases = 4000;
    final mismatches = <String>[];
    for (var i = 0; i < cases; i++) {
      final source = _fuzzContent(random);
      final content = Uint8List.fromList(latin1.encode(source));
      final reference = _materialized(document, page, content);
      final sync = _record(document, (device) {
        PdfInterpreter(cos: document.cos, device: device)
            .drawPageContent(page, content);
      });
      // Every stream resumes across 7-operation chunks. One in eight also
      // yields inside a chunk: under node each yield is a timer of about a
      // millisecond, which on every stream would make this a minute of sleep.
      final yieldInterval = i % 8 == 0 ? 3 : 1 << 30;
      final chunked = await _recordAsync(document, (device) async {
        final walk = PdfInterpreter(cos: document.cos, device: device)
            .beginPageContent(page, content);
        while (
            !await walk.advance(operations: 7, yieldInterval: yieldInterval)) {}
      });

      if (!_sameRecord(sync, reference) || !_sameRecord(chunked, reference)) {
        mismatches.add('#$i: $source');
      }
    }
    expect(mismatches, isEmpty,
        reason: '${mismatches.length}/$cases streams diverged; first: '
            '${mismatches.take(3).join('\n')}');
  });

  group('signed zeros', () {
    // `w Td TD Tm TL Tc Tw Tz Ts` always read their operands from the
    // materialized COS objects, where on the web `-0` and `-0.0` are ints and
    // become the shared CosInteger(0): +0. The fast path must drop the sign
    // there too. `m l c v y re cm` read the unboxed numbers on both paths and
    // keep it. These are the fuzz's minimized web divergences, plus one per
    // operator.
    const streams = [
      '-0.0 w s',
      '-0 Tc /F1 9 Tf (ab) Tj',
      '[(a) (b)] rg -0 w b*',
      '-0.0 w 10 10 m 20 20 l S',
      '-0 w 10 10 m 20 20 l S',
      'BT /F1 9 Tf -0.0 -0 Td (ab) Tj ET',
      'BT /F1 9 Tf -0 -0.0 TD (ab) Tj T* (ab) Tj ET',
      'BT /F1 9 Tf 1 -0.0 -0 1 -0.0 -0 Tm (ab) Tj ET',
      'BT /F1 9 Tf -0.0 TL T* (ab) Tj ET',
      'BT /F1 9 Tf -0.0 Tc (ab) Tj ET',
      'BT /F1 9 Tf -0.0 Tw (a b) Tj ET',
      'BT /F1 9 Tf -0.0 Tz (ab) Tj ET',
      'BT /F1 9 Tf -0.0 Ts (ab) Tj ET',
      '-0.0 -0 m -0 -0.0 l -0.0 -0 -0 -0.0 -0.0 -0 c S',
      '-0.0 -0 -0 -0.0 re f -0 1 1 -0.0 -0.0 -0 cm 0 0 5 5 re f',
    ];
    for (final source in streams) {
      test('`$source` records the same through the cursor fast path', () async {
        final content = Uint8List.fromList(latin1.encode(source));
        final reference = _materialized(document, page, content);
        final sync = _record(document, (device) {
          PdfInterpreter(cos: document.cos, device: device)
              .drawPageContent(page, content);
        });
        final chunked = await _recordAsync(document, (device) async {
          final walk = PdfInterpreter(cos: document.cos, device: device)
              .beginPageContent(page, content);
          while (!await walk.advance(operations: 1, yieldInterval: 1)) {}
        });
        expect(_sameRecord(sync, reference), isTrue, reason: 'sync walk');
        expect(_sameRecord(chunked, reference), isTrue, reason: 'resumed walk');
      });
    }

    test('`w` keeps a real -0.0 on the VM and drops it on the web, both ways',
        () {
      for (final walk in [
        (Uint8List content, RecordingPdfDevice device) =>
            PdfInterpreter(cos: document.cos, device: device)
                .drawPageContent(page, content),
        (Uint8List content, RecordingPdfDevice device) =>
            PdfInterpreter(cos: document.cos, device: device)
                .drawPageOperations(page, ContentStreamParser.parse(content)),
      ]) {
        double width(String source) {
          final device = RecordingPdfDevice();
          walk(Uint8List.fromList(latin1.encode(source)), device);
          return device.commands
              .whereType<PdfStrokePathCommand>()
              .single
              .stroke
              .width;
        }

        final real = width('-0.0 w 10 10 m 20 20 l S');
        expect(real, 0);
        expect(real.isNegative, !_isWeb);
        // An integer token `-0` is the int 0 on the VM, and +0 on the web.
        expect(width('-0 w 10 10 m 20 20 l S').isNegative, isFalse);
      }
    });
  });
}

/// A one-page PDF whose resources name a Helvetica `/F1`.
Uint8List _onePagePdf() {
  const content = 'BT /F1 24 Tf 72 720 Td (Hello, world!) Tj ET';
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R '
        '/Resources << /Font << /F1 5 0 R >> >> >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xrefOffset = buffer.length;
  buffer.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer.write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
      'startxref\n$xrefOffset\n%%EOF\n');
  return Uint8List.fromList(latin1.encode(buffer.toString()));
}

/// The reference walk: materialize the operations (keeping the prefix before
/// a malformed token, which is where the cursor walk stops too) and run them
/// through the String-dispatched path.
_Record _materialized(PdfDocument document, PdfPage page, Uint8List content) {
  final operations = <ContentOperation>[];
  final reader = ContentStreamParser.cursor(content);
  try {
    ContentOperation? operation;
    while ((operation = reader.nextOperation()) != null) {
      operations.add(operation!);
    }
  } on CosParseException {
    // the prefix stands
  }
  return _record(document, (device) {
    PdfInterpreter(cos: document.cos, device: device)
        .drawPageOperations(page, operations);
  });
}

/// A recorded walk: the serialized commands (null when nothing serializes).
typedef _Record = Uint8List?;

_Record _record(PdfDocument document, void Function(RecordingPdfDevice) walk) {
  final device = RecordingPdfDevice();
  try {
    walk(device);
  } on CosParseException {
    // a malformed token ends the walk; what was recorded before it stands
  }
  return _serialize(document, device);
}

Future<_Record> _recordAsync(PdfDocument document,
    Future<void> Function(RecordingPdfDevice) walk) async {
  final device = RecordingPdfDevice();
  try {
    await walk(device);
  } on CosParseException {
    // as above
  }
  return _serialize(document, device);
}

_Record _serialize(PdfDocument document, RecordingPdfDevice device) =>
    serializeCommands(
      device.commands,
      cos: document.cos,
      decodeImages: false,
      imagePlaceholders: true,
      compactStateScopes: true,
    );

bool _sameRecord(_Record a, _Record b) {
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

const _numbers = [
  '0', '-0', '1', '-7', '123', '256', '257', '-1', '-2', '100000', //
  '9007199254740993', '123456789012345678', '1.5', '-0.25', '.5', '-.5',
  '5.', '0.0', '-0.0', '1.234567890123456789', '72.0', '0.001', '+3', '+.5',
  '3.14159', '12', '24',
];
const _malformed = ['1e5', '--5', '1-2', '.', '-', '1.2.3'];
const _others = [
  '/F1',
  '/F1 9 Tf',
  '(abc)',
  '<4142>',
  '[1 2 3]',
  '[(a) -250 (b)]',
  '<</A 1>>',
  'true',
  'false',
  'null',
  '{',
  '}',
  '[1 2 Tc 3]',
  'BI /W 1 /H 1 /CS /G /BPC 8 ID \x7f EI',
];
const _operators = [
  'm', 'l', 'c', 'v', 'y', 're', 'cm', 'w', 'Td', 'TD', 'Tm', 'TL', 'Tc', //
  'Tw', 'Tz', 'Ts', 'S', 's', 'f', 'F', 'f*', 'B', 'B*', 'b', 'b*', 'n', 'h',
  'W', 'W*', 'q', 'Q', 'J', 'j', 'M', 'd', 'g', 'G', 'rg', 'RG', 'k', 'K',
  'T*', 'BT', 'ET', 'Tr', 'Tj', 'TJ', "'", '"', 'i', 'ri', 'xx', 'Tq', 'abcd',
  'EMC', 'BMC', 'MP', 'd1',
];

String _fuzzContent(math.Random random) {
  final out = StringBuffer('BT /F1 12 Tf ');
  final tokens = 20 + random.nextInt(120);
  for (var i = 0; i < tokens; i++) {
    final roll = random.nextInt(100);
    if (roll == 0 && random.nextInt(8) == 0) {
      out.write(_malformed[random.nextInt(_malformed.length)]);
    } else if (roll < 55) {
      out.write(_numbers[random.nextInt(_numbers.length)]);
    } else if (roll < 62) {
      out.write(_others[random.nextInt(_others.length)]);
    } else {
      out.write(_operators[random.nextInt(_operators.length)]);
    }
    out.write(random.nextInt(5) == 0 ? '\n' : ' ');
  }
  // End by painting and showing text, so pending path and text state are
  // observable in the record.
  out.write(' (ab) Tj ET 1 w S 10 10 m 20 20 l S');
  return out.toString();
}
