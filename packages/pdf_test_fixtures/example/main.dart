import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main() {
  final bytes = buildClassicPdf();
  final document = CosDocument.open(bytes);

  print('Fixture bytes: ${bytes.length}');
  print('Fixture PDF version: ${document.version}');
}
