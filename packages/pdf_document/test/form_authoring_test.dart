import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

/// Authoring the field types beyond text/check box/push button (#934):
/// radio groups, combo and list boxes, and empty signature fields.
void main() {
  PdfDocument reopen(PdfEditor editor) => PdfDocument.open(editor.save());

  CosDictionary stateDict(PdfDocument doc, CosDictionary widget, String key) {
    final ap = doc.cos.resolve(widget['AP']) as CosDictionary;
    return doc.cos.resolve(ap[key]) as CosDictionary;
  }

  group('radio groups', () {
    test('one parent field, one kid widget per on-state', () {
      final editor = PdfEditor(PdfDocument.open(buildClassicPdf()));
      editor.addRadioGroup(0, 'size', [
        (const PdfRect(50, 500, 66, 516), 'S'),
        (const PdfRect(80, 500, 96, 516), 'M'),
        (const PdfRect(110, 500, 126, 516), 'L'),
      ]);

      final out = reopen(editor);
      final form = PdfAcroForm.of(out)!;
      final field = form.fieldNamed('size')!;
      expect(field.type, PdfFieldType.radioGroup);
      expect(field.widgets, hasLength(3));
      expect(field.onStates, ['S', 'M', 'L']);
      expect(field.value, 'Off');
      expect(field.isChecked, isFalse);
      for (var i = 0; i < 3; i++) {
        final widget = field.widgets[i];
        expect(widget['T'], isNull, reason: 'kids are pure widgets');
        expect(field.widgetPageIndex(i), 0);
        expect(field.widgetOnState(i), ['S', 'M', 'L'][i]);
        final normal = stateDict(out, widget, 'N');
        final down = stateDict(out, widget, 'D');
        expect(
            normal.entries.keys, unorderedEquals([field.onStates[i], 'Off']));
        expect(down.entries.keys, unorderedEquals(normal.entries.keys));
        for (final state in normal.entries.values) {
          expect(out.cos.resolve(state), isA<CosStream>());
        }
      }
      // every kid is listed on the page
      final annots = out.cos.resolve(out.page(0).dict['Annots']) as CosArray;
      expect(annots.length, 3);
      // /Fields lists the parent once, not the kids
      expect(form.fields.where((f) => f.name == 'size'), hasLength(1));
      expect(
          form.describeFields().single.rect, const PdfRect(50, 500, 66, 516));
    });

    test('filling after a reload selects exactly one button', () {
      final editor = PdfEditor(PdfDocument.open(buildClassicPdf()));
      editor.addRadioGroup(0, 'size', [
        (const PdfRect(50, 500, 66, 516), 'S'),
        (const PdfRect(80, 500, 96, 516), 'M'),
      ]);
      final filler = PdfEditor(reopen(editor));
      filler.setRadioValue(filler.acroForm!.fieldNamed('size')!, 'M');

      final out = reopen(filler);
      final field = PdfAcroForm.of(out)!.fieldNamed('size')!;
      expect(field.value, 'M');
      expect(field.isChecked, isTrue);
      expect(
        [for (final w in field.widgets) (out.cos.resolve(w['AS']) as CosName)],
        [const CosName('Off'), const CosName('M')],
      );
    });

    test('selected pre-selects a button', () {
      final editor = PdfEditor(PdfDocument.open(buildClassicPdf()));
      final field = editor.addRadioGroup(
        0,
        'yn',
        [
          (const PdfRect(50, 500, 66, 516), 'Yes'),
          (const PdfRect(80, 500, 96, 516), 'No'),
        ],
        selected: 'No',
      );
      expect(field.value, 'No');
      final out = reopen(editor);
      final reread = PdfAcroForm.of(out)!.fieldNamed('yn')!;
      expect(reread.value, 'No');
      expect(out.cos.resolve(reread.widgets[1]['AS']), const CosName('No'));
      expect(out.cos.resolve(reread.widgets[0]['AS']), const CosName('Off'));
    });

    test('addRadioButton extends a group, across pages too', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(2)));
      var group = editor.addRadioGroup(0, 'pick', [
        (const PdfRect(50, 500, 66, 516), 'A'),
      ]);
      group =
          editor.addRadioButton(group, 0, const PdfRect(80, 500, 96, 516), 'B');
      expect(group.onStates, ['A', 'B']);
      final saved = reopen(editor);

      // a later session adds a third button on another page
      final later = PdfEditor(saved);
      later.addRadioButton(later.acroForm!.fieldNamed('pick')!, 1,
          const PdfRect(50, 400, 66, 416), 'C');
      final out = reopen(later);
      final field = PdfAcroForm.of(out)!.fieldNamed('pick')!;
      expect(field.onStates, ['A', 'B', 'C']);
      expect(field.widgetPageIndex(2), 1);
      expect(stateDict(out, field.widgets[2], 'N').entries.keys,
          unorderedEquals(['C', 'Off']));

      final filler = PdfEditor(out);
      filler.setRadioValue(filler.acroForm!.fieldNamed('pick')!, 'C');
      expect(PdfAcroForm.of(reopen(filler))!.fieldNamed('pick')!.value, 'C');
    });

    test('bad on-states and non-groups are refused', () {
      final editor = PdfEditor(PdfDocument.open(buildClassicPdf()));
      expect(() => editor.addRadioGroup(0, 'r', const []), throwsArgumentError);
      expect(
        () => editor.addRadioGroup(0, 'r', [
          (const PdfRect(0, 0, 10, 10), 'A'),
          (const PdfRect(20, 0, 30, 10), 'A'),
        ]),
        throwsArgumentError,
      );
      expect(
        () => editor
            .addRadioGroup(0, 'r', [(const PdfRect(0, 0, 10, 10), 'Off')]),
        throwsArgumentError,
      );
      final group =
          editor.addRadioGroup(0, 'r', [(const PdfRect(0, 0, 10, 10), 'A')]);
      expect(
        () =>
            editor.addRadioButton(group, 0, const PdfRect(20, 0, 30, 10), 'A'),
        throwsArgumentError,
      );
      final text = editor.addTextField(0, 't', const PdfRect(0, 50, 50, 70));
      expect(
        () => editor.addRadioButton(text, 0, const PdfRect(0, 0, 1, 1), 'X'),
        throwsArgumentError,
      );
    });

    test('an existing file radio group takes another button', () {
      // buildAcroFormPdf's "color" group has kid widgets
      final editor = PdfEditor(PdfDocument.open(buildAcroFormPdf()));
      final group = editor.acroForm!.fields
          .firstWhere((f) => f.type == PdfFieldType.radioGroup);
      final before = group.onStates.length;
      editor.addRadioButton(
          group, 0, const PdfRect(300, 300, 316, 316), 'Extra');
      final out = reopen(editor);
      final reread = PdfAcroForm.of(out)!.fieldNamed(group.name)!;
      expect(reread.onStates, hasLength(before + 1));
      expect(reread.onStates.last, 'Extra');
    });
  });

  group('choice fields', () {
    const options = [
      ('us', 'United States'),
      ('au', 'Australia'),
      ('nz', 'nz')
    ];

    test('combo box: /Opt pairs, flags, fill after reload', () {
      final editor = PdfEditor(PdfDocument.open(buildClassicPdf()));
      editor.addComboBoxField(
          0, 'country', const PdfRect(50, 600, 250, 622), options,
          editable: true);

      final out = reopen(editor);
      final field = PdfAcroForm.of(out)!.fieldNamed('country')!;
      expect(field.type, PdfFieldType.comboBox);
      expect(field.options, options);
      expect(field.flags & PdfFormField.editFlag, isNot(0));
      final opt = out.cos.resolve(field.dict['Opt']) as CosArray;
      expect(out.cos.resolve(opt[0]), isA<CosArray>(),
          reason: 'export differs from display: a pair');
      expect(out.cos.resolve(opt[2]), isA<CosString>(),
          reason: 'export equals display: a plain string');
      expect(field.widgets.single['AP'], isNotNull,
          reason: 'an appearance is generated up front');

      final filler = PdfEditor(out);
      filler.setChoiceValue(filler.acroForm!.fieldNamed('country')!, 'au');
      final filled = PdfAcroForm.of(reopen(filler))!.fieldNamed('country')!;
      expect(filled.value, 'au');
      // editable: free text is accepted
      final free = PdfEditor(out);
      free.setChoiceValue(free.acroForm!.fieldNamed('country')!, 'Fiji');
      expect(
          PdfAcroForm.of(reopen(free))!.fieldNamed('country')!.value, 'Fiji');
    });

    test('list box: multiSelect flag, fill writes /I', () {
      final editor = PdfEditor(PdfDocument.open(buildClassicPdf()));
      editor.addListBoxField(
          0, 'langs', const PdfRect(50, 400, 250, 480), options,
          multiSelect: true);
      final out = reopen(editor);
      final field = PdfAcroForm.of(out)!.fieldNamed('langs')!;
      expect(field.type, PdfFieldType.listBox);
      expect(field.options, options);
      expect(field.flags & PdfFormField.multiSelectFlag, isNot(0));
      expect(field.flags & PdfFormField.comboFlag, 0);

      final filler = PdfEditor(out);
      filler.setChoiceValue(filler.acroForm!.fieldNamed('langs')!, 'nz');
      final filled = PdfAcroForm.of(reopen(filler))!.fieldNamed('langs')!;
      expect(filled.value, 'nz');
      expect(filled.dict['I'], isNotNull);
    });

    test('a non-editable combo refuses values outside its options', () {
      final editor = PdfEditor(PdfDocument.open(buildClassicPdf()));
      final field = editor.addComboBoxField(
          0, 'c', const PdfRect(50, 600, 250, 622), options);
      expect(field.flags & PdfFormField.editFlag, 0);
      expect(() => editor.setChoiceValue(field, 'Fiji'), throwsArgumentError);
    });

    test('setChoiceOptions rewrites options and drops a stale value', () {
      final editor = PdfEditor(PdfDocument.open(buildClassicPdf()));
      var field = editor.addListBoxField(
          0, 'l', const PdfRect(50, 400, 250, 480), options);
      editor.setChoiceValue(field, 'au');
      field = editor.setChoiceOptions(
          editor.acroForm!.fieldNamed('l')!, const [('au', 'Oz'), ('x', 'X')],
          multiSelect: true);
      var out = reopen(editor);
      var reread = PdfAcroForm.of(out)!.fieldNamed('l')!;
      expect(reread.options, const [('au', 'Oz'), ('x', 'X')]);
      expect(reread.value, 'au', reason: 'still offered, so kept');
      expect(reread.flags & PdfFormField.multiSelectFlag, isNot(0));

      final next = PdfEditor(out);
      next.setChoiceOptions(next.acroForm!.fieldNamed('l')!, const [('x', 'X')],
          multiSelect: false);
      out = reopen(next);
      reread = PdfAcroForm.of(out)!.fieldNamed('l')!;
      expect(reread.value, isNull, reason: 'no longer offered');
      expect(reread.flags & PdfFormField.multiSelectFlag, 0);
      expect(
          () => next.setChoiceOptions(
              next.addTextField(0, 't', const PdfRect(0, 0, 9, 9)), const []),
          throwsArgumentError);
    });
  });

  group('signature fields', () {
    final key = RsaPrivateKey.fromPem(testSignerKeyPem);
    final cert = pemBytes(testSignerCertPem);
    final signedAt = DateTime.utc(2026, 9, 23, 12);

    Uint8List authored() {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(2)));
      editor.addSignatureField(1, 'Approver', const PdfRect(72, 72, 272, 132));
      return editor.save();
    }

    test('an unsigned /FT /Sig widget with SigFlags 1', () {
      final doc = PdfDocument.open(authored());
      final form = PdfAcroForm.of(doc)!;
      final field = form.fieldNamed('Approver')!;
      expect(field.type, PdfFieldType.signature);
      expect(field.dict['V'], isNull);
      expect(field.widgetPageIndex(0), 1);
      expect(field.widgetRect(0), const PdfRect(72, 72, 272, 132));
      final flags = doc.cos.resolve(form.dict['SigFlags']) as CosInteger;
      expect(flags.value & 1, 1);
      expect(PdfSignature.of(doc), isEmpty, reason: 'nothing is signed yet');
    });

    test('saveSigned fills the authored field by name', () {
      final editor = PdfEditor(PdfDocument.open(authored()));
      final signed = editor.saveSigned(
        privateKey: key,
        certificates: [cert],
        fieldName: 'Approver',
        reason: 'Approved',
        signingTime: signedAt,
      );
      final doc = PdfDocument.open(signed);
      final form = PdfAcroForm.of(doc)!;
      expect(form.fields.where((f) => f.type == PdfFieldType.signature),
          hasLength(1),
          reason: 'signed into the existing field, no new one');
      final signature = PdfSignature.of(doc).single;
      expect(signature.field.name, 'Approver');
      final result = signature.validate();
      expect(result.intact, isTrue, reason: result.problems.join('; '));
      expect(result.signatureValid, isTrue);
      expect(signature.field.widgetPageIndex(0), 1);
      expect((doc.cos.resolve(form.dict['SigFlags']) as CosInteger).value, 3);
    });

    test('authoring and signing in the same session', () {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)));
      editor.addSignatureField(0, 'Here', const PdfRect(72, 72, 272, 132));
      final signed = editor.saveSigned(
        privateKey: key,
        certificates: [cert],
        fieldName: 'Here',
        signingTime: signedAt,
      );
      final signature = PdfSignature.of(PdfDocument.open(signed)).single;
      expect(signature.field.name, 'Here');
      expect(signature.validate().intact, isTrue);
    });

    test('self-signed and PAdES paths fill the authored field', () async {
      final identity = PdfSigningIdentity.generate(
        name: 'Ada Lovelace',
        notBefore: DateTime.utc(2026),
        validity: const Duration(days: 3650),
      );
      final selfSigned = PdfEditor(PdfDocument.open(authored())).saveSelfSigned(
        identity: identity,
        fieldName: 'Approver',
        signingTime: signedAt,
      );
      final a = PdfSignature.of(PdfDocument.open(selfSigned)).single;
      expect(a.field.name, 'Approver');
      expect(a.validate().intact, isTrue);

      final pades =
          await PdfEditor(PdfDocument.open(authored())).saveSelfSignedPades(
        identity: identity,
        level: PdfPadesLevel.bT,
        fieldName: 'Approver',
        timestampClient: (request) async =>
            buildTestTimeStampToken(request, genTime: signedAt),
        signingTime: signedAt,
      );
      final b = PdfSignature.of(PdfDocument.open(pades)).single;
      expect(b.field.name, 'Approver');
      expect(b.subFilter, 'ETSI.CAdES.detached');
      expect(b.validate().intact, isTrue);
    });
  });

  group('changeFieldType to the new kinds', () {
    test('text converts to each new type at the same place', () {
      for (final type in [
        PdfFieldType.radioGroup,
        PdfFieldType.comboBox,
        PdfFieldType.listBox,
        PdfFieldType.signature,
      ]) {
        final editor = PdfEditor(PdfDocument.open(buildAcroFormPdf()));
        final rebuilt =
            editor.changeFieldType(editor.acroForm!.fieldNamed('name')!, type);
        expect(rebuilt.type, type);
        final info = PdfAcroForm.of(reopen(editor))!
            .describeFields()
            .firstWhere((i) => i.name == 'name');
        expect(info.type, type);
        expect(info.rect, const PdfRect(72, 700, 300, 724));
      }
    });

    test('choice options survive combo <-> list; radio states become options',
        () {
      final editor = PdfEditor(PdfDocument.open(buildClassicPdf()));
      final combo = editor.addComboBoxField(
          0, 'c', const PdfRect(50, 600, 250, 622), const [('a', 'A')]);
      final list = editor.changeFieldType(combo, PdfFieldType.listBox);
      expect(list.options, const [('a', 'A')]);

      final radio = editor.addRadioGroup(0, 'r', [
        (const PdfRect(50, 500, 66, 516), 'Red'),
        (const PdfRect(80, 500, 96, 516), 'Blue'),
      ]);
      final asCombo = editor.changeFieldType(radio, PdfFieldType.comboBox);
      expect(asCombo.options, const [('Red', 'Red'), ('Blue', 'Blue')]);
      expect(asCombo.widgets, hasLength(1));
    });

    test('a check box becomes a one-button radio group keeping its state', () {
      final editor = PdfEditor(PdfDocument.open(buildClassicPdf()));
      final box =
          editor.addCheckBoxField(0, 'cb', const PdfRect(50, 500, 66, 516));
      final radio = editor.changeFieldType(box, PdfFieldType.radioGroup);
      expect(radio.onStates, ['Yes']);
      editor.setRadioValue(radio, 'Yes');
      expect(PdfAcroForm.of(reopen(editor))!.fieldNamed('cb')!.value, 'Yes');
    });

    test('a signed signature is not retyped; unknown is refused', () {
      final key = RsaPrivateKey.fromPem(testSignerKeyPem);
      final signed =
          PdfEditor(PdfDocument.open(buildMultiPagePdf(1))).saveSigned(
        privateKey: key,
        certificates: [pemBytes(testSignerCertPem)],
        appearance:
            const PdfSignatureAppearance(rect: PdfRect(72, 72, 272, 132)),
      );
      final editor = PdfEditor(PdfDocument.open(signed));
      final field = editor.acroForm!.fields.single;
      expect(() => editor.changeFieldType(field, PdfFieldType.text),
          throwsStateError);
      expect(() => editor.changeFieldType(field, PdfFieldType.unknown),
          throwsArgumentError);
    });
  });
}
