import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/update.dart';

ReleaseInfo _release(
  String tag, {
  String notes = '',
  String html = '',
  Map<String, String> assets = const {},
}) =>
    ReleaseInfo(
      version: AppVersion.tryParse(tag)!,
      tagName: tag,
      name: tag,
      notes: notes,
      htmlUrl: html.isEmpty ? 'https://example.test/$tag' : html,
      assets: assets,
    );

/// A release with an explicit version, for tags the parser would otherwise
/// reject - used to prove the `app-v` tag filter, not the version parser.
ReleaseInfo _tagged(String tag, AppVersion version) => ReleaseInfo(
      version: version,
      tagName: tag,
      name: tag,
      notes: '',
      htmlUrl: 'https://example.test/$tag',
      assets: const {},
    );

UpdateService _service(
  String current, {
  required List<ReleaseInfo> releases,
  bool throwOnFetch = false,
  Duration checkInterval = const Duration(hours: 24),
  DateTime Function()? now,
  TargetPlatform? platform,
}) =>
    UpdateService(
      currentVersion: current,
      checkInterval: checkInterval,
      now: now ?? DateTime.now,
      platform: platform,
      fetcher: () async {
        if (throwOnFetch) throw Exception('offline');
        return releases;
      },
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('AppVersion', () {
    test('parses tags with the app-v / v prefix and build metadata', () {
      expect(AppVersion.tryParse('app-v1.2.3'), const AppVersion(1, 2, 3));
      expect(AppVersion.tryParse('v2.0.1'), const AppVersion(2, 0, 1));
      expect(AppVersion.tryParse('1.2.2+5'), const AppVersion(1, 2, 2));
      expect(AppVersion.tryParse('1.4'), const AppVersion(1, 4, 0));
    });

    test('rejects garbage', () {
      expect(AppVersion.tryParse('nightly'), isNull);
      expect(AppVersion.tryParse('pdf_cos-v1.2.1'), isNull);
      expect(AppVersion.tryParse(''), isNull);
    });

    test('orders by major, then minor, then patch', () {
      expect(AppVersion.tryParse('1.2.3')! > AppVersion.tryParse('1.2.2')!,
          isTrue);
      expect(AppVersion.tryParse('1.3.0')! > AppVersion.tryParse('1.2.9')!,
          isTrue);
      expect(AppVersion.tryParse('2.0.0')! > AppVersion.tryParse('1.9.9')!,
          isTrue);
      expect(AppVersion.tryParse('1.2.2')! > AppVersion.tryParse('1.2.2')!,
          isFalse);
    });

    test('a final release outranks the same numbers as a pre-release', () {
      expect(
        AppVersion.tryParse('1.2.0')! > AppVersion.tryParse('1.2.0-rc.1')!,
        isTrue,
      );
    });

    test('exposes comparison operators, equality, and toString', () {
      final a = AppVersion.tryParse('1.2.3')!;
      final b = AppVersion.tryParse('1.2.4')!;
      expect(a < b, isTrue);
      expect(b >= a, isTrue);
      expect(a <= a, isTrue);
      expect(a == AppVersion.tryParse('1.2.3'), isTrue);
      expect(a.hashCode, AppVersion.tryParse('1.2.3')!.hashCode);
      expect(a.toString(), '1.2.3');
      expect(AppVersion.tryParse('1.2.0-rc.1')!.toString(), '1.2.0-rc.1');
    });
  });

  group('ReleaseInfo.fromJson', () {
    test('reads the version, notes, and asset download URLs', () {
      final release = ReleaseInfo.fromJson({
        'tag_name': 'app-v1.3.0',
        'name': 'DartPDF 1.3.0',
        'body': 'Shiny new things',
        'html_url': 'https://example.test/app-v1.3.0',
        'assets': [
          {
            'name': 'dartpdf-macos.dmg',
            'browser_download_url': 'https://example.test/dmg',
          },
        ],
      });
      expect(release, isNotNull);
      expect(release!.version, const AppVersion(1, 3, 0));
      expect(release.name, 'DartPDF 1.3.0');
      expect(release.notes, 'Shiny new things');
      expect(release.assets['dartpdf-macos.dmg'], 'https://example.test/dmg');
    });

    test('returns null for a non-version tag', () {
      expect(ReleaseInfo.fromJson({'tag_name': 'pdf_cos-v1.0.0'}), isNull);
      expect(ReleaseInfo.fromJson(const {}), isNull);
    });
  });

  group('UpdateService.checkForUpdates', () {
    test('flags an update when a newer app release exists', () async {
      final service = _service('1.2.2', releases: [
        _release('app-v1.2.2'),
        _release('app-v1.3.0'),
        _tagged('v9.9.9', const AppVersion(9, 9, 9)), // not an app-v tag
      ]);
      await service.checkForUpdates();

      expect(service.status, UpdateStatus.updateAvailable);
      expect(service.updateAvailable, isTrue);
      expect(service.latest!.version, const AppVersion(1, 3, 0));
      expect(service.shouldNotify, isTrue);
    });

    test('reports up to date when nothing is newer', () async {
      final service = _service('1.3.0', releases: [
        _release('app-v1.2.2'),
        _release('app-v1.3.0'),
      ]);
      await service.checkForUpdates();

      expect(service.status, UpdateStatus.upToDate);
      expect(service.updateAvailable, isFalse);
      expect(service.shouldNotify, isFalse);
    });

    test('a non-app release tag is never mistaken for an app update', () async {
      final service = _service('1.2.2', releases: [
        _tagged('v2.0.0', const AppVersion(2, 0, 0)),
      ]);
      await service.checkForUpdates();

      expect(service.status, UpdateStatus.upToDate);
      expect(service.latest, isNull);
    });

    test('surfaces fetch failures without throwing', () async {
      final service = _service('1.2.2', releases: const [], throwOnFetch: true);
      await service.checkForUpdates();

      expect(service.status, UpdateStatus.failed);
      expect(service.error, isNotNull);
      expect(service.updateAvailable, isFalse);
    });

    test('throttles repeat checks but honours force', () async {
      var calls = 0;
      final service = UpdateService(
        currentVersion: '1.2.2',
        checkInterval: const Duration(hours: 24),
        fetcher: () async {
          calls++;
          return [_release('app-v1.3.0')];
        },
      );

      await service.checkForUpdates();
      await service.checkForUpdates(); // within the interval: skipped
      expect(calls, 1);

      await service.checkForUpdates(force: true);
      expect(calls, 2);
    });

    test('dismiss silences the banner for that release only', () async {
      final service = _service('1.2.2', releases: [_release('app-v1.3.0')]);
      await service.checkForUpdates();
      expect(service.shouldNotify, isTrue);

      await service.dismiss();
      expect(service.shouldNotify, isFalse);
      expect(service.updateAvailable, isTrue); // still available, just quiet
    });
  });

  group('UpdateService.downloadUrl', () {
    final assets = {
      'dartpdf-macos.dmg': 'https://example.test/dmg',
      'dartpdf-windows-installer.exe': 'https://example.test/win-installer',
      'dartpdf-windows-x64.zip': 'https://example.test/win',
      'dartpdf-linux-x86_64.AppImage': 'https://example.test/appimage',
      'app-release.apk': 'https://example.test/apk',
    };

    for (final scenario in [
      (platform: TargetPlatform.macOS, url: 'https://example.test/dmg'),
      (
        platform: TargetPlatform.windows,
        url: 'https://example.test/win-installer'
      ),
      (platform: TargetPlatform.linux, url: 'https://example.test/appimage'),
      (platform: TargetPlatform.android, url: 'https://example.test/apk'),
    ]) {
      test('points at the ${scenario.platform.name} artifact', () async {
        final service = _service(
          '1.2.2',
          releases: [_release('app-v1.3.0', assets: assets)],
          platform: scenario.platform,
        );
        await service.checkForUpdates();
        expect(service.downloadUrl, scenario.url);
      });
    }

    test('falls back to the portable Windows bundle when no installer exists',
        () async {
      final service = _service(
        '1.2.2',
        releases: [
          _release(
            'app-v1.3.0',
            assets: const {
              'dartpdf-windows-portable.exe':
                  'https://example.test/win-portable',
              'dartpdf-windows-x64.zip': 'https://example.test/win-zip',
            },
          ),
        ],
        platform: TargetPlatform.windows,
      );
      await service.checkForUpdates();
      expect(service.downloadUrl, 'https://example.test/win-portable');
    });

    test('falls back to the release page when no asset matches', () async {
      final service = _service(
        '1.2.2',
        releases: [
          _release('app-v1.3.0', html: 'https://example.test/page'),
        ],
        platform: TargetPlatform.iOS,
      );
      await service.checkForUpdates();
      expect(service.downloadUrl, 'https://example.test/page');
    });
  });

  group('UpdateService default GitHub fetcher', () {
    test('parses the releases response and resolves a platform download',
        () async {
      late http.Request captured;
      final service = UpdateService(
        currentVersion: '1.2.2',
        platform: TargetPlatform.macOS,
        clientFactory: () => MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode([
              {
                'tag_name': 'app-v1.3.0',
                'name': 'DartPDF 1.3.0',
                'body': 'notes',
                'html_url': 'https://example.test/app-v1.3.0',
                'assets': [
                  {
                    'name': 'dartpdf-macos.dmg',
                    'browser_download_url': 'https://example.test/dmg',
                  },
                ],
              },
              {'tag_name': 'pdf_cos-v9.9.9'}, // dropped by fromJson
            ]),
            200,
          );
        }),
      );

      await service.checkForUpdates();

      expect(service.status, UpdateStatus.updateAvailable);
      expect(service.latest!.version, const AppVersion(1, 3, 0));
      expect(service.downloadUrl, 'https://example.test/dmg');
      // Hit the releases endpoint and identified itself (GitHub 403s without).
      expect(captured.url.host, 'api.github.com');
      expect(captured.url.path, '/repos/ben-milanko/dart-pdf/releases');
      expect(captured.headers['User-Agent'], isNotNull);
    });

    test('a non-200 response surfaces as a failed check', () async {
      final service = UpdateService(
        currentVersion: '1.2.2',
        clientFactory: () =>
            MockClient((_) async => http.Response('rate limited', 403)),
      );

      await service.checkForUpdates();

      expect(service.status, UpdateStatus.failed);
      expect(service.error, isNotNull);
      expect(service.updateAvailable, isFalse);
    });

    test('a non-list body is treated as no releases', () async {
      final service = UpdateService(
        currentVersion: '1.2.2',
        clientFactory: () =>
            MockClient((_) async => http.Response('{"message":"nope"}', 200)),
      );

      await service.checkForUpdates();

      expect(service.status, UpdateStatus.upToDate);
      expect(service.latest, isNull);
    });
  });
}
