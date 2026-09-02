import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_viewer_example/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> openDemo(
    WidgetTester tester, {
    PdfIdentityStore? identityStore,
  }) async {
    // the mock store is process-global: start every test from defaults
    SharedPreferences.setMockInitialValues({});
    // These exercise the desktop dock. At the default 800px test width the
    // open thumbnail panel intentionally collapses it to the mobile tool sheet.
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ViewerApp(identityStore: identityStore));
    // use-deferred-loading makes the localizations delegate load
    // asynchronously, so the app subtree - and the post-frame demo open -
    // only appear after the deferred unit resolves over several frames.
    // pumpAndSettle can't be used (the open demo runs a periodic clock timer
    // that never settles), so pump a bounded number of frames until the demo
    // viewer is up.
    for (var i = 0; i < 20 && find.byType(PdfViewer).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Demo pages are 612×792pt and the viewer opens fit-page, so the
  /// on-screen page rect comes from the viewer's own fit math.
  Rect pageRect(WidgetTester tester) {
    final viewer = tester.getRect(find.byType(PdfViewer));
    const aspect = 792 / 612;
    final zoom = (viewer.height / (viewer.width * aspect)).clamp(0.0, 1.0);
    final width = viewer.width * zoom;
    return Rect.fromLTWH(viewer.left + (viewer.width - width) / 2, viewer.top,
        width, width * aspect);
  }

  /// A view-space point at the given fractions of the first page.
  Offset onPage(WidgetTester tester, double fx, double fy) {
    final page = pageRect(tester);
    return page.topLeft + Offset(page.width * fx, page.height * fy);
  }

  /// Opens the grouped desktop dock when necessary, then taps its tool.
  Future<void> tapToolbar(WidgetTester tester, String tooltip) async {
    Finder buttonFor(String label) => find.byWidgetPredicate(
          (widget) =>
              widget is Tooltip &&
              (widget.message == label ||
                  (widget.message?.startsWith('$label (') ?? false) ||
                  (widget.message?.startsWith('$label -') ?? false)),
        );

    final group = switch (tooltip) {
      'Select' => 'select',
      'Draw' => 'draw',
      'Rectangle' => 'shapes',
      'Note' => 'insert',
      'Digital signature' => 'insert',
      _ => null,
    };
    if (group != null) {
      await tester.tap(find.byKey(ValueKey('pdf-group-$group')));
      await tester.pump();
      // A group chip arms its default tool itself. Tapping the same tool in
      // the strip would immediately toggle it back to Select.
      if (const {'Select', 'Draw', 'Rectangle'}.contains(tooltip)) return;
    }
    final button = buttonFor(tooltip);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
  }

  /// Arms the select tool and taps [position] (waiting out the viewer's
  /// competing double-tap recognizer).
  Future<void> selectAt(WidgetTester tester, Offset position) async {
    await tapToolbar(tester, 'Select');
    await tester.tapAt(position);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// Adds a rectangle annotation dragged out from 25% across the page and
  /// returns its view-space center, ready to be selected.
  Future<Offset> addRectangle(WidgetTester tester) async {
    await tapToolbar(tester, 'Rectangle');
    final start = onPage(tester, 0.25, 0.25);
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(30, 20)); // past the drag slop
    await tester.pump();
    await gesture.moveBy(const Offset(70, 50));
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400)); // revision reload
    return start + const Offset(50, 35);
  }

  testWidgets('rectangle tool drags out an annotation', (tester) async {
    await openDemo(tester);
    final center = await addRectangle(tester);

    // committed straight to the document: the select tool finds it
    await selectAt(tester, center);
    expect(find.byTooltip('Delete annotation'), findsOneWidget);
  });

  testWidgets('note tool prompts for text and places a note', (tester) async {
    await openDemo(tester);
    await tapToolbar(tester, 'Note');

    final position = onPage(tester, 0.4, 0.3);
    await tester.tapAt(position);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(AlertDialog), findsOneWidget); // the text prompt
    await tester.enterText(find.byType(TextField).last, 'A test note');
    await tester.tap(find.text('OK'));
    // one frame starts the route pop, the next finishes its transition
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(AlertDialog), findsNothing);

    // the note exists: selecting its icon (20pt, hung down-right of the
    // tap point) surfaces the annotation buttons
    final s = pageRect(tester).width / 612;
    await selectAt(tester, position + Offset(10 * s, 10 * s));
    expect(find.byTooltip('Delete annotation'), findsOneWidget);
    expect(find.byTooltip('Edit annotation text'), findsOneWidget);
  });

  testWidgets('select tool picks an annotation and deletes it', (tester) async {
    await openDemo(tester);
    final center = await addRectangle(tester);
    await selectAt(tester, center);

    expect(find.byTooltip('Delete annotation'), findsOneWidget);
    await tapToolbar(tester, 'Delete annotation');
    expect(find.byTooltip('Delete annotation'), findsNothing);

    // tapping the same spot again selects nothing
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byTooltip('Delete annotation'), findsNothing);
  });

  testWidgets('dragging a selected annotation moves it', (tester) async {
    await openDemo(tester);
    final center = await addRectangle(tester);
    await selectAt(tester, center);
    expect(find.byTooltip('Delete annotation'), findsOneWidget);

    // pass the slop in a small step so the pan's accepted start point is
    // still inside the annotation, then move for real
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(19, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(20, 15));
    await tester.pump();
    await gesture.moveBy(const Offset(20, 15));
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));

    // the move landed: tapping the shifted center hits the annotation
    await tester.tapAt(center + const Offset(59, 30));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byTooltip('Delete annotation'), findsOneWidget);
  });

  testWidgets('note text can be edited through the selection', (tester) async {
    await openDemo(tester);

    // place a note
    await tapToolbar(tester, 'Note');
    final position = onPage(tester, 0.45, 0.35);
    await tester.tapAt(position);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.enterText(find.byType(TextField).last, 'first draft');
    await tester.tap(find.text('OK'));
    await tester.pump(const Duration(milliseconds: 400));

    final s = pageRect(tester).width / 612;
    await selectAt(tester, position + Offset(10 * s, 10 * s));
    expect(find.byTooltip('Edit annotation text'), findsOneWidget);
    await tapToolbar(tester, 'Edit annotation text');
    await tester.pump();

    expect(find.widgetWithText(TextField, 'first draft'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'second draft');
    await tester.tap(find.text('OK'));
    await tester.pump(const Duration(milliseconds: 400));

    // the selection survived the rewrite: reopening shows the new text
    await tapToolbar(tester, 'Edit annotation text');
    await tester.pump();
    expect(find.widgetWithText(TextField, 'second draft'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
  });

  testWidgets('draw tool collects strokes and they auto-commit',
      (tester) async {
    await openDemo(tester);
    await tapToolbar(tester, 'Draw');

    final start = onPage(tester, 0.3, 0.5);
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(25, 10));
    await tester.pump();
    await gesture.moveBy(const Offset(40, -20));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    // auto-commit: no confirm button - the stroke lands on its own
    expect(find.byTooltip('Add ink annotation'), findsNothing);
    await tester.pump(const Duration(seconds: 1));

    // committed: the select tool finds the stroke
    await selectAt(tester, start + const Offset(30, 0));
    expect(find.byTooltip('Delete annotation'), findsOneWidget);
  });

  testWidgets('digital signature creates an identity and signs the PDF',
      (tester) async {
    final identities = InMemoryIdentityStore();
    await openDemo(tester, identityStore: identities);
    await tapToolbar(tester, 'Digital signature');

    final start = onPage(tester, 0.25, 0.3);
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(30, 20));
    await tester.pump();
    await gesture.moveBy(const Offset(160, 55));
    await gesture.up();
    await tester.pump();

    expect(find.text('Create signing identity'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'Example Signer');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    final viewer = tester.widget<PdfViewer>(find.byType(PdfViewer));
    expect(viewer.editing!.signatures, hasLength(1));
    final validation = viewer.editing!.signatures.single.validate();
    expect(validation.intact, isTrue);
    expect(validation.coversWholeDocument, isTrue);
    expect(await identities.ids(), ['Example Signer']);

    // The demo runs a periodic clock, so explicitly unmount it rather than
    // leaving that timer for the test binding's invariant check.
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
