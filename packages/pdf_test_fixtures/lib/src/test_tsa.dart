/// A self-contained RFC 3161 timestamp authority for tests: it answers a
/// [buildTimeStampRequest] blob with a real, verifiable TimeStampToken signed
/// by the test signer identity. Test-only - never use outside this repo.
library;

import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';

import 'signer_identity.dart';

/// Mints a TimeStampToken (the bare ContentInfo) for [timeStampRequest] - the
/// DER `TimeStampReq` produced by [buildTimeStampRequest]. The token copies
/// the request's MessageImprint and nonce, stamps it with [genTime] (default
/// a fixed test instant), and signs it with [key]/[certificateChain]
/// (defaulting to the test signer identity acting as the TSA).
///
/// Hand the result back from a `PdfTimestampClient` to exercise the PAdES
/// B-T/B-LTA paths without a network.
Uint8List buildTestTimeStampToken(
  Uint8List timeStampRequest, {
  RsaPrivateKey? key,
  List<Uint8List>? certificateChain,
  DateTime? genTime,
  BigInt? serialNumber,
}) {
  key ??= RsaPrivateKey.fromPem(testSignerKeyPem);
  certificateChain ??= [pemBytes(testSignerCertPem)];
  final time = (genTime ?? DateTime.utc(2026, 6, 15, 9, 30)).toUtc();

  final request = DerObject.parse(timeStampRequest).children;
  // TimeStampReq ::= SEQUENCE { version, messageImprint, reqPolicy?, nonce?,
  //   certReq? }
  final messageImprint = request[1];
  BigInt? nonce;
  for (var i = 2; i < request.length; i++) {
    if (request[i].tag == DerTag.integer) {
      nonce = request[i].asInteger;
      break;
    }
  }

  // TSTInfo ::= SEQUENCE { version, policy, messageImprint, serialNumber,
  //   genTime, accuracy?, ordering DEFAULT FALSE, nonce?, ... }
  final tstInfo = derSequence([
    derInteger(BigInt.one),
    derOid('1.2.3.4.1'), // a test policy OID
    messageImprint.encoded,
    derInteger(serialNumber ?? BigInt.from(0x7e57)),
    derGeneralizedTime(time),
    if (nonce != null) derInteger(nonce),
  ]);

  return cmsSignEncapsulated(
    eContent: tstInfo,
    eContentType: TspOid.tstInfo,
    privateKey: key,
    certificates: certificateChain,
    signingTime: time,
  );
}
