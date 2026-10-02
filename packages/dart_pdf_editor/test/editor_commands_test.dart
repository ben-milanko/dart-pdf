import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

// PdfEditorCommands: the toolbar's intents as one object - tool arming with
// its prerequisites, group opening, recent tools, the catalog - shared by the
// stock toolbar, the viewer's keyboard shortcuts and the host.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// A desktop-sized surface, so the whole dock fits on one row.
  void wide(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  PdfToolGroup stockGroup(String id) =>
      pdfToolGroups.firstWhere((group) => group.id == id);

  ({PdfEditTool? tool, PdfMarkupKind? markup}) tool(PdfEditTool tool) =>
      (tool: tool, markup: null);

  group('PdfEditorCommands', () {
    late PdfEditingController editing;
    late PdfViewerController viewer;
    late PdfEditorCommands commands;

    setUp(() {
      editing = PdfEditingController(buildMultiPagePdf(1));
      viewer = PdfViewerController();
      commands =
          PdfEditorCommands(controller: editing, viewerController: viewer);
    });
    tearDown(() {
      commands.dispose();
      editing.dispose();
      viewer.dispose();
    });

    test('recent tools: most recent first, Hand mode never recorded', () {
      expect(commands.recentTools.value, isEmpty);
      editing.tool = PdfEditTool.rectangle;
      editing.tool = PdfEditTool.ink;
      editing.tool = null;
      editing.tool = PdfEditTool.rectangle;
      expect(commands.recentTools.value,
          [tool(PdfEditTool.rectangle), tool(PdfEditTool.ink)]);
    });

    test('opening a group arms its default tool; again drops to Select', () {
      commands.openGroup(stockGroup('shapes'));
      expect(editing.tool, PdfEditTool.rectangle);
      expect(commands.currentGroupId, 'shapes');

      commands.openGroup(stockGroup('shapes'));
      expect(editing.tool, PdfEditTool.select);
      expect(commands.openGroupId, 'select');

      // a group without a side-effect-free default arms nothing
      commands.openGroup(stockGroup('measure'));
      expect(editing.tool, isNull);
      expect(commands.currentGroupId, 'measure');
    });

    test('a controller swap restarts recent tools but keeps the open group',
        () async {
      commands.openGroup(stockGroup('measure'));
      editing.tool = PdfEditTool.rectangle;
      editing.tool = null;
      expect(commands.recentTools.value, [tool(PdfEditTool.rectangle)]);

      var announced = 0;
      commands.recentTools.addListener(() => announced++);
      final next = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(next.dispose);
      commands.controller = next;

      expect(commands.controller, same(next));
      expect(commands.recentTools.value, isEmpty);
      expect(commands.openGroupId, 'measure');
      // announced after the swap, never from inside it (a swap usually
      // lands while a parent builds)
      expect(announced, 0);
      await Future<void>.delayed(Duration.zero);
      expect(announced, 1);

      // the old session no longer feeds the history; the new one does
      editing.tool = PdfEditTool.ink;
      next.tool = PdfEditTool.line;
      expect(commands.recentTools.value, [tool(PdfEditTool.line)]);
    });

    test('applyColor sets the creation colour', () {
      commands.applyColor(const Color(0xFF43A047));
      expect(editing.color, const Color(0xFF43A047));
    });

    test('a toolbar-less catalog lists the tools only', () {
      final ids = [for (final c in commands.catalog(_FakeContext())) c.id];
      expect(ids, contains('tool-rectangle'));
      expect(ids, contains('markup-highlight'));
      expect(
          ids.where(
              (id) => !id.startsWith('tool-') && !id.startsWith('markup-')),
          isEmpty);
    });
  });

  group('the stock toolbar', () {
    testWidgets(
        'a controller swap keeps the open group and forgets recent tools',
        (tester) async {
      wide(tester);
      final first = PdfEditingController(buildMultiPagePdf(1));
      final second = PdfEditingController(buildMultiPagePdf(1));
      final viewer = PdfViewerController();
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      addTearDown(viewer.dispose);
      final current = ValueNotifier(first);
      addTearDown(current.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ValueListenableBuilder(
              valueListenable: current,
              builder: (context, controller, _) => PdfEditingToolbar(
                  controller: controller, viewerController: viewer),
            ),
          ),
        ),
      ));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('pdf-group-shapes')),
          kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(first.tool, PdfEditTool.rectangle);
      await tester.tap(find.byKey(const ValueKey('pdf-group-measure')),
          kind: PointerDeviceKind.mouse);
      await tester.pump();
      final measure = find.byKey(const ValueKey('pdf-tool-measureDistance'));
      expect(measure, findsOneWidget);
      final commands = PdfEditorCommands.of(tester.element(measure));
      expect(commands.recentTools.value, [tool(PdfEditTool.rectangle)]);

      current.value = second;
      await tester.pump();

      // the Measure strip is still open over the new document...
      expect(measure, findsOneWidget);
      // ...through the same commands, now driving the new session, with no
      // history carried over from the old one
      expect(PdfEditorCommands.of(tester.element(measure)), same(commands));
      expect(commands.controller, same(second));
      expect(commands.recentTools.value, isEmpty);
    });

    testWidgets('a measure tool asks for the scale before it arms',
        (tester) async {
      wide(tester);
      final editing = PdfEditingController(buildMultiPagePdf(1));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: PdfEditingToolbar(
                controller: editing, viewerController: viewer),
          ),
        ),
      ));
      await tester.tap(find.byKey(const ValueKey('pdf-group-measure')),
          kind: PointerDeviceKind.mouse);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pdf-tool-measureDistance')),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(find.byType(PdfScaleDialog), findsOneWidget);
      await tester.enterText(
          find.byKey(const ValueKey('pdf-scale-value')), '2');
      await tester.tap(find.byKey(const ValueKey('pdf-scale-apply')));
      await tester.pumpAndSettle();
      expect(editing.hasMeasurementScale, isTrue);
      expect(editing.tool, PdfEditTool.measureDistance);
    });
  });

  group('toolGroups', () {
    Future<PdfEditingController> pumpToolbar(
        WidgetTester tester, List<PdfToolGroup> groups) async {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: PdfEditingToolbar(
              controller: editing,
              viewerController: viewer,
              toolGroups: groups,
            ),
          ),
        ),
      ));
      await tester.pump();
      return editing;
    }

    testWidgets('an ordered list with a host group of commands',
        (tester) async {
      var approvals = 0;
      final approved = ValueNotifier(false);
      addTearDown(approved.dispose);
      final approve = PdfCommand(
        id: 'approve',
        icon: Icons.verified_outlined,
        label: (_) => 'Approve',
        selected: approved,
        invoke: (context) async {
          approvals++;
          approved.value = true;
        },
      );
      final editing = await pumpToolbar(tester, [
        stockGroup('select'),
        stockGroup('shapes'),
        PdfToolGroup(
          'review',
          Icons.rate_review_outlined,
          [
            PdfToolEntry.command(approve),
            const PdfToolEntry.tool(
                PdfEditTool.note, Icons.sticky_note_2_outlined),
          ],
          labelBuilder: (_) => 'Review',
        ),
        stockGroup('draw'),
      ]);

      final shapes = find.byKey(const ValueKey('pdf-group-shapes'));
      final review = find.byKey(const ValueKey('pdf-group-review'));
      final draw = find.byKey(const ValueKey('pdf-group-draw'));
      expect(find.byKey(const ValueKey('pdf-group-markup')), findsNothing);
      expect(find.byKey(const ValueKey('pdf-group-measure')), findsNothing);
      // the dock follows the list's order
      expect(
          tester.getCenter(shapes).dx, lessThan(tester.getCenter(review).dx));
      expect(tester.getCenter(review).dx, lessThan(tester.getCenter(draw).dx));
      expect(find.text('Review'), findsOneWidget);

      // a group with no kind and no default tool opens its strip unarmed
      await tester.tap(review, kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(editing.tool, isNull);
      final approveButton = find.byKey(const ValueKey('pdf-command-approve'));
      expect(approveButton, findsOneWidget);
      expect(
          tester.getSemantics(approveButton), isSemantics(isSelected: false));

      await tester.tap(approveButton, kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(approvals, 1);
      expect(tester.getSemantics(approveButton), isSemantics(isSelected: true));

      // a stock tool in a host group still arms through the commands
      await tester.tap(find.byKey(const ValueKey('pdf-tool-note')),
          kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(editing.tool, PdfEditTool.note);
    });

    testWidgets('a disabled command is drawn disabled', (tester) async {
      final command = PdfCommand(
        id: 'later',
        icon: Icons.schedule,
        label: (_) => 'Later',
        enabled: PdfCommand.neverSelected,
        invoke: (context) async => fail('a disabled command ran'),
      );
      await pumpToolbar(tester, [
        stockGroup('select'),
        PdfToolGroup(
            'extra', Icons.more_horiz, [PdfToolEntry.command(command)]),
      ]);
      await tester.tap(find.byKey(const ValueKey('pdf-group-extra')),
          kind: PointerDeviceKind.mouse);
      await tester.pump();
      final button = find.byKey(const ValueKey('pdf-command-later'));
      expect(tester.getSemantics(button), isSemantics(isEnabled: false));
    });

    testWidgets('a stock group keeps its behaviour wherever it sits',
        (tester) async {
      await pumpToolbar(tester, [
        stockGroup('edit'),
        stockGroup('select'),
        stockGroup('markup'),
      ]);
      final edit = find.byKey(const ValueKey('pdf-group-edit'));
      final markup = find.byKey(const ValueKey('pdf-group-markup'));
      expect(tester.getCenter(edit).dx, lessThan(tester.getCenter(markup).dx));
      // Edit's strip still names its tools...
      await tester.tap(edit, kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(find.text('Content'), findsOneWidget);
      // ...and Markup's still asks for a text selection
      await tester.tap(markup, kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(
          find.byKey(const ValueKey('pdf-markup-highlight')), findsOneWidget);
    });

    testWidgets('PdfEditingToolbar.groups filters host lists by kind',
        (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: PdfEditingToolbar(
              controller: editing,
              viewerController: viewer,
              groups: const {PdfEditToolGroup.select, PdfEditToolGroup.draw},
              toolGroups: [
                ...pdfToolGroups,
                PdfToolGroup('host', Icons.extension, [
                  PdfToolEntry.command(PdfCommand(
                    id: 'noop',
                    icon: Icons.extension,
                    label: (_) => 'Noop',
                    invoke: (_) async {},
                  )),
                ]),
              ],
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(find.byKey(const ValueKey('pdf-group-draw')), findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-group-shapes')), findsNothing);
      // a host group has no kind, so the kind filter leaves it alone
      expect(find.byKey(const ValueKey('pdf-group-host')), findsOneWidget);
    });
  });

  group('PdfEditorView', () {
    Future<void> pump(WidgetTester tester, Widget body) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: body)));
      await tester.pump();
    }

    testWidgets('one commands object for the toolbar, the viewer and the host',
        (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(2));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      final commands =
          PdfEditorCommands(controller: editing, viewerController: viewer);
      addTearDown(commands.dispose);
      await pump(
          tester,
          PdfEditorView(
            controller: editing,
            viewerController: viewer,
            commands: commands,
          ));
      expect(PdfEditorCommands.of(tester.element(find.byType(PdfViewer))),
          same(commands));
      expect(
          PdfEditorCommands.of(tester
              .element(find.byKey(const ValueKey('pdf-tool-bar-shapes')))),
          same(commands));

      // the host's handle drives the stock toolbar
      commands.openGroup(stockGroup('measure'));
      await tester.pump();
      expect(find.byKey(const ValueKey('pdf-tool-measureDistance')),
          findsOneWidget);
    });

    testWidgets('owns its commands when the host passes none', (tester) async {
      await pump(tester, PdfEditorView(bytes: buildMultiPagePdf(1)));
      final commands =
          PdfEditorCommands.of(tester.element(find.byType(PdfViewer)));
      expect(
          PdfEditorCommands.of(tester
              .element(find.byKey(const ValueKey('pdf-tool-bar-shapes')))),
          same(commands));
      expect(commands.controller,
          same(tester.widget<PdfViewer>(find.byType(PdfViewer)).editing));
    });

    testWidgets('catalog: tools, panels, view modes and save', (tester) async {
      var saved = 0;
      var savedAs = 0;
      final prefs = PdfEditingPreferences();
      addTearDown(prefs.dispose);
      await pump(
          tester,
          PdfEditorView(
            bytes: buildMultiPagePdf(1),
            preferences: prefs,
            alwaysAllowSave: true,
            onSave: (_) => saved++,
            onSaveAs: (_) => savedAs++,
          ));
      final context = tester.element(find.byType(PdfViewer));
      final catalog = PdfEditorCommands.of(context).catalog(context);
      final byId = {for (final command in catalog) command.id: command};
      expect(
          byId.keys,
          containsAll([
            'tool-select',
            'tool-rectangle',
            'markup-highlight',
            'panel-search',
            'panel-pages',
            'panel-bookmarks',
            'panel-annotations',
            'panel-annotation-library',
            'panel-properties',
            'view-annotations',
            'view-reflow',
            'view-page-grid',
            'view-form-fields',
            'view-scrollbar-chapters',
            'save',
            'save-as',
          ]));
      // the shell offers neither without the host callback behind it
      expect(byId, isNot(contains('tool-signatureBox')));
      expect(byId, isNot(contains('tool-image')));
      // tools carry their key binding
      expect(byId['tool-rectangle']!.shortcutLabel, 'R');
      expect(byId['tool-rectangle']!.category, PdfCommandCategory.tool);
      expect(byId['tool-rectangle']!.toolGroup?.id, 'shapes');
      expect(byId['tool-rectangle']!.label(context), 'Rectangle');

      final bookmarks = byId['panel-bookmarks']!;
      final before = prefs.showBookmarkSidebar;
      expect(bookmarks.selected.value, before);
      await bookmarks.invoke(context);
      expect(prefs.showBookmarkSidebar, !before);
      expect(bookmarks.selected.value, !before);

      await byId['tool-rectangle']!.invoke(context);
      expect(byId['tool-rectangle']!.selected.value, isTrue);

      await byId['view-reflow']!.invoke(context);
      await tester.pump();
      expect(byId['view-reflow']!.selected.value, isTrue);
      await byId['view-reflow']!.invoke(context);
      await tester.pump();
      expect(byId['view-reflow']!.selected.value, isFalse);

      expect(byId['save']!.enabled.value, isTrue);
      await byId['save']!.invoke(context);
      await byId['save-as']!.invoke(context);
      expect((saved, savedAs), (1, 1));
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('the catalog follows the features', (tester) async {
      await pump(
          tester,
          PdfEditorView(
            bytes: buildMultiPagePdf(1),
            features: const PdfEditorFeatures(
              bookmarks: false,
              reflowView: false,
              markup: false,
              tools: {PdfEditTool.select, PdfEditTool.ink},
            ),
          ));
      final context = tester.element(find.byType(PdfViewer));
      final ids = [
        for (final command in PdfEditorCommands.of(context).catalog(context))
          command.id
      ];
      expect(ids, containsAll(['tool-select', 'tool-ink', 'panel-pages']));
      for (final gone in [
        'tool-rectangle',
        'markup-highlight',
        'panel-bookmarks',
        'view-reflow',
        'save',
      ]) {
        expect(ids, isNot(contains(gone)), reason: gone);
      }
    });

    testWidgets('a catalog measure command asks for the scale first',
        (tester) async {
      await pump(tester, PdfEditorView(bytes: buildMultiPagePdf(1)));
      final context = tester.element(find.byType(PdfViewer));
      final commands = PdfEditorCommands.of(context);
      final measure = commands
          .catalog(context)
          .firstWhere((command) => command.id == 'tool-measureDistance');
      final done = measure.invoke(context);
      await tester.pumpAndSettle();
      expect(find.byType(PdfScaleDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await done;
      // dismissed: nothing armed
      expect(commands.controller.tool, isNot(PdfEditTool.measureDistance));
    });
  });

  group('keyboard tool shortcuts', () {
    const scale = 800 / 612;
    final empty = const Offset(450 * scale, (792 - 400) * scale);

    Future<PdfEditingController> pumpViewer(WidgetTester tester,
        {required bool scoped}) async {
      final editing = PdfEditingController(buildMultiPagePdf(2));
      final viewer = PdfViewerController();
      final commands =
          PdfEditorCommands(controller: editing, viewerController: viewer);
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      addTearDown(commands.dispose);
      Widget body = ListenableBuilder(
        listenable: editing,
        builder: (context, _) => PdfViewer(
          initialFit: PdfViewerFit.width,
          document: editing.document,
          controller: viewer,
          editing: editing,
        ),
      );
      if (scoped) {
        body = PdfEditorCommandsScope(commands: commands, child: body);
      }
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: body)));
      await tester.pump();
      await tester.tapAt(empty, kind: PointerDeviceKind.mouse);
      await tester.pump();
      return editing;
    }

    testWidgets('under commands, M asks for the scale before it arms',
        (tester) async {
      final editing = await pumpViewer(tester, scoped: true);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await tester.pumpAndSettle();
      expect(find.byType(PdfScaleDialog), findsOneWidget);
      expect(editing.tool, isNot(PdfEditTool.measureDistance));

      await tester.enterText(
          find.byKey(const ValueKey('pdf-scale-value')), '4');
      await tester.tap(find.byKey(const ValueKey('pdf-scale-apply')));
      await tester.pumpAndSettle();
      expect(editing.tool, PdfEditTool.measureDistance);
      expect(editing.preferences.measurementScale, isNotNull);
    });

    testWidgets('under commands, H asks for a signature first', (tester) async {
      final editing = await pumpViewer(tester, scoped: true);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
      await tester.pumpAndSettle();
      expect(find.byType(PdfSignatureDialog), findsOneWidget);
      expect(editing.tool, isNot(PdfEditTool.signature));
    });

    testWidgets('under commands, plain tools still toggle', (tester) async {
      final editing = await pumpViewer(tester, scoped: true);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.pump();
      expect(editing.tool, PdfEditTool.rectangle);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.pump();
      expect(editing.tool, PdfEditTool.select);
    });

    testWidgets('a bare viewer arms directly, as before', (tester) async {
      final editing = await pumpViewer(tester, scoped: false);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await tester.pumpAndSettle();
      expect(find.byType(PdfScaleDialog), findsNothing);
      expect(editing.tool, PdfEditTool.measureDistance);
    });

    testWidgets('PdfEditorView routes its shortcuts through the commands',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: PdfEditorView(
                  bytes: buildMultiPagePdf(1),
                  initialFit: PdfViewerFit.width))));
      await tester.pump();
      await tester.tapAt(tester.getCenter(find.byType(PdfViewer)),
          kind: PointerDeviceKind.mouse);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await tester.pumpAndSettle();
      expect(find.byType(PdfScaleDialog), findsOneWidget);
    });
  });
}

/// A context the toolbar-less catalog never reads (labels are closures).
class _FakeContext extends Fake implements BuildContext {}
