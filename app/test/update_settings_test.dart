import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/editor_screen.dart';
import 'package:dart_pdf_editor_app/update.dart';

ReleaseInfo _release(String tag) => ReleaseInfo(
      version: AppVersion.tryParse(tag)!,
      tagName: tag,
      name: tag,
      notes: '',
      htmlUrl: 'https://example.test/$tag',
      assets: const {},
    );

UpdateService _fakeService({
  required String current,
  required List<ReleaseInfo> releases,
  // Update checks are a desktop-only feature (mobile updates through the app
  // stores), and widget tests default to the Android target platform, so pin a
  // desktop platform to exercise the update UI.
  TargetPlatform platform = TargetPlatform.macOS,
}) =>
    UpdateService(
      currentVersion: current,
      platform: platform,
      fetcher: () async => releases,
    );

void main() {
  late PdfEditingPreferences prefs;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    prefs = PdfEditingPreferences();
  });

  tearDown(() => prefs.dispose());

  testWidgets('Settings can check for updates and offer a download',
      (tester) async {
    final updates =
        _fakeService(current: '1.2.0', releases: [_release('app-v1.3.0')]);
    addTearDown(updates.dispose);

    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(prefs: prefs, updateService: updates),
    ));
    await tester.pump();

    await tester.tap(find.byTooltip('DartPDF menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('settings-check-updates')), findsOneWidget);

    await tester.ensureVisible(
        find.byKey(const ValueKey('settings-check-updates')));
    await tester.tap(find.byKey(const ValueKey('settings-check-updates')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('settings-update-available')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings-download-update')),
      findsOneWidget,
    );
    expect(find.textContaining('1.3.0'), findsWidgets);
  });

  testWidgets('Settings says up to date when nothing is newer',
      (tester) async {
    final updates =
        _fakeService(current: '1.3.0', releases: [_release('app-v1.3.0')]);
    addTearDown(updates.dispose);

    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(prefs: prefs, updateService: updates),
    ));
    await tester.pump();

    await tester.tap(find.byTooltip('DartPDF menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(
        find.byKey(const ValueKey('settings-check-updates')));
    await tester.tap(find.byKey(const ValueKey('settings-check-updates')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('settings-up-to-date')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-download-update')),
      findsNothing,
    );
  });

  testWidgets('startup auto-check shows the update banner', (tester) async {
    final updates =
        _fakeService(current: '1.2.0', releases: [_release('app-v1.3.0')]);
    addTearDown(updates.dispose);

    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(
        prefs: prefs,
        updateService: updates,
        autoCheckUpdates: true,
      ),
    ));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('update-available-banner')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('update-banner-download')),
      findsOneWidget,
    );
    expect(find.textContaining('1.3.0'), findsOneWidget);

    // "Later" dismisses the banner and silences it for this release.
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('update-available-banner')),
      findsNothing,
    );
    expect(updates.shouldNotify, isFalse);
  });

  testWidgets('no banner when already on the latest version', (tester) async {
    final updates =
        _fakeService(current: '1.3.0', releases: [_release('app-v1.3.0')]);
    addTearDown(updates.dispose);

    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(
        prefs: prefs,
        updateService: updates,
        autoCheckUpdates: true,
      ),
    ));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('update-available-banner')),
      findsNothing,
    );
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('no startup banner on ${platform.name} (updates via the store)',
        (tester) async {
      final updates = _fakeService(
        current: '1.2.0',
        releases: [_release('app-v1.3.0')],
        platform: platform,
      );
      addTearDown(updates.dispose);

      await tester.pumpWidget(MaterialApp(
        home: EditorScreen(
          prefs: prefs,
          updateService: updates,
          autoCheckUpdates: true,
        ),
      ));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('update-available-banner')),
        findsNothing,
      );
    });

    testWidgets('Settings hides the Updates section on ${platform.name}',
        (tester) async {
      final updates = _fakeService(
        current: '1.2.0',
        releases: [_release('app-v1.3.0')],
        platform: platform,
      );
      addTearDown(updates.dispose);

      await tester.pumpWidget(MaterialApp(
        home: EditorScreen(prefs: prefs, updateService: updates),
      ));
      await tester.pump();

      await tester.tap(find.byTooltip('DartPDF menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('settings-check-updates')),
        findsNothing,
      );
    });
  }
}
