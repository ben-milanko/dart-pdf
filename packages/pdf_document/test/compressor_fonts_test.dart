import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_document/src/compressor_font_program.dart';
import 'package:pdf_document/src/compressor_fonts.dart';
import 'package:test/test.dart';

void main() {
  final original = File('test/fonts/DejaVuSans.ttf').readAsBytesSync();
  final parsed = PdfEmbeddedFont.parse(original);
  final a = parsed.glyphForRune(65);
  final accented = parsed.glyphForRune(0xe9);
  final z = parsed.glyphForRune(90);

  test('TrueType retains IDs, metrics, used outlines and composite closure',
      () {
    final subset = PdfSubsetFontProgram.parse(original).subset({a, accented})!;
    final before = _tables(original);
    final after = _tables(subset);
    expect(subset.length, lessThan(original.length ~/ 2));
    expect(after['maxp'], before['maxp']);
    expect(after['hmtx'], before['hmtx']);
    expect(after['cmap'], before['cmap']);
    final dependencies = _glyphClosure(original, {0, a, accented});
    expect(dependencies.length, greaterThan(3), reason: 'é is composite');
    for (final gid in dependencies) {
      expect(_glyph(subset, gid), _glyph(original, gid), reason: 'glyph $gid');
    }
    expect(_glyph(subset, z), isEmpty);
    final reparsed = PdfEmbeddedFont.parse(subset);
    expect(reparsed.glyphForRune(65), a);
    expect(
        reparsed.advanceForGlyph(accented), parsed.advanceForGlyph(accented));
    expect(_checksum(subset), 0xb1b0afba);
    _verifyTableChecksums(subset);
  });

  test('short loca offsets and recursive composite components remain valid',
      () {
    final bytes =
        File('test/fonts/LiberationSans-Regular.ttf').readAsBytesSync();
    final font = PdfEmbeddedFont.parse(bytes);
    final gid = font.glyphForRune(0x1eae); // nested accented Vietnamese glyph
    final subset = PdfSubsetFontProgram.parse(bytes).subset({gid})!;
    for (final dependency in _glyphClosure(bytes, {0, gid})) {
      expect(_glyph(subset, dependency), _glyph(bytes, dependency));
    }
    expect(_checksum(subset), 0xb1b0afba);
  });

  test('font rights and unsupported formats preserve the original program', () {
    final copy = Uint8List.fromList(original);
    final offset = _tableOffsets(copy)['OS/2']!.$1;
    ByteData.sublistView(copy).setUint16(offset + 8, 0x0100);
    expect(() => PdfSubsetFontProgram.parse(copy), throwsFormatException);
    expect(() => PdfSubsetFontProgram.parse(Uint8List.fromList([2, 0, 5, 0])),
        throwsFormatException);
  });

  test('page, form, pattern, appearance and Type 3 content all retain glyphs',
      () {
    for (final source in [
      'page',
      'form',
      'pattern',
      'appearance',
      'charproc'
    ]) {
      final document = _pdfWithFont(original, a, source: source);
      final font = _font(document);
      final originalMap = document.cos.resolve(font['ToUnicode']);
      final stats = subsetPdfFonts(document);
      expect(stats.fontsSubset, 1, reason: source);
      expect(stats.bytesSaved, greaterThan(100000), reason: source);
      final subset = _fontBytes(document);
      expect(_glyph(subset, a), _glyph(original, a), reason: source);
      expect(_glyph(subset, z), isEmpty, reason: source);
      expect(document.cos.resolve(font['ToUnicode']), same(originalMap));
      final baseName =
          (document.cos.resolve(font['BaseFont']) as CosName).value;
      expect(baseName, matches(RegExp(r'^[A-Z]{6}\+DejaVuSans$')));
    }
  });

  test('CIDToGIDMap preserves glyphs addressed by non-identity CIDs', () {
    final document = _pdfWithFont(original, 5);
    final descendant = _descendant(document);
    final map = Uint8List(12);
    ByteData.sublistView(map).setUint16(10, a);
    descendant['CIDToGIDMap'] = CosStream(CosDictionary(), map);
    expect(subsetPdfFonts(document).fontsSubset, 1);
    expect(_glyph(_fontBytes(document), a), _glyph(original, a));
    expect(_glyph(_fontBytes(document), z), isEmpty);
  });

  test('page-tree leaves with a missing Type still contribute text usage', () {
    final document = _pdfWithFont(original, a);
    document.page(0).dict.entries.remove('Type');
    expect(subsetPdfFonts(document).fontsSubset, 1);
    expect(_glyph(_fontBytes(document), a), _glyph(original, a));
  });

  test('shared fonts collect every text-show operator and resource scope', () {
    final document = _pdfWithFont(original, a);
    final shown = [a, accented, z, parsed.glyphForRune(0x3a9)];
    final text = '/F0 12 Tf <${_hex(shown[0])}> Tj '
        '[<${_hex(shown[1])}> -30] TJ <${_hex(shown[2])}> \' '
        '0 0 <${_hex(shown[3])}> "';
    document.page(0).dict['Contents'] = _stream(text);
    expect(subsetPdfFonts(document).fontsSubset, 1);
    final subset = _fontBytes(document);
    for (final gid in shown) {
      expect(_glyph(subset, gid), _glyph(original, gid));
    }
  });

  test('editable form fonts and unsupported shared encodings are retained', () {
    final formDoc = _pdfWithFont(original, a);
    final font = _font(formDoc);
    formDoc.catalog['AcroForm'] = CosDictionary({
      'DR': CosDictionary({
        'Font': CosDictionary({'F0': font})
      }),
      'Fields': CosArray([]),
    });
    final formStats = subsetPdfFonts(formDoc);
    expect(formStats.fontsSubset, 0);
    expect(formStats.warnings, contains(contains('editable form')));
    expect(_fontBytes(formDoc), original);

    final sharedDoc = _pdfWithFont(original, a);
    final shared = CosDictionary(Map.of(_font(sharedDoc).entries))
      ..['Encoding'] = const CosName('UniJIS-UTF16-H');
    sharedDoc.page(0).resources['AlternateFont'] = shared;
    expect(subsetPdfFonts(sharedDoc).fontsSubset, 0);
    expect(_fontBytes(sharedDoc), original);
  });

  test('undecodable content does not discard unseen glyphs', () {
    final document = _pdfWithFont(original, a);
    document.page(0).dict['Contents'] = CosStream(
        CosDictionary({'Filter': const CosName('FlateDecode')}),
        Uint8List.fromList([1, 2, 3]));
    final stats = subsetPdfFonts(document);
    expect(stats.fontsSubset, 0);
    expect(stats.warnings, isNotEmpty);
    expect(_fontBytes(document), original);
  });

  test('malformed multi-descendant consumers protect shared programs', () {
    final document = _pdfWithFont(original, a);
    final alternate = CosDictionary(Map.of(_font(document).entries))
      ..['DescendantFonts'] = CosArray([
        _descendant(document),
        CosDictionary({'Subtype': const CosName('CIDFontType2')}),
      ]);
    document.page(0).resources['AlternateFont'] = alternate;
    expect(subsetPdfFonts(document).fontsSubset, 0);
    expect(_fontBytes(document), original);
  });

  test('editable form resource aliases P and Parent retain the complete font',
      () {
    for (final alias in ['P', 'Parent']) {
      final document = _pdfWithFont(original, a);
      document.catalog['AcroForm'] = CosDictionary({
        'DR': CosDictionary({
          'Font': CosDictionary({alias: _font(document)})
        }),
        'Fields': CosArray([]),
      });
      expect(subsetPdfFonts(document).fontsSubset, 0, reason: alias);
      expect(_fontBytes(document), original, reason: alias);
    }
  });

  test('a font stream aliased as an attachment is preserved', () {
    final document = _pdfWithFont(original, a);
    document.catalog['Attachment'] =
        CosDictionary({'EF': _fontStream(document)});
    expect(subsetPdfFonts(document).fontsSubset, 0);
    expect(_fontBytes(document), original);
  });

  test('CFF keeps charstring IDs and relocates private subroutine offsets', () {
    final bytes = _cffFixture();
    final subset = PdfSubsetFontProgram.parse(bytes).subset({1})!;
    expect(subset.length, lessThan(bytes.length ~/ 2));
    final before = _readCff(bytes);
    final after = _readCff(subset);
    expect(after.charStrings.length, before.charStrings.length);
    expect(after.charStrings[0], before.charStrings[0]);
    expect(after.charStrings[1], before.charStrings[1]);
    expect(after.charStrings[2], [14]);
    expect(after.globalSubrs, before.globalSubrs);
    expect(after.localSubrs, before.localSubrs);
    expect(after.privateOffset, before.privateOffset,
        reason: 'private before CharStrings stays in place');
    expect(after.subrsOffset, lessThan(before.subrsOffset),
        reason: 'relative Subrs target after CharStrings is relocated');
    expect(PdfSubsetFontProgram.parse(subset).subset({1}), isNull);
  });

  test('CID-keyed CFF maps CIDs and relocates FDArray, FDSelect and privates',
      () {
    final bytes = _cffFixture(cid: true);
    final program = PdfSubsetFontProgram.parse(bytes);
    expect(program.glyphForCid(25), 1);
    expect(program.glyphForCid(1), 0);
    final subset = program.subset({program.glyphForCid(25)})!;
    final before = _readCff(bytes, cid: true);
    final after = _readCff(subset, cid: true);
    expect(after.charStrings[1], before.charStrings[1]);
    expect(after.charStrings[2], [14]);
    expect(after.localSubrs, before.localSubrs);
    expect(after.globalSubrs, before.globalSubrs);
    expect(after.privateOffset, lessThan(before.privateOffset));
    expect(PdfSubsetFontProgram.parse(subset).glyphForCid(25), 1);
  });

  test('CFF font stream optimization retains CID widths and decodes correctly',
      () {
    final document = _pdfWithFont(original, 25);
    final descendant = _descendant(document)
      ..['Subtype'] = const CosName('CIDFontType0');
    descendant.entries.remove('CIDToGIDMap');
    final descriptor =
        document.cos.resolve(descendant['FontDescriptor']) as CosDictionary;
    descriptor.entries.remove('FontFile2');
    descriptor['FontFile3'] = CosStream(
        CosDictionary({'Subtype': const CosName('CIDFontType0C')}),
        _cffFixture(cid: true));
    final widths = descendant['W'];
    expect(subsetPdfFonts(document).fontsSubset, 1);
    expect(descendant['W'], same(widths));
    final stream = document.cos.resolve(descriptor['FontFile3']) as CosStream;
    final subset = Uint8List.fromList(document.cos.decodeStreamData(stream));
    expect(_readCff(subset, cid: true).charStrings[2], [14]);
  });
}

String _hex(int gid) => gid.toRadixString(16).padLeft(4, '0');

CosStream _stream(String content, [CosDictionary? dictionary]) => CosStream(
    dictionary ?? CosDictionary(), Uint8List.fromList(latin1.encode(content)));

PdfDocument _pdfWithFont(Uint8List bytes, int gid, {String source = 'page'}) {
  final builder = CosDocumentBuilder();
  final root = CosDictionary({'Type': const CosName('Catalog')});
  final rootRef = builder.add(root);
  final pages = CosDictionary({'Type': const CosName('Pages')});
  final pagesRef = builder.add(pages);
  final font = PdfEmbeddedFont.parse(bytes)..encodeHex('AéZΩ');
  final fonts = font.buildResource(builder.add);
  final resources = CosDictionary({'Font': fonts});
  final content = 'BT /F0 12 Tf <${_hex(gid)}> Tj ET';
  final page = CosDictionary({
    'Type': const CosName('Page'),
    'Parent': pagesRef,
    'MediaBox': CosArray(
        [CosInteger(0), CosInteger(0), CosInteger(300), CosInteger(300)]),
    'Resources': resources,
    'Contents': builder.add(_stream(source == 'page' ? content : '')),
  });
  if (source == 'form') {
    resources['XObject'] = CosDictionary({
      'X1': builder.add(
          _stream(content, CosDictionary({'Subtype': const CosName('Form')})))
    });
  } else if (source == 'pattern') {
    resources['Pattern'] = CosDictionary({
      'P1': builder
          .add(_stream(content, CosDictionary({'PatternType': CosInteger(1)})))
    });
  } else if (source == 'appearance') {
    page['Annots'] = CosArray([
      builder.add(CosDictionary({
        'Subtype': const CosName('Stamp'),
        'Rect': CosArray(
            [CosInteger(0), CosInteger(0), CosInteger(100), CosInteger(100)]),
        'AP': CosDictionary({
          'N': CosDictionary({
            'Off': builder.add(_stream(content)),
          })
        }),
      }))
    ]);
  } else if (source == 'charproc') {
    fonts['T3'] = CosDictionary({
      'Type': const CosName('Font'),
      'Subtype': const CosName('Type3'),
      'CharProcs': CosDictionary({'A': builder.add(_stream(content))}),
    });
  }
  pages['Kids'] = CosArray([builder.add(page)]);
  pages['Count'] = CosInteger(1);
  root['Pages'] = pagesRef;
  return PdfDocument.open(builder.build(root: rootRef));
}

CosDictionary _font(PdfDocument document) => document.cos.resolve(
    (document.cos.resolve(document.page(0).resources['Font'])
        as CosDictionary)['F0']) as CosDictionary;

CosDictionary _descendant(PdfDocument document) => document.cos.resolve(
    (document.cos.resolve(_font(document)['DescendantFonts']) as CosArray)
        .items
        .single) as CosDictionary;

CosStream _fontStream(PdfDocument document) => document.cos.resolve(
    (document.cos.resolve(_descendant(document)['FontDescriptor'])
        as CosDictionary)['FontFile2']) as CosStream;

Uint8List _fontBytes(PdfDocument document) =>
    Uint8List.fromList(document.cos.decodeStreamData(_fontStream(document)));

Map<String, (int, int)> _tableOffsets(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  return {
    for (var i = 0; i < data.getUint16(4); i++)
      String.fromCharCodes(bytes, 12 + i * 16, 16 + i * 16): (
        data.getUint32(20 + i * 16),
        data.getUint32(24 + i * 16)
      )
  };
}

Map<String, Uint8List> _tables(Uint8List bytes) => {
      for (final entry in _tableOffsets(bytes).entries)
        entry.key: Uint8List.sublistView(
            bytes, entry.value.$1, entry.value.$1 + entry.value.$2),
    };

Uint8List _glyph(Uint8List bytes, int gid) {
  final tables = _tables(bytes);
  final short = ByteData.sublistView(tables['head']!).getInt16(50) == 0;
  final loca = ByteData.sublistView(tables['loca']!);
  final start = short ? loca.getUint16(gid * 2) * 2 : loca.getUint32(gid * 4);
  final end =
      short ? loca.getUint16((gid + 1) * 2) * 2 : loca.getUint32((gid + 1) * 4);
  return Uint8List.sublistView(tables['glyf']!, start, end);
}

Set<int> _glyphClosure(Uint8List bytes, Set<int> glyphs) {
  final keep = {...glyphs};
  final queue = glyphs.toList();
  while (queue.isNotEmpty) {
    final glyph = ByteData.sublistView(_glyph(bytes, queue.removeLast()));
    if (glyph.lengthInBytes == 0 || glyph.getInt16(0) >= 0) continue;
    var at = 10;
    int flags;
    do {
      flags = glyph.getUint16(at);
      final component = glyph.getUint16(at + 2);
      if (keep.add(component)) queue.add(component);
      at += 4 + ((flags & 1) == 0 ? 2 : 4);
      if (flags & 8 != 0) at += 2;
      if (flags & 64 != 0) at += 4;
      if (flags & 128 != 0) at += 8;
    } while (flags & 32 != 0);
  }
  return keep;
}

int _checksum(Uint8List bytes) {
  var sum = 0;
  for (var at = 0; at < bytes.length; at += 4) {
    var value = 0;
    for (var i = 0; i < 4; i++) {
      value = value * 256 + (at + i < bytes.length ? bytes[at + i] : 0);
    }
    sum = (sum + value) & 0xffffffff;
  }
  return sum;
}

void _verifyTableChecksums(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final tables = _tables(bytes);
  for (var i = 0; i < data.getUint16(4); i++) {
    final tag = String.fromCharCodes(bytes, 12 + i * 16, 16 + i * 16);
    final table = Uint8List.fromList(tables[tag]!);
    if (tag == 'head') ByteData.sublistView(table).setUint32(8, 0);
    expect(_checksum(table), data.getUint32(16 + i * 16), reason: tag);
  }
}

// Independent, deliberately noncanonical CFF fixture: non-CID Private lives
// before CharStrings but its Subrs INDEX lives after them. The CID variation
// places FDArray, FDSelect and Private after CharStrings. Both exercise every
// relocation class without consulting the production subsetter's parser.
Uint8List _cffFixture({bool cid = false}) {
  List<int> integer(int value) =>
      [29, value >> 24 & 255, value >> 16 & 255, value >> 8 & 255, value & 255];
  List<int> index(List<List<int>> objects) {
    if (objects.isEmpty) return [0, 0];
    final offsets = <int>[1];
    for (final object in objects) {
      offsets.add(offsets.last + object.length);
    }
    return [
      objects.length >> 8,
      objects.length & 255,
      2,
      for (final offset in offsets) ...[offset >> 8, offset & 255],
      for (final object in objects) ...object
    ];
  }

  final names = index(['SubsetTest'.codeUnits]);
  final strings = index(cid
      ? ['Adobe'.codeUnits, 'Identity'.codeUnits]
      : ['customOne'.codeUnits, 'customTwo'.codeUnits]);
  final globals = index([
    [139, 139, 21, 11]
  ]);
  final charset = cid ? [0, 0, 25, 0, 100] : [0, 1, 135, 1, 136];
  final chars = index([
    [14],
    [32, 29, 32, 10, 14],
    [
      139,
      139,
      21,
      for (var i = 0; i < 160; i++) ...[140 + i % 90, 139, 5],
      14
    ]
  ]);
  final locals = index([
    [239, 139, 5, 11]
  ]);
  List<int> top(
          int charsetAt, int charAt, int privateAt, int fdAt, int selectAt) =>
      [
        if (cid) ...[...integer(391), ...integer(392), ...integer(0), 12, 30],
        ...integer(charsetAt),
        15,
        ...integer(charAt),
        17,
        if (cid) ...[
          ...integer(fdAt),
          12,
          36,
          ...integer(selectAt),
          12,
          37
        ] else ...[
          ...integer(12),
          ...integer(privateAt),
          18
        ],
      ];
  final prefix = 4 +
      names.length +
      index([top(0, 0, 0, 0, 0)]).length +
      strings.length +
      globals.length;
  final charAt = prefix + charset.length + (cid ? 0 : 12);
  final fdAt = charAt + chars.length;
  final fdSize = index([
    [...integer(12), ...integer(0), 18]
  ]).length;
  final selectAt = fdAt + fdSize;
  final privateAt = cid ? selectAt + 4 : prefix + charset.length;
  final subrsAt = cid ? privateAt + 12 : charAt + chars.length;
  final private = [...integer(500), 20, ...integer(subrsAt - privateAt), 19];
  return Uint8List.fromList([
    1,
    0,
    4,
    4,
    ...names,
    ...index([top(prefix, charAt, privateAt, fdAt, selectAt)]),
    ...strings,
    ...globals,
    ...charset,
    if (!cid) ...private,
    ...chars,
    if (cid) ...[
      ...index([
        [...integer(12), ...integer(privateAt), 18]
      ]),
      0,
      0,
      0,
      0,
      ...private,
    ],
    ...locals,
  ]);
}

({
  List<List<int>> charStrings,
  List<List<int>> globalSubrs,
  List<List<int>> localSubrs,
  int privateOffset,
  int subrsOffset
}) _readCff(Uint8List bytes, {bool cid = false}) {
  final data = ByteData.sublistView(bytes);
  ({int end, List<(int, int)> ranges}) index(int start) {
    final count = data.getUint16(start);
    if (count == 0) return (end: start + 2, ranges: []);
    final size = bytes[start + 2];
    final base = start + 3 + size * (count + 1);
    int offset(int i) {
      var result = 0;
      for (var n = 0; n < size; n++) {
        result = result * 256 + bytes[start + 3 + i * size + n];
      }
      return base + result - 1;
    }

    return (
      end: offset(count),
      ranges: [for (var i = 0; i < count; i++) (offset(i), offset(i + 1))]
    );
  }

  Map<int, List<int>> dict((int, int) range) {
    final result = <int, List<int>>{};
    var stack = <int>[];
    var at = range.$1;
    while (at < range.$2) {
      final first = bytes[at++];
      if (first == 29) {
        stack.add(data.getInt32(at));
        at += 4;
      } else {
        final op = first == 12 ? 0x0c00 | bytes[at++] : first;
        result[op] = stack;
        stack = [];
      }
    }
    return result;
  }

  List<List<int>> values(int start) => [
        for (final range in index(start).ranges)
          bytes.sublist(range.$1, range.$2)
      ];
  final name = index(bytes[2]);
  final topIndex = index(name.end);
  final top = dict(topIndex.ranges.single);
  final strings = index(topIndex.end);
  final host = cid ? dict(index(top[0x0c24]!.single).ranges.single) : top;
  final privateAt = host[18]![1];
  final private = dict((privateAt, privateAt + host[18]![0]));
  final subrsAt = privateAt + private[19]!.single;
  return (
    charStrings: values(top[17]!.single),
    globalSubrs: values(strings.end),
    localSubrs: values(subrsAt),
    privateOffset: privateAt,
    subrsOffset: subrsAt
  );
}
