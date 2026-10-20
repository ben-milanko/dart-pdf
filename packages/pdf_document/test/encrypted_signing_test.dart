// Signing password-protected documents (#935): every signing path writes its
// revision through encrypt-on-write, leaving only the signature's /Contents
// plain (ISO 32000 §7.6.1), and the signature validates after reopening.
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:test/test.dart';

final signerKey = RsaPrivateKey.fromPem(testSignerKeyPem);
final signerCert = pemBytes(testSignerCertPem);
final signedAt = DateTime.utc(2026, 9, 23, 10, 0, 0);

const _reason = 'Encrypted approval';
const _location = 'Somewhere private';

PdfTimestampClient testTsa() =>
    (request) async => buildTestTimeStampToken(request, genTime: signedAt);

const _schemes = {
  2: 'RC4-40',
  3: 'RC4-128',
  4: 'AES-128',
  6: 'AES-256 (R6)',
};

bool _contains(Uint8List haystack, List<int> needle) {
  outer:
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}

/// Reopens [bytes] with [password] and checks every signature is intact,
/// that the newest covers the whole file, and that the file stayed
/// encrypted with the sig-dict text strings encrypted too.
List<PdfSignature> _expectSignedAndEncrypted(Uint8List bytes,
    {String password = 'user', bool newestCoversAll = true}) {
  final doc = PdfDocument.open(bytes, password: password);
  expect(doc.cos.isEncrypted, isTrue);
  final signatures = PdfSignature.of(doc);
  expect(signatures, isNotEmpty);
  for (final signature in signatures) {
    final result = signature.validate();
    expect(result.digestMatches, isTrue, reason: '${result.problems}');
    expect(result.signatureValid, isTrue, reason: '${result.problems}');
  }
  if (newestCoversAll) {
    // (a B-LT /DSS is a later, unsigned revision by design)
    final newest = signatures.last.validate();
    expect(newest.coversWholeDocument, isTrue, reason: '${newest.problems}');
    expect(newest.problems, isEmpty);
  }
  // /Reason and /Location decrypt back ...
  final approval = signatures.firstWhere((s) => !s.isDocumentTimeStamp);
  expect(approval.reason, _reason);
  expect(approval.location, _location);
  // ... but never appear in the file as plaintext.
  expect(_contains(bytes, latin1.encode(_reason)), isFalse);
  expect(_contains(bytes, latin1.encode(_location)), isFalse);
  return signatures;
}

void main() {
  group('saveSigned on an encrypted document', () {
    for (final MapEntry(key: revision, value: label) in _schemes.entries) {
      test(label, () {
        final source = buildEncryptedPdf(
            revision: revision, userPassword: 'user', ownerPassword: 'owner');
        final signed =
            PdfEditor(PdfDocument.open(source, password: 'user')).saveSigned(
          privateKey: signerKey,
          certificates: [signerCert],
          signingTime: signedAt,
          reason: _reason,
          location: _location,
        );
        final signature = _expectSignedAndEncrypted(signed).single;
        // /Contents is the plain CMS in the file: the /ByteRange gap's hex
        // is exactly what the reader reports, and it opens a DER SEQUENCE.
        final range = signature.byteRange;
        final gap =
            String.fromCharCodes(signed.sublist(range[1] + 1, range[2] - 1));
        final contents = signature.contents;
        expect(contents.first, 0x30);
        final hex = contents
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join()
            .toUpperCase();
        expect(gap.startsWith(hex), isTrue);
        // the rest of the document still decrypts
        final doc = PdfDocument.open(signed, password: 'user');
        expect(String.fromCharCodes(doc.page(0).contentBytes()),
            contains('Hello, world!'));
        expect(doc.info['Title'], 'Secret Title');
      });
    }

    test('opened with the owner password', () {
      final source = buildEncryptedPdf(
          revision: 4, userPassword: 'user', ownerPassword: 'owner');
      final signed =
          PdfEditor(PdfDocument.open(source, password: 'owner')).saveSigned(
        privateKey: signerKey,
        certificates: [signerCert],
        signingTime: signedAt,
        reason: _reason,
        location: _location,
      );
      _expectSignedAndEncrypted(signed);
      _expectSignedAndEncrypted(signed, password: 'owner');
    });

    for (final revision in [3, 6]) {
      test('owner-password-only (empty user password), ${_schemes[revision]}',
          () {
        final source = buildEncryptedPdf(revision: revision);
        final signed = PdfEditor(PdfDocument.open(source)).saveSigned(
          privateKey: signerKey,
          certificates: [signerCert],
          signingTime: signedAt,
          reason: _reason,
          location: _location,
        );
        _expectSignedAndEncrypted(signed, password: '');
      });
    }

    for (final revision in [2, 4, 6]) {
      test('a second signature on top, ${_schemes[revision]}', () {
        final source = buildEncryptedPdf(
            revision: revision, userPassword: 'user', ownerPassword: 'owner');
        final first =
            PdfEditor(PdfDocument.open(source, password: 'user')).saveSigned(
          privateKey: signerKey,
          certificates: [signerCert],
          signingTime: signedAt,
          reason: _reason,
          location: _location,
        );
        final second =
            PdfEditor(PdfDocument.open(first, password: 'user')).saveSelfSigned(
          identity: PdfSigningIdentity.generate(name: 'Second Signer'),
          signingTime: signedAt,
        );
        final signatures = _expectSignedAndEncrypted(second);
        expect(signatures, hasLength(2));
        // the first signature now covers only its own revision
        final firstResult = signatures.first.validate();
        expect(firstResult.intact, isTrue);
        expect(firstResult.coversWholeDocument, isFalse);
        expect(signatures.last.signerName, 'Second Signer');
      });
    }
  });

  group('every signing path on an encrypted document', () {
    PdfEditor encryptedEditor({int revision = 6}) => PdfEditor(PdfDocument.open(
        buildEncryptedPdf(
            revision: revision, userPassword: 'user', ownerPassword: 'owner'),
        password: 'user'));

    test('saveSignedEcdsa / saveSelfSigned (RC4-128)', () {
      final signed = encryptedEditor(revision: 3).saveSelfSigned(
        identity: PdfSigningIdentity.generate(name: 'Ada Lovelace'),
        signingTime: signedAt,
        reason: _reason,
        location: _location,
      );
      _expectSignedAndEncrypted(signed);
    });

    test('saveSignedExternal (AES-128)', () async {
      final signed = await encryptedEditor(revision: 4).saveSignedExternal(
        signer: (attributes) async => rsaSign(signerKey,
            '2.16.840.1.101.3.4.2.1', crypto.sha256.convert(attributes).bytes),
        certificates: [signerCert],
        signingTime: signedAt,
        reason: _reason,
        location: _location,
      );
      _expectSignedAndEncrypted(signed);
    });

    test('a visible signature box', () {
      final signed = encryptedEditor().saveSigned(
        privateKey: signerKey,
        certificates: [signerCert],
        signingTime: signedAt,
        reason: _reason,
        location: _location,
        appearance: const PdfSignatureAppearance(
          rect: PdfRect(72, 640, 340, 720),
        ),
      );
      _expectSignedAndEncrypted(signed);
    });

    for (final level in PdfPadesLevel.values) {
      test('saveSignedPades ${level.name} (AES-256)', () async {
        final signed = await encryptedEditor().saveSignedPades(
          privateKey: RsaPrivateKey.fromDer(pkixLeafKey),
          certificates: [pkixLeafCert, pkixCaCert],
          level: level,
          timestampClient: level == PdfPadesLevel.bB ? null : testTsa(),
          revocationClient: (chain) async => PdfRevocationMaterial(
            ocspResponses: [pkixOcspGood],
            crls: [pkixCrl],
            certificates: [pkixCaCert],
          ),
          signingTime: signedAt,
          reason: _reason,
          location: _location,
        );
        final signatures = _expectSignedAndEncrypted(signed,
            newestCoversAll: level != PdfPadesLevel.bLT);
        final approval =
            signatures.firstWhere((s) => !s.isDocumentTimeStamp).validate();
        expect(approval.padesLevel, level);
        if (level.index >= PdfPadesLevel.bLT.index) {
          final doc = PdfDocument.open(signed, password: 'user');
          expect(PdfDss.of(doc)!.ocspResponses, isNotEmpty);
          expect(approval.isLtvEnabled, isTrue);
          expect(approval.embeddedRevocation, PdfRevocationStatus.good);
        }
        if (level == PdfPadesLevel.bLTA) {
          final docTs = signatures.singleWhere((s) => s.isDocumentTimeStamp);
          final result = docTs.validate();
          expect(result.signatureValid, isTrue);
          expect(result.timestamp!.valid, isTrue);
        }
      });
    }

    test('saveSelfSignedPades B-T (RC4-40)', () async {
      final signed = await encryptedEditor(revision: 2).saveSelfSignedPades(
        identity: PdfSigningIdentity.generate(name: 'Grace Hopper'),
        level: PdfPadesLevel.bT,
        timestampClient: testTsa(),
        signingTime: signedAt,
        reason: _reason,
        location: _location,
      );
      final signatures = _expectSignedAndEncrypted(signed);
      expect(signatures.single.validate().timestamp!.valid, isTrue);
    });

    test('addDocumentTimestamp on a signed encrypted file', () async {
      final signed = encryptedEditor(revision: 4).saveSigned(
        privateKey: signerKey,
        certificates: [signerCert],
        signingTime: signedAt,
        reason: _reason,
        location: _location,
      );
      final stamped =
          await PdfEditor(PdfDocument.open(signed, password: 'user'))
              .addDocumentTimestamp(testTsa());
      final signatures = _expectSignedAndEncrypted(stamped);
      expect(signatures.where((s) => s.isDocumentTimeStamp), hasLength(1));
    });

    test('certify (DocMDP) then an approval signature', () async {
      final certified = await encryptedEditor().saveSignedPades(
        privateKey: signerKey,
        certificates: [signerCert],
        signingTime: signedAt,
        reason: _reason,
        location: _location,
        certify: true,
        docMdpPermissions: 2,
      );
      final doc = PdfDocument.open(certified, password: 'user');
      final perms = doc.cos.resolve(doc.catalog['Perms']) as CosDictionary;
      final signature = PdfSignature.of(doc).single;
      expect(
          identical(doc.cos.resolve(perms['DocMDP']), signature.dict), isTrue);
      _expectSignedAndEncrypted(certified);

      final approved = PdfEditor(doc).saveSigned(
        privateKey: signerKey,
        certificates: [signerCert],
        signingTime: signedAt,
      );
      expect(_expectSignedAndEncrypted(approved), hasLength(2));
    });
  });
}
