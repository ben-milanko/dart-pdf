import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

void main() {
  const fixtures = [
    'operator-in-TJ-array.pdf',
    'rotation.pdf',
    'xobject-image.pdf',
    'gradientfill.pdf',
    'tiling-pattern-box.pdf',
    'pattern_text_embedded_font.pdf',
    'blendmode.pdf',
    'knockout_smask.pdf',
  ];

  test('streaming and materialized interpretation are byte-equivalent', () {
    for (final name in fixtures) {
      final document = PdfDocument.open(
        File('../../test_corpora/pdfjs/$name').readAsBytesSync(),
      );
      for (var pageIndex = 0;
          pageIndex < math.min(2, document.pageCount);
          pageIndex++) {
        final page = document.page(pageIndex);
        final content = page.contentBytes();

        final materialized = RecordingPdfDevice();
        PdfInterpreter(cos: document.cos, device: materialized)
            .drawPageOperations(page, ContentStreamParser.parse(content));
        final streamed = RecordingPdfDevice();
        PdfInterpreter(cos: document.cos, device: streamed)
            .drawPageContent(page, content);

        final materializedBytes = serializeCommands(
          materialized.commands,
          cos: document.cos,
          decodeImages: false,
          imagePlaceholders: true,
          compactStateScopes: true,
        );
        final streamedBytes = serializeCommands(
          streamed.commands,
          cos: document.cos,
          decodeImages: false,
          imagePlaceholders: true,
          compactStateScopes: true,
        );
        expect(materializedBytes, isNotNull, reason: '$name page $pageIndex');
        expect(streamedBytes, materializedBytes,
            reason: '$name page $pageIndex');
      }
    }
  });

  // The cursor walk runs number-only operators straight from the cursor's
  // operand buffer by their packed operator code; parse()/drawPageOperations
  // materializes every operation and dispatches on its String. Random
  // streams - braces, junk keywords, arrays and dictionaries, true/false/
  // null, ints past 2^53, signed zeros, `.5`/`5.`, operand-count mismatches,
  // the odd malformed number - must record identically both ways, sync and
  // through the resumable walk in small chunks (the worker's shape).
  test('seeded fuzz: the cursor fast path matches the materialized walk',
      () async {
    final document = PdfDocument.open(buildClassicPdf());
    final page = document.page(0);
    final random = math.Random(20260927);
    const cases = 4000;
    final mismatches = <String>[];
    for (var i = 0; i < cases; i++) {
      final source = _fuzzContent(random);
      final content = Uint8List.fromList(latin1.encode(source));

      // Reference: materialize the operations (keeping the prefix before a
      // malformed token, which is where the cursor walk stops too) and run
      // them through the String-dispatched path.
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
      final reference = _record(document, (device) {
        PdfInterpreter(cos: document.cos, device: device)
            .drawPageOperations(page, operations);
      });

      final sync = _record(document, (device) {
        PdfInterpreter(cos: document.cos, device: device)
            .drawPageContent(page, content);
      });
      final chunked = await _recordAsync(document, (device) async {
        final walk = PdfInterpreter(cos: document.cos, device: device)
            .beginPageContent(page, content);
        while (!await walk.advance(operations: 7, yieldInterval: 3)) {}
      });

      if (!_sameRecord(sync, reference) || !_sameRecord(chunked, reference)) {
        mismatches.add('#$i: $source');
      }
    }
    expect(mismatches, isEmpty,
        reason: '${mismatches.length}/$cases streams diverged; first: '
            '${mismatches.take(3).join('\n')}');
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
