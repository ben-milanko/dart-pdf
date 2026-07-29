import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/editor_screen.dart';
import 'package:dart_pdf_editor_app/update.dart';
import 'package:dart_pdf_editor_app/update_installer.dart';
import 'package:dart_pdf_editor_app/update_platform.dart';

/// Records apply calls without touching disk. macOS hand-off avoids the
/// AppImage self-replace path (which would call exit(0)).
class _FakeOps implements UpdatePlatformOps {
  _FakeOps({required this.platform});

  @override
  final TargetPlatform platform;
  @override
  final String? appImagePath = null;

  String? opened;

  @override
  Future<String> downloadDirectory() async => '/downloads';
  @override
  String joinPath(String dir, String name) => '$dir/$name';
  @override
  String parentDirectory(String path) =>
      path.substring(0, path.lastIndexOf('/'));
  @override
  Future<void> writeArtifact(String path, List<int> bytes,
      {bool executable = false}) async {}
  @override
  Future<void> replaceInPlace(
      {required String from, required String to}) async {}
  @override
  Future<Never> relaunchAndExit(String path) async =>
      throw StateError('relaunch not expected in hand-off test');
  @override
  Future<void> openArtifact(String path) async => opened = path;
}

ReleaseInfo _dmgRelease() => ReleaseInfo(
      version: const AppVersion(1, 3, 0),
      tagName: 'app-v1.3.0',
      name: 'app-v1.3.0',
      notes: '',
      htmlUrl: 'https://example.test/app-v1.3.0',
      assets: const {'dartpdf-macos.dmg': 'https://example.test/dmg'},
      assetSizes: const {'dartpdf-macos.dmg': 64},
    );

ReleaseInfo _nightlyWindowsRelease() => const ReleaseInfo(
      version: AppVersion(1, 3, 0),
      tagName: dartPdfNightlyTag,
      name: 'DartPDF nightly',
      notes: '',
      htmlUrl: 'https://example.test/nightly',
      assets: {
        'dartpdf-nightly-windows-installer.exe':
            'https://example.test/nightly.exe',
      },
      assetSizes: {'dartpdf-nightly-windows-installer.exe': 64},
      isNightly: true,
      commitSha: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );

void main() {
  late PdfEditingPreferences prefs;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    prefs = PdfEditingPreferences();
  });
  tearDown(() => prefs.dispose());

  testWidgets('the banner "Update now" downloads and hands off the artifact',
      (tester) async {
    final updates = UpdateService(
      currentVersion: '1.2.0',
      platform: TargetPlatform.macOS,
      fetcher: () async => [_dmgRelease()],
    );
    addTearDown(updates.dispose);

    final ops = _FakeOps(platform: TargetPlatform.macOS);
    final bytes = Uint8List.fromList(List.generate(64, (i) => i));
    final installer = UpdateInstaller(
      ops: ops,
      clientFactory: () => MockClient.streaming((request, body) async =>
          http.StreamedResponse(Stream.value(bytes), 200, contentLength: 64)),
    );

    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(
        prefs: prefs,
        updateService: updates,
        updateInstaller: installer,
        autoCheckUpdates: true,
      ),
    ));
    await tester.pumpAndSettle();

    // The button reads "Update now" because an in-app apply path exists.
    expect(find.text('Update now'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('update-banner-download')));
    await tester.pumpAndSettle();

    // Downloaded and handed to the OS installer, with a confirming snackbar.
    expect(ops.opened, '/downloads/dartpdf-macos.dmg');
    expect(find.byKey(const ValueKey('update-handed-off')), findsOneWidget);
  });

  testWidgets('a download failure surfaces a snackbar with a fallback action',
      (tester) async {
    final updates = UpdateService(
      currentVersion: '1.2.0',
      platform: TargetPlatform.macOS,
      fetcher: () async => [_dmgRelease()],
    );
    addTearDown(updates.dispose);

    // A 404 makes downloadAndApply throw UpdateInstallException, driving the
    // flow's failure branch (dismiss dialog, show the failed snackbar).
    final installer = UpdateInstaller(
      ops: _FakeOps(platform: TargetPlatform.macOS),
      clientFactory: () => MockClient((_) async => http.Response('no', 404)),
    );

    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(
        prefs: prefs,
        updateService: updates,
        updateInstaller: installer,
        autoCheckUpdates: true,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('update-banner-download')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('update-progress-dialog')), findsNothing);
    expect(find.byKey(const ValueKey('update-install-failed')), findsOneWidget);
  });

  testWidgets(
      'a nightly notification downloads and opens its Windows installer',
      (tester) async {
    final updates = UpdateService(
      currentVersion: '1.3.0',
      currentBuildCommit: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      platform: TargetPlatform.windows,
      fetcher: () async => [_nightlyWindowsRelease()],
    );
    addTearDown(updates.dispose);
    await updates.setNightlyUpdates(true);

    final ops = _FakeOps(platform: TargetPlatform.windows);
    final bytes = Uint8List.fromList(List.generate(64, (i) => i));
    final installer = UpdateInstaller(
      ops: ops,
      clientFactory: () => MockClient.streaming((request, body) async =>
          http.StreamedResponse(Stream.value(bytes), 200, contentLength: 64)),
    );

    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(
        prefs: prefs,
        updateService: updates,
        updateInstaller: installer,
        autoCheckUpdates: true,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Update now'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('update-banner-download')));
    await tester.pumpAndSettle();

    expect(
      ops.opened,
      '/downloads/dartpdf-nightly-windows-installer.exe',
    );
    expect(find.byKey(const ValueKey('update-handed-off')), findsOneWidget);
  });
}
