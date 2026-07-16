// The controller's annotation sync surface: the change feed
// (annotationChanges - per-revision /NM-keyed diffs across edits, undo,
// and redo), remote replay (applyRemoteChange, echo-free), and the
// onboarding helpers (ensureAnnotationNames, annotationBaseline,
// findAnnotationByName). Two controllers piped together stand in for two
// devices behind a store like Firestore.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// Collects every batch the controller emits; remember to drain the
  /// microtask queue (broadcast streams deliver asynchronously).
  (List<List<PdfAnnotationChange>>, StreamSubscription) listen(
      PdfEditingController editing) {
    final batches = <List<PdfAnnotationChange>>[];
    final sub = editing.annotationChanges.listen(batches.add);
    addTearDown(sub.cancel);
    return (batches, sub);
  }

  PdfAnnotationChange remoteRectangle({bool locked = false}) {
    final source = PdfEditingController(buildClassicPdf());
    try {
      source.addRectangle(0, const PdfRect(100, 600, 200, 700));
      if (locked) {
        final annotation = source.annotationAt(0, 0)!;
        source.apply(
          (editor) => editor.setAnnotationFlags(0, annotation, 128),
        );
      }
      return source.annotationBaseline().single;
    } finally {
      source.dispose();
    }
  }

  group('change feed', () {
    test('create, modify, delete each emit one named change', () async {
      final editing = PdfEditingController(buildClassicPdf());
      addTearDown(editing.dispose);
      final (batches, _) = listen(editing);

      editing.addRectangle(0, const PdfRect(100, 600, 200, 700));
      await pumpEventQueue();
      expect(batches, hasLength(1));
      final created = batches[0].single;
      expect(created.kind, PdfAnnotationChangeKind.created);
      expect(created.pageIndex, 0);
      expect(created.name, isNotNull);
      expect(created.snapshot!.subtype, 'Square');

      editing.selectAnnotation(0, 0);
      editing.moveSelected(24, 0);
      await pumpEventQueue();
      expect(batches, hasLength(2));
      final modified = batches[1].single;
      expect(modified.kind, PdfAnnotationChangeKind.modified);
      expect(modified.name, created.name);
      expect(modified.snapshot!.rect.left, closeTo(124, 1e-6));

      editing.deleteSelected();
      await pumpEventQueue();
      expect(batches, hasLength(3));
      final removed = batches[2].single;
      expect(removed.kind, PdfAnnotationChangeKind.removed);
      expect(removed.name, created.name);
      expect(removed.snapshot, isNull);
    });

    test('undo emits the inverse, redo re-emits', () async {
      final editing = PdfEditingController(buildClassicPdf());
      addTearDown(editing.dispose);
      final (batches, _) = listen(editing);

      editing.addRectangle(0, const PdfRect(100, 600, 200, 700));
      await pumpEventQueue();
      final name = batches[0].single.name;

      editing.undo();
      await pumpEventQueue();
      expect(batches, hasLength(2));
      expect(batches[1].single.kind, PdfAnnotationChangeKind.removed);
      expect(batches[1].single.name, name);

      editing.redo();
      await pumpEventQueue();
      expect(batches, hasLength(3));
      expect(batches[2].single.kind, PdfAnnotationChangeKind.created);
      expect(batches[2].single.name, name);
    });

    test('a text rewrite keeps the identity: one modification, no churn',
        () async {
      final editing = PdfEditingController(buildClassicPdf());
      addTearDown(editing.dispose);
      editing.addFreeText(0, const PdfRect(100, 600, 280, 660), 'before');
      editing.selectAnnotation(0, 0);
      final name = editing.selectedAnnotation!.name;
      expect(name, isNotNull);

      final (batches, _) = listen(editing);
      editing.setSelectedText('after');
      await pumpEventQueue();
      // remove + re-add under the same /NM must read as a modification
      expect(batches, hasLength(1));
      final change = batches[0].single;
      expect(change.kind, PdfAnnotationChangeKind.modified);
      expect(change.name, name);
    });

    test('metadata edits (author) reach the feed despite repainting nothing',
        () async {
      final editing = PdfEditingController(buildClassicPdf());
      addTearDown(editing.dispose);
      editing.addRectangle(0, const PdfRect(100, 600, 200, 700));
      editing.selectAnnotation(0, 0);

      final (batches, _) = listen(editing);
      expect(editing.setSelectedAuthor('Ben'), isTrue);
      await pumpEventQueue();
      expect(batches, hasLength(1));
      expect(batches[0].single.kind, PdfAnnotationChangeKind.modified);
    });
  });

  group('remote replay', () {
    test('a remote locked creation is a non-crossable undo checkpoint', () {
      final editing = PdfEditingController(buildClassicPdf());
      addTearDown(editing.dispose);
      final change = remoteRectangle(locked: true);

      expect(editing.applyRemoteChange(change), isTrue);
      expect(editing.canUndo, isFalse);
      final length = editing.bytes.length;

      editing.undo();

      expect(editing.bytes.length, length);
      final annotation = editing.document.page(0).annotations.single;
      expect(annotation.name, change.name);
      expect(annotation.isLocked, isTrue);
    });

    test('a local edit after a remote change undoes to the checkpoint', () {
      final editing = PdfEditingController(buildClassicPdf());
      addTearDown(editing.dispose);
      final remote = remoteRectangle(locked: true);
      editing.applyRemoteChange(remote);

      editing.addEllipse(0, const PdfRect(300, 600, 400, 700));
      expect(editing.canUndo, isTrue);
      expect(editing.document.page(0).annotations, hasLength(2));

      editing.undo();
      expect(editing.canUndo, isFalse);
      expect(editing.canRedo, isTrue);
      expect(editing.document.page(0).annotations.single.name, remote.name);

      editing.redo();
      expect(editing.document.page(0).annotations, hasLength(2));
      expect(
        editing.document.page(0).annotations.first.name,
        remote.name,
      );
    });

    test('a later remote change seals older local history in place', () {
      final editing = PdfEditingController(buildClassicPdf());
      addTearDown(editing.dispose);
      editing.addEllipse(0, const PdfRect(300, 600, 400, 700));
      final localName = editing.document.page(0).annotations.single.name;
      final remote = remoteRectangle(locked: true);

      expect(editing.applyRemoteChange(remote), isTrue);
      expect(editing.canUndo, isFalse,
          reason: 'history before a remote checkpoint is sealed');

      editing.undo();
      final annotations = editing.document.page(0).annotations;
      expect(annotations, hasLength(2));
      expect(annotations.map((annotation) => annotation.name),
          containsAll([localName, remote.name]));
    });

    test('applyRemoteChange lands the annotation and never echoes', () async {
      // device A authors; device B replays
      final a = PdfEditingController(buildClassicPdf());
      final b = PdfEditingController(buildClassicPdf());
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      final (fromA, _) = listen(a);
      final (fromB, _) = listen(b);

      a.addInkStroke(0, const [(100, 100), (160, 160), (220, 100)]);
      a.finishInk();
      await pumpEventQueue();
      expect(fromA, hasLength(1));

      // the wire format: JSON string, as a store would hold it
      final wire = jsonEncode(fromA[0].single.snapshot!.toJson());
      final replayed = PdfAnnotationSnapshot.fromJson(
          jsonDecode(wire) as Map<String, dynamic>);
      expect(
          b.applyRemoteChange(PdfAnnotationChange(
            kind: PdfAnnotationChangeKind.created,
            pageIndex: 0,
            name: replayed.name,
            snapshot: replayed,
          )),
          isTrue);
      await pumpEventQueue();

      expect(fromB, isEmpty, reason: 'remote applies must not echo');
      final arrived = b.document.page(0).annotations.single;
      expect(arrived.subtype, 'Ink');
      expect(arrived.name, fromA[0].single.name);
      expect(b.findAnnotationByName(arrived.name!), isNotNull);
    });

    test('a remote modification replaces; a remote removal removes', () async {
      final a = PdfEditingController(buildClassicPdf());
      final b = PdfEditingController(buildClassicPdf());
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      final (fromA, _) = listen(a);
      final (fromB, _) = listen(b);

      a.addRectangle(0, const PdfRect(100, 600, 200, 700));
      a.selectAnnotation(0, 0);
      a.moveSelected(24, 0);
      a.deleteSelected();
      await pumpEventQueue();
      expect(fromA, hasLength(3));

      for (final batch in fromA) {
        for (final change in batch) {
          expect(b.applyRemoteChange(change), isTrue);
        }
      }
      await pumpEventQueue();
      expect(b.document.page(0).annotations, isEmpty);
      expect(fromB, isEmpty);

      // replaying only create + modify (no removal) leaves the moved box
      final c = PdfEditingController(buildClassicPdf());
      addTearDown(c.dispose);
      c.applyRemoteChange(fromA[0].single);
      c.applyRemoteChange(fromA[1].single);
      final annotation = c.document.page(0).annotations.single;
      expect(annotation.rect.left, closeTo(124, 1e-6));
    });

    test('removing an unknown name is a no-op without a revision', () {
      final editing = PdfEditingController(buildClassicPdf());
      addTearDown(editing.dispose);
      expect(
          editing.applyRemoteChange(const PdfAnnotationChange(
            kind: PdfAnnotationChangeKind.removed,
            pageIndex: 0,
            name: 'nobody',
          )),
          isFalse);
      expect(editing.isModified, isFalse);
    });

    test('two devices converge through a piped store', () async {
      final a = PdfEditingController(buildMultiPagePdf(2));
      final b = PdfEditingController(buildMultiPagePdf(2));
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      // pipe both ways, like two Firestore listeners
      final subA = a.annotationChanges.listen((batch) {
        for (final change in batch) {
          b.applyRemoteChange(change);
        }
      });
      final subB = b.annotationChanges.listen((batch) {
        for (final change in batch) {
          a.applyRemoteChange(change);
        }
      });
      addTearDown(subA.cancel);
      addTearDown(subB.cancel);

      a.addRectangle(0, const PdfRect(100, 600, 200, 700));
      await pumpEventQueue();
      b.addEllipse(1, const PdfRect(50, 50, 120, 120));
      await pumpEventQueue();

      for (final editing in [a, b]) {
        expect(editing.document.page(0).annotations, hasLength(1));
        expect(editing.document.page(1).annotations, hasLength(1));
      }
      // identity matches across devices
      expect(a.document.page(0).annotations.single.name,
          b.document.page(0).annotations.single.name);
      expect(a.document.page(1).annotations.single.name,
          b.document.page(1).annotations.single.name);
    });
  });

  group('onboarding', () {
    test('ensureAnnotationNames + annotationBaseline seed a legacy document',
        () async {
      // a "legacy" file: an annotation whose /NM was stripped
      final seedController = PdfEditingController(buildClassicPdf())
        ..addRectangle(0, const PdfRect(100, 600, 200, 700));
      final stripped = PdfEditor(PdfDocument.open(seedController.bytes));
      stripped.setAnnotationName(
          0, stripped.document.page(0).annotations.single, null);
      final legacyBytes = stripped.save();
      seedController.dispose();

      final editing = PdfEditingController(legacyBytes);
      addTearDown(editing.dispose);
      final (batches, _) = listen(editing);

      expect(editing.annotationBaseline(), isEmpty,
          reason: 'anonymous annotations cannot join sync yet');
      expect(editing.ensureAnnotationNames(), 1);
      await pumpEventQueue();
      expect(batches, isEmpty, reason: 'naming is identity, not an edit');

      final baseline = editing.annotationBaseline();
      expect(baseline, hasLength(1));
      expect(baseline.single.kind, PdfAnnotationChangeKind.created);
      expect(baseline.single.name, isNotNull);
      expect(baseline.single.snapshot!.subtype, 'Square');

      // the baseline replays on a fresh device
      final other = PdfEditingController(buildClassicPdf());
      addTearDown(other.dispose);
      expect(other.applyRemoteChange(baseline.single), isTrue);
      expect(
          other.document.page(0).annotations.single.name, baseline.single.name);
    });
  });
}
