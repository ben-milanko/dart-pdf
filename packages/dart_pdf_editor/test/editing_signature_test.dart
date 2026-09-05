import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('PdfInkSignature', () {
    test('normalizes pad strokes and round-trips through JSON', () {
      final signature = PdfInkSignature.fromPad(
        [
          [const Offset(10, 20), const Offset(110, 70)],
          [const Offset(60, 20)],
        ],
        [
          [0.2, 0.9],
          null,
        ],
        const Color(0xFF1A3E8C),
      )!;
      expect(signature.aspect, 2.0); // 100 wide, 50 tall
      expect(signature.color, 0x1A3E8C);
      expect(signature.strokes.first.first, (0.0, 0.0));
      expect(signature.strokes.first.last, (1.0, 1.0));
      expect(signature.strokes.last.single, (0.5, 0.0));

      final decoded = PdfInkSignature.decode(signature.encode())!;
      expect(decoded.strokes, signature.strokes);
      expect(decoded.pressures, signature.pressures);
      expect(decoded.color, signature.color);
      expect(decoded.aspect, signature.aspect);
    });

    test('carries the pen width, quoted at the reference size', () {
      final signature = PdfInkSignature.fromPad(
        [
          [const Offset(0, 0), const Offset(100, 50)]
        ],
        [null],
        const Color(0xFF000000),
        strokeWidth: 4,
      )!;
      expect(signature.strokeWidth, 4);
      // the pen scales with whatever size the signature is drawn at
      expect(signature.strokeWidthFor(PdfInkSignature.referenceWidth), 4);
      expect(signature.strokeWidthFor(PdfInkSignature.referenceWidth / 2), 2);
      expect(PdfInkSignature.decode(signature.encode())!.strokeWidth, 4);
    });

    test('a signature saved before the pad had a pen keeps the old one', () {
      const legacy = '{"color":0,"aspect":2.0,'
          '"strokes":[[0.0,0.0,1.0,1.0]],"pressures":[null]}';
      expect(PdfInkSignature.decode(legacy)!.strokeWidth,
          PdfInkSignature.defaultStrokeWidth);
      // and a nonsensical width is no better than none
      const zero = '{"color":0,"aspect":2.0,"strokeWidth":0,'
          '"strokes":[[0.0,0.0,1.0,1.0]],"pressures":[null]}';
      expect(PdfInkSignature.decode(zero)!.strokeWidth,
          PdfInkSignature.defaultStrokeWidth);
    });

    test('an empty pad yields no signature; junk decodes to null', () {
      expect(PdfInkSignature.fromPad([], [], const Color(0xFF000000)), isNull);
      expect(PdfInkSignature.decode('not json'), isNull);
      expect(PdfInkSignature.decode('{"color": 1}'), isNull);
    });

    test('persists through PdfEditingPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final a = PdfEditingPreferences();
      await a.ready;
      a.signature = PdfInkSignature.fromPad(
        [
          [const Offset(0, 0), const Offset(80, 40)]
        ],
        [null],
        const Color(0xFF000000),
      );
      await pumpEventQueue();

      final b = PdfEditingPreferences();
      await b.ready;
      expect(b.signature, isNotNull);
      expect(b.signature!.aspect, 2.0);
      expect(b.signature!.strokes.single.last, (1.0, 1.0));

      a.signature = null;
      await pumpEventQueue();
      final c = PdfEditingPreferences();
      await c.ready;
      expect(c.signature, isNull);
    });

    test('migrates the legacy singleton into the signature library', () async {
      final legacy = PdfInkSignature.fromPad(
        [
          [const Offset(0, 0), const Offset(80, 40)]
        ],
        [null],
        const Color(0xFF1A3E8C),
      )!;
      SharedPreferences.setMockInitialValues({
        'dart_pdf_editor.editing.signature': legacy.encode(),
      });

      final preferences = PdfEditingPreferences();
      await preferences.ready;
      expect(preferences.savedSignatures, hasLength(1));
      expect(preferences.savedSignatures.single.name, 'Signature 1');
      expect(preferences.signature!.color, 0x1A3E8C);

      await pumpEventQueue();
      final reopened = PdfEditingPreferences();
      await reopened.ready;
      expect(reopened.savedSignatures, hasLength(1));
      expect(reopened.activeSavedSignature!.id, 'legacy-signature');
    });

    test('persists multiple signatures and the active choice', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = PdfEditingPreferences();
      await preferences.ready;
      final editing = PdfEditingController(
        buildMultiPagePdf(1),
        preferences: preferences,
      );
      addTearDown(editing.dispose);
      final first = editing.addSavedSignature(PdfInkSignature.fromPad(
        [
          [const Offset(0, 0), const Offset(100, 50)]
        ],
        [null],
        const Color(0xFF000000),
      )!);
      final second = editing.addSavedSignature(PdfInkSignature.fromPad(
        [
          [const Offset(0, 0), const Offset(50, 100)]
        ],
        [null],
        const Color(0xFFB71C1C),
      )!);
      expect(editing.savedSignatures, hasLength(2));
      expect(editing.activeSavedSignature, second);

      // Either design can be selected and used repeatedly.
      expect(editing.placeSignature(0, 100, 600), isTrue);
      expect(editing.placeSignature(0, 300, 600), isTrue);
      editing.selectSavedSignature(first);
      expect(editing.placeSignature(0, 300, 300), isTrue);
      expect(editing.document.page(0).annotations, hasLength(3));

      await pumpEventQueue();
      final reopened = PdfEditingPreferences();
      await reopened.ready;
      expect(reopened.savedSignatures, hasLength(2));
      expect(reopened.activeSavedSignature!.id, first.id);
    });

    test('renames, redraws, and deletes individual saved signatures', () {
      PdfInkSignature drawing(int color, double width, double height) =>
          PdfInkSignature.fromPad(
            [
              [Offset.zero, Offset(width, height)]
            ],
            [null],
            Color(0xFF000000 | color),
          )!;

      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      final first = editing.addSavedSignature(drawing(0, 100, 50));
      final second = editing.addSavedSignature(drawing(0x1A3E8C, 50, 100));
      final staleSecond = second;
      expect(editing.renameSavedSignature(second, 'Work'), isTrue);
      final renamed = editing.savedSignatures.last;
      expect(renamed.name, 'Work');
      expect(
          editing.redrawSavedSignature(staleSecond, drawing(0xB71C1C, 120, 40)),
          isTrue,
          reason: 'an id-stable stale handle must not restore the old name');
      expect(editing.savedSignatures.last.name, 'Work');
      expect(editing.activeSavedSignature!.signature.color, 0xB71C1C);
      expect(editing.activeSavedSignature!.signature.aspect, 3);

      editing.removeSavedSignature(first);
      expect(editing.savedSignatures.map((entry) => entry.name), ['Work']);
      expect(editing.color, const Color(0xFFB71C1C));
      expect(editing.preferences.strokeWidth,
          editing.savedSignatures.single.signature.strokeWidth);
      editing.removeSavedSignature(editing.savedSignatures.single);
      expect(editing.savedSignatures, isEmpty);
      expect(editing.preferences.signature, isNull);
    });
  });

  group('placeSignature', () {
    PdfInkSignature signature() => PdfInkSignature.fromPad(
          [
            [const Offset(0, 0), const Offset(100, 50)]
          ],
          [
            [0.2, 1.0]
          ],
          const Color(0xFF1A3E8C),
        )!;

    test('stamps a centered, y-flipped Ink annotation', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..color = const Color(0xFF1A3E8C)
        ..preferences.signature = signature();
      expect(editing.placeSignature(0, 300, 400, width: 100), isTrue);

      final ink = editing.document.page(0).annotations.single;
      expect(ink.subtype, 'Ink');
      // the signature follows the selected toolbar colour
      expect(ink.color, 0x1A3E8C);
      // 100×50 centered on (300, 400): strokes span 250..350, 375..425
      // (the /Rect is padded for the stroke width)
      expect(ink.rect.left, lessThan(250));
      expect(ink.rect.right, greaterThan(350));
      expect(ink.rect.bottom, lessThan(375));
      expect(ink.rect.top, greaterThan(425));
      expect(ink.rect.width, lessThan(120));
    });

    test('a signature dropped at the corner hangs off the page', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..preferences.signature = signature();
      final box = editing.document.page(0).cropBox;
      expect(
          editing.placeSignature(0, box.right, box.bottom, width: 100), isTrue);

      // the tap is the centre, edge or not: roughly half the signature
      // runs off each of the two sides it was dropped against
      final ink = editing.document.page(0).annotations.single;
      expect(ink.rect.right, greaterThan(box.right));
      expect(ink.rect.bottom, lessThan(box.bottom));
      expect(ink.rect.left, lessThan(box.right));
      expect(ink.rect.top, greaterThan(box.bottom));
    });

    test('a signature is never sized wider than the page', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..preferences.signature = signature();
      final box = editing.document.page(0).cropBox;
      // running off the edge is a placement, not a size
      expect(editing.placeSignature(0, 300, 400, width: 5000), isTrue);
      final ink = editing.document.page(0).annotations.single;
      expect(ink.rect.width, lessThan(box.width));
    });

    test('the placed signature follows the selected colour, not the drawn one',
        () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..preferences.signature = signature() // drawn in 0x1A3E8C
        ..color = const Color(0xFF00AA00);
      expect(editing.placeSignature(0, 300, 400, width: 100), isTrue);
      expect(editing.document.page(0).annotations.single.color, 0x00AA00);
    });

    test('the placed pen follows the tool width, scaled with the size', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..preferences.signature = signature()
        ..preferences.strokeWidth = 4;
      expect(editing.placeSignature(0, 300, 400), isTrue);
      expect(editing.document.page(0).annotations.single.borderWidth,
          closeTo(4, 1e-9));

      // half the default size, so half the pen - the proportions hold
      expect(
          editing.placeSignature(0, 300, 200,
              width: PdfInkSignature.referenceWidth / 2),
          isTrue);
      expect(editing.document.page(0).annotations.last.borderWidth,
          closeTo(2, 1e-9));
    });

    test('without a saved signature nothing happens', () {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      expect(editing.placeSignature(0, 300, 400), isFalse);
      expect(editing.document.page(0).annotations, isEmpty);
      expect(editing.isModified, isFalse);
    });
  });

  group('signature tool in the viewer', () {
    testWidgets('signature library shows previews and chooses either design',
        (tester) async {
      PdfInkSignature drawing(int color, double width, double height) =>
          PdfInkSignature.fromPad(
            [
              [Offset.zero, Offset(width, height)]
            ],
            [null],
            Color(0xFF000000 | color),
          )!;

      final first = PdfSavedSignature.create(
        name: 'Personal',
        signature: drawing(0x000000, 100, 50),
      );
      final second = PdfSavedSignature.create(
        name: 'Company',
        signature: drawing(0x1A3E8C, 60, 80),
      );
      PdfSavedSignature? selected;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showPdfSignatureLibrary(
              context,
              signatures: [first, second],
              activeId: first.id,
              onAdd: (_) async => null,
              onRename: (_, __) async => null,
              onRedraw: (_, __) async => null,
              onSelect: (value) => selected = value,
              onDelete: (_) {},
            ),
            child: const Text('signatures'),
          ),
        ),
      ));

      await tester.tap(find.text('signatures'));
      await tester.pumpAndSettle();
      expect(find.byType(PdfSignaturePreview), findsNWidgets(2));
      expect(find.text('Personal'), findsOneWidget);
      expect(find.text('Company'), findsOneWidget);

      await tester
          .tap(find.byKey(const ValueKey('pdf-signature-library-item-1')));
      await tester.pump();
      expect(selected, second);
      expect(
        tester
            .widget<ListTile>(
                find.byKey(const ValueKey('pdf-signature-library-item-1')))
            .selected,
        isTrue,
      );
    });

    testWidgets('draw in the dialog, then tap pages to place', (tester) async {
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
          bottomNavigationBar: PdfEditingToolbar(
            controller: editing,
            viewerController: viewer,
          ),
        ),
      ));
      await tester.pump();

      // the signature tool lives in the Insert group's strip
      final dockScrollable = find
          .descendant(
              of: find.byType(PdfEditingToolbar),
              matching: find.byType(Scrollable))
          .last;
      final stripScrollable = find
          .descendant(
              of: find.byType(PdfEditingToolbar),
              matching: find.byType(Scrollable))
          .first;
      final insertChip = find.byKey(const ValueKey('pdf-group-insert'));
      await tester.scrollUntilVisible(insertChip, 80,
          scrollable: dockScrollable);
      await tester.tap(insertChip);
      await tester.pump();

      // no saved signature: the tool button opens the pad dialog first
      await tester.scrollUntilVisible(
          find.byTooltip('Signature - tap a page to place it (H)'), 100,
          scrollable: stripScrollable);
      await tester
          .tap(find.byTooltip('Signature - tap a page to place it (H)'));
      await tester.pumpAndSettle();
      expect(find.byType(PdfSignatureDialog), findsOneWidget);

      // Done is disabled until something is drawn
      expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, 'Done'))
              .onPressed,
          isNull);

      final pad = find.byKey(const ValueKey('pdf-signature-pad'));
      await tester.timedDrag(
          pad, const Offset(120, 30), const Duration(milliseconds: 200));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await tester.pumpAndSettle();

      expect(editing.preferences.signature, isNotNull);
      expect(editing.tool, PdfEditTool.signature);

      // tap the page; the double-tap recognizer holds taps ~300ms
      await tester.tapAt(tester.getCenter(find.byType(PdfViewer)));
      await tester.pumpAndSettle(const Duration(milliseconds: 350));

      final ink = editing.document.page(0).annotations.single;
      expect(ink.subtype, 'Ink');

      // armed again later, the saved signature is reused without a dialog
      editing.tool = null;
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
          find.byTooltip('Signature - tap a page to place it (H)'), 100,
          scrollable: stripScrollable);
      await tester
          .tap(find.byTooltip('Signature - tap a page to place it (H)'));
      await tester.pumpAndSettle();
      expect(find.byType(PdfSignatureDialog), findsNothing);
      expect(editing.tool, PdfEditTool.signature);
    });

    testWidgets('the pad takes any ink colour and a pen thickness',
        (tester) async {
      PdfInkSignature? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () async {
                result = await showPdfSignatureDialog(
                  context,
                  initialStrokeWidth: 2,
                  // stands in for the editor's full colour picker
                  pickColor: (context, initial) async =>
                      const Color(0xFF00AA88),
                );
              },
              child: const Text('sign'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('sign'));
      await tester.pumpAndSettle();
      expect(find.text('2.0 pt'), findsOneWidget);

      await tester.timedDrag(find.byKey(const ValueKey('pdf-signature-pad')),
          const Offset(120, 30), const Duration(milliseconds: 200));
      await tester.pump();

      // any colour at all, not just the three pen presets
      await tester.tap(find.byKey(const ValueKey('pdf-signature-custom-ink')));
      await tester.pumpAndSettle();

      // and a pen as thick as the slider goes
      await tester.drag(
          find.byKey(const ValueKey('pdf-signature-stroke-width')),
          const Offset(400, 0));
      await tester.pump();
      expect(
          find.text('${PdfInkSignature.maxStrokeWidth.toStringAsFixed(1)} pt'),
          findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await tester.pumpAndSettle();
      expect(result!.color, 0x00AA88);
      expect(result!.strokeWidth, PdfInkSignature.maxStrokeWidth);
    });

    testWidgets('the custom swatch falls back to the stock colour picker',
        (tester) async {
      PdfInkSignature? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: FilledButton(
              // no pickColor injected: the pad opens the stock picker
              onPressed: () async {
                result = await showPdfSignatureDialog(context);
              },
              child: const Text('sign'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('sign'));
      await tester.pumpAndSettle();
      await tester.timedDrag(find.byKey(const ValueKey('pdf-signature-pad')),
          const Offset(120, 30), const Duration(milliseconds: 200));
      await tester.pump();

      // dismissing the picker leaves the ink as it was
      await tester.tap(find.byKey(const ValueKey('pdf-signature-custom-ink')));
      await tester.pumpAndSettle();
      expect(find.byType(PdfColorPicker), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
      await tester.pumpAndSettle();
      expect(find.byType(PdfColorPicker), findsNothing);

      // committing one takes it
      await tester.tap(find.byKey(const ValueKey('pdf-signature-custom-ink')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'OK'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await tester.pumpAndSettle();
      // the pad's default ink, round-tripped through the picker unchanged
      expect(result!.color, 0x000000);
    });

    testWidgets('drawing seeds the tool colour and pen width', (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      editing.preferences.strokeWidth = 5;
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
          bottomNavigationBar: PdfEditingToolbar(
            controller: editing,
            viewerController: viewer,
          ),
        ),
      ));
      await tester.pump();

      final dockScrollable = find
          .descendant(
              of: find.byType(PdfEditingToolbar),
              matching: find.byType(Scrollable))
          .last;
      final stripScrollable = find
          .descendant(
              of: find.byType(PdfEditingToolbar),
              matching: find.byType(Scrollable))
          .first;
      final insertChip = find.byKey(const ValueKey('pdf-group-insert'));
      await tester.scrollUntilVisible(insertChip, 80,
          scrollable: dockScrollable);
      await tester.tap(insertChip);
      await tester.pump();
      const signatureTip = 'Signature - tap a page to place it (H)';
      await tester.scrollUntilVisible(find.byTooltip(signatureTip), 100,
          scrollable: stripScrollable);
      await tester.tap(find.byTooltip(signatureTip));
      await tester.pumpAndSettle();

      // the pad opens on the tool's current pen, not a fixed one
      expect(find.text('5.0 pt'), findsOneWidget);

      // the custom swatch routes through the editor's own picker (recents and
      // document colours wired), not a bare one
      await tester.tap(find.byKey(const ValueKey('pdf-signature-custom-ink')));
      await tester.pumpAndSettle();
      expect(find.byType(PdfColorPicker), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('pdf-signature-ink-b71c1c')));
      await tester.pump();
      await tester.drag(
          find.byKey(const ValueKey('pdf-signature-stroke-width')),
          const Offset(-400, 0));
      await tester.pump();

      await tester.timedDrag(find.byKey(const ValueKey('pdf-signature-pad')),
          const Offset(120, 30), const Duration(milliseconds: 200));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await tester.pumpAndSettle();

      // arming the tool must not restore the signature scope over the ink
      // and pen the pad just came back with
      expect(editing.tool, PdfEditTool.signature);
      expect(editing.color.toARGB32() & 0xFFFFFF, 0xB71C1C);
      expect(editing.preferences.strokeWidth, PdfInkSignature.minStrokeWidth);

      // and the stamped ink carries them
      await tester.tapAt(tester.getCenter(find.byType(PdfViewer)));
      await tester.pumpAndSettle(const Duration(milliseconds: 350));
      final ink = editing.document.page(0).annotations.single;
      expect(ink.color, 0xB71C1C);
      expect(ink.borderWidth, closeTo(PdfInkSignature.minStrokeWidth, 1e-9));
    });

    testWidgets('Clear wipes the pad and disables Done', (tester) async {
      PdfInkSignature? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () async {
                result = await showPdfSignatureDialog(context);
              },
              child: const Text('sign'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('sign'));
      await tester.pumpAndSettle();

      final pad = find.byKey(const ValueKey('pdf-signature-pad'));
      await tester.timedDrag(
          pad, const Offset(80, 20), const Duration(milliseconds: 200));
      await tester.pump();
      await tester.tap(find.text('Clear'));
      await tester.pump();
      expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, 'Done'))
              .onPressed,
          isNull);

      // draw again and finish
      await tester.timedDrag(
          pad, const Offset(60, -15), const Duration(milliseconds: 200));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      expect(result!.strokes, hasLength(1));
    });
  });
}
