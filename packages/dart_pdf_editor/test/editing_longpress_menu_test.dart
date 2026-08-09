import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Touch long-press opens the context menu mice reach by right-clicking:
// on an annotation (select mode or reader mode), or on empty page area when
// the clipboard has something to paste. Form fields deliberately do not
// claim this gesture: their actions live in the contextual toolbar. The
// recognizer only claims when the press point has an annotation menu to
// offer, so text selection keeps its long press everywhere else.

// 800×600 viewport, fit-width: 612pt page → view scale
const scale = 800 / 612;

Offset viewPoint(double x, double y) => Offset(x * scale, (792 - y) * scale);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // controllers share the process-wide annotation clipboard by default;
    // start each test from empty so one test's copy can't leak into the next.
    PdfAnnotationSnapshotClipboard.instance.clear();
  });

  Future<PdfEditingController> pumpViewer(WidgetTester tester,
      {Uint8List? bytes}) async {
    final editing = PdfEditingController(bytes ?? buildMultiPagePdf(1));
    addTearDown(editing.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: editing,
          builder: (context, _) => PdfViewer(
            initialFit: PdfViewerFit.width,
            document: editing.document,
            editing: editing,
          ),
        ),
      ),
    ));
    await tester.pump();
    return editing;
  }

  /// Holds a touch pointer until the long-press deadline fires and any
  /// menu route settles, then lifts.
  Future<void> longPressAt(WidgetTester tester, Offset at) async {
    final gesture =
        await tester.startGesture(at, kind: PointerDeviceKind.touch);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  group('select mode', () {
    testWidgets('long-press on an annotation selects it and opens the menu',
        (tester) async {
      final editing = await pumpViewer(tester);
      editing
        ..addRectangle(0, const PdfRect(300, 400, 400, 450))
        ..tool = PdfEditTool.select;
      await tester.pump();

      await longPressAt(tester, viewPoint(350, 425));
      expect(editing.selectedAnnotationSlots, [(0, 0)]);
      expect(
          find.byKey(const ValueKey('pdf-annot-menu-delete')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pdf-annot-menu-delete')));
      await tester.pumpAndSettle();
      expect(editing.document.page(0).annotations, isEmpty);
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('long-press on empty area pastes from the clipboard',
        (tester) async {
      final editing = await pumpViewer(tester);
      editing
        ..addRectangle(0, const PdfRect(300, 400, 400, 450))
        ..tool = PdfEditTool.select
        ..selectAnnotation(0, 0)
        ..copySelectedAnnotations()
        ..clearAnnotationSelection();
      await tester.pump();

      // press point must sit inside the 800×600 viewport (view y ≈ 408)
      await longPressAt(tester, viewPoint(200, 480));
      final paste =
          tester.widget(find.byKey(const ValueKey('pdf-annot-menu-paste')))
              as PopupMenuItem;
      expect(paste.enabled, isTrue);
      await tester.tap(find.byKey(const ValueKey('pdf-annot-menu-paste')));
      await tester.pumpAndSettle();

      final annotations = editing.document.page(0).annotations;
      expect(annotations, hasLength(2));
      // pasted centered on the press point
      expect(annotations[1].rect.left + annotations[1].rect.width / 2,
          closeTo(200, 1));
      expect(annotations[1].rect.bottom + annotations[1].rect.height / 2,
          closeTo(480, 1));
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('long-press on empty area without a clipboard does nothing',
        (tester) async {
      final editing = await pumpViewer(tester);
      editing
        ..addRectangle(0, const PdfRect(300, 400, 400, 450))
        ..tool = PdfEditTool.select;
      await tester.pump();

      await longPressAt(tester, viewPoint(350, 200));
      expect(find.byKey(const ValueKey('pdf-annot-menu-delete')), findsNothing);
      expect(find.byKey(const ValueKey('pdf-annot-menu-paste')), findsNothing);
      await tester.pump(const Duration(milliseconds: 400));
    });
  });

  group('reader mode', () {
    testWidgets('long-press on an annotation opens the menu without a tool',
        (tester) async {
      final editing = await pumpViewer(tester);
      editing.addRectangle(0, const PdfRect(300, 400, 400, 450));
      await tester.pump();
      expect(editing.tool, isNull);

      await longPressAt(tester, viewPoint(350, 425));
      expect(editing.selectedAnnotationSlots, [(0, 0)]);
      expect(
          find.byKey(const ValueKey('pdf-annot-menu-delete')), findsOneWidget);
      // dismiss
      await tester.tapAt(const Offset(780, 580));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('long-press on page text still selects the word',
        (tester) async {
      // the controller must ride the viewer from the first build - it
      // attaches in initState
      final controller = PdfViewerController();
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: editing,
            builder: (context, _) => PdfViewer(
              initialFit: PdfViewerFit.width,
              document: editing.document,
              controller: controller,
              editing: editing,
            ),
          ),
        ),
      ));
      await tester.pump();

      // 'Page 1' baseline at (72, 720), 24pt - press mid-word
      await longPressAt(tester, viewPoint(100, 726));
      expect(controller.selectedText, 'Page');
      expect(find.byKey(const ValueKey('pdf-annot-menu-delete')), findsNothing);
      await tester.pump(const Duration(milliseconds: 400));
    });
  });

  group('form tool', () {
    testWidgets('long-press on a field does not open a field menu',
        (tester) async {
      final editing = await pumpViewer(tester, bytes: buildAcroFormPdf());
      editing.tool = PdfEditTool.form;
      await tester.pump();

      // the 'name' text field at [72 700 300 724]
      await longPressAt(tester, viewPoint(180, 712));
      expect(find.byKey(const ValueKey('pdf-form-menu-rename')), findsNothing);
      await tester.pump(const Duration(milliseconds: 400));
    });
  });

  // When the host sets `contextMenuEnabled: false`, the popup menu is
  // suppressed but the underlying gesture outcomes (annotation selection,
  // text selection) must still run. The recognizer returns early in
  // `_maybeAnnotationMenu` (`pdf_viewer.dart`) and `_onSecondaryTapUp` so
  // neither annotation nor plain-text menus reach the user.
  group('contextMenuEnabled: false', () {
    Future<PdfEditingController> pumpViewerNoContextMenu(
        WidgetTester tester,
        {Uint8List? bytes}) async {
      final editing =
          PdfEditingController(bytes ?? buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: editing,
            builder: (context, _) => PdfViewer(
              initialFit: PdfViewerFit.width,
              document: editing.document,
              editing: editing,
              contextMenuEnabled: false,
            ),
          ),
        ),
      ));
      await tester.pump();
      return editing;
    }

    testWidgets(
        'long-press on an annotation in select mode suppresses the menu '
        'but still selects the annotation',
        (tester) async {
      final editing = await pumpViewerNoContextMenu(tester);
      editing
        ..addRectangle(0, const PdfRect(300, 400, 400, 450))
        ..tool = PdfEditTool.select;
      await tester.pump();

      await longPressAt(tester, viewPoint(350, 425));
      expect(editing.selectedAnnotationSlots, [(0, 0)],
          reason: 'annotation selection still happens; only the popup is '
              'suppressed');
      expect(find.byKey(const ValueKey('pdf-annot-menu-delete')),
          findsNothing);
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets(
        'long-press on an annotation in reader mode suppresses the menu',
        (tester) async {
      final editing = await pumpViewerNoContextMenu(tester);
      editing.addRectangle(0, const PdfRect(300, 400, 400, 450));
      await tester.pump();
      expect(editing.tool, isNull);

      await longPressAt(tester, viewPoint(350, 425));
      expect(find.byKey(const ValueKey('pdf-annot-menu-delete')),
          findsNothing);
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets(
        'long-press on plain page text still selects the word; no menu pops',
        (tester) async {
      final controller = PdfViewerController();
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: editing,
            builder: (context, _) => PdfViewer(
              initialFit: PdfViewerFit.width,
              document: editing.document,
              controller: controller,
              editing: editing,
              contextMenuEnabled: false,
            ),
          ),
        ),
      ));
      await tester.pump();

      // 'Page 1' baseline at (72, 720), 24pt - press mid-word
      await longPressAt(tester, viewPoint(100, 726));
      expect(controller.selectedText, 'Page',
          reason: 'text selection survives; only the context menu is '
              'suppressed');
      expect(find.byKey(const ValueKey('pdf-text-menu-copy')), findsNothing);
      expect(
          find.byKey(const ValueKey('pdf-text-menu-select-all')),
          findsNothing);
      await tester.pump(const Duration(milliseconds: 400));
    });
  });

  // When the host supplies an onContextMenuRequested callback, the
  // suppressed gesture is delivered to the callback instead of being
  // dropped. The request carries the resolved target (annotation, text,
  // form widget, ...) so the host never has to re-run a hit test.
  group('onContextMenuRequested host takeover', () {
    testWidgets(
        'long-press on an annotation in select mode hands the gesture to '
        'the host instead of opening the stock menu', (tester) async {
      final hostCalls = <PdfContextMenuRequest>[];
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: editing,
            builder: (context, _) => PdfViewer(
              initialFit: PdfViewerFit.width,
              document: editing.document,
              editing: editing,
              contextMenuEnabled: false,
              onContextMenuRequested: hostCalls.add,
            ),
          ),
        ),
      ));
      await tester.pump();
      editing
        ..addRectangle(0, const PdfRect(300, 400, 400, 450))
        ..tool = PdfEditTool.select;
      await tester.pump();

      await longPressAt(tester, viewPoint(350, 425));
      expect(editing.selectedAnnotationSlots, [(0, 0)],
          reason: 'annotation is still selected by the long-press; only the '
              'menu is rerouted');
      expect(hostCalls, hasLength(1),
          reason: 'host takeover fires exactly once per long-press');
      expect(hostCalls.first.pageIndex, 0,
          reason: 'pageIndex is forwarded');
      // pagePoint should be in page coordinates near (350, 425).
      final (x, y) = hostCalls.first.pagePoint;
      expect(x, closeTo(350, 0.001));
      expect(y, closeTo(425, 0.001));
      // the resolved target rides along, so the host can branch on it
      expect(hostCalls.first.target, PdfContextMenuTarget.annotation);
      expect(hostCalls.first.annotation?.subtype, 'Square');
      expect(hostCalls.first.slot, 0);
      // the stock annotation menu must not pop up either
      expect(find.byKey(const ValueKey('pdf-annot-menu-delete')),
          findsNothing);
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets(
        'long-press in reader mode on a plain-text page hands the gesture '
        'to the host', (tester) async {
      final hostCalls = <PdfContextMenuRequest>[];
      final controller = PdfViewerController();
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: editing,
            builder: (context, _) => PdfViewer(
              initialFit: PdfViewerFit.width,
              document: editing.document,
              controller: controller,
              editing: editing,
              contextMenuEnabled: false,
              onContextMenuRequested: hostCalls.add,
            ),
          ),
        ),
      ));
      await tester.pump();

      // 'Page 1' baseline at (72, 720), 24pt - press mid-word
      await longPressAt(tester, viewPoint(100, 726));
      expect(hostCalls, hasLength(1),
          reason: 'reader-mode long-press is also handed to the host');
      expect(hostCalls.first.target, PdfContextMenuTarget.text);
      expect(hostCalls.first.selectedText, 'Page');
      expect(controller.selectedText, 'Page',
          reason: 'text selection still happens before the host callback');
      expect(find.byKey(const ValueKey('pdf-text-menu-copy')), findsNothing);
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets(
        'with contextMenuEnabled: true, host callback is NOT invoked',
        (tester) async {
      // Verify the gate is the suppression itself, not the callback's
      // presence: the default menu is responsible for the gesture.
      var hostCalls = 0;
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: editing,
            builder: (context, _) => PdfViewer(
              initialFit: PdfViewerFit.width,
              document: editing.document,
              editing: editing,
              // contextMenuEnabled defaults to true
              onContextMenuRequested: (request) {
                hostCalls++;
              },
            ),
          ),
        ),
      ));
      await tester.pump();
      editing
        ..addRectangle(0, const PdfRect(300, 400, 400, 450))
        ..tool = PdfEditTool.select;
      await tester.pump();

      await longPressAt(tester, viewPoint(350, 425));
      expect(hostCalls, 0,
          reason: 'host callback only fires when the stock menu is suppressed');
      // and the stock menu does pop
      expect(find.byKey(const ValueKey('pdf-annot-menu-delete')),
          findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
    });

    // 🔴 #1 fix coverage: the reader-mode touch long-press path
    // (_maybeAnnotationMenu in pdf_viewer.dart) previously returned
    // false when contextMenuEnabled was off, silently dropping the
    // gesture before the host saw it. Verify all four entry points now
    // route to the host: desktop right-click, editing-overlay long-press,
    // touch text-selection long-press, and reader-mode annotation
    // long-press. This is the missing fourth case.
    testWidgets(
        'long-press on an annotation in reader mode hands the gesture to '
        'the host instead of opening the stock menu', (tester) async {
      final hostCalls = <PdfContextMenuRequest>[];
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: editing,
            builder: (context, _) => PdfViewer(
              initialFit: PdfViewerFit.width,
              document: editing.document,
              editing: editing,
              contextMenuEnabled: false,
              onContextMenuRequested: hostCalls.add,
            ),
          ),
        ),
      ));
      await tester.pump();
      editing.addRectangle(0, const PdfRect(300, 400, 400, 450));
      await tester.pump();
      expect(editing.tool, isNull,
          reason: 'reader mode has no active tool');

      await longPressAt(tester, viewPoint(350, 425));
      expect(editing.selectedAnnotationSlots, [(0, 0)],
          reason: 'the reader-mode long-press still selects the annotation '
              'before handing the gesture off');
      expect(hostCalls, hasLength(1),
          reason: 'reader-mode annotation long-press now fires the host '
              'callback exactly once');
      expect(hostCalls.first.pageIndex, 0,
          reason: 'pageIndex is forwarded');
      final (x, y) = hostCalls.first.pagePoint;
      expect(x, closeTo(350, 0.001),
          reason: 'pagePoint is in page coordinates');
      expect(y, closeTo(425, 0.001));
      expect(hostCalls.first.target, PdfContextMenuTarget.annotation);
      expect(hostCalls.first.annotation?.subtype, 'Square');
      expect(find.byKey(const ValueKey('pdf-annot-menu-delete')),
          findsNothing,
          reason: 'the stock annotation menu stays suppressed');
      await tester.pump(const Duration(milliseconds: 400));
    });

    // A null callback is the "host doesn't care about menu gestures"
    // opt-out: the gesture should be dropped cleanly without throwing
    // or leaving state behind. Touches the reader-mode annotation path
    // (the most fragile of the four).
    testWidgets(
        'null onContextMenuRequested drops the reader-mode gesture cleanly',
        (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: editing,
            builder: (context, _) => PdfViewer(
              initialFit: PdfViewerFit.width,
              document: editing.document,
              editing: editing,
              contextMenuEnabled: false,
              // onContextMenuRequested intentionally omitted
            ),
          ),
        ),
      ));
      await tester.pump();
      editing.addRectangle(0, const PdfRect(300, 400, 400, 450));
      await tester.pump();

      await longPressAt(tester, viewPoint(350, 425));
      // The annotation is still selected by the long-press (the host
      // refusal only suppresses the popup), and no popup appears.
      expect(editing.selectedAnnotationSlots, [(0, 0)]);
      expect(find.byKey(const ValueKey('pdf-annot-menu-delete')),
          findsNothing);
      // No crash, no exceptions, no leaked routes.
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 400));
    });

    // 🟢 minor verification: when both selectable text and an annotation
    // sit under the press point, exactly one host callback fires (the
    // text path wins; _onLongPressStart returns before the annotation
    // branch can run). Constructed by adding an annotation over a
    // known-text region and long-pressing there.
    testWidgets(
        'text+annotation overlap: host callback fires exactly once',
        (tester) async {
      var hostCalls = 0;
      final controller = PdfViewerController();
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: editing,
            builder: (context, _) => PdfViewer(
              initialFit: PdfViewerFit.width,
              document: editing.document,
              controller: controller,
              editing: editing,
              contextMenuEnabled: false,
              onContextMenuRequested: (request) {
                hostCalls++;
              },
            ),
          ),
        ),
      ));
      await tester.pump();
      // 'Page 1' baseline at (72, 720), 24pt - cover the 'Page' word
      // with an annotation centered at (100, 726).
      editing.addRectangle(0, const PdfRect(80, 712, 160, 740));
      await tester.pump();

      await longPressAt(tester, viewPoint(100, 726));
      expect(hostCalls, 1,
          reason: 'exactly one host invocation - the text path handles '
              'overlapping annotations');
      expect(controller.selectedText, 'Page');
      await tester.pump(const Duration(milliseconds: 400));
    });
  });
}
