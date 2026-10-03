// The example's runtime design switch: Material -> Cupertino from the app
// menu, Cupertino -> Material from the Cupertino settings page. The open
// document, its page and its unsaved edits survive both swaps (the edit
// session lives in the app-wide workspace, above the app root), and the
// choice is saved like the example's other preferences.

import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoApp;
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf_document/pdf_document.dart' show PdfMemoryCacheStore;
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:pdf_viewer_example/main.dart';
import 'package:pdf_viewer_example/workspace.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ViewerApp(
      cacheStore: PdfMemoryCacheStore(),
      initialBytes: buildMultiPagePdf(4),
    ));
    await pumpUntilViewer(tester);
  }

  PdfEditorView editorView(WidgetTester tester) =>
      tester.widget<PdfEditorView>(find.byType(PdfEditorView));

  void expectNoErrors(WidgetTester tester) {
    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
  }

  testWidgets('Material -> Cupertino -> Material keeps the document and edits',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpApp(tester);
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(CupertinoApp), findsNothing);

    final session = editorView(tester).controller!;
    final viewer = editorView(tester).viewerController!;
    // an unsaved edit, then a page other than the first
    session.removePage(0);
    await tester.pump();
    expect(session.document.pageCount, 3);
    expect(session.canUndo, isTrue);
    unawaited(viewer.jumpToPage(2));
    await tester.pumpAndSettle();
    expect(viewer.currentPage, 2);

    // Material -> Cupertino, from the app menu
    await tester.tap(find.byKey(const ValueKey('dartpdf-app-menu')));
    await tester.pumpAndSettle();
    final toCupertino = find.byKey(const ValueKey('dartpdf-design-cupertino'));
    await tester.ensureVisible(toCupertino);
    await tester.pumpAndSettle();
    await tester.tap(toCupertino);
    await pumpUntilViewer(tester);
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoApp), findsOneWidget);
    expect(find.byType(MaterialApp), findsNothing);
    expect(find.byKey(const ValueKey('cupertino-nav-bar')), findsOneWidget);
    // the same session and viewer controller, edit and page intact
    expect(identical(editorView(tester).controller, session), isTrue);
    expect(identical(editorView(tester).viewerController, viewer), isTrue);
    expect(session.document.pageCount, 3);
    expect(session.canUndo, isTrue);
    expect(viewer.currentPage, 2);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(ExampleDesignPreference.storageKey), 'cupertino');
    expectNoErrors(tester);

    // Cupertino -> Material, from the Cupertino settings page
    await tester.tap(find.byKey(const ValueKey('cupertino-settings')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cupertino-design-cupertino')),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cupertino-design-material')));
    await pumpUntilViewer(tester);
    await tester.pumpAndSettle();
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(CupertinoApp), findsNothing);
    expect(find.byKey(const ValueKey('dartpdf-app-menu')), findsOneWidget);
    expect(identical(editorView(tester).controller, session), isTrue);
    expect(session.document.pageCount, 3);
    expect(session.canUndo, isTrue);
    expect(viewer.currentPage, 2);
    expect(prefs.getString(ExampleDesignPreference.storageKey), 'material');
    // the launch document was not opened again: still one tab
    expect(find.byTooltip('Close tab'), findsOneWidget);
    expectNoErrors(tester);
  });

  testWidgets('a saved Cupertino choice restores on restart', (tester) async {
    SharedPreferences.setMockInitialValues(
        {ExampleDesignPreference.storageKey: 'cupertino'});
    await pumpApp(tester);
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoApp), findsOneWidget);
    expect(find.byType(MaterialApp), findsNothing);
    expect(find.byKey(const ValueKey('cupertino-nav-bar')), findsOneWidget);
    expect(find.byType(PdfViewer), findsOneWidget);
    expectNoErrors(tester);
  });

  testWidgets('Material is the default', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpApp(tester);
    await tester.pumpAndSettle();
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(CupertinoApp), findsNothing);
  });

  testWidgets('the Cupertino appearance setting drives the brightness',
      (tester) async {
    SharedPreferences.setMockInitialValues(
        {ExampleDesignPreference.storageKey: 'cupertino'});
    await pumpApp(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cupertino-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cupertino-appearance-dark')));
    await tester.pumpAndSettle();
    final app = tester.widget<CupertinoApp>(find.byType(CupertinoApp));
    expect(app.theme?.brightness, Brightness.dark);
    // back to following the platform
    await tester.tap(find.byKey(const ValueKey('cupertino-appearance-system')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<CupertinoApp>(find.byType(CupertinoApp))
            .theme
            ?.brightness,
        isNull);
    expectNoErrors(tester);
  });
}

/// The editor localizations load asynchronously: pump until a viewer is up.
Future<void> pumpUntilViewer(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 20 && find.byType(PdfViewer).evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump();
}
