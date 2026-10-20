// PdfEditorView.extraPanels: a host's own dock panels beside the stock ones -
// a panel switch toggle, a resizable frame on their dock with a move handle
// that redocks them, a bottom sheet on compact layouts, and their dock and
// visibility persisted by id (or the visibility kept by the host).

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final geometries = <PdfSidebarPanelGeometry>[];
  setUp(geometries.clear);

  PdfEditorPanel notes({ValueNotifier<bool>? open, bool inSwitch = true}) =>
      PdfEditorPanel(
        id: 'notes',
        icon: Icons.sticky_note_2_outlined,
        label: 'Notes',
        open: open,
        showInPanelSwitch: inSwitch,
        width: 240,
        builder: (context, geometry) {
          geometries.add(geometry);
          return Column(key: const ValueKey('host-notes'), children: [
            Row(children: [
              if (geometry.moveHandle(key: const ValueKey('host-notes-move'))
                  case final handle?)
                handle,
              const Expanded(child: Text('Notes')),
              if (geometry.closeButton(key: const ValueKey('host-notes-close'))
                  case final close?)
                close,
            ]),
          ]);
        },
      );

  Future<PdfEditingPreferences> pump(
      WidgetTester tester, List<PdfEditorPanel> panels,
      {Size size = const Size(1200, 800), PdfViewModeHolder? viewMode}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final prefs = PdfEditingPreferences();
    addTearDown(prefs.dispose);
    await prefs.ready;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfEditorView(
          bytes: buildMultiPagePdf(2),
          preferences: prefs,
          viewMode: viewMode,
          extraPanels: panels,
        ),
      ),
    ));
    await tester.pump();
    return prefs;
  }

  final toggle = find.byKey(const ValueKey('pdf-shell-panel-notes-toggle'));
  final docked = find.byKey(const ValueKey('pdf-shell-panel-notes-docked'));
  final body = find.byKey(const ValueKey('host-notes'));

  testWidgets('a panel switch toggle opens it on its dock', (tester) async {
    final prefs = await pump(tester, [notes()]);
    expect(toggle, findsOneWidget);
    expect(body, findsNothing);

    await tester.tap(toggle);
    await tester.pump();
    expect(docked, findsOneWidget);
    expect(body, findsOneWidget);
    expect(prefs.extraPanelOpen('notes'), isTrue);
    expect(geometries.last.bottomSheet, isFalse);
    expect(geometries.last.dock, PdfPanelDock.right);
    expect(tester.getSize(docked).width, 240);
    // on the right of the viewer
    expect(tester.getCenter(docked).dx,
        greaterThan(tester.getCenter(find.byType(PdfViewer)).dx));

    // the frame's close button closes it
    await tester.tap(find.byKey(const ValueKey('host-notes-close')));
    await tester.pump();
    expect(body, findsNothing);
    expect(prefs.extraPanelOpen('notes'), isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the move handle redocks it to another edge', (tester) async {
    final prefs = await pump(tester, [notes()]);
    await tester.tap(toggle);
    await tester.pump();

    final handle = find.byKey(const ValueKey('host-notes-move'));
    expect(handle, findsOneWidget);
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(-24, 0));
    await tester.pump(const Duration(milliseconds: 40));
    final leftZone = find.byKey(const ValueKey('pdf-shell-dropzone-left'));
    expect(leftZone, findsOneWidget);
    await gesture.moveTo(tester.getCenter(leftZone));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(prefs.extraPanelDock('notes'), PdfPanelDock.left);
    expect(tester.getCenter(docked).dx,
        lessThan(tester.getCenter(find.byType(PdfViewer)).dx));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a host-kept open notifier drives it, without a toggle',
      (tester) async {
    final open = ValueNotifier(false);
    addTearDown(open.dispose);
    final prefs = await pump(tester, [notes(open: open, inSwitch: false)]);
    expect(toggle, findsNothing);
    expect(body, findsNothing);

    open.value = true;
    await tester.pump();
    expect(docked, findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('host-notes-close')));
    await tester.pump();
    expect(open.value, isFalse);
    expect(body, findsNothing);
    // the preferences were left alone
    expect(prefs.extraPanelOpen('notes'), isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('compact: a bottom sheet with its own chrome', (tester) async {
    final open = ValueNotifier(true);
    addTearDown(open.dispose);
    await pump(tester, [notes(open: open)], size: const Size(400, 800));
    final sheet = find.byKey(const ValueKey('pdf-shell-panel-notes-sheet'));
    expect(sheet, findsOneWidget);
    expect(docked, findsNothing);
    expect(geometries.last.bottomSheet, isTrue);
    // the sheet carries the title and close; the frame offers neither
    expect(find.descendant(of: sheet, matching: find.text('Notes')),
        findsNWidgets(2));
    expect(find.byKey(const ValueKey('host-notes-close')), findsNothing);
    await tester
        .tap(find.byKey(const ValueKey('pdf-shell-panel-notes-sheet-close')));
    await tester.pump();
    expect(open.value, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('steps aside for the page grid', (tester) async {
    final open = ValueNotifier(true);
    addTearDown(open.dispose);
    final mode = PdfViewModeController(initialMode: PdfViewMode.pages);
    addTearDown(mode.dispose);
    await pump(tester, [notes(open: open)], viewMode: mode);
    expect(docked, findsOneWidget);
    mode.viewMode = PdfViewMode.pageGrid;
    await tester.pump();
    expect(docked, findsNothing);
    mode.viewMode = PdfViewMode.pages;
    await tester.pump();
    expect(docked, findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
