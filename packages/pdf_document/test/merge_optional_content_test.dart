import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:test/test.dart';

void main() {
  test(
      'import preserves independent default layer states and source references',
      () {
    final a = _layerDocument('A', baseOn: false, on: [0]);
    final b = _layerDocument('B', baseOn: true, on: [0], off: [0]);
    final beforeA = a.catalog.toString();
    final beforeB = b.catalog.toString();
    final editor = PdfEditor(_emptyDocument())
      ..appendPagesFrom(a)
      ..appendPagesFrom(b);
    final merged = PdfDocument.open(editor.save());
    final properties = _dict(merged, merged.catalog['OCProperties']);
    final config = _dict(merged, properties['D']);
    final groups = _array(merged, properties['OCGs']);
    final visible = _names(merged, config['ON']);
    final hidden = _names(merged, config['OFF']);
    expect(groups, hasLength(4));
    expect(visible, {'A0', 'B1'});
    expect(hidden, {'A1', 'B0'});
    for (var page = 0; page < 2; page++) {
      final resources = merged.page(page).resources;
      final pageGroups = _dict(merged, resources['Properties']);
      for (var i = 0; i < 2; i++) {
        final group = merged.cos.resolve(pageGroups['G$i']);
        expect(
            groups
                .map(merged.cos.resolve)
                .any((entry) => identical(entry, group)),
            isTrue);
      }
    }
    expect(a.catalog.toString(), beforeA);
    expect(b.catalog.toString(), beforeB);
  });

  test(
      'usage applications stay within source groups, including empty all-target lists',
      () {
    final editor = PdfEditor(_layerDocument('A', targets: null))
      ..appendPagesFrom(_layerDocument('B', targets: [1]))
      ..appendPagesFrom(_layerDocument('C', targets: []));
    final merged = PdfDocument.open(editor.save());
    final config =
        _dict(merged, _dict(merged, merged.catalog['OCProperties'])['D']);
    final applications = _array(merged, config['AS']);
    expect(applications, hasLength(3));
    final targets = [
      for (final application in applications)
        _names(merged, _dict(merged, application)['OCGs'])
    ];
    expect(targets, [
      {'A0', 'A1'},
      {'B1'},
      {'C0', 'C1'}
    ]);
    final groups =
        _array(merged, _dict(merged, merged.catalog['OCProperties'])['OCGs']);
    for (final group in groups) {
      final usage = _dict(merged, _dict(merged, group)['Usage']);
      expect(_dict(merged, usage['Print'])['PrintState'], isA<CosName>());
    }
  });

  test(
      'first imported output intent survives and later profiles do not replace it',
      () {
    final source = _layerDocument('First');
    final editor = PdfEditor(_emptyDocument())
      ..appendPagesFrom(source)
      ..appendPagesFrom(_layerDocument('Second'));
    final merged = PdfDocument.open(editor.save());
    final intents = _array(merged, merged.catalog['OutputIntents']);
    expect(intents, hasLength(1));
    final intent = _dict(merged, intents.single);
    expect(
        (merged.cos.resolve(intent['OutputConditionIdentifier']) as CosString)
            .text,
        'First');
    final profile =
        merged.cos.resolve(intent['DestOutputProfile']) as CosStream;
    expect(profile.rawBytes, [1, 2, 3, 4]);
    expect(source.catalog['OutputIntents'], isNotNull);
  });
}

CosDictionary _dict(PdfDocument document, CosObject? value) =>
    document.cos.resolve(value) as CosDictionary;

List<CosObject> _array(PdfDocument document, CosObject? value) =>
    (document.cos.resolve(value) as CosArray).items;

Set<String> _names(PdfDocument document, CosObject? value) => {
      for (final group in _array(document, value))
        (document.cos.resolve(_dict(document, group)['Name']) as CosString)
            .text,
    };

PdfDocument _emptyDocument() {
  final builder = CosDocumentBuilder();
  final pages = builder.add(CosDictionary({
    'Type': const CosName('Pages'),
    'Kids': CosArray([]),
    'Count': const CosInteger(0),
  }));
  return PdfDocument.open(builder.build(
      root: builder.add(CosDictionary({
    'Type': const CosName('Catalog'),
    'Pages': pages,
  }))));
}

PdfDocument _layerDocument(
  String label, {
  bool baseOn = true,
  List<int> on = const [],
  List<int> off = const [],
  List<int>? targets,
}) {
  final builder = CosDocumentBuilder();
  final groups = [
    for (var i = 0; i < 2; i++)
      builder.add(CosDictionary({
        'Type': const CosName('OCG'),
        'Name': CosString.fromText('$label$i'),
        'Usage': CosDictionary({
          'Print': CosDictionary({
            'PrintState': CosName(i == 0 ? 'ON' : 'OFF'),
          })
        }),
      }))
  ];
  final pages = CosDictionary({'Type': const CosName('Pages')});
  final parent = builder.add(pages);
  final page = builder.add(CosDictionary({
    'Type': const CosName('Page'),
    'Parent': parent,
    'MediaBox': CosArray([
      const CosInteger(0),
      const CosInteger(0),
      const CosInteger(612),
      const CosInteger(792)
    ]),
    'Resources': CosDictionary({
      'Properties': CosDictionary({
        'G0': groups[0],
        'G1': groups[1],
      })
    }),
  }));
  pages['Count'] = const CosInteger(1);
  pages['Kids'] = CosArray([page]);
  return PdfDocument.open(builder.build(
      root: builder.add(CosDictionary({
    'Type': const CosName('Catalog'),
    'Pages': parent,
    'OCProperties': builder.add(CosDictionary({
      'OCGs': builder.add(CosArray(groups)),
      'D': builder.add(CosDictionary({
        'BaseState': CosName(baseOn ? 'ON' : 'OFF'),
        'ON': builder.add(CosArray([for (final index in on) groups[index]])),
        'OFF': builder.add(CosArray([for (final index in off) groups[index]])),
        'AS': CosArray([
          CosDictionary({
            'Event': const CosName('Print'),
            'Category': CosArray([const CosName('Print')]),
            if (targets != null)
              'OCGs': CosArray([for (final index in targets) groups[index]]),
          })
        ]),
      })),
    })),
    'OutputIntents': CosArray([
      CosDictionary({
        'Type': const CosName('OutputIntent'),
        'S': const CosName('GTS_PDFA1'),
        'OutputConditionIdentifier': CosString.fromText(label),
        'DestOutputProfile': builder.add(CosStream(
            CosDictionary({'N': const CosInteger(3)}),
            Uint8List.fromList([1, 2, 3, 4]))),
      })
    ]),
  }))));
}
