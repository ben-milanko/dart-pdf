// Count check-marks (PdfEditor.addCheckMark): a tick drawn inside a /Stamp
// with /Name /Check, so the editing UI can tally them Bluebeam-style and
// each mark stays a real annotation (select/move/resize/delete).
import 'dart:convert';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

void main() {
  PdfDocument roundTrip(void Function(PdfEditor) edit) {
    final editor = PdfEditor(PdfDocument.open(buildClassicPdf()));
    edit(editor);
    return PdfDocument.open(editor.save());
  }

  test('addCheckMark places a /Stamp /Name /Check with a tick appearance', () {
    final doc =
        roundTrip((e) => e.addCheckMark(0, const PdfRect(100, 500, 120, 520)));
    final mark = doc.page(0).annotations.single;
    expect(mark.subtype, 'Stamp');
    expect(mark.iconName, 'Check');
    expect(mark.isCheckMark, isTrue);
    // no caption — it's a symbol, not a text stamp
    expect(mark.contents, anyOf(isNull, isEmpty));

    final form = mark.normalAppearance!;
    final content = latin1.decode(doc.cos.decodeStreamData(form));
    // a stroked three-point tick (move + two line segments + stroke)
    expect(content, contains(' m\n'));
    expect('l\n'.allMatches(content).length, 2);
    expect(content, contains('S'));
  });

  test('check-marks carry an /NM identity and the chosen colour', () {
    final doc = roundTrip((e) => e.addCheckMark(
        0, const PdfRect(0, 0, 20, 20),
        color: 0xC03030, author: 'Ben'));
    final mark = doc.page(0).annotations.single;
    expect(mark.name, isNotNull); // /NM stamped like every created annotation
    expect(mark.author, 'Ben');
    expect(mark.color, 0xC03030);
  });

  test('an opaque check-mark adds no ExtGState; a translucent one does', () {
    final opaque =
        roundTrip((e) => e.addCheckMark(0, const PdfRect(0, 0, 20, 20)));
    final opaqueForm = opaque.page(0).annotations.single.normalAppearance!;
    expect(opaqueForm.dictionary['Resources'], isNull);

    final faint = roundTrip((e) =>
        e.addCheckMark(0, const PdfRect(0, 0, 20, 20), opacity: 0.5));
    final faintForm = faint.page(0).annotations.single.normalAppearance!;
    final content = latin1.decode(faint.cos.decodeStreamData(faintForm));
    expect(content, contains('/GS0 gs'));
  });

  test('a non-check stamp is not a check-mark', () {
    final doc = roundTrip(
        (e) => e.addStamp(0, const PdfRect(0, 0, 80, 30), 'APPROVED'));
    expect(doc.page(0).annotations.single.isCheckMark, isFalse);
  });
}
