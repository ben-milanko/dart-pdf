// The Snapshot tool (PdfEditTool.snapshot): drag a region to capture it
// as a raster image (handed to PdfViewer.onSnapshot) AND as detached
// vector graphics kept on the clipboard for pasting back into the PDF.
import 'dart:convert';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('PdfEditingController snapshot clipboard', () {
    test('copyVectorSnapshot fills the clipboard; paste adds a vector stamp',
        () {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(2));
      addTearDown(editing.dispose);

      expect(editing.hasSnapshotClipboard, isFalse);
      editing.copyVectorSnapshot(0, const PdfRect(60, 700, 220, 740));
      expect(editing.hasSnapshotClipboard, isTrue);

      expect(editing.pasteSnapshot(1, at: (300, 400)), isTrue);
      final stamp = editing.document.page(1).annotations.single;
      expect(stamp.subtype, 'Stamp');
      // natural size (160x40) centered on the paste point
      expect(stamp.rect.width, closeTo(160, 1e-6));
      expect(stamp.rect.height, closeTo(40, 1e-6));
      expect((stamp.rect.left + stamp.rect.right) / 2, closeTo(300, 1e-6));
      // pasting it back is vector: the appearance draws the captured form
      final ap =
          latin1.decode(editing.document.cos.decodeStreamData(stamp.normalAppearance!));
      expect(ap, contains('/Cap Do'));
      // the pasted stamp is selected for immediate move/resize
      expect(editing.hasAnnotationSelection, isTrue);
    });

    test('pasteSnapshot with no clipboard is a no-op', () {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      expect(editing.pasteSnapshot(0), isFalse);
      expect(editing.isModified, isFalse);
    });

    test('the snapshot clipboard clamps an oversized region into the page', () {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      editing.copyVectorSnapshot(0, const PdfRect(0, 0, 600, 780));
      expect(editing.pasteSnapshot(0, at: (10, 10)), isTrue);
      final rect = editing.document.page(0).annotations.single.rect;
      // pinned to the low edge of the 612x792 crop box
      expect(rect.left, closeTo(0, 1e-6));
      expect(rect.bottom, closeTo(0, 1e-6));
    });
  });

  group('snapshot tool in the viewer', () {
    const scale = 800 / 612;
    Offset view(double x, double y) => Offset(x * scale, (792 - y) * scale);

    Future<PdfEditingController> pumpEditor(WidgetTester tester,
        {PdfSnapshotHandler? onSnapshot}) async {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(2));
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
              onSnapshot: onSnapshot,
            ),
          ),
        ),
      ));
      await tester.pump();
      return editing;
    }

    testWidgets('dragging a region fills the vector clipboard', (tester) async {
      final editing = await pumpEditor(tester);
      editing.tool = PdfEditTool.snapshot;
      await tester.pump();

      // copyVectorSnapshot runs synchronously on drag-end (no raster needed)
      final gesture = await tester.startGesture(view(70, 740));
      await gesture.moveTo(view(150, 710));
      await gesture.moveTo(view(220, 700));
      await gesture.up();
      await tester.pump();

      expect(editing.hasSnapshotClipboard, isTrue);
      // nothing was written to the document by the capture itself
      expect(editing.document.page(0).annotations, isEmpty);
      expect(editing.isModified, isFalse);
      // drain the viewer's double-tap timer left by the touch gesture
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('the host handler receives a PNG and a vector snapshot',
        (tester) async {
      PdfSnapshot? captured;
      final editing = await pumpEditor(tester,
          onSnapshot: (context, snap) async => captured = snap);
      editing.tool = PdfEditTool.snapshot;
      await tester.pump();

      await tester.runAsync(() async {
        final gesture = await tester.startGesture(view(70, 740));
        await gesture.moveTo(view(150, 720));
        await gesture.moveTo(view(220, 700));
        await gesture.up();
        // captureSnapshot renders + encodes a PNG (toImage) — let it finish
        for (var i = 0; i < 50 && captured == null; i++) {
          await tester.pump(const Duration(milliseconds: 20));
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      expect(captured, isNotNull);
      expect(captured!.pageIndex, 0);
      expect(captured!.pngBytes, isNotEmpty);
      // PNG magic number
      expect(captured!.pngBytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
      // the vector half pastes back into the document
      expect(editing.pasteSnapshot(1, at: (300, 400)), isTrue);
      expect(editing.document.page(1).annotations.single.subtype, 'Stamp');
    });
  });
}
