import 'dart:math' as math;
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('callout through the controller', () {
    test('addCallout builds a FreeText callout pointing at the target', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..preferences.author = 'Ben'
        ..preferences.opacity = 0.45
        ..addCallout(
            0, const PdfRect(300, 600, 460, 660), 'Look here', (120, 500));

      final annot = editing.document.page(0).annotations.single;
      expect(annot.subtype, 'FreeText');
      expect(annot.isCallout, isTrue);
      expect(annot.contents, 'Look here');
      expect(annot.appearanceOpacity, closeTo(0.45, 1e-9));
      final line = annot.calloutLine!;
      expect(line.first, (120.0, 500.0), reason: 'leader tip is the target');
      expect(annot.rect.left, lessThanOrEqualTo(120));
      expect(annot.rect.bottom, lessThanOrEqualTo(500));
    });

    test('the callout tool exposes the color/font controls', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..tool = PdfEditTool.callout;
      // the callout tool exposes the same box controls as free text
      expect(editing.toolUsesColor, isTrue);
    });

    test('resizing a selected callout resizes the box, not the arrow', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..preferences.opacity = 0.55
        ..addCallout(0, const PdfRect(300, 600, 460, 660), 'x', (120, 500));
      expect(editing.selectAnnotation(0, 0), isTrue);
      final terminus0 =
          editing.document.page(0).annotations.single.calloutLine!.first;

      editing.resizeSelected(const PdfRect(320, 610, 520, 690));

      final a = editing.document.page(0).annotations.single;
      expect(a.isCallout, isTrue);
      expect(a.calloutLine!.first, terminus0, reason: 'arrow tip stays put');
      expect(a.calloutBox!.left, closeTo(320, 0.5));
      expect(a.calloutBox!.right, closeTo(520, 0.5));
      expect(a.appearanceOpacity, closeTo(0.55, 1e-9));
    });

    test('autosize fits the box and leaves the arrow tip alone', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..preferences.fontSize = 14
        ..addCallout(0, const PdfRect(300, 600, 700, 700), 'Hi', (120, 500));
      expect(editing.selectAnnotation(0, 0), isTrue);
      final tip0 =
          editing.document.page(0).annotations.single.calloutLine!.first;

      editing.autosizeSelectedTextBox();

      final a = editing.document.page(0).annotations.single;
      expect(a.isCallout, isTrue);
      expect(a.calloutLine!.first, tip0, reason: 'arrow tip untouched');
      expect(a.calloutBox!.width, lessThan(400), reason: 'box shrank to fit');
    });

    test('reshapeSelectedCalloutTarget moves only the arrow', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addCallout(0, const PdfRect(300, 600, 460, 660), 'x', (120, 500));
      expect(editing.selectAnnotation(0, 0), isTrue);
      final box0 = editing.document.page(0).annotations.single.calloutBox!;

      editing.reshapeSelectedCalloutTarget((560, 630));

      final a = editing.document.page(0).annotations.single;
      expect(a.calloutLine!.first, (560.0, 630.0));
      expect(a.calloutBox!.left, closeTo(box0.left, 0.5));
      expect(a.calloutBox!.top, closeTo(box0.top, 0.5));
      expect(a.calloutBox!.bottom, closeTo(box0.bottom, 0.5));
    });

    test('moving a callout moves the box; every arrow keeps its tip', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addCallout(0, const PdfRect(300, 600, 460, 660), 'x', (120, 500));
      expect(editing.selectAnnotation(0, 0), isTrue);
      expect(editing.addSelectedCalloutLeader((560, 450)), isTrue);
      final box0 = editing.document.page(0).annotations.single.calloutBox!;

      editing.moveSelected(40, -30);
      editing.nudgeSelected(1, 0); // the arrow keys move it the same way

      final a = editing.document.page(0).annotations.single;
      expect(a.isCallout, isTrue);
      expect([
        for (final l in a.calloutLeaders!) l.first
      ], [
        (120.0, 500.0),
        (560.0, 450.0)
      ], reason: 'arrows stay where they point');
      expect(a.calloutBox!.left, closeTo(box0.left + 41, 0.01));
      expect(a.calloutBox!.top, closeTo(box0.top - 30, 0.01));
      expect(editing.selectedAnnotation?.isCallout, isTrue,
          reason: 'the selection survives the move');
    });

    test('add/remove leader through the controller', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addCallout(0, const PdfRect(300, 600, 460, 660), 'x', (120, 630));
      expect(editing.selectAnnotation(0, 0), isTrue);
      expect(editing.canAddSelectedCalloutLeader, isTrue);
      expect(editing.canRemoveSelectedCalloutLeader, isFalse,
          reason: 'the only leader stays');
      expect(editing.removeSelectedCalloutLeader(), isFalse);

      // no target: aimed off the box, away from the existing arrow (which
      // points left), so it never lands on top of it
      expect(editing.addSelectedCalloutLeader(), isTrue);
      var leaders = editing.selectedCalloutLeaders!;
      expect(leaders, hasLength(2));
      final box = editing.selectedAnnotation!.calloutBox!;
      final (tx, ty) = leaders[1].first;
      expect(tx > box.right || ty < box.bottom || ty > box.top, isTrue,
          reason: 'the new tip sits outside the box');
      expect(tx, greaterThan(box.left), reason: 'not on the existing side');

      expect(editing.addSelectedCalloutLeader((380, 450)), isTrue);
      expect(editing.selectedCalloutLeaders, hasLength(3));
      // the leader nearest a point is the one that point removes
      expect(editing.selectedCalloutLeaderNear((385, 470)), 2);
      expect(editing.selectedCalloutLeaderNear((130, 630)), 0);
      expect(editing.removeSelectedCalloutLeader(0), isTrue);
      leaders = editing.selectedCalloutLeaders!;
      expect(leaders, hasLength(2));
      expect(leaders.last.first, (380.0, 450.0));
      expect(leaders.every((l) => l.first != (120.0, 630.0)), isTrue);

      // a reshape by index re-aims just that leader
      editing.reshapeSelectedCalloutTarget((500, 300), leader: 1);
      expect(editing.selectedCalloutLeaders![1].first, (500.0, 300.0));
      expect(editing.selectedCalloutLeaders![0].first, leaders.first.first);
    });

    test('editing a callout\'s text or font keeps its leaders and box', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addCallout(0, const PdfRect(300, 600, 460, 660), 'x', (120, 500));
      expect(editing.selectAnnotation(0, 0), isTrue);
      expect(editing.addSelectedCalloutLeader((560, 450)), isTrue);
      final box0 = editing.selectedAnnotation!.calloutBox!;

      void expectStillACallout(String why) {
        final a = editing.document.page(0).annotations.single;
        expect(a.isCallout, isTrue, reason: why);
        expect([
          for (final l in a.calloutLeaders!) l.first
        ], [
          (120.0, 500.0),
          (560.0, 450.0)
        ], reason: why);
        expect(a.calloutBox!.left, closeTo(box0.left, 0.01), reason: why);
        expect(a.calloutBox!.top, closeTo(box0.top, 0.01), reason: why);
        expect(a.calloutBox!.width, closeTo(box0.width, 0.01), reason: why);
      }

      editing.setSelectedText('new words');
      expectStillACallout('text edit');
      expect(editing.document.page(0).annotations.single.contents, 'new words');

      editing.restyleSelectedText(size: 20, font: PdfStandardFont.courier);
      expectStillACallout('font restyle');
      expect(editing.selectedTextStyle?.size, 20);

      expect(
          editing.setSelectedRichText(const [
            PdfFreeTextRun('rich ', color: 0x0000FF),
            PdfFreeTextRun('text', color: 0xFF0000),
          ]),
          isTrue);
      expectStillACallout('rich commit');
      final a = editing.document.page(0).annotations.single;
      expect(a.contents, 'rich text');
      expect(a.freeTextStyle!.color, 0x0000FF);
    });
  });

  group('cloud callout through the controller', () {
    PdfAnnotation only(PdfEditingController e) =>
        e.document.page(0).annotations.single;
    const region = PdfRect(300, 500, 420, 560);
    const note = PdfRect(120, 620, 260, 660);

    test('addCloudCallout marks the region and leads the note to it', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..preferences.lineScale = 1.5
        ..addCloudCallout(0, region, note, 'Revise');
      final annot = only(editing);
      expect(annot.isCallout, isTrue);
      expect(annot.contents, 'Revise');
      final r = annot.calloutRegion!;
      expect(r.shape, PdfCalloutRegionShape.cloud);
      expect(r.cloudScale, 1.5);
      expect(r.vertices.first, (300.0, 500.0));
      expect(annot.calloutBox!.left, closeTo(120, 0.01));
      expect(annot.freeTextStyle!.borderColor, isNull,
          reason: 'the note is plain text, no box around it');
      // a plain leader from the note's edge to the cloud
      final line = annot.calloutLine!;
      expect(line.last.$2, inInclusiveRange(note.bottom - 0.01, note.top));
      expect(line.first.$1, lessThan(region.left + 40));
    });

    test('the region restyles to a dashed polygon and back, one undo each', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addCloudCallout(0, region, note, 'x');
      expect(editing.selectAnnotation(0, 0), isTrue);

      expect(
          editing.restyleSelectedCalloutRegion(
              shape: PdfCalloutRegionShape.polygon,
              lineStyle: PdfLineStyle.dashed),
          isTrue);
      expect(only(editing).calloutRegion!.shape, PdfCalloutRegionShape.polygon);
      expect(PdfLineStyle.ofDashArray(only(editing).calloutRegion!.dash),
          PdfLineStyle.dashed);
      expect(editing.selectedAnnotation?.calloutRegion, isNotNull);

      expect(
          editing.restyleSelectedCalloutRegion(
              shape: PdfCalloutRegionShape.cloud, cloudScale: 2),
          isTrue);
      expect(only(editing).calloutRegion!.shape, PdfCalloutRegionShape.cloud);
      expect(only(editing).calloutRegion!.cloudScale, 2);
      expect(editing.selectedLineScale, 2);

      editing.undo();
      expect(only(editing).calloutRegion!.shape, PdfCalloutRegionShape.polygon);
    });

    test('moving the note leaves the cloud; a whole move carries both', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addCloudCallout(0, region, note, 'x');
      expect(editing.selectAnnotation(0, 0), isTrue);

      editing.moveSelected(-40, 10);
      expect(only(editing).calloutRegion!.vertices.first, (300.0, 500.0));
      expect(only(editing).calloutBox!.left, closeTo(80, 0.01));

      editing.moveSelected(10, -20, wholeCallout: true);
      expect(only(editing).calloutRegion!.vertices.first, (310.0, 480.0));
      expect(only(editing).calloutBox!.left, closeTo(90, 0.01));
    });

    test('reshapeSelectedCalloutRegion moves a corner; the note stays', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addCloudCallout(0, region, note, 'x');
      expect(editing.selectAnnotation(0, 0), isTrue);
      editing.reshapeSelectedCalloutRegion(
          [(300, 500), (420, 500), (460, 600), (300, 560)]);
      expect(only(editing).calloutRegion!.vertices[2], (460.0, 600.0));
      expect(only(editing).calloutBox!.left, closeTo(120, 0.01));
    });

    test('text edits keep the cloud', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addCloudCallout(0, region, note, 'x');
      expect(editing.selectAnnotation(0, 0), isTrue);
      editing.setSelectedText('new words');
      expect(only(editing).calloutRegion, isNotNull);
      editing.restyleSelectedText(size: 20, font: PdfStandardFont.courier);
      expect(only(editing).calloutRegion!.vertices.first, (300.0, 500.0));
    });
  });

  group('callout tool in the viewer', () {
    const scale = 800 / 612;
    Offset view(double x, double y) => Offset(x * scale, (792 - y) * scale);

    Future<void> drag(WidgetTester tester, Offset from, Offset to) async {
      final gesture = await tester.startGesture(from);
      await gesture.moveTo(Offset.lerp(from, to, 0.5)!);
      await gesture.moveTo(to);
      await gesture.up();
      await tester.pump();
    }

    Future<void> settle(WidgetTester tester) =>
        tester.pumpAndSettle(const Duration(milliseconds: 300));

    Future<void> tap(WidgetTester tester, Offset position) async {
      await tester.tapAt(position);
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<PdfEditingController> pumpEditor(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: editing,
            builder: (context, _) => PdfViewer(
              initialFit: PdfViewerFit.width,
              document: editing.document,
              controller: viewer,
              editing: editing,
            ),
          ),
        ),
      ));
      await tester.pump();
      return editing;
    }

    const editorKey = ValueKey('pdf-freetext-editor');

    testWidgets('dragging from the terminus to the box places a callout',
        (tester) async {
      final editing = await pumpEditor(tester);
      editing.tool = PdfEditTool.callout;
      await tester.pump();

      // press at the terminus (what we point at), release where the box goes
      await drag(tester, view(150, 500), view(360, 660));

      // the box editor opens in place, nothing committed yet
      expect(find.byKey(editorKey), findsOneWidget);
      expect(editing.isEditingText, isTrue);
      expect(editing.document.page(0).annotations, isEmpty);

      await tester.enterText(find.byKey(editorKey), 'Callout body');
      await tap(tester, view(450, 400)); // commit outside the box

      expect(find.byKey(editorKey), findsNothing);
      final annot = editing.document.page(0).annotations.single;
      expect(annot.isCallout, isTrue);
      expect(annot.contents, 'Callout body');
      final line = annot.calloutLine!;
      // the leader points back at the terminus we pressed on
      expect(line.first.$1, closeTo(150, 2));
      expect(line.first.$2, closeTo(500, 2));
      await settle(tester);
    });

    dynamic previewBox(WidgetTester tester) => [
          for (final paint
              in tester.widgetList<CustomPaint>(find.byType(CustomPaint)))
            if (paint.painter?.runtimeType.toString() ==
                '_EditingPreviewPainter')
              (paint.painter! as dynamic).calloutBox,
        ].firstWhere((b) => b != null, orElse: () => null);

    testWidgets('the cloud callout tool clouds the dragged area, then the note',
        (tester) async {
      final editing = await pumpEditor(tester);
      editing.tool = PdfEditTool.cloudCallout;
      await tester.pump();

      // drag the cloud around the area to mark
      final gesture = await tester.startGesture(view(300, 560));
      await gesture.moveTo(view(360, 530));
      await gesture.moveTo(view(420, 500));
      await tester.pump();
      final dragging = previewBox(tester);
      expect(dragging, isNotNull);
      expect(dragging.cloud, isTrue, reason: 'the cloud previews on the drag');
      expect(dragging.region, hasLength(4));
      expect(dragging.note, isNotNull, reason: 'with the note it will open');
      expect(dragging.leader, isNotNull);
      expect((dragging.note as Rect).right, lessThan(view(300, 560).dx),
          reason: 'the note sits up-left');

      await gesture.up();
      await tester.pump();
      expect(find.byKey(editorKey), findsOneWidget);
      final typing = previewBox(tester);
      expect(typing.cloud, isTrue, reason: 'the cloud stays while typing');
      expect(typing.note, isNull, reason: 'the editor is the note');
      expect(typing.leader, isNotNull);

      await tester.enterText(find.byKey(editorKey), 'Trainstop on concrete');
      await tap(tester, view(500, 400));
      expect(previewBox(tester), isNull, reason: 'gone once committed');

      final annot = editing.document.page(0).annotations.single;
      expect(annot.contents, 'Trainstop on concrete');
      final region = annot.calloutRegion!;
      expect(region.shape, PdfCalloutRegionShape.cloud);
      final xs = [for (final p in region.vertices) p.$1];
      final ys = [for (final p in region.vertices) p.$2];
      expect(xs.reduce(math.min), closeTo(300, 1));
      expect(xs.reduce(math.max), closeTo(420, 1));
      expect(ys.reduce(math.min), closeTo(500, 1));
      expect(ys.reduce(math.max), closeTo(560, 1));
      expect(annot.calloutBox!.right, lessThan(300));
      await settle(tester);
    });

    testWidgets('a tap drops a default cloud around the tap', (tester) async {
      final editing = await pumpEditor(tester);
      editing.tool = PdfEditTool.cloudCallout;
      await tester.pump();
      await tap(tester, view(360, 400));
      expect(find.byKey(editorKey), findsOneWidget);
      await tester.enterText(find.byKey(editorKey), 'Here');
      await tap(tester, view(150, 700));
      final region = editing.document.page(0).annotations.single.calloutRegion!;
      final xs = [for (final p in region.vertices) p.$1];
      expect((xs.reduce(math.min) + xs.reduce(math.max)) / 2, closeTo(360, 1));
      await settle(tester);
    });

    testWidgets('dragging a selected cloud moves it all; the note moves alone',
        (tester) async {
      final editing = await pumpEditor(tester);
      editing.addCloudCallout(0, const PdfRect(300, 380, 420, 440),
          const PdfRect(100, 480, 300, 600), 'x');
      editing.tool = PdfEditTool.select;
      expect(editing.selectAnnotation(0, 0), isTrue);
      await tester.pump();

      // grab the cloud
      await drag(tester, view(360, 410), view(380, 390));
      await settle(tester);
      var a = editing.document.page(0).annotations.single;
      expect(a.calloutRegion!.vertices.first.$1, closeTo(320, 1));
      expect(a.calloutBox!.left, closeTo(120, 1), reason: 'the note came too');

      // grab the note
      // the note now spans (120, 460)-(320, 580); grab its middle
      await drag(tester, view(220, 520), view(180, 520));
      await settle(tester);
      a = editing.document.page(0).annotations.single;
      expect(a.calloutBox!.left, closeTo(80, 1));
      expect(a.calloutRegion!.vertices.first.$1, closeTo(320, 1),
          reason: 'the cloud stayed');
    });

    testWidgets('a cloud corner handle reshapes the cloud', (tester) async {
      final editing = await pumpEditor(tester);
      editing.addCloudCallout(0, const PdfRect(300, 400, 420, 460),
          const PdfRect(120, 520, 260, 560), 'x');
      editing.tool = PdfEditTool.select;
      expect(editing.selectAnnotation(0, 0), isTrue);
      await tester.pump();
      // the top-right corner (420, 460)
      await drag(tester, view(420, 460), view(460, 500));
      await settle(tester);
      final region = editing.document.page(0).annotations.single.calloutRegion!;
      expect(region.vertices[2].$1, closeTo(460, 1.5));
      expect(region.vertices[2].$2, closeTo(500, 1.5));
    });

    testWidgets('the placement drag previews the leader, not a box',
        (tester) async {
      final editing = await pumpEditor(tester);
      editing.tool = PdfEditTool.callout;
      await tester.pump();

      final gesture = await tester.startGesture(view(150, 500));
      await gesture.moveTo(view(250, 580));
      await gesture.moveTo(view(360, 660));
      await tester.pump();

      final painters = [
        for (final paint
            in tester.widgetList<CustomPaint>(find.byType(CustomPaint)))
          if (paint.painter?.runtimeType.toString() == '_EditingPreviewPainter')
            paint.painter! as dynamic,
      ];
      expect(painters, isNotEmpty);
      for (final painter in painters) {
        expect(painter.dragRect, isNull,
            reason: 'no rubber-band rectangle under the leader');
        expect(painter.dragLine, isNull);
      }
      expect(
          painters.any((p) => (p.calloutLeaders as List?)?.length == 1), isTrue,
          reason: 'the leader (with its arrow) is what previews');
      final box = painters
          .map((p) => p.calloutBox)
          .firstWhere((b) => b != null, orElse: () => null);
      expect(box, isNotNull, reason: 'the text box it will drop is outlined');
      expect(box.region, isNull, reason: 'no cloud on a plain callout');
      expect((box.note as Rect).topLeft, view(360, 660),
          reason: 'the box sits where the drag releases');

      await gesture.up();
      await tester.pump();
      await tap(tester, view(450, 400));
      await settle(tester);
    });

    testWidgets('an empty callout box commits nothing', (tester) async {
      final editing = await pumpEditor(tester);
      editing.tool = PdfEditTool.callout;
      await tester.pump();

      await drag(tester, view(150, 500), view(360, 660));
      expect(find.byKey(editorKey), findsOneWidget);
      await tap(tester, view(450, 400)); // commit with no text

      expect(editing.document.page(0).annotations, isEmpty);
      await settle(tester);
    });

    testWidgets('dragging the terminus handle re-aims the arrow, box stays',
        (tester) async {
      final editing = await pumpEditor(tester);
      editing.addCallout(0, const PdfRect(300, 600, 460, 660), 'x', (150, 480));
      editing.tool = PdfEditTool.select;
      expect(editing.selectAnnotation(0, 0), isTrue);
      await tester.pump();
      final box0 = editing.document.page(0).annotations.single.calloutBox!;

      // the terminus handle sits at the arrow tip (150, 480); drag it away
      await drag(tester, view(150, 480), view(230, 430));
      await tester.pump();

      final a = editing.document.page(0).annotations.single;
      expect(a.isCallout, isTrue);
      final tip = a.calloutLine!.first;
      expect(tip.$1, closeTo(230, 6), reason: 'arrow tip followed the drag');
      expect(tip.$2, closeTo(430, 6));
      expect(a.calloutBox!.left, closeTo(box0.left, 1), reason: 'box unmoved');
      expect(a.calloutBox!.top, closeTo(box0.top, 1));
      await settle(tester);
    });

    testWidgets('dragging the base handle slides the base, box + tip stay',
        (tester) async {
      final editing = await pumpEditor(tester);
      editing.addCallout(0, const PdfRect(300, 600, 460, 660), 'x', (150, 630));
      editing.tool = PdfEditTool.select;
      expect(editing.selectAnnotation(0, 0), isTrue);
      await tester.pump();
      final a0 = editing.document.page(0).annotations.single;
      final tip0 = a0.calloutLine!.first;
      final base0 = a0.calloutLine!.last; // ~ (300, 630) on the left edge
      final box0 = a0.calloutBox!;

      // the base handle sits at the attach point; drag it inside toward the
      // top edge - it snaps onto the perimeter there
      await drag(tester, view(base0.$1, base0.$2), view(400, 640));
      await tester.pump();

      final a = editing.document.page(0).annotations.single;
      expect(a.calloutLine!.first, tip0, reason: 'arrow tip unchanged');
      final base = a.calloutLine!.last;
      expect((base.$1 - base0.$1).abs() + (base.$2 - base0.$2).abs(),
          greaterThan(5),
          reason: 'the base moved');
      expect(a.calloutBox!.left, closeTo(box0.left, 1), reason: 'box unmoved');
      expect(a.calloutBox!.right, closeTo(box0.right, 1));
      await settle(tester);
    });

    testWidgets('dragging the box moves it while the arrows stay put',
        (tester) async {
      final editing = await pumpEditor(tester);
      editing.addCallout(0, const PdfRect(300, 600, 460, 660), 'x', (150, 480));
      editing.tool = PdfEditTool.select;
      expect(editing.selectAnnotation(0, 0), isTrue);
      expect(editing.addSelectedCalloutLeader((520, 470)), isTrue);
      await tester.pump();
      final box0 = editing.document.page(0).annotations.single.calloutBox!;

      // grab the text box (not a handle) and drag it up-left
      await drag(tester, view(380, 640), view(340, 690));
      await tester.pump();

      final a = editing.document.page(0).annotations.single;
      expect(a.isCallout, isTrue);
      expect([
        for (final l in a.calloutLeaders!) l.first
      ], [
        (150.0, 480.0),
        (520.0, 470.0)
      ], reason: 'every arrow tip stays where it pointed');
      expect(a.calloutBox!.left, closeTo(box0.left - 40, 2));
      expect(a.calloutBox!.top, closeTo(box0.top + 50, 2));
      await settle(tester);
    });

    testWidgets('a selected callout shows nodes only: no outline or knob',
        (tester) async {
      final editing = await pumpEditor(tester);
      editing.addCallout(0, const PdfRect(300, 600, 460, 660), 'x', (150, 480));
      editing.tool = PdfEditTool.select;
      expect(editing.selectAnnotation(0, 0), isTrue);
      await tester.pump();

      final dynamic painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .firstWhere(
              (p) => p.runtimeType.toString() == '_EditingPreviewPainter');
      expect(painter.selectionOutline, isFalse);
      expect(painter.extraSelectionRects, isEmpty,
          reason: 'no second box around the leader-enclosing /Rect');
      expect(painter.showRotateHandle, isFalse);
      expect(painter.showHandles, isTrue,
          reason: 'the text box still resizes from its handles');
      expect((painter.vertexHandles as List).length, 2,
          reason: 'the leader keeps its terminus + base nodes');

      // where the rotate knob would sit above the box, a drag no longer spins
      final box = editing.document.page(0).annotations.single.calloutBox!;
      final knob =
          view((box.left + box.right) / 2, box.top) - const Offset(0, 24);
      await drag(tester, knob, knob + const Offset(60, 0));
      expect(editing.document.page(0).annotations.single.appearanceRotation,
          closeTo(0, 1e-6));
      await settle(tester);
    });

    testWidgets('each leader has its own terminus handle', (tester) async {
      final editing = await pumpEditor(tester);
      editing.addCallout(0, const PdfRect(300, 600, 460, 660), 'x', (150, 480));
      editing.tool = PdfEditTool.select;
      expect(editing.selectAnnotation(0, 0), isTrue);
      expect(editing.addSelectedCalloutLeader((520, 470)), isTrue);
      await tester.pump();

      // the second leader's tip handle sits at (520, 470)
      await drag(tester, view(520, 470), view(560, 420));
      await tester.pump();

      final leaders =
          editing.document.page(0).annotations.single.calloutLeaders!;
      expect(leaders.first.first, (150.0, 480.0), reason: 'leader 0 untouched');
      expect(leaders[1].first.$1, closeTo(560, 6));
      expect(leaders[1].first.$2, closeTo(420, 6));
      await settle(tester);
    });

    testWidgets('the context menu adds and removes leaders', (tester) async {
      final editing = await pumpEditor(tester);
      editing.addCallout(0, const PdfRect(300, 600, 460, 660), 'x', (150, 480));
      editing.tool = PdfEditTool.select;
      await tester.pump();

      Future<void> menu(Offset at) async {
        final gesture = await tester.startGesture(at,
            kind: PointerDeviceKind.mouse, buttons: kSecondaryButton);
        await gesture.up();
        await tester.pumpAndSettle();
      }

      await menu(view(380, 630));
      final remove = find.byKey(const ValueKey('pdf-annot-menu-remove-leader'));
      expect(remove, findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pdf-annot-menu-add-leader')));
      await tester.pumpAndSettle();
      expect(editing.selectedCalloutLeaders, hasLength(2));

      await menu(view(380, 630));
      await tester
          .tap(find.byKey(const ValueKey('pdf-annot-menu-remove-leader')));
      await tester.pumpAndSettle();
      expect(editing.selectedCalloutLeaders, hasLength(1));
      await settle(tester);
    });

    testWidgets('a plain tap makes the tap the terminus and offsets the box',
        (tester) async {
      final editing = await pumpEditor(tester);
      editing.tool = PdfEditTool.callout;
      await tester.pump();

      await tap(tester, view(250, 500)); // no drag: the tap is the terminus
      expect(find.byKey(editorKey), findsOneWidget);

      await tester.enterText(find.byKey(editorKey), 'Tapped callout');
      await tap(tester, view(450, 400)); // commit

      final annot = editing.document.page(0).annotations.single;
      expect(annot.isCallout, isTrue);
      final line = annot.calloutLine!;
      expect(line.first.$1, closeTo(250, 2));
      expect(line.first.$2, closeTo(500, 2));
      await settle(tester);
    });
  });

  test('callout survives a save/reload round-trip', () {
    final editing = PdfEditingController(buildMultiPagePdf(1))
      ..addCallout(0, const PdfRect(300, 600, 460, 660), 'persist', (120, 500));
    final reopened = PdfDocument.open(editing.bytes);
    final annot = reopened.page(0).annotations.single;
    expect(annot.isCallout, isTrue);
    expect(annot.calloutLine!.first, (120.0, 500.0));
    final ap =
        latin1.decode(reopened.cos.decodeStreamData(annot.normalAppearance!));
    expect(ap, contains('Tj'));
  });
}
