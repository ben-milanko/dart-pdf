import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:dart_pdf_editor_app/update_installer.dart';
import 'package:dart_pdf_editor_app/update_platform.dart';

/// A fake [UpdatePlatformOps] that records every call instead of touching the
/// real disk or spawning processes, so the installer's apply sequence is
/// asserted deterministically.
class _FakeOps implements UpdatePlatformOps {
  _FakeOps({required this.platform, this.appImagePath});

  @override
  final TargetPlatform platform;
  @override
  final String? appImagePath;

  final List<String> log = [];
  final Map<String, Uint8List> written = {};
  String? replacedFrom;
  String? replacedTo;
  String? relaunched;
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
      {bool executable = false}) async {
    written[path] = Uint8List.fromList(bytes);
    log.add('write:$path:exec=$executable');
  }

  @override
  Future<void> replaceInPlace(
      {required String from, required String to}) async {
    replacedFrom = from;
    replacedTo = to;
    log.add('replace:$from->$to');
  }

  @override
  Future<Never> relaunchAndExit(String path) async {
    relaunched = path;
    log.add('relaunch:$path');
    // The real implementation calls exit(0) here and never returns; the fake
    // throws a sentinel so callers can observe that a relaunch was requested.
    throw const _ExitCalled();
  }

  @override
  Future<void> openArtifact(String path) async {
    opened = path;
    log.add('open:$path');
  }
}

class _ExitCalled implements Exception {
  const _ExitCalled();
}

/// A client that streams [bytes] back in [chunks] pieces with a 200 status.
http.Client Function() _okClient(Uint8List bytes, {int chunks = 1, int? len}) {
  final pieces = <List<int>>[];
  final step = (bytes.length / chunks).ceil();
  for (var i = 0; i < bytes.length; i += step) {
    pieces.add(bytes.sublist(i, (i + step).clamp(0, bytes.length)));
  }
  return () => MockClient.streaming((request, bodyStream) async =>
      http.StreamedResponse(Stream.fromIterable(pieces), 200,
          contentLength: len ?? bytes.length));
}

Uint8List _bytes(int n) =>
    Uint8List.fromList(List.generate(n, (i) => i % 256));

void main() {
  const appImageAsset = 'dartpdf-linux-x86_64.AppImage';
  const tarAsset = 'dartpdf-linux-x64.tar.gz';
  const dmgAsset = 'dartpdf-macos.dmg';
  const exeAsset = 'dartpdf-windows-installer.exe';

  group('UpdateInstaller.modeFor', () {
    test('AppImage running as an AppImage self-replaces', () {
      final installer = UpdateInstaller(
        ops: _FakeOps(
            platform: TargetPlatform.linux, appImagePath: '/apps/DartPDF'),
      );
      expect(installer.modeFor(appImageAsset), UpdateApplyMode.inPlaceRelaunch);
    });

    test('AppImage asset but not running as one falls back to unsupported', () {
      final installer = UpdateInstaller(
        ops: _FakeOps(platform: TargetPlatform.linux, appImagePath: null),
      );
      expect(installer.modeFor(appImageAsset), UpdateApplyMode.unsupported);
    });

    test('a Linux tarball has no in-place path', () {
      final installer = UpdateInstaller(
        ops: _FakeOps(
            platform: TargetPlatform.linux, appImagePath: '/apps/DartPDF'),
      );
      expect(installer.modeFor(tarAsset), UpdateApplyMode.unsupported);
    });

    test('macOS and Windows hand off to the OS installer', () {
      expect(
        UpdateInstaller(ops: _FakeOps(platform: TargetPlatform.macOS))
            .modeFor(dmgAsset),
        UpdateApplyMode.openArtifact,
      );
      expect(
        UpdateInstaller(ops: _FakeOps(platform: TargetPlatform.windows))
            .modeFor(exeAsset),
        UpdateApplyMode.openArtifact,
      );
    });

    test('a missing asset name is unsupported', () {
      final installer =
          UpdateInstaller(ops: _FakeOps(platform: TargetPlatform.macOS));
      expect(installer.modeFor(null), UpdateApplyMode.unsupported);
      expect(installer.modeFor(''), UpdateApplyMode.unsupported);
    });

    test('mobile platforms are unsupported', () {
      final installer =
          UpdateInstaller(ops: _FakeOps(platform: TargetPlatform.android));
      expect(installer.modeFor('app-release.apk'), UpdateApplyMode.unsupported);
    });
  });

  group('UpdateInstaller.downloadAndApply - AppImage in place', () {
    test('writes an executable, replaces the running image, and relaunches',
        () async {
      final ops = _FakeOps(
          platform: TargetPlatform.linux, appImagePath: '/apps/DartPDF');
      final bytes = _bytes(1024);
      final installer = UpdateInstaller(ops: ops, clientFactory: _okClient(bytes));

      var applyingBeforeWrite = false;
      var onApplyingCalls = 0;

      await expectLater(
        installer.downloadAndApply(
          url: 'https://example.test/appimage',
          assetName: appImageAsset,
          expectedSize: bytes.length,
          onApplying: () {
            onApplyingCalls++;
            // Fires after the download but before anything is written to disk.
            applyingBeforeWrite = ops.written.isEmpty;
          },
        ),
        throwsA(isA<_ExitCalled>()),
      );

      // onApplying fired once, right after the verified download.
      expect(onApplyingCalls, 1);
      expect(applyingBeforeWrite, isTrue);
      // Staged next to the target (same directory) and marked executable.
      expect(ops.written.keys.single, '/apps/.dartpdf-update.AppImage.part');
      expect(ops.written.values.single, bytes);
      expect(ops.log, contains('write:/apps/.dartpdf-update.AppImage.part:'
          'exec=true'));
      expect(ops.replacedFrom, '/apps/.dartpdf-update.AppImage.part');
      expect(ops.replacedTo, '/apps/DartPDF');
      expect(ops.relaunched, '/apps/DartPDF');
    });
  });

  group('UpdateInstaller.downloadAndApply - hand off', () {
    test('downloads to the download dir and opens it (macOS)', () async {
      final ops = _FakeOps(platform: TargetPlatform.macOS);
      final bytes = _bytes(2048);
      final installer = UpdateInstaller(ops: ops, clientFactory: _okClient(bytes));

      final outcome = await installer.downloadAndApply(
        url: 'https://example.test/dmg',
        assetName: dmgAsset,
        expectedSize: bytes.length,
      );

      expect(outcome, UpdateInstallOutcome.handedOff);
      expect(ops.written['/downloads/dartpdf-macos.dmg'], bytes);
      // Hand-off artifacts are not marked executable.
      expect(ops.log, contains('write:/downloads/dartpdf-macos.dmg:exec=false'));
      expect(ops.opened, '/downloads/dartpdf-macos.dmg');
      expect(ops.relaunched, isNull);
    });
  });

  group('UpdateInstaller.downloadAndApply - guards', () {
    test('returns unsupported without downloading', () async {
      final ops = _FakeOps(platform: TargetPlatform.linux, appImagePath: null);
      var built = false;
      final installer = UpdateInstaller(
        ops: ops,
        clientFactory: () {
          built = true;
          return MockClient((_) async => http.Response('x', 200));
        },
      );

      final outcome = await installer.downloadAndApply(
        url: 'https://example.test/appimage',
        assetName: appImageAsset,
      );

      expect(outcome, UpdateInstallOutcome.unsupported);
      expect(built, isFalse, reason: 'no download for an unsupported apply');
      expect(ops.written, isEmpty);
    });

    test('a size mismatch aborts before writing anything', () async {
      final ops = _FakeOps(
          platform: TargetPlatform.linux, appImagePath: '/apps/DartPDF');
      final bytes = _bytes(500);
      final installer = UpdateInstaller(ops: ops, clientFactory: _okClient(bytes));

      await expectLater(
        installer.downloadAndApply(
          url: 'https://example.test/appimage',
          assetName: appImageAsset,
          expectedSize: 999, // wrong
        ),
        throwsA(isA<UpdateInstallException>()),
      );
      expect(ops.written, isEmpty);
      expect(ops.replacedTo, isNull);
      expect(ops.relaunched, isNull);
    });

    test('an empty download is rejected', () async {
      final ops = _FakeOps(platform: TargetPlatform.macOS);
      final installer = UpdateInstaller(
        ops: ops,
        clientFactory: () => MockClient.streaming((request, body) async =>
            http.StreamedResponse(const Stream.empty(), 200, contentLength: 0)),
      );

      await expectLater(
        installer.downloadAndApply(url: 'https://example.test/dmg', assetName: dmgAsset),
        throwsA(isA<UpdateInstallException>()),
      );
      expect(ops.opened, isNull);
    });

    test('refuses a non-https artifact URL before downloading', () async {
      final ops = _FakeOps(platform: TargetPlatform.macOS);
      var built = false;
      final installer = UpdateInstaller(
        ops: ops,
        clientFactory: () {
          built = true;
          return MockClient((_) async => http.Response('x', 200));
        },
      );

      await expectLater(
        installer.downloadAndApply(
          url: 'http://example.test/dmg', // not https
          assetName: dmgAsset,
        ),
        throwsA(isA<UpdateInstallException>()),
      );
      expect(built, isFalse, reason: 'must reject before any network use');
      expect(ops.written, isEmpty);
    });

    test('a non-200 response fails', () async {
      final ops = _FakeOps(platform: TargetPlatform.macOS);
      final installer = UpdateInstaller(
        ops: ops,
        clientFactory: () =>
            MockClient((_) async => http.Response('nope', 404)),
      );

      await expectLater(
        installer.downloadAndApply(url: 'https://example.test/dmg', assetName: dmgAsset),
        throwsA(isA<UpdateInstallException>()),
      );
    });

    test('cancellation stops the download and applies nothing', () async {
      final ops = _FakeOps(platform: TargetPlatform.macOS);
      final bytes = _bytes(1000);
      final installer =
          UpdateInstaller(ops: ops, clientFactory: _okClient(bytes, chunks: 4));

      await expectLater(
        installer.downloadAndApply(
          url: 'https://example.test/dmg',
          assetName: dmgAsset,
          isCancelled: () => true,
        ),
        throwsA(isA<UpdateCancelledException>()),
      );
      expect(ops.written, isEmpty);
      expect(ops.opened, isNull);
    });
  });

  group('UpdateInstaller.downloadAndApply - progress', () {
    test('reports monotonically increasing received bytes up to the total',
        () async {
      final ops = _FakeOps(platform: TargetPlatform.macOS);
      final bytes = _bytes(1000);
      final installer =
          UpdateInstaller(ops: ops, clientFactory: _okClient(bytes, chunks: 5));

      final received = <int>[];
      int? seenTotal;
      await installer.downloadAndApply(
        url: 'https://example.test/dmg',
        assetName: dmgAsset,
        expectedSize: bytes.length,
        onProgress: (r, t) {
          received.add(r);
          seenTotal = t;
        },
      );

      expect(seenTotal, 1000);
      expect(received.first, 0);
      expect(received.last, 1000);
      for (var i = 1; i < received.length; i++) {
        expect(received[i], greaterThanOrEqualTo(received[i - 1]));
      }
    });
  });
}
