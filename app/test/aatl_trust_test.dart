import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor_app/settings_screen.dart';
import 'package:dart_pdf_editor_app/recents.dart';
import 'package:dart_pdf_editor_app/signature_trust.dart';
import 'package:dart_pdf_editor_app/signature_trust_store_io.dart' as store;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_document/trust_lists.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/l10n/app_localizations.dart';

void main() {
  final pki = TestRevocationPki.generate(random: Random(24));
  final signed =
      PdfEditor(PdfDocument.open(buildMultiPagePdf(1))).saveSignedEcdsa(
    privateKey: pki.signerKey,
    certificates: pki.chain,
    signingTime: DateTime.utc(2026, 6, 10),
  );
  // The EU list knows nothing of the test PKI; the "AATL" holds its root.
  final euStore = PdfTrustStore()
    ..addDer(PdfSigningIdentity.generate(name: 'EU CA').certificate,
        source: PdfEuLotl.sourceName);
  PdfTrustStore aatlStore() =>
      PdfAatlSnapshot([pki.root], signedAt: DateTime.utc(2026, 9))
          .toTrustStore();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  bool trusts(PdfTrustStore? store) =>
      PdfSignature.of(PdfDocument.open(signed))
          .single
          .validate(trustStore: store)
          .chainTrusted ==
      true;

  group('AatlTrustSetting', () {
    test('defaults off and persists the choice', () async {
      final setting = AatlTrustSetting();
      await setting.load();
      expect(setting.value, isFalse);
      await setting.save(true);
      final reloaded = AatlTrustSetting();
      await reloaded.load();
      expect(reloaded.value, isTrue);
    });
  });

  group('SignatureTrust with the AATL', () {
    late int aatlLoads;
    late int cacheDeletes;
    late Completer<PdfTrustStore?>? pendingAatl;
    late AatlTrustSetting setting;
    late SignatureTrust trust;

    setUp(() {
      aatlLoads = 0;
      cacheDeletes = 0;
      pendingAatl = null;
      setting = AatlTrustSetting();
      trust = SignatureTrust(
        loadAnchors: () async => euStore,
        loadAatl: () {
          aatlLoads++;
          return pendingAatl?.future ?? Future.value(aatlStore());
        },
        deleteAatlCache: () async => cacheDeletes++,
        aatl: setting,
      );
    });

    PdfEditingController attached() {
      final controller = PdfEditingController(signed);
      addTearDown(() {
        trust.detach(controller);
        controller.dispose();
      });
      trust.attach(controller);
      return controller;
    }

    test('off by default: the panel is offered the one-click action', () async {
      final controller = attached();
      await pumpEventQueue();
      expect(aatlLoads, 0, reason: 'nothing is downloaded from Adobe');
      expect(controller.signatureTrustAction, isNotNull);
      expect(trusts(controller.trustStore), isFalse);
    });

    test('the panel action turns it on, loads and re-validates', () async {
      final controller = attached();
      await pumpEventQueue();
      await controller.signatureTrustAction!.onPressed();
      expect(setting.value, isTrue);
      expect(aatlLoads, 1);
      expect(controller.signatureTrustAction, isNull);
      // EU and AATL roots together, each labelled with its list
      final store = controller.trustStore!;
      expect(store.anchors, hasLength(2));
      expect(store.anchors.map(store.sourceOf),
          containsAll([PdfEuLotl.sourceName, PdfAatl.sourceName]));
      expect(trusts(store), isTrue);

      final saved = AatlTrustSetting();
      await saved.load();
      expect(saved.value, isTrue);
    });

    test('turning it off drops the roots at once and deletes the cache',
        () async {
      final controller = attached();
      await trust.setAatlEnabled(true);
      expect(trusts(controller.trustStore), isTrue);

      await trust.setAatlEnabled(false);
      expect(trusts(controller.trustStore), isFalse);
      expect(
          controller.trustStore!.anchors.map(controller.trustStore!.sourceOf),
          [PdfEuLotl.sourceName]);
      expect(cacheDeletes, 1);
      expect(controller.signatureTrustAction, isNotNull);
    });

    test('a download still in flight when it is turned off is discarded',
        () async {
      final controller = attached();
      await pumpEventQueue();
      pendingAatl = Completer();
      final turningOn = trust.setAatlEnabled(true);
      await pumpEventQueue();
      await trust.setAatlEnabled(false);
      pendingAatl!.complete(aatlStore());
      await turningOn;
      await pumpEventQueue();
      expect(trusts(controller.trustStore), isFalse);
    });

    test('a saved "on" loads lazily with the first signed document', () async {
      await setting.save(true);
      final unsigned = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(unsigned.dispose);
      trust.attach(unsigned);
      await pumpEventQueue();
      expect(aatlLoads, 0);
      expect(unsigned.signatureTrustAction, isNull);

      final controller = attached();
      await pumpEventQueue();
      expect(aatlLoads, 1);
      expect(trusts(controller.trustStore), isTrue);
      trust.detach(unsigned);
    });

    testWidgets('the Settings switch flips the saved choice', (tester) async {
      SignatureTrust.debugPlatformDefault = trust;
      addTearDown(() => SignatureTrust.debugPlatformDefault = null);
      final prefs = PdfEditingPreferences();
      addTearDown(prefs.dispose);
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showAppSettings(context, prefs: prefs, recents: RecentsStore()),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final toggle = find.byKey(const ValueKey('settings-aatl'));
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      expect(find.text('Trust Adobe Approved Trust List'), findsOneWidget);
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(setting.value, isTrue);
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(setting.value, isFalse);
      expect(cacheDeletes, 1);
    });
  });

  group('AATL cache', () {
    final now = DateTime.utc(2026, 9, 24);
    late File file;

    setUp(() async {
      final dir = await Directory.systemTemp.createTemp('aatl');
      addTearDown(() => dir.delete(recursive: true));
      file = File('${dir.path}/aatl.pem');
    });

    String snapshot({required DateTime signed, required DateTime fetched}) =>
        PdfAatlSnapshot([pki.root], signedAt: signed, fetchedAt: fetched)
            .toPem();

    Future<String> offline() async => throw const SocketException('offline');

    Future<PdfTrustStore?> load({Future<String> Function()? fetch}) =>
        store.loadAatlTrustStore(
          now: now,
          cacheFile: () async => file,
          fetchSnapshotPem: fetch ?? offline,
        );

    test('a recently fetched, current copy loads without downloading',
        () async {
      await file.writeAsString(snapshot(
          signed: DateTime.utc(2026, 9, 10),
          fetched: now.subtract(const Duration(days: 2))));
      var fetched = false;
      final loaded = await load(fetch: () async {
        fetched = true;
        return offline();
      });
      expect(fetched, isFalse);
      expect(loaded?.sourceOf(loaded.anchors.single), PdfAatl.sourceName);
    });

    test('a copy older than a week is refreshed from Adobe', () async {
      await file.writeAsString(snapshot(
          signed: DateTime.utc(2026, 9, 10),
          fetched: now.subtract(const Duration(days: 8))));
      final fresh = snapshot(signed: DateTime.utc(2026, 9, 20), fetched: now);
      expect(await load(fetch: () async => fresh), isNotNull);
      expect(await file.readAsString(), fresh);
    });

    test('a failed refresh falls back to a copy within maxAge', () async {
      await file.writeAsString(snapshot(
          signed: DateTime.utc(2026, 3, 1),
          fetched: now.subtract(const Duration(days: 30))));
      expect(await load(), isNotNull);
    });

    test('but never to a copy Adobe signed over a year ago', () async {
      await file.writeAsString(snapshot(
          signed: DateTime.utc(2025, 8, 1),
          fetched: now.subtract(const Duration(days: 30))));
      expect(await load(), isNull);
    });

    test('deleteAatlCache removes the downloaded copy', () async {
      await file.writeAsString(
          snapshot(signed: DateTime.utc(2026, 9, 10), fetched: now));
      await store.deleteAatlCache(cacheFile: () async => file);
      expect(await file.exists(), isFalse);
    });
  });
}
