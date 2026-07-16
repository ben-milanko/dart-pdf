// Smoke-test the parser against real PDF files:
//   dart tool/inspect.dart <file.pdf> ...
import 'dart:io';

import 'package:pdf_document/pdf_document.dart';

void main(List<String> args) {
  var ok = 0;
  var failed = 0;
  for (final path in args) {
    try {
      final doc = PdfDocument.open(File(path).readAsBytesSync());
      final page = doc.page(0);
      final title = doc.info['Title'];
      final fields = PdfAcroForm.of(doc)?.fields.length ?? 0;
      stdout.writeln('OK   PDF ${doc.version}, ${doc.pageCount} page(s), '
          'page 1 ${page.mediaBox.width.round()}x'
          '${page.mediaBox.height.round()}'
          '${fields == 0 ? '' : ', $fields field(s)'}'
          '${title == null || title.isEmpty ? '' : ', "$title"'} - $path');
      for (final signature in PdfSignature.of(doc)) {
        final result = signature.validate();
        stdout.writeln('     signature "${signature.field.name}" '
            'by ${signature.signerName ?? '?'}: '
            '${result.intact ? 'intact' : 'INVALID'}'
            '${result.coversWholeDocument ? ', covers whole file' : ''}'
            '${result.problems.isEmpty ? '' : ' (${result.problems.join('; ')})'}');
      }
      ok++;
    } catch (e) {
      stdout.writeln('FAIL $path\n     $e');
      failed++;
    }
  }
  stdout.writeln('\n$ok ok, $failed failed');
  if (failed > 0) exitCode = 1;
}
