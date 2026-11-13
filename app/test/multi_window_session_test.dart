// Resuming a multi-window session: the primary window reopens the first
// window of the last session itself and every other one as its own window,
// a restored window reopens its documents, and closing one window of several
// forgets it. flutter_test cannot create real native windows, so the opener
// is a fake and each window is pumped on its own.

import 'dart:io';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/editor_screen.dart';
import 'package:dart_pdf_editor_app/session_store.dart';
import 'package:dart_pdf_editor_app/window_sessions.dart';
import 'package:dart_pdf_editor_app/window_support.dart';

import 'test_finders.dart';

void main() {
  late PdfEditingPreferences prefs;
  late Directory tempDir;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    prefs = PdfEditingPreferences();
    tempDir = Directory.systemTemp.createTempSync('dartpdf_window_session');
  });

  tearDown(() {
    prefs.dispose();
    tempDir.deleteSync(recursive: true);
  });

  SessionDocument seedFile(String name) {
    final path = '${tempDir.path}/$name';
    File(path).writeAsBytesSync(buildClassicPdf());
    return SessionDocument(title: name, path: path);
  }

  Finder tabTitle(String name) => find.descendant(
        of: find.byKey(const ValueKey('tab-strip')),
        matching: findMiddleEllipsisText(name),
      );

  // Restore reads real files, which only progresses under runAsync.
  Future<void> pumpWindow(WidgetTester tester, Widget window) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(window);
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();
  }

  List<List<String>> titles(List<List<SessionDocument>> windows) => [
        for (final w in windows) [for (final d in w) d.title]
      ];

  testWidgets('the primary reopens the first window and opens the others',
      (tester) async {
    final a = seedFile('a.pdf');
    final b = seedFile('b.pdf');
    final c = seedFile('c.pdf');
    await SessionStore().saveWindows([
      [a],
      [b, c],
    ]);
    final sessions = WindowSessions(SessionStore());
    final restored = <WindowSessionSlot>[];

    await pumpWindow(
      tester,
      MaterialApp(
        home: EditorScreen(
          prefs: prefs,
          windowSessions: sessions,
          onRestoreWindow: (_, slot) {
            restored.add(slot);
            return true;
          },
        ),
      ),
    );

    expect(tabTitle('a.pdf'), findsOneWidget);
    expect(tabTitle('b.pdf'), findsNothing);
    expect(restored.single.documents.map((d) => d.title), ['b.pdf', 'c.pdf']);
    // The other window is still part of the session while it reopens.
    expect(titles(await SessionStore().loadWindows()), [
      ['a.pdf'],
      ['b.pdf', 'c.pdf'],
    ]);
  });

  testWidgets('a window that cannot be created restores into the primary',
      (tester) async {
    final a = seedFile('a.pdf');
    final b = seedFile('b.pdf');
    await SessionStore().saveWindows([
      [a],
      [b],
    ]);

    await pumpWindow(
      tester,
      MaterialApp(
        home: EditorScreen(
          prefs: prefs,
          windowSessions: WindowSessions(SessionStore()),
          onRestoreWindow: (_, __) => false,
        ),
      ),
    );

    expect(tabTitle('a.pdf'), findsOneWidget);
    expect(tabTitle('b.pdf'), findsOneWidget);
    expect(titles(await SessionStore().loadWindows()), [
      ['a.pdf', 'b.pdf'],
    ]);
  });

  testWidgets(
      'a restored window reopens its documents, and closing it '
      'while another is open forgets it', (tester) async {
    final a = seedFile('a.pdf');
    final b = seedFile('b.pdf');
    final sessions = WindowSessions(SessionStore());
    final primary = sessions.open(documents: [a]);
    final slot = sessions.open(documents: [b]);
    sessions.markLoaded();
    final coordinator = DartPdfWindowCloseCoordinator();

    await pumpWindow(
      tester,
      DartPdfWindowCloseScope(
        coordinator: coordinator,
        child: MaterialApp(
          home: EditorScreen(
            prefs: prefs,
            windowSessions: sessions,
            sessionSlot: slot,
            ownsApplicationSession: false,
          ),
        ),
      ),
    );

    expect(tabTitle('b.pdf'), findsOneWidget);
    expect(primary.documents.single.title, 'a.pdf');
    expect(titles(await SessionStore().loadWindows()), [
      ['a.pdf'],
      ['b.pdf'],
    ]);

    expect(await coordinator.requestClose(), isTrue);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(titles(await SessionStore().loadWindows()), [
      ['a.pdf'],
    ]);
  });

  testWidgets('closing the last window keeps it in the session',
      (tester) async {
    final a = seedFile('a.pdf');
    final sessions = WindowSessions(SessionStore());
    final slot = sessions.open(documents: [a]);
    sessions.markLoaded();
    final coordinator = DartPdfWindowCloseCoordinator();

    await pumpWindow(
      tester,
      DartPdfWindowCloseScope(
        coordinator: coordinator,
        child: MaterialApp(
          home: EditorScreen(
            prefs: prefs,
            windowSessions: sessions,
            sessionSlot: slot,
            ownsApplicationSession: false,
          ),
        ),
      ),
    );

    expect(await coordinator.requestClose(), isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(titles(await SessionStore().loadWindows()), [
      ['a.pdf'],
    ]);
  });
}
