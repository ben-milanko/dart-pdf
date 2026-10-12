import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

const rectA = PdfRect(50, 700, 150, 750);
const rectB = PdfRect(200, 700, 300, 750);
const rectC = PdfRect(350, 700, 450, 750);

PdfEditingController shapes() => PdfEditingController(buildMultiPagePdf(2))
  ..addRectangle(0, rectA)
  ..addEllipse(0, rectB)
  ..addRectangle(0, rectC)
  ..addRectangle(1, rectA);

void selectPair(PdfEditingController editing) =>
    editing.selectAnnotationSlots([(0, 0), (0, 1)]);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PdfAnnotationSnapshotClipboard.instance.clear();
    PdfSnapshotClipboard.instance.clear();
  });

  test('group and ungroup are single revisions and persist through reopen', () {
    final editing = shapes();
    addTearDown(editing.dispose);
    selectPair(editing);
    final before = editing.revisionCount;
    expect(editing.canGroupSelectedAnnotations, isTrue);
    expect(editing.groupSelectedAnnotations(), isTrue);
    expect(editing.revisionCount, before + 1);
    expect(editing.canGroupSelectedAnnotations, isFalse);
    expect(editing.canUngroupSelectedAnnotations, isTrue);
    expect(editing.groupSelectedAnnotations(), isFalse);
    final reopened = PdfEditingController(editing.bytes);
    addTearDown(reopened.dispose);
    reopened.selectAnnotation(0, 1);
    expect(reopened.selectedAnnotationSlots.toSet(), {(0, 0), (0, 1)});

    editing.undo();
    editing.selectAnnotation(0, 1);
    expect(editing.selectedAnnotationSlots, [(0, 1)]);
    editing.redo();
    editing.selectAnnotation(0, 1);
    expect(editing.selectedAnnotationSlots.toSet(), {(0, 0), (0, 1)});
    expect(editing.ungroupSelectedAnnotations(), isTrue);
    expect(editing.revisionCount, before + 2);
    expect(editing.selectedAnnotationSlots.toSet(), {(0, 0), (0, 1)});
    editing.selectAnnotation(0, 1);
    expect(editing.selectedAnnotationSlots, [(0, 1)]);
    editing.undo();
    editing.selectAnnotation(0, 0);
    expect(editing.selectedAnnotationSlots.toSet(), {(0, 0), (0, 1)});
    editing.redo();
    editing.selectAnnotation(0, 0);
    expect(editing.selectedAnnotationSlots, [(0, 0)]);
  });

  test('click, modifier selection, marquee and sidebar range expand groups',
      () {
    final editing = shapes();
    addTearDown(editing.dispose);
    selectPair(editing);
    editing.groupSelectedAnnotations();
    editing.clearAnnotationSelection();
    editing.selectAnnotationAt(0, 100, 725);
    expect(editing.selectedAnnotationSlots.toSet(), {(0, 0), (0, 1)});
    expect(editing.selectedAnnotationSlot, (0, 0));
    editing.selectAnnotationAt(0, 250, 725, toggle: true);
    expect(editing.hasAnnotationSelection, isFalse);
    editing.selectAnnotation(0, 2);
    editing.toggleAnnotationSelection(0, 1);
    expect(editing.selectedAnnotationSlots.toSet(), {(0, 0), (0, 1), (0, 2)});
    editing.toggleAnnotationSelection(0, 0);
    expect(editing.selectedAnnotationSlots, [(0, 2)]);
    expect(editing.selectAnnotationsIn(0, const PdfRect(90, 710, 110, 730)), 2);
    expect(editing.selectedAnnotationSlots.toSet(), {(0, 0), (0, 1)});
    editing.selectAnnotationSlots([(0, 1)]);
    expect(editing.selectedAnnotationSlots.toSet(), {(0, 0), (0, 1)});
  });

  test('moving and deleting a selected member operate on the entire group', () {
    final editing = shapes();
    addTearDown(editing.dispose);
    selectPair(editing);
    editing.groupSelectedAnnotations();
    editing.selectAnnotation(0, 1);
    editing.moveSelected(15, -20);
    final a = editing.pageAt(0).annotations;
    expect(a[0].rect, const PdfRect(65, 680, 165, 730));
    expect(a[1].rect, const PdfRect(215, 680, 315, 730));
    expect(a[2].rect, rectC);
    editing.deleteSelected();
    expect(editing.pageAt(0).annotations.single.rect, rectC);
    editing.undo();
    editing.selectAnnotation(0, 0);
    expect(editing.selectedAnnotationSlots.toSet(), {(0, 0), (0, 1)});
  });

  test('grouping merges an existing group with another selected annotation',
      () {
    final editing = shapes();
    addTearDown(editing.dispose);
    selectPair(editing);
    editing.groupSelectedAnnotations();
    editing.toggleAnnotationSelection(0, 2);
    expect(editing.groupSelectedAnnotations(), isTrue);
    editing.selectAnnotation(0, 2);
    expect(editing.selectedAnnotationSlots.toSet(), {(0, 0), (0, 1), (0, 2)});
    expect(editing.canGroupSelectedAnnotations, isFalse);
    expect(editing.ungroupSelectedAnnotations(), isTrue);
    expect(PdfAnnotationGroups.ofPage(editing.pageAt(0)).slotsFor(1), [1]);
  });

  test('grouping rejects single and cross-page selections', () {
    final editing = shapes();
    addTearDown(editing.dispose);
    editing.selectAnnotation(0, 0);
    expect(editing.groupSelectedAnnotations(), isFalse);
    editing.toggleAnnotationSelection(1, 0);
    final before = editing.document;
    expect(editing.groupSelectedAnnotations(), isFalse);
    expect(editing.document, same(before));
  });

  test('a locked or host-protected member protects the whole group', () {
    final editing = shapes();
    addTearDown(editing.dispose);
    selectPair(editing);
    editing.groupSelectedAnnotations();
    editing.setAnnotationLocked(0, 1, true);
    expect(editing.hasAnnotationSelection, isFalse);
    expect(editing.selectAnnotation(0, 0), isFalse);
    expect(editing.selectAnnotationAt(0, 100, 725), isFalse);
    expect(editing.selectAnnotationsIn(0, rectA), 0);
    editing.setAnnotationLocked(0, 1, false);
    editing.selectAnnotation(0, 0);
    final protectedName = editing.pageAt(0).annotations[1].name;
    editing.canEditAnnotation = (a) => a.name != protectedName;
    expect(editing.hasAnnotationSelection, isFalse);
    expect(editing.selectAnnotation(0, 0), isFalse);
  });

  test('copy/paste across documents makes independent groups with fresh names',
      () {
    final source = shapes();
    addTearDown(source.dispose);
    selectPair(source);
    source.groupSelectedAnnotations();
    final names =
        source.pageAt(0).annotations.take(2).map((a) => a.name).toSet();
    expect(source.copySelectedAnnotations(), 2);
    final target = PdfEditingController(buildMultiPagePdf(1));
    addTearDown(target.dispose);
    expect(target.pasteAnnotations(0), isTrue);
    expect(target.pasteAnnotations(0), isTrue);
    final groups = PdfAnnotationGroups.ofPage(target.pageAt(0));
    expect(groups.slotsFor(0), [0, 1]);
    expect(groups.slotsFor(2), [2, 3]);
    expect(target.pageAt(0).annotations.any((a) => names.contains(a.name)),
        isFalse);
    target.selectAnnotation(0, 2);
    target.ungroupSelectedAnnotations();
    expect(PdfAnnotationGroups.ofPage(target.pageAt(0)).slotsFor(0), [0, 1]);
    expect(PdfAnnotationGroups.ofPage(source.pageAt(0)).slotsFor(0), [0, 1]);
  });

  test('apply to pages preserves groups in one revision', () {
    final editing = shapes();
    addTearDown(editing.dispose);
    selectPair(editing);
    editing.groupSelectedAnnotations();
    expect(editing.applySelectedAnnotationsToPages([0, 1]), 2);
    expect(PdfAnnotationGroups.ofPage(editing.pageAt(1)).slotsFor(1), [1, 2]);
    editing.undo();
    expect(editing.pageAt(1).annotations, hasLength(1));
    expect(PdfAnnotationGroups.ofPage(editing.pageAt(0)).slotsFor(0), [0, 1]);
  });

  testWidgets('right-click Group and Ungroup act on the existing selection',
      (tester) async {
    final editing = PdfEditingController(buildMultiPagePdf(1));
    addTearDown(editing.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: editing,
          builder: (context, _) => PdfViewer(
            document: editing.document,
            editing: editing,
            initialFit: PdfViewerFit.width,
          ),
        ),
      ),
    ));
    await tester.pump();
    editing
      ..addRectangle(0, rectA)
      ..addEllipse(0, rectB)
      ..addRectangle(0, rectC);
    await tester.pump();
    selectPair(editing);
    await tester.pump();
    const point = Offset(100 * 800 / 612, (792 - 725) * 800 / 612);
    Future<void> rightClick() async {
      await tester.tapAt(point,
          kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
    }

    await rightClick();
    final group = find.byKey(const ValueKey('pdf-annot-menu-group'));
    final ungroup = find.byKey(const ValueKey('pdf-annot-menu-ungroup'));
    expect(group, findsOneWidget);
    expect(ungroup, findsNothing);
    await tester.tap(group);
    await tester.pumpAndSettle();
    editing.clearAnnotationSelection();
    await tester.pump();
    // Starting a drag on one member selects and moves the group together.
    await tester.dragFrom(point, const Offset(30, 20),
        kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    final moved = editing.pageAt(0).annotations;
    expect(moved[0].rect.left, greaterThan(rectA.left));
    expect(moved[0].rect.left - rectA.left,
        closeTo(moved[1].rect.left - rectB.left, 0.01));
    expect(moved[0].rect.bottom - rectA.bottom,
        closeTo(moved[1].rect.bottom - rectB.bottom, 0.01));
    editing.clearAnnotationSelection();
    await tester.pump();
    await rightClick();
    expect(editing.selectedAnnotationSlots.toSet(), {(0, 0), (0, 1)});
    expect(ungroup, findsOneWidget);
    expect((tester.widget(group) as PopupMenuItem).enabled, isFalse);
    await tester.tap(ungroup);
    await tester.pumpAndSettle();
    editing.clearAnnotationSelection();
    await tester.pump();
    await tester.tapAt(point, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(editing.selectedAnnotationSlots, [(0, 0)]);
  });
}
