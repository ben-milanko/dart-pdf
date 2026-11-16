// Annotates the hero sample agreement with the real PdfEditor: fills the
// form, adds two highlights, a comment, and an ink signature. See README.md.
//
// Usage (from packages/pdf_document):
//   fvm dart run ../../doc/marketing/hero/annotate_hero.dart \
//     agreement.pdf geo.json out.pdf sig.json
import 'dart:convert';
import 'dart:io';
import 'package:pdf_document/pdf_document.dart';

void main(List<String> args) {
  final geo =
      jsonDecode(File(args[1]).readAsStringSync()) as Map<String, dynamic>;
  PdfRect r(String k) {
    final v = (geo[k] as List).cast<num>();
    return PdfRect(
        v[0].toDouble(), v[1].toDouble(), v[2].toDouble(), v[3].toDouble());
  }

  final doc = PdfDocument.open(File(args[0]).readAsBytesSync());
  final ed = PdfEditor(doc);
  final form = PdfAcroForm.of(doc)!;
  for (final f in form.fields) {
    switch (f.name) {
      case 'client':
        ed.setTextValue(f, 'Maya Chen');
      case 'start':
        ed.setTextValue(f, 'Dec 1, 2026');
      case 'fee':
        ed.setTextValue(f, r'$4,800');
      case 'agree':
        ed.setCheckBoxValue(f, true);
    }
  }
  ed.addHighlight(0, [r('hl')], color: 0xFFD54A, author: 'Maya');
  final ul = r('ul');
  ed.addHighlight(0, [ul], color: 0x8FD3FF, author: 'Maya');
  final n = (geo['hl_note'] as List).cast<num>();
  ed.addNote(0, n[0].toDouble(), n[1].toDouble(), 'Can we do 30 days?',
      author: 'Maya');
  final s = r('client_sig');
  final sig = (jsonDecode(File(args[3]).readAsStringSync()) as List)
      .map((st) => (st as List)
          .map((q) => ((q as List)[0] as num, q[1] as num))
          .toList())
      .toList();
  List<List<(double, double)>> place(double x, double y, double k) => [
        for (final st in sig) [for (final (a, b) in st) (x + a * k, y + b * k)]
      ];
  ed.addInk(0, place(s.left + 14, s.bottom + 10, 0.95),
      color: 0x1A4FB4, strokeWidth: 1.4, author: 'Maya');
  File(args[2]).writeAsBytesSync(ed.save());
}
