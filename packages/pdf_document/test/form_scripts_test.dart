import 'package:pdf_document/pdf_document.dart';
import 'package:test/test.dart';

/// Unit semantics of the AF* helper ports in form_scripts.dart. The
/// document-level wiring (calculation order, fill path, appearances) is in
/// form_scripts_fill_test.dart.
void main() {
  PdfFieldScript parse(String source, PdfFieldScriptTrigger trigger) =>
      parsePdfFieldScript(source, trigger);
  const k = PdfFieldScriptTrigger.keystroke;
  const f = PdfFieldScriptTrigger.format;
  const v = PdfFieldScriptTrigger.validate;
  const c = PdfFieldScriptTrigger.calculate;

  PdfFormatScript fmt(String source) => parse(source, f) as PdfFormatScript;
  PdfKeystrokeScript key(String source) =>
      parse(source, k) as PdfKeystrokeScript;

  group('recognition', () {
    test('the shapes producers write', () {
      expect(parse('AFNumber_Format(2, 0, 0, 0, "\$", true);', f),
          isA<PdfNumberFormatScript>());
      expect(parse('AFNumber_Format(2,0,0,0,"",true)', f),
          isA<PdfNumberFormatScript>());
      expect(parse('\r\n  AFNumber_Keystroke(2, 0, 0, 0, "", true);\r\n', k),
          isA<PdfNumberKeystrokeScript>());
      expect(parse('/* generated */ AFPercent_Format(2, 0); // trailing', f),
          isA<PdfPercentFormatScript>());
      expect(parse("AFDate_FormatEx('mm/dd/yyyy');", f),
          isA<PdfDateFormatScript>());
      expect(parse('AFRange_Validate(true, 0, true, 100);', v),
          isA<PdfRangeValidateScript>());
      expect(parse('AFSpecial_Keystroke(3);', k),
          isA<PdfSpecialKeystrokeScript>());
    });

    test('AFSimple_Calculate field lists: new Array, literal, and list', () {
      for (final src in [
        'AFSimple_Calculate("SUM", new Array ("A", "B.c"));',
        'AFSimple_Calculate("SUM", ["A", "B.c"]);',
        'AFSimple_Calculate("sum", "A, B.c");',
      ]) {
        final s = parse(src, c);
        expect(s, isA<PdfSimpleCalculateScript>(), reason: src);
        s as PdfSimpleCalculateScript;
        expect(s.operation, PdfSimpleCalculation.sum);
        expect(s.fields, ['A', 'B.c']);
      }
    });

    test('string escapes in arguments', () {
      final s = parse(r'AFNumber_Format(2, 0, 0, 0, "\\\" ", false);', f)
          as PdfNumberFormatScript;
      expect(s.style.currency, r'\" ');
      expect(s.style.currencyPrepend, isFalse);
    });

    test('legacy numeric date and time formats map to their patterns', () {
      String pattern(String src, PdfFieldScriptTrigger t) {
        final s = parse(src, t);
        return switch (s) {
          PdfDateFormatScript(:final dateFormat) => dateFormat,
          PdfDateKeystrokeScript(:final dateFormat) => dateFormat,
          _ => fail('$src not recognised: $s'),
        };
      }

      expect(pattern('AFDate_Format(0);', f), 'm/d');
      expect(pattern('AFDate_Format(2);', f), 'mm/dd/yy');
      expect(pattern('AFDate_Format(11);', f), 'mmmm d, yyyy');
      expect(pattern('AFDate_Keystroke(7);', k), 'yy-mm-dd');
      expect(pattern('AFTime_Format(1);', f), 'h:MM tt');
      expect(pattern('AFTime_Keystroke(2);', k), 'HH:MM:ss');
      expect(pattern('AFTime_FormatEx("HH:MM");', f), 'HH:MM');
      expect(parse('AFDate_Format(99);', f), isA<PdfUnsupportedFieldScript>());
    });

    test('arbitrary scripts are unsupported and say why', () {
      final s = parse('event.value = this.getField("A").value * 2;', c);
      expect(s, isA<PdfUnsupportedFieldScript>());
      expect(s.isSupported, isFalse);
      expect(s.trigger, c);
      expect((s as PdfUnsupportedFieldScript).reason, isNotEmpty);

      // two statements are not one helper call
      expect(parse('AFNumber_Format(2,0,0,0,"",true); app.alert("hi");', f),
          isA<PdfUnsupportedFieldScript>());
      // unknown helper
      expect(parse('AFExactMatch(/x/, "y");', v),
          isA<PdfUnsupportedFieldScript>());
      // unknown AFSimple_Calculate function
      expect(parse('AFSimple_Calculate("MEDIAN", "A");', c),
          isA<PdfUnsupportedFieldScript>());
      expect(parse('', f), isA<PdfUnsupportedFieldScript>());
    });

    test('a helper under the wrong trigger is not run', () {
      final s = parse('AFNumber_Format(2, 0, 0, 0, "", true);', k);
      expect(s, isA<PdfUnsupportedFieldScript>());
      expect((s as PdfUnsupportedFieldScript).reason, contains('format'));
    });

    test('simplified field notation', () {
      final s = parse(
          '/*** BVCALC (Qty * Price) - Line\\ 2.Discount EVCALC ***/ '
          'event.value = AFMakeNumber(getField("Qty").value) * ...',
          c);
      expect(s, isA<PdfSimplifiedCalculateScript>());
      s as PdfSimplifiedCalculateScript;
      expect(s.inputs, ['Qty', 'Price', 'Line 2.Discount']);
      final values = {'Qty': '3', 'Price': '2.5', 'Line 2.Discount': '1'};
      expect(s.calculate((n) => [values[n]]), '6.5');
      expect(parse('/*** BVCALC A * EVCALC ***/', c),
          isA<PdfUnsupportedFieldScript>());
    });
  });

  group('AFMakeNumber', () {
    test('reads numbers leniently, rejects everything else', () {
      expect(pdfAfMakeNumber('12'), 12);
      expect(pdfAfMakeNumber(' -1.5 '), -1.5);
      expect(pdfAfMakeNumber('+.5'), 0.5);
      expect(pdfAfMakeNumber('1,5'), 1.5);
      expect(pdfAfMakeNumber('1,234.5'), 1234.5);
      expect(pdfAfMakeNumber('1e3'), 1000);
      expect(pdfAfMakeNumber(''), isNull);
      expect(pdfAfMakeNumber(null), isNull);
      expect(pdfAfMakeNumber('abc'), isNull);
      expect(pdfAfMakeNumber('12abc'), isNull);
      expect(pdfAfMakeNumber('Off'), isNull);
    });
  });

  group('AFNumber_Format', () {
    String show(String args, String value) =>
        fmt('AFNumber_Format($args);').format(value).text;

    test('sepStyle 0-4', () {
      expect(show('2, 0, 0, 0, "", true', '1234567.891'), '1,234,567.89');
      expect(show('2, 1, 0, 0, "", true', '1234567.891'), '1234567.89');
      expect(show('2, 2, 0, 0, "", true', '1234567.891'), '1.234.567,89');
      expect(show('2, 3, 0, 0, "", true', '1234567.891'), '1234567,89');
      expect(show('2, 4, 0, 0, "", true', '1234567.891'), "1'234'567.89");
      expect(show('0, 0, 0, 0, "", true', '999.5'), '1,000');
      expect(show('3, 0, 0, 0, "", true', '12'), '12.000');
      expect(show('2, 0, 0, 0, "", true', '123'), '123.00');
    });

    test('negStyle and currency placement', () {
      PdfFieldDisplay d(String args, String value) =>
          fmt('AFNumber_Format($args);').format(value);
      // 0: minus sign, before a prepended currency
      expect(d('2, 0, 0, 0, "\$", true', '-1234.5').text, r'-$1,234.50');
      expect(d('2, 0, 0, 0, " EUR", false', '-1234.5').text, '-1,234.50 EUR');
      // 1: red, no sign
      expect(d('2, 0, 1, 0, "\$", true', '-3'),
          const PdfFieldDisplay(r'$3.00', textColor: 0xFF0000));
      expect(d('2, 0, 1, 0, "\$", true', '3'), const PdfFieldDisplay(r'$3.00'));
      // 2: parentheses around currency and number
      expect(
          d('2, 0, 2, 0, "\$", true', '-3'), const PdfFieldDisplay(r'($3.00)'));
      expect(d('2, 2, 2, 0, " €", false', '-1234.5').text, '(1.234,50 €)');
      // 3: red parentheses
      expect(d('2, 0, 3, 0, "", true', '-3'),
          const PdfFieldDisplay('(3.00)', textColor: 0xFF0000));
      // a value that rounds to zero carries no sign
      expect(
          d('2, 0, 2, 0, "", true', '-0.001'), const PdfFieldDisplay('0.00'));
      expect(d('2, 0, 0, 0, "", true', '-0.004').text, '0.00');
    });

    test('empty and non-numeric values show nothing', () {
      expect(show('2, 0, 0, 0, "\$", true', ''), '');
      expect(show('2, 0, 0, 0, "\$", true', 'n/a'), '');
    });

    test('missing trailing arguments take the helper defaults', () {
      expect(show('1', '1234.56'), '1,234.6');
    });
  });

  group('AFNumber_Keystroke', () {
    test('partial input: digits, one sign, one decimal separator', () {
      final dot = key('AFNumber_Keystroke(2, 0, 0, 0, "", true);');
      for (final ok in ['', '1', '-', '+1', '-12.', '.5', '12.34']) {
        expect(dot.acceptsPartial(ok), isTrue, reason: ok);
      }
      for (final bad in ['a', '1.2.3', '1,2', '--1', '1-']) {
        expect(dot.acceptsPartial(bad), isFalse, reason: bad);
      }
      final comma = key('AFNumber_Keystroke(2, 2, 0, 0, "", true);');
      expect(comma.acceptsPartial('12,5'), isTrue);
      expect(comma.acceptsPartial('12.5'), isFalse);
    });

    test('commit validates and normalises', () {
      final dot = key('AFNumber_Keystroke(2, 0, 0, 0, "\$", true);');
      expect(dot.commit('12.5').value, '12.5');
      expect(dot.commit(' +7 ').value, '7');
      expect(dot.commit('').isValid, isTrue);
      // what the formatted display contains reads back
      expect(dot.commit(r'$1,234.50').value, '1234.50');
      expect(dot.commit(r'($3.00)').value, '-3.00');
      // a comma that is not thousands grouping is refused, not guessed at
      final bad = dot.commit('1,5', fieldName: 'Amount');
      expect(bad.isValid, isFalse);
      expect(bad.failure, PdfFieldInputFailure.format);
      expect(bad.message, contains('"Amount"'));
      expect(dot.commit('12.').isValid, isTrue);
      expect(dot.commit('.').isValid, isFalse);
      expect(dot.commit('abc').isValid, isFalse);

      final comma = key('AFNumber_Keystroke(2, 2, 0, 0, " €", false);');
      expect(comma.commit('1234,5').value, '1234.5');
      expect(comma.commit('1.234,5 €').value, '1234.5');
      expect(comma.commit('1234.5').isValid, isFalse);
    });
  });

  group('AFPercent', () {
    test('format shows the fraction times 100', () {
      expect(fmt('AFPercent_Format(2, 0);').format('0.125').text, '12.50%');
      expect(fmt('AFPercent_Format(0, 0);').format('12.5').text, '1,250%');
      expect(fmt('AFPercent_Format(1, 2);').format('0.5').text, '50,0%');
      expect(fmt('AFPercent_Format(1, 0, true);').format('0.5').text, '%50.0');
      expect(fmt('AFPercent_Format(1, 0);').format('-0.5').text, '-50.0%');
      expect(fmt('AFPercent_Format(2, 0);').format('').text, '');
    });

    test('keystroke takes a number, and "15%" as 0.15', () {
      final s = key('AFPercent_Keystroke(2, 0);');
      expect(s.acceptsPartial('12.5'), isTrue);
      expect(s.acceptsPartial('12%'), isTrue);
      expect(s.acceptsPartial('x'), isFalse);
      expect(s.commit('0.15').value, '0.15');
      expect(s.commit('15%').value, '0.15');
      expect(s.commit('12.5 %').value, '0.125');
      expect(s.commit('abc%').isValid, isFalse);
    });
  });

  group('dates', () {
    final now = DateTime(2026, 9, 23);
    final date = DateTime(2024, 3, 5, 14, 7, 9);

    test('util.printd tokens', () {
      expect(pdfPrintDate('mm/dd/yyyy', date), '03/05/2024');
      expect(pdfPrintDate('m/d/yy', date), '3/5/24');
      expect(
          pdfPrintDate('dddd, mmmm d, yyyy', date), 'Tuesday, March 5, 2024');
      expect(pdfPrintDate('ddd d-mmm-yy', date), 'Tue 5-Mar-24');
      expect(pdfPrintDate('HH:MM:ss', date), '14:07:09');
      expect(pdfPrintDate('h:MM tt', date), '2:07 pm');
      expect(pdfPrintDate('hh:MM t', DateTime(2024, 1, 1, 0, 5)), '12:05 a');
      expect(pdfPrintDate(r'yyyy\m', date), '2024m');
    });

    test('parsing: exact, lenient, two-digit years, invalid dates', () {
      expect(pdfParseDate('03/05/2024', 'mm/dd/yyyy'), DateTime(2024, 3, 5));
      expect(pdfParseDate('3/5/2024', 'mm/dd/yyyy'), DateTime(2024, 3, 5));
      expect(pdfParseDate('3-5-2024', 'mm/dd/yyyy'), DateTime(2024, 3, 5));
      expect(pdfParseDate('2024-03-05', 'yyyy-mm-dd'), DateTime(2024, 3, 5));
      expect(pdfParseDate('5-Mar-24', 'd-mmm-yy'), DateTime(2024, 3, 5));
      expect(
          pdfParseDate('March 5, 2024', 'mmmm d, yyyy'), DateTime(2024, 3, 5));
      expect(
          pdfParseDate('5 march 2024', 'mmmm d, yyyy'), DateTime(2024, 3, 5));
      expect(pdfParseDate('3/5/99', 'm/d/yy'), DateTime(1999, 3, 5));
      expect(pdfParseDate('3/5/49', 'm/d/yy'), DateTime(2049, 3, 5));
      // no year typed: the current year
      expect(pdfParseDate('3/5', 'mm/dd/yyyy', now: now), DateTime(2026, 3, 5));
      expect(pdfParseDate('2/29/2024', 'mm/dd/yyyy'), DateTime(2024, 2, 29));
      expect(pdfParseDate('2/29/2023', 'mm/dd/yyyy'), isNull);
      expect(pdfParseDate('13/01/2024', 'mm/dd/yyyy'), isNull);
      expect(pdfParseDate('hello', 'mm/dd/yyyy'), isNull);
      expect(pdfParseDate('1/2/3/4', 'mm/dd/yyyy'), isNull);
      expect(pdfParseDate('', 'mm/dd/yyyy'), isNull);
    });

    test('parsing times', () {
      final base = DateTime(2026, 9, 23);
      expect(pdfParseDate('2:30 pm', 'h:MM tt', now: base),
          DateTime(2026, 9, 23, 14, 30));
      expect(pdfParseDate('12:15 am', 'h:MM tt', now: base),
          DateTime(2026, 9, 23, 0, 15));
      expect(pdfParseDate('14:30', 'HH:MM', now: base),
          DateTime(2026, 9, 23, 14, 30));
      expect(pdfParseDate('25:00', 'HH:MM', now: base), isNull);
      expect(pdfParseDate('3/5/24 2:07 pm', 'm/d/yy h:MM tt'),
          DateTime(2024, 3, 5, 14, 7));
    });

    test('AFDate_FormatEx reprints a readable date, leaves the rest', () {
      final s = fmt('AFDate_FormatEx("dd mmm yyyy");');
      // numbers are read in the field's own order: day first here
      expect(s.format('3/5/2024').text, '03 May 2024');
      expect(s.format('2024-03-05').text, '05 Mar 2024');
      expect(s.format('not a date').text, 'not a date');
      expect(s.format('').text, '');
      expect(fmt('AFDate_Format(2);').format('3/5/2024').text, '03/05/24');
      expect(
          fmt('AFTime_Format(1);').format('14:07', now: now).text, '2:07 pm');
    });

    test('AFDate_KeystrokeEx: anything while typing, a date on commit', () {
      final s = key('AFDate_KeystrokeEx("mm/dd/yyyy");');
      expect(s.acceptsPartial('3/'), isTrue);
      expect(s.acceptsPartial('garbage'), isTrue);
      // the stored value stays as typed
      expect(s.commit(' 3/5/2024 ').value, '3/5/2024');
      expect(s.commit('').isValid, isTrue);
      final bad = s.commit('2/30/2024', fieldName: 'Due');
      expect(bad.isValid, isFalse);
      expect(bad.failure, PdfFieldInputFailure.date);
      expect(bad.message, contains('"Due"'));
      expect(bad.message, contains('mm/dd/yyyy'));
    });
  });

  group('AFSpecial', () {
    test('util.printx', () {
      expect(pdfPrintMask('999-99-9999', '123456789'), '123-45-6789');
      expect(pdfPrintMask('999-99-9999', '123-45-6789'), '123-45-6789');
      expect(pdfPrintMask('(999) 999-9999', '555.123.4567'), '(555) 123-4567');
      expect(pdfPrintMask('>AAA-999', 'abc123'), 'ABC-123');
      expect(pdfPrintMask(r'\9X*', 'a-bcd'), '9a-bcd');
      // stops as soon as the source runs out, literals included
      expect(pdfPrintMask('99999-9999', '12345'), '12345');
    });

    test('format: zip, zip+4, phone (7 and 10 digit), SSN', () {
      String show(int psf, String value) =>
          fmt('AFSpecial_Format($psf);').format(value).text;
      expect(show(0, '123456'), '12345');
      expect(show(1, '123456789'), '12345-6789');
      expect(show(2, '5551234567'), '(555) 123-4567');
      expect(show(2, '5551234'), '555-1234');
      expect(show(3, '123456789'), '123-45-6789');
      expect(show(3, ''), '');
    });

    test('keystroke: masked or bare placeholders, prefix while typing', () {
      final ssn = key('AFSpecial_Keystroke(3);');
      expect(ssn.acceptsPartial('123-4'), isTrue);
      expect(ssn.acceptsPartial('12345'), isTrue);
      expect(ssn.acceptsPartial('12a'), isFalse);
      expect(ssn.acceptsPartial('1234567890'), isFalse);
      expect(ssn.commit('123-45-6789').value, '123-45-6789');
      expect(ssn.commit('123456789').value, '123456789');
      expect(ssn.commit('12345678').isValid, isFalse);
      expect(ssn.commit('123 45 6789').isValid, isFalse);

      final zip = key('AFSpecial_Keystroke(0);');
      expect(zip.commit('12345').isValid, isTrue);
      expect(zip.commit('1234').isValid, isFalse);
      final zip4 = key('AFSpecial_Keystroke(1);');
      expect(zip4.commit('12345-6789').isValid, isTrue);
      expect(zip4.commit('123456789').isValid, isTrue);
      expect(zip4.commit('12345').isValid, isFalse);

      final phone = key('AFSpecial_Keystroke(2);');
      expect(phone.commit('555-1234').isValid, isTrue);
      expect(phone.commit('5551234').isValid, isTrue);
      expect(phone.commit('(555) 123-4567').isValid, isTrue);
      expect(phone.commit('5551234567').isValid, isTrue);
      expect(phone.commit('555-12345').isValid, isFalse);
      expect(phone.acceptsPartial('(555'), isTrue);
    });

    test('AFSpecial_KeystrokeEx custom masks', () {
      final s = key('AFSpecial_KeystrokeEx("AA-9999");');
      expect(s.acceptsPartial('AB-12'), isTrue);
      expect(s.acceptsPartial('A1'), isFalse);
      expect(s.commit('AB-1234').isValid, isTrue);
      expect(s.commit('AB1234').isValid, isTrue);
      expect(s.commit('AB-123').isValid, isFalse);
      final any = key('AFSpecial_KeystrokeEx("OOX");');
      expect(any.commit('a1#').isValid, isTrue);
      expect(any.commit('#1a').isValid, isFalse);
    });
  });

  group('AFRange_Validate', () {
    PdfFieldInputResult? check(String args, String value) =>
        (parse('AFRange_Validate($args);', v) as PdfValidateScript)
            .validate(value);

    test('both bounds are inclusive', () {
      expect(check('true, 0, true, 100', '0'), isNull);
      expect(check('true, 0, true, 100', '100'), isNull);
      expect(check('true, 0, true, 100', '50.5'), isNull);
      final low = check('true, 0, true, 100', '-0.01')!;
      expect(low.failure, PdfFieldInputFailure.range);
      expect(
          low.message,
          'Invalid value: must be greater than or equal to 0 and less than '
          'or equal to 100.');
      expect(check('true, 0, true, 100', '100.5'), isNotNull);
    });

    test('one-sided bounds', () {
      expect(check('true, 10, false, 0', '10'), isNull);
      expect(check('true, 10, false, 0', '9')!.message,
          'Invalid value: must be greater than or equal to 10.');
      expect(check('false, 0, true, 1.5', '1.5'), isNull);
      expect(check('false, 0, true, 1.5', '2')!.message,
          'Invalid value: must be less than or equal to 1.5.');
      expect(check('false, 0, false, 0', '-1e9'), isNull);
    });

    test('empty and non-numeric values pass', () {
      expect(check('true, 0, true, 100', ''), isNull);
      expect(check('true, 0, true, 100', 'abc'), isNull);
    });
  });

  group('AFSimple_Calculate', () {
    String calc(String op, Map<String, List<String?>> values,
            [List<String> names = const ['A', 'B', 'C']]) =>
        (parse('AFSimple_Calculate("$op", ${names.map((n) => '"$n"').toList()});',
                c) as PdfCalculateScript)
            .calculate((n) => values[n] ?? const []);

    final values = {
      'A': ['2'],
      'B': ['3.5'],
      'C': ['-1'],
    };

    test('SUM AVG PRD MIN MAX', () {
      expect(calc('SUM', values), '4.5');
      expect(calc('AVG', values), '1.5');
      expect(calc('PRD', values), '-7');
      expect(calc('MIN', values), '-1');
      expect(calc('MAX', values), '3.5');
    });

    test('empty, non-numeric and missing fields', () {
      final sparse = {
        'A': ['2'],
        'B': [''],
        'C': ['n/a'],
      };
      // empty/non-numeric count as 0 and take part in AVG/PRD
      expect(calc('SUM', sparse), '2');
      expect(calc('AVG', sparse), '0.666667');
      expect(calc('PRD', sparse), '0');
      // a name with no field contributes nothing
      expect(
          calc('SUM', {
            'A': ['1']
          }, [
            'A',
            'Nope'
          ]),
          '1');
      expect(calc('SUM', {}, ['Nope']), '0');
    });

    test('a parent name covers every child field', () {
      expect(
          calc('SUM', {
            'Row': ['1', '2', '3'],
          }, [
            'Row'
          ]),
          '6');
    });

    test('rounded to six decimals like the helper', () {
      expect(
          calc('SUM', {
            'A': ['0.1'],
            'B': ['0.2'],
          }, [
            'A',
            'B'
          ]),
          '0.3');
      expect(
          calc('AVG', {
            'A': ['1'],
            'B': ['2'],
            'C': ['2'],
          }),
          '1.666667');
    });
  });
}
