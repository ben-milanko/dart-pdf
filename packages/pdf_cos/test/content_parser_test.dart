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
    expect(ops, isEmpty); // no operator ever arrived — nothing to run
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
}
