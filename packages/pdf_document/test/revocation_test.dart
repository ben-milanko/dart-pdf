import 'dart:math';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

final signedAt = DateTime.utc(2026, 6, 10, 12);
final now = DateTime.utc(2026, 9, 1, 8);

void main() {
  final pki = TestRevocationPki.generate(random: Random(936));
  final signerCert = X509Certificate.parse(pki.signer);
  final trust = PdfTrustStore.trusting([pki.root]);

  Uint8List signPlain() =>
      PdfEditor(PdfDocument.open(buildMultiPagePdf(1))).saveSignedEcdsa(
        privateKey: pki.signerKey,
        certificates: pki.chain,
        signingTime: signedAt,
      );

  Future<Uint8List> signTimestamped(DateTime genTime) =>
      PdfEditor(PdfDocument.open(buildMultiPagePdf(1))).saveSignedPadesEcdsa(
        privateKey: pki.signerKey,
        certificates: pki.chain,
        level: PdfPadesLevel.bT,
        timestampClient: (req) async =>
            buildTestTimeStampToken(req, genTime: genTime),
        signingTime: signedAt,
      );

  PdfSignature only(Uint8List bytes) =>
      PdfSignature.of(PdfDocument.open(bytes)).single;

  // Live material: the intermediate answers OCSP for the signer directly,
  // and the root's CRL covers the intermediate.
  Uint8List ocspFor({
    OcspCertStatus status = OcspCertStatus.good,
    DateTime? thisUpdate,
    DateTime? nextUpdate,
    DateTime? revocationTime,
    EcPrivateKey? key,
    Uint8List? responder,
  }) =>
      buildTestOcspResponse(
        certificate: pki.signer,
        issuer: pki.intermediate,
        signerKey: key ?? pki.intermediateKey,
        responderCertificate: responder,
        status: status,
        thisUpdate: thisUpdate ?? now.subtract(const Duration(hours: 1)),
        nextUpdate: nextUpdate ?? now.add(const Duration(days: 3)),
        revocationTime: revocationTime,
      );

  Uint8List rootCrl({Map<BigInt, DateTime> revoked = const {}}) => buildTestCrl(
        issuer: pki.root,
        issuerKey: pki.rootKey,
        revoked: revoked,
        thisUpdate: now.subtract(const Duration(days: 1)),
        nextUpdate: now.add(const Duration(days: 6)),
      );

  PdfRevocationClient serve({
    List<Uint8List> ocsp = const [],
    List<Uint8List> crls = const [],
  }) =>
      (chain) async => PdfRevocationMaterial(ocspResponses: ocsp, crls: crls);

  group('validateOnline', () {
    test('good OCSP for the signer + good CRL for the intermediate', () async {
      final result = await only(signPlain()).validateOnline(
        trustStore: trust,
        revocationClient: serve(ocsp: [ocspFor()], crls: [rootCrl()]),
        now: now,
      );
      expect(result.chainTrusted, isTrue, reason: '${result.chainProblems}');
      expect(result.liveRevocationChecked, isTrue);
      expect(result.revocation, hasLength(2));
      final [leaf, intermediate] = result.revocation;
      expect(leaf.certificate.subjectCommonName, 'Revocation Test Signer');
      expect(leaf.status, PdfRevocationStatus.good);
      expect(leaf.source, PdfRevocationSource.live);
      expect(leaf.mechanism, PdfRevocationMechanism.ocsp);
      expect(intermediate.status, PdfRevocationStatus.good);
      expect(intermediate.mechanism, PdfRevocationMechanism.crl);
      expect(result.revocationStatus, PdfRevocationStatus.good);
    });

    test('the client receives the built chain, leaf first', () async {
      List<X509Certificate>? seen;
      await only(signPlain()).validateOnline(
        trustStore: trust,
        revocationClient: (chain) async {
          seen = chain;
          return const PdfRevocationMaterial();
        },
        now: now,
      );
      expect(seen!.map((c) => c.subjectCommonName), [
        'Revocation Test Signer',
        'Revocation Test Intermediate',
        'Revocation Test Root',
      ]);
    });

    test('a revoked signer without a timestamp makes the chain untrusted',
        () async {
      final result = await only(signPlain()).validateOnline(
        trustStore: trust,
        revocationClient: serve(ocsp: [
          ocspFor(
              status: OcspCertStatus.revoked,
              revocationTime: DateTime.utc(2026, 8, 1)),
        ], crls: [
          rootCrl()
        ]),
        now: now,
      );
      expect(result.intact, isTrue);
      expect(result.chainTrusted, isFalse);
      expect(result.revocationStatus, PdfRevocationStatus.revoked);
      expect(result.revokedBeforeSigning, isTrue);
      expect(result.revocation.first.revocationTime, DateTime.utc(2026, 8, 1));
      expect(result.chainProblems.last, contains('was revoked'));
    });

    test('revocation after a trusted timestamp keeps the signature trusted',
        () async {
      final result = await only(await signTimestamped(signedAt)).validateOnline(
        trustStore: trust,
        revocationClient: serve(ocsp: [
          ocspFor(
              status: OcspCertStatus.revoked,
              revocationTime: DateTime.utc(2026, 8, 1)),
        ], crls: [
          rootCrl()
        ]),
        now: now,
      );
      expect(result.timestamp?.valid, isTrue);
      expect(result.revocationStatus, PdfRevocationStatus.revoked);
      expect(result.revocation.first.affectsSignature, isFalse);
      expect(result.revokedBeforeSigning, isFalse);
      expect(result.chainTrusted, isTrue, reason: '${result.chainProblems}');
    });

    test('revocation before the timestamp still invalidates', () async {
      final result = await only(await signTimestamped(DateTime.utc(2026, 8, 5)))
          .validateOnline(
        trustStore: trust,
        revocationClient: serve(ocsp: [
          ocspFor(
              status: OcspCertStatus.revoked,
              revocationTime: DateTime.utc(2026, 8, 1)),
        ]),
        now: now,
      );
      expect(result.revokedBeforeSigning, isTrue);
      expect(result.chainTrusted, isFalse);
    });

    test('a revoked intermediate (via CRL) is caught too', () async {
      final intermediateSerial = X509Certificate.parse(pki.intermediate).serial;
      final result = await only(signPlain()).validateOnline(
        trustStore: trust,
        revocationClient: serve(ocsp: [
          ocspFor()
        ], crls: [
          rootCrl(revoked: {intermediateSerial: DateTime.utc(2026, 7, 1)}),
        ]),
        now: now,
      );
      expect(result.revocation[1].status, PdfRevocationStatus.revoked);
      expect(result.revocation[1].mechanism, PdfRevocationMechanism.crl);
      expect(result.chainTrusted, isFalse);
    });

    test('an authorized delegated responder is accepted', () async {
      final result = await only(signPlain()).validateOnline(
        trustStore: trust,
        revocationClient: serve(
            ocsp: [ocspFor(key: pki.responderKey, responder: pki.responder)],
            crls: [rootCrl()]),
        now: now,
      );
      expect(result.revocation.first.status, PdfRevocationStatus.good);
    });

    test('a delegate without the OCSPSigning purpose is refused', () async {
      final result = await only(signPlain()).validateOnline(
        trustStore: trust,
        revocationClient: serve(ocsp: [
          ocspFor(key: pki.responderKey, responder: pki.rogueResponder),
        ], crls: [
          rootCrl()
        ]),
        now: now,
      );
      final leaf = result.revocation.first;
      expect(leaf.status, PdfRevocationStatus.unknown);
      expect(leaf.problems.join(), contains('did not authorize'));
      expect(result.revocationStatus, PdfRevocationStatus.unknown);
      // soft-fail: unknown does not by itself untrust the chain
      expect(result.chainTrusted, isTrue);
    });

    test('a forged OCSP signature is refused', () async {
      final forger = EcPrivateKey.generate(EcCurve.p256, random: Random(1));
      final result = await only(signPlain()).validateOnline(
        trustStore: trust,
        revocationClient: serve(ocsp: [
          ocspFor(status: OcspCertStatus.good, key: forger),
        ]),
        now: now,
      );
      expect(result.revocation.first.status, PdfRevocationStatus.unknown);
      expect(result.revocation.first.problems.join(), contains('verify'));
    });

    test('a stale OCSP response does not count', () async {
      final result = await only(signPlain()).validateOnline(
        trustStore: trust,
        revocationClient: serve(ocsp: [
          ocspFor(
            thisUpdate: now.subtract(const Duration(days: 10)),
            nextUpdate: now.subtract(const Duration(days: 3)),
          ),
        ]),
        now: now,
      );
      expect(result.revocation.first.status, PdfRevocationStatus.unknown);
      expect(result.revocation.first.problems.join(), contains('stale'));
    });

    test('a response dated in the future does not count', () async {
      final result = await only(signPlain()).validateOnline(
        trustStore: trust,
        revocationClient: serve(ocsp: [
          ocspFor(thisUpdate: now.add(const Duration(days: 1))),
        ]),
        now: now,
      );
      expect(result.revocation.first.status, PdfRevocationStatus.unknown);
    });

    test('an OCSP entry for the same serial from another CA is ignored',
        () async {
      // Another CA issuing a certificate with the signer's serial: its
      // "revoked" answer must not apply to our signer.
      final other = TestRevocationPki.generate(random: Random(7));
      final response = buildTestOcspResponse(
        certificate: other.signer, // same serial 0x5151
        issuer: other.intermediate,
        signerKey: other.intermediateKey,
        status: OcspCertStatus.revoked,
        thisUpdate: now,
        nextUpdate: now.add(const Duration(days: 1)),
      );
      final result = await only(signPlain()).validateOnline(
        trustStore: trust,
        revocationClient: serve(ocsp: [response]),
        now: now,
      );
      expect(result.revocation.first.status, PdfRevocationStatus.none);
      expect(result.chainTrusted, isTrue);
    });

    test('a CRL signed by the wrong key is refused', () async {
      final forged = buildTestCrl(
        issuer: pki.intermediate,
        issuerKey: pki.rootKey, // wrong key for the intermediate's name
        revoked: {signerCert.serial: DateTime.utc(2026, 7, 1)},
        thisUpdate: now,
        nextUpdate: now.add(const Duration(days: 1)),
      );
      final result = await only(signPlain()).validateOnline(
        trustStore: trust,
        revocationClient: serve(crls: [forged]),
        now: now,
      );
      expect(result.revocation.first.status, PdfRevocationStatus.unknown);
      expect(result.chainTrusted, isTrue);
    });

    test('a failing client is reported as revocation unknown', () async {
      final result = await only(signPlain()).validateOnline(
        trustStore: trust,
        revocationClient: (chain) async => throw StateError('offline'),
        now: now,
      );
      expect(result.revocationStatus, PdfRevocationStatus.unknown);
      expect(result.revocation.first.problems.join(), contains('offline'));
      expect(result.chainTrusted, isTrue);
    });

    test('works without a trust store (chain built from the CMS certs)',
        () async {
      final result = await only(signPlain()).validateOnline(
        revocationClient: serve(ocsp: [
          ocspFor(
              status: OcspCertStatus.revoked,
              revocationTime: DateTime.utc(2026, 8, 1)),
        ]),
        now: now,
      );
      expect(result.revocation.first.status, PdfRevocationStatus.revoked);
      // a revoked signer is never left at "trust not judged"
      expect(result.chainTrusted, isFalse);
    });

    test('a self-signed signer has nothing to check', () async {
      final identity = PdfSigningIdentity.generate(
        name: 'Self',
        notBefore: DateTime.utc(2026),
        random: Random(3),
      );
      final bytes = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)))
          .saveSelfSigned(identity: identity, signingTime: signedAt);
      var called = false;
      final result = await only(bytes).validateOnline(
        revocationClient: (chain) async {
          called = true;
          return const PdfRevocationMaterial();
        },
        now: now,
      );
      expect(called, isFalse);
      expect(result.isSelfSigned, isTrue);
      expect(result.revocation, isEmpty);
      expect(result.revocationStatus, PdfRevocationStatus.none);
    });
  });

  group('embedded /DSS revocation', () {
    test('an embedded revoked OCSP answer makes validate() untrusted',
        () async {
      final bytes = await PdfEditor(PdfDocument.open(buildMultiPagePdf(1)))
          .saveSignedPadesEcdsa(
        privateKey: pki.signerKey,
        certificates: pki.chain,
        level: PdfPadesLevel.bLT,
        timestampClient: (req) async =>
            buildTestTimeStampToken(req, genTime: DateTime.utc(2026, 8, 5)),
        signingTime: signedAt,
        revocationClient: (chain) async => PdfRevocationMaterial(
          ocspResponses: [
            ocspFor(
                status: OcspCertStatus.revoked,
                revocationTime: DateTime.utc(2026, 8, 1)),
          ],
          crls: [rootCrl()],
        ),
      );
      final result = only(bytes).validate(trustStore: trust);
      expect(result.embeddedRevocation, PdfRevocationStatus.revoked);
      final leaf = result.revocation.first;
      expect(leaf.status, PdfRevocationStatus.revoked);
      expect(leaf.source, PdfRevocationSource.embedded);
      expect(result.liveRevocationChecked, isFalse);
      expect(result.chainTrusted, isFalse);
    });

    test('embedded good + live revoked: the live revocation wins', () async {
      final bytes = await PdfEditor(PdfDocument.open(buildMultiPagePdf(1)))
          .saveSignedPadesEcdsa(
        privateKey: pki.signerKey,
        certificates: pki.chain,
        level: PdfPadesLevel.bLT,
        timestampClient: (req) async =>
            buildTestTimeStampToken(req, genTime: DateTime.utc(2026, 8, 5)),
        signingTime: signedAt,
        revocationClient: (chain) async => PdfRevocationMaterial(
          ocspResponses: [ocspFor()],
          crls: [rootCrl()],
        ),
      );
      final offline = only(bytes).validate(trustStore: trust);
      expect(offline.revocation.first.source, PdfRevocationSource.embedded);
      expect(offline.revocation.first.status, PdfRevocationStatus.good);

      final online = await only(bytes).validateOnline(
        trustStore: trust,
        revocationClient: serve(ocsp: [
          ocspFor(
              status: OcspCertStatus.revoked,
              revocationTime: DateTime.utc(2026, 7, 1)),
        ]),
        now: now,
      );
      expect(online.revocation.first.source, PdfRevocationSource.live);
      expect(online.revocation.first.status, PdfRevocationStatus.revoked);
      expect(online.chainTrusted, isFalse);
    });
  });

  group('pdfOnlineRevocationClient', () {
    final chain = [
      for (final der in pki.chain) X509Certificate.parse(der),
    ];

    test('POSTs OCSP with a nonce, falls back to CRL for the intermediate',
        () async {
      final requests = <PdfRevocationRequest>[];
      final client = pdfOnlineRevocationClient(
        clock: () => now,
        random: Random(5),
        fetch: (request) async {
          requests.add(request);
          if (request.isPost) {
            expect(request.url.toString(), testOcspUrl);
            expect(request.contentType, 'application/ocsp-request');
            final nonce = _requestNonce(request.body!);
            // the signer's OCSP succeeds; the intermediate's (asked of the
            // same URL) is refused so the root CRL is fetched
            final cert = _requestSerial(request.body!);
            if (cert != signerCert.serial) throw StateError('HTTP 500');
            return buildTestOcspResponse(
              certificate: pki.signer,
              issuer: pki.intermediate,
              signerKey: pki.intermediateKey,
              thisUpdate: now,
              nextUpdate: now.add(const Duration(days: 1)),
              nonce: nonce,
            );
          }
          expect(request.url.toString(), testIntermediateCrlUrl);
          return rootCrl();
        },
      );
      final material = await client(chain);
      expect(material.ocspResponses, hasLength(1));
      expect(material.crls, hasLength(1));
      expect(requests.where((r) => r.isPost), hasLength(2));
    });

    test('drops a response echoing the wrong nonce and uses the CRL', () async {
      final signerCrl = buildTestCrl(
        issuer: pki.intermediate,
        issuerKey: pki.intermediateKey,
        thisUpdate: now,
        nextUpdate: now.add(const Duration(days: 1)),
      );
      final client = pdfOnlineRevocationClient(
        clock: () => now,
        fetch: (request) async {
          if (request.isPost) {
            return buildTestOcspResponse(
              certificate: pki.signer,
              issuer: pki.intermediate,
              signerKey: pki.intermediateKey,
              thisUpdate: now,
              nonce: ocspNonceValue(BigInt.from(42)), // a replayed answer
            );
          }
          return request.url.toString() == testSignerCrlUrl
              ? signerCrl
              : rootCrl();
        },
      );
      final material = await client(chain);
      expect(material.ocspResponses, isEmpty);
      expect(material.crls, hasLength(2));
    });

    test('accepts a responder that ignores the nonce', () async {
      final client = pdfOnlineRevocationClient(
        clock: () => now,
        fetch: (request) async {
          if (request.isPost) return ocspFor();
          return rootCrl();
        },
      );
      final material = await client(chain);
      expect(material.ocspResponses, isNotEmpty);
    });

    test('end to end through validateOnline', () async {
      final client = pdfOnlineRevocationClient(
        clock: () => now,
        fetch: (request) async {
          if (request.isPost) {
            if (_requestSerial(request.body!) != signerCert.serial) {
              throw StateError('no OCSP for CAs');
            }
            return buildTestOcspResponse(
              certificate: pki.signer,
              issuer: pki.intermediate,
              signerKey: pki.intermediateKey,
              status: OcspCertStatus.revoked,
              revocationTime: DateTime.utc(2026, 8, 1),
              thisUpdate: now,
              nextUpdate: now.add(const Duration(days: 1)),
              nonce: _requestNonce(request.body!),
            );
          }
          return rootCrl();
        },
      );
      final result = await only(signPlain()).validateOnline(
          trustStore: trust, revocationClient: client, now: now);
      expect(result.revocation.map((r) => r.status),
          [PdfRevocationStatus.revoked, PdfRevocationStatus.good]);
      expect(result.chainTrusted, isFalse);
    });
  });

  group('pdfOnlineRevocationClient falls back to the CRL', () {
    final chain = [
      for (final der in pki.chain) X509Certificate.parse(der),
    ];
    final signerCrl = buildTestCrl(
      issuer: pki.intermediate,
      issuerKey: pki.intermediateKey,
      revoked: {signerCert.serial: DateTime.utc(2026, 7, 1)},
      thisUpdate: now.subtract(const Duration(hours: 1)),
      nextUpdate: now.add(const Duration(days: 1)),
    );

    /// Serves [ocsp] for the signer's OCSP request (the intermediate's gets
    /// a 500) and the right CRL for each distribution point; returns the
    /// URLs fetched.
    Future<(PdfRevocationMaterial, List<String>)> run(Uint8List ocsp) async {
      final fetched = <String>[];
      final client = pdfOnlineRevocationClient(
        clock: () => now,
        useNonce: false,
        fetch: (request) async {
          fetched.add(request.url.toString());
          if (request.isPost) {
            if (_requestSerial(request.body!) != signerCert.serial) {
              throw StateError('HTTP 500');
            }
            return ocsp;
          }
          return request.url.toString() == testSignerCrlUrl
              ? signerCrl
              : rootCrl();
        },
      );
      return (await client(chain), fetched);
    }

    Future<void> expectCrlDecides(Uint8List ocsp) async {
      final (material, fetched) = await run(ocsp);
      expect(fetched, contains(testSignerCrlUrl),
          reason: 'an unusable OCSP answer must not suppress the CRL');
      final result = await only(signPlain()).validateOnline(
        trustStore: trust,
        revocationClient: (_) async => material,
        now: now,
      );
      final leaf = result.revocation.first;
      expect(leaf.mechanism, PdfRevocationMechanism.crl);
      expect(leaf.status, PdfRevocationStatus.revoked);
    }

    test('a forged-signature OCSP answer', () async {
      final forger = EcPrivateKey.generate(EcCurve.p256, random: Random(2));
      await expectCrlDecides(ocspFor(key: forger));
    });

    test('a stale OCSP answer', () async {
      await expectCrlDecides(ocspFor(
        thisUpdate: now.subtract(const Duration(days: 10)),
        nextUpdate: now.subtract(const Duration(days: 2)),
      ));
    });

    test('an answer from an unauthorized responder', () async {
      await expectCrlDecides(
          ocspFor(key: pki.responderKey, responder: pki.rogueResponder));
    });

    test('a verified OCSP answer still settles it without the CRL', () async {
      final (_, fetched) = await run(ocspFor());
      expect(fetched, isNot(contains(testSignerCrlUrl)));
    });
  });

  group('encrypted (AES-256) signed documents', () {
    Uint8List encryptedSource() => buildEncryptedPdf(
        revision: 6, userPassword: 'user', ownerPassword: 'owner');

    PdfSignature reopen(Uint8List bytes) {
      final doc = PdfDocument.open(bytes, password: 'user');
      expect(doc.cos.isEncrypted, isTrue);
      return PdfSignature.of(doc).single;
    }

    test('validateOnline sees a good and a revoked signer', () async {
      final signed =
          PdfEditor(PdfDocument.open(encryptedSource(), password: 'user'))
              .saveSignedEcdsa(
        privateKey: pki.signerKey,
        certificates: pki.chain,
        signingTime: signedAt,
      );
      final good = await reopen(signed).validateOnline(
        trustStore: trust,
        revocationClient: serve(ocsp: [ocspFor()], crls: [rootCrl()]),
        now: now,
      );
      expect(good.intact, isTrue, reason: '${good.problems}');
      expect(good.revocationStatus, PdfRevocationStatus.good);
      expect(good.chainTrusted, isTrue, reason: '${good.chainProblems}');

      final revoked = await reopen(signed).validateOnline(
        trustStore: trust,
        revocationClient: serve(ocsp: [
          ocspFor(
              status: OcspCertStatus.revoked,
              revocationTime: DateTime.utc(2026, 8, 1)),
        ]),
        now: now,
      );
      expect(revoked.revokedBeforeSigning, isTrue);
      expect(revoked.chainTrusted, isFalse);
    });

    test('embedded /DSS material in an encrypted B-LT file is read', () async {
      final signed =
          await PdfEditor(PdfDocument.open(encryptedSource(), password: 'user'))
              .saveSignedPadesEcdsa(
        privateKey: pki.signerKey,
        certificates: pki.chain,
        level: PdfPadesLevel.bLT,
        timestampClient: (req) async =>
            buildTestTimeStampToken(req, genTime: signedAt),
        signingTime: signedAt,
        revocationClient: (chain) async => PdfRevocationMaterial(
          ocspResponses: [ocspFor()],
          crls: [rootCrl()],
        ),
      );
      final result = reopen(signed).validate(trustStore: trust);
      expect(result.intact, isTrue, reason: '${result.problems}');
      expect(result.revocation.map((r) => (r.status, r.source)), [
        (PdfRevocationStatus.good, PdfRevocationSource.embedded),
        (PdfRevocationStatus.good, PdfRevocationSource.embedded),
      ]);
      expect(result.chainTrusted, isTrue, reason: '${result.chainProblems}');
    });
  });

  group('OCSP primitives', () {
    test('forCertificate checks issuer hashes, not just the serial', () {
      final other = TestRevocationPki.generate(random: Random(8));
      final response = OcspResponse.parse(ocspFor());
      final intermediate = X509Certificate.parse(pki.intermediate);
      expect(response.forCertificate(signerCert, intermediate), isNotNull);
      expect(
          response.forCertificate(X509Certificate.parse(other.signer),
              X509Certificate.parse(other.intermediate)),
          isNull);
      expect(response.forSerial(signerCert.serial), isNotNull);
    });

    test('echoesNonce matches only the request nonce', () {
      final response = OcspResponse.parse(buildTestOcspResponse(
        certificate: pki.signer,
        issuer: pki.intermediate,
        signerKey: pki.intermediateKey,
        thisUpdate: now,
        nonce: ocspNonceValue(BigInt.from(0xBEEF)),
      ));
      expect(response.echoesNonce(BigInt.from(0xBEEF)), isTrue);
      expect(response.echoesNonce(BigInt.from(0xBEEE)), isFalse);
    });

    test('revocation reason is parsed', () {
      final response = OcspResponse.parse(buildTestOcspResponse(
        certificate: pki.signer,
        issuer: pki.intermediate,
        signerKey: pki.intermediateKey,
        status: OcspCertStatus.revoked,
        revocationTime: DateTime.utc(2026, 8, 1),
        revocationReason: 1, // keyCompromise
        thisUpdate: now,
      ));
      final single = response.responses.single;
      expect(single.revocationTime, DateTime.utc(2026, 8, 1));
      expect(single.revocationReason, 1);
    });

    test('issued certificates carry AIA, CRLDP, EKU and CA flags', () {
      expect(signerCert.ocspResponderUrl, testOcspUrl);
      expect(signerCert.crlDistributionUrls, [testSignerCrlUrl]);
      expect(signerCert.isCa, isFalse);
      expect(X509Certificate.parse(pki.intermediate).isCa, isTrue);
      final responder = X509Certificate.parse(pki.responder);
      expect(responder.extendedKeyUsages, [OcspOid.ocspSigning]);
      expect(responder.hasOcspNoCheck, isTrue);
    });
  });
}

/// The serial of the single CertID in an OCSPRequest.
BigInt _requestSerial(Uint8List request) {
  final tbs = DerObject.parse(request).children.first;
  final requestList = tbs.children.first;
  return requestList.children.first.children.first.children[3].asInteger;
}

/// The nonce extnValue payload of an OCSPRequest (to echo back).
Uint8List? _requestNonce(Uint8List request) {
  final tbs = DerObject.parse(request).children.first;
  for (final field in tbs.children) {
    if (field.tag == DerTag.context(2)) {
      for (final ext in field.children.first.children) {
        if (ext.children.first.asOid == OcspOid.nonce) {
          return ext.children.last.content;
        }
      }
    }
  }
  return null;
}
