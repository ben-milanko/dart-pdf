import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:test/test.dart';

Uint8List _pdf(List<String> pageContents,
    {String resources = '/Resources << >>'}) {
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [${[
      for (var i = 0; i < pageContents.length; i++) '${3 + i * 2} 0 R'
    ].join(' ')}] /Count ${pageContents.length} >>',
    for (var i = 0; i < pageContents.length; i++) ...[
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] '
          '$resources /Contents ${4 + i * 2} 0 R >>',
      '<< /Length ${latin1.encode(pageContents[i]).length} >>\n'
          'stream\n${pageContents[i]}\nendstream',
    ],
  ];
  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xrefOffset = buffer.length;
  buffer
    ..write('xref\n0 ${objects.length + 1}\n')
    ..write('0000000000 65535 f \n');
  for (final offset in offsets) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer
    ..write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n')
    ..write('startxref\n$xrefOffset\n%%EOF\n');
  return Uint8List.fromList(latin1.encode(buffer.toString()));
}

String _content(Uint8List bytes, int page) =>
    latin1.decode(PdfDocument.open(bytes).page(page).contentBytes());

void main() {
  test('annotation replacement keeps fill, geometry, identity and styles', () {
    var document = PdfDocument.open(_pdf(['']));
    var editor = PdfEditor(document)
      ..addSquare(0, const PdfRect(10, 10, 50, 50),
          strokeColor: 0xFF0000,
          fillColor: 0x00FF00,
          name: 'shape',
          author: 'Author');
    document = PdfDocument.open(editor.save());
    editor = PdfEditor(document);
    final annotation = document.page(0).annotations.single;
    expect(editor.annotationColors(0, annotation).map((c) => c.rgb).toSet(),
        {0xFF0000, 0x00FF00});
    expect(
        editor.replaceAnnotationColors(0, annotation,
            find: 0xFF0000, replace: 0x0000FF, fill: false),
        greaterThan(0));
    expect(editor.impact.annotationPages, contains(0));
    expect(editor.impact.contentPages, isEmpty);
    document = PdfDocument.open(editor.save());
    final changed = document.page(0).annotations.single;
    expect(changed.color, 0x0000FF);
    expect(changed.interiorColor, 0x00FF00);
    expect(changed.rect, const PdfRect(10, 10, 50, 50));
    expect(changed.name, 'shape');
    expect(changed.author, 'Author');
    expect(
        latin1.decode(document.cos.decodeStreamData(changed.normalAppearance!)),
        contains('0 0 1 RG'));
    editor = PdfEditor(document)
      ..resizeAnnotation(0, changed, const PdfRect(10, 10, 70, 70));
    final reopened = PdfDocument.open(editor.save());
    expect(reopened.page(0).annotations.single.color, 0x0000FF);
    expect(reopened.page(0).annotations.single.interiorColor, 0x00FF00);
  });

  test(
      'mixed rich text replaces only matching runs and keeps editable metadata',
      () {
    var document = PdfDocument.open(_pdf(['']));
    var editor = PdfEditor(document)
      ..addFreeTextRich(0, const PdfRect(5, 5, 95, 50), const [
        PdfFreeTextRun('red ', color: 0xFF0000),
        PdfFreeTextRun('green color:#ff0000', color: 0x00FF00),
      ]);
    document = PdfDocument.open(editor.save());
    editor = PdfEditor(document);
    expect(
        editor.replaceAnnotationColors(0, document.page(0).annotations.single,
            find: 0xFF0000, replace: 0x0000FF),
        greaterThan(0));
    document = PdfDocument.open(editor.save());
    final changed = document.page(0).annotations.single;
    expect(changed.freeTextStyle!.color, 0x0000FF);
    final runs =
        PdfAnnotationEditing.parseFreeTextRichContent(changed.richContent!);
    expect(runs.map((r) => r.color), [0x0000FF, 0x00FF00]);
    expect(changed.contents, 'red green color:#ff0000');
    expect(changed.richContent, contains('green color:#ff0000'));
  });

  test('transparent annotation fill leaves its stroke and records no interior',
      () {
    var document = PdfDocument.open(_pdf(['']));
    var editor = PdfEditor(document)
      ..addSquare(0, const PdfRect(10, 10, 50, 50),
          strokeColor: 0x00FF00, fillColor: 0xFF0000);
    document = PdfDocument.open(editor.save());
    editor = PdfEditor(document);
    expect(
        editor.replaceAnnotationColors(0, document.page(0).annotations.single,
            find: 0xFF0000, transparent: true),
        greaterThan(0));
    document = PdfDocument.open(editor.save());
    final changed = document.page(0).annotations.single;
    expect(changed.interiorColor, isNull);
    expect(changed.color, 0x00FF00);
    final ops = ContentStreamParser.parse(
        document.cos.decodeStreamData(changed.normalAppearance!));
    expect(ops.map((o) => o.operator), isNot(contains('B')));
    expect(ops.map((o) => o.operator), contains('S'));
  });

  test('lists explicit page-content colors by frequency', () {
    final editor = PdfEditor(PdfDocument.open(_pdf([
      '1 0 0 rg 0 0 10 10 re f\n'
          '1 0 0 RG 0 0 m 20 20 l S\n'
          '0 1 0 rg 20 20 10 10 re f\n',
    ])));

    final colors = editor.contentColors(0);

    expect(colors.map((color) => color.rgb), [0xFF0000, 0x00FF00]);
    expect(colors.first.fillUses, 1);
    expect(colors.first.strokeUses, 1);
  });

  test('replaces matching fill and stroke colors in page content', () {
    final editor = PdfEditor(PdfDocument.open(_pdf([
      '1 0 0 rg 0 0 10 10 re f\n'
          '1 0 0 RG 0 0 m 20 20 l S\n'
          '0 1 0 rg 20 20 10 10 re f\n',
    ])));

    final count = editor.replaceColors(0, find: 0xFF0000, replace: 0x0000FF);
    expect(count, 2);

    final content = _content(editor.save(), 0);
    expect(content, contains('0 0 1 rg'));
    expect(content, contains('0 0 1 RG'));
    expect(content, contains('0 1 0 rg'));
  });

  test('replaces several source colors in one pass', () {
    final editor = PdfEditor(PdfDocument.open(_pdf([
      '1 0 0 rg 0 0 10 10 re f\n'
          '0 0 1 rg 20 20 10 10 re f\n',
    ])));

    final count = editor.replaceColors(
      0,
      finds: const [0xFF0000, 0x0000FF],
      replace: 0x0000FF,
    );
    expect(count, 2);

    final content = _content(editor.save(), 0);
    expect(RegExp(r'0 0 1 rg').allMatches(content), hasLength(2));
    expect(content, isNot(contains('1 0 0 rg')));
  });

  test('can limit processing to fills or strokes', () {
    final editor = PdfEditor(PdfDocument.open(_pdf([
      '1 0 0 rg 0 0 10 10 re f\n'
          '1 0 0 RG 0 0 m 20 20 l S\n',
    ])));

    final count = editor.replaceColors(0,
        find: 0xFF0000, replace: 0x0000FF, stroke: false);
    expect(count, 1);

    final content = _content(editor.save(), 0);
    expect(content, contains('0 0 1 rg'));
    expect(content, contains('1 0 0 RG'));
  });

  test('matches gray cmyk and simple color-space sc operators', () {
    final editor = PdfEditor(PdfDocument.open(_pdf([
      '0 g 0 0 10 10 re f\n'
          '0 1 1 0 k 10 10 10 10 re f\n'
          '/CS1 cs 1 0 0 sc 20 20 10 10 re f\n',
    ], resources: '/Resources << /ColorSpace << /CS1 /DeviceRGB >> >>')));

    final count = editor.replaceColors(0, find: 0xFF0000, replace: 0x0000FF);
    expect(count, 2);

    final content = _content(editor.save(), 0);
    expect(content, contains('0 g'));
    expect(content, contains('0 0 1 rg'));
    expect(RegExp(r'0 0 1 rg').allMatches(content), hasLength(2));
  });

  test('tolerance matches near colors', () {
    final editor = PdfEditor(PdfDocument.open(_pdf([
      '0.98 0.02 0 rg 0 0 10 10 re f\n',
    ])));

    expect(
        editor.replaceColors(0, find: 0xFF0000, replace: 0x0000FF), equals(0));
    expect(
        editor.replaceColors(0,
            find: 0xFF0000, replace: 0x0000FF, tolerance: 6),
        1);
  });

  test('can replace matching paths and text with transparent output', () {
    final editor = PdfEditor(PdfDocument.open(_pdf([
      '1 0 0 rg 0 0 10 10 re f\n'
          'BT 12 Tf (Hidden) Tj ET\n'
          '0 1 0 rg 20 20 10 10 re f\n',
    ])));

    final count = editor.replaceColors(0, find: 0xFF0000, transparent: true);
    expect(count, 2);

    final content = _content(editor.save(), 0);
    expect(content, contains('n\n'));
    expect(content, contains('3 Tr\n(Hidden) Tj\n0 Tr'));
    expect(content, contains('0 1 0 rg'));
  });

  test('replaceColorsOnPages touches only requested pages', () {
    final editor = PdfEditor(PdfDocument.open(_pdf([
      '1 0 0 rg 0 0 10 10 re f',
      '1 0 0 rg 0 0 10 10 re f',
    ])));

    final count =
        editor.replaceColorsOnPages([1], find: 0xFF0000, replace: 0x0000FF);
    expect(count, 1);

    final saved = editor.save();
    expect(_content(saved, 0), contains('1 0 0 rg'));
    expect(_content(saved, 1), contains('0 0 1 rg'));
  });
}
