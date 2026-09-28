import 'dart:io';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

/// A one-page file whose catalog lists one output intent per entry of
/// [profiles], each carrying that profile as its /DestOutputProfile stream.
/// Returns the document and the profile streams' references, in order.
(PdfDocument, List<CosReference>) outputIntentDocument(
    List<(int, Uint8List)> profiles) {
  final builder = CosDocumentBuilder();
  final pages = CosDictionary();
  final pagesRef = builder.add(pages);
  final content = builder.add(CosStream(
      CosDictionary(), Uint8List.fromList('0 0 0 1 k 0 0 9 9 re f'.codeUnits)));
  final page = builder.add(CosDictionary({
    'Type': const CosName('Page'),
    'Parent': pagesRef,
    'MediaBox': CosArray([
      const CosInteger(0),
      const CosInteger(0),
      const CosInteger(200),
      const CosInteger(200),
    ]),
    'Contents': content,
  }));
  pages.entries
    ..['Type'] = const CosName('Pages')
    ..['Kids'] = CosArray([page])
    ..['Count'] = const CosInteger(1);
  final profileRefs = [
    for (final (channels, bytes) in profiles)
      builder.add(CosStream(CosDictionary({'N': CosInteger(channels)}), bytes)),
  ];
  final catalog = builder.add(CosDictionary({
    'Type': const CosName('Catalog'),
    'Pages': pagesRef,
    'OutputIntents': CosArray([
      for (final ref in profileRefs)
        CosDictionary({
          'Type': const CosName('OutputIntent'),
          'S': const CosName('GTS_PDFX'),
          'DestOutputProfile': ref,
        }),
    ]),
  }));
  return (PdfDocument.open(builder.build(root: catalog)), profileRefs);
}

/// Applies an incremental revision that replaces the catalog with the result
/// of [edit] on a copy of it.
void editCatalog(PdfDocument doc,
    void Function(CosDictionary catalog, CosIncrementalUpdater updater) edit) {
  final updater = CosIncrementalUpdater(doc.cos);
  final catalog = CosDictionary({...doc.cos.catalog.entries});
  edit(catalog, updater);
  updater.replaceObject(
      (doc.cos.trailer['Root'] as CosReference).objectNumber, catalog);
  doc.applyIncrementalUpdate(updater.save());
}

void main() {
  group('PdfColorContext.forDocument across revisions', () {
    test('an edit that leaves the output intents alone keeps the context', () {
      final (doc, _) = outputIntentDocument([(4, genericCmykIcc())]);
      final context = PdfColorContext.forDocument(doc.cos);
      expect(context.outputProfile?.channels, 4);
      for (var edit = 0; edit < 3; edit++) {
        final revision = doc.cos.revision;
        doc.applyIncrementalUpdate((PdfEditor(doc)
              ..addSquare(0, PdfRect(10.0 + edit, 10, 60, 60)))
            .save());
        expect(doc.cos.revision, greaterThan(revision));
        expect(PdfColorContext.forDocument(doc.cos), same(context));
      }
    });

    test('redefining the profile stream in place gives a new context', () {
      final (doc, refs) = outputIntentDocument([(4, genericCmykIcc())]);
      final context = PdfColorContext.forDocument(doc.cos);
      final updater = CosIncrementalUpdater(doc.cos)
        ..replaceObject(
            refs.single.objectNumber,
            CosStream(
                CosDictionary({'N': const CosInteger(1)}), genericGrayIcc()));
      doc.applyIncrementalUpdate(updater.save());
      final next = PdfColorContext.forDocument(doc.cos);
      expect(next, isNot(same(context)));
      expect(next.outputProfile?.channels, 1);
    });

    test('pointing the intent at a new stream gives a new context', () {
      final (doc, _) = outputIntentDocument([(4, genericCmykIcc())]);
      final context = PdfColorContext.forDocument(doc.cos);
      editCatalog(doc, (catalog, updater) {
        final gray = updater.addObject(CosStream(
            CosDictionary({'N': const CosInteger(1)}), genericGrayIcc()));
        catalog['OutputIntents'] = CosArray([
          CosDictionary({
            'Type': const CosName('OutputIntent'),
            'S': const CosName('GTS_PDFX'),
            'DestOutputProfile': gray,
          }),
        ]);
      });
      final next = PdfColorContext.forDocument(doc.cos);
      expect(next, isNot(same(context)));
      expect(next.outputProfile?.channels, 1);
    });

    test('removing /OutputIntents drops the profile', () {
      final (doc, _) = outputIntentDocument([(4, genericCmykIcc())]);
      final context = PdfColorContext.forDocument(doc.cos);
      editCatalog(doc, (catalog, _) => catalog.entries.remove('OutputIntents'));
      final next = PdfColorContext.forDocument(doc.cos);
      expect(next, isNot(same(context)));
      expect(next.outputProfile, isNull);
    });

    test('an unusable first intent does not mask an edit to a later one', () {
      // The first profile never parses, so the context comes from the second;
      // redefining the second must still be seen.
      final (doc, refs) = outputIntentDocument([
        (4, ascii('not a profile at all')),
        (4, genericCmykIcc()),
      ]);
      final context = PdfColorContext.forDocument(doc.cos);
      expect(context.outputProfile?.channels, 4);
      final updater = CosIncrementalUpdater(doc.cos)
        ..replaceObject(
            refs.last.objectNumber,
            CosStream(
                CosDictionary({'N': const CosInteger(1)}), genericGrayIcc()));
      doc.applyIncrementalUpdate(updater.save());
      final next = PdfColorContext.forDocument(doc.cos);
      expect(next, isNot(same(context)));
      expect(next.outputProfile?.channels, 1);
    });

    test('image-overprint substitutes survive an edit (GWG010)', () {
      // Substitutes are memoised per colour context, four per image. A
      // context replaced on every revision rebuilt them on each edit and,
      // from the fifth revision on, silently stopped overprinting the image.
      final file =
          File('../../test_corpora/ghent/1-CMYK/GWG010_CMYK_OP_x3.pdf');
      if (!file.existsSync()) {
        markTestSkipped('test_corpora/ghent not found');
        return;
      }
      final doc = PdfDocument.open(file.readAsBytesSync());
      (List<CosStream>, Uint8List) record() {
        final page = doc.page(0);
        final device = RecordingPdfDevice();
        PdfInterpreter(cos: doc.cos, device: device)
            .drawPageContent(page, page.contentBytes());
        final wire = serializeCommands(device.commands,
            cos: doc.cos,
            decodeImages: true,
            maxImagePixelRatio: 2,
            compactStateScopes: true)!;
        return ([for (final r in device.imageRequests) r.stream], wire);
      }

      final (streams, wire) = record();
      for (var edit = 0; edit < 6; edit++) {
        doc.applyIncrementalUpdate((PdfEditor(doc)
              ..addSquare(0, PdfRect(20.0 + edit, 20, 80, 80)))
            .save());
        final (nextStreams, nextWire) = record();
        expect(nextStreams.length, streams.length);
        for (var i = 0; i < streams.length; i++) {
          expect(nextStreams[i], same(streams[i]),
              reason: 'image $i after edit ${edit + 1}');
        }
        expect(nextWire, wire, reason: 'record after edit ${edit + 1}');
      }
    });
  });

  group('PdfColorContext process colours', () {
    test('memoised deviceCmyk/deviceGray equal a direct conversion', () {
      final (doc, _) = outputIntentDocument([(4, genericCmykIcc())]);
      final context = PdfColorContext.forDocument(doc.cos);
      final profile = context.outputProfile!;
      const relative = PdfRenderingIntent.relativeColorimetric;
      const samples = [
        double.nan,
        -0.5,
        -0.0,
        0.0,
        0.3,
        0.7,
        1.0,
        1.5,
      ];
      PdfColor direct(List<double> cmyk) =>
          profile.toSrgb([for (final v in cmyk) v.clamp(0.0, 1.0).toDouble()],
              intent: relative);
      for (var pass = 0; pass < 2; pass++) {
        // The second pass is served from the memo.
        for (final c in samples) {
          for (final m in samples) {
            for (final y in samples) {
              for (final k in samples) {
                expect(context.deviceCmyk(c, m, y, k), direct([c, m, y, k]),
                    reason: 'cmyk $c $m $y $k, pass $pass');
              }
            }
          }
          expect(context.deviceGray(c),
              direct([0, 0, 0, 1 - c.clamp(0.0, 1.0).toDouble()]),
              reason: 'gray $c, pass $pass');
        }
      }
      // A K-only colour and the gray that maps to the same K keep their own
      // entries and still agree with each other.
      expect(context.deviceGray(0.25), context.deviceCmyk(0, 0, 0, 0.75));
    });

    test('the memo stops learning at its cap and stays exact', () {
      final (doc, _) = outputIntentDocument([(4, genericCmykIcc())]);
      final context = PdfColorContext.forDocument(doc.cos);
      final profile = context.outputProfile!;
      for (var pass = 0; pass < 2; pass++) {
        for (var i = 0; i < 6000; i++) {
          final cmyk = [i / 6000, 0.2, 0.4, 0.1];
          expect(
              context.deviceCmyk(cmyk[0], cmyk[1], cmyk[2], cmyk[3]),
              profile.toSrgb(cmyk,
                  intent: PdfRenderingIntent.relativeColorimetric));
        }
      }
    });
  });
}
