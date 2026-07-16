// The Snapshot tool (PdfEditTool.snapshot): drag a region to capture it
// as a raster image (handed to PdfViewer.onSnapshot) AND as detached
// vector graphics kept on the clipboard for pasting back into the PDF.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_cos/pdf_cos.dart';
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
      final ap = latin1.decode(
          editing.document.cos.decodeStreamData(stamp.normalAppearance!));
      expect(ap, contains('/Cap Do'));
      // the pasted stamp is selected for immediate move/resize
      expect(editing.hasAnnotationSelection, isTrue);
    });

    test('captureVectorSnapshot reads without filling the clipboard', () {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      final snap =
          editing.captureVectorSnapshot(0, const PdfRect(60, 700, 220, 740));
      expect(snap.region, const PdfRect(60, 700, 220, 740));
      expect(editing.hasSnapshotClipboard, isFalse);
      expect(editing.snapshotClipboard, isNull);
    });

    test('copying without a paste point cascades repeat pastes', () {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      editing.copyVectorSnapshot(0, const PdfRect(60, 700, 220, 740));
      expect(editing.snapshotClipboard, isNotNull);

      expect(editing.pasteSnapshot(0), isTrue);
      final first = editing.document.page(0).annotations.last.rect;
      expect(editing.pasteSnapshot(0), isTrue);
      final second = editing.document.page(0).annotations.last.rect;
      // the second paste cascades 12pt down-right of the first
      expect(second.left, closeTo(first.left + 12, 1e-6));
      expect(second.bottom, closeTo(first.bottom - 12, 1e-6));
    });

    test('copying an annotation clears the snapshot clipboard (last wins)', () {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      editing.addRectangle(0, const PdfRect(10, 10, 60, 60));
      editing.copyVectorSnapshot(0, const PdfRect(60, 700, 220, 740));
      expect(editing.hasSnapshotClipboard, isTrue);

      editing.selectAnnotationAt(0, 35, 35);
      expect(editing.copySelectedAnnotations(), 1);
      // the annotation copy supersedes the snapshot on the clipboard
      expect(editing.hasSnapshotClipboard, isFalse);
      expect(editing.hasAnnotationClipboard, isTrue);
    });

    test('pasteSnapshot with no clipboard is a no-op', () {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      expect(editing.pasteSnapshot(0), isFalse);
      expect(editing.isModified, isFalse);
    });

    test('recolorSnapshotSelected retints the pasted vector snapshot', () {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      editing.copyVectorSnapshot(0, const PdfRect(60, 700, 220, 740));
      expect(editing.pasteSnapshot(0, at: (100, 100)), isTrue);
      // the paste leaves the new stamp selected, ready to recolour
      expect(editing.canRecolorSnapshotSelected, isTrue);
      expect(editing.recolorSnapshotSelected(const Color(0xFFFF0000)), isTrue);

      final stamp = editing.document.page(0).annotations.single;
      final cos = editing.document.cos;
      final res =
          cos.resolve(stamp.normalAppearance!.dictionary['Resources'])
              as CosDictionary;
      final xobj = cos.resolve(res['XObject']) as CosDictionary;
      final cap = cos.resolve(xobj['Cap']) as CosStream;
      // the captured graphics now paint in the chosen ink
      expect(latin1.decode(cos.decodeStreamData(cap)), contains('1 0 0 rg'));
    });

    test('a non-snapshot selection is not recolourable as a snapshot', () {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      editing.addRectangle(0, const PdfRect(10, 10, 60, 60));
      editing.selectAnnotationAt(0, 35, 35);
      expect(editing.hasAnnotationSelection, isTrue);
      expect(editing.canRecolorSnapshotSelected, isFalse);
      expect(
          editing.recolorSnapshotSelected(const Color(0xFF00FF00)), isFalse);
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

    test('a shared clipboard carries a snapshot between sessions (tabs)', () {
      SharedPreferences.setMockInitialValues({});
      final shared = PdfSnapshotClipboard();
      addTearDown(shared.dispose);
      final tabA = PdfEditingController(buildMultiPagePdf(1),
          snapshotClipboard: shared);
      final tabB = PdfEditingController(buildMultiPagePdf(1),
          snapshotClipboard: shared);
      addTearDown(tabA.dispose);
      addTearDown(tabB.dispose);

      // copy in one tab…
      expect(tabB.hasSnapshotClipboard, isFalse);
      tabA.copyVectorSnapshot(0, const PdfRect(60, 700, 220, 740));
      // …and the other can paste it
      expect(tabB.hasSnapshotClipboard, isTrue);
      expect(tabB.pasteSnapshot(0, at: (300, 400)), isTrue);
      expect(tabB.document.page(0).annotations.single.subtype, 'Stamp');
    });

    test('private clipboards (no shared holder) stay independent', () {
      SharedPreferences.setMockInitialValues({});
      final tabA = PdfEditingController(buildMultiPagePdf(1));
      final tabB = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(tabA.dispose);
      addTearDown(tabB.dispose);

      tabA.copyVectorSnapshot(0, const PdfRect(60, 700, 220, 740));
      expect(tabA.hasSnapshotClipboard, isTrue);
      // no shared holder → the copy doesn't leak into the other session
      expect(tabB.hasSnapshotClipboard, isFalse);
    });

    test('pasteSnapshotBytes imports an interchange PDF (Bluebeam interop)',
        () {
      SharedPreferences.setMockInitialValues({});
      // a snapshot serialized to the portable single-page PDF (as a host
      // would read off the OS clipboard from us or another PDF tool)
      final source = PdfDocument.open(buildMultiPagePdf(1));
      final pdfBytes = PdfEditor(source)
          .captureVectorSnapshot(0, const PdfRect(60, 700, 220, 740))
          .toPdfBytes();

      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      expect(editing.pasteSnapshotBytes(pdfBytes, 0, at: (300, 400)), isTrue);
      expect(editing.document.page(0).annotations.single.subtype, 'Stamp');
      // the import also lands on the clipboard for repeat pastes
      expect(editing.hasSnapshotClipboard, isTrue);
    });

    test('pasteSnapshotBytes rejects non-PDF bytes', () {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      expect(
          editing.pasteSnapshotBytes(
              Uint8List.fromList([1, 2, 3, 4]), 0),
          isFalse);
      expect(editing.isModified, isFalse);
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
        // captureSnapshot renders + encodes a PNG (toImage) - let it finish
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
      // the host-facing interchange bytes are a valid single-page PDF (what a
      // host writes to the OS clipboard for Bluebeam) and re-import cleanly
      final interchange = PdfDocument.open(captured!.pdfBytes);
      expect(interchange.pageCount, 1);
      expect(PdfVectorSnapshot.fromPdfBytes(captured!.pdfBytes).displayWidth,
          closeTo(captured!.vector.displayWidth, 1e-6));
      // the vector half pastes back into the document
      expect(editing.pasteSnapshot(1, at: (300, 400)), isTrue);
      expect(editing.document.page(1).annotations.single.subtype, 'Stamp');
    });
  });
}
