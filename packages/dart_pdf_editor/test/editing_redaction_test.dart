import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  PdfEditingController controller([int pages = 1]) {
    SharedPreferences.setMockInitialValues({});
    return PdfEditingController(buildMultiPagePdf(pages));
  }

  group('controller redaction', () {
    test('addRedaction marks a /Redact region without removing content', () {
      final editing = controller();
      addTearDown(editing.dispose);
      // "Page 1" sits at 72,720 (24pt) — mark a box over it
      editing.addRedaction(0, const PdfRect(60, 715, 200, 748));

      expect(editing.hasRedactionMarks, isTrue);
      final redact = editing.document
          .page(0)
          .annotations
          .singleWhere((a) => a.subtype == 'Redact');
      expect(redact, isNotNull);
      // marking is undoable — nothing burned yet
      expect(editing.canUndo, isTrue);
      expect(latin1.decode(editing.bytes, allowInvalid: true),
          contains('Page 1'));
    });

    test('applyRedactions burns the marks irreversibly', () {
      final editing = controller();
      addTearDown(editing.dispose);
      editing.addRedaction(0, const PdfRect(60, 715, 200, 748));

      expect(editing.applyRedactions(), isTrue);

      // the secret is gone from the saved bytes, not merely covered
      expect(latin1.decode(editing.bytes, allowInvalid: true),
          isNot(contains('Page 1')));
      // the /Redact mark is gone
      expect(editing.document.page(0).annotations, isEmpty);
      // burning is irreversible: undo history is cleared, doc stays modified
      expect(editing.canUndo, isFalse);
      expect(editing.canRedo, isFalse);
      expect(editing.isModified, isTrue);
      expect(editing.hasRedactionMarks, isFalse);
    });

    test('applyRedactions is a no-op with nothing marked', () {
      final editing = controller();
      addTearDown(editing.dispose);
      expect(editing.applyRedactions(), isFalse);
      expect(editing.isModified, isFalse);
    });

    testWidgets('the burned page renders with a solid fill over the region',
        (tester) async {
      final editing = controller();
      addTearDown(editing.dispose);
      editing.addRedaction(0, const PdfRect(60, 712, 200, 748));
      editing.applyRedactions();

      late ui.Image image;
      late ByteData data;
      await tester.runAsync(() async {
        image = await PdfPageRenderer.renderImage(editing.document.page(0));
        data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      });
      // sample the middle of the redacted region (page 72,730 → raster y-down)
      int at(int x, int y) {
        final i = (y * image.width + x) * 4;
        return (data.getUint8(i) << 16) |
            (data.getUint8(i + 1) << 8) |
            data.getUint8(i + 2);
      }

      // 612x792 raster at ratio 1; region center ~ (130, 730) page → (130, 62)
      expect(at(130, 62), 0x000000, reason: 'redacted area is solid black');
      image.dispose();
    });

    test('addRedactionQuads marks per-page text runs', () {
      final editing = controller(2);
      addTearDown(editing.dispose);
      editing.addRedactionQuads({
        0: [const PdfRect(60, 715, 200, 748)],
        1: const [],
      });
      expect(
          editing.document
              .page(0)
              .annotations
              .where((a) => a.subtype == 'Redact'),
          hasLength(1));
      expect(editing.document.page(1).annotations, isEmpty);
    });
  });

  group('redaction in the viewer', () {
    const scale = 800 / 612;
    Offset view(double x, double y) => Offset(x * scale, (792 - y) * scale);

    Future<void> drag(WidgetTester tester, Offset from, Offset to) async {
      final gesture = await tester.startGesture(from);
      await gesture.moveTo(Offset.lerp(from, to, 0.5)!);
      await gesture.moveTo(to);
      await gesture.up();
      await tester.pump();
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

    testWidgets('dragging out a region marks a redaction', (tester) async {
      final editing = await pumpEditor(tester);
      editing.tool = PdfEditTool.redact;
      await tester.pump();

      await drag(tester, view(60, 748), view(200, 715));
      await tester.pump();

      expect(editing.hasRedactionMarks, isTrue);
      final redact =
          editing.document.page(0).annotations.singleWhere((a) => a.subtype == 'Redact');
      expect(redact, isNotNull);
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
    });
  });

  group('toolbar apply flow', () {
    Future<PdfEditingController> pumpToolbar(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: ListenableBuilder(
            listenable: editing,
            builder: (context, _) => PdfEditingToolbar(
              controller: editing,
              viewerController: viewer,
            ),
          ),
        ),
      ));
      await tester.pump();
      return editing;
    }

    testWidgets('apply button confirms before burning', (tester) async {
      final editing = await pumpToolbar(tester);
      editing
        ..tool = PdfEditTool.redact
        ..addRedaction(0, const PdfRect(60, 715, 200, 748));
      await tester.pump();

      // the apply button is present while the tool is armed and marks exist
      final apply = find.byKey(const ValueKey('pdf-apply-redactions'));
      await tester.ensureVisible(apply);
      await tester.tap(apply);
      await tester.pumpAndSettle();

      // a confirm dialog warns it is irreversible
      expect(find.byKey(const ValueKey('pdf-redaction-confirm')), findsOneWidget);

      // cancel leaves the mark untouched
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(editing.hasRedactionMarks, isTrue);

      // confirm burns it
      await tester.tap(apply);
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const ValueKey('pdf-redaction-confirm-apply')));
      await tester.pumpAndSettle();

      expect(editing.hasRedactionMarks, isFalse);
      expect(latin1.decode(editing.bytes, allowInvalid: true),
          isNot(contains('Page 1')));
    });
  });
}
