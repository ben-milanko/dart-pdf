import 'dart:convert';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/editing/editing_overlay.dart';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'editing_reflow_test.dart'
    show buildParagraphPdf, selectElementByText, textRuns;

// 2x2 RGBA PNG, the same fixture the image-content tests use.
final tinyPngBytes =
    base64.decode('iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0k'
        'AAAAGUlEQVR4nGP4z8DwHwgbWBgZ/jNyicr7AgA3BAUOTnqjAAAAAABJRU5ErkJggg==');

/// A body line, a logo-ish filled path, and a second line reached with a
/// relative `Td` so a move of the first has something to disturb.
const mixedContent = 'BT /F1 12 Tf 14 TL 72 700 Td '
    '(Alpha beta gamma delta) Tj '
    'T* (epsilon zeta eta theta) Tj ET\n'
    '0 0 1 rg 100 600 80 40 re f\n';

Uint8List buildTwoPageContentPdf({int targetRotation = 0}) {
  const targetContent = 'BT /F1 12 Tf 72 500 Td (Target page) Tj ET\n';
  final rotate = targetRotation == 0 ? '' : '/Rotate $targetRotation ';
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 2 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Contents 4 0 R /Resources << /Font << /F1 7 0 R >> >> >>',
    '<< /Length ${mixedContent.length} >>\nstream\n$mixedContent\nendstream',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] $rotate'
        '/Contents 6 0 R /Resources << /Font << /F1 8 0 R >> >> >>',
    '<< /Length ${targetContent.length} >>\nstream\n$targetContent\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>',
  ];
  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xrefOffset = buffer.length;
  buffer
    ..write('xref\n0 ${objects.length + 1}\n')
    ..write('0000000000 65535 f \n');
  for (final offset in offsets) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer
    ..write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n')
    ..write('startxref\n$xrefOffset\n%%EOF\n');
  return ascii.encode(buffer.toString());
}

double bottomOf(PdfEditingController editing, String text) => textRuns(
      editing.document,
    ).firstWhere((r) => r.text == text).bottom;

PdfRect boundsOf(PdfEditingController editing, int id) =>
    editing.elementsOn(0).elements[id].bounds!;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('moveSelectedElement (controller)', () {
    test('moves a text run and keeps it selected', () {
      final editing = PdfEditingController(buildParagraphPdf(mixedContent));
      addTearDown(editing.dispose);

      expect(selectElementByText(editing, 'Alpha beta gamma delta'), isTrue);
      expect(editing.canMoveSelectedElement, isTrue);
      final selectedId = editing.selectedElement!.id;
      final secondBefore = bottomOf(editing, 'epsilon zeta eta theta');

      expect(editing.moveSelectedElement(24, -60), isTrue);

      // still selected, still the same run - the id survives the rewrite
      expect(editing.selectedElement, isNotNull);
      expect(editing.selectedElement!.id, selectedId);
      expect(editing.selectedElement!.text, 'Alpha beta gamma delta');
      expect(editing.selectedElementPage, 0);

      final moved = editing.selectedElement!.bounds!;
      expect(moved.left, closeTo(72 + 24, 0.05));
      expect(bottomOf(editing, 'Alpha beta gamma delta'),
          closeTo(700 - 2.4 - 60, 0.05));
      // the line after it is placed relatively; it must not have followed
      expect(bottomOf(editing, 'epsilon zeta eta theta'),
          closeTo(secondBefore, 0.05));
    });

    test('moves a filled path', () {
      final editing = PdfEditingController(buildParagraphPdf(mixedContent));
      addTearDown(editing.dispose);

      expect(editing.selectElementAt(0, 140, 620), isTrue);
      expect(editing.selectedElement!.kind, PdfElementKind.path);
      expect(editing.moveSelectedElement(-30, 15), isTrue);

      final bounds = editing.selectedElement!.bounds!;
      expect(bounds.left, closeTo(70, 0.05));
      expect(bounds.bottom, closeTo(615, 0.05));
      expect(bounds.width, closeTo(80, 0.05));
      expect(bounds.height, closeTo(40, 0.05));
    });

    test('a move is one undoable revision', () {
      final editing = PdfEditingController(buildParagraphPdf(mixedContent));
      addTearDown(editing.dispose);

      expect(selectElementByText(editing, 'Alpha beta gamma delta'), isTrue);
      final before = bottomOf(editing, 'Alpha beta gamma delta');
      expect(editing.moveSelectedElement(0, -50), isTrue);
      expect(bottomOf(editing, 'Alpha beta gamma delta'),
          closeTo(before - 50, 0.05));

      editing.undo();
      expect(
          bottomOf(editing, 'Alpha beta gamma delta'), closeTo(before, 0.05));
    });

    test('arrow-key nudges reach the selected element', () {
      final editing = PdfEditingController(buildParagraphPdf(mixedContent));
      addTearDown(editing.dispose);

      expect(selectElementByText(editing, 'Alpha beta gamma delta'), isTrue);
      final before = bottomOf(editing, 'Alpha beta gamma delta');

      // view y runs down, so "up" raises the run in page space
      editing.nudgeSelected(0, -1);
      expect(bottomOf(editing, 'Alpha beta gamma delta'),
          closeTo(before + 1, 0.05));
      editing.nudgeSelected(10, 0);
      expect(editing.selectedElement!.bounds!.left, closeTo(82, 0.05));
      expect(editing.selectedElement!.text, 'Alpha beta gamma delta');
    });

    test('nothing selected, nothing moves', () {
      final editing = PdfEditingController(buildParagraphPdf(mixedContent));
      addTearDown(editing.dispose);
      expect(editing.canMoveSelectedElement, isFalse);
      expect(editing.moveSelectedElement(10, 10), isFalse);
    });

    test('a clipping path is not movable', () {
      final editing =
          PdfEditingController(buildParagraphPdf('50 50 200 200 re W f\n'));
      addTearDown(editing.dispose);
      expect(editing.selectElementAt(0, 150, 150), isTrue);
      expect(editing.canMoveSelectedElement, isFalse);
      expect(editing.moveSelectedElement(10, 10), isFalse);
    });

    test('a drag toward the next page parks it at the edge, still on paper',
        () {
      final editing = PdfEditingController(buildParagraphPdf(mixedContent));
      addTearDown(editing.dispose);
      expect(selectElementByText(editing, 'Alpha beta gamma delta'), isTrue);
      final before = boundsOf(editing, editing.selectedElement!.id);

      // far past the bottom edge - a drag aimed at the page below
      expect(editing.moveSelectedElement(0, -2000), isTrue);

      final after = editing.selectedElement!.bounds!;
      final height = before.top - before.bottom;
      expect(after.top - after.bottom, closeTo(height, 0.1),
          reason: 'the tether shifts, it does not squash');
      // the run is shorter than pageTether, so the tether keeps all of it
      expect(after.bottom, closeTo(0, 1),
          reason: 'it parks flush with the page edge, not below it');
      expect(after.top, lessThanOrEqualTo(792));
      expect(editing.selectedElement?.text, 'Alpha beta gamma delta');
    });

    test('a drag toward the page above leaves it grabbable', () {
      final editing = PdfEditingController(buildParagraphPdf(mixedContent));
      addTearDown(editing.dispose);
      expect(selectElementByText(editing, 'Alpha beta gamma delta'), isTrue);

      final before = boundsOf(editing, editing.selectedElement!.id);
      expect(editing.moveSelectedElement(0, 2000), isTrue);
      final after = editing.selectedElement!.bounds!;
      expect(after.top, closeTo(792, 1),
          reason: 'it parks flush with the top edge, not above it');
      expect(after.bottom, closeTo(792 - (before.top - before.bottom), 1));
      // the whole point of the tether: it can still be hit-tested, so the
      // user can pick it up again
      expect(
          editing.selectElementAt(
              0, (after.left + after.right) / 2, after.bottom + 1),
          isTrue);
    });

    test('an already tethered element does not jump back on a further drag',
        () {
      final editing = PdfEditingController(buildParagraphPdf(mixedContent));
      addTearDown(editing.dispose);
      expect(selectElementByText(editing, 'Alpha beta gamma delta'), isTrue);
      expect(editing.moveSelectedElement(0, -2000), isTrue);
      final parked = editing.selectedElement!.bounds!;
      // pushing further the same way is refused, not silently re-centred
      expect(editing.moveSelectedElement(0, -50), isFalse);
      expect(editing.selectedElement!.bounds!.bottom,
          closeTo(parked.bottom, 0.01));
    });

    test('moving an image element keeps its size', () {
      final editing = PdfEditingController(PdfImageDocument.fromImageBytes(
        [tinyPngBytes],
        pageSize: const PdfPageSize(200, 200),
        fit: PdfImageFit.fill,
      ));
      addTearDown(editing.dispose);

      expect(editing.selectElementAt(0, 100, 100), isTrue);
      expect(editing.selectedElement!.kind, PdfElementKind.image);
      final before = boundsOf(editing, editing.selectedElement!.id);
      expect(editing.moveSelectedElement(12, 8), isTrue);

      final after = editing.selectedElement!.bounds!;
      expect(after.left, closeTo(before.left + 12, 0.05));
      expect(after.bottom, closeTo(before.bottom + 8, 0.05));
      expect(after.width, closeTo(before.width, 0.05));
      expect(after.height, closeTo(before.height, 0.05));
    });

    test('moves a text element onto another page and keeps it editable', () {
      final editing = PdfEditingController(buildTwoPageContentPdf());
      addTearDown(editing.dispose);
      expect(selectElementByText(editing, 'Alpha beta gamma delta'), isTrue);
      final source = editing.selectedElement!.bounds!;
      final sourceX = (source.left + source.right) / 2;
      final sourceY = (source.bottom + source.top) / 2;

      expect(
        editing.moveSelectedElementToPage(
          1,
          sourceX: sourceX,
          sourceY: sourceY,
          targetX: 240,
          targetY: 420,
        ),
        isTrue,
      );

      expect(
        editing.elementsOn(0).elements.map((e) => e.text),
        isNot(contains('Alpha beta gamma delta')),
      );
      expect(bottomOf(editing, 'epsilon zeta eta theta'), closeTo(683.6, 0.1),
          reason: 'the following source line stays where it was');
      expect(editing.selectedElementPage, 1);
      expect(editing.selectedElement?.kind, PdfElementKind.text);
      expect(editing.selectedElement?.text, 'Alpha beta gamma delta');
      expect(editing.canEditSelectedElementText, isTrue);
      final moved = editing.selectedElement!.bounds!;
      expect((moved.left + moved.right) / 2, closeTo(240, 0.1));
      expect((moved.bottom + moved.top) / 2, closeTo(420, 0.1));

      // Page 2 already owns a different /F1 (Courier). The moved run keeps
      // its source Helvetica under a remapped resource name.
      final page = editing.document.page(1);
      final fonts =
          editing.document.cos.resolve(page.resources['Font']) as CosDictionary;
      final font = editing.document.cos
              .resolve(fonts[editing.selectedElement!.resourceName!])
          as CosDictionary;
      expect(font['BaseFont'], const CosName('Helvetica'));

      // The cross-page move is one revision.
      editing.undo();
      expect(
        editing.elementsOn(0).elements.map((e) => e.text),
        contains('Alpha beta gamma delta'),
      );
      expect(
        editing.elementsOn(1).elements.map((e) => e.text),
        isNot(contains('Alpha beta gamma delta')),
      );
    });

    test('a cross-page move preserves screen orientation across /Rotate', () {
      final editing = PdfEditingController(
        buildTwoPageContentPdf(targetRotation: 90),
      );
      addTearDown(editing.dispose);
      expect(selectElementByText(editing, 'Alpha beta gamma delta'), isTrue);
      final before = editing.selectedElement!.bounds!;
      final sourceGeometry = PdfPageGeometry(
        cropBox: editing.document.page(0).cropBox,
        rotation: 0,
        viewSize: const Size(612, 792),
      );
      final sourceRect = sourceGeometry.toViewRect(before);
      final sourceX = (before.left + before.right) / 2;
      final sourceY = (before.bottom + before.top) / 2;

      expect(
        editing.moveSelectedElementToPage(
          1,
          sourceX: sourceX,
          sourceY: sourceY,
          targetX: 300,
          targetY: 400,
        ),
        isTrue,
      );

      final targetGeometry = PdfPageGeometry(
        cropBox: editing.document.page(1).cropBox,
        rotation: 90,
        viewSize: const Size(792, 612),
      );
      final movedRect = targetGeometry.toViewRect(
        editing.selectedElement!.bounds!,
      );
      expect(movedRect.center,
          offsetMoreOrLessEquals(targetGeometry.toViewOffset(300, 400)));
      expect(movedRect.size.width, closeTo(sourceRect.width, 0.1));
      expect(movedRect.size.height, closeTo(sourceRect.height, 0.1));
    });
  });

  group('dragging page content in the viewer', () {
    const scale = 800 / 612;
    Offset view(double x, double y) => Offset(x * scale, (792 - y) * scale);

    /// The overlay's preview painter, where the drag's floating artwork and
    /// the selection chrome are staged.
    dynamic overlayPainter(WidgetTester tester) => tester
        .widgetList<CustomPaint>(find.descendant(
          of: find.byType(EditingPageOverlay),
          matching: find.byType(CustomPaint),
        ))
        .map((paint) => paint.painter)
        .singleWhere(
          (painter) =>
              painter.runtimeType.toString() == '_EditingPreviewPainter',
        );

    /// The overlay's own MouseRegion cursor - what the system shows on hover.
    MouseCursor regionCursor(WidgetTester tester) {
      final paint = find
          .descendant(
              of: find.byType(EditingPageOverlay),
              matching: find.byType(CustomPaint))
          .first;
      final region =
          find.ancestor(of: paint, matching: find.byType(MouseRegion)).first;
      return tester.widget<MouseRegion>(region).cursor;
    }

    /// A mouse hovering the overlay. One pointer per test - the binding is
    /// shared across a file, so a second added pointer on the same device
    /// trips the mouse tracker.
    Future<TestGesture> hover(WidgetTester tester) async {
      final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await g.addPointer(location: const Offset(5, 5));
      addTearDown(g.removePointer);
      await tester.pump();
      return g;
    }

    Future<void> hoverTo(
        WidgetTester tester, TestGesture g, Offset target) async {
      await g.moveTo(target);
      await tester.pump();
    }

    Future<void> drag(WidgetTester tester, Offset from, Offset to) async {
      final gesture = await tester.startGesture(from);
      await gesture.moveTo(Offset.lerp(from, to, 0.5)!);
      await gesture.moveTo(to);
      await gesture.up();
      await tester.pump();
    }

    Future<PdfEditingController> pumpEditor(
      WidgetTester tester, {
      Uint8List? bytes,
      PdfPageLayout pageLayout = const PdfPageLayout.verticalContinuous(),
    }) async {
      final editing =
          PdfEditingController(bytes ?? buildParagraphPdf(mixedContent));
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
              pageLayout: pageLayout,
            ),
          ),
        ),
      ));
      await tester.pump();
      return editing;
    }

    testWidgets('a drag on a selected text run repositions it', (tester) async {
      final editing = await pumpEditor(tester);
      editing.tool = PdfEditTool.content;
      await tester.pump();
      expect(selectElementByText(editing, 'Alpha beta gamma delta'), isTrue);
      await tester.pump();

      final secondBefore = bottomOf(editing, 'epsilon zeta eta theta');
      await drag(tester, view(100, 703), view(160, 603));

      expect(bottomOf(editing, 'Alpha beta gamma delta'),
          closeTo(700 - 2.4 - 100, 1));
      expect(
          textRuns(editing.document)
              .firstWhere((r) => r.text == 'Alpha beta gamma delta')
              .text,
          'Alpha beta gamma delta');
      expect(bottomOf(editing, 'epsilon zeta eta theta'),
          closeTo(secondBefore, 1));
      expect(editing.selectedElement?.text, 'Alpha beta gamma delta',
          reason: 'the run stays selected, ready for another nudge');
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
    });

    testWidgets('a drag grabs an unselected element in the same gesture',
        (tester) async {
      final editing = await pumpEditor(tester);
      editing.tool = PdfEditTool.content;
      await tester.pump();
      expect(editing.selectedElement, isNull);

      await drag(tester, view(140, 620), view(140, 670));

      expect(editing.selectedElement?.kind, PdfElementKind.path);
      expect(editing.selectedElement!.bounds!.bottom, closeTo(650, 1));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
    });

    testWidgets('the selected element hovers as draggable', (tester) async {
      final editing = await pumpEditor(tester);
      editing.tool = PdfEditTool.content;
      await tester.pump();

      final mouse = await hover(tester);

      // before selecting, an element under the pointer is click-to-select
      await hoverTo(tester, mouse, view(140, 620));
      expect(regionCursor(tester), SystemMouseCursors.click);

      expect(editing.selectElementAt(0, 140, 620), isTrue);
      await tester.pump();
      await hoverTo(tester, mouse, view(141, 621));
      expect(regionCursor(tester), SystemMouseCursors.move);

      // empty page area is neither
      await hoverTo(tester, mouse, view(450, 500));
      expect(regionCursor(tester), SystemMouseCursors.basic);
    });

    testWidgets('the drag floats the element alone, over a clean page',
        (tester) async {
      final editing = await pumpEditor(tester);
      editing.tool = PdfEditTool.content;
      await tester.pump();
      expect(editing.selectElementAt(0, 140, 620), isTrue);
      // the pair renders off the selection, deferred past a frame
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final from = view(140, 620);
      final gesture = await tester.startGesture(from);
      await gesture.moveTo(from + const Offset(10, 10));
      await gesture.moveTo(from + const Offset(40, 25));
      await tester.pump();

      final painter = overlayPainter(tester);
      expect(painter.elementLiftOffset, const Offset(40, 25),
          reason: 'the float tracks the pointer');
      expect(painter.elementLiftFrom, isNotNull,
          reason: 'the resting footprint is where the clean page shows');
      expect(painter.elementClean, isA<ui.Picture>(),
          reason: 'the page without the element fills the hole it leaves');
      expect(painter.elementOnly, isA<ui.Picture>(),
          reason: 'the element alone is what travels - not a clip of the '
              'page, which would carry whatever shares its box');
      expect(painter.elementLiftSettled, isFalse,
          reason: 'mid-drag the clean page is clipped to the footprint');
      // the chrome box travels with it
      expect(painter.elementRect!.center - painter.elementLiftFrom!.center,
          const Offset(40, 25));

      await gesture.up();
      await tester.pump();

      // the pair is held past the commit, now unclipped, so the page does not
      // blank while the edited revision re-renders
      final after = overlayPainter(tester);
      expect(after.elementClean, isA<ui.Picture>());
      expect(after.elementOnly, isA<ui.Picture>());
      expect(after.elementLiftSettled, isTrue,
          reason: 'settled paints the whole page, covering the dropped raster');
      expect(after.elementLiftOffset, const Offset(40, 25),
          reason: 'the afterimage sits where the element was dropped');
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
    });

    testWidgets('dropping content on another page re-homes it there',
        (tester) async {
      final editing = await pumpEditor(
        tester,
        bytes: buildTwoPageContentPdf(),
        pageLayout: const PdfPageLayout.horizontalContinuous(),
      );
      editing.tool = PdfEditTool.content;
      await tester.pump();
      expect(selectElementByText(editing, 'Alpha beta gamma delta'), isTrue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      final overlays = find.byType(EditingPageOverlay);
      expect(overlays, findsNWidgets(2));
      final sourcePage = tester.getRect(overlays.at(0));
      final targetPage = tester.getRect(overlays.at(1));
      final sourceGeometry = PdfPageGeometry(
        cropBox: editing.document.page(0).cropBox,
        rotation: 0,
        viewSize: sourcePage.size,
      );
      final targetGeometry = PdfPageGeometry(
        cropBox: editing.document.page(1).cropBox,
        rotation: 0,
        viewSize: targetPage.size,
      );
      final from = sourcePage.topLeft + sourceGeometry.toViewOffset(100, 703);
      final to = targetPage.topLeft + targetGeometry.toViewOffset(160, 500);

      final gesture = await tester.startGesture(
        from,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(Offset.lerp(from, to, 0.5)!);
      await gesture.moveTo(to);
      await tester.pump();

      expect(
        tester.widgetList<CustomPaint>(find.byType(CustomPaint)).where(
            (paint) =>
                paint.painter.runtimeType.toString() ==
                '_MoveDragPreviewPainter'),
        isNotEmpty,
        reason: 'the isolated content paints over the destination page',
      );

      await gesture.up();
      await tester.pump();

      expect(editing.selectedElementPage, 1);
      expect(editing.selectedElement?.text, 'Alpha beta gamma delta');
      expect(
        editing.elementsOn(0).elements.map((element) => element.text),
        isNot(contains('Alpha beta gamma delta')),
      );
      final moved = editing.selectedElement!.bounds!;
      expect((moved.left + moved.right) / 2, greaterThan(100));
      expect((moved.bottom + moved.top) / 2, closeTo(500, 2));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
    });

    testWidgets('arrow keys nudge the selected element in the viewer',
        (tester) async {
      final editing = await pumpEditor(tester);
      editing.tool = PdfEditTool.content;
      await tester.pump();
      // focus the viewer's shortcut scope without selecting anything
      await tester.tapAt(view(450, 500), kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 400));

      expect(selectElementByText(editing, 'Alpha beta gamma delta'), isTrue);
      await tester.pump();
      final before = bottomOf(editing, 'Alpha beta gamma delta');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(bottomOf(editing, 'Alpha beta gamma delta'),
          closeTo(before + 1, 0.05));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(editing.selectedElement!.bounds!.left, closeTo(82, 0.05));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
    });

    testWidgets('a click with the content tool selects without moving',
        (tester) async {
      final editing = await pumpEditor(tester);
      editing.tool = PdfEditTool.content;
      await tester.pump();

      final before = boundsOf(editing, 2);
      await tester.tapAt(view(140, 620));
      // the tap handler waits out the double-tap window before acting
      await tester.pump(const Duration(milliseconds: 400));

      expect(editing.selectedElement?.kind, PdfElementKind.path);
      expect(editing.selectedElement!.bounds!.bottom,
          closeTo(before.bottom, 0.01));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
    });
  });
}
