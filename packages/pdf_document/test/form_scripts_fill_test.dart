import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:test/test.dart';

/// A text field for [_buildScriptedForm]: its name, the /AA scripts by
/// trigger key (K/F/V/C), an initial /V, and read-only.
typedef _Field = ({
  String name,
  Map<String, String> scripts,
  String? value,
  bool readOnly,
});

_Field _field(String name,
        {Map<String, String> scripts = const {},
        String? value,
        bool readOnly = false}) =>
    (name: name, scripts: scripts, value: value, readOnly: readOnly);

/// One page with one text-field widget per entry of [fields] (merged
/// field/widget dictionaries), the scripts as /JavaScript actions under
/// each field's /AA, and /CO listing the fields named in [calculationOrder]
/// (omitted entirely when null). A JS stream is used for the /C script so
/// both string and stream /JS forms are exercised.
Uint8List _buildScriptedForm(List<_Field> fields,
    {List<String>? calculationOrder}) {
  final b = CosDocumentBuilder();
  final pages = CosDictionary({'Type': const CosName('Pages')});
  final pagesRef = b.add(pages);
  final page = CosDictionary({
    'Type': const CosName('Page'),
    'Parent': pagesRef,
    'MediaBox': CosArray(
        [0, 0, 612, 792].map((v) => CosInteger(v)).toList(growable: false)),
  });
  final pageRef = b.add(page);
  final refs = <String, CosReference>{};
  final annots = <CosObject>[];
  var y = 700;
  for (final f in fields) {
    final aa = CosDictionary({});
    f.scripts.forEach((key, js) {
      aa[key] = CosDictionary({
        'S': const CosName('JavaScript'),
        'JS': key == 'C'
            ? b.add(CosStream(
                CosDictionary({}), Uint8List.fromList(utf8.encode(js))))
            : CosString.fromText(js),
      });
    });
    final dict = CosDictionary({
      'Type': const CosName('Annot'),
      'Subtype': const CosName('Widget'),
      'FT': const CosName('Tx'),
      'T': CosString.fromText(f.name),
      'Rect': CosArray([
        const CosInteger(72),
        CosInteger(y),
        const CosInteger(300),
        CosInteger(y + 20),
      ]),
      'P': pageRef,
      'DA': CosString.fromText('/Helv 10 Tf 0 g'),
      if (f.value != null) 'V': CosString.fromText(f.value!),
      if (f.readOnly) 'Ff': const CosInteger(PdfFormField.readOnlyFlag),
      if (aa.entries.isNotEmpty) 'AA': aa,
    });
    final ref = b.add(dict);
    refs[f.name] = ref;
    annots.add(ref);
    y -= 30;
  }
  page['Annots'] = CosArray(annots);
  pages['Kids'] = CosArray([pageRef]);
  pages['Count'] = const CosInteger(1);
  final helv = b.add(CosDictionary({
    'Type': const CosName('Font'),
    'Subtype': const CosName('Type1'),
    'BaseFont': const CosName('Helvetica'),
  }));
  final acroForm = CosDictionary({
    'Fields': CosArray(annots),
    'DA': CosString.fromText('/Helv 0 Tf 0 g'),
    'DR': CosDictionary({
      'Font': CosDictionary({'Helv': helv}),
    }),
    if (calculationOrder != null)
      'CO': CosArray([for (final n in calculationOrder) refs[n]!]),
  });
  final catalog = b.add(CosDictionary({
    'Type': const CosName('Catalog'),
    'Pages': pagesRef,
    'AcroForm': acroForm,
  }));
  return b.build(root: catalog);
}

String _appearance(PdfDocument doc, PdfFormField field) {
  final cos = doc.cos;
  final ap = cos.resolve(field.widgets.first['AP']) as CosDictionary;
  final n = cos.resolve(ap['N']) as CosStream;
  return latin1.decode(cos.decodeStreamData(n));
}

void main() {
  const money = 'AFNumber_Format(2, 0, 0, 0, "\$", true);';
  const moneyKey = 'AFNumber_Keystroke(2, 0, 0, 0, "\$", true);';

  /// An invoice: two line amounts, a subtotal, 10% tax via simplified field
  /// notation, and a total - a three-step dependency chain.
  List<_Field> invoice() => [
        _field('Line.1', scripts: {'K': moneyKey, 'F': money}),
        _field('Line.2', scripts: {'K': moneyKey, 'F': money}),
        _field('Subtotal',
            readOnly: true,
            scripts: {'F': money, 'C': 'AFSimple_Calculate("SUM", "Line");'}),
        _field('Tax', readOnly: true, scripts: {
          'F': money,
          'C': '/*** BVCALC Subtotal * 0.1 EVCALC ***/ event.value = '
              'AFMakeNumber(getField("Subtotal").value) * 0.1',
        }),
        _field('Total', readOnly: true, scripts: {
          'F': money,
          'C': 'AFSimple_Calculate("SUM", new Array ("Subtotal", "Tax"));',
        }),
      ];

  PdfDocument roundTrip(Uint8List bytes, void Function(PdfEditor) edit) {
    final editor = PdfEditor(PdfDocument.open(bytes));
    edit(editor);
    return PdfDocument.open(editor.save());
  }

  group('field scripts on the model', () {
    test('recognised and skipped scripts are exposed per field', () {
      final form = PdfAcroForm.of(PdfDocument.open(_buildScriptedForm([
        _field('Amount', scripts: {
          'K': moneyKey,
          'F': money,
          'V': 'AFRange_Validate(true, 0, false, 0);',
        }),
        _field('Custom', scripts: {
          'F': 'event.value = util.printd("yyyy", new Date());',
          'C': 'AFSimple_Calculate("SUM", "Amount");',
        }),
        _field('Plain'),
      ])))!;

      final amount = form.fieldNamed('Amount')!.scripts;
      expect(amount.keystroke, isA<PdfNumberKeystrokeScript>());
      expect(amount.format, isA<PdfNumberFormatScript>());
      expect(amount.validate, isA<PdfRangeValidateScript>());
      expect(amount.recognized, hasLength(3));
      expect(amount.hasUnsupported, isFalse);

      final custom = form.fieldNamed('Custom')!.scripts;
      expect(custom.unsupported.single.trigger, PdfFieldScriptTrigger.format);
      expect(custom.unsupported.single.source, contains('util.printd'));
      // the /C script is a stream here and still reads
      expect(custom.calculate, isA<PdfSimpleCalculateScript>());

      expect(form.fieldNamed('Plain')!.scripts.isEmpty, isTrue);
    });

    test('calculationOrder follows /CO, then calculated fields it omits', () {
      final form = PdfAcroForm.of(PdfDocument.open(_buildScriptedForm(invoice(),
          calculationOrder: ['Total', 'Subtotal'])))!;
      expect(form.calculationOrder.map((f) => f.name),
          ['Total', 'Subtotal', 'Tax']);
    });
  });

  group('calculations', () {
    test('a fill re-runs the chain in /CO order within the same edit', () {
      final doc = roundTrip(
          _buildScriptedForm(invoice(),
              calculationOrder: ['Subtotal', 'Tax', 'Total']), (e) {
        final form = e.acroForm!;
        e.setTextValue(form.fieldNamed('Line.1')!, '100');
        e.setTextValue(form.fieldNamed('Line.2')!, '23.5');
      });
      final form = PdfAcroForm.of(doc)!;
      expect(form.fieldNamed('Subtotal')!.value, '123.5');
      expect(form.fieldNamed('Tax')!.value, '12.35');
      expect(form.fieldNamed('Total')!.value, '135.85');

      // read-only calculated fields got appearances, formatted
      final total = form.fieldNamed('Total')!;
      expect(_appearance(doc, total), contains(r'($135.85) Tj'));
      expect(total.formattedValue, r'$135.85');
    });

    test('/CO order is honoured as written: a wrong order stays stale', () {
      // Total before Subtotal: Total sees the previous subtotal, exactly as
      // a single ordered pass in a conforming viewer does
      final doc = roundTrip(
          _buildScriptedForm(invoice(),
              calculationOrder: ['Total', 'Tax', 'Subtotal']), (e) {
        e.setTextValue(e.acroForm!.fieldNamed('Line.1')!, '100');
      });
      final form = PdfAcroForm.of(doc)!;
      expect(form.fieldNamed('Subtotal')!.value, '100');
      // Tax and Total ran on the old (empty) subtotal
      expect(form.fieldNamed('Tax')!.value, '0');
      expect(form.fieldNamed('Total')!.value, '0');
    });

    test('forms without /CO still calculate, in field order', () {
      final doc = roundTrip(_buildScriptedForm(invoice()), (e) {
        e.setTextValue(e.acroForm!.fieldNamed('Line.2')!, '10');
      });
      final form = PdfAcroForm.of(doc)!;
      expect(form.fieldNamed('Total')!.value, '11');
    });

    test('recalculateFields reports what changed and skips no-ops', () {
      final editor = PdfEditor(PdfDocument.open(_buildScriptedForm([
        ...invoice(),
      ], calculationOrder: [
        'Subtotal',
        'Tax',
        'Total'
      ])));
      final first = editor.recalculateFields();
      // empty lines sum to 0
      expect(first.map((c) => '${c.field.name}=${c.value}'),
          ['Subtotal=0', 'Tax=0', 'Total=0']);
      expect(editor.recalculateFields(), isEmpty);
    });

    test('the field just entered keeps its value', () {
      final doc = roundTrip(
          _buildScriptedForm([
            _field('A'),
            _field('Sum', scripts: {'C': 'AFSimple_Calculate("SUM", "A");'}),
          ]), (e) {
        final form = e.acroForm!;
        e.setTextValue(form.fieldNamed('A')!, '4');
        // overriding the calculated field by hand stands until an input
        // changes again
        e.setTextValue(form.fieldNamed('Sum')!, '99');
      });
      expect(PdfAcroForm.of(doc)!.fieldNamed('Sum')!.value, '99');
    });

    test('unsupported calculate scripts are left alone', () {
      final doc = roundTrip(
          _buildScriptedForm([
            _field('A'),
            _field('B',
                value: 'kept',
                scripts: {'C': 'event.value = getField("A").value * 2;'}),
          ]), (e) {
        e.setTextValue(e.acroForm!.fieldNamed('A')!, '4');
      });
      expect(PdfAcroForm.of(doc)!.fieldNamed('B')!.value, 'kept');
    });
  });

  group('format on the appearance', () {
    test('/V stays raw while the appearance shows the formatted value', () {
      final doc = roundTrip(
          _buildScriptedForm([
            _field('Amount', scripts: {'F': money}),
            _field('When', scripts: {'F': 'AFDate_FormatEx("mmmm d, yyyy");'}),
            _field('SSN', scripts: {'F': 'AFSpecial_Format(3);'}),
            _field('Rate', scripts: {'F': 'AFPercent_Format(1, 0);'}),
          ]), (e) {
        final form = e.acroForm!;
        e.setTextValue(form.fieldNamed('Amount')!, '1234.5');
        e.setTextValue(form.fieldNamed('When')!, '3/5/2024');
        e.setTextValue(form.fieldNamed('SSN')!, '123456789');
        e.setTextValue(form.fieldNamed('Rate')!, '0.075');
      });
      final form = PdfAcroForm.of(doc)!;
      void check(String name, String raw, String shown) {
        final field = form.fieldNamed(name)!;
        expect(field.value, raw);
        expect(_appearance(doc, field), contains('($shown) Tj'));
      }

      check('Amount', '1234.5', r'$1,234.50');
      check('When', '3/5/2024', 'March 5, 2024');
      check('SSN', '123456789', '123-45-6789');
      check('Rate', '0.075', '7.5%');
    });

    test('negative red styles paint the text red', () {
      final doc = roundTrip(
          _buildScriptedForm([
            _field('Balance',
                scripts: {'F': 'AFNumber_Format(2, 0, 3, 0, "", true);'}),
          ]), (e) {
        e.setTextValue(e.acroForm!.fieldNamed('Balance')!, '-12');
      });
      final ap = _appearance(doc, PdfAcroForm.of(doc)!.fieldNamed('Balance')!);
      expect(ap, contains('1 0 0 rg'));
      expect(ap, contains(r'(\(12.00\)) Tj'));
    });

    test('flattening keeps the formatted text', () {
      final doc = roundTrip(
          _buildScriptedForm([
            _field('Amount', value: '5', scripts: {'F': money}),
          ]),
          (e) => e.flattenForm());
      final resources =
          doc.cos.resolve(doc.page(0).dict['Resources']) as CosDictionary;
      final xobjects = doc.cos.resolve(resources['XObject']) as CosDictionary;
      final flat = [
        for (final ref in xobjects.entries.values)
          latin1.decode(
              doc.cos.decodeStreamData(doc.cos.resolve(ref) as CosStream)),
      ].join();
      expect(flat, contains(r'($5.00) Tj'));
    });
  });

  group('enterTextValue', () {
    Uint8List form() => _buildScriptedForm([
          _field('Amount', scripts: {
            'K': 'AFNumber_Keystroke(2, 2, 0, 0, " kr", false);',
            'F': 'AFNumber_Format(2, 2, 0, 0, " kr", false);',
            'V': 'AFRange_Validate(true, 0, true, 1000);',
          }),
          _field('Due', scripts: {'K': 'AFDate_KeystrokeEx("dd/mm/yyyy");'}),
          _field('Free'),
        ]);

    test('normalises a valid entry before storing it', () {
      late PdfFieldInputResult result;
      final doc = roundTrip(form(), (e) {
        result = e.enterTextValue(e.acroForm!.fieldNamed('Amount')!, '12,5');
      });
      expect(result.isValid, isTrue);
      final field = PdfAcroForm.of(doc)!.fieldNamed('Amount')!;
      expect(field.value, '12.5');
      expect(_appearance(doc, field), contains('(12,50 kr) Tj'));
    });

    test('refuses keystroke and range failures with a message', () {
      final editor = PdfEditor(PdfDocument.open(form()));
      final amount = editor.acroForm!.fieldNamed('Amount')!;
      expect(
          () => editor.enterTextValue(amount, 'twelve'),
          throwsA(isA<PdfFieldInputException>()
              .having((e) => e.result.failure, 'failure',
                  PdfFieldInputFailure.format)
              .having((e) => e.message, 'message', contains('"Amount"'))));
      expect(
          () => editor.enterTextValue(amount, '1000,01'),
          throwsA(isA<PdfFieldInputException>().having(
              (e) => e.result.failure, 'failure', PdfFieldInputFailure.range)));
      final due = editor.acroForm!.fieldNamed('Due')!;
      expect(() => editor.enterTextValue(due, '31/02/2024'),
          throwsA(isA<ArgumentError>()));
      // nothing was written
      expect(editor.acroForm!.fieldNamed('Amount')!.value, isNull);

      // the checks alone, for a UI that validates before committing
      expect(amount.checkInput('5').isValid, isTrue);
      expect(amount.acceptsPartialInput('5,2'), isTrue);
      expect(amount.acceptsPartialInput('5x'), isFalse);
    });

    test('fields without scripts store the value verbatim', () {
      final doc = roundTrip(form(), (e) {
        e.enterTextValue(e.acroForm!.fieldNamed('Free')!, '  anything ');
      });
      expect(PdfAcroForm.of(doc)!.fieldNamed('Free')!.value, '  anything ');
    });
  });
}
