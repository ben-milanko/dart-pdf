// Dev tool: emits PAdES files signed through the CSC remote-signing path
// against the in-process test CSC service, for cross-validation with
// pyHanko / Adobe. Writes into the directory in argv[0]:
//   csc_pkcs1_blta.pdf - RSA PKCS#1 v1.5 (PIN, SCAL2), full /DSS, B-LTA
//   csc_pss_bt.pdf     - RSASSA-PSS, B-T
//   csc_ecdsa_bt.pdf   - ECDSA P-256 returned as raw r || s, B-T
// plus the trust anchors: pkix_ca.crt (RSA files and the TSA) and
// ec_ca.crt (the ECDSA file).
//   dart run tool/emit_csc_signed.dart /tmp/csc
import 'dart:io';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

Future<void> main(List<String> args) async {
  final dir = Directory(args.isNotEmpty ? args[0] : '/tmp/csc')
    ..createSync(recursive: true);
  final signedAt = DateTime.utc(2026, 6, 15, 10, 0, 0);
  final leafKey = RsaPrivateKey.fromDer(pkixLeafKey);
  final standard = TestCscService.standard();
  final service = TestCscService(credentials: [
    TestCscCredential(
      id: 'pkcs1',
      key: leafKey,
      chain: [pkixLeafCert, pkixCaCert],
      authMode: 'explicit',
      pin: '1234',
      scal: 2,
      keyAlgorithms: const [TestCscOid.rsaEncryption],
    ),
    TestCscCredential(
      id: 'pss',
      key: leafKey,
      chain: [pkixLeafCert, pkixCaCert],
      keyAlgorithms: const [TestCscOid.rsassaPss],
    ),
    standard.credentials['ec-raw']!,
  ]);
  final client = PdfCscClient(
    transport: (request) async {
      final r =
          service.handle(request.method, request.body, request.accessToken);
      return PdfCscResponse(r.status, r.body);
    },
    accessToken: service.serviceToken,
  );
  final credentials = {
    for (final c in await client.listCredentials()) c.id: c,
  };

  // an in-process TSA signing with the CA-issued TSA cert+key
  Future<Uint8List> tsa(Uint8List request) async => buildTestTimeStampToken(
        request,
        key: RsaPrivateKey.fromDer(pkixTsaKey),
        certificateChain: [pkixTsaCert, pkixCaCert],
        genTime: signedAt,
      );
  PdfEditor fresh() => PdfEditor(PdfDocument.open(buildMultiPagePdf(2)));

  Future<void> write(String name, Uint8List bytes) async {
    File('${dir.path}/$name').writeAsBytesSync(bytes);
    stdout.writeln('wrote ${dir.path}/$name (${bytes.length} bytes)');
  }

  await write(
    'csc_pkcs1_blta.pdf',
    await fresh().saveSignedPadesRemote(
      signer: cscRemoteSigner(
        client: client,
        credential: credentials['pkcs1']!,
        authorizer: (_) async => const PdfCscAuthorization.secrets(pin: '1234'),
      ),
      level: PdfPadesLevel.bLTA,
      timestampClient: tsa,
      signingTime: signedAt,
      reason: 'CSC remote signing demo',
      revocationClient: (chain) async => PdfRevocationMaterial(
        ocspResponses: [pkixOcspGood],
        crls: [pkixCrl],
        certificates: [pkixCaCert, pkixTsaCert],
      ),
    ),
  );
  await write(
    'csc_pss_bt.pdf',
    await fresh().saveSignedPadesRemote(
      signer: cscRemoteSigner(client: client, credential: credentials['pss']!),
      level: PdfPadesLevel.bT,
      timestampClient: tsa,
      signingTime: signedAt,
    ),
  );
  final ec = credentials['ec-raw']!;
  await write(
    'csc_ecdsa_bt.pdf',
    await fresh().saveSignedPadesRemote(
      signer: cscRemoteSigner(client: client, credential: ec),
      level: PdfPadesLevel.bT,
      timestampClient: tsa,
      signingTime: signedAt,
    ),
  );
  File('${dir.path}/pkix_ca.crt').writeAsBytesSync(pkixCaCert);
  File('${dir.path}/ec_ca.crt').writeAsBytesSync(ec.certificates.last);
}
