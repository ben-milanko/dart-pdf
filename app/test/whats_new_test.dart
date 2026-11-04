// The app ships its own CHANGELOG.md as an asset and reads it back in the
// "What's new" dialog, so these cover both halves: the markdown subset the
// changelog is written in, and the dialog reaching the real bundled asset
// (which also guards the pubspec asset declaration - drop it and the last
// group fails).
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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

const _nightlyBody = r'''
Rolling Windows + macOS test build from [`abc1234`](https://github.com/o/r/commit/abc1234def), built 2026-10-22 03:00 UTC.

- **Windows:** use the installer.

## Tickets since [DartPDF 10.0.0](https://github.com/o/r/releases/tag/app-v10.0.0)

- feat(editor): editable tables ([#1140](https://github.com/o/r/pull/1140))
- fix: keep \[brackets\] literal ([#1134](https://github.com/o/r/pull/1134))

[Full comparison](https://github.com/o/r/compare/a...b).

## Changes since the previous nightly

- feat(editor): editable tables (#1140) ([abc1234](https://github.com/o/r/commit/abc))

<!-- main-sha: ABC1234DEF5678 -->
<!-- app-version: 10.0.0 -->
''';

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

  group('parseNightlyTickets', () {
    test('reads the ticket section and the build commit', () {
      final tickets = parseNightlyTickets(_nightlyBody)!;
      expect(tickets.sinceVersion, '10.0.0');
      expect(tickets.commitSha, 'abc1234def5678');
      expect(tickets.tickets.map((t) => t.number), [1140, 1134]);
      expect(tickets.tickets.first.title, 'feat(editor): editable tables');
      expect(tickets.tickets.first.url, 'https://github.com/o/r/pull/1140');
      expect(tickets.tickets.last.title, 'fix: keep [brackets] literal');
    });

    test('an empty list is only reported when the workflow said so', () {
      const heading = '## Tickets since [DartPDF 10.0.0](https://x)\n\n';
      final none = parseNightlyTickets(
          '${heading}No new merged tickets since this release.\n')!;
      expect(none.tickets, isEmpty);
      expect(
          parseNightlyTickets('${heading}This nightly and the latest release '
              'have different histories.\n'),
          isNull);
    });

    test('a body without the section yields null', () {
      expect(parseNightlyTickets(''), isNull);
      expect(parseNightlyTickets('## Changes since the previous nightly\n'),
          isNull);
    });
  });

  test('fetchNightlyReleaseNotes reads the rolling release body', () async {
    late Uri requested;
    final client = MockClient((request) async {
      requested = request.url;
      return http.Response('{"body": "notes"}', 200);
    });
    expect(await fetchNightlyReleaseNotes(client: client), 'notes');
    expect(requested.path, endsWith('/releases/tags/app-nightly'));

    final failing = MockClient((_) async => http.Response('', 404));
    expect(fetchNightlyReleaseNotes(client: failing),
        throwsA(isA<http.ClientException>()));
  });

  test('fetchLatestReleaseChangelog reads CHANGELOG.md at the latest tag',
      () async {
    final requested = <Uri>[];
    final client = MockClient((request) async {
      requested.add(request.url);
      if (request.url.host == 'api.github.com') {
        return http.Response('{"tag_name": "app-v12.0.0"}', 200);
      }
      return http.Response('## 12.0.0\n\n- Latest.\n', 200);
    });
    expect(await fetchLatestReleaseChangelog(client: client),
        '## 12.0.0\n\n- Latest.\n');
    expect(requested.first.path, endsWith('/releases/latest'));
    expect(requested.last.toString(),
        'https://raw.githubusercontent.com/ben-milanko/dart-pdf/app-v12.0.0/app/CHANGELOG.md');

    final failing = MockClient((_) async => http.Response('', 404));
    expect(fetchLatestReleaseChangelog(client: failing),
        throwsA(isA<http.ClientException>()));
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

    Future<void> pumpDialog(
      WidgetTester tester,
      String changelog, {
      NightlyNotesFetcher? nightlyNotes,
      ReleaseChangelogFetcher? releaseChangelog,
    }) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showWhatsNew(context,
                  bundle: _FakeBundle(changelog),
                  nightlyNotes: nightlyNotes,
                  releaseChangelog: releaseChangelog),
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

    testWidgets('Close dismisses it', (tester) async {
      await pumpDialog(tester, '## 1.0.0\n\n- Something.\n');
      expect(find.byKey(const ValueKey('whats-new-dialog')), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('whats-new-dialog')), findsNothing);
    });

    testWidgets('says so rather than showing an empty sheet', (tester) async {
      await pumpDialog(tester, '# Changelog\n');

      expect(
          find.byKey(const ValueKey('whats-new-unavailable')), findsOneWidget);
    });

    testWidgets('a stable build has no nightly section', (tester) async {
      await pumpDialog(tester, '## 1.0.0\n\n- Something.\n');
      expect(find.byKey(const ValueKey('whats-new-nightly')), findsNothing);
      expect(find.byKey(const ValueKey('whats-new-nightly-unavailable')),
          findsNothing);
    });

    testWidgets('a nightly lists its tickets above the changelog',
        (tester) async {
      await pumpDialog(tester, '## 1.0.0\n\n- Something.\n',
          nightlyNotes: () async => _nightlyBody);

      expect(find.byKey(const ValueKey('whats-new-nightly')), findsOneWidget);
      expect(find.text('Tickets since 10.0.0'), findsOneWidget);
      expect(
          find.byKey(const ValueKey('whats-new-ticket-1140')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('whats-new-ticket-1134')), findsOneWidget);
      // The test binary has no build commit, so the list reads as coming
      // from a newer nightly than the one running.
      expect(find.text('From a newer nightly (abc1234) than this build.'),
          findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Tickets since 10.0.0')).dy,
        lessThan(tester.getTopLeft(find.text('1.0.0')).dy),
      );
    });

    testWidgets('a nightly shows the latest release, not its own changelog',
        (tester) async {
      await pumpDialog(tester, '## 1.0.0\n\n- Bundled.\n',
          nightlyNotes: () async => _nightlyBody,
          releaseChangelog: () async =>
              '# Changelog\n\n## ${AppInfo.version}\n\n- Released.\n');

      expect(find.text('Released.'), findsOneWidget);
      expect(find.text('Bundled.'), findsNothing);
      // A nightly is not the release it shares a package version with.
      expect(find.byKey(const ValueKey('whats-new-installed')), findsNothing);
    });

    testWidgets('an offline nightly falls back to the bundled changelog',
        (tester) async {
      await pumpDialog(tester, '## 1.0.0\n\n- Bundled.\n',
          nightlyNotes: () async => _nightlyBody,
          releaseChangelog: () async => throw http.ClientException('offline'));

      expect(find.text('Bundled.'), findsOneWidget);
    });

    testWidgets('a nightly with nothing new says so', (tester) async {
      await pumpDialog(tester, '## 1.0.0\n\n- Something.\n',
          nightlyNotes: () async =>
              '## Tickets since [DartPDF 10.0.0](https://x)\n\n'
              'No new merged tickets since this release.\n');

      expect(find.text('No new tickets since 10.0.0.'), findsOneWidget);
    });

    testWidgets('an offline nightly still shows the changelog', (tester) async {
      await pumpDialog(tester, '## 1.0.0\n\n- Something.\n',
          nightlyNotes: () async => throw http.ClientException('offline'));

      expect(find.byKey(const ValueKey('whats-new-nightly-unavailable')),
          findsOneWidget);
      expect(find.text('Something.'), findsOneWidget);
    });

    testWidgets('tapping a ticket opens its pull request', (tester) async {
      const launcher = MethodChannel('plugins.flutter.io/url_launcher');
      final launched = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(launcher, (call) async {
        if (call.method == 'launch') {
          launched.add((call.arguments as Map)['url'] as String);
        }
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(launcher, null));

      await pumpDialog(tester, '## 1.0.0\n\n- Something.\n',
          nightlyNotes: () async => _nightlyBody);
      await tester.tap(find.byKey(const ValueKey('whats-new-ticket-1140')));
      await tester.pumpAndSettle();

      expect(launched, ['https://github.com/o/r/pull/1140']);
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

    testWidgets('the About block offers GitHub and email feedback',
        (tester) async {
      await tester.pumpWidget(MaterialApp(home: EditorScreen(prefs: prefs)));
      await tester.pump();
      await tester.tap(find.byTooltip('DartPDF menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      expect(
          find.byKey(const ValueKey('settings-report-issue')), findsOneWidget);
      final email = find.byKey(const ValueKey('settings-email-feedback'));
      expect(email, findsOneWidget);
      // The address is shown, not just linked: it must be reachable without a
      // mail client.
      expect(
          find.descendant(
              of: email, matching: find.text(AppInfo.feedbackEmail)),
          findsOneWidget);
    });

    group('feedback links', () {
      const launcher = MethodChannel('plugins.flutter.io/url_launcher');
      late List<String> launched;
      late bool mailClient;
      String? clipboard;

      setUp(() {
        launched = [];
        mailClient = true;
        clipboard = null;
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(launcher, (call) async {
          if (call.method != 'launch') return null;
          final url = (call.arguments as Map)['url'] as String;
          if (url.startsWith('mailto:') && !mailClient) return false;
          launched.add(url);
          return true;
        });
        messenger.setMockMethodCallHandler(SystemChannels.platform,
            (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String?;
          }
          return null;
        });
      });

      tearDown(() {
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(launcher, null);
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      });

      Future<void> tapTile(WidgetTester tester, String key) async {
        await tester.pumpWidget(MaterialApp(home: EditorScreen(prefs: prefs)));
        await tester.pump();
        await tester.tap(find.byTooltip('DartPDF menu'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();
        final tile = find.byKey(ValueKey(key));
        await tester.ensureVisible(tile);
        await tester.pumpAndSettle();
        await tester.tap(tile);
        await tester.pumpAndSettle();
      }

      testWidgets('report an issue opens the GitHub feedback form',
          (tester) async {
        await tapTile(tester, 'settings-report-issue');
        expect(launched, [AppInfo.feedbackIssueUrl]);
      });

      testWidgets('email feedback opens the mail client', (tester) async {
        await tapTile(tester, 'settings-email-feedback');
        expect(launched, [AppInfo.feedbackMailto().toString()]);
        expect(clipboard, isNull);
      });

      testWidgets('with no mail client the address is copied instead',
          (tester) async {
        mailClient = false;
        await tapTile(tester, 'settings-email-feedback');
        expect(launched, isEmpty);
        expect(clipboard, AppInfo.feedbackEmail);
        expect(find.textContaining('Copied to clipboard'), findsOneWidget);
      });
    });
  });
}
