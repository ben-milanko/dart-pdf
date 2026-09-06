// The Snapshot tool copies the captured region to the system clipboard as a
// PNG (on top of keeping a vector copy for in-app paste-back). Flutter's
// built-in Clipboard is text-only, so the app routes the PNG through its own
// platform channel - behind the ImageClipboardWriter seam these tests fake.

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/image_clipboard.dart';
import 'package:dart_pdf_editor_app/editor_screen.dart';

void main() {
  setUp(() {
    // controllers share the process-wide snapshot clipboard by default; start
    // each test from empty so one test's capture can't leak into the next.
    PdfSnapshotClipboard.instance.clear();
    PdfAnnotationSnapshotClipboard.instance.clear();
  });

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

  testWidgets('the default writer sends PDF and PNG in one native call',
      (tester) async {
    // copyPngToClipboard is the production ImageClipboardWriter. Its native
    // channel is unavailable under flutter_test, so install a mock handler and
    // assert the default writer sends the captured PNG through it.
    const channel = MethodChannel('dev.milanko.dartpdf/image_clipboard');
    Uint8List? written;
    Uint8List? pdf;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        expect(call.method, 'copySnapshot');
        final args = call.arguments as Map;
        written = args['png'] as Uint8List;
        pdf = args['pdf'] as Uint8List;
        return true;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

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
    // Let the async channel call and handler callback run.
    for (var i = 0; i < 10 && reported == null; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(written, [0x89, 0x50, 1, 2]);
    expect(reported, isTrue);
    expect(
        PdfDocument.open(pdf!).page(0).mediaBox, const PdfRect(0, 0, 160, 40));
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets(
      'older and mobile runners fall back to PNG when PDF is unsupported',
      (tester) async {
    const channel = MethodChannel('dev.milanko.dartpdf/image_clipboard');
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call.method);
      if (call.method == 'copyPng') return true;
      throw MissingPluginException();
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    expect(await copySnapshotToClipboard(Uint8List(2), Uint8List(4)), isTrue);
    expect(await readPdfFromClipboard(), isNull);
    expect(calls, ['copySnapshot', 'copyPng', 'readPdf']);
  });

  testWidgets('PDF reader returns external bytes and respects local ownership',
      (tester) async {
    const channel = MethodChannel('dev.milanko.dartpdf/image_clipboard');
    Uint8List? offered = buildMultiPagePdf(1);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      expect(call.method, 'readPdf');
      return offered == null ? null : {'pdf': offered, 'changeToken': 42};
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    expect((await readPdfFromClipboard())!.bytes, offered);
    expect((await readPdfFromClipboard())!.changeToken, 42);
    offered = null; // runner identifies this process as the current owner
    expect(await readPdfFromClipboard(), isNull);
  });

  testWidgets('the default reader asks the native channel for image bytes',
      (tester) async {
    const channel = MethodChannel('dev.milanko.dartpdf/image_clipboard');
    final image = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2]);
    var calls = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        expect(call.method, 'readImage');
        calls++;
        return image;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final read = await readImageFromClipboard();

    expect(calls, 1);
    expect(read, image);
  });

  testWidgets('the default text reader reads Flutter\'s clipboard on native',
      (tester) async {
    var calls = 0;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        calls++;
        return const <String, Object?>{'text': 'Native clipboard text'};
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    final read = await readTextFromClipboard();

    expect(calls, 1);
    expect(read, 'Native clipboard text');
  });

  testWidgets(
      'local annotation Copy records native precedence without writing bytes',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = PdfEditingPreferences();
    addTearDown(prefs.dispose);
    const channel = MethodChannel('dev.milanko.dartpdf/image_clipboard');
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call.method);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(MaterialApp(
        home: EditorScreen(
      prefs: prefs,
      initialDocument: (bytes: buildMultiPagePdf(1), title: 'Copy.pdf'),
    )));
    await tester.pumpAndSettle();
    final editing = tester.widget<PdfViewer>(find.byType(PdfViewer)).editing!;
    editing.addRectangle(0, const PdfRect(10, 10, 30, 30));
    editing.selectAnnotation(0, 0);
    editing.copySelectedAnnotations();
    await tester.pumpAndSettle();
    expect(calls, ['markLocalCopy']);
    editing.pasteSnapshotBytes(buildMultiPagePdf(1), 0);
    await tester.pumpAndSettle();
    expect(calls, ['markLocalCopy'],
        reason: 'an external import is not a local copy');
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets(
      'EditorScreen wires both desktop clipboard directions through the shell',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = PdfEditingPreferences();
    addTearDown(prefs.dispose);
    final pdf = makeSnapshot(Uint8List(4)).pdfBytes;
    Uint8List? written;
    await tester.pumpWidget(MaterialApp(
        home: EditorScreen(
      prefs: prefs,
      initialDocument: (bytes: buildMultiPagePdf(1), title: 'Target.pdf'),
      pdfClipboardReader: () async => PdfClipboardPdf(pdf),
      snapshotClipboardWriter: (bytes, png) async {
        written = bytes;
        return true;
      },
    )));
    await tester.pumpAndSettle();
    final viewer = tester.widget<PdfViewer>(find.byType(PdfViewer));
    final context = tester.element(find.byType(PdfViewer));
    expect((await viewer.systemPdfPasteProvider!(context))!.bytes, pdf);
    await viewer.onSnapshot!(context, makeSnapshot(Uint8List(4)));
    expect(PdfDocument.open(written!).page(0).mediaBox,
        const PdfRect(0, 0, 160, 40));
    await tester.pumpAndSettle();
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
        // captureSnapshot rasterizes + PNG-encodes (toImage) - let it finish.
        for (var i = 0; i < 50 && written == null; i++) {
          await tester.pump(const Duration(milliseconds: 20));
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      expect(reported, isTrue);
      expect(written, isNotNull);
      // PNG magic number - the captured raster reached the clipboard writer.
      expect(written!.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
      // the vector half still lands on the in-app clipboard for paste-back.
      expect(editing.hasSnapshotClipboard, isTrue);
    });
  });
}
