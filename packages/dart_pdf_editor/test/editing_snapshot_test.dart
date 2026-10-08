// The Snapshot tool (PdfEditTool.snapshot): drag a region to capture it
// as a raster image (handed to PdfViewer.onSnapshot) AND as detached
// vector graphics kept on the clipboard for pasting back into the PDF.
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    // controllers share the process-wide snapshot clipboard by default; start
    // each test from empty so one test's capture can't leak into the next.
    PdfSnapshotClipboard.instance.clear();
    PdfAnnotationSnapshotClipboard.instance.clear();
  });

  group('PdfEditingController snapshot clipboard', () {
    test('PDF import replaces the clipboard, shares vectors, and undoes once',
        () {
      final editing = PdfEditingController(buildMultiPagePdf(2));
      addTearDown(editing.dispose);
      editing.addRectangle(0, const PdfRect(10, 10, 30, 30));
      editing.selectAnnotation(0, 0);
      editing.copySelectedAnnotations();
      final bytes = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)))
          .captureVectorSnapshot(0, const PdfRect(60, 700, 220, 740))
          .toPdfBytes();
      final before = Uint8List.fromList(editing.bytes);
      expect(editing.pasteSnapshotBytes(bytes, 1, at: (300, 400)), isTrue);
      expect(editing.hasAnnotationClipboard, isFalse);
      expect(editing.document.page(1).annotations.single.rect,
          const PdfRect(220, 380, 380, 420));
      final firstSnapshot = editing.snapshotClipboard.snapshot;
      editing.undo();
      expect(editing.bytes, before);
      expect(editing.snapshotClipboard.snapshot, same(firstSnapshot));
      editing.redo();
      expect(editing.document.page(1).annotations, hasLength(1));
      final tab = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(tab.dispose);
      expect(tab.pasteSnapshot(0), isTrue);
      expect(tab.document.page(0).annotations.single.subtype, 'Stamp');
    });

    test('repeat PDF imports preserve the snapshot and position cascade', () {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      final pdf = PdfEditor(editing.document)
          .captureVectorSnapshot(0, const PdfRect(0, 0, 100, 50))
          .toPdfBytes();
      expect(editing.pasteSnapshotBytes(pdf, 0), isTrue);
      final snapshot = editing.snapshotClipboard.snapshot;
      final first = editing.document.page(0).annotations.single.rect;
      expect(editing.pasteSnapshotBytes(Uint8List.fromList(pdf), 0), isTrue);
      expect(editing.snapshotClipboard.snapshot, same(snapshot));
      expect(
          editing.document.page(0).annotations.last.rect.left, first.left + 12);
    });

    test('invalid PDF or target leaves the document and clipboards intact', () {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      editing.addRectangle(0, const PdfRect(10, 10, 30, 30));
      editing.selectAnnotation(0, 0);
      editing.copySelectedAnnotations();
      final before = Uint8List.fromList(editing.bytes);
      final pdf = editing
          .captureVectorSnapshot(0, const PdfRect(0, 0, 100, 50))
          .toPdfBytes();
      expect(editing.pasteSnapshotBytes(Uint8List.fromList([1, 2, 3]), 0),
          isFalse);
      expect(editing.pasteSnapshotBytes(pdf, -1), isFalse);
      expect(editing.pasteSnapshotBytes(pdf, 1), isFalse);
      expect(editing.bytes, before);
      expect(editing.hasAnnotationClipboard, isTrue);
      expect(editing.hasSnapshotClipboard, isFalse);
    });

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
      expect(editing.snapshotClipboard.snapshot, isNull);
    });

    test('copying without a paste point cascades repeat pastes', () {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      editing.copyVectorSnapshot(0, const PdfRect(60, 700, 220, 740));
      expect(editing.snapshotClipboard.snapshot, isNotNull);

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
      final res = cos.resolve(stamp.normalAppearance!.dictionary['Resources'])
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
      expect(editing.recolorSnapshotSelected(const Color(0xFF00FF00)), isFalse);
    });

    test('a snapshot pasted at a point centers there, off the page included',
        () {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      editing.copyVectorSnapshot(0, const PdfRect(0, 0, 600, 780));
      expect(editing.pasteSnapshot(0, at: (10, 10)), isTrue);
      final rect = editing.document.page(0).annotations.single.rect;
      // the 600x780 region centers on the point it was pasted at, running
      // off three sides of the 612x792 crop box
      expect(rect.left, closeTo(-290, 1e-6));
      expect(rect.bottom, closeTo(-380, 1e-6));
      expect(rect.right, closeTo(310, 1e-6));
      expect(rect.top, closeTo(400, 1e-6));
    });

    test('the point-less snapshot cascade stays tethered to the page', () {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      editing.copyVectorSnapshot(0, const PdfRect(520, 20, 600, 80));
      final box = editing.document.page(0).cropBox;
      for (var i = 0; i < 30; i++) {
        expect(editing.pasteSnapshot(0), isTrue);
      }
      const tether = PdfEditingController.pageTether;
      for (final annotation in editing.document.page(0).annotations) {
        final rect = annotation.rect;
        expect(math.min(rect.right, box.right) - math.max(rect.left, box.left),
            greaterThanOrEqualTo(tether - 1e-6));
        expect(math.min(rect.top, box.top) - math.max(rect.bottom, box.bottom),
            greaterThanOrEqualTo(tether - 1e-6));
      }
    });

    test('a snapshot captured in one tab pastes as vector in another', () {
      SharedPreferences.setMockInitialValues({});
      // two documents ("tabs") that share one snapshot clipboard, mirroring
      // the app's process-wide PdfSnapshotClipboard.instance
      final clip = PdfSnapshotClipboard();
      final tabA =
          PdfEditingController(buildMultiPagePdf(1), snapshotClipboard: clip);
      final tabB =
          PdfEditingController(buildMultiPagePdf(1), snapshotClipboard: clip);
      addTearDown(tabA.dispose);
      addTearDown(tabB.dispose);

      // capture a region in tab A
      tabA.copyVectorSnapshot(0, const PdfRect(60, 700, 220, 740));
      // tab B sees it on the shared clipboard - so ⌘V pastes vector, not the
      // raster the capture also dropped on the system clipboard
      expect(tabB.hasSnapshotClipboard, isTrue);
      expect(tabB.pasteSnapshot(0, at: (300, 400)), isTrue);

      final stamp = tabB.document.page(0).annotations.single;
      expect(stamp.subtype, 'Stamp');
      final ap = latin1
          .decode(tabB.document.cos.decodeStreamData(stamp.normalAppearance!));
      // the appearance *draws* the captured form - it is vector, not an image
      expect(ap, contains('/Cap Do'));
    });

    test('the shared clipboard survives closing the source tab', () {
      SharedPreferences.setMockInitialValues({});
      final clip = PdfSnapshotClipboard();
      final tabA =
          PdfEditingController(buildMultiPagePdf(1), snapshotClipboard: clip);
      final tabB =
          PdfEditingController(buildMultiPagePdf(1), snapshotClipboard: clip);
      addTearDown(tabB.dispose);

      tabA.copyVectorSnapshot(0, const PdfRect(60, 700, 220, 740));
      // the source tab is closed before the paste (the snapshot is detached)
      tabA.dispose();

      expect(tabB.hasSnapshotClipboard, isTrue);
      expect(tabB.pasteSnapshot(0, at: (300, 400)), isTrue);
      expect(tabB.document.page(0).annotations.single.subtype, 'Stamp');
    });
  });

  group('cropping a pasted snapshot', () {
    test('the crop tool trims a vector snapshot and resets it', () {
      final editing = PdfEditingController(buildMultiPagePdf(1),
          snapshotClipboard: PdfSnapshotClipboard());
      addTearDown(editing.dispose);
      editing.copyVectorSnapshot(0, const PdfRect(60, 700, 220, 740));
      expect(editing.pasteSnapshot(0, at: (300, 400)), isTrue);
      editing.selectAnnotation(0, 0);
      final rect = editing.selectedAnnotation!.rect;
      expect(editing.canCropSelected, isTrue);
      expect(editing.selectedHasCrop, isFalse);

      // keep the left half
      editing.cropSelectedImage(PdfRect(
          rect.left, rect.bottom, rect.left + rect.width / 2, rect.top));
      final cropped = editing.selectedAnnotation!;
      expect(cropped.rect.width, closeTo(rect.width / 2, 1e-6));
      expect(
          PdfEditor(editing.document).isVectorSnapshotStamp(cropped), isTrue);
      expect(editing.selectedHasCrop, isTrue);

      // a second crop composes against the capture, not the cropped box
      final half = cropped.rect;
      editing.cropSelectedImage(PdfRect(
          half.left, half.bottom + half.height / 2, half.right, half.top));
      final crop = PdfEditor(editing.document)
          .vectorSnapshotCrop(editing.selectedAnnotation!)!;
      expect(crop.left, closeTo(0, 1e-6));
      expect(crop.right, closeTo(0.5, 1e-6));
      expect(crop.bottom, closeTo(0.5, 1e-6));
      expect(crop.top, closeTo(1, 1e-6));

      editing.resetSelectedImageCrop();
      final restored = editing.selectedAnnotation!;
      expect(editing.selectedHasCrop, isFalse);
      expect(restored.rect.left, closeTo(rect.left, 1e-6));
      expect(restored.rect.right, closeTo(rect.right, 1e-6));
      expect(restored.rect.bottom, closeTo(rect.bottom, 1e-6));
      expect(restored.rect.top, closeTo(rect.top, 1e-6));
    });

    test('an ordinary text stamp still cannot be cropped', () {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      editing.addStamp(0, const PdfRect(100, 100, 220, 140), 'APPROVED');
      editing.selectAnnotation(0, 0);
      expect(editing.canCropSelected, isFalse);
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
      final pdf = PdfDocument.open(captured!.pdfBytes);
      expect(pdf.pageCount, 1);
      expect(pdf.page(0).mediaBox.width, captured!.vector.displayWidth);
      // PNG magic number
      expect(captured!.pngBytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
      // the vector half pastes back into the document
      expect(editing.pasteSnapshot(1, at: (300, 400)), isTrue);
      expect(editing.document.page(1).annotations.single.subtype, 'Stamp');
    });

    testWidgets('tapping out a polygon captures the traced region',
        (tester) async {
      PdfSnapshot? captured;
      final editing = await pumpEditor(tester,
          onSnapshot: (context, snap) async => captured = snap);
      editing.tool = PdfEditTool.snapshot;
      await tester.pump();

      await tester.tapAt(view(100, 740));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tapAt(view(260, 740));
      await tester.pump(const Duration(milliseconds: 400));
      // two taps are a line, not a region: nothing captured yet
      expect(editing.hasSnapshotClipboard, isFalse);
      await tester.tapAt(view(100, 640));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(view(100, 640));
      await tester.pump();
      // the vector half lands synchronously on the double-tap
      expect(editing.hasSnapshotClipboard, isTrue);
      await tester.runAsync(() async {
        // captureSnapshot renders + encodes a PNG (toImage) - let it finish
        for (var i = 0; i < 50 && captured == null; i++) {
          await tester.pump(const Duration(milliseconds: 20));
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      expect(captured, isNotNull);
      final polygon = captured!.pagePolygon!;
      expect(polygon, hasLength(3),
          reason: 'three tapped vertices, the double-tap not double-counted');
      expect(polygon.first.$1, closeTo(100, 1));
      expect(polygon.first.$2, closeTo(740, 1));
      // the box is the polygon's bounds
      expect(captured!.pageRect.left, closeTo(100, 1));
      expect(captured!.pageRect.right, closeTo(260, 1));
      expect(captured!.pageRect.bottom, closeTo(640, 1));
      expect(captured!.pageRect.top, closeTo(740, 1));
      // the vector half carries the polygon clip
      final exported = PdfDocument.open(captured!.pdfBytes);
      expect(latin1.decode(exported.page(0).contentBytes()), contains('W\nn'));
      // the raster is cut to the triangle: its far corner is transparent,
      // a point inside it is opaque paper
      final pixels = await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(captured!.pngBytes);
        final frame = await codec.getNextFrame();
        final image = frame.image;
        final data = await image.toByteData();
        final size = (image.width, image.height);
        image.dispose();
        return (data!, size);
      });
      final (data, (w, h)) = pixels!;
      int alphaAt(int x, int y) => data.getUint8((y * w + x) * 4 + 3);
      expect(alphaAt(w - 2, h - 2), 0);
      expect(alphaAt(4, 4), 255);
      // nothing was written to the document by the capture itself
      expect(editing.document.page(0).annotations, isEmpty);
      expect(editing.isModified, isFalse);
      await tester.pump(const Duration(milliseconds: 400));
    });
  });
}
