// The Cupertino host example: the editor in a CupertinoApp with a nav bar
// built from PdfHeaderParts, a toolbar from the command catalog, and a
// Cupertino presenter - the acceptance test for the 5.x UI seams.

import 'package:dart_pdf_editor/cupertino.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:pdf_viewer_example/cupertino_host.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpHost(WidgetTester tester,
      {Size size = const Size(1000, 800)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(CupertinoHostApp(bytes: buildMultiPagePdf(2)));
    // the editor localizations load asynchronously
    for (var i = 0; i < 10 && find.byType(PdfViewer).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump();
  }

  void expectNoErrors(WidgetTester tester) {
    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
  }

  testWidgets('nav bar from header parts, toolbar from the catalog',
      (tester) async {
    await pumpHost(tester);
    expect(find.byType(CupertinoApp), findsOneWidget);
    final nav = find.byKey(const ValueKey('cupertino-nav-bar'));
    expect(nav, findsOneWidget);
    expect(find.descendant(of: nav, matching: find.byType(PdfPageNumberField)),
        findsOneWidget);
    expect(find.descendant(of: nav, matching: find.byType(PdfSearchField)),
        findsOneWidget);
    expect(
        find.descendant(
            of: nav, matching: find.byKey(const ValueKey('pdf-shell-save'))),
        findsOneWidget);
    // the stock header and toolbar are gone
    expect(find.byType(PdfEditingToolbar), findsNothing);
    expect(find.byKey(const ValueKey('cupertino-command-bar')), findsOneWidget);

    // a catalog command arms its tool, and reads back as selected
    final rect = find.byKey(const ValueKey('cupertino-tool-rectangle'));
    expect(rect, findsOneWidget);
    await tester.tap(rect);
    await tester.pumpAndSettle();
    final commands = PdfEditorCommands.of(tester.element(rect));
    expect(commands.controller.tool, PdfEditTool.rectangle);
    expect(tester.widget<CupertinoButton>(rect).color, isNotNull);
    expectNoErrors(tester);
  });

  testWidgets('menus are action sheets', (tester) async {
    await pumpHost(tester);
    final viewer = find.byType(PdfViewer);
    final page = tester.getTopLeft(viewer);
    // right-click the fixture's page text
    final scale = tester.getSize(viewer).width / 612;
    await tester.tapAt(page + Offset(80 * scale, (792 - 728) * scale),
        kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pdf-cupertino-menu')), findsOneWidget);
    expect(find.byType(CupertinoActionSheet), findsOneWidget);
    expect(find.byKey(const ValueKey('pdf-text-menu-copy')), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoActionSheet), findsNothing);
    expectNoErrors(tester);
  });

  testWidgets('prompts are alert dialogs; notices are toasts', (tester) async {
    await pumpHost(tester);
    final context = tester.element(find.byType(PdfViewer));
    final presenter = PdfEditorPresenter.of(context);
    expect(presenter, isA<PdfCupertinoPresenter>());

    final answer = presenter.text(
        context, const PdfTextRequest(title: 'Name', initial: 'a'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('pdf-text-prompt-field')), 'Report');
    await tester.tap(find.byKey(const ValueKey('pdf-text-prompt-ok')));
    await tester.pumpAndSettle();
    expect(await answer, 'Report');

    final confirmed = presenter.confirm(
        context,
        const PdfConfirmRequest(
            title: 'Remove?',
            message: 'Sure?',
            confirmLabel: 'Remove',
            destructive: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(await confirmed, isTrue);

    // Save reports through the Cupertino toast
    await tester.tap(find.byKey(const ValueKey('pdf-shell-save')));
    await tester.pump();
    expect(find.byKey(const ValueKey('pdf-cupertino-toast')), findsOneWidget);
    expect(find.text('Saved (1)'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    expect(find.byKey(const ValueKey('pdf-cupertino-toast')), findsNothing);
    expectNoErrors(tester);
  });

  testWidgets('compact: the controls part keeps the rest one tap away',
      (tester) async {
    await pumpHost(tester, size: const Size(390, 800));
    expect(find.byKey(const ValueKey('pdf-shell-save')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pdf-shell-controls')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pdf-shell-thumbnails-toggle')),
        findsOneWidget);
    // save stays in the nav bar, not duplicated in the sheet
    expect(find.byKey(const ValueKey('pdf-shell-save')), findsOneWidget);
    expectNoErrors(tester);
  });
}
