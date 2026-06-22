// Dev tool: emits a PAdES B-LTA file (leaf signer, CA-issued TSA, full /DSS)
// to the path in argv[0], for cross-validation with pyHanko / Adobe.
//   dart run tool/emit_pades_ltv.dart /tmp/pades_blta.pdf
import 'dart:io';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

Future<void> main(List<String> args) async {
  final out = args.isNotEmpty ? args[0] : '/tmp/pades_blta.pdf';
  final leafKey = RsaPrivateKey.fromDer(pkixLeafKey);

  // an in-process TSA signing with the CA-issued TSA cert+key
  Future<Uint8List> tsa(Uint8List request) async => buildTestTimeStampToken(
        request,
        key: RsaPrivateKey.fromDer(pkixTsaKey),
        certificateChain: [pkixTsaCert, pkixCaCert],
        genTime: DateTime.utc(2026, 6, 15, 10, 0, 0),
      );

  final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(2)));
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
