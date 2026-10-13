import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

Uint8List compositeText(String text) {
  final builder = CosDocumentBuilder();
  final font = PdfUnicodeFont(PdfStandardFont.helvetica);
  final hex = font.encodeHex(text);
  final resource = font.buildResource(builder.add).entries.values.first;
  final content =
      Uint8List.fromList(latin1.encode('BT /F0 24 Tf 72 700 Td <$hex> Tj ET'));
  final page = CosDictionary({
    'Type': const CosName('Page'),
    'MediaBox': CosArray(
        const [CosInteger(0), CosInteger(0), CosInteger(612), CosInteger(792)]),
    'Contents': builder.add(CosStream(
        CosDictionary({'Length': CosInteger(content.length)}), content)),
    'Resources': CosDictionary({
      'Font': CosDictionary({'F0': builder.add(resource)})
    }),
  });
  final pageRef = builder.add(page);
  final pages = builder.add(CosDictionary({
    'Type': const CosName('Pages'),
    'Kids': CosArray([pageRef]),
    'Count': const CosInteger(1)
  }));
  page['Parent'] = pages;
  return builder.build(
      root: builder.add(
          CosDictionary({'Type': const CosName('Catalog'), 'Pages': pages})));
}

void main() {
  test('restyling a rotated callout leaves leader points in place', () {
    final seed = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)))
      ..addCallout(0, const PdfRect(300, 600, 460, 660), 'Detail', (120, 500));
    var doc = PdfDocument.open(seed.save());
    final rotation = PdfEditor(doc)
      ..rotateAnnotation(0, doc.page(0).annotations.single, 37);
    doc = PdfDocument.open(rotation.save());
    final before = doc.page(0).annotations.single;
    final points = before.calloutLine!;
    final angle = before.appearanceRotation;
    final editor = PdfEditor(doc);
    expect(editor.restyleCalloutLeader(0, before, width: 7), isTrue);
    final after = PdfDocument.open(editor.save()).page(0).annotations.single;
    expect(after.appearanceRotation, closeTo(angle, 1e-5));
    for (var i = 0; i < points.length; i++) {
      expect(after.calloutLine![i].$1, closeTo(points[i].$1, 0.01));
      expect(after.calloutLine![i].$2, closeTo(points[i].$2, 0.01));
    }
    expect(after.calloutLeaderStyle!.width, 7);
    final next = PdfEditor(after.document);
    expect(next.restyleCalloutLeader(0, after, width: 9), isTrue);
    final again = PdfDocument.open(next.save()).page(0).annotations.single;
    for (var i = 0; i < points.length; i++) {
      expect(again.calloutLine![i].$1, closeTo(points[i].$1, 0.01));
      expect(again.calloutLine![i].$2, closeTo(points[i].$2, 0.01));
    }
  });

  test('composite text formatting preserves surrounding text and placement',
      () {
    final doc = PdfDocument.open(compositeText('Hello world again'));
    final snapshot = PdfPageElements.of(doc, 0);
    final original =
        snapshot.elements.singleWhere((e) => e.kind == PdfElementKind.text);
    final editor = PdfEditor(doc);
    expect(
        editor.replaceElementText(snapshot, original, 'world', 'world',
            style: const PdfTextStyle(bold: true, italic: true)),
        1);
    final out = PdfDocument.open(editor.save());
    final elements = PdfPageElements.of(out, 0)
        .elements
        .where((e) => e.kind == PdfElementKind.text)
        .toList();
    expect(elements.map((e) => e.text).join(), 'Hello world again');
    final fonts =
        out.cos.resolve(out.page(0).resources['Font']) as CosDictionary;
    final styled = elements.singleWhere((e) => e.text == 'world');
    final face = out.cos.resolve(fonts[styled.resourceName!]) as CosDictionary;
    expect((out.cos.resolve(face['BaseFont']) as CosName).value,
        'Helvetica-BoldOblique');
    expect(elements.last.bounds!.right, closeTo(original.bounds!.right, 0.01));
    // A miss must allocate no font or create a revision.
    final miss = PdfEditor(out);
    expect(
        miss.replaceStyledText(
            0, 'missing', 'missing', const PdfTextStyle(bold: true)),
        0);
    expect(miss.hasChanges, isFalse);
  });

  test(
      'callout leaders keep their own width, color, dash and arrow with no outline',
      () {
    final seed = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)))
      ..addCallout(
          0, const PdfRect(300, 600, 460, 660), 'Look here', (120, 500),
          strokeColor: 0xFF0000,
          strokeWidth: 6,
          leaderDash: const [12, 6],
          outlineColor: (null,),
          outlineWidth: 0,
          ending: PdfLineEnding.closedArrow);
    var doc = PdfDocument.open(seed.save());
    var a = doc.page(0).annotations.single;
    expect(a.freeTextStyle!.borderColor, isNull);
    expect(a.freeTextStyle!.borderWidth, 0);
    expect(a.calloutLeaderStyle!.width, 6);
    expect(a.calloutLeaderStyle!.color, 0xFF0000);
    expect(a.calloutLeaderStyle!.dash, [12, 6]);
    final editor = PdfEditor(doc);
    editor.restyleCalloutLeader(0, a,
        width: 8, color: 0x0000FF, ending: PdfLineEnding.openArrow);
    editor.reshapeCallout(0, PdfAnnotation.fromDict(doc, a.dict),
        target: (100, 450));
    doc = PdfDocument.open(editor.save());
    a = doc.page(0).annotations.single;
    expect(a.freeTextStyle!.borderColor, isNull);
    expect(a.freeTextStyle!.borderWidth, 0);
    expect(a.calloutLeaderStyle!.width, 8);
    expect(a.calloutLeaderStyle!.color, 0x0000FF);
    expect(a.calloutLeaderStyle!.dash, [12, 6]);
    final appearance =
        latin1.decode(doc.cos.decodeStreamData(a.normalAppearance!));
    expect(appearance, contains('8 w'));
    expect(appearance, contains('[12 6] 0 d'));
    expect(appearance, contains('0 0 1 RG'));
    expect(appearance, isNot(contains(' re\nS')));
  });
}
