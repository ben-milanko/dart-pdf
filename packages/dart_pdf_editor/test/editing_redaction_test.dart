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

    testWidgets('burning a redaction refreshes the stale low-res preview',
        (tester) async {
      // Regression: the burn swaps to a same-geometry revision, which used to
      // *rebind* (keep, and mark fresh) the cached low-res preview — so a fast
      // scroll right after redacting flashed the now-removed content, and the
      // on-screen render could never replace it. The changed page's preview
      // must be dropped at the swap so it refreshes to the redacted content.
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
              pagePreviews: true,
              document: editing.document,
              controller: viewer,
              editing: editing,
            ),
          ),
        ),
      ));
      await tester.pump();
      final cache = viewer.debugPreviewCache!;

      // the redaction region in preview pixels: previews are 200px on the
      // longest side, so a 612x792 page scales by 200/792; the box
      // [60,712]-[200,748] (page space, y-up) maps to roughly x∈[15,50],
      // y∈[11,20] from the top. Sample its center.
      Future<int> previewLuma(int px, int py) async {
        final image = cache.imageFor(0);
        if (image == null) return -1;
        late int luma;
        await tester.runAsync(() async {
          final data =
              (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
          final i = (py * image.width + px) * 4;
          luma = (data.getUint8(i) + data.getUint8(i + 1) + data.getUint8(i + 2)) ~/ 3;
        });
        image.dispose();
        return luma;
      }

      // seed the preview from the pre-redaction content: the region is mostly
      // white page (thin "Page 1" glyphs), so it reads light
      await tester.runAsync(
          () => cache.renderPreview(0, editing.document.page(0)));
      expect(await previewLuma(32, 15), greaterThan(140),
          reason: 'pre-redaction preview is light page');

      editing.addRedaction(0, const PdfRect(60, 712, 200, 748));
      editing.applyRedactions();
      await tester.pump();

      // let the on-screen render refresh the (now-dropped) preview; in the
      // old rebind path it stayed "fresh" and this never converged
      var luma = -1;
      for (var i = 0; i < 60; i++) {
        await tester
            .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
        luma = await previewLuma(32, 15);
        if (luma >= 0 && luma < 80) break;
      }
      expect(luma, lessThan(80),
          reason: 'preview now shows the solid redaction fill, not old text');
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
