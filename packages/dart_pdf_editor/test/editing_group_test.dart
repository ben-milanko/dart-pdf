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

  test('a group resizes, flips, rotates and undoes as one object', () {
    final editing = shapes();
    addTearDown(editing.dispose);
    selectPair(editing);
    editing.groupSelectedAnnotations();
    expect(editing.selectedIsSingleGroup, isTrue);
    expect(editing.selectedGroupBounds, const PdfRect(50, 700, 300, 750));
    expect(editing.canResizeSelected, isTrue);
    expect(editing.canAlignSelected, isFalse);
    final before = editing.revisionCount;
    editing.resizeSelected(const PdfRect(50, 700, 550, 800));
    expect(editing.revisionCount, before + 1);
    final a = editing.pageAt(0).annotations;
    expect(a[0].rect, const PdfRect(50, 700, 250, 800));
    expect(a[1].rect, const PdfRect(350, 700, 550, 800));
    expect(a[2].rect, rectC);
    expect(editing.selectedIsSingleGroup, isTrue);
    editing.undo();
    editing.selectAnnotation(0, 0);
    editing.resizeSelected(const PdfRect(50, 700, 300, 750), flipX: true);
    expect(editing.pageAt(0).annotations[0].rect,
        const PdfRect(200, 700, 300, 750));
    editing.rotateSelected(90);
    expect(editing.selectedGroupBounds!.width, closeTo(50, 0.01));
    expect(editing.selectedGroupBounds!.height, closeTo(250, 0.01));
    expect(PdfAnnotationGroups.ofPage(editing.pageAt(0)).slotsFor(0), [0, 1]);
  });

  test('grouped callout leaders move with the whole group', () {
    final editing = PdfEditingController(buildMultiPagePdf(1))
      ..addCallout(0, const PdfRect(300, 600, 460, 660), 'Detail', (120, 500))
      ..addRectangle(0, rectA);
    addTearDown(editing.dispose);
    selectPair(editing);
    editing.groupSelectedAnnotations();
    final tip = editing.pageAt(0).annotations.first.calloutLine!.first;
    editing.moveSelected(20, 30);
    final moved = editing.pageAt(0).annotations.first.calloutLine!.first;
    expect(moved.$1, closeTo(tip.$1 + 20, 0.01));
    expect(moved.$2, closeTo(tip.$2 + 30, 0.01));
    final from = editing.selectedGroupBounds!;
    final box = editing.pageAt(0).annotations.first.calloutBox!;
    editing.resizeSelected(PdfRect(from.left, from.bottom,
        from.left + from.width * 2, from.bottom + from.height * 2));
    final expected = PdfRect(
        from.left + (box.left - from.left) * 2,
        from.bottom + (box.bottom - from.bottom) * 2,
        from.left + (box.right - from.left) * 2,
        from.bottom + (box.top - from.bottom) * 2);
    expect(editing.pageAt(0).annotations.first.calloutBox, expected);
    editing.ungroupSelectedAnnotations();
    editing.selectAnnotation(0, 0);
    editing.restyleSelectedCalloutLeader(width: 7);
    final actual = editing.selectedAnnotation!.calloutBox!;
    expect(actual.left, closeTo(expected.left, 0.01));
    expect(actual.top, closeTo(expected.top, 0.01));
  });

  test('formatting a resized group retains the group artwork transform', () {
    final editing = PdfEditingController(buildMultiPagePdf(1))
      ..addFreeText(0, rectA, 'First')
      ..addFreeText(0, rectB, 'Second');
    addTearDown(editing.dispose);
    selectPair(editing);
    editing.groupSelectedAnnotations();
    editing.resizeSelected(const PdfRect(50, 700, 550, 800));
    final rects = [for (final a in editing.pageAt(0).annotations) a.rect];
    editing.toggleSelectedTextFormatting(PdfTextFormatting.bold);
    expect([for (final a in editing.pageAt(0).annotations) a.rect], rects);
    expect(
        editing
            .pageAt(0)
            .annotations
            .every((a) => a.freeTextStyle!.fontName.contains('Bold')),
        isTrue);
    for (final a in editing.pageAt(0).annotations) {
      final bbox = pdfRectFrom(
          editing.document.cos, a.normalAppearance!.dictionary['BBox'])!;
      expect(a.rect.width / bbox.width, closeTo(2, 0.01));
      expect(a.rect.height / bbox.height, closeTo(2, 0.01));
    }
    expect(editing.selectedIsSingleGroup, isTrue);
    editing.ungroupSelectedAnnotations();
    editing.selectAnnotation(0, 0);
    editing.toggleSelectedTextFormatting(PdfTextFormatting.italic);
    final selected = editing.selectedAnnotation!;
    final bbox = pdfRectFrom(
        editing.document.cos, selected.normalAppearance!.dictionary['BBox'])!;
    expect(selected.rect, rects.first);
    expect(selected.rect.width / bbox.width, closeTo(2, 0.01));
    editing.restyleSelected(opacity: 0.5);
    final restyled = editing.selectedAnnotation!;
    final styledBox = pdfRectFrom(
        editing.document.cos, restyled.normalAppearance!.dictionary['BBox'])!;
    expect(restyled.rect, rects.first);
    expect(restyled.rect.width / styledBox.width, closeTo(2, 0.01));
    expect(restyled.appearanceOpacity, closeTo(0.5, 0.01));
  });

  test('alignment and page moves treat a group as one object', () {
    final editing = shapes();
    addTearDown(editing.dispose);
    selectPair(editing);
    editing.groupSelectedAnnotations();
    editing.selectAnnotationSlots([(0, 0), (0, 2)]);
    editing.alignSelected(PdfAlignment.left);
    final a = editing.pageAt(0).annotations;
    expect(a[1].rect.left - a[0].rect.left, 150);
    expect(a[2].rect.left, a[0].rect.left);
    editing.selectAnnotation(0, 0);
    expect(editing.moveSelectedToPage(1, 20, -100), isTrue);
    expect(editing.pageAt(0).annotations, hasLength(1));
    expect(editing.pageAt(1).annotations, hasLength(3));
    expect(editing.selectedIsSingleGroup, isTrue);
    expect(PdfAnnotationGroups.ofPage(editing.pageAt(1)).slotsFor(1), [1, 2]);
    editing.undo();
    expect(PdfAnnotationGroups.ofPage(editing.pageAt(0)).slotsFor(0), [0, 1]);
  });

  test('individual rotation rotates each selected group as a unit', () {
    final editing = shapes();
    addTearDown(editing.dispose);
    selectPair(editing);
    editing.groupSelectedAnnotations();
    editing.selectAnnotationSlots([(0, 0), (0, 2)]);
    editing.rotateSelected(90,
        mode: PdfAnnotationRotationMode.individualCenters);
    final a = editing.pageAt(0).annotations;
    final cx0 = (a[0].rect.left + a[0].rect.right) / 2;
    final cx1 = (a[1].rect.left + a[1].rect.right) / 2;
    final cy0 = (a[0].rect.bottom + a[0].rect.top) / 2;
    final cy1 = (a[1].rect.bottom + a[1].rect.top) / 2;
    expect(cx0, closeTo(cx1, 0.01));
    expect(cy1 - cy0, closeTo(150, 0.01));
    expect((a[2].rect.left + a[2].rect.right) / 2, 400);
  });

  testWidgets('group selection has one box and shared resize/rotate handles',
      (tester) async {
    final editing = shapes();
    addTearDown(editing.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ListenableBuilder(
                listenable: editing,
                builder: (context, _) => PdfViewer(
                    document: editing.document,
                    editing: editing,
                    initialFit: PdfViewerFit.width)))));
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    selectPair(editing);
    editing.groupSelectedAnnotations();
    await tester.pumpAndSettle();
    dynamic painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.painter)
        .firstWhere(
            (p) => p.runtimeType.toString() == '_EditingPreviewPainter');
    expect(painter.extraSelectionRects, isEmpty);
    expect(painter.showHandles, isTrue);
    expect(painter.showRotateHandle, isTrue);
    const scale = 800 / 612;
    Offset point(double x, double y) => Offset(x * scale, (792 - y) * scale);
    // The empty gap between the members belongs to the group selection.
    await tester.dragFrom(point(175, 725), const Offset(20, 10),
        kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    final bounds = editing.selectedGroupBounds!;
    final revision = editing.revisionCount;
    await tester.dragFrom(
        point(bounds.right, bounds.top), const Offset(100, -30),
        kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(editing.revisionCount, revision + 1);
    expect(editing.pageAt(0).annotations[0].rect.width, greaterThan(100));
    expect(editing.pageAt(0).annotations[1].rect.width,
        closeTo(editing.pageAt(0).annotations[0].rect.width, 0.01));
    final group = editing.selectedGroupBounds!;
    final center =
        point((group.left + group.right) / 2, (group.bottom + group.top) / 2);
    final knob = Offset(center.dx, point(0, group.top).dy - 22);
    final rotate =
        await tester.startGesture(knob, kind: PointerDeviceKind.mouse);
    await rotate.moveTo(center + Offset(group.height * scale / 2 + 22, 0));
    await tester.pump();
    await rotate.up();
    await tester.pumpAndSettle();
    expect(editing.pageAt(0).annotations.first.appearanceRotation.abs(),
        closeTo(1.5708, 0.03));
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
