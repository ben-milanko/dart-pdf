import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

CosDictionary _fonts(PdfDocument doc) =>
    doc.cos.resolve(PdfAcroForm.of(doc)!.defaultResources!['Font'])
        as CosDictionary;

CosDictionary _descriptor(PdfDocument doc, CosDictionary font) {
  final descendants = doc.cos.resolve(font['DescendantFonts']) as CosArray;
  final cid = doc.cos.resolve(descendants.items.first) as CosDictionary;
  return doc.cos.resolve(cid['FontDescriptor']) as CosDictionary;
}

int _programCount(PdfDocument doc) => doc.cos.objectNumbers.where((number) {
      final obj = doc.cos.resolve(CosReference(number, 0));
      return obj is CosDictionary &&
          (obj.containsKey('FontFile2') || obj.containsKey('FontFile3'));
    }).length;

void _checkAppearance(PdfDocument doc, PdfFormField field, String text,
    PdfEmbeddedFont font, CosObject program) {
  for (final widget in field.widgets) {
    final ap = doc.cos.resolve(widget['AP']) as CosDictionary;
    final stream = doc.cos.resolve(ap['N']) as CosStream;
    final resources =
        doc.cos.resolve(stream.dictionary['Resources']) as CosDictionary;
    final fonts = doc.cos.resolve(resources['Font']) as CosDictionary;
    final type0 = doc.cos.resolve(fonts.entries.values.single) as CosDictionary;
    final descriptor = _descriptor(doc, type0);
    expect(descriptor['FontFile2'] ?? descriptor['FontFile3'], program);
    final unicode = doc.cos.resolve(type0['ToUnicode']) as CosStream;
    final mapping = latin1.decode(doc.cos.decodeStreamData(unicode));
    final descendants = doc.cos.resolve(type0['DescendantFonts']) as CosArray;
    final cid = doc.cos.resolve(descendants.items.first) as CosDictionary;
    final widths = doc.cos.resolve(cid['W']) as CosArray;
    final gids = <int>{
      for (var i = 0; i < widths.items.length; i += 2)
        (widths.items[i] as CosInteger).value,
    };
    final content = latin1.decode(doc.cos.decodeStreamData(stream));
    for (final rune in text.runes) {
      final gid = font.glyphForRune(rune);
      final hex = gid.toRadixString(16).padLeft(4, '0');
      expect(content.toLowerCase(), contains(hex));
      expect(mapping.toLowerCase(),
          contains('<$hex> <${rune.toRadixString(16).padLeft(4, '0')}>'));
      expect(gids, contains(gid));
    }
  }
}

void main() {
  for (final path in [
    'test/fonts/DejaVuSans.ttf',
    '../dart_pdf_editor_assets/assets/fonts/TeXGyreHeros-Regular.otf',
  ]) {
    test('shares font program across text/choice fills and reopen: $path', () {
      final bytes = File(path).readAsBytesSync();
      final font = PdfEmbeddedFont.parse(bytes);
      var editor = PdfEditor(PdfDocument.open(buildClassicPdf()));
      for (var i = 0; i < 30; i++) {
        final field =
            editor.addTextField(0, 'text$i', const PdfRect(20, 20, 300, 50));
        editor.setTextFieldStyle(field,
            font: PdfEmbeddedFont.parse(bytes), fontSize: 10);
        editor.setTextValue(field, i.isEven ? 'W€' : 'éĄ');
      }
      final combo = editor.addComboBoxField(
          0, 'combo', const PdfRect(20, 60, 300, 90), [('x', '€Ą')]);
      editor.setChoiceFieldStyle(combo, font: font);
      editor.setChoiceValue(combo, 'x');
      final list = editor.addListBoxField(
          0, 'list', const PdfRect(20, 100, 300, 150), [('y', 'Wé')]);
      editor.setChoiceFieldStyle(list, font: font);
      editor.setChoiceValue(list, 'y');
      final initial = editor.save();
      var doc = PdfDocument.open(initial);
      expect(_programCount(doc), 1);
      expect(_fonts(doc).entries.keys.where((name) => name.startsWith('FF')),
          hasLength(1));
      final type0 = doc.cos.resolve(_fonts(doc)['FF0']) as CosDictionary;
      final descriptor = _descriptor(doc, type0);
      final program = descriptor['FontFile2'] ?? descriptor['FontFile3']!;
      for (var i = 0; i < 30; i++) {
        _checkAppearance(doc, PdfAcroForm.of(doc)!.fieldNamed('text$i')!,
            i.isEven ? 'W€' : 'éĄ', font, program);
      }
      _checkAppearance(
          doc, PdfAcroForm.of(doc)!.fieldNamed('combo')!, '€Ą', font, program);
      _checkAppearance(
          doc, PdfAcroForm.of(doc)!.fieldNamed('list')!, 'Wé', font, program);
      editor = PdfEditor(doc);
      final field = editor.acroForm!.fieldNamed('text0')!;
      editor.setTextFieldStyle(field, font: PdfEmbeddedFont.parse(bytes));
      editor.setTextValue(field, 'Žł');
      editor.resizeFormWidget('text0', 0, const PdfRect(20, 20, 400, 60));
      final later = editor.save();
      expect(later.length - initial.length, lessThan(15000));
      doc = PdfDocument.open(later);
      expect(_programCount(doc), 1);
      _checkAppearance(
          doc, PdfAcroForm.of(doc)!.fieldNamed('text0')!, 'Žł', font, program);
      // A different widget's mappings must survive the later edit unchanged.
      _checkAppearance(
          doc, PdfAcroForm.of(doc)!.fieldNamed('text1')!, 'éĄ', font, program);
      print('30 text fields + combo/list: ${initial.length} bytes; '
          'refill/style/resize growth: ${later.length - initial.length} bytes');
    });
  }

  test('same PostScript name with different bytes is not conflated', () {
    final bytes = File('test/fonts/DejaVuSans.ttf').readAsBytesSync();
    final other = Uint8List.fromList([...bytes, 0]);
    final a = PdfEmbeddedFont.parse(bytes);
    final b = PdfEmbeddedFont.parse(other);
    expect(a.postScriptName, b.postScriptName);
    final editor = PdfEditor(PdfDocument.open(buildClassicPdf()));
    for (final (i, font) in [a, b].indexed) {
      final field =
          editor.addTextField(0, 'f$i', const PdfRect(20, 20, 300, 50));
      editor.setTextFieldStyle(field, font: font);
      editor.setTextValue(field, 'hello');
    }
    final doc = PdfDocument.open(editor.save());
    expect(_programCount(doc), 2);
    expect(_fonts(doc).entries.keys.where((name) => name.startsWith('FF')),
        hasLength(2));
  });
}
