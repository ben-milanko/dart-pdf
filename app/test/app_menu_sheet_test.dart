// On a phone the app menu is a bottom sheet: a search field, four large
// buttons (New, Open, Print, Sign), and the rarer actions folded under Export
// and More tools. Tablets and desktops keep the sectioned popup
// (app_menu_sections_test.dart).
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/editor_screen.dart';

void main() {
  late PdfEditingPreferences prefs;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    prefs = PdfEditingPreferences();
  });
  tearDown(() => prefs.dispose());

  void phoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> pump(
    WidgetTester tester, {
    bool withDoc = false,
    bool withScanner = false,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(
        prefs: prefs,
        documentScanner: withScanner ? () async => null : null,
        initialDocument:
            withDoc ? (bytes: buildClassicPdf(), title: 'Report.pdf') : null,
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('DartPDF menu'));
    await tester.pumpAndSettle();
  }

  Finder key(String value) => find.byKey(ValueKey(value));

  testWidgets('a phone gets the sheet with the four large buttons',
      (tester) async {
    phoneSize(tester);
    await pump(tester, withDoc: true);
    await openMenu(tester);

    expect(key('app-menu-sheet'), findsOneWidget);
    expect(find.text('FILE'), findsNothing);
    expect(key('menu-command-palette'), findsOneWidget);
    for (final id in [
      'menu-new',
      'menu-open',
      'menu-print',
      'menu-digital-signature',
    ]) {
      expect(key(id), findsOneWidget, reason: id);
    }
    expect(find.text('New'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Print'), findsOneWidget);
    expect(find.text('Sign'), findsOneWidget);

    // The header's Share button already covers this on a phone.
    expect(key('menu-save-as'), findsNothing);
    // Rarer actions are folded, not listed.
    expect(key('menu-reduce-file-size'), findsNothing);
    expect(key('menu-compare'), findsNothing);
    expect(key('menu-group-export'), findsOneWidget);
    expect(key('menu-group-more-tools'), findsOneWidget);
    expect(key('menu-read-only'), findsOneWidget);
    expect(key('menu-settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a folded group opens a page, and back returns to the menu',
      (tester) async {
    phoneSize(tester);
    await pump(tester, withDoc: true);
    await openMenu(tester);

    await tester.tap(key('menu-group-export'));
    await tester.pumpAndSettle();
    expect(key('app-menu-sheet-export'), findsOneWidget);
    expect(key('menu-export-image'), findsOneWidget);
    expect(key('menu-reduce-file-size'), findsOneWidget);
    expect(key('menu-print'), findsNothing);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(key('app-menu-sheet'), findsOneWidget);

    await tester.tap(key('menu-group-more-tools'));
    await tester.pumpAndSettle();
    expect(key('menu-compare'), findsOneWidget);
    expect(key('menu-insert-document'), findsOneWidget);

    // System back leaves the page first, then the sheet.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(key('app-menu-sheet'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(key('app-menu-sheet'), findsNothing);
  });

  testWidgets('with nothing open only New and Open remain', (tester) async {
    phoneSize(tester);
    await pump(tester);
    await openMenu(tester);

    expect(key('menu-new'), findsOneWidget);
    expect(key('menu-open'), findsOneWidget);
    expect(key('menu-print'), findsNothing);
    expect(key('menu-digital-signature'), findsNothing);
    expect(key('menu-group-export'), findsNothing);
    expect(key('menu-read-only'), findsNothing);
    expect(key('menu-settings'), findsOneWidget);
  });

  testWidgets('New asks blank or scan, then runs the pick', (tester) async {
    phoneSize(tester);
    await pump(tester, withScanner: true);
    await openMenu(tester);

    await tester.tap(key('menu-new'));
    await tester.pumpAndSettle();
    expect(key('app-menu-sheet-new'), findsOneWidget);
    expect(key('menu-scan-document'), findsOneWidget);

    await tester.tap(key('menu-new-document'));
    await tester.pumpAndSettle();
    expect(key('app-menu-sheet-new'), findsNothing);
    expect(key('new-document-dialog'), findsOneWidget);
  });

  testWidgets('read-only is a switch in the sheet', (tester) async {
    phoneSize(tester);
    await pump(tester, withDoc: true);
    await openMenu(tester);

    final row = key('menu-read-only');
    expect(tester.getSemantics(row), isSemantics(isToggled: false));
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.byType(PdfReader), findsOneWidget);

    await openMenu(tester);
    expect(tester.getSemantics(row), isSemantics(isToggled: true));
  });

  testWidgets('a tablet-width touch screen keeps the popup', (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pump(tester, withDoc: true);
    await openMenu(tester);

    expect(key('app-menu-sheet'), findsNothing);
    expect(find.text('FILE'), findsOneWidget);
  });
}
