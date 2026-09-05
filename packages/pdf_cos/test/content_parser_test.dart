import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:test/test.dart';

Uint8List ascii(String s) => Uint8List.fromList(s.codeUnits);

void main() {
  test('parses operators with their operands', () {
    final ops = ContentStreamParser.parse(
        ascii('q 1 0 0 1 50.5 50 cm BT /F1 12 Tf (Hello) Tj ET Q'));

    expect(
        ops.map((op) => op.operator), ['q', 'cm', 'BT', 'Tf', 'Tj', 'ET', 'Q']);

    final cm = ops[1];
    expect(cm.operands, hasLength(6));
    expect(cm.operands[4], const CosReal(50.5));

    final tf = ops[3];
    expect(tf.operands, [const CosName('F1'), const CosInteger(12)]);

    final tj = ops[4];
    expect(tj.operands.single, CosString.fromText('Hello'));
  });

  test('operators with quote and star names', () {
    final ops = ContentStreamParser.parse(ascii("T* (a) ' (b) Tj"));
    expect(ops.map((op) => op.operator), ['T*', "'", 'Tj']);
  });

  test('booleans and null are operands', () {
    final ops = ContentStreamParser.parse(ascii('true false null gs'));
    expect(ops.single.operator, 'gs');
    expect(ops.single.operands, hasLength(3));
  });

  test('array and dictionary operands', () {
    final ops = ContentStreamParser.parse(ascii('[(a) 120 (b)] TJ'));
    expect(ops.single.operator, 'TJ');
    final array = ops.single.operands.single as CosArray;
    expect(array.length, 3);
  });

  test('stray operators inside an array operand are dropped', () {
    // pdf.js operator-in-TJ-array.pdf: real-world generators emit
    // `[(a) 0.0 Tc -250.0 (b)] TJ`; a strict array parse aborted the page
    final ops = ContentStreamParser.parse(
        ascii('[(Grandes) 0.0 Tc -250.0 (Clienteles)] TJ 0.0 Tc'));
    expect(ops.map((op) => op.operator), ['TJ', 'Tc']);
    final array = ops[0].operands.single as CosArray;
    // the numbers stay (harmless TJ adjustments), the operator is gone
    expect(array.items, [
      isA<CosString>(),
      const CosReal(0),
      const CosReal(-250),
      isA<CosString>(),
    ]);
  });

  test('an unterminated array operand keeps what parsed', () {
    final ops = ContentStreamParser.parse(ascii('[(a) 1 2'));
    expect(ops, isEmpty); // no operator ever arrived - nothing to run
  });

  test('inline image becomes one BI operation', () {
    final ops = ContentStreamParser.parse(
        ascii('q BI /W 2 /H 1 /CS /G /BPC 8 ID \x00\xff EI Q'));
    expect(ops.map((op) => op.operator), ['q', 'BI', 'Q']);

    final bi = ops[1];
    final dict = bi.operands[0] as CosDictionary;
    expect(dict['W'], const CosInteger(2));
    expect(dict['H'], const CosInteger(1));
    final data = bi.operands[1] as CosString;
    expect(data.bytes, [0x00, 0xFF]);
  });

  test('junk operands before an inline image do not leak past it', () {
    final ops = ContentStreamParser.parse(
        ascii('123 BI /W 1 /H 1 /CS /G /BPC 8 ID \x7f EI Q'));
    expect(ops.map((op) => op.operator), ['BI', 'Q']);
    expect(ops.last.operands, isEmpty);
  });

  test('operationLimit returns a prefix on operation boundaries', () {
    final ops = ContentStreamParser.parse(
        ascii('q 1 0 0 1 50 50 cm BI /W 1 /H 1 /CS /G /BPC 8 ID \x7f EI Q'),
        operationLimit: 3);

    expect(ops.map((op) => op.operator), ['q', 'cm', 'BI']);
    final data = ops[2].operands[1] as CosString;
    expect(data.bytes, [0x7F]);
  });

  test('incremental cursor emits one operation at a time and honors its limit',
      () {
    final cursor = ContentStreamParser.cursor(
      ascii('q 1 0 0 1 50 50 cm (Hello) Tj Q'),
      operationLimit: 3,
    );

    expect(cursor.operationCount, 0);
    expect(cursor.isFinished, isFalse);
    expect(cursor.nextOperation()!.operator, 'q');
    expect(cursor.operationCount, 1);
    final matrix = cursor.nextOperation()!;
    expect(matrix.operator, 'cm');
    expect(matrix.operands, hasLength(6));
    final text = cursor.nextOperation()!;
    expect(text.operator, 'Tj');
    expect((text.operands.single as CosString).text, 'Hello');
    expect(cursor.isFinished, isTrue);
    expect(cursor.nextOperation(), isNull);
    expect(cursor.operationCount, 3);
  });

  test('DCT inline image ignores EI-like bytes before JPEG EOI', () {
    final bytes = BytesBuilder()
      ..add(ascii('q BI /W 1 /H 1 /CS /RGB /BPC 8 /F /DCT ID\r\n'))
      ..add([0xFF, 0xD8, 0x20, 0x45, 0x49, 0x20, 0x00, 0xFF, 0xD9])
      ..add(ascii('\r\nEI Q'));
    final ops = ContentStreamParser.parse(bytes.takeBytes());
    expect(ops.map((op) => op.operator), ['q', 'BI', 'Q']);

    final data = ops[1].operands[1] as CosString;
    expect(data.bytes, [0xFF, 0xD8, 0x20, 0x45, 0x49, 0x20, 0x00, 0xFF, 0xD9]);
  });

  test('serializes regular content operations', () {
    final bytes = ContentStreamSerializer.serialize([
      ContentOperation('q', const []),
      ContentOperation('cm', const [
        CosInteger(1),
        CosInteger(0),
        CosInteger(0),
        CosInteger(1),
        CosInteger(50),
        CosInteger(50),
      ]),
      ContentOperation('Tf', const [CosName('F1'), CosInteger(12)]),
      ContentOperation('Tj', [CosString.fromText('Hi')]),
      ContentOperation('Q', const []),
    ]);

    expect(
        latin1.decode(bytes), 'q\n1 0 0 1 50 50 cm\n/F1 12 Tf\n(Hi) Tj\nQ\n');
  });

  test('incremental numeric operations stay primitive until COS access', () {
    final cursor = ContentStreamParser.cursor(ascii('1 2.5 3 m /F1 12 Tf'));
    final move = cursor.nextOperation()!;
    expect(move.operator, 'm');
    expect(move.numberOperands, <num>[1, 2.5, 3]);
    expect(move.operands, const <CosObject>[
      CosInteger(1),
      CosReal(2.5),
      CosInteger(3),
    ]);

    final font = cursor.nextOperation()!;
    expect(font.operator, 'Tf');
    expect(font.numberOperands, isNull,
        reason: 'mixed operands retain their general COS representation');
    expect(font.operands, const <CosObject>[CosName('F1'), CosInteger(12)]);
  });

  test('serializes inline image operations', () {
    final bytes = ContentStreamSerializer.serialize([
      ContentOperation('BI', [
        CosDictionary({
          'W': const CosInteger(2),
          'H': const CosInteger(1),
          'CS': const CosName('G'),
          'BPC': const CosInteger(8),
        }),
        CosString(Uint8List.fromList([0x00, 0xFF])),
      ]),
    ]);

    expect(bytes, ascii('BI /W 2 /H 1 /CS /G /BPC 8 ID\n\x00\xff\nEI\n'));
  });
}
