import 'dart:convert';
import 'dart:math' as math;

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

PdfDocument shapes() {
  final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(2)))
    ..addSquare(0, const PdfRect(50, 700, 150, 750), contents: 'square')
    ..addCircle(0, const PdfRect(200, 700, 300, 750), contents: 'circle')
    ..addSquare(0, const PdfRect(350, 700, 450, 750))
    ..addSquare(0, const PdfRect(500, 700, 550, 750))
    ..addSquare(1, const PdfRect(50, 700, 150, 750));
  return PdfDocument.open(editor.save());
}

PdfDocument edited(PdfDocument doc, void Function(PdfEditor) edit) {
  final editor = PdfEditor(doc);
  edit(editor);
  return PdfDocument.open(editor.save());
}

void main() {
  test('group frame corners follow rigid transforms without expanding', () {
    var doc = shapes();
    doc = edited(
        doc, (e) => e.groupAnnotations(0, doc.page(0).annotations.take(3)));
    final original =
        PdfAnnotationGroups.ofPage(doc.page(0)).selectionQuadFor(1)!;
    expect(original,
        [(50.0, 700.0), (450.0, 700.0), (450.0, 750.0), (50.0, 750.0)]);
    var transform = PdfMatrix.identity;
    for (final degrees in [37.0, 41.0, -78.0]) {
      final angle = degrees * math.pi / 180;
      final c = math.cos(angle), s = math.sin(angle);
      final turn = PdfMatrix(
          c, s, -s, c, 250 - c * 250 + s * 725, 725 - s * 250 - c * 725);
      transform = transform.concat(turn);
      doc = edited(
          doc,
          (e) =>
              e.transformAnnotations(0, doc.page(0).annotations.take(3), turn));
      final groups = PdfAnnotationGroups.ofPage(doc.page(0));
      for (final member in [0, 1, 2]) {
        final actual = groups.selectionQuadFor(member)!;
        for (var i = 0; i < 4; i++) {
          final expected = transform.apply(original[i].$1, original[i].$2);
          expect(actual[i].$1, closeTo(expected.$1, 0.001));
          expect(actual[i].$2, closeTo(expected.$2, 0.001));
        }
      }
      expect(groups.selectionQuadFor(3), isNull);
      expect(groups.selectionQuadFor(-1), isNull);
    }
    // Foreign groups without appearances still have a usable square-to-page
    // frame; malformed optional orientation metadata falls back to that frame.
    for (final a in doc.page(0).annotations.take(3)) {
      a.dict.entries.remove('AP');
      a.dict[kPdfAnnotationGroupRotationKey] = const CosName('invalid');
    }
    final foreign = PdfAnnotationGroups.ofPage(doc.page(0));
    expect(foreign.rotationFor(0), 0);
    final quad = foreign.selectionQuadFor(0)!;
    expect(quad[0].$1, closeTo(50, 0.001));
    expect(quad[0].$2, closeTo(700, 0.001));
    expect(quad[2].$1, closeTo(450, 0.001));
    expect(quad[2].$2, closeTo(750, 0.001));
  });

  test('group orientation survives leader removal and resets when merged', () {
    var doc = shapes();
    doc = edited(
        doc, (e) => e.groupAnnotations(0, doc.page(0).annotations.take(3)));
    const angle = 37 * math.pi / 180;
    doc = edited(
        doc,
        (e) => e.transformAnnotations(
            0,
            doc.page(0).annotations.take(3),
            PdfMatrix(math.cos(angle), math.sin(angle), -math.sin(angle),
                math.cos(angle), 400, 0)));
    doc = edited(
        doc, (e) => e.removeAnnotation(0, doc.page(0).annotations.first));
    expect(PdfAnnotationGroups.ofPage(doc.page(0)).rotationFor(0),
        closeTo(angle, 0.00001));
    doc = edited(doc, (e) => e.groupAnnotations(0, doc.page(0).annotations));
    expect(PdfAnnotationGroups.ofPage(doc.page(0)).rotationFor(0), 0);
    doc = edited(doc, (e) => e.ungroupAnnotations(0, doc.page(0).annotations));
    expect(
        doc
            .page(0)
            .annotations
            .every((a) => a.dict[kPdfAnnotationGroupRotationKey] == null),
        isTrue);
  });

  test('group transforms detach shared appearances and preserve point geometry',
      () {
    final seed = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)))
      ..addSquare(0, const PdfRect(50, 700, 150, 750))
      ..addSquare(0, const PdfRect(200, 700, 300, 750));
    final a = seed.document.page(0).annotations;
    a[1].dict['AP'] = a[0].dict['AP']!;
    final doc = PdfDocument.open(seed.save());
    final editor = PdfEditor(doc);
    expect(
        editor.transformAnnotations(
            0, doc.page(0).annotations, const PdfMatrix(2, 0, 0, 2, -50, -700)),
        isTrue);
    final out = PdfDocument.open(editor.save());
    final transformed = out.page(0).annotations;
    expect(transformed[0].rect, const PdfRect(50, 700, 250, 800));
    expect(transformed[1].rect, const PdfRect(350, 700, 550, 800));
    expect(
        identical(
            transformed[0].normalAppearance, transformed[1].normalAppearance),
        isFalse);
    expect(transformed[0].appearanceQuad![0].$1, 50);
    expect(transformed[1].appearanceQuad![0].$1, 350);
  });

  test('removing the leader keeps surviving members grouped', () {
    var doc = shapes();
    doc = edited(doc, (e) => e.groupAnnotations(0, doc.page(0).annotations));
    doc = edited(
        doc, (e) => e.removeAnnotation(0, doc.page(0).annotations.first));
    final a = doc.page(0).annotations;
    expect(PdfAnnotationGroups.ofPage(doc.page(0)).slotsFor(0), [0, 1, 2]);
    expect(a.first.dict['IRT'], isNull);
    expect(a[1].inReplyTo, a.first.name);
    expect(a[2].inReplyTo, a.first.name);
  });

  test('sync replacement of a group leader preserves its surviving group', () {
    var doc = shapes();
    doc = edited(doc, (e) => e.groupAnnotations(0, doc.page(0).annotations));
    final leader = doc.page(0).annotations.first;
    final snapshot =
        PdfAnnotationSnapshot.capture(doc, leader, keepName: true)!;
    doc = edited(doc, (e) => e.upsertAnnotation(0, snapshot));
    expect(PdfAnnotationGroups.ofPage(doc.page(0)).slotsFor(0), [0, 1, 2, 3]);
    for (final child in doc.page(0).annotations.take(3)) {
      expect(child.inReplyTo, leader.name);
    }
  });

  test('standard grouping and ungrouping preserve appearance, names and order',
      () {
    final doc = shapes();
    final before = doc.page(0).annotations;
    final names = [for (final a in before) a.name];
    final rects = [for (final a in before) a.rect];
    final appearances = [
      for (final a in before)
        latin1.decode(doc.cos.decodeStreamData(a.normalAppearance!)),
    ];
    final grouped = edited(doc, (e) {
      expect(e.groupAnnotations(0, before.take(2)), isTrue);
      expect(e.impact.visualPages, isEmpty);
      expect(e.impact.annotationPages, {0});
    });
    final after = grouped.page(0).annotations;
    expect(after[1].dict['IRT'], isA<CosReference>());
    expect(after[1].inReplyTo, after[0].name);
    expect(after[1].replyType, 'Group');
    expect(after[1].isReply, isFalse);
    expect(PdfAnnotationGroups.ofPage(grouped.page(0)).slotsFor(0), [0, 1]);
    expect(PdfAnnotationGroups.ofPage(grouped.page(0)).slotsFor(1), [0, 1]);
    expect(PdfAnnotationGroups.ofPage(grouped.page(0)).slotsFor(2), [2]);
    expect([for (final a in after) a.name], names);
    expect([for (final a in after) a.rect], rects);
    expect([
      for (final a in after)
        latin1.decode(grouped.cos.decodeStreamData(a.normalAppearance!)),
    ], appearances);
    // Group links must never appear as comment replies.
    expect(PdfCommentThread.forPage(grouped, 0), hasLength(4));
    expect(
        PdfCommentThread.forPage(grouped, 0)
            .every((t) => t.root.replies.isEmpty),
        isTrue);

    final ungrouped = edited(grouped, (e) {
      expect(e.ungroupAnnotations(0, [after[0]]), isTrue);
    });
    expect(PdfAnnotationGroups.ofPage(ungrouped.page(0)).slotsFor(1), [1]);
    expect(ungrouped.page(0).annotations[1].dict['IRT'], isNull);
    expect([for (final a in ungrouped.page(0).annotations) a.name], names);
  });

  test('merging includes all members of each existing group', () {
    var doc = shapes();
    doc = edited(doc, (e) {
      final a = doc.page(0).annotations;
      e.groupAnnotations(0, a.take(2));
      e.groupAnnotations(0, a.skip(2));
    });
    final a = doc.page(0).annotations;
    doc = edited(doc, (e) => e.groupAnnotations(0, [a[1], a[3]]));
    final groups = PdfAnnotationGroups.ofPage(doc.page(0));
    expect(groups.slotsFor(0), [0, 1, 2, 3]);
    final editor = PdfEditor(doc);
    expect(editor.groupAnnotations(0, [doc.page(0).annotations[3]]), isFalse);
    expect(editor.hasChanges, isFalse);
  });

  test('grouping rejects cross-page markups and comment replies', () {
    final doc = shapes();
    final editor = PdfEditor(doc);
    expect(() => editor.groupAnnotations(0, [doc.page(1).annotations.single]),
        throwsArgumentError);
    final reply = PdfAnnotation.fromDict(
        doc,
        CosDictionary({
          'Subtype': const CosName('Text'),
          'IRT': doc.cos.referenceTo(doc.page(0).annotations.first.dict)!,
        }));
    expect(pdfCanGroupAnnotation(reply), isFalse);
  });

  for (final indirectArray in [false, true]) {
    test(
        'inline leader is promoted with an ${indirectArray ? 'indirect' : 'direct'} /Annots array',
        () {
      var doc = shapes();
      final seed = CosIncrementalUpdater(doc.cos);
      final page = doc.page(0);
      final a = page.annotations;
      final array = CosArray([
        CosDictionary({...a[0].dict.entries}..remove('NM')),
        doc.cos.referenceTo(a[1].dict)!,
      ]);
      page.dict['Annots'] = indirectArray ? seed.addObject(array) : array;
      seed.markChanged(page.dict);
      doc = PdfDocument.open(seed.save());
      doc = edited(doc, (e) => e.groupAnnotations(0, doc.page(0).annotations));
      final after = doc.page(0).annotations;
      expect(doc.cos.referenceTo(after[0].dict), isNotNull);
      expect(after[0].name, isNotNull);
      expect(after[1].inReplyTo, after[0].name);
      expect(PdfAnnotationGroups.ofPage(doc.page(0)).slotsFor(0), [0, 1]);
      doc =
          edited(doc, (e) => e.ungroupAnnotations(0, doc.page(0).annotations));
      expect(
          doc.page(0).annotations.every((a) => a.dict['IRT'] == null), isTrue);
    });
  }

  test('cycles and dangling foreign group links resolve without names', () {
    final doc = shapes();
    final a = doc.page(0).annotations;
    for (var i = 0; i < 2; i++) {
      a[i].dict['IRT'] = doc.cos.referenceTo(a[1 - i].dict)!;
      a[i].dict['RT'] = const CosName('Group');
      a[i].dict.entries.remove('NM');
    }
    a[2].dict['IRT'] = const CosReference(99999, 0);
    a[2].dict['RT'] = const CosName('Group');
    final groups = PdfAnnotationGroups.ofPage(doc.page(0));
    expect(groups.slotsFor(1), [0, 1]);
    expect(groups.slotsFor(2), [2]);
    expect(groups.slotsFor(-1), isEmpty);
  });
}
