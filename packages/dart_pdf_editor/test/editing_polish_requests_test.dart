import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey, TextInputAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

final png = base64.decode('iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0k'
    'AAAAGUlEQVR4nGP4z8DwHwgbWBgZ/jNyicr7AgA3BAUOTnqjAAAAAABJRU5ErkJggg==');
const scale = 800 / 612;
Offset point(double x, double y) => Offset(x * scale, (792 - y) * scale);

Future<void> press(WidgetTester tester, LogicalKeyboardKey key,
    {bool shift = false, bool meta = false}) async {
  final modifier =
      meta ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(modifier);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(modifier);
  await tester.pumpAndSettle();
}

Future<(PdfEditingController, PdfViewerController)> pumpEditor(
  WidgetTester tester, {
  PdfSystemImagePasteProvider? image,
  PdfSystemPdfPasteProvider? pdf,
  PdfTextPrompt? prompt,
  bool externalImagesFirst = true,
}) async {
  final editing = PdfEditingController(buildMultiPagePdf(2));
  final viewer = PdfViewerController();
  addTearDown(editing.dispose);
  addTearDown(viewer.dispose);
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: ListenableBuilder(
    listenable: editing,
    builder: (context, _) => PdfViewer(
      document: editing.document,
      editing: editing,
      controller: viewer,
      initialFit: PdfViewerFit.width,
      systemImagePasteProvider: image,
      systemImagePasteOverridesLocalClipboard: externalImagesFirst,
      systemPdfPasteProvider: pdf,
      editingTextPrompt: prompt,
    ),
  ))));
  await tester.pump();
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  return (editing, viewer);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PdfAnnotationSnapshotClipboard.instance.clear();
    PdfSnapshotClipboard.instance.clear();
  });

  for (final meta in [false, true]) {
    testWidgets(
        '${meta ? 'Cmd' : 'Ctrl'} formatting works on a selected box, with undo/redo',
        (tester) async {
      final (editing, _) = await pumpEditor(tester);
      editing.addFreeText(0, const PdfRect(100, 600, 350, 660), 'Hello');
      await tester.pump();
      await tester.tapAt(point(400, 400), kind: PointerDeviceKind.mouse);
      editing.selectAnnotation(0, 0);
      await tester.pump();
      await press(tester, LogicalKeyboardKey.keyB, meta: meta);
      expect(editing.selectedTextStyle!.font.isBold, isTrue);
      await press(tester, LogicalKeyboardKey.keyI, meta: meta);
      expect(editing.selectedTextStyle!.font.isItalic, isTrue);
      await press(tester, LogicalKeyboardKey.keyU, meta: meta);
      expect(editing.selectedFreeTextStyle!.underline, isTrue);
      await press(tester, LogicalKeyboardKey.keyZ, meta: meta);
      expect(editing.pageAt(0).annotations.single.freeTextStyle!.underline,
          isFalse);
      await press(tester, LogicalKeyboardKey.keyZ, shift: true, meta: meta);
      expect(editing.pageAt(0).annotations.single.freeTextStyle!.underline,
          isTrue);
    });
  }

  testWidgets('Ctrl+B, Ctrl+I and Ctrl+U style the PDF page text selection',
      (tester) async {
    final (editing, viewer) = await pumpEditor(tester);
    await tester.tapAt(point(100, 727),
        kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(viewer.selectedText, isNotEmpty);
    Navigator.of(tester.element(find.byType(PdfViewer))).pop();
    await tester.pumpAndSettle();
    final oldRevision = editing.revisionId;
    await press(tester, LogicalKeyboardKey.keyB);
    expect(editing.revisionId, greaterThan(oldRevision));
    final fonts = editing.document.cos
        .resolve(editing.pageAt(0).resources['Font']) as CosDictionary;
    expect(fonts.entries.values.any((ref) {
      final font = editing.document.cos.resolve(ref);
      return font is CosDictionary &&
          (editing.document.cos.resolve(font['BaseFont']) as CosName)
              .value
              .contains('Bold');
    }), isTrue);
    await tester.tapAt(point(100, 727),
        kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(PdfViewer))).pop();
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.keyI);
    final styledFonts = editing.document.cos
        .resolve(editing.pageAt(0).resources['Font']) as CosDictionary;
    expect(styledFonts.entries.values.any((ref) {
      final font = editing.document.cos.resolve(ref);
      return font is CosDictionary &&
          (editing.document.cos.resolve(font['BaseFont']) as CosName)
              .value
              .contains('BoldOblique');
    }), isTrue);
    await tester.tapAt(point(100, 727),
        kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(PdfViewer))).pop();
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.keyU);
    expect(editing.pageAt(0).annotations.single.subtype, 'Underline');
  });

  test('formatting grouped text boxes preserves grouping and run styles', () {
    final editing = PdfEditingController(buildMultiPagePdf(1))
      ..addFreeText(0, const PdfRect(100, 600, 250, 650), 'First')
      ..addFreeText(0, const PdfRect(300, 600, 450, 650), 'Second');
    addTearDown(editing.dispose);
    editing.selectAnnotationSlots([(0, 0), (0, 1)]);
    editing.groupSelectedAnnotations();
    editing.toggleSelectedTextFormatting(PdfTextFormatting.bold);
    expect(PdfAnnotationGroups.ofPage(editing.pageAt(0)).slotsFor(0), [0, 1]);
    expect(
        editing
            .pageAt(0)
            .annotations
            .every((a) => a.freeTextStyle!.fontName.contains('Bold')),
        isTrue);
    editing.toggleSelectedTextFormatting(PdfTextFormatting.bold);
    expect(
        editing
            .pageAt(0)
            .annotations
            .every((a) => !a.freeTextStyle!.fontName.contains('Bold')),
        isTrue);
  });

  test(
      'pending ink undo follows stroke order across pages before document edits',
      () {
    final editing = PdfEditingController(buildMultiPagePdf(2))
      ..inkCommitDelay = null;
    addTearDown(editing.dispose);
    editing.addRectangle(0, const PdfRect(100, 600, 200, 650));
    editing.addInkStroke(0, const [(10, 10), (20, 20)],
        pressures: const [0.2, 0.8]);
    editing.addInkStroke(1, const [(30, 30), (40, 40)]);
    final revision = editing.revisionId;
    editing.undo();
    expect(editing.strokesOn(1), isEmpty);
    expect(editing.strokesOn(0), hasLength(1));
    expect(editing.revisionId, revision);
    editing.undo();
    expect(editing.hasPendingInk, isFalse);
    editing.undo();
    expect(editing.pageAt(0).annotations, isEmpty);
    editing.redo();
    expect(editing.pageAt(0).annotations, hasLength(1));
    editing.redo();
    expect(editing.strokePressuresOn(0).single, [0.2, 0.8]);
    editing.redo();
    expect(editing.strokesOn(1), hasLength(1));
    editing.finishInk();
    expect(editing.pageAt(0).annotations, hasLength(2));
    expect(editing.pageAt(1).annotations, hasLength(1));
  });

  test('a new ink stroke discards the old document redo branch', () {
    final editing = PdfEditingController(buildMultiPagePdf(1))
      ..inkCommitDelay = null;
    addTearDown(editing.dispose);
    editing.addRectangle(0, const PdfRect(100, 600, 200, 650));
    editing.undo();
    editing.addInkStroke(0, const [(10, 10), (20, 20)]);
    expect(editing.canRedo, isFalse);
    expect(editing.isModified, isTrue);
    editing.undo();
    editing.redo();
    expect(editing.pageAt(0).annotations, isEmpty);
    expect(editing.strokesOn(0), hasLength(1));
    expect(editing.canRedo, isFalse);
  });

  testWidgets('redoing all ink strokes re-arms their automatic commit',
      (tester) async {
    final editing = PdfEditingController(buildMultiPagePdf(1));
    addTearDown(editing.dispose);
    editing.addInkStroke(0, const [(10, 10), (20, 20)]);
    editing.addInkStroke(0, const [(30, 30), (40, 40)]);
    editing.undo();
    await tester.pump(const Duration(seconds: 1));
    expect(editing.strokesOn(0), hasLength(1));
    editing.redo();
    await tester.pump(const Duration(seconds: 1));
    expect(editing.hasPendingInk, isFalse);
    expect(editing.pageAt(0).annotations.single.inkList, hasLength(2));
  });

  for (final format in PdfTextFormatting.values) {
    test('rich $format toggles off despite an unstyled fallback DA', () {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      editing.apply((e) {
        e.addFreeTextRich(0, const PdfRect(100, 600, 350, 660), [
          PdfFreeTextRun('Rich',
              font: PdfStandardFont.helveticaBoldOblique, underline: true),
        ]);
        final a = e.document.page(0).annotations.single;
        a.dict['DA'] = CosString.fromText('/Helvetica 12 Tf 0 0 0 rg');
        a.dict.entries.remove(kPdfFreeTextUnderlineKey);
      });
      editing.selectAnnotation(0, 0);
      editing.toggleSelectedTextFormatting(format);
      final runs = PdfAnnotationEditing.parseFreeTextRichContent(
          editing.selectedAnnotation!.richContent!);
      final run = runs.single;
      expect(
          switch (format) {
            PdfTextFormatting.bold => (run.font as PdfStandardFont).isBold,
            PdfTextFormatting.italic => (run.font as PdfStandardFont).isItalic,
            PdfTextFormatting.underline => run.underline,
          },
          isFalse);
    });
  }

  testWidgets('repeated external PDF paste keeps vector content',
      (tester) async {
    final source = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)))
        .captureVectorSnapshot(0, const PdfRect(60, 700, 220, 740))
        .toPdfBytes();
    var imageReads = 0;
    final (editing, _) = await pumpEditor(tester,
        pdf: (_) async => PdfClipboardPdf(source, changeToken: 'same-copy'),
        image: (_) async {
          imageReads++;
          return png;
        });
    await tester.tapAt(point(300, 500), kind: PointerDeviceKind.mouse);
    await press(tester, LogicalKeyboardKey.keyV);
    await press(tester, LogicalKeyboardKey.keyV);
    expect(imageReads, 0);
    expect(editing.pageAt(0).annotations, hasLength(2));
    expect(editing.pageAt(0).annotations.every((a) => !a.isImageStamp), isTrue);
  });

  testWidgets('readers without ownership tracking retain local vector paste',
      (tester) async {
    var reads = 0;
    final (editing, _) =
        await pumpEditor(tester, externalImagesFirst: false, image: (_) async {
      reads++;
      return png;
    });
    editing.copyVectorSnapshot(0, const PdfRect(60, 700, 220, 740));
    await tester.tapAt(point(300, 500), kind: PointerDeviceKind.mouse);
    await press(tester, LogicalKeyboardKey.keyV);
    expect(reads, 0);
    expect(editing.pageAt(0).annotations.single.isImageStamp, isFalse);
  });

  test('multi-rotation rejects an annotation with an unusable appearance', () {
    final seed = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)))
      ..addSquare(0, const PdfRect(100, 600, 150, 650))
      ..addSquare(0, const PdfRect(200, 600, 250, 650));
    seed.document
        .page(0)
        .annotations
        .last
        .normalAppearance!
        .dictionary
        .entries
        .remove('BBox');
    final editing = PdfEditingController(seed.save());
    addTearDown(editing.dispose);
    editing.selectAnnotationSlots([(0, 0), (0, 1)]);
    final before = editing.bytes;
    expect(editing.canRotateSelected, isFalse);
    editing.rotateSelected(90);
    expect(editing.bytes, before);
  });

  test(
      'callout outline edits and text formatting preserve independent leader style',
      () {
    final editing = PdfEditingController(buildMultiPagePdf(1))
      ..addCallout(0, const PdfRect(300, 600, 450, 660), 'Detail', (120, 500))
      ..selectAnnotation(0, 0);
    addTearDown(editing.dispose);
    editing.restyleSelectedCalloutLeader(
        width: 7,
        color: const Color(0xFF0000FF),
        lineStyle: PdfLineStyle.dashed);
    editing.restyleSelectedText(border: (null,), borderWidth: 0);
    editing.toggleSelectedTextFormatting(PdfTextFormatting.bold);
    editing.setSelectedText('New detail');
    final a = editing.selectedAnnotation!;
    expect(a.freeTextStyle!.borderColor, isNull);
    expect(a.freeTextStyle!.borderWidth, 0);
    expect(a.calloutLeaderStyle!.width, 7);
    expect(a.calloutLeaderStyle!.color, 0x0000FF);
    expect(a.calloutLeaderStyle!.dash, isNotEmpty);
  });

  test('callout text edits preserve distinct leader and outline dash patterns',
      () {
    final editing = PdfEditingController(buildMultiPagePdf(1));
    addTearDown(editing.dispose);
    editing.apply((e) => e.addCallout(
        0, const PdfRect(300, 600, 450, 660), 'Detail', (120, 500),
        strokeWidth: 5,
        leaderDash: const [15, 5],
        outlineWidth: 2,
        outlineDash: const [4, 2]));
    editing.selectAnnotation(0, 0);
    editing.restyleSelectedText(size: 18);
    editing.setSelectedText('New detail');
    expect(editing.selectedAnnotation!.borderDash, [4, 2]);
    expect(editing.selectedAnnotation!.calloutLeaderStyle!.dash, [15, 5]);
    expect(editing.selectedAnnotation!.calloutLeaderStyle!.width, 5);
  });

  testWidgets('Ctrl+Z removes fresh ink before an older annotation',
      (tester) async {
    final (editing, _) = await pumpEditor(tester);
    editing
      ..addRectangle(0, const PdfRect(100, 600, 200, 650))
      ..tool = PdfEditTool.ink;
    await tester.pump();
    await tester.dragFrom(point(100, 700), const Offset(80, 30),
        kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(editing.hasPendingInk, isTrue);
    await press(tester, LogicalKeyboardKey.keyZ);
    expect(editing.hasPendingInk, isFalse);
    expect(editing.pageAt(0).annotations.single.subtype, 'Square');
    await tester.pump(const Duration(seconds: 1));
    expect(editing.pageAt(0).annotations, hasLength(1));
    await press(tester, LogicalKeyboardKey.keyY);
    expect(editing.hasPendingInk, isTrue);
    editing.finishInk();
    await tester.pumpAndSettle();
    expect(editing.pageAt(0).annotations.last.subtype, 'Ink');
  });

  testWidgets('callout properties expose independent leader and outline widths',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    addTearDown(tester.view.resetPhysicalSize);
    final editing = PdfEditingController(buildMultiPagePdf(1))
      ..addCallout(0, const PdfRect(300, 600, 450, 660), 'Detail', (120, 500))
      ..selectAnnotation(0, 0);
    addTearDown(editing.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Align(
      alignment: Alignment.centerRight,
      child: PdfAnnotationPropertiesPanel(controller: editing),
    ))));
    await tester.pumpAndSettle();
    final leader =
        find.byKey(const ValueKey('pdf-prop-callout-leader-width-input'));
    final outline =
        find.byKey(const ValueKey('pdf-prop-callout-outline-width-input'));
    final scrollable = find
        .descendant(
            of: find.byType(PdfAnnotationPropertiesPanel),
            matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(leader, 300, scrollable: scrollable);
    expect(leader, findsOneWidget);
    await tester.enterText(leader, '6');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(outline, -300, scrollable: scrollable);
    await tester.enterText(outline, '0');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(editing.selectedAnnotation!.calloutLeaderStyle!.width, 6);
    expect(editing.selectedAnnotation!.freeTextStyle!.borderWidth, 0);
  });

  testWidgets('callout properties switch the box between cloud and rectangle',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    addTearDown(tester.view.resetPhysicalSize);
    final editing = PdfEditingController(buildMultiPagePdf(1))
      ..addCallout(0, const PdfRect(300, 600, 450, 660), 'Detail', (120, 500),
          boxShape: PdfCalloutBoxShape.cloud)
      ..selectAnnotation(0, 0);
    addTearDown(editing.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Align(
      alignment: Alignment.centerRight,
      child: PdfAnnotationPropertiesPanel(controller: editing),
    ))));
    await tester.pumpAndSettle();
    const shapeKey = ValueKey('pdf-prop-callout-box-shape');
    PdfDropdown<PdfCalloutBoxShape> shape() =>
        tester.widget<PdfDropdown<PdfCalloutBoxShape>>(find.byKey(shapeKey));
    expect(shape().value, PdfCalloutBoxShape.cloud);
    expect(find.byKey(const ValueKey('pdf-prop-callout-cloud-scale')),
        findsOneWidget,
        reason: 'a cloud offers its scallop size');

    shape().onChanged!(PdfCalloutBoxShape.rectangle);
    await tester.pumpAndSettle();
    expect(editing.selectedAnnotation!.calloutBoxShape,
        PdfCalloutBoxShape.rectangle);
    expect(shape().value, PdfCalloutBoxShape.rectangle);
    expect(find.byKey(const ValueKey('pdf-prop-callout-cloud-scale')),
        findsNothing,
        reason: 'a rectangle has no scallops to size');

    tester
        .widget<PdfDropdown<PdfLineStyle>>(
            find.byKey(const ValueKey('pdf-prop-callout-box-dash')))
        .onChanged!(PdfLineStyle.dotted);
    await tester.pumpAndSettle();
    expect(PdfLineStyle.ofDashArray(editing.selectedAnnotation!.borderDash),
        PdfLineStyle.dotted);
  });

  for (final mode in PdfAnnotationRotationMode.values) {
    testWidgets('right-click rotation invokes ${mode.name}', (tester) async {
      final (editing, _) = await pumpEditor(tester,
          prompt: (context,
                  {required title, initial = '', multiline = false}) async =>
              '90');
      editing
        ..addRectangle(0, const PdfRect(100, 600, 200, 650))
        ..addRectangle(0, const PdfRect(300, 600, 400, 650));
      editing.selectAnnotationSlots([(0, 0), (0, 1)]);
      await tester.pump();
      await tester.tapAt(point(150, 625),
          kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      final action = find.byKey(ValueKey('pdf-annot-menu-rotate-${mode.name}'));
      expect(action, findsOneWidget);
      await tester.tap(action);
      await tester.pumpAndSettle();
      final a = editing.pageAt(0).annotations.first;
      expect(a.rect.width, closeTo(50, 0.01));
      expect(
          (a.rect.left + a.rect.right) / 2,
          closeTo(mode == PdfAnnotationRotationMode.selectionCenter ? 250 : 150,
              0.01));
    });

    test('multi-selection rotates with ${mode.name} in one revision', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addRectangle(0, const PdfRect(100, 600, 200, 650))
        ..addRectangle(0, const PdfRect(300, 600, 400, 650));
      addTearDown(editing.dispose);
      editing.selectAnnotationSlots([(0, 0), (0, 1)]);
      final revision = editing.revisionCount;
      editing.rotateSelected(90, mode: mode);
      expect(editing.revisionCount, revision + 1);
      final a = editing.pageAt(0).annotations;
      double cx(PdfAnnotation a) => (a.rect.left + a.rect.right) / 2;
      double cy(PdfAnnotation a) => (a.rect.bottom + a.rect.top) / 2;
      if (mode == PdfAnnotationRotationMode.selectionCenter) {
        expect(cx(a[0]), closeTo(250, 0.01));
        expect(cy(a[0]), closeTo(525, 0.01));
        expect(cx(a[1]), closeTo(250, 0.01));
        expect(cy(a[1]), closeTo(725, 0.01));
      } else {
        expect(cx(a[0]), closeTo(150, 0.01));
        expect(cx(a[1]), closeTo(350, 0.01));
        expect(cy(a[0]), closeTo(625, 0.01));
        expect(cy(a[1]), closeTo(625, 0.01));
      }
      expect(a[0].rect.width, closeTo(50, 0.01));
      expect(a[0].rect.height, closeTo(100, 0.01));
      editing.undo();
      expect(editing.pageAt(0).annotations.first.rect,
          const PdfRect(100, 600, 200, 650));
    });
  }

  testWidgets(
      'a new external clipboard image supersedes a local annotation copy',
      (tester) async {
    final (editing, _) = await pumpEditor(tester, image: (_) async => png);
    editing.addRectangle(0, const PdfRect(100, 600, 200, 650));
    editing.selectAnnotation(0, 0);
    editing.copySelectedAnnotations();
    await tester.pump();
    await tester.tapAt(point(400, 400), kind: PointerDeviceKind.mouse);
    await press(tester, LogicalKeyboardKey.keyV);
    await tester.runAsync(() async {
      for (var i = 0; i < 50; i++) {
        if (editing.pageAt(0).annotations.length == 2) return;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pumpAndSettle();
    expect(editing.pageAt(0).annotations, hasLength(2));
    expect(editing.pageAt(0).annotations.last.isImageStamp, isTrue);
  });

  testWidgets(
      'paste captures its destination and rejects a stale clipboard read',
      (tester) async {
    final completion = Completer<Uint8List?>();
    var reads = 0;
    final (editing, _) = await pumpEditor(tester, image: (_) {
      reads++;
      return completion.future;
    });
    await tester.tapAt(point(300, 500), kind: PointerDeviceKind.mouse);
    await press(tester, LogicalKeyboardKey.keyV);
    await press(tester, LogicalKeyboardKey.keyV);
    expect(reads, 1);
    editing.addRectangle(0, const PdfRect(100, 600, 200, 650));
    completion.complete(png);
    await tester.pumpAndSettle();
    expect(editing.pageAt(0).annotations, hasLength(1));
    expect(editing.pageAt(0).annotations.single.subtype, 'Square');
  });
}
