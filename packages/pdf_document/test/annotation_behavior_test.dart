import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

PdfDocument _edited(void Function(PdfEditor) edit) {
  final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)));
  edit(editor);
  return PdfDocument.open(editor.save());
}

void main() {
  test('capability matrix is shared and cached per parsed annotation', () {
    final doc = _edited((editor) {
      editor
        ..addSquare(0, const PdfRect(10, 10, 80, 60),
            strokeColor: 0x112233, strokeWidth: 3, fillColor: 0x445566)
        ..addLine(0, (100, 20), (180, 50), strokeWidth: 2)
        ..addInk(0, [
          [(200, 20), (240, 50)],
        ])
        ..addNote(0, 280, 60, 'note');
    });
    final [square, line, ink, note] = doc.page(0).annotations;

    expect(identical(square.behavior, square.behavior), isTrue);
    expect(identical(square.behavior.style, square.behavior.style), isTrue);
    expect(square.behavior.selectable, isTrue);
    expect(square.behavior.resizable, isTrue);
    expect(square.behavior.rotatable, isTrue);
    expect(square.behavior.canRestyle, isTrue);
    expect(square.behavior.supportsFill, isTrue);
    expect(square.behavior.supportsStrokeWidth, isTrue);
    expect(square.behavior.supportsLineStyle, isTrue);
    expect(square.behavior.supportsOpacity, isTrue);
    expect(square.behavior.resizeBehavior,
        PdfAnnotationResizeBehavior.regenerateShape);
    expect(square.behavior.style.color, 0x112233);
    expect(square.behavior.style.fillColor, 0x445566);
    expect(square.behavior.style.strokeWidth, 3);

    expect(line.behavior.lineFamily, isTrue);
    expect(line.behavior.supportsLineEndings, isTrue);
    expect(line.behavior.supportsStrokeWidth, isTrue);
    expect(line.behavior.supportsOpacity, isTrue);
    expect(line.behavior.resizeBehavior,
        PdfAnnotationResizeBehavior.regenerateLine);

    expect(ink.behavior.resizable, isTrue);
    expect(ink.behavior.supportsLineStyle, isFalse);
    expect(ink.behavior.canRestyle, isTrue);

    expect(note.behavior.textEditable, isTrue);
    expect(note.behavior.resizable, isFalse);
    expect(note.behavior.supportsOpacity, isFalse);
  });

  test('free-text style comes from /DA and drives resize strategy', () {
    final doc = _edited((editor) => editor.addFreeText(
          0,
          const PdfRect(20, 100, 220, 160),
          'Styled',
          font: PdfStandardFont.times,
          fontSize: 14,
          color: 0x102030,
          fillColor: 0x405060,
          borderColor: 0x708090,
          borderWidth: 2,
        ));
    final annotation = doc.page(0).annotations.single;
    final behavior = annotation.behavior;

    expect(behavior.textEditable, isTrue);
    expect(behavior.canRestyle, isTrue);
    expect(behavior.supportsFill, isTrue);
    expect(behavior.supportsOpacity, isTrue);
    expect(behavior.resizeBehavior, PdfAnnotationResizeBehavior.reflowText);
    expect(behavior.standardTextFont, PdfStandardFont.times);
    expect(behavior.style.color, 0x102030);
    expect(behavior.style.fillColor, 0x405060);
    expect(behavior.style.borderColor, 0x708090);
    expect(behavior.style.freeText?.fontSize, 14);
  });

  test('interactive and structural subtypes are not generally selectable', () {
    final doc = PdfDocument.open(buildMultiPagePdf(1));
    PdfAnnotation annotation(String subtype) => PdfAnnotation.fromDict(
          doc,
          CosDictionary({
            'Subtype': CosName(subtype),
            'Rect': CosArray(const [
              CosInteger(0),
              CosInteger(0),
              CosInteger(10),
              CosInteger(10),
            ]),
          }),
        );

    expect(annotation('Popup').behavior.selectable, isFalse);
    expect(annotation('Link').behavior.selectable, isFalse);
    expect(annotation('Widget').behavior.selectable, isFalse);
    expect(annotation('ForeignSubtype').behavior.selectable, isTrue);
    expect(annotation('ForeignSubtype').behavior.canRestyle, isFalse);
    expect(annotation('ForeignSubtype').behavior.resizeBehavior,
        PdfAnnotationResizeBehavior.none);
  });

  test('malformed and foreign appearance data falls back without rebuilding',
      () {
    final doc = _edited((editor) {
      editor
        ..addFreeText(0, const PdfRect(20, 100, 220, 160), 'Text')
        ..addHighlight(0, const [PdfRect(20, 200, 120, 214)]);
    });
    final freeText = doc.page(0).annotations[0];
    freeText.dict['DA'] = CosString.fromText('/Embedded 12 Tf 0 g');
    final foreignText = PdfAnnotation.fromDict(doc, freeText.dict);
    expect(foreignText.behavior.canRestyle, isFalse);
    expect(foreignText.behavior.standardTextFont, isNull);
    expect(foreignText.behavior.resizeBehavior,
        PdfAnnotationResizeBehavior.stretch);

    final highlight = doc.page(0).annotations[1];
    highlight.dict['QuadPoints'] = CosArray(const [
      CosInteger(20),
      CosInteger(200),
      CosInteger(120),
      CosInteger(204),
      CosInteger(116),
      CosInteger(214),
      CosInteger(24),
      CosInteger(210),
    ]);
    final rotatedMarkup = PdfAnnotation.fromDict(doc, highlight.dict);
    expect(rotatedMarkup.behavior.markupQuads, isNull);
    expect(rotatedMarkup.behavior.canRestyle, isFalse);
  });

  test('legacy restyle gate delegates to the shared descriptor', () {
    final doc = _edited((editor) => editor.addCircle(
          0,
          const PdfRect(20, 20, 80, 80),
          strokeColor: 0x123456,
        ));
    final annotation = doc.page(0).annotations.single;
    expect(pdfCanRestyleAnnotation(annotation), annotation.behavior.canRestyle);
  });
}
