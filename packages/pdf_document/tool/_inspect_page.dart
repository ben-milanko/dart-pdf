import 'dart:io';
import 'package:pdf_document/pdf_document.dart';

void main(List<String> args) {
  final doc = PdfDocument.open(File(args[0]).readAsBytesSync());
  final p = doc.page(0);
  final b = p.cropBox;
  print('rotation=${p.rotation} crop L=${b.left} B=${b.bottom} '
      'R=${b.right} T=${b.top} w=${b.width} h=${b.height}');
}
