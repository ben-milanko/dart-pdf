// The display-only annotation subtype filter (`hiddenAnnotationSubtypes`):
// the renderer/interpreter skip, the worker wire + record cache, the page
// view's re-render on a toggle, the viewer's link taps, the editing
// controller's hit tests, and the persisted preference. Like
// showAnnotations, the document never changes.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _green = (0x00, 0xA0, 0x00);
const _red = (0xFF, 0x00, 0x00);
const _white = (0xFF, 0xFF, 0xFF);

/// Raster points (y down on a 612x792 page) inside the square's fill and
/// inside the link's 20pt red border band.
const _squarePoint = (150, 792 - 650);
const _linkPoint = (305, 792 - 650);

/// One page carrying a green /Square filling (100, 600)-(200, 700) and a
/// /Link over (300, 600)-(400, 700) with a 20pt red border appearance.
Uint8List _squareAndLink() {
  final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(2)));
  editor.addSquare(0, const PdfRect(100, 600, 200, 700),
      strokeColor: 0x00A000, fillColor: 0x00A000);
  editor.addLinkToPage(0, const [PdfRect(300, 600, 400, 700)],
      targetPage: 1, borderColor: 0xFF0000, borderWidth: 20);
  return editor.save();
}

(int, int, int) _pixelAt(ByteData pixels, int width, (int, int) at,
    {double scale = 1}) {
  final x = (at.$1 * scale).round();
  final y = (at.$2 * scale).round();
  final i = (y * width + x) * 4;
  return (pixels.getUint8(i), pixels.getUint8(i + 1), pixels.getUint8(i + 2));
}

Future<ByteData> _pixelsOf(ui.Picture picture, PdfPage page) async {
  final size = PdfPageRenderer.pageSize(page);
  final image = await PdfPageRenderer.rasterize(picture, size, 1);
  try {
    return (await image.toByteData())!;
  } finally {
    image.dispose();
  }
}

/// Logs the hidden-subtype set of every record a page view asks for.
class _LoggingWorker extends PdfRenderWorker {
  _LoggingWorker(this._inner);

  final PdfRenderWorker _inner;
  final List<Set<String>> hiddenPerRecord = [];

  @override
  bool get isActive => _inner.isActive;

  @override
  Future<List<PdfRenderCommand>?> record(
    int pageIndex, {
    bool annotations = true,
    Set<String> hiddenAnnotationSubtypes = const {},
    int priority = 0,
    double? imagePixelRatio,
    bool decodeImages = true,
    int? commandLimit,
    PdfRect? imageDecodeRegion,
    PdfPartialRecordSink? onPartial,
    PdfRecordDecodeGate? decodeGate,
  }) {
    hiddenPerRecord.add(hiddenAnnotationSubtypes);
    return _inner.record(
      pageIndex,
      annotations: annotations,
      hiddenAnnotationSubtypes: hiddenAnnotationSubtypes,
      priority: priority,
      imagePixelRatio: imagePixelRatio,
      decodeImages: decodeImages,
      commandLimit: commandLimit,
      imageDecodeRegion: imageDecodeRegion,
      onPartial: onPartial,
    );
  }

  @override
  void cancel(int pageIndex, {int priority = 0}) =>
      _inner.cancel(pageIndex, priority: priority);

  @override
  void dispose() => _inner.dispose();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('rendering', () {
    test('the interpreter skips only the named subtypes', () {
      final page = PdfDocument.open(_squareAndLink()).page(0);
      List<PdfRenderCommand> record(Set<String> hidden) {
        final recorder = RecordingPdfDevice();
        PdfInterpreter(cos: page.document.cos, device: recorder)
            .drawAnnotations(page, skipSubtypes: hidden);
        return recorder.commands;
      }

      final all = record(const {});
      final noLinks = record(const {'Link'});
      final noSquares = record(const {'Square'});
      expect(noLinks, isNotEmpty, reason: 'the square still draws');
      expect(noLinks.length, lessThan(all.length));
      expect(noSquares.length, lessThan(all.length));
      expect(record(const {'Link', 'Square'}), isEmpty);
    });

    testWidgets('hiding Link drops the link and keeps the square',
        (tester) async {
      await tester.runAsync(() async {
        final page = PdfDocument.open(_squareAndLink()).page(0);
        final shown = await _pixelsOf(
            await PdfPageRenderer.renderPictureWithPlan(
                page, const PdfPageRenderPlan()),
            page);
        expect(_pixelAt(shown, 612, _squarePoint), _green);
        expect(_pixelAt(shown, 612, _linkPoint), _red);

        const plan = PdfPageRenderPlan(hiddenAnnotationSubtypes: {'Link'});
        final picture = await PdfPageRenderer.renderPictureWithPlan(page, plan);
        final hidden = await _pixelsOf(picture, page);
        expect(_pixelAt(hidden, 612, _squarePoint), _green);
        expect(_pixelAt(hidden, 612, _linkPoint), _white);

        final recorded = await _pixelsOf(
            await PdfPageRenderer.renderPictureRecordedWithPlan(page, plan),
            page);
        expect(_pixelAt(recorded, 612, _linkPoint), _white);
      });
    });

    testWidgets('a skipAnnotation predicate combines with the hidden set',
        (tester) async {
      await tester.runAsync(() async {
        final page = PdfDocument.open(_squareAndLink()).page(0);
        final pixels = await _pixelsOf(
            await PdfPageRenderer.renderPicture(page,
                hiddenAnnotationSubtypes: const {'Link'},
                skipAnnotation: (a) => a.subtype == 'Square'),
            page);
        expect(_pixelAt(pixels, 612, _squarePoint), _white);
        expect(_pixelAt(pixels, 612, _linkPoint), _white);
      });
    });

    test('render plans with different hidden sets are different plans', () {
      expect(const PdfPageRenderPlan(hiddenAnnotationSubtypes: {'Link'}),
          isNot(const PdfPageRenderPlan()));
      expect(PdfPageRenderPlan(hiddenAnnotationSubtypes: {'Link', 'Square'}),
          PdfPageRenderPlan(hiddenAnnotationSubtypes: {'Square', 'Link'}));
      expect(
          PdfPageRenderPlan(hiddenAnnotationSubtypes: {'Link', 'Square'})
              .hashCode,
          PdfPageRenderPlan(hiddenAnnotationSubtypes: {'Square', 'Link'})
              .hashCode);
    });
  });

  group('worker', () {
    testWidgets('a worker record honours the hidden set and its cache key',
        (tester) async {
      await tester.runAsync(() async {
        final bytes = _squareAndLink();
        final page = PdfDocument.open(bytes).page(0);
        // start() wraps the isolate in the record cache, so this also pins
        // that a toggle can't be answered from the other setting's entry.
        final worker = PdfRenderWorker.start(bytes);
        addTearDown(worker.dispose);
        expect(worker.isActive, isTrue);

        Future<ByteData> recorded(Set<String> hidden) async {
          final commands =
              await worker.record(0, hiddenAnnotationSubtypes: hidden);
          expect(commands, isNotNull);
          return _pixelsOf(
              await PdfPageRenderer.pictureFromCommands(page, commands!), page);
        }

        final shown = await recorded(const {});
        expect(_pixelAt(shown, 612, _linkPoint), _red);
        final hidden = await recorded(const {'Link'});
        expect(_pixelAt(hidden, 612, _linkPoint), _white);
        expect(_pixelAt(hidden, 612, _squarePoint), _green);
        final again = await recorded(const {});
        expect(_pixelAt(again, 612, _linkPoint), _red);
      });
    });

    testWidgets('toggling a page view re-records with the new hidden set',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetDevicePixelRatio);
      final bytes = _squareAndLink();
      final document = PdfDocument.open(bytes);
      final worker = _LoggingWorker(PdfRenderWorker.start(bytes));
      addTearDown(worker.dispose);
      final boundary = GlobalKey();

      Widget view(Set<String> hidden) => Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 612,
              child: RepaintBoundary(
                key: boundary,
                child: PdfPageView(
                  page: document.page(0),
                  hiddenAnnotationSubtypes: hidden,
                  renderWorker: worker,
                ),
              ),
            ),
          );

      Future<ByteData> settle() async {
        for (var i = 0; i < 100; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump();
        }
        final render = boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        final image = (await tester.runAsync(() => render.toImage()))!;
        final pixels = (await tester.runAsync(() => image.toByteData()))!;
        expect(image.width, 612);
        image.dispose();
        return pixels;
      }

      await tester.pumpWidget(view(const {}));
      final shown = await settle();
      expect(_pixelAt(shown, 612, _linkPoint), _red);
      expect(worker.hiddenPerRecord, isNotEmpty);
      expect(worker.hiddenPerRecord.every((h) => h.isEmpty), isTrue);

      final before = worker.hiddenPerRecord.length;
      await tester.pumpWidget(view(const {'Link'}));
      final hidden = await settle();
      expect(
          worker.hiddenPerRecord.skip(before), contains(equals(const {'Link'})),
          reason: 'the toggle must ask the worker for a filtered record');
      expect(_pixelAt(hidden, 612, _linkPoint), _white,
          reason: 'no stale worker scene with the link still drawn');
      expect(_pixelAt(hidden, 612, _squarePoint), _green);

      await tester.pumpWidget(view(const {}));
      final back = await settle();
      expect(_pixelAt(back, 612, _linkPoint), _red);
    });
  });

  group('viewer', () {
    testWidgets('a hidden link takes no taps; a shown one navigates',
        (tester) async {
      // the GoTo link in buildAnnotatedPdf: rect (72, 600)-(200, 624) on a
      // 612x792 page, targeting page 3; fit-width in an 800px viewport
      const scale = 800 / 612;
      const target = Offset(136 * scale, (792 - 612) * scale);

      Future<PdfViewerController> pumpViewer(Set<String> hidden) async {
        final controller = PdfViewerController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(MaterialApp(
          key: ValueKey(hidden.join()),
          home: Scaffold(
            body: PdfViewer(
              document: PdfDocument.open(buildAnnotatedPdf()),
              controller: controller,
              hiddenAnnotationSubtypes: hidden,
              initialFit: PdfViewerFit.width,
            ),
          ),
        ));
        await tester.pump();
        return controller;
      }

      Future<void> tapLink() async {
        await tester.tapAt(tester.getTopLeft(find.byType(PdfViewer)) + target);
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
      }

      final shown = await pumpViewer(const {});
      await tapLink();
      expect(shown.currentPage, 2, reason: 'the tap target is the GoTo link');

      final hidden = await pumpViewer(const {'Link'});
      expect(
        tester
            .widget<PdfPageView>(find.byType(PdfPageView).first)
            .hiddenAnnotationSubtypes,
        {'Link'},
      );
      await tapLink();
      expect(hidden.currentPage, 0, reason: 'link is hidden, tap is inert');
    });
  });

  group('editing', () {
    testWidgets('the live annotation layer leaves hidden subtypes unpainted',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 1100);
      addTearDown(tester.view.reset);
      final editing = PdfEditingController(_squareAndLink());
      addTearDown(editing.dispose);
      final boundary = GlobalKey();
      const scale = 800 / 612;

      Widget viewer(Set<String> hidden) => MaterialApp(
            home: Scaffold(
              body: RepaintBoundary(
                key: boundary,
                child: PdfViewer(
                  editing: editing,
                  hiddenAnnotationSubtypes: hidden,
                  initialFit: PdfViewerFit.width,
                ),
              ),
            ),
          );

      Future<ByteData> settle() async {
        for (var i = 0; i < 100; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump();
        }
        final render = boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        final image = (await tester.runAsync(() => render.toImage()))!;
        final pixels = (await tester.runAsync(() => image.toByteData()))!;
        expect(image.width, 800);
        image.dispose();
        return pixels;
      }

      await tester.pumpWidget(viewer(const {}));
      final shown = await settle();
      expect(_pixelAt(shown, 800, _linkPoint, scale: scale), _red);
      expect(_pixelAt(shown, 800, _squarePoint, scale: scale), _green);

      await tester.pumpWidget(viewer(const {'Link'}));
      final hidden = await settle();
      expect(_pixelAt(hidden, 800, _linkPoint, scale: scale), _white);
      expect(_pixelAt(hidden, 800, _squarePoint, scale: scale), _green);
      expect(editing.canUndo, isFalse, reason: 'no revision was recorded');
    });
  });

  group('preference', () {
    test('showLinks toggles notify, persist, and leave the document alone',
        () async {
      final prefs = PdfEditingPreferences();
      await prefs.ready;
      expect(prefs.showLinks, isTrue);
      expect(prefs.hiddenAnnotationSubtypes, isEmpty);

      final editing =
          PdfEditingController(_squareAndLink(), preferences: prefs);
      addTearDown(editing.dispose);
      // a real edit, so there is history for the toggle to (not) disturb
      editing.apply((e) => e.addSquare(1, const PdfRect(10, 10, 50, 50)));
      expect(editing.canUndo, isTrue);
      final revision = editing.revisionId;
      final bytes = editing.bytes;

      var notified = 0;
      prefs.addListener(() => notified++);
      prefs.showLinks = false;
      expect(notified, 1);
      expect(prefs.hiddenAnnotationSubtypes, {'Link'});
      expect(prefs.showLinks, isFalse);
      prefs.showLinks = false;
      expect(notified, 1, reason: 'no-op writes do not notify');

      expect(editing.revisionId, revision);
      expect(editing.canUndo, isTrue);
      expect(editing.canRedo, isFalse);
      expect(editing.bytes, equals(bytes));
      expect(editing.document.page(0).annotations.map((a) => a.subtype),
          contains('Link'),
          reason: 'display only - the link is still in the document');

      prefs.hiddenAnnotationSubtypes = {'Link', 'Square'};
      expect(notified, 2);
      await pumpEventQueue();

      final restored = PdfEditingPreferences();
      await restored.ready;
      expect(restored.hiddenAnnotationSubtypes, {'Link', 'Square'});
      expect(restored.showLinks, isFalse);

      restored.showLinks = true;
      expect(restored.hiddenAnnotationSubtypes, {'Square'});
      expect(editing.revisionId, revision);
    });

    test('editor hit tests skip hidden subtypes', () {
      final editing = PdfEditingController(_squareAndLink());
      addTearDown(editing.dispose);
      // inside the square (100, 600)-(200, 700)
      expect(editing.selectableAnnotationAt(0, 150, 650)?.$2.subtype, 'Square');
      editing.preferences.hiddenAnnotationSubtypes = {'Square'};
      expect(editing.selectableAnnotationAt(0, 150, 650), isNull);
      editing.selectAnnotationsIn(0, const PdfRect(0, 0, 612, 792));
      expect(editing.selectedAnnotation?.subtype, isNot('Square'));
    });
  });
}
