import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

/// One page with 'Hello, world!' at 72,720 (24pt) and a URI link whose
/// rectangle covers the text - the sidebar shows that text as the link's
/// label.
Uint8List buildLinkOverTextPdf() {
  const content = 'BT /F1 24 Tf 72 720 Td (Hello, world!) Tj ET';
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R '
        '/Resources << /Font << /F1 5 0 R >> >> '
        '/Annots [ << /Type /Annot /Subtype /Link /Rect [60 700 300 760] '
        '/A << /S /URI /URI (https://example.com) >> >> ] >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xrefOffset = buffer.length;
  buffer
    ..write('xref\n0 ${objects.length + 1}\n')
    ..write('0000000000 65535 f \n');
  for (final offset in offsets) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer
    ..write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n')
    ..write('startxref\n$xrefOffset\n%%EOF\n');
  return ascii(buffer.toString());
}

void main() {
  Future<void> pumpSidebar(WidgetTester tester, PdfEditingController editing,
      PdfViewerController viewer) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Row(children: [
          Expanded(
            child: ListenableBuilder(
              listenable: editing,
              builder: (context, _) => PdfViewer(
                initialFit: PdfViewerFit.width,
                document: editing.document,
                controller: viewer,
                editing: editing,
              ),
            ),
          ),
          PdfAnnotationSidebar(controller: editing, viewerController: viewer),
        ]),
      ),
    ));
    await tester.pump();
  }

  testWidgets('a signed signature is deletable from the sidebar',
      (tester) async {
    final editing = PdfEditingController(buildMultiPagePdf(1));
    final viewer = PdfViewerController();
    addTearDown(editing.dispose);
    addTearDown(viewer.dispose);

    final ok = await editing.addSelfSignedSignature(
      PdfSigningIdentity.generate(name: 'Ada Lovelace'),
      appearance:
          const PdfSignatureAppearance(page: 0, rect: PdfRect(72, 640, 320, 720)),
    );
    expect(ok, isTrue);
    expect(editing.signatures, hasLength(1));

    await pumpSidebar(tester, editing, viewer);
    expect(find.text('Signature field'), findsOneWidget);

    // reveal the row actions (hover) and delete the signature
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.text('Signature field')));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('pdf-signature-delete-0-0')));
    await tester.pumpAndSettle();
    expect(find.text('Remove signature?'), findsOneWidget);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    expect(editing.signatures, isEmpty);
  });

  testWidgets('a signature with no trust store reads as unverified',
      (tester) async {
    final editing = PdfEditingController(buildMultiPagePdf(1));
    final viewer = PdfViewerController();
    addTearDown(editing.dispose);
    addTearDown(viewer.dispose);

    final ok = await editing.addSelfSignedSignature(
      PdfSigningIdentity.generate(name: 'Ada Lovelace'),
      appearance: const PdfSignatureAppearance(
          page: 0, rect: PdfRect(72, 640, 320, 720)),
    );
    expect(ok, isTrue);

    await pumpSidebar(tester, editing, viewer);
    // validation runs off the build frame; let it land
    await tester.pumpAndSettle();

    // crypto is intact but no anchors are configured, so trust is unjudged
    expect(find.text('Valid — unverified'), findsOneWidget);
    expect(find.text('No trusted authorities are configured'), findsOneWidget);
    expect(find.text('Signed by Ada Lovelace'), findsOneWidget);
  });

  testWidgets('a signature reads as trusted when its CA is in the trust store',
      (tester) async {
    final editing = PdfEditingController(buildMultiPagePdf(1));
    final viewer = PdfViewerController();
    addTearDown(editing.dispose);
    addTearDown(viewer.dispose);

    final identity = PdfSigningIdentity.generate(name: 'Ada Lovelace');
    final ok = await editing.addSelfSignedSignature(
      identity,
      appearance: const PdfSignatureAppearance(
          page: 0, rect: PdfRect(72, 640, 320, 720)),
    );
    expect(ok, isTrue);

    // trusting the (self-signed) signer certificate makes it a valid anchor
    editing.trustStore = PdfTrustStore.trusting([identity.certificate]);

    await pumpSidebar(tester, editing, viewer);
    // validation runs off the build frame; let it land
    await tester.pumpAndSettle();

    expect(find.text('Valid — trusted'), findsOneWidget);
    expect(find.text('Trusted via Ada Lovelace'), findsOneWidget);
  });

  testWidgets('annotations carry the author and the sidebar shows it',
      (tester) async {
    final editing = PdfEditingController(buildMultiPagePdf(1))
      ..preferences.author = 'Ben'
      ..addNote(0, 100, 700, 'first note');
    final viewer = PdfViewerController();
    addTearDown(editing.dispose);
    addTearDown(viewer.dispose);

    expect(editing.document.page(0).annotations.single.author, 'Ben');

    await pumpSidebar(tester, editing, viewer);
    expect(find.text('Ben - first note'), findsOneWidget);
  });

  testWidgets('long-press multi-select deletes the checked set as one undo',
      (tester) async {
    final editing = PdfEditingController(buildMultiPagePdf(2))
      ..addNote(0, 100, 700, 'first note')
      ..addRectangle(0, const PdfRect(100, 100, 200, 150))
      ..addRectangle(1, const PdfRect(100, 100, 200, 150));
    final viewer = PdfViewerController();
    addTearDown(editing.dispose);
    addTearDown(viewer.dispose);
    await pumpSidebar(tester, editing, viewer);

    await tester.longPress(find.text('Note'));
    await tester.pump();
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.byType(Checkbox), findsNWidgets(3));

    // check the page-1 square too (the first of the two Square tiles)
    await tester.tap(find.text('Square').first);
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete selected'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(editing.document.page(0).annotations, isEmpty);
    expect(editing.document.page(1).annotations, hasLength(1));
    // the revision swap leaves selection mode
    expect(find.text('2 selected'), findsNothing);
    expect(find.byType(Checkbox), findsNothing);

    // both went in one revision: a single undo restores them together
    editing.undo();
    await tester.pump();
    expect(editing.document.page(0).annotations, hasLength(2));
  });

  testWidgets('ctrl-click toggles rows in and out of the selection',
      (tester) async {
    final editing = PdfEditingController(buildMultiPagePdf(1))
      ..addRectangle(0, const PdfRect(100, 100, 200, 150))
      ..addEllipse(0, const PdfRect(250, 100, 350, 150))
      ..addNote(0, 100, 700, 'note');
    final viewer = PdfViewerController();
    addTearDown(editing.dispose);
    addTearDown(viewer.dispose);
    await pumpSidebar(tester, editing, viewer);

    // ctrl-click selects without navigating (and sets the range anchor)
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(find.text('Square'));
    await tester.pump();
    expect(editing.selectedAnnotationSlots, [(0, 0)]);

    // a second ctrl-click adds to the selection
    await tester.tap(find.text('Circle'));
    await tester.pump();
    expect(editing.selectedAnnotationSlots.toSet(), {(0, 0), (0, 1)});

    // ctrl-clicking a selected row removes it again
    await tester.tap(find.text('Circle'));
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(editing.selectedAnnotationSlots, [(0, 0)]);
    // no checkbox mode - this is the desktop modifier path
    expect(find.byType(Checkbox), findsNothing);
  });

  testWidgets('shift-click selects the range from the anchor', (tester) async {
    final editing = PdfEditingController(buildMultiPagePdf(1))
      ..addRectangle(0, const PdfRect(100, 100, 200, 150))
      ..addEllipse(0, const PdfRect(250, 100, 350, 150))
      ..addNote(0, 100, 700, 'note');
    final viewer = PdfViewerController();
    addTearDown(editing.dispose);
    addTearDown(viewer.dispose);
    await pumpSidebar(tester, editing, viewer);

    // anchor on the first row
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(find.text('Square'));
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    // shift-click the last row selects everything between
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.text('Note'));
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(editing.selectedAnnotationSlots.toSet(), {(0, 0), (0, 1), (0, 2)});
  });

  testWidgets('locked rows still navigate and flash but expose no edit actions',
      (tester) async {
    final editing = PdfEditingController(buildMultiPagePdf(1))
      ..addRectangle(0, const PdfRect(250, 350, 400, 450))
      ..addEllipse(0, const PdfRect(100, 100, 200, 150));
    final locked = editing.annotationAt(0, 0)!;
    editing.apply(
      (editor) => editor.setAnnotationFlags(0, locked, 128),
    );
    final viewer = PdfViewerController();
    addTearDown(editing.dispose);
    addTearDown(viewer.dispose);
    await pumpSidebar(tester, editing, viewer);

    expect(
        find.byKey(const ValueKey('pdf-annotation-delete-0-0')), findsNothing);
    expect(find.byKey(const ValueKey('pdf-annotation-delete-0-1')),
        findsOneWidget);

    await tester.tap(find.text('Square'));
    await tester.pump();
    expect(editing.hasAnnotationSelection, isFalse);
    expect(editing.pendingFlash, isNotNull);
    expect(editing.pendingFlash?.slot, 0);
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Square'));
    await tester.pump();
    expect(find.text('1 selected'), findsNothing);

    await tester.longPress(find.text('Circle'));
    await tester.pump();
    expect(find.text('1 selected'), findsOneWidget);

    final squareTile = find.ancestor(
      of: find.text('Square'),
      matching: find.byType(ListTile),
    );
    final circleTile = find.ancestor(
      of: find.text('Circle'),
      matching: find.byType(ListTile),
    );
    final squareCheckbox = tester.widget<Checkbox>(find.descendant(
      of: squareTile,
      matching: find.byType(Checkbox),
    ));
    final circleCheckbox = tester.widget<Checkbox>(find.descendant(
      of: circleTile,
      matching: find.byType(Checkbox),
    ));
    expect(squareCheckbox.onChanged, isNull);
    expect(circleCheckbox.onChanged, isNotNull);

    await tester.tap(find.text('Square'));
    await tester.pump();
    expect(find.text('1 selected'), findsOneWidget);
    await tester.pump(PdfEditingController.flashLifetime);
  });

  testWidgets('the sidebar locks and unlocks an annotation from its row',
      (tester) async {
    final editing = PdfEditingController(buildMultiPagePdf(1))
      ..addRectangle(0, const PdfRect(250, 350, 400, 450));
    final viewer = PdfViewerController();
    addTearDown(editing.dispose);
    addTearDown(viewer.dispose);
    await pumpSidebar(tester, editing, viewer);

    final lock = find.byKey(const ValueKey('pdf-annotation-lock-0-0'));
    expect(lock, findsOneWidget);
    expect(editing.annotationAt(0, 0)!.isLocked, isFalse);

    // lock it from the row
    await tester.tap(lock);
    await tester.pump();
    final locked = editing.annotationAt(0, 0)!;
    expect(locked.isLocked, isTrue);
    expect(locked.isLockedContents, isTrue);

    // the row's delete action is gone, but the (unlock) lock button remains
    // reachable - the only way back for a locked annotation
    expect(
        find.byKey(const ValueKey('pdf-annotation-delete-0-0')), findsNothing);
    expect(find.byKey(const ValueKey('pdf-annotation-lock-0-0')),
        findsOneWidget);

    // unlock it again
    await tester.tap(find.byKey(const ValueKey('pdf-annotation-lock-0-0')));
    await tester.pump();
    expect(editing.annotationAt(0, 0)!.isLocked, isFalse);
    expect(
        find.byKey(const ValueKey('pdf-annotation-delete-0-0')), findsOneWidget);
  });

  testWidgets('tapping a tile zooms the viewer to the annotation',
      (tester) async {
    // mid-page, so framing it needs no clamping at the document edges
    final editing = PdfEditingController(buildMultiPagePdf(1))
      ..addRectangle(0, const PdfRect(250, 350, 400, 450));
    final viewer = PdfViewerController();
    addTearDown(editing.dispose);
    addTearDown(viewer.dispose);
    await pumpSidebar(tester, editing, viewer);
    // zoom is reported in px/pt; the 520px viewport over the 612pt page
    // rests at fit-width = 520/612
    expect(viewer.zoom, closeTo(520 / 612, 0.01));

    await tester.tap(find.text('Square'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    // the viewer is 520x600 over a 612pt page: framing the 150pt-wide rect
    // at 40% viewport fill wants a px/pt scale of 0.4 * 520 / 150 ≈ 1.39
    expect(viewer.zoom, closeTo(0.4 * 520 / 150, 0.05));
    expect(editing.selectedAnnotation?.subtype, 'Square');

    // the rect (fractions of 612x792, y-down) is centered and contained
    final region = viewer.visiblePageRegion(0)!;
    expect(region.center.dx, closeTo(325 / 612, 0.02));
    expect(region.center.dy, closeTo((792 - 400) / 792, 0.02));
    expect(region.left, lessThan(250 / 612));
    expect(region.right, greaterThan(400 / 612));
    expect(region.top, lessThan((792 - 450) / 792));
    expect(region.bottom, greaterThan((792 - 350) / 792));
  });

  // the detail tests mount the sidebar alone: tiles don't need a viewer
  Future<void> pumpSidebarOnly(
      WidgetTester tester, PdfEditingController editing) async {
    final viewer = PdfViewerController();
    addTearDown(viewer.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Row(children: [
          const Expanded(child: SizedBox()),
          PdfAnnotationSidebar(
              controller: editing, viewerController: viewer, width: 360),
        ]),
      ),
    ));
    await tester.pump();
  }

  testWidgets('form-field tiles show the kind, name, and value',
      (tester) async {
    final editing = PdfEditingController(buildAcroFormPdf());
    addTearDown(editing.dispose);
    await pumpSidebarOnly(tester, editing);

    expect(find.text('Text field'), findsNWidgets(3)); // name/address/serial
    expect(find.text('name - prefilled'), findsOneWidget);
    expect(find.text('address'), findsOneWidget); // no value yet
    expect(find.text('serial - A-1000'), findsOneWidget);
    expect(find.text('Button field'), findsNWidgets(3)); // agree + 2 radios
    expect(find.text('agree - Off'), findsOneWidget);
    // radio kids inherit name and value up the /Parent chain
    expect(find.text('color - Off'), findsNWidgets(2));
    expect(find.text('Choice field'), findsOneWidget);
    expect(find.text('size - Medium'), findsOneWidget);
  });

  testWidgets('link tiles show where each link goes', (tester) async {
    final editing = PdfEditingController(buildAnnotatedPdf());
    addTearDown(editing.dispose);
    await pumpSidebarOnly(tester, editing);

    expect(find.text('Link'), findsNWidgets(5));
    expect(find.text('app://invoice/42'), findsOneWidget); // URI
    expect(find.text('Page 3'), findsOneWidget); // GoTo destination
    expect(find.text('Page 2'), findsOneWidget); // named destination
    expect(find.text('NextPage'), findsOneWidget); // named action
    expect(find.text('app://hidden'), findsOneWidget);
    // the push button resolves its field name through /Parent
    expect(find.text('Button field'), findsOneWidget);
    expect(find.text('actions.launch'), findsOneWidget);
  });

  testWidgets('a link over page text shows that text as its label',
      (tester) async {
    final editing = PdfEditingController(buildLinkOverTextPdf());
    addTearDown(editing.dispose);
    await pumpSidebarOnly(tester, editing);

    expect(find.text('Hello, world! - https://example.com'), findsOneWidget);
  });

  group('search', () {
    testWidgets('filters by type, contents, and author', (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(2))
        ..preferences.author = 'Ben'
        ..addNote(0, 100, 700, 'review this paragraph')
        ..addRectangle(0, const PdfRect(100, 100, 200, 150))
        ..addStamp(1, const PdfRect(100, 600, 240, 650), 'DRAFT');
      addTearDown(editing.dispose);
      await pumpSidebarOnly(tester, editing);
      expect(find.text('Note'), findsOneWidget);
      expect(find.text('Square'), findsOneWidget);
      expect(find.text('Stamp'), findsOneWidget);

      // by contents
      await tester.enterText(
          find.byKey(const ValueKey('pdf-annotation-search')), 'draft');
      await tester.pump();
      expect(find.text('Stamp'), findsOneWidget);
      expect(find.text('Note'), findsNothing);
      expect(find.text('Square'), findsNothing);
      // only the matching page's header survives
      expect(find.text('Page 2'), findsOneWidget);
      expect(find.text('Page 1'), findsNothing);

      // by type label
      await tester.enterText(
          find.byKey(const ValueKey('pdf-annotation-search')), 'square');
      await tester.pump();
      expect(find.text('Square'), findsOneWidget);
      expect(find.text('Stamp'), findsNothing);

      // by author (every tile carries 'Ben - …' except the bare square)
      await tester.enterText(
          find.byKey(const ValueKey('pdf-annotation-search')), 'review');
      await tester.pump();
      expect(find.text('Note'), findsOneWidget);
      expect(find.text('Stamp'), findsNothing);
    });

    testWidgets('no match shows its own message; clear restores the list',
        (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addNote(0, 100, 700, 'first note');
      addTearDown(editing.dispose);
      await pumpSidebarOnly(tester, editing);

      await tester.enterText(
          find.byKey(const ValueKey('pdf-annotation-search')), 'zzz');
      await tester.pump();
      expect(find.text('No matching annotations'), findsOneWidget);
      expect(find.text('Note'), findsNothing);

      await tester
          .tap(find.byKey(const ValueKey('pdf-annotation-search-clear')));
      await tester.pump();
      expect(find.text('Note'), findsOneWidget);
      expect(find.text('No matching annotations'), findsNothing);
    });

    testWidgets('the filter survives an edit', (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addNote(0, 100, 700, 'keep me')
        ..addRectangle(0, const PdfRect(100, 100, 200, 150));
      addTearDown(editing.dispose);
      await pumpSidebarOnly(tester, editing);

      await tester.enterText(
          find.byKey(const ValueKey('pdf-annotation-search')), 'note');
      await tester.pump();
      expect(find.text('Square'), findsNothing);

      // a new revision rebuilds the list - still filtered
      editing.addEllipse(0, const PdfRect(300, 100, 400, 150));
      await tester.pump();
      expect(find.text('Note'), findsOneWidget);
      expect(find.text('Square'), findsNothing);
      expect(find.text('Circle'), findsNothing);
    });
  });
}
