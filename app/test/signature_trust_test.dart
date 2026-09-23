import 'dart:io';
import 'dart:math';

import 'package:dart_pdf_editor_app/signature_trust.dart';
import 'package:dart_pdf_editor_app/signature_trust_store_io.dart' as store;
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pdf_cos/pdf_cos.dart';
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
    expect(withSignature.trustStore, same(anchors));
    expect(unsigned.trustStore, same(anchors));
    trust.detach(unsigned);
    trust.detach(withSignature);
  });

  test('a fresh cached EU snapshot loads without touching the network',
      () async {
    final dir = await Directory.systemTemp.createTemp('eutl');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/eutl.pem');
    final now = DateTime.utc(2026, 9, 23);
    await file.writeAsString(PdfEuTrustListSnapshot(
      entries: [
        PdfTrustListEntry(
          territory: 'XX',
          serviceName: 'Test CA',
          serviceType: 'http://uri.etsi.org/TrstSvc/Svctype/CA/QC',
          certificate: pki.root,
        ),
      ],
      fetchedAt: now.subtract(const Duration(days: 2)),
    ).toPem());
    final loaded =
        await store.loadEuTrustStore(now: now, cacheFile: () async => file);
    expect(loaded?.anchors.single.subjectCommonName, 'Revocation Test Root');
    expect(X509Certificate.parse(pki.root).isCa, isTrue);
  });
}
