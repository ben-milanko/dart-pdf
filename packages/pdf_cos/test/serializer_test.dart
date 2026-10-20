import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

/// Serializes, reparses, and serializes again: both byte runs must agree.
void expectRoundTrip(CosObject object) {
  final first = CosSerializer.serialize(object);
  final reparsed = CosParser(first).parseObject();
  expect(CosSerializer.serialize(reparsed), first);
}

void main() {
  test('scalars serialize to PDF syntax', () {
    expect(String.fromCharCodes(CosSerializer.serialize(CosNull.instance)),
        'null');
    expect(
        String.fromCharCodes(CosSerializer.serialize(const CosBoolean(true))),
        'true');
    expect(String.fromCharCodes(CosSerializer.serialize(const CosInteger(42))),
        '42');
    expect(String.fromCharCodes(CosSerializer.serialize(const CosReal(1.5))),
        '1.5');
    expect(
        String.fromCharCodes(CosSerializer.serialize(const CosReal(2))), '2.0');
    expect(String.fromCharCodes(CosSerializer.serialize(const CosName('Type'))),
        '/Type');
  });

  test('reals never use exponent notation', () {
    expect(CosSerializer.formatReal(0.0000001), isNot(contains('e')));
    expect(CosSerializer.formatReal(1e20), isNot(contains('e')));
  });

  test('lossless mode preserves font matrices and expands exponents exactly',
      () {
    for (final value in [
      0.0001220703125,
      1e-20,
      -1.25e-30,
      1.25e21,
      1e200,
      3.141592653589793,
      -0.0
    ]) {
      final text = CosSerializer.formatRealExact(value);
      expect(text, isNot(contains('e')));
      expect(double.parse(text), value);
      final parsed = CosParser(CosSerializer.serialize(CosReal(value),
              preserveRealPrecision: true))
          .parseObject() as CosReal;
      expect(parsed.value, value);
    }
  });

  test('strings escape delimiters', () {
    final out = String.fromCharCodes(
        CosSerializer.serialize(CosString.fromText(r'a(b)c\d')));
    expect(out, r'(a\(b\)c\\d)');
  });

  test('text strings beyond Latin-1 encode as UTF-16BE with a BOM', () {
    // Latin-1 text stays single-byte
    expect(CosString.fromText('naïve').bytes, [0x6E, 0x61, 0xEF, 0x76, 0x65]);
    // anything past 0xFF switches the whole string to UTF-16BE
    const text = 'già ✓ 漢字 🎉';
    final cos = CosString.fromText(text);
    expect(cos.bytes[0], 0xFE);
    expect(cos.bytes[1], 0xFF);
    expect(cos.text, text); // round-trips through the BOM-sniffing getter
  });

  test('names escape special characters', () {
    final out = String.fromCharCodes(
        CosSerializer.serialize(const CosName('Lime Green')));
    expect(out, '/Lime#20Green');
  });

  test('round trips', () {
    expectRoundTrip(const CosInteger(-7));
    expectRoundTrip(const CosReal(3.25));
    expectRoundTrip(CosString.fromText('with (parens) and \\ slash'));
    expectRoundTrip(CosString(ascii('CAFE'), isHex: true));
    expectRoundTrip(const CosReference(12, 3));
    expectRoundTrip(CosArray([
      const CosInteger(1),
      CosArray([const CosName('Nested')]),
      const CosBoolean(false),
    ]));
    expectRoundTrip(CosDictionary({
      'Type': const CosName('Page'),
      'Parent': const CosReference(2, 0),
      'MediaBox': CosArray([
        const CosInteger(0),
        const CosInteger(0),
        const CosReal(612.5),
        const CosInteger(792),
      ]),
    }));
    expectRoundTrip(CosStream(
      CosDictionary({'Length': const CosInteger(5)}),
      ascii('Hello'),
    ));
  });
}
