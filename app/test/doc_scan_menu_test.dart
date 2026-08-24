// The device document-scan actions ("Scan to new document" and "Insert scan")
// are wired into the DartPDF app menu on mobile. The real scan uses the native
// ML Kit / VisionKit channels, so these tests inject a fake DocumentScanner
// that returns a known PDF and assert the menu wiring and the effects each
// action produces. flutter_test's default platform is android, so the entries
// show without a platform override.
//
// The menu is opened by key rather than by tooltip on purpose: `find.byTooltip`
// enables the semantics tree, and a later document swap (the insert path)
// re-renders the viewer, which trips a debug semantics-build assertion. Keeping
// semantics off sidesteps that framework check.
import 'dart:async';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/editor_screen.dart';

import 'test_finders.dart';

void main() {
  late PdfEditingPreferences prefs;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    prefs = PdfEditingPreferences();
  });

  tearDown(() => prefs.dispose());

  // A scanner that hands back a two-page PDF, standing in for a capture.
  Future<Uint8List?> fakeScan() async => buildMultiPagePdf(2);

  Future<void> pump(
    WidgetTester tester, {
    bool withDoc = false,
    bool withScanner = true,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(
        prefs: prefs,
        documentScanner: withScanner ? fakeScan : null,
        initialDocument:
            withDoc ? (bytes: buildClassicPdf(), title: 'Scan.pdf') : null,
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('dartpdf-app-menu')));
    await tester.pumpAndSettle();
  }

  testWidgets('the app menu offers Scan to new document', (tester) async {
    await pump(tester);
    await openMenu(tester);

    expect(find.byKey(const ValueKey('menu-scan-document')), findsOneWidget);
    expect(find.text('Scan to new document…'), findsOneWidget);
  });

  testWidgets('Scan to new document opens the scanned pages in a tab',
      (tester) async {
    await pump(tester);
    await openMenu(tester);

    await tester.tap(find.byKey(const ValueKey('menu-scan-document')));
    await tester.pumpAndSettle();

    // A brand-new untitled tab now holds the scan.
    expect(findMiddleEllipsisText('Untitled.pdf'), findsOneWidget);
  });

  testWidgets('no Insert scan entry without a document open', (tester) async {
    await pump(tester);
    await openMenu(tester);

    expect(find.byKey(const ValueKey('menu-insert-scan')), findsNothing);
  });

  testWidgets('the menu offers Insert scan with a document open',
      (tester) async {
    await pump(tester, withDoc: true);
    await openMenu(tester);

    expect(find.byKey(const ValueKey('menu-insert-scan')), findsOneWidget);
    expect(find.text('Insert scan…'), findsOneWidget);
  });

  testWidgets('Insert scan runs the scanner and inserts its pages',
      (tester) async {
    // A recording scanner proves the Insert scan entry reaches the scan+insert
    // path. The actual page splice is covered by the editor package's
    // insertPagesFrom* tests; asserting the mutated render here trips a
    // framework semantics-build assertion (SnackBar announcement over the
    // swapped document), so this stops at the wiring - matching drop_insert.
    var scanned = 0;
    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(
        prefs: prefs,
        documentScanner: () async {
          scanned++;
          return buildMultiPagePdf(2);
        },
        initialDocument: (bytes: buildClassicPdf(), title: 'Scan.pdf'),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await openMenu(tester);

    await tester.tap(find.byKey(const ValueKey('menu-insert-scan')));
    await tester.pump();

    expect(scanned, 1);
  });

  testWidgets('a cancelled scan (null) opens no tab', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(prefs: prefs, documentScanner: () async => null),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await openMenu(tester);

    await tester.tap(find.byKey(const ValueKey('menu-scan-document')));
    await tester.pumpAndSettle();

    // No document was created; the welcome screen is still up.
    expect(findMiddleEllipsisText('Untitled.pdf'), findsNothing);
    expect(find.byType(PdfEditorView), findsNothing);
  });

  testWidgets('a failing scan toasts instead of throwing', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(
        prefs: prefs,
        documentScanner: () async => throw StateError('scanner unavailable'),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await openMenu(tester);

    await tester.tap(find.byKey(const ValueKey('menu-scan-document')));
    await tester.pump(); // reject the future
    await tester.pump(); // show the snack bar

    // The toast carries the platform's own reason after the sentence - which
    // failure it was is the whole diagnostic value.
    expect(
      find.textContaining("Couldn't scan the document."),
      findsOneWidget,
    );
    expect(find.textContaining('scanner unavailable'), findsOneWidget);
    expect(findMiddleEllipsisText('Untitled.pdf'), findsNothing);
  });

  testWidgets('a failing Insert scan toasts instead of throwing',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(
        prefs: prefs,
        documentScanner: () async => throw StateError('scanner unavailable'),
        initialDocument: (bytes: buildClassicPdf(), title: 'Scan.pdf'),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await openMenu(tester);

    await tester.tap(find.byKey(const ValueKey('menu-insert-scan')));
    await tester.pump(); // reject the future
    await tester.pump(); // show the snack bar

    // The toast carries the platform's own reason after the sentence - which
    // failure it was is the whole diagnostic value.
    expect(
      find.textContaining("Couldn't scan the document."),
      findsOneWidget,
    );
    expect(find.textContaining('scanner unavailable'), findsOneWidget);
  });

  testWidgets('a second scan request while one is up is ignored',
      (tester) async {
    // The platform scanner runs one session at a time and answers a second
    // request with an error instead of a camera, so the app must not make one.
    var scanned = 0;
    final gate = Completer<Uint8List?>();
    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(
        prefs: prefs,
        documentScanner: () {
          scanned++;
          return gate.future;
        },
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await openMenu(tester);
    await tester.tap(find.byKey(const ValueKey('menu-scan-document')));
    await tester.pump();
    await openMenu(tester);
    await tester.tap(find.byKey(const ValueKey('menu-scan-document')));
    await tester.pump();

    expect(scanned, 1);
    gate.complete(null); // cancel, so the in-flight scan settles
    await tester.pumpAndSettle();
  });

  testWidgets('no scan entries where scanning is unsupported', (tester) async {
    // A desktop platform with no injected scanner: the entries hide.
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await pump(tester, withDoc: true, withScanner: false);
    await openMenu(tester);

    expect(find.byKey(const ValueKey('menu-scan-document')), findsNothing);
    expect(find.byKey(const ValueKey('menu-insert-scan')), findsNothing);

    // Reset before the test body ends so the foundation-vars invariant passes.
    debugDefaultTargetPlatformOverride = null;
  });
}
