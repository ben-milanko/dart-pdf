// Per-annotation read-only enforcement: the document's own /F ReadOnly
// and Locked flags (§12.5.3) and the host's canEditAnnotation predicate
// gate every mutating path - selection, marquee, ⌘A, delete, the
// eraser, and text/contents edits.

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// Sets the /F flag word on the annotation in slot [index] of page 0.
  void flag(PdfEditingController editing, int index, int flags) {
    final annotation = editing.annotationAt(0, index)!;
    editing.apply((e) => e.setAnnotationFlags(0, annotation, flags),
        pages: const [0]);
  }

  group('/F flags', () {
    test('a Locked annotation cannot be selected or deleted', () {
      final editing = PdfEditingController(buildClassicPdf());
      addTearDown(editing.dispose);
      editing.addRectangle(0, const PdfRect(100, 600, 200, 700));
      editing.addEllipse(0, const PdfRect(300, 600, 400, 700));
      flag(editing, 0, 128); // locked

      // hit test, sidebar select, and ⌘A all skip it
      expect(editing.selectableAnnotationAt(0, 150, 650), isNull);
      expect(editing.selectAnnotation(0, 0), isFalse);
      expect(editing.selectAllAnnotationsOn(0), 1);
      expect(editing.selectedAnnotationSlots, [(0, 1)]);

      // the marquee over both finds only the unlocked one
      editing.clearAnnotationSelection();
      expect(editing.selectAnnotationsIn(0, const PdfRect(0, 0, 612, 792)), 1);

      // deletes refuse, alone and in a batch
      editing.deleteAnnotation(0, 0);
      expect(editing.pageAt(0).annotations, hasLength(2));
      editing.deleteAnnotations(const [(0, 0), (0, 1)]);
      final survivors = editing.pageAt(0).annotations;
      expect(survivors, hasLength(1));
      expect(survivors.single.subtype, 'Square');
    });

    test('ReadOnly blocks the same paths', () {
      final editing = PdfEditingController(buildClassicPdf());
      addTearDown(editing.dispose);
      editing.addRectangle(0, const PdfRect(100, 600, 200, 700));
      flag(editing, 0, 64);
      expect(editing.selectableAnnotationAt(0, 150, 650), isNull);
      expect(editing.selectAnnotation(0, 0), isFalse);
      editing.deleteAnnotation(0, 0);
      expect(editing.pageAt(0).annotations, hasLength(1));
    });

    test('the eraser skips locked ink', () {
      final editing = PdfEditingController(buildClassicPdf());
      addTearDown(editing.dispose);
      editing.addInkStroke(0, const [(100, 650), (200, 650)]);
      editing.finishInk();
      flag(editing, 0, 128);

      expect(editing.inkAnnotationAt(0, 150, 650), isNull);
      expect(editing.sliceErase(0, const [(150, 640), (150, 660)]), isFalse);
      expect(editing.pageAt(0).annotations.single.inkList, hasLength(1));
    });

    test('LockedContents blocks text edits but not moves', () {
      final editing = PdfEditingController(buildClassicPdf());
      addTearDown(editing.dispose);
      editing.addFreeText(0, const PdfRect(100, 600, 280, 660), 'fixed');
      flag(editing, 0, 512);

      expect(editing.selectAnnotation(0, 0), isTrue,
          reason: 'LockedContents still selects and moves');
      expect(editing.canEditSelectedText, isFalse);
      expect(editing.setSelectedContents('changed'), isFalse);
      expect(editing.selectedAnnotation!.contents, 'fixed');

      editing.moveSelected(24, 0);
      expect(editing.selectedAnnotation!.rect.left, closeTo(124, 1e-6));
    });
  });

  group('canEditAnnotation predicate', () {
    test('gates selection by author', () {
      final editing = PdfEditingController(buildClassicPdf());
      addTearDown(editing.dispose);
      editing.preferences.author = 'Alice';
      editing.addRectangle(0, const PdfRect(100, 600, 200, 700));
      editing.preferences.author = 'Bob';
      editing.addEllipse(0, const PdfRect(300, 600, 400, 700));

      editing.canEditAnnotation = (a) => a.author == 'Bob';
      expect(editing.selectableAnnotationAt(0, 150, 650), isNull,
          reason: "Alice's rectangle is not Bob's to edit");
      expect(editing.selectableAnnotationAt(0, 350, 650), isNotNull);
      expect(editing.selectAllAnnotationsOn(0), 1);
      expect(editing.selectedAnnotation!.author, 'Bob');

      // and the locked one survives a sweep delete
      editing.deleteAnnotations(const [(0, 0), (0, 1)]);
      expect(editing.pageAt(0).annotations.single.author, 'Alice');
    });

    test('setting the predicate drops newly ineligible selections', () {
      final editing = PdfEditingController(buildClassicPdf());
      addTearDown(editing.dispose);
      editing.preferences.author = 'Alice';
      editing.addRectangle(0, const PdfRect(100, 600, 200, 700));
      editing.preferences.author = 'Bob';
      editing.addEllipse(0, const PdfRect(300, 600, 400, 700));
      expect(editing.selectAllAnnotationsOn(0), 2);

      var notified = 0;
      editing.addListener(() => notified++);
      editing.canEditAnnotation = (a) => a.author == 'Bob';
      expect(notified, 1);
      expect(editing.selectedAnnotationSlots, [(0, 1)]);

      // clearing restores normal behavior
      editing.canEditAnnotation = null;
      expect(editing.selectAllAnnotationsOn(0), 2);
    });

    test('remote applies bypass the gate - sync is not user editing', () {
      final editing = PdfEditingController(buildClassicPdf());
      addTearDown(editing.dispose);
      editing.preferences.author = 'Alice';
      editing.addRectangle(0, const PdfRect(100, 600, 200, 700));
      editing.canEditAnnotation = (_) => false;

      // a remote removal of Alice's annotation still lands: the predicate
      // governs this user's UI, not the document's convergence
      final name = editing.pageAt(0).annotations.single.name!;
      expect(
          editing.applyRemoteChange(PdfAnnotationChange(
            kind: PdfAnnotationChangeKind.removed,
            pageIndex: 0,
            name: name,
          )),
          isTrue);
      expect(editing.pageAt(0).annotations, isEmpty);
    });
  });
}
