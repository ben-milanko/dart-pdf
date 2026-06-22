import 'dart:convert';
import 'dart:io';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

void main() {
  final fontBytes = File('test/fonts/DejaVuSans.ttf').readAsBytesSync();

  String appearanceContent(PdfDocument doc, PdfFormField field) {
    final ap = doc.cos.resolve(field.widgets[0]['AP']) as CosDictionary;
    final n = doc.cos.resolve(ap['N']) as CosStream;
    return latin1.decode(doc.cos.decodeStreamData(n));
  }

  group('setTextFieldStyle (base-14)', () {
    test('writes /DA, /Q, /Ff and regenerates the appearance', () {
      final editor = PdfEditor(PdfDocument.open(buildClassicPdf()));
      final field =
          editor.addTextField(0, 'notes', const PdfRect(50, 600, 350, 660));
      editor.setTextValue(field, 'hello there world');
      editor.setTextFieldStyle(field,
          font: PdfStandardFont.timesBold,
          fontSize: 18,
          color: 0xCC0000,
          align: PdfTextAlign.center,
          multiline: true);

      final out = PdfDocument.open(editor.save());
      final reread = PdfAcroForm.of(out)!.fieldNamed('notes')!;
      expect(reread.isMultiline, isTrue);
      expect(reread.quadding, 1);
      expect(reread.appearanceFontSize, 18);
      expect(reread.appearanceColor, 0xCC0000);
      final da = reread.defaultAppearance!;
      expect(da, contains('/TimesBold 18 Tf'));
      // the chosen base-14 face is registered in /DR
      final drFonts = out.cos
          .resolve(PdfAcroForm.of(out)!.defaultResources!['Font']) as CosDictionary;
      final tb = out.cos.resolve(drFonts['TimesBold']) as CosDictionary;
      expect((out.cos.resolve(tb['BaseFont']) as CosName).value, 'Times-Bold');
      // the appearance shows the value (simple-font byte string)
      expect(appearanceContent(out, reread), contains('hello'));
    });

    test('autoSize sets /DA size 0', () {
      final editor = PdfEditor(PdfDocument.open(buildClassicPdf()));
      final field =
          editor.addTextField(0, 'amt', const PdfRect(50, 600, 200, 624));
      editor.setTextFieldStyle(field, autoSize: true);
      final out = PdfDocument.open(editor.save());
      final reread = PdfAcroForm.of(out)!.fieldNamed('amt')!;
      expect(reread.appearanceFontSize, 0);
    });
  });

  group('setTextFieldStyle (embedded)', () {
    test('embeds a Type0 face in /DR and shows it as glyph ids', () {
      final editor = PdfEditor(PdfDocument.open(buildClassicPdf()));
      final field =
          editor.addTextField(0, 'name', const PdfRect(50, 600, 350, 624));
      editor.setTextFieldStyle(field,
          font: PdfEmbeddedFont.parse(fontBytes), fontSize: 12);
      editor.setTextValue(field, 'Wörld');

      final out = PdfDocument.open(editor.save());
      final form = PdfAcroForm.of(out)!;
      final reread = form.fieldNamed('name')!;
      // /DR gained a Type0 font under the /DA name
      final name = RegExp(r'/(\S+)\s+[\d.]+\s+Tf')
          .firstMatch(reread.defaultAppearance!)!
          .group(1)!;
      final drFonts =
          out.cos.resolve(form.defaultResources!['Font']) as CosDictionary;
      final type0 = out.cos.resolve(drFonts[name]) as CosDictionary;
      expect((out.cos.resolve(type0['Subtype']) as CosName).value, 'Type0');
      // the appearance shows a Type0 hex string, not a literal ( ) string
      final content = appearanceContent(out, reread);
      expect(content, contains('> Tj'));
      expect(content, isNot(contains('(W')));
      // the appearance carries its own embedded font resource
      final ap = out.cos.resolve(reread.widgets[0]['AP']) as CosDictionary;
      final apForm = out.cos.resolve(ap['N']) as CosStream;
      final res = out.cos.resolve(apForm.dictionary['Resources']) as CosDictionary;
      final apFonts = out.cos.resolve(res['Font']) as CosDictionary;
      expect(apFonts.containsKey(name), isTrue);
    });

    test('a later fill regenerates correctly from the /DR program', () {
      final editor = PdfEditor(PdfDocument.open(buildClassicPdf()));
      final field =
          editor.addTextField(0, 'name', const PdfRect(50, 600, 350, 624));
      editor.setTextFieldStyle(field,
          font: PdfEmbeddedFont.parse(fontBytes), fontSize: 14);
      // reopen so the only font source is the /DR (no live PdfEmbeddedFont)
      final mid = PdfDocument.open(editor.save());
      final editor2 = PdfEditor(mid);
      final field2 = PdfAcroForm.of(mid)!.fieldNamed('name')!;
      editor2.setTextValue(field2, 'Filled later');

      final out = PdfDocument.open(editor2.save());
      final reread = PdfAcroForm.of(out)!.fieldNamed('name')!;
      expect(reread.value, 'Filled later');
      final content = appearanceContent(out, reread);
      expect(content, contains('> Tj'));
    });
  });
}
