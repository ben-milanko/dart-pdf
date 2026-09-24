import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_document/trust_lists.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

String c14nDoc(String xml, XmlC14nMethod method) => utf8.decode(
    canonicalizeDocument(XmlLiteDocument.parseString(xml), method: method));

void main() {
  group('Canonical XML', () {
    // The example of the Exclusive XML Canonicalization spec (§2.2): the
    // same subtree canonicalizes differently under the two methods.
    const spec = '<n0:local xmlns:n0="foo:bar" xmlns:n3="ftp://example.org">'
        '<n1:elem2 xmlns:n1="http://example.net" xml:lang="en">'
        '<n3:stuff xmlns:n3="ftp://example.org"/></n1:elem2></n0:local>';

    XmlLiteElement elem2() =>
        XmlLiteDocument.parseString(spec).root.childElements.first;

    test('exclusive renders only visibly used namespaces', () {
      expect(
          utf8.decode(
              canonicalizeElement(elem2(), method: XmlC14nMethod.exclusive)),
          '<n1:elem2 xmlns:n1="http://example.net" xml:lang="en">'
          '<n3:stuff xmlns:n3="ftp://example.org"></n3:stuff></n1:elem2>');
    });

    test('inclusive renders every inherited namespace at the apex', () {
      expect(
          utf8.decode(
              canonicalizeElement(elem2(), method: XmlC14nMethod.inclusive)),
          '<n1:elem2 xmlns:n0="foo:bar" xmlns:n1="http://example.net" '
          'xmlns:n3="ftp://example.org" xml:lang="en">'
          '<n3:stuff></n3:stuff></n1:elem2>');
    });

    test('normalizes line endings, escapes, sorts attributes, drops comments',
        () {
      const xml = '<?xml version="1.0"?>\r\n<!-- gone -->\r\n'
          '<r b="2" a="x&#9;y&quot;" xmlns="urn:d">'
          'a &amp; b &lt; c > d&#13;\r\n<e/><?pi  data ?><!-- c --></r>';
      expect(
          c14nDoc(xml, XmlC14nMethod.exclusive),
          '<r xmlns="urn:d" a="x&#x9;y&quot;" b="2">'
          'a &amp; b &lt; c &gt; d&#xD;\n<e></e><?pi data ?></r>');
    });

    test('undeclaring the default namespace emits xmlns=""', () {
      const xml = '<a xmlns="urn:a"><b xmlns=""><c/></b></a>';
      expect(c14nDoc(xml, XmlC14nMethod.inclusive),
          '<a xmlns="urn:a"><b xmlns=""><c></c></b></a>');
      expect(c14nDoc(xml, XmlC14nMethod.exclusive),
          '<a xmlns="urn:a"><b xmlns=""><c></c></b></a>');
    });

    test('attributes sort by namespace URI, then local name', () {
      const xml = '<e xmlns:z="urn:a" xmlns:a="urn:z" a:x="1" z:y="2" b="3"/>';
      expect(c14nDoc(xml, XmlC14nMethod.inclusive),
          '<e xmlns:a="urn:z" xmlns:z="urn:a" b="3" z:y="2" a:x="1"></e>');
    });

    test('entity declarations are refused', () {
      expect(
          () => XmlLiteDocument.parseString(
              '<!DOCTYPE r [<!ENTITY x "y">]><r>&x;</r>'),
          throwsFormatException);
    });
  });

  final rng = Random(927);
  final now = DateTime.utc(2026, 9, 23);

  (EcPrivateKey, Uint8List) signer(String name) {
    final key = EcPrivateKey.generate(EcCurve.p256, random: rng);
    return (
      key,
      buildSelfSignedCertificate(
        key: key,
        commonName: name,
        notBefore: DateTime.utc(2026),
        notAfter: DateTime.utc(2030),
        random: rng,
      ),
    );
  }

  final (lotlKey, lotlCert) = signer('Test LOTL signer');
  final (xxKey, xxCert) = signer('Test XX TL signer');
  final (yyKey, yyCert) = signer('Test YY TL signer');
  final pki = TestRevocationPki.generate(random: Random(94));
  final otherCa = TestRevocationPki.generate(random: Random(95));

  String b64(Uint8List der) => base64.encode(der);

  String lotlBody({String next = '2027-03-01T00:00:00Z'}) => '''
<SchemeInformation>
  <TSLSequenceNumber>7</TSLSequenceNumber>
  <ListIssueDateTime>2026-09-01T00:00:00Z</ListIssueDateTime>
  <NextUpdate><dateTime>$next</dateTime></NextUpdate>
  <PointersToOtherTSL>
${[
        ('XX', xxCert, 'https://tl.test.invalid/xx.xml'),
        ('YY', yyCert, 'https://tl.test.invalid/yy.xml'),
        ('YY', yyCert, 'https://tl.test.invalid/yy.pdf'),
      ].map((p) => '''
    <OtherTSLPointer>
      <ServiceDigitalIdentities><ServiceDigitalIdentity><DigitalId>
        <X509Certificate>${b64(p.$2)}</X509Certificate>
      </DigitalId></ServiceDigitalIdentity></ServiceDigitalIdentities>
      <TSLLocation>${p.$3}</TSLLocation>
      <AdditionalInformation>
        <OtherInformation><SchemeTerritory>${p.$1}</SchemeTerritory></OtherInformation>
        <OtherInformation><ns3:MimeType xmlns:ns3="http://uri.etsi.org/02231/v2/additionaltypes#">${p.$3.endsWith('.pdf') ? 'application/pdf' : 'application/vnd.etsi.tsl+xml'}</ns3:MimeType></OtherInformation>
      </AdditionalInformation>
    </OtherTSLPointer>''').join()}
  </PointersToOtherTSL>
</SchemeInformation>
''';

  String service(String type, String status, Uint8List cert, String name) => '''
<TSPService><ServiceInformation>
  <ServiceTypeIdentifier>http://uri.etsi.org/TrstSvc/Svctype/$type</ServiceTypeIdentifier>
  <ServiceName><Name xml:lang="en">$name</Name></ServiceName>
  <ServiceDigitalIdentity><DigitalId><X509Certificate>${b64(cert)}</X509Certificate></DigitalId></ServiceDigitalIdentity>
  <ServiceStatus>http://uri.etsi.org/TrstSvc/TrustedList/Svcstatus/$status</ServiceStatus>
</ServiceInformation></TSPService>''';

  String scheme(String next) =>
      '<SchemeInformation><NextUpdate><dateTime>$next</dateTime></NextUpdate>'
      '</SchemeInformation>';

  String xxBody({String next = '2027-01-15T00:00:00Z'}) => '''
${scheme(next)}
<TrustServiceProviderList><TrustServiceProvider><TSPServices>
${service('CA/QC', 'granted', pki.root, 'Test Qualified CA &amp; Co')}
${service('CA/QC', 'withdrawn', otherCa.root, 'Withdrawn CA')}
${service('TSA/QTST', 'granted', otherCa.intermediate, 'A timestamp service')}
</TSPServices></TrustServiceProvider></TrustServiceProviderList>
''';

  String yyBody() => '''
${scheme('2027-02-01T00:00:00Z')}
<TrustServiceProviderList><TrustServiceProvider><TSPServices>
${service('NationalRootCA-QC', 'granted', otherCa.root, 'YY national root')}
</TSPServices></TrustServiceProvider></TrustServiceProviderList>
''';

  Uint8List bytesOf(String s) => Uint8List.fromList(utf8.encode(s));

  test('the signed fixture list verifies and tampering breaks it', () {
    final signed = signTestTrustList(lotlBody(), lotlKey, lotlCert);
    final ok = verifyEnvelopedXmlSignature(XmlLiteDocument.parse(signed));
    expect(ok.valid, isTrue, reason: '${ok.problems}');
    expect(ok.signer?.subjectCommonName, 'Test LOTL signer');

    final tampered = utf8
        .decode(signed)
        .replaceFirst('<TSLSequenceNumber>7', '<TSLSequenceNumber>8');
    final bad =
        verifyEnvelopedXmlSignature(XmlLiteDocument.parseString(tampered));
    expect(bad.valid, isFalse);
    expect(bad.problems.join(), contains('digest mismatch'));
  });

  group('EU trusted lists', () {
    Map<String, Uint8List> served() => {
          PdfEuLotl.url.toString():
              signTestTrustList(lotlBody(), lotlKey, lotlCert),
          'https://tl.test.invalid/xx.xml':
              signTestTrustList(xxBody(), xxKey, xxCert),
          'https://tl.test.invalid/yy.xml':
              signTestTrustList(yyBody(), yyKey, yyCert),
        };
    final pinned = {crypto.sha256.convert(lotlCert).toString()};

    Future<PdfEuTrustListSnapshot> fetchFrom(Map<String, Uint8List> files) =>
        fetchEuTrustedLists(
          fetch: (url) async =>
              files[url.toString()] ?? (throw StateError('404 $url')),
          pinnedSigners: pinned,
          now: now,
        );

    test('keeps active qualified CA services from verified lists', () async {
      final snapshot = await fetchFrom(served());
      expect(snapshot.problems, isEmpty);
      expect(snapshot.lotlSequenceNumber, 7);
      expect(snapshot.lotlNextUpdate, DateTime.utc(2027, 3));
      // the earliest NextUpdate of the lists it was built from
      expect(snapshot.expires, DateTime.utc(2027, 1, 15));
      expect(snapshot.isCurrentAt(now), isTrue);
      expect(snapshot.isCurrentAt(DateTime.utc(2027, 1, 16)), isFalse);
      expect(snapshot.entries.map((e) => (e.territory, e.serviceName)), [
        ('XX', 'Test Qualified CA & Co'),
        ('YY', 'YY national root'),
      ]);
    });

    test('a list signed by a key its pointer does not name is skipped',
        () async {
      final files = served()
        ..['https://tl.test.invalid/xx.xml'] =
            signTestTrustList(xxBody(), yyKey, yyCert);
      final snapshot = await fetchFrom(files);
      expect(snapshot.problems.keys, ['XX']);
      expect(snapshot.entries.map((e) => e.territory), ['YY']);
    });

    test('an unreachable list is skipped, not fatal', () async {
      final files = served()..remove('https://tl.test.invalid/yy.xml');
      final snapshot = await fetchFrom(files);
      expect(snapshot.problems.keys, ['YY']);
      expect(snapshot.entries, hasLength(1));
    });

    test('a LOTL from an unpinned signer is refused', () async {
      final files = served()
        ..[PdfEuLotl.url.toString()] =
            signTestTrustList(lotlBody(), xxKey, xxCert);
      await expectLater(fetchFrom(files), throwsFormatException);
    });

    test('a tampered LOTL is refused', () async {
      final signed = utf8.decode(served()[PdfEuLotl.url.toString()]!);
      final files = served()
        ..[PdfEuLotl.url.toString()] = bytesOf(signed.replaceFirst(
            'https://tl.test.invalid/xx.xml', 'https://evil.invalid/xx.xml'));
      await expectLater(fetchFrom(files), throwsFormatException);
    });

    test('the PEM snapshot round-trips into a working trust store', () async {
      final snapshot = await fetchFrom(served());
      final pem = snapshot.toPem();
      final back = PdfEuTrustListSnapshot.fromPem(pem);
      expect(back.entries, hasLength(2));
      expect(back.lotlSequenceNumber, 7);
      expect(back.fetchedAt, now);

      // A signature under the listed CA now validates as trusted.
      final signed =
          PdfEditor(PdfDocument.open(buildMultiPagePdf(1))).saveSignedEcdsa(
        privateKey: pki.signerKey,
        certificates: pki.chain.sublist(0, 2),
        signingTime: DateTime.utc(2026, 6, 10),
      );
      final result = PdfSignature.of(PdfDocument.open(signed))
          .single
          .validate(trustStore: PdfTrustLists.eutl(pem, now: now));
      expect(result.chainTrusted, isTrue, reason: '${result.chainProblems}');
      expect(result.trustChain.last.subjectCommonName, 'Revocation Test Root');
    });

    test('an expired LOTL is refused', () async {
      final files = served()
        ..[PdfEuLotl.url.toString()] = signTestTrustList(
            lotlBody(next: '2026-09-01T00:00:00Z'), lotlKey, lotlCert);
      await expectLater(
          fetchFrom(files),
          throwsA(isA<FormatException>()
              .having((e) => e.message, 'message', contains('expired'))));
    });

    test('a LOTL within the grace period is still accepted', () async {
      final files = served()
        ..[PdfEuLotl.url.toString()] = signTestTrustList(
            lotlBody(next: '2026-09-22T20:00:00Z'), lotlKey, lotlCert);
      final snapshot = await fetchFrom(files);
      expect(snapshot.entries, hasLength(2));
      // ...but the snapshot built from it expires with it
      expect(snapshot.expires, DateTime.utc(2026, 9, 22, 20));
    });

    test('an expired national list is skipped with a problem', () async {
      final files = served()
        ..['https://tl.test.invalid/xx.xml'] = signTestTrustList(
            xxBody(next: '2026-08-01T00:00:00Z'), xxKey, xxCert);
      final snapshot = await fetchFrom(files);
      expect(snapshot.problems.keys, ['XX']);
      expect(snapshot.problems['XX'], contains('expired'));
      expect(snapshot.entries.map((e) => e.territory), ['YY']);
      expect(snapshot.expires, DateTime.utc(2027, 2));
    });

    test('an expired snapshot PEM is refused and round-trips its expiry',
        () async {
      final pem = (await fetchFrom(served())).toPem();
      expect(PdfEuTrustListSnapshot.fromPem(pem).expires,
          DateTime.utc(2027, 1, 15));
      expect(() => PdfTrustLists.eutl(pem, now: DateTime.utc(2027, 2)),
          throwsFormatException);
    });

    test('the pinned LOTL signers are SHA-256 fingerprints', () {
      expect(PdfEuLotl.signerFingerprints, isNotEmpty);
      for (final f in PdfEuLotl.signerFingerprints) {
        expect(f, matches(RegExp(r'^[0-9a-f]{64}$')));
      }
    });
  });

  group('AATL loader', () {
    String settings(List<(String, String, Uint8List)> identities) =>
        '<?xml version="1.0"?>\n<SecuritySettings><TrustedIdentities>'
        '${identities.map((i) => '<Identity><ImportAction>${i.$1}</ImportAction>'
            '<Certificate>${b64(i.$3)}</Certificate>'
            '<Trust><Root>${i.$2}</Root></Trust></Identity>').join()}'
        '</TrustedIdentities></SecuritySettings>';

    Uint8List aatlFile(String xml) {
      final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)));
      editor.addEmbeddedFile('SecuritySettings.xml', bytesOf(xml));
      return editor.save();
    }

    final xml = settings([
      ('1', '1', pki.root), // added as a trusted root
      ('2', '1', otherCa.root), // updated trusted root
      ('3', '1', otherCa.intermediate), // removed
      ('1', '0', pki.intermediate), // not a root
    ]);

    test('keeps added/updated identities marked as trusted roots', () {
      final snapshot =
          parseAatlSecuritySettings(aatlFile(xml), verifySignature: false);
      expect(snapshot.anchors, [pki.root, otherCa.root]);
      expect(snapshot.toTrustStore().anchors, hasLength(2));
      expect(snapshot.toPem(), contains('BEGIN CERTIFICATE'));
    });

    test('an unsigned file is refused when verifying', () {
      expect(() => parseAatlSecuritySettings(aatlFile(xml)),
          throwsFormatException);
    });

    test('a file signed under the pinned root is accepted', () {
      final signed = PdfEditor(PdfDocument.open(aatlFile(xml))).saveSignedEcdsa(
        privateKey: pki.signerKey,
        certificates: pki.chain,
        signingTime: DateTime.utc(2026, 9, 10),
      );
      final rootPrint = crypto.sha256.convert(pki.root).toString();
      final snapshot =
          parseAatlSecuritySettings(signed, rootFingerprint: rootPrint);
      expect(snapshot.anchors, hasLength(2));
      expect(snapshot.signer, 'Revocation Test Signer');
      // An age limit, when asked for, is judged from the signing time.
      expect(
          parseAatlSecuritySettings(signed,
                  rootFingerprint: rootPrint,
                  maxAge: const Duration(days: 30),
                  now: DateTime.utc(2026, 9, 20))
              .anchors,
          hasLength(2));
      expect(
          () => parseAatlSecuritySettings(signed,
              rootFingerprint: rootPrint,
              maxAge: const Duration(days: 30),
              now: DateTime.utc(2026, 12, 1)),
          throwsFormatException);
      // ...and refused against the real Adobe pin.
      expect(() => parseAatlSecuritySettings(signed), throwsFormatException);
    });
  });
}

/// Wraps [body] in a trusted-list root and signs it the way ETSI lists are:
/// an enveloped ds:Signature (exclusive C14N, SHA-256 reference over the
/// whole document, ECDSA-SHA256) carrying the signer certificate.
Uint8List signTestTrustList(String body, EcPrivateKey key, Uint8List cert) {
  const root = 'TrustServiceStatusList';
  String build(String digest, String value) =>
      '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<$root xmlns="http://uri.etsi.org/02231/v2#" Id="tsl">$body'
      '<ds:Signature xmlns:ds="http://www.w3.org/2000/09/xmldsig#">'
      '<ds:SignedInfo>'
      '<ds:CanonicalizationMethod Algorithm="http://www.w3.org/2001/10/xml-exc-c14n#"/>'
      '<ds:SignatureMethod Algorithm="http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha256"/>'
      '<ds:Reference URI=""><ds:Transforms>'
      '<ds:Transform Algorithm="http://www.w3.org/2000/09/xmldsig#enveloped-signature"/>'
      '<ds:Transform Algorithm="http://www.w3.org/2001/10/xml-exc-c14n#"/>'
      '</ds:Transforms>'
      '<ds:DigestMethod Algorithm="http://www.w3.org/2001/04/xmlenc#sha256"/>'
      '<ds:DigestValue>$digest</ds:DigestValue></ds:Reference>'
      '</ds:SignedInfo>'
      '<ds:SignatureValue>$value</ds:SignatureValue>'
      '<ds:KeyInfo><ds:X509Data><ds:X509Certificate>${base64.encode(cert)}'
      '</ds:X509Certificate></ds:X509Data></ds:KeyInfo>'
      '</ds:Signature></$root>';

  XmlLiteElement signatureOf(XmlLiteDocument d) =>
      d.root.childElements.firstWhere((e) => e.localName == 'Signature');

  final draft = XmlLiteDocument.parseString(build('', ''));
  final digest = base64.encode(crypto.sha256
      .convert(canonicalizeDocument(draft,
          method: XmlC14nMethod.exclusive, omit: signatureOf(draft)))
      .bytes);
  final withDigest = XmlLiteDocument.parseString(build(digest, ''));
  final signedInfo = signatureOf(withDigest).childElements.first;
  final der = ecdsaSign(
      key,
      crypto.sha256
          .convert(
              canonicalizeElement(signedInfo, method: XmlC14nMethod.exclusive))
          .bytes);
  // XMLDSig ECDSA values are raw r || s, each padded to the field size.
  final rs = DerObject.parse(der).children;
  List<int> fixed(BigInt v) {
    final hex = v.toRadixString(16).padLeft(64, '0');
    return [
      for (var i = 0; i < 64; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ];
  }

  final value =
      base64.encode([...fixed(rs[0].asInteger), ...fixed(rs[1].asInteger)]);
  return Uint8List.fromList(utf8.encode(build(digest, value)));
}
