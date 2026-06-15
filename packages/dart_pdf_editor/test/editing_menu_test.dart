import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 800×600 viewport, fit-width: 612pt page → view scale
const scale = 800 / 612;

Offset viewPoint(double x, double y) => Offset(x * scale, (792 - y) * scale);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('controller z-order', () {
    PdfEditingController threeRects() {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addRectangle(0, const PdfRect(50, 700, 150, 750))
        ..addRectangle(0, const PdfRect(200, 700, 300, 750))
        ..addRectangle(0, const PdfRect(350, 700, 450, 750))
        ..tool = PdfEditTool.select;
      return editing;
    }

    test('bringSelectedToFront reorders /Annots and the selection follows', () {
      final editing = threeRects()..selectAnnotation(0, 0);
      addTearDown(editing.dispose);
      const rectA = PdfRect(50, 700, 150, 750);

      expect(editing.canBringSelectedToFront, isTrue);
      editing.bringSelectedToFront();

      expect(editing.document.page(0).annotations[2].rect, rectA);
      expect(editing.selectedAnnotationSlots, [(0, 2)]);
      expect(editing.canBringSelectedToFront, isFalse);
      expect(editing.canSendSelectedToBack, isTrue);

      // one revision: a single undo restores the original order
      editing.undo();
      expect(editing.document.page(0).annotations[0].rect, rectA);
    });

    test('sendSelectedToBack is a no-op for the bottom annotation', () {
      final editing = threeRects()..selectAnnotation(0, 0);
      addTearDown(editing.dispose);
      final before = editing.document;

      expect(editing.canSendSelectedToBack, isFalse);
      editing.sendSelectedToBack();
      expect(identical(editing.document, before), isTrue);
      expect(editing.selectedAnnotationSlots, [(0, 0)]);
    });

    test('a multi-selection moves as a block, keeping relative order', () {
      final editing = threeRects();
      addTearDown(editing.dispose);
      // marquee over the first two rects
      editing.selectAnnotationsIn(0, const PdfRect(40, 690, 310, 760));
      expect(editing.selectedAnnotationSlots, [(0, 0), (0, 1)]);
      expect(editing.canSendSelectedToBack, isFalse); // already the bottom

      editing.bringSelectedToFront();
      final rects = [
        for (final a in editing.document.page(0).annotations) a.rect
      ];
      expect(rects, const [
        PdfRect(350, 700, 450, 750), // C dropped to the back
        PdfRect(50, 700, 150, 750), // A and B on top, A still below B
        PdfRect(200, 700, 300, 750),
      ]);
      expect(editing.selectedAnnotationSlots, [(0, 1), (0, 2)]);
      expect(editing.canBringSelectedToFront, isFalse);
    });
  });

  group('context menu', () {
    Future<PdfEditingController> pumpViewer(WidgetTester tester,
        {PdfAnnotationMenuBuilder? menuBuilder}) async {
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
              annotationMenuBuilder: menuBuilder,
            ),
          ),
        ),
      ));
      await tester.pump();
      editing
        ..addRectangle(0, const PdfRect(60, 700, 160, 750)) // A, slot 0
        ..addRectangle(0, const PdfRect(200, 700, 300, 750)); // B, slot 1
      await tester.pump();
      return editing;
    }

    Future<void> rightClick(WidgetTester tester, Offset at) async {
      await tester.tapAt(at,
          kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
    }

    testWidgets('right-click selects the annotation and shows the menu',
        (tester) async {
      final editing = await pumpViewer(tester);

      await rightClick(tester, viewPoint(110, 725)); // inside A only
      expect(editing.selectedAnnotationSlots, [(0, 0)]);
      expect(find.text('Bring to front'), findsOneWidget);
      expect(find.text('Send to back'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);

      await tester.tap(find.text('Bring to front'));
      await tester.pumpAndSettle();
      expect(editing.document.page(0).annotations[1].rect,
          const PdfRect(60, 700, 160, 750));
      expect(editing.selectedAnnotationSlots, [(0, 1)]);
      expect(find.text('Bring to front'), findsNothing); // menu closed
    });

    testWidgets('z-order entries disable when they would change nothing',
        (tester) async {
      await pumpViewer(tester);

      await rightClick(tester, viewPoint(250, 725)); // B, already on top
      final front =
          tester.widget(find.byKey(const ValueKey('pdf-annot-menu-front')))
              as PopupMenuItem;
      final back =
          tester.widget(find.byKey(const ValueKey('pdf-annot-menu-back')))
              as PopupMenuItem;
      expect(front.enabled, isFalse);
      expect(back.enabled, isTrue);
    });

    testWidgets('delete from the menu removes the selection', (tester) async {
      final editing = await pumpViewer(tester);

      await rightClick(tester, viewPoint(110, 725));
      await tester.tap(find.byKey(const ValueKey('pdf-annot-menu-delete')));
      await tester.pumpAndSettle();

      final annotations = editing.document.page(0).annotations;
      expect(annotations, hasLength(1));
      expect(annotations.single.rect, const PdfRect(200, 700, 300, 750));
      expect(editing.hasAnnotationSelection, isFalse);
    });

    testWidgets('right-click keeps an existing multi-selection',
        (tester) async {
      final editing = await pumpViewer(tester);
      editing.addRectangle(0, const PdfRect(350, 700, 450, 750)); // C, top
      await tester.pump();
      editing
        ..tool = PdfEditTool.select
        ..selectAnnotationsIn(0, const PdfRect(50, 690, 310, 760)); // A + B
      expect(editing.selectedAnnotationSlots, [(0, 0), (0, 1)]);

      await rightClick(tester, viewPoint(250, 725)); // B, already selected
      expect(editing.selectedAnnotationSlots, [(0, 0), (0, 1)]);

      await tester.tap(find.byKey(const ValueKey('pdf-annot-menu-front')));
      await tester.pumpAndSettle();
      // the block moved above C, keeping its order; the selection followed
      final rects = [
        for (final a in editing.document.page(0).annotations) a.rect
      ];
      expect(rects, const [
        PdfRect(350, 700, 450, 750),
        PdfRect(60, 700, 160, 750),
        PdfRect(200, 700, 300, 750),
      ]);
      expect(editing.selectedAnnotationSlots, [(0, 1), (0, 2)]);
    });

    testWidgets('host actions ride below a divider and get the request',
        (tester) async {
      PdfAnnotationMenuRequest? received;
      final editing = await pumpViewer(
        tester,
        menuBuilder: (context, request) => [
          PdfAnnotationMenuItem(
            key: const ValueKey('host-copy-comment'),
            label: 'Copy comment',
            icon: Icons.copy,
            onSelected: (request) => received = request,
          ),
        ],
      );

      await rightClick(tester, viewPoint(110, 725));
      expect(find.byType(PopupMenuDivider), findsOneWidget);
      expect(find.text('Bring to front'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('host-copy-comment')));
      await tester.pumpAndSettle();
      expect(received, isNotNull);
      expect(received!.pageIndex, 0);
      expect(received!.slots, [(0, 0)]);
      expect(received!.primary!.rect, const PdfRect(60, 700, 160, 750));
      expect(identical(received!.controller, editing), isTrue);
    });

    testWidgets('right-click on empty page space shows no annotation menu',
        (tester) async {
      final editing = await pumpViewer(tester);

      await rightClick(tester, viewPoint(450, 400));
      expect(find.text('Bring to front'), findsNothing);
      expect(editing.hasAnnotationSelection, isFalse);
    });
  });

  group('text context menu (mouse)', () {
    // a plain reader (no editing controller); fixture text 'Page 1' sits
    // at 72,720 in 24pt Helvetica ('Page' spans x 72..120)
    Future<PdfViewerController> pumpReader(WidgetTester tester) async {
      final controller = PdfViewerController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PdfViewer(
            initialFit: PdfViewerFit.width,
            document: PdfDocument.open(buildMultiPagePdf(1)),
            controller: controller,
          ),
        ),
      ));
      await tester.pump();
      return controller;
    }

    Future<void> rightClick(WidgetTester tester, Offset at) async {
      await tester.tapAt(at,
          kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
    }

    testWidgets('right-click on a word selects it and opens the text menu',
        (tester) async {
      final controller = await pumpReader(tester);

      await rightClick(tester, viewPoint(100, 720)); // 'Page'
      expect(controller.selectedText, 'Page');
      expect(find.byKey(const ValueKey('pdf-text-menu-copy')), findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-text-menu-select-all')),
          findsOneWidget);
      final copy = tester.widget<PopupMenuItem>(
          find.byKey(const ValueKey('pdf-text-menu-copy')));
      expect(copy.enabled, isTrue);
    });

    testWidgets('Copy puts the selection on the system clipboard',
        (tester) async {
      await pumpReader(tester);
      final copied = <String?>[];
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String?);
        }
        return null;
      });

      await rightClick(tester, viewPoint(100, 720));
      await tester.tap(find.byKey(const ValueKey('pdf-text-menu-copy')));
      await tester.pumpAndSettle();
      expect(copied, ['Page']);
    });

    testWidgets('Select all selects the whole page text', (tester) async {
      final controller = await pumpReader(tester);

      await rightClick(tester, viewPoint(100, 720));
      await tester
          .tap(find.byKey(const ValueKey('pdf-text-menu-select-all')));
      await tester.pumpAndSettle();
      expect(controller.selectedText, 'Page 1');
    });

    testWidgets('Copy is disabled over blank space, Select all stays on',
        (tester) async {
      final controller = await pumpReader(tester);

      await rightClick(tester, viewPoint(450, 400)); // no text here
      expect(controller.hasSelection, isFalse);
      final copy = tester.widget<PopupMenuItem>(
          find.byKey(const ValueKey('pdf-text-menu-copy')));
      expect(copy.enabled, isFalse);
      final all = tester.widget<PopupMenuItem>(
          find.byKey(const ValueKey('pdf-text-menu-select-all')));
      expect(all.enabled, isTrue);
    });

    testWidgets('a right-click inside an existing selection keeps it',
        (tester) async {
      final controller = await pumpReader(tester);

      // first right-click selects the word 'Page' and opens the menu
      await rightClick(tester, viewPoint(100, 720));
      expect(controller.selectedText, 'Page');
      // dismiss the menu (tap the modal barrier) without clearing the
      // viewer's text selection
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(controller.selectedText, 'Page');

      // a second right-click inside the selection must not collapse it
      // back to a single word
      await rightClick(tester, viewPoint(110, 720));
      expect(controller.selectedText, 'Page');
    });
  });
}
