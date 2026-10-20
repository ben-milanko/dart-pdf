import 'dart:convert';
import 'dart:math' as math;
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

void main() {
  test('resizing a table rewraps cells without stretching the font', () {
    const text = 'What do ARTC do when there is a train order working';
    final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)));
    editor.addTable(
        0,
        const PdfRect(20, 30, 100, 230),
        PdfTableData([
          [text]
        ], columnWidths: [
          80
        ], rowHeights: [
          200
        ], fontSize: 12));
    var document = PdfDocument.open(editor.save());
    String content(PdfDocument doc) => latin1.decode(doc.cos
        .decodeStreamData(doc.page(0).annotations.single.normalAppearance!));
    final narrow = content(document);
    final resize = PdfEditor(document);
    resize.resizeAnnotation(0, document.page(0).annotations.single,
        const PdfRect(20, 30, 380, 230));
    document = PdfDocument.open(resize.save());
    final wide = content(document);
    expect(wide, isNot(narrow), reason: 'rebuild, rather than stretch, the AP');
    expect(wide, contains('/Helv 12 Tf'));
    expect(RegExp(r'\bTj\b').allMatches(wide).length,
        lessThan(RegExp(r'\bTj\b').allMatches(narrow).length));
    expect(
        document.page(0).annotations.single.table!.width, closeTo(360, 1e-6));
    expect(document.page(0).annotations.single.table!.fontSize, 12);
    final shrink = PdfEditor(document);
    shrink.resizeAnnotation(0, document.page(0).annotations.single,
        const PdfRect(20, 30, 100, 230));
    final reopened = PdfDocument.open(shrink.save());
    expect(content(reopened), narrow);
    expect(reopened.page(0).annotations.single.table!.cells, [
      [text]
    ]);
  });

  for (final pageRotation in [0, 90, 180, 270]) {
    test('table reflow preserves rotation on page $pageRotation', () {
      final sideways = pageRotation == 90 || pageRotation == 270;
      final editor = PdfEditor(
          PdfDocument.open(buildMultiPagePdf(1, rotation: pageRotation)));
      editor.addTable(
          0,
          PdfRect(
              20, 30, 20 + (sideways ? 200 : 80), 30 + (sideways ? 80 : 200)),
          PdfTableData([
            ['Clarifications for train order working']
          ], columnWidths: [
            80
          ], rowHeights: [
            200
          ], fontSize: 12));
      var document = PdfDocument.open(editor.save());
      final rotate = PdfEditor(document);
      rotate.rotateAnnotation(0, document.page(0).annotations.single, 37);
      document = PdfDocument.open(rotate.save());
      final resize = PdfEditor(document);
      final target = PdfRect(
          40, 50, 40 + (sideways ? 200 : 360), 50 + (sideways ? 360 : 200));
      resize.resizeAnnotationLocal(
          0, document.page(0).annotations.single, target);
      final result = PdfDocument.open(resize.save());
      final annotation = result.page(0).annotations.single;
      final form = annotation.normalAppearance!;
      final matrix = form.dictionary['Matrix'] as CosArray;
      final a = (matrix[0] as CosReal).value, b = (matrix[1] as CosReal).value;
      final c = (matrix[2] as CosReal).value, d = (matrix[3] as CosReal).value;
      expect(math.sqrt(a * a + b * b), closeTo(1, 1e-6));
      expect(math.sqrt(c * c + d * d), closeTo(1, 1e-6));
      expect(math.atan2(b, a), closeTo(37 * math.pi / 180, 1e-6));
      expect(annotation.table!.width, closeTo(360, 1e-6));
      expect(annotation.table!.height, closeTo(200, 1e-6));
      expect(latin1.decode(result.cos.decodeStreamData(form)),
          contains('/Helv 12 Tf'));
    });
  }

  test('Excel range round-trips tabs, quotes, multiline cells and empty edges',
      () {
    final table = PdfTableData([
      ['Name', 'Notes', ''],
      ['Ben', 'First\nSecond', 'A\tB'],
      ['"Quoted"', '=A1+1', ''],
    ]);
    final decoded = PdfTableData.fromTsv('${table.toTsv()}\r\n');
    expect(decoded.cells, table.cells);
    expect(decoded.cells[2][1], '=A1+1');
    expect(PdfTableData.fromTsv('a\tb\t\r\nc\t').cells, [
      ['a', 'b', ''],
      ['c', '', '']
    ]);
    expect(table.toTsv(firstRow: 1, lastRow: 1, firstColumn: 0, lastColumn: 1),
        'Ben\t"First\nSecond"');
  });
  test('table input budgets and malformed quoting fail without truncating data',
      () {
    expect(() => PdfTableData.fromTsv('"unclosed\tx'), throwsFormatException);
    expect(() => PdfTableData.fromTsv(List.filled(101, 'a').join('\t')),
        throwsFormatException);
    expect(() => PdfTableData(List.generate(501, (_) => ['a'])),
        throwsFormatException);
    expect(() => PdfTableData([]), throwsFormatException);
    expect(
        () => PdfTableData([
              ['a'],
              ['a', 'b']
            ]),
        throwsFormatException);
    expect(
        () => PdfTableData([
              ['a']
            ], columnWidths: [
              double.nan
            ]),
        throwsFormatException);
    expect(PdfTableData.decode('{}'), isNull);
  });
  for (final rotation in [0, 90, 180, 270]) {
    test(
        'vector table remains editable after save/reopen at rotation $rotation',
        () {
      final table = PdfTableData([
        ['Name', 'Amount'],
        ['Ben', '123.45']
      ], columnWidths: [
        160,
        80
      ], rowHeights: [
        30,
        40
      ], fontSize: 12);
      final editor =
          PdfEditor(PdfDocument.open(buildMultiPagePdf(1, rotation: rotation)));
      editor.addTable(0, const PdfRect(20, 30, 320, 200), table);
      final document = PdfDocument.open(editor.save());
      final annotation = document.page(0).annotations.single;
      expect(annotation.table!.toJson(), table.toJson());
      expect(annotation.normalAppearance, isNotNull);
      expect(annotation.behavior.canRestyle, isFalse,
          reason:
              'generic stamp restyling must not turn a table into a rubber stamp');
      final appearance = latin1
          .decode(document.cos.decodeStreamData(annotation.normalAppearance!));
      expect(appearance, contains('(Ben)'));
      expect(appearance, contains('(123.45)'));
      final update = PdfEditor(document);
      expect(
          update.updateTable(
              0,
              annotation,
              PdfTableData([
                ['Changed', 'Value']
              ])),
          isTrue);
      final reopened = PdfDocument.open(update.save());
      expect(reopened.page(0).annotations.single.table!.cells, [
        ['Changed', 'Value']
      ]);
    });
  }
  test('editing cells preserves a rotated, mirrored and resized local frame',
      () {
    final table = PdfTableData([
      ['Name', 'Value'],
      ['Ben', '12']
    ]);
    final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)));
    editor.addTable(0, const PdfRect(20, 30, 220, 100), table);
    var document = PdfDocument.open(editor.save());
    final rotate = PdfEditor(document);
    rotate.rotateAnnotation(0, document.page(0).annotations.single, 37);
    document = PdfDocument.open(rotate.save());
    final resize = PdfEditor(document);
    resize.resizeAnnotationLocal(
        0, document.page(0).annotations.single, const PdfRect(40, 50, 300, 170),
        flipX: true);
    document = PdfDocument.open(resize.save());
    final before = document.page(0).annotations.single;
    final quad = before.appearanceQuad!;
    final update = PdfEditor(document);
    expect(
        update.updateTable(
            0,
            before,
            PdfTableData([
              ['Changed', 'Value'],
              ['Ben', '25']
            ])),
        isTrue);
    final after = PdfDocument.open(update.save()).page(0).annotations.single;
    expect(after.table!.cells[1][1], '25');
    for (var i = 0; i < 4; i++) {
      expect(after.appearanceQuad![i].$1, closeTo(quad[i].$1, 1e-6));
      expect(after.appearanceQuad![i].$2, closeTo(quad[i].$2, 1e-6));
    }
  });
  test('protected tables cannot be rewritten', () {
    final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)));
    editor.addTable(
        0,
        const PdfRect(20, 20, 220, 100),
        PdfTableData([
          ['A', 'B']
        ]));
    final document = PdfDocument.open(editor.save());
    final lock = PdfEditor(document);
    lock.setAnnotationFlags(0, document.page(0).annotations.single, 128);
    final locked = PdfDocument.open(lock.save());
    final change = PdfEditor(locked);
    expect(
        change.updateTable(
            0,
            locked.page(0).annotations.single,
            PdfTableData([
              ['X']
            ])),
        isFalse);
    expect(change.hasChanges, isFalse);
  });
}
