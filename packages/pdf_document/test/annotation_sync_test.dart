// The annotation sync surface: /NM identity (stamped at creation,
// preserved through rewrites), serializable snapshots, name-keyed
// upsert/remove, and pdfDiffAnnotations - the building blocks for
// syncing annotations through an external store (Firestore, a server).

import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

PdfDocument edited(PdfDocument doc, void Function(PdfEditor) edit) {
  final editor = PdfEditor(doc);
  edit(editor);
  return PdfDocument.open(editor.save());
}

void main() {
  group('/NM identity', () {
    test('every creator stamps a unique generated /NM', () {
      final doc = edited(PdfDocument.open(buildClassicPdf()), (e) {
        e
          ..addHighlight(0, [const PdfRect(10, 700, 60, 712)])
          ..addUnderline(0, [const PdfRect(10, 680, 60, 692)])
          ..addStrikeOut(0, [const PdfRect(10, 660, 60, 672)])
          ..addSquiggly(0, [const PdfRect(10, 640, 60, 652)])
          ..addInk(0, [
            [(100, 100), (150, 150)]
          ])
          ..addSquare(0, const PdfRect(200, 200, 260, 260))
          ..addCircle(0, const PdfRect(300, 200, 360, 260))
          ..addFreeText(0, const PdfRect(100, 300, 250, 340), 'Hello')
          ..addNote(0, 400, 400, 'A note')
          ..addStamp(0, const PdfRect(100, 500, 220, 540), 'DRAFT');
      });
      final names = [
        for (final annotation in doc.page(0).annotations) annotation.name
      ];
      expect(names, hasLength(10));
      expect(names, everyElement(isNotNull));
      expect(names.toSet(), hasLength(10), reason: 'names must be unique');
      // version-4 UUID shape
      expect(
          names.first,
          matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}'
              r'-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    });

    test('a passed name wins over generation', () {
      final doc = edited(
          PdfDocument.open(buildClassicPdf()),
          (e) => e.addSquare(0, const PdfRect(10, 10, 60, 60),
              name: 'sync-abc'));
      expect(doc.page(0).annotations.single.name, 'sync-abc');
    });

    test('the name survives restyle, resize, and ink slicing', () {
      var doc = edited(PdfDocument.open(buildClassicPdf()), (e) {
        e
          ..addSquare(0, const PdfRect(100, 100, 200, 200), name: 'shape-1')
          ..addInk(
              0,
              [
                [(300, 400), (400, 400)]
              ],
              strokeWidth: 4,
              name: 'ink-1');
      });

      doc = edited(doc, (e) {
        final square = doc.page(0).annotations[0];
        e.restyleAnnotation(0, square, color: 0x2196F3, strokeWidth: 6);
      });
      expect(doc.page(0).annotations[0].name, 'shape-1');

      doc = edited(doc, (e) {
        final square = doc.page(0).annotations[0];
        e.resizeAnnotation(0, square, const PdfRect(100, 100, 260, 240));
      });
      expect(doc.page(0).annotations[0].name, 'shape-1');

      doc = edited(doc, (e) {
        final ink = doc.page(0).annotations[1];
        e.sliceInk(0, ink, [(350, 400)], 5);
      });
      final sliced = doc.page(0).annotations[1];
      expect(sliced.subtype, 'Ink');
      expect(sliced.name, 'ink-1');
      expect(sliced.inkList, hasLength(2), reason: 'slice split the stroke');
    });

    test('setAnnotationName sets and removes', () {
      var doc = edited(PdfDocument.open(buildClassicPdf()),
          (e) => e.addNote(0, 100, 700, 'hi', name: 'note-1'));
      doc = edited(doc, (e) {
        e.setAnnotationName(0, doc.page(0).annotations.single, 'note-2');
      });
      expect(doc.page(0).annotations.single.name, 'note-2');
      doc = edited(doc, (e) {
        e.setAnnotationName(0, doc.page(0).annotations.single, null);
      });
      expect(doc.page(0).annotations.single.name, isNull);
    });

    test('nameAnnotations stamps only the unnamed and skips widgets/links',
        () {
      // a legacy state: markup annotations without /NM beside the
      // fixture's links and widget
      var doc = edited(PdfDocument.open(buildAnnotatedPdf()), (e) {
        e
          ..addNote(0, 100, 700, 'legacy')
          ..addSquare(0, const PdfRect(50, 50, 90, 90), name: 'kept');
      });
      doc = edited(doc, (e) {
        final note =
            doc.page(0).annotations.firstWhere((a) => a.subtype == 'Text');
        e.setAnnotationName(0, note, null);
      });

      var named = -1;
      doc = edited(doc, (e) => named = e.nameAnnotations());
      expect(named, 1, reason: 'only the stripped note needed a name');
      for (final annotation in doc.page(0).annotations) {
        if (const {'Link', 'Widget'}.contains(annotation.subtype)) {
          expect(annotation.name, isNull);
        } else {
          expect(annotation.name, isNotNull);
        }
      }
      expect(doc.page(0).annotations.where((a) => a.subtype == 'Link'),
          isNotEmpty);

      // a second run finds nothing to do
      final editor = PdfEditor(doc);
      expect(editor.nameAnnotations(), 0);
      expect(editor.hasChanges, isFalse);
    });
  });

  group('snapshot serialization', () {
    test('toJson/fromJson round-trips through a JSON string, appearance '
        'byte-identical', () {
      final doc = edited(
          PdfDocument.open(buildClassicPdf()),
          (e) => e.addInk(
                0,
                [
                  [(100, 100), (150, 160), (200, 100)]
                ],
                color: 0x6A1B9A,
                strokeWidth: 3,
                pressures: [
                  [0.2, 0.9, 0.4]
                ],
                contents: 'pressured stroke',
                author: 'Ben',
                name: 'ink-sync-1',
              ));
      final original = doc.page(0).annotations.single;
      final snapshot =
          PdfAnnotationSnapshot.capture(doc, original, keepName: true)!;
      expect(snapshot.name, 'ink-sync-1');

      // through the wire: Map → string → Map → snapshot
      final wire = jsonEncode(snapshot.toJson());
      final restored = PdfAnnotationSnapshot.fromJson(
          jsonDecode(wire) as Map<String, dynamic>);
      expect(restored.name, 'ink-sync-1');
      expect(restored.subtype, 'Ink');
      expect(restored.rect, snapshot.rect);

      // replay into a fresh copy of the base document
      final replayed = edited(PdfDocument.open(buildClassicPdf()),
          (e) => e.upsertAnnotation(0, restored));
      final arrived = replayed.page(0).annotations.single;
      expect(arrived.name, 'ink-sync-1');
      expect(arrived.author, 'Ben');
      expect(arrived.contents, 'pressured stroke');
      expect(arrived.rect, original.rect);

      Uint8List appearance(PdfDocument d, PdfAnnotation a) {
        final ap = d.cos.resolve(a.dict['AP']) as CosDictionary;
        final n = d.cos.resolve(ap['N']) as CosStream;
        return d.cos.decodeStreamData(n);
      }

      expect(appearance(replayed, arrived), appearance(doc, original),
          reason: 'the appearance must travel byte for byte');
    });

    test('fromJson rejects junk and future versions', () {
      expect(() => PdfAnnotationSnapshot.fromJson({'v': 2}),
          throwsFormatException);
      expect(
          () => PdfAnnotationSnapshot.fromJson(
              {'v': 1, 'subtype': 'Ink', 'rect': 'no', 'dict': null}),
          throwsFormatException);
    });
  });

  group('name-keyed editing', () {
    PdfDocument withSquare() => edited(
        PdfDocument.open(buildMultiPagePdf(2)),
        (e) => e.addSquare(0, const PdfRect(100, 100, 200, 200),
            strokeColor: 0xE53935, name: 'sq-1'));

    test('upsertAnnotation creates when the name is absent', () {
      final doc = withSquare();
      final snapshot = PdfAnnotationSnapshot.capture(
          doc, doc.page(0).annotations.single,
          keepName: true)!;
      final base = PdfDocument.open(buildMultiPagePdf(2));
      final out = edited(base, (e) => e.upsertAnnotation(1, snapshot));
      expect(out.page(0).annotations, isEmpty);
      expect(out.page(1).annotations.single.name, 'sq-1');
    });

    test('upsertAnnotation replaces in place of the name', () {
      final doc = withSquare();
      // a "remote" restyle: capture, mutate the snapshot's source, replay
      final restyled = edited(doc, (e) {
        e.restyleAnnotation(0, doc.page(0).annotations.single,
            color: 0x1B5E20);
      });
      final snapshot = PdfAnnotationSnapshot.capture(
          restyled, restyled.page(0).annotations.single,
          keepName: true)!;

      final out = edited(doc, (e) => e.upsertAnnotation(0, snapshot));
      final annotations = out.page(0).annotations;
      expect(annotations, hasLength(1), reason: 'replace, not duplicate');
      expect(annotations.single.name, 'sq-1');
      expect(annotations.single.color, 0x1B5E20);
    });

    test('upsertAnnotation follows a page move', () {
      final doc = withSquare();
      final snapshot = PdfAnnotationSnapshot.capture(
          doc, doc.page(0).annotations.single,
          keepName: true)!;
      // remote says the annotation now lives on page 1
      final out = edited(doc, (e) => e.upsertAnnotation(1, snapshot));
      expect(out.page(0).annotations, isEmpty);
      expect(out.page(1).annotations.single.name, 'sq-1');
    });

    test('upsertAnnotation refuses a nameless snapshot', () {
      final doc = withSquare();
      final anonymous =
          PdfAnnotationSnapshot.capture(doc, doc.page(0).annotations.single);
      expect(() => PdfEditor(doc).upsertAnnotation(0, anonymous!),
          throwsArgumentError);
    });

    test('removeAnnotationByName', () {
      final doc = withSquare();
      final out = edited(doc, (e) {
        expect(e.removeAnnotationByName('sq-1'), isTrue);
      });
      expect(out.page(0).annotations, isEmpty);
      expect(PdfEditor(out).removeAnnotationByName('sq-1'), isFalse);
    });
  });

  group('pdfDiffAnnotations', () {
    // Editing mutates the in-memory COS of the document it runs on, so
    // each diffed state opens fresh from its own bytes - exactly how the
    // editing controller hands revisions to the diff.
    Uint8List editBytes(Uint8List bytes, void Function(PdfEditor) edit) {
      final editor = PdfEditor(PdfDocument.open(bytes));
      edit(editor);
      return editor.save();
    }

    test('create, modify, remove', () {
      final baseBytes = buildClassicPdf();
      final createdBytes = editBytes(
          baseBytes,
          (e) => e.addSquare(0, const PdfRect(100, 100, 200, 200),
              name: 'sq-1'));

      var changes = pdfDiffAnnotations(PdfDocument.open(baseBytes),
          PdfDocument.open(createdBytes),
          pages: [0]);
      expect(changes, hasLength(1));
      expect(changes.single.kind, PdfAnnotationChangeKind.created);
      expect(changes.single.name, 'sq-1');
      expect(changes.single.pageIndex, 0);
      expect(changes.single.snapshot, isNotNull);

      final movedBytes = editBytes(createdBytes, (e) {
        e.moveAnnotation(0, e.document.page(0).annotations.single, 24, 0);
      });
      changes = pdfDiffAnnotations(PdfDocument.open(createdBytes),
          PdfDocument.open(movedBytes),
          pages: [0]);
      expect(changes.single.kind, PdfAnnotationChangeKind.modified);
      expect(changes.single.name, 'sq-1');
      expect(changes.single.snapshot!.rect.left, closeTo(124, 1e-6));

      final removedBytes = editBytes(movedBytes, (e) {
        e.removeAnnotation(0, e.document.page(0).annotations.single);
      });
      changes = pdfDiffAnnotations(PdfDocument.open(movedBytes),
          PdfDocument.open(removedBytes),
          pages: [0]);
      expect(changes.single.kind, PdfAnnotationChangeKind.removed);
      expect(changes.single.name, 'sq-1');
      expect(changes.single.snapshot, isNull);
    });

    test('an untouched document diffs empty', () {
      final doc = edited(PdfDocument.open(buildClassicPdf()),
          (e) => e.addNote(0, 100, 700, 'hi'));
      expect(pdfDiffAnnotations(doc, doc), isEmpty);
    });

    test('a cross-page move is a modification', () {
      final baseBytes = editBytes(buildMultiPagePdf(2),
          (e) => e.addSquare(0, const PdfRect(50, 50, 90, 90), name: 'sq-1'));
      final doc = PdfDocument.open(baseBytes);
      final snapshot = PdfAnnotationSnapshot.capture(
          doc, doc.page(0).annotations.single,
          keepName: true)!;
      final movedBytes =
          editBytes(baseBytes, (e) => e.upsertAnnotation(1, snapshot));
      final changes = pdfDiffAnnotations(
          PdfDocument.open(baseBytes), PdfDocument.open(movedBytes));
      expect(changes, hasLength(1));
      expect(changes.single.kind, PdfAnnotationChangeKind.modified);
      expect(changes.single.pageIndex, 1);
    });

    test('anonymous annotations: unchanged matches, edited splits into '
        'removed + created', () {
      var bytes = editBytes(buildClassicPdf(), (e) {
        e
          ..addNote(0, 100, 700, 'steady')
          ..addSquare(0, const PdfRect(50, 50, 90, 90));
      });
      // strip the generated names to simulate a legacy file
      bytes = editBytes(bytes, (e) {
        for (final annotation in e.document.page(0).annotations) {
          e.setAnnotationName(0, annotation, null);
        }
      });
      final movedBytes = editBytes(bytes, (e) {
        final square = e.document
            .page(0)
            .annotations
            .firstWhere((a) => a.subtype == 'Square');
        e.moveAnnotation(0, square, 10, 10);
      });
      final changes = pdfDiffAnnotations(
          PdfDocument.open(bytes), PdfDocument.open(movedBytes),
          pages: [0]);
      expect(changes, hasLength(2), reason: 'the note matched itself');
      expect(changes.map((c) => c.kind).toSet(), {
        PdfAnnotationChangeKind.created,
        PdfAnnotationChangeKind.removed,
      });
      expect(changes.map((c) => c.name), everyElement(isNull));
    });

    test('widgets and links stay out of the diff', () {
      final baseBytes = buildAcroFormPdf();
      final inkedBytes = editBytes(
          baseBytes,
          (e) => e.addInk(0, [
                [(30, 30), (60, 60)]
              ]));
      final changes = pdfDiffAnnotations(
          PdfDocument.open(baseBytes), PdfDocument.open(inkedBytes));
      expect(changes, hasLength(1));
      expect(changes.single.snapshot!.subtype, 'Ink');
    });
  });
}
