import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

/// The fixture form with every fillable field changed.
Uint8List _filledForm() {
  final editor = PdfEditor(PdfDocument.open(buildAcroFormPdf()));
  final form = editor.acroForm!;
  editor
    ..setTextValue(form.fieldNamed('name')!, 'Ada Lovelace')
    ..setTextValue(form.fieldNamed('address')!, '12 Analytical Way\nLondon')
    ..setCheckBoxValue(form.fieldNamed('agree')!, true)
    ..setRadioValue(form.fieldNamed('color')!, 'Blue')
    ..setChoiceValue(form.fieldNamed('size')!, 'Large');
  return editor.save();
}

/// The fixture form with a few comments, one reply among them.
Uint8List _commentedForm() {
  final editor = PdfEditor(PdfDocument.open(buildAcroFormPdf()));
  editor
    ..addHighlight(0, [const PdfRect(72, 700, 200, 714)],
        color: 0x00FF00, contents: 'check this', author: 'Ada', name: 'hl-1')
    ..addSquare(0, const PdfRect(300, 300, 400, 380),
        strokeColor: 0x0000FF, strokeWidth: 3, author: 'Ada', name: 'sq-1')
    ..addInk(
        0,
        [
          [(100, 100), (150, 160), (200, 120)],
        ],
        author: 'Ada',
        name: 'ink-1')
    ..addNote(0, 500, 700, 'a sticky note', author: 'Ada', name: 'note-1');
  final doc = PdfDocument.open(editor.save());
  final replier = PdfEditor(doc);
  final note = doc.page(0).annotations.firstWhere((a) => a.name == 'note-1');
  replier.replyToAnnotation(0, note, 'a reply', author: 'Charles');
  return replier.save();
}

Map<String, PdfAnnotation> _byName(PdfDocument doc) => {
      for (final a in doc.page(0).annotations)
        if (a.name != null) a.name!: a,
    };

void main() {
  group('pdfSniffExchangeFormat', () {
    test('tells the four formats apart', () {
      expect(pdfSniffExchangeFormat(buildAcroFormPdf()), PdfExchangeFormat.pdf);
      expect(
          pdfSniffExchangeFormat(PdfFormData().toFdf()), PdfExchangeFormat.fdf);
      expect(pdfSniffExchangeFormat(PdfFormData().toXfdf()),
          PdfExchangeFormat.xfdf);
      expect(
          pdfSniffExchangeFormat(
              PdfXdpPackage.build(PdfDocument.open(buildAcroFormPdf()))),
          PdfExchangeFormat.xdp);
      expect(
          pdfSniffExchangeFormat(
              utf8.encode('<?xml version="1.0"?>\n<!-- hi -->\n<html></html>')),
          isNull);
      expect(pdfSniffExchangeFormat(utf8.encode('hello')), isNull);
    });
  });

  group('form data', () {
    for (final (format, write) in [
      ('FDF', (PdfFormData d) => d.toFdf()),
      ('XFDF', (PdfFormData d) => d.toXfdf()),
    ]) {
      test('$format round-trips every fillable field', () {
        final data = PdfFormData.of(PdfDocument.open(_filledForm()),
            annotations: false, targetFile: 'form.pdf');
        final parsed = PdfFormData.parse(write(data));
        expect(parsed.targetFile, 'form.pdf');

        final editor = PdfEditor(PdfDocument.open(buildAcroFormPdf()));
        final result = editor.importFormData(parsed);
        expect(result.filledFields,
            unorderedEquals(['name', 'address', 'agree', 'color', 'size']));
        // the read-only serial already holds the exported value
        expect(result.skippedFields, isEmpty);
        expect(result.unmatchedFields, isEmpty);

        final form = PdfAcroForm.of(PdfDocument.open(editor.save()))!;
        expect(form.fieldNamed('name')!.value, 'Ada Lovelace');
        expect(form.fieldNamed('address')!.value, '12 Analytical Way\nLondon');
        expect(form.fieldNamed('agree')!.isChecked, isTrue);
        expect(form.fieldNamed('color')!.inherited('V'),
            isA<CosName>().having((n) => n.value, 'value', 'Blue'));
        expect(form.fieldNamed('size')!.value, 'L');
      });
    }

    test('reads an Acrobat-style FDF: no xref, nested /Kids, name values', () {
      const fdf = '%FDF-1.2\n%âãÏÓ\n'
          '1 0 obj\n<< /FDF << /F (form.pdf) /Fields [\n'
          '<< /T (name) /V (Grace Hopper) >>\n'
          '<< /T (agree) /V /Yes >>\n'
          '<< /T (color) /V /Red >>\n'
          '<< /T (serial) /V (B-2) >>\n'
          '<< /T (missing) /V (x) >>\n'
          '<< /T (parent) /Kids [ << /T (child) /V (deep) >> ] >>\n'
          '] >> >>\nendobj\n'
          'trailer\n<< /Root 1 0 R >>\n%%EOF\n';
      final data = PdfFormData.parseFdf(Uint8List.fromList(latin1.encode(fdf)));
      expect(data.targetFile, 'form.pdf');
      expect(data.fields.map((f) => f.name),
          ['name', 'agree', 'color', 'serial', 'missing', 'parent.child']);
      expect(data.fields[1].isState, isTrue);

      final editor = PdfEditor(PdfDocument.open(buildAcroFormPdf()));
      final result = editor.importFormData(data);
      expect(result.filledFields, ['name', 'agree', 'color']);
      expect(result.skippedFields.keys, ['serial']); // read-only
      expect(result.unmatchedFields, ['missing', 'parent.child']);
      final form = PdfAcroForm.of(PdfDocument.open(editor.save()))!;
      expect(form.fieldNamed('name')!.value, 'Grace Hopper');
      expect(form.fieldNamed('agree')!.isChecked, isTrue);
      expect(form.fieldNamed('serial')!.value, 'A-1000');
    });

    test('reads nested XFDF fields and reports bad values', () {
      final xfdf = utf8.encode('''<?xml version="1.0" encoding="UTF-8"?>
<xfdf xmlns="http://ns.adobe.com/xfdf/" xml:space="preserve">
  <f href="form.pdf"/>
  <fields>
    <field name="name"><value>Katherine &amp; co</value></field>
    <field name="color"><value>Green</value></field>
    <field name="size"><value>Small</value></field>
    <field name="group"><field name="inner"><value>v</value></field></field>
  </fields>
</xfdf>''');
      final data = PdfFormData.parse(xfdf);
      expect(data.fields.map((f) => f.name),
          ['name', 'color', 'size', 'group.inner']);
      final editor = PdfEditor(PdfDocument.open(buildAcroFormPdf()));
      final result = editor.importFormData(data);
      expect(result.filledFields, ['name', 'size']);
      expect(result.skippedFields.keys, ['color']); // not a radio option
      expect(result.unmatchedFields, ['group.inner']);
      final form = PdfAcroForm.of(PdfDocument.open(editor.save()))!;
      expect(form.fieldNamed('name')!.value, 'Katherine & co');
    });

    test('an import that changes nothing leaves the document clean', () {
      final data = PdfFormData.of(PdfDocument.open(buildAcroFormPdf()));
      final editor = PdfEditor(PdfDocument.open(buildAcroFormPdf()));
      final result = editor.importFormData(PdfFormData.parse(data.toFdf()));
      expect(result.changed, isFalse);
      expect(result.filledFields, isEmpty);
    });

    test('the target file identifiers travel in FDF /ID and XFDF <ids>', () {
      final ids = [
        Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]),
        Uint8List.fromList([0x01, 0x02]),
      ];
      final data = PdfFormData(documentIds: ids, targetFile: 'a.pdf');
      expect(PdfFormData.parseFdf(data.toFdf()).documentIds, ids);
      expect(PdfFormData.parseXfdf(data.toXfdf()).documentIds, ids);
      expect(utf8.decode(data.toXfdf()),
          contains('<ids original="DEADBEEF" modified="0102"/>'));
    });
  });

  group('comments', () {
    test('FDF round-trips comments with their appearances and threads', () {
      final source = PdfDocument.open(_commentedForm());
      final fdf = PdfFormData.of(source, fields: false).toFdf();
      expect(latin1.decode(fdf.sublist(0, 8)), '%FDF-1.2');

      final data = PdfFormData.parseFdf(fdf);
      expect(data.fields, isEmpty);
      expect(data.annotations.map((a) => a.subtype),
          containsAll(['Highlight', 'Square', 'Ink', 'Text']));
      expect(data.annotations.every((a) => a.subtype != 'Popup'), isTrue);

      final editor = PdfEditor(PdfDocument.open(buildAcroFormPdf()));
      final result = editor.importFormData(data);
      expect(result.annotationsAdded, data.annotations.length);
      final out = PdfDocument.open(editor.save());
      final byName = _byName(out);
      expect(byName.keys, containsAll(['hl-1', 'sq-1', 'ink-1', 'note-1']));
      expect(byName['hl-1']!.contents, 'check this');
      expect(byName['hl-1']!.author, 'Ada');
      expect(byName['sq-1']!.normalAppearance, isNotNull);
      final reply = out.page(0).annotations.firstWhere((a) => a.isReply);
      expect(reply.contents, 'a reply');
      expect(reply.author, 'Charles');
      expect(reply.inReplyTo, 'note-1');
    });

    test('XFDF round-trips comments, regenerating appearances', () {
      final source = PdfDocument.open(_commentedForm());
      final xfdf = PdfFormData.of(source, fields: false).toXfdf();
      final text = utf8.decode(xfdf);
      expect(text, contains('<highlight '));
      expect(text, contains('<inklist><gesture>'));
      expect(text, contains('inreplyto="note-1"'));

      final editor = PdfEditor(PdfDocument.open(buildAcroFormPdf()));
      final result = editor.importFormData(PdfFormData.parseXfdf(xfdf));
      expect(result.skippedAnnotations, isEmpty);
      final out = PdfDocument.open(editor.save());
      final byName = _byName(out);
      for (final name in ['hl-1', 'sq-1', 'ink-1', 'note-1']) {
        expect(byName[name]!.normalAppearance, isNotNull, reason: name);
        expect(byName[name]!.author, 'Ada', reason: name);
      }
      expect(byName['hl-1']!.color, 0x00FF00);
      expect(byName['hl-1']!.contents, 'check this');
      expect(byName['sq-1']!.color, 0x0000FF);
      expect(byName['sq-1']!.borderWidth, 3);
      expect(byName['note-1']!.contents, 'a sticky note');
      final reply = out.page(0).annotations.firstWhere((a) => a.isReply);
      expect(reply.inReplyTo, 'note-1');
      expect(reply.contents, 'a reply');
    });

    test('importing the same comments twice replaces instead of duplicating',
        () {
      final data = PdfFormData.parse(
          PdfFormData.of(PdfDocument.open(_commentedForm())).toXfdf());
      final editor = PdfEditor(PdfDocument.open(buildAcroFormPdf()));
      editor.importFormData(data);
      final once = PdfDocument.open(editor.save());
      final count = once.page(0).annotations.length;

      final again = PdfEditor(once);
      final result = again.importFormData(data);
      expect(result.annotationsAdded, 0);
      expect(result.annotationsReplaced, data.annotations.length);
      expect(PdfDocument.open(again.save()).page(0).annotations.length, count);
    });

    test('reads an Acrobat-style XFDF comment set', () {
      final xfdf = utf8.encode('''<?xml version="1.0" encoding="UTF-8" ?>
<xfdf xmlns="http://ns.adobe.com/xfdf/" xml:space="preserve">
<annots>
<square color="#FF0000" creationdate="D:20260101120000Z" flags="print"
  date="D:20260102120000Z" name="a1" page="0" rect="100,100,200,150"
  subject="Rectangle" title="Reviewer" width="2" style="dash" dashes="3,3"/>
<line color="#0000FF" page="0" rect="50,50,300,90" name="a2"
  start="60,60" end="290,80" head="None" tail="OpenArrow" width="1"/>
<polygon page="0" rect="0,0,100,100" name="a3" color="#00FF00"
  vertices="10,10;90,10;50,90"/>
<freetext page="0" rect="300,600,500,650" name="a4" justification="centered"
  color="#FFFFCC">
  <contents>Hello, free text</contents>
  <defaultappearance>/Helv 14 Tf 1 0 0 rg</defaultappearance>
</freetext>
<stamp page="0" rect="350,400,500,450" name="a5" icon="NotApproved"/>
<text page="0" rect="20,700,40,720" name="a6" icon="Comment">
  <contents-richtext><body xmlns="http://www.w3.org/1999/xhtml"><p>rich <b>note</b></p></body></contents-richtext>
</text>
<caret page="0" rect="10,10,20,20" name="a7"/>
<square page="9" rect="1,1,2,2" name="off-page" color="#000000"/>
</annots>
</xfdf>''');
      final data = PdfFormData.parse(xfdf);
      expect(data.annotations, hasLength(8));
      final editor = PdfEditor(PdfDocument.open(buildAcroFormPdf()));
      final result = editor.importFormData(data);
      expect(result.annotationsAdded, 7);
      expect(result.skippedAnnotations, hasLength(1));
      expect(result.skippedAnnotations.single, contains('off-page'));

      final byName = _byName(PdfDocument.open(editor.save()));
      final square = byName['a1']!;
      expect(square.subtype, 'Square');
      expect(square.color, 0xFF0000);
      expect(square.subject, 'Rectangle');
      expect(square.author, 'Reviewer');
      expect(square.borderDash, [3, 3]);
      expect(square.modificationDate, DateTime.utc(2026, 1, 2, 12));
      expect(square.normalAppearance, isNotNull);
      expect(byName['a2']!.normalAppearance, isNotNull);
      expect(pdfLineEndings(byName['a2']!)!.$2, PdfLineEnding.openArrow);
      expect(byName['a3']!.normalAppearance, isNotNull);
      expect(byName['a4']!.contents, 'Hello, free text');
      expect(byName['a4']!.normalAppearance, isNotNull);
      expect(byName['a5']!.subtype, 'Stamp');
      expect(byName['a5']!.normalAppearance, isNotNull);
      expect(byName['a6']!.contents, 'rich note');
      expect((byName['a6']!.dict['RC'] as CosString).text,
          contains('<b>note</b>'));
      // no generator for carets: added as given
      expect(byName['a7']!.subtype, 'Caret');
    });

    test('FDF and XFDF convert into each other', () {
      final data = PdfFormData.of(PdfDocument.open(_commentedForm()));
      final viaXfdf =
          PdfFormData.parseXfdf(PdfFormData.parseFdf(data.toFdf()).toXfdf());
      expect(viaXfdf.annotations.map((a) => a.name),
          data.annotations.map((a) => a.name));
      expect(viaXfdf.fields.map((f) => f.name), data.fields.map((f) => f.name));
      final back = PdfFormData.parseFdf(viaXfdf.toFdf());
      expect(back.annotations.map((a) => a.subtype),
          data.annotations.map((a) => a.subtype));
    });
  });

  group('XDP', () {
    test('build embeds the PDF and its form data; toPdf applies it', () {
      final filled = PdfDocument.open(_filledForm());
      final xdp = PdfXdpPackage.parse(PdfXdpPackage.build(filled));
      expect(xdp.pdf, filled.cos.bytes);
      expect(xdp.hasData, isTrue);
      expect(xdp.dataFields.map((f) => f.name), contains('name[0]'));

      // applying the package's data to the blank form fills it
      final editor = PdfEditor(PdfDocument.open(buildAcroFormPdf()));
      final result = editor.importXdp(xdp);
      expect(result.unmatchedFields, isEmpty);
      final form = PdfAcroForm.of(PdfDocument.open(editor.save()))!;
      expect(form.fieldNamed('name')!.value, 'Ada Lovelace');
      expect(form.fieldNamed('agree')!.isChecked, isTrue);
      expect(form.fieldNamed('size')!.value, 'L');

      // and opening it yields the embedded PDF unchanged (already filled)
      expect(xdp.toPdf(), filled.cos.bytes);
    });

    test('a referenced PDF is recorded, not embedded', () {
      final bytes = PdfXdpPackage.build(PdfDocument.open(buildAcroFormPdf()),
          pdfHref: 'form.pdf');
      final xdp = PdfXdpPackage.parse(bytes);
      expect(xdp.pdf, isNull);
      expect(xdp.pdfHref, 'form.pdf');
      expect(xdp.toPdf, throwsStateError);
    });

    String xdpWith(String data, {Uint8List? pdf, String extra = ''}) =>
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<xdp:xdp xmlns:xdp="http://ns.adobe.com/xdp/">'
        '<xfa:datasets xmlns:xfa="http://www.xfa.org/schema/xfa-data/1.0/">'
        '<xfa:data>$data</xfa:data></xfa:datasets>$extra'
        '${pdf == null ? '' : '<pdf xmlns="http://ns.adobe.com/xdp/pdf/">'
            '<document><chunk>${base64Encode(pdf)}</chunk></document></pdf>'}'
        '</xdp:xdp>';

    test('fills a hybrid XFA form through its AcroForm fields', () {
      final xdp = PdfXdpPackage.parse(utf8.encode(xdpWith(
          '<form1><name>fresh</name><ghost>x</ghost></form1>',
          pdf: buildXfaFormPdf())));
      final result =
          PdfEditor(PdfDocument.open(buildXfaFormPdf())).importXdp(xdp);
      expect(result.filledFields, ['name']);
      expect(result.unmatchedFields, ['form1[0].ghost[0]']);

      final opened = PdfDocument.open(xdp.toPdf());
      final form = PdfAcroForm.of(opened)!;
      expect(form.fieldNamed('name')!.value, 'fresh');
      expect(form.hasXfa, isFalse); // the stale XFA copy is dropped
    });

    test('matches XFA-style AcroForm names across page subforms', () {
      // name the fixture's field the way XFA hybrids do
      final doc = PdfDocument.open(buildAcroFormPdf());
      final editor = PdfEditor(doc);
      final field = editor.acroForm!.fieldNamed('name')!;
      field.dict['T'] = CosString.fromText('form1[0].Page1[0].name[0]');
      final renamed =
          PdfDocument.open((editor..setTextValue(field, 'x')).save());
      expect(PdfAcroForm.of(renamed)!.fields.map((f) => f.name),
          contains('form1[0].Page1[0].name[0]'));

      final xdp = PdfXdpPackage.parse(
          utf8.encode(xdpWith('<form1><name>matched</name></form1>')));
      final filler = PdfEditor(renamed);
      final result = filler.importXdp(xdp);
      expect(result.filledFields, ['form1[0].Page1[0].name[0]']);
    });

    for (final asArray in [true, false]) {
      test(
          'replaces the datasets of a dynamic XFA form '
          '(${asArray ? 'packet array' : 'single stream'})', () {
        final source = buildXfaFormPdf(withFields: false, xfaAsArray: asArray);
        final xdp = PdfXdpPackage.parse(utf8.encode(
            xdpWith('<form1><name>dynamic</name></form1>', pdf: source)));
        final editor = PdfEditor(PdfDocument.open(source));
        final result = editor.importXdp(xdp);
        expect(result.xfaDatasetsReplaced, isTrue);
        expect(result.changed, isTrue);

        final saved = PdfDocument.open(editor.save());
        expect(PdfAcroForm.of(saved)!.hasXfa, isTrue);
        final exported = utf8.decode(PdfXdpPackage.build(saved));
        expect(exported, contains('<name>dynamic</name>'));
        expect(exported, isNot(contains('stale')));
        // the form's own packets travel, with the PDF added before the end
        expect(exported, contains('<template'));
        expect(exported, contains('<chunk>'));
        expect(PdfXdpPackage.parse(utf8.encode(exported)).pdf, isNotNull);
      });
    }

    test('an embedded XFDF packet brings its comments', () {
      final xdp = PdfXdpPackage.parse(utf8.encode(xdpWith('<f/>',
          pdf: buildAcroFormPdf(),
          extra: '<xfdf xmlns="http://ns.adobe.com/xfdf/"><annots>'
              '<square page="0" rect="10,10,50,50" name="x1" color="#FF0000"/>'
              '</annots></xfdf>')));
      expect(xdp.comments!.annotations, hasLength(1));
      final opened = PdfDocument.open(xdp.toPdf());
      expect(_byName(opened)['x1']!.subtype, 'Square');
    });

    test('rejects what is not XDP', () {
      expect(() => PdfXdpPackage.parse(utf8.encode('<xfdf/>')),
          throwsFormatException);
      expect(() => PdfXdpPackage.parse(utf8.encode('<xdp:xdp')),
          throwsFormatException);
      expect(
          () => PdfFormData.parse(buildAcroFormPdf()), throwsFormatException);
    });
  });
}
