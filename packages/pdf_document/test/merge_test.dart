import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

// Independent, from-scratch fixture: indirect field/name-tree arrays, a shared
// multi-widget field, inherited form defaults, and a named link/bookmark.
Uint8List richPdf(String label,
    {String font = 'Helvetica', bool legacy = false}) {
  final b = CosDocumentBuilder();
  final pages = CosDictionary({'Type': const CosName('Pages')});
  final pagesRef = b.add(pages);
  final leaves = [
    for (var i = 0; i < 2; i++)
      CosDictionary({
        'Type': const CosName('Page'),
        'Parent': pagesRef,
        'MediaBox': CosArray([
          const CosInteger(0),
          const CosInteger(0),
          const CosInteger(612),
          const CosInteger(792)
        ]),
        'Resources': CosDictionary(),
        'Contents': b.add(CosStream(CosDictionary(),
            Uint8List.fromList('BT ($label ${i + 1}) Tj ET'.codeUnits))),
      })
  ];
  final refs = [for (final leaf in leaves) b.add(leaf)];
  pages['Kids'] = CosArray(refs);
  pages['Count'] = const CosInteger(2);
  final root = CosDictionary({'T': CosString.fromText('client')});
  final rootRef = b.add(root);
  final field = CosDictionary({
    'Parent': rootRef,
    'T': CosString.fromText('name'),
    'FT': const CosName('Tx'),
    'V': CosString.fromText(label),
  });
  final fieldRef = b.add(field);
  root['Kids'] = b.add(CosArray([fieldRef]));
  final widgets = [
    for (var i = 0; i < 2; i++)
      b.add(CosDictionary({
        'Type': const CosName('Annot'),
        'Subtype': const CosName('Widget'),
        'Parent': fieldRef,
        'P': refs[i],
        'Rect': CosArray([
          const CosInteger(20),
          const CosInteger(20),
          const CosInteger(180),
          const CosInteger(50)
        ]),
      }))
  ];
  field['Kids'] = b.add(CosArray(widgets));
  final link = b.add(CosDictionary({
    'Type': const CosName('Annot'),
    'Subtype': const CosName('Link'),
    'Rect': CosArray([
      const CosInteger(20),
      const CosInteger(60),
      const CosInteger(180),
      const CosInteger(80)
    ]),
    'A': b.add(CosDictionary(
        {'S': const CosName('GoTo'), 'D': CosString.fromText('chapter')})),
  }));
  leaves[0]['Annots'] = b.add(CosArray([widgets[0], link]));
  leaves[1]['Annots'] = b.add(CosArray([widgets[1]]));
  final destination = CosArray([
    refs[1],
    const CosName('XYZ'),
    const CosInteger(10),
    const CosInteger(700),
    CosNull.instance
  ]);
  final outlines = CosDictionary({'Type': const CosName('Outlines')});
  final outlinesRef = b.add(outlines);
  final heading = CosDictionary({
    'Title': CosString.fromText(label),
    'Parent': outlinesRef,
    'Dest': const CosName('chapter'),
    'Count': const CosInteger(-1),
    'F': const CosInteger(2),
  });
  final headingRef = b.add(heading);
  final child = b.add(CosDictionary({
    'Title': CosString.fromText('Start'), 'Parent': headingRef,
    // Integer page destinations must be remapped, not copied verbatim.
    'A': CosDictionary({
      'S': const CosName('GoTo'),
      'D': CosArray([const CosInteger(0), const CosName('Fit')])
    }),
  }));
  heading['First'] = child;
  heading['Last'] = child;
  outlines['First'] = headingRef;
  outlines['Last'] = headingRef;
  outlines['Count'] = const CosInteger(1);
  final catalog = b.add(CosDictionary({
    'Type': const CosName('Catalog'),
    'Pages': pagesRef,
    'PageMode': CosName(legacy ? 'UseThumbs' : 'UseOutlines'),
    'Outlines': outlinesRef,
    if (legacy)
      'Dests': CosDictionary({'chapter': destination})
    else
      'Names': b.add(CosDictionary({
        'Dests': b.add(CosDictionary({
          'Kids': CosArray([
            b.add(CosDictionary({
              'Names': b.add(CosArray([
                CosString.fromText('chapter'),
                CosDictionary({'D': destination}),
              ]))
            })),
          ])
        })),
      })),
    'AcroForm': b.add(CosDictionary({
      'Fields': b.add(CosArray([rootRef])),
      'DA': CosString.fromText('/F1 11 Tf 0 g'),
      'Q': const CosInteger(2),
      'DR': b.add(CosDictionary({
        'Font': CosDictionary({
          'F1': b.add(CosDictionary({
            'Type': const CosName('Font'),
            'Subtype': const CosName('Type1'),
            'BaseFont': CosName(font)
          })),
        })
      })),
    })),
  }));
  return b.build(
      root: catalog,
      info: b.add(CosDictionary({'Title': CosString.fromText(label)})));
}

void main() {
  test('bytes-only merge preserves order and leaves input buffers unchanged',
      () {
    final first = buildMultiPagePdf(2);
    final original = Uint8List.fromList(first);
    final result =
        PdfMerger.merge([first, buildMultiPagePdf(3), buildMultiPagePdf(1)]);
    final doc = PdfDocument.open(result);
    expect(doc.pageCount, 6);
    expect([
      for (var i = 0; i < 6; i++)
        String.fromCharCodes(doc.page(i).contentBytes())
    ], [
      for (final n in [1, 2, 1, 2, 3, 1]) contains('(Page $n)')
    ]);
    expect(first, original);
    expect(result.sublist(0, first.length), original);
    final single = PdfMerger.merge([first]);
    expect(single, first);
    expect(identical(single, first), isFalse);
  });

  test('invalid input and password lists fail explicitly', () {
    expect(() => PdfMerger.merge([]), throwsArgumentError);
    expect(() => PdfMerger.merge([buildMultiPagePdf(1)], passwords: []),
        throwsArgumentError);
    expect(() => PdfMerger.merge([Uint8List(0)]),
        throwsA(isA<CosParseException>()));
    expect(
        () => PdfMerger.merge(
            [buildMultiPagePdf(1), buildEncryptedPdf(userPassword: 'secret')]),
        throwsA(isA<CosPasswordException>()));
  });

  for (final revision in [2, 3, 4, 6]) {
    for (final encryptedBase in [false, true]) {
      test(
          'R$revision source imports into ${encryptedBase ? 'encrypted' : 'plain'} base',
          () {
        final base = encryptedBase
            ? buildEncryptedPdf(revision: revision, userPassword: 'base')
            : buildMultiPagePdf(1);
        final incoming =
            buildEncryptedPdf(revision: revision, userPassword: 'source');
        final result = PdfMerger.merge([base, incoming, buildMultiPagePdf(1)],
            passwords: [encryptedBase ? 'base' : '', 'source', '']);
        final doc =
            PdfDocument.open(result, password: encryptedBase ? 'base' : '');
        expect(doc.cos.isEncrypted, encryptedBase);
        expect(doc.pageCount, 3);
        expect(String.fromCharCodes(doc.page(1).contentBytes()),
            contains('Hello, world!'));
        expect(String.fromCharCodes(doc.page(2).contentBytes()),
            contains('Page 1'));
        if (encryptedBase) {
          expect(() => PdfDocument.open(result),
              throwsA(isA<CosPasswordException>()));
          expect(doc.info['Title'], 'Secret Title');
        }
      });
    }
  }

  for (final cryptName in ['Identity', 'StdCF']) {
    for (final compressed in [false, true]) {
      test(
          'source /Crypt $cryptName (${compressed ? 'Flate' : 'raw'}) is replaced by destination encryption',
          () {
        final source = PdfDocument.open(
            buildEncryptedPdf(revision: 4, userPassword: 'source'),
            password: 'source');
        final update = CosIncrementalUpdater(source.cos);
        final content =
            Uint8List.fromList('BT (imported crypt stream) Tj ET'.codeUnits);
        final payload = compressed
            ? Uint8List.fromList(ZLibEncoder().encode(content))
            : content;
        final crypt = CosDictionary({'Name': CosName(cryptName)});
        final stream = CosStream(
            CosDictionary({
              'Filter': compressed
                  ? CosArray(
                      [const CosName('Crypt'), const CosName('FlateDecode')])
                  : const CosName('Crypt'),
              'DecodeParms':
                  compressed ? CosArray([crypt, CosNull.instance]) : crypt,
            }),
            payload);
        source.page(0).dict['Contents'] = update.addObject(stream);
        update.markChanged(source.page(0).dict);
        final input = update.save();
        for (final encryptedBase in [false, true]) {
          final base = encryptedBase
              ? buildEncryptedPdf(revision: 6, userPassword: 'base')
              : buildMultiPagePdf(1);
          final merged = PdfMerger.merge([base, input],
              passwords: [encryptedBase ? 'base' : '', 'source']);
          final result =
              PdfDocument.open(merged, password: encryptedBase ? 'base' : '');
          expect(result.page(1).contentBytes(), content);
          final imported =
              result.cos.resolve(result.page(1).dict['Contents']) as CosStream;
          final filters = imported.dictionary['Filter'];
          if (compressed) {
            expect((filters as CosArray).items, [const CosName('FlateDecode')]);
          } else {
            expect(filters, isNull);
          }
          if (encryptedBase) expect(imported.rawBytes, isNot(payload));
        }
      });
    }
  }

  test('form defaults come along when the destination has no AcroForm', () {
    final source = PdfDocument.open(richPdf('source', font: 'Courier'));
    final form = PdfAcroForm.of(source)!;
    form.dict['NeedAppearances'] = const CosBoolean(true);
    final update = CosIncrementalUpdater(source.cos)..markChanged(form.dict);
    final doc = PdfDocument.open(
        PdfMerger.merge([buildMultiPagePdf(1), update.save()]));
    final imported = PdfAcroForm.of(doc)!;
    expect(imported.needsAppearances, isTrue);
    expect(imported.fields.single.name, 'client.name');
    expect(imported.fields.single.widgetPageIndex(0), 1);
    expect(imported.fields.single.widgetPageIndex(1), 2);
  });

  test('form strings and outlines are re-encrypted with the destination', () {
    final merged = PdfMerger.merge([
      buildEncryptedPdf(revision: 6, userPassword: 'base'),
      richPdf('source'),
    ], passwords: [
      'base',
      ''
    ]);
    final doc = PdfDocument.open(merged, password: 'base');
    expect(PdfAcroForm.of(doc)!.fields.single.value, 'source');
    expect(PdfOutline.of(doc).items.single.title, 'source');
    expect(PdfDestination.parse(doc, const CosName('chapter'))!.pageIndex, 2);
    expect(String.fromCharCodes(merged), isNot(contains('(source)')));
  });

  test('complete imports include hidden fields and their calculation order',
      () {
    final source = PdfDocument.open(richPdf('source'));
    final form = PdfAcroForm.of(source)!;
    final update = CosIncrementalUpdater(source.cos);
    final hidden = update.addObject(CosDictionary({
      'FT': const CosName('Tx'),
      'T': CosString.fromText('hidden'),
      'V': CosString.fromText('stored value'),
    }));
    final fields = source.cos.resolve(form.dict['Fields']) as CosArray;
    form.dict['Fields'] = CosArray([...fields.items, hidden]);
    form.dict['CO'] = CosArray([hidden]);
    update.markChanged(form.dict);
    final bytes = update.save();
    final doc = PdfDocument.open(PdfMerger.merge([bytes, bytes]));
    final merged = PdfAcroForm.of(doc)!;
    expect(merged.fields.map((f) => f.name),
        ['client.name', 'hidden', 'client_2.name', 'hidden_2']);
    expect(merged.fieldNamed('hidden_2')!.value, 'stored value');
    final order = doc.cos.resolve(merged.dict['CO']) as CosArray;
    expect(order.length, 2);
    expect(
        doc.cos.resolve(order[1]), same(merged.fieldNamed('hidden_2')!.dict));
  });

  test('forms retain widgets, values and independent default resources', () {
    final first = richPdf('base', legacy: true);
    final source = richPdf('source', font: 'Courier');
    final sourceBefore = Uint8List.fromList(source);
    final merged = PdfMerger.merge([first, source, source]);
    final doc = PdfDocument.open(merged);
    final form = PdfAcroForm.of(doc)!;
    expect(form.fields.map((f) => f.name),
        ['client.name', 'client_2.name', 'client_3.name']);
    for (var i = 0; i < 3; i++) {
      final field = form.fields[i];
      expect(field.widgets, hasLength(2));
      expect([field.widgetPageIndex(0), field.widgetPageIndex(1)],
          [i * 2, i * 2 + 1]);
    }
    final resources = form.defaultResources!;
    final fonts = doc.cos.resolve(resources['Font']) as CosDictionary;
    final courier = doc.cos.resolve(fonts['F1_2']) as CosDictionary;
    expect(courier['BaseFont'], const CosName('Courier'));
    final imported = form.fieldNamed('client_2.name')!;
    final parent = doc.cos.resolve(imported.dict['Parent']) as CosDictionary;
    expect((doc.cos.resolve(parent['DA']) as CosString).text,
        contains('/F1_2 11 Tf'));
    expect(parent['Q'], const CosInteger(2));
    final edit = PdfEditor(doc)..setTextValue(imported, 'changed');
    final reopened = PdfDocument.open(edit.save());
    final fields = PdfAcroForm.of(reopened)!.fields;
    expect(fields.map((f) => f.value), ['base', 'changed', 'source']);
    expect(fields[1].widgets.every((w) => w.containsKey('AP')), isTrue);
    expect(source, sourceBefore);
  });

  test('named destinations, links, outline hierarchy and PageMode survive', () {
    final doc = PdfDocument.open(PdfMerger.merge([
      richPdf('base', legacy: true),
      richPdf('source'),
      richPdf('third'),
    ]));
    expect(doc.catalog['PageMode'], const CosName('UseThumbs'));
    expect(doc.info['Title'], 'base');
    for (var i = 0; i < 3; i++) {
      final name = i == 0 ? 'chapter' : 'chapter_${i + 1}';
      final dest = PdfDestination.parse(doc, CosString.fromText(name))!;
      expect(dest.pageIndex, i * 2 + 1);
      expect(dest.params, [10, 700, null]);
      final link =
          doc.page(i * 2).annotations.whereType<PdfLinkAnnotation>().single;
      expect((link.action as PdfGoToAction).destination.pageIndex, i * 2 + 1);
    }
    final outline = PdfOutline.of(doc);
    expect(outline.items.map((i) => i.title), ['base', 'source', 'third']);
    for (var i = 0; i < 3; i++) {
      final item = outline.items[i];
      expect(item.destination!.pageIndex, i * 2 + 1);
      expect(item.open, isFalse);
      expect(item.bold, isTrue);
      expect(item.children.single.destination!.pageIndex, i * 2);
    }
    expect(PdfOutline.rootCount(doc), 3);
  });

  test('subset insertion prunes off-page widgets and cannot alias named links',
      () {
    final editor = PdfEditor(PdfDocument.open(richPdf('base')))
      ..appendPagesFrom(PdfDocument.open(richPdf('source')),
          indices: [0], at: 1);
    final doc = PdfDocument.open(editor.save());
    expect(doc.pageCount, 3);
    final field = PdfAcroForm.of(doc)!.fieldNamed('client_2.name')!;
    expect(field.widgets, hasLength(1));
    expect(field.widgetPageIndex(0), 1);
    final link = doc.page(1).annotations.whereType<PdfLinkAnnotation>().single;
    expect(link.action, isNull); // source's chapter was on the omitted page
    expect(PdfDestination.parse(doc, const CosName('chapter'))!.pageIndex, 2);
    expect(PdfDestination.parse(doc, const CosName('chapter_2')), isNull);
    expect(PdfOutline.of(doc).items.last.children.single.destination!.pageIndex,
        1);
  });
}
