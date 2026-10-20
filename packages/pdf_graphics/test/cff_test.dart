import 'dart:io';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_graphics/src/fonts/cff.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

void main() {
  late CffFont font;

  setUp(() => font = CffFont.parse(buildTestCffFont())!);

  test('parses the CFF structure', () {
    expect(font.numGlyphs, 2);
    expect(font.isCidKeyed, isFalse);
  });

  test('encoding maps character codes to glyphs', () {
    expect(font.gidForCode(65), 1);
    expect(font.gidForCode(66), 0);
  });

  test('charstrings interpret to em-unit outlines', () {
    final square = font.outlineForGlyph(1)!;
    expect(square.segments.first, isA<PdfMoveTo>());
    final move = square.segments.first as PdfMoveTo;
    expect(move.x, closeTo(0, 1e-9));
    expect(move.y, closeTo(0, 1e-9));
    // 800 font units at the default 0.001 matrix = 0.8 em
    final lines = square.segments.whereType<PdfLineTo>().toList();
    expect(lines, hasLength(3));
    expect(lines[0].x, closeTo(0.8, 1e-9));
    expect(lines[1].y, closeTo(0.8, 1e-9));
    expect(square.segments.last, isA<PdfClosePath>());
  });

  test('width comes from the leading charstring operand', () {
    font.outlineForGlyph(1);
    // nominalWidthX 600 + operand 60 = 660 units = 0.66 em
    expect(font.advanceForGlyph(1), closeTo(0.66, 1e-9));
  });

  test('empty glyphs return no outline but a default width', () {
    expect(font.outlineForGlyph(0), isNull);
    // .notdef has no width operand: defaultWidthX 500
    expect(font.advanceForGlyph(0), closeTo(0.5, 1e-9));
  });

  test('endchar seac composes accented glyphs', () {
    final cff = _cffFromFormFont('../../test_corpora/pdfjs/endchar.pdf',
        formName: 'Fm0', fontName: 'T1_0');

    final e = cff.outlineForGlyph(cff.gidForName('E'))!;
    final acute = cff.outlineForGlyph(cff.gidForName('acute'))!;
    final eacute = cff.outlineForGlyph(cff.gidForName('Eacute'));
    expect(eacute, isNotNull);
    expect(eacute!.segments.length,
        greaterThan(e.segments.length + acute.segments.length - 2));
  });

  test('endchar seac composes tilde accents', () {
    final cff = _cffFromPageFont('../../test_corpora/pdfjs/glyph_accent.pdf',
        fontName: 'F1');

    final a = cff.outlineForGlyph(cff.gidForName('a'))!;
    final tilde = cff.outlineForGlyph(cff.gidForName('tilde'))!;
    final atilde = cff.outlineForGlyph(cff.gidForName('atilde'));
    expect(atilde, isNotNull);
    expect(atilde!.segments.length,
        greaterThan(a.segments.length + tilde.segments.length - 2));
  });

  test('garbage input parses to null', () {
    expect(CffFont.parse(ascii('not a font')), isNull);
  });

  test(
    'OpenType CFF faces retain their Unicode cmap',
    () {
      final bytes = File(
        '/System/Library/Fonts/ヒラギノ明朝 ProN.ttc',
      ).readAsBytesSync();
      final face = OpenTypeCffFont.parse(bytes);
      expect(face, isNotNull);
      final glyph = face!.gidForUnicode('日'.codeUnitAt(0));
      expect(glyph, greaterThan(0));
      expect(face.outlineForGlyph(glyph), isNotNull);
      expect(face.advanceForGlyph(glyph), greaterThan(0));
    },
    skip: !Platform.isMacOS,
  );

  test('OpenType CFF reads Unicode cmap formats and collections', () {
    final bytes = _testOpenTypeCff();
    final face = OpenTypeCffFont.parse(bytes);
    expect(face, isNotNull);
    expect(face!.numGlyphs, 2);
    expect(face.gidForUnicode(0x41), 1, reason: 'format 0');
    expect(face.gidForUnicode(0x42), 1, reason: 'format 4');
    expect(face.gidForUnicode(0x400), 1, reason: 'format 6');
    expect(face.gidForUnicode(0x1F600), 1, reason: 'format 12');
    expect(face.gidForUnicode(0x43), 0);
    expect(face.outlineForGlyph(1), isNotNull);
    expect(face.advanceForGlyph(1), closeTo(0.66, 1e-9));

    final collection = _testOpenTypeCffCollection();
    expect(OpenTypeCffFont.parse(collection, collectionIndex: 1), isNotNull);
    expect(OpenTypeCffFont.parse(collection, collectionIndex: -1), isNull);
    expect(OpenTypeCffFont.parse(collection, collectionIndex: 2), isNull);
  });

  test('OpenType CFF rejects malformed or incomplete containers', () {
    final plain = _testOpenTypeCff();
    expect(OpenTypeCffFont.parse(plain, collectionIndex: 1), isNull);
    expect(OpenTypeCffFont.parse(ascii('not an sfnt')), isNull);

    final trueType = Uint8List.fromList(plain)
      ..setRange(0, 4, const [0, 1, 0, 0]);
    expect(OpenTypeCffFont.parse(trueType), isNull);
    expect(OpenTypeCffFont.parse(_testOpenTypeCff(cmaps: const [])), isNull);
  });
}

Uint8List _testOpenTypeCff({
  int faceOffset = 0,
  List<List<int>>? cmaps,
}) {
  final cff = buildTestCffFont();
  final cmap = _cmapTable(cmaps ?? _testCmaps());
  const directoryLength = 12 + 2 * 16;
  final cffOffset = faceOffset + directoryLength;
  final cmapOffset = cffOffset + cff.length;
  return Uint8List.fromList([
    ..._u32(0x4F54544F), // OTTO
    ..._u16(2),
    ..._u16(0),
    ..._u16(0),
    ..._u16(0),
    ...'CFF '.codeUnits,
    ..._u32(0),
    ..._u32(cffOffset),
    ..._u32(cff.length),
    ...'cmap'.codeUnits,
    ..._u32(0),
    ..._u32(cmapOffset),
    ..._u32(cmap.length),
    ...cff,
    ...cmap,
  ]);
}

Uint8List _testOpenTypeCffCollection() {
  const firstOffset = 20;
  final first = _testOpenTypeCff(faceOffset: firstOffset);
  final secondOffset = firstOffset + first.length;
  final second = _testOpenTypeCff(faceOffset: secondOffset);
  return Uint8List.fromList([
    ...'ttcf'.codeUnits,
    ..._u32(0x00010000),
    ..._u32(2),
    ..._u32(firstOffset),
    ..._u32(secondOffset),
    ...first,
    ...second,
  ]);
}

List<List<int>> _testCmaps() {
  final format0Glyphs = List<int>.filled(256, 0)..[0x41] = 1;
  return [
    [
      ..._u16(0),
      ..._u16(262),
      ..._u16(0),
      ...format0Glyphs,
    ],
    [
      ..._u16(4),
      ..._u16(34),
      ..._u16(0),
      ..._u16(4), // two segments
      ..._u16(4),
      ..._u16(1),
      ..._u16(0),
      ..._u16(0x42),
      ..._u16(0xFFFF),
      ..._u16(0),
      ..._u16(0x42),
      ..._u16(0xFFFF),
      ..._u16(0xFFFF), // glyph 2 plus -1 => glyph 1
      ..._u16(1),
      ..._u16(4),
      ..._u16(0),
      ..._u16(2),
    ],
    [
      ..._u16(6),
      ..._u16(12),
      ..._u16(0),
      ..._u16(0x400),
      ..._u16(1),
      ..._u16(1),
    ],
    [
      ..._u16(12),
      ..._u16(0),
      ..._u32(28),
      ..._u32(0),
      ..._u32(1),
      ..._u32(0x1F600),
      ..._u32(0x1F600),
      ..._u32(1),
    ],
  ];
}

Uint8List _cmapTable(List<List<int>> subtables) {
  final recordsLength = 4 + subtables.length * 8;
  var offset = recordsLength;
  final records = <int>[];
  for (var index = 0; index < subtables.length; index++) {
    records
      ..addAll(_u16(0))
      ..addAll(_u16(index))
      ..addAll(_u32(offset));
    offset += subtables[index].length;
  }
  return Uint8List.fromList([
    ..._u16(0),
    ..._u16(subtables.length),
    ...records,
    for (final subtable in subtables) ...subtable,
  ]);
}

List<int> _u16(int value) => [(value >> 8) & 0xFF, value & 0xFF];

List<int> _u32(int value) => [
      (value >> 24) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ];

CffFont _cffFromPageFont(String path, {required String fontName}) {
  final doc = PdfDocument.open(File(path).readAsBytesSync());
  final cos = doc.cos;
  return _cffFromResources(cos, doc.page(0).resources, fontName);
}

CffFont _cffFromFormFont(
  String path, {
  required String formName,
  required String fontName,
}) {
  final doc = PdfDocument.open(File(path).readAsBytesSync());
  final cos = doc.cos;
  final xobjects =
      cos.resolve(doc.page(0).resources['XObject']) as CosDictionary;
  final form = cos.resolve(xobjects[formName]) as CosStream;
  final resources = cos.resolve(form.dictionary['Resources']) as CosDictionary;
  return _cffFromResources(cos, resources, fontName);
}

CffFont _cffFromResources(
    CosDocument cos, CosDictionary resources, String fontName) {
  final fonts = cos.resolve(resources['Font']) as CosDictionary;
  final pdfFont = cos.resolve(fonts[fontName]) as CosDictionary;
  final descriptor = cos.resolve(pdfFont['FontDescriptor']) as CosDictionary;
  final fontFile = cos.resolve(descriptor['FontFile3']) as CosStream;
  return CffFont.parse(cos.decodeStreamData(fontFile))!;
}
