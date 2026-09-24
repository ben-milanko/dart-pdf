import 'dart:io';
import 'dart:math';

import 'package:dart_pdf_editor_app/signature_trust.dart';
import 'package:dart_pdf_editor_app/signature_trust_store_io.dart' as store;
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_document/trust_lists.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main() {
  final pki = TestRevocationPki.generate(random: Random(936));
  final signed =
      PdfEditor(PdfDocument.open(buildMultiPagePdf(1))).saveSignedEcdsa(
    privateKey: pki.signerKey,
    certificates: pki.chain,
    signingTime: DateTime.utc(2026, 6, 10),
  );

  test('the platform default stays off under flutter test', () {
    expect(store.networkTrustAvailable, isFalse);
    expect(SignatureTrust.platformDefault, isNull);
  });

  test('httpRevocationClient POSTs OCSP and GETs CRLs over package:http',
      () async {
    final now = DateTime.now().toUtc();
    final seen = <String>[];
    final client = MockClient((request) async {
      seen.add('${request.method} ${request.url}');
      if (request.method == 'POST') {
        expect(request.headers['Content-Type'], 'application/ocsp-request');
        return http.Response.bytes(
            buildTestOcspResponse(
              certificate: pki.signer,
              issuer: pki.intermediate,
              signerKey: pki.intermediateKey,
              thisUpdate: now,
              nextUpdate: now.add(const Duration(days: 1)),
            ),
            200);
      }
      return http.Response.bytes(
          buildTestCrl(
            issuer: pki.root,
            issuerKey: pki.rootKey,
            thisUpdate: now,
            nextUpdate: now.add(const Duration(days: 1)),
          ),
          200);
    });
    final result =
        await PdfSignature.of(PdfDocument.open(signed)).single.validateOnline(
              trustStore: PdfTrustStore.trusting([pki.root]),
              revocationClient: httpRevocationClient(client: client),
            );
    expect(result.revocationStatus, PdfRevocationStatus.good);
    expect(result.chainTrusted, isTrue);
    expect(seen, contains('GET $testIntermediateCrlUrl'));
  });

  test('attach wires revocation, loads anchors once a signature appears',
      () async {
    var loads = 0;
    final anchors = PdfTrustStore.trusting([pki.root]);
    Future<PdfTrustStore?>? ready;
    final trust = SignatureTrust(
      revocationClient: (chain) async => const PdfRevocationMaterial(),
      loadAnchors: () {
        loads++;
        return ready = Future<PdfTrustStore?>.value(anchors);
      },
    );

    final unsigned = PdfEditingController(buildMultiPagePdf(1));
    addTearDown(unsigned.dispose);
    trust.attach(unsigned);
    expect(unsigned.revocationClient, isNotNull);
    expect(loads, 0, reason: 'an unsigned document never fetches the lists');

    final withSignature = PdfEditingController(signed);
    addTearDown(withSignature.dispose);
    trust.attach(withSignature);
    expect(loads, 1);
    await ready;
    await Future<void>.delayed(Duration.zero);
    expect(withSignature.trustStore?.anchors, anchors.anchors);
    expect(unsigned.trustStore?.anchors, anchors.anchors);
    trust.detach(unsigned);
    trust.detach(withSignature);
  });

  group('EU trusted list cache', () {
    final now = DateTime.utc(2026, 9, 23);
    late File file;

    setUp(() async {
      final dir = await Directory.systemTemp.createTemp('eutl');
      addTearDown(() => dir.delete(recursive: true));
      file = File('${dir.path}/eutl.pem');
    });

    String snapshot({
      required Duration age,
      required DateTime expires,
      String name = 'Test CA',
    }) =>
        PdfEuTrustListSnapshot(
          entries: [
            PdfTrustListEntry(
              territory: 'XX',
              serviceName: name,
              serviceType: 'http://uri.etsi.org/TrstSvc/Svctype/CA/QC',
              certificate: pki.root,
            ),
          ],
          fetchedAt: now.subtract(age),
          expires: expires,
        ).toPem();

    Future<String> offline() async => throw const SocketException('offline');

    Future<PdfTrustStore?> load({Future<String> Function()? fetch}) =>
        store.loadEuTrustStore(
          now: now,
          cacheFile: () async => file,
          fetchSnapshotPem: fetch ?? offline,
        );

    test('a fresh, current cache loads without fetching', () async {
      await file.writeAsString(
          snapshot(age: const Duration(days: 2), expires: DateTime.utc(2027)));
      var fetched = false;
      final loaded = await load(fetch: () async {
        fetched = true;
        return offline();
      });
      expect(fetched, isFalse);
      expect(loaded?.anchors.single.subjectCommonName, 'Revocation Test Root');
    });

    test('a recent cache past its NextUpdate is refreshed, not used', () async {
      await file.writeAsString(snapshot(
          age: const Duration(days: 1), expires: DateTime.utc(2026, 9, 1)));
      final fresh = snapshot(
          age: Duration.zero, expires: DateTime.utc(2027), name: 'Fresh CA');
      final loaded = await load(fetch: () async => fresh);
      expect(loaded?.anchors, hasLength(1));
      expect(await file.readAsString(), fresh);
    });

    test('an expired cache is never resurrected when the refresh fails',
        () async {
      await file.writeAsString(snapshot(
          age: const Duration(days: 30), expires: DateTime.utc(2026, 9, 1)));
      expect(await load(), isNull);
    });

    test('an old but still current cache covers a failed refresh', () async {
      await file.writeAsString(
          snapshot(age: const Duration(days: 30), expires: DateTime.utc(2027)));
      expect(await load(), isNotNull);
    });

    test('an expired snapshot from the refresh is not cached', () async {
      final stale =
          snapshot(age: Duration.zero, expires: DateTime.utc(2026, 9, 1));
      expect(await load(fetch: () async => stale), isNull);
      expect(await file.exists(), isFalse);
    });
  });
}
