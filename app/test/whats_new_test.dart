// The app ships its own CHANGELOG.md as an asset and reads it back in the
// "What's new" dialog, so these cover both halves: the markdown subset the
// changelog is written in, and the dialog reaching the real bundled asset
// (which also guards the pubspec asset declaration - drop it and the last
// group fails).
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/app_info.dart';
import 'package:dart_pdf_editor_app/editor_screen.dart';
import 'package:dart_pdf_editor_app/whats_new.dart';

/// An [AssetBundle] that serves one string for the changelog key.
class _FakeBundle extends CachingAssetBundle {
  _FakeBundle(this.contents);

  final String contents;

  @override
  Future<ByteData> load(String key) async {
    if (key != appChangelogAsset) throw FlutterError('unexpected asset $key');
    return ByteData.sublistView(Uint8List.fromList(contents.codeUnits));
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    if (key != appChangelogAsset) throw FlutterError('unexpected asset $key');
    return contents;
  }
}

void main() {
  group('parseChangelog', () {
    test('reads sections newest first and skips the document title', () {
      final releases = parseChangelog('''
# Changelog

## 4.5.0

- Ship the changelog with the app.

## 4.4.0

- Print directly on Windows.
- Zoom to 10000%.
''');

      expect(releases.map((r) => r.version), ['4.5.0', '4.4.0']);
      expect(releases.first.notes, ['Ship the changelog with the app.']);
      expect(releases.last.notes,
          ['Print directly on Windows.', 'Zoom to 10000%.']);
    });

    test('rejoins a bullet that wraps across lines', () {
      final releases = parseChangelog('''
## 1.0.0

- Open and scroll dense vector drawings faster, and prepare text for
  selection and search from the render worker's own pass over the page
  rather than a second one.
- A second entry.
''');

      expect(releases.single.notes, [
        "Open and scroll dense vector drawings faster, and prepare text for "
            "selection and search from the render worker's own pass over the "
            "page rather than a second one.",
        'A second entry.',
      ]);
    });

    test('a blank line between bullets does not join them', () {
      final releases = parseChangelog('''
## 1.0.0

- First.

- Second.
''');

      expect(releases.single.notes, ['First.', 'Second.']);
    });

    test('keeps an Unreleased heading as written', () {
      final releases = parseChangelog('## Unreleased\n\n- In flight.\n');
      expect(releases.single.version, 'Unreleased');
    });

    test('empty or note-less input yields no crash', () {
      expect(parseChangelog(''), isEmpty);
      expect(parseChangelog('# Changelog\n\nNothing yet.\n'), isEmpty);
      expect(parseChangelog('## 1.0.0\n').single.notes, isEmpty);
    });
  });

  group('changelogSpans', () {
    const bold = TextStyle(fontWeight: FontWeight.w600);
    const code = TextStyle(fontFamily: 'monospace');

    List<(String, TextStyle?)> runs(String text) => [
          for (final span
              in changelogSpans(text, bold: bold, code: code).cast<TextSpan>())
            (span.text!, span.style),
        ];

    test('splits bold and code out of the surrounding text', () {
      expect(
        runs('Use **Optimise** in the `dart_pdf_printing` plugin.'),
        [
          ('Use ', null),
          ('Optimise', bold),
          (' in the ', null),
          ('dart_pdf_printing', code),
          (' plugin.', null),
        ],
      );
    });

    test('an unterminated marker stays literal', () {
      expect(runs('100% **of the time'), [('100% **of the time', null)]);
      expect(runs('a ` backtick'), [('a ` backtick', null)]);
    });
  });

  group('the dialog', () {
    late PdfEditingPreferences prefs;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      prefs = PdfEditingPreferences();
      debugResetChangelogCache();
      // rootBundle memoizes the load per key, and a future completed inside a
      // finished test's fake-async zone never resolves for the next one's
      // listeners. Evicting the key gives each test its own cold read.
      rootBundle.evict(appChangelogAsset);
    });
    tearDown(() => prefs.dispose());

    Future<void> pumpDialog(WidgetTester tester, String changelog) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  showWhatsNew(context, bundle: _FakeBundle(changelog)),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('lists every release and badges the running one',
        (tester) async {
      final installed = AppInfo.version;
      await pumpDialog(tester, '''
# Changelog

## $installed

- Something new.

## 0.0.1

- The first cut.
''');

      expect(find.byKey(const ValueKey('whats-new-dialog')), findsOneWidget);
      expect(find.text(installed), findsOneWidget);
      expect(find.text('0.0.1'), findsOneWidget);
      expect(find.text('Something new.'), findsOneWidget);
      // Only the running build's section carries the badge.
      expect(find.byKey(const ValueKey('whats-new-installed')), findsOneWidget);
      expect(find.text('Installed'), findsOneWidget);
    });

    testWidgets('says so rather than showing an empty sheet', (tester) async {
      await pumpDialog(tester, '# Changelog\n');

      expect(
          find.byKey(const ValueKey('whats-new-unavailable')), findsOneWidget);
    });

    testWidgets('the command palette runs it', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        await tester.pumpWidget(MaterialApp(home: EditorScreen(prefs: prefs)));
        await tester.pump();

        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        await tester.enterText(
            find.byKey(const ValueKey('command-palette-field')), "what's new");
        await tester.pumpAndSettle();

        final result = find.byKey(const ValueKey('palette-result-whats-new'));
        expect(result, findsOneWidget);
        await tester.tap(result);
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('whats-new-dialog')), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('settings opens it from the About block', (tester) async {
      await tester.pumpWidget(MaterialApp(home: EditorScreen(prefs: prefs)));
      await tester.pump();
      await tester.tap(find.byTooltip('DartPDF menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      final tile = find.byKey(const ValueKey('settings-whats-new'));
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await tester.pumpAndSettle();

      // No fake bundle here: this reads the CHANGELOG.md the app really
      // ships, so a missing asset declaration surfaces as a failure. The
      // versions themselves move every release, so the assertion is that the
      // file arrived and parsed into at least one section - not which one.
      expect(find.byKey(const ValueKey('whats-new-dialog')), findsOneWidget);
      expect(find.byKey(const ValueKey('whats-new-unavailable')), findsNothing);
    });
  });
}
