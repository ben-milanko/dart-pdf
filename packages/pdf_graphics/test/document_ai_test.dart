// The Document-AI read seam (PdfDocumentContext): a thin adapter that
// gathers a document's text, form fields, and annotations into a clean
// shape for a host-supplied model. (The write seam, PdfDocumentActionSink,
// is an abstract host-provided interface — nothing to test here.)
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

void main() {
  test('gathers text, fields, and annotations', () {
    final doc = PdfDocument.open(buildAcroFormPdf());
    final context = PdfDocumentContext.of(doc);

    expect(context.pages, isNotEmpty);
    expect(context.pages.first.width, greaterThan(0));
    expect(context.fields, isNotEmpty);
    expect(context.fields.map((f) => f.name), isNotEmpty);

    final prompt = context.toPromptText();
    expect(prompt, contains('Form fields:'));
    expect(prompt, contains(context.fields.first.name));

    // Serializable for a model/transport.
    expect(context.toJson()['fields'], isA<List<Object?>>());
  });

  test('surfaces text injected by an OCR layer', () {
    final doc = PdfDocument.open(buildClassicPdf());
    PdfEditor(doc).injectTextLayer(0, const [
      PdfOcrSpan(text: 'Invoice', bounds: PdfRect(72, 700, 200, 720)),
    ]);
    // injectTextLayer mutates the in-memory COS, so the same document now
    // carries the layer.
    final context = PdfDocumentContext.of(doc);
    expect(context.pages.single.text, contains('Invoice'));
  });

  test('includeText:false skips extraction', () {
    final doc = PdfDocument.open(buildClassicPdf());
    final context = PdfDocumentContext.of(doc, includeText: false);
    expect(context.pages.single.text, isEmpty);
  });
}
