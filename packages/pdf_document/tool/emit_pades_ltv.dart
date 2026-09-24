// Dev tool: emits a PAdES B-LTA file (leaf signer, CA-issued TSA, full /DSS)
// to the path in argv[0], for cross-validation with pyHanko / Adobe.
//   dart run tool/emit_pades_ltv.dart /tmp/pades_blta.pdf
// Pass --encrypted=N to sign a password-protected source instead: N is the
// security handler revision (2 RC4-40, 3 RC4-128, 4 AES-128, 6 AES-256; a
// bare --encrypted means 6). User password "user", owner password "owner".
import 'dart:io';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

Future<void> main(List<String> args) async {
  final encryptArg = args.where((a) => a.startsWith('--encrypted')).firstOrNull;
  final encrypted = encryptArg != null;
  final revision = int.tryParse(encryptArg?.split('=').last ?? '') ?? 6;
  final paths = [
    for (final a in args)
      if (!a.startsWith('--')) a
  ];
  final out = paths.isNotEmpty ? paths[0] : '/tmp/pades_blta.pdf';
  final leafKey = RsaPrivateKey.fromDer(pkixLeafKey);

  // an in-process TSA signing with the CA-issued TSA cert+key
  Future<Uint8List> tsa(Uint8List request) async => buildTestTimeStampToken(
        request,
        key: RsaPrivateKey.fromDer(pkixTsaKey),
        certificateChain: [pkixTsaCert, pkixCaCert],
        genTime: DateTime.utc(2026, 6, 15, 10, 0, 0),
      );

  final editor = PdfEditor(encrypted
      ? PdfDocument.open(
          buildEncryptedPdf(
              revision: revision, userPassword: 'user', ownerPassword: 'owner'),
          password: 'user')
      : PdfDocument.open(buildMultiPagePdf(2)));
  final bytes = await editor.saveSignedPades(
    privateKey: leafKey,
    certificates: [pkixLeafCert, pkixCaCert],
    level: PdfPadesLevel.bLTA,
    timestampClient: tsa,
    signingTime: DateTime.utc(2026, 6, 15, 10, 0, 0),
    reason: 'PAdES B-LTA demo',
    revocationClient: (chain) async => PdfRevocationMaterial(
      ocspResponses: [pkixOcspGood],
      crls: [pkixCrl],
      certificates: [pkixCaCert, pkixTsaCert],
    ),
  );
  File(out).writeAsBytesSync(bytes);
  File('$out.ca.crt').writeAsBytesSync(pkixCaCert);
  stdout.writeln('wrote $out (${bytes.length} bytes)');
}
