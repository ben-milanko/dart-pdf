// Runs on the VM and under dart2js (`dart test -p node`, as CI does). On the
// web an integral double is an int, so the COS type a number operand
// materializes as differs by platform - and whatever it is, it must not depend
// on where the number sits in its operation, or a content rewrite saves `12`
// in one place and `12.0` in another. Keep this file free of `dart:io` and of
// int literals past 2^53.
import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:test/test.dart';

const _isWeb = identical(0, 0.0);

Uint8List _bytes(String s) => Uint8List.fromList(latin1.encode(s));

/// The operand at [index] of the single operation in [source], with the
/// operation's serialized text.
(CosObject, String) _operand(String source, int index) {
  final operation = ContentStreamParser.parse(_bytes(source)).single;
  return (operation.operands[index], _serialized(operation));
}

String _serialized(ContentOperation operation) =>
    latin1.decode(ContentStreamSerializer.serialize([operation])).trim();

/// How [operand] is written back out by a content rewrite.
String _written(CosObject operand) =>
    _serialized(ContentOperation('J', [operand]));

void main() {
  const numbers = [
    '0', '-0', '7', '-7', '257', '12', '3000000000', //
    '12.0', '5.', '-0.0', '0.0', '-.0', '72.0', '1.5', '-0.25', '.5',
    '1.234567890123456789', '9007199254740993',
  ];

  group('a number operand materializes one way wherever it sits', () {
    for (final number in numbers) {
      test(number, () {
        // All-number operation: the cursor's unboxed buffer, materialized by
        // ContentOperation.operands.
        final (reference, _) = _operand('$number J', 0);
        // The same token before a non-number operand (materialized when the
        // object arrives) and after one (materialized as it is read), in
        // every shape of non-number operand.
        final shapes = <(String, int)>[
          ('$number /A J', 0),
          ('$number $number /A J', 1),
          ('/A $number J', 1),
          ('null $number rg', 1),
          ('<</A 1>> $number J', 1),
          ('[1 2 3] $number J', 1),
          ('(s) $number /B $number J', 3),
        ];
        for (final (source, index) in shapes) {
          final (operand, text) = _operand(source, index);
          expect(operand.runtimeType, reference.runtimeType,
              reason: '`$source` operand $index');
          expect(_written(operand), _written(reference),
              reason: '`$source` serializes as `$text`');
        }
      });
    }
  });

  test('an integral real is a CosInteger on the web, a CosReal on the VM', () {
    // After a non-number operand: the case the cursor once materialized as a
    // CosReal on every platform, which on the web turned the `12` a font
    // size had always saved as into `12.0`.
    for (final source in ['/F1 12.0 Tf', '/F1 12 Tf']) {
      final (size, text) = _operand(source, 1);
      if (_isWeb || source == '/F1 12 Tf') {
        expect(size, isA<CosInteger>(), reason: source);
        expect(text, '/F1 12 Tf');
      } else {
        expect(size, isA<CosReal>(), reason: source);
        expect((size as CosReal).value, 12.0);
      }
    }
    final (zero, _) = _operand('null -0.0 rg', 1);
    if (_isWeb) {
      expect(zero, isA<CosInteger>());
      expect((zero as CosInteger).value, 0);
    } else {
      expect(zero, isA<CosReal>());
      expect((zero as CosReal).value.isNegative, isTrue);
    }
  });

  test('the cursor halves materialize what parse does', () {
    const source = '/F1 12.0 Tf 1 -0.0 5. 7 m null -0.0 rg (x) 12.0 5. J';
    final parsed = ContentStreamParser.parse(_bytes(source));
    final cursor = ContentStreamParser.cursor(_bytes(source));
    for (final expected in parsed) {
      expect(cursor.nextOperator(), expected.operator);
      final taken = cursor.takeOperation();
      expect([for (final o in taken.operands) '${o.runtimeType} $o'],
          [for (final o in expected.operands) '${o.runtimeType} $o']);
    }
    expect(cursor.nextOperator(), isNull);
  });
}
