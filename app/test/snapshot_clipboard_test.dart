// The Snapshot tool copies the captured region to the system clipboard as a
// PNG (on top of keeping a vector copy for in-app paste-back). Flutter's
// built-in Clipboard is text-only, so the app routes the PNG through
// super_clipboard — behind the ImageClipboardWriter seam these tests fake.
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/image_clipboard.dart';

void main() {
  // A throwaway PdfSnapshot whose pngBytes are the only field the handler reads.
  PdfSnapshot makeSnapshot(Uint8List png) {
    SharedPreferences.setMockInitialValues({});
    final editing = PdfEditingController(buildMultiPagePdf(1));
    addTearDown(editing.dispose);
    final vector =
        editing.captureVectorSnapshot(0, const PdfRect(60, 700, 220, 740));
    return PdfSnapshot(
      pageIndex: 0,
      pageRect: const PdfRect(60, 700, 220, 740),
      pngBytes: png,
      vector: vector,
    );
  }

  testWidgets('handler writes the PNG bytes and reports success',
      (tester) async {
    Uint8List? written;
    bool? reported;
    final handler = clipboardSnapshotHandler(
      writer: (bytes) async {
        written = bytes;
        return true;
      },
      onResult: (copied) => reported = copied,
    );

    final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);
    await tester.pumpWidget(
      Builder(builder: (context) {
        handler(context, makeSnapshot(png));
        return const SizedBox();
      }),
    );
    await tester.pump();

    expect(written, png);
    expect(reported, isTrue);
  });

  testWidgets('a writer that returns false reports failure', (tester) async {
    bool? reported;
    final handler = clipboardSnapshotHandler(
      writer: (bytes) async => false,
      onResult: (copied) => reported = copied,
    );

    await tester.pumpWidget(
      Builder(builder: (context) {
        handler(context, makeSnapshot(Uint8List(4)));
        return const SizedBox();
      }),
    );
    await tester.pump();

    expect(reported, isFalse);
  });

  testWidgets('a throwing writer is caught and reports failure',
      (tester) async {
    bool? reported;
    final handler = clipboardSnapshotHandler(
      writer: (bytes) async => throw StateError('no clipboard'),
      onResult: (copied) => reported = copied,
    );

    await tester.pumpWidget(
      Builder(builder: (context) {
        handler(context, makeSnapshot(Uint8List(4)));
        return const SizedBox();
      }),
    );
    await tester.pump();

    expect(reported, isFalse);
  });

  testWidgets('the default writer hands a PNG item to super_clipboard',
      (tester) async {
    // copyPngToClipboard is the production ImageClipboardWriter. There's no
    // native clipboard channel under flutter_test, so the plugin call throws —
    // which the handler turns into a copied=false result. This exercises the
    // real writer + the handler's catch path together.
    bool? reported;
    final handler = clipboardSnapshotHandler(
      // no writer: → defaults to copyPngToClipboard
      onResult: (copied) => reported = copied,
    );

    await tester.pumpWidget(
      Builder(builder: (context) {
        handler(context, makeSnapshot(Uint8List.fromList([0x89, 0x50, 1, 2])));
        return const SizedBox();
      }),
    );
    // let the async plugin call reject and the catch run
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(reported, isFalse);
  });

  group('Snapshot tool through the viewer', () {
    const scale = 800 / 612;
    Offset view(double x, double y) => Offset(x * scale, (792 - y) * scale);

    testWidgets('dragging a region routes a real PNG to the clipboard writer',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildMultiPagePdf(1));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);

      Uint8List? written;
      bool? reported;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: editing,
            builder: (context, _) => PdfViewer(
              initialFit: PdfViewerFit.width,
              document: editing.document,
              controller: viewer,
              editing: editing,
              onSnapshot: clipboardSnapshotHandler(
                writer: (bytes) async {
                  written = bytes;
                  return true;
                },
                onResult: (copied) => reported = copied,
              ),
            ),
          ),
        ),
      ));
      await tester.pump();

      editing.tool = PdfEditTool.snapshot;
      await tester.pump();

      await tester.runAsync(() async {
        final gesture = await tester.startGesture(view(70, 740));
        await gesture.moveTo(view(150, 720));
        await gesture.moveTo(view(220, 700));
        await gesture.up();
        // captureSnapshot rasterizes + PNG-encodes (toImage) — let it finish.
        for (var i = 0; i < 50 && written == null; i++) {
          await tester.pump(const Duration(milliseconds: 20));
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      expect(reported, isTrue);
      expect(written, isNotNull);
      // PNG magic number — the captured raster reached the clipboard writer.
      expect(written!.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
      // the vector half still lands on the in-app clipboard for paste-back.
      expect(editing.hasSnapshotClipboard, isTrue);
    });
  });
}
